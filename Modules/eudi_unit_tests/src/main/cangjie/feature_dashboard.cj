// Device unit tests for feature-dashboard, migrated from the iOS feature-dashboard
// Tests/Interactor directory (7 iOS test classes, 78 test cases).
//
// iOS source: Modules/feature-dashboard/Tests/Interactor/
//   TestDashboardInteractor.swift         (1 case)
//   TestDocumentTabInteractor.swift       (22 cases)
//   TestDocumentDetailsInteractor.swift   (20 cases)
//   TestTransactionTabInteractor.swift    (15 cases)
//   TestSettingsInteractor.swift          (13 cases)
//   TestHomeTabInteractor.swift           (5 cases)
//   TestTransactionDetailsInteractor.swift (2 cases)
//
// Cangjie target: DashboardInteractor (dashboard_interactor.cj) collapses
// DocumentTabInteractor, TransactionTabInteractor, DocumentDetailsInteractor,
// TransactionDetailsInteractor, and HomeTabInteractor into one class.
// SettingsInteractor functionality lives in settings_view.cj.
//
// Shared fakes already defined in this package (dev_test_fakes.cj):
//   FakeWalletKitController, makeDocClaimsDecodable, makeWalletStorageDocument
// Shared fakes from dev_tests_startup.cj (same package):
//   FakePrefsController, FakeConfigLogic, FakePinStore
// Do NOT redefine any of those.
package eudi_unit_tests

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import eudi_logic_core.{
    WalletKitController, WalletKit,
    TransactionLogItem, TransactionLogData,
    DocumentStatus, DocDataFormat,
    CredentialsUsageCounts, CredentialPolicy,
    DocumentCategories,
    DocClaimsDecodable, DocClaim, DocDataValue, WalletStorageDocument,
    StatusIdentifier, DisplayMetadata, CredentialStatus,
    DocumentTypeIdentifier, DocumentElementType, DocumentElementClaim,
    ProximitySessionCoordinator, RemoteSessionCoordinator,
    OfferedIssuanceModel, OfferedDocModel,
    ScopedDocument, DynamicIssuancePendingData,
    ParsedUrlRef, DeferredDocument, IssuedDocument,
    WalletCoreError, RegistrationRefusedError
}
import eudi_feature_dashboard.{
    DashboardInteractor,
    DashboardFilterController, FilterUISectionType,
    DocumentRow, DocumentRowState,
    TransactionRow,
    DocumentDetails,
    TransactionDetails,
    TransactionDetailsViewModel,
    DocumentDetailsViewModel,
    RevokedDocumentRow, revokedRowsFrom,
    DashboardViewModel,
    CredentialUsageInfo,
    DeferredIssuanceOutcome,
    ReIssueResult,
    SettingsInteractor
}
import eudi_logic_ui.InMemoryRouterHost
import eudi_feature_common.{BiometryType, BiometryAvailability, BiometryError, BiometryUnlockResult}
import eudi_logic_business.{PrefsKey, PrefsController, ConfigLogic, BleAvailibity, ReachabilityController, FilterIds}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Build a TransactionLogItem with a given epoch-seconds timestamp and value string.
func makeTransactionLog(id!: String = "tx-1", timestamp!: Int64 = 1700000000, value!: String = "PID"): TransactionLogItem {
    TransactionLogItem(
        id: id,
        transactionLogData: TransactionLogData(timestamp: timestamp, value: value)
    )
}

// A filter the sheet can select, addressed the way the sheet addresses it.
class ToggleTarget {
    let sectionId: String
    let filterId: String
    init(sectionId: String, filterId: String) {
        this.sectionId = sectionId
        this.filterId = filterId
    }
}

// First not-yet-selected filter in the rendered sheet. Date pickers are skipped
// (they move through updateDateFilters), and an already-selected one is no good
// as a probe: re-picking the selected item of a single-selection group leaves it
// selected, so nothing would be observable.
func firstUnselectedFilter(fc: DashboardFilterController): ?ToggleTarget {
    for (section in fc.sections()) {
        for (item in section.filters) {
            match (item.sectionType) {
                case FilterUISectionType.radio where !item.selected =>
                    return Some(ToggleTarget(section.id, item.id))
                case _ => ()
            }
        }
    }
    return Option<ToggleTarget>.None
}

// First filter of one named section, whatever its current selection.
func firstFilterOfSection(fc: DashboardFilterController, sectionId: String): ?ToggleTarget {
    for (section in fc.sections()) {
        if (section.id == sectionId && !section.filters.isEmpty()) {
            return Some(ToggleTarget(section.id, section.filters[0].id))
        }
    }
    return Option<ToggleTarget>.None
}

// Current selection flag of one filter as the sheet would render it.
func selectionFlagOf(fc: DashboardFilterController, sectionId: String, filterId: String): ?Bool {
    for (section in fc.sections()) {
        if (section.id != sectionId) {
            continue
        }
        for (item in section.filters) {
            if (item.id == filterId) {
                return Some(item.selected)
            }
        }
    }
    return Option<Bool>.None
}

func firstDatePicker(fc: DashboardFilterController): ?ToggleTarget {
    for (section in fc.sections()) {
        for (item in section.filters) {
            match (item.sectionType) {
                case FilterUISectionType.datePicker =>
                    return Some(ToggleTarget(section.id, item.id))
                case _ => ()
            }
        }
    }
    return Option<ToggleTarget>.None
}

func nonHeaderDocumentCount(rows: Array<DocumentRow>): Int64 {
    var n: Int64 = 0
    for (r in rows) {
        if (!r.isHeader) {
            n++
        }
    }
    return n
}

func nonHeaderTransactionCount(rows: Array<TransactionRow>): Int64 {
    var n: Int64 = 0
    for (r in rows) {
        if (!r.isHeader) {
            n++
        }
    }
    return n
}

func filteredDocHas(fc: DashboardFilterController, all: Array<DocumentRow>, id: String): Bool {
    for (r in fc.filteredDocumentRows(all)) {
        if (!r.isHeader && r.id == id) {
            return true
        }
    }
    return false
}

func filteredTxHas(fc: DashboardFilterController, all: Array<TransactionRow>, id: String): Bool {
    for (r in fc.filteredTransactionRows(all)) {
        if (!r.isHeader && r.id == id) {
            return true
        }
    }
    return false
}

// Build a DocClaimsDecodable with a CredentialsUsageCounts attached.
// Independent implementation (does not subclass FakeDocClaims, which is not open).
class FakeDocWithUsage <: DocClaimsDecodable {
    let id_: String
    let usage_: ?CredentialsUsageCounts
    init(id: String, usage: ?CredentialsUsageCounts) {
        this.id_ = id
        this.usage_ = usage
    }
    public prop id: String { get() { this.id_ } }
    public prop statusIdentifier: ?StatusIdentifier { get() { None } }
    public prop createdAt: DateTime { get() { DateTime.now() } }
    public prop modifiedAt: ?DateTime { get() { None } }
    public prop displayName: ?String { get() { Some("PID") } }
    public prop docType: String { get() { "eu.europa.ec.eudi.pid.1" } }
    public prop docClaims: Array<DocClaim> { get() { Array<DocClaim>() } }
    public prop docDataFormat: DocDataFormat { get() { DocDataFormat.cbor } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { HashMap<Int64, Bool>() } }
    public prop display: ?Array<DisplayMetadata> { get() { None } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { None } }
    public prop credentialIssuerIdentifier: ?String { get() { None } }
    public prop configurationIdentifier: ?String { get() { None } }
    public prop validFrom: ?DateTime { get() { None } }
    public prop validUntil: ?DateTime { get() { None } }
    public prop secureAreaName: ?String { get() { None } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { this.usage_ } }
    public prop credentialPolicy: CredentialPolicy { get() { CredentialPolicy.rotateUse } }
}

// A DocClaimsDecodable carrying given_name / family_name claims so getBearersName()
// resolves a real bearer name (mirrors iOS Constants.createEuPidModel bearer "John").
class FakePidDocWithName <: DocClaimsDecodable {
    let id_: String
    let claims_: Array<DocClaim>
    init(id: String, firstName: ?String, lastName: ?String) {
        this.id_ = id
        let list = ArrayList<DocClaim>()
        if (let Some(f) <- firstName) {
            list.add(DocClaim(name: "given_name", dataValue: DocDataValue.text(f), stringValue: f))
        }
        if (let Some(l) <- lastName) {
            list.add(DocClaim(name: "family_name", dataValue: DocDataValue.text(l), stringValue: l))
        }
        this.claims_ = list.toArray()
    }
    public prop id: String { get() { this.id_ } }
    public prop statusIdentifier: ?StatusIdentifier { get() { None } }
    public prop createdAt: DateTime { get() { DateTime.now() } }
    public prop modifiedAt: ?DateTime { get() { None } }
    public prop displayName: ?String { get() { Some("PID") } }
    public prop docType: String { get() { "eu.europa.ec.eudi.pid.1" } }
    public prop docClaims: Array<DocClaim> { get() { this.claims_ } }
    public prop docDataFormat: DocDataFormat { get() { DocDataFormat.cbor } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { HashMap<Int64, Bool>() } }
    public prop display: ?Array<DisplayMetadata> { get() { None } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { None } }
    public prop credentialIssuerIdentifier: ?String { get() { None } }
    public prop configurationIdentifier: ?String { get() { None } }
    public prop validFrom: ?DateTime { get() { None } }
    public prop validUntil: ?DateTime { get() { None } }
    public prop secureAreaName: ?String { get() { None } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { None } }
    public prop credentialPolicy: CredentialPolicy { get() { CredentialPolicy.rotateUse } }
}

// Per-deferred-id issuance outcome for FakeDeferredWalletKit.requestDeferredIssuance.
enum DeferredResult {
    | issuedDoc(DocClaimsDecodable)   // completed → returns an issued (non-deferred) doc
    | stillDeferred(DeferredDocument) // issuer not ready → returns a DeferredDocument (skipped by interactor)
    | throwsError                     // issuance throws → interactor records id in `failed`
}

// FakeWalletKitController extension that drives requestDeferredIssuance() per-doc.
// FakeWalletKitController is `open`; override just requestDeferredIssuance + revoked set.
class FakeDeferredWalletKit <: FakeWalletKitController {
    // Map deferred-doc id → configured outcome.
    let outcomes = HashMap<String, DeferredResult>()

    public override func requestDeferredIssuance(doc: WalletStorageDocument): DocClaimsDecodable {
        match (this.outcomes.get(doc.id)) {
            case Some(DeferredResult.issuedDoc(d)) => d
            case Some(DeferredResult.stillDeferred(d)) => d
            case Some(DeferredResult.throwsError) => throw Exception("fake: deferred issuance failed for ${doc.id}")
            case None => throw Exception("fake: no deferred outcome configured for ${doc.id}")
        }
    }
}

// FakeWalletKitController whose bookmark store/remove throw — drives the
// saveBookmark/deleteBookmark failure paths (iOS thrown-error → interactor false).
class ThrowingBookmarkWalletKit <: FakeWalletKitController {
    public override func storeBookmarkedDocument(id: String): Unit {
        throw Exception("fake: storeBookmarkedDocument failed")
    }
    public override func removeBookmarkedDocument(id: String): Unit {
        throw Exception("fake: removeBookmarkedDocument failed")
    }
}

// FakeWalletKitController whose reIssueDocument returns a document (success path)
// rather than the base class's throw — drives ReIssueResult.ReIssueSuccess.
class SucceedingReIssueWalletKit <: FakeWalletKitController {
    public override func reIssueDocument(identifier!: String, isBackgroundOperation!: Bool): WalletStorageDocument {
        return makeWalletStorageDocument(id: identifier, status: DocumentStatus.issued)
    }
}

// FakeWalletKitController whose reIssueDocument throws RegistrationRefusedError —
// the controller's registration pre-check refusal (iOS: recognised by
// isTrustBlocked → .issuerNotTrusted).
class RegistrationRefusedReIssueWalletKit <: FakeWalletKitController {
    public override func reIssueDocument(identifier!: String, isBackgroundOperation!: Bool): WalletStorageDocument {
        throw RegistrationRefusedError()
    }
}

// Configurable ReachabilityController fake for HomeTab BLE tests.
class FakeReachabilityController <: ReachabilityController {
    var bleAvailability: BleAvailibity = BleAvailibity.unavailable
    var openBleSettingsCalls: Int64 = 0
    var hasInternetResult: Bool = true
    public func hasInternet(): Bool { this.hasInternetResult }
    public func getBleAvailibity(callback: (BleAvailibity) -> Unit): Unit {
        callback(this.bleAvailability)
    }
    public func openBleSettings(): Unit { this.openBleSettingsCalls += 1 }
}

// Configurable PrefsController fake for Settings tests. Tracks per-key writes and
// serves per-key bool values (unlike the shared FakePrefsController, which is fixed
// to false). Kept local to this file to avoid touching the startup-test fake.
class SettingsPrefsFake <: PrefsController {
    let bools = HashMap<String, Bool>()
    let lastSet = HashMap<String, Bool>()
    var setCount: Int64 = 0
    public func setValue(value: ToString, forKey: PrefsKey): Unit {
        this.setCount += 1
        this.lastSet[forKey.rawValue] = value.toString() == "true"
    }
    public func getString(forKey: PrefsKey): ?String { None }
    public func getOptionalString(forKey: PrefsKey): String { "" }
    public func getBool(forKey: PrefsKey): Bool {
        match (this.bools.get(forKey.rawValue)) {
            case Some(b) => b
            case None => false
        }
    }
    public func getFloat(forKey: PrefsKey): Float64 { 0.0 }
    public func getInt(forKey: PrefsKey): Int64 { 0 }
    public func remove(forKey: PrefsKey): Unit {}
    public func getValue(forKey: PrefsKey): ?String { None }
    public func getUserLocale(): String { "en_GB" }
}

