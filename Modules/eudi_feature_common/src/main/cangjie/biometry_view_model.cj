/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Biometry/BiometryViewModel.swift + the storage calls of
 * Interactor/BiometryInteractor.swift) to Cangjie.
 *
 * The screen authenticates with biometrics *or* the quick PIN. Like iOS, the
 * biometry trigger follows the persisted `biometryEnabled` preference and the
 * platform biometry type: without both, the caption switches to
 * `quickPinOnlyCaption`, the trigger is not rendered, and the PIN is verified
 * through the same PinStore used by the QuickPin flow (PBKDF2 hash +
 * constant-time compare — never a plain-text comparison). There is no fake
 * biometric success.
 *
 * Success/back navigation reuse the config's ThreeWayNavigationType over
 * AppRoutes names, dispatched through the injected RouterHost.
 */
package eudi_feature_common

import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}
import eudi_logic_authentication.{PinThrottleController, PinLockoutState, AuthenticationConfigImpl, LogicAuthAssembly}
import eudi_logic_business.{PrefsController, PrefsKey, createPrefsController, KeyChainControllerImpl}
import std.time.*

/**
 * Composition-root seam for the PIN lockout throttle (iOS
 * `LogicAuthAssembly.resolvePinThrottleController`). Throttle state is persisted
 * to disk by KeychainPinThrottleProvider, so a fresh controller still reads back
 * the live lockout window (counters / timestamps survive across instances).
 */
public func createPinThrottleController(): PinThrottleController {
    let keyChain = KeyChainControllerImpl(
        service: "eudi_pin_throttle",
        accessGroup: "",
        storageDir: FilePinStore.DEFAULT_STORAGE_DIR
    )
    return LogicAuthAssembly(keyChain).resolvePinThrottleController()
}

/**
 * iOS `AUTO_VERIFY_ON_APPEAR_DELAY` (250 ms): let the screen settle before the
 * platform biometric sheet takes over, so a cancel returns to a drawn page.
 */
let AUTO_VERIFY_ON_APPEAR_DELAY_MS: Int64 = 250

/** Reducer state of BiometryView (mirrors iOS `BiometryState`). */
public class BiometryViewState <: ViewState {
    public let config: BiometricUiConfig
    // iOS `areBiometricsEnabled`: the *persisted preference*, not the hardware
    // probe. Settings only lets the flag go true after a real evaluation, so a
    // true value already implies working hardware at enrolment time.
    public let biometryEnabled: Bool
    // iOS `biometryImage`: the face-id / touch-id asset, None for an
    // unsupported type. The trigger renders only when both this and
    // `biometryEnabled` are set (iOS `if areBiometricsEnabled, let image`).
    public let biometryImage: ?String
    // iOS `biometryError`: drives the alert; a plain `biometricError` is
    // swallowed because the platform sheet already reported it.
    public let biometryError: ?String
    // iOS `autoBiometryInitiated`: the on-appear auto-prompt fires once.
    public let autoBiometryInitiated: Bool
    // iOS `isCancellable`: derived from config.navigationBackType != nil.
    public let isCancellable: Bool
    public let pinError: ?LocalizableStringKey
    public let quickPinSize: Int64
    // iOS BiometryState.isLockedOut / lockoutMessage (PIN throttle UI).
    public let isLockedOut: Bool
    public let lockoutMessage: ?LocalizableStringKey

    public init(
        config!: BiometricUiConfig,
        biometryEnabled!: Bool = false,
        biometryImage!: ?String = Option<String>.None,
        biometryError!: ?String = Option<String>.None,
        autoBiometryInitiated!: Bool = false,
        pinError!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        quickPinSize!: Int64 = 6,
        isLockedOut!: Bool = false,
        lockoutMessage!: ?LocalizableStringKey = Option<LocalizableStringKey>.None
    ) {
        this.config = config
        this.biometryEnabled = biometryEnabled
        this.biometryImage = biometryImage
        this.biometryError = biometryError
        this.autoBiometryInitiated = autoBiometryInitiated
        this.isCancellable = config.navigationBackType.isSome()
        this.pinError = pinError
        this.quickPinSize = quickPinSize
        this.isLockedOut = isLockedOut
        this.lockoutMessage = lockoutMessage
    }

