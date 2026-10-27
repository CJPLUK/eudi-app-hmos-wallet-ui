/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * interactors (Interactor/Dashboard/DocumentTabInteractor.swift,
 * TransactionTabInteractor.swift, Interactor/Detail/DocumentDetailsInteractor.swift,
 * TransactionDetailsInteractor.swift) to Cangjie.
 *
 * Pure business-logic seam wrapping WalletKitController (logic-core). NO ArkUI
 * imports here (UI-free layer; importing kit.ArkUI.* would pollute `None`). The
 * interactor performs the blocking engine calls and returns flat, render-ready
 * data classes; the View renders them with built-in components only (R-102) and
 * marshals the calls through spawn{} / spawn(UIThread){} (S-001).
 */
package eudi_feature_dashboard

import std.collection.{ArrayList, HashMap}
import kit.PerformanceAnalysisKit.Hilog
import std.sort.*
import std.time.*
import eudi_logic_core.{
    WalletKitController, DocClaimsDecodable, DocClaim, TransactionLogItem,
    DocumentCategory, DocumentCategories, DocumentTypeIdentifier, DocumentStatus,
    CredentialPolicy, issuerName, issuerLogo, hasExpired, getExpiryDate, documentTypeIdentifier,
    getBearersName, WalletStorageDocument, IssuedDocument, DeferredDocument, CredentialsUsageCounts,
    isTrustBlocked
}
import eudi_logic_business.{
    DateUtil, ReachabilityController, BleAvailibity,
    Filters, FilterGroup, FilterItem, FilterSort, FilterGroupType, FilterElementType,
    SingleSelectionFilterGroup, ReversibleSingleSelectionFilterGroup,
    MultipleSelectionFilterGroup, FilterMultipleAction,
    FilterableList, FilterableItem, FilterableItemPayload, FilterableAttributes,
    FilterValidatorImpl, FilterValidator, FilterResultPartialState, FilterResult,
    SortOrderType, FilterIds, Filter, SortAction,
    PrefsController, PrefsKey
}
import eudi_logic_resources.{LocalizableStringKey, LocalizableManager}

// ─── Flat render-ready row models (no ArkUI) ───────────────────────────────

/** Document state — mirrors iOS DocumentTabUIModel.Value.State. */
public enum DocumentRowState {
    | issued
    | pending
    | failed
    | revoked
    | expired
}

/**
 * Result of DashboardInteractor.reIssueDocument(). Mirrors the iOS
 * DocumentDetails `DocumentDetailsReIssuancePartialState`: success |
 * issuerNotTrusted (trust-blocked, incl. RegistrationRefusedError — the UI
 * raises the blocking "Issuance blocked" alert) | failure(error).
 */
public enum ReIssueResult {
    | ReIssueSuccess
    | ReIssueIssuerNotTrusted
    | ReIssueFailure(String)
}

/**
 * Result of DashboardInteractor.requestDeferredIssuance(). Mirrors the iOS
 * DocumentTabInteractor `DeferredPartialState`:
 *   - `.completion(issued:[DocumentTabUIModel], failed:[String])` → `issued`
 *     rows + `failed` deferred ids;
 *   - `.cancelled` → `cancelled == true`.
 * Cangjie has no cooperative Task cancellation in this headless seam, so
 * `cancelled` is surfaced as a field the caller can inspect (always false on the
 * normal completion path — the only path reachable without a cancelling task).
 */
public class DeferredIssuanceOutcome {
    /** Rows for documents whose deferred issuance completed (no longer deferred). */
    public let issued: Array<DocumentRow>
    /** Ids of deferred documents whose re-issuance threw. */
    public let failed: Array<String>
    /** True only if the run was cancelled before finishing (iOS `.cancelled`). */
    public let cancelled: Bool

    public init(issued!: Array<DocumentRow>, failed!: Array<String>, cancelled!: Bool = false) {
        this.issued = issued
        this.failed = failed
        this.cancelled = cancelled
    }
}

/**
 * A flat, render-ready document row. Mirrors the displayed fields of the iOS
 * DocumentTabUIModel — already resolved to plain Strings so the View can render
 * with built-in components only inside ForEach (R-102).
 */
public class DocumentRow {
    public let id: String
    public let isHeader: Bool
    public let categoryTitle: String
    public let title: String
    public let issuer: String
    public let supportingText: String
    public let logoUrl: String
    public let state: DocumentRowState
    /** Expiry as epoch seconds (0 = no expiry) — drives the "Expiry period" filter. */
    public let expiryTimestamp: Int64
    /** Issued (valid-from) epoch seconds — drives the "Date Issued" sort. */
    public let issuedTimestamp: Int64
    /** Trailing credential-usage badge "remaining/total" (iOS
     *  documentsListCredentialsUsageText, e.g. "1/1"); "" hides it. */
    public let usageText: String
    /**
     * Category-card edge flags (first/last doc in a grouped card). Baked at list
     * build time so ForEach itemGenerator never indexes the live `@State rows`
     * by a possibly-stale idx (delete → DocumentTabRefresh race → OOB crash).
     */
    public let isCardTop: Bool
    public let isCardBottom: Bool

    public init(
        id!: String,
        isHeader!: Bool,
        categoryTitle!: String,
        title!: String,
        issuer!: String,
        supportingText!: String,
        logoUrl!: String,
        state!: DocumentRowState,
        expiryTimestamp!: Int64 = 0,
        issuedTimestamp!: Int64 = 0,
        usageText!: String = "",
        isCardTop!: Bool = true,
        isCardBottom!: Bool = true
    ) {
        this.id = id
        this.isHeader = isHeader
        this.categoryTitle = categoryTitle
        this.title = title
        this.issuer = issuer
        this.supportingText = supportingText
        this.logoUrl = logoUrl
        this.state = state
        this.expiryTimestamp = expiryTimestamp
        this.issuedTimestamp = issuedTimestamp
        this.usageText = usageText
        this.isCardTop = isCardTop
        this.isCardBottom = isCardBottom
    }

    /** Convenience header-row factory (category title separator). */
    public static func header(title: String): DocumentRow {
        DocumentRow(
            id: "hdr_${title}",
            isHeader: true,
            categoryTitle: title,
            title: title,
            issuer: "",
            supportingText: "",
            logoUrl: "",
            state: DocumentRowState.issued
        )
    }
}

/** A flat, render-ready transaction row. Mirrors iOS TransactionTabUIModel. */
public class TransactionRow {
    public let id: String
    public let isHeader: Bool
    public let title: String
    public let dateText: String
    public let groupTitle: String
    /**
     * Relying-party (verifier) name for this transaction — drives the iOS
     * "Filter by relying party name" multi-select group (addRelyingPartyName).
     * None when the wallet log carries no relying-party value (mapped to the
     * iOS `FILTER_BY_RELYING_PARTY_NONE` "No Relying Party" item).
     */
    public let relyingPartyName: ?String
    public let statusLabel: String
    public let typeLabel: String
    public let isCompleted: Bool
    public let timestamp: Int64
    public let isCardTop: Bool
    public let isCardBottom: Bool

    public init(
        id!: String,
        isHeader!: Bool,
        title!: String,
        dateText!: String,
        groupTitle!: String,
        relyingPartyName!: ?String = Option<String>.None,
        statusLabel!: String = "Completed",
        typeLabel!: String = "Presentation",
        isCompleted!: Bool = true,
        timestamp!: Int64 = 0,
        isCardTop!: Bool = true,
        isCardBottom!: Bool = true
    ) {
        this.id = id
        this.isHeader = isHeader
        this.title = title
        this.dateText = dateText
        this.groupTitle = groupTitle
        this.relyingPartyName = relyingPartyName
        this.statusLabel = statusLabel
        this.typeLabel = typeLabel
        this.isCompleted = isCompleted
        this.timestamp = timestamp
        this.isCardTop = isCardTop
        this.isCardBottom = isCardBottom
    }

    public static func header(title: String): TransactionRow {
        TransactionRow(id: "thdr_${title}", isHeader: true, title: title, dateText: "", groupTitle: title)
    }

    public func withCardEdges(top: Bool, bottom: Bool): TransactionRow {
        TransactionRow(
            id: this.id, isHeader: this.isHeader, title: this.title,
            dateText: this.dateText, groupTitle: this.groupTitle,
            relyingPartyName: this.relyingPartyName,
            statusLabel: this.statusLabel, typeLabel: this.typeLabel,
            isCompleted: this.isCompleted, timestamp: this.timestamp,
            isCardTop: top, isCardBottom: bottom
        )
    }
}

// ─── Filters UI model (mirrors iOS FilterUISection / FilterUIItem) ──────────

/** Section kind — radio list or the date-range picker. Mirrors iOS FilterSectionType. */
public enum FilterUISectionType {
    | radio
    | datePicker
}

/**
 * A single selectable filter row. Mirrors the displayed fields of the iOS
 * `FilterUIItem` (id / title / selected / optional start-end dates for the
 * date-range item). Render-ready Strings so the View renders with built-in
 * components only (R-102).
 */
public class FilterUIItem {
    public let id: String
    public let title: String
    public let selected: Bool
    public let sectionType: FilterUISectionType
    public let startDate: ?DateTime
    public let endDate: ?DateTime

    public init(
        id!: String,
        title!: String,
        selected!: Bool,
        sectionType!: FilterUISectionType = FilterUISectionType.radio,
        startDate!: ?DateTime = Option<DateTime>.None,
        endDate!: ?DateTime = Option<DateTime>.None
    ) {
        this.id = id
        this.title = title
        this.selected = selected
        this.sectionType = sectionType
        this.startDate = startDate
        this.endDate = endDate
    }
}

/** A titled group of filter rows. Mirrors iOS `FilterUISection`. */
public class FilterUISection {
    public let id: String
    public let sectionTitle: String
    public let filters: Array<FilterUIItem>

    public init(id!: String, sectionTitle!: String, filters!: Array<FilterUIItem>) {
        this.id = id
        this.sectionTitle = sectionTitle
        this.filters = filters
    }
}

/** A single key/value claim row for the details screen. */
public class ClaimRow {
    public let title: String
    public let value: String

    public init(title!: String, value!: String) {
        this.title = title
        this.value = value
    }
}

/**
 * A grouped section of claim rows. Mirrors the iOS `WrapExpandableListView`
 * sections of DocumentDetailsView / TransactionDetailsView (one section per
 * mDoc namespace / nested claim group; documents with flat claims collapse to a
 * single section titled with the document name).
 */
public class ClaimSection {
    public let id: String
    public let title: String
    public let rows: Array<ClaimRow>

    public init(id!: String, title!: String, rows!: Array<ClaimRow>) {
        this.id = id
        this.title = title
        this.rows = rows
    }
}

/**
 * Render-ready issuer-card bundle. Mirrors the iOS
 * `IssuerDocumentDetailsCardUIModel`: header (logo + issuer name + supporting
 * date / "View details") plus the expanded body (issued/revoked message +
 * optional reissue action).
 */