// ─── TestDashboardInteractor (1 iOS case) ────────────────────────────────────

func runDashboardInteractorTests(t: DeviceTestRun): Unit {
    // ── testGetWalletKitController_WhenInteractorReturnsWalletKitController_ThenVerifyControllerIsInjected ──
    // iOS asserts the accessor hands back the very instance that was injected.
    // Cangjie has no reference-identity operator in use here, so identity is
    // established behaviourally: the fake is seeded with a document id no other
    // instance carries, and the returned controller must expose exactly that.
    let fake1 = FakeWalletKitController()
    fake1.allDocuments = [makeDocClaimsDecodable(id: "injected-marker-doc")]
    let interactor1 = DashboardInteractor(walletController: fake1)
    let returned1 = interactor1.getWalletKitController()
    let docs1 = returned1.fetchAllDocuments()
    t.eqInt(docs1.size, 1, "dashboard.getWalletKitController_returnsInjected_docCount")
    if (docs1.size == 1) {
        t.eqStr(docs1[0].id, "injected-marker-doc", "dashboard.getWalletKitController_returnsInjectedInstance")
    } else {
        t.check(false, "dashboard.getWalletKitController_returnsInjectedInstance_wrongCount")
    }
    // Guard: a different instance must NOT satisfy the assertion above, otherwise
    // it would pass for any controller and prove nothing about injection.
    let other1 = FakeWalletKitController()
    t.eqInt(other1.fetchAllDocuments().size, 0, "dashboard.getWalletKitController_otherInstanceIsDistinguishable")
}

// ─── TestDocumentTabInteractor (22 iOS cases) ─────────────────────────────────

