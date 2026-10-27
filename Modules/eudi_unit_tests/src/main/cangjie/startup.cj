// Device unit tests for feature-startup (StartupInteractorImpl), migrated from
// iOS feature-startup/Tests/TestStartupInteractor.swift. Runs via the device
// bridge (DeviceTestRun in dev_unit_driver.cj). Hand-written fakes replace iOS
// Cuckoo mocks. The Cangjie StartupInteractorImpl depends on PinStore +
// PrefsController + ConfigLogic (walletKit/hasDocuments deferred — see its impl),
// so the route depends on hasPin + forcePidActivation only.
package eudi_unit_tests

import eudi_feature_startup.StartupInteractorImpl
import eudi_feature_common.{PinStore, BiometricUiConfig, QuickPinUiConfig}
import eudi_logic_business.{PrefsController, PrefsKey, ConfigLogic, AppBuildType, AppBuildVariant, KeyChainConfig}
import eudi_logic_ui.{AppRoutes, NavArgs, RouteConfigArgs}

// ── Fakes ───────────────────────────────────────────────────────────────────

class FakePinStore <: PinStore {
    var pinSet: Bool = false
    var clearCount: Int64 = 0
    public func setPin(pin: String): Unit {}
    public func isPinValid(pin: String): Bool { false }
    public func hasPin(): Bool { this.pinSet }
    public func clearPin(): Unit { this.clearCount += 1 }
}

class FakePrefsController <: PrefsController {
    var ranBefore: Bool = false
    var setCount: Int64 = 0
    public func setValue(value: ToString, forKey: PrefsKey): Unit {
        this.setCount += 1
        match (forKey) {
            case PrefsKey.runAtLeastOnce => this.ranBefore = true
            case _ => ()
        }
    }
    public func getString(forKey: PrefsKey): ?String { None }
    public func getOptionalString(forKey: PrefsKey): String { "" }
    public func getBool(forKey: PrefsKey): Bool {
        match (forKey) {
            case PrefsKey.runAtLeastOnce => this.ranBefore
            case _ => false
        }
    }
    public func getFloat(forKey: PrefsKey): Float64 { 0.0 }
    public func getInt(forKey: PrefsKey): Int64 { 0 }
    public func remove(forKey: PrefsKey): Unit {}
    public func getValue(forKey: PrefsKey): ?String { None }
    public func getUserLocale(): String { "en_GB" }
}

class FakeConfigLogic <: ConfigLogic {
    var forcePid: Bool = false
    public prop appBuildType: AppBuildType { get() { AppBuildType.RELEASE } }
    public prop appBuildVariant: AppBuildVariant { get() { AppBuildVariant.PROD } }
    public prop appVersion: String { get() { "test" } }
    public prop changelogUrl: ?String { get() { None } }
    public prop forcePidActivation: Bool { get() { this.forcePid } }
    public prop keyChainConfig: KeyChainConfig {
        get() { KeyChainConfig("svc", "grp") }
    }
}

func makeStartupInteractor(
    pinSet: Bool, ranBefore: Bool, forcePid: Bool, hasDocs!: Bool = false
): (StartupInteractorImpl, FakePinStore, FakePrefsController) {
    let ps = FakePinStore()
    ps.pinSet = pinSet
    let prefs = FakePrefsController()
    prefs.ranBefore = ranBefore
    let cfg = FakeConfigLogic()
    cfg.forcePid = forcePid
    let wallet = FakeWalletKitController()
    if (hasDocs) {
        wallet.allDocuments = [makeDocClaimsDecodable(id: "startup-pid")]
    }
    let interactor = StartupInteractorImpl(
        pinStore: ps, prefsController: prefs, configLogic: cfg, walletController: wallet
    )
    return (interactor, ps, prefs)
}

func routeIs(actual: Option<String>, expected: String): Bool {
    match (actual) {
        case Some(r) => r == expected
        case None => false
    }
}

// ── Tests (mirror iOS TestStartupInteractor intent for the Cangjie impl) ──────

// Reads back the success destination the interactor stashed for the biometry
// screen. iOS asserts the whole expected UIConfig.Biometry by equality; the
// success route is the part that differs per case, so it is what gets compared.
func biometrySuccessKey(): String {
    match (NavArgs.shared.get(AppRoutes.biometry)) {
        case Some(v) => match (v as RouteConfigArgs) {
            case Some(args) => match (args.config as BiometricUiConfig) {
                case Some(cfg) => cfg.navigationSuccessType.key()
                case None => "not-a-biometry-config"
            }
            case None => "not-route-config-args"
        }
        case None => "absent"
    }
}

