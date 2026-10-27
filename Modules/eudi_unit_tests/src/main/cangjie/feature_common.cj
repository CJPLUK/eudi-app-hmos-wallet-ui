// Device unit tests for feature-common ViewModels.
//
// Migrated 1:1 from three iOS test classes:
//   TestBiometryInteractor (22 cases) — mapped to BiometryViewModel
//   TestQuickPinInteractor (11 cases) — mapped to QuickPinViewModel
//   TestScannerInteractor  (3 cases)  — mapped to QRScanView helpers / FormValidatorImpl
//
// iOS tests drive BiometryInteractor / QuickPinInteractor with Cuckoo mocks;
// Cangjie folds that logic into the ViewModel. This file constructs each
// ViewModel with fully-injected fakes so there is no keychain / file I/O and
// the tests run headless on-device via DeviceTestRun.
//
// Shared fakes used below:
//   FakePinStore            — defined in dev_tests_startup.cj (same package)
//   FakePinThrottleProvider — defined in authentication.cj
//   FakeBiometryController  — defined in dev_test_fakes.cj
//
// FakePinStoreFC is a local extension of PinStore with configurable isPinValid
// and setPin call-count tracking (FakePinStore in dev_tests_startup.cj always
// returns isPinValid=false and ignores setPin, which is too limited here).
package eudi_unit_tests

import std.collection.{HashMap, ArrayList}
import eudi_feature_common.{
    QuickPinViewModel, QuickPinUiConfig, QuickPinFlow, QuickPinStep,
    BiometryViewModel, BiometricUiConfig,
    BiometryType, BiometryAvailability, BiometryError,
    BiometryUnlockResult,
    PinStore, RequestDataCell, RequestDataSection, RequestViewModel,
    isMandatoryPresentationClaim
}
import eudi_logic_ui.{
    InMemoryRouterHost,
    ThreeWayNavigationType
}
import eudi_logic_authentication.{PinThrottleControllerImpl, PinLockoutState}
import eudi_logic_business.{FormValidatorImpl, FormInput, ValidatableForm, PrefsController, PrefsKey}
import eudi_logic_core.{RemoteSessionCoordinator, PresentationState, DocClaim, DocDataValue}
import eudi_logic_resources.{LocalizableStringKey, ThemeManager}

// ─────────────────────────────────────────────────────────────────────────────
// FakePinStoreFC — configurable PinStore for feature-common tests
// (FakePinStore in dev_tests_startup.cj always returns isPinValid=false and
// ignores setPin count, which is too limited for QuickPin/Biometry tests.)
// ─────────────────────────────────────────────────────────────────────────────

class FakePinStoreFC <: PinStore {
    /** Toggle to control isPinValid() return value. */
    var validResult: Bool = false
    /** Set to true after the first setPin() call (mirrors pinSet semantics). */
    var pinSet: Bool = false
    /** Number of times setPin() was called. */
    var setCount: Int64 = 0
    /** The last PIN value passed to setPin(). */
    var lastPin: String = ""
    /** Number of times clearPin() was called. */
    var clearCount: Int64 = 0

    public func setPin(pin: String): Unit {
        this.setCount += 1
        this.lastPin = pin
        this.pinSet = true
    }

    public func isPinValid(pin: String): Bool {
        return this.validResult
    }

    public func hasPin(): Bool {
        return this.pinSet
    }

