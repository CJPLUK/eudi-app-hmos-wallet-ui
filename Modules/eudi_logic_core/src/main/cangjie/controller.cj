/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Controller/WalletKitController.swift +
 * WalletKitTransactionLogController.swift.
 *
 * iOS `final actor WalletKitControllerImpl` → Cangjie class; the actor's serial
 * isolation is matched by the underlying WalletStorageView/storage controllers
 * serialising their own access. `async` methods become synchronous (the wallet
 * engine calls block); `try?` becomes try/catch returning the iOS fallback.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.{AtomicInt64, Mutex}
import std.time.DateTime
import eudi_logic_business.ConfigLogic
import eudi_logic_business.DateUtil
import eudi_logic_business.StringUtil
import eudi_logic_business.KeyChainWrapper
import eudi_logic_business.KeyChainController
import eudi_logic_storage.BookmarkStorageController
import eudi_logic_storage.TransactionLogStorageController
import eudi_logic_storage.RevokedDocumentStorageController
import eudi_logic_storage.FailedReIssuedDocStorageController
import eudi_logic_storage.Bookmark
import eudi_logic_storage.TransactionLog as StorageTransactionLog
import eudi_logic_storage.StorageError
import eudi_logic_storage.RevokedDocument
import eudi_logic_storage.FailedReIssuedDocument
import eudi_logic_api.NetworkSessionProvider
import kit.PerformanceAnalysisKit.Hilog
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.RegistrationPolicyViolation
import ohos_app_cangjie_eudi_cjetsi_1196x2.etsi_trust.TrustPolicy

/** Mirrors the private `KeyIdentifier` enum (KeyChainWrapper) in the controller. */
class KeyIdentifier <: KeyChainWrapper {
    static let dynamicIssuancePendingUrl = KeyIdentifier("dynamicIssuancePendingUrl")
    private let raw: String
    init(raw: String) { this.raw = raw }
    public prop value: String { get() { this.raw } }
}

/** Mirrors iOS `public protocol WalletKitController: Sendable`. */
public interface WalletKitController {
    prop wallet: WalletKit

    func startProximityPresentation(): ProximitySessionCoordinator
    func startSameDevicePresentation(deepLink: ParsedUrlRef): RemoteSessionCoordinator
    func startCrossDevicePresentation(urlString: String): RemoteSessionCoordinator
    func stopPresentation(): Unit