public class IssuerCardData {
    public let issuerName: String
    public let issuerLogoUrl: String
    public let supportingText: String   // "Expires on: …" / "Expired on: …" / "Document revoked" / "View details"
    public let isRevoked: Bool
    /** iOS DocumentState.expired — never true together with isRevoked (iOS
     *  transformToIssuerDetailsCardDataUi checks isRevoked first). */
    public let isExpired: Bool
    public let issuedOnText: String      // "Issued on: …" (expanded body), "" when unknown

    public init(
        issuerName!: String,
        issuerLogoUrl!: String,
        supportingText!: String,
        isRevoked!: Bool,
        isExpired!: Bool = false,
        issuedOnText!: String
    ) {
        this.issuerName = issuerName
        this.issuerLogoUrl = issuerLogoUrl
        this.supportingText = supportingText
        this.isRevoked = isRevoked
        this.isExpired = isExpired
        this.issuedOnText = issuedOnText
    }
}

/**
 * Credential-usage footer. Mirrors iOS `DocumentCredentialsInfoUi`
 * (availableCredentials / totalCredentials → "Instances remaining X/Y").
 * Present only for documents whose policy keeps a usage counter.
 */
public class CredentialUsageInfo {
    public let remaining: Int64
    public let total: Int64

    public init(remaining!: Int64, total!: Int64) {
        this.remaining = remaining
        this.total = total
    }

    public func text(): String {
        LocalizableManager.get(
            LocalizableStringKey.documentDetailsDocumentCredentialsText(["${this.remaining}", "${this.total}"])
        )
    }
}

/** Render-ready document-details bundle. */
/**
 * A single entry in the document-data list (mirrors iOS ExpandableListItem):
 * a scalar field (title + value) when `isGroup` is false, or a nested group
 * (title + child rows, rendered as an expandable section) when true. The list is
 * a single flat, alphabetically-ordered sequence so scalars and groups interleave
 * exactly like the iOS WrapExpandableListView.
 */
public class DocumentField {
    public let id: String
    public let isGroup: Bool
    public let title: String
    public let value: String
    public let rows: Array<ClaimRow>
    public init(id!: String, isGroup!: Bool, title!: String, value!: String = "", rows!: Array<ClaimRow> = Array<ClaimRow>()) {
        this.id = id
        this.isGroup = isGroup
        this.title = title
        this.value = value
        this.rows = rows
    }
}

/**
 * Title-case a snake/dot/dash claim key for a nested-group header, mirroring how
 * iOS prettifies the namespace title ("authentic_source" → "Authentic Source").
 * Used only when the group claim has no issuer-provided display name; leaf claim
 * labels keep their raw-key fallback (iOS shows e.g. exp/iat raw).
 */
func prettifyGroupKey(key: String): String {
    let out = ArrayList<Byte>()
    var capNext = true
    for (b in key.toArray()) {
        if (b == b'_' || b == b'.' || b == b'-') {
            if (!out.isEmpty()) {
                out.add(b' ')
            }
            capNext = true
        } else {
            var c = b
            if (capNext && c >= b'a' && c <= b'z') {
                c = c - 32
            }
            capNext = false
            out.add(c)
        }
    }
    if (out.isEmpty()) {
        return key
    }
    return String.fromUtf8(out.toArray())
}

public class DocumentDetails {
    public let id: String
    public let title: String
    public let issuer: String
    public let issuerLogoUrl: String
    public let expiresText: String
    public let isRevoked: Bool
    /** Mirrors iOS DocumentDetailsPartialState.isBookmarked (from walletController.isDocumentBookmarked). */
    public let isBookmarked: Bool
    // Flat claims kept for compatibility; `documentFields` is the single ordered
    // list (scalars + expandable groups interleaved) used by the document-data
    // list — mirrors iOS document.documentFields rendered via WrapExpandableListView.
    public let claims: Array<ClaimRow>
    public let sections: Array<ClaimSection>
    public let documentFields: Array<DocumentField>
    public let issuerCard: IssuerCardData
    public let credentialUsage: ?CredentialUsageInfo

    public init(
        id!: String,
        title!: String,
        issuer!: String,
        issuerLogoUrl!: String,
        expiresText!: String,
        isRevoked!: Bool,
        claims!: Array<ClaimRow>,
        sections!: Array<ClaimSection>,
        documentFields!: Array<DocumentField> = Array<DocumentField>(),
        issuerCard!: IssuerCardData,
        credentialUsage!: ?CredentialUsageInfo = Option<CredentialUsageInfo>.None,
        isBookmarked!: Bool = false
    ) {
        this.id = id
        this.title = title
        this.issuer = issuer
        this.issuerLogoUrl = issuerLogoUrl
        this.expiresText = expiresText
        this.isRevoked = isRevoked
        this.claims = claims
        this.sections = sections
        this.documentFields = documentFields
        this.issuerCard = issuerCard
        this.credentialUsage = credentialUsage
        this.isBookmarked = isBookmarked
    }
}

/** Render-ready transaction-details bundle (mirrors iOS TransactionDetailsUiModel). */
public class TransactionDetails {
    public let id: String
    public let title: String
    public let dateText: String
    // Card fields — mirror iOS TransactionDetailsCardData.
    public let transactionTypeLabel: String
    public let relyingPartyName: String
    public let relyingPartyIsVerified: Bool
    public let statusLabel: String
    public let isCompleted: Bool
    // "Data shared" grouped sections (mirrors iOS items).
    public let sections: Array<ClaimSection>

    public init(
        id!: String,
        title!: String,
        dateText!: String,
        transactionTypeLabel!: String,
        relyingPartyName!: String,
        relyingPartyIsVerified!: Bool,
        statusLabel!: String,
        isCompleted!: Bool,
        sections!: Array<ClaimSection>
    ) {
        this.id = id
        this.title = title
        this.dateText = dateText
        this.transactionTypeLabel = transactionTypeLabel
        this.relyingPartyName = relyingPartyName
        this.relyingPartyIsVerified = relyingPartyIsVerified
        this.statusLabel = statusLabel
        this.isCompleted = isCompleted
        this.sections = sections
    }
}

// ─── Interactor ────────────────────────────────────────────────────────────

/**
 * Wraps WalletKitController for the dashboard feature. Mirrors the iOS
 * DocumentTab / TransactionTab / DocumentDetails / TransactionDetails
 * interactors, collapsed into one seam (no separate actor types needed).
 *
 * All methods are blocking; the View calls them from spawn{}.
 */
public class DashboardInteractor {
    private let walletController: WalletKitController
    /** Reachability seam (BLE availability / settings). None → degraded preview. */
    private let reachability: ?ReachabilityController
    /** Batch-counter preference seam (iOS isBatchCounterEnabled gating). */
    private let prefs: ?PrefsController

    public init(walletController!: WalletKitController, prefs!: ?PrefsController = None) {
        this.walletController = walletController
        this.reachability = Option<ReachabilityController>.None
        this.prefs = prefs
    }

    public init(
        walletController!: WalletKitController,
        reachability!: ReachabilityController,
        prefs!: ?PrefsController = None
    ) {
        this.walletController = walletController
        this.reachability = Some(reachability)
        this.prefs = prefs
    }

    /**
     * Mirrors iOS HomeTabInteractor.fetchUsername(): the main PID document's
     * bearer first name (trimmed). Returns "" when no PID is stored. Blocking;
     * the view wraps the call in spawn{}.
     */
    public func fetchUsername(): String {
        match (this.walletController.fetchMainPidDocument()) {
            case Some(doc) =>
                match (getBearersName(doc)) {
                    case Some((first, _)) => first.trimAscii()
                    case None => ""
                }
            case None => ""
        }
    }

    /**
     * Mirrors iOS HomeTabInteractor.getBleAvailability() (a publisher there).
     * The ReachabilityController answers through the callback — asynchronously
     * when the ACCESS_BLUETOOTH runtime prompt has to be shown first or the
     * radio state is read over the ArkTS bridge. With no reachability seam
     * wired (preview) it reports `unavailable`.
     */
    public func getBleAvailability(callback: (BleAvailibity) -> Unit): Unit {
        match (this.reachability) {
            case Some(r) => r.getBleAvailibity(callback)
            case None => callback(BleAvailibity.unavailable)
        }
    }

    /** Mirrors iOS HomeTabInteractor.openBleSettings(). */
    public func openBleSettings(): Unit {
        match (this.reachability) {
            case Some(r) => r.openBleSettings()
            case None => ()
        }
    }

    private static func uiDateParser(d: DateTime): String {
        DateUtil.formatDate(d, "dd MMM yyyy")
    }

    /**
     * Builds a DateTime from a wallet transaction-log epoch timestamp. The
     * MdocDataModel transaction log stamps epoch seconds; if a millisecond
     * stamp is ever passed it is normalised down to seconds first.
     */
    private static func dateFromTimestamp(timestamp: Int64): DateTime {
        var seconds = timestamp
        if (seconds > 100000000000) {
            // looks like milliseconds → normalise to seconds
            seconds = seconds / 1000
        }
        // An epoch is an absolute instant. iOS DateFormatter renders that instant
        // in Calendar.current; DateTime otherwise exposes the UTC fields here,
        // which made History one timezone offset behind the phone clock.
        return DateTime.fromUnixTimeStamp(Duration.second * seconds).inLocal()
    }

    /** iOS TransactionCategory.category(for:): Today, This week, then month/year. */
    private static func transactionCategoryKey(date: DateTime): Int64 {
        if (DateUtil.isToday(date)) {
            return Int64.Max - 2
        }
        if (DateUtil.isThisWeek(date)) {
            return Int64.Max - 3
        }
        return DateUtil.monthYearOrder(date)
    }

    private static func transactionCategoryTitle(date: DateTime): String {
        if (DateUtil.isToday(date)) {
            return LocalizableManager.get(LocalizableStringKey.today)
        }
        if (DateUtil.isThisWeek(date)) {
            return LocalizableManager.get(LocalizableStringKey.thisWeek)
        }
        return DateUtil.formattedMonthYear(date)
    }

    /** Mirrors iOS Date.formattedForTransactionDisplay() exactly. */
    private static func formattedTransactionDisplay(date: DateTime, timestamp: Int64): String {
        var seconds = timestamp
        if (seconds > 100000000000) {
            seconds = seconds / 1000
        }
        let nowSeconds = DateTime.now().toUnixTimeStamp().toMilliseconds() / 1000
        let diffMinutes = (nowSeconds - seconds) / 60
        if (diffMinutes < 0) {
            return LocalizableManager.get(LocalizableStringKey.unknownDate)
        }
        if (diffMinutes == 0) {
            return LocalizableManager.get(LocalizableStringKey.justNow)
        }
        if (diffMinutes < 60) {
            if (diffMinutes == 1) {
                return LocalizableManager.get(LocalizableStringKey.minuteAgo([diffMinutes.toString()]))
            }
            return LocalizableManager.get(LocalizableStringKey.minutesAgo([diffMinutes.toString()]))
        }
        if (DateUtil.isToday(date)) {
            return DateUtil.formatDate(date, "hh:mm a")
        }
        return DateUtil.formatDate(date, "dd MMM yyyy hh:mm a")
    }

