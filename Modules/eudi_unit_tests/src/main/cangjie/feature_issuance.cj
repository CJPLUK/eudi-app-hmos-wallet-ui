// Device unit tests for feature-issuance interactors, migrated 1:1 from:
//   iOS TestAddDocumentInteractor.swift  (19 cases)
//   iOS TestDocumentOfferInteractor.swift (17 cases, some GAP — see mapping below)
//
// Runs via the device bridge (DeviceTestRun in dev_unit_driver.cj).
// Hand-written fakes only — no Cuckoo, no real engine, no keychain I/O.
//
// Architecture:
//   AddDocumentInteractorImpl(walletController: FakeWalletKitController)
//   DocumentOfferInteractorImpl(walletController: FakeIssuanceWalletController,
//                               configLogic:     FakeIssuanceConfigLogic)
//
// FakeWalletKitController fields used here:
//   .scopedDocuments             → getScopedDocuments()
//   .issuedStorageDocuments      → issueDocuments(...)
//   .issuedByOfferDocuments      → issueDocumentsByOfferUrl(...)
//   .dynamicIssuancePendingData  → getDynamicIssuancePendingData()
//   .documentsByIds              → fetchDocuments(ids:)
//   .issuedDocumentsByType       → fetchIssuedDocuments(types:)
//
// resolveOfferUrlDocTypes / resumePendingIssuance throw by default in
// FakeWalletKitController. Tests that need them use FakeIssuanceWalletController
// (defined below) which adds configurable returns.
package eudi_unit_tests

import eudi_feature_issuance.{
    AddDocumentInteractorImpl, DocumentOfferInteractorImpl,
    IssueResultKind, ResumeResultKind,
    OfferResultKind, OfferRequest, OfferItem, toOfferRequest
}
import eudi_feature_common.IssuanceFlow
import eudi_logic_resources.{LocalizableStringKey, LocalizableManager}
import eudi_logic_business.{ConfigLogic, AppBuildType, AppBuildVariant, KeyChainConfig, ParsedUrl}
import eudi_logic_core.{
    WalletCoreError,
    WalletCoreErrorKind,
    DocumentTypeIdentifier, ScopedDocument, WalletStorageDocument,
    DocumentStatus, DocMetadataBlob, OfferedIssuanceModel, OfferedDocModel, TxCode,
    DynamicIssuancePendingData, ParsedUrlRef,
    DocClaimsDecodable,
    CoreScopedDocumentsResult, IssuanceResult,
    IssuerRegistration, IssuerRegistrationBlockedReason, RegistrationDetails
}

// ─────────────────────────────────────────────────────────────────────────────
// Local fakes  (all must be top-level; Cangjie disallows local class definitions)
// ─────────────────────────────────────────────────────────────────────────────

/** ConfigLogic fake used by DocumentOfferInteractorImpl. */
class FakeIssuanceConfigLogic <: ConfigLogic {
    public var forcePid: Bool = true  // iOS default mock returns true
    public prop appBuildType: AppBuildType   { get() { AppBuildType.RELEASE } }
    public prop appBuildVariant: AppBuildVariant { get() { AppBuildVariant.PROD } }
    public prop appVersion: String           { get() { "test" } }
    public prop changelogUrl: ?String        { get() { Option<String>.None } }
    public prop forcePidActivation: Bool     { get() { this.forcePid } }
    public prop keyChainConfig: KeyChainConfig {
        get() { KeyChainConfig("svc", "grp") }
    }
}

/**
 * Extended fake that adds configurable returns for the two methods that
 * FakeWalletKitController throws on by default:
 *   - resolveOfferUrlDocTypes  (DocumentOffer tests)
 *   - resumePendingIssuance    (dynamic-issuance resume tests)
 *
 * Inherits FakeWalletKitController so all other configurable fields remain available.
 */
open class FakeIssuanceWalletController <: FakeWalletKitController {

    /** When Some, resolveOfferUrlDocTypes returns it; otherwise throws. */
    public var offerResult: ?OfferedIssuanceModel = Option<OfferedIssuanceModel>.None

    /**
     * When Some, resumePendingIssuance returns it.
     * When resumeShouldThrow is true, throws (error message in resumeError).
     */
    public var resumeResult: ?WalletStorageDocument = Option<WalletStorageDocument>.None
    public var resumeShouldThrow: Bool = false
    public var resumeError: String = "unable to issue and store"
    /** When true, resumePendingIssuance throws a trust failure instead of a plain
     *  exception — iOS stubs WalletError(code: .trustError) here. */
    public var resumeTrustError: Bool = false

    public override func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel {
        match (this.offerResult) {
            case Some(m) => m
            case None => throw Exception("fake: resolveOfferUrlDocTypes not configured")
        }
    }

    public override func resumePendingIssuance(
        pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef
    ): Array<WalletStorageDocument> {
        if (this.resumeTrustError) {
            throw WalletCoreError.issuerNotTrusted()
        }
        if (this.resumeShouldThrow) {
            throw Exception(this.resumeError)
        }
        match (this.resumeResult) {
            case Some(d) => [d]
            case None => throw Exception("fake: resumePendingIssuance not configured")
        }
    }
}

/** FakeWalletKitController whose getScopedDocuments reports every issuer failed
 *  (the interface is non-throwing now; iOS ScopedDocumentsResult.allIssuersFailed). */
class FakeScopedAllFailed <: FakeWalletKitController {
    public override func getScopedDocuments(): CoreScopedDocumentsResult {
        return CoreScopedDocumentsResult(
            documents: Array<ScopedDocument>(),
            errors: [Exception("unable to fetch document")],
            totalIssuers: 1
        )
    }
}

/** All issuers failed and one failure is trust-blocked → `.issuerNotTrusted`. */
class FakeScopedAllFailedTrust <: FakeWalletKitController {
    public override func getScopedDocuments(): CoreScopedDocumentsResult {
        return CoreScopedDocumentsResult(
            documents: Array<ScopedDocument>(),
            errors: [Exception("plain"), WalletCoreError.issuerNotTrusted()],
            totalIssuers: 2
        )
    }
}

/** FakeWalletKitController that throws from issueDocuments (for failure tests). */
class FakeIssueThrows <: FakeWalletKitController {
    public override func issueDocuments(
        issuerId: String,
        identifiers: Array<String>,
        docTypeIdentifier: DocumentTypeIdentifier
    ): IssuanceResult {
        throw Exception("unable to issue and store")
    }
}

/**
 * FakeIssuanceWalletController that additionally throws from
 * issueDocumentsByOfferUrl (for offer failure tests).
 */
class FakeOfferIssueThrows <: FakeIssuanceWalletController {
    public override func issueDocumentsByOfferUrl(
        offerUri: String,
        docTypes: Array<OfferedDocModel>,
        txCodeValue: ?String
    ): IssuanceResult {
        throw Exception("unable to issue and store")
    }
}

// Trust-failure fakes. iOS stubs the engine to throw
// WalletError(code: .trustError); the Cangjie signal is
// WalletCoreError.issuerNotTrusted() (see dev_tests_error_issuer_trust.cj).

/** Throws a trust failure from issueDocuments. */
class FakeIssueTrustError <: FakeWalletKitController {
    public override func issueDocuments(
        issuerId: String,
        identifiers: Array<String>,
        docTypeIdentifier: DocumentTypeIdentifier
    ): IssuanceResult {
        throw WalletCoreError.issuerNotTrusted()
    }
}

/** Throws a trust failure from resumePendingIssuance. */
class FakeResumeTrustError <: FakeWalletKitController {
    public override func resumePendingIssuance(
        pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef
    ): Array<WalletStorageDocument> {
        throw WalletCoreError.issuerNotTrusted()
    }
}

