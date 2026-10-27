/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-issuance
 * module (UI/Document/Add/AddDocumentViewModel.swift,
 * UI/Document/Offer/DocumentOfferViewModel.swift,
 * UI/Document/Code/OfferCodeViewModel.swift) to Cangjie.
 *
 * ViewModels extend eudi_logic_ui.BaseViewModel<S> exactly like the delivered
 * features (StartupViewModel / DashboardViewModel). Each holds an immutable
 * ViewState reduced via setState; views subscribe through onStateChange and
 * marshal @State writes with spawn(UIThread). No ArkUI import here (UI-free
 * seam, avoids bare-None pollution).
 *
 * Blocking engine calls run on a background thread (the view wraps the VM call
 * in spawn{}); the VM itself stays synchronous and pushes routes / sets state.
 */
package eudi_feature_issuance

import std.collection.ArrayList
import std.sync.Mutex
import ohos.hilog.Hilog
import std.time.*
import ohos.base.*
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, NavArgs,
    RouteConfigArgs, UIConfigType, TwoWayNavigationType, ThreeWayNavigationType,
    DeepLinkNavigationType, UIConfigGeneric, uiColor, RelyingPartyRegistrationData
}
import eudi_logic_core.{DocumentTypeIdentifier, NotificationCenter, NotificationName, IssuerRegistration}
import eudi_feature_common.{
    IssuanceFlow, IssuanceFlowUiConfig, IssuanceCodeUiConfig,
    SuccessUIConfig, SuccessTitle, SuccessButton, SuccessButtonStyle, SuccessVisualKind,
    issuerToRegistrationData
}
import eudi_logic_resources.{LocalizableStringKey, ThemeManager}

// ─── AddDocument ─────────────────────────────────────────────────────────────

/** Mirrors iOS `AddDocumentViewState`. */
public class AddDocumentState <: ViewState {
    public let buckets: ArrayList<AddDocumentBucket>
    public let isLoading: Bool
    public let hasError: Bool
    public let errorMessage: String
    // Browser-authorization handoff: when non-empty the view shows the Web
    // component loading this URL (iOS dynamic-issuance via presentation).
    public let authUrl: String
    public let flow: IssuanceFlow
    /** Shows the blocking "Issuance blocked" alert (iOS
     *  `isTrustBlockedAlertShowing`). Mutually exclusive with `hasError`:
     *  an unverifiable issuer is not a retryable error. */
    public let isTrustBlockedAlertShowing: Bool
    /** Shows the blocking "Issuance blocked" registration alert (iOS
     *  `isRegistrationBlockedAlertShowing`): the provider is not registered
     *  for this issuance — refused before anything was issued. */
    public let isRegistrationBlockedAlertShowing: Bool

    public init(
        buckets!: ArrayList<AddDocumentBucket> = ArrayList<AddDocumentBucket>(),
        isLoading!: Bool = false,
        hasError!: Bool = false,
        errorMessage!: String = "",
        authUrl!: String = "",
        flow!: IssuanceFlow = IssuanceFlow.NoDocument,
        isTrustBlockedAlertShowing!: Bool = false,
        isRegistrationBlockedAlertShowing!: Bool = false
    ) {
        this.buckets = buckets
        this.isLoading = isLoading
        this.hasError = hasError
        this.errorMessage = errorMessage
        this.authUrl = authUrl
        this.flow = flow
        this.isTrustBlockedAlertShowing = isTrustBlockedAlertShowing
        this.isRegistrationBlockedAlertShowing = isRegistrationBlockedAlertShowing
    }
}

/** Mirrors iOS `AddDocumentViewModel`. */
public class AddDocumentViewModel <: BaseViewModel<AddDocumentState> {
    private let interactor: AddDocumentInteractor
    /** The selected row is retained while its browser authorization is active.
     *  A failed issuer session must be retried by creating a fresh PAR/session,
     *  not by merely reloading the document catalogue. */
    private var lastIssuedItem: ?AddDocumentItem = None
    /** Serialises auth-code resume: duplicate Web intercepts must not race
     *  resumePendingIssuance / NavPathStack push (that snap the app to Startup). */
    private let resumeLock = Mutex()
    private var resumeHandled: Bool = false

    public init(router!: RouterHost, interactor!: AddDocumentInteractor, flow!: IssuanceFlow) {
        super(router, AddDocumentState(isLoading: true, flow: flow))
        this.interactor = interactor
    }

