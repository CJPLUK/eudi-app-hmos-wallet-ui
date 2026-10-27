/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Biometry/BiometryView.swift) to Cangjie ArkUI.
 *
 * Shared "authenticate with biometrics or PIN" screen. The biometry trigger
 * follows iOS exactly: it renders only when the persisted preference is on
 * *and* the platform reports a face/fingerprint asset, otherwise the page
 * degrades to the PIN path with the config's quickPinOnlyCaption. Failures
 * other than the platform's own "not recognized" open the iOS alert with
 * "Open settings" / "Cancel". No fake biometric success exists anywhere.
 *
 * Plain @Component (no @Entry / NavDestination — composition root owns the
 * navigation shell). PIN entry reuses eudi_logic_ui PinTextFieldView; the
 * field remounts via the generation toggle after every full-length attempt
 * (same paradigm as QuickPinView).
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** Default config used when the host injects nothing (pre-auth login shape). */
func defaultBiometricUiConfig(): BiometricUiConfig {
    BiometricUiConfig(
        navigationTitle: LocalizableStringKey.biometryConfirmRequest,
        caption: LocalizableStringKey.loginCaption,
        quickPinOnlyCaption: LocalizableStringKey.loginCaptionQuickPinOnly,
        navigationSuccessType: ThreeWayNavigationType.ThreeWayPop,
        navigationBackType: Some(ThreeWayNavigationType.ThreeWayPop),
        isPreAuthorization: true,
        shouldInitializeBiometricOnCreate: true
    )
}

/**
 * Biometry / PIN fallback screen (fc_common_biometry exposed symbol).
 *
 * Injection points (S-017):
 *  - `config`: BiometricUiConfig (titles, captions, navigation behaviour).
 *  - `viewModel`: optional pre-built BiometryViewModel (composition root
 *    wires the real RouterHost + device biometry); defaults to the
 *    emulator-degraded self-contained model.
 *  - `onAuthenticated`: fires after a successful PIN (or real biometric)
 *    authentication, alongside the config navigation dispatch.
 */
@Component
public class BiometryView {
    public var config: BiometricUiConfig = defaultBiometricUiConfig()
    public var viewModel: ?BiometryViewModel = Option<BiometryViewModel>.None
    public var onAuthenticated: () -> Unit = { => }

    private var vm: ?BiometryViewModel = Option<BiometryViewModel>.None

