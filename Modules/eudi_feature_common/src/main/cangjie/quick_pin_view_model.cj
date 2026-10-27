/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/QuickPin/QuickPinViewModel.swift + the storage calls of
 * Interactor/QuickPinInteractor.swift) to Cangjie.
 *
 * Reducer state machine on eudi_logic_ui.BaseViewModel:
 *  - Set flows  (setWithActivation / setWithoutActivation):
 *      FirstInput → RetryInput(first) → Succeeded (two-input comparison)
 *  - Update flow: Validate (check the current PIN through PinStore) →
 *      FirstInput → RetryInput(first) → Succeeded
 *
 * PIN format validation goes through the delivered eudi_logic_business
 * FormValidator (ValidateNotEmpty + full-string ValidateRegex "[0-9]{6}"),
 * never ad-hoc string checks. PIN persistence/verification goes through the
 * PinStore seam (FilePinStore default: salted PBKDF2 hash, constant-time
 * compare) — there is no plain-text PIN comparison anywhere in this flow
 * (the only String equality is between the two fresh user inputs of the
 * confirmation step, mirroring iOS `confirmRetry`).
 *
 * The iOS 250 ms Combine debounce is dropped: input arrives via the
 * PinTextFieldView onPinChange callback which already fires once per
 * keystroke; processing triggers only at exactly quickPinSize digits.
 */
package eudi_feature_common

import std.collection.ArrayList
import std.time.*
import eudi_logic_ui.*
import eudi_logic_business.{Rule, FormInput, ValidatableForm, FormValidator, FormValidatorImpl}
import eudi_logic_authentication.{PinThrottleController, PinLockoutState, AuthenticationConfigImpl}
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** Mirrors iOS `QuickPinStep` plus an explicit terminal success state. */
public enum QuickPinStep {
    | Validate
    | FirstInput
    | RetryInput(String)
    | Succeeded
}

/** Mirrors iOS `QuickPinState` (ViewState of the reducer). */
public class QuickPinViewState <: ViewState {
    public let config: QuickPinUiConfig
    public let navigationTitle: LocalizableStringKey
    public let title: LocalizableStringKey
    public let caption: LocalizableStringKey
    public let pinTextFieldTitle: LocalizableStringKey
    public let successTitle: LocalizableStringKey
    public let successCaption: LocalizableStringKey
    public let successButton: LocalizableStringKey
    public let successNavigationType: DeepLinkNavigationType
    public let isCancellable: Bool
    public let pinError: ?LocalizableStringKey
    public let step: QuickPinStep
    public let quickPinSize: Int64
    // iOS QuickPinState.isLockedOut / lockoutMessage (PIN throttle UI).
    public let isLockedOut: Bool
    public let lockoutMessage: ?LocalizableStringKey

    public init(
        config!: QuickPinUiConfig,
        navigationTitle!: LocalizableStringKey,
        title!: LocalizableStringKey,
        caption!: LocalizableStringKey,
        pinTextFieldTitle!: LocalizableStringKey,
        successTitle!: LocalizableStringKey,
        successCaption!: LocalizableStringKey,
        successButton!: LocalizableStringKey,
        successNavigationType!: DeepLinkNavigationType,
        isCancellable!: Bool,
        pinError!: ?LocalizableStringKey,
        step!: QuickPinStep,
        quickPinSize!: Int64 = 6,
        isLockedOut!: Bool = false,
        lockoutMessage!: ?LocalizableStringKey = Option<LocalizableStringKey>.None
    ) {
        this.config = config
        this.navigationTitle = navigationTitle
        this.title = title
        this.caption = caption
        this.pinTextFieldTitle = pinTextFieldTitle
        this.successTitle = successTitle
        this.successCaption = successCaption
        this.successButton = successButton
        this.successNavigationType = successNavigationType
        this.isCancellable = isCancellable
        this.pinError = pinError
        this.step = step
        this.quickPinSize = quickPinSize
        this.isLockedOut = isLockedOut
        this.lockoutMessage = lockoutMessage
    }

