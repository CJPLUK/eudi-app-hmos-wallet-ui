/*
 * rqes_view_models.cj — ports the 5 ViewModels + ViewStates of eudi-lib-ios-rqes-ui
 * Sources/Presentation/UI/{ServiceSelection,DocumentSelectionView,CredentialSelection,
 * SignedDocument,DocumentView}.
 *
 * ViewModels extend eudi_logic_ui.BaseViewModel<S> like every delivered feature; each is a
 * UI-free synchronous seam over the RQES Domain 底座 (RQESInteractor from eudi_cjrqes_ui).
 * The View subscribes via onStateChange and marshals blocking calls through spawn{} /
 * spawn(UIThread){}. No ArkUI import here.
 *
 * Authorization opens the EXTERNAL system browser (iOS UIApplication.openURLIfPossible): the
 * VM publishes the URL into `authUrl`, and the View opens it via the platform bridge, then the
 * flow resumes through the app's rqes:// deep link. Localization: RQES-specific strings use
 * LocalizableStringKey.custom(...) pending real keys (task card §7.5).
 */
package eudi_feature_rqes

import std.collection.ArrayList
import eudi_logic_ui.{BaseViewModel, ViewState, RouterHost, ContentErrorConfig, AppRoutes}
import eudi_logic_resources.LocalizableStringKey
import ohos_app_cangjie_eudi_cjrqes_ui.{
    RQESInteractor, QTSPData, DocumentData, SessionData, FetchCredentialsResult, EudiRQESUiError
}
import ohos_app_cangjie_eudi_cjrqes_csc.ListCredentialInfo
import ohos_app_cangjie_eudi_cjrqes_kit.Document

// ─── iOS RQES SDK error text (1:1) ───────────────────────────────────────────
// eudi-lib-ios-rqes-ui Sources/Domain/Entities/Localization/LocalizableKey.swift:
// every RQES error screen builds ContentErrorView.Config with the same title
// (.genericErrorMessage) + retry button (.genericErrorButtonRetry) and one of
// two descriptions — the service-unavailable message or the document-not-found
// message (unableToOpenBrowser for the browser-launch failure). Kept as literal
// strings via LocalizableStringKey.custom (the SDK strings have no HMOS key yet).
let RQES_ERR_TITLE: String = "Oups! Something went wrong"
let RQES_ERR_RETRY: String = "TRY AGAIN"
let RQES_ERR_SERVICE: String = "It seems the RQES Signing service is unavailable. Please try again later."
let RQES_ERR_DOC_NOT_FOUND: String = "No Document data found"
let RQES_ERR_BROWSER: String = "Unable to open browser"

/** iOS `.genericServiceErrorMessage` error config (title + service message + retry). */
func rqesServiceError(cancelAction!: () -> Unit, retryAction!: () -> Unit): ContentErrorConfig {
    ContentErrorConfig(
        title: LocalizableStringKey.custom(RQES_ERR_TITLE),
        description: LocalizableStringKey.custom(RQES_ERR_SERVICE),
        button: LocalizableStringKey.custom(RQES_ERR_RETRY),
        cancelAction: cancelAction,
        hasRetry: true,
        retryAction: retryAction)
}

/** iOS `.genericErrorDocumentNotFound` error config (title + doc-not-found + retry). */
func rqesDocNotFoundError(cancelAction!: () -> Unit, retryAction!: () -> Unit): ContentErrorConfig {
    ContentErrorConfig(
        title: LocalizableStringKey.custom(RQES_ERR_TITLE),
        description: LocalizableStringKey.custom(RQES_ERR_DOC_NOT_FOUND),
        button: LocalizableStringKey.custom(RQES_ERR_RETRY),
        cancelAction: cancelAction,
        hasRetry: true,
        retryAction: retryAction)
}