    @State
    var errorText: String = ""
    @State
    var biometryEnabled: Bool = false
    @State
    var fieldGeneration: Int64 = 0
    @State
    var lockedOut: Bool = false
    @State
    var lockoutText: String = ""
    /** iOS `biometryImage` — empty when the platform reports no biometry. */
    @State
    var biometryImageToken: String = ""
    /** iOS `biometryError` alert body; empty keeps the alert closed. */
    @State
    var biometryErrorText: String = ""
    /** iOS `isCancellable` (config.navigationBackType != nil). */
    @State
    var isCancellable: Bool = false
    /** iOS `biometryTitleCaption()` — empty when suppressed. */
    @State
    var titleCaptionText: String = ""
    /** iOS `biometryPinTitle()`. */
    @State
    var pinTitleText: String = ""

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? BiometryViewModel(router: InMemoryRouterHost(), config: this.config)
        this.vm = Some(model)
        // Marshal every state update onto the UI thread: the lockout tick fires
        // setState from a background thread (S-001), and @State writes must be
        // on the UI thread.
        model.onStateChange({ state => spawn(UIThread) { => this.syncFromState(state) } })
        // iOS `.task { await viewModel.initialize() }` — always runs; the
        // shouldInitializeBiometricOnCreate gate lives inside initialize().
        model.initialize()
        this.syncFromState(model.viewState)
        // iOS fires the on-appear prompt after AUTO_VERIFY_ON_APPEAR_DELAY so
        // the page is drawn behind the platform sheet.
        if (model.shouldAutoPromptBiometry()) {
            model.markAutoBiometryInitiated()
            spawn {
                sleep(Duration.millisecond * AUTO_VERIFY_ON_APPEAR_DELAY_MS)
                this.runBiometryOffUiThread(model)
            }
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func syncFromState(state: BiometryViewState): Unit {
        this.titleCaptionText = match (state.titleCaptionKey()) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
        this.pinTitleText = LocalizableManager.get(state.pinFieldTitleKey())
        this.errorText = match (state.pinError) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
        this.biometryEnabled = state.biometryEnabled
        this.biometryImageToken = state.biometryTriggerToken() ?? ""
        this.biometryErrorText = state.biometryError ?? ""
        this.isCancellable = state.isCancellable
        this.lockedOut = state.isLockedOut
        this.lockoutText = match (state.lockoutMessage) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
    }

    private func handlePinChange(value: String): Unit {
        match (this.vm) {
            case Some(model) =>
                if (model.onPinInput(value)) {
                    this.onAuthenticated()
                }
            case None => ()
        }
    }

    private func handlePinComplete(completed: String): Unit {
        if (completed.isEmpty()) {
            return
        }
        // Process the terminal value only from PinTextFieldView.onPinComplete.
        // Calling into the view model from onChange while the native TextInput
        // is still applying the sixth character can make a fast IME sequence
        // visibly stop at the fifth box.
        match (this.vm) {
            case Some(model) =>
                if (model.onPinInput(completed)) {
                    this.onAuthenticated()
                } else {
                    // A rejected PIN starts a new attempt only after the
                    // completion event has been fully handled.
                    this.fieldGeneration += 1
                }
            case None => ()
        }
    }

    /**
     * The platform evaluation blocks its caller until ArkTS answers, and ArkTS
     * drains that command queue on the UI event loop — running it on the UI
     * thread would deadlock until the bridge timed out. Evaluate on a worker,
     * then marshal navigation back to the UI thread.
     */
    private func runBiometryOffUiThread(model: BiometryViewModel): Unit {
        if (model.authenticateWithBiometry()) {
            spawn(UIThread) {
                =>
                model.completeAuthenticated()
                this.onAuthenticated()
            }
        }
    }

    private func handleBiometry(): Unit {
        match (this.vm) {
            case Some(model) => spawn { this.runBiometryOffUiThread(model) }
            case None => ()
        }
    }

    private func handleBack(): Unit {
        match (this.vm) {
            case Some(model) => model.onBack()
            case None => ()
        }
    }

    private func navigationTitleText(): String {
        LocalizableManager.get(this.config.navigationTitle)
    }

    /** iOS `biometryPinTitle()` resolved by the view model (caption switch). */
    private func pinFieldTitle(): LocalizableStringKey {
        LocalizableStringKey.custom(this.pinTitleText)
    }

    /** iOS `biometryTitleCaption()` — None keeps the header caption hidden. */
    private func titleCaptionKeyOrNone(): ?LocalizableStringKey {
        if (this.titleCaptionText.isEmpty()) {
            return Option<LocalizableStringKey>.None
        }
        return Some(LocalizableStringKey.custom(this.titleCaptionText))
    }

    /** Dismiss + open the system biometrics settings (iOS alert primary action). */
    private func handleOpenSettings(): Unit {
        match (this.vm) {
            case Some(model) =>
                model.dismissBiometryError()
                model.onSettings()
            case None => ()
        }
    }

    private func handleDismissBiometryError(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissBiometryError()
            case None => ()
        }
    }

    private func hasError(): Bool {
        !this.errorText.isEmpty()
    }