    public func copyWith(
        biometryEnabled!: ?Bool = Option<Bool>.None,
        biometryImage!: ??String = Option<?String>.None,
        biometryError!: ??String = Option<?String>.None,
        autoBiometryInitiated!: ?Bool = Option<Bool>.None,
        pinError!: ??LocalizableStringKey = Option<?LocalizableStringKey>.None,
        isLockedOut!: ?Bool = Option<Bool>.None,
        lockoutMessage!: ??LocalizableStringKey = Option<?LocalizableStringKey>.None
    ): BiometryViewState {
        BiometryViewState(
            config: this.config,
            biometryEnabled: biometryEnabled ?? this.biometryEnabled,
            biometryImage: biometryImage ?? this.biometryImage,
            biometryError: biometryError ?? this.biometryError,
            autoBiometryInitiated: autoBiometryInitiated ?? this.autoBiometryInitiated,
            pinError: pinError ?? this.pinError,
            quickPinSize: this.quickPinSize,
            isLockedOut: isLockedOut ?? this.isLockedOut,
            lockoutMessage: lockoutMessage ?? this.lockoutMessage
        )
    }

    /** iOS BiometryView caption switch: biometrics caption vs PIN-only caption. */
    public func captionKey(): LocalizableStringKey {
        if (this.biometryEnabled) {
            return this.config.caption
        }
        return this.config.quickPinOnlyCaption
    }

    /**
     * iOS `biometryTitleCaption()`: the header caption is suppressed when the
     * config carries its own PIN-field title or the screen is a pre-authorization
     * (login) shape — there the caption belongs above the PIN boxes instead.
     */
    public func titleCaptionKey(): ?LocalizableStringKey {
        match (this.config.pinTextFieldTitle) {
            case Some(_) => return Option<LocalizableStringKey>.None
            case None => ()
        }
        if (this.config.isPreAuthorization) {
            return Option<LocalizableStringKey>.None
        }
        return Some(this.captionKey())
    }

    /** iOS `biometryPinTitle()`: explicit config title, else the caption switch. */
    public func pinFieldTitleKey(): LocalizableStringKey {
        match (this.config.pinTextFieldTitle) {
            case Some(key) => key
            case None => this.captionKey()
        }
    }

    /** iOS `if viewState.areBiometricsEnabled, let image = viewState.biometryImage`. */
    public func biometryTriggerToken(): ?String {
        if (!this.biometryEnabled) {
            return Option<String>.None
        }
        return this.biometryImage
    }
}

/** Mirrors iOS `BiometryViewModel` on the emulator-degraded biometry seam. */
public class BiometryViewModel <: BaseViewModel<BiometryViewState> {
    private let pinStore: PinStore
    private let biometryController: BiometryController
    private let pinThrottle: PinThrottleController
    // iOS BiometryInteractor persists the biometry-enabled flag through
    // PrefsController(.biometryEnabled); injectable so tests can drive
    // set/isBiometryEnabled without touching disk.
    private let prefs: PrefsController
    private let maxAttempts: Int64
    // Generation guard: bumped whenever a tick should stop, so a stale spawned
    // loop sees the change and returns (Cangjie has no Task.cancel here).
    private var tickGen: Int64 = 0

    public init(
        router!: RouterHost,
        config!: BiometricUiConfig,
        pinStore!: PinStore = createPinStore(),
        biometryController!: BiometryController = createBiometryController(),
        pinThrottle!: PinThrottleController = createPinThrottleController(),
        prefs!: PrefsController = createPrefsController()
    ) {
        super(router, BiometryViewState(config: config))
        this.pinStore = pinStore
        this.biometryController = biometryController
        this.pinThrottle = pinThrottle
        this.prefs = prefs
        this.maxAttempts = AuthenticationConfigImpl().maxFailedPinAttempts
    }

    // ── iOS BiometryInteractor accessors (folded into the ViewModel) ──────────
    //
    // iOS surfaces these on the BiometryInteractor; the Cangjie ViewModel owns
    // the same responsibilities and exposes them 1:1, delegating to the injected
    // BiometryController (type/image/method) and PrefsController (enabled flag).

    /**
     * Mirrors iOS `setBiometrySelection(isEnabled:)`: persist the biometry-enabled
     * preference (PrefsController.setValue(_, forKey: .biometryEnabled)).
     */
    public func setBiometrySelection(isEnabled: Bool): Unit {
        this.prefs.setValue(isEnabled, PrefsKey.biometryEnabled)
    }

    /**
     * Mirrors iOS `isBiometryEnabled()`: read the persisted preference
     * (PrefsController.getBool(.biometryEnabled), false when absent).
     */
    public func isBiometryEnabled(): Bool {
        return this.prefs.getBool(PrefsKey.biometryEnabled)
    }

    /** Mirrors iOS `getBiometryType()`: delegate to the biometry controller. */
    public func getBiometryType(): BiometryType {
        return this.biometryController.getBiometryType()
    }