    /**
     * Mirrors DocumentTabInteractor.fetchDocuments + the category grouping the
     * iOS DocumentTabView applies: returns a flat list with one header row per
     * category followed by that category's document rows, ordered by category.
     */
    public func fetchDocumentRows(): Array<DocumentRow> {
        let documents = this.walletController.fetchAllDocuments()
        if (documents.size == 0) {
            return Array<DocumentRow>()
        }

        let revoked = this.collectRevoked()
        let categories = this.walletController.getDocumentCategories().sortedByOrder()

        // category.order -> (title, rows)
        let grouped: HashMap<Int64, ArrayList<DocumentRow>> = HashMap<Int64, ArrayList<DocumentRow>>()
        let titles: HashMap<Int64, String> = HashMap<Int64, String>()
        let order: ArrayList<Int64> = ArrayList<Int64>()

        for (doc in documents) {
            let category = this.categoryFor(doc, categories)
            let key = category.order
            if (!grouped.contains(key)) {
                grouped[key] = ArrayList<DocumentRow>()
                titles[key] = LocalizableManager.get(category.title)
                order.add(key)
            }
            grouped[key].add(this.toDocumentRow(doc, revoked))
        }

        // order categories ascending by DocumentCategory.order
        let sortedKeys = this.sortedInts(order)

        let result = ArrayList<DocumentRow>()
        for (key in sortedKeys) {
            result.add(DocumentRow.header(titles[key]))
            // iOS DocumentTabViewModel default sort: by document name ascending.
            // The engine returns storage order, so sort each category's rows —
            // otherwise iOS shows "PID (MSO Mdoc Deferred)" above "PID (SD-JWT
            // VC)" while OHOS shows the reverse.
            let rows = grouped[key].toArray()
            var i = 1
            while (i < rows.size) {
                let kr = rows[i]
                let kt = kr.title.toAsciiLower()
                var j = i - 1
                while (j >= 0 && rows[j].title.toAsciiLower() > kt) {
                    rows[j + 1] = rows[j]
                    j--
                }
                rows[j + 1] = kr
                i++
            }
            for (row in rows) {
                result.add(row)
            }
        }
        return result.toArray()
    }

    /**
     * Search + sort over the grouped document rows. Mirrors the iOS
     * DocumentTabViewModel `applySearch(query:)` + the default sort (by document
     * name) pipeline: a case-insensitive substring match on the document title /
     * issuer keeps a category header only when it still has at least one matching
     * row, and `ascending=false` reverses the row order within each category.
     * Real data only — operates on the rows fetched from WalletKitController.
     */
    public func fetchDocumentRowsFiltered(query: String, ascending: Bool): Array<DocumentRow> {
        let all = this.fetchDocumentRows()
        let needle = query.toAsciiLower()

        // Re-bucket the flat (header, rows...) list by header so empty groups can
        // be dropped after filtering, emitting each group as it closes. No
        // mutable-capturing closure (Cangjie forbids it); the emit logic is a
        // private helper called at each header boundary and once at the end.
        let result = ArrayList<DocumentRow>()
        var pendingHeader: ?DocumentRow = Option<DocumentRow>.None
        var pendingRows = ArrayList<DocumentRow>()

        for (row in all) {
            if (row.isHeader) {
                this.emitGroup(result, pendingHeader, pendingRows, ascending)
                pendingHeader = Some(row)
                pendingRows = ArrayList<DocumentRow>()
            } else {
                if (needle.isEmpty() ||
                    row.title.toAsciiLower().contains(needle) ||
                    row.issuer.toAsciiLower().contains(needle)) {
                    pendingRows.add(row)
                }
            }
        }
        this.emitGroup(result, pendingHeader, pendingRows, ascending)
        return result.toArray()
    }

    /**
     * Appends a category (header + its rows) to `out` only when it still has at
     * least one row after filtering; reverses the row order when ascending=false.
     */
    private func emitGroup(
        out: ArrayList<DocumentRow>,
        header: ?DocumentRow,
        rows: ArrayList<DocumentRow>,
        ascending: Bool
    ): Unit {
        match (header) {
            case Some(h) where rows.size > 0 =>
                out.add(h)
                if (ascending) {
                    for (r in rows) {
                        out.add(r)
                    }
                } else {
                    var i = rows.size - 1
                    while (i >= 0) {
                        out.add(rows[i])
                        i--
                    }
                }
            case _ => ()
        }
    }

    /** Mirrors TransactionTabInteractor.fetchTransactions and iOS category grouping. */
    public func fetchTransactionRows(): Array<TransactionRow> {
        let logs = this.walletController.fetchTransactionLogs()
        if (logs.size == 0) {
            return Array<TransactionRow>()
        }

        // iOS groups current transactions as TODAY / THIS WEEK, then falls back
        // to month/year for older records.
        let grouped: HashMap<Int64, ArrayList<TransactionRow>> = HashMap<Int64, ArrayList<TransactionRow>>()
        let titles: HashMap<Int64, String> = HashMap<Int64, String>()
        let order: ArrayList<Int64> = ArrayList<Int64>()

        for (log in logs) {
            let date = DashboardInteractor.dateFromTimestamp(log.transactionLogData.timestamp)
            let key = DashboardInteractor.transactionCategoryKey(date)
            if (!grouped.contains(key)) {
                grouped[key] = ArrayList<TransactionRow>()
                titles[key] = DashboardInteractor.transactionCategoryTitle(date)
                order.add(key)
            }
            grouped[key].add(
                TransactionRow(
                    id: log.id,
                    isHeader: false,
                    title: this.transactionTitle(log),
                    dateText: DashboardInteractor.formattedTransactionDisplay(
                        date,
                        log.transactionLogData.timestamp
                    ),
                    groupTitle: titles[key],
                    relyingPartyName: this.relyingPartyName(log),
                    statusLabel: if (log.transactionLogData.status == "completed") {
                        LocalizableManager.get(LocalizableStringKey.completed)
                    } else {
                        LocalizableManager.get(LocalizableStringKey.failed)
                    },
                    typeLabel: LocalizableManager.get(LocalizableStringKey.presentation),
                    isCompleted: log.transactionLogData.status == "completed",
                    timestamp: log.transactionLogData.timestamp
                )
            )
        }

        // newest first → descending by monthYearOrder
        let sortedKeys = this.sortedIntsDesc(order)
        let result = ArrayList<TransactionRow>()
        for (key in sortedKeys) {
            result.add(TransactionRow.header(titles[key]))
            let rows = grouped[key]
            // HashMap persistence order is undefined; iOS sorts transactions by
            // timestamp inside each month as well as sorting the month sections.
            var i = 1
            while (i < rows.size) {
                let current = rows[i]
                var j = i - 1
                while (j >= 0 && rows[j].timestamp < current.timestamp) {
                    rows[j + 1] = rows[j]
                    j--
                }
                rows[j + 1] = current
                i++
            }
            var index = 0
            while (index < rows.size) {
                result.add(rows[index].withCardEdges(index == 0, index == rows.size - 1))
                index++
            }
        }
        return result.toArray()
    }

    /**
     * Builds the document-tab filter controller (mirrors DocumentTabViewModel's
     * setFilters): default Sort + State filters over the real document rows.
     */
    public func buildDocumentFilterController(rows: Array<DocumentRow>): DashboardFilterController {
        return DashboardFilterController.forDocuments(rows)
    }

    /**
     * Builds the transaction-tab filter controller (mirrors
     * TransactionTabViewModel's setFilters): default Sort + a date-range group
     * clamped to the wallet's min/max transaction dates. Timestamps are recovered
     * from the wallet logs so the date filter operates on real data.
     */
    /** Row id → epoch seconds; shared by the filter factory and the refresh path. */
    private func transactionTimestamps(): HashMap<String, Int64> {
        let timestamps = HashMap<String, Int64>()
        for (log in this.walletController.fetchTransactionLogs()) {
            let date = DashboardInteractor.dateFromTimestamp(log.transactionLogData.timestamp)
            timestamps[log.id] = date.toUnixTimeStamp().toMilliseconds() / 1000
        }
        return timestamps
    }

    /**
     * Mirrors iOS TransactionTabInteractor.updateLists(filterableList:): after a
     * refetch, swap the filter engine's source rows without resetting selections.
     * Documents have no extra per-row data, so that side calls
     * `DashboardFilterController.updateLists(rows)` directly.
     */
    public func updateTransactionFilterLists(
        controller: DashboardFilterController,
        rows: Array<TransactionRow>
    ): Unit {
        controller.updateLists(rows, this.transactionTimestamps())
    }

    public func buildTransactionFilterController(rows: Array<TransactionRow>): DashboardFilterController {
        let timestamps = this.transactionTimestamps()
        var minTs: ?Int64 = Option<Int64>.None
        var maxTs: ?Int64 = Option<Int64>.None
        for ((_, secs) in timestamps) {
            match (minTs) {
                case Some(m) => if (secs < m) { minTs = Some(secs) }
                case None => minTs = Some(secs)
            }
            match (maxTs) {
                case Some(m) => if (secs > m) { maxTs = Some(secs) }
                case None => maxTs = Some(secs)
            }
        }
        let now = DateTime.now()
        let minDate = match (minTs) {
            case Some(s) => DateTime.fromUnixTimeStamp(Duration.second * s).inLocal()
            case None => now
        }
        let maxDate = match (maxTs) {
            // iOS adds one minute so the latest row is not clipped by picker precision.
            case Some(s) => DateTime.fromUnixTimeStamp(Duration.second * (s + 60)).inLocal()
            case None => now
        }
        return DashboardFilterController.forTransactions(rows, timestamps, minDate, maxDate)
    }

