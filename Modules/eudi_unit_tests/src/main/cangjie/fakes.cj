// Shared fake implementations for device unit tests.
//
// Used by dev_tests_*.cj files in this same package. All fakes are hand-written
// (no Cuckoo) to stay headless-safe: no real engine, no keychain, no I/O.
//
// DO NOT use in production code. Only the dev_tests_* files should reference
// these classes.
package eudi_unit_tests

import std.collection.HashMap
import std.time.DateTime
import eudi_logic_core.{
    WalletKitController, WalletKit,
    DocClaimsDecodable, WalletStorageDocument,
    DocumentStatus, DocDataFormat, DocMetadataBlob,
    ProximitySessionCoordinator, RemoteSessionCoordinator,
    OfferedIssuanceModel, OfferedDocModel,
    DocumentTypeIdentifier, DocumentCategories,
    TransactionLogItem, TransactionLogData,
    DynamicIssuancePendingData,
    ScopedDocument, CoreScopedDocumentsResult,
    IssuanceResult, IssuerRegistration,
    RelyingPartyRegistration, RegistrationStatus, OveraskedClaim,
    CredentialStatus, CredentialPolicy,
    StatusIdentifier, CredentialsUsageCounts,
    DisplayMetadata,
    DocClaim, DocDataValue, DocumentElementType, DocumentElementClaim,
    ParsedUrlRef
}
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy
import eudi_logic_business.{ParsedUrl}
import eudi_feature_common.{
    BiometryController, BiometryType, BiometryAvailability, BiometryError,
    BiometryUnlockResult
}

// ─────────────────────────────────────────────────────────────────────────────
// Test data builders
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Construct a minimal IssuedDocument (which implements DocClaimsDecodable) for
 * use in fake controller fields. All fields have test-friendly defaults; callers
 * can override any named parameter.
 *
 * Example:
 *   fakeController.allDocuments = [makeDocClaimsDecodable(id: "d1", docType: "org.iso.18013.5.1.mDL")]
 */
// Minimal DocClaimsDecodable impl (18 props) — avoids the heavy IssuedDocument
// constructor; only id/docType/displayName/format/policy/createdAt are meaningful.
class FakeDocClaims <: DocClaimsDecodable {
    let id_: String
    let docType_: String
    let displayName_: ?String
    let docDataFormat_: DocDataFormat
    let credentialPolicy_: CredentialPolicy
    let createdAt_: DateTime
    init(id_: String, docType_: String, displayName_: ?String, docDataFormat_: DocDataFormat,
         credentialPolicy_: CredentialPolicy, createdAt_: DateTime) {
        this.id_ = id_
        this.docType_ = docType_
        this.displayName_ = displayName_
        this.docDataFormat_ = docDataFormat_
        this.credentialPolicy_ = credentialPolicy_
        this.createdAt_ = createdAt_
    }
    public prop id: String { get() { this.id_ } }
    public prop statusIdentifier: ?StatusIdentifier { get() { None } }
    public prop createdAt: DateTime { get() { this.createdAt_ } }
    public prop modifiedAt: ?DateTime { get() { None } }
    public prop displayName: ?String { get() { this.displayName_ } }
    public prop docType: String { get() { this.docType_ } }
    public prop docClaims: Array<DocClaim> { get() { Array<DocClaim>() } }
    public prop docDataFormat: DocDataFormat { get() { this.docDataFormat_ } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { HashMap<Int64, Bool>() } }
    public prop display: ?Array<DisplayMetadata> { get() { None } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { None } }
    public prop credentialIssuerIdentifier: ?String { get() { None } }
    public prop configurationIdentifier: ?String { get() { None } }
    public prop validFrom: ?DateTime { get() { None } }
    public prop validUntil: ?DateTime { get() { None } }
    public prop secureAreaName: ?String { get() { None } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { None } }
    public prop credentialPolicy: CredentialPolicy { get() { this.credentialPolicy_ } }
}

public func makeDocClaimsDecodable(
    id!: String = "fake-doc-id",
    docType!: String = "eu.europa.ec.eudi.pid.1",
    displayName!: ?String = Some("Fake Document"),
    docDataFormat!: DocDataFormat = DocDataFormat.cbor,
    credentialPolicy!: CredentialPolicy = CredentialPolicy.rotateUse,
    createdAt!: DateTime = DateTime.now()
): DocClaimsDecodable {
    return FakeDocClaims(id, docType, displayName, docDataFormat, credentialPolicy, createdAt)
}