    /** Mirrors iOS `initialize()` (sans deep-link / resume-on-launch which here
     *  is driven by the explicit Web-view redirect callback). */
    public func initialize(): Unit {
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: true, flow: s.flow) })
        let flow = this.viewState.flow
        let result = this.interactor.fetchScopedDocuments(flow)
        if (result.isSuccess) {
            this.setState({ s => AddDocumentState(buckets: result.buckets, isLoading: false, flow: s.flow) })
        } else if (result.isIssuerNotTrusted) {
            // iOS `.issuerNotTrusted`: empty the cell list (no error page) and
            // raise the blocking trust alert.
            this.setState({ s =>
                AddDocumentState(isLoading: false, flow: s.flow, isTrustBlockedAlertShowing: true)
            })
        } else {
            this.setState({ s =>
                AddDocumentState(isLoading: false, hasError: true, errorMessage: result.errorMessage, flow: s.flow)
            })
        }
    }

    /** Mirrors iOS `onClick` → `issueDocument`. Runs the blocking engine call;
     *  the caller (view) invokes this inside spawn{}. */
    public func issueDocument(item: AddDocumentItem): Unit {
        this.lastIssuedItem = Some(item)
        synchronized(this.resumeLock) { this.resumeHandled = false }
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: true, flow: s.flow) })
        let result = this.interactor.issueDocument(item.issuerId, item.configIds, item.docTypeIdentifier)
        // Prefetch success summaries on this background thread — never decode
        // SD-JWT claims on the UI thread (Error there aborts navigation).
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            case IssueSuccess =>
                match (this.fetchSummaries(result.successIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Runs on the caller's background spawn{} — marshal navigation to UI thread.
        this.router.runOnUi({ =>
            match (result.kind) {
                case IssueSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            AddDocumentState(buckets: s.buckets, isLoading: false, hasError: true,
                                errorMessage: unableFetchDocumentText(), flow: s.flow)
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, this.successDeepLink())
                    }
                case IssueDynamic =>
                    // open the in-app Web component on this URL
                    this.setState({ s =>
                        AddDocumentState(buckets: s.buckets, isLoading: false, authUrl: result.authUrl, flow: s.flow)
                    })
                case IssueDeferred => this.routeToDeferredSuccess(result.deferredName, result.deferredIssuer)
                case IssueFailure =>
                    this.setState({ s =>
                        AddDocumentState(buckets: s.buckets, isLoading: false, hasError: true, errorMessage: result.errorMessage, flow: s.flow)
                    })
                case IssueIssuerNotTrusted => this.showTrustBlockedAlert()
                case IssueRegistrationBlocked => this.showRegistrationBlockedAlert()
            }
        })
    }

    /** Web-view redirect captured → resume issuance (blocking; view wraps in spawn). */
    public func onAuthorizationRedirect(redirectUrl: String): Unit {
        var accepted = false
        synchronized(this.resumeLock) {
            if (!this.resumeHandled) {
                this.resumeHandled = true
                accepted = true
            }
        }
        if (!accepted) {
            Hilog.info(0, "VCI-DEBUG", "AddDoc resume ignored (already handled) urlLen=${redirectUrl.size}")
            return
        }
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: true, flow: s.flow) })
        let result = this.interactor.resumeDynamicIssuance(redirectUrl)
        // Decode on the background spawn before touching NavPathStack.
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            case ResumeSuccess =>
                match (this.fetchSummaries(result.docIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Navigation must run on the UI thread — this method executes on the
        // Web-view's background spawn{}; pushing off the UI thread corrupts the
        // NavPathStack and snaps the app to the splash root.
        this.router.runOnUi({ =>
            match (result.kind) {
                case ResumeSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            AddDocumentState(buckets: s.buckets, isLoading: false, hasError: true,
                                errorMessage: unableFetchDocumentText(), flow: s.flow)
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, this.successDeepLink())
                    }
                // The Cangjie in-app Web flow resumes here (iOS runs the browser
                // inside issueDocument); the resume result carries the deferred
                // doc/issuer names so the caption matches iOS.
                case ResumeDeferred => this.routeToDeferredSuccess(result.deferredName, result.deferredIssuer)
                case ResumeNoPending =>
                    this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: false, flow: s.flow) })
                case ResumeFailure =>
                    this.setState({ s =>
                        AddDocumentState(buckets: s.buckets, isLoading: false, hasError: true, errorMessage: result.errorMessage, flow: s.flow)
                    })
                case ResumeIssuerNotTrusted => this.showTrustBlockedAlert()
            }
        })
    }

    public func dismissError(): Unit {
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: false, flow: s.flow) })
    }

    /** iOS clears the generic error and raises the blocking alert instead. */
    public func showTrustBlockedAlert(): Unit {
        this.setState({ s =>
            AddDocumentState(
                buckets: s.buckets, isLoading: false, flow: s.flow,
                isTrustBlockedAlertShowing: true
            )
        })
    }

    /** Mirrors iOS `onTrustBlockedClose()`: dismiss, and pop back only for the
     *  ExtraDocument flow (the NoDocument onboarding screen has nowhere to go). */
    public func onTrustBlockedClose(): Unit {
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: false, flow: s.flow) })
        match (this.viewState.flow) {
            case ExtraDocument(_) => this.router.pop()
            case NoDocument => ()
        }
    }

    /** iOS `.registrationBlocked`: stop the cell spinner, clear any error and
     *  raise the blocking registration alert. */
    public func showRegistrationBlockedAlert(): Unit {
        this.setState({ s =>
            AddDocumentState(
                buckets: s.buckets, isLoading: false, flow: s.flow,
                isRegistrationBlockedAlertShowing: true
            )
        })
    }

    /** iOS registration alert Close: just dismiss (no pop). */
    public func dismissRegistrationBlockedAlert(): Unit {
        this.setState({ s => AddDocumentState(buckets: s.buckets, isLoading: false, flow: s.flow) })
    }

    /** Converts a browser/network failure into the normal retryable error page. */
    public func authorizationFailed(message: String): Unit {
        this.setState({ s =>
            AddDocumentState(
                buckets: s.buckets,
                isLoading: false,
                hasError: true,
                errorMessage: message,
                flow: s.flow
            )
        })
    }

    /** Retry the failed authorization from its beginning. The old authorization
     *  request cannot be resumed when the issuer returned `no code issued`;
     *  issueDocument creates a new DPoP/PAR authorization session. */
    public func retryLastIssue(): Unit {
        match (this.lastIssuedItem) {
            case Some(item) => this.issueDocument(item)
            case None => this.initialize()
        }
    }

    public func pop(): Unit {
        this.router.pop()
    }

    private func successDeepLink(): DeepLinkNavigationType {
        match (this.viewState.flow) {
            case NoDocument => DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard)
            case ExtraDocument(_) => DeepLinkNavigationType.DeepLinkPop(AppRoutes.dashboard, false)
        }
    }

    /**
     * Fetch success-screen summaries without letting decode failures abort the
     * caller. Credential is already stored — empty fields still get a success
     * screen. Must run off the UI thread.
     */
    /**
     * None = the store had nothing to show for these ids. iOS maps that to
     * `.failure(unableFetchDocument)` and raises an error, so the caller must not
     * navigate to a success screen with placeholder rows.
     */
    private func fetchSummaries(docIds: Array<String>): ?ArrayList<IssuedDocumentSummary> {
        try {
            return Some(this.interactor.fetchStoredDocuments(docIds))
        } catch (e: Exception) {
            Hilog.warn(0, "VCI-DEBUG", "AddDoc fetchStoredDocuments failed: ${e.message}")
            return None
        }
    }

    /**
     * Deferred issuance keeps the generic in-progress success (no document data
     * exists yet to render the document-details layout), mirroring iOS
     * AddDocumentViewModel.onDeferredSuccess: title "In progress" (pending
     * color), scoped deferred caption picked by docName/issuer availability
     * (branch order replicated 1:1 from iOS), and the bundled
     * document-success-pending illustration.
     */
    private func routeToDeferredSuccess(docName: String, issuerName: String): Unit {
        let subtitle = if (docName.isEmpty()) {
            LocalizableStringKey.scopedIssuanceSuccessDeferredCaptionDocName([docName])
        } else if (!docName.isEmpty() && !issuerName.isEmpty()) {
            LocalizableStringKey.scopedIssuanceSuccessDeferredCaptionDocNameAndIssuer([docName, issuerName])
        } else {
            LocalizableStringKey.scopedIssuanceSuccessDeferredCaption
        }
        pushGenericSuccess(
            SuccessUIConfig(
                title: SuccessTitle(value: LocalizableStringKey.inProgress, color: pendingColor()),
                subtitle: subtitle,
                buttons: [
                    SuccessButton(
                        title: LocalizableStringKey.okButton,
                        style: SuccessButtonStyle.StylePrimary,
                        navigationType: this.successDeepLink()
                    )
                ],
                visualKind: SuccessVisualKind.CustomIcon(ThemeManager.shared.image.documentSuccessPending, pendingColor())
            )
        )
    }

    private func pushGenericSuccess(config: SuccessUIConfig): Unit {
        NavArgs.shared.set(AppRoutes.genericSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.genericSuccess)
    }

    private func pushDocumentSuccess(
        summaries: ArrayList<IssuedDocumentSummary>,
        navigation: DeepLinkNavigationType
    ): Unit {
        // Idempotent: a double redirect must not stack two success pages
        // (that desyncs pathNames vs NavPathStack and Done→splash).
        if (this.router.isScreenForeground(AppRoutes.issuanceSuccess)) {
            Hilog.warn(0, "VCI-DEBUG", "skip duplicate issuanceSuccess push")
            return
        }
        var relyingParty = ""
        var issuerLogoUrl = ""
        if (summaries.size > 0) {
            relyingParty = summaries[0].issuer
            issuerLogoUrl = summaries[0].issuerLogoUrl
        }
        let config = DocumentIssuanceSuccessUIConfig(
            relyingParty: relyingParty,
            issuerLogoUrl: issuerLogoUrl,
            documents: summaries,
            successNavigation: navigation
        )
        NavArgs.shared.set(AppRoutes.issuanceSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.issuanceSuccess)
    }
}

