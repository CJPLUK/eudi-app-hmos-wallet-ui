/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-issuance
 * module (Interactor/AddDocumentInteractor.swift + DocumentOfferInteractor.swift)
 * to Cangjie for the EUDI HarmonyOS wallet.
 *
 * Pure business-logic seam wrapping WalletKitController (logic-core). This file
 * deliberately does NOT import ArkUI (kit.ArkUI.* would pollute bare `None`),
 * matching the project convention that Interactor/Model files stay UI-free.
 *
 * Faithful mirror of the iOS partial-state result enums. Because the in-app
 * Web-component authorization flow (page/index.cj reference) opens the engine's
 * `pendingAuthorizationUrl` directly and resumes via `resumePendingIssuance`,
 * the iOS `.dynamicIssuance(RemoteSessionCoordinator)` arm (which on iOS hands
 * the auth URL to feature-presentation via startSameDevicePresentation) is here
 * realised as `.dynamicIssuance(authUrl, pendingDoc)` — the URL + pending doc
 * the issuance Web view needs to drive the browser-authorization handshake.
 */
package eudi_feature_issuance

import std.collection.{ArrayList, HashMap}
import ohos.hilog.Hilog
import eudi_logic_business.{ConfigLogic, ParsedUrl, UrlUtil}
import eudi_logic_core.*
import eudi_feature_common.IssuanceFlow

// ─── AddDocument partial states (iOS AddDocumentInteractor.swift enums) ──────

/** Mirrors iOS `ScopedDocumentsPartialState`. The success payload is an ordered
 *  list of issuer buckets (issuerId + its add-document cell models). */
public class ScopedDocumentsResult {
    public let isSuccess: Bool
    public let buckets: ArrayList<AddDocumentBucket>
    public let errorMessage: String
    /** Every issuer failed and at least one failure was a trust block (iOS
     *  `.issuerNotTrusted`). Distinct from `failure`: the UI empties the list
     *  and raises the blocking trust alert instead of a retryable error. */
    public let isIssuerNotTrusted: Bool

    private init(
        isSuccess: Bool,
        buckets: ArrayList<AddDocumentBucket>,
        errorMessage: String,
        isIssuerNotTrusted!: Bool = false
    ) {
        this.isSuccess = isSuccess
        this.buckets = buckets
        this.errorMessage = errorMessage
        this.isIssuerNotTrusted = isIssuerNotTrusted
    }

    public static func success(buckets: ArrayList<AddDocumentBucket>): ScopedDocumentsResult {
        ScopedDocumentsResult(true, buckets, "")
    }

    public static func failure(message: String): ScopedDocumentsResult {
        ScopedDocumentsResult(false, ArrayList<AddDocumentBucket>(), message)
    }

    public static func issuerNotTrusted(): ScopedDocumentsResult {
        ScopedDocumentsResult(false, ArrayList<AddDocumentBucket>(), "", isIssuerNotTrusted: true)
    }
}

/** One issuer bucket = a header label + its add-document cells, mirroring the
 *  iOS `OrderedDictionary<String, [AddDocumentUIModel]>` entry. */
public class AddDocumentBucket {
    public let issuerId: String
    public let items: ArrayList<AddDocumentItem>

    public init(issuerId!: String, items!: ArrayList<AddDocumentItem>) {
        this.issuerId = issuerId
        this.items = items
    }
}

/** Mirrors iOS `AddDocumentUIModel` (the data the cell needs to issue). */
public class AddDocumentItem {
    public let id: String
    public let name: String
    public let issuerId: String
    public let order: Int64
    public let configIds: Array<String>
    public let docTypeIdentifier: DocumentTypeIdentifier
    public var isLoading: Bool

    public init(
        id!: String,
        name!: String,
        issuerId!: String,
        order!: Int64,
        configIds!: Array<String>,
        docTypeIdentifier!: DocumentTypeIdentifier,
        isLoading!: Bool = false
    ) {
        this.id = id
        this.name = name
        this.issuerId = issuerId
        this.order = order
        this.configIds = configIds
        this.docTypeIdentifier = docTypeIdentifier
        this.isLoading = isLoading
    }
}

/** Discriminator for the `issueDocument` outcome (iOS `IssueResultPartialState`). */
public enum IssueResultKind {
    | IssueSuccess
    | IssueDynamic
    | IssueDeferred
    | IssueFailure
    /** The issuer failed trust validation (iOS `.issuerNotTrusted`). Distinct from
     *  `IssueFailure` because the UI blocks the flow with a dedicated alert instead
     *  of showing a retryable error. */
    | IssueIssuerNotTrusted
    /** The issuer's registration certificate refuses this issuance (iOS
     *  `.registrationBlocked(reason)`): the provider is not registered as an
     *  issuer, or not registered for this attestation. Refused BEFORE issuing. */
    | IssueRegistrationBlocked
}

/** Mirrors iOS `IssueResultPartialState`. The `.dynamicIssuance` arm carries the
 *  browser-authorization URL + the pending document for the in-app Web view. */
public class IssueResult {
    public let kind: IssueResultKind
    public let successIds: Array<String>
    public let authUrl: String
    public let pendingDoc: ?WalletStorageDocument
    public let deferredName: String
    public let deferredIssuer: String
    public let errorMessage: String
    /** Payload of the `.registrationBlocked` arm; `None` on every other kind. */
    public let registrationBlockedReason: ?IssuerRegistrationBlockedReason

    private init(
        kind: IssueResultKind,
        successIds: Array<String>,
        authUrl: String,
        pendingDoc: ?WalletStorageDocument,
        deferredName: String,
        deferredIssuer: String,
        errorMessage: String,
        registrationBlockedReason!: ?IssuerRegistrationBlockedReason = None
    ) {
        this.kind = kind
        this.successIds = successIds
        this.authUrl = authUrl
        this.pendingDoc = pendingDoc
        this.deferredName = deferredName
        this.deferredIssuer = deferredIssuer
        this.errorMessage = errorMessage
        this.registrationBlockedReason = registrationBlockedReason
    }

