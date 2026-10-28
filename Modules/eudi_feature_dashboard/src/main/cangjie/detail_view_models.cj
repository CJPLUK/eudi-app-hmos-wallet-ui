/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * detail view models (UI/Detail/Document/DocumentDetailsViewModel.swift,
 * UI/Detail/Transaction/TransactionDetailsViewModel.swift) to Cangjie.
 *
 * UI-free VMs: blocking interactor calls (WalletKitController) are wrapped in
 * spawn{} by the views; @State writebacks marshalled with spawn(UIThread).
 */
package eudi_feature_dashboard

import eudi_logic_ui.{BaseViewModel, ViewState, RouterHost, AppRoutes}
import eudi_logic_core.WalletCoreError

// ─── Document details ──────────────────────────────────────────────────────

/** Mirrors Swift `DocumentDetailsViewState` (trimmed to delivered fields). */
public class DocumentDetailsState <: ViewState {
    public let details: ?DocumentDetails
    public let isLoading: Bool
    /** Shows the blocking "Issuance blocked" alert (iOS
     *  `isTrustBlockedAlertShowing`): the re-issuance was refused because the
     *  issuer could not be verified or its registration is blocked. */
    public let isTrustBlockedAlertShowing: Bool
    /** iOS `viewState.isBookmarked`: seeded from the stored document, flipped by toggleBookmark. */
    public let isBookmarked: Bool
    /** iOS `showBookmarkAlert`: the "Saved to / Removed from favorites" alert. */
    public let isBookmarkAlertShowing: Bool

    public init(
        details!: ?DocumentDetails = Option<DocumentDetails>.None,
        isLoading!: Bool = true,
        isTrustBlockedAlertShowing!: Bool = false,
        isBookmarked!: Bool = false,
        isBookmarkAlertShowing!: Bool = false
    ) {
        this.details = details
        this.isLoading = isLoading
        this.isTrustBlockedAlertShowing = isTrustBlockedAlertShowing
        this.isBookmarked = isBookmarked
        this.isBookmarkAlertShowing = isBookmarkAlertShowing
    }
}

/** Mirrors Swift `DocumentDetailsViewModel<Router>`. */
public class DocumentDetailsViewModel <: BaseViewModel<DocumentDetailsState> {
    private let interactor: DashboardInteractor
    private let documentId: String

    public init(router!: RouterHost, interactor!: DashboardInteractor, documentId!: String) {
        super(router, DocumentDetailsState(details: Option<DocumentDetails>.None, isLoading: true))
        this.interactor = interactor
        this.documentId = documentId
    }

    /** Blocking; view wraps in spawn{}. Mirrors fetchDocumentDetails(). */
    public func fetchDetails(): Unit {
        let result = this.interactor.fetchDocumentDetails(this.documentId)
        let bookmarked = match (result) {
            case Some(d) => d.isBookmarked
            case None => false
        }
        this.setState({ _ => DocumentDetailsState(details: result, isLoading: false, isBookmarked: bookmarked) })
    }

    /**
     * Blocking; view wraps in spawn{}. Mirrors iOS saveBookmark(_:): stores or
     * removes the bookmark, flips the state and raises the favorites alert. A
     * storage failure leaves the state untouched, as iOS swallows the error.
     */
    public func toggleBookmark(): Unit {
        let wasBookmarked = this.viewState.isBookmarked
        let ok = if (wasBookmarked) {
            this.interactor.deleteBookmark(this.documentId)
        } else {
            this.interactor.saveBookmark(this.documentId)
        }
        if (!ok) {
            return
        }
        this.setState({ s =>
            DocumentDetailsState(
                details: s.details, isLoading: s.isLoading, isTrustBlockedAlertShowing: s.isTrustBlockedAlertShowing,
                isBookmarked: !wasBookmarked, isBookmarkAlertShowing: true
            )
        })
    }

    /** iOS favorites alert Close. */
    public func dismissBookmarkAlert(): Unit {
        this.setState({ s =>
            DocumentDetailsState(
                details: s.details, isLoading: s.isLoading, isTrustBlockedAlertShowing: s.isTrustBlockedAlertShowing,
                isBookmarked: s.isBookmarked
            )
        })
    }