// ─── DocumentOffer ───────────────────────────────────────────────────────────

/** Mirrors iOS `DocumentOfferViewState`. */
public class DocumentOfferState <: ViewState {
    public let isLoading: Bool
    public let issuerName: String
    public let issuerLogoUrl: String
    public let offers: ArrayList<OfferItem>
    public let allowIssue: Bool
    public let hasError: Bool
    public let errorMessage: String
    public let authUrl: String
    /** Shows the blocking "Issuance blocked" alert (iOS
     *  `isTrustBlockedAlertShowing`). */
    public let isTrustBlockedAlertShowing: Bool
    /** Shows the blocking registration alert (iOS
     *  `isRegistrationBlockedAlertShowing`): the provider is not registered
     *  for this issuance — refused before anything was issued. */
    public let isRegistrationBlockedAlertShowing: Bool
    /** iOS `initialized`: the offer resolved (success or failure). While false
     *  and not loading the view renders nothing (iOS `Color.clear`). */
    public let initialized: Bool
    /** iOS `issuerRegistration` — the RelyingPartyRegistrationView header data
     *  derived from the offer's issuer-registration verdict (replaces the old
     *  ContentHeaderView config). */
    public let issuerRegistration: ?RelyingPartyRegistrationData

    public init(
        isLoading!: Bool = true,
        issuerName!: String = "",
        issuerLogoUrl!: String = "",
        offers!: ArrayList<OfferItem> = ArrayList<OfferItem>(),
        allowIssue!: Bool = false,
        hasError!: Bool = false,
        errorMessage!: String = "",
        authUrl!: String = "",
        isTrustBlockedAlertShowing!: Bool = false,
        isRegistrationBlockedAlertShowing!: Bool = false,
        initialized!: Bool = false,
        issuerRegistration!: ?RelyingPartyRegistrationData = None
    ) {
        this.isLoading = isLoading
        this.issuerName = issuerName
        this.issuerLogoUrl = issuerLogoUrl
        this.offers = offers
        this.allowIssue = allowIssue
        this.hasError = hasError
        this.errorMessage = errorMessage
        this.authUrl = authUrl
        this.isTrustBlockedAlertShowing = isTrustBlockedAlertShowing
        this.isRegistrationBlockedAlertShowing = isRegistrationBlockedAlertShowing
        this.initialized = initialized
        this.issuerRegistration = issuerRegistration
    }
}