    public static func success(ids: Array<String>): IssueResult {
        IssueResult(IssueResultKind.IssueSuccess, ids, "", Option<WalletStorageDocument>.None, "", "", "")
    }

    public static func dynamicIssuance(authUrl: String, pendingDoc: WalletStorageDocument): IssueResult {
        IssueResult(IssueResultKind.IssueDynamic, Array<String>(), authUrl, Some(pendingDoc), "", "", "")
    }

    public static func deferredSuccess(name: String, issuer: String): IssueResult {
        IssueResult(IssueResultKind.IssueDeferred, Array<String>(), "", Option<WalletStorageDocument>.None, name, issuer, "")
    }

    public static func failure(message: String): IssueResult {
        IssueResult(IssueResultKind.IssueFailure, Array<String>(), "", Option<WalletStorageDocument>.None, "", "", message)
    }

    public static func issuerNotTrusted(): IssueResult {
        IssueResult(IssueResultKind.IssueIssuerNotTrusted, Array<String>(), "", Option<WalletStorageDocument>.None, "", "", "")
    }

    public static func registrationBlocked(reason: IssuerRegistrationBlockedReason): IssueResult {
        IssueResult(
            IssueResultKind.IssueRegistrationBlocked, Array<String>(), "",
            Option<WalletStorageDocument>.None, "", "", "",
            registrationBlockedReason: Some(reason)
        )
    }
}

/** Discriminator for the dynamic-issuance resume outcome
 *  (iOS `IssueDynamicDocumentPartialState`). */
public enum ResumeResultKind {
    | ResumeSuccess
    | ResumeNoPending
    | ResumeDeferred
    | ResumeFailure
    /** The issuer failed trust validation (iOS `.issuerNotTrusted`). */
    | ResumeIssuerNotTrusted
}

/** Mirrors iOS `IssueDynamicDocumentPartialState`. */
public class ResumeResult {
    public let kind: ResumeResultKind
    /** All issued document ids (iOS `successIds` from the issueDocument loop);
     *  combined issuance ("PID Combined") carries one id per issued format. */
    public let docIds: Array<String>
    public let errorMessage: String
    /** Deferred document display name / issuer name for the in-progress success
     *  caption. iOS runs the auth-code browser inside issueDocument and returns
     *  `.deferredSuccess(scopedDocument)` with both names; the Cangjie in-app
     *  Web flow resumes here instead, so the resume carries them to keep the
     *  success screen text identical to iOS. */
    public let deferredName: String
    public let deferredIssuer: String

    private init(
        kind: ResumeResultKind,
        docIds: Array<String>,
        errorMessage: String,
        deferredName!: String = "",
        deferredIssuer!: String = ""
    ) {
        this.kind = kind
        this.docIds = docIds
        this.errorMessage = errorMessage
        this.deferredName = deferredName
        this.deferredIssuer = deferredIssuer
    }

    public static func success(docIds: Array<String>): ResumeResult {
        ResumeResult(ResumeResultKind.ResumeSuccess, docIds, "")
    }

    public static func noPending(): ResumeResult {
        ResumeResult(ResumeResultKind.ResumeNoPending, Array<String>(), "")
    }

    public static func deferredSuccess(name: String, issuer: String): ResumeResult {
        ResumeResult(ResumeResultKind.ResumeDeferred, Array<String>(), "", deferredName: name, deferredIssuer: issuer)
    }

    public static func failure(message: String): ResumeResult {
        ResumeResult(ResumeResultKind.ResumeFailure, Array<String>(), message)
    }

    public static func issuerNotTrusted(): ResumeResult {
        ResumeResult(ResumeResultKind.ResumeIssuerNotTrusted, Array<String>(), "")
    }
}

/** One displayed claim row on the success screen (iOS ListItemData: label + value). */
public class SuccessFieldRow {
    public let title: String
    public let value: String

    public init(title!: String, value!: String) {
        this.title = title
        this.value = value
    }
}

/**
 * A fetched, stored document reduced to what the document-issuance success
 * screen consumes — mirrors the iOS `DocumentUIModel` subset that
 * DocumentSuccessView renders: the document name, its issuer (name + logo) and
 * the per-document field detail list (ListItemSection.listItems).
 */
public class IssuedDocumentSummary {
    public let id: String
    public let name: String
    public let issuer: String
    public let issuerLogoUrl: String
    public let fields: Array<SuccessFieldRow>

    public init(
        id: String,
        name: String,
        issuer!: String = "",
        issuerLogoUrl!: String = "",
        fields!: Array<SuccessFieldRow> = Array<SuccessFieldRow>()
    ) {
        this.id = id
        this.name = name
        this.issuer = issuer
        this.issuerLogoUrl = issuerLogoUrl
        this.fields = fields
    }
}

/**
 * Flattens a stored document's claims into success-screen field rows. Recurses
 * into nested DocClaim children (mDoc namespaces) and skips image-only leaves
 * (no readable text), mirroring the iOS DocumentUIModel.documentFields mapping.
 */
func flattenSuccessFields(doc: DocClaimsDecodable): Array<SuccessFieldRow> {
    let rows = ArrayList<SuccessFieldRow>()
    for (claim in doc.docClaims) {
        appendSuccessClaim(claim, rows)
    }
    return rows.toArray()
}

func appendSuccessClaim(claim: DocClaim, rows: ArrayList<SuccessFieldRow>): Unit {
    match (claim.children) {
        case Some(children) where children.size > 0 =>
            for (child in children) {
                appendSuccessClaim(child, rows)
            }
        case _ =>
            if (!claim.stringValue.isEmpty()) {
                rows.add(SuccessFieldRow(title: claim.displayName ?? claim.name, value: claim.stringValue))
            }
    }
}

// ─── AddDocumentInteractor (iOS AddDocumentInteractor.swift) ─────────────────