    func fetchAllDocuments(): Array<DocClaimsDecodable>
    func fetchDeferredDocuments(): Array<WalletStorageDocument>
    func fetchIssuedDocuments(): Array<DocClaimsDecodable>
    func fetchIssuedDocuments(types!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable>
    func fetchIssuedDocumentsExcluding(excluded!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable>
    func fetchMainPidDocument(): ?DocClaimsDecodable
    func fetchDocument(id: String): ?DocClaimsDecodable
    func fetchDocuments(ids: Array<String>): Array<DocClaimsDecodable>
    func clearAllDocuments(): Unit
    func deleteDocument(id: String, status: DocumentStatus): Unit
    func loadDocuments(): Unit
    func issueDocuments(issuerId: String, identifiers: Array<String>, docTypeIdentifier: DocumentTypeIdentifier): IssuanceResult
    func reIssueDocument(identifier!: String, isBackgroundOperation!: Bool): WalletStorageDocument
    func requestDeferredIssuance(doc: WalletStorageDocument): DocClaimsDecodable
    func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel
    func issueDocumentsByOfferUrl(offerUri: String, docTypes: Array<OfferedDocModel>, txCodeValue: ?String): IssuanceResult
    func parseDocClaim(docId: String, groupId: String, docClaim: DocClaim, claimType: DocumentElementType, parser: (String) -> String): Array<DocumentElementClaim>
    func retrieveLogFileUrl(): ?String
    func resumePendingIssuance(pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef): Array<WalletStorageDocument>
    func storeDynamicIssuancePendingUrl(url: ParsedUrlRef): Unit
    func getDynamicIssuancePendingData(): ?DynamicIssuancePendingData
    func getScopedDocuments(): CoreScopedDocumentsResult
    func getDocumentCategories(): DocumentCategories

    // ── Registration-certificate (WRPRC) trust layer ─────────────────────────
    /** Mirrors `getIssuerRegistration(for:)` — reads the verdict captured on the
     *  resolved offer; no network. */
    func getIssuerRegistration(offer: OfferedIssuanceModel): ?IssuerRegistration
    /** Mirrors `getIssuerRegistration(issuerId:configIds:)` — resolves the
     *  issuer's WRPRC verdict; any thrown error yields None. */
    func getIssuerRegistration(issuerId: String, configIds: Array<String>): ?IssuerRegistration
    /** Mirrors `getVerifierRegistration(policy:trustViolations:overaskedClaims:verifierName:verifierIsTrusted:)`. */
    func getVerifierRegistration(
        policy: ?WrpRegistrationPolicy,
        trustViolations: Array<String>,
        overaskedClaims: Array<OveraskedClaim>,
        verifierName: ?String,
        verifierIsTrusted: Bool
    ): RelyingPartyRegistration
    /** Mirrors `getVerifierRegistrationForFailedRequest()` — shows who asked
     *  when the request was unsatisfiable. */
    func getVerifierRegistrationForFailedRequest(): ?RelyingPartyRegistration

    func isDocumentBookmarked(id: String): Bool
    func storeBookmarkedDocument(id: String): Unit
    func removeBookmarkedDocument(id: String): Unit

    func fetchTransactionLog(id: String): TransactionLogItem
    func logPresentation(relyingPartyName: String, docLabels: Array<String>): Unit
    /** As above, with an explicit presenter name (subject CN of the reader
     *  certificate chain head); when None the controller resolves it from the
     *  active presentation session. A non-empty CN overrides the display name
     *  (iOS `TransactionLog.withPresenterName()`). */
    func logPresentation(relyingPartyName: String, docLabels: Array<String>, presenterName: ?String): Unit
    func fetchTransactionLogs(): Array<TransactionLogItem>

    func isDocumentRevoked(id: String): Bool
    func fetchRevokedDocuments(): Array<String>
    func storeRevokedDocuments(ids: Array<String>): Unit
    func removeRevokedDocument(id: String): Unit

    func getDocumentStatus(statusIdentifier: StatusIdentifier): CredentialStatus
    func isDocumentLowOnCredentials(document: ?DocClaimsDecodable): Bool

    func storeFailedReIssuedDocuments(ids: Array<String>): Unit
    func removeAllFailedReIssuedDocuments(): Unit

    func refreshUsageCounters(): Unit
}

/** Mirrors iOS `final actor WalletKitControllerImpl: WalletKitController`. */
public class WalletKitControllerImpl <: WalletKitController {
    private let _wallet: WalletKit
    private let sessionCoordinatorHolder: SessionCoordinatorHolder
    private let walletKitConfig: WalletKitConfig
    private let configLogic: ConfigLogic
    private let keyChainController: KeyChainController
    private let bookmarkStorageController: BookmarkStorageController
    private let transactionLogStorageController: TransactionLogStorageController
    private let revokedDocumentStorageController: RevokedDocumentStorageController
    private let failedReIssuedDocStorageController: FailedReIssuedDocStorageController
    private let documentRegistrationManager: DocumentRegistrationManager
    private let coordinatorFactory: SessionCoordinatorFactory
    /** Serialises get-then-remove of the auth-code pending URL (double Web
     *  intercept must not both observe the same pending issuance). */
    private let dynamicIssuanceLock = Mutex()

    public init(
        walletKitConfig!: WalletKitConfig,
        configLogic!: ConfigLogic,
        keyChainController!: KeyChainController,
        sessionCoordinatorHolder!: SessionCoordinatorHolder,
        bookmarkStorageController!: BookmarkStorageController,
        transactionLogStorageController!: TransactionLogStorageController,
        revokedDocumentStorageController!: RevokedDocumentStorageController,
        failedReIssuedDocStorageController!: FailedReIssuedDocStorageController,
        networkSessionProvider!: NetworkSessionProvider,
        documentRegistrationManager!: DocumentRegistrationManager,
        coordinatorFactory!: SessionCoordinatorFactory
    ) {
        this.walletKitConfig = walletKitConfig
        this.configLogic = configLogic
        this.keyChainController = keyChainController
        this.sessionCoordinatorHolder = sessionCoordinatorHolder
        this.bookmarkStorageController = bookmarkStorageController
        this.transactionLogStorageController = transactionLogStorageController
        this.revokedDocumentStorageController = revokedDocumentStorageController
        this.failedReIssuedDocStorageController = failedReIssuedDocStorageController
        this.documentRegistrationManager = documentRegistrationManager
        this.coordinatorFactory = coordinatorFactory

        // Mirrors the iOS init: construct EudiWallet from config; iOS fatalErrors
        // if construction fails — here construction is total.
        let issuersCfg = HashMap<String, OpenId4VciConfiguration>()
        for ((host, vci) in walletKitConfig.issuersConfig) {
            issuersCfg.add(host, vci.config)
        }
        this._wallet = WalletKitImpl(
            eudiWalletConfig: EudiWalletConfiguration(
                serviceName: configLogic.keyChainConfig.documentStorageServiceName,
                accessGroup: configLogic.keyChainConfig.keychainAccessGroup,
                userAuthenticationRequired: walletKitConfig.userAuthenticationRequired,
                trustedReaderRootCertificates: walletKitConfig.trustedReaderRootCertificates,
                trustedIssuerRootCertificates: walletKitConfig.trustedIssuerRootCertificates,
                trustConfiguration: walletKitConfig.trustConfiguration,
                logFileName: walletKitConfig.logFileName
            ),
            openID4VpConfig: walletKitConfig.vpConfig,
            openID4VciConfigurations: issuersCfg,
            transactionLogger: walletKitConfig.transactionLogger
        )
    }

    public prop wallet: WalletKit {
        get() { this._wallet }
    }

    // ── Issuance by offer ─────────────────────────────────────────────────────

    public func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel {
        return this._wallet.resolveOfferUrlDocTypes(offerUri)
    }

    public func issueDocumentsByOfferUrl(offerUri: String, docTypes: Array<OfferedDocModel>, txCodeValue: ?String): IssuanceResult {
        let mapped = ArrayList<OfferedDocModel>()
        for (docType in docTypes) {
            // Batch size = min(app documentIssuanceConfig, issuer-derived), mirroring
            // iOS everywhere (resolveCredentialOptions clamps the app batch down to the
            // issuer's). issuer-derived is the value resolved on the offered model
            // (reuse-policy cap, else issuer batch_credential_issuance); the app config
            // caps it further. e.g. PROD issuer.eudiw.dev advertises batch 100 but the
            // app caps PID at 60 (matches iOS 60/60); DEV's reuse policy is 30 (< 60).
            // Without the app-config cap OHOS created 100 keys → a 148 KB /credential
            // POST that stdx TLS cannot write.
            let rule = this.walletKitConfig.documentIssuanceConfig.rule(docType.documentTypeIdentifier)
            let issuerBatch = match (docType.credentialOptions) {
                case Some(co) => co.batchSize
                case None => rule.numberOfCredentials
            }
            let policy = match (docType.credentialOptions) {
                case Some(co) => co.credentialPolicy
                case None => rule.policy
            }
            let finalBatch = if (rule.numberOfCredentials < issuerBatch) {
                rule.numberOfCredentials
            } else {
                issuerBatch
            }
            let credentialOptions = CredentialOptions(credentialPolicy: policy, batchSize: finalBatch)
            mapped.add(docType.copy(credentialOptions: credentialOptions, keyOptions: this.walletKitConfig.keyOptions))
        }
        let response = this._wallet.issueDocumentsByOfferUrl(offerUri, mapped.toArray(), txCodeValue)
        return IssuanceResult(
            documents: response.documents,
            issuerRegistration: this.makeIssuerRegistration(response.wrpIssuerPolicy, response.wrpIssuerWarnings)
        )
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public func clearAllDocuments(): Unit {
        let ids = ArrayList<String>()
        if (let Some(docs) <- safeLoadAllDocuments()) {
            for (d in docs) { ids.add(d.id) }
        }
        try { this._wallet.deleteAllDocuments() } catch (_: Exception) {}
        removeAllRegistration(ids.toArray())
    }

    public func deleteDocument(id: String, status: DocumentStatus): Unit {
        this._wallet.deleteDocument(id, status)
        this.revokedDocumentStorageController.delete(id)
    }

    public func loadDocuments(): Unit {
        try {
            let _ = this._wallet.loadAllDocuments()
        } catch (_: Exception) {}
    }

    // ── Presentation ──────────────────────────────────────────────────────────

    public func startProximityPresentation(): ProximitySessionCoordinator {
        this.stopPresentation()
        // Mirrors `wallet.openID4VpConfig = walletKitConfig.vpConfig` right before
        // beginPresentation: the Settings registration toggle applies per session
        // (the engine reads validateRegistrationCertificate for BLE here too).
        this._wallet.setOpenId4VpConfig(this.walletKitConfig.vpConfig)
        let session = this._wallet.beginPresentation(PresentationFlow.ble)
        let coordinator = this.coordinatorFactory.makeProximity(session)
        this.sessionCoordinatorHolder.setActiveProximityCoordinator(coordinator)
        return coordinator
    }

    public func startSameDevicePresentation(deepLink: ParsedUrlRef): RemoteSessionCoordinator {
        return this.startRemotePresentation(decodeDeeplink(deepLink) ?? "")
    }

    public func startCrossDevicePresentation(urlString: String): RemoteSessionCoordinator {
        return this.startRemotePresentation(urlString)
    }

    public func stopPresentation(): Unit {
        // iOS relies on ARC to release the session's transport once the holder
        // drops the coordinator; HarmonyOS has no such release, so the engine's
        // active presentation is stopped explicitly (BLE advertising / GATT
        // server teardown + ephemeral EDeviceKey deletion) before the holder is
        // cleared — cancel/back must tear the radio down immediately.
        try {
            this._wallet.stopPresentation()
        } catch (e: Exception) {
            Hilog.error(0, "VPFLOW", "stopPresentation: engine stop failed: " + e.message)
        }
        this.sessionCoordinatorHolder.clear()
    }

    // ── Fetch ─────────────────────────────────────────────────────────────────

    public func fetchAllDocuments(): Array<DocClaimsDecodable> {
        let result = ArrayList<DocClaimsDecodable>()
        for (d in this.fetchIssuedDocuments()) { result.add(d) }
        for (d in transformToDeferredDecodables(this.fetchDeferredDocuments())) { result.add(d) }
        return result.toArray()
    }

    public func fetchDeferredDocuments(): Array<WalletStorageDocument> {
        return this._wallet.storage.deferredDocuments
    }

    public func fetchIssuedDocuments(): Array<DocClaimsDecodable> {
        return this._wallet.storage.docModels
    }

    public func fetchIssuedDocuments(types!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable> {
        let rawValues = ArrayList<String>()
        for (t in types) { rawValues.add(t.rawValue) }
        let out = ArrayList<DocClaimsDecodable>()
        for (d in this._wallet.storage.docModels) {
            if (containsString(rawValues, d.docType)) { out.add(d) }
        }
        return out.toArray()
    }

    public func fetchMainPidDocument(): ?DocClaimsDecodable {
        let pids = this.fetchIssuedDocuments(types: [DocumentTypeIdentifier.mDocPid, DocumentTypeIdentifier.sdJwtPid])
        // iOS: sorted by createdAt ascending, take `.last` (the most recent).
        var best: ?DocClaimsDecodable = None
        for (d in pids) {
            match (best) {
                case None => best = d
                case Some(b) => if (d.createdAt >= b.createdAt) { best = d }
            }
        }
        return best
    }

    public func fetchIssuedDocumentsExcluding(excluded!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable> {
        let excludedRaw = ArrayList<String>()
        for (e in excluded) { excludedRaw.add(e.rawValue) }
        let out = ArrayList<DocClaimsDecodable>()
        for (d in this.fetchIssuedDocuments()) {
            if (!containsString(excludedRaw, d.docType)) { out.add(d) }
        }
        return out.toArray()
    }

    public func fetchDocument(id: String): ?DocClaimsDecodable {
        return this._wallet.storage.getDocumentModel(id)
    }

    public func fetchDocuments(ids: Array<String>): Array<DocClaimsDecodable> {
        let idList = ArrayList<String>()
        for (i in ids) { idList.add(i) }
        let documents = ArrayList<DocClaimsDecodable>()
        for (d in this.fetchIssuedDocuments()) {
            if (containsString(idList, d.id)) { documents.add(d) }
        }
        registerForDocumentIdentityExtension(documents.toArray())
        return documents.toArray()
    }

    // ── Issuance ──────────────────────────────────────────────────────────────

    public func issueDocuments(issuerId: String, identifiers: Array<String>, docTypeIdentifier: DocumentTypeIdentifier): IssuanceResult {
        let rule = this.walletKitConfig.documentIssuanceConfig.rule(docTypeIdentifier)
        let response = this._wallet.issueDocuments(
            issuerId,
            identifiers,
            CredentialOptions(credentialPolicy: rule.policy, batchSize: rule.numberOfCredentials),
            this.walletKitConfig.keyOptions
        )
        return IssuanceResult(
            documents: response.documents,
            issuerRegistration: this.makeIssuerRegistration(response.wrpIssuerPolicy, response.wrpIssuerWarnings)
        )
    }

    public func reIssueDocument(identifier!: String, isBackgroundOperation!: Bool): WalletStorageDocument {
        // Registration pre-check (iOS): a blocked issuer registration refuses the
        // re-issuance before the engine is asked to do anything.
        match (this.fetchDocument(identifier)) {
            case Some(document) =>
                match ((document.credentialIssuerIdentifier, document.configurationIdentifier)) {
                    case (Some(issuerId), Some(configId)) =>
                        match (this.getIssuerRegistration(issuerId, [configId])) {
                            case Some(registration) =>
                                match (registration) {
                                    case blocked(_) => throw RegistrationRefusedError()
                                    case _ => ()
                                }
                            case None => ()
                        }
                    case _ => ()
                }
            case None => ()
        }
        let response = this._wallet.reissueDocument(identifier, this.walletKitConfig.keyOptions, isBackgroundOperation)
        if (response.documents.size == 0) {
            throw WalletCoreError.unableToIssueAndStore()
        }
        return response.documents[0]
    }

    public func requestDeferredIssuance(doc: WalletStorageDocument): DocClaimsDecodable {
        let metadata = DocMetadata.fromBlob(doc.metadata)
        match (metadata) {
            case None => throw WalletCoreError.missingMetadata()
            case Some(m) =>
                let rule = this.walletKitConfig.documentIssuanceConfig.rule(documentTypeIdentifier(doc))
                let result = this._wallet.requestDeferredIssuance(
                    m.credentialIssuerIdentifier,
                    doc,
                    CredentialOptions(credentialPolicy: rule.policy, batchSize: rule.numberOfCredentials),
                    this.walletKitConfig.keyOptions
                )
                if (result.isDeferred) {
                    return result.transformToDeferredDecodable()
                }
                match (this.fetchDocument(result.id)) {
                    case Some(d) => return d
                    case None => throw WalletCoreError.unableFetchDocument()
                }
        }
    }

    public func resumePendingIssuance(pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef): Array<WalletStorageDocument> {
        let metadata = DocMetadata.fromBlob(pendingDoc.metadata)
        match (metadata) {
            case None => throw WalletCoreError.missingMetadata()
            case Some(m) =>
                let rule = this.walletKitConfig.documentIssuanceConfig.rule(documentTypeIdentifier(pendingDoc))
                return this._wallet.resumePendingIssuance(
                    m.credentialIssuerIdentifier,
                    pendingDoc,
                    webUrl,
                    CredentialOptions(credentialPolicy: rule.policy, batchSize: rule.numberOfCredentials),
                    this.walletKitConfig.keyOptions
                )
        }
    }

    public func retrieveLogFileUrl(): ?String {
        // iOS creates the log file/dir under the engine log path; with no engine
        // log path available (EudiWallet.getLogFileURL returns nil), mirror nil.
        return WalletKitImpl.getLogFileURL(this.walletKitConfig.logFileName)
    }

    public func storeDynamicIssuancePendingUrl(url: ParsedUrlRef): Unit {
        this.keyChainController.storeValue(
            KeyIdentifier.dynamicIssuancePendingUrl,
            parsedUrlToString(url)
        )
    }

    public func getDynamicIssuancePendingData(): ?DynamicIssuancePendingData {
        synchronized(this.dynamicIssuanceLock) {
            let urlString = this.keyChainController.getValue(KeyIdentifier.dynamicIssuancePendingUrl)
            match (urlString) {
                case None => return None
                case Some(s) =>
                    let parsed = toCompatibleUrl(s)
                    match (parsed) {
                        case None => return None
                        case Some(url) =>
                            this.keyChainController.removeObject(KeyIdentifier.dynamicIssuancePendingUrl)
                            let pending = this._wallet.storage.pendingDocuments
                            if (pending.size == 0) { return None }
                            // The keychain holds the exact authorization URL stored at
                            // issue time (issuance_interactor stores `pendingAuthUrl(doc)`).
                            // Match the pending document by that URL rather than taking the
                            // unordered collection's last entry: with one-offer/many-config
                            // issuance several pending docs may exist and they all share the
                            // same authorization URL, but positional `last` is still wrong
                            // for any non-shared/legacy case. Resume then signs out the whole
                            // sibling batch from the matched doc.
                            var matched: ?WalletStorageDocument = None
                            var i: Int64 = 0
                            while (i < pending.size) {
                                let doc = pending[i]
                                match (doc.metadata) {
                                    case Some(blob) =>
                                        match (blob.pendingAuthorizationUrl) {
                                            case Some(authUrl) =>
                                                if (authUrl == s) {
                                                    matched = Some(doc)
                                                }
                                            case None => ()
                                        }
                                    case None => ()
                                }
                                i++
                            }
                            let pendingDoc = match (matched) {
                                case Some(d) => d
                                case None =>
                                    // No URL-keyed match (e.g. legacy metadata without a
                                    // stored authorization URL): take the NEWEST pending by
                                    // createdAt. Positional `last` picked whatever the
                                    // unordered store returned — with stale pendings from
                                    // aborted runs piled up, that resumed a days-old
                                    // document whose parse then failed with an empty-message
                                    // exception ("Unable to issue and store…").
                                    var newest = pending[0]
                                    var k: Int64 = 1
                                    while (k < pending.size) {
                                        if (pending[k].createdAt > newest.createdAt) {
                                            newest = pending[k]
                                        }
                                        k++
                                    }
                                    newest
                            }
                            return DynamicIssuancePendingData(pendingDoc: pendingDoc, url: url)
                    }
            }
        }
    }

    public func getScopedDocuments(): CoreScopedDocumentsResult {
        // iOS fans out over issuers concurrently in a task group of Results;
        // here issuers are queried in sequence (same total result), each via
        // getIssuerMetadata, partitioning per-issuer failures instead of letting
        // one failing issuer kill the whole Add-document list. Non-throwing.
        let issuersConfig = this.walletKitConfig.issuersConfig
        let documents = ArrayList<ScopedDocument>()
        let errors = ArrayList<Exception>()
        for ((issuerName, orderedVciConfig) in issuersConfig) {
            try {
                let metadata = this._wallet.getIssuerMetadata(issuerName)
                let host = hostOrFallback(metadata.credentialIssuerIdentifier, issuerName)
                for ((configKey, credential) in metadata.credentialsSupported) {
                    match (credential) {
                        case msoMdoc(config) =>
                            let id = DocumentTypeIdentifier.fromRawValue(config.docType)
                            documents.add(ScopedDocument(
                                name: credentialName(config.credentialMetadata, configKey),
                                issuer: host,
                                order: orderedVciConfig.order,
                                configId: configKey,
                                isPid: id == DocumentTypeIdentifier.mDocPid,
                                docTypeIdentifier: id
                            ))
                        case sdJwtVc(config) =>
                            match (config.vct) {
                                case None => ()
                                case Some(vct) =>
                                    let id = DocumentTypeIdentifier.fromRawValue(vct)
                                    documents.add(ScopedDocument(
                                        name: credentialName(config.credentialMetadata, configKey),
                                        issuer: host,
                                        order: orderedVciConfig.order,
                                        configId: configKey,
                                        isPid: id == DocumentTypeIdentifier.sdJwtPid,
                                        docTypeIdentifier: id
                                    ))
                            }
                        case _ => ()
                    }
                }
            } catch (e: Exception) {
                errors.add(e)
            }
        }
        return CoreScopedDocumentsResult(
            documents: documents.toArray(),
            errors: errors.toArray(),
            totalIssuers: Int64(issuersConfig.size)
        )
    }

    public func isDocumentLowOnCredentials(document: ?DocClaimsDecodable): Bool {
        match (document) {
            case Some(doc) =>
                match (doc.credentialsUsageCounts) {
                    case Some(counts) => doc.credentialPolicy == CredentialPolicy.oneTimeUse && counts.remaining <= 1
                    case None => false
                }
            case None => false
        }
    }

    public func getDocumentCategories(): DocumentCategories {
        return this.walletKitConfig.documentsCategories.sortedByOrder()
    }

    // ── Registration-certificate (WRPRC) trust layer ─────────────────────────

    /**
     * Mirrors `isIssuerRegistrationEnforced`: the issuer side refuses only when
     * the Settings toggle is on AND the VCI registration policy is Enforce.
     */
    private prop isIssuerRegistrationEnforced: Bool {
        get() {
            if (!this.walletKitConfig.validateIssuerRegistrationCertificate) { return false }
            match (this.walletKitConfig.trustConfiguration.wrprcVciTrustPolicy) {
                case TrustPolicy.Enforce => return true
                case _ => return false
            }
        }
    }

    /**
     * Mirrors `makeIssuerRegistration(policy:warnings:)` — the issuer-side WRPRC
     * decision table:
     *  1. no policy → `.blocked(notRegisteredAsProvider)` when enforced, else None
     *  2. any `.credentialNotCovered` warning → `.blocked(attestationNotRegistered)`
     *  3. any other warning → `.blocked(notRegisteredAsProvider)`
     *  4. none → `.verified(details)` from the decoded policy subject.
     */
    private func makeIssuerRegistration(
        policy: ?WrpRegistrationPolicy,
        warnings: ?HashMap<String, Array<RegistrationPolicyViolation>>
    ): ?IssuerRegistration {
        let p = match (policy) {
            case None =>
                if (this.isIssuerRegistrationEnforced) {
                    return Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.notRegisteredAsProvider))
                }
                return None
            case Some(value) => value
        }

        let raised = ArrayList<RegistrationPolicyViolation>()
        match (warnings) {
            case Some(map) =>
                for ((_, violations) in map) {
                    for (v in violations) { raised.add(v) }
                }
            case None => ()
        }

        for (violation in raised) {
            if (violation.reason.isCredentialNotCovered()) {
                return Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.attestationNotRegistered))
            }
        }
        if (raised.size > 0) {
            return Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.notRegisteredAsProvider))
        }