    /** Mirrors DocumentDetailsInteractor.fetchStoredDocument. */
    public func fetchDocumentDetails(documentId: String): ?DocumentDetails {
        match (this.walletController.fetchDocument(documentId)) {
            case Some(doc) =>
                let revoked = this.walletController.isDocumentRevoked(documentId)
                let bookmarked = this.walletController.isDocumentBookmarked(documentId)
                let expires = getExpiryDate(doc, DashboardInteractor.uiDateParser) ?? ""
                // iOS IssuerDocumentDetailsCardUIModel: always createdAt via
                // formattedForDocumentDetails ("dd MMMM yyyy - HH:mm"). Never
                // MSO validFrom — that is validity start, not issuance display.
                // .inLocal() mirrors iOS DateFormatter default (device TZ); createdAt
                // is reloaded from unix millis as UTC-anchored DateTime.
                let issuedOn = LocalizableManager.get(
                    LocalizableStringKey.documentDetailsIssuedOn(
                        [DateUtil.formatDate(doc.createdAt.inLocal(), "dd MMMM yyyy - HH:mm")]
                    )
                )
                // Issuer card shows the expiry in short "dd MMM yyyy" form (iOS
                // "Expires on: 23 Sep 2026"). getExpiryDate returns the validUntil
                // already in that form, or — for SD-JWT, where validUntil is empty —
                // the raw ISO date_of_expiry claim ("2026-09-23"); normalize the
                // latter. localizedDateTime echoes an already-formatted value back
                // unchanged, so it is safe on both paths.
                let expiresShort = if (expires.isEmpty()) {
                    ""
                } else {
                    DateUtil.localizedDateTime(expires, "dd MMM yyyy")
                }
                // iOS transformToIssuerDetailsCardDataUi: isRevoked → .revoked,
                // else hasExpired → .expired, else .issued.
                let expired = !revoked && hasExpired(doc)
                let supporting = if (revoked) {
                    LocalizableManager.get(LocalizableStringKey.documentDetailsRevokedDocument)
                } else if (expired && !expiresShort.isEmpty()) {
                    LocalizableManager.get(LocalizableStringKey.documentDetailsExpiredOn([expiresShort]))
                } else if (!expiresShort.isEmpty()) {
                    LocalizableManager.get(LocalizableStringKey.documentDetailsExpiresOn([expiresShort]))
                } else {
                    LocalizableManager.get(LocalizableStringKey.viewDetails)
                }
                let issuerCard = IssuerCardData(
                    issuerName: issuerName(doc),
                    issuerLogoUrl: issuerLogo(doc) ?? "",
                    supportingText: supporting,
                    isRevoked: revoked,
                    isExpired: expired,
                    issuedOnText: issuedOn
                )
                Some(
                    DocumentDetails(
                        id: doc.id,
                        title: doc.displayName ?? LocalizableManager.get(LocalizableStringKey.documents),
                        issuer: issuerName(doc),
                        issuerLogoUrl: issuerLogo(doc) ?? "",
                        expiresText: expires,
                        isRevoked: revoked,
                        claims: this.flattenClaims(doc),
                        sections: this.claimSections(doc),
                        documentFields: this.documentFields(doc),
                        issuerCard: issuerCard,
                        credentialUsage: this.credentialUsage(doc),
                        isBookmarked: bookmarked
                    )
                )
            case None => None
        }
    }