/** Throws a trust failure from issueDocumentsByOfferUrl. */
class FakeOfferIssueTrustError <: FakeIssuanceWalletController {
    public override func issueDocumentsByOfferUrl(
        offerUri: String,
        docTypes: Array<OfferedDocModel>,
        txCodeValue: ?String
    ): IssuanceResult {
        throw WalletCoreError.issuerNotTrusted()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

func makeScopedDoc(
    name!: String = "Doc",
    issuer!: String = "issuer.dev",
    order!: Int64 = 0,
    configId!: String = "test-config-id",
    isPid!: Bool = true,
    docTypeIdentifier!: DocumentTypeIdentifier = DocumentTypeIdentifier.mDocPid
): ScopedDocument {
    ScopedDocument(
        name: name, issuer: issuer, order: order,
        configId: configId, isPid: isPid, docTypeIdentifier: docTypeIdentifier
    )
}

func makeParsedUrl(raw: String): ParsedUrl {
    return ParsedUrl(Option<String>.None, Option<String>.None, raw, Option<String>.None, Option<String>.None)
}

func makeAddInteractor(fake: FakeWalletKitController): AddDocumentInteractorImpl {
    AddDocumentInteractorImpl(walletController: fake)
}

func makeOfferInteractor(
    fake: FakeIssuanceWalletController,
    cfg: FakeIssuanceConfigLogic
): DocumentOfferInteractorImpl {
    DocumentOfferInteractorImpl(walletController: fake, configLogic: cfg)
}

/**
 * Makes resolveOfferUrlDocTypes succeed so processOfferRequest can populate
 * lastDocOffers. The offer carries a PID docType and a stored PID because
 * FakeIssuanceConfigLogic keeps iOS's forcePidActivation=true default, which
 * otherwise rejects the offer before it is resolved.
 */
func primeOfferResolution(fake: FakeIssuanceWalletController): Unit {
    fake.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "id",
            docTypeOrVct: "eu.europa.ec.eudi.pid.1",
            displayName: "My Document"
        )]
    ))
    fake.issuedDocumentsByType = [makeDocClaimsDecodable()]
}

// ─────────────────────────────────────────────────────────────────────────────
// AddDocument tests  (iOS TestAddDocumentInteractor.swift, 19 cases)
// ─────────────────────────────────────────────────────────────────────────────