/** Mirrors iOS `DocumentOfferViewModel`. */
public class DocumentOfferViewModel <: BaseViewModel<DocumentOfferState> {
    private let interactor: DocumentOfferInteractor
    private var offerUri: String
    // tx-code requirements remembered from processOfferRequest.
    private var txCodeRequired: Bool = false
    private var txCodeLength: Int64 = 0
    private var resolvedIssuerName: String = ""
    private let resumeLock = Mutex()
    private var resumeHandled: Bool = false

    // The foreground offer screen (iOS notificationActions equivalent): a new
    // credential-offer deep link arriving while this screen is up posts
    // CredentialOfferNew, and the ACTIVE view-model reloads in place instead of
    // the router re-pushing (which flashed the old page during the transition).
    private static var activeOffer: ?DocumentOfferViewModel = None
    private static var observerRegistered: Bool = false

    public init(router!: RouterHost, interactor!: DocumentOfferInteractor, offerUri!: String) {
        super(router, DocumentOfferState(isLoading: true))
        this.interactor = interactor
        this.offerUri = offerUri
        Hilog.info(0, "VCI-DEBUG", "OfferVM init uriLen=${offerUri.size}")
        DocumentOfferViewModel.activeOffer = Some(this)
        if (!DocumentOfferViewModel.observerRegistered) {
            DocumentOfferViewModel.observerRegistered = true
            NotificationCenter.addObserver(NotificationName.CredentialOfferNew) { n =>
                match ((DocumentOfferViewModel.activeOffer, n.map)) {
                    case (Some(vm), Some(m)) =>
                        if (m.contains("uri")) {
                            vm.reloadWithUri(m["uri"])
                        }
                    case _ => ()
                }
            }
        }
    }

    /** Mirrors iOS handleNotification(with:): swap in the new offer uri and
     *  reload in place (loading state first, resolve on a background thread). */
    public func reloadWithUri(uri: String): Unit {
        this.offerUri = uri
        synchronized(this.resumeLock) { this.resumeHandled = false }
        this.setState({ _ => DocumentOfferState(isLoading: true) })
        spawn {
            this.initialize()
        }
    }

