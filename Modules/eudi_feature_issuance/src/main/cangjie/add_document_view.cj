/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-issuance
 * module (UI/Document/Add/AddDocumentView.swift) to Cangjie ArkUI.
 *
 * Add-document screen: lists issuable document types grouped by issuer
 * (cards rendered with built-in components — no custom @Component inside the
 * ForEach item generator, R-102). Tapping a row issues that document. For an
 * auth-code (eudiw PID) credential the engine returns a Pending doc carrying a
 * browser-authorization URL; the screen swaps to an embedded Web component (the
 * verified pattern from third_party/eudi_lib_openid4vp_vci/entry/.../page/index.cj)
 * that loads the authorization URL, intercepts the
 * `eu.europa.ec.euidi://...?code=` redirect, and resumes issuance.
 *
 * Blocking engine calls run in spawn{}; @State writes are marshalled with
 * spawn(UIThread) (S-001).
 */
package eudi_feature_issuance

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.arkui.component.web.*
import ohos.web.webview.*
import ohos.hilog.Hilog
import ohos.base.*
import kit.ArkUI.*
import std.collection.ArrayList
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_logic_core.DocumentTypeIdentifier
import eudi_feature_common.{IssuanceFlow, ScannerUiConfig, ScannerFlow}

/** Redirect schemes intercepted to capture the authorization `?code=`
 *  (OpenID4VCI redirect_uri / iOS AddDocumentInteractor). Two schemes exist:
 *  app-registered issuer configs use eu.europa.ec.euidi://authorization while
 *  unregistered issuers fall back to the wallet-kit default
 *  eudi-openid4ci://authorize (iOS matches both because its
 *  ASWebAuthenticationSession takes the callback scheme dynamically). */
let ISSUANCE_REDIRECT_SCHEME: String = "eu.europa.ec.euidi://"
let ISSUANCE_REDIRECT_SCHEME_DEFAULT: String = "eudi-openid4ci://"

func isIssuanceRedirect(url: String): Bool {
    url.startsWith(ISSUANCE_REDIRECT_SCHEME) || url.startsWith(ISSUANCE_REDIRECT_SCHEME_DEFAULT)
}

/** True for the ExtraDocument flow (opened from Documents "+"), which shows the
 *  leading back chevron; the NoDocument onboarding flow does not (mirrors iOS). */
func isExtraDocumentFlow(flow: IssuanceFlow): Bool {
    match (flow) {
        case IssuanceFlow.ExtraDocument(_) => true
        case _ => false
    }
}

@Component
public class AddDocumentView {
    public var viewModel: ?AddDocumentViewModel = Option<AddDocumentViewModel>.None

    @State
    var rows: Array<AddDocumentRow> = Array<AddDocumentRow>()
    @State
    var isLoading: Bool = true
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""
    @State
    var authUrl: String = ""
    /** Prevents a slow authorization request from appearing as a blank page. */
    @State
    var authPageLoaded: Bool = false
    /** iOS shows the leading back chevron only for the ExtraDocument flow (opened
     *  from Documents "+"); the NoDocument onboarding flow has no back. */
    @State
    var showBack: Bool = false
    /** Blocking "Issuance blocked" alert for an issuer that failed trust
     *  validation (iOS `isTrustBlockedAlertShowing`). */
    @State
    var showTrustBlockedAlert: Bool = false
    /** Blocking "Issuance blocked" alert for a provider whose registration
     *  certificate refuses this issuance (iOS `isRegistrationBlockedAlertShowing`). */
    @State
    var showRegistrationBlockedAlert: Bool = false

    private var vm: ?AddDocumentViewModel = Option<AddDocumentViewModel>.None
    private let authWebController = WebviewController()
    /** Web onLoadIntercept can fire the same auth-code redirect more than once;
     *  only the first spawn may resume issuance (avoids racing NavPathStack). */
    private var redirectHandled: Bool = false

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultAddDocumentViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.rows = flattenRows(state.buckets)
                this.isLoading = state.isLoading
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
                if (state.authUrl.isEmpty()) {
                    this.authPageLoaded = true
                } else if (this.authUrl != state.authUrl) {
                    this.authPageLoaded = false
                    // New authorization session → allow one redirect again.
                    this.redirectHandled = false
                }
                this.authUrl = state.authUrl
                this.showBack = isExtraDocumentFlow(state.flow)
                this.showTrustBlockedAlert = state.isTrustBlockedAlertShowing
                this.showRegistrationBlockedAlert = state.isRegistrationBlockedAlertShowing
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

    /** Leading back chevron → pop (ExtraDocument flow only; mirrors iOS). */
    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    /** Trailing scan action → open the issuing QR scanner (iOS toolbar scan).
     *  Carries FlowIssuing so the scanner shows the "Scan QR" title/caption. */
    private func onScan(): Unit {
        match (this.vm) {
            case Some(model) =>
                let config = ScannerUiConfig(
                    flow: ScannerFlow.FlowIssuing(
                        TwoWayNavigationType.NavPopTo(AppRoutes.dashboard),
                        ThreeWayNavigationType.ThreeWayPopTo(AppRoutes.issuanceOption)
                    )
                )
                NavArgs.shared.set(AppRoutes.qrScanner, RouteConfigArgs(config))
                model.router.push(AppRoutes.qrScanner)
            case None => ()
        }
    }

