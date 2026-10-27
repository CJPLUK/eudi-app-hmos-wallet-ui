/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-issuance
 * module (UI/Document/Offer/DocumentOfferView.swift +
 * UI/Document/Code/OfferCodeView.swift) to Cangjie ArkUI.
 *
 * Credential-offer review screen + transaction-code screen. Both reuse the
 * embedded Web-component authorization path when the offer issuance returns a
 * Pending (auth-code) document. Built-in components only inside ForEach
 * generators (R-102); blocking engine calls in spawn{}, @State writes via
 * spawn(UIThread) (S-001).
 */
package eudi_feature_issuance

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.arkui.component.web.*
import ohos.web.webview.*
import ohos.base.*
import ohos.hilog.Hilog
import kit.ArkUI.*
import std.collection.ArrayList
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_feature_common.IssuanceCodeUiConfig

// Master switch for the debug-only test-issuer auto-fill + ArkWeb DevTools.
//   true  = WebView 加载 issuer 授权页后自动填表并自动提交（+ 页面调试横幅 + web 调试）；
//   false = 完全手动授权（默认,交由用户在网页上自行填写/提交）。
// 单一配置点：add_document_view / document_offer_view 的 onPageEnd 三处均 gate 此常量。
// 需要自动化测试时改回 true 即可。
public let DEBUG_ISSUER_AUTOFILL: Bool = false

// Debug-only JS injected into the test-issuer authorization form once it loads,
// gated behind DEBUG_ISSUER_AUTOFILL. The payload is deliberately NOT kept in
// the repository: it types synthetic identity data into a live issuer's
// authorization form and auto-submits it, which must never run outside a
// developer's own test session. Keep a local copy at
// dev-progress/local/issuer_autofill.js.txt (git-ignored) and paste it back
// here while testing.
let AUTH_FORM_FILL_JS: String = ""

// ─── DocumentOfferView ───────────────────────────────────────────────────────

@Component
public class DocumentOfferView {
    public var viewModel: ?DocumentOfferViewModel = Option<DocumentOfferViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var issuerName: String = ""
    @State
    var issuerLogoUrl: String = ""
    @State
    var offerNames: Array<String> = Array<String>()
    @State
    var allowIssue: Bool = false
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""
    @State
    var authUrl: String = ""
    /** Blocking "Issuance blocked" alert for an issuer that failed trust
     *  validation (iOS `isTrustBlockedAlertShowing`). */
    @State
    var showTrustBlockedAlert: Bool = false
    /** Blocking "Issuance blocked" alert for a provider whose registration
     *  certificate refuses this issuance (iOS `isRegistrationBlockedAlertShowing`). */
    @State
    var showRegistrationBlockedAlert: Bool = false
    /** iOS `initialized`: offer resolved. False + not loading → blank content
     *  (iOS `Color.clear`), e.g. behind the registration-blocked alert. */
    @State
    var initialized: Bool = false
    /** Registration header snapshot (state → @State scalar convention, matching
     *  BaseRequestView): the RelyingPartyRegistrationView payload. */
    @State
    var hasRegistration: Bool = false
    @State
    var regName: String = ""
    @State
    var regIdentifier: String = ""
    @State
    var regIsVerified: Bool = false
    @State
    var regLogoUrl: String = ""
    @State
    var regPrivacyUrl: String = ""
    @State
    var regIntendedUse: String = ""

    private var vm: ?DocumentOfferViewModel = Option<DocumentOfferViewModel>.None
    // Named controller so the authorization WebView can be scripted (debug
    // auto-fill of the test-issuer form's mandatory fields, incl. the native
    // date input that synthetic taps cannot commit back to the page).
    private let authWebController = WebviewController()
    private var redirectHandled: Bool = false