    public func build() {
        Stack(alignContent: Alignment.Center) {
            Column(space: SPACING_LARGE_MEDIUM) {
                // Navigation bar (iOS toolbar): the back chevron is gated on
                // isCancellable — config.navigationBackType != nil — not on the
                // bar itself, so the login gate keeps its title without a way
                // to back out of it.
                if (this.config.displayNavigationBar) {
                    Row(space: SPACING_SMALL) {
                        if (this.isCancellable) {
                            Text("\u{2039}")
                                .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .width(44.0)
                                .height(44.0)
                                .textAlign(TextAlign.Center)
                                .onClick({ _ => this.handleBack() })
                        }
                        Text(this.navigationTitleText())
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    }
                    .width(100.percent)
                    .height(44.0)
                    .justifyContent(FlexAlign.Start)
                }

                if (this.config.displayLogo) {
                    Column(space: SPACING_EXTRA_SMALL) {
                        Text("EU Digital Identity")
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        Text("Wallet")
                            .fontSize(uiFontSize(ThemeManager.shared.font.titleMedium))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    }
                    .width(100.percent)
                    .alignItems(HorizontalAlign.Start)
                }

                // iOS ContentTitleView(title: config.title, caption:
                // biometryTitleCaption()) — the caption is suppressed for
                // pre-authorization shapes, where it titles the PIN field.
                ContentTitleView(
                    title: this.config.title,
                    caption: this.titleCaptionKeyOrNone()
                )

                // PIN fallback path (always present). iOS keeps the field
                // unfocused while biometrics are on and disables it during a
                // lockout window.
                if (this.fieldGeneration % 2 == 0) {
                    PinTextFieldView(
                        pinTitle: this.pinFieldTitle(),
                        maxDigits: 6,
                        hasError: this.hasError(),
                        isDisabled: this.lockedOut,
                        refocusOnAppear: !this.biometryEnabled && !this.lockedOut,
                        onPinChange: { value => this.handlePinChange(value) },
                        onPinComplete: { value => this.handlePinComplete(value) }
                    )
                } else {
                    PinTextFieldView(
                        pinTitle: this.pinFieldTitle(),
                        maxDigits: 6,
                        hasError: this.hasError(),
                        isDisabled: this.lockedOut,
                        refocusOnAppear: !this.biometryEnabled && !this.lockedOut,
                        onPinChange: { value => this.handlePinChange(value) },
                        onPinComplete: { value => this.handlePinComplete(value) }
                    )
                }

                if (this.hasError()) {
                    Text(this.errorText)
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                        .fontColor(uiColor(ThemeManager.shared.color.red))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }

                // PIN lockout countdown (iOS lockoutMessage, red). Shown after too
                // many wrong attempts; input is ignored by the view model meanwhile.
                if (this.lockedOut && !this.lockoutText.isEmpty()) {
                    Text(this.lockoutText)
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                        .fontColor(uiColor(ThemeManager.shared.color.red))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }

                Blank()

                // Biometrics trigger — iOS renders the face-id / touch-id asset
                // itself, bottom-trailing, only when the preference is on and
                // the platform reports a type.
                if (!this.biometryImageToken.isEmpty()) {
                    Row {
                        Row {
                            AppIcon(
                                token: this.biometryImageToken,
                                size: 48.0,
                                color: uiColor(ThemeManager.shared.color.blue)
                            )
                        }
                        .width(64.0)
                        .height(64.0)
                        .justifyContent(FlexAlign.Center)
                        .onClick({ _ => this.handleBiometry() })
                    }
                    .width(100.percent)
                    .justifyContent(FlexAlign.End)
                }
            }
            .width(100.percent)
            .height(100.percent)
            .padding(ThemeManager.shared.dimension.padding)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .alignItems(HorizontalAlign.Start)

            // iOS `.alert(item: $viewModel.biometryError)`.
            if (!this.biometryErrorText.isEmpty()) {
                AlertView(
                    title: LocalizableStringKey.genericErrorTitle,
                    message: LocalizableStringKey.custom(this.biometryErrorText),
                    actions: [
                        AlertAction(
                            title: LocalizableStringKey.biometryOpenSettings,
                            callback: { => this.handleOpenSettings() }
                        ),
                        AlertAction(
                            title: LocalizableStringKey.cancelButton,
                            callback: { => this.handleDismissBiometryError() }
                        )
                    ],
                    onDismiss: { => this.handleDismissBiometryError() }
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
    }
}