/** Mirrors iOS `AddDocumentInteractor` protocol. */
public interface AddDocumentInteractor {
    func fetchScopedDocuments(flow: IssuanceFlow): ScopedDocumentsResult
    func issueDocument(issuerId: String, configIds: Array<String>, docTypeIdentifier: DocumentTypeIdentifier): IssueResult
    func resumeDynamicIssuance(redirectUrl: String): ResumeResult
    func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary>
}

/** Mirrors iOS `final actor AddDocumentInteractorImpl`. */
public class AddDocumentInteractorImpl <: AddDocumentInteractor {
    private let walletController: WalletKitController

    public init(walletController!: WalletKitController) {
        this.walletController = walletController
    }

    /**
     * Mirrors iOS `fetchScopedDocuments(with:)`: groups scoped documents by
     * issuer, folds PID config-ids into a single "PID combined" cell, filters by
     * the active flow, and orders buckets by max(order) then issuer name.
     *
     * Partial failure is tolerated (iOS ScopedDocumentsResult): one failing
     * issuer no longer kills the list — its errors stay silent. Only when EVERY
     * issuer failed does the fetch fail: a trust-blocked error among them raises
     * the blocking issuer-not-trusted outcome, otherwise the first error text.
     */
    public func fetchScopedDocuments(flow: IssuanceFlow): ScopedDocumentsResult {
        let result = this.walletController.getScopedDocuments()
        if (result.allIssuersFailed) {
            for (error in result.errors) {
                if (isTrustBlocked(error)) {
                    return ScopedDocumentsResult.issuerNotTrusted()
                }
            }
            if (result.errors.size > 0) {
                return ScopedDocumentsResult.failure(errorText(result.errors[0]))
            }
            return ScopedDocumentsResult.failure(WalletCoreError.unableFetchDocuments().errorDescription)
        }
        let scoped = result.documents

        // issuerId -> mutable bucket builder
        let order: ArrayList<String> = ArrayList<String>()
        let nonPid: HashMap<String, ArrayList<AddDocumentItem>> = HashMap<String, ArrayList<AddDocumentItem>>()
        let pidConfigIds: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
        let pidIdentifier: HashMap<String, DocumentTypeIdentifier> = HashMap<String, DocumentTypeIdentifier>()
        let pidOrder: HashMap<String, Int64> = HashMap<String, Int64>()
        let maxOrder: HashMap<String, Int64> = HashMap<String, Int64>()

        for (doc in scoped) {
            if (!matchesFlow(doc, flow)) {
                continue
            }
            let issuerId = doc.issuer
            if (!nonPid.contains(issuerId)) {
                order.add(issuerId)
                nonPid[issuerId] = ArrayList<AddDocumentItem>()
                pidConfigIds[issuerId] = ArrayList<String>()
                maxOrder[issuerId] = doc.order
            }
            if (doc.order > maxOrder[issuerId]) {
                maxOrder[issuerId] = doc.order
            }
            if (doc.isPid) {
                pidConfigIds[issuerId].add(doc.configId)
                pidIdentifier[issuerId] = doc.docTypeIdentifier
                pidOrder[issuerId] = doc.order
            } else {
                nonPid[issuerId].add(
                    AddDocumentItem(
                        id: "cell_${issuerId}_${doc.configId}",
                        name: doc.name,
                        issuerId: issuerId,
                        order: doc.order,
                        configIds: [doc.configId],
                        docTypeIdentifier: doc.docTypeIdentifier
                    )
                )
            }
        }

        let buckets: ArrayList<AddDocumentBucket> = ArrayList<AddDocumentBucket>()
        for (issuerId in order) {
            let items = nonPid[issuerId]
            let pids = pidConfigIds[issuerId]
            if (pids.size > 0) {
                items.add(
                    AddDocumentItem(
                        id: "cell_${issuerId}_pid_combined",
                        name: "PID Combined",
                        issuerId: issuerId,
                        order: pidOrder.get(issuerId) ?? 0,
                        configIds: toArray(pids),
                        docTypeIdentifier: pidIdentifier.get(issuerId) ?? DocumentTypeIdentifier.mDocPid
                    )
                )
            }
            // iOS sorts cells case-insensitively by name.
            sortByName(items)
            buckets.add(AddDocumentBucket(issuerId: issuerId, items: items))
        }

        // iOS orders buckets by max(order) desc, then issuer name asc.
        sortBuckets(buckets, maxOrder)
        return ScopedDocumentsResult.success(buckets)
    }