    /** Swift `@Copyable` replacement: rebuild with selective overrides. */
    public func copyWith(
        navigationTitle!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        caption!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        pinTextFieldTitle!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        pinError!: ??LocalizableStringKey = Option<?LocalizableStringKey>.None,
        step!: ?QuickPinStep = Option<QuickPinStep>.None,
        isLockedOut!: ?Bool = Option<Bool>.None,
        lockoutMessage!: ??LocalizableStringKey = Option<?LocalizableStringKey>.None
    ): QuickPinViewState {
        QuickPinViewState(
            config: this.config,
            navigationTitle: navigationTitle ?? this.navigationTitle,
            title: this.title,
            caption: caption ?? this.caption,
            pinTextFieldTitle: pinTextFieldTitle ?? this.pinTextFieldTitle,
            successTitle: this.successTitle,
            successCaption: this.successCaption,
            successButton: this.successButton,
            successNavigationType: this.successNavigationType,
            isCancellable: this.isCancellable,
            pinError: pinError ?? this.pinError,
            step: step ?? this.step,
            quickPinSize: this.quickPinSize,
            isLockedOut: isLockedOut ?? this.isLockedOut,
            lockoutMessage: lockoutMessage ?? this.lockoutMessage
        )
    }

    public func isSucceeded(): Bool {
        match (this.step) {
            case Succeeded => true
            case _ => false
        }
    }

    public func isRetryStep(): Bool {
        match (this.step) {
            case RetryInput(_) => true
            case _ => false
        }
    }
}

/**
 * Mirrors iOS `QuickPinViewModel`. The success screen hand-off mirrors iOS
 * `onSuccess()`: a SuccessUIConfig is stored in NavArgs under the
 * generic_success route key and the router pushes that route. `onCompleted`
 * additionally fires for embedding hosts that wire the screen directly.
 */
public class QuickPinViewModel <: BaseViewModel<QuickPinViewState> {
    private let pinStore: PinStore
    private let validator: FormValidator
    private let pinThrottle: PinThrottleController
    private let maxAttempts: Int64
    private var tickGen: Int64 = 0

    public init(
        router!: RouterHost,
        config!: QuickPinUiConfig,
        pinStore!: PinStore = createPinStore(),
        validator!: FormValidator = FormValidatorImpl(),
        pinThrottle!: PinThrottleController = createPinThrottleController()
    ) {
        super(router, QuickPinViewModel.initialState(config))
        this.pinStore = pinStore
        this.validator = validator
        this.pinThrottle = pinThrottle
        this.maxAttempts = AuthenticationConfigImpl().maxFailedPinAttempts
    }

    /**
     * Restore an in-progress lockout when the screen appears (iOS
     * `getPinLockoutState()` on init). Only the update flow's "verify current
     * PIN" step is throttled, so this is a no-op for the set flow.
     */
    public func refreshLockoutOnAppear(): Unit {
        let lockout = this.pinThrottle.getState()
        if (lockout.isActive()) {
            this.startLockoutTick(lockout.remaining())
        }
    }

