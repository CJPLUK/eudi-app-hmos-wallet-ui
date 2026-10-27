/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/QuickPin/QuickPinView.swift) to Cangjie ArkUI.
 *
 * Plain @Component (no @Entry / no NavDestination chrome — the navigation
 * shell belongs to the composition root, see target_architecture
 * navigation_shell). State lives in QuickPinViewModel; this page registers
 * the single-slot onStateChange listener and mirrors the fresh state into
 * its own @State fields (eudi_logic_ui BaseViewModel paradigm). PIN entry
 * reuses the delivered eudi_logic_ui PinTextFieldView (S-018 transparent
 * overlay already encapsulated there).
 *
 * Field reset paradigm: PinTextFieldView keeps its typed value in an
 * internal @State, so after every full-length submission the page bumps
 * `fieldGeneration` and renders the field from the alternate if/else branch
 * — ArkUI tears the old instance down and mounts a fresh (empty) one. This
 * reproduces the iOS `uiPinInputField = ""` reset of every processPin
 * branch.
 *
 * The update-flow cancellation dialog reuses eudi_logic_ui AlertView
 * (baked-alpha scrim; the card stays opaque).
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * PIN set / update screen (fc_common_quickpin exposed symbol).
 *
 * Injection points (S-017 — instantiate with real values):
 *  - `config`: QuickPinUiConfig deciding Set / Update behaviour.
 *  - `viewModel`: optional pre-built QuickPinViewModel (composition root
 *    passes one wired to the real RouterHost); when absent the page builds
 *    a self-contained one over InMemoryRouterHost + FilePinStore.
 *  - `onCompleted` / `onCancelled`: flow-completion callbacks for hosts.
 */
@Component
public class QuickPinView {
    public var config: QuickPinUiConfig = QuickPinUiConfig(flow: QuickPinFlow.SetWithoutActivation)
    public var viewModel: ?QuickPinViewModel = Option<QuickPinViewModel>.None
    public var onCompleted: () -> Unit = { => }
    public var onCancelled: () -> Unit = { => }

    private var vm: ?QuickPinViewModel = Option<QuickPinViewModel>.None

    @State
    var navigationTitleText: String = ""
    @State
    var titleText: String = ""
    @State
    var captionText: String = ""
    @State
    var fieldTitleText: String = ""
    @State
    var errorText: String = ""
    @State
    var succeeded: Bool = false
    @State
    var showBack: Bool = false
    @State
    var showCancelConfirm: Bool = false
    @State
    var fieldGeneration: Int64 = 0
    @State
    var lockedOut: Bool = false
    @State
    var lockoutText: String = ""
    @State
    var successTitleText: String = ""
    @State
    var successCaptionText: String = ""
    @State
    var successButtonText: String = ""

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? QuickPinViewModel(router: InMemoryRouterHost(), config: this.config)
        this.vm = Some(model)
        // Marshal state updates to the UI thread (the lockout tick fires
        // setState from a background thread, S-001).
        model.onStateChange({ state => spawn(UIThread) { => this.syncFromState(state) } })
        model.refreshLockoutOnAppear()
        this.syncFromState(model.viewState)
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    /** Mirrors the reducer state into page @State (UI-thread callbacks only). */
    private func syncFromState(state: QuickPinViewState): Unit {
        this.navigationTitleText = LocalizableManager.get(state.navigationTitle)
        this.titleText = LocalizableManager.get(state.title)
        this.captionText = if (state.config.isUpdateFlow) {
            ""
        } else {
            LocalizableManager.get(state.caption)
        }
        this.fieldTitleText = LocalizableManager.get(state.pinTextFieldTitle)
        this.errorText = match (state.pinError) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
        this.succeeded = state.isSucceeded()
        this.lockedOut = state.isLockedOut
        this.lockoutText = match (state.lockoutMessage) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
        match (this.vm) {
            case Some(model) => this.showBack = model.showsLeadingBackButton()
            case None => this.showBack = false
        }
        this.successTitleText = LocalizableManager.get(state.successTitle)
        this.successCaptionText = LocalizableManager.get(state.successCaption)
        this.successButtonText = LocalizableManager.get(state.successButton)
    }

    private func handlePinChange(value: String): Unit {
        match (this.vm) {
            case Some(model) => model.onPinInput(value)
            case None => ()
        }
    }

    /**
     * Full-length input is deliberately processed here, rather than through
     * the TextInput onChange callback. The completion handler runs after the
     * native control has accepted its last character, so resetting the field
     * cannot race a fast IME sequence.
     */
    private func handlePinComplete(completed: String): Unit {
        if (completed.isEmpty()) {
            return
        }
        this.handlePinChange(completed)
        this.fieldGeneration += 1
    }

    /** Leading back: cancel dialog on update flow, step rewind on set flow. */
    private func handleBack(): Unit {
        match (this.vm) {
            case Some(model) =>
                if (model.viewState.isCancellable) {
                    this.showCancelConfirm = true
                } else if (model.rewindToFirstInput()) {
                    this.fieldGeneration += 1
                }
            case None => ()
        }
    }

    private func handleCancelDismiss(): Unit {
        this.showCancelConfirm = false
    }

    /** Confirmed cancellation: notify host, pop through the router (iOS onPop). */
    private func handleCancelConfirm(): Unit {
        this.showCancelConfirm = false
        this.onCancelled()
        match (this.vm) {
            case Some(model) => model.onPop()
            case None => ()
        }
    }

    /** Success button: notify host and dispatch the configured navigation. */
    private func handleSuccessButton(): Unit {
        this.onCompleted()
        match (this.vm) {
            case Some(model) => model.onSuccessAction()
            case None => ()
        }
    }