    /**
     * Mirrors iOS `issueDocument(issuerId:configIds:docTypeIdentifier:)`.
     * For an auth-code (browser) credential the engine returns a Pending doc
     * carrying `metadata.pendingAuthorizationUrl` — surfaced as `.dynamicIssuance`.
     *
     * A deferred document must carry a `metadata.configurationIdentifier` that
     * resolves to a scoped document (iOS AddDocumentInteractor.swift:166-171). If
     * the metadata is missing or the configId cannot be extracted, the issuance is
     * treated as a failure (iOS `.unableToIssueAndStore`) rather than a spurious
     * deferred success — matching the iOS `guard ... else { error = ...; continue }`.
     * The error path takes precedence over a deferred success, mirroring the iOS
     * post-loop ordering (`if let error … else if !successIds … else if deferred`).
     */
    public func issueDocument(
        issuerId: String,
        configIds: Array<String>,
        docTypeIdentifier: DocumentTypeIdentifier
    ): IssueResult {
        // Pre-check (iOS): a `.blocked` issuer registration refuses the issuance
        // BEFORE the engine issues anything. An absent verdict (None) vouches.
        match (this.walletController.getIssuerRegistration(issuerId, configIds)) {
            case Some(registration) =>
                match (registration) {
                    case IssuerRegistration.blocked(reason) => return IssueResult.registrationBlocked(reason)
                    case _ => ()
                }
            case None => ()
        }
        try {
            let issuance = this.walletController.issueDocuments(issuerId, configIds, docTypeIdentifier)
            let docs = issuance.documents

            // Post-check (iOS): the verdict captured during issuance must vouch;
            // otherwise the already-stored documents are discarded and the flow
            // blocks — issuance REFUSES on a bad registration, it never warns.
            if (!vouchesForIssuer(issuance.issuerRegistration)) {
                this.discard(docs)
                return IssueResult.issuerNotTrusted()
            }

            if (docs.size == 0) {
                return IssueResult.failure(localizedIssueError())
            }

            let successIds: ArrayList<String> = ArrayList<String>()
            var deferred: ?ScopedDocument = None
            var hadError = false
            for (doc in docs) {
                match (pendingAuthUrl(doc)) {
                    case Some(url) =>
                        // First auth-code doc drives the in-app Web authorization.
                        this.walletController.storeDynamicIssuancePendingUrl(authParsedUrl(url))
                        return IssueResult.dynamicIssuance(url, doc)
                    case None =>
                        if (doc.status == DocumentStatus.deferred) {
                            // iOS guards on DocMetadata(from:)?.configurationIdentifier
                            // then resolves the scoped document for that configId.
                            match (deferredConfigId(doc)) {
                                case Some(configId) =>
                                    deferred = Some(getScopedDocument(configId))
                                case None =>
                                    hadError = true
                            }
                        } else {
                            successIds.add(doc.id)
                        }
                }
            }

            // iOS ordering: error first, then plain success, then deferred success.
            if (hadError) {
                return IssueResult.failure(localizedIssueError())
            }
            if (successIds.size > 0) {
                return IssueResult.success(toArray(successIds))
            }
            match (deferred) {
                case Some(scoped) =>
                    let name = if (scoped.name.isEmpty()) { "" } else { scoped.name }
                    let issuer = if (scoped.issuer.isEmpty()) { issuerId } else { scoped.issuer }
                    return IssueResult.deferredSuccess(name, issuer)
                case None => ()
            }
            return IssueResult.failure(localizedIssueError())
        } catch (e: Exception) {
            if (isTrustBlocked(e)) {
                return IssueResult.issuerNotTrusted()
            }
            return IssueResult.failure(errorText(e))
        }
    }

    /**
     * Mirrors iOS `discard(_:)`: deletes documents an untrusted issuance already
     * stored, so a refused issuance leaves NOTHING in the wallet. Per-document
     * delete failures are swallowed (iOS `try?`).
     */
    private func discard(docs: Array<WalletStorageDocument>): Unit {
        for (doc in docs) {
            try {
                this.walletController.deleteDocument(doc.id, doc.status)
            } catch (_: Exception) {}
        }
    }

    /**
     * Extracts the `configurationIdentifier` a deferred document must carry, from
     * its metadata blob. Returns None when metadata is absent or the identifier is
     * unset/empty — the condition that fails the iOS guard and forces a failure.
     * Mirrors iOS `DocMetadata(from: doc.metadata)?.configurationIdentifier`.
     */
    private func deferredConfigId(doc: WalletStorageDocument): ?String {
        match (doc.metadata) {
            case Some(meta) =>
                match (meta.configurationIdentifier) {
                    case Some(id) where !id.isEmpty() => Some(id)
                    case _ => None
                }
            case None => None
        }
    }

    /**
     * Resolves the scoped document for a configId, mirroring the iOS
     * `getScopedDocument(configId:)` helper which returns the first matching
     * scoped document or `ScopedDocument.empty()`.
     */
    private func getScopedDocument(configId: String): ScopedDocument {
        for (doc in this.walletController.getScopedDocuments().documents) {
            if (doc.configId == configId) {
                return doc
            }
        }
        return ScopedDocument.empty()
    }

    /**
     * Mirrors iOS `resumeDynamicIssuance()` combined with the Web-view redirect
     * capture: takes the intercepted redirect URL (`eu.europa.ec.euidi://...?code=`),
     * looks up the stored pending data, and calls `resumePendingIssuance`.
     */
    public func resumeDynamicIssuance(redirectUrl: String): ResumeResult {
        let pendingOpt = this.walletController.getDynamicIssuancePendingData()
        match (pendingOpt) {
            case None => return ResumeResult.noPending()
            case Some(pendingData) =>
                try {
                    let webUrl = authParsedUrl(redirectUrl)
                    let docs = this.walletController.resumePendingIssuance(pendingData.pendingDoc, Some(webUrl))
                    // Mirrors the iOS AddDocumentInteractor.issueDocument loop over
                    // the returned document array: issued → successIds, deferred →
                    // deferredDocument; successIds win over deferred (the deferred
                    // credential surfaces later via the Documents-tab poll).
                    let successIds = ArrayList<String>()
                    var deferredDoc: ?WalletStorageDocument = Option<WalletStorageDocument>.None
                    for (doc in docs) {
                        if (doc.status == DocumentStatus.issued) {
                            successIds.add(doc.id)
                        } else if (doc.status == DocumentStatus.deferred) {
                            deferredDoc = Some(doc)
                        }
                    }
                    if (successIds.size > 0) {
                        return ResumeResult.success(successIds.toArray())
                    }
                    match (deferredDoc) {
                        case Some(doc) =>
                            // Carry the deferred doc / issuer names so the
                            // "In progress" caption matches iOS ("Your document X
                            // from Y has been requested…"). Same source as the
                            // issueDocument deferred path: the scoped document for
                            // the stored configurationIdentifier (issuer = host, as
                            // iOS shows); DocMetadata display as the fallback.
                            var name = metadataDisplayName(doc)
                            var issuer = ""
                            match (deferredConfigId(doc)) {
                                case Some(configId) =>
                                    let scoped = this.getScopedDocument(configId)
                                    if (!scoped.name.isEmpty()) { name = scoped.name }
                                    if (!scoped.issuer.isEmpty()) { issuer = scoped.issuer }
                                case None => ()
                            }
                            return ResumeResult.deferredSuccess(name, issuer)
                        case None => return ResumeResult.failure(localizedIssueError())
                    }
                } catch (e: Exception) {
                    Hilog.error(0, "VCI-DEBUG", "resumeDynamicIssuance failed: ${e} msg=${e.message}")
                    if (isTrustBlocked(e)) {
                        return ResumeResult.issuerNotTrusted()
                    }
                    return ResumeResult.failure(errorText(e))
                }
        }
    }