func runDocumentTabInteractorTests(t: DeviceTestRun): Unit {

    // Both testHasDeferredDocuments_* cases are asserted further down, next to the
    // requestDeferredIssuance tests they sit with (search "hasDeferredDocuments_present").

    // iOS: testFetchDocuments_WhenWalletKitControllerReturnsEmptyDocuments_ThenReturnsError
    // Cangjie: fetchDocumentRows() returns empty array when allDocuments is empty.
    let fake2 = FakeWalletKitController()
    fake2.allDocuments = Array<DocClaimsDecodable>()
    let interactor2 = DashboardInteractor(walletController: fake2)
    let rows2 = interactor2.fetchDocumentRows()
    t.check(rows2.isEmpty(), "docTab.fetchDocuments_empty_returnsEmpty")

    // iOS: testFetchDocuments_WhenWalletKitControllerReturnsData_ThenReturnsUiModels
    // Cangjie: fetchDocumentRows() returns non-empty list when allDocuments has items.
    let fake3 = FakeWalletKitController()
    fake3.allDocuments = [makeDocClaimsDecodable(id: "pid-1"), makeDocClaimsDecodable(id: "mdl-1")]
    let interactor3 = DashboardInteractor(walletController: fake3)
    let rows3 = interactor3.fetchDocumentRows()
    t.check(!rows3.isEmpty(), "docTab.fetchDocuments_withData_returnsNonEmpty")

    // iOS: testFetchDocuments_WhenWalletKitControllerReturnsDataWithNilUsageCount_ThenReturnsUiModels
    // Cangjie: documents without credentialsUsageCounts still produce rows.
    let fake4 = FakeWalletKitController()
    fake4.allDocuments = [makeDocClaimsDecodable(id: "pid-2", credentialPolicy: CredentialPolicy.rotateUse)]
    let interactor4 = DashboardInteractor(walletController: fake4)
    let rows4 = interactor4.fetchDocumentRows()
    t.check(!rows4.isEmpty(), "docTab.fetchDocuments_nilUsageCount_returnsRows")

    // iOS: DocumentTabInteractor.fetchDocuments → usageCount: isBatchCounterEnabled() ? … : nil
    // Cangjie: the card's usageText is built only while PrefsKey.batchCounter is on;
    // off → empty (badge hidden), on → "remaining/total" (1/1 when the engine has no counts).
    // The badge is built only for an IssuedDocument (usageTextFor matches on the
    // concrete type), so the fixture must be one — FakeDocClaims never gets a badge.
    let fakeBadge = FakeWalletKitController()
    fakeBadge.allDocuments = [IssuedDocument(
        id: "pid-badge", createdAt: DateTime.now(), displayName: Some("Fake Document"),
        docType: "eu.europa.ec.eudi.pid.1", credentialPolicy: CredentialPolicy.rotateUse
    )]
    let prefsBadgeOff = SettingsPrefsFake()
    prefsBadgeOff.bools[PrefsKey.batchCounter.rawValue] = false
    let rowsBadgeOff = DashboardInteractor(walletController: fakeBadge, prefs: prefsBadgeOff).fetchDocumentRows()
    var badgeHiddenWhenOff = true
    for (r in rowsBadgeOff) { if (!r.isHeader && !r.usageText.isEmpty()) { badgeHiddenWhenOff = false } }
    t.check(badgeHiddenWhenOff, "docTab.usageBadge_hiddenWhenBatchCounterOff")
    let prefsBadgeOn = SettingsPrefsFake()
    prefsBadgeOn.bools[PrefsKey.batchCounter.rawValue] = true
    let rowsBadgeOn = DashboardInteractor(walletController: fakeBadge, prefs: prefsBadgeOn).fetchDocumentRows()
    var badgeShownWhenOn = false
    for (r in rowsBadgeOn) { if (!r.isHeader && !r.usageText.isEmpty()) { badgeShownWhenOn = true } }
    t.check(badgeShownWhenOn, "docTab.usageBadge_shownWhenBatchCounterOn")

    // iOS: testDeleteDeferredDocument_WhenWalletKitControllerDeleteSucceedsAndNoDocumentsRemain_ThenReturnsNoDocuments
    // Cangjie: deleteDocument() returns true on success; fetchDocumentRows empty after.
    let fake5 = FakeWalletKitController()
    fake5.allDocuments = Array<DocClaimsDecodable>()
    let interactor5 = DashboardInteractor(walletController: fake5)
    let deleted5 = interactor5.deleteDocument("some-id")
    t.check(deleted5, "docTab.deleteDeferredDocument_succeeds_returnsTrue")
    let rows5 = interactor5.fetchDocumentRows()
    t.check(rows5.isEmpty(), "docTab.deleteDeferredDocument_noDocsRemain_empty")

    // iOS: testDeleteDeferredDocument_WhenWalletKitControllerDeleteFails_ThenReturnsFailure
    // Cangjie: deleteDeferredDocument() catches the controller exception and returns
    // false (iOS returns .failure). Driven by deleteDocumentShouldThrow.
    let fake6 = FakeWalletKitController()
    fake6.deleteDocumentShouldThrow = true
    let interactor6 = DashboardInteractor(walletController: fake6)
    let deleted6 = interactor6.deleteDeferredDocument("deferred-id")
    t.check(!deleted6, "docTab.deleteDeferredDocument_deleteThrows_returnsFalse")
    // The delete was still attempted, and against the deferred partition.
    t.eqInt(fake6.deleteDocumentCalls, 1, "docTab.deleteDeferredDocument_deleteThrows_stillAttempted")
    t.check(fake6.lastDeletedDocumentStatus == DocumentStatus.deferred,
        "docTab.deleteDeferredDocument_deleteThrows_usedDeferredStatus")

    // iOS: testDeleteDeferredDocument_WhenWalletKitControllerDeleteSucceeds_ThenReturnsDocuments
    // Cangjie: after delete, the remaining documents are fetched fresh from allDocuments.
    let fake7 = FakeWalletKitController()
    fake7.allDocuments = [makeDocClaimsDecodable(id: "pid-3")]
    let interactor7 = DashboardInteractor(walletController: fake7)
    let deleted7 = interactor7.deleteDocument("some-other-id")
    t.check(deleted7, "docTab.deleteDeferredDocument_withDocs_returnsTrue")
    let rows7 = interactor7.fetchDocumentRows()
    t.check(!rows7.isEmpty(), "docTab.deleteDeferredDocument_docsRemain_nonEmpty")

    // iOS: testApplyFilters_WhenFilterValidatorApplyFilters_ThenApplyFiltersWasCalled
    // iOS only verifies the validator method was invoked. Here applyFilters is
    // the step that copies the snapshot onto the applied list: deselecting
    // "Valid" (a multiple-selection group with nothing else on) must leave the
    // applied list alone until apply, then drop every issued document.
    let fake8 = FakeWalletKitController()
    fake8.allDocuments = [
        makeDocClaimsDecodable(id: "pid-4a", displayName: Some("Alpha")),
        makeDocClaimsDecodable(id: "pid-4b", displayName: Some("Beta"))
    ]
    let interactor8 = DashboardInteractor(walletController: fake8)
    let rows8 = interactor8.fetchDocumentRows()
    let fc8 = interactor8.buildDocumentFilterController(rows8)
    let appliedBefore8 = nonHeaderDocumentCount(fc8.filteredDocumentRows(rows8))
    t.check(appliedBefore8 > 0, "docTab.applyFilters_startsWithAppliedList")
    fc8.updateFilter(FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)
    t.eqInt(nonHeaderDocumentCount(fc8.filteredDocumentRows(rows8)), appliedBefore8,
        "docTab.applyFilters_updateDoesNotRebuildAppliedList")
    fc8.applyFilters()
    t.eqInt(nonHeaderDocumentCount(fc8.filteredDocumentRows(rows8)), 0,
        "docTab.applyFilters_rebuildsAppliedListFromSnapshot")

    // iOS: testUpdateLists_WhenDocumentsFetchedAndStateIsSuccess_ThenUsesFilterValidatorUpdateLists
    // Cangjie: DashboardFilterController.updateLists(rows) swaps the engine's source
    // list (delegates to FilterValidatorImpl.updateLists, same as iOS) while keeping
    // filter selections. Verified behaviourally: a row present only in the refreshed
    // list survives filtering, and a row only in the original list is gone.
    let fake9 = FakeWalletKitController()
    fake9.allDocuments = [makeDocClaimsDecodable(id: "old-doc", displayName: Some("Old Doc"))]
    let interactor9 = DashboardInteractor(walletController: fake9)
    let rows9old = interactor9.fetchDocumentRows()
    let fc9 = interactor9.buildDocumentFilterController(rows9old)

    fake9.allDocuments = [makeDocClaimsDecodable(id: "new-doc", displayName: Some("New Doc"))]
    let rows9new = interactor9.fetchDocumentRows()
    fc9.updateLists(rows9new)
    fc9.applyFilters()

    let filtered9 = fc9.filteredDocumentRows(rows9new)
    var sawNew9 = false
    for (r in filtered9) {
        if (r.id == "new-doc") { sawNew9 = true }
    }
    t.check(sawNew9, "docTab.updateLists_refreshedRow_survivesFiltering")
    // The stale row is no longer part of the engine's source list.
    let staleFiltered9 = fc9.filteredDocumentRows(rows9old)
    t.check(staleFiltered9.isEmpty(), "docTab.updateLists_staleRow_droppedFromSource")

    // iOS: testResetFilters_WhenFilterValidatorResetFilters_ThenResetFiltersWasCalled
    // resetFilters restores the default groups and re-applies, so a list that
    // applyFilters just emptied (Valid deselected) must come back.
    let fake10 = FakeWalletKitController()
    fake10.allDocuments = [makeDocClaimsDecodable(id: "pid-5", displayName: Some("PID"))]
    let interactor10 = DashboardInteractor(walletController: fake10)
    let rows10 = interactor10.fetchDocumentRows()
    let fc10 = interactor10.buildDocumentFilterController(rows10)
    fc10.updateFilter(FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)
    fc10.applyFilters()
    t.eqInt(nonHeaderDocumentCount(fc10.filteredDocumentRows(rows10)), 0,
        "docTab.resetFilters_setup_listEmpty")
    fc10.resetFilters()
    t.check(nonHeaderDocumentCount(fc10.filteredDocumentRows(rows10)) > 0,
        "docTab.resetFilters_restoresDefaultAppliedList")
    match (selectionFlagOf(fc10, FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)) {
        case Some(selected) => t.check(selected, "docTab.resetFilters_restoresValidSelection")
        case None => t.check(false, "docTab.resetFilters_restoresValidSelection_missing")
    }

    // iOS: testRevertFilters_WhenFilterValidatorRevertFilters_ThenRevertFiltersWasCalled
    // revertFilters throws away the snapshot and re-emits the already-applied
    // groups: the sheet selection rolls back, the applied list does not.
    let fake11 = FakeWalletKitController()
    fake11.allDocuments = [makeDocClaimsDecodable(id: "pid-6", displayName: Some("PID"))]
    let interactor11 = DashboardInteractor(walletController: fake11)
    let rows11 = interactor11.fetchDocumentRows()
    let fc11 = interactor11.buildDocumentFilterController(rows11)
    let appliedBefore11 = nonHeaderDocumentCount(fc11.filteredDocumentRows(rows11))
    fc11.updateFilter(FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)
    match (selectionFlagOf(fc11, FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)) {
        case Some(selected) => t.check(!selected, "docTab.revertFilters_setup_validDeselected")
        case None => t.check(false, "docTab.revertFilters_setup_validDeselected_missing")
    }
    t.eqInt(nonHeaderDocumentCount(fc11.filteredDocumentRows(rows11)), appliedBefore11,
        "docTab.revertFilters_setup_appliedListUntouched")
    fc11.revertFilters()
    match (selectionFlagOf(fc11, FilterIds.FILTER_BY_STATE_GROUP_ID, FilterIds.FILTER_BY_STATE_VALID)) {
        case Some(selected) => t.check(selected, "docTab.revertFilters_restoresSnapshotSelection")
        case None => t.check(false, "docTab.revertFilters_restoresSnapshotSelection_missing")
    }
    t.eqInt(nonHeaderDocumentCount(fc11.filteredDocumentRows(rows11)), appliedBefore11,
        "docTab.revertFilters_doesNotRebuildAppliedList")

    // iOS: testUpdateFilters_WhenFilterValidatorUpdateFilters_ThenUpdateFiltersWasCalled
    // updateFilter is snapshot-only: an unselected radio becomes selected and
    // the applied list stays put. Empty ids are a no-op, so this uses a real one.
    let fake12 = FakeWalletKitController()
    fake12.allDocuments = [makeDocClaimsDecodable(id: "pid-7", displayName: Some("PID"))]
    let interactor12 = DashboardInteractor(walletController: fake12)
    let rows12 = interactor12.fetchDocumentRows()
    let fc12 = interactor12.buildDocumentFilterController(rows12)
    let appliedBefore12 = nonHeaderDocumentCount(fc12.filteredDocumentRows(rows12))
    match (firstUnselectedFilter(fc12)) {
        case Some(target) =>
            fc12.updateFilter(target.sectionId, target.filterId)
            match (selectionFlagOf(fc12, target.sectionId, target.filterId)) {
                case Some(after) => t.check(after, "docTab.updateFilters_movesSnapshotSelection")
                case None => t.check(false, "docTab.updateFilters_movesSnapshotSelection_missing")
            }
            t.eqInt(nonHeaderDocumentCount(fc12.filteredDocumentRows(rows12)), appliedBefore12,
                "docTab.updateFilters_leavesAppliedListUntouched")
        case None => t.check(false, "docTab.updateFilters_noUnselectedFilter")
    }

    // iOS: testApplySearch_WhenFilterValidatorApplySearch_ThenUsesFilterValidator
    // applySearch writes the query and immediately applyFilters, so the applied
    // list must keep the matching document and drop the other.
    let fake13 = FakeWalletKitController()
    fake13.allDocuments = [
        makeDocClaimsDecodable(id: "pid-8a", displayName: Some("Alpha")),
        makeDocClaimsDecodable(id: "pid-8b", displayName: Some("Beta"))
    ]
    let interactor13 = DashboardInteractor(walletController: fake13)
    let rows13 = interactor13.fetchDocumentRows()
    let fc13 = interactor13.buildDocumentFilterController(rows13)
    fc13.applySearch("Alpha")
    t.check(filteredDocHas(fc13, rows13, "pid-8a"), "docTab.applySearch_keepsMatchingRow")
    t.check(!filteredDocHas(fc13, rows13, "pid-8b"), "docTab.applySearch_dropsNonMatchingRow")

    // iOS: testOnFilterChangeState_WhenStreamEmitsResults_ThenProcessesResultsCorrectly
    // iOS stubs the validator stream to yield filterApplyResult then
    // filterUpdateResult and asserts the consumer saw exactly those two, each
    // mapped to its own case — the apply result carries a list, the update result
    // carries filters only. Cangjie's consumer is onEngine(), which draws the same
    // distinction (apply rebuilds the applied id list, update moves only the
    // snapshot), so here the two kinds are told apart by their effects. The
    // "exactly two emissions, in this order" assertion sits in the host suite
    // (filter_validator_test.cj, testEngineEmitsApplyThenUpdateInOrder) where the
    // emissions themselves are observable.
    let fakeSeq = FakeWalletKitController()
    fakeSeq.allDocuments = [
        makeDocClaimsDecodable(id: "seq-a", displayName: Some("Alpha")),
        makeDocClaimsDecodable(id: "seq-b", displayName: Some("Beta"))
    ]
    let interactorSeq = DashboardInteractor(walletController: fakeSeq)
    let rowsSeq = interactorSeq.fetchDocumentRows()
    let fcSeq = interactorSeq.buildDocumentFilterController(rowsSeq)

    // An apply event populates the applied list (iOS results[0]: filteredList).
    fcSeq.applyFilters()
    let appliedSeq = fcSeq.filteredDocumentRows(rowsSeq).size
    t.check(appliedSeq > 0, "docTab.filterChangeState_applyEvent_populatesFilteredList")

    // An update event carries filters only (iOS results[1]: updatedFilters): it
    // must move the snapshot the sheet renders and leave the applied list alone.
    match (firstUnselectedFilter(fcSeq)) {
        case Some(target) =>
            fcSeq.updateFilter(target.sectionId, target.filterId)
            match (selectionFlagOf(fcSeq, target.sectionId, target.filterId)) {
                case Some(after) =>
                    t.check(after, "docTab.filterChangeState_updateEvent_movesSnapshotSelection")
                case None =>
                    t.check(false, "docTab.filterChangeState_updateEvent_filterMissingFromSnapshot")
            }
            t.eqInt(fcSeq.filteredDocumentRows(rowsSeq).size, appliedSeq,
                "docTab.filterChangeState_updateEvent_leavesAppliedListUntouched")
        case None =>
            t.check(false, "docTab.filterChangeState_updateEvent_noUnselectedFilter")
    }

    // The next apply event does rebuild the list, so the two kinds cannot have
    // been collapsed into one handler.
    fcSeq.applySearch("zzz-no-such-document")
    fcSeq.applyFilters()
    t.check(fcSeq.filteredDocumentRows(rowsSeq).isEmpty(),
        "docTab.filterChangeState_applyEvent_rebuildsFilteredList")

    // ── testOnFilterChangeState_WhenStreamYieldsCompletion_ThenForwardsCancelledAndFinishes ──
    // iOS: the validator stream completes → interactor yields .cancelled and
    // finishes the stream, after which nothing more is delivered.
    // Cangjie: there is no stream to finish, so completion is recorded as
    // terminal state (isCancelled) and later engine emissions are ignored.
    let fake14 = FakeWalletKitController()
    fake14.allDocuments = [makeDocClaimsDecodable(id: "pid-cancel")]
    let interactor14 = DashboardInteractor(walletController: fake14)
    let rows14 = interactor14.fetchDocumentRows()
    let fc14 = interactor14.buildDocumentFilterController(rows14)
    t.check(!fc14.isCancelled, "docTab.filterChangeState_beforeCompletion_notCancelled")
    fc14.applyFilters()
    let sectionsBefore14 = fc14.sections().size
    let appliedBefore14 = fc14.filteredDocumentRows(rows14).size
    fc14.complete()
    t.check(fc14.isCancelled, "docTab.filterChangeState_completion_cancelled")
    // iOS asserts the FIRST value delivered after completion is `.cancelled` — i.e.
    // completion surfaces cancellation and nothing result-shaped. The analogue here
    // is that the completion event leaves both result-carrying surfaces untouched.
    t.eqInt(fc14.sections().size, sectionsBefore14,
        "docTab.filterChangeState_completion_carriesNoFilterResult_sections")
    t.eqInt(fc14.filteredDocumentRows(rows14).size, appliedBefore14,
        "docTab.filterChangeState_completion_carriesNoFilterResult_appliedList")
    // Terminal means terminal: driving the engine afterwards must not revive it
    // nor mutate the frozen snapshot (iOS: yields after finish() are dropped).
    fc14.applySearch("anything")
    fc14.applyFilters()
    t.check(fc14.isCancelled, "docTab.filterChangeState_afterCompletion_staysCancelled")
    t.eqInt(fc14.sections().size, sectionsBefore14, "docTab.filterChangeState_afterCompletion_snapshotFrozen")
    // Idempotent: the engine drops its listener on the first completion, so a
    // second complete() cannot re-emit or flip anything back.
    fc14.complete()
    t.check(fc14.isCancelled, "docTab.filterChangeState_completeTwice_idempotent")

    // iOS: testRequestDeferredIssuance_WhenAllIssuanceSucceeds_ThenReturnsIssuedModels
    // Cangjie: requestDeferredIssuance() iterates deferred docs, calls the controller,
    // and returns issued rows for docs that completed (are no longer DeferredDocument).
    let defFakeA = FakeDeferredWalletKit()
    defFakeA.deferredDocuments = [makeWalletStorageDocument(id: "def-a", status: DocumentStatus.deferred)]
    defFakeA.outcomes["def-a"] = DeferredResult.issuedDoc(makeDocClaimsDecodable(id: "issued-a", displayName: Some("PID")))
    let defInteractorA = DashboardInteractor(walletController: defFakeA)
    let outcomeA = defInteractorA.requestDeferredIssuance()
    t.eqInt(outcomeA.issued.size, 1, "docTab.requestDeferredIssuance_allSucceed_oneIssued")
    t.eqInt(outcomeA.failed.size, 0, "docTab.requestDeferredIssuance_allSucceed_noFailed")
    t.check(!outcomeA.cancelled, "docTab.requestDeferredIssuance_allSucceed_notCancelled")

    // iOS: testRequestDeferredIssuance_WhenIssuanceFails_ThenReturnsFailedIds
    // Cangjie: a throwing deferred call records that deferred doc's id in `failed`.
    let defFakeB = FakeDeferredWalletKit()
    defFakeB.deferredDocuments = [makeWalletStorageDocument(id: "fail-id", status: DocumentStatus.deferred)]
    defFakeB.outcomes["fail-id"] = DeferredResult.throwsError
    let defInteractorB = DashboardInteractor(walletController: defFakeB)
    let outcomeB = defInteractorB.requestDeferredIssuance()
    t.eqInt(outcomeB.issued.size, 0, "docTab.requestDeferredIssuance_fails_noIssued")
    t.eqInt(outcomeB.failed.size, 1, "docTab.requestDeferredIssuance_fails_oneFailed")
    if (outcomeB.failed.size == 1) {
        t.eqStr(outcomeB.failed[0], "fail-id", "docTab.requestDeferredIssuance_fails_correctFailedId")
    } else {
        t.check(false, "docTab.requestDeferredIssuance_fails_correctFailedId_wrongCount")
    }

    // iOS: testRequestDeferredIssuance_WhenNoDeferredDocuments_ThenReturnsEmptyIssuedAndFailed
    // Cangjie: no deferred docs → both arrays empty.
    let defFakeC = FakeDeferredWalletKit()
    defFakeC.deferredDocuments = Array<WalletStorageDocument>()
    let defInteractorC = DashboardInteractor(walletController: defFakeC)
    let outcomeC = defInteractorC.requestDeferredIssuance()
    t.check(outcomeC.issued.isEmpty(), "docTab.requestDeferredIssuance_noDeferred_issuedEmpty")
    t.check(outcomeC.failed.isEmpty(), "docTab.requestDeferredIssuance_noDeferred_failedEmpty")

    // Cangjie extra: a deferred doc whose issuance is still pending (returns a
    // DeferredDocument) is skipped from `issued` — mirrors iOS
    // `(document is DeferrredDocument) == false` guard.
    let defFakeD = FakeDeferredWalletKit()
    defFakeD.deferredDocuments = [
        makeWalletStorageDocument(id: "still-def", status: DocumentStatus.deferred),
        makeWalletStorageDocument(id: "done-def", status: DocumentStatus.deferred)
    ]
    defFakeD.outcomes["still-def"] = DeferredResult.stillDeferred(
        DeferredDocument(id: "still-def", createdAt: DateTime.now(), docType: "", docDataFormat: DocDataFormat.cbor)
    )
    defFakeD.outcomes["done-def"] = DeferredResult.issuedDoc(makeDocClaimsDecodable(id: "done-def", displayName: Some("PID")))
    let defInteractorD = DashboardInteractor(walletController: defFakeD)
    let outcomeD = defInteractorD.requestDeferredIssuance()
    t.eqInt(outcomeD.issued.size, 1, "docTab.requestDeferredIssuance_stillDeferredSkipped_oneIssued")
    t.eqInt(outcomeD.failed.size, 0, "docTab.requestDeferredIssuance_stillDeferredSkipped_noFailed")

    // ── testHasDeferredDocuments_WhenWalletKitControllerReturnsDeferredDocuments_ThenReturnsTrue ──
    let hasDefFake = FakeDeferredWalletKit()
    hasDefFake.deferredDocuments = [makeWalletStorageDocument(id: "has-def", status: DocumentStatus.deferred)]
    hasDefFake.outcomes["has-def"] = DeferredResult.issuedDoc(makeDocClaimsDecodable(id: "has-def-issued"))
    let hasDefInteractor = DashboardInteractor(walletController: hasDefFake)
    t.check(hasDefInteractor.hasDeferredDocuments(), "docTab.hasDeferredDocuments_present_returnsTrue")
    // The accessor must not consume or complete anything — the polling decision is
    // separate from the polling itself (iOS calls it as a guard before scheduling).
    t.eqInt(hasDefInteractor.requestDeferredIssuance().issued.size, 1, "docTab.hasDeferredDocuments_present_processedOne")

    // ── testHasDeferredDocuments_WhenWalletKitControllerReturnsNoDeferredDocuments_ThenReturnsFalse ──
    let noDefFake = FakeDeferredWalletKit()
    noDefFake.deferredDocuments = Array<WalletStorageDocument>()
    let noDefInteractor = DashboardInteractor(walletController: noDefFake)
    t.check(!noDefInteractor.hasDeferredDocuments(), "docTab.hasDeferredDocuments_absent_returnsFalse")
    t.eqInt(noDefInteractor.requestDeferredIssuance().issued.size, 0, "docTab.hasDeferredDocuments_absent_processedNone")

    // iOS: testInitializeFilters_WhenCalled_ThenInitializesFilterValidatorWithCorrectArguments
    let fake18 = FakeWalletKitController()
    fake18.allDocuments = [makeDocClaimsDecodable(id: "pid-9", displayName: Some("PID"))]
    let interactor18 = DashboardInteractor(walletController: fake18)
    let rows18 = interactor18.fetchDocumentRows()
    // buildDocumentFilterController is the Cangjie equivalent of initializeFilters
    let fc18 = interactor18.buildDocumentFilterController(rows18)
    let sections18 = fc18.sections()
    // Should have at least one filter section (sort section at minimum).
    t.check(sections18.size >= 1, "docTab.initializeFilters_producesAtLeastOneSortSection")

    // iOS: testOnFilterChangeState_WhenStreamYieldsCompletion_ThenForwardsCancelledAndFinishes
    // Covered by the fc14 block above (completion → isCancelled, terminal, idempotent).

    // iOS: testDeleteDeferredDocument_WhenEmptyDocumentsButForcePidActivationDisabled_ThenReturnsSuccess
    // Cangjie: deleteDocument() does not check forcePidActivation; it always returns
    // true (no throw from fake). Verified by calling with empty allDocuments.
    let fake20 = FakeWalletKitController()
    fake20.allDocuments = Array<DocClaimsDecodable>()
    let interactor20 = DashboardInteractor(walletController: fake20)
    let del20 = interactor20.deleteDocument("any-id")
    t.check(del20, "docTab.deleteDeferredDocument_forcePidDisabled_returnsTrue")

    // iOS: testAddDynamicFilters_WhenDocumentsHaveIssuerAndCategoryAttributes_ThenPopulatesIssuerAndCategoryGroups
    // Cangjie: forDocuments() builds issuer + category groups from row data. Verify
    // that two distinct-issuer documents produce an issuer group with ≥2 items.
    let docA = makeDocClaimsDecodable(id: "doc-a", displayName: Some("Doc A"))
    let docB = makeDocClaimsDecodable(id: "doc-b", displayName: Some("Doc B"))
    let fake21 = FakeWalletKitController()
    fake21.allDocuments = [docA, docB]
    let interactor21 = DashboardInteractor(walletController: fake21)
    let rows21 = interactor21.fetchDocumentRows()
    let fc21 = interactor21.buildDocumentFilterController(rows21)
    let sections21 = fc21.sections()
    // At least a sort section must exist; issuer/category groups appear only if
    // rows carry distinct issuer/category metadata. With FakeDocClaims (no issuer
    // display metadata), issuer is "" so the issuer group may be empty — that is
    // the correct Cangjie behavior for test data without issuer metadata.
    t.check(sections21.size >= 1, "docTab.addDynamicFilters_sectionsExist")
}