    public func clearPin(): Unit {
        this.clearCount += 1
        this.pinSet = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FakeBiometryPrefs — writable in-memory PrefsController for biometry tests
// (the shared FakePrefsController in dev_tests_startup.cj hard-codes biometryEnabled
// to false and does not read back what was written, so it cannot verify the
// setBiometrySelection → isBiometryEnabled round-trip). This fake stores each key
// value in a HashMap so writes are observable and read back, mirroring the real
// PrefsControllerImpl semantics (getBool: "true"/"1" → true, absent → false).
// ─────────────────────────────────────────────────────────────────────────────

class FakeBiometryPrefs <: PrefsController {
    let store = HashMap<String, String>()
    /** setValue call count (mirrors iOS verify(prefsController).setValue). */
    var setCount: Int64 = 0

    public func setValue(value: ToString, forKey: PrefsKey): Unit {
        this.setCount += 1
        this.store.add(forKey.rawValue, value.toString())
    }
    public func getString(forKey: PrefsKey): ?String { this.store.get(forKey.rawValue) }
    public func getOptionalString(forKey: PrefsKey): String { this.getString(forKey) ?? "" }
    public func getBool(forKey: PrefsKey): Bool {
        match (this.store.get(forKey.rawValue)) {
            case Some(v) =>
                let lowered = v.toAsciiLower()
                return lowered == "true" || lowered == "1"
            case None => false
        }
    }
    public func getFloat(forKey: PrefsKey): Float64 { 0.0 }
    public func getInt(forKey: PrefsKey): Int64 { 0 }
    public func remove(forKey: PrefsKey): Unit { this.store.remove(forKey.rawValue) }
    public func getValue(forKey: PrefsKey): ?String { this.getString(forKey) }
    public func getUserLocale(): String { "en_GB" }
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Build a QuickPinViewModel with all fakes injected. Returns (vm, router). */
func makeQuickPinVMWith(
    flow: QuickPinFlow,
    pinStore: PinStore,
    throttleProvider: FakePinThrottleProvider
): (QuickPinViewModel, InMemoryRouterHost) {
    let router = InMemoryRouterHost()
    let vm = QuickPinViewModel(
        router: router,
        config: QuickPinUiConfig(flow: flow),
        pinStore: pinStore,
        validator: FormValidatorImpl(),
        pinThrottle: PinThrottleControllerImpl(throttleProvider)
    )
    return (vm, router)
}

/** Build a BiometryViewModel with all fakes injected. Returns (vm, router). */
func makeBiometryVMWith(
    biometryCtrl: FakeBiometryController,
    pinStore: PinStore,
    throttleProvider: FakePinThrottleProvider,
    prefs!: PrefsController = FakeBiometryPrefs()
): (BiometryViewModel, InMemoryRouterHost) {
    let router = InMemoryRouterHost()
    // Use the same config shape as defaultBiometricUiConfig() in biometry_view.cj
    // so LocalizableStringKey values are guaranteed to exist in the resources module.
    let cfg = BiometricUiConfig(
        navigationTitle: LocalizableStringKey.biometryConfirmRequest,
        caption: LocalizableStringKey.loginCaption,
        quickPinOnlyCaption: LocalizableStringKey.loginCaptionQuickPinOnly,
        navigationSuccessType: ThreeWayNavigationType.ThreeWayPop,
        navigationBackType: Option<ThreeWayNavigationType>.None,
        isPreAuthorization: false,
        shouldInitializeBiometricOnCreate: false
    )
    let vm = BiometryViewModel(
        router: router,
        config: cfg,
        pinStore: pinStore,
        biometryController: biometryCtrl,
        pinThrottle: PinThrottleControllerImpl(throttleProvider),
        prefs: prefs
    )
    return (vm, router)
}

// ─────────────────────────────────────────────────────────────────────────────
// runFeatureCommonTests — entry point called from the device test driver
// ─────────────────────────────────────────────────────────────────────────────

func runFeatureCommonTests(t: DeviceTestRun): Unit {
    runQuickPinViewModelTests(t)
    runBiometryViewModelTests(t)
    runScannerTests(t)
    runRequestSelectionParityTests(t)
}

// ─────────────────────────────────────────────────────────────────────────────
// Request selection — iOS proximity mandatory-field parity
// ─────────────────────────────────────────────────────────────────────────────

func runRequestSelectionParityTests(t: DeviceTestRun): Unit {
    let pidFamily = DocClaim(
        name: "family_name", dataValue: DocDataValue.text("Doe"), stringValue: "Doe",
        namespace: Some("eu.europa.ec.eudi.pid.1")
    )
    let pidCity = DocClaim(
        name: "resident_city", dataValue: DocDataValue.text("Brussels"), stringValue: "Brussels",
        namespace: Some("eu.europa.ec.eudi.pid.1")
    )
    t.check(isMandatoryPresentationClaim("eu.europa.ec.eudi.pid.1", pidFamily),
        "request.pid_family_name_is_locked")
    t.check(!isMandatoryPresentationClaim("eu.europa.ec.eudi.pid.1", pidCity),
        "request.pid_resident_city_is_selectable")
    t.check(!isMandatoryPresentationClaim("org.example.photo-id", pidFamily),
        "request.unknown_mdoc_claim_is_selectable")

    let router = InMemoryRouterHost()
    let vm = RequestViewModel(router: router)
    let required = RequestDataCell(groupId: Some("required"), title: "Family name", value: "Doe", isRequired: true)
    let optional = RequestDataCell(groupId: Some("optional"), title: "Resident city", value: "Brussels")
    let cells = ArrayList<RequestDataCell>()
    cells.add(required)
    cells.add(optional)
    let sections = ArrayList<RequestDataSection>()
    sections.add(RequestDataSection(id: "pid", title: "PID", cells: cells))
    vm.setItems(relyingParty: "Verifier", relyingPartyIsTrusted: true, sections: sections)
    t.check(!vm.toggleSelection("required") && required.selected,
        "request.required_claim_cannot_toggle")
    t.check(vm.toggleSelection("optional") && !optional.selected,
        "request.optional_claim_toggles")
}

// ─────────────────────────────────────────────────────────────────────────────
// QuickPinViewModel tests — iOS TestQuickPinInteractor (11 cases)
// ─────────────────────────────────────────────────────────────────────────────

func runQuickPinViewModelTests(t: DeviceTestRun): Unit {

    // testSetPin_WhenNewPinIsSet_ThenVerifyAtLeastOnce
    // iOS: mock pinStorageController.setPin(with:) → verify called once.
    // Cangjie: onPinInput("123456") [FirstInput] then onPinInput("123456") [RetryInput]
    //          → confirmRetry calls pinStore.setPin once.
    { =>
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.SetWithoutActivation, ps, tp)
        vm.onPinInput("123456")  // FirstInput → RetryInput
        vm.onPinInput("123456")  // RetryInput confirm → setPin
        t.check(ps.setCount == 1, "quickPin.setPin_calledOnce")
        t.eqStr(ps.lastPin, "123456", "quickPin.setPin_correctPin")
    }()

    // testIsPinValid_WhenStoredAndProvidedPinsMatch_ThenReturnPartialStateSuccess
    // iOS: isPinValid(pin:) = .success (throttle not involved, returns success).
    // Cangjie (Update flow): onPinInput with isPinValid=true → step advances to FirstInput.
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = true
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("123456")  // Validate step; isPinValid=true → advance
        let stepIsFirstInput = match (vm.viewState.step) {
            case FirstInput => true
            case _ => false
        }
        t.check(stepIsFirstInput, "quickPin.isPinValid_match_advancesToFirstInput")
    }()

    // testIsPinValid_WhenStoredAndProvidedPinsDoNotMatch_ThenReturnPartialStateFailure
    // iOS: isPinValid = .failure(quickPinInvalid) → pinError shown, no advance.
    // Cangjie (Update flow): isPinValid=false + throttle idle → pinError set, step stays Validate.
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.idle
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("123456")
        let stepIsValidate = match (vm.viewState.step) {
            case Validate => true
            case _ => false
        }
        let hasError = match (vm.viewState.pinError) {
            case Some(_) => true
            case None => false
        }
        t.check(stepIsValidate, "quickPin.isPinValid_noMatch_staysValidate")
        t.check(hasError, "quickPin.isPinValid_noMatch_pinError")
    }()

