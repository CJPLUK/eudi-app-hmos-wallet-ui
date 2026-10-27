/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-startup module
 * (Sources/UI/StartupView.swift, StartupViewModel.swift,
 *  Sources/Interactor/StartupInteractor.swift) to Cangjie ArkUI.
 *
 * Startup decision logic:
 *  1. manageStorageForFirstRun — if PrefsController.runAtLeastOnce is false,
 *     clear any stale state and set the flag (mirrors iOS first-run guard).
 *  2. splashDuration delay.
 *  3. PinStore.hasPin() → true: push biometry config (verify flow).
 *     PinStore.hasPin() → false: push quickPin config (set flow).
 *     Whether forcePidActivation is true affects the successor route inside
 *     those flows (mirrors iOS StartupInteractor :53 / :73 branches).
 *
 * walletKitController (loadDocuments / fetchAllDocuments) is in logic-core
 * which is not yet delivered; per target_architecture decision the hasDocuments
 * check is skipped and the biometry success nav defaults to dashboard, matching
 * the no-document path behaviour (forcePidActivation == false default).
 *
 * Plain @Component — no @Entry / NavDestination. The composition root owns the
 * navigation shell and mounts StartupView as the "startup" destination.
 */
package eudi_feature_startup

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.hilog.*
import std.time.*
import kit.ArkUI.*
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager, ImageManager}
import eudi_feature_common.{PinStore, FilePinStore, QuickPinFlow, QuickPinUiConfig, BiometricUiConfig}
import eudi_logic_business.{PrefsController, PrefsControllerImpl, PrefsKey, ConfigLogic, ConfigLogicImpl}
import eudi_logic_core.WalletKitController

// ─── StartupState ────────────────────────────────────────────────────────────

/** Mirrors Swift `StartupState: ViewState`. */
public class StartupState <: ViewState {
    public let splashDuration: Float64
    public let hasError: Bool

    public init(splashDuration!: Float64 = 1.5, hasError!: Bool = false) {
        this.splashDuration = splashDuration
        this.hasError = hasError
    }
}

// ─── StartupInteractor ───────────────────────────────────────────────────────

/**
 * Mirrors Swift `StartupInteractor` protocol (initialize → AppRoute string).
 * Returns Some(route-name) on success, None on failure (mirrors iOS
 * `setupError` semantics — Cangjie has no throws, failures travel as payload).
 */
public interface StartupInteractor {
    /**
     * Run first-run housekeeping, wait splash duration, then return Some(route)
     * the app should navigate to, or None if initialisation failed.
     */
    func initialize(splashDuration: Float64): Option<String>
}

/**
 * Mirrors Swift `StartupInteractorImpl`. Uses `PinStore` (eudi_feature_common)
 * for hasPin, `PrefsController` for first-run flag, `ConfigLogic` for
 * forcePidActivation, and `WalletKitController` (logic-core) for the document
 * check that picks the post-biometry destination.
 */
public class StartupInteractorImpl <: StartupInteractor {
    private let pinStore: PinStore
    private let prefsController: PrefsController
    private let configLogic: ConfigLogic
    /**
     * None only on the degraded path below (a StartupView built without an injected
     * ViewModel, which cannot reach the composition root that owns the wallet).
     * The app always injects it, so the routing decision uses the real store.
     */
    private let walletController: ?WalletKitController

    public init(
        pinStore!: PinStore,
        prefsController!: PrefsController,
        configLogic!: ConfigLogic,
        walletController!: ?WalletKitController = None
    ) {
        this.pinStore = pinStore
        this.prefsController = prefsController
        this.configLogic = configLogic
        this.walletController = walletController
    }

    public func initialize(splashDuration: Float64): Option<String> {
        try {
            manageStorageForFirstRun()
            sleepMillis(Int64(splashDuration * 1000.0))
            if (this.pinStore.hasPin()) {
                // iOS StartupInteractor:61-63 — both inputs matter: a wallet that
                // already holds documents goes to the dashboard even when PID
                // activation is forced.
                let successRoute = if (!this.hasDocuments() && this.configLogic.forcePidActivation) {
                    AppRoutes.issuanceAddDocument
                } else {
                    AppRoutes.dashboard
                }
                NavArgs.shared.set(AppRoutes.biometry, buildBiometricConfig(successRoute))
                return Some(AppRoutes.biometry)
            } else {
                let flow = if (this.configLogic.forcePidActivation) {
                    QuickPinFlow.SetWithActivation
                } else {
                    QuickPinFlow.SetWithoutActivation
                }
                NavArgs.shared.set(AppRoutes.quickPin, RouteConfigArgs(QuickPinUiConfig(flow: flow)))
                return Some(AppRoutes.quickPin)
            }
        } catch (_: Exception) {
            return None
        }
    }

    /**
     * iOS: `try? await walletKitController.loadDocuments()` followed by
     * `!fetchAllDocuments().isEmpty`. Both calls are best-effort there (`try?`), so
     * a store that cannot be read degrades to "no documents" rather than blocking
     * startup.
     */
    private func hasDocuments(): Bool {
        match (this.walletController) {
            case Some(wallet) =>
                try {
                    wallet.loadDocuments()
                } catch (_: Exception) {
                    ()
                }
                try {
                    return !wallet.fetchAllDocuments().isEmpty()
                } catch (_: Exception) {
                    return false
                }
            // No wallet reachable → same conservative answer iOS gives when its
            // best-effort load fails.
            case None => false
        }
    }

    private func manageStorageForFirstRun(): Unit {
        if (!this.prefsController.getBool(PrefsKey.runAtLeastOnce)) {
            // Mirrors iOS StartupInteractor:88 — clear stale credentials on first run.
            // walletKitController.clearAllDocuments() deferred (logic-core not delivered).
            this.pinStore.clearPin()
            this.prefsController.setValue("true", PrefsKey.runAtLeastOnce)
        }
    }