/** iOS `.unableToOpenBrowser` error config (title + browser message + retry). */
func rqesBrowserError(cancelAction!: () -> Unit, retryAction!: () -> Unit): ContentErrorConfig {
    ContentErrorConfig(
        title: LocalizableStringKey.custom(RQES_ERR_TITLE),
        description: LocalizableStringKey.custom(RQES_ERR_BROWSER),
        button: LocalizableStringKey.custom(RQES_ERR_RETRY),
        cancelAction: cancelAction,
        hasRetry: true,
        retryAction: retryAction)
}

// ─── Flat render-ready UI models (no ArkUI) ──────────────────────────────────

/** iOS SelectionItemData — one step row on DocumentSelection (document / service / certificate). */
public class RqesSelectionRow {
    public let step: Int64
    public let overline: ?LocalizableStringKey
    public let mainText: LocalizableStringKey
    public let subtitle: ?LocalizableStringKey
    public let actionText: ?LocalizableStringKey
    public let enabled: Bool
    // iOS leadingIconTint: .success (green, step completed) vs .onSurface (pending/active).
    public let done: Bool
    public let action: () -> Unit

    public init(step!: Int64, mainText!: LocalizableStringKey, overline!: ?LocalizableStringKey = None,
                subtitle!: ?LocalizableStringKey = None, actionText!: ?LocalizableStringKey = None,
                enabled!: Bool = true, done!: Bool = false, action!: () -> Unit = { => }) {
        this.step = step
        this.overline = overline
        this.mainText = mainText
        this.subtitle = subtitle
        this.actionText = actionText
        this.enabled = enabled
        this.done = done
        this.action = action
    }
}

/** iOS CredentialDataUIModel — one selectable signing credential row. */
public class RqesCredentialRow {
    public let id: String
    public let label: String
    public init(id!: String, label!: String) {
        this.id = id
        this.label = label
    }
}

func credentialToRow(info: ListCredentialInfo): RqesCredentialRow {
    let label = match (info.description) {
        case Some(d) => d
        case None => info.credentialID
    }
    return RqesCredentialRow(id: info.credentialID, label: label)
}

// ═══ ServiceSelection (.rssps) ═══════════════════════════════════════════════

/** iOS ServiceSelectionState. `authUrl` non-empty → View opens external browser. */
public class ServiceSelectionState <: ViewState {
    public let isLoading: Bool
    public let services: Array<QTSPData>
    public let error: ?ContentErrorConfig
    public let authUrl: String

    public init(isLoading!: Bool = false, services!: Array<QTSPData> = Array<QTSPData>(),
                error!: ?ContentErrorConfig = None, authUrl!: String = "") {
        this.isLoading = isLoading
        this.services = services
        this.error = error
        this.authUrl = authUrl
    }
}

public class ServiceSelectionViewModel <: BaseViewModel<ServiceSelectionState> {
    private let interactor: RQESInteractor
    public var selectedItem: ?QTSPData = None

    public init(router!: RouterHost, interactor!: RQESInteractor) {
        super(router, ServiceSelectionState())
        this.interactor = interactor
    }