    /**
     * Mirrors iOS `getBiometricsImage()`: the face-id / touch-id asset token, or
     * None for an unsupported type. iOS returns `Image?`; here the token is the
     * ImageManager string (Theme.shared.image.faceId / .touchId counterpart).
     */
    public func getBiometricsImage(): ?String {
        match (this.biometryController.getBiometryType()) {
            case FaceID => Some(ThemeManager.shared.image.faceId)
            case TouchID => Some(ThemeManager.shared.image.touchId)
            case _ => Option<String>.None
        }
    }

    /**
     * Mirrors iOS `getBiometricsMethod()`: "Face ID" / "Touch ID" / "" by type.
     */
    public func getBiometricsMethod(): String {
        match (this.biometryController.getBiometryType()) {
            case FaceID => "Face ID"
            case TouchID => "Touch ID"
            case _ => ""
        }
    }

    /**
     * Mirrors iOS `openSettings(action:)`: delegate to the biometry controller,
     * which opens the app settings page and invokes `action` on a successful open.
     */
    public func openSettings(action: () -> Unit): Unit {
        this.biometryController.openSettings(action)
    }

    /**
     * Mirrors iOS `initialize()`: publish the persisted biometry preference and
     * the platform biometry asset, restore an in-progress lockout window, and —
     * when the config asks for it — fire the on-appear biometric prompt once,
     * after the same short delay iOS uses so the screen is on-screen first.
     */
    public func initialize(): Unit {
        let enabled = this.isBiometryEnabled()
        let image = this.getBiometricsImage()
        this.setState({ s =>
            s.copyWith(biometryEnabled: Some(enabled), biometryImage: Some(image))
        })
        let lockout = this.pinThrottle.getState()
        if (lockout.isActive()) {
            this.startLockoutTick(lockout.remaining())
        }
    }

    /**
     * iOS `config.shouldInitializeBiometricOnCreate, areBiometricsEnabled,
     * !autoBiometryInitiated`. The *view* owns the timing and the thread: the
     * platform call blocks its caller until ArkTS answers, and ArkTS drains
     * that queue on the UI event loop, so it must never run on the UI thread.
     */
    public func shouldAutoPromptBiometry(): Bool {
        return this.viewState.config.shouldInitializeBiometricOnCreate &&
            this.viewState.biometryEnabled && !this.viewState.autoBiometryInitiated
    }

    /** Latches the once-per-screen auto prompt (iOS `autoBiometryInitiated`). */
    public func markAutoBiometryInitiated(): Unit {
        this.setState({ s => s.copyWith(autoBiometryInitiated: Some(true)) })
    }

    /**
     * Per-keystroke PIN hook. A full-length value is verified against the
     * stored PIN through PinStore (iOS `processPin` → interactor validation).
     * Returns true when authentication succeeded and navigation fired.
     */
    public func onPinInput(value: String): Bool {
        // iOS `processPin` guard: ignore input entirely while locked out.
        if (this.viewState.isLockedOut) {
            return false
        }
        match (this.viewState.pinError) {
            case Some(_) =>
                if (!value.isEmpty()) {
                    this.setState({ s => s.copyWith(pinError: Some(Option<LocalizableStringKey>.None)) })
                }
            case None => ()
        }
        if (Int64(value.toRuneArray().size) != this.viewState.quickPinSize) {
            return false
        }
        if (this.pinStore.isPinValid(value)) {
            this.pinThrottle.recordSuccess()
            this.stopLockoutTick()
            this.setState({ s => s.copyWith(pinError: Some(Option<LocalizableStringKey>.None)) })
            this.authenticationSuccess()
            return true
        }
        // Wrong PIN: record the failure. When it crosses the threshold the
        // throttle returns an active lockout window; otherwise show invalid-PIN.
        let lockout = this.pinThrottle.recordFailure()
        if (lockout.isActive()) {
            this.startLockoutTick(lockout.remaining())
        } else {
            this.setState({ s =>
                s.copyWith(pinError: Some(Some(LocalizableStringKey.invalidQuickPin)))
            })
        }
        return false
    }

    /**
     * Biometry trigger (iOS `onBiometry` → interactor.authenticate()). A
     * success resets the PIN throttle and navigates; a failure raises the
     * alert, except for the plain `BiometricError` which iOS swallows because
     * the platform sheet has already told the user. Never a fake success.
     */
    public func onBiometry(): Bool {
        if (!this.authenticateWithBiometry()) {
            return false
        }
        this.completeAuthenticated()
        return true
    }