    private func buildBiometricConfig(successRoute: String): RouteConfigArgs {
        // iOS StartupInteractor:56-57: navigationTitle = .enterYourPin, title = .loginTitle
        let cfg = BiometricUiConfig(
            navigationTitle: LocalizableStringKey.enterYourPin,
            title: Some(LocalizableStringKey.loginTitle),
            caption: LocalizableStringKey.loginCaption,
            quickPinOnlyCaption: LocalizableStringKey.loginCaptionQuickPinOnly,
            navigationSuccessType: ThreeWayNavigationType.ThreeWayPush(successRoute),
            navigationBackType: Option<ThreeWayNavigationType>.None,
            isPreAuthorization: true,
            shouldInitializeBiometricOnCreate: true,
            // iOS keeps the navigation bar on the login gate; the back chevron
            // is suppressed by navigationBackType == nil (isCancellable), not by
            // hiding the bar, so the "Enter your PIN" title still shows.
            displayNavigationBar: true
        )
        return RouteConfigArgs(cfg)
    }
}

// ─── sleepMillis helper ───────────────────────────────────────────────────────

/**
 * Blocks the calling thread for approximately `ms` milliseconds.
 * Called from the background thread of StartupViewModel.initialize(), not
 * the UI thread — per S-001 compliance.
 */
func sleepMillis(ms: Int64): Unit {
    if (ms <= 0) {
        return
    }
    sleep(ms * Duration.millisecond)
}

// ─── StartupViewModel ────────────────────────────────────────────────────────

/**
 * Mirrors Swift `StartupViewModel`. Holds the current StartupState and drives
 * the startup decision sequence from `initialize()`.
 *
 * `initialize()` is called from `StartupView.aboutToAppear()` via a detached
 * thread so the splash timer does not block the UI thread (S-001).
 */
public class StartupViewModel <: BaseViewModel<StartupState> {
    private let interactor: StartupInteractor
    /** Process-wide guard: the splash decides the route exactly once per launch.
     *  Without it, navigating back to the splash re-fires initialize() and pushes
     *  the auth/dashboard route again, looping the navigation and freezing the UI. */
    private static var didNavigate: Bool = false

    public init(
        router!: RouterHost,
        interactor!: StartupInteractor,
        splashDuration!: Float64 = 1.5
    ) {
        super(router, StartupState(splashDuration: splashDuration))
        this.interactor = interactor
    }

    /**
     * Runs on a background thread: blocks for splash duration then pushes the
     * decided route, or sets hasError=true if initialisation failed.
     * UI state updates are dispatched via spawn(UIThread) per S-001.
     * Mirrors iOS StartupViewModel.initialize() with setupError semantics.
     */
    public func initialize(): Unit {
        if (StartupViewModel.didNavigate) {
            // NavPathStack may be empty while pathNames still lies about
            // dashboard — probe the real stack, not getCurrentScreen().
            spawn(UIThread) {
                =>
                if (this.router.realStackIsEmpty()) {
                    Hilog.warn(0, "NavDebug", "Startup reappear with empty real stack — recovering dashboard")
                    this.router.push(AppRoutes.dashboard)
                }
            }
            return
        }
        let duration = this.viewState.splashDuration
        let routeOpt = this.interactor.initialize(duration)
        spawn(UIThread) {
            =>
            match (routeOpt) {
                case Some(route) =>
                    StartupViewModel.didNavigate = true
                    this.router.push(route)
                case None =>
                    this.setState({ prev => StartupState(splashDuration: prev.splashDuration, hasError: true) })
            }
        }
    }
}

// ─── StartupView ─────────────────────────────────────────────────────────────

/**
 * Splash / startup screen (fc_startup_screen exposed symbol `StartupView`).
 *
 * Shows the app logo centred on a full-screen background-coloured canvas,
 * then on `aboutToAppear` triggers the startup decision sequence on a
 * background thread via `StartupViewModel.initialize()`.
 *
 * Injection points:
 *  - `viewModel`: pre-built StartupViewModel (composition root wires the real
 *    RouterHost + interactor dependencies); defaults to an emulator-safe
 *    self-contained instance.
 */
@Component
public class StartupView {
    public var viewModel: ?StartupViewModel = Option<StartupViewModel>.None

    @State
    var hasError: Bool = false

    private var vm: ?StartupViewModel = Option<StartupViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.hasError = state.hasError
            }
        })
        spawn {
            =>
            model.initialize()
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func logoSrc(): String {
        ThemeManager.shared.image.logo
    }

    public func build() {
        Stack {
            AppIcon(token: this.logoSrc(), size: 160.0)
        }
        .width(100.percent)
        .height(100.percent)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
        .alignContent(Alignment.Center)
    }
}

// ─── default ViewModel factory ───────────────────────────────────────────────

/**
 * Constructs a self-contained StartupViewModel suitable for the emulator:
 * uses FilePinStore (feature-common), PrefsControllerImpl (logic-business),
 * and ConfigLogicImpl (logic-business).
 */
func makeDefaultViewModel(): StartupViewModel {
    let pinStore: PinStore = FilePinStore()
    let prefsController: PrefsController = PrefsControllerImpl()
    let configLogic: ConfigLogic = ConfigLogicImpl()
    let interactor: StartupInteractor = StartupInteractorImpl(
        pinStore: pinStore,
        prefsController: prefsController,
        configLogic: configLogic
    )
    return StartupViewModel(
        router: InMemoryRouterHost(),
        interactor: interactor
    )
}