    protected override func aboutToAppear(): Unit {
        // Debug-only: enable ArkWeb DevTools so the in-app authorization WebView
        // can be inspected/automated over the Chrome DevTools Protocol (debug
        // signing only; harmless no-op in release). Lets test automation drive
        // the issuer OAuth form (incl. native date-picker fields that synthetic
        // taps cannot commit back to the page).
        if (DEBUG_ISSUER_AUTOFILL) {
            WebviewController.setWebDebuggingAccess(true)
        }
        let model = this.viewModel ?? makeDefaultDocumentOfferViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.isLoading = state.isLoading
                this.issuerName = state.issuerName
                this.issuerLogoUrl = state.issuerLogoUrl
                this.offerNames = offerNamesOf(state.offers)
                this.allowIssue = state.allowIssue
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
                if (!state.authUrl.isEmpty() && this.authUrl != state.authUrl) {
                    this.redirectHandled = false
                }
                this.authUrl = state.authUrl
                this.showTrustBlockedAlert = state.isTrustBlockedAlertShowing
                this.showRegistrationBlockedAlert = state.isRegistrationBlockedAlertShowing
                this.initialized = state.initialized
                this.syncRegistration(state.issuerRegistration)
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

    /** Copies the issuer-registration header into @State scalars (plain-prop
     *  passing, same convention as BaseRequestView.syncRegistration). */
    private func syncRegistration(data: ?RelyingPartyRegistrationData): Unit {
        match (data) {
            case Some(reg) =>
                this.hasRegistration = true
                this.regName = LocalizableManager.get(reg.primary.name)
                this.regIdentifier = optOfferKeyText(reg.primary.identifier)
                this.regIsVerified = reg.primary.isVerified
                this.regLogoUrl = reg.primary.logoUrl
                this.regPrivacyUrl = reg.privacyPolicyUrl
                this.regIntendedUse = optOfferKeyText(reg.intendedUse)
            case None =>
                this.hasRegistration = false
                this.regName = ""
                this.regIdentifier = ""
                this.regIsVerified = false
                this.regLogoUrl = ""
                this.regPrivacyUrl = ""
                this.regIntendedUse = ""
        }
    }

    /** Rebuilds the header payload from the @State snapshot. */
    private func registrationData(): RelyingPartyRegistrationData {
        let identifier: ?LocalizableStringKey = if (this.regIdentifier.isEmpty()) {
            None
        } else {
            Some(LocalizableStringKey.custom(this.regIdentifier))
        }
        let intendedUse: ?LocalizableStringKey = if (this.regIntendedUse.isEmpty()) {
            None
        } else {
            Some(LocalizableStringKey.custom(this.regIntendedUse))
        }
        RelyingPartyRegistrationData(
            primary: RegisteredParty(
                name: LocalizableStringKey.custom(this.regName),
                identifier: identifier,
                isVerified: this.regIsVerified,
                logoUrl: this.regLogoUrl
            ),
            privacyPolicyUrl: this.regPrivacyUrl,
            intendedUse: intendedUse
        )
    }

    private func onIssue(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.onIssueDocuments() }
            case None => ()
        }
    }

    private func onRedirectCaptured(redirectUrl: String): Unit {
        if (this.redirectHandled) {
            Hilog.info(0, "VCI-DEBUG", "offer-web redirect ignored (already handled)")
            return
        }
        this.redirectHandled = true
        match (this.vm) {
            case Some(model) => spawn { => model.onAuthorizationRedirect(redirectUrl) }
            case None => ()
        }
    }

    private func onCancel(): Unit {
        match (this.vm) {
            case Some(model) => model.onPop()
            case None => ()
        }
    }

    private func onDismissError(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissError()
            case None => ()
        }
    }

    private func onTrustBlockedClose(): Unit {
        match (this.vm) {
            case Some(model) => model.onTrustBlockedClose()
            case None => ()
        }
    }

    private func onRegistrationBlockedClose(): Unit {
        match (this.vm) {
            case Some(model) => model.onRegistrationBlockedClose()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Bottom) {
                if (!this.authUrl.isEmpty()) {
                    this.authorizationWebView()
                } else if (this.hasError) {
                    ContentErrorView(
                        config: ContentErrorConfig(
                            description: LocalizableStringKey.custom(this.errorMessage),
                            cancelAction: { => this.onDismissError() }
                        )
                    )
                } else {
                    this.offerContent()
                }
                // iOS 95b71766 replaced TrustBlockedSheetContent with the
                // standard alertView (single Close; dismiss + pop).
                if (this.showTrustBlockedAlert) {
                    AlertView(
                        title: LocalizableStringKey.issuanceBlockedTitle,
                        message: LocalizableStringKey.issuanceBlockedMessage,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.close,
                                callback: { => this.onTrustBlockedClose() }
                            )
                        ],
                        onDismiss: { => this.onTrustBlockedClose() }
                    )
                }
                // iOS registration-blocked alert: the provider is not registered
                // for this issuance — nothing was issued (Close pops back).
                if (this.showRegistrationBlockedAlert) {
                    AlertView(
                        title: LocalizableStringKey.issuanceRegistrationBlockedTitle,
                        message: LocalizableStringKey.issuanceRegistrationBlockedMessage,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.close,
                                callback: { => this.onRegistrationBlockedClose() }
                            )
                        ],
                        onDismiss: { => this.onRegistrationBlockedClose() }
                    )
                }
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
    }

    @Builder
    private func authorizationWebView() {
        Web(src: this.authUrl, controller: this.authWebController)
            .onLoadIntercept({ event =>
                let url = event.data.getRequestUrl()
                Hilog.info(0, "VCI-DEBUG", "offer-web intercept urlLen=${url.size}")
                if (isIssuanceRedirect(url)) {
                    this.onRedirectCaptured(url)
                    return true
                }
                return false
            })
            .onPageEnd({ event =>
                Hilog.info(0, "VCI-DEBUG", "offer-web pageEnd urlLen=${event.url.size}")
                // Debug auto-fill of the test-issuer authorization form (see
                // AUTH_FORM_FILL_JS). Fires after each page load; idempotent and
                // never submits, so it is safe on every navigation in this flow.
                if (DEBUG_ISSUER_AUTOFILL) {
                    this.authWebController.runJavaScript(AUTH_FORM_FILL_JS, { _, _ => })
                }
            })
            .domStorageAccess(true)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .width(100.percent)
            .height(100.percent)
    }

    @Builder
    private func offerContent() {
        Column {
            // Toolbar: cancel (xmark) leading.
            Row {
                Image(appImageSrc(ThemeManager.shared.image.xmark))
                    .width(24.0)
                    .height(24.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                    .onClick({ _ => this.onCancel() })
                Blank()
            }
            .width(100.percent)
            .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)

            // iOS nav title .addDocumentRequest → .issuanceRequestTitle.
            Text(LocalizableManager.get(LocalizableStringKey.issuanceRequestTitle))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(uiFontWeight(ThemeManager.shared.font.headlineMedium))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Center)
                .width(100.percent)

            if (!this.initialized && !this.isLoading) {
                // iOS `Color.clear`: offer never resolved (e.g. registration
                // blocked) — blank content behind the blocking alert.
                Column {}
                    .width(100.percent)
                    .layoutWeight(1)
            } else if (this.isLoading) {
                // Resolving the offer — spinner, NOT the empty view: rendering
                // the "(!) Unable to fetch…" empty state while offers are still
                // loading flashed it on every entry (iOS shows a shimmer mock
                // during initialize and only shows the empty view when a
                // resolved offer truly has no documents).
                Column(space: SPACING_MEDIUM) {
                    Blank()
                    ContentLoaderView(showLoader: true)
                    Blank()
                }
                .width(100.percent)
                .layoutWeight(1)
                .padding(SPACING_MEDIUM)
            } else if (this.offerNames.size == 0) {
                Column(space: SPACING_MEDIUM) {
                    // iOS noDocumentsFound still leads with the registration
                    // header so the user sees WHO offered nothing.
                    if (this.hasRegistration) {
                        RelyingPartyRegistrationView(data: this.registrationData())
                    }
                    ContentEmptyView(title: LocalizableStringKey.requestCredentialOfferNoDocument)
                }
                .width(100.percent)
                .layoutWeight(1)
                .padding(SPACING_MEDIUM)
            } else {
                Scroll {
                    Column(space: SPACING_MEDIUM) {
                        // iOS RelyingPartyRegistrationView header (replaces
                        // ContentHeaderView): registered issuer + optional
                        // privacy-policy link + optional intended use.
                        if (this.hasRegistration) {
                            RelyingPartyRegistrationView(data: this.registrationData())
                        }
                        ForEach(
                            this.offerNames,
                            itemGenerator: { name: String, _: Int64 =>
                                Row {
                                    Text(name)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                        .layoutWeight(1)
                                        .textAlign(TextAlign.Start)
                                }
                                .width(100.percent)
                                .padding(SPACING_MEDIUM)
                                .backgroundColor(uiColor(ThemeManager.shared.color.groupedElevatedBackground))
                                .borderRadius(18.0)
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(top: 0.0, right: ThemeManager.shared.dimension.padding, bottom: SPACING_MEDIUM, left: ThemeManager.shared.dimension.padding)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)

                // bottom issue button
                Column {
                    WrapButtonView(
                        title: LocalizableStringKey.issueButton,
                        style: ButtonViewStyle.primary(),
                        isLoading: this.isLoading,
                        isEnabled: this.allowIssue,
                        onAction: { => this.onIssue() }
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_LARGE_MEDIUM, left: SPACING_MEDIUM)
            }
        }
        .width(100.percent)
        .height(100.percent)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }
}

/** "" for an absent localization key (offer registration header snapshot). */
func optOfferKeyText(key: ?LocalizableStringKey): String {
    match (key) {
        case Some(k) => LocalizableManager.get(k)
        case None => ""
    }
}

func offerNamesOf(offers: ArrayList<OfferItem>): Array<String> {
    let out = Array<String>(offers.size, repeat: "")
    var i = 0
    for (o in offers) {
        out[i] = o.name
        i += 1
    }
    return out
}

func makeDefaultDocumentOfferViewModel(): DocumentOfferViewModel {
    return DocumentOfferViewModel(
        router: InMemoryRouterHost(),
        interactor: NoopDocumentOfferInteractor(),
        offerUri: ""
    )
}

// ─── OfferCodeView ───────────────────────────────────────────────────────────

@Component
public class OfferCodeView {
    public var viewModel: ?OfferCodeViewModel = Option<OfferCodeViewModel>.None

    @State
    var isLoading: Bool = false
    @State
    var issuerName: String = ""
    @State
    var txCodeLength: Int64 = 6
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""
    @State
    var authUrl: String = ""
    /** Blocking "Issuance blocked" alert for an issuer that failed trust
     *  validation (iOS `isTrustBlockedAlertShowing`). */
    @State
    var showTrustBlockedAlert: Bool = false

    private var vm: ?OfferCodeViewModel = Option<OfferCodeViewModel>.None
    private let authWebController = WebviewController()
    private var redirectHandled: Bool = false

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultOfferCodeViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.isLoading = state.isLoading
                this.issuerName = state.issuerName
                this.txCodeLength = state.txCodeLength
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
                if (!state.authUrl.isEmpty() && this.authUrl != state.authUrl) {
                    this.redirectHandled = false
                }
                this.authUrl = state.authUrl
                this.showTrustBlockedAlert = state.isTrustBlockedAlertShowing
            }
        })
        // initialise display fields from the VM's current state
        this.issuerName = model.viewState.issuerName
        this.txCodeLength = model.viewState.txCodeLength
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onCodeComplete(code: String): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.submitCode(code) }
            case None => ()
        }
    }

    private func onRedirectCaptured(redirectUrl: String): Unit {
        if (this.redirectHandled) {
            Hilog.info(0, "VCI-DEBUG", "offer-code-web redirect ignored (already handled)")
            return
        }
        this.redirectHandled = true
        match (this.vm) {
            case Some(model) => spawn { => model.onAuthorizationRedirect(redirectUrl) }
            case None => ()
        }
    }

    private func onCancel(): Unit {
        match (this.vm) {
            case Some(model) => model.onPop()
            case None => ()
        }
    }

    private func onDismissError(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissError()
            case None => ()
        }
    }

    private func onTrustBlockedClose(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissTrustBlockedAlert()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Bottom) {
                if (!this.authUrl.isEmpty()) {
                    this.authorizationWebView()
                } else if (this.hasError) {
                    ContentErrorView(
                        config: ContentErrorConfig(
                            description: LocalizableStringKey.custom(this.errorMessage),
                            cancelAction: { => this.onDismissError() }
                        )
                    )
                } else {
                    this.codeContent()
                }
                // iOS 95b71766: TrustBlockedSheetContent → standard alertView.
                if (this.showTrustBlockedAlert) {
                    AlertView(
                        title: LocalizableStringKey.issuanceBlockedTitle,
                        message: LocalizableStringKey.issuanceBlockedMessage,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.close,
                                callback: { => this.onTrustBlockedClose() }
                            )
                        ],
                        onDismiss: { => this.onTrustBlockedClose() }
                    )
                }
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
    }

    @Builder
    private func authorizationWebView() {
        Web(src: this.authUrl, controller: this.authWebController)
            .onLoadIntercept({ event =>
                let url = event.data.getRequestUrl()
                Hilog.info(0, "VCI-DEBUG", "offer-web intercept urlLen=${url.size}")
                if (isIssuanceRedirect(url)) {
                    this.onRedirectCaptured(url)
                    return true
                }
                return false
            })
            .onPageEnd({ event =>
                Hilog.info(0, "VCI-DEBUG", "offer-web pageEnd urlLen=${event.url.size}")
                // Debug auto-fill of the test-issuer authorization form (see
                // AUTH_FORM_FILL_JS). Fires after each page load; idempotent and
                // never submits, so it is safe on every navigation in this flow.
                if (DEBUG_ISSUER_AUTOFILL) {
                    this.authWebController.runJavaScript(AUTH_FORM_FILL_JS, { _, _ => })
                }
            })
            .domStorageAccess(true)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .width(100.percent)
            .height(100.percent)
    }

    @Builder
    private func codeContent() {
        Column {
            Row {
                Image(appImageSrc(ThemeManager.shared.image.chevronLeft))
                    .width(24.0)
                    .height(24.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                    .onClick({ _ => this.onCancel() })
                Blank()
            }
            .width(100.percent)
            .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)

            Scroll {
                Column(space: SPACING_MEDIUM) {
                    ContentHeaderView(
                        config: ContentHeaderConfig(
                            appIconAndTextData: AppIconAndTextData(
                                appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                                appTextSrc: ThemeManager.shared.image.euditext
                            )
                        )
                    )
                    ContentTitleView(
                        title: LocalizableStringKey.issuanceCodeTitle([this.issuerName]),
                        caption: LocalizableStringKey.issuanceCodeCaption([codeLengthString(this.txCodeLength)])
                    )
                    EasySpacer(spacerHeight: SPACING_LARGE)
                    if (this.isLoading) {
                        ContentLoaderView(showLoader: true)
                    } else {
                        PinTextFieldView(
                            maxDigits: this.txCodeLength,
                            isSecureEntry: true,
                            isDisabled: this.isLoading,
                            onPinComplete: { code => this.onCodeComplete(code) }
                        )
                    }
                }
                .width(100.percent)
                .padding(top: 0.0, right: ThemeManager.shared.dimension.padding, bottom: SPACING_MEDIUM, left: ThemeManager.shared.dimension.padding)
            }
            .align(Alignment.TopStart)
            .layoutWeight(1)
        }
        .width(100.percent)
        .height(100.percent)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }
}

func codeLengthString(len: Int64): String {
    "${len}"
}

func makeDefaultOfferCodeViewModel(): OfferCodeViewModel {
    return OfferCodeViewModel(
        router: InMemoryRouterHost(),
        interactor: NoopDocumentOfferInteractor(),
        config: IssuanceCodeUiConfig(
            offerUri: "",
            issuerName: "",
            txCodeLength: 6,
            successNavigation: TwoWayNavigationType.NavPush(AppRoutes.dashboard),
            navigationCancelType: ThreeWayNavigationType.ThreeWayPop
        )
    )
}

/** Standalone-render interactor (no engine wired). */
class NoopDocumentOfferInteractor <: DocumentOfferInteractor {
    public func processOfferRequest(uri: String): OfferRequest {
        OfferRequest.failure("not wired")
    }
    public func issueDocuments(uri: String, txCodeValue: ?String): OfferResult {
        OfferResult.failure("not wired")
    }
    public func resumeDynamicIssuance(redirectUrl: String): ResumeResult {
        ResumeResult.noPending()
    }
    public func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary> {
        ArrayList<IssuedDocumentSummary>()
    }
}