    /**
     * Mirrors iOS `fetchStoredDocuments(documentIds:)` → DocumentUIModel: each
     * stored document is reduced to its name, issuer (name + logo) and flattened
     * field list (the iOS `documentFields`). The fields drive the per-document
     * detail section on the success screen.
     *
     * Nothing retrievable is a failure, not an empty success: iOS returns
     * `.failure(WalletCoreError.unableFetchDocument)` when its compactMap yields
     * nothing, and its ViewModel raises an error instead of navigating. Per-document
     * decode failures still degrade to a name-only summary (below), so reaching the
     * throw means the store returned nothing at all for these ids.
     */
    public func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary> {
        let out: ArrayList<IssuedDocumentSummary> = ArrayList<IssuedDocumentSummary>()
        let docs = this.walletController.fetchDocuments(documentIds)
        for (doc in docs) {
            try {
                out.add(
                    IssuedDocumentSummary(
                        doc.id,
                        doc.displayName ?? doc.id,
                        issuer: issuerName(doc),
                        issuerLogoUrl: issuerLogo(doc) ?? "",
                        fields: flattenSuccessFields(doc)
                    )
                )
            } catch (_: Exception) {
                Hilog.warn(0, "VCI-DEBUG", "fetchStoredDocuments: skip doc ${doc.id} (decode failed)")
                out.add(IssuedDocumentSummary(doc.id, doc.displayName ?? doc.id))
            }
        }
        if (out.isEmpty()) {
            throw WalletCoreError.unableFetchDocument()
        }
        return out
    }

    private func matchesFlow(doc: ScopedDocument, flow: IssuanceFlow): Bool {
        match (flow) {
            case NoDocument => doc.isPid
            case ExtraDocument(filterOpt) =>
                match (filterOpt) {
                    case Some(filter) =>
                        if (filter.isEmpty()) {
                            true
                        } else {
                            doc.docTypeIdentifier.rawValue == filter
                        }
                    case None => true
                }
        }
    }
}

// ─── DocumentOffer partial states (iOS DocumentOfferInteractor.swift) ────────

/** A single offered credential reduced to its display name (iOS UIOffer). */
public class OfferItem {
    public let name: String
    public init(name: String) {
        this.name = name
    }
}

/** Mirrors iOS `OfferRequestPartialState` (success payload = DocumentOfferUIModel
 *  plus the issuer's registration verdict; `.registrationBlocked` refuses the
 *  offer BEFORE anything is issued). */
public class OfferRequest {
    public let isSuccess: Bool
    public let issuerName: String
    public let issuerLogoUrl: String
    public let txCodeRequired: Bool
    public let txCodeLength: Int64
    public let offers: ArrayList<OfferItem>
    public let errorMessage: String
    /** iOS `.success(_, issuerRegistration)` second payload — the verdict the
     *  view state turns into the RelyingPartyRegistrationView header data. */
    public let issuerRegistration: ?IssuerRegistration
    /** iOS `.registrationBlocked(reason)`: the provider is not registered for
     *  this issuance. Distinct from `failure` — the UI resets the offer and
     *  raises the blocking registration alert instead of a retryable error. */
    public let isRegistrationBlocked: Bool
    /** Payload of the `.registrationBlocked` arm; `None` otherwise. */
    public let registrationBlockedReason: ?IssuerRegistrationBlockedReason

    private init(
        isSuccess: Bool,
        issuerName: String,
        issuerLogoUrl: String,
        txCodeRequired: Bool,
        txCodeLength: Int64,
        offers: ArrayList<OfferItem>,
        errorMessage: String,
        issuerRegistration!: ?IssuerRegistration = None,
        isRegistrationBlocked!: Bool = false,
        registrationBlockedReason!: ?IssuerRegistrationBlockedReason = None
    ) {
        this.isSuccess = isSuccess
        this.issuerName = issuerName
        this.issuerLogoUrl = issuerLogoUrl
        this.txCodeRequired = txCodeRequired
        this.txCodeLength = txCodeLength
        this.offers = offers
        this.errorMessage = errorMessage
        this.issuerRegistration = issuerRegistration
        this.isRegistrationBlocked = isRegistrationBlocked
        this.registrationBlockedReason = registrationBlockedReason
    }

    public static func success(
        issuerName!: String,
        issuerLogoUrl!: String,
        txCodeRequired!: Bool,
        txCodeLength!: Int64,
        offers!: ArrayList<OfferItem>,
        issuerRegistration!: ?IssuerRegistration = None
    ): OfferRequest {
        OfferRequest(
            true, issuerName, issuerLogoUrl, txCodeRequired, txCodeLength, offers, "",
            issuerRegistration: issuerRegistration
        )
    }

    public static func failure(message: String): OfferRequest {
        OfferRequest(false, "", "", false, 0, ArrayList<OfferItem>(), message)
    }

    public static func registrationBlocked(reason: IssuerRegistrationBlockedReason): OfferRequest {
        OfferRequest(
            false, "", "", false, 0, ArrayList<OfferItem>(), "",
            isRegistrationBlocked: true, registrationBlockedReason: Some(reason)
        )
    }

    /**
     * Mirrors iOS `DocumentOfferUIModel.mock()`
     * (feature-issuance/.../Model/DocumentOfferUIModel.swift:79): a sample default
     * offer UI model with the unknown-issuer name, no logo, no tx-code, and five
     * "Document Name" offers. `"Issuer"` is the resolved value of
     * `LocalizableStringKey.unknownIssuer` (logic-resources); kept as a literal so
     * this pure-logic file needs no resources dependency (tests assert equivalence
     * against `LocalizableManager.get(unknownIssuer)`).
     */
    public static func mock(): OfferRequest {
        let offers = ArrayList<OfferItem>()
        var i = 0
        while (i < 5) {
            offers.add(OfferItem("Document Name"))
            i += 1
        }
        return OfferRequest.success(
            issuerName: "Issuer",
            issuerLogoUrl: "",
            txCodeRequired: false,
            txCodeLength: 0,
            offers: offers
        )
    }
}