    /**
     * Blocking; view wraps in spawn{}. Mirrors iOS onDeleteDocument: removes the
     * document. Returns whether the deletion succeeded; the VIEW pops back on the
     * UI thread on success (calling router.pop() here ran on the background spawn
     * thread, where ArkUI navigation is a no-op — the delete appeared to do
     * nothing).
     */
    public func deleteDocument(): Bool {
        return this.interactor.deleteDocument(this.documentId)
    }

    /**
     * Blocking; view wraps in spawn{}. Mirrors iOS issueNewDocument: re-issues
     * the document then refetches the details (the iOS flow pops on the
     * reissuance-refresh notification; here we refresh in place). A trust-
     * blocked refusal — incl. `RegistrationRefusedError` from the registration
     * pre-check — raises the blocking "Issuance blocked" alert instead of an
     * error (iOS `.issuerNotTrusted` → `isTrustBlockedAlertShowing = true`).
     */
    public func reIssueDocument(): ReIssueResult {
        let outcome = this.interactor.reIssueDocument(this.documentId)
        match (outcome) {
            case ReIssueSuccess => this.fetchDetails()
            case ReIssueIssuerNotTrusted =>
                this.setState({ s =>
                    DocumentDetailsState(
                        details: s.details, isLoading: false, isTrustBlockedAlertShowing: true,
                        isBookmarked: s.isBookmarked
                    )
                })
            case ReIssueFailure(_) => ()
        }
        return outcome
    }

    /** iOS trust-blocked alert Close: just dismiss. */
    public func dismissTrustBlockedAlert(): Unit {
        this.setState({ s => DocumentDetailsState(details: s.details, isLoading: false, isBookmarked: s.isBookmarked) })
    }

    public func onBack(): Unit {
        this.router.pop()
    }
}

// ─── Transaction details ───────────────────────────────────────────────────

/** Mirrors Swift `TransactionDetailsUiState` (trimmed to delivered fields). */
public class TransactionDetailsState <: ViewState {
    public let details: ?TransactionDetails
    public let isLoading: Bool
    /**
     * Set when the lookup failed outright, carrying the text to show. Distinct
     * from `details == None`, which means "the log exists but no details could be
     * built" — iOS keeps the same split via `.failure(error)` versus an empty
     * success, and shows the error message rather than the no-results copy.
     */
    public let errorMessage: ?String

    public init(
        details!: ?TransactionDetails = Option<TransactionDetails>.None,
        isLoading!: Bool = true,
        errorMessage!: ?String = Option<String>.None
    ) {
        this.details = details
        this.isLoading = isLoading
        this.errorMessage = errorMessage
    }
}

/** Mirrors Swift `TransactionDetailsViewModel<Router>`. */
public class TransactionDetailsViewModel <: BaseViewModel<TransactionDetailsState> {
    private let interactor: DashboardInteractor
    private let transactionId: String

    public init(router!: RouterHost, interactor!: DashboardInteractor, transactionId!: String) {
        super(router, TransactionDetailsState(details: Option<TransactionDetails>.None, isLoading: true))
        this.interactor = interactor
        this.transactionId = transactionId
    }

    /**
     * Blocking; view wraps in spawn{}.
     *
     * The interactor signals a failed lookup by throwing (the Cangjie carrier for
     * iOS's `.failure(error)`), and the view calls this from a bare `spawn{}`, so
     * the throw has to stop here: unhandled, it kills the coroutine with the
     * spinner still up. iOS ends the same path with `isLoading: false` plus the
     * error message on screen, which is what the error state below drives.
     */
    public func fetchDetails(): Unit {
        try {
            let result = this.interactor.fetchTransactionDetails(this.transactionId)
            this.setState({ _ => TransactionDetailsState(details: result, isLoading: false) })
        } catch (e: Exception) {
            let message = match (e) {
                case walletError: WalletCoreError => walletError.errorDescription
                case _ => WalletCoreError.unableToFetchTransactionLog().errorDescription
            }
            this.setState({ _ =>
                TransactionDetailsState(
                    details: Option<TransactionDetails>.None,
                    isLoading: false,
                    errorMessage: message
                )
            })
        }
    }

    public func onBack(): Unit {
        this.router.pop()
    }
}