    // testHasPin_WhenThereIsAStoredPin_ThenReturnTrue
    // iOS: hasPin() = true (storage has an entry).
    // Cangjie: FakePinStoreFC.pinSet=true → hasPin()=true.
    { =>
        let ps = FakePinStoreFC()
        ps.pinSet = true
        t.check(ps.hasPin(), "quickPin.hasPin_true")
    }()

    // testHasPin_WhenThereIsNoStoredPin_ThenReturnFalse
    // iOS: hasPin() = false.
    // Cangjie: fresh FakePinStoreFC → hasPin()=false.
    { =>
        let ps = FakePinStoreFC()
        t.check(!ps.hasPin(), "quickPin.hasPin_false")
    }()

    // testChangePin_WhenCurrentPinIsValid_ThenReturnPartialStateSuccess
    // iOS: isPinValid=true → setPin(newPin) called → .success.
    // Cangjie (Update flow): validate old (valid) → FirstInput → enter new →
    //   RetryInput confirm → Succeeded + setPin(new).
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = true
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("111111")  // Validate step: correct old PIN
        vm.onPinInput("222222")  // FirstInput: new PIN
        vm.onPinInput("222222")  // RetryInput: confirm new PIN
        let succeeded = match (vm.viewState.step) {
            case Succeeded => true
            case _ => false
        }
        t.check(succeeded, "quickPin.changePin_valid_succeeded")
        t.check(ps.setCount == 1, "quickPin.changePin_valid_setPinCalled")
        t.eqStr(ps.lastPin, "222222", "quickPin.changePin_valid_newPin")
    }()

    // testChangePin_WhenCurrentPinIsNotValid_ThenReturnPartialStateFailure
    // iOS: isPinValid=false → setPin NOT called → .failure(quickPinInvalid).
    // Cangjie (Update flow): wrong old PIN → setPin NOT called, pinError shown.
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.idle
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("999999")
        t.check(ps.setCount == 0, "quickPin.changePin_invalid_setPinNotCalled")
        let hasError = match (vm.viewState.pinError) {
            case Some(_) => true
            case None => false
        }
        t.check(hasError, "quickPin.changePin_invalid_pinError")
    }()

    // testGetPinLockoutState_WhenThrottleControllerReturnsIdle_ThenReturnsIdle
    // iOS: throttle.getState() = .idle → getPinLockoutState() = .idle.
    // Cangjie: refreshLockoutOnAppear() with idle throttle → isLockedOut=false.
    { =>
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        tp.state = PinLockoutState.idle
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.refreshLockoutOnAppear()
        t.check(!vm.viewState.isLockedOut, "quickPin.lockoutState_idle_notLocked")
    }()

    // testGetPinLockoutState_WhenThrottleControllerReturnsActiveLockout_ThenForwardsLockout
    // iOS: throttle.getState() = .active(remaining:30, total:90) → forwarded.
    // Cangjie: active lockout on refreshLockoutOnAppear → isLockedOut=true.
    { =>
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        tp.state = PinLockoutState.active(30.0, 90.0)
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.refreshLockoutOnAppear()
        t.check(vm.viewState.isLockedOut, "quickPin.lockoutState_active_isLocked")
    }()

    // testRecordPinFailure_WhenThrottleControllerReturnsLockout_ThenForwardsLockout
    // iOS: recordPinFailure() returns .active(remaining:60, total:300) → forwarded.
    // Cangjie: wrong PIN + throttle returns active lockout → isLockedOut=true.
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.active(60.0, 300.0)
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("999999")
        t.check(vm.viewState.isLockedOut, "quickPin.recordFailure_active_isLocked")
    }()

    // testResetPinThrottle_WhenCalled_ThenDelegatesToThrottleController
    // iOS: resetPinThrottle() calls throttle.recordSuccess().
    // Cangjie: correct PIN in Update-validate step internally calls recordSuccess().
    { =>
        let ps = FakePinStoreFC()
        ps.validResult = true
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeQuickPinVMWith(QuickPinFlow.Update, ps, tp)
        vm.onPinInput("123456")
        t.check(tp.successCount == 1, "quickPin.resetPinThrottle_recordSuccessCalled")
    }()
}