    /** Mirrors iOS `initialize()`. Blocking; view wraps in spawn. */
    public func initialize(): Unit {
        var attempt = this.interactor.processOfferRequest(this.offerUri)
        if (!attempt.isSuccess && !attempt.isRegistrationBlocked) {
            // One silent retry before surfacing the error page: the emulator's
            // first DNS lookup for a fresh issuer host intermittently fails
            // (iOS shows loading throughout; flashing an error that a retry
            // then replaces reads as a glitch). A registration refusal is not
            // transient — no retry.
            sleep(Duration.second)
            attempt = this.interactor.processOfferRequest(this.offerUri)
        }
        // Immutable rebind — Cangjie lambdas may not capture mutable locals.
        let request = attempt
        if (request.isSuccess) {
            this.txCodeRequired = request.txCodeRequired
            this.txCodeLength = request.txCodeLength
            this.resolvedIssuerName = request.issuerName
            // iOS: the issuer-registration verdict becomes the
            // RelyingPartyRegistrationView header data (name/logo from the offer).
            let issuerLogo: ?String = if (request.issuerLogoUrl.isEmpty()) {
                None
            } else {
                Some(request.issuerLogoUrl)
            }
            let registrationData = issuerToRegistrationData(
                issuerRegistration: request.issuerRegistration,
                issuerName: request.issuerName,
                issuerLogo: issuerLogo
            )
            this.setState({ _ =>
                DocumentOfferState(
                    isLoading: false,
                    issuerName: request.issuerName,
                    issuerLogoUrl: request.issuerLogoUrl,
                    offers: request.offers,
                    allowIssue: request.offers.size > 0,
                    initialized: true,
                    issuerRegistration: Some(registrationData)
                )
            })
        } else if (request.isRegistrationBlocked) {
            // iOS `.registrationBlocked`: reset to the empty offer model
            // (initialized stays false → Color.clear behind the alert), forbid
            // issuing and raise the blocking registration alert.
            this.setState({ _ =>
                DocumentOfferState(
                    isLoading: false,
                    allowIssue: false,
                    initialized: false,
                    isRegistrationBlockedAlertShowing: true
                )
            })
        } else {
            Hilog.info(0, "VCI-DEBUG", "OfferVM initialize FAILED uriLen=${this.offerUri.size} err=${request.errorMessage}")
            this.setState({ _ =>
                DocumentOfferState(
                    isLoading: false, hasError: true, errorMessage: request.errorMessage,
                    allowIssue: false, initialized: true
                )
            })
        }
    }