    private func onCellTap(row: AddDocumentRow): Unit {
        if (this.isLoading || row.isHeader) {
            return
        }
        match (row.item) {
            case Some(item) =>
                match (this.vm) {
                    case Some(model) => spawn { => model.issueDocument(item) }
                    case None => ()
                }
            case None => ()
        }
    }

    private func onRedirectCaptured(redirectUrl: String): Unit {
        if (this.redirectHandled) {
            Hilog.info(0, "VCI-DEBUG", "issuance-web redirect ignored (already handled)")
            return
        }
        this.redirectHandled = true
        match (this.vm) {
            case Some(model) => spawn { => model.onAuthorizationRedirect(redirectUrl) }
            case None => ()
        }
    }

    private func onAuthorizationPageEnd(): Unit {
        this.authPageLoaded = true
        // Gateway errors are otherwise rendered as a blank-looking web page.
        // Convert them to the standard retryable native error state.
        this.authWebController.runJavaScript(
            "document.body ? document.body.innerText : ''",
            { _, result =>
                match (result) {
                    case Some(body) =>
                        if (body.contains("no code issued") ||
                            (body.contains("server_error") && body.contains("error_description"))) {
                            match (this.vm) {
                                case Some(model) => model.authorizationFailed(
                                    "The issuer did not return an authorization code. Please retry to start a new authorization session."
                                )
                                case None => ()
                            }
                        } else if (body.contains("504") || body.contains("Gateway Time-out") ||
                            body.contains("502 Bad Gateway") || body.contains("503 Service Unavailable")) {
                            match (this.vm) {
                                case Some(model) => model.authorizationFailed(
                                    "The issuer authorization service is temporarily unavailable. Please try again."
                                )
                                case None => ()
                            }
                        }
                    case None => ()
                }
            }
        )
    }