    private func hasError(): Bool {
        !this.errorText.isEmpty()
    }

    private func cancelActions(): Array<AlertAction> {
        [
            AlertAction(
                title: LocalizableStringKey.quickPinUpdateCancellationContinue,
                callback: { => this.handleCancelDismiss() }
            ),
            AlertAction(
                title: LocalizableStringKey.cancelButton,
                isDestructive: true,
                callback: { => this.handleCancelConfirm() }
            )
        ]
    }

    public func build() {
        Stack(alignContent: Alignment.Center) {
            Column {
                if (!this.succeeded) {
                    this.buildToolbar()
                }

                if (this.succeeded) {
                    this.buildSuccessBody()
                } else {
                    this.buildInputBody()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .padding(ThemeManager.shared.dimension.padding)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))

            if (this.showCancelConfirm) {
                AlertView(
                    title: LocalizableStringKey.quickPinUpdateCancellationTitle,
                    message: LocalizableStringKey.quickPinUpdateCancellationCaption,
                    actions: this.cancelActions(),
                    onDismiss: { => this.handleCancelDismiss() }
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
    }

    /**
     * iOS toolbar (ContentScreenView inline nav bar): circular back button
     * — same affordance as the other screens — plus the centered nav title.
     */
    @Builder
    func buildToolbar() {
        Row(space: SPACING_SMALL) {
            if (this.showBack) {
                Row {
                    Text("‹")
                        .fontSize(28.0)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
                .onClick({ _ => this.handleBack() })
            } else {
                Row {}
                    .width(40.0)
                    .height(40.0)
            }
            Text(this.navigationTitleText)
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Row {}
                .width(40.0)
                .height(40.0)
        }
        .width(100.percent)
        .padding(top: 0.0, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)
    }

    /** iOS passes titleWeight .bold over titleLarge — displayMedium is the same 28pt at Bold. */
    private func boldTitleFont(): TypographyStyle {
        ThemeManager.shared.font.displayMedium
    }

    private func isUpdateFlow(): Bool {
        match (this.vm) {
            case Some(model) => model.viewState.config.isUpdateFlow
            case None => false
        }
    }

    @Builder
    func buildInputBody() {
        Column(space: SPACING_SMALL) {
            // iOS ContentHeaderView: centered EU wallet logo above the title.
            ContentHeaderView(config: this.headerConfig())
            ContentTitleView(
                title: LocalizableStringKey.custom(this.titleText),
                caption: LocalizableStringKey.custom(this.captionText),
                titleFont: this.boldTitleFont()
            )
            // iOS: VSpacer.small on update flow, VSpacer.extraLarge on set flow.
            if (!this.isUpdateFlow()) {
                Row {}
                    .height(SPACING_LARGE)
            }
            // Remount-on-generation field reset (see file header).
            if (this.fieldGeneration % 2 == 0) {
                PinTextFieldView(
                    pinTitle: LocalizableStringKey.custom(this.fieldTitleText),
                    maxDigits: 6,
                    hasError: this.hasError(),
                    refocusOnAppear: true,
                    onPinChange: { value => this.handlePinChange(value) },
                    onPinComplete: { value => this.handlePinComplete(value) }
                )
            } else {
                PinTextFieldView(
                    pinTitle: LocalizableStringKey.custom(this.fieldTitleText),
                    maxDigits: 6,
                    hasError: this.hasError(),
                    refocusOnAppear: true,
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

            // PIN lockout countdown (iOS lockoutMessage, red) for the update flow.
            if (this.lockedOut && !this.lockoutText.isEmpty()) {
                Text(this.lockoutText)
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                    .fontColor(uiColor(ThemeManager.shared.color.red))
                    .textAlign(TextAlign.Start)
                    .width(100.percent)
            }
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }

    /** Set flows show the secured-wallet illustration (iOS); update shows ✓. */
    private func successIsSetFlow(): Bool {
        match (this.vm) {
            case Some(model) => model.viewState.config.isSetFlow
            case None => true
        }
    }

    private func headerConfig(): ContentHeaderConfig {
        ContentHeaderConfig(
            appIconAndTextData: AppIconAndTextData(
                appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                appTextSrc: ThemeManager.shared.image.euditext
            )
        )
    }

    @Builder
    func buildSuccessBody() {
        Column(space: SPACING_MEDIUM) {
            ContentHeaderView(config: this.headerConfig())
            // iOS: set flow → success-secured-wallet illustration + green title;
            // update flow → green ✓.
            if (this.successIsSetFlow()) {
                AppIcon(token: ThemeManager.shared.image.successSecuredWallet, size: 160.0)
            } else {
                Text("✓")
                    .fontSize(uiFontSize(ThemeManager.shared.font.displayLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.success))
                    .textAlign(TextAlign.Center)
            }
            Text(this.successTitleText)
                .fontSize(uiFontSize(ThemeManager.shared.font.titleMedium))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(if (this.successIsSetFlow()) {
                    ThemeManager.shared.color.success
                } else {
                    ThemeManager.shared.color.primaryLabel
                }))
                .textAlign(TextAlign.Center)
                .width(100.percent)
            Text(this.successCaptionText)
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                .textAlign(TextAlign.Center)
                .width(100.percent)
            WrapButtonView(
                title: LocalizableStringKey.custom(this.successButtonText),
                style: ButtonViewStyle.primary(),
                onAction: { => this.handleSuccessButton() }
            )
        }
        .width(100.percent)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
    }
}
