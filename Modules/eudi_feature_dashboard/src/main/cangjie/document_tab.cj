/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (Tab/Document/DocumentTabView.swift) to Cangjie.
 *
 * Renders the real issued-document list (grouped by category) fetched via the
 * DashboardInteractor → WalletKitController.fetchAllDocuments(). When the wallet
 * has no documents it shows the authentic empty state plus an "Add document"
 * button (push the no-document issuance flow).
 *
 * Loader gating (the cause of the original "stuck dot" on the Documents tab):
 * the view owns its OWN `isLoading` @State that starts true and is flipped to
 * false as soon as the blocking fetch returns — so the empty state always
 * renders for a new wallet instead of waiting on a never-cleared global flag.
 * The blocking fetch runs in spawn{}; the @State writeback is marshalled with
 * spawn(UIThread) (S-001).
 */
package eudi_feature_dashboard

import std.collection.HashMap
import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.time.*
import std.collection.ArrayList
import kit.PerformanceAnalysisKit.Hilog
import eudi_logic_ui.{
    ContentUnavailableView, uiColor, uiFontSize,
    SPACING_NONE, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, ContentLoaderView, AppIcon, appImageSrc,
    AlertView, AlertAction, EUDI_SCRIM_COLOR
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_logic_core.{NotificationCenter, NotificationName}

/**
 * Documents Tab view: real list + empty state + Add Document entry point.
 * Mounted as TabContent content inside DashboardView; receives the shared
 * DashboardViewModel so it can both load documents and push routes.
 */
@Component
public class DocumentTabView {
    public var viewModel: ?DashboardViewModel = Option<DashboardViewModel>.None

    @State
    var rows: Array<DocumentRow> = Array<DocumentRow>()
    @State
    var isLoading: Bool = true
    /** Whether the wallet has ANY documents (drives the search/sort bar). */
    @State
    var hasAnyDocuments: Bool = false
    /** Live search query (mirrors iOS DocumentTabViewModel applySearch). */
    @State
    var searchQuery: String = ""
    /** Sort direction (mirrors iOS default name sort; true = ascending). */
    @State
    var sortAscending: Bool = true
    /** Deferred/failed-document delete confirmation (mirrors iOS onDeleteDeferredDocument). */
    @State
    var showDeleteDeferredDialog: Bool = false
    /** Id + title of the deferred document pending deletion (populated on row tap). */
    @State
    var pendingDeleteId: String = ""
    @State
    var pendingDeleteTitle: String = ""
    /** Deferred ids whose re-issuance failed (iOS failedDocuments) — rows render "Issuance failed". */
    @State
    var failedIds: Array<String> = Array<String>()

    /** True while a 5s deferred-issuance poll round is in flight (iOS deferredTask). */
    private var pollActive: Bool = false
    /** Bumped on disappear to cancel in-flight polls (iOS deferredTask?.cancel()). */
    private var pollGeneration: Int64 = 0
    /**
     * Latest poll outcome awaiting UI application. spawn(UIThread) does NOT fire
     * from a slept background thread (PIN-lockout precedent), so the poll thread
     * parks its result here and posts DocumentTabRefresh; reload()'s (verified)
     * UI-thread callback consumes it.
     */
    private var lastOutcome: ?DeferredIssuanceOutcome = None

    /** Guards against double-registration if aboutToAppear fires more than once. */
    private var observerRegistered: Bool = false

    protected override func aboutToAppear(): Unit {
        this.reload()
        // Reload when any issuance/revocation/re-issuance op changes the document
        // store (mirrors iOS DocumentTabViewModel observing DocumentTabRefresh).
        // Without this the tab keeps the empty rows captured on first mount and a
        // freshly-issued credential never appears until the app is relaunched.
        if (!this.observerRegistered) {
            this.observerRegistered = true
            NotificationCenter.addObserver(NotificationName.DocumentTabRefresh, { _ => this.reload() })
            // The filter button now lives in the Dashboard's shared nav bar; it
            // posts DocumentOpenFilters so this tab (which owns the overlay) opens it.
        }
    }

    protected override func aboutToDisappear(): Unit {
        // Cancel any in-flight deferred poll (iOS onDisappear → deferredTask?.cancel()).
        this.pollGeneration = this.pollGeneration + 1
        this.pollActive = false
    }

    /**
     * Re-fetches the rows applying the current search query + the FilterValidator
     * engine selections (mirrors DocumentTabViewModel.fetch + applySearch). The
     * VM builds/refreshes the filter controller from the real wallet documents.
     */
    private func reload(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                let q = this.searchQuery
                spawn {
                    =>
                    let loaded = model.loadDocumentRowsApplyingFilters(q)
                    // hasAnyDocuments must reflect the unfiltered wallet so the
                    // search bar stays visible while a query yields no matches.
                    let total = model.loadDocumentRows()
                    let hasAny = total.size > 0
                    spawn(UIThread) {
                        =>
                        // Consume a parked poll outcome first so the failed
                        // override below sees the fresh failed ids.
                        match (this.lastOutcome) {
                            case Some(outcome) =>
                                this.lastOutcome = None
                                if (outcome.failed.size > 0) {
                                    let merged = ArrayList<String>()
                                    for (f in this.failedIds) { merged.add(f) }
                                    for (f in outcome.failed) {
                                        var seen = false
                                        for (m in merged) { if (m == f) { seen = true } }
                                        if (!seen) { merged.add(f) }
                                    }
                                    this.failedIds = merged.toArray()
                                }
                                if (outcome.issued.size > 0) {
                                    // The "Documents issued" sheet lives at the
                                    // dashboard layer (above the tab bar).
                                    DashboardOverlayData.shared.issuedRows = outcome.issued
                                    this.showDeleteDeferredDialog = false
                                    NotificationCenter.post(NotificationName.DeferredDocsIssued)
                                }
                            case None => ()
                        }
                        // Annotate card edges on the snapshot before publishing
                        // to @State — ForEach must not re-index this.rows by idx
                        // during render (see DocumentRow.isCardTop).
                        this.rows = this.annotateCardGeometry(this.applyFailedOverride(loaded))
                        this.hasAnyDocuments = hasAny
                        this.isLoading = false
                        // Report the row count up so the shared nav bar can
                        // enable/gray its trailing filter (iOS disabled:isEmpty).
                        let m = HashMap<String, String>()
                        m.add("key", "doc")
                        m.add("value", if (hasAny) { "true" } else { "false" })
                        NotificationCenter.postMap(NotificationName.DashboardToolbarSync, m)
                        // iOS onDocumentsRetrievedPostActions: re-arm the 5s
                        // deferred poll after every fetch while deferred docs remain.
                        this.armDeferredPoll()
                    }
                }
            case None =>
                // standalone/preview: nothing to load, show empty state.
                this.isLoading = false
        }
    }

    /**
     * Re-labels rows whose deferred re-issuance failed (iOS failedDocuments
     * ranks above the DeferrredDocument type check): pending → failed with the
     * "Issuance failed" supporting text.
     */
    private func applyFailedOverride(rows: Array<DocumentRow>): Array<DocumentRow> {
        if (this.failedIds.size == 0) {
            return rows
        }
        let out = ArrayList<DocumentRow>()
        for (row in rows) {
            var isFailed = false
            for (fid in this.failedIds) {
                if (fid == row.id) { isFailed = true }
            }
            if (isFailed && !row.isHeader) {
                out.add(DocumentRow(
                    id: row.id,
                    isHeader: false,
                    categoryTitle: row.categoryTitle,
                    title: row.title,
                    issuer: row.issuer,
                    supportingText: LocalizableManager.get(LocalizableStringKey.issuanceFailed),
                    logoUrl: row.logoUrl,
                    state: DocumentRowState.failed,
                    expiryTimestamp: row.expiryTimestamp,
                    issuedTimestamp: row.issuedTimestamp,
                    usageText: row.usageText,
                    isCardTop: row.isCardTop,
                    isCardBottom: row.isCardBottom
                ))
            } else {
                out.add(row)
            }
        }
        return out.toArray()
    }

    /**
     * Bake first/last-in-category-card flags onto each document row using a
     * stable snapshot. Call once before assigning `@State rows` so list render
     * never touches `this.rows[idx ± 1]` (IndexOutOfBounds under refresh race).
     */
    private func annotateCardGeometry(rows: Array<DocumentRow>): Array<DocumentRow> {
        let n = rows.size
        if (n == 0) {
            return rows
        }
        let out = ArrayList<DocumentRow>()
        var i: Int64 = 0
        while (i < n) {
            let row = rows[i]
            if (row.isHeader) {
                out.add(row)
            } else {
                let top = (i <= 0) || rows[i - 1].isHeader
                let bottom = (i + 1 >= n) || rows[i + 1].isHeader
                out.add(DocumentRow(
                    id: row.id,
                    isHeader: false,
                    categoryTitle: row.categoryTitle,
                    title: row.title,
                    issuer: row.issuer,
                    supportingText: row.supportingText,
                    logoUrl: row.logoUrl,
                    state: row.state,
                    expiryTimestamp: row.expiryTimestamp,
                    issuedTimestamp: row.issuedTimestamp,
                    usageText: row.usageText,
                    isCardTop: top,
                    isCardBottom: bottom
                ))
            }
            i = i + 1
        }
        return out.toArray()
    }

    /**
     * Mirrors iOS DocumentTabViewModel.onDocumentsRetrievedPostActions: while
     * the wallet still holds deferred documents, wait 5s then run one
     * requestDeferredIssuance round; on completion merge failed ids, stash the
     * issued rows, refresh the list, and (500ms later) present the
     * "Documents issued" sheet. reload() re-arms the next round.
     */
    private func armDeferredPoll(): Unit {
        if (this.pollActive) {
            return
        }
        var hasPending = false
        for (row in this.rows) {
            if (!row.isHeader && rowStateIsPending(row.state)) { hasPending = true }
        }
        if (!hasPending) {
            return
        }
        match (this.viewModel) {
            case Some(model) =>
                this.pollActive = true
                let gen = this.pollGeneration
                Hilog.info(0, "DeferredPoll", "armed gen=" + gen.toString())
                spawn {
                    =>
                    // The whole body is guarded: an uncaught exception would kill
                    // this thread silently and leave pollActive stuck true,
                    // permanently stopping the poll loop.
                    try {
                        sleep(5 * Duration.second)
                        // No `return` inside lambdas (unsupported); nest via if/else.
                        if (gen == this.pollGeneration) {
                            Hilog.info(0, "DeferredPoll", "round start gen=" + gen.toString())
                            let outcome = model.requestDeferredIssuance()
                            Hilog.info(0, "DeferredPoll",
                                "round done issued=" + outcome.issued.size.toString() +
                                " failed=" + outcome.failed.size.toString())
                            // spawn(UIThread) does not fire from a slept background
                            // thread — park the outcome and bounce through the
                            // DocumentTabRefresh observer → reload() (the verified
                            // background→UI marshalling path in this tab).
                            this.lastOutcome = Some(outcome)
                            this.pollActive = false
                            NotificationCenter.post(NotificationName.DocumentTabRefresh)
                        } else {
                            this.pollActive = false
                        }
                    } catch (e: Exception) {
                        Hilog.error(0, "DeferredPoll", "round error: " + e.message)
                        this.pollActive = false
                    }
                }
            case None => ()
        }
    }


    private func onSearchChange(value: String): Unit {
        this.searchQuery = value
        this.reload()
    }



    private func onRowTap(row: DocumentRow): Unit {
        if (row.isHeader) {
            return
        }
        // Mirrors iOS DocumentTabView.onAction: issued/revoked/expired open the
        // detail screen; pending (deferred) / failed have no detail — tapping
        // opens a delete confirmation instead.
        match (row.state) {
            case DocumentRowState.pending | DocumentRowState.failed =>
                this.pendingDeleteId = row.id
                this.pendingDeleteTitle = row.title
                this.showDeleteDeferredDialog = true
            case _ =>
                match (this.viewModel) {
                    case Some(model) => model.onDocumentDetails(row.id)
                    case None => ()
                }
        }
    }

    /** Confirm-delete path for a deferred/failed document; refreshes on success. */
    private func confirmDeleteDeferred(): Unit {
        this.showDeleteDeferredDialog = false
        let id = this.pendingDeleteId
        match (this.viewModel) {
            case Some(model) =>
                spawn {
                    =>
                    let ok = model.onDeleteDeferredDocument(id)
                    if (ok) {
                        spawn(UIThread) { => this.reload() }
                    }
                }
            case None => ()
        }
    }

    private func supportingColor(state: DocumentRowState): Color {
        match (state) {
            case DocumentRowState.revoked => uiColor(ThemeManager.shared.color.red)
            case DocumentRowState.expired => uiColor(ThemeManager.shared.color.red)
            case DocumentRowState.failed => uiColor(ThemeManager.shared.color.red)
            // Deferred → warning (yellow), mirrors iOS supportingColor(.pending).
            case DocumentRowState.pending => uiColor(ThemeManager.shared.color.warning)
            case _ => uiColor(ThemeManager.shared.color.secondaryLabel)
        }
    }

    /** Trailing indicator image key by state (mirrors iOS indicatorImage).
     *  Raster PNGs ignore fillColor, so pending/failed use pre-tinted variants
     *  (warning-yellow clock / red exclamation) baked into image_data. */
    private func trailingIconKey(state: DocumentRowState): String {
        match (state) {
            case DocumentRowState.pending => "clock.fill.warning"
            case DocumentRowState.failed => "exclamationmark.circle.fill.red"
            case DocumentRowState.revoked => "exclamationmark.circle.fill.red"
            // issued/expired: accent chevron. fillColor cannot tint a raster PNG,
            // so use the PRE-TINTED accent variant (plain chevronRight rendered black).
            case _ => ThemeManager.shared.image.chevronRightAccent
        }
    }

    // ── Category-card grouping geometry (iOS: one rounded card per category,
    //    documents separated by hairline dividers) ────────────────────────────

    private func rowTopRadius(row: DocumentRow): Float64 {
        if (row.isCardTop) { return 18.0 }
        return 0.0
    }

    private func rowBottomRadius(row: DocumentRow): Float64 {
        if (row.isCardBottom) { return 18.0 }
        return 0.0
    }

    /** Trailing indicator color by state (mirrors iOS indicatorImageColor). */
    private func trailingIconColor(state: DocumentRowState): Color {
        match (state) {
            case DocumentRowState.pending => uiColor(ThemeManager.shared.color.warning)
            case DocumentRowState.failed => uiColor(ThemeManager.shared.color.red)
            case DocumentRowState.revoked => uiColor(ThemeManager.shared.color.red)
            case _ => uiColor(ThemeManager.shared.color.accent)
        }
    }

    public func build() {
        Stack(alignContent: Alignment.TopStart) {
            Column {
                // The nav bar (menu + title + trailing +/filter) is the Dashboard's
                // shared top bar now. This tab renders only its search + content.
                // Search bar always present (iOS .searchable shows on the empty state).
                this.searchBar()
                if (this.isLoading) {
                    this.loaderContent()
                } else if (!this.hasAnyDocuments) {
                    // Empty wallet → authentic empty state + Add document.
                    this.emptyContent()
                } else if (this.rows.size == 0) {
                    this.noMatchesContent()
                } else {
                    this.listContent()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .justifyContent(FlexAlign.Start)

            // Delete confirmation for a deferred/failed document (iOS
            // issuanceDetailsDeletion dialog on tapping a pending/failed row).
            if (this.showDeleteDeferredDialog) {
                AlertView(
                    title: LocalizableStringKey.issuanceDetailsDeletionTitle([this.pendingDeleteTitle]),
                    message: LocalizableStringKey.issuanceDetailsDeletionCaption([this.pendingDeleteTitle]),
                    // iOS buttons: "no" (cancel) / "yes" (destructive).
                    actions: [
                        AlertAction(title: LocalizableStringKey.no, callback: { => this.showDeleteDeferredDialog = false }),
                        AlertAction(
                            title: LocalizableStringKey.yes,
                            isDestructive: true,
                            callback: { => this.confirmDeleteDeferred() }
                        )
                    ],
                    onDismiss: { => this.showDeleteDeferredDialog = false }
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
    }

    @Builder
    private func searchBar() {
        // iOS keeps the search field full-width; the filter lives in the nav bar
        // (top-right), not inside the search row.
        Row(space: SPACING_SMALL) {
            // iOS .searchable renders a leading magnifying-glass glyph INSIDE the
            // gray field, sitting close to the hint text. Nest the icon +
            // transparent TextInput in a gray pill (a sibling icon would land on
            // white). TextInput carries a default text inset, so zero its left
            // padding to keep the glyph-to-text gap tight like iOS.
            Row(space: 6.0) {
                AppIcon(token: ThemeManager.shared.image.searchIcon, size: 18.0)
                TextInput(text: this.searchQuery, placeholder: LocalizableManager.get(LocalizableStringKey.search))
                    .layoutWeight(1)
                    .height(48.0)
                    .padding(left: 0.0, right: 0.0, top: 0.0, bottom: 0.0)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .backgroundColor(Color.Transparent)
                    .onChange({ value => this.onSearchChange(value) })
            }
            .layoutWeight(1)
            .padding(top: 0.0, right: 0.0, bottom: 0.0, left: SPACING_MEDIUM)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))
            // iOS .searchable field is strongly rounded (~0.44 × height); a small
            // radius read as a boxy field. 22 on the 48-tall field matches iOS.
            .borderRadius(22.0)
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }

    @Builder
    private func noMatchesContent() {
        // iOS anchors the empty copy just below the search bar (near the top), not
        // vertically centered in the remaining space.
        Column {
            ContentUnavailableView(
                title: LocalizableStringKey.noResults,
                description: LocalizableStringKey.noResultsDocumentsDescription
            )
        }
        .width(100.percent)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
    }

    @Builder
    private func loaderContent() {
        Column {
            ContentLoaderView(showLoader: true)
        }
        .width(100.percent)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
    }

    @Builder
    private func emptyContent() {
        // iOS empty state is just the "No results" copy — adding a document is the
        // top-right "+" in the nav bar, not a centre button.
        Column {
            ContentUnavailableView(
                title: LocalizableStringKey.noResults,
                description: LocalizableStringKey.noResultsDocumentsDescription
            )
        }
        .width(100.percent)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
    }

    @Builder
    private func listContent() {
        Scroll {
            // space 0: same-category rows must sit flush so they merge into ONE
            // visual card (iOS groups a category's documents in a single rounded
            // container with dividers between rows).
            Column(space: SPACING_NONE) {
                ForEach(
                    this.rows,
                    itemGenerator: { row: DocumentRow, idx: Int64 =>
                        // Built-in components only (R-102).
                        if (row.isHeader) {
                            Text(row.categoryTitle)
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                .fontWeight(FontWeight.Medium)
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .width(100.percent)
                                .textAlign(TextAlign.Start)
                                // iOS category header uses SPACING_SMALL top padding
                                // (was SPACING_MEDIUM → too big a gap under the search bar).
                                .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
                        } else {
                            Column(space: SPACING_NONE) {
                                Row(space: SPACING_MEDIUM) {
                                    if (!row.logoUrl.isEmpty()) {
                                        Image(row.logoUrl)
                                            .width(ThemeManager.shared.dimension.remoteImageIconSize)
                                            .height(ThemeManager.shared.dimension.remoteImageIconSize)
                                            .objectFit(ImageFit.Contain)
                                    }
                                    Column(space: 4.0) {
                                        Text(row.issuer)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                            .width(100.percent)
                                            .textAlign(TextAlign.Start)
                                        Text(row.title)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                            // iOS WrapListItemView main text is medium-weight (plain style).
                                            .fontWeight(FontWeight.Medium)
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .width(100.percent)
                                            .textAlign(TextAlign.Start)
                                        if (!row.supportingText.isEmpty()) {
                                            Text(row.supportingText)
                                                // iOS renders this smaller than the Callout
                                                // body; bodySmall matches the compact "Valid
                                                // until …" line.
                                                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                                .fontColor(this.supportingColor(row.state))
                                                .width(100.percent)
                                                .textAlign(TextAlign.Start)
                                        }
                                    }
                                    .layoutWeight(1)
                                    if (!row.usageText.isEmpty()) {
                                        // iOS batch counter "1/1" (secondaryLabel)
                                        // sits left of the trailing indicator.
                                        Text(row.usageText)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                    }
                                    Image(appImageSrc(this.trailingIconKey(row.state)))
                                        .width(22.0)
                                        .height(22.0)
                                        .objectFit(ImageFit.Contain)
                                        .fillColor(this.trailingIconColor(row.state))
                                }
                                .width(100.percent)
                                .padding(SPACING_MEDIUM)
                                .onClick({ _ => this.onRowTap(row) })
                                // Divider between rows that share the category card
                                // (iOS puts a hairline between grouped documents).
                                if (!row.isCardBottom) {
                                    Row {
                                        Divider()
                                            .color(dividerHairline())
                                            .strokeWidth(1.0)
                                            .layoutWeight(1)
                                    }
                                    .width(100.percent)
                                    .padding(top: 0.0, right: SPACING_MEDIUM, bottom: 0.0, left: SPACING_MEDIUM)
                                }
                            }
                            .width(100.percent)
                            .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                            .borderRadius(
                                topLeft: this.rowTopRadius(row),
                                topRight: this.rowTopRadius(row),
                                bottomLeft: this.rowBottomRadius(row),
                                bottomRight: this.rowBottomRadius(row)
                            )
                            .margin(left: SPACING_MEDIUM, right: SPACING_MEDIUM, top: 0.0, bottom: 0.0)
                        }
                    },
                    // Stable per-row keys so ArkUI diffs correctly when the list is
                    // refreshed live (DocumentTabRefresh after issuance). Without this
                    // ForEach reuses instances by index and renders stale card content
                    // (e.g. a newly issued doc showing the previous card's name).
                    // The key must ALSO include the row's mutable display state:
                    // a deferred→issued conversion keeps the same id, and an
                    // id-only key made ForEach reuse the old "Pending" rendering.
                    keyGenerator: { row: DocumentRow, idx: Int64 =>
                        if (row.isHeader) {
                            "h_" + row.categoryTitle
                        } else {
                            // Key includes display state AND baked card-edge flags
                            // (no live rows[idx±1] lookup — that raced with reload).
                            let top = if (row.isCardTop) { "t" } else { "" }
                            let bottom = if (row.isCardBottom) { "b" } else { "" }
                            "d_" + row.id + "_" + row.supportingText + "_" + top + bottom
                        }
                    }
                )
            }
            .width(100.percent)
            // Bottom inset = floating tab bar + fade zone so the last row can
            // always scroll fully clear of the bar (iOS behaviour).
            .padding(top: 0.0, right: 0.0, bottom: 104.0, left: 0.0)
        }
        .align(Alignment.TopStart)
        .layoutWeight(1)
    }
}

/** True for the pending (deferred) row state. */
func rowStateIsPending(state: DocumentRowState): Bool {
    match (state) {
        case DocumentRowState.pending => true
        case _ => false
    }
}

/** Hairline divider colour between grouped rows (same recipe as ListDividerView). */
func dividerHairline(): Color {
    Color((ThemeManager.shared.color.separator.light & 0x00FFFFFFu32) | 0xCC000000u32)
}
