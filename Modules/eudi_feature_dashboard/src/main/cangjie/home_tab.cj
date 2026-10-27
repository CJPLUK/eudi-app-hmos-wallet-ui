/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (Tab/Home/HomeTabView.swift + HomeTabViewModel.swift) to Cangjie.
 *
 * HomeTabView renders, top-to-bottom:
 *   - a leading menu-icon bar (mirrors the iOS HomeTab toolbar leadingActions:
 *     a hamburger that pushes the side menu). iOS hangs this off the Dashboard
 *     navigation bar's leading slot only on the Home tab; this shell's Dashboard
 *     has no shared nav bar (it is a hideTitleBar NavDestination), so — matching
 *     the iOS intent — the menu icon lives at the top of the Home tab content,
 *     leading-aligned, styled like a toolbar icon, and only on this tab.
 *   - ContentHeaderView (EUDI logo + wordmark).
 *   - the "welcomeBack([username])" greeting, shown only when a username is
 *     resolved (mirrors `if let username` in iOS).
 *   - two HomeCardView action cards (Authenticate / Sign Document), each with a
 *     "Learn more" secondary button that opens an AlertView (title + message + OK).
 *
 * Dialogs (overlays, matching the AlertView pattern):
 *   - Authenticate: In person / Online choice + destructive Cancel + a message
 *     (homeScreenAuthenticateDescription), mirroring iOS confirmationDialog.
 *   - BLE disabled: shown when the in-person engagement is requested but BLE is
 *     not available. The ReachabilityController asks for the ACCESS_BLUETOOTH
 *     runtime permission (when missing) and reads the radio state, answering
 *     through a callback; the in-person option then either pushes the proximity
 *     flow (.available) or surfaces the same "Enable bluetooth?" modal (Enable →
 *     openBleSettings / Cancel) the iOS app shows for .disabled/.noPermission/
 *     .unavailable.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.*
import eudi_logic_business.BleAvailibity
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

/**
 * Home Tab view. Plain @Component (not @Entry / not NavDestination root);
 * mounted as TabContent content inside DashboardView. Receives the shared
 * DashboardViewModel so it can resolve the username, query BLE availability and
 * push routes (router is read from the VM). All optional for standalone preview.
 */
@Component
public class HomeTabView {
    public var viewModel: ?DashboardViewModel = Option<DashboardViewModel>.None
    public var router: ?RouterHost = Option<RouterHost>.None

    /** Mirrors iOS `isAuthenticateModalShowing`: In-Person / Online choice. */
    @State
    var showAuthChoice: Bool = false
    /** Mirrors iOS `isAuthenticateAlertShowing`: Authenticate "Learn more" alert. */
    @State
    var showAuthLearnMore: Bool = false
    /** Mirrors iOS `isSignDocumentAlertShowing`: Sign-document "Learn more" alert. */
    @State
    var showSignLearnMore: Bool = false
    /** Mirrors iOS `isBleModalShowing`. */
    @State
    var showBleModal: Bool = false
    /** Resolved username greeting suffix (", John" or "" — mirrors getUserName). */
    @State
    var usernameSuffix: String = ""

    protected override func aboutToAppear(): Unit {
        // Mirrors HomeTabViewModel.onCreate(): fetch the bearer name off the main
        // thread, then write the @State back on the UI thread (S-001).
        match (this.viewModel) {
            case Some(vm) =>
                spawn {
                    =>
                    let name = vm.loadUsername()
                    let suffix = if (name.isEmpty()) { "" } else { ", ${name}" }
                    spawn(UIThread) {
                        =>
                        this.usernameSuffix = suffix
                    }
                }
            case None => ()
        }
    }