    /**
     * The blocking half of `onBiometry`: runs the platform evaluation and
     * updates state, but performs no navigation, so a caller on a worker
     * thread can marshal the success back to the UI thread itself.
     */
    public func authenticateWithBiometry(): Bool {
        match (this.biometryController.requestBiometricUnlock()) {
            case UnlockSuccess =>
                this.pinThrottle.recordSuccess()
                this.stopLockoutTick()
                this.setState({ s =>
                    s.copyWith(
                        pinError: Some(Option<LocalizableStringKey>.None),
                        biometryError: Some(Option<String>.None)
                    )
                })
                return true
            case UnlockFailure(err) =>
                match (err) {
                    case BiometricError => ()
                    case _ =>
                        this.setState({ s => s.copyWith(biometryError: Some(Some(err.message()))) })
                }
                return false
        }
    }

    /** Navigation half of a successful authentication; must run on the UI thread. */
    public func completeAuthenticated(): Unit {
        this.authenticationSuccess()
    }

    /** Dismisses the biometry alert (iOS `.alert(item: $viewModel.biometryError)`). */
    public func dismissBiometryError(): Unit {
        this.setState({ s => s.copyWith(biometryError: Some(Option<String>.None)) })
    }

    /** Mirrors iOS `onSettings()`: the alert's primary action. */
    public func onSettings(): Unit {
        this.biometryController.openSettings({ => })
    }

    /** Dispatch the config's success navigation (iOS `authenticationSuccess`). */
    private func authenticationSuccess(): Unit {
        this.dispatch(this.viewState.config.navigationSuccessType)
    }

    // ── PIN lockout tick (iOS startLockoutTick/stopLockoutTick) ───────────────

    /** Smallest integer ≥ remaining seconds (iOS `Int(ceil(remaining))`). */
    private func ceilSecs(remaining: Float64): Int64 {
        let base = Int64(remaining)
        if (remaining > Float64(base)) {
            return base + 1
        }
        return base
    }

    private func pad2(n: Int64): String {
        if (n < 10) {
            return "0${n}"
        }
        return "${n}"
    }

    /** iOS `buildLockoutMessage`: quick_pin_locked_out("<max>", "MM:SS"). */
    private func buildLockoutMessage(remainingSeconds: Int64): LocalizableStringKey {
        let safe = if (remainingSeconds < 0) {
            0
        } else {
            remainingSeconds
        }
        let mmss = "${this.pad2(safe / 60)}:${this.pad2(safe % 60)}"
        return LocalizableStringKey.quickPinLockedOut(["${this.maxAttempts}", mmss])
    }

    private func startLockoutTick(initialRemaining: Float64): Unit {
        let secs = this.ceilSecs(initialRemaining)
        if (secs <= 0) {
            this.stopLockoutTick()
            return
        }
        this.tickGen += 1
        let myGen = this.tickGen
        this.setState({ s =>
            s.copyWith(
                isLockedOut: Some(true),
                lockoutMessage: Some(Some(this.buildLockoutMessage(secs))),
                pinError: Some(Option<LocalizableStringKey>.None)
            )
        })
        spawn {
            while (true) {
                sleep(Duration.second)
                if (myGen != this.tickGen) {
                    return
                }
                let state = this.pinThrottle.getState()
                if (state.isActive()) {
                    let r = this.ceilSecs(state.remaining())
                    // setState is marshalled to the UI thread by the view's
                    // onStateChange listener (spawn(UIThread) there), so the
                    // background tick can update state directly.
                    if (myGen == this.tickGen) {
                        this.setState({ s =>
                            s.copyWith(lockoutMessage: Some(Some(this.buildLockoutMessage(r))))
                        })
                    }
                } else {
                    if (myGen == this.tickGen) {
                        this.stopLockoutTick()
                    }
                    return
                }
            }
        }
    }

    private func stopLockoutTick(): Unit {
        // Bump the generation so any running tick loop exits on its next wake.
        this.tickGen += 1
        this.setState({ s =>
            s.copyWith(
                isLockedOut: Some(false),
                lockoutMessage: Some(Option<LocalizableStringKey>.None)
            )
        })
    }

    /**
     * Back affordance (iOS `onPop`): dispatch navigationBackType when the
     * config provides one; otherwise plain pop.
     */
    public func onBack(): Unit {
        match (this.viewState.config.navigationBackType) {
            case Some(backType) => this.dispatch(backType)
            case None => this.router.pop()
        }
    }

    private func dispatch(navigation: ThreeWayNavigationType): Unit {
        dispatchThreeWayNavigation(this.router, navigation)
    }
}