func runAddDocumentInteractorTests(t: DeviceTestRun): Unit {

    // ── testFetchScopedDocuments_whenScopedDocuments_thenReturnsSuccess ──────
    // iOS: one scopedDocument → success, count==1, first configId=="test-config-id"
    let fake1 = FakeWalletKitController()
    fake1.scopedDocuments = [makeScopedDoc()]
    let interactor1 = makeAddInteractor(fake1)
    let res1 = interactor1.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(res1.isSuccess, "addDoc.fetchScoped_oneScopedDoc_success")
    t.eqInt(res1.buckets.size, 1, "addDoc.fetchScoped_oneScopedDoc_bucketCount1")
    if (res1.buckets.size > 0) {
        let items1 = res1.buckets[0].items
        t.check(items1.size > 0 && items1[0].configIds.size > 0 &&
            items1[0].configIds[0] == "test-config-id",
            "addDoc.fetchScoped_oneScopedDoc_configId")
    }

    // ── testFetchScopedDocuments_whenScopedDocumentsCompare_thenReturnsSuccess ──
    // iOS: two scoped docs same issuer → one bucket, bucket[0].value.count==2
    // Cangjie: one bucket with 2 items (one PID combined cell + one non-PID cell)
    let fake2 = FakeWalletKitController()
    fake2.scopedDocuments = [
        makeScopedDoc(configId: "pid"),
        makeScopedDoc(
            name: "MDL", configId: "mdl", isPid: false,
            docTypeIdentifier: DocumentTypeIdentifier.fromRawValue("org.iso.18013.5.1.mDL")
        )
    ]
    let interactor2 = makeAddInteractor(fake2)
    let res2 = interactor2.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(res2.isSuccess, "addDoc.fetchScoped_twoDocsCompare_success")
    if (res2.buckets.size > 0) {
        t.eqInt(res2.buckets[0].items.size, 2,
            "addDoc.fetchScoped_twoDocsCompare_items2")
    }

    // ── testFetchScopedDocuments_whenGetScopedDocuments_thenReturnsSuccess (noDocument) ──
    // iOS: one non-PID doc + flow==.noDocument → success, count==0
    // Cangjie: flow==NoDocument only passes isPid==true docs → 0 buckets
    let fake3 = FakeWalletKitController()
    fake3.scopedDocuments = [
        makeScopedDoc(isPid: false,
            docTypeIdentifier: DocumentTypeIdentifier.fromRawValue("org.iso.18013.5.1.mDL"))
    ]
    let interactor3 = makeAddInteractor(fake3)
    let res3 = interactor3.fetchScopedDocuments(IssuanceFlow.NoDocument)
    t.check(res3.isSuccess, "addDoc.fetchScoped_noDocFlow_success")
    t.eqInt(res3.buckets.size, 0, "addDoc.fetchScoped_noDocFlow_noBuckets")

    // ── testFetchScopedDocuments_whenGetScopedDocuments_thenReturnsFailure ──
    // iOS 95b71766: getScopedDocuments no longer throws — it reports per-issuer
    // errors; allIssuersFailed (no trust block) → .failure(first error).
    let fake4 = FakeScopedAllFailed()
    let interactor4 = makeAddInteractor(fake4)
    let res4 = interactor4.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(!res4.isSuccess, "addDoc.fetchScoped_allFailed_failure")
    t.check(!res4.isIssuerNotTrusted, "addDoc.fetchScoped_allFailed_notTrustBlocked")
    t.eqStr(res4.errorMessage, "unable to fetch document", "addDoc.fetchScoped_allFailed_firstErrorText")

    // ── testFetchScopedDocuments_whenAllIssuersFailedWithTrustError_thenIssuerNotTrusted ──
    // iOS: result.allIssuersFailed && errors.contains(isTrustBlocked) → .issuerNotTrusted.
    let fake4t = FakeScopedAllFailedTrust()
    let interactor4t = makeAddInteractor(fake4t)
    let res4t = interactor4t.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(res4t.isIssuerNotTrusted, "addDoc.fetchScoped_allFailedTrust_issuerNotTrusted")
    t.check(!res4t.isSuccess, "addDoc.fetchScoped_allFailedTrust_notSuccess")
    t.eqStr(res4t.errorMessage, "", "addDoc.fetchScoped_allFailedTrust_noGenericErrorMessage")

    // ── partial failure tolerated: one issuer fails, one delivers → success ──
    // iOS ScopedDocumentsResult: errors.count < totalIssuers → bucket the docs,
    // failing issuer stays silent.
    let fake4p = FakeWalletKitController()
    fake4p.scopedDocuments = [makeScopedDoc()]
    fake4p.scopedErrors = [Exception("one issuer down")]
    fake4p.scopedTotalIssuers = 2
    let interactor4p = makeAddInteractor(fake4p)
    let res4p = interactor4p.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(res4p.isSuccess, "addDoc.fetchScoped_partialFailure_stillSuccess")
    t.eqInt(res4p.buckets.size, 1, "addDoc.fetchScoped_partialFailure_bucketsFromSurvivors")

    // ── testIssueDocument_whenDefferedPendingDocument_thenReturnSuccess ──────
    // iOS: issueDocuments returns a deferred doc whose metadata carries a
    //   configurationIdentifier resolving to a scoped doc → .deferredSuccess.
    //   (iOS Constants.defferedPendingDocument metadata has configurationIdentifier
    //   "eu.europa.ec.eudi.pid_vc_sd_jwt_deferred" + stubGetScopedDocuments.)
    let fake5 = FakeWalletKitController()
    fake5.scopedDocuments = [makeScopedDoc(configId: "cfg-def")]
    fake5.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "deferred-doc", status: DocumentStatus.deferred,
            metadata: Some(DocMetadataBlob(
                credentialIssuerIdentifier: "issuer.dev",
                configurationIdentifier: Some("cfg-def")
            )))
    ]
    let interactor5 = makeAddInteractor(fake5)
    let res5 = interactor5.issueDocument(
        "issuer.dev",
        ["deferred-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok5 = match (res5.kind) { case IssueDeferred => true; case _ => false }
    t.check(ok5, "addDoc.issue_deferredDoc_deferredSuccess")

    // ── testIssueDocument_whenIssuedDocument_thenReturnSuccess ───────────────
    // iOS: issueDocuments returns an issued doc → .success
    let fake6 = FakeWalletKitController()
    fake6.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "issued-doc", status: DocumentStatus.issued)
    ]
    let interactor6 = makeAddInteractor(fake6)
    let res6 = interactor6.issueDocument(
        "issuer.dev",
        ["deferred-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok6 = match (res6.kind) { case IssueSuccess => true; case _ => false }
    t.check(ok6, "addDoc.issue_issuedDoc_success")

    // ── testIssueDocument_whenDefferedPendingDocument_thenReturnsFailure ─────
    // iOS: issueDocuments throws WalletCoreError → .failure(.unableToIssueAndStore)
    let fake7 = FakeIssueThrows()
    let interactor7 = makeAddInteractor(fake7)
    let res7 = interactor7.issueDocument(
        "issuer.dev",
        ["fail-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok7 = match (res7.kind) { case IssueFailure => true; case _ => false }
    t.check(ok7, "addDoc.issue_throws_failure")

    // ── testResumeDynamicIssuance_whenDefferedPending_thenReturnDefferedSuccess ──
    // iOS: getDynamicIssuancePendingData() → pendingData; resumePendingIssuance
    //      returns deferred doc → .deferredSuccess
    let fake8 = FakeIssuanceWalletController()
    let pendingDoc8 = makeWalletStorageDocument(id: "deferred-doc", status: DocumentStatus.deferred)
    fake8.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: pendingDoc8, url: makeParsedUrl("https://example.com"))
    )
    fake8.resumeResult = Some(pendingDoc8)
    let interactor8 = makeAddInteractor(fake8)
    let res8 = interactor8.resumeDynamicIssuance("https://example.com")
    let ok8 = match (res8.kind) { case ResumeDeferred => true; case _ => false }
    t.check(ok8, "addDoc.resume_deferredPending_deferredSuccess")

    // ── testResumeDynamicIssuance_whenIssuePending_thenReturnSuccess ─────────
    // iOS: resumePendingIssuance returns issued doc with id=="doc-id" → .success("doc-id")
    let fake9 = FakeIssuanceWalletController()
    let issuedDoc9 = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.issued)
    let pendingDoc9 = makeWalletStorageDocument(id: "issued-pending", status: DocumentStatus.issued)
    fake9.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: pendingDoc9, url: makeParsedUrl("https://example.com"))
    )
    fake9.resumeResult = Some(issuedDoc9)
    let interactor9 = makeAddInteractor(fake9)
    let res9 = interactor9.resumeDynamicIssuance("https://example.com")
    let ok9 = match (res9.kind) { case ResumeSuccess => true; case _ => false }
    t.check(ok9, "addDoc.resume_issuedPending_success")
    t.check(res9.docIds.size == 1 && res9.docIds[0] == "doc-id", "addDoc.resume_issuedPending_docId")

    // ── testResumeDynamicIssuance_whenIssuePending_thenIssuanceFails ─────────
    // iOS: resumePendingIssuance throws → .failure(.unableToIssueAndStore)
    let fake10 = FakeIssuanceWalletController()
    let pendingDoc10 = makeWalletStorageDocument(id: "issued-pending", status: DocumentStatus.issued)
    fake10.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: pendingDoc10, url: makeParsedUrl("https://example.com"))
    )
    fake10.resumeShouldThrow = true
    let interactor10 = makeAddInteractor(fake10)
    let res10 = interactor10.resumeDynamicIssuance("https://example.com")
    let ok10 = match (res10.kind) { case ResumeFailure => true; case _ => false }
    t.check(ok10, "addDoc.resume_issuanceFails_failure")

    // ── testIssueDocument_whenWalletThrowsTrustError_thenReturnsIssuerNotTrusted ──
    // iOS: issueDocuments throws WalletError(.trustError) → .issuerNotTrusted,
    // NOT the generic .failure — the UI blocks the flow instead of offering retry.
    let fakeTrust1 = FakeIssueTrustError()
    let interactorTrust1 = makeAddInteractor(fakeTrust1)
    let resTrust1 = interactorTrust1.issueDocument(
        "issuer.dev",
        ["untrusted-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let okTrust1 = match (resTrust1.kind) { case IssueIssuerNotTrusted => true; case _ => false }
    t.check(okTrust1, "addDoc.issue_trustError_issuerNotTrusted")
    t.eqStr(resTrust1.errorMessage, "", "addDoc.issue_trustError_noGenericErrorMessage")

    // ── testIssueDocument_whenRegistrationBlocked_thenReturnsRegistrationBlocked ──
    // iOS: getIssuerRegistration(issuerId:configIds:) == .blocked(reason) →
    // .registrationBlocked(reason) BEFORE issuing (nothing reaches the engine,
    // nothing is stored, nothing is deleted).
    let fakeRegBlocked = FakeWalletKitController()
    fakeRegBlocked.issuerRegistrationResult =
        Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.attestationNotRegistered))
    fakeRegBlocked.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "never-issued", status: DocumentStatus.issued)
    ]
    let interactorRegBlocked = makeAddInteractor(fakeRegBlocked)
    let resRegBlocked = interactorRegBlocked.issueDocument(
        "issuer.dev",
        ["blocked-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let okRegBlocked = match (resRegBlocked.kind) { case IssueRegistrationBlocked => true; case _ => false }
    t.check(okRegBlocked, "addDoc.issue_registrationBlocked_blocked")
    let reasonMatches = match (resRegBlocked.registrationBlockedReason) {
        case Some(reason) =>
            match (reason) {
                case IssuerRegistrationBlockedReason.attestationNotRegistered => true
                case _ => false
            }
        case None => false
    }
    t.check(reasonMatches, "addDoc.issue_registrationBlocked_carriesReason")
    t.eqInt(fakeRegBlocked.deleteDocumentCalls, 0, "addDoc.issue_registrationBlocked_nothingDeleted")

    // ── testIssueDocument_whenIssuanceRegistrationDoesNotVouch_thenDiscardsAndBlocks ──
    // iOS: !issuance.issuerRegistration.vouchesForIssuer → discard(docs) (each
    // deleted, errors swallowed) + .issuerNotTrusted. A verified registration on
    // the RESULT vouches; a blocked one does not; None (not evaluated) vouches.
    let fakeVouch = FakeWalletKitController()
    fakeVouch.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "stored-then-discarded", status: DocumentStatus.issued)
    ]
    fakeVouch.issuedRegistration =
        Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.notRegisteredAsProvider))
    let interactorVouch = makeAddInteractor(fakeVouch)
    let resVouch = interactorVouch.issueDocument(
        "issuer.dev",
        ["discard-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let okVouch = match (resVouch.kind) { case IssueIssuerNotTrusted => true; case _ => false }
    t.check(okVouch, "addDoc.issue_nonVouchingRegistration_issuerNotTrusted")
    t.eqInt(fakeVouch.deleteDocumentCalls, 1, "addDoc.issue_nonVouchingRegistration_discardsStoredDoc")
    t.eqStr(fakeVouch.lastDeletedDocumentId, "stored-then-discarded",
        "addDoc.issue_nonVouchingRegistration_deletesIssuedId")

    // Invariant: a nil (not evaluated) issuer registration VOUCHES — the plain
    // success path above (fake6) already runs with issuedRegistration == None.
    // A verified verdict also vouches:
    let fakeVouchOk = FakeWalletKitController()
    fakeVouchOk.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "kept-doc", status: DocumentStatus.issued)
    ]
    fakeVouchOk.issuedRegistration = Some(IssuerRegistration.verified(RegistrationDetails(
        tradeName: "Trusted Issuer", uniqueId: "issuer-uid"
    )))
    let interactorVouchOk = makeAddInteractor(fakeVouchOk)
    let resVouchOk = interactorVouchOk.issueDocument(
        "issuer.dev",
        ["kept-doc"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let okVouchOk = match (resVouchOk.kind) { case IssueSuccess => true; case _ => false }
    t.check(okVouchOk, "addDoc.issue_verifiedRegistration_success")
    t.eqInt(fakeVouchOk.deleteDocumentCalls, 0, "addDoc.issue_verifiedRegistration_nothingDeleted")

    // ── testResumeDynamicIssuance_whenWalletThrowsTrustError_thenReturnsIssuerNotTrusted ──
    // iOS: resumePendingIssuance throws WalletError(.trustError) → .issuerNotTrusted
    let fakeTrust2 = FakeResumeTrustError()
    let pendingDocTrust2 = makeWalletStorageDocument(id: "issued-pending", status: DocumentStatus.issued)
    fakeTrust2.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: pendingDocTrust2, url: makeParsedUrl("https://example.com"))
    )
    let interactorTrust2 = makeAddInteractor(fakeTrust2)
    let resTrust2 = interactorTrust2.resumeDynamicIssuance("https://example.com")
    let okTrust2 = match (resTrust2.kind) { case ResumeIssuerNotTrusted => true; case _ => false }
    t.check(okTrust2, "addDoc.resume_trustError_issuerNotTrusted")

    // ── testResumeDynamicIssuance_whenPending_thenReturnSuccess ──────────────
    // iOS: resumePendingIssuance returns pending-status doc → .failure
    // (iOS logic: only .deferred/.issued → success; .pending → unableToIssueAndStore)
    let fake11 = FakeIssuanceWalletController()
    let pendingDoc11 = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.pending)
    fake11.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: pendingDoc11, url: makeParsedUrl("https://example.com"))
    )
    fake11.resumeResult = Some(pendingDoc11)
    let interactor11 = makeAddInteractor(fake11)
    let res11 = interactor11.resumeDynamicIssuance("https://example.com")
    let ok11 = match (res11.kind) { case ResumeFailure => true; case _ => false }
    t.check(ok11, "addDoc.resume_pendingDoc_failure")

    // ── testResumeDynamicIssuance_whenReturnsNoPending_thenNoPendingDataExists ──
    // iOS: getDynamicIssuancePendingData() returns nil → .noPending
    let fake12 = FakeWalletKitController()
    fake12.dynamicIssuancePendingData = Option<DynamicIssuancePendingData>.None
    let interactor12 = makeAddInteractor(fake12)
    let res12 = interactor12.resumeDynamicIssuance("")
    let ok12 = match (res12.kind) { case ResumeNoPending => true; case _ => false }
    t.check(ok12, "addDoc.resume_noPending_noPending")

    // ── testFetchStoredDocuments_whenDocumentsExist_thenReturnsSuccess ────────
    // iOS: fetchDocuments(with: documentIds) → [pidDocument, mdlDocument] →
    //      .success, count==2
    let fake13 = FakeWalletKitController()
    fake13.documentsByIds = [
        makeDocClaimsDecodable(id: "doc-id-1", docType: "eu.europa.ec.eudi.pid.1",
            displayName: Some("PID Doc")),
        makeDocClaimsDecodable(id: "doc-id-2", docType: "org.iso.18013.5.1.mDL",
            displayName: Some("MDL Doc"))
    ]
    let interactor13 = makeAddInteractor(fake13)
    let res13 = interactor13.fetchStoredDocuments(["doc-id-1", "doc-id-2"])
    t.eqInt(res13.size, 2, "addDoc.fetchStored_twoExist_count2")
    if (res13.size >= 2) {
        t.eqStr(res13[0].id, "doc-id-1", "addDoc.fetchStored_doc0_id")
        t.eqStr(res13[1].id, "doc-id-2", "addDoc.fetchStored_doc1_id")
    }

    // ── testFetchStoredDocuments_whenDocumentsDoNotExist_thenReturnsFailure ──
    // iOS returns .failure(.unableFetchDocument) when nothing comes back. Cangjie
    // signals failure by throwing that same error (project convention), so the
    // ViewModel raises an error page instead of a success screen.
    let fake14 = FakeWalletKitController()
    fake14.documentsByIds = Array<DocClaimsDecodable>()
    let interactor14 = makeAddInteractor(fake14)
    var threw14 = false
    var kind14 = false
    try {
        let _ = interactor14.fetchStoredDocuments(["non-existent-doc"])
    } catch (e: WalletCoreError) {
        threw14 = true
        kind14 = e.kind == WalletCoreErrorKind.unableFetchDocument
    }
    t.check(threw14, "addDoc.fetchStored_nonExistent_throwsFailure")
    t.check(kind14, "addDoc.fetchStored_nonExistent_errorIsUnableFetchDocument")

    // ── testFetchStoredDocuments_whenNoDocumentsReturned_thenReturnsFailure ──
    // iOS: documentIds==[] → same failure.
    let fake15 = FakeWalletKitController()
    fake15.documentsByIds = Array<DocClaimsDecodable>()
    let interactor15 = makeAddInteractor(fake15)
    var threw15 = false
    try {
        let _ = interactor15.fetchStoredDocuments(Array<String>())
    } catch (_: WalletCoreError) {
        threw15 = true
    }
    t.check(threw15, "addDoc.fetchStored_emptyIds_throwsFailure")

    // Guard: the non-empty case above must still return normally, otherwise the
    // two assertions could pass for a method that always throws.
    t.eqInt(res13.size, 2, "addDoc.fetchStored_nonEmpty_doesNotThrow")

    // ── testFetchScopedDocuments_WhenExtraDocumentFilterTypeIsSet_ThenNonMatchingDocsFilteredOut ──
    // iOS: flow==.extraDocument(filterType: .mDocPid) → non-PID doc skipped
    let fake16 = FakeWalletKitController()
    fake16.scopedDocuments = [
        makeScopedDoc(name: "PID Doc", configId: "pid", isPid: true,
            docTypeIdentifier: DocumentTypeIdentifier.mDocPid),
        makeScopedDoc(name: "MDL Doc", configId: "mdl", isPid: false,
            docTypeIdentifier: DocumentTypeIdentifier.fromRawValue("org.iso.18013.5.1.mDL"))
    ]
    let interactor16 = makeAddInteractor(fake16)
    let filterStr = DocumentTypeIdentifier.mDocPid.rawValue
    let res16 = interactor16.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Some(filterStr)))
    t.check(res16.isSuccess, "addDoc.fetchScoped_filterType_success")
    var allPid16 = true
    for (bucket16 in res16.buckets) {
        for (item16 in bucket16.items) {
            if (item16.docTypeIdentifier != DocumentTypeIdentifier.mDocPid) {
                allPid16 = false
            }
        }
    }
    t.check(allPid16, "addDoc.fetchScoped_filterType_onlyPidItems")

    // ── testIssueDocument_WhenWalletReturnsEmptyDocs_ThenReturnsFailure ──────
    // iOS: issueDocuments returns [] → .failure(.unableToIssueAndStore)
    let fake17 = FakeWalletKitController()
    fake17.issuedStorageDocuments = Array<WalletStorageDocument>()
    let interactor17 = makeAddInteractor(fake17)
    let res17 = interactor17.issueDocument(
        "issuer.dev",
        ["empty"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok17 = match (res17.kind) { case IssueFailure => true; case _ => false }
    t.check(ok17, "addDoc.issue_emptyDocs_failure")

    // ── testIssueDocument_WhenDeferredDocHasNilMetadata_ThenReturnsFailure ───
    // iOS: deferred doc with metadata==nil → guard configurationIdentifier fails →
    //      .failure(.unableToIssueAndStore) (AddDocumentInteractor.swift:166-171).
    // Cangjie now mirrors the guard: nil metadata → IssueFailure (not deferred).
    let fake18 = FakeWalletKitController()
    fake18.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "deferred-orphan",
            status: DocumentStatus.deferred, metadata: Option<DocMetadataBlob>.None)
    ]
    let interactor18 = makeAddInteractor(fake18)
    let res18 = interactor18.issueDocument(
        "issuer.dev",
        ["deferred-orphan"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok18 = match (res18.kind) { case IssueFailure => true; case _ => false }
    t.check(ok18, "addDoc.issue_deferredNilMeta_failure")

    // ── (metadata guard) deferred doc whose metadata carries no configId ──────
    // iOS: DocMetadata(from:)?.configurationIdentifier == nil → guard fails →
    //      .failure. Metadata present but configurationIdentifier==None.
    let fake18b = FakeWalletKitController()
    fake18b.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "deferred-no-configid",
            status: DocumentStatus.deferred,
            metadata: Some(DocMetadataBlob(
                credentialIssuerIdentifier: "issuer.dev",
                configurationIdentifier: Option<String>.None
            )))
    ]
    let interactor18b = makeAddInteractor(fake18b)
    let res18b = interactor18b.issueDocument(
        "issuer.dev",
        ["deferred-no-configid"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok18b = match (res18b.kind) { case IssueFailure => true; case _ => false }
    t.check(ok18b, "addDoc.issue_deferredNoConfigId_failure")

    // ── (metadata guard) deferred doc WITH a resolvable configId → deferred OK ──
    // iOS: guard passes; getScopedDocument(configId:) resolves the scoped doc →
    //      .deferredSuccess(document). Cangjie: IssueDeferred, name from scoped doc.
    let fake18c = FakeWalletKitController()
    fake18c.scopedDocuments = [
        makeScopedDoc(name: "Deferred PID", issuer: "issuer.dev", configId: "cfg-deferred")
    ]
    fake18c.issuedStorageDocuments = [
        makeWalletStorageDocument(id: "deferred-ok",
            status: DocumentStatus.deferred,
            metadata: Some(DocMetadataBlob(
                credentialIssuerIdentifier: "issuer.dev",
                configurationIdentifier: Some("cfg-deferred")
            )))
    ]
    let interactor18c = makeAddInteractor(fake18c)
    let res18c = interactor18c.issueDocument(
        "issuer.dev",
        ["cfg-deferred"],
        DocumentTypeIdentifier.fromRawValue("eu.europa.ec.eudi.pid.1")
    )
    let ok18c = match (res18c.kind) { case IssueDeferred => true; case _ => false }
    t.check(ok18c, "addDoc.issue_deferredWithConfigId_deferredSuccess")
    t.eqStr(res18c.deferredName, "Deferred PID",
        "addDoc.issue_deferredWithConfigId_nameFromScoped")

    // ── testFetchScopedDocuments_WhenDocumentsReturned_ThenReturnsSuccessMocks ──
    // iOS: 4 scoped docs across 2 issuers → 2 buckets, each issuer present
    let fake19 = FakeWalletKitController()
    fake19.scopedDocuments = [
        makeScopedDoc(name: "Doc 1", issuer: "issuer.dev",  order: 0, configId: "id1"),
        makeScopedDoc(name: "Doc 2", issuer: "issuer.dev",  order: 0, configId: "id2"),
        makeScopedDoc(name: "Doc 3", issuer: "issuer.dev",  order: 1, configId: "id3"),
        makeScopedDoc(name: "Doc 4", issuer: "issuer2.dev", order: 1, configId: "id4")
    ]
    let interactor19 = makeAddInteractor(fake19)
    let res19 = interactor19.fetchScopedDocuments(IssuanceFlow.ExtraDocument(Option<String>.None))
    t.check(res19.isSuccess, "addDoc.fetchScoped_4docs2issuers_success")
    t.eqInt(res19.buckets.size, 2, "addDoc.fetchScoped_4docs2issuers_2buckets")
    var foundIssuer1 = false
    var foundIssuer2 = false
    for (bucket19 in res19.buckets) {
        if (bucket19.issuerId == "issuer.dev")  { foundIssuer1 = true }
        if (bucket19.issuerId == "issuer2.dev") { foundIssuer2 = true }
    }
    t.check(foundIssuer1, "addDoc.fetchScoped_4docs2issuers_issuer1Present")
    t.check(foundIssuer2, "addDoc.fetchScoped_4docs2issuers_issuer2Present")
}

// ─────────────────────────────────────────────────────────────────────────────
// DocumentOffer tests  (iOS TestDocumentOfferInteractor.swift, 17 cases)
// ─────────────────────────────────────────────────────────────────────────────

func runDocumentOfferInteractorTests(t: DeviceTestRun): Unit {

    // ── testResumeDynamicIssuance_WhenNoPendingData_ThenReturnNoPending ───────
    // iOS: getDynamicIssuancePendingData returns nil → .noPending
    let oFake1 = FakeIssuanceWalletController()
    let oCfg1  = FakeIssuanceConfigLogic()
    oFake1.dynamicIssuancePendingData = Option<DynamicIssuancePendingData>.None
    let oIntr1 = makeOfferInteractor(oFake1, oCfg1)
    let oRes1  = oIntr1.resumeDynamicIssuance("")
    let ookR1 = match (oRes1.kind) { case ResumeNoPending => true; case _ => false }
    t.check(ookR1, "offerDoc.resume_noPendingData_noPending")

    // ── testResumeDynamicIssuance_WhenDocumentIssued_ThenReturnFailure ────────
    // iOS: pendingData exists; resumePendingIssuance throws → .failure
    let oFake2 = FakeIssuanceWalletController()
    let oCfg2  = FakeIssuanceConfigLogic()
    let oDoc2  = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.issued)
    oFake2.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: oDoc2, url: makeParsedUrl("someURL"))
    )
    oFake2.resumeShouldThrow = true
    let oIntr2 = makeOfferInteractor(oFake2, oCfg2)
    let oRes2  = oIntr2.resumeDynamicIssuance("someURL")
    let ookR2 = match (oRes2.kind) { case ResumeFailure => true; case _ => false }
    t.check(ookR2, "offerDoc.resume_issued_throws_failure")

    // ── testResumeDynamicIssuance_WhenDocumentIssued_ThenReturnSuccess ────────
    // iOS: resumePendingIssuance returns issued doc → .success
    let oFake3 = FakeIssuanceWalletController()
    let oCfg3  = FakeIssuanceConfigLogic()
    let oDoc3  = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.issued)
    oFake3.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: oDoc3, url: makeParsedUrl("someURL"))
    )
    oFake3.resumeResult = Some(oDoc3)
    oFake3.documentsByIds = [makeDocClaimsDecodable(id: "doc-id")]
    let oIntr3 = makeOfferInteractor(oFake3, oCfg3)
    let oRes3  = oIntr3.resumeDynamicIssuance("someURL")
    let ookR3 = match (oRes3.kind) { case ResumeSuccess => true; case _ => false }
    t.check(ookR3, "offerDoc.resume_issued_success")

    // ── testResumeDynamicIssuance_WhenDocumentDeffered_ThenReturnSuccess ──────
    // iOS: resumePendingIssuance returns deferred doc → (iOS) .success(route)
    // Cangjie: deferred → ResumeDeferred (routes to deferred-success screen)
    let oFake4 = FakeIssuanceWalletController()
    let oCfg4  = FakeIssuanceConfigLogic()
    let oDoc4  = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.deferred)
    oFake4.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: oDoc4, url: makeParsedUrl("someURL"))
    )
    oFake4.resumeResult = Some(oDoc4)
    let oIntr4 = makeOfferInteractor(oFake4, oCfg4)
    let oRes4  = oIntr4.resumeDynamicIssuance("someURL")
    let ookR4 = match (oRes4.kind) { case ResumeDeferred => true; case _ => false }
    t.check(ookR4, "offerDoc.resume_deferred_deferredSuccess")

    // ── testResumeDynamicIssuance_WhenDocumentPending_ThenReturnFailure ───────
    // iOS: resumePendingIssuance returns pending-status doc → .failure
    let oFake5 = FakeIssuanceWalletController()
    let oCfg5  = FakeIssuanceConfigLogic()
    let oDoc5  = makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.pending)
    oFake5.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: oDoc5, url: makeParsedUrl("someURL"))
    )
    oFake5.resumeResult = Some(oDoc5)
    let oIntr5 = makeOfferInteractor(oFake5, oCfg5)
    let oRes5  = oIntr5.resumeDynamicIssuance("someURL")
    let ookR5 = match (oRes5.kind) { case ResumeFailure => true; case _ => false }
    t.check(ookR5, "offerDoc.resume_pending_failure")

    // ── testIssueDocuments_WhenIssueDocumentsByOfferUrl_ThenReturnFailure ─────
    // iOS: issueDocumentsByOfferUrl throws → .failure(.unableToIssueAndStore)
    // issueDocuments re-resolves the offer when lastDocOffers is empty and fails
    // early if that re-resolve fails, so the offer must be primed or this never
    // reaches issueDocumentsByOfferUrl and would pass for the wrong reason.
    let oFake6 = FakeOfferIssueThrows()
    let oCfg6  = FakeIssuanceConfigLogic()
    primeOfferResolution(oFake6)
    let oIntr6 = makeOfferInteractor(oFake6, oCfg6)
    let _ = oIntr6.processOfferRequest("uri")
    let oRes6  = oIntr6.issueDocuments("uri", Some("txCodeValue"))
    let ookO6 = match (oRes6.kind) { case OfferFailure => true; case _ => false }
    t.check(ookO6, "offerDoc.issue_byOfferUrl_throws_failure")

    // ── testIssueDocuments_WhenWalletThrowsTrustError_ThenReturnsIssuerNotTrusted ──
    // iOS: issueDocumentsByOfferUrl throws WalletError(.trustError) →
    // .issuerNotTrusted. Same offer priming as the failure case above, so the
    // throw really comes from issueDocumentsByOfferUrl.
    let oFakeTrust1 = FakeOfferIssueTrustError()
    let oCfgTrust1  = FakeIssuanceConfigLogic()
    primeOfferResolution(oFakeTrust1)
    let oIntrTrust1 = makeOfferInteractor(oFakeTrust1, oCfgTrust1)
    let _ = oIntrTrust1.processOfferRequest("uri")
    let oResTrust1  = oIntrTrust1.issueDocuments("uri", Some("txCodeValue"))
    let ookTrust1 = match (oResTrust1.kind) { case OfferIssuerNotTrusted => true; case _ => false }
    t.check(ookTrust1, "offerDoc.issue_trustError_issuerNotTrusted")
    t.eqStr(oResTrust1.errorMessage, "", "offerDoc.issue_trustError_noGenericErrorMessage")

    // ── testResumeDynamicIssuance_WhenWalletThrowsTrustError_ThenReturnsIssuerNotTrusted ──
    // iOS: resumePendingIssuance throws WalletError(.trustError) → .issuerNotTrusted
    let oFakeTrust2 = FakeIssuanceWalletController()
    oFakeTrust2.resumeTrustError = true
    let oCfgTrust2  = FakeIssuanceConfigLogic()
    let oPendingTrust2 = makeWalletStorageDocument(id: "issued-pending", status: DocumentStatus.issued)
    oFakeTrust2.dynamicIssuancePendingData = Some(
        DynamicIssuancePendingData(pendingDoc: oPendingTrust2, url: makeParsedUrl("https://example.com"))
    )
    let oIntrTrust2 = makeOfferInteractor(oFakeTrust2, oCfgTrust2)
    let oResTrust2  = oIntrTrust2.resumeDynamicIssuance("https://example.com")
    let ookTrust2 = match (oResTrust2.kind) { case ResumeIssuerNotTrusted => true; case _ => false }
    t.check(ookTrust2, "offerDoc.resume_trustError_issuerNotTrusted")

    // ── testIssueDocuments_WhenIssueDocumentsByOfferUrlEmptyDocuments_ThenReturnFailure ──
    // iOS: issueDocumentsByOfferUrl returns [] → .failure
    let oFake7 = FakeIssuanceWalletController()
    let oCfg7  = FakeIssuanceConfigLogic()
    oFake7.issuedByOfferDocuments = Array<WalletStorageDocument>()
    primeOfferResolution(oFake7)
    let oIntr7 = makeOfferInteractor(oFake7, oCfg7)
    let _ = oIntr7.processOfferRequest("uri")
    let oRes7  = oIntr7.issueDocuments("uri", Some("txCodeValue"))
    let ookO7 = match (oRes7.kind) { case OfferFailure => true; case _ => false }
    t.check(ookO7, "offerDoc.issue_byOfferUrl_empty_failure")

    // ── testIssueDocuments_WhenIssueDocumentsByOfferUrl_ThenReturnSuccess (deferred) ──
    // iOS: issueDocumentsByOfferUrl returns [deferred doc] → .deferredSuccess(route)
    let oFake8 = FakeIssuanceWalletController()
    let oCfg8  = FakeIssuanceConfigLogic()
    oFake8.issuedByOfferDocuments = [
        makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.deferred)
    ]
    primeOfferResolution(oFake8)
    let oIntr8 = makeOfferInteractor(oFake8, oCfg8)
    let _ = oIntr8.processOfferRequest("uri")
    let oRes8  = oIntr8.issueDocuments("uri", Some("txCodeValue"))
    let ookO8 = match (oRes8.kind) { case OfferDeferred => true; case _ => false }
    t.check(ookO8, "offerDoc.issue_byOfferUrl_deferredDoc_deferredSuccess")

    // ── testIssueDocuments_WhenIssueDocumentsByOfferUrlauthorizePresentationUrl_ThenReturnSuccess ──
    // iOS reaches .partialSuccess by passing `docOffers: []` while the engine returns
    // one document (1 != 0). Cangjie derives the offered list from the resolved offer
    // rather than from a caller argument, so the mismatch is produced the way it
    // happens in practice: two documents offered, one actually issued.
    let oFake9 = FakeIssuanceWalletController()
    let oCfg9  = FakeIssuanceConfigLogic()
    oFake9.issuedByOfferDocuments = [
        makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.issued)
    ]
    oFake9.documentsByIds = [makeDocClaimsDecodable()]
    oFake9.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: [
            OfferedDocModel(
                credentialConfigurationIdentifier: "id-1",
                docTypeOrVct: "eu.europa.ec.eudi.pid.1",
                displayName: "My Document"
            ),
            OfferedDocModel(
                credentialConfigurationIdentifier: "id-2",
                docTypeOrVct: "org.iso.18013.5.1.mDL",
                displayName: "Second Document"
            )
        ]
    ))
    oFake9.issuedDocumentsByType = [makeDocClaimsDecodable()]
    let oIntr9 = makeOfferInteractor(oFake9, oCfg9)
    let _ = oIntr9.processOfferRequest("uri")
    let oRes9  = oIntr9.issueDocuments("uri", Some("txCodeValue"))
    // iOS: one document came back for an empty offer list → count mismatch →
    // .partialSuccess. Cangjie now reports the same distinction.
    let ookO9 = match (oRes9.kind) { case OfferPartialSuccess => true; case _ => false }
    t.check(ookO9, "offerDoc.issue_countMismatch_partialSuccess")
    t.eqInt(oRes9.documentIds.size, 1, "offerDoc.issue_partialSuccess_carriesIssuedIds")

    // ── testIssueDocuments_WhenIssueDocumentsByOfferUrlWithDocOffers_ThenReturnSuccess ──
    // iOS: [issued doc] + non-empty docOffers → .success(route)
    // Cangjie: prime lastDocOffers via processOfferRequest first
    let oFake10 = FakeIssuanceWalletController()
    let oCfg10  = FakeIssuanceConfigLogic()
    oFake10.issuedByOfferDocuments = [
        makeWalletStorageDocument(id: "doc-id", status: DocumentStatus.issued)
    ]
    oFake10.documentsByIds = [makeDocClaimsDecodable()]
    oFake10.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "id",
            docTypeOrVct: "eu.europa.ec.eudi.pid.1",
            displayName: "My Document"
        )]
    ))
    oFake10.issuedDocumentsByType = [makeDocClaimsDecodable()]  // hasPidStored=true
    let oIntr10 = makeOfferInteractor(oFake10, oCfg10)
    let _ = oIntr10.processOfferRequest("uri")  // primes lastDocOffers
    let oRes10  = oIntr10.issueDocuments("uri", Some("txCodeValue"))
    let ookO10 = match (oRes10.kind) { case OfferSuccess => true; case _ => false }
    t.check(ookO10, "offerDoc.issue_withDocOffers_success")

    // ── testProcessOfferRequest_WhenResolveOfferUrlDocTypes_ThenReturnFailure ─
    // iOS: resolveOfferUrlDocTypes throws → .failure
    let oFake11 = FakeIssuanceWalletController()
    let oCfg11  = FakeIssuanceConfigLogic()
    // offerResult stays None → resolveOfferUrlDocTypes throws
    let oIntr11 = makeOfferInteractor(oFake11, oCfg11)
    let oRes11  = oIntr11.processOfferRequest("uri")
    t.check(!oRes11.isSuccess,
        "offerDoc.processOffer_resolveThrows_failure")

    // ── testOfferedIssuance_WhenModelTransforms_ThenToDocumentOfferUIModel ───
    // iOS asserts the pure mapping (transformToDocumentOfferUi) field by field.
    // toOfferRequest() is the extracted Cangjie equivalent, callable without going
    // through the interactor or its validation.
    let transformModel = OfferedIssuanceModel(
        issuerName: "Issuer",
        issuerLogoUrl: Some("https://logo.com/logo.png"),
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "id",
            docTypeOrVct: "eu.europa.ec.eudi.pid.1",
            displayName: "Display Name"
        )],
        txCodeSpec: Some(TxCode(inputMode: "numeric", length: Some(6)))
    )
    let transformed = toOfferRequest(transformModel)
    t.check(transformed.isSuccess, "offerDoc.transformModel_isSuccess")
    t.eqStr(transformed.issuerName, "Issuer", "offerDoc.transformModel_issuerName")
    t.eqStr(transformed.issuerLogoUrl, "https://logo.com/logo.png", "offerDoc.transformModel_issuerLogo")
    t.eqInt(transformed.offers.size, 1, "offerDoc.transformModel_oneOffer")
    if (transformed.offers.size == 1) {
        t.eqStr(transformed.offers[0].name, "Display Name", "offerDoc.transformModel_offerName")
    } else {
        t.check(false, "offerDoc.transformModel_offerName_wrongCount")
    }
    t.check(transformed.txCodeRequired, "offerDoc.transformModel_txCodeRequired")
    t.eqInt(transformed.txCodeLength, 6, "offerDoc.transformModel_txCodeLength")
    // No tx-code spec → not required, length 0 (iOS `txCodeSpec?.length ?? 0`).
    let noTxCode = toOfferRequest(OfferedIssuanceModel(issuerName: "Issuer2", docModels: Array<OfferedDocModel>()))
    t.check(!noTxCode.txCodeRequired, "offerDoc.transformModel_noTxCode_notRequired")
    t.eqInt(noTxCode.txCodeLength, 0, "offerDoc.transformModel_noTxCode_lengthZero")
    t.eqStr(noTxCode.issuerLogoUrl, "", "offerDoc.transformModel_noLogo_emptyString")

    // The interactor path still rejects a text-mode tx code before mapping.
    let oFake12 = FakeIssuanceWalletController()
    let oCfg12  = FakeIssuanceConfigLogic()
    oFake12.offerResult = Some(OfferedIssuanceModel(
        issuerName: "Issuer",
        issuerLogoUrl: Some("https://logo.com/logo.png"),
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "id",
            docTypeOrVct: "eu.europa.ec.eudi.pid.1",
            displayName: "Display Name"
        )],
        txCodeSpec: Some(TxCode(inputMode: "text", length: Some(6)))
    ))
    oFake12.issuedDocumentsByType = [makeDocClaimsDecodable()]
    let oIntr12 = makeOfferInteractor(oFake12, oCfg12)
    let oRes12  = oIntr12.processOfferRequest("uri")
    t.check(!oRes12.isSuccess,
        "offerDoc.transformModel_textMode_CANGJIE_failure_GAP_iosTransformTest")

    // ── testDocumentOffer_MockUIModel ─────────────────────────────────────────
    // iOS: DocumentOfferUIModel.mock() → issuerName==unknownIssuer, no logo,
    //      no txCode, 5 uiOffers each "Document Name", docOffers empty.
    // Cangjie: OfferRequest.mock() mirrors the same sample default model.
    let mockOffer = OfferRequest.mock()
    t.check(mockOffer.isSuccess, "offerDoc.mock_isSuccess")
    t.eqStr(mockOffer.issuerName, LocalizableManager.get(LocalizableStringKey.unknownIssuer),
        "offerDoc.mock_issuerName_unknownIssuer")
    t.eqStr(mockOffer.issuerLogoUrl, "", "offerDoc.mock_noLogo")
    t.check(!mockOffer.txCodeRequired, "offerDoc.mock_noTxCode")
    t.eqInt(mockOffer.txCodeLength, 0, "offerDoc.mock_txCodeLen0")
    t.eqInt(mockOffer.offers.size, 5, "offerDoc.mock_fiveOffers")
    var allDocName = mockOffer.offers.size == 5
    for (mo in mockOffer.offers) {
        if (mo.name != "Document Name") { allDocName = false }
    }
    t.check(allDocName, "offerDoc.mock_allOffersDocumentName")

    // ── testProcessOfferRequest_WhenTxCodeLengthOutOfRange_ThenReturnsTransactionCodeFormatFailure ──
    // iOS: txCodeSpec.length==3 (out of 4..6) → .failure(.transactionCodeFormat).
    // Cangjie surfaces .transactionCodeFormat as the txCodeFormatError() message,
    // asserted here to distinguish it from other failure kinds (missingPid etc.).
    let txCodeFormatMsg = "The transaction code must be 4 to 6 digits"
    let oFake13 = FakeIssuanceWalletController()
    let oCfg13  = FakeIssuanceConfigLogic()
    oFake13.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: Array<OfferedDocModel>(),
        txCodeSpec: Some(TxCode(inputMode: "numeric", length: Some(3)))
    ))
    oFake13.issuedDocumentsByType = [makeDocClaimsDecodable()]
    let oIntr13 = makeOfferInteractor(oFake13, oCfg13)
    let oRes13  = oIntr13.processOfferRequest("uri")
    t.check(!oRes13.isSuccess,
        "offerDoc.processOffer_txCodeLen3_failure")
    t.eqStr(oRes13.errorMessage, txCodeFormatMsg,
        "offerDoc.processOffer_txCodeLen3_transactionCodeFormat")

    // ── testProcessOfferRequest_WhenTxCodeInputModeIsText_ThenReturnsTransactionCodeFormatFailure ──
    // iOS: inputMode==.text, length==5 → .failure(.transactionCodeFormat)
    let oFake14 = FakeIssuanceWalletController()
    let oCfg14  = FakeIssuanceConfigLogic()
    oFake14.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: Array<OfferedDocModel>(),
        txCodeSpec: Some(TxCode(inputMode: "text", length: Some(5)))
    ))
    oFake14.issuedDocumentsByType = [makeDocClaimsDecodable()]
    let oIntr14 = makeOfferInteractor(oFake14, oCfg14)
    let oRes14  = oIntr14.processOfferRequest("uri")
    t.check(!oRes14.isSuccess,
        "offerDoc.processOffer_txCodeText_failure")
    t.eqStr(oRes14.errorMessage, txCodeFormatMsg,
        "offerDoc.processOffer_txCodeText_transactionCodeFormat")

    // ── testProcessOfferRequest_WhenForcePidActivationButNoPidStoredOrOffered_ThenMissingPidFailure ──
    // iOS: forcePidActivation=true, no PID stored, offer has no PID doctype → .failure(.missingPid)
    let oFake15 = FakeIssuanceWalletController()
    let oCfg15  = FakeIssuanceConfigLogic()
    oCfg15.forcePid = true
    oFake15.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "non-pid-id",
            docTypeOrVct: "non-pid-doctype",
            displayName: "Other Doc"
        )]
    ))
    oFake15.issuedDocumentsByType = Array<DocClaimsDecodable>()  // no PID stored
    let oIntr15 = makeOfferInteractor(oFake15, oCfg15)
    let oRes15  = oIntr15.processOfferRequest("uri")
    t.check(!oRes15.isSuccess,
        "offerDoc.processOffer_missingPid_failure")

    // ── testProcessOfferRequest_WhenResolveOfferUrlDocTypes_ThenReturnSuccess ─
    // iOS: resolveOfferUrlDocTypes returns offer → .success, issuerName matches
    let oFake16 = FakeIssuanceWalletController()
    let oCfg16  = FakeIssuanceConfigLogic()
    oFake16.offerResult = Some(OfferedIssuanceModel(
        issuerName: "issuerName",
        issuerLogoUrl: Some("issuerLogoUrl"),
        docModels: [OfferedDocModel(
            credentialConfigurationIdentifier: "id",
            docTypeOrVct: "eu.europa.ec.eudi.pid.1",
            displayName: "My Document"
        )]
    ))
    oFake16.issuedDocumentsByType = [makeDocClaimsDecodable()]  // hasPidStored=true
    let oIntr16 = makeOfferInteractor(oFake16, oCfg16)
    let oRes16  = oIntr16.processOfferRequest("uri")
    t.check(oRes16.isSuccess,
        "offerDoc.processOffer_resolve_success")
    t.eqStr(oRes16.issuerName, "issuerName",
        "offerDoc.processOffer_resolve_issuerName")
    // iOS 95b71766: the success payload carries the issuer-registration verdict
    // (None here — the fake resolves no registration → header without seal).
    let oRes16NoReg = match (oRes16.issuerRegistration) { case None => true; case Some(_) => false }
    t.check(oRes16NoReg, "offerDoc.processOffer_resolve_noRegistrationVerdict")

    // ── testProcessOfferRequest_whenIssuerRegistrationBlocked_thenRegistrationBlocked ──
    // iOS: getIssuerRegistration(for: offer) == .blocked(reason) →
    // .registrationBlocked BEFORE issuing.
    let oFakeReg = FakeIssuanceWalletController()
    let oCfgReg  = FakeIssuanceConfigLogic()
    primeOfferResolution(oFakeReg)
    oFakeReg.issuerRegistrationResult =
        Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.notRegisteredAsProvider))
    let oIntrReg = makeOfferInteractor(oFakeReg, oCfgReg)
    let oResReg  = oIntrReg.processOfferRequest("uri")
    t.check(oResReg.isRegistrationBlocked, "offerDoc.processOffer_registrationBlocked_blocked")
    t.check(!oResReg.isSuccess, "offerDoc.processOffer_registrationBlocked_notSuccess")
    t.eqStr(oResReg.errorMessage, "", "offerDoc.processOffer_registrationBlocked_noGenericErrorMessage")

    // A verified registration flows through into the success payload.
    let oFakeRegOk = FakeIssuanceWalletController()
    let oCfgRegOk  = FakeIssuanceConfigLogic()
    primeOfferResolution(oFakeRegOk)
    oFakeRegOk.issuerRegistrationResult = Some(IssuerRegistration.verified(RegistrationDetails(
        tradeName: "Trusted Issuer", uniqueId: "issuer-uid"
    )))
    let oIntrRegOk = makeOfferInteractor(oFakeRegOk, oCfgRegOk)
    let oResRegOk  = oIntrRegOk.processOfferRequest("uri")
    t.check(oResRegOk.isSuccess, "offerDoc.processOffer_verifiedRegistration_success")
    let oResRegOkCarries = match (oResRegOk.issuerRegistration) { case Some(_) => true; case None => false }
    t.check(oResRegOkCarries, "offerDoc.processOffer_verifiedRegistration_carriesVerdict")

    // ── testIssueDocuments_whenIssuanceRegistrationDoesNotVouch_thenDiscardsAndBlocks ──
    // iOS: !issuance.issuerRegistration.vouchesForIssuer → discard(issuedDocuments)
    // + .issuerNotTrusted (issuance REFUSES and deletes what was stored).
    let oFakeVouch = FakeIssuanceWalletController()
    let oCfgVouch  = FakeIssuanceConfigLogic()
    primeOfferResolution(oFakeVouch)
    oFakeVouch.issuedByOfferDocuments = [
        makeWalletStorageDocument(id: "offer-discarded", status: DocumentStatus.issued)
    ]
    oFakeVouch.issuedByOfferRegistration =
        Some(IssuerRegistration.blocked(IssuerRegistrationBlockedReason.attestationNotRegistered))
    let oIntrVouch = makeOfferInteractor(oFakeVouch, oCfgVouch)
    let _ = oIntrVouch.processOfferRequest("uri")
    let oResVouch  = oIntrVouch.issueDocuments("uri", Some("txCodeValue"))
    let ookVouch = match (oResVouch.kind) { case OfferIssuerNotTrusted => true; case _ => false }
    t.check(ookVouch, "offerDoc.issue_nonVouchingRegistration_issuerNotTrusted")
    t.eqInt(oFakeVouch.deleteDocumentCalls, 1, "offerDoc.issue_nonVouchingRegistration_discardsStoredDoc")
    t.eqStr(oFakeVouch.lastDeletedDocumentId, "offer-discarded",
        "offerDoc.issue_nonVouchingRegistration_deletesIssuedId")
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point (called from dev_unit_driver.cj:runAllUnitSuites)
// ─────────────────────────────────────────────────────────────────────────────

func runFeatureIssuanceTests(t: DeviceTestRun): Unit {
    runAddDocumentInteractorTests(t)
    runDocumentOfferInteractorTests(t)
}