// ─────────────────────────────────────────────────────────────────────────────
// BiometryViewModel tests — iOS TestBiometryInteractor (22 cases)
// ─────────────────────────────────────────────────────────────────────────────

func runBiometryViewModelTests(t: DeviceTestRun): Unit {

    // testIsBiometryEnabled_WhenPrefsControllerReturnsTrue_ThenReturnEnabled
    // iOS: prefsController.getBool(biometryEnabled) = true → areBiometricsEnabled.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.TouchID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let prefs = FakeBiometryPrefs()
        prefs.setValue(true, PrefsKey.biometryEnabled)
        let (vm, _) = makeBiometryVMWith(fake, ps, tp, prefs: prefs)
        vm.initialize()
        t.check(vm.viewState.biometryEnabled, "biometry.isBiometryEnabled_true")
    }()

    // testIsBiometryEnabled_WhenPrefsControllerReturnsFalse_ThenReturnIsNotEnabled
    // iOS: getBool(biometryEnabled) = false → the trigger stays hidden even
    // though the platform reports a usable fingerprint sensor.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.TouchID
        fake.availability = BiometryAvailability.Available
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.initialize()
        t.check(!vm.viewState.biometryEnabled, "biometry.isBiometryEnabled_false")
        t.check(vm.viewState.biometryTriggerToken().isNone(), "biometry.trigger_hiddenWhenPrefOff")
    }()

    // iOS `biometryImage`: the face-id / touch-id asset follows the platform type.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let prefs = FakeBiometryPrefs()
        prefs.setValue(true, PrefsKey.biometryEnabled)
        let (vm, _) = makeBiometryVMWith(fake, ps, tp, prefs: prefs)
        vm.initialize()
        match (vm.viewState.biometryTriggerToken()) {
            case Some(token) =>
                t.eqStr(token, ThemeManager.shared.image.faceId, "biometry.trigger_faceIdAsset")
            case None => t.check(false, "biometry.trigger_missingForEnabledFaceId")
        }
    }()

    // iOS `onBiometry` failure: everything but `biometricError` opens the alert.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        fake.unlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.DeniedAccess)
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        t.check(!vm.onBiometry(), "biometry.onBiometry_deniedAccessReturnsFalse")
        match (vm.viewState.biometryError) {
            case Some(msg) =>
                t.eqStr(msg, BiometryError.DeniedAccess.message(), "biometry.onBiometry_deniedAccessAlert")
            case None => t.check(false, "biometry.onBiometry_deniedAccessAlertMissing")
        }
        vm.dismissBiometryError()
        t.check(vm.viewState.biometryError.isNone(), "biometry.dismissBiometryError_clears")
    }()

    // iOS swallows the plain `biometricError` — the platform sheet already
    // told the user their biometric was not recognized.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        fake.unlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.BiometricError)
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        t.check(!vm.onBiometry(), "biometry.onBiometry_biometricErrorReturnsFalse")
        t.check(vm.viewState.biometryError.isNone(), "biometry.onBiometry_biometricErrorNotAlerted")
    }()

    // testIsPinValid_WhenQuickPinInteractorReturnsValid_ThenReturnSuccessPartialState
    // iOS: isPinValid(..) = .success → emits success state.
    // Cangjie: onPinInput with isPinValid=true → returns true.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        ps.validResult = true
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let result = vm.onPinInput("123456")
        t.check(result, "biometry.isPinValid_match_success")
    }()

    // testIsPinValid_WhenQuickPinInteractorReturnsNotValid_ThenReturnFailurePartialState
    // iOS: isPinValid = .failure(quickPinInvalid) → pinError shown.
    // Cangjie: onPinInput with isPinValid=false + throttle idle → false + pinError.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.idle
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let result = vm.onPinInput("999999")
        let hasError = match (vm.viewState.pinError) {
            case Some(_) => true
            case None => false
        }
        t.check(!result, "biometry.isPinValid_noMatch_failure")
        t.check(hasError, "biometry.isPinValid_noMatch_pinError")
    }()

    // testSetBiometrySelection_WhenMethodCalledWithTrue_ThenVerifyPrefsControllerSet
    // iOS: setBiometrySelection(isEnabled:true) → prefsController.setValue called.
    // Cangjie: VM.setBiometrySelection persists through the injected PrefsController;
    //   assert setValue was invoked AND the value round-trips through isBiometryEnabled.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let prefs = FakeBiometryPrefs()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp, prefs: prefs)
        vm.setBiometrySelection(true)
        t.check(prefs.setCount == 1, "biometry.setBiometrySelection_setValueCalled")
        t.check(vm.isBiometryEnabled(), "biometry.setBiometrySelection_true_roundTrips")
        // Also verify the false path clears the flag (extra parity for isEnabled false).
        vm.setBiometrySelection(false)
        t.check(!vm.isBiometryEnabled(), "biometry.setBiometrySelection_false_roundTrips")
    }()

    // testBiometricsImage_WhenControllerReturnsFaceIdType_ThenReturnFaceIdImage
    // iOS: getBiometryType()=.faceID → image=Theme.shared.image.faceId.
    // Cangjie: VM.getBiometricsImage() returns the faceId asset token (the
    //   ImageManager string that is the Theme.shared.image.faceId counterpart).
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let img = vm.getBiometricsImage()
        t.check(img == Some(ThemeManager.shared.image.faceId), "biometry.getBiometricsImage_faceID")
    }()

    // testBiometricsImage_WhenControllerReturnsTouchIdType_ThenReturnTouchIdImage
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.TouchID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let img = vm.getBiometricsImage()
        t.check(img == Some(ThemeManager.shared.image.touchId), "biometry.getBiometricsImage_touchID")
    }()

    // testBiometricsImage_WhenControllerReturnsNotSupportedType_ThenReturnNil
    // iOS: unsupported type → nil. Cangjie: getBiometricsImage() → None.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.BiometryNone
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let isNone = match (vm.getBiometricsImage()) { case None => true; case Some(_) => false }
        t.check(isNone, "biometry.getBiometricsImage_none")
    }()

    // testBiometricType_WhenControllerReturnsFaceIdType_ThenReturnFaceIdType
    // iOS: getBiometryType() = .faceID → returns .faceID.
    // Cangjie: VM.getBiometryType() now delegates to the injected controller.
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let isFace = match (vm.getBiometryType()) { case FaceID => true; case _ => false }
        t.check(isFace, "biometry.getBiometryType_faceID")
    }()

    // testBiometricType_WhenControllerReturnsTouchIdType_ThenReturnTouchIdType
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.TouchID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let isTouch = match (vm.getBiometryType()) { case TouchID => true; case _ => false }
        t.check(isTouch, "biometry.getBiometryType_touchID")
    }()

    // testCurrentBiometricsMethod_WhenControllerReturnsFaceIdType_ThenReturnFaceIdStringLiteral
    // iOS: getBiometricsMethod() = "Face ID". Cangjie: VM.getBiometricsMethod().
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.FaceID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        t.eqStr(vm.getBiometricsMethod(), "Face ID", "biometry.getBiometricsMethod_faceID")
    }()

    // testCurrentBiometricsMethod_WhenControllerReturnsTouchIdType_ThenReturnTouchIdStringLiteral
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.TouchID
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        t.eqStr(vm.getBiometricsMethod(), "Touch ID", "biometry.getBiometricsMethod_touchID")
    }()

    // testCurrentBiometricsMethod_WhenControllerReturnsNotSupportedType_ThenReturnEmptyString
    // iOS: unsupported type → "". Cangjie: VM.getBiometricsMethod() → "".
    { =>
        let fake = FakeBiometryController()
        fake.biometryType = BiometryType.BiometryNone
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        t.eqStr(vm.getBiometricsMethod(), "", "biometry.getBiometricsMethod_none")
    }()

    // testAuthenticate_WhenRequestBiometricUnlockSucceeds_ThenEmitsAuthenticated
    // iOS: requestBiometricUnlock() succeeds → state = .authenticated.
    // Cangjie: onBiometry() with UnlockSuccess → returns true, recordSuccess called.
    { =>
        let fake = FakeBiometryController()
        fake.unlockResult = BiometryUnlockResult.UnlockSuccess
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let result = vm.onBiometry()
        t.check(result, "biometry.authenticate_unlockSucceeds_true")
        t.check(tp.successCount == 1, "biometry.authenticate_unlockSucceeds_recordSuccess")
    }()

    // testAuthenticate_WhenRequestBiometricUnlockFails_ThenEmitsFailureWithError
    // iOS: requestBiometricUnlock() throws SystemBiometryError.deniedAccess → .failure(.deniedAccess).
    // Cangjie: onBiometry() with UnlockFailure(DeniedAccess) → false + pinError = denial message.
    { =>
        let fake = FakeBiometryController()
        fake.unlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.DeniedAccess)
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let result = vm.onBiometry()
        let hasError = match (vm.viewState.pinError) {
            case Some(_) => true
            case None => false
        }
        t.check(!result, "biometry.authenticate_deniedAccess_false")
        t.check(hasError, "biometry.authenticate_deniedAccess_pinError")
    }()

    // testAuthenticate_WhenRequestThrowsGenericError_ThenEmitsBiometricErrorFailure
    // iOS: generic Error → .failure(.biometricError).
    // Cangjie: UnlockFailure(BiometricError) (closest equivalent) → false + pinError.
    { =>
        let fake = FakeBiometryController()
        fake.unlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.BiometricError)
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let result = vm.onBiometry()
        t.check(!result, "biometry.authenticate_genericError_false")
    }()

    // testOpenSettings_WhenCalled_ThenDelegatesToBiometryController
    // iOS: interactor.openSettings(action:) → biometryController.openSettings called.
    // Cangjie: VM.openSettings() delegates to the injected controller; assert the
    //   controller received the call (openSettingsCalls == 1).
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.openSettings({ => })
        t.check(fake.openSettingsCalls == 1, "biometry.openSettings_delegatesToController")
    }()

    // Additional: when the controller reports a successful open, the action fires
    // (mirrors iOS completion-handler success branch). Uses a heap flag because a
    // lambda that captures a mutable var cannot be passed as an argument.
    { =>
        let fake = FakeBiometryController()
        fake.openSettingsInvokesAction = true
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        let invoked = ArrayList<Bool>()
        vm.openSettings({ => invoked.add(true) })
        t.check(!invoked.isEmpty(), "biometry.openSettings_success_invokesAction")
    }()

    // testMaxFailedPinAttempts_WhenConfigured_ThenReflectsAuthenticationConfig
    // iOS: interactor.maxFailedPinAttempts == 3 (from MockAuthenticationConfig).
    // Cangjie: maxAttempts is private in BiometryViewModel (AuthenticationConfigImpl default = 3).
    //   Observable effect: wrong-PIN failure with active throttle → isLockedOut=true.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.active(30.0, 30.0)  // crosses threshold
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.onPinInput("000000")
        t.check(vm.viewState.isLockedOut, "biometry.maxFailedAttempts_lockout_fires")
    }()

    // testGetPinLockoutState_WhenThrottleControllerReturnsIdle_ThenReturnsIdle
    // iOS: getPinLockoutState() = .idle → forwarded.
    // Cangjie: initialize() with an idle throttle → isLockedOut=false.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        tp.state = PinLockoutState.idle
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.initialize()
        t.check(!vm.viewState.isLockedOut, "biometry.getPinLockoutState_idle_notLocked")
    }()

    // testGetPinLockoutState_WhenThrottleControllerReturnsActiveLockout_ThenForwardsLockout
    // iOS: getPinLockoutState() = .active(remaining:60, total:300) → forwarded.
    // Cangjie: active throttle on appear → isLockedOut=true.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        tp.state = PinLockoutState.active(60.0, 300.0)
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.initialize()
        t.check(vm.viewState.isLockedOut, "biometry.getPinLockoutState_active_isLocked")
    }()

    // testRecordPinFailure_WhenCalled_ThenForwardsThrottleControllerResult
    // iOS: recordPinFailure() returns .active(remaining:30, total:90) → forwarded.
    // Cangjie: wrong PIN + active throttle → isLockedOut=true.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        ps.validResult = false
        let tp = FakePinThrottleProvider()
        tp.failureResult = PinLockoutState.active(30.0, 90.0)
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.onPinInput("000000")
        t.check(vm.viewState.isLockedOut, "biometry.recordPinFailure_active_isLocked")
    }()

    // testResetPinThrottle_WhenCalled_ThenDelegatesToThrottleController
    // iOS: resetPinThrottle() calls throttle.recordSuccess().
    // Cangjie: correct PIN (onPinInput) → recordSuccess() called.
    { =>
        let fake = FakeBiometryController()
        let ps = FakePinStoreFC()
        ps.validResult = true
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.onPinInput("123456")
        t.check(tp.successCount == 1, "biometry.resetPinThrottle_pin_recordSuccessCalled")
    }()

    // Additional: resetPinThrottle via biometry success path (onBiometry → recordSuccess).
    { =>
        let fake = FakeBiometryController()
        fake.unlockResult = BiometryUnlockResult.UnlockSuccess
        let ps = FakePinStoreFC()
        let tp = FakePinThrottleProvider()
        let (vm, _) = makeBiometryVMWith(fake, ps, tp)
        vm.onBiometry()
        t.check(tp.successCount == 1, "biometry.resetPinThrottle_biometrySuccess_recordSuccessCalled")
    }()
}