    /** Mirrors the iOS init switches over `config.flow`. */
    private static func initialState(config: QuickPinUiConfig): QuickPinViewState {
        let successNavigation: DeepLinkNavigationType = match (config.flow) {
            case SetWithActivation => DeepLinkNavigationType.DeepLinkPush(AppRoutes.issuanceAddDocument)
            case SetWithoutActivation => DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard)
            case Update => DeepLinkNavigationType.DeepLinkPop(AppRoutes.dashboard, false)
        }
        let successButton: LocalizableStringKey = match (config.flow) {
            case SetWithActivation => LocalizableStringKey.quickPinSetSuccessButton
            case SetWithoutActivation => LocalizableStringKey.quickPinSetNoActivationSuccessButton
            case Update => LocalizableStringKey.quickPinUpdateSuccessButton
        }
        let successCaption: LocalizableStringKey = match (config.flow) {
            case SetWithActivation => LocalizableStringKey.quickPinSetSuccess
            case SetWithoutActivation => LocalizableStringKey.quickPinSetNoActivationSuccess
            case Update => LocalizableStringKey.quickPinUpdateSuccess
        }
        let isSet = config.isSetFlow
        return QuickPinViewState(
            config: config,
            navigationTitle: if (isSet) {
                LocalizableStringKey.quickPinNavigationEnterPin
            } else {
                LocalizableStringKey.quickPinUpdateTitle
            },
            title: if (isSet) {
                LocalizableStringKey.quickPinSetTitle
            } else {
                LocalizableStringKey.quickPinUpdateTitle
            },
            caption: LocalizableStringKey.quickPinSetCaptionOne,
            pinTextFieldTitle: if (isSet) {
                LocalizableStringKey.quickPinEnterPin
            } else {
                LocalizableStringKey.quickPinUpdateCaptionOne
            },
            successTitle: if (isSet) {
                LocalizableStringKey.walletIsSecured
            } else {
                LocalizableStringKey.successTitlePunctuated
            },
            successCaption: successCaption,
            successButton: successButton,
            successNavigationType: successNavigation,
            isCancellable: config.isUpdateFlow,
            pinError: Option<LocalizableStringKey>.None,
            step: if (isSet) {
                QuickPinStep.FirstInput
            } else {
                QuickPinStep.Validate
            },
            quickPinSize: 6
        )
    }

    /** Set flows hide the caption on update (iOS `contentCaption`). */
    public func contentCaption(): ?LocalizableStringKey {
        if (this.viewState.config.isUpdateFlow) {
            return Option<LocalizableStringKey>.None
        }
        return this.viewState.caption
    }

    /**
     * PIN format gate through eudi_logic_business FormValidator:
     * non-empty + full-string `[0-9]{quickPinSize}` (R-100: FormValidator's
     * ValidateRegex is already full-match, not substring search).
     */
    public func isPinFormatValid(pin: String): Bool {
        let form = ValidatableForm(
            [
                FormInput(
                    [
                        Rule.ValidateNotEmpty("Invalid pin"),
                        Rule.ValidateRegex("[0-9]{${this.viewState.quickPinSize}}", "Invalid pin")
                    ],
                    pin
                )
            ]
        )
        return this.validator.validateForm(form).isValid
    }

    /**
     * Per-keystroke input hook (PinTextFieldView.onPinChange). Mirrors the
     * iOS `uiPinInputField.didSet`: any typing clears the previous error;
     * a full-length value triggers the step machine.
     */
    public func onPinInput(value: String): Unit {
        if (this.viewState.isSucceeded()) {
            return
        }
        // iOS `processPin` guard: ignore input entirely while locked out.
        if (this.viewState.isLockedOut) {
            return
        }
        match (this.viewState.pinError) {
            case Some(_) =>
                if (!value.isEmpty()) {
                    this.setState({ s => s.copyWith(pinError: Some(Option<LocalizableStringKey>.None)) })
                }
            case None => ()
        }
        if (Int64(value.toRuneArray().size) == this.viewState.quickPinSize) {
            this.processPin(value)
        }
    }

    /** Mirrors iOS `processPin` (switch over the current step). */
    private func processPin(value: String): Unit {
        if (!this.isPinFormatValid(value)) {
            this.setState({ s =>
                s.copyWith(pinError: Some(Some(LocalizableStringKey.invalidQuickPin)))
            })
            return
        }
        match (this.viewState.step) {
            case Validate => this.onValidateCurrentPin(value)
            case FirstInput => this.advanceToRetryInput(value)
            case RetryInput(previousPin) => this.confirmRetry(previousPin, value)
            case Succeeded => ()
        }
    }

    /** Update flow: verify the current PIN through PinStore (iOS `onValidate`). */
    private func onValidateCurrentPin(value: String): Unit {
        if (this.pinStore.isPinValid(value)) {
            this.pinThrottle.recordSuccess()
            this.stopLockoutTick()
            this.setState({ s =>
                s.copyWith(
                    pinTextFieldTitle: Some(LocalizableStringKey.quickPinUpdateCaptionTwo),
                    pinError: Some(Option<LocalizableStringKey>.None),
                    step: Some(QuickPinStep.FirstInput)
                )
            })
        } else {
            // Wrong current PIN: record the failure; cross the threshold → lock.
            let lockout = this.pinThrottle.recordFailure()
            if (lockout.isActive()) {
                this.startLockoutTick(lockout.remaining())
            } else {
                this.setState({ s =>
                    s.copyWith(pinError: Some(Some(LocalizableStringKey.invalidQuickPin)))
                })
            }
        }
    }

    // ── PIN lockout tick (iOS startLockoutTick/stopLockoutTick) ───────────────

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
                pinError: Some(Option<LocalizableStringKey>.None),
                isLockedOut: Some(true),
                lockoutMessage: Some(Some(this.buildLockoutMessage(secs)))
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
        this.tickGen += 1
        this.setState({ s =>
            s.copyWith(
                isLockedOut: Some(false),
                lockoutMessage: Some(Option<LocalizableStringKey>.None)
            )
        })
    }

    /** First input accepted → remember it and ask for confirmation. */
    private func advanceToRetryInput(value: String): Unit {
        let fieldTitle = if (this.viewState.config.isUpdateFlow) {
            LocalizableStringKey.quickPinUpdateCaptionThree
        } else {
            LocalizableStringKey.quickPinSetCaptionTwo
        }
        this.setState({ s =>
            s.copyWith(
                navigationTitle: Some(LocalizableStringKey.quickPinConfirmPin),
                pinTextFieldTitle: Some(fieldTitle),
                pinError: Some(Option<LocalizableStringKey>.None),
                step: Some(QuickPinStep.RetryInput(value))
            )
        })
    }

    /**
     * Confirmation step: both fresh inputs must match (iOS `confirmRetry`),
     * then the PIN is persisted through PinStore (hashed — never stored or
     * compared as plain text against stored state).
     */
    private func confirmRetry(previousPin: String, value: String): Unit {
        if (previousPin != value) {
            this.setState({ s =>
                s.copyWith(pinError: Some(Some(LocalizableStringKey.quickPinDoNotMatch)))
            })
            return
        }
        this.pinStore.setPin(value)
        this.setState({ s =>
            s.copyWith(
                pinError: Some(Option<LocalizableStringKey>.None),
                step: Some(QuickPinStep.Succeeded)
            )
        })
    }

    /**
     * Mirrors iOS `onSuccess()` routing: build the SuccessUIConfig for the
     * flow and push generic_success with the config as NavArgs payload.
     * Returns the config so embedding hosts can also render it inline.
     */
    public func successConfig(): SuccessUIConfig {
        SuccessUIConfig(
            title: SuccessTitle(value: this.viewState.successTitle),
            subtitle: this.viewState.successCaption,
            buttons: [
                SuccessButton(
                    title: this.viewState.successButton,
                    style: SuccessButtonStyle.StylePrimary,
                    navigationType: this.viewState.successNavigationType
                )
            ],
            visualKind: if (this.viewState.config.isUpdateFlow) {
                // Update flow → green checkmark (iOS checkmarkCircle).
                SuccessVisualKind.DefaultIcon
            } else {
                // Set flow → success-secured-wallet illustration (iOS).
                SuccessVisualKind.CustomIcon(
                    ThemeManager.shared.image.successSecuredWallet,
                    uiColor(ThemeManager.shared.color.success)
                )
            }
        )
    }

    /** Push the generic success screen (iOS `router.push(.genericSuccess)`). */
    public func routeToSuccess(): Unit {
        NavArgs.shared.set(AppRoutes.genericSuccess, RouteConfigArgs(this.successConfig()))
        this.router.push(AppRoutes.genericSuccess)
    }

    /**
     * Inline success-button action: dispatch the flow's success navigation
     * (same end state as tapping the button of the pushed iOS success
     * screen — dashboard pop on update, dashboard/issuance push on set).
     */
    public func onSuccessAction(): Unit {
        dispatchDeepLinkNavigation(this.router, this.viewState.successNavigationType)
    }

    /**
     * Leading-back affordance (iOS `showsLeadingBackButton`): update flow is
     * cancellable; set flows expose back only while confirming.
     */
    public func showsLeadingBackButton(): Bool {
        if (this.viewState.isSucceeded()) {
            return false
        }
        if (this.viewState.isCancellable) {
            return true
        }
        return this.viewState.config.isSetFlow && this.viewState.isRetryStep()
    }

    /**
     * Set-flow back from the confirmation step (iOS `onLeadingBack` second
     * branch): return to FirstInput, dropping the remembered first PIN.
     * Returns true when the step was rewound (caller resets the field).
     */
    public func rewindToFirstInput(): Bool {
        if (!this.viewState.config.isSetFlow || !this.viewState.isRetryStep()) {
            return false
        }
        this.setState({ s =>
            s.copyWith(
                navigationTitle: Some(LocalizableStringKey.quickPinNavigationEnterPin),
                pinTextFieldTitle: Some(LocalizableStringKey.quickPinEnterPin),
                pinError: Some(Option<LocalizableStringKey>.None),
                step: Some(QuickPinStep.FirstInput)
            )
        })
        return true
    }

    /** Update-flow cancellation confirmed: pop back (iOS `onPop`). */
    public func onPop(): Unit {
        this.router.pop()
    }
}