/**
 * Mirrors iOS `OfferedIssuanceModel.transformToDocumentOfferUi()` — a pure mapping
 * from the wallet's resolved offer to the UI payload, with no I/O and no validation.
 * Kept standalone (rather than inlined in processOfferRequest) so the field mapping
 * is assertable on its own, the way iOS tests it.
 */
public func toOfferRequest(
    offer: OfferedIssuanceModel,
    issuerRegistration!: ?IssuerRegistration = None
): OfferRequest {
    let items: ArrayList<OfferItem> = ArrayList<OfferItem>()
    for (doc in offer.docModels) {
        items.add(OfferItem(doc.displayName))
    }
    let required = match (offer.txCodeSpec) {
        case Some(_) => true
        case None => false
    }
    let length = match (offer.txCodeSpec) {
        case Some(spec) => spec.length ?? 0
        case None => 0
    }
    return OfferRequest.success(
        issuerName: offer.issuerName,
        issuerLogoUrl: offer.issuerLogoUrl ?? "",
        txCodeRequired: required,
        txCodeLength: length,
        offers: items,
        issuerRegistration: issuerRegistration
    )
}

/** Discriminator for the offer-issue outcome (iOS `OfferResultPartialState`). */
public enum OfferResultKind {
    | OfferSuccess
    /** Fewer documents came back than were offered (iOS `.partialSuccess`). */
    | OfferPartialSuccess
    | OfferDynamic
    | OfferDeferred
    | OfferFailure
    /** The issuer failed trust validation (iOS `.issuerNotTrusted`). */
    | OfferIssuerNotTrusted
}

/** Mirrors iOS `OfferResultPartialState`. */
public class OfferResult {
    public let kind: OfferResultKind
    public let documentIds: Array<String>
    public let authUrl: String
    public let pendingDoc: ?WalletStorageDocument
    public let errorMessage: String

    private init(
        kind: OfferResultKind,
        documentIds: Array<String>,
        authUrl: String,
        pendingDoc: ?WalletStorageDocument,
        errorMessage: String
    ) {
        this.kind = kind
        this.documentIds = documentIds
        this.authUrl = authUrl
        this.pendingDoc = pendingDoc
        this.errorMessage = errorMessage
    }

    public static func success(ids: Array<String>): OfferResult {
        OfferResult(OfferResultKind.OfferSuccess, ids, "", Option<WalletStorageDocument>.None, "")
    }

    /**
     * Mirrors iOS `.partialSuccess`: the issuance went through but returned fewer
     * documents than the offer listed. iOS navigates to the same success route as
     * a full success; the distinction lives in the interactor contract.
     */
    public static func partialSuccess(ids: Array<String>): OfferResult {
        OfferResult(OfferResultKind.OfferPartialSuccess, ids, "", Option<WalletStorageDocument>.None, "")
    }

    public static func dynamicIssuance(authUrl: String, pendingDoc: WalletStorageDocument): OfferResult {
        OfferResult(OfferResultKind.OfferDynamic, Array<String>(), authUrl, Some(pendingDoc), "")
    }

    public static func deferredSuccess(): OfferResult {
        OfferResult(OfferResultKind.OfferDeferred, Array<String>(), "", Option<WalletStorageDocument>.None, "")
    }

    public static func failure(message: String): OfferResult {
        OfferResult(OfferResultKind.OfferFailure, Array<String>(), "", Option<WalletStorageDocument>.None, message)
    }

    public static func issuerNotTrusted(): OfferResult {
        OfferResult(OfferResultKind.OfferIssuerNotTrusted, Array<String>(), "", Option<WalletStorageDocument>.None, "")
    }
}

/** Mirrors iOS `DocumentOfferInteractor` protocol. */
public interface DocumentOfferInteractor {
    func processOfferRequest(uri: String): OfferRequest
    func issueDocuments(uri: String, txCodeValue: ?String): OfferResult
    func resumeDynamicIssuance(redirectUrl: String): ResumeResult
    func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary>
}

/** Mirrors iOS `final actor DocumentOfferInteractorImpl`. */
public class DocumentOfferInteractorImpl <: DocumentOfferInteractor {
    private let walletController: WalletKitController
    private let configLogic: ConfigLogic
    // cached offered doc models from the last processOfferRequest (iOS carries
    // these in the UI config's docOffers; here the interactor retains them so
    // issueDocumentsByOfferUrl gets the real OfferedDocModel array).
    private var lastDocOffers: Array<OfferedDocModel> = Array<OfferedDocModel>()

    private static let CODE_MIN_LENGTH: Int64 = 4
    private static let CODE_MAX_LENGTH: Int64 = 6

    public init(walletController!: WalletKitController, configLogic!: ConfigLogic) {
        this.walletController = walletController
        this.configLogic = configLogic
    }

    /** Mirrors iOS `processOfferRequest(with:)`. */
    public func processOfferRequest(uri: String): OfferRequest {
        try {
            let offer = this.walletController.resolveOfferUrlDocTypes(uri)
            this.lastDocOffers = offer.docModels

            let pidTypes: Array<DocumentTypeIdentifier> = [DocumentTypeIdentifier.mDocPid, DocumentTypeIdentifier.sdJwtPid]
            let hasPidStored = this.walletController.fetchIssuedDocuments(types: pidTypes).size > 0

            // tx-code format validation (iOS: length 4..6, inputMode != text)
            match (offer.txCodeSpec) {
                case Some(spec) =>
                    if (spec.inputMode == "text") {
                        return OfferRequest.failure(txCodeFormatError())
                    }
                    match (spec.length) {
                        case Some(len) =>
                            if (len < DocumentOfferInteractorImpl.CODE_MIN_LENGTH ||
                                len > DocumentOfferInteractorImpl.CODE_MAX_LENGTH) {
                                return OfferRequest.failure(txCodeFormatError())
                            }
                        case None => ()
                    }
                case None => ()
            }

            var hasPidInOffer = false
            for (doc in offer.docModels) {
                let id = doc.documentTypeIdentifier
                if (id == DocumentTypeIdentifier.mDocPid || id == DocumentTypeIdentifier.sdJwtPid) {
                    hasPidInOffer = true
                }
            }

            if (this.configLogic.forcePidActivation && !hasPidStored && !hasPidInOffer) {
                return OfferRequest.failure(missingPidError())
            }

            // Registration-certificate check (iOS): the verdict captured on the
            // resolved offer refuses a blocked provider BEFORE anything issues;
            // otherwise it travels with the success payload for the header.
            let issuerRegistration = this.walletController.getIssuerRegistration(offer)
            match (issuerRegistration) {
                case Some(registration) =>
                    match (registration) {
                        case IssuerRegistration.blocked(reason) => return OfferRequest.registrationBlocked(reason)
                        case _ => ()
                    }
                case None => ()
            }

            return toOfferRequest(offer, issuerRegistration: issuerRegistration)
        } catch (e: Exception) {
            return OfferRequest.failure(errorText(e))
        }
    }