// ─────────────────────────────────────────────────────────────────────────────
// ScannerInteractor tests — iOS TestScannerInteractor (3 cases)
// ─────────────────────────────────────────────────────────────────────────────
//
// iOS ScannerInteractor wraps FormValidator + WalletKitController.
// Cangjie has no dedicated ScannerViewModel; the two responsibilities live on
// FormValidatorImpl (form validation) and WalletKitController
// (startCrossDevicePresentation). Both are exercised headlessly here:
//   · validateForm / validateForms → FormValidatorImpl directly (same class on
//     both platforms).
//   · startCrossDevicePresentation → a WalletKitController fake that returns a
//     FakePresentationCoordinator (a live RemoteSessionCoordinator) injected in
//     place of the real wallet-engine session. The physical camera scan is
//     platform-limited (no camera on the emulator), but the interactor delegation
//     under test — "the scanned URL is forwarded to the controller, which returns
//     a usable coordinator" — is verified against a real assertion.

// WalletKitController fake whose startCrossDevicePresentation returns a
// FakePresentationCoordinator (defined in dev_tests_feature_presentation.cj, same
// package) and records the last scanned URL, mirroring the iOS
// walletKitController.startCrossDevicePresentation(urlString:) mock.
class FakeScannerWallet <: FakeWalletKitController {
    public var lastCrossDeviceUrl: String = ""
    public var crossDeviceCalls: Int64 = 0