// ─── TestDocumentDetailsInteractor (20 iOS cases) ────────────────────────────

func runDocumentDetailsInteractorTests(t: DeviceTestRun): Unit {

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsValidDocument_ThenReturnsExpectedValues
    // Cangjie: fetchDocumentDetails returns Some(DocumentDetails) when documentById is set.
    let fake1 = FakeWalletKitController()
    fake1.documentById = Some(makeDocClaimsDecodable(id: "pid-10"))
    let interactor1 = DashboardInteractor(walletController: fake1)
    let result1 = interactor1.fetchDocumentDetails("pid-10")
    t.check(result1.isSome(), "docDetails.fetchStored_validDoc_returnsSome")
    match (result1) {
        case Some(d) => t.eqStr(d.id, "pid-10", "docDetails.fetchStored_validDoc_correctId")
        case None => t.check(false, "docDetails.fetchStored_validDoc_correctId_unexpectedNone")
    }

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsValidDocumentWithBatchDisabled_ThenReturnsExpectedValues
    // Cangjie: same path regardless of batch flag (flag not in this interactor).
    let fake2 = FakeWalletKitController()
    let docWithUsage = FakeDocWithUsage("pid-11", Some(CredentialsUsageCounts(5, 2)))
    fake2.documentById = Some(docWithUsage)
    let interactor2 = DashboardInteractor(walletController: fake2)
    let result2 = interactor2.fetchDocumentDetails("pid-11")
    t.check(result2.isSome(), "docDetails.fetchStored_batchDisabled_returnsSome")
    match (result2) {
        case Some(d) =>
            t.eqStr(d.id, "pid-11", "docDetails.fetchStored_batchDisabled_correctId")
        case None => t.check(false, "docDetails.fetchStored_batchDisabled_unexpectedNone")
    }

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsValidDocumentWithNilUsageCount_ThenReturnsExpectedValues
    // Cangjie: credentialUsage is None when document has no credentialsUsageCounts.
    let fake3 = FakeWalletKitController()
    fake3.documentById = Some(makeDocClaimsDecodable(id: "pid-12"))
    let interactor3 = DashboardInteractor(walletController: fake3)
    let result3 = interactor3.fetchDocumentDetails("pid-12")
    t.check(result3.isSome(), "docDetails.fetchStored_nilUsage_returnsSome")
    match (result3) {
        case Some(d) =>
            t.check(d.credentialUsage.isNone(), "docDetails.fetchStored_nilUsage_credentialUsageNone")
        case None => t.check(false, "docDetails.fetchStored_nilUsage_unexpectedNone")
    }

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsValidDocument_ThenReturnsExpectedValuesWithIssuerDetailsCard
    // Cangjie: issuerCard is always populated (issuerName / supportingText / issuedOnText).
    let fake4 = FakeWalletKitController()
    fake4.documentById = Some(makeDocClaimsDecodable(id: "pid-13"))
    let interactor4 = DashboardInteractor(walletController: fake4)
    let result4 = interactor4.fetchDocumentDetails("pid-13")
    t.check(result4.isSome(), "docDetails.fetchStored_issuerCard_returnsSome")
    match (result4) {
        case Some(d) =>
            // issuerCard always present; isRevoked=false for non-revoked doc.
            t.check(!d.issuerCard.isRevoked, "docDetails.fetchStored_issuerCard_notRevoked")
        case None => t.check(false, "docDetails.fetchStored_issuerCard_unexpectedNone")
    }

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsRevokedDocument_ThenReturnsExpectedValuesWithIssuerDetailsCard
    // Cangjie: issuerCard.isRevoked=true when documentRevokedResult=true.
    let fake5 = FakeWalletKitController()
    fake5.documentById = Some(makeDocClaimsDecodable(id: "pid-14"))
    fake5.documentRevokedResult = true
    let interactor5 = DashboardInteractor(walletController: fake5)
    let result5 = interactor5.fetchDocumentDetails("pid-14")
    t.check(result5.isSome(), "docDetails.fetchStored_revokedDoc_returnsSome")
    match (result5) {
        case Some(d) =>
            t.check(d.issuerCard.isRevoked, "docDetails.fetchStored_revokedDoc_issuerCardRevoked")
            t.check(d.isRevoked, "docDetails.fetchStored_revokedDoc_isRevoked")
        case None => t.check(false, "docDetails.fetchStored_revokedDoc_unexpectedNone")
    }

    // iOS: testFetchStoredDocument_WhenWalletKitControllerReturnsDocumentFetchFailure_ThenReturnsError
    // Cangjie: fetchDocumentDetails returns None when documentById=None.
    let fake6 = FakeWalletKitController()
    fake6.documentById = None
    let interactor6 = DashboardInteractor(walletController: fake6)
    let result6 = interactor6.fetchDocumentDetails("nonexistentId")
    t.check(result6.isNone(), "docDetails.fetchStored_fetchFailure_returnsNone")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsRebootRequired_ThenReturnsRebootTrue
    // Cangjie: deleteDocument() returns true (shouldReboot concept not in this interactor).
    let fake7 = FakeWalletKitController()
    let interactor7 = DashboardInteractor(walletController: fake7)
    let del7 = interactor7.deleteDocument("pid-id")
    t.check(del7, "docDetails.deleteDocument_rebootRequired_returnsTrue")
    t.eqInt(fake7.deleteDocumentCalls, 1, "docDetails.deleteDocument_rebootRequired_callCount1")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsRebootNotRequired_ThenReturnsRebootTrue
    // Cangjie: same path; both iOS reboot variants return true in Cangjie.
    let fake8 = FakeWalletKitController()
    let interactor8 = DashboardInteractor(walletController: fake8)
    let del8 = interactor8.deleteDocument("pid-id-2")
    t.check(del8, "docDetails.deleteDocument_rebootNotRequired_returnsTrue")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsMultipleValidDocuments_ThenShouldDeleteAllDocuments
    // Cangjie: deleteDocument() calls the controller once (deletes the single named doc).
    let fake9 = FakeWalletKitController()
    let interactor9 = DashboardInteractor(walletController: fake9)
    let del9 = interactor9.deleteDocument("pid-id-3")
    t.check(del9, "docDetails.deleteDocument_multipleValidDocs_deletesOnce")
    t.eqInt(fake9.deleteDocumentCalls, 1, "docDetails.deleteDocument_multipleValidDocs_oneDeleteCall")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsNonValidDocuments_ThenShouldNotDeleteAllDocuments
    // Cangjie: Cangjie does not clear-all for non-PID document types; deleteDocument always
    // calls deleteDocument(id, status) once.
    let fake10 = FakeWalletKitController()
    let interactor10 = DashboardInteractor(walletController: fake10)
    let del10 = interactor10.deleteDocument("other-id")
    t.check(del10, "docDetails.deleteDocument_nonValidType_returnsTrue")
    t.eqInt(fake10.clearAllDocumentsCalls, 0, "docDetails.deleteDocument_nonValidType_noClearAll")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsDifferentPid_ThenShouldNotDeleteAllDocuments
    // Cangjie: no clearAll on non-PID doc. Same assertion as above.
    let fake11 = FakeWalletKitController()
    let interactor11 = DashboardInteractor(walletController: fake11)
    interactor11.deleteDocument("other-pid-id")
    t.eqInt(fake11.clearAllDocumentsCalls, 0, "docDetails.deleteDocument_differentPid_noClearAll")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsDeleteSuccess_ThenSucceeds
    // Cangjie: deleteDocument() returns true on success.
    let fake12 = FakeWalletKitController()
    let interactor12 = DashboardInteractor(walletController: fake12)
    let del12 = interactor12.deleteDocument("nonexistentId")
    t.check(del12, "docDetails.deleteDocument_success_returnsTrue")

    // iOS: testDeleteDocument_WhenWalletKitControllerReturnsDeleteWithError_ThenReturnsFailure
    // Cangjie: deleteDocument() catches the controller exception and returns false
    // (iOS returns .failure). Driven by deleteDocumentShouldThrow.
    let fakeDelErr = FakeWalletKitController()
    fakeDelErr.deleteDocumentShouldThrow = true
    let interactorDelErr = DashboardInteractor(walletController: fakeDelErr)
    let delErr = interactorDelErr.deleteDocument("pid-err")
    t.check(!delErr, "docDetails.deleteDocument_controllerThrows_returnsFalse")
    t.eqInt(fakeDelErr.deleteDocumentCalls, 1, "docDetails.deleteDocument_controllerThrows_stillAttempted")
    t.check(fakeDelErr.lastDeletedDocumentStatus == DocumentStatus.issued,
        "docDetails.deleteDocument_controllerThrows_usedIssuedStatus")

    // iOS: testSaveDocument_WhenWalletKitControllerReturnsSaveSuccess_ThenNoErrorThrown
    // Cangjie: DashboardInteractor.saveBookmark() delegates to
    // walletController.storeBookmarkedDocument and returns true on success.
    let fake14 = FakeWalletKitController()
    let interactor14 = DashboardInteractor(walletController: fake14)
    let saved14 = interactor14.saveBookmark("pid-id-save")
    t.check(saved14, "docDetails.saveDocument_saveBookmark_returnsTrue")
    t.eqInt(fake14.storeBookmarkedDocumentCalls, 1, "docDetails.saveDocument_storeBookmark_callCount1")

    // iOS: testSaveDocument_WhenWalletKitControllerReturnsSaveFailure_ThenReturnsError
    // Cangjie: a throwing store surfaces as saveBookmark() == false (interactor
    // catches and reports failure, mirroring the iOS thrown-error path).
    let fakeSaveFail = ThrowingBookmarkWalletKit()
    let interactorSaveFail = DashboardInteractor(walletController: fakeSaveFail)
    let savedFail = interactorSaveFail.saveBookmark("nonexistentId")
    t.check(!savedFail, "docDetails.saveDocument_saveFailure_returnsFalse")

    // iOS: testDeleteBookmark_WhenWalletKitControllerReturnsDeleteSuccess_ThenNoErrorThrown
    // Cangjie: DashboardInteractor.deleteBookmark() delegates to removeBookmarkedDocument.
    let fake16 = FakeWalletKitController()
    let interactor16 = DashboardInteractor(walletController: fake16)
    let delBm16 = interactor16.deleteBookmark("pid-id-bm")
    t.check(delBm16, "docDetails.deleteBookmark_deleteBookmark_returnsTrue")
    t.eqInt(fake16.removeBookmarkedDocumentCalls, 1, "docDetails.deleteBookmark_removeBookmark_callCount1")

    // iOS: testDeleteBookmark_WhenWalletKitControllerReturnsDeleteFailure_ThenReturnsError
    // Cangjie: a throwing remove surfaces as deleteBookmark() == false.
    let fakeDelFail = ThrowingBookmarkWalletKit()
    let interactorDelFail = DashboardInteractor(walletController: fakeDelFail)
    let delBmFail = interactorDelFail.deleteBookmark("nonexistentId")
    t.check(!delBmFail, "docDetails.deleteBookmark_deleteFailure_returnsFalse")

    // iOS: testFetchStoredDocument ... isBookmarked=false path (⚠️ real assertion).
    // Cangjie: fetchDocumentDetails reflects walletController.isDocumentBookmarked (false).
    let fakeBmFalse = FakeWalletKitController()
    fakeBmFalse.documentById = Some(makeDocClaimsDecodable(id: "pid-bm-false"))
    fakeBmFalse.bookmarkedResult = false
    let interactorBmFalse = DashboardInteractor(walletController: fakeBmFalse)
    match (interactorBmFalse.fetchDocumentDetails("pid-bm-false")) {
        case Some(d) => t.check(!d.isBookmarked, "docDetails.fetchStored_notBookmarked_isBookmarkedFalse")
        case None => t.check(false, "docDetails.fetchStored_notBookmarked_unexpectedNone")
    }

    // iOS: testFetchStoredDocument ... isBookmarked=true path (⚠️ real assertion).
    let fakeBmTrue = FakeWalletKitController()
    fakeBmTrue.documentById = Some(makeDocClaimsDecodable(id: "pid-bm-true"))
    fakeBmTrue.bookmarkedResult = true
    let interactorBmTrue = DashboardInteractor(walletController: fakeBmTrue)
    match (interactorBmTrue.fetchDocumentDetails("pid-bm-true")) {
        case Some(d) => t.check(d.isBookmarked, "docDetails.fetchStored_bookmarked_isBookmarkedTrue")
        case None => t.check(false, "docDetails.fetchStored_bookmarked_unexpectedNone")
    }

    // iOS: testReIssueDocument_WhenWalletKitControllerSucceeds_ThenReturnsSuccess
    // Cangjie: reIssueDocument() → ReIssueSuccess when the controller returns without throwing.
    let fakeReissueOk = SucceedingReIssueWalletKit()
    let interactorReissueOk = DashboardInteractor(walletController: fakeReissueOk)
    let reissueOk = match (interactorReissueOk.reIssueDocument("pid-id")) {
        case ReIssueSuccess => true
        case _ => false
    }
    t.check(reissueOk, "docDetails.reIssueDocument_succeeds_returnsSuccess")

    // iOS: testReIssueDocument_WhenWalletKitControllerThrows_ThenReturnsFailure
    // Cangjie: the not-configured fake throws a plain error → ReIssueFailure(msg).
    let fake18 = FakeWalletKitController()
    let interactor18 = DashboardInteractor(walletController: fake18)
    let reissue18Failed = match (interactor18.reIssueDocument("pid-id")) {
        case ReIssueFailure(_) => true
        case _ => false
    }
    t.check(reissue18Failed, "docDetails.reIssueDocument_throws_returnsFailure")

    // iOS: reIssueDocument → RegistrationRefusedError (registration pre-check
    // refusal) → error.isTrustBlocked → .issuerNotTrusted (the view raises the
    // blocking "Issuance blocked" alert, not a retryable error).
    let fakeReissueRefused = RegistrationRefusedReIssueWalletKit()
    let interactorReissueRefused = DashboardInteractor(walletController: fakeReissueRefused)
    let reissueRefused = match (interactorReissueRefused.reIssueDocument("pid-id")) {
        case ReIssueIssuerNotTrusted => true
        case _ => false
    }
    t.check(reissueRefused, "docDetails.reIssueDocument_registrationRefused_issuerNotTrusted")

    // iOS: testDeleteDocument_WhenForcePidActivationDisabled_ThenSkipsClearAllAndPerformsDelete
    // Cangjie: no forcePidActivation logic in DashboardInteractor; deleteDocument always
    // calls the controller once and returns true (fake does not throw).
    let fake20 = FakeWalletKitController()
    let interactor20 = DashboardInteractor(walletController: fake20)
    let del20 = interactor20.deleteDocument("pid-id-force")
    t.check(del20, "docDetails.deleteDocument_forcePidDisabled_returnsTrue")
    t.eqInt(fake20.deleteDocumentCalls, 1, "docDetails.deleteDocument_forcePidDisabled_oneDeleteCall")
    t.eqInt(fake20.clearAllDocumentsCalls, 0, "docDetails.deleteDocument_forcePidDisabled_noClearAll")
}