    /** Mirrors iOS `onIssueDocuments()`. When a tx-code is required, route to the
     *  code screen; otherwise issue directly. */
    public func onIssueDocuments(): Unit {
        if (this.txCodeRequired) {
            let config = IssuanceCodeUiConfig(
                offerUri: this.offerUri,
                issuerName: this.resolvedIssuerName,
                txCodeLength: this.txCodeLength,
                successNavigation: TwoWayNavigationType.NavPush(AppRoutes.dashboard),
                navigationCancelType: ThreeWayNavigationType.ThreeWayPop
            )
            NavArgs.shared.set(AppRoutes.issuanceCode, RouteConfigArgs(config))
            this.router.push(AppRoutes.issuanceCode)
            return
        }

        synchronized(this.resumeLock) { this.resumeHandled = false }
        this.setState({ s =>
            DocumentOfferState(
                isLoading: true, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
        let result = this.interactor.issueDocuments(this.offerUri, Option<String>.None)
        this.handleOfferResult(result)
    }

    /** Web-view redirect captured → resume (blocking; view wraps in spawn). */
    public func onAuthorizationRedirect(redirectUrl: String): Unit {
        var accepted = false
        synchronized(this.resumeLock) {
            if (!this.resumeHandled) {
                this.resumeHandled = true
                accepted = true
            }
        }
        if (!accepted) {
            Hilog.info(0, "VCI-DEBUG", "OfferVM resume ignored (already handled)")
            return
        }
        this.setState({ s =>
            DocumentOfferState(
                isLoading: true, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
        let result = this.interactor.resumeDynamicIssuance(redirectUrl)
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            case ResumeSuccess =>
                match (this.fetchSummaries(result.docIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Navigation must run on the UI thread — see AddDocumentViewModel note.
        this.router.runOnUi({ =>
            match (result.kind) {
                case ResumeSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            DocumentOfferState(isLoading: false, hasError: true,
                                errorMessage: unableFetchDocumentText(),
                                issuerName: s.issuerName, offers: s.offers,
                                initialized: s.initialized, issuerRegistration: s.issuerRegistration)
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard))
                    }
                case ResumeDeferred => this.routeToDeferredSuccess()
                case ResumeNoPending =>
                    this.setState({ s =>
                        DocumentOfferState(
                            isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                            offers: s.offers, allowIssue: s.allowIssue,
                            initialized: s.initialized, issuerRegistration: s.issuerRegistration
                        )
                    })
                case ResumeFailure =>
                    this.setState({ s =>
                        DocumentOfferState(isLoading: false, hasError: true, errorMessage: result.errorMessage,
                            issuerName: s.issuerName, offers: s.offers,
                            initialized: s.initialized, issuerRegistration: s.issuerRegistration)
                    })
                case ResumeIssuerNotTrusted => this.showTrustBlockedAlert()
            }
        })
    }

    private func handleOfferResult(result: OfferResult): Unit {
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            // Partial success carries ids just like full success (iOS fetches for both).
            case OfferSuccess | OfferPartialSuccess =>
                match (this.fetchSummaries(result.documentIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Runs on the caller's background spawn{} — marshal navigation to UI thread.
        this.router.runOnUi({ =>
            match (result.kind) {
                // iOS routes .partialSuccess to the same success screen as .success.
                case OfferSuccess | OfferPartialSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            DocumentOfferState(isLoading: false, hasError: true,
                                errorMessage: unableFetchDocumentText(),
                                issuerName: s.issuerName, offers: s.offers,
                                initialized: s.initialized, issuerRegistration: s.issuerRegistration)
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard))
                    }
                case OfferDynamic =>
                    synchronized(this.resumeLock) { this.resumeHandled = false }
                    this.setState({ s =>
                        DocumentOfferState(
                            isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                            offers: s.offers, allowIssue: s.allowIssue, authUrl: result.authUrl,
                            initialized: s.initialized, issuerRegistration: s.issuerRegistration
                        )
                    })
                case OfferDeferred => this.routeToDeferredSuccess()
                case OfferFailure =>
                    this.setState({ s =>
                        DocumentOfferState(isLoading: false, hasError: true, errorMessage: result.errorMessage,
                            issuerName: s.issuerName, offers: s.offers,
                            initialized: s.initialized, issuerRegistration: s.issuerRegistration)
                    })
                case OfferIssuerNotTrusted => this.showTrustBlockedAlert()
            }
        })
    }

    /** iOS clears the generic error and raises the blocking alert instead. */
    public func showTrustBlockedAlert(): Unit {
        this.setState({ s =>
            DocumentOfferState(
                isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue, isTrustBlockedAlertShowing: true,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
    }

    /** Mirrors iOS `onTrustBlockedClose()`: dismiss + pop. */
    public func onTrustBlockedClose(): Unit {
        this.setState({ s =>
            DocumentOfferState(
                isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
        this.onPop()
    }

    /** Mirrors iOS `onRegistrationBlockedClose()`: dismiss + pop. */
    public func onRegistrationBlockedClose(): Unit {
        this.setState({ s =>
            DocumentOfferState(
                isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
        this.onPop()
    }

    public func onPop(): Unit {
        this.router.pop()
    }

    public func dismissError(): Unit {
        this.setState({ s =>
            DocumentOfferState(
                isLoading: false, issuerName: s.issuerName, issuerLogoUrl: s.issuerLogoUrl,
                offers: s.offers, allowIssue: s.allowIssue,
                initialized: s.initialized, issuerRegistration: s.issuerRegistration
            )
        })
    }

    /**
     * None = the store had nothing to show for these ids. iOS maps that to
     * `.failure(unableFetchDocument)` and raises an error, so the caller must not
     * navigate to a success screen with placeholder rows.
     */
    private func fetchSummaries(docIds: Array<String>): ?ArrayList<IssuedDocumentSummary> {
        try {
            return Some(this.interactor.fetchStoredDocuments(docIds))
        } catch (e: Exception) {
            Hilog.warn(0, "VCI-DEBUG", "OfferVM fetchStoredDocuments failed: ${e.message}")
            return None
        }
    }

    private func routeToDeferredSuccess(): Unit {
        pushGenericSuccess(
            SuccessUIConfig(
                title: SuccessTitle(value: LocalizableStringKey.inProgress, color: pendingColor()),
                // iOS DocumentOfferInteractor deferred route: caption
                // .issuanceSuccessDeferredCaption([issuerName]).
                subtitle: LocalizableStringKey.issuanceSuccessDeferredCaption([this.viewState.issuerName]),
                buttons: [
                    SuccessButton(
                        title: LocalizableStringKey.okButton,
                        style: SuccessButtonStyle.StylePrimary,
                        navigationType: DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard)
                    )
                ],
                visualKind: SuccessVisualKind.CustomIcon(ThemeManager.shared.image.documentSuccessPending, pendingColor())
            )
        )
    }

    private func pushGenericSuccess(config: SuccessUIConfig): Unit {
        NavArgs.shared.set(AppRoutes.genericSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.genericSuccess)
    }

    private func pushDocumentSuccess(
        summaries: ArrayList<IssuedDocumentSummary>,
        navigation: DeepLinkNavigationType
    ): Unit {
        // Idempotent: a double redirect must not stack two success pages
        // (that desyncs pathNames vs NavPathStack and Done→splash).
        if (this.router.isScreenForeground(AppRoutes.issuanceSuccess)) {
            Hilog.warn(0, "VCI-DEBUG", "skip duplicate issuanceSuccess push")
            return
        }
        var relyingParty = ""
        var issuerLogoUrl = ""
        if (summaries.size > 0) {
            relyingParty = summaries[0].issuer
            issuerLogoUrl = summaries[0].issuerLogoUrl
        }
        let config = DocumentIssuanceSuccessUIConfig(
            relyingParty: relyingParty,
            issuerLogoUrl: issuerLogoUrl,
            documents: summaries,
            successNavigation: navigation
        )
        NavArgs.shared.set(AppRoutes.issuanceSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.issuanceSuccess)
    }
}

// ─── OfferCode ───────────────────────────────────────────────────────────────

/** Mirrors iOS `OfferCodeViewState`. */
public class OfferCodeState <: ViewState {
    public let isLoading: Bool
    public let issuerName: String
    public let txCodeLength: Int64
    public let hasError: Bool
    public let errorMessage: String
    public let authUrl: String
    /** Shows the blocking "Issuance blocked" alert (iOS
     *  `isTrustBlockedAlertShowing`). */
    public let isTrustBlockedAlertShowing: Bool

    public init(
        isLoading!: Bool = false,
        issuerName!: String = "",
        txCodeLength!: Int64 = 0,
        hasError!: Bool = false,
        errorMessage!: String = "",
        authUrl!: String = "",
        isTrustBlockedAlertShowing!: Bool = false
    ) {
        this.isLoading = isLoading
        this.issuerName = issuerName
        this.txCodeLength = txCodeLength
        this.hasError = hasError
        this.errorMessage = errorMessage
        this.authUrl = authUrl
        this.isTrustBlockedAlertShowing = isTrustBlockedAlertShowing
    }
}

/** Mirrors iOS `OfferCodeViewModel`. */
public class OfferCodeViewModel <: BaseViewModel<OfferCodeState> {
    private let interactor: DocumentOfferInteractor
    private let offerUri: String
    private let issuerName: String
    private let txCodeLength: Int64
    private let resumeLock = Mutex()
    private var resumeHandled: Bool = false

    public init(
        router!: RouterHost,
        interactor!: DocumentOfferInteractor,
        config!: IssuanceCodeUiConfig
    ) {
        super(router, OfferCodeState(issuerName: config.issuerName, txCodeLength: config.txCodeLength))
        this.interactor = interactor
        this.offerUri = config.offerUri
        this.issuerName = config.issuerName
        this.txCodeLength = config.txCodeLength
    }

    /** Mirrors iOS `processCode`: when the entered code reaches the expected
     *  length, issue. Blocking; view wraps in spawn. */
    public func submitCode(code: String): Unit {
        if (Int64(code.size) != this.txCodeLength) {
            return
        }
        synchronized(this.resumeLock) { this.resumeHandled = false }
        this.setState({ s => OfferCodeState(isLoading: true, issuerName: s.issuerName, txCodeLength: s.txCodeLength) })
        let result = this.interactor.issueDocuments(this.offerUri, Some(code))
        this.handleOfferResult(result)
    }

    public func onAuthorizationRedirect(redirectUrl: String): Unit {
        var accepted = false
        synchronized(this.resumeLock) {
            if (!this.resumeHandled) {
                this.resumeHandled = true
                accepted = true
            }
        }
        if (!accepted) {
            Hilog.info(0, "VCI-DEBUG", "OfferCode resume ignored (already handled)")
            return
        }
        this.setState({ s => OfferCodeState(isLoading: true, issuerName: s.issuerName, txCodeLength: s.txCodeLength) })
        let result = this.interactor.resumeDynamicIssuance(redirectUrl)
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            case ResumeSuccess =>
                match (this.fetchSummaries(result.docIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Navigation must run on the UI thread — see AddDocumentViewModel note.
        this.router.runOnUi({ =>
            match (result.kind) {
                case ResumeSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength,
                                hasError: true, errorMessage: unableFetchDocumentText())
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard))
                    }
                case ResumeDeferred => this.routeToDeferredSuccess()
                case ResumeNoPending =>
                    this.setState({ s => OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength) })
                case ResumeFailure =>
                    this.setState({ s =>
                        OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength,
                            hasError: true, errorMessage: result.errorMessage)
                    })
                case ResumeIssuerNotTrusted => this.showTrustBlockedAlert()
            }
        })
    }

    public func onPop(): Unit {
        this.router.pop()
    }

    public func dismissError(): Unit {
        this.setState({ s => OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength) })
    }

    /** iOS clears the generic error and raises the blocking alert instead. */
    public func showTrustBlockedAlert(): Unit {
        this.setState({ s =>
            OfferCodeState(
                isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength,
                isTrustBlockedAlertShowing: true
            )
        })
    }

    public func dismissTrustBlockedAlert(): Unit {
        this.setState({ s => OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength) })
    }

    private func handleOfferResult(result: OfferResult): Unit {
        var successSummaries = ArrayList<IssuedDocumentSummary>()
        var fetchFailed = false
        match (result.kind) {
            // Partial success carries ids just like full success (iOS fetches for both).
            case OfferSuccess | OfferPartialSuccess =>
                match (this.fetchSummaries(result.documentIds)) {
                    case Some(list) => successSummaries = list
                    case None => fetchFailed = true
                }
            case _ => ()
        }
        let uiSummaries = successSummaries
        // Copied to an immutable binding for the UI-thread closure below.
        let summariesMissing = fetchFailed
        // Runs on the caller's background spawn{} — marshal navigation to UI thread.
        this.router.runOnUi({ =>
            match (result.kind) {
                // iOS routes .partialSuccess to the same success screen as .success.
                case OfferSuccess | OfferPartialSuccess =>
                    // Nothing retrievable → iOS raises the error instead of showing
                    // a success screen built from placeholder rows.
                    if (summariesMissing) {
                        this.setState({ s =>
                            OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength,
                                hasError: true, errorMessage: unableFetchDocumentText())
                        })
                    } else {
                        this.pushDocumentSuccess(uiSummaries, DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard))
                    }
                case OfferDynamic =>
                    synchronized(this.resumeLock) { this.resumeHandled = false }
                    this.setState({ s =>
                        OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength, authUrl: result.authUrl)
                    })
                case OfferDeferred => this.routeToDeferredSuccess()
                case OfferFailure =>
                    this.setState({ s =>
                        OfferCodeState(isLoading: false, issuerName: s.issuerName, txCodeLength: s.txCodeLength,
                            hasError: true, errorMessage: result.errorMessage)
                    })
                case OfferIssuerNotTrusted => this.showTrustBlockedAlert()
            }
        })
    }

    /**
     * None = the store had nothing to show for these ids. iOS maps that to
     * `.failure(unableFetchDocument)` and raises an error, so the caller must not
     * navigate to a success screen with placeholder rows.
     */
    private func fetchSummaries(docIds: Array<String>): ?ArrayList<IssuedDocumentSummary> {
        try {
            return Some(this.interactor.fetchStoredDocuments(docIds))
        } catch (e: Exception) {
            Hilog.warn(0, "VCI-DEBUG", "OfferCode fetchStoredDocuments failed: ${e.message}")
            return None
        }
    }

    private func routeToDeferredSuccess(): Unit {
        pushGenericSuccess(
            SuccessUIConfig(
                title: SuccessTitle(value: LocalizableStringKey.inProgress, color: pendingColor()),
                // iOS DocumentOfferInteractor deferred route: caption
                // .issuanceSuccessDeferredCaption([issuerName]).
                subtitle: LocalizableStringKey.issuanceSuccessDeferredCaption([this.viewState.issuerName]),
                buttons: [
                    SuccessButton(
                        title: LocalizableStringKey.okButton,
                        style: SuccessButtonStyle.StylePrimary,
                        navigationType: DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard)
                    )
                ],
                visualKind: SuccessVisualKind.CustomIcon(ThemeManager.shared.image.documentSuccessPending, pendingColor())
            )
        )
    }

    private func pushGenericSuccess(config: SuccessUIConfig): Unit {
        NavArgs.shared.set(AppRoutes.genericSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.genericSuccess)
    }

    private func pushDocumentSuccess(
        summaries: ArrayList<IssuedDocumentSummary>,
        navigation: DeepLinkNavigationType
    ): Unit {
        // Idempotent: a double redirect must not stack two success pages
        // (that desyncs pathNames vs NavPathStack and Done→splash).
        if (this.router.isScreenForeground(AppRoutes.issuanceSuccess)) {
            Hilog.warn(0, "VCI-DEBUG", "skip duplicate issuanceSuccess push")
            return
        }
        var relyingParty = ""
        var issuerLogoUrl = ""
        if (summaries.size > 0) {
            relyingParty = summaries[0].issuer
            issuerLogoUrl = summaries[0].issuerLogoUrl
        }
        let config = DocumentIssuanceSuccessUIConfig(
            relyingParty: relyingParty,
            issuerLogoUrl: issuerLogoUrl,
            documents: summaries,
            successNavigation: navigation
        )
        NavArgs.shared.set(AppRoutes.issuanceSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.issuanceSuccess)
    }
}

// ─── shared ──────────────────────────────────────────────────────────────────

func pendingColor(): Color {
    uiColor(ThemeManager.shared.color.pending)
}