    /** Mirrors iOS `issueDocuments(with:..., txCodeValue:)`. */
    public func issueDocuments(uri: String, txCodeValue: ?String): OfferResult {
        try {
            Hilog.info(0, "VCI-DEBUG", "offer issueDocuments uriLen=${uri.size} docOffers=${this.lastDocOffers.size}")
            if (this.lastDocOffers.isEmpty()) {
                // This interactor never resolved the offer (a parent rebuild can
                // hand the view a fresh VM/interactor pair whose initialize never
                // ran) — issuing with an empty docTypes list loops zero times and
                // surfaced as "Unable to issue and store". Re-resolve in place.
                let refreshed = this.processOfferRequest(uri)
                if (refreshed.isRegistrationBlocked) {
                    // Late registration refusal (no iOS counterpart — iOS never
                    // re-resolves here): block the flow like a trust failure
                    // rather than surfacing a blank retryable error.
                    return OfferResult.issuerNotTrusted()
                }
                if (!refreshed.isSuccess) {
                    return OfferResult.failure(refreshed.errorMessage)
                }
                Hilog.info(0, "VCI-DEBUG", "offer issueDocuments re-resolved docOffers=${this.lastDocOffers.size}")
            }
            let issuance = this.walletController.issueDocumentsByOfferUrl(uri, this.lastDocOffers, txCodeValue)
            let issued = issuance.documents

            // Post-check (iOS): a non-vouching issuer registration discards the
            // already-stored documents and blocks — issuance refuses, never warns.
            if (!vouchesForIssuer(issuance.issuerRegistration)) {
                this.discard(issued)
                return OfferResult.issuerNotTrusted()
            }

            if (issued.size == 0) {
                return OfferResult.failure(localizedIssueError())
            }

            // deferred?
            for (doc in issued) {
                if (doc.status == DocumentStatus.deferred) {
                    return OfferResult.deferredSuccess()
                }
            }
            // browser authorization (auth-code) needed?
            for (doc in issued) {
                match (pendingAuthUrl(doc)) {
                    case Some(url) =>
                        this.walletController.storeDynamicIssuancePendingUrl(authParsedUrl(url))
                        return OfferResult.dynamicIssuance(url, doc)
                    case None => ()
                }
            }
            let ids: ArrayList<String> = ArrayList<String>()
            for (doc in issued) {
                ids.add(doc.id)
            }
            // iOS: `issuedDocuments.count == docOffers.count` → .success, otherwise
            // .partialSuccess. Only the count is compared there, so a mismatch in
            // either direction is partial.
            if (ids.size != this.lastDocOffers.size) {
                return OfferResult.partialSuccess(toArray(ids))
            }
            return OfferResult.success(toArray(ids))
        } catch (e: Exception) {
            if (isTrustBlocked(e)) {
                return OfferResult.issuerNotTrusted()
            }
            return OfferResult.failure(errorText(e))
        }
    }

    /**
     * Mirrors iOS `discard(_:)`: deletes documents an untrusted issuance already
     * stored, so a refused issuance leaves NOTHING in the wallet. Per-document
     * delete failures are swallowed (iOS `try?`).
     */
    private func discard(docs: Array<WalletStorageDocument>): Unit {
        for (doc in docs) {
            try {
                this.walletController.deleteDocument(doc.id, doc.status)
            } catch (_: Exception) {}
        }
    }

    /** Mirrors iOS `resumeDynamicIssuance(issuerName:successNavigation:)`. */
    public func resumeDynamicIssuance(redirectUrl: String): ResumeResult {
        let pendingOpt = this.walletController.getDynamicIssuancePendingData()
        match (pendingOpt) {
            case None => return ResumeResult.noPending()
            case Some(pendingData) =>
                try {
                    let webUrl = authParsedUrl(redirectUrl)
                    let docs = this.walletController.resumePendingIssuance(pendingData.pendingDoc, Some(webUrl))
                    // Mirrors the iOS issueDocument loop: issued → successIds,
                    // deferred → deferred flag; successIds win over deferred.
                    let successIds = ArrayList<String>()
                    var hasDeferred = false
                    for (doc in docs) {
                        if (doc.status == DocumentStatus.issued) {
                            successIds.add(doc.id)
                        } else if (doc.status == DocumentStatus.deferred) {
                            hasDeferred = true
                        }
                    }
                    if (successIds.size > 0) {
                        return ResumeResult.success(successIds.toArray())
                    }
                    if (hasDeferred) {
                        // Offer flow caption only uses the issuer name from the
                        // offer state (iOS issuanceSuccessDeferredCaption).
                        return ResumeResult.deferredSuccess("", "")
                    }
                    return ResumeResult.failure(localizedIssueError())
                } catch (e: Exception) {
                    if (isTrustBlocked(e)) {
                        return ResumeResult.issuerNotTrusted()
                    }
                    return ResumeResult.failure(errorText(e))
                }
        }
    }