func quickPinFlowRaw(): String {
    match (NavArgs.shared.get(AppRoutes.quickPin)) {
        case Some(v) => match (v as RouteConfigArgs) {
            case Some(args) => match (args.config as QuickPinUiConfig) {
                case Some(cfg) => cfg.flow.rawValue()
                case None => "not-a-quickpin-config"
            }
            case None => "not-route-config-args"
        }
        case None => "absent"
    }
}

func runStartupTests(t: DeviceTestRun): Unit {
    // ── testInitialize_WhenIsNotFirstBootAndPinIsNotSet_ThenReturnQuickPinAppRoute ──
    // iOS also asserts the carried QuickPinUiConfig and that first-run storage
    // manipulation did NOT happen (verifyFirstBootStorageManipulation(count: 0)).
    let (i1, ps1, _) = makeStartupInteractor(false, true, false)
    t.check(routeIs(i1.initialize(0.0), AppRoutes.quickPin), "startup.notFirstBoot_pinNotSet_quickPin")
    // iOS expects .setWithActivation because its test config forces PID
    // activation; this fake leaves forcePidActivation false, so the Cangjie
    // branch under test is the without-activation one.
    t.eqStr(quickPinFlowRaw(), "setWithoutActivation", "startup.notFirstBoot_pinNotSet_quickPinFlow")
    t.eqInt(ps1.clearCount, 0, "startup.notFirstBoot_pinNotSet_noStorageManipulation")

    // ── testInitialize_WhenIsNotFirstBootAndPinIsSetAndHasIssuedDocuments_ThenReturnBiometricsAppRouteWithNavigationSuccessDashboard ──
    // iOS stubs forcePidActivation=true in both of these cases; the document store
    // is what separates them. Wallet holds a document → dashboard.
    let (i2, _, _) = makeStartupInteractor(true, true, true, hasDocs: true)
    t.check(routeIs(i2.initialize(0.0), AppRoutes.biometry), "startup.notFirstBoot_pinSet_biometry")
    t.eqStr(biometrySuccessKey(), "push to ${AppRoutes.dashboard}",
        "startup.notFirstBoot_pinSet_hasDocs_successDashboard")

    // ── testInitialize_WhenIsNotFirstBootAndPinIsSetAndHasNoIssuedDocuments_ThenReturnBiometricsAppRouteWithNavigationSuccessAddDocument ──
    // Same config, empty store → add-document. Only `hasDocs` differs from the case
    // above, so the assertion pins the document check rather than the config flag.
    let (i3, _, _) = makeStartupInteractor(true, true, true, hasDocs: false)
    t.check(routeIs(i3.initialize(0.0), AppRoutes.biometry), "startup.notFirstBoot_pinSet_forcePid_biometry")
    t.eqStr(biometrySuccessKey(), "push to ${AppRoutes.issuanceAddDocument}",
        "startup.notFirstBoot_pinSet_noDocs_successAddDocument")

    // Guard for the conjunction: an empty store alone must NOT divert to
    // add-document when PID activation is not forced (iOS `&&`).
    let (i3b, _, _) = makeStartupInteractor(true, true, false, hasDocs: false)
    i3b.initialize(0.0)
    t.eqStr(biometrySuccessKey(), "push to ${AppRoutes.dashboard}",
        "startup.notFirstBoot_pinSet_noDocs_noForcePid_successDashboard")

    // ── testInitialize_WhenIsFirstBootAndPinIsNotSet_ThenClearDocumentStorageAndReturnQuickPinAppRoute ──
    // iOS clears the document storage on first boot; the Cangjie impl clears the
    // stale PIN and records runAtLeastOnce (document storage is walletKit-owned
    // and not wired here), then routes to quickPin.
    let (i4, ps4, prefs4) = makeStartupInteractor(false, false, false)
    t.check(routeIs(i4.initialize(0.0), AppRoutes.quickPin), "startup.firstBoot_pinNotSet_quickPin")
    t.eqInt(ps4.clearCount, 1, "startup.firstBoot_clearsStaleCredentials")
    t.check(prefs4.setCount >= 1, "startup.firstBoot_setsRunAtLeastOnce")

    // Guard for the case above: without a first boot nothing is cleared, so the
    // clear assertion cannot pass vacuously.
    let (i5, ps5, _) = makeStartupInteractor(true, true, false)
    i5.initialize(0.0)
    t.eqInt(ps5.clearCount, 0, "startup.notFirstBoot_doesNotClear")
}