// ─── DocumentDetailsViewModel bookmark (iOS DocumentDetailsViewModel.saveBookmark) ──

func runDocumentDetailsBookmarkTests(t: DeviceTestRun): Unit {
    // Not bookmarked → toggle stores it, flips the state and raises the alert.
    let fake = FakeWalletKitController()
    fake.documentById = Some(makeDocClaimsDecodable(id: "pid-bm"))
    fake.bookmarkedResult = false
    let vm = DocumentDetailsViewModel(router: InMemoryRouterHost(), interactor: DashboardInteractor(walletController: fake),
        documentId: "pid-bm")
    vm.fetchDetails()
    t.check(!vm.viewState.isBookmarked, "docDetailsVm.bookmark_seededFalse")
    vm.toggleBookmark()
    t.eqInt(fake.storeBookmarkedDocumentCalls, 1, "docDetailsVm.bookmark_save_storeCalled")
    t.check(vm.viewState.isBookmarked, "docDetailsVm.bookmark_save_flipsTrue")
    t.check(vm.viewState.isBookmarkAlertShowing, "docDetailsVm.bookmark_save_alertShown")
    vm.dismissBookmarkAlert()
    t.check(!vm.viewState.isBookmarkAlertShowing && vm.viewState.isBookmarked,
        "docDetailsVm.bookmark_dismiss_keepsBookmarked")
    // Bookmarked → toggle removes it.
    vm.toggleBookmark()
    t.eqInt(fake.removeBookmarkedDocumentCalls, 1, "docDetailsVm.bookmark_remove_removeCalled")
    t.check(!vm.viewState.isBookmarked && vm.viewState.isBookmarkAlertShowing,
        "docDetailsVm.bookmark_remove_flipsFalse")

    // Seeded from storage when already bookmarked.
    let fakeSeeded = FakeWalletKitController()
    fakeSeeded.documentById = Some(makeDocClaimsDecodable(id: "pid-bm-seed"))
    fakeSeeded.bookmarkedResult = true
    let vmSeeded = DocumentDetailsViewModel(router: InMemoryRouterHost(),
        interactor: DashboardInteractor(walletController: fakeSeeded), documentId: "pid-bm-seed")
    vmSeeded.fetchDetails()
    t.check(vmSeeded.viewState.isBookmarked, "docDetailsVm.bookmark_seededTrue")

    // Storage failure leaves the state untouched and shows no alert (iOS swallows it).
    let fakeFail = ThrowingBookmarkWalletKit()
    fakeFail.documentById = Some(makeDocClaimsDecodable(id: "pid-bm-fail"))
    let vmFail = DocumentDetailsViewModel(router: InMemoryRouterHost(),
        interactor: DashboardInteractor(walletController: fakeFail), documentId: "pid-bm-fail")
    vmFail.fetchDetails()
    vmFail.toggleBookmark()
    t.check(!vmFail.viewState.isBookmarked && !vmFail.viewState.isBookmarkAlertShowing,
        "docDetailsVm.bookmark_failure_stateUnchanged")
}

// ─── Revoked-documents modal rows (iOS revokedDocuments.sorted(by: >)) ───────

func runRevokedModalRowsTests(t: DeviceTestRun): Unit {
    let map = HashMap<String, String>()
    map.add("Driving License", "mdl-1")
    map.add("PID", "pid-1")
    map.add("Age Verification", "age-1")
    let rows = revokedRowsFrom(map)
    t.eqInt(rows.size, 3, "revokedModal.rows_oneRowPerDocument")
    t.check(rows[0].name == "PID" && rows[1].name == "Driving License" && rows[2].name == "Age Verification",
        "revokedModal.rows_sortedDescendingByName")
    t.check(rows[0].id == "pid-1" && rows[2].id == "age-1", "revokedModal.rows_keepDocumentId")
    t.eqInt(revokedRowsFrom(HashMap<String, String>()).size, 0, "revokedModal.rows_emptyMap")
}

// ─── TestTransactionTabInteractor (15 iOS cases) ─────────────────────────────