    /**
     * Mirrors iOS `fetchStoredDocuments(documentIds:)` → DocumentUIModel: each
     * stored document is reduced to its name, issuer (name + logo) and flattened
     * field list (the iOS `documentFields`). The fields drive the per-document
     * detail section on the success screen.
     *
     * Nothing retrievable is a failure, not an empty success: iOS returns
     * `.failure(WalletCoreError.unableFetchDocument)` when its compactMap yields
     * nothing, and its ViewModel raises an error instead of navigating. Per-document
     * decode failures still degrade to a name-only summary (below), so reaching the
     * throw means the store returned nothing at all for these ids.
     */
    public func fetchStoredDocuments(documentIds: Array<String>): ArrayList<IssuedDocumentSummary> {
        let out: ArrayList<IssuedDocumentSummary> = ArrayList<IssuedDocumentSummary>()
        let docs = this.walletController.fetchDocuments(documentIds)
        for (doc in docs) {
            try {
                out.add(
                    IssuedDocumentSummary(
                        doc.id,
                        doc.displayName ?? doc.id,
                        issuer: issuerName(doc),
                        issuerLogoUrl: issuerLogo(doc) ?? "",
                        fields: flattenSuccessFields(doc)
                    )
                )
            } catch (_: Exception) {
                Hilog.warn(0, "VCI-DEBUG", "fetchStoredDocuments: skip doc ${doc.id} (decode failed)")
                out.add(IssuedDocumentSummary(doc.id, doc.displayName ?? doc.id))
            }
        }
        if (out.isEmpty()) {
            throw WalletCoreError.unableFetchDocument()
        }
        return out
    }
}

// ─── Shared helpers ──────────────────────────────────────────────────────────

/** Extracts the pending browser-authorization URL from a doc (iOS
 *  `doc.authorizePresentationUrl` → Cangjie `metadata.pendingAuthorizationUrl`).
 *  Only relevant for Pending-status docs. */
func pendingAuthUrl(doc: WalletStorageDocument): ?String {
    match (doc.metadata) {
        case Some(meta) =>
            match (meta.pendingAuthorizationUrl) {
                case Some(url) =>
                    if (url.isEmpty()) {
                        None
                    } else {
                        Some(url)
                    }
                case None => None
            }
        case None => None
    }
}

/** Builds a ParsedUrl for resumePendingIssuance from a raw URL string. */
func authParsedUrl(url: String): ParsedUrl {
    match (UrlUtil.parse(url)) {
        case Some(p) => p
        case None =>
            // Fall back to a path-only ParsedUrl so resume still receives the raw
            // value (engine extractAuthCode re-parses the query itself).
            ParsedUrl(Option<String>.None, Option<String>.None, url, Option<String>.None, Option<String>.None)
    }
}

func toArray(list: ArrayList<String>): Array<String> {
    let out = Array<String>(list.size, repeat: "")
    var i = 0
    for (v in list) {
        out[i] = v
        i += 1
    }
    return out
}

func sortByName(items: ArrayList<AddDocumentItem>): Unit {
    // simple insertion sort (case-insensitive by name) — small lists.
    var i = 1
    while (i < items.size) {
        let key = items[i]
        var j = i - 1
        while (j >= 0 && items[j].name.toAsciiLower() > key.name.toAsciiLower()) {
            items[j + 1] = items[j]
            j -= 1
        }
        items[j + 1] = key
        i += 1
    }
}

func sortBuckets(buckets: ArrayList<AddDocumentBucket>, maxOrder: HashMap<String, Int64>): Unit {
    var i = 1
    while (i < buckets.size) {
        let key = buckets[i]
        let keyOrder = maxOrder.get(key.issuerId) ?? 0
        var j = i - 1
        while (j >= 0 && bucketGreater(maxOrder.get(buckets[j].issuerId) ?? 0, buckets[j].issuerId, keyOrder, key.issuerId)) {
            buckets[j + 1] = buckets[j]
            j -= 1
        }
        buckets[j + 1] = key
        i += 1
    }
}

/** True when (orderA, issuerA) should come AFTER (orderB, issuerB):
 *  order desc, then issuer name asc — mirrors iOS bucket ordering. */
func bucketGreater(orderA: Int64, issuerA: String, orderB: Int64, issuerB: String): Bool {
    if (orderA != orderB) {
        return orderA < orderB
    }
    return issuerA.toAsciiLower() > issuerB.toAsciiLower()
}

func errorText(e: Exception): String {
    let msg = e.message
    if (msg.isEmpty()) {
        // Empty-message exceptions (NoneValueException & friends) hid the real
        // failure behind the generic text — surface the exception type at least.
        return localizedIssueError() + " (" + e.toString() + ")"
    }
    return msg
}

func localizedIssueError(): String {
    "Unable to issue and store the document"
}

/** Message shown when nothing could be retrieved for the issued ids (iOS `unableFetchDocument`). */
func unableFetchDocumentText(): String {
    WalletCoreError.unableFetchDocument().errorDescription
}

func missingPidError(): String {
    "A PID document is required before adding other documents"
}

func txCodeFormatError(): String {
    "The transaction code must be 4 to 6 digits"
}

/** English-preferred display-metadata name pick (mirrors DocMetadata.getDisplayName). */
func pickMetadataName(entries: ?Array<DisplayMetadata>): String {
    match (entries) {
        case Some(ds) =>
            for (d in ds) {
                if (let Some(loc) <- d.localeIdentifier && loc == "en") {
                    return d.name ?? ""
                }
            }
            if (ds.size > 0) {
                return ds[0].name ?? ""
            }
            return ""
        case None => ""
    }
}

/** Credential display name from a stored document's DocMetadata blob. */
func metadataDisplayName(doc: WalletStorageDocument): String {
    match (doc.metadata) {
        case Some(meta) => pickMetadataName(meta.display)
        case None => ""
    }
}

/** Issuer display name from a stored document's DocMetadata blob. */
func metadataIssuerName(doc: WalletStorageDocument): String {
    match (doc.metadata) {
        case Some(meta) => pickMetadataName(meta.issuerDisplay)
        case None => ""
    }
}