        return Some(IssuerRegistration.verified(RegistrationDetails(
            tradeName: p.name ?? p.sub,
            uniqueId: p.sub,
            logoUrl: None,
            intendedUse: localizedPolicyPurposeValue(p.purpose),
            privacyPolicyUrl: p.privacyPolicy,
            serviceDescription: localizedPolicyPurposeValue(p.srvDescription)
        )))
    }

    /** Mirrors `getIssuerRegistration(for:)` — the verdict captured while the
     *  offer was resolved; no network. */
    public func getIssuerRegistration(offer: OfferedIssuanceModel): ?IssuerRegistration {
        return this.makeIssuerRegistration(offer.wrpVciRegistrationPolicy, offer.wrpVciWarnings)
    }

    /** Mirrors `getIssuerRegistration(issuerId:configIds:)` — iOS `try?`: any
     *  thrown error yields None (not evaluated, which vouches). */
    public func getIssuerRegistration(issuerId: String, configIds: Array<String>): ?IssuerRegistration {
        var response: EngineIssuerResponse
        try {
            response = this._wallet.resolveIssuerRegistration(issuerId, configIds)
        } catch (_: Exception) {
            return None
        }
        return this.makeIssuerRegistration(response.wrpIssuerPolicy, response.wrpIssuerWarnings)
    }

    /**
     * Mirrors `getVerifierRegistration(...)` — the verifier-side decision table.
     * With the toggle off, everything collapses to the `.notSupported` baseline
     * (nothing resolved / refused / displayed).
     */
    public func getVerifierRegistration(
        policy: ?WrpRegistrationPolicy,
        trustViolations: Array<String>,
        overaskedClaims: Array<OveraskedClaim>,
        verifierName: ?String,
        verifierIsTrusted: Bool
    ): RelyingPartyRegistration {
        let unregistered = RelyingPartyRegistration(
            name: verifierName,
            uniqueId: None,
            isVerified: verifierIsTrusted,
            logoUrl: None,
            registration: RegistrationStatus.notSupported
        )

        if (!this.walletKitConfig.validateIssuerRegistrationCertificate) { return unregistered }

        let p = match (policy) {
            case None =>
                if (trustViolations.size == 0) { return unregistered }
                return RelyingPartyRegistration(
                    name: verifierName,
                    uniqueId: None,
                    isVerified: verifierIsTrusted,
                    logoUrl: None,
                    registration: RegistrationStatus.notVerified(None)
                )
            case Some(value) => value
        }

        let subjectDetails = RegistrationDetails(
            tradeName: p.name ?? p.sub,
            uniqueId: p.sub,
            logoUrl: None,
            intendedUse: localizedPolicyPurposeValue(p.purpose),
            privacyPolicyUrl: p.privacyPolicy,
            serviceDescription: localizedPolicyPurposeValue(p.srvDescription)
        )

        let status: RegistrationStatus = if (trustViolations.size == 0) {
            RegistrationStatus.verified(subjectDetails, overaskedClaims)
        } else {
            RegistrationStatus.notVerified(Some(subjectDetails))
        }

        return RelyingPartyRegistration(
            name: status.resolveRequesterName(
                registrationName: p.name,
                accessCertificateName: verifierName
            ),
            uniqueId: Some(p.sub),
            isVerified: verifierIsTrusted,
            logoUrl: None,
            registration: status
        )
    }

    /** Mirrors `getVerifierRegistrationForFailedRequest()` — an unsatisfiable
     *  request still shows who asked (from the per-session VP validator). */
    public func getVerifierRegistrationForFailedRequest(): ?RelyingPartyRegistration {
        match (this._wallet.wrpVpRegistrationPolicy) {
            case None => return None
            case Some(policy) =>
                return Some(this.getVerifierRegistration(
                    Some(policy),
                    Array<String>(),
                    Array<OveraskedClaim>(),
                    None,
                    false
                ))
        }
    }

    // ── Bookmarks ─────────────────────────────────────────────────────────────

    public func isDocumentBookmarked(id: String): Bool {
        try {
            let _ = this.bookmarkStorageController.retrieve(id)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public func storeBookmarkedDocument(id: String): Unit {
        this.bookmarkStorageController.store(Bookmark(id))
    }

    public func removeBookmarkedDocument(id: String): Unit {
        this.bookmarkStorageController.delete(id)
    }

    // ── Transaction logs ──────────────────────────────────────────────────────

    public func fetchTransactionLog(id: String): TransactionLogItem {
        try {
            let storedLog = this.transactionLogStorageController.retrieve(id)
            let self0 = this
            return toTransactionLogItem(storedLog, storedLog.identifier, { log => self0._wallet.parseTransactionLog(log) })
        } catch (_: Exception) {
            throw WalletCoreError.unableToFetchTransactionLog()
        }
    }

    /**
     * Record a completed presentation as a transaction-log entry (iOS logs it in
     * PresentationSession.sendResponse via the injected TransactionLogger). The
     * value is a small JSON blob `{ts, rp, docs, status}` so the History tab can
     * recover the real timestamp + relying-party name (StorageTransactionLog has
     * no timestamp field of its own).
     *
     * Resolves the presenter name from the active session's reader certificate
     * chain (iOS `TransactionLog.withPresenterName()` is applied before
     * encoding); see the presenterName overload below.
     */
    public func logPresentation(relyingPartyName: String, docLabels: Array<String>): Unit {
        this.logPresentation(relyingPartyName, docLabels, this.resolveActivePresenterName())
    }

    /**
     * As above with an explicit presenter name. Mirrors iOS
     * `TransactionLog.withPresenterName()` semantics: the subject CN of the
     * reader certificate chain head overrides the relying-party display name
     * only when non-empty; otherwise the given name is kept.
     */
    public func logPresentation(relyingPartyName: String, docLabels: Array<String>, presenterName: ?String): Unit {
        let effectiveRelyingParty = match (presenterName) {
            case Some(name) where !name.isEmpty() => name
            case _ => relyingPartyName
        }
        let ts = DateTime.now().toUnixTimeStamp().toMilliseconds() / 1000
        var docs = ""
        var i = 0
        while (i < docLabels.size) {
            if (i > 0) { docs += ", " }
            docs += docLabels[i]
            i++
        }
        try {
            let value = encodePresentationTransactionValue(ts, effectiveRelyingParty, docs)
            // Transaction logs are persistent, so their identifiers must also be
            // unique across process restarts. `newUuid()` is only a process-local
            // counter (group-0, group-1, ...); using it here overwrote an older
            // History row whenever the application restarted and presented again.
            this.transactionLogStorageController.store(
                StorageTransactionLog(newTransactionLogIdentifier(), value)
            )
            NotificationCenter.post(NotificationName.TransactionTabRefresh)
        } catch (e: Exception) {
            Hilog.error(0, "VPFLOW", "logPresentation store failed: " + e.message)
        }
    }

    /**
     * Presenter CN from whichever presentation session is still active: remote
     * (OpenID4VP) first, then proximity (BLE). None when no coordinator is
     * active or the chain head carries no usable CN — the caller then keeps the
     * relying-party display name it already has.
     */
    private func resolveActivePresenterName(): ?String {
        try {
            let chain = this.sessionCoordinatorHolder.getActiveRemoteCoordinator().readerCertificateChain
            match (presenterNameFromCertificateChain(chain)) {
                case Some(name) => return Some(name)
                case None => ()
            }
        } catch (_: Exception) {}
        try {
            let chain = this.sessionCoordinatorHolder.getActiveProximityCoordinator().readerCertificateChain
            return presenterNameFromCertificateChain(chain)
        } catch (_: Exception) {
            return None
        }
    }

    public func fetchTransactionLogs(): Array<TransactionLogItem> {
        var storedLogs: Array<StorageTransactionLog>
        try {
            storedLogs = this.transactionLogStorageController.retrieveAll()
        } catch (_: StorageError) {
            // Empty store (retrieveAll throws itemsNotFound when there are no
            // logs) is an empty wallet, not an error — mirror iOS `try?` which
            // turns the empty-store throw into an empty result. Returning []
            // lets the UI render its empty state instead of an error/spinner.
            return Array<TransactionLogItem>()
        } catch (_: Exception) {
            throw WalletCoreError.unableToFetchTransactionLog()
        }
        let out = ArrayList<TransactionLogItem>()
        let self0 = this
        for (log in storedLogs) {
            try {
                out.add(toTransactionLogItem(log, log.identifier, { l => self0._wallet.parseTransactionLog(l) }))
            } catch (_: Exception) {
                // iOS compactMap drops the entries that fail to parse.
            }
        }
        return out.toArray()
    }

    // ── Revocation ────────────────────────────────────────────────────────────

    public func fetchRevokedDocuments(): Array<String> {
        let all = this.revokedDocumentStorageController.retrieveAll()
        let out = ArrayList<String>()
        for (r in all) { out.add(r.identifier) }
        return out.toArray()
    }

    public func storeRevokedDocuments(ids: Array<String>): Unit {
        let docs = Array<RevokedDocument>(ids.size, { i => RevokedDocument(ids[i]) })
        this.revokedDocumentStorageController.store(docs)
    }

    public func removeRevokedDocument(id: String): Unit {
        this.revokedDocumentStorageController.delete(id)
    }

    public func isDocumentRevoked(id: String): Bool {
        try {
            let _ = this.revokedDocumentStorageController.retrieve(id)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public func getDocumentStatus(statusIdentifier: StatusIdentifier): CredentialStatus {
        return this._wallet.getDocumentStatus(statusIdentifier)
    }

    // ── Failed re-issued docs ─────────────────────────────────────────────────

    public func storeFailedReIssuedDocuments(ids: Array<String>): Unit {
        let docs = Array<FailedReIssuedDocument>(ids.size, { i => FailedReIssuedDocument(ids[i]) })
        this.failedReIssuedDocStorageController.store(docs)
    }

    public func removeAllFailedReIssuedDocuments(): Unit {
        this.failedReIssuedDocStorageController.deleteAll()
    }

    public func refreshUsageCounters(): Unit {
        this._wallet.refreshUsageCounters()
    }

    // ── parseDocClaim (the recursive claim flattener) ─────────────────────────

    public func parseDocClaim(docId: String, groupId: String, docClaim: DocClaim, claimType: DocumentElementType, parser: (String) -> String): Array<DocumentElementClaim> {
        return parseDocClaimImpl(docId, groupId, docClaim, claimType, parser)
    }

    // ── private helpers (mirror the private extension on the controller) ──────

    private func safeLoadAllDocuments(): ?Array<WalletStorageDocument> {
        try {
            return this._wallet.loadAllDocuments()
        } catch (_: Exception) {
            return None
        }
    }

    private func registerForDocumentIdentityExtension(documents: Array<DocClaimsDecodable>): Unit {
        // iOS spawns a Task that, on iOS 26 + cbor docs, registers with the OS
        // document store. The HarmonyOS registration manager is the no-op path
        // (no OS document store), so registration runs and is a no-op — faithful
        // to every device lacking IdentityDocumentServices.
        for (document in documents) {
            if (document.docDataFormat == DocDataFormat.cbor) {
                try {
                    this.documentRegistrationManager.addRegistration(
                        document.docType,
                        Array<Array<UInt8>>(),
                        document.id,
                        document.validUntil
                    )
                } catch (_: Exception) {
                    // iOS rethrows as WalletCoreError.unableFetchDocuments inside the
                    // detached task; here the no-op manager never throws.
                }
            }
        }
    }

    private func removeAllRegistration(ids: Array<String>): Unit {
        if (ids.size == 0) { return }
        try {
            this.documentRegistrationManager.removeRegistration(ids)
        } catch (_: Exception) {}
    }

    private func decodeDeeplink(link: ParsedUrlRef): ?String {
        return removeSchemeFromComponents(parsedUrlToString(link))
    }

    private func startRemotePresentation(urlString: String): RemoteSessionCoordinator {
        Hilog.info(0, "VPFLOW", "startRemotePresentation len=" + urlString.size.toString())
        this.stopPresentation()
        // Mirrors `wallet.openID4VpConfig = walletKitConfig.vpConfig` right before
        // beginPresentation (Settings registration toggle applies per session).
        this._wallet.setOpenId4VpConfig(this.walletKitConfig.vpConfig)
        let data = urlString.toArray()
        let session = this._wallet.beginPresentation(PresentationFlow.openid4vp(data))
        let coordinator = this.coordinatorFactory.makeRemote(session)
        this.sessionCoordinatorHolder.setActiveRemoteCoordinator(coordinator)
        return coordinator
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// parseDocClaim — the recursive claim flattener (free function so the interface
// default extension in iOS maps cleanly).
// ─────────────────────────────────────────────────────────────────────────────

func parseDocClaimImpl(docId: String, groupId: String, docClaim: DocClaim, claimType: DocumentElementType, parser: (String) -> String): Array<DocumentElementClaim> {
    func shouldGroup(title: String, children: Array<DocClaim>): Bool {
        if (children.size <= 1 || title.isEmpty()) { return false }
        for (c in children) {
            if (c.children.isNone()) { return false }
        }
        return true
    }

    match (docClaim.children) {
        case Some(children) where children.size > 0 =>
            let title = StringUtil.ifNilOrEmpty(docClaim.displayName, { => docClaim.name })
            if (shouldGroup(title, children)) {
                let grouped = ArrayList<DocumentElementClaim>()
                var index = 0
                for (entry in children) {
                    let inner = entry.children ?? Array<DocClaim>()
                    let innerClaims = ArrayList<DocumentElementClaim>()
                    for (ic in inner) {
                        for (parsed in parseDocClaimImpl(docId, groupId, ic, claimType, parser)) {
                            innerClaims.add(parsed)
                        }
                    }
                    grouped.add(DocumentElementClaim.group(
                        newUuid(),
                        "${title} ${index + 1}",
                        sortByName(innerClaims.toArray())
                    ))
                    index++
                }
                return [DocumentElementClaim.group(newUuid(), title, grouped.toArray())]
            } else {
                let childClaims = ArrayList<DocumentElementClaim>()
                for (c in children) {
                    for (parsed in parseDocClaimImpl(docId, groupId, c, claimType, parser)) {
                        childClaims.add(parsed)
                    }
                }
                let sorted = sortByName(childClaims.toArray())
                if (title.isEmpty()) {
                    return sorted
                }
                return [DocumentElementClaim.group(newUuid(), title, sorted)]
            }
        case _ => ()
    }

    // primitive value
    let value = buildPrimitiveValue(docClaim, parser)
    return [DocumentElementClaim.primitive(
        groupId,
        StringUtil.ifNilOrEmpty(docClaim.displayName, { => docClaim.name }),
        docId,
        docClaim.namespace,
        docClaim.path,
        claimType,
        value,
        DocumentElementClaimStatus.available(false)
    )]
}

func buildPrimitiveValue(docClaim: DocClaim, parser: (String) -> String): DocumentElementValue {
    match (docClaim.dataValue.image) {
        case Some(bytes) => return DocumentElementValue.image(bytes)
        case None =>
            let parsed = parseUserPseudonym(parseDate(docClaim, parser))
            return DocumentElementValue.string(parsed.stringValue)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small controller helpers
// ─────────────────────────────────────────────────────────────────────────────

func containsString(list: ArrayList<String>, value: String): Bool {
    for (s in list) {
        if (s == value) { return true }
    }
    return false
}

func credentialName(metadata: ?CredentialMetadata, fallback: String): String {
    match (metadata) {
        case Some(m) => getDisplayName(m.display, fallback)
        case None => fallback
    }
}

func hostOrFallback(issuerIdentifier: String, fallback: String): String {
    match (toCompatibleUrl(issuerIdentifier)) {
        case Some(parsed) =>
            match (parsed.host) {
                case Some(h) where !h.isEmpty() => h
                case _ => fallback
            }
        case None => fallback
    }
}

func parsedUrlToString(url: ParsedUrlRef): String {
    let sb = StringBuilder()
    match (url.scheme) {
        case Some(s) => sb.append(s); sb.append("://")
        case None => ()
    }
    match (url.host) {
        case Some(h) => sb.append(h)
        case None => ()
    }
    sb.append(url.path)
    match (url.query) {
        case Some(q) => sb.append("?"); sb.append(q)
        case None => ()
    }
    match (url.fragment) {
        case Some(f) => sb.append("#"); sb.append(f)
        case None => ()
    }
    return sb.toString()
}

let uuidCounter = AtomicInt64(0)

// Extra sequence protects the (rare but valid) case where two transaction logs
// are produced in the same millisecond. The wall-clock component keeps the id
// unique after a process restart, unlike `uuidCounter` on its own.
let transactionLogIdCounter = AtomicInt64(0)

/** Mirrors iOS `UUID().uuidString` for synthesised group ids. */
func newUuid(): String {
    let n = uuidCounter.fetchAdd(1)
    return "group-${n}"
}

/** Persistent transaction identifier; mirrors iOS `UUID().uuidString` semantics. */
func newTransactionLogIdentifier(): String {
    let millis = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let sequence = transactionLogIdCounter.fetchAdd(1)
    return "transaction-${millis}-${sequence}"
}