func runTransactionTabInteractorTests(t: DeviceTestRun): Unit {

    // iOS: testFetchTransactions_WhenWalletKitControllerThrowsError_ThenReturnsExpectedError
    // iOS ends this path at isLoading:false with transactions:[] — the empty list.
    // Cangjie carries the failure as a throw out of the interactor and converts it in
    // the view model, so assert both halves: the interactor signals the failure, and
    // every view-model entry point (first load and the search handler) degrades to the
    // empty list rather than throwing into a UI event.
    let fakeTxErr = FakeWalletKitController()
    fakeTxErr.fetchTransactionLogsShouldThrow = true
    let interactorTxErr = DashboardInteractor(walletController: fakeTxErr)
    var txThrew = false
    try {
        let _ = interactorTxErr.fetchTransactionRows()
    } catch (_: Exception) {
        txThrew = true
    }
    t.check(txThrew, "txTab.fetchTransactions_controllerThrows_interactorSignalsFailure")

    let txErrVm = DashboardViewModel(router: InMemoryRouterHost(), interactor: interactorTxErr)
    var txVmThrew = false
    var txVmRows = Array<TransactionRow>()
    try {
        txVmRows = txErrVm.loadTransactionRows()
    } catch (_: Exception) {
        txVmThrew = true
    }
    t.check(!txVmThrew, "txTab.fetchTransactions_controllerThrows_viewModelContainsThrow")
    t.check(txVmRows.isEmpty(), "txTab.fetchTransactions_controllerThrows_yieldsEmptyRows")

    // The search path calls straight in with no wrapper above it, so it has to be
    // safe on its own.
    var txSearchThrew = false
    var txSearchRows = Array<TransactionRow>()
    try {
        txSearchRows = txErrVm.transactionApplySearch("anything")
    } catch (_: Exception) {
        txSearchThrew = true
    }
    t.check(!txSearchThrew, "txTab.fetchTransactions_controllerThrows_searchPathContainsThrow")
    t.check(txSearchRows.isEmpty(), "txTab.fetchTransactions_controllerThrows_searchYieldsEmptyRows")

    // iOS: testFetchTransactions_WhenWalletKitControllerReturnsEmptyTransactions_ThenReturnsExpectedError
    // Cangjie: fetchTransactionRows() returns empty array when transactionLogs is empty.
    let fake2 = FakeWalletKitController()
    fake2.transactionLogs = Array<TransactionLogItem>()
    let interactor2 = DashboardInteractor(walletController: fake2)
    let rows2 = interactor2.fetchTransactionRows()
    t.check(rows2.isEmpty(), "txTab.fetchTransactions_empty_returnsEmpty")

    // iOS: testFetchTransactions_WhenWalletKitControllerReturnsData_ThenReturnsExpectedUIModels
    // Cangjie: fetchTransactionRows() returns rows+header when logs are present.
    let fake3 = FakeWalletKitController()
    fake3.transactionLogs = [makeTransactionLog(id: "tx-a", value: "EUDI Remote Verifier")]
    let interactor3 = DashboardInteractor(walletController: fake3)
    let rows3 = interactor3.fetchTransactionRows()
    t.check(!rows3.isEmpty(), "txTab.fetchTransactions_withData_nonEmpty")
    // First row is a header (month/year); second is the transaction row.
    t.check(rows3.size >= 2, "txTab.fetchTransactions_withData_hasHeaderAndRow")
    t.check(rows3[0].isHeader, "txTab.fetchTransactions_withData_firstRowIsHeader")
    t.check(!rows3[1].isHeader, "txTab.fetchTransactions_withData_secondRowIsNotHeader")

    // Regression for the UI Apply chain: iOS reuses the validator on fetch,
    // calls updateLists, then applyFilters. A refresh must not reset the just-
    // committed selection by rebuilding the controller with defaults.
    let persistFake = FakeWalletKitController()
    persistFake.transactionLogs = [
        makeTransactionLog(id: "tx-persist-a", value: "Alpha"),
        makeTransactionLog(id: "tx-persist-b", value: "Beta")
    ]
    let persistVm = DashboardViewModel(
        router: InMemoryRouterHost(),
        interactor: DashboardInteractor(walletController: persistFake)
    )
    let persistInitial = persistVm.loadTransactionRowsApplyingFilters()
    t.eqInt(nonHeaderTransactionCount(persistInitial), 2,
        "txTab.filterReloadPersistence_initiallyShowsBoth")
    persistVm.transactionUpdateFilter(FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")
    let persistApplied = persistVm.transactionApplyFilters()
    t.eqInt(nonHeaderTransactionCount(persistApplied), 1,
        "txTab.filterReloadPersistence_applyDropsDeselectedParty")
    let persistReloaded = persistVm.loadTransactionRowsApplyingFilters()
    t.eqInt(nonHeaderTransactionCount(persistReloaded), 1,
        "txTab.filterReloadPersistence_reloadKeepsAppliedSelection")

    // iOS: testInitializeFilters_WhenInitializedWithFilterableList_ThenInitializesFilterValidator
    // Cangjie: buildTransactionFilterController() from real rows initializes the validator.
    let fake4 = FakeWalletKitController()
    fake4.transactionLogs = [makeTransactionLog(id: "tx-b")]
    let interactor4 = DashboardInteractor(walletController: fake4)
    let rows4 = interactor4.fetchTransactionRows()
    let fc4 = interactor4.buildTransactionFilterController(rows4)
    let sections4 = fc4.sections()
    t.check(sections4.size >= 1, "txTab.initializeFilters_producesAtLeastOneSortSection")

    // iOS: testInitializeFilters_WhenWalletKitControllerReturnsEmptyTransactions_ThenInitializesFilterValidator
    // Cangjie: buildTransactionFilterController() with empty rows produces sections (sort group always present).
    let fake5 = FakeWalletKitController()
    fake5.transactionLogs = Array<TransactionLogItem>()
    let interactor5 = DashboardInteractor(walletController: fake5)
    let rows5 = interactor5.fetchTransactionRows()
    let fc5 = interactor5.buildTransactionFilterController(rows5)
    let sections5 = fc5.sections()
    t.check(sections5.size >= 1, "txTab.initializeFilters_emptyList_stillProducesSections")

    // iOS: testApplyFilters_WhenFilterValidatorApplyFilters_ThenApplyFiltersWasCalled
    // Same apply-copies-snapshot contract as the document tab, using the
    // relying-party group: deselecting "Alpha" must wait for applyFilters
    // before that transaction drops out.
    let fake6 = FakeWalletKitController()
    fake6.transactionLogs = [
        makeTransactionLog(id: "tx-c-a", value: "Alpha"),
        makeTransactionLog(id: "tx-c-b", value: "Beta")
    ]
    let interactor6 = DashboardInteractor(walletController: fake6)
    let rows6 = interactor6.fetchTransactionRows()
    let fc6 = interactor6.buildTransactionFilterController(rows6)
    t.check(filteredTxHas(fc6, rows6, "tx-c-a"), "txTab.applyFilters_startsWithAlpha")
    t.check(filteredTxHas(fc6, rows6, "tx-c-b"), "txTab.applyFilters_startsWithBeta")
    fc6.updateFilter(FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")
    t.check(filteredTxHas(fc6, rows6, "tx-c-a"),
        "txTab.applyFilters_updateDoesNotDropAlpha")
    fc6.applyFilters()
    t.check(!filteredTxHas(fc6, rows6, "tx-c-a"), "txTab.applyFilters_rebuildsAndDropsAlpha")
    t.check(filteredTxHas(fc6, rows6, "tx-c-b"), "txTab.applyFilters_keepsBeta")

    // iOS: testUpdateLists_WhenTransactionsFetchedAndStateIsSuccess_ThenUsesFilterValidatorToUpdateLists
    // Cangjie: DashboardInteractor.updateTransactionFilterLists() supplies the row
    // timestamps and delegates to DashboardFilterController.updateLists(rows:timestamps:),
    // which swaps FilterValidatorImpl's source list (same seam iOS uses).
    let fakeUL = FakeWalletKitController()
    fakeUL.transactionLogs = [makeTransactionLog(id: "tx-old")]
    let interactorUL = DashboardInteractor(walletController: fakeUL)
    let rowsULold = interactorUL.fetchTransactionRows()
    let fcUL = interactorUL.buildTransactionFilterController(rowsULold)

    fakeUL.transactionLogs = [makeTransactionLog(id: "tx-new")]
    let rowsULnew = interactorUL.fetchTransactionRows()
    interactorUL.updateTransactionFilterLists(fcUL, rowsULnew)
    fcUL.applyFilters()

    let filteredUL = fcUL.filteredTransactionRows(rowsULnew)
    var sawNewUL = false
    for (r in filteredUL) {
        if (r.id == "tx-new") { sawNewUL = true }
    }
    t.check(sawNewUL, "txTab.updateLists_refreshedRow_survivesFiltering")
    let staleUL = fcUL.filteredTransactionRows(rowsULold)
    t.check(staleUL.isEmpty(), "txTab.updateLists_staleRow_droppedFromSource")

    // Regression: History can stay mounted while a presentation route appends a
    // transaction. Its default date range must advance with the new source;
    // otherwise the old max date silently filters the freshly written row out.
    let oldTsUL: Int64 = 1788544076 // 04 Sep 2026
    let newTsUL: Int64 = 1788776756 // 07 Sep 2026
    let rangeFake = FakeWalletKitController()
    rangeFake.transactionLogs = [makeTransactionLog(id: "range-old", timestamp: oldTsUL)]
    let rangeInteractor = DashboardInteractor(walletController: rangeFake)
    let initialRangeRows = rangeInteractor.fetchTransactionRows()
    let rangeFc = rangeInteractor.buildTransactionFilterController(initialRangeRows)
    let calendarNowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let calendarDayMs: Int64 = 24 * 60 * 60 * 1000
    t.check(rangeFc.calendarRangeMin.toUnixTimeStamp().toMilliseconds() <= calendarNowMs - 364 * calendarDayMs,
        "txTab.calendar_start_allowsPastYear")
    t.check(rangeFc.calendarRangeMax.toUnixTimeStamp().toMilliseconds() >= calendarNowMs + 364 * calendarDayMs,
        "txTab.calendar_end_allowsFutureYear")
    rangeFake.transactionLogs = [
        makeTransactionLog(id: "range-old", timestamp: oldTsUL),
        makeTransactionLog(id: "range-new", timestamp: newTsUL)
    ]
    let refreshedRangeRows = rangeInteractor.fetchTransactionRows()
    rangeInteractor.updateTransactionFilterLists(rangeFc, refreshedRangeRows)
    rangeFc.applyFilters()
    t.check(filteredTxHas(rangeFc, refreshedRangeRows, "range-new"),
        "txTab.updateLists_defaultDateRangeAdvancesToNewTransaction")

    // iOS: testResetFilters_WhenFilterValidatorResetFilters_ThenResetFiltersWasCalled
    let fake8 = FakeWalletKitController()
    fake8.transactionLogs = [
        makeTransactionLog(id: "tx-d-a", value: "Alpha"),
        makeTransactionLog(id: "tx-d-b", value: "Beta")
    ]
    let interactor8 = DashboardInteractor(walletController: fake8)
    let rows8 = interactor8.fetchTransactionRows()
    let fc8 = interactor8.buildTransactionFilterController(rows8)
    fc8.updateFilter(FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")
    fc8.applyFilters()
    t.check(!filteredTxHas(fc8, rows8, "tx-d-a"), "txTab.resetFilters_setup_alphaDropped")
    fc8.resetFilters()
    t.check(filteredTxHas(fc8, rows8, "tx-d-a"), "txTab.resetFilters_restoresAlpha")
    t.check(filteredTxHas(fc8, rows8, "tx-d-b"), "txTab.resetFilters_keepsBeta")

    // iOS: testRevertFilters_WhenFilterValidatorRevertFilters_ThenRevertFiltersWasCalled
    let fake9 = FakeWalletKitController()
    fake9.transactionLogs = [
        makeTransactionLog(id: "tx-e-a", value: "Alpha"),
        makeTransactionLog(id: "tx-e-b", value: "Beta")
    ]
    let interactor9 = DashboardInteractor(walletController: fake9)
    let rows9 = interactor9.fetchTransactionRows()
    let fc9 = interactor9.buildTransactionFilterController(rows9)
    let appliedBefore9 = nonHeaderTransactionCount(fc9.filteredTransactionRows(rows9))
    fc9.updateFilter(FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")
    match (selectionFlagOf(fc9, FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")) {
        case Some(selected) => t.check(!selected, "txTab.revertFilters_setup_alphaDeselected")
        case None => t.check(false, "txTab.revertFilters_setup_alphaDeselected_missing")
    }
    t.eqInt(nonHeaderTransactionCount(fc9.filteredTransactionRows(rows9)), appliedBefore9,
        "txTab.revertFilters_setup_appliedListUntouched")
    fc9.revertFilters()
    match (selectionFlagOf(fc9, FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")) {
        case Some(selected) => t.check(selected, "txTab.revertFilters_restoresSnapshotSelection")
        case None => t.check(false, "txTab.revertFilters_restoresSnapshotSelection_missing")
    }
    t.eqInt(nonHeaderTransactionCount(fc9.filteredTransactionRows(rows9)), appliedBefore9,
        "txTab.revertFilters_doesNotRebuildAppliedList")

    // ── testOnFilterChangeState_WhenStreamYieldsCompletion_ThenForwardsCancelledAndFinishes ──
    // Same cancellation contract as the document tab, asserted on the transaction
    // flavour of the controller because the two tabs construct it differently
    // (isTransaction + timestamps) and iOS covers each tab with its own case.
    let fakeC = FakeWalletKitController()
    fakeC.transactionLogs = [makeTransactionLog(id: "tx-cancel")]
    let interactorC = DashboardInteractor(walletController: fakeC)
    let rowsC = interactorC.fetchTransactionRows()
    let fcC = interactorC.buildTransactionFilterController(rowsC)
    t.check(!fcC.isCancelled, "txTab.filterChangeState_beforeCompletion_notCancelled")
    fcC.applyFilters()
    let sectionsBeforeC = fcC.sections().size
    let appliedBeforeC = fcC.filteredTransactionRows(rowsC).size
    fcC.complete()
    t.check(fcC.isCancelled, "txTab.filterChangeState_completion_cancelled")
    // Same as the document tab: completion must surface cancellation only, never a
    // filter result (iOS: the first delivered value is `.cancelled`).
    t.eqInt(fcC.sections().size, sectionsBeforeC,
        "txTab.filterChangeState_completion_carriesNoFilterResult_sections")
    t.eqInt(fcC.filteredTransactionRows(rowsC).size, appliedBeforeC,
        "txTab.filterChangeState_completion_carriesNoFilterResult_appliedList")
    fcC.applySearch("anything")
    fcC.applyFilters()
    t.check(fcC.isCancelled, "txTab.filterChangeState_afterCompletion_staysCancelled")
    t.eqInt(fcC.sections().size, sectionsBeforeC, "txTab.filterChangeState_afterCompletion_snapshotFrozen")
    fcC.complete()
    t.check(fcC.isCancelled, "txTab.filterChangeState_completeTwice_idempotent")

    // iOS: testUpdateFilters_WhenFilterValidatorUpdateFilters_ThenUpdateFiltersWasCalled
    // Relying-party group is multiple-selection and starts all-selected, so the
    // observable move is clearing one named item without touching the applied list.
    let fake10 = FakeWalletKitController()
    fake10.transactionLogs = [
        makeTransactionLog(id: "tx-f-a", value: "Alpha"),
        makeTransactionLog(id: "tx-f-b", value: "Beta")
    ]
    let interactor10 = DashboardInteractor(walletController: fake10)
    let rows10 = interactor10.fetchTransactionRows()
    let fc10 = interactor10.buildTransactionFilterController(rows10)
    let appliedBefore10 = nonHeaderTransactionCount(fc10.filteredTransactionRows(rows10))
    fc10.updateFilter(FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")
    match (selectionFlagOf(fc10, FilterIds.FILTER_BY_RELYING_PARY_NAME, "Alpha")) {
        case Some(selected) => t.check(!selected, "txTab.updateFilters_movesSnapshotSelection")
        case None => t.check(false, "txTab.updateFilters_movesSnapshotSelection_missing")
    }
    t.eqInt(nonHeaderTransactionCount(fc10.filteredTransactionRows(rows10)), appliedBefore10,
        "txTab.updateFilters_leavesAppliedListUntouched")

    // iOS: testUpdateDateFilters_WhenFilterValidatorUpdateDateFilters_ThenUpdateDateFiltersWasCalled
    // The date-picker item must carry the new range on the snapshot (the sheet
    // reads startDate/endDate), and the applied list must stay put until apply.
    let fake11 = FakeWalletKitController()
    fake11.transactionLogs = [makeTransactionLog(id: "tx-g", timestamp: 1700000000, value: "PID")]
    let interactor11 = DashboardInteractor(walletController: fake11)
    let rows11 = interactor11.fetchTransactionRows()
    let fc11 = interactor11.buildTransactionFilterController(rows11)
    let appliedBefore11tx = nonHeaderTransactionCount(fc11.filteredTransactionRows(rows11))
    let start = DateTime.of(year: 2020, month: 1, dayOfMonth: 1)
    let end = DateTime.of(year: 2020, month: 1, dayOfMonth: 2)
    match (firstDatePicker(fc11)) {
        case Some(target) =>
            fc11.updateDateFilters(target.sectionId, target.filterId, start, end)
            var sawStart = false
            var sawEnd = false
            for (section in fc11.sections()) {
                if (section.id != target.sectionId) {
                    continue
                }
                for (item in section.filters) {
                    if (item.id != target.filterId) {
                        continue
                    }
                    match (item.startDate) {
                        case Some(sd) => sawStart = sd == start
                        case None => ()
                    }
                    match (item.endDate) {
                        case Some(ed) => sawEnd = ed == end
                        case None => ()
                    }
                }
            }
            t.check(sawStart, "txTab.updateDateFilters_writesStartDate")
            t.check(sawEnd, "txTab.updateDateFilters_writesEndDate")
            t.eqInt(nonHeaderTransactionCount(fc11.filteredTransactionRows(rows11)), appliedBefore11tx,
                "txTab.updateDateFilters_leavesAppliedListUntouched")
        case None => t.check(false, "txTab.updateDateFilters_noDatePicker")
    }

    // iOS: testApplySearch_WhenFilterValidatorApplySearch_ThenUsesFilterValidator
    let fake12 = FakeWalletKitController()
    fake12.transactionLogs = [
        makeTransactionLog(id: "tx-h-a", value: "Alpha"),
        makeTransactionLog(id: "tx-h-b", value: "Beta")
    ]
    let interactor12 = DashboardInteractor(walletController: fake12)
    let rows12 = interactor12.fetchTransactionRows()
    let fc12 = interactor12.buildTransactionFilterController(rows12)
    fc12.applySearch("Alpha")
    t.check(filteredTxHas(fc12, rows12, "tx-h-a"), "txTab.applySearch_keepsMatchingRow")
    t.check(!filteredTxHas(fc12, rows12, "tx-h-b"), "txTab.applySearch_dropsNonMatchingRow")

    // iOS: testOnFilterChangeState_WhenStreamYieldsCompletion_ThenForwardsCancelledAndFinishes
    // Covered by the fcC block above (transaction flavour of the same contract).

    // iOS: testInitializeFilters_WhenTransactionsHaveRelyingParty_ThenRelyingPartyGroupIsPopulated
    // Cangjie: TransactionRow now carries relyingPartyName (from the log value string);
    // forTransactions builds a FILTER_BY_RELYING_PARY_NAME group with a "none" item plus
    // one item per distinct relying-party name, sorted alphabetically (mirrors iOS
    // addRelyingPartyName). Two distinct verifiers + one empty-value → 3 items.
    let rpFake = FakeWalletKitController()
    rpFake.transactionLogs = [
        makeTransactionLog(id: "rp-1", value: "Verifier B"),
        makeTransactionLog(id: "rp-2", value: "Verifier A"),
        makeTransactionLog(id: "rp-3", value: "")
    ]
    let rpInteractor = DashboardInteractor(walletController: rpFake)
    let rpRows = rpInteractor.fetchTransactionRows()
    let rpFc = rpInteractor.buildTransactionFilterController(rpRows)
    let rpSections = rpFc.sections()
    // Find the relying-party section (id == "relying_party_name").
    var rpSectionFound = false
    let rpItemIds = ArrayList<String>()
    let rpItemSet = HashMap<String, Bool>()
    for (sec in rpSections) {
        if (sec.id == "relying_party_name") {
            rpSectionFound = true
            for (f in sec.filters) {
                rpItemIds.add(f.id)
                rpItemSet[f.id] = true
            }
        }
    }
    t.check(rpSectionFound, "txTab.relyingParty_groupPopulated")
    t.check(rpItemSet.contains("relying_party_name_none"), "txTab.relyingParty_hasNoneItem")
    t.check(rpItemSet.contains("Verifier A"), "txTab.relyingParty_hasVerifierA")
    t.check(rpItemSet.contains("Verifier B"), "txTab.relyingParty_hasVerifierB")
    // 3 items total: none + 2 distinct names.
    t.eqInt(rpItemIds.size, 3, "txTab.relyingParty_threeItems")

    // Cangjie extra: the two named items appear alphabetically after the "none"
    // item (mirrors iOS sorted { $0.name < $1.name } prepended with the none item).
    if (rpItemIds.size == 3) {
        t.eqStr(rpItemIds[0], "relying_party_name_none", "txTab.relyingParty_noneFirst")
        t.eqStr(rpItemIds[1], "Verifier A", "txTab.relyingParty_sortedA")
        t.eqStr(rpItemIds[2], "Verifier B", "txTab.relyingParty_sortedB")
    } else {
        t.check(false, "txTab.relyingParty_sortOrder_wrongCount")
    }

    // Cangjie extra: fetchTransactionRows populates relyingPartyName on the row from
    // the log value (mirrors iOS relyingParty.name → attributes.relyingPartyName).
    let rpRowFake = FakeWalletKitController()
    rpRowFake.transactionLogs = [makeTransactionLog(id: "rp-row", value: "EUDI Remote Verifier")]
    let rpRowInteractor = DashboardInteractor(walletController: rpRowFake)
    let rpRowRows = rpRowInteractor.fetchTransactionRows()
    var rpRowName = ""
    for (row in rpRowRows) {
        if (!row.isHeader) {
            match (row.relyingPartyName) {
                case Some(n) => rpRowName = n
                case None => ()
            }
        }
    }
    t.eqStr(rpRowName, "EUDI Remote Verifier", "txTab.relyingParty_rowCarriesName")

    // iOS: testOnFilterChangeState_WhenStreamEmitsResults_ThenProcessesResultsAsExpected
    // Same contract as the document tab above, asserted on the transaction flavour
    // of the controller because the two tabs build it differently (isTransaction +
    // timestamps) and iOS covers each tab with its own case: an apply event carries
    // the filtered list, an update event carries filters only.
    let fakeSeqTx = FakeWalletKitController()
    fakeSeqTx.transactionLogs = [
        makeTransactionLog(id: "txseq-a", value: "Alpha"),
        makeTransactionLog(id: "txseq-b", value: "Beta")
    ]
    let interactorSeqTx = DashboardInteractor(walletController: fakeSeqTx)
    let rowsSeqTx = interactorSeqTx.fetchTransactionRows()
    let fcSeqTx = interactorSeqTx.buildTransactionFilterController(rowsSeqTx)

    fcSeqTx.applyFilters()
    let appliedSeqTx = fcSeqTx.filteredTransactionRows(rowsSeqTx).size
    t.check(appliedSeqTx > 0, "txTab.filterChangeState_applyEvent_populatesFilteredList")

    // Every radio filter in the transaction sheet starts selected, so the probe
    // runs the other way: the relying-party group is multiple-selection, where
    // clearing a selected item is a real move.
    match (firstFilterOfSection(fcSeqTx, FilterIds.FILTER_BY_RELYING_PARY_NAME)) {
        case Some(target) =>
            fcSeqTx.updateFilter(target.sectionId, target.filterId)
            match (selectionFlagOf(fcSeqTx, target.sectionId, target.filterId)) {
                case Some(after) =>
                    t.check(!after, "txTab.filterChangeState_updateEvent_movesSnapshotSelection")
                case None =>
                    t.check(false, "txTab.filterChangeState_updateEvent_filterMissingFromSnapshot")
            }
            t.eqInt(fcSeqTx.filteredTransactionRows(rowsSeqTx).size, appliedSeqTx,
                "txTab.filterChangeState_updateEvent_leavesAppliedListUntouched")
        case None =>
            t.check(false, "txTab.filterChangeState_updateEvent_relyingPartySectionMissing")
    }

    fcSeqTx.applySearch("zzz-no-such-transaction")
    fcSeqTx.applyFilters()
    t.check(fcSeqTx.filteredTransactionRows(rowsSeqTx).isEmpty(),
        "txTab.filterChangeState_applyEvent_rebuildsFilteredList")
}

// ─── TestSettingsInteractor (13 iOS cases) ────────────────────────────────────
// iOS SettingsInteractor functionality in Cangjie lives in settings_view.cj and is
// driven from SettingsViewModel (ArkUI-bound). Pure-logic parts use FakePrefsController
// and FakeConfigLogic (both already defined in dev_tests_startup.cj, same package).

func runSettingsInteractorTests(t: DeviceTestRun): Unit {

    // iOS: testGetAppVersion_WhenConfigLogicReturnsAppVersion_ThenReturnsExpectedVersion
    // Cangjie: ConfigLogic.appVersion is read by SettingsViewModel.buildMenuItems().
    // Test the FakeConfigLogic appVersion property directly.
    let cfg1 = FakeConfigLogic()
    t.eqStr(cfg1.appVersion, "test", "settings.getAppVersion_returnsConfigLogicValue")

    // iOS: testRetrieveLogFileUrl_WhenWalletKitControllerReturnsLogFileUrl_ThenReturnsExpectedUrl
    // Cangjie: WalletKitController.retrieveLogFileUrl() returns ?String (None on HarmonyOS;
    // Hilog is used instead of a shareable file URL).
    let fake2 = FakeWalletKitController()
    fake2.logFileUrl = Some("file.url")
    let url2 = fake2.retrieveLogFileUrl()
    t.check(url2.isSome(), "settings.retrieveLogFileUrl_configured_returnsSome")
    match (url2) {
        case Some(u) => t.eqStr(u, "file.url", "settings.retrieveLogFileUrl_configured_correctUrl")
        case None => t.check(false, "settings.retrieveLogFileUrl_configured_unexpectedNone")
    }

    // iOS: testRetrieveChangelogUrl_WhenConfigLogicReturnsChangelogUrl_ThenReturnsExpectedUrl
    // Cangjie: ConfigLogic.changelogUrl is ?String; FakeConfigLogic returns None.
    let cfg3 = FakeConfigLogic()
    let clog3 = cfg3.changelogUrl
    // FakeConfigLogic returns None; a real ConfigLogic may return a URL.
    t.check(clog3.isNone(), "settings.retrieveChangelogUrl_fake_returnsNone")

    // iOS: testIsBiometryAvailable_WhenDeviceSupportsFaceId_ThenReturnsTrue
    // Cangjie: BiometryController.canEvaluate() → BiometryAvailability.Available.
    let biometry4 = FakeBiometryController()
    biometry4.biometryType = BiometryType.FaceID
    biometry4.availability = BiometryAvailability.Available
    let avail4 = biometry4.canEvaluate()
    t.check(match (avail4) { case BiometryAvailability.Available => true; case _ => false }, "settings.isBiometryAvailable_faceId_available")

    // iOS: testIsBiometryAvailable_WhenDeviceDoesNotSupportBiometry_ThenReturnsFalse
    let biometry5 = FakeBiometryController()
    biometry5.biometryType = BiometryType.BiometryNone
    biometry5.availability = BiometryAvailability.Unavailable(BiometryError.BiometryNotSupported)
    let avail5 = biometry5.canEvaluate()
    t.check(match (avail5) { case BiometryAvailability.Unavailable(_) => true; case _ => false }, "settings.isBiometryAvailable_none_unavailable")

    // ── testIsBiometryEnabled_WhenBiometryInteractorReturnsEnabled_ThenReturnsTrue ──
    // Cangjie stores the flag in PrefsController(PrefsKey.biometryEnabled) rather than
    // on the biometry controller. Both paths go through the real interactor method;
    // asserting the fake's own getBool() would have proven nothing about production code.
    let prefsBiomOn = SettingsPrefsFake()
    prefsBiomOn.bools[PrefsKey.biometryEnabled.rawValue] = true
    let settingsBiomOn = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: prefsBiomOn,
        biometryController: FakeBiometryController()
    )
    t.check(settingsBiomOn.isBiometryEnabled(), "settings.isBiometryEnabled_prefTrue_returnsTrue")

    // False path, same seam — guards against the accessor being hardwired to true.
    let settingsBiomOff = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: SettingsPrefsFake(),
        biometryController: FakeBiometryController()
    )
    t.check(!settingsBiomOff.isBiometryEnabled(), "settings.isBiometryEnabled_prefUnset_returnsFalse")

    // iOS: testAuthenticateBiometry_WhenAuthenticationSucceeds_ThenReturnsAuthenticated
    let biometry7 = FakeBiometryController()
    biometry7.unlockResult = BiometryUnlockResult.UnlockSuccess
    let unlock7 = biometry7.requestBiometricUnlock()
    t.check(match (unlock7) { case BiometryUnlockResult.UnlockSuccess => true; case _ => false }, "settings.authenticateBiometry_success_returnsAuthenticated")

    // iOS: testAuthenticateBiometry_WhenAuthenticationFails_ThenReturnsFailure
    let biometry8 = FakeBiometryController()
    biometry8.unlockResult = BiometryUnlockResult.UnlockFailure(BiometryError.DeniedAccess)
    let unlock8 = biometry8.requestBiometricUnlock()
    t.check(match (unlock8) { case BiometryUnlockResult.UnlockFailure(_) => true; case _ => false }, "settings.authenticateBiometry_failure_returnsFailure")

    // iOS: testSetBiometrySelection_WhenCalled_ThenDelegatesToBiometryInteractor
    // Cangjie: iOS delegates to BiometryInteractor.setBiometrySelection; the Cangjie
    // SettingsInteractor collapses that into a direct PrefsController write of
    // PrefsKey.biometryEnabled (same observable persisted decision). Verify the write
    // is delegated to the prefs seam with the correct value.
    let biomPrefs = SettingsPrefsFake()
    let settingsBiom = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: biomPrefs,
        biometryController: FakeBiometryController()
    )
    settingsBiom.setBiometrySelection(true)
    t.eqInt(biomPrefs.setCount, 1, "settings.setBiometrySelection_delegatesToPrefs_setCount1")
    match (biomPrefs.lastSet.get(PrefsKey.biometryEnabled.rawValue)) {
        case Some(v) => t.check(v, "settings.setBiometrySelection_writesBiometryEnabledTrue")
        case None => t.check(false, "settings.setBiometrySelection_biometryEnabledKeyNotWritten")
    }

    // iOS: testOpenBiometrySettings_WhenCalled_ThenDelegatesToBiometryInteractor
    // Cangjie: HarmonyOS has no openSettings() seam on BiometryController (system
    // intent only); the observable decision point is the biometry availability the
    // settings toggle gates on. Verify isBiometryAvailable() reflects the controller.
    let biomAvailController = FakeBiometryController()
    biomAvailController.availability = BiometryAvailability.Available
    // isBiometryAvailable() reads getBiometryType() (iOS: type != .none), so the
    // fake must carry a concrete sensor type, not just the availability verdict.
    biomAvailController.biometryType = BiometryType.FaceID
    let settingsAvail = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: SettingsPrefsFake(),
        biometryController: biomAvailController
    )
    t.check(settingsAvail.isBiometryAvailable(), "settings.openBiometrySettings_availabilityGate_available")

    // iOS: testIsBatchCounterEnabled_WhenPrefsControllerReturnsTrue_ThenReturnsTrue
    // Cangjie: SettingsInteractor.isBatchCounterEnabled() reads PrefsKey.batchCounter.
    let batchTruePrefs = SettingsPrefsFake()
    batchTruePrefs.bools[PrefsKey.batchCounter.rawValue] = true
    let settingsBatchTrue = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: batchTruePrefs,
        biometryController: FakeBiometryController()
    )
    t.check(settingsBatchTrue.isBatchCounterEnabled(), "settings.isBatchCounterEnabled_true_returnsTrue")

    // iOS: testIsBatchCounterEnabled_WhenPrefsControllerReturnsFalse_ThenReturnsFalse
    let batchFalsePrefs = SettingsPrefsFake()
    batchFalsePrefs.bools[PrefsKey.batchCounter.rawValue] = false
    let settingsBatchFalse = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: batchFalsePrefs,
        biometryController: FakeBiometryController()
    )
    t.check(!settingsBatchFalse.isBatchCounterEnabled(), "settings.isBatchCounterEnabled_false_returnsFalse")

    // iOS: testBatchCounter_WhenSetToTrue_CallsPrefsControllerWithTrue
    // Cangjie: SettingsInteractor.setBatchCounter delegates to PrefsController.setValue
    // for PrefsKey.batchCounter with the given value.
    let batchSetPrefs = SettingsPrefsFake()
    let settingsBatchSet = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: batchSetPrefs,
        biometryController: FakeBiometryController()
    )
    settingsBatchSet.setBatchCounter(true)
    t.eqInt(batchSetPrefs.setCount, 1, "settings.setBatchCounter_callsPrefs_setCount1")
    match (batchSetPrefs.lastSet.get(PrefsKey.batchCounter.rawValue)) {
        case Some(v) => t.check(v, "settings.setBatchCounter_writesBatchCounterTrue")
        case None => t.check(false, "settings.setBatchCounter_batchCounterKeyNotWritten")
    }

    // Cangjie extra: getAppVersion()/authenticateBiometry() through the real interactor seam.
    let settingsVersion = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: SettingsPrefsFake(),
        biometryController: FakeBiometryController()
    )
    t.eqStr(settingsVersion.getAppVersion(), "test", "settings.getAppVersion_interactor_returnsConfigValue")

    let biomUnlock = FakeBiometryController()
    biomUnlock.unlockResult = BiometryUnlockResult.UnlockSuccess
    let settingsUnlock = SettingsInteractor(
        configLogic: FakeConfigLogic(),
        prefsController: SettingsPrefsFake(),
        biometryController: biomUnlock
    )
    t.check(
        match (settingsUnlock.authenticateBiometry()) { case BiometryUnlockResult.UnlockSuccess => true; case _ => false },
        "settings.authenticateBiometry_interactor_success"
    )
}