    private func activeRouter(): ?RouterHost {
        match (this.viewModel) {
            case Some(vm) => Some(vm.router)
            case None => this.router
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

    private func hasUsername(): Bool {
        !this.usernameSuffix.isEmpty()
    }

    private func welcomeText(): String {
        LocalizableManager.get(LocalizableStringKey.welcomeBack([this.usernameSuffix]))
    }

    // ── Authenticate flow ─────────────────────────────────────────────────────

    private func onAuthenticate(): Unit {
        this.showAuthChoice = true
    }

    /** Mirrors iOS `onShare()`: in-person BLE proximity engagement (BLE-gated). */
    private func onInPerson(): Unit {
        this.showAuthChoice = false
        match (this.viewModel) {
            case Some(vm) =>
                // The seam answers asynchronously when the ACCESS_BLUETOOTH prompt
                // is shown first / the radio is read over the bridge; @State
                // writes and navigation go back to the UI thread.
                vm.bleAvailability({ availability =>
                    spawn(UIThread) { => this.onBleAvailability(availability) }
                })
            case None => this.onBleAvailability(BleAvailibity.unavailable)
        }
    }

    /** iOS `onShare()`: only disabled/unauthorized prompt; transient unknown is not mislabeled as Bluetooth off. */
    private func onBleAvailability(availability: BleAvailibity): Unit {
        if (availability == BleAvailibity.available) {
            match (this.activeRouter()) {
                case Some(r) => r.push(AppRoutes.proximityConnection)
                case None => ()
            }
        } else if (availability == BleAvailibity.disabled || availability == BleAvailibity.noPermission) {
            // Matches iOS HomeTabViewModel.onShare().
            this.showBleModal = true
        }
    }

    /** Mirrors iOS `onShowScanner()`: scan a QR for the online OpenID4VP flow. */
    private func onOnline(): Unit {
        this.showAuthChoice = false
        match (this.activeRouter()) {
            case Some(r) => r.push(AppRoutes.qrScanner)
            case None => ()
        }
    }

    private func authChoiceActions(): Array<AlertAction> {
        [
            AlertAction(title: LocalizableStringKey.inPerson, callback: { => this.onInPerson() }),
            AlertAction(title: LocalizableStringKey.online, callback: { => this.onOnline() }),
            // Destructive Cancel, mirroring iOS `Button(.cancelButton, role: .destructive)`.
            AlertAction(title: LocalizableStringKey.cancelButton, isDestructive: true, callback: { => this.showAuthChoice = false })
        ]
    }

    private func onSignDocument(): Unit {
        match (this.activeRouter()) {
            case Some(r) => r.push(AppRoutes.signDocument)
            case None => ()
        }
    }

    private func onBleSettings(): Unit {
        this.showBleModal = false
        match (this.viewModel) {
            case Some(vm) => vm.openBleSettings()
            case None => ()
        }
    }

    private func bleActions(): Array<AlertAction> {
        [
            AlertAction(title: LocalizableStringKey.bleDisabledModalButton, callback: { => this.onBleSettings() }),
            AlertAction(title: LocalizableStringKey.cancelButton, callback: { => this.showBleModal = false })
        ]
    }

    public func build() {
        Stack(alignContent: Alignment.Center) {
            Column {
                // The nav bar (menu button + "Home" title) is now the Dashboard's
                // shared top bar; the tab renders only its scroll content.
                Scroll {
                    Column(space: 8.0) {
                        ContentHeaderView(config: this.headerConfig())

                        // iOS shows the greeting even without a resolved username
                        // ("Welcome%@" → "Welcome"); not gated on hasUsername().
                        Text(this.welcomeText())
                            .fontSize(uiFontSize(ThemeManager.shared.font.titleMedium))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                            .textAlign(TextAlign.Start)

                        HomeCardView(
                            text: LocalizableStringKey.authenticateAuthoriseTransactions,
                            buttonText: LocalizableStringKey.authenticate,
                            illustrationSrc: ThemeManager.shared.image.homeIdentity,
                            hasLearnMore: true,
                            learnMoreText: Some(LocalizableStringKey.learnMore),
                            learnMoreIconSrc: ThemeManager.shared.image.infoCircle,
                            onLearnMore: { => this.showAuthLearnMore = true },
                            onCardAction: { => this.onAuthenticate() }
                        )
                        HomeCardView(
                            text: LocalizableStringKey.electronicallySignDigitalDocuments,
                            buttonText: LocalizableStringKey.signDocument,
                            illustrationSrc: ThemeManager.shared.image.homeContract,
                            hasLearnMore: true,
                            learnMoreText: Some(LocalizableStringKey.learnMore),
                            learnMoreIconSrc: ThemeManager.shared.image.infoCircle,
                            onLearnMore: { => this.showSignLearnMore = true },
                            onCardAction: { => this.onSignDocument() }
                        )
                    }
                    .width(100.percent)
                    // Bottom inset clears the floating tab bar (it overlays the
                    // scroll content) so the last card's button stays reachable.
                    .padding(top: 0.0, right: 16.0, bottom: 96.0, left: 16.0)
                }
                .align(Alignment.TopStart)
                .width(100.percent)
                .layoutWeight(1)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))

            // ── Overlays (one at a time) ──────────────────────────────────────
            if (this.showAuthChoice) {
                // iOS presents the In-person / Online choice as a bottom action
                // sheet (.confirmationDialog), not a centered alert.
                ConfirmationSheetView(
                    title: LocalizableStringKey.authenticate,
                    // iOS confirmationDialog message: the dedicated authenticate description
                    // (the card text above keeps authenticateAuthoriseTransactions).
                    message: LocalizableStringKey.homeScreenAuthenticateDescription,
                    actions: this.authChoiceActions(),
                    onDismiss: { => this.showAuthChoice = false }
                )
            }
            if (this.showAuthLearnMore) {
                AlertView(
                    title: LocalizableStringKey.alertAccessOnlineServices,
                    message: LocalizableStringKey.alertAccessOnlineServicesMessage,
                    actions: [AlertAction(title: LocalizableStringKey.okButton, callback: { => this.showAuthLearnMore = false })],
                    onDismiss: { => this.showAuthLearnMore = false }
                )
            }
            if (this.showSignLearnMore) {
                AlertView(
                    title: LocalizableStringKey.alertSignDocumentsSafely,
                    message: LocalizableStringKey.alertSignDocumentsSafelyMessage,
                    actions: [AlertAction(title: LocalizableStringKey.okButton, callback: { => this.showSignLearnMore = false })],
                    onDismiss: { => this.showSignLearnMore = false }
                )
            }
            if (this.showBleModal) {
                AlertView(
                    title: LocalizableStringKey.bleDisabledModalTitle,
                    message: LocalizableStringKey.bleDisabledModalCaption,
                    actions: this.bleActions(),
                    onDismiss: { => this.showBleModal = false }
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
    }
}