    /**
     * Mirrors iOS DocumentDetailsInteractor.deleteDocument: removes the document
     * from the wallet via WalletKitController. Blocking; view wraps in spawn{}.
     */
    public func deleteDocument(documentId: String): Bool {
        try {
            this.walletController.deleteDocument(documentId, DocumentStatus.issued)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Mirrors iOS DocumentTabViewModel.onDeleteDeferredDocument: removes a
     * deferred (or failed-deferred) document from the wallet. Deferred docs are
     * stored under a different partition than issued ones, so the delete must
     * pass `DocumentStatus.deferred` (WKDocumentStatus.Deferred). Blocking; the
     * view wraps in spawn{}.
     */
    public func deleteDeferredDocument(documentId: String): Bool {
        try {
            this.walletController.deleteDocument(documentId, DocumentStatus.deferred)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Mirrors iOS DocumentDetailsInteractor.reIssueDocument: re-issues the
     * document via WalletKitController (foreground operation). A trust-blocked
     * throw — including `RegistrationRefusedError` from the controller's
     * registration pre-check — maps to the issuer-not-trusted outcome (iOS
     * `error.isTrustBlocked ? .issuerNotTrusted : .failure(error)`). Blocking;
     * view wraps in spawn{}.
     */
    public func reIssueDocument(documentId: String): ReIssueResult {
        try {
            this.walletController.reIssueDocument(identifier: documentId, isBackgroundOperation: false)
            return ReIssueResult.ReIssueSuccess
        } catch (e: Exception) {
            if (isTrustBlocked(e)) {
                return ReIssueResult.ReIssueIssuerNotTrusted
            }
            return ReIssueResult.ReIssueFailure(e.message)
        }
    }

    /**
     * Mirrors iOS DocumentTabInteractor.requestDeferredIssuance():
     * DeferredPartialState.completion(issued:[…], failed:[…]).
     *
     * Iterates the wallet's deferred documents, calls
     * walletController.requestDeferredIssuance on each, and:
     *   - if the returned document is still a DeferredDocument (issuance not yet
     *     complete on the issuer side) → skip it (iOS `(document is
     *     DeferrredDocument) == false` guard);
     *   - else → transform to a render-ready DocumentRow (marking revoked ones
     *     from fetchRevokedDocuments, exactly like iOS transformToDocumentTabUi
     *     with isRevoked);
     *   - if the call throws → record the deferred id in `failed`.
     *
     * Blocking; the View wraps in spawn{}. Cancellation (iOS `.cancelled`) has no
     * cooperative-task equivalent in this seam, so the outcome always reports
     * cancelled=false on this path.
     */
    public func requestDeferredIssuance(): DeferredIssuanceOutcome {
        let issued = ArrayList<DocumentRow>()
        let failed = ArrayList<String>()
        let revoked = this.collectRevoked()

        for (deferred in this.fetchDeferredStorageDocuments()) {
            try {
                let document = this.walletController.requestDeferredIssuance(deferred)
                // Still deferred → issuer has not produced the credential yet; skip
                // (mirrors iOS `if (document is DeferrredDocument) == false`).
                if (!(document is DeferredDocument)) {
                    issued.add(this.toDocumentRow(document, revoked))
                }
            } catch (e: Exception) {
                Hilog.error(0, "DeferredPoll",
                    "doc " + deferred.id + " poll failed: " + e.message)
                failed.add(deferred.id)
            }
        }
        return DeferredIssuanceOutcome(issued: issued.toArray(), failed: failed.toArray())
    }

    /**
     * Mirrors iOS `DocumentTabInteractor.hasDeferredDocuments()`
     * (`!fetchDeferredDocuments().isEmpty`). Drives the deferred-issuance polling
     * decision, which previously could only be observed through the side effects
     * of requestDeferredIssuance().
     */
    public func hasDeferredDocuments(): Bool {
        return !this.fetchDeferredStorageDocuments().isEmpty()
    }

    /**
     * Mirrors iOS `DashboardInteractor.getWalletKitController()` /
     * `HomeTabInteractor.getWalletKitController()` — a passthrough of the injected
     * controller, so the injection itself is directly assertable instead of being
     * inferred from an unrelated call like fetchUsername().
     */
    public func getWalletKitController(): WalletKitController {
        return this.walletController
    }

    /** Deferred documents held by the wallet store (mirrors fetchDeferredDocuments). */
    private func fetchDeferredStorageDocuments(): Array<WalletStorageDocument> {
        try {
            return this.walletController.fetchDeferredDocuments()
        } catch (_: Exception) {
            return Array<WalletStorageDocument>()
        }
    }

    /**
     * Mirrors iOS DocumentDetailsInteractor.save(_:): bookmarks the document via
     * WalletKitController.storeBookmarkedDocument. Returns false if the store
     * throws (iOS surfaces the throw; the View wraps this blocking call in spawn{}).
     */
    public func saveBookmark(documentId: String): Bool {
        try {
            this.walletController.storeBookmarkedDocument(documentId)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Mirrors iOS DocumentDetailsInteractor.delete(_:): removes the bookmark via
     * WalletKitController.removeBookmarkedDocument. Returns false if it throws.
     */
    public func deleteBookmark(documentId: String): Bool {
        try {
            this.walletController.removeBookmarkedDocument(documentId)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Mirrors iOS TransactionDetailsInteractor.fetchTransactionDetails.
     *
     * Presentation metadata is decoded from the stored transaction envelope so
     * the card matches iOS: type, relying party, timestamp and status.
     */
    public func fetchTransactionDetails(id: String): ?TransactionDetails {
        let log = this.walletController.fetchTransactionLog(id)
        let date = DashboardInteractor.dateFromTimestamp(log.transactionLogData.timestamp)
        return Some(
            TransactionDetails(
                id: log.id,
                title: this.transactionTitle(log),
                // iOS TransactionDetailsCardData uses formattedTimestamp():
                // "dd MMM yyyy hh:mm a" in the device-local timezone.
                dateText: DateUtil.formatDate(date, "dd MMM yyyy hh:mm a"),
                transactionTypeLabel: LocalizableManager.get(LocalizableStringKey.presentation),
                relyingPartyName: log.transactionLogData.value,
                relyingPartyIsVerified: false,
                statusLabel: if (log.transactionLogData.status == "completed") {
                    LocalizableManager.get(LocalizableStringKey.completed)
                } else {
                    LocalizableManager.get(LocalizableStringKey.failed)
                },
                isCompleted: log.transactionLogData.status == "completed",
                sections: this.transactionSections(log)
            )
        )
    }

    // ── Private helpers ──────────────────────────────────────────────────

    private func collectRevoked(): HashMap<String, Bool> {
        let map = HashMap<String, Bool>()
        try {
            for (id in this.walletController.fetchRevokedDocuments()) {
                map[id] = true
            }
        } catch (_: Exception) {
            ()
        }
        return map
    }

    private func categoryFor(doc: DocClaimsDecodable, categories: DocumentCategories): DocumentCategory {
        let identifier = documentTypeIdentifier(doc)
        for (entry in categories.entries) {
            for (id in entry[1]) {
                if (id == identifier) {
                    return entry[0]
                }
            }
        }
        return DocumentCategory.other
    }

    private func toDocumentRow(doc: DocClaimsDecodable, revoked: HashMap<String, Bool>): DocumentRow {
        let isRevoked = revoked.contains(doc.id)
        let expired = hasExpired(doc)
        // Deferred (not-yet-issued) documents take precedence — mirrors iOS
        // DocumentTabUIModel.State: `self is DeferrredDocument ? .pending`, which
        // ranks above revoked/issued. Without this branch a deferred document
        // renders as a normal issued card (chevron + "Valid until"), diverging
        // from iOS which shows a "Pending" warning label + clock indicator.
        let state = if (doc is DeferredDocument) {
            DocumentRowState.pending
        } else if (isRevoked) {
            DocumentRowState.revoked
        } else if (expired) {
            DocumentRowState.expired
        } else {
            DocumentRowState.issued
        }

        // Document-list "Valid until" shows the short "dd MMM yyyy" form (iOS).
        // getExpiryDate yields validUntil already in that form, or the raw ISO
        // date_of_expiry claim for SD-JWT — normalize the latter (idempotent on the
        // already-formatted path; see fetchDocumentDetails issuer card).
        let expires: ?String = match (getExpiryDate(doc, DashboardInteractor.uiDateParser)) {
            case Some(e) where !e.isEmpty() => Some(DateUtil.localizedDateTime(e, "dd MMM yyyy"))
            case _ => None
        }
        let supporting = this.supportingText(state, expires)
        let expiryTs: Int64 = match (doc.validUntil) {
            case Some(d) => d.toUnixTimeStamp().toMilliseconds() / 1000
            case None => 0
        }
        // iOS DocumentFilterableAttributes.issuedDate = document.createdAt
        let issuedTs: Int64 = doc.createdAt.toUnixTimeStamp().toMilliseconds() / 1000

        return DocumentRow(
            id: doc.id,
            isHeader: false,
            categoryTitle: "",
            title: doc.displayName ?? "",
            issuer: issuerName(doc),
            supportingText: supporting,
            logoUrl: issuerLogo(doc) ?? "",
            state: state,
            expiryTimestamp: expiryTs,
            issuedTimestamp: issuedTs,
            usageText: usageTextFor(doc)
        )
    }

    /**
     * Trailing credential-usage badge "remaining/total" (iOS getUsageCount /
     * documentsListCredentialsUsageText). iOS builds it only while the
     * "batch issuance counter" preference is on
     * (`usageCount: isBatchCounterEnabled() ? … : nil`); deferred documents
     * show no count (isDeferred → nil); issued documents default to 1/1 when
     * the engine has not populated CredentialsUsageCounts.
     */
    private func usageTextFor(doc: DocClaimsDecodable): String {
        let enabled = match (this.prefs) {
            case Some(p) => p.getBool(PrefsKey.batchCounter)
            case None => false
        }
        if (!enabled) {
            return ""
        }
        match (doc) {
            case _: DeferredDocument => ""
            case idoc: IssuedDocument =>
                let (rem, tot) = match (idoc.credentialsUsageCounts) {
                    case Some(c) => (c.remaining, c.total)
                    case None => (Int64(1), Int64(1))
                }
                LocalizableManager.get(
                    LocalizableStringKey.documentsListCredentialsUsageText([rem.toString(), tot.toString()])
                )
            case _ => ""
        }
    }

    private func supportingText(state: DocumentRowState, expires: ?String): String {
        match (state) {
            case DocumentRowState.revoked => LocalizableManager.get(LocalizableStringKey.revoked)
            case DocumentRowState.expired => LocalizableManager.get(LocalizableStringKey.expired)
            case DocumentRowState.failed => LocalizableManager.get(LocalizableStringKey.issuanceFailed)
            case DocumentRowState.pending => LocalizableManager.get(LocalizableStringKey.pending)
            case DocumentRowState.issued =>
                match (expires) {
                    case Some(e) where !e.isEmpty() =>
                        LocalizableManager.get(LocalizableStringKey.validUntil([e])).replace("\n", "")
                    case _ => ""
                }
        }
    }

    /**
     * Flattens a document's claims into key/value rows. Recurses one level into
     * nested DocClaim children (e.g. mDoc namespaces). Mirrors the displayed
     * claim list of iOS DocumentDetailsView (skips image/portrait claims, which
     * carry no readable text).
     */
    private func flattenClaims(doc: DocClaimsDecodable): Array<ClaimRow> {
        let rows = ArrayList<ClaimRow>()
        for (claim in doc.docClaims) {
            this.appendClaim(claim, rows)
        }
        return rows.toArray()
    }

    private func appendClaim(claim: DocClaim, rows: ArrayList<ClaimRow>): Unit {
        match (claim.children) {
            case Some(children) where children.size > 0 =>
                for (child in children) {
                    this.appendClaim(child, rows)
                }
            case _ =>
                // leaf claim — skip image-only values (no readable text)
                if (!claim.stringValue.isEmpty()) {
                    rows.add(
                        ClaimRow(
                            title: claim.displayName ?? claim.name,
                            value: claim.stringValue
                        )
                    )
                }
        }
    }

    /**
     * Groups a document's claims into sections. Mirrors the iOS
     * DocumentDetailsView claim grouping: each top-level claim that has children
     * (an mDoc namespace / nested group) becomes its own section titled with the
     * group's display name; the remaining leaf claims fold into a single section
     * titled with the document display name (or "Document data").
     */
    private func claimSections(doc: DocClaimsDecodable): Array<ClaimSection> {
        let sections = ArrayList<ClaimSection>()
        let topLevel = ArrayList<ClaimRow>()
        var idx = 0
        for (claim in doc.docClaims) {
            match (claim.children) {
                case Some(children) where children.size > 0 =>
                    let rows = ArrayList<ClaimRow>()
                    for (child in children) {
                        this.appendClaim(child, rows)
                    }
                    if (rows.size > 0) {
                        sections.add(
                            ClaimSection(
                                id: "${doc.id}_grp_${idx}",
                                title: claim.displayName ?? claim.name,
                                rows: rows.toArray()
                            )
                        )
                        idx++
                    }
                case _ =>
                    if (!claim.stringValue.isEmpty()) {
                        topLevel.add(ClaimRow(title: claim.displayName ?? claim.name, value: claim.stringValue))
                    }
            }
        }
        if (topLevel.size > 0) {
            let groupTitle = doc.displayName ?? LocalizableManager.get(LocalizableStringKey.documentData)
            sections.add(ClaimSection(id: "${doc.id}_grp_main", title: groupTitle, rows: topLevel.toArray()))
        }
        return sections.toArray()
    }

    /**
     * Build the single ordered document-data list (mirrors iOS document.documentFields):
     * one flat sequence in claim order where each top-level claim is a scalar field
     * or a nested group (expandable), so scalars and groups interleave alphabetically
     * exactly like the iOS WrapExpandableListView (no separate per-group cards).
     */
    private func documentFields(doc: DocClaimsDecodable): Array<DocumentField> {
        let out = ArrayList<DocumentField>()
        var idx = 0
        for (claim in doc.docClaims) {
            match (claim.children) {
                case Some(children) where children.size > 0 =>
                    let rows = ArrayList<ClaimRow>()
                    for (child in children) { this.appendClaim(child, rows) }
                    if (rows.size > 0) {
                        // iOS renders the nested-group (namespace) header prettified
                        // ("authentic_source" → "Authentic Source"); only the leaf
                        // claim labels fall back to the raw key. Mirror that: when the
                        // group claim carries no display name, Title-case its key.
                        let groupTitle = match (claim.displayName) {
                            case Some(dn) => dn
                            case None => prettifyGroupKey(claim.name)
                        }
                        out.add(DocumentField(
                            id: "${doc.id}_f_${idx}", isGroup: true,
                            title: groupTitle, rows: rows.toArray()
                        ))
                        idx++
                    }
                case _ =>
                    if (!claim.stringValue.isEmpty()) {
                        out.add(DocumentField(
                            id: "${doc.id}_f_${idx}", isGroup: false,
                            title: claim.displayName ?? claim.name, value: claim.stringValue
                        ))
                        idx++
                    }
            }
        }
        // iOS renders the document-data list alphabetically by label (scalars
        // and nested groups interleaved in one ordered sequence); the decoded
        // claim order is issuer-dependent, so sort here for parity.
        let arr = out.toArray()
        var i = 1
        while (i < arr.size) {
            let key = arr[i]
            let keyTitle = key.title.toAsciiLower()
            var j = i - 1
            while (j >= 0 && arr[j].title.toAsciiLower() > keyTitle) {
                arr[j + 1] = arr[j]
                j--
            }
            arr[j + 1] = key
            i++
        }
        return arr
    }

    /**
     * Maps the document's credential-usage counters to the footer model.
     * Mirrors iOS: shown only while the batch-counter preference is on, and
     * defaults to 1/1 when the engine has not populated usage counts.
     */
    private func credentialUsage(doc: DocClaimsDecodable): ?CredentialUsageInfo {
        let enabled = match (this.prefs) {
            case Some(p) => p.getBool(PrefsKey.batchCounter)
            case None => false
        }
        if (!enabled) {
            return None
        }
        match (doc.credentialsUsageCounts) {
            case Some(counts) => Some(CredentialUsageInfo(remaining: counts.remaining, total: counts.total))
            case None => Some(CredentialUsageInfo(remaining: 1, total: 1))
        }
    }

    /**
     * Builds the "Data shared" sections for a transaction. The engine persists
     * only a flat value string (no structured per-document claim partition), so
     * the value is surfaced as a single "Data shared" section; an empty value
     * yields no section (mirrors iOS, which shows no list for non-presentation
     * logs).
     */
    private func transactionSections(log: TransactionLogItem): Array<ClaimSection> {
        let value = log.transactionLogData.documents
        if (value.isEmpty()) {
            return Array<ClaimSection>()
        }
        let title = LocalizableManager.get(LocalizableStringKey.dataShared)
        return [
            ClaimSection(
                id: "${log.id}_shared",
                title: title,
                rows: [ClaimRow(title: title, value: value)]
            )
        ]
    }

    private func transactionTitle(log: TransactionLogItem): String {
        let value = log.transactionLogData.value
        if (value.isEmpty()) {
            return LocalizableManager.get(LocalizableStringKey.dataShared)
        }
        return value
    }

    /**
     * Relying-party (verifier) name for a transaction. The wallet engine persists
     * only the flat TransactionLogData (timestamp + value); the presentation log's
     * value string is the relying-party display name written when the presentation
     * completed, so it is surfaced as the relying-party name (iOS
     * TransactionFilterableAttributes.relyingPartyName ← logData.relyingParty.name).
     * An empty value → None (maps to the iOS "No Relying Party" filter item).
     */
    private func relyingPartyName(log: TransactionLogItem): ?String {
        let value = log.transactionLogData.value.trimAscii()
        if (value.isEmpty()) {
            return None
        }
        return Some(value)
    }

    private func sortedInts(values: ArrayList<Int64>): ArrayList<Int64> {
        let copy = ArrayList<Int64>()
        for (v in values) { copy.add(v) }
        var i = 1
        while (i < copy.size) {
            let cur = copy[i]
            var j = i - 1
            while (j >= 0 && copy[j] > cur) {
                copy[j + 1] = copy[j]
                j--
            }
            copy[j + 1] = cur
            i++
        }
        return copy
    }

    private func sortedIntsDesc(values: ArrayList<Int64>): ArrayList<Int64> {
        let asc = this.sortedInts(values)
        let desc = ArrayList<Int64>()
        var i = asc.size - 1
        while (i >= 0) {
            desc.add(asc[i])
            i--
        }
        return desc
    }
}

// ─── Filters controller (wraps the logic-business FilterValidator engine) ────

/**
 * "GOVERNMENT" → "Government" for filter-row display (iOS filter sheet shows
 * title-cased category names while list section headers stay uppercase).
 */
func titleCaseAscii(s: String): String {
    if (s.isEmpty()) { return s }
    let lower = s.toAsciiLower()
    let head = s[0..1].toAsciiUpper()
    return head + lower[1..lower.size]
}

/** Row-backed FilterableItemPayload — carries the row id. */
class RowPayload <: FilterableItemPayload {
    private let rowId: String
    init(rowId: String) { this.rowId = rowId }
    public prop id: String { get() { this.rowId } }
}

/**
 * Row-backed FilterableAttributes — exposes the sort key (title) and the
 * search tags / a state tag (issued|expired|revoked) so the document state
 * filter predicate and the sort action both operate on real row data.
 */
class RowAttributes <: FilterableAttributes {
    private let key: String
    private let tags: Array<String>
    public let stateTag: String
    public let timestamp: Int64
    /** Issuer display name + document category — drive the iOS multi-select
     *  "Filter by issuer" / "Filter by category" groups. */
    public let issuer: String
    public let category: String
    /** Expiry epoch seconds (0 = none) for the "Expiry period" filter. */
    public let expiryTimestamp: Int64
    /** Relying-party (verifier) name — drives the iOS transaction "Filter by
     *  relying party name" group. None = "No Relying Party". */
    public let relyingPartyName: ?String
    /** Transaction-only filter attributes. Empty for document rows. */
    public let transactionStatus: String
    public let transactionType: String
    init(key: String, tags: Array<String>, stateTag: String, timestamp: Int64,
         issuer!: String = "", category!: String = "", expiryTimestamp!: Int64 = 0,
         relyingPartyName!: ?String = Option<String>.None,
         transactionStatus!: String = "", transactionType!: String = "") {
        this.key = key
        this.tags = tags
        this.stateTag = stateTag
        this.timestamp = timestamp
        this.issuer = issuer
        this.category = category
        this.expiryTimestamp = expiryTimestamp
        this.relyingPartyName = relyingPartyName
        this.transactionStatus = transactionStatus
        this.transactionType = transactionType
    }
    public prop sortingKey: String { get() { this.key } }
    public prop searchTags: Array<String> { get() { this.tags } }
    // Zero-padded epoch strings so the string-keyed SortAction orders documents
    // chronologically (Date Issued reuses `timestamp`; Expiry Date uses expiry).
    public prop issuedSortKey: String { get() { "${this.timestamp}".padStart(15, padding: "0") } }
    public prop expirySortKey: String { get() { "${this.expiryTimestamp}".padStart(15, padding: "0") } }
}

/**
 * Mirrors the iOS DocumentTabViewModel / TransactionTabViewModel filter plumbing:
 * builds the default Filters, wires the logic-business FilterValidator engine,
 * and maps the engine's FilterableList back to render-ready rows. The controller
 * keeps the engine's emitted snapshot so the FiltersListView can render the
 * in-progress (not-yet-applied) selections, exactly like iOS where the sheet
 * shows the snapshot until "Show Results" is tapped.
 */
public class DashboardFilterController {
    private let validator: FilterValidatorImpl
    private let isTransaction: Bool
    // Maps row id → the full row so the filtered FilterableList can be re-expanded.
    private let docRowsById: HashMap<String, DocumentRow>
    private let txRowsById: HashMap<String, TransactionRow>
    // Transaction bounds change whenever a newly completed presentation is
    // appended. Keep them mutable so the default date range follows the live
    // History source instead of remaining pinned to the newest row that existed
    // when the dashboard view model was first created.
    private var minDate: DateTime
    private var maxDate: DateTime
    /** True only when the holder selected a narrower range themselves. */
    private var dateRangeCustomized: Bool = false

    // Latest engine emissions.
    private var snapshotFilters: Filters
    private var appliedFilteredIds: ArrayList<String>
    // Set when the engine signals completion (iOS `.cancelled` + stream finish).
    private var cancelledFlag: Bool = false
    private var terminated: Bool = false

    private init(
        validator: FilterValidatorImpl,
        isTransaction: Bool,
        docRowsById: HashMap<String, DocumentRow>,
        txRowsById: HashMap<String, TransactionRow>,
        defaults: Filters,
        minDate: DateTime,
        maxDate: DateTime
    ) {
        this.validator = validator
        this.isTransaction = isTransaction
        this.docRowsById = docRowsById
        this.txRowsById = txRowsById
        this.minDate = minDate
        this.maxDate = maxDate
        this.snapshotFilters = defaults
        this.appliedFilteredIds = ArrayList<String>()

        this.validator.setFilterResultListener({ state => this.onEngine(state) })
        // Prime the applied result so the list is filtered from the start.
        this.validator.applyFilters(if (this.isTransaction) {
            SortOrderType.descending
        } else {
            SortOrderType.ascending
        })
    }

    private func onEngine(state: FilterResultPartialState): Unit {
        // iOS finishes the AsyncStream on `.completion`, after which yields are
        // dropped and the consumer's `for await` ends. A finished stream cannot
        // deliver more values, so emissions arriving after termination are
        // ignored here rather than mutating state behind the consumer's back.
        if (this.terminated) {
            return
        }
        match (state) {
            case FilterResultPartialState.success(result) =>
                match (result) {
                    case FilterResult.filterApplyResult(list, snap, _) =>
                        this.snapshotFilters = snap
                        let ids = ArrayList<String>()
                        for (item in list.items) {
                            ids.add(item.payload.id)
                        }
                        this.appliedFilteredIds = ids
                    case FilterResult.filterUpdateResult(snap) =>
                        this.snapshotFilters = snap
                }
            case FilterResultPartialState.completion =>
                // iOS: `case .completion: continuation.yield(.cancelled); continuation.finish()`.
                // There is no stream to yield into here, so the cancellation is
                // recorded as terminal state the caller can read instead.
                this.terminated = true
                this.cancelledFlag = true
        }
    }

    /**
     * True once the filter engine signalled completion — the equivalent of iOS
     * emitting `.cancelled` and finishing the stream. The controller is terminal
     * afterwards: it accepts no further engine emissions, and the last observed
     * filters/ids stay frozen at their values from the moment of cancellation.
     */
    public prop isCancelled: Bool {
        get() { this.cancelledFlag }
    }

    /**
     * Tears the controller down, mirroring iOS `deinit { filtersStateAsync?.finish() }`
     * plus the validator's stream completion. Idempotent: the engine drops its
     * listener on the first call, so a second call cannot re-emit.
     */
    public func complete(): Unit {
        this.validator.complete()
    }

    public prop dateRangeMin: DateTime { get() { this.minDate } }
    public prop dateRangeMax: DateTime { get() { this.maxDate } }

    /**
     * Bounds exposed to the two calendar pickers. iOS FiltersListView falls back
     * to one year either side of today when explicit limits are absent. Keep that
     * usable window here while still retaining transactions outside it.
     */
    public prop calendarRangeMin: DateTime {
        get() {
            let fallback = DateTime.now().addDays(-365)
            return if (this.minDate.toUnixTimeStamp().toMilliseconds() <
                fallback.toUnixTimeStamp().toMilliseconds()) { this.minDate } else { fallback }
        }
    }

    public prop calendarRangeMax: DateTime {
        get() {
            let fallback = DateTime.now().addDays(365)
            return if (this.maxDate.toUnixTimeStamp().toMilliseconds() >
                fallback.toUnixTimeStamp().toMilliseconds()) { this.maxDate } else { fallback }
        }
    }

    /** UI sections built from the current (snapshot) filters — mirrors iOS filterUIModel. */
    public func sections(): Array<FilterUISection> {
        let out = ArrayList<FilterUISection>()
        // iOS renders ONLY filterGroups (screen-recording verified: the sheet
        // has Expiry Period / Issuer / Category / State — NO "Sort by" section;
        // FilterSort exists in the model but is never presented).
        for (group in this.snapshotFilters.filterGroups) {
            // iOS excludes the Ascending/Descending (orderBy) group from the
            // sheet (FiltersListView filters it out); render parity.
            let isOrderBy = match (group.filterType) {
                case FilterGroupType.orderBy => true
                case _ => false
            }
            if (isOrderBy) {
                continue
            }
            let items = ArrayList<FilterUIItem>()
            for (f in group.filters) {
                let sectionType = match (f.filterElementType) {
                    case FilterElementType.datePicker => FilterUISectionType.datePicker
                    case FilterElementType.radio => FilterUISectionType.radio
                }
                items.add(
                    FilterUIItem(
                        id: f.id,
                        title: f.name,
                        selected: f.selected,
                        sectionType: sectionType,
                        startDate: f.startDate,
                        endDate: f.endDate
                    )
                )
            }
            out.add(FilterUISection(id: group.id, sectionTitle: group.name, filters: items.toArray()))
        }
        return out.toArray()
    }

    public func updateFilter(sectionId: String, filterId: String): Unit {
        this.validator.updateFilter(sectionId, filterId)
    }

    /** Select a sort option in the dedicated FilterSort (Default/Date Issued/Expiry). */
    public func updateSort(filterId: String): Unit {
        this.validator.updateSort(filterId)
    }

    public func updateDateFilters(sectionId: String, filterId: String, start: DateTime, end: DateTime): Unit {
        if (this.isTransaction &&
            sectionId == FilterIds.FILTER_BY_TRANSACTION_DATE_GROUP_ID &&
            filterId == FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE) {
            // Choosing the full current range is equivalent to the default. This
            // also lets "Reset dates" resume following future transactions.
            let startMs = start.toUnixTimeStamp().toMilliseconds()
            let endMs = end.toUnixTimeStamp().toMilliseconds()
            // Treat any range covering the whole current source as the default.
            // This also avoids comparing two separately-created DateTime.now()
            // fallback values that can differ by a few milliseconds.
            let coversSourceRange =
                startMs <= this.minDate.toUnixTimeStamp().toMilliseconds() &&
                endMs >= this.maxDate.toUnixTimeStamp().toMilliseconds()
            this.dateRangeCustomized = !coversSourceRange
        }
        this.validator.updateDateFilters(sectionId, filterId, start, end)
    }

    public func applyFilters(): Unit {
        this.validator.applyFilters(if (this.isTransaction) {
            SortOrderType.descending
        } else {
            SortOrderType.ascending
        })
    }

    public func resetFilters(): Unit {
        this.validator.resetFilters()
        if (this.isTransaction) {
            // FilterValidator's immutable initial snapshot contains the bounds
            // from controller creation. Re-apply the current live bounds after
            // reset so Reset cannot bring the stale upper limit back.
            this.dateRangeCustomized = false
            this.validator.updateDateFilters(
                FilterIds.FILTER_BY_TRANSACTION_DATE_GROUP_ID,
                FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE,
                this.minDate,
                this.maxDate
            )
            this.validator.applyFilters(SortOrderType.descending)
        }
    }

    public func revertFilters(): Unit {
        this.validator.revertFilters()
    }

    public func applySearch(query: String): Unit {
        this.validator.applySearch(query)
    }

    /**
     * Swaps the source list the engine filters over, mirroring iOS
     * `FilterValidator.updateLists(sortOrder:filterableList:)` as called from
     * `DocumentTabInteractor.updateLists(filterableList:)`.
     *
     * Filter selections are deliberately preserved — a document refetch must not
     * reset the user's open filter sheet. Like iOS this only replaces the list;
     * the caller calls `applyFilters()` afterwards to re-emit a filtered result.
     * The dynamic issuer/category groups are NOT rebuilt here (iOS keeps that in
     * `addDynamicFilters`), so a brand-new issuer stays unfiltered until then.
     */
    public func updateLists(rows: Array<DocumentRow>): Unit {
        this.docRowsById.clear()
        let items = ArrayList<FilterableItem>()
        var currentCategory = ""
        for (row in rows) {
            if (row.isHeader) {
                currentCategory = row.categoryTitle
                continue
            }
            this.docRowsById[row.id] = row
            items.add(DashboardFilterController.documentItem(row, currentCategory))
        }
        this.validator.updateLists(SortOrderType.ascending, FilterableList(items.toArray()))
    }

    /** Transaction-tab counterpart of `updateLists(rows:)`; `timestamps` maps row id → epoch seconds. */
    public func updateLists(rows: Array<TransactionRow>, timestamps: HashMap<String, Int64>): Unit {
        this.txRowsById.clear()
        let items = ArrayList<FilterableItem>()
        var nextMinSeconds: ?Int64 = None
        var nextMaxSeconds: ?Int64 = None
        for (row in rows) {
            if (row.isHeader) {
                continue
            }
            this.txRowsById[row.id] = row
            let ts = if (timestamps.contains(row.id)) { timestamps[row.id] } else { 0 }
            if (ts > 0) {
                match (nextMinSeconds) {
                    case Some(v) => if (ts < v) { nextMinSeconds = Some(ts) }
                    case None => nextMinSeconds = Some(ts)
                }
                match (nextMaxSeconds) {
                    case Some(v) => if (ts > v) { nextMaxSeconds = Some(ts) }
                    case None => nextMaxSeconds = Some(ts)
                }
            }
            items.add(DashboardFilterController.transactionItem(row, ts))
        }
        this.validator.updateLists(SortOrderType.descending, FilterableList(items.toArray()))

        match ((nextMinSeconds, nextMaxSeconds)) {
            case (Some(minSeconds), Some(maxSeconds)) =>
                let nextMin = DateTime.fromUnixTimeStamp(Duration.second * minSeconds).inLocal()
                // Match iOS getLatestTransactionDate(): leave one minute of
                // headroom so the newest row cannot be clipped by picker precision.
                let nextMax = DateTime.fromUnixTimeStamp(Duration.second * (maxSeconds + 60)).inLocal()
                if (!this.dateRangeCustomized) {
                    // The date filter is selected by default, so merely replacing
                    // the source list would still reject rows newer than the old
                    // maxDate. Move the default range before the caller applies.
                    this.validator.updateDateFilters(
                        FilterIds.FILTER_BY_TRANSACTION_DATE_GROUP_ID,
                        FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE,
                        nextMin,
                        nextMax
                    )
                }
                this.minDate = nextMin
                this.maxDate = nextMax
            case _ => ()
        }
    }

    /** Shared by `forDocuments` and `updateLists` so both build identical attributes. */
    private static func documentItem(row: DocumentRow, category: String): FilterableItem {
        let stateTag = match (row.state) {
            case DocumentRowState.revoked => "revoked"
            case DocumentRowState.expired => "expired"
            case _ => "issued"
        }
        return FilterableItem(
            RowPayload(row.id),
            RowAttributes(row.title, [row.title, row.issuer], stateTag, row.issuedTimestamp,
                issuer: row.issuer, category: category, expiryTimestamp: row.expiryTimestamp)
        )
    }

    /** Shared by `forTransactions` and `updateLists`. */
    private static func transactionItem(row: TransactionRow, timestamp: Int64): FilterableItem {
        return FilterableItem(
            RowPayload(row.id),
            RowAttributes(
                row.dateText,
                [row.title],
                "issued",
                timestamp,
                relyingPartyName: row.relyingPartyName,
                transactionStatus: if (row.isCompleted) { "completed" } else { "failed" },
                // Like iOS, the current history source exposes presentation logs.
                transactionType: "presentation"
            )
        )
    }

    /** Re-expands the engine's filtered id set into the original grouped rows (headers re-added). */
    public func filteredDocumentRows(allGrouped: Array<DocumentRow>): Array<DocumentRow> {
        let keep = HashMap<String, Bool>()
        for (id in this.appliedFilteredIds) { keep[id] = true }
        return DashboardFilterController.reGroupDocuments(allGrouped, keep)
    }

    public func filteredTransactionRows(allGrouped: Array<TransactionRow>): Array<TransactionRow> {
        let keep = HashMap<String, Bool>()
        for (id in this.appliedFilteredIds) { keep[id] = true }
        return DashboardFilterController.reGroupTransactions(allGrouped, keep)
    }

    private static func reGroupDocuments(all: Array<DocumentRow>, keep: HashMap<String, Bool>): Array<DocumentRow> {
        let out = ArrayList<DocumentRow>()
        var pendingHeader: ?DocumentRow = Option<DocumentRow>.None
        var any = false
        for (row in all) {
            if (row.isHeader) {
                pendingHeader = Some(row)
                any = false
            } else if (keep.contains(row.id)) {
                match (pendingHeader) {
                    case Some(h) where !any =>
                        out.add(h)
                        any = true
                    case _ => ()
                }
                out.add(row)
            }
        }
        return out.toArray()
    }

    private static func reGroupTransactions(all: Array<TransactionRow>, keep: HashMap<String, Bool>): Array<TransactionRow> {
        let out = ArrayList<TransactionRow>()
        var pendingHeader: ?TransactionRow = Option<TransactionRow>.None
        var any = false
        for (row in all) {
            if (row.isHeader) {
                pendingHeader = Some(row)
                any = false
            } else if (keep.contains(row.id)) {
                match (pendingHeader) {
                    case Some(h) where !any =>
                        out.add(h)
                        any = true
                    case _ => ()
                }
                out.add(row)
            }
        }
        return out.toArray()
    }

    /** Sort a string list ascending (case-sensitive, mirrors iOS `sorted { $0 < $1 }`). */
    private static func sortedStrings(values: ArrayList<String>): Array<String> {
        let arr = values.toArray()
        sort<String>(arr, lessThan: { a, b => a < b }, stable: true)
        return arr
    }

    // ── Factories (mirror the iOS default Filters per tab) ────────────────────

    /**
     * Document tab filters (mirrors DocumentTabViewModel default filters):
     *  - Sort group: order by name (ascending default / descending).
     *  - State group: Valid / Expired / Revoked (single selection; none = all).
     */
    public static func forDocuments(rows: Array<DocumentRow>): DashboardFilterController {
        let byId = HashMap<String, DocumentRow>()
        let items = ArrayList<FilterableItem>()
        // Distinct issuers / categories drive the dynamic multi-select groups.
        let issuerSeen = HashMap<String, Bool>()
        let issuerOrder = ArrayList<String>()
        let categorySeen = HashMap<String, Bool>()
        let categoryOrder = ArrayList<String>()
        var currentCategory = ""
        for (row in rows) {
            if (row.isHeader) {
                currentCategory = row.categoryTitle
                if (!currentCategory.isEmpty() && !categorySeen.contains(currentCategory)) {
                    categorySeen[currentCategory] = true
                    categoryOrder.add(currentCategory)
                }
                continue
            }
            byId[row.id] = row
            let iss = row.issuer
            if (!iss.isEmpty() && !issuerSeen.contains(iss)) {
                issuerSeen[iss] = true
                issuerOrder.add(iss)
            }
            items.add(DashboardFilterController.documentItem(row, currentCategory))
        }
        let list = FilterableList(items.toArray())
        // "now" captured once for the expiry-period predicates (epoch seconds).
        let nowTs: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds() / 1000
        let day: Int64 = 86400

        // 1. Sort (dedicated FilterSort, single-select): Default (name) / Date Issued
        //    / Expiry Date — mirrors iOS DocumentTabInteractor FilterSort (the
        //    Ascending/Descending pair is the transaction-tab sort, not documents).
        let docSort = FilterSort(
            id: FilterIds.FILTER_SORT_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.sortBy),
            filters: [
                FilterItem(
                    id: FilterIds.FILTER_SORT_DEFAULT,
                    name: LocalizableManager.get(LocalizableStringKey.defaultLabel),
                    selected: true,
                    isDefault: true,
                    filterableAction: SortAction(keySelector: { a => Some(a.sortingKey) })
                ),
                FilterItem(
                    id: FilterIds.FILTER_SORT_DATE_ISSUED,
                    name: LocalizableManager.get(LocalizableStringKey.dateIssued),
                    selected: false,
                    filterableAction: SortAction(keySelector: { a => match (a as RowAttributes) { case Some(r) => Some(r.issuedSortKey); case None => None } })
                ),
                FilterItem(
                    id: FilterIds.FILTER_SORT_EXPIRY_DATE,
                    name: LocalizableManager.get(LocalizableStringKey.expiryDate),
                    selected: false,
                    filterableAction: SortAction(keySelector: { a => match (a as RowAttributes) { case Some(r) => Some(r.expirySortKey); case None => None } })
                )
            ]
        )

        // 2. State (multiple): Valid (default selected) / Expired / Revoked.
        let statePredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) =>
                    if (filter.id == FilterIds.FILTER_BY_STATE_VALID) {
                        r.stateTag == "issued"
                    } else if (filter.id == FilterIds.FILTER_BY_STATE_EXPIRED) {
                        r.stateTag == "expired"
                    } else if (filter.id == FilterIds.FILTER_BY_STATE_REVOKED) {
                        r.stateTag == "revoked"
                    } else {
                        false
                    }
                case None => false
            }
        }
        let stateGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_STATE_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByState),
            filters: [
                FilterItem(id: FilterIds.FILTER_BY_STATE_VALID, name: LocalizableManager.get(LocalizableStringKey.valid), selected: true, isDefault: true),
                FilterItem(id: FilterIds.FILTER_BY_STATE_EXPIRED, name: LocalizableManager.get(LocalizableStringKey.expired), selected: false),
                FilterItem(id: FilterIds.FILTER_BY_STATE_REVOKED, name: LocalizableManager.get(LocalizableStringKey.revoked), selected: false)
            ],
            filterableAction: FilterMultipleAction(predicate: statePredicate),
            filterType: FilterGroupType.other
        )

        // 3. Issuer (multiple, dynamic; all selected by default = show all).
        let issuerPredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) => r.issuer == filter.name
                case None => false
            }
        }
        let issuerItems = ArrayList<FilterItem>()
        for (iss in issuerOrder) {
            issuerItems.add(FilterItem(id: iss, name: iss, selected: true))
        }
        let issuerGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_ISSUER_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByIssuer),
            filters: issuerItems.toArray(),
            filterableAction: FilterMultipleAction(predicate: issuerPredicate),
            filterType: FilterGroupType.issuer
        )

        // 4. Category (multiple, dynamic; all selected by default).
        let categoryPredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) => r.category == filter.id
                case None => false
            }
        }
        let categoryItems = ArrayList<FilterItem>()
        for (cat in categoryOrder) {
            // Display title-cased ("Government"/"Other" — iOS filter sheet,
            // recording frames2/f012); the list section header stays uppercase.
            categoryItems.add(FilterItem(id: cat, name: titleCaseAscii(cat), selected: true))
        }
        let categoryGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_DOCUMENT_CATEGORY_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByCategory),
            filters: categoryItems.toArray(),
            filterableAction: FilterMultipleAction(predicate: categoryPredicate),
            filterType: FilterGroupType.documentCategory
        )

        // 5. Expiry period (single): Default / Next 7 / Next 30 / Beyond 30 / Before today.
        let periodPredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) =>
                    let ts = r.expiryTimestamp
                    if (filter.id == FilterIds.FILTER_BY_PERIOD_DEFAULT) {
                        true
                    } else if (filter.id == FilterIds.FILTER_BY_PERIOD_NEXT_7) {
                        ts > nowTs && ts <= nowTs + (7 * day)
                    } else if (filter.id == FilterIds.FILTER_BY_PERIOD_NEXT_30) {
                        ts > nowTs && ts <= nowTs + (30 * day)
                    } else if (filter.id == FilterIds.FILTER_BY_PERIOD_BEYOND_30) {
                        ts > nowTs + (30 * day)
                    } else if (filter.id == FilterIds.FILTER_BY_PERIOD_EXPIRED) {
                        ts > 0 && ts < nowTs
                    } else {
                        true
                    }
                case None => true
            }
        }
        let periodGroup = SingleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_PERIOD_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.selectExpiryPeriod),
            filters: [
                FilterItem(id: FilterIds.FILTER_BY_PERIOD_DEFAULT, name: LocalizableManager.get(LocalizableStringKey.defaultLabel), selected: true, isDefault: true, filterableAction: Filter(predicate: periodPredicate)),
                FilterItem(id: FilterIds.FILTER_BY_PERIOD_NEXT_7, name: LocalizableManager.get(LocalizableStringKey.nextSevenDays), selected: false, filterableAction: Filter(predicate: periodPredicate)),
                FilterItem(id: FilterIds.FILTER_BY_PERIOD_NEXT_30, name: LocalizableManager.get(LocalizableStringKey.nextThirtyDays), selected: false, filterableAction: Filter(predicate: periodPredicate)),
                FilterItem(id: FilterIds.FILTER_BY_PERIOD_BEYOND_30, name: LocalizableManager.get(LocalizableStringKey.beyondThiryDays), selected: false, filterableAction: Filter(predicate: periodPredicate)),
                FilterItem(id: FilterIds.FILTER_BY_PERIOD_EXPIRED, name: LocalizableManager.get(LocalizableStringKey.beforeToday), selected: false, filterableAction: Filter(predicate: periodPredicate))
            ],
            filterType: FilterGroupType.other
        )

        let defaults = Filters(
            filterGroups: [periodGroup, issuerGroup, categoryGroup, stateGroup],
            sortOrder: SortOrderType.ascending,
            sort: docSort
        )
        let validator = FilterValidatorImpl(
            filters: defaults,
            initialFilters: defaults,
            initialList: list
        )
        validator.initializeValidator(defaults, list)
        let now = DateTime.now()
        return DashboardFilterController(validator, false, byId, HashMap<String, TransactionRow>(), defaults, now, now)
    }

    /**
     * Transaction tab filters (mirrors TransactionTabViewModel default filters):
     *  - Sort group: Newest / Oldest (date order).
     *  - Date-range group: a single date-range item with start/end DatePicker,
     *    clamped to the wallet's min/max transaction dates.
     */
    public static func forTransactions(
        rows: Array<TransactionRow>,
        timestamps: HashMap<String, Int64>,
        minDate: DateTime,
        maxDate: DateTime
    ): DashboardFilterController {
        let byId = HashMap<String, TransactionRow>()
        let items = ArrayList<FilterableItem>()
        // Distinct relying-party names drive the dynamic multi-select group
        // (mirrors iOS addRelyingPartyName); preserve first-seen order, sorted below.
        let rpSeen = HashMap<String, Bool>()
        let rpOrder = ArrayList<String>()
        for (row in rows) {
            if (row.isHeader) { continue }
            byId[row.id] = row
            let ts = if (timestamps.contains(row.id)) { timestamps[row.id] } else { 0 }
            match (row.relyingPartyName) {
                case Some(name) where !name.isEmpty() =>
                    if (!rpSeen.contains(name)) {
                        rpSeen[name] = true
                        rpOrder.add(name)
                    }
                case _ => ()
            }
            items.add(DashboardFilterController.transactionItem(row, ts))
        }
        let list = FilterableList(items.toArray())

        let transactionDateSort = SortAction(keySelector: { a =>
            match (a as RowAttributes) {
                case Some(r) => Some(r.issuedSortKey)
                case None => Option<String>.None
            }
        })

        // This drives sortOrder but sections() deliberately keeps it off-screen,
        // matching iOS filterUISection.
        let sortGroup = SingleSelectionFilterGroup(
            id: FilterIds.ASCENDING_DESCENDING_GROUP,
            name: LocalizableManager.get(LocalizableStringKey.orderBy),
            filters: [
                FilterItem(
                    id: FilterIds.ORDER_BY_ASCENDING,
                    name: LocalizableManager.get(LocalizableStringKey.ascending),
                    selected: false,
                    filterableAction: transactionDateSort
                ),
                FilterItem(
                    id: FilterIds.ORDER_BY_DESCENDING,
                    name: LocalizableManager.get(LocalizableStringKey.descending),
                    selected: true,
                    isDefault: true,
                    filterableAction: transactionDateSort
                )
            ],
            filterType: FilterGroupType.orderBy
        )

        let datePredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match ((attrs as RowAttributes, filter.startDate, filter.endDate)) {
                case (Some(r), Some(s), Some(e)) =>
                    let date = DateTime.fromUnixTimeStamp(Duration.second * r.timestamp).inLocal()
                    DateUtil.isBetween(date, Some(s), Some(e)) ?? true
                case _ => true
            }
        }
        let dateGroup = SingleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_TRANSACTION_DATE_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByDate),
            filters: [
                FilterItem(
                    id: FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE,
                    name: LocalizableManager.get(LocalizableStringKey.filterByDate),
                    selected: true,
                    isDefault: true,
                    startDate: Some(minDate),
                    endDate: Some(maxDate),
                    filterElementType: FilterElementType.datePicker,
                    filterableAction: Filter(predicate: datePredicate)
                )
            ],
            filterType: FilterGroupType.dateRange
        )

        let statusPredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) =>
                    if (filter.id == FilterIds.FILTER_BY_STATUS_COMPLETED) {
                        r.transactionStatus == "completed"
                    } else if (filter.id == FilterIds.FILTER_BY_STATUS_FAILED) {
                        r.transactionStatus == "failed"
                    } else {
                        true
                    }
                case None => false
            }
        }
        let statusGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_STATUS_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByStatus),
            filters: [
                FilterItem(id: FilterIds.FILTER_BY_STATUS_COMPLETED,
                    name: LocalizableManager.get(LocalizableStringKey.completed),
                    selected: true, isDefault: true),
                FilterItem(id: FilterIds.FILTER_BY_STATUS_FAILED,
                    name: LocalizableManager.get(LocalizableStringKey.failed),
                    selected: true, isDefault: true)
            ],
            filterableAction: FilterMultipleAction(predicate: statusPredicate),
            filterType: FilterGroupType.other
        )

        // Relying-party name (multiple, dynamic). Mirrors iOS addRelyingPartyName:
        // a "No Relying Party" item (matches transactions with no name) plus one
        // item per distinct relying-party name, sorted alphabetically; all selected
        // by default (= show all).
        let relyingPartyPredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) =>
                    if (filter.id == FilterIds.FILTER_BY_RELYING_PARTY_NONE) {
                        // "No Relying Party" matches rows without a name.
                        match (r.relyingPartyName) {
                            case Some(n) => n.isEmpty()
                            case None => true
                        }
                    } else {
                        match (r.relyingPartyName) {
                            case Some(n) => n == filter.name
                            case None => false
                        }
                    }
                case None => false
            }
        }
        let sortedRpNames = DashboardFilterController.sortedStrings(rpOrder)
        let relyingPartyItems = ArrayList<FilterItem>()
        relyingPartyItems.add(
            FilterItem(
                id: FilterIds.FILTER_BY_RELYING_PARTY_NONE,
                name: LocalizableManager.get(LocalizableStringKey.withoutRelyingName),
                selected: true,
                isDefault: true
            )
        )
        for (name in sortedRpNames) {
            relyingPartyItems.add(FilterItem(id: name, name: name, selected: true, isDefault: true))
        }
        let relyingPartyGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_RELYING_PARY_NAME,
            name: LocalizableManager.get(LocalizableStringKey.relyingParty),
            filters: relyingPartyItems.toArray(),
            filterableAction: FilterMultipleAction(predicate: relyingPartyPredicate),
            filterType: FilterGroupType.relyingParty
        )

        let typePredicate: (FilterableAttributes, FilterItem) -> Bool = { attrs, filter =>
            match (attrs as RowAttributes) {
                case Some(r) => r.transactionType == filter.id
                case None => false
            }
        }
        let typeGroup = MultipleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_TYPE_ID,
            name: LocalizableManager.get(LocalizableStringKey.filterByType),
            filters: [
                FilterItem(id: FilterIds.FILTER_BY_TYPE_PRESENTATION,
                    name: LocalizableManager.get(LocalizableStringKey.presentation),
                    selected: true, isDefault: true),
                FilterItem(id: FilterIds.FILTER_BY_TYPE_ISSUANCE,
                    name: LocalizableManager.get(LocalizableStringKey.issuance),
                    selected: true, isDefault: true),
                FilterItem(id: FilterIds.FILTER_BY_TYPE_SIGNING,
                    name: LocalizableManager.get(LocalizableStringKey.signing),
                    selected: true, isDefault: true)
            ],
            filterableAction: FilterMultipleAction(predicate: typePredicate),
            filterType: FilterGroupType.other
        )

        let transactionSort = FilterSort(
            id: FilterIds.FILTER_SORT_GROUP_ID,
            name: LocalizableManager.get(LocalizableStringKey.sortBy),
            filters: [
                FilterItem(
                    id: FilterIds.FILTER_SORT_DEFAULT,
                    name: LocalizableManager.get(LocalizableStringKey.transactionDate),
                    selected: true,
                    isDefault: true,
                    filterableAction: transactionDateSort
                )
            ]
        )

        let defaults = Filters(
            filterGroups: [sortGroup, dateGroup, statusGroup, relyingPartyGroup, typeGroup],
            sortOrder: SortOrderType.descending,
            sort: Some(transactionSort)
        )
        let validator = FilterValidatorImpl(
            filters: defaults,
            initialFilters: defaults,
            initialList: list
        )
        validator.initializeValidator(defaults, list)
        return DashboardFilterController(validator, true, HashMap<String, DocumentRow>(), byId, defaults, minDate, maxDate)
    }
}