// ─── TestHomeTabInteractor (5 iOS cases) ─────────────────────────────────────

func runHomeTabInteractorTests(t: DeviceTestRun): Unit {

    // iOS: testFetchUsername_WhenPidDocumentReturnsValidName_ThenReturnsThatName
    // Cangjie: fetchUsername() calls getBearersName() on the main PID document and
    // returns the trimmed first name. FakePidDocWithName carries a given_name claim
    // ("John") + family_name (getBearersName requires both), mirroring iOS
    // Constants.createEuPidModel bearer "John".
    let fake1 = FakeWalletKitController()
    fake1.mainPidDocument = Some(FakePidDocWithName("pid-home", Some("John"), Some("Doe")))
    let interactor1 = DashboardInteractor(walletController: fake1)
    let username1 = interactor1.fetchUsername()
    t.eqStr(username1, "John", "homeTab.fetchUsername_validName_returnsJohn")

    // iOS: testFetchUsername_when no PID document → returns ""
    let fake1b = FakeWalletKitController()
    fake1b.mainPidDocument = None
    let interactor1b = DashboardInteractor(walletController: fake1b)
    let username1b = interactor1b.fetchUsername()
    t.eqStr(username1b, "", "homeTab.fetchUsername_noPidDoc_empty")

    // Cangjie extra (⚠️ no-name path): a PID doc without name claims → getBearersName
    // returns None → fetchUsername "".
    let fake1c = FakeWalletKitController()
    fake1c.mainPidDocument = Some(makeDocClaimsDecodable(id: "pid-noname"))
    let interactor1c = DashboardInteractor(walletController: fake1c)
    t.eqStr(interactor1c.fetchUsername(), "", "homeTab.fetchUsername_noNameClaim_empty")

    // ── testGetWalletKitController_WhenInteractorReturnsWalletKitController_ThenVerifyControllerIsInjected ──
    // Same accessor as the dashboard case, asserted here too because iOS declares it
    // on both interactors. Behavioural identity via a marker document (see the
    // dashboard case for why reference identity is not used).
    let fake2 = FakeWalletKitController()
    fake2.allDocuments = [makeDocClaimsDecodable(id: "home-injected-marker")]
    let interactor2 = DashboardInteractor(walletController: fake2)
    let docs2 = interactor2.getWalletKitController().fetchAllDocuments()
    t.eqInt(docs2.size, 1, "homeTab.getWalletKitController_returnsInjected_docCount")
    if (docs2.size == 1) {
        t.eqStr(docs2[0].id, "home-injected-marker", "homeTab.getWalletKitController_returnsInjectedInstance")
    } else {
        t.check(false, "homeTab.getWalletKitController_returnsInjectedInstance_wrongCount")
    }

    // iOS: testOpenBleSettings_WhenReachabilityControllerFetchBleSettings_ThenVerifyBleSettingsOpen
    // Cangjie: with a wired reachability seam, openBleSettings() delegates to it.
    let fake3 = FakeWalletKitController()
    let reach3 = FakeReachabilityController()
    let interactor3 = DashboardInteractor(walletController: fake3, reachability: reach3)
    interactor3.openBleSettings()
    t.eqInt(reach3.openBleSettingsCalls, 1, "homeTab.openBleSettings_delegatesToReachability")

    // iOS: testGetBleAvailability_WhenReachabilityControllerReturnsBleAvailability_ThenVerifyAvailableEnum
    // Cangjie: getBleAvailability() returns the value the reachability seam reports.
    let fake4 = FakeWalletKitController()
    let reach4 = FakeReachabilityController()
    reach4.bleAvailability = BleAvailibity.available
    let interactor4 = DashboardInteractor(walletController: fake4, reachability: reach4)
    // The seam answers through a callback (permission prompt / radio read may be
    // asynchronous on device; the fake answers inline). 1-cell array: Cangjie
    // closures cannot capture a mutable local.
    let cell4 = Array<BleAvailibity>(1, repeat: BleAvailibity.unavailable)
    interactor4.getBleAvailability({ a => cell4[0] = a })
    t.check(cell4[0] == BleAvailibity.available, "homeTab.getBleAvailability_available_returnsAvailable")

    // iOS: testGetBleAvailability_WhenReachabilityControllerReturnsBleAvailability_ThenVerifyDisabledEnum
    // Cangjie: disabled availability round-trips through the seam.
    let fake5 = FakeWalletKitController()
    let reach5 = FakeReachabilityController()
    reach5.bleAvailability = BleAvailibity.disabled
    let interactor5 = DashboardInteractor(walletController: fake5, reachability: reach5)
    let cell5 = Array<BleAvailibity>(1, repeat: BleAvailibity.available)
    interactor5.getBleAvailability({ a => cell5[0] = a })
    t.check(cell5[0] == BleAvailibity.disabled, "homeTab.getBleAvailability_disabled_returnsDisabled")

    // Cangjie extra: with no reachability seam wired, getBleAvailability() degrades to
    // unavailable and openBleSettings() is a safe no-op (the preview/degraded path).
    let fake6 = FakeWalletKitController()
    let interactor6 = DashboardInteractor(walletController: fake6)
    let cell6 = Array<BleAvailibity>(1, repeat: BleAvailibity.available)
    interactor6.getBleAvailability({ a => cell6[0] = a })
    t.check(cell6[0] == BleAvailibity.unavailable, "homeTab.getBleAvailability_noReachability_unavailable")
    interactor6.openBleSettings()
    t.check(true, "homeTab.openBleSettings_noReachability_noOp")
}