/**
 * Construct a minimal WalletStorageDocument for use in fake controller fields.
 *
 * Example:
 *   fakeController.deferredDocuments = [makeWalletStorageDocument(id: "def1", status: DocumentStatus.deferred)]
 */
public func makeWalletStorageDocument(
    id!: String = "fake-storage-doc-id",
    docType!: String = "eu.europa.ec.eudi.pid.1",
    docDataFormat!: DocDataFormat = DocDataFormat.cbor,
    createdAt!: DateTime = DateTime.now(),
    metadata!: ?DocMetadataBlob = None,
    status!: DocumentStatus = DocumentStatus.issued
): WalletStorageDocument {
    return WalletStorageDocument(
        id: id,
        docType: docType,
        docDataFormat: docDataFormat,
        createdAt: createdAt,
        metadata: metadata,
        status: status
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// FakeWalletKitController
// ─────────────────────────────────────────────────────────────────────────────

/**
 * In-memory fake implementation of WalletKitController for unit tests.
 *
 * Design:
 *   - Methods returning Array<X>  → configurable public var (default []).
 *   - Methods returning ?X        → configurable public var (default None).
 *   - Methods returning Unit      → call counter public var (default 0).
 *   - Methods returning complex objects that are hard to construct headlessly
 *     → throw Exception("fake: <method> not configured") so tests that do not
 *       call them pass silently, and tests that do call them get a clear error.
 *   - Methods whose production caller has a catch branch → an opt-in
 *     `<method>ShouldThrow` flag (default false). Without it the error path is
 *     unreachable from tests, which is how iOS's delete/fetch failure cases
 *     ended up with no Cangjie coverage.
 *
 * wallet prop is required by the interface. The fake throws on access because
 * no real WalletKit is needed for headless tests; wire a real one only if a
 * test truly needs it.
 */
public open class FakeWalletKitController <: WalletKitController {

    // ── wallet prop ──────────────────────────────────────────────────────────
    // Required by the interface; headless tests must not call this.
    public open prop wallet: WalletKit {
        get() { throw Exception("fake: wallet prop not configured") }
    }

    // ── configurable return values ────────────────────────────────────────────

    /** Returned by fetchAllDocuments(). */
    public var allDocuments: Array<DocClaimsDecodable> = Array<DocClaimsDecodable>()

    /** Returned by fetchDeferredDocuments(). */
    public var deferredDocuments: Array<WalletStorageDocument> = Array<WalletStorageDocument>()

    /** Returned by fetchIssuedDocuments() (no-arg variant). */
    public var issuedDocuments: Array<DocClaimsDecodable> = Array<DocClaimsDecodable>()

    /** Returned by fetchIssuedDocuments(types:). */
    public var issuedDocumentsByType: Array<DocClaimsDecodable> = Array<DocClaimsDecodable>()

    /** Returned by fetchIssuedDocumentsExcluding(excluded:). */
    public var issuedDocumentsExcluding: Array<DocClaimsDecodable> = Array<DocClaimsDecodable>()

    /** Returned by fetchMainPidDocument(). */
    public var mainPidDocument: ?DocClaimsDecodable = None

    /** Returned by fetchDocument(id:). */
    public var documentById: ?DocClaimsDecodable = None

    /** Returned by fetchDocuments(ids:). */
    public var documentsByIds: Array<DocClaimsDecodable> = Array<DocClaimsDecodable>()

    /** Documents of the IssuanceResult returned by issueDocuments(...). */
    public var issuedStorageDocuments: Array<WalletStorageDocument> = Array<WalletStorageDocument>()

    /** Issuer verdict of the IssuanceResult returned by issueDocuments(...)
     *  (None vouches — iOS `Optional<IssuerRegistration>.vouchesForIssuer`). */
    public var issuedRegistration: ?IssuerRegistration = None

    /** Documents of the IssuanceResult returned by issueDocumentsByOfferUrl(...). */
    public var issuedByOfferDocuments: Array<WalletStorageDocument> = Array<WalletStorageDocument>()

    /** Issuer verdict of the IssuanceResult returned by issueDocumentsByOfferUrl(...). */
    public var issuedByOfferRegistration: ?IssuerRegistration = None

    /** Returned by fetchTransactionLogs(). */
    public var transactionLogs: Array<TransactionLogItem> = Array<TransactionLogItem>()

    /** Documents of the CoreScopedDocumentsResult returned by getScopedDocuments(). */
    public var scopedDocuments: Array<ScopedDocument> = Array<ScopedDocument>()

    /** Per-issuer errors of the CoreScopedDocumentsResult (default none). */
    public var scopedErrors: Array<Exception> = Array<Exception>()

    /** totalIssuers of the CoreScopedDocumentsResult (default 1 → allIssuersFailed
     *  only when scopedErrors carries exactly one error). */
    public var scopedTotalIssuers: Int64 = 1

    /** Returned by both getIssuerRegistration overloads (offer / issuerId+configIds). */
    public var issuerRegistrationResult: ?IssuerRegistration = None

    /** When Some, returned by getVerifierRegistration(...) as-is; when None a
     *  minimal `.notSupported` baseline is derived from the call arguments. */
    public var verifierRegistrationResult: ?RelyingPartyRegistration = None

    /** Returned by getVerifierRegistrationForFailedRequest(). */
    public var failedRequestRegistration: ?RelyingPartyRegistration = None

    /** Returned by fetchRevokedDocuments(). */
    public var revokedDocumentIds: Array<String> = Array<String>()

    /** Returned by getDynamicIssuancePendingData(). */
    public var dynamicIssuancePendingData: ?DynamicIssuancePendingData = None

    /** Returned by isDocumentBookmarked(id:). */
    public var bookmarkedResult: Bool = false

    /** Returned by isDocumentRevoked(id:). */
    public var documentRevokedResult: Bool = false

    /** Returned by isDocumentLowOnCredentials(document:). */
    public var lowOnCredentialsResult: Bool = false

    /** Returned by getDocumentStatus(statusIdentifier:). */
    public var documentStatus: CredentialStatus = CredentialStatus.valid

    /** Returned by retrieveLogFileUrl(). */
    public var logFileUrl: ?String = None

    // ── call counters (Unit-returning methods) ────────────────────────────────

    public var stopPresentationCalls: Int64 = 0
    public var clearAllDocumentsCalls: Int64 = 0
    public var loadDocumentsCalls: Int64 = 0
    public var deleteDocumentCalls: Int64 = 0
    public var lastDeletedDocumentId: String = ""
    public var lastDeletedDocumentStatus: DocumentStatus = DocumentStatus.issued
    public var storeDynamicIssuancePendingUrlCalls: Int64 = 0
    public var storeBookmarkedDocumentCalls: Int64 = 0
    public var removeBookmarkedDocumentCalls: Int64 = 0
    public var storeRevokedDocumentsCalls: Int64 = 0
    public var removeRevokedDocumentCalls: Int64 = 0
    public var storeFailedReIssuedDocumentsCalls: Int64 = 0
    public var removeAllFailedReIssuedDocumentsCalls: Int64 = 0
    public var refreshUsageCountersCalls: Int64 = 0
    /** logPresentation(...) call count + the last relying-party name / doc labels / presenter passed. */
    public var logPresentationCalls: Int64 = 0
    public var lastLoggedRelyingParty: String = ""
    public var lastLoggedDocLabels: Array<String> = Array<String>()
    public var lastLoggedPresenterName: ?String = None

    public init() {}

    // ── Presentation ──────────────────────────────────────────────────────────

    public open func startProximityPresentation(): ProximitySessionCoordinator {
        throw Exception("fake: startProximityPresentation not configured")
    }

    public open func startSameDevicePresentation(deepLink: ParsedUrlRef): RemoteSessionCoordinator {
        throw Exception("fake: startSameDevicePresentation not configured")
    }

    public open func startCrossDevicePresentation(urlString: String): RemoteSessionCoordinator {
        throw Exception("fake: startCrossDevicePresentation not configured")
    }

    public open func stopPresentation(): Unit {
        this.stopPresentationCalls += 1
    }

    // ── Fetch ─────────────────────────────────────────────────────────────────

    public open func fetchAllDocuments(): Array<DocClaimsDecodable> {
        return this.allDocuments
    }

    public open func fetchDeferredDocuments(): Array<WalletStorageDocument> {
        return this.deferredDocuments
    }

    public open func fetchIssuedDocuments(): Array<DocClaimsDecodable> {
        return this.issuedDocuments
    }

    public open func fetchIssuedDocuments(types!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable> {
        return this.issuedDocumentsByType
    }

    public open func fetchIssuedDocumentsExcluding(excluded!: Array<DocumentTypeIdentifier>): Array<DocClaimsDecodable> {
        return this.issuedDocumentsExcluding
    }

    public open func fetchMainPidDocument(): ?DocClaimsDecodable {
        return this.mainPidDocument
    }

    public open func fetchDocument(id: String): ?DocClaimsDecodable {
        return this.documentById
    }

    public open func fetchDocuments(ids: Array<String>): Array<DocClaimsDecodable> {
        return this.documentsByIds
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public open func clearAllDocuments(): Unit {
        this.clearAllDocumentsCalls += 1
    }

    /** When true, deleteDocument() throws — drives the interactor's catch→false path. */
    public var deleteDocumentShouldThrow: Bool = false

    public open func deleteDocument(id: String, status: DocumentStatus): Unit {
        this.deleteDocumentCalls += 1
        this.lastDeletedDocumentId = id
        this.lastDeletedDocumentStatus = status
        if (this.deleteDocumentShouldThrow) {
            throw Exception("fake: deleteDocument failed")
        }
    }

    public open func loadDocuments(): Unit {
        this.loadDocumentsCalls += 1
    }

    // ── Issuance ──────────────────────────────────────────────────────────────

    public open func issueDocuments(issuerId: String, identifiers: Array<String>, docTypeIdentifier: DocumentTypeIdentifier): IssuanceResult {
        return IssuanceResult(documents: this.issuedStorageDocuments, issuerRegistration: this.issuedRegistration)
    }

    public open func reIssueDocument(identifier!: String, isBackgroundOperation!: Bool): WalletStorageDocument {
        throw Exception("fake: reIssueDocument not configured")
    }

    public open func requestDeferredIssuance(doc: WalletStorageDocument): DocClaimsDecodable {
        throw Exception("fake: requestDeferredIssuance not configured")
    }

    public open func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel {
        throw Exception("fake: resolveOfferUrlDocTypes not configured")
    }

    public open func issueDocumentsByOfferUrl(offerUri: String, docTypes: Array<OfferedDocModel>, txCodeValue: ?String): IssuanceResult {
        return IssuanceResult(documents: this.issuedByOfferDocuments, issuerRegistration: this.issuedByOfferRegistration)
    }

    public open func parseDocClaim(docId: String, groupId: String, docClaim: DocClaim, claimType: DocumentElementType, parser: (String) -> String): Array<DocumentElementClaim> {
        return Array<DocumentElementClaim>()
    }

    public open func retrieveLogFileUrl(): ?String {
        return this.logFileUrl
    }

    public open func resumePendingIssuance(pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef): Array<WalletStorageDocument> {
        throw Exception("fake: resumePendingIssuance not configured")
    }

    public open func storeDynamicIssuancePendingUrl(url: ParsedUrlRef): Unit {
        this.storeDynamicIssuancePendingUrlCalls += 1
    }

    public open func getDynamicIssuancePendingData(): ?DynamicIssuancePendingData {
        return this.dynamicIssuancePendingData
    }

    public open func getScopedDocuments(): CoreScopedDocumentsResult {
        return CoreScopedDocumentsResult(
            documents: this.scopedDocuments,
            errors: this.scopedErrors,
            totalIssuers: this.scopedTotalIssuers
        )
    }

    public open func getDocumentCategories(): DocumentCategories {
        return DocumentCategories()
    }

    // ── Registration-certificate (WRPRC) trust layer ──────────────────────────

    public open func getIssuerRegistration(offer: OfferedIssuanceModel): ?IssuerRegistration {
        return this.issuerRegistrationResult
    }

    public open func getIssuerRegistration(issuerId: String, configIds: Array<String>): ?IssuerRegistration {
        return this.issuerRegistrationResult
    }

    public open func getVerifierRegistration(
        policy: ?WrpRegistrationPolicy,
        trustViolations: Array<String>,
        overaskedClaims: Array<OveraskedClaim>,
        verifierName: ?String,
        verifierIsTrusted: Bool
    ): RelyingPartyRegistration {
        match (this.verifierRegistrationResult) {
            case Some(registration) => return registration
            case None =>
                // Baseline "unregistered" verdict (iOS getVerifierRegistration
                // kill-switch arm): name/badge from the access-certificate side.
                return RelyingPartyRegistration(
                    name: verifierName,
                    uniqueId: None,
                    isVerified: verifierIsTrusted,
                    logoUrl: None,
                    registration: RegistrationStatus.notSupported
                )
        }
    }

    public open func getVerifierRegistrationForFailedRequest(): ?RelyingPartyRegistration {
        return this.failedRequestRegistration
    }

    // ── Bookmarks ─────────────────────────────────────────────────────────────

    public open func isDocumentBookmarked(id: String): Bool {
        return this.bookmarkedResult
    }

    public open func storeBookmarkedDocument(id: String): Unit {
        this.storeBookmarkedDocumentCalls += 1
    }

    public open func removeBookmarkedDocument(id: String): Unit {
        this.removeBookmarkedDocumentCalls += 1
    }

    // ── Transaction logs ──────────────────────────────────────────────────────

    public open func fetchTransactionLog(id: String): TransactionLogItem {
        throw Exception("fake: fetchTransactionLog not configured")
    }

    /** When true, fetchTransactionLogs() throws — drives the interactor's error path. */
    public var fetchTransactionLogsShouldThrow: Bool = false

    public open func fetchTransactionLogs(): Array<TransactionLogItem> {
        if (this.fetchTransactionLogsShouldThrow) {
            throw Exception("fake: fetchTransactionLogs failed")
        }
        return this.transactionLogs
    }

    public open func logPresentation(relyingPartyName: String, docLabels: Array<String>): Unit {
        this.logPresentation(relyingPartyName, docLabels, Option<String>.None)
    }

    public open func logPresentation(relyingPartyName: String, docLabels: Array<String>, presenterName: ?String): Unit {
        this.logPresentationCalls += 1
        this.lastLoggedRelyingParty = relyingPartyName
        this.lastLoggedDocLabels = docLabels
        this.lastLoggedPresenterName = presenterName
    }

    // ── Revocation ────────────────────────────────────────────────────────────

    public open func isDocumentRevoked(id: String): Bool {
        return this.documentRevokedResult
    }

    public open func fetchRevokedDocuments(): Array<String> {
        return this.revokedDocumentIds
    }

    public open func storeRevokedDocuments(ids: Array<String>): Unit {
        this.storeRevokedDocumentsCalls += 1
    }

    public open func removeRevokedDocument(id: String): Unit {
        this.removeRevokedDocumentCalls += 1
    }

    public open func getDocumentStatus(statusIdentifier: StatusIdentifier): CredentialStatus {
        return this.documentStatus
    }

    public open func isDocumentLowOnCredentials(document: ?DocClaimsDecodable): Bool {
        return this.lowOnCredentialsResult
    }

    // ── Failed re-issued docs ─────────────────────────────────────────────────

    public open func storeFailedReIssuedDocuments(ids: Array<String>): Unit {
        this.storeFailedReIssuedDocumentsCalls += 1
    }

    public open func removeAllFailedReIssuedDocuments(): Unit {
        this.removeAllFailedReIssuedDocumentsCalls += 1
    }

    public open func refreshUsageCounters(): Unit {
        this.refreshUsageCountersCalls += 1
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FakeBiometryController
// ─────────────────────────────────────────────────────────────────────────────

/**
 * In-memory fake implementation of BiometryController for unit tests.
 *
 * All three return values are configurable public vars:
 *   - biometryType  (default BiometryNone)
 *   - availability  (default Unavailable(BiometryNotSupported))
 *   - unlockResult  (default UnlockFailure(BiometryNotSupported))
 *
 * Example — test that app handles successful biometry:
 *   let fake = FakeBiometryController()
 *   fake.biometryType = BiometryType.FaceID
 *   fake.availability = BiometryAvailability.Available
 *   fake.unlockResult = BiometryUnlockResult.UnlockSuccess
 */
public class FakeBiometryController <: BiometryController {

    /** Returned by getBiometryType(). Default: no biometry hardware. */
    public var biometryType: BiometryType = BiometryType.BiometryNone

    /** Returned by canEvaluate(). Default: unavailable (no hardware). */
    public var availability: BiometryAvailability = BiometryAvailability.Unavailable(BiometryError.BiometryNotSupported)

    /** Returned by requestBiometricUnlock(). Default: failure (no hardware). */
    public var unlockResult: BiometryUnlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.BiometryNotSupported)

    /** Number of times openSettings() was called (mirrors iOS verify delegation). */
    public var openSettingsCalls: Int64 = 0
    /** When true, openSettings() invokes its action (mirrors a successful open). */
    public var openSettingsInvokesAction: Bool = false

    public init() {}

    public func getBiometryType(): BiometryType {
        return this.biometryType
    }

    public func canEvaluate(): BiometryAvailability {
        return this.availability
    }

    public func requestBiometricUnlock(): BiometryUnlockResult {
        return this.unlockResult
    }

    public func openSettings(action: () -> Unit): Unit {
        this.openSettingsCalls += 1
        if (this.openSettingsInvokesAction) {
            action()
        }
    }
}