    // iOS initiate(): load QTSPs; empty → error → pop.
    public func initiate(): Unit {
        let services = interactor.getQTSps()
        if (!services.isEmpty()) {
            setState({ _ => ServiceSelectionState(services: services) })
        } else {
            setState({ _ => ServiceSelectionState(error: rqesServiceError(
                cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }

    public func nextStep(): Unit {
        openAuthorization()
    }

    // iOS openAuthorization(): createRQESService + openAuthrorizationURL + updateQTSP → external browser.
    func openAuthorization(): Unit {
        setState({ s => ServiceSelectionState(isLoading: true, services: s.services) })
        try {
            let sel = match (selectedItem) {
                case Some(q) => q
                case None => throw EudiRQESUiError.noRQESServiceProvided()
            }
            interactor.createRQESService(sel)
            let url = interactor.openAuthrorizationURL()
            interactor.updateQTSP(sel)
            setState({ s => ServiceSelectionState(services: s.services, authUrl: url) })
        } catch (_: Exception) {
            setState({ s => ServiceSelectionState(services: s.services, error: rqesServiceError(
                cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }

    // iOS openURLIfPossible failure branch → setErrorState(.unableToOpenBrowser).
    // The View reports back when RqesBrowser.open returns false (no handler / launch failed).
    public func onBrowserOpenFailed(): Unit {
        setState({ s => ServiceSelectionState(services: s.services, error: rqesBrowserError(
            cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
    }
}

// ═══ DocumentSelection (.initial / .credentials) ═════════════════════════════

/** iOS DocumentSelectionState — the 3 step rows (document / service / certificate). */
public class DocumentSelectionState <: ViewState {
    public let isLoading: Bool
    public let documentRow: ?RqesSelectionRow
    public let serviceRow: ?RqesSelectionRow
    public let certificateRow: ?RqesSelectionRow
    public let error: ?ContentErrorConfig

    public init(isLoading!: Bool = true, documentRow!: ?RqesSelectionRow = None,
                serviceRow!: ?RqesSelectionRow = None, certificateRow!: ?RqesSelectionRow = None,
                error!: ?ContentErrorConfig = None) {
        this.isLoading = isLoading
        this.documentRow = documentRow
        this.serviceRow = serviceRow
        this.certificateRow = certificateRow
        this.error = error
    }
}

public class DocumentSelectionViewModel <: BaseViewModel<DocumentSelectionState> {
    private let interactor: RQESInteractor

    public init(router!: RouterHost, interactor!: RQESInteractor) {
        super(router, DocumentSelectionState())
        this.interactor = interactor
    }

    // iOS initiate(): read session doc name + qtsp; build 3 rows (certificate only once qtsp chosen).
    // The session was already initialised by DocumentSignInteractor.initiateSigning
    // (facade.initiate with the picked file) before this route was pushed — iOS
    // RouterGraph presents this screen against the same pre-initialised session.
    public func initiate(): Unit {
        let sess = interactor.getSession()
        let docName: ?String = match (sess) {
            case Some(s) => match (s.document) {
                case Some(d) => Some(d.documentName)
                case None => None
            }
            case None => None
        }
        let qtspName: ?String = match (sess) {
            case Some(s) => match (s.qtsp) {
                case Some(q) => Some(q.name)
                case None => None
            }
            case None => None
        }
        match (docName) {
            case Some(name) =>
                setState({ _ => DocumentSelectionState(
                    isLoading: false,
                    documentRow: documentRowFor(name),
                    serviceRow: serviceRowFor(qtspName),
                    certificateRow: certificateRowFor(qtspName)) })
            case None =>
                setState({ _ => DocumentSelectionState(isLoading: false, error: rqesDocNotFoundError(
                    cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }

    public func viewDocument(): Unit { router.push(RqesRoutes.documentViewer) }
    public func selectService(): Unit { router.push(RqesRoutes.serviceSelection) }
    public func selectCertificate(): Unit { router.push(RqesRoutes.credentialSelection) }
    // iOS onCancel(): exit the whole signing flow back to the dashboard document list.
    public func onCancel(): Unit { router.popTo(AppRoutes.dashboard) }

    // Strings mirror iOS LocalizableKey exactly (SelectionItemData in DocumentSelectionViewModel).
    private func documentRowFor(name: String): RqesSelectionRow {
        return RqesSelectionRow(
            step: 1,
            mainText: LocalizableStringKey.custom(name),
            overline: LocalizableStringKey.custom("Select document"),
            subtitle: LocalizableStringKey.custom("Choose a document from your device to sign electronically."),
            actionText: LocalizableStringKey.custom("View"),
            done: true,
            action: { => this.viewDocument() })
    }

    private func serviceRowFor(qtspName: ?String): RqesSelectionRow {
        return match (qtspName) {
            case Some(n) => RqesSelectionRow(
                step: 2,
                mainText: LocalizableStringKey.custom(n),
                overline: LocalizableStringKey.custom("Select signing service"),
                subtitle: LocalizableStringKey.custom("Remote Signing Service enables secure online document signing."),
                enabled: false,
                done: true)
            case None => RqesSelectionRow(
                step: 2,
                mainText: LocalizableStringKey.custom("Select signing service"),
                subtitle: LocalizableStringKey.custom("Remote Signing Service enables secure online document signing."),
                enabled: true,
                done: false,
                action: { => this.selectService() })
        }
    }

    private func certificateRowFor(qtspName: ?String): ?RqesSelectionRow {
        return match (qtspName) {
            case Some(_) => Some(RqesSelectionRow(
                step: 3,
                mainText: LocalizableStringKey.custom("Select signing certificate"),
                subtitle: LocalizableStringKey.custom("The signing certificate is used to verify your identity and is linked to your electronic signature."),
                done: false,
                action: { => this.selectCertificate() }))
            case None => None
        }
    }
}

// ═══ CredentialSelection ═════════════════════════════════════════════════════

/** iOS CredentialSelectionState. credentialInfos are kept on the VM (data, not display). */
public class CredentialSelectionState <: ViewState {
    public let isLoading: Bool
    public let credentials: Array<RqesCredentialRow>
    public let error: ?ContentErrorConfig
    public let authUrl: String

    public init(isLoading!: Bool = true, credentials!: Array<RqesCredentialRow> = Array<RqesCredentialRow>(),
                error!: ?ContentErrorConfig = None, authUrl!: String = "") {
        this.isLoading = isLoading
        this.credentials = credentials
        this.error = error
        this.authUrl = authUrl
    }
}

public class CredentialSelectionViewModel <: BaseViewModel<CredentialSelectionState> {
    private let interactor: RQESInteractor
    private var credentialInfos: Array<ListCredentialInfo> = Array<ListCredentialInfo>()

    public init(router!: RouterHost, interactor!: RQESInteractor) {
        super(router, CredentialSelectionState())
        this.interactor = interactor
    }

    // iOS initiate(): fetchCredentials; failure → error → pop.
    public func initiate(): Unit {
        match (interactor.fetchCredentials()) {
            case success(creds) =>
                credentialInfos = creds
                let rows = ArrayList<RqesCredentialRow>()
                for (c in creds) { rows.add(credentialToRow(c)) }
                setState({ _ => CredentialSelectionState(isLoading: false, credentials: rows.toArray()) })
            case failure(_) =>
                setState({ _ => CredentialSelectionState(isLoading: false, error: rqesServiceError(
                    cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }

    // iOS setCertificate(): look up the CredentialInfo by row id, save it as the chosen certificate.
    public func setCertificate(rowId: String): Unit {
        for (c in credentialInfos) {
            if (c.credentialID == rowId) {
                interactor.saveCertificate(c)
                return
            }
        }
    }

    public func nextStep(): Unit {
        openAuthorization()
    }

    // iOS openAuthorization(): openCredentialAuthrorizationURL → external browser.
    func openAuthorization(): Unit {
        try {
            let url = interactor.openCredentialAuthrorizationURL()
            setState({ s => CredentialSelectionState(isLoading: false, credentials: s.credentials, authUrl: url) })
        } catch (_: Exception) {
            // iOS openAuthorization catch → setErrorState(.genericServiceErrorMessage);
            // cancel dismisses (re-shows the list via initiate), retry = initiate.
            setState({ s => CredentialSelectionState(isLoading: false, credentials: s.credentials, error: rqesServiceError(
                cancelAction: { => this.initiate() }, retryAction: { => this.initiate() })) })
        }
    }

    // iOS openURLIfPossible failure branch → setErrorState(.unableToOpenBrowser).
    // The View reports back when RqesBrowser.open returns false (no handler / launch failed).
    public func onBrowserOpenFailed(): Unit {
        setState({ s => CredentialSelectionState(isLoading: false, credentials: s.credentials, error: rqesBrowserError(
            cancelAction: { => this.initiate() }, retryAction: { => this.initiate() })) })
    }
}

// ═══ SignedDocument (.sign) ══════════════════════════════════════════════════

/** iOS SignedDocumenState — success screen after the remote sign completes. */
public class SignedDocumentState <: ViewState {
    public let isLoading: Bool
    public let documentName: String
    public let qtspName: String
    public let error: ?ContentErrorConfig
    public let isInitialized: Bool

    public init(isLoading!: Bool = true, documentName!: String = "", qtspName!: String = "",
                error!: ?ContentErrorConfig = None, isInitialized!: Bool = false) {
        this.isLoading = isLoading
        this.documentName = documentName
        this.qtspName = qtspName
        this.error = error
        this.isInitialized = isInitialized
    }
}

public class SignedDocumentViewModel <: BaseViewModel<SignedDocumentState> {
    private let interactor: RQESInteractor
    public var pdfUrl: ?String = None

    public init(router!: RouterHost, interactor!: RQESInteractor) {
        super(router, SignedDocumentState())
        this.interactor = interactor
    }

    // iOS initiate(): sign the document (once), then read name/qtsp for the success view.
    public func initiate(): Unit {
        if (viewState.isInitialized) { return }
        try {
            let signed = interactor.signDocument()
            let sess = interactor.getSession()
            let fileUrl: ?String = match (signed) {
                case Some(d) => Some(d.fileURL)
                case None => None
            }
            match (fileUrl) {
                case Some(u) =>
                    pdfUrl = Some(u)
                    interactor.updateDocument(u)
                case None => ()
            }
            let docName = sessionDocumentName(sess)
            let qtspName = sessionQtspName(sess)
            match ((docName, qtspName)) {
                case (Some(dn), Some(qn)) =>
                    setState({ _ => SignedDocumentState(isLoading: false, documentName: dn, qtspName: qn, isInitialized: true) })
                case _ =>
                    setState({ _ => SignedDocumentState(isLoading: false, error: rqesDocNotFoundError(
                        cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
            }
        } catch (_: Exception) {
            setState({ _ => SignedDocumentState(isLoading: false, error: rqesServiceError(
                cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }

    public func viewDocument(): Unit { router.push(RqesRoutes.documentViewer) }
    // iOS SignedDocumentView Done → onCancel(): close the flow back to the dashboard.
    public func onCancel(): Unit { router.popTo(AppRoutes.dashboard) }
}

// ═══ DocumentViewer (.view) ══════════════════════════════════════════════════

/** iOS DocumentState — PDF preview (`pdfPath` empty = none). */
public class DocumentViewerState <: ViewState {
    public let isLoading: Bool
    public let pdfPath: String
    public let error: ?ContentErrorConfig

    public init(isLoading!: Bool = true, pdfPath!: String = "", error!: ?ContentErrorConfig = None) {
        this.isLoading = isLoading
        this.pdfPath = pdfPath
        this.error = error
    }
}

public class DocumentViewerViewModel <: BaseViewModel<DocumentViewerState> {
    private let interactor: RQESInteractor

    public init(router!: RouterHost, interactor!: RQESInteractor) {
        super(router, DocumentViewerState())
        this.interactor = interactor
    }

    // iOS initiate(): read the session document uri and load it for preview.
    public func initiate(): Unit {
        let uri = sessionDocumentUri(interactor.getSession())
        match (uri) {
            case Some(u) => setState({ _ => DocumentViewerState(isLoading: false, pdfPath: u) })
            case None => setState({ _ => DocumentViewerState(isLoading: false, error: rqesDocNotFoundError(
                cancelAction: { => this.router.pop() }, retryAction: { => this.initiate() })) })
        }
    }
}

// ─── shared session accessors ────────────────────────────────────────────────
func sessionDocumentName(sess: ?SessionData): ?String {
    return match (sess) {
        case Some(s) => match (s.document) { case Some(d) => Some(d.documentName); case None => None }
        case None => None
    }
}
func sessionQtspName(sess: ?SessionData): ?String {
    return match (sess) {
        case Some(s) => match (s.qtsp) { case Some(q) => Some(q.name); case None => None }
        case None => None
    }
}
func sessionDocumentUri(sess: ?SessionData): ?String {
    return match (sess) {
        case Some(s) => match (s.document) { case Some(d) => Some(d.uri); case None => None }
        case None => None
    }
}