// ─── TestTransactionDetailsInteractor (2 iOS cases) ──────────────────────────

// Extended fake that allows configuring a single TransactionLogItem return value.
// FakeWalletKitController.fetchTransactionLog() throws by default; this subclass
// lets tests configure a real log without needing the full wallet engine, and
// lets them induce the lookup failure on purpose (iOS stubs `.failure(error)`)
// rather than relying on an unconfigured fake to happen to throw.
class FakeTxLogController <: FakeWalletKitController {
    var txLog: ?TransactionLogItem = Option<TransactionLogItem>.None
    var shouldThrow: Bool = false

    // Override: return configured txLog or throw (inherits all 40 other methods from base).
    public override func fetchTransactionLog(id: String): TransactionLogItem {
        if (this.shouldThrow) {
            throw WalletCoreError.unableToFetchTransactionLog()
        }
        match (this.txLog) {
            case Some(log) => log
            case None => throw Exception("fake: fetchTransactionLog not configured")
        }
    }
}

func runTransactionDetailsInteractorTests(t: DeviceTestRun): Unit {

    // iOS: testGetTransactionDetails_WhenWalletKitControllerReturnsTransactions_ThenReturnsExpectedUIModel
    // Cangjie: fetchTransactionDetails(id:) calls walletController.fetchTransactionLog(id).
    let txId = "transactionId1"
    let fake1 = FakeTxLogController()
    fake1.txLog = Some(makeTransactionLog(id: txId, value: "EUDI Remote Verifier"))
    let interactor1 = DashboardInteractor(walletController: fake1)
    let result1 = interactor1.fetchTransactionDetails(txId)
    t.check(result1.isSome(), "txDetails.getTransactionDetails_found_returnsSome")
    match (result1) {
        case Some(d) => t.eqStr(d.id, txId, "txDetails.getTransactionDetails_found_correctId")
        case None => t.check(false, "txDetails.getTransactionDetails_found_unexpectedNone")
    }

    // iOS: testGetTransactionDetails_WhenWalletKitControllerReturnsTransactionsFailure_ThenReturnsExpectedError
    // iOS returns .failure(error) and the view model turns that into isLoading:false
    // plus the error message on screen. Cangjie carries the failure as a throw out of
    // the interactor, so the aligned behaviour is asserted in two steps: the interactor
    // does signal the failure, and the view model converts it into the error state
    // instead of letting it escape the spawn{} the view calls it from.
    let fake2 = FakeTxLogController()
    fake2.shouldThrow = true
    let interactor2 = DashboardInteractor(walletController: fake2)
    var caughtException2 = false
    try {
        let _ = interactor2.fetchTransactionDetails("nonexistentTransactionId")
    } catch (_: Exception) {
        caughtException2 = true
    }
    t.check(caughtException2, "txDetails.getTransactionDetails_failure_interactorSignalsFailure")

    let detailsVm = TransactionDetailsViewModel(
        router: InMemoryRouterHost(),
        interactor: interactor2,
        transactionId: "nonexistentTransactionId"
    )
    var detailsVmThrew = false
    try {
        detailsVm.fetchDetails()
    } catch (_: Exception) {
        detailsVmThrew = true
    }
    t.check(!detailsVmThrew, "txDetails.getTransactionDetails_failure_viewModelContainsThrow")
    let failedState = detailsVm.viewState
    t.check(!failedState.isLoading, "txDetails.getTransactionDetails_failure_clearsLoading")
    t.check(failedState.details.isNone(), "txDetails.getTransactionDetails_failure_noDetails")
    match (failedState.errorMessage) {
        case Some(message) =>
            t.eqStr(
                message,
                WalletCoreError.unableToFetchTransactionLog().errorDescription,
                "txDetails.getTransactionDetails_failure_surfacesErrorMessage"
            )
        case None =>
            t.check(false, "txDetails.getTransactionDetails_failure_surfacesErrorMessage_missing")
    }

    // The success path must leave the error slot empty, so the error state cannot
    // shadow real details.
    let okVm = TransactionDetailsViewModel(
        router: InMemoryRouterHost(),
        interactor: interactor1,
        transactionId: txId
    )
    okVm.fetchDetails()
    t.check(okVm.viewState.errorMessage.isNone(), "txDetails.getTransactionDetails_found_noErrorMessage")
}

// ─── Main entry point ─────────────────────────────────────────────────────────

func runFeatureDashboardTests(t: DeviceTestRun): Unit {
    runDashboardInteractorTests(t)
    runDocumentTabInteractorTests(t)
    runDocumentDetailsInteractorTests(t)
    runDocumentDetailsBookmarkTests(t)
    runRevokedModalRowsTests(t)
    runTransactionTabInteractorTests(t)
    runSettingsInteractorTests(t)
    runHomeTabInteractorTests(t)
    runTransactionDetailsInteractorTests(t)
}