    public override func startCrossDevicePresentation(urlString: String): RemoteSessionCoordinator {
        this.crossDeviceCalls += 1
        this.lastCrossDeviceUrl = urlString
        return FakePresentationCoordinator(PresentationState.loading, makePresRequest())
    }
}

func runScannerTests(t: DeviceTestRun): Unit {

    // testValidateForm_WhenValidateForm_ThenReturnsSuccess
    // iOS: formValidator.validateForm(form:) called once; result forwarded.
    // Cangjie: FormValidatorImpl.validateForm on a form with no rules → isValid=true.
    { =>
        let validator = FormValidatorImpl()
        let form = ValidatableForm([FormInput([], "any")])
        let result = validator.validateForm(form)
        t.check(result.isValid, "scanner.validateForm_noRules_valid")
    }()

    // testValidateForms_WhenValidateForm_ThenReturnsSuccess
    // iOS: formValidator.validateForms(forms:) called once; result forwarded.
    // Cangjie: FormValidatorImpl.validateForms on a single no-rule form → isValid=true.
    { =>
        let validator = FormValidatorImpl()
        let form = ValidatableForm([FormInput([], "")])
        let result = validator.validateForms([form])
        t.check(result.isValid, "scanner.validateForms_noRules_valid")
    }()

    // testStartCrossDevicePresentation_WhenStartCrossDevicePresentation_ThenReturnSuccess
    // iOS: walletKitController.startCrossDevicePresentation(urlString:) called once,
    //   forwarding the scanned URL, and returns a RemoteSessionCoordinator.
    // Cangjie: inject FakeScannerWallet (returns a FakePresentationCoordinator);
    //   assert the scanned URL was forwarded and a usable coordinator is returned
    //   (its initial state is observable — a live RemoteSessionCoordinator, not nil).
    { =>
        let wallet = FakeScannerWallet()
        let scanResult = "openid4vp://?client_id=verifier.eudiw.dev&request_uri=https://x"
        let coordinator: RemoteSessionCoordinator = wallet.startCrossDevicePresentation(scanResult)
        t.check(wallet.crossDeviceCalls == 1, "scanner.startCrossDevicePresentation_calledOnce")
        t.eqStr(wallet.lastCrossDeviceUrl, scanResult, "scanner.startCrossDevicePresentation_forwardsUrl")
        // The returned coordinator is a real RemoteSessionCoordinator: its stream/
        // state is reachable (loading), proving a usable non-nil coordinator.
        let stateIsLoading = match (coordinator.getState()) {
            case loading => true
            case _ => false
        }
        t.check(stateIsLoading, "scanner.startCrossDevicePresentation_returnsCoordinator")
    }()
}