    private func onRetry(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.retryLastIssue() }
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
            case Some(model) => model.dismissRegistrationBlockedAlert()
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
                            cancelAction: { => this.onDismissError() },
                            hasRetry: true,
                            retryAction: { => this.onRetry() }
                        )
                    )
                } else {
                    this.listContent()
                }
                // iOS 95b71766 replaced TrustBlockedSheetContent with the
                // standard alertView: a blocking alert with a single Close —
                // no retry, because the issuer could not be verified.
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
                // for this issuance — refused before anything was issued.
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
        // Embedded browser authorization (auth-code issuance) — verified pattern.
        Stack {
            Web(src: this.authUrl, controller: this.authWebController)
                .onLoadIntercept({ event =>
                    let url = event.data.getRequestUrl()
                    Hilog.info(0, "VCI-DEBUG", "issuance-web intercept urlLen=${url.size}")
                    if (isIssuanceRedirect(url)) {
                        this.onRedirectCaptured(url)
                        return true
                    }
                    return false
                })
                .onPageEnd({ event =>
                    Hilog.info(0, "VCI-DEBUG", "issuance-web pageEnd urlLen=${event.url.size}")
                    this.onAuthorizationPageEnd()
                    // Debug auto-fill of the test-issuer authorization form (see
                    // AUTH_FORM_FILL_JS in document_offer_view.cj). Idempotent retry
                    // loop; never submits.
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
            if (!this.authPageLoaded) {
                Column {
                    ContentLoaderView(showLoader: true)
                }
                .width(100.percent)
                .height(100.percent)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(Color.White)
            }
        }
        .width(100.percent)
        .height(100.percent)
    }

    /**
     * Nav bar mirroring the iOS AddDocumentView toolbar: leading back chevron
     * (ExtraDocument flow only), centered "Choose from list" title, trailing scan
     * (qrcode.viewfinder) — matching the shared circular-chip button style.
     */
    @Builder
    private func navBar() {
        Stack(alignContent: Alignment.Center) {
            Text(LocalizableManager.get(LocalizableStringKey.chooseFromList))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            Row {
                if (this.showBack) {
                    Row {
                        AppIcon(
                            token: ThemeManager.shared.image.chevronLeft,
                            size: 25.0,
                            color: uiColor(ThemeManager.shared.color.primaryLabel)
                        )
                    }
                    .width(40.0)
                    .height(40.0)
                    .justifyContent(FlexAlign.Center)
                    .borderRadius(20.0)
                    .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                    .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
                    .onClick({ _ => this.onBack() })
                } else {
                    Row {}.width(40.0).height(40.0)
                }
                Row {}.layoutWeight(1)
                Row {
                    AppIcon(
                        token: ThemeManager.shared.image.qrCodeViewfinder,
                        size: 22.0,
                        color: uiColor(ThemeManager.shared.color.primaryLabel)
                    )
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
                .onClick({ _ => this.onScan() })
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Center)
        }
        .width(100.percent)
        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }

    @Builder
    private func listContent() {
        Column {
            this.navBar()
            if (this.isLoading) {
                // Fetching issuer metadata over the network takes a few seconds;
                // show a loader instead of the "no documents" empty state so the
                // list does not flash "no document" before the issuers arrive.
                Column {
                    ContentLoaderView(showLoader: true)
                }
                .width(100.percent)
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
            } else if (this.rows.size == 0) {
                Column(space: SPACING_MEDIUM) {
                    Text(LocalizableManager.get(LocalizableStringKey.chooseFromListTitle))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .width(100.percent)
                    ContentEmptyView(title: LocalizableStringKey.issuanceAddDocumentNoOptions)
                }
                .width(100.percent)
                .padding(SPACING_MEDIUM)
                .layoutWeight(1)
            } else {
                Scroll {
                    Column(space: SPACING_MEDIUM_SMALL) {
                        Text(LocalizableManager.get(LocalizableStringKey.chooseFromListTitle))
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                        ForEach(
                            this.rows,
                            itemGenerator: { row: AddDocumentRow, _: Int64 =>
                                // Built-in components only (R-102): a card-styled
                                // row, header or tappable attestation cell.
                                if (row.isHeader) {
                                    Text(row.title)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                        .fontWeight(FontWeight.Medium)
                                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                        .width(100.percent)
                                        .padding(top: SPACING_MEDIUM_SMALL, right: 0.0, bottom: 0.0, left: 0.0)
                                } else {
                                    Row(space: SPACING_SMALL) {
                                        Text(row.title)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .layoutWeight(1)
                                            .textAlign(TextAlign.Start)
                                        Image(appImageSrc(ThemeManager.shared.image.plus))
                                            .width(20.0)
                                            .height(20.0)
                                            .objectFit(ImageFit.Contain)
                                            .fillColor(uiColor(ThemeManager.shared.color.accent))
                                    }
                                    .width(100.percent)
                                    .padding(SPACING_MEDIUM)
                                    .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                                    .borderRadius(18.0)
                                    .opacity(this.rowOpacity())
                                    .onClick({ _ => this.onCellTap(row) })
                                }
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(top: 0.0, right: ThemeManager.shared.dimension.padding, bottom: SPACING_MEDIUM, left: ThemeManager.shared.dimension.padding)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
            }
        }
        .width(100.percent)
        .height(100.percent)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }

    private func rowOpacity(): Float64 {
        if (this.isLoading) {
            return 0.5
        }
        return 1.0
    }
}

/** A flattened display row: either an issuer header or a tappable cell. */
public class AddDocumentRow {
    public let isHeader: Bool
    public let title: String
    public let item: ?AddDocumentItem

    public init(isHeader!: Bool, title!: String, item!: ?AddDocumentItem) {
        this.isHeader = isHeader
        this.title = title
        this.item = item
    }
}

/** Flattens issuer buckets into header + cell rows for a single ForEach. */
func flattenRows(buckets: ArrayList<AddDocumentBucket>): Array<AddDocumentRow> {
    let acc: ArrayList<AddDocumentRow> = ArrayList<AddDocumentRow>()
    for (bucket in buckets) {
        acc.add(AddDocumentRow(isHeader: true, title: bucket.issuerId, item: Option<AddDocumentItem>.None))
        for (item in bucket.items) {
            acc.add(AddDocumentRow(isHeader: false, title: item.name, item: Some(item)))
        }
    }
    let out = Array<AddDocumentRow>(acc.size, repeat: AddDocumentRow(isHeader: true, title: "", item: Option<AddDocumentItem>.None))
    var i = 0
    for (r in acc) {
        out[i] = r
        i += 1
    }
    return out
}

/** Emulator-safe default (composition root supplies the wired instance). */
func makeDefaultAddDocumentViewModel(): AddDocumentViewModel {
    return AddDocumentViewModel(
        router: InMemoryRouterHost(),
        interactor: NoopAddDocumentInteractor(),
        flow: IssuanceFlow.NoDocument
    )
}

/** A standalone-render interactor returning an empty list (no engine wired). */
class NoopAddDocumentInteractor <: AddDocumentInteractor {
    public func fetchScopedDocuments(flow: IssuanceFlow): ScopedDocumentsResult {
        ScopedDocumentsResult.success(ArrayList<AddDocumentBucket>())
    }
    public func issueDocument(issuerId: String, configIds: Array<String>, docTypeIdentifier: DocumentTypeIdentifier): IssueResult {
        IssueResult.failure("not wired")
    }
    public func resumeDynamicIssuance(redirectUrl: String): ResumeResult {
        ResumeResult.noPending()
    }
    public func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary> {
        ArrayList<IssuedDocumentSummary>()
    }
}
