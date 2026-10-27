/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (DashboardViewModel.swift + DocumentTabViewModel.swift +
 * TransactionTabViewModel.swift) to Cangjie.
 *
 * Owns the DashboardState (toolbar/title/paused) and the selectedTab cursor.
 * Also exposes the DashboardInteractor (WalletKitController seam) so the tab
 * views can load real documents / transactions. No ArkUI import here (UI-free
 * VM layer); blocking interactor calls are wrapped in spawn{} by the views and
 * @State writebacks marshalled with spawn(UIThread) (S-001).
 */
package eudi_feature_dashboard

import std.collection.HashMap
import std.time.DateTime
import eudi_logic_ui.{BaseViewModel, RouterHost, ToolBarContent, AppRoutes, NavArgs, RouteConfigArgs}
import eudi_logic_business.BleAvailibity
import eudi_logic_resources.{LocalizableStringKey}
import eudi_feature_common.{IssuanceFlowUiConfig, IssuanceFlow}

/**
 * Mirrors Swift `DashboardViewModel<Router>`.
 * Owns the DashboardState and the selectedTab cursor, plus the optional
 * DashboardInteractor (None in standalone/preview, wired by the composition
 * root in production).
 */
public class DashboardViewModel <: BaseViewModel<DashboardState> {

    /** Mirrors Swift `selectedTab: SelectedTab = .home`. */
    public var selectedTab: SelectedTab = SelectedTab.Home

    /** WalletKitController seam (None → empty-wallet preview behaviour). */
    public let interactor: ?DashboardInteractor

    /** Cached document/transaction filter controllers (built on first list load). */
    private var documentFilter: ?DashboardFilterController = Option<DashboardFilterController>.None
    private var transactionFilter: ?DashboardFilterController = Option<DashboardFilterController>.None
    /** Cached unfiltered grouped rows so the filter engine result can be re-grouped. */
    private var documentRowsCache: Array<DocumentRow> = Array<DocumentRow>()
    private var transactionRowsCache: Array<TransactionRow> = Array<TransactionRow>()

    public init(router!: RouterHost) {
        super(
            router,
            DashboardState(
                navigationTitle: LocalizableStringKey.custom(""),
                toolBarContent: ToolBarContent(),
                isPaused: false
            )
        )
        this.interactor = Option<DashboardInteractor>.None
    }

    public init(router!: RouterHost, interactor!: DashboardInteractor) {
        super(
            router,
            DashboardState(
                navigationTitle: LocalizableStringKey.custom(""),
                toolBarContent: ToolBarContent(),
                isPaused: false
            )
        )
        this.interactor = Some(interactor)
    }

    /** Mirrors Swift `onCreate()`: clears the paused flag. */
    public func onCreate(): Unit {
        onResume()
    }

    /** Mirrors Swift `onPause()`: marks state as paused. */
    public func onPause(): Unit {
        this.setState({ s =>
            DashboardState(
                navigationTitle: s.navigationTitle,
                toolBarContent: s.toolBarContent,
                isPaused: true
            )
        })
    }

    /** Mirrors Swift `onResume()`: clears the paused flag. */
    public func onResume(): Unit {
        this.setState({ s =>
            DashboardState(
                navigationTitle: s.navigationTitle,
                toolBarContent: s.toolBarContent,
                isPaused: false
            )
        })
    }

    // ── Data loading (blocking; called from spawn{} in the views) ──────────

    /**
     * Loads the grouped document rows (mirrors DocumentTabViewModel.fetch).
     *
     * Degrades a failed read to the empty list for the same reason as
     * loadTransactionRows: the views call these loaders from bare `spawn{}` blocks
     * and event handlers, so a throw escaping here has nothing above it.
     */
    public func loadDocumentRows(): Array<DocumentRow> {
        match (this.interactor) {
            case Some(i) =>
                try {
                    return i.fetchDocumentRows()
                } catch (_: Exception) {
                    return Array<DocumentRow>()
                }
            case None => Array<DocumentRow>()
        }
    }

    /**
     * Loads the grouped document rows with a search query + sort direction
     * applied (mirrors DocumentTabViewModel.applySearch + the default name sort).
     * Empty query with ascending=true is equivalent to loadDocumentRows().
     */
    public func loadDocumentRowsFiltered(query: String, ascending: Bool): Array<DocumentRow> {
        match (this.interactor) {
            case Some(i) =>
                try {
                    return i.fetchDocumentRowsFiltered(query, ascending)
                } catch (_: Exception) {
                    return Array<DocumentRow>()
                }
            case None => Array<DocumentRow>()
        }
    }

    /**
     * Loads the grouped transaction rows (mirrors TransactionTabViewModel.fetch).
     *
     * The interactor reports a transaction-log failure by throwing, and iOS ends
     * that path at `isLoading: false, transactions: [:]` — the empty list. The
     * conversion belongs here rather than in the view so that every entry point
     * gets it: the first load is wrapped, but the search handler calls straight
     * in, and there a throw would escape from a UI event with nothing above it.
     */
    public func loadTransactionRows(): Array<TransactionRow> {
        match (this.interactor) {
            case Some(i) =>
                try {
                    return i.fetchTransactionRows()
                } catch (_: Exception) {
                    return Array<TransactionRow>()
                }
            case None => Array<TransactionRow>()
        }
    }

    /** Mirrors HomeTabViewModel.fetchUsername — the main PID bearer first name. */
    public func loadUsername(): String {
        match (this.interactor) {
            case Some(i) => i.fetchUsername()
            case None => ""
        }
    }

    /** Mirrors HomeTabInteractor.getBleAvailability(); the value is delivered to
     *  `callback` (possibly asynchronously — permission prompt / radio read). */
    public func bleAvailability(callback: (BleAvailibity) -> Unit): Unit {
        match (this.interactor) {
            case Some(i) => i.getBleAvailability(callback)
            case None => callback(BleAvailibity.unavailable)
        }
    }

    /** Mirrors HomeTabInteractor.openBleSettings(). */
    public func openBleSettings(): Unit {
        match (this.interactor) {
            case Some(i) => i.openBleSettings()
            case None => ()
        }
    }

    // ── Document filters (mirror DocumentTabViewModel filter plumbing) ────────

    /**
     * Returns the document rows with the applied filters in effect. Builds the
     * filter controller from the wallet's documents on first call, caching both
     * the controller and the unfiltered grouped rows so the engine result can be
     * re-grouped (headers re-added) cheaply on every change.
     */
    public func loadDocumentRowsApplyingFilters(query: String): Array<DocumentRow> {
        match (this.interactor) {
            case Some(i) =>
                // Same degradation as the transaction side: assembling the filters
                // reads the wallet again, so either read can fail, and both end on
                // the empty list rather than throwing into a UI event handler.
                try {
                    let all = i.fetchDocumentRows()
                    // Rebuild the filter controller ONLY when the document set changes
                    // (count differs). Otherwise reuse the cached controller so the
                    // user's filter selections survive reloads and reopening the
                    // Filters sheet (rebuilding every call reset them to defaults).
                    let needRebuild = match (this.documentFilter) {
                        case None => true
                        case Some(_) => all.size != this.documentRowsCache.size
                    }
                    this.documentRowsCache = all
                    let controller = if (needRebuild) {
                        // Tear the outgoing controller down before dropping it, the way
                        // iOS finishes the filter stream in deinit. Without this the
                        // discarded controller keeps the engine listener and stays
                        // drivable, so a stale reference could still mutate filters.
                        match (this.documentFilter) {
                            case Some(old) => old.complete()
                            case None => ()
                        }
                        let c = i.buildDocumentFilterController(all)
                        this.documentFilter = Some(c)
                        c
                    } else {
                        this.documentFilter.getOrThrow()
                    }
                    // Always push the current query (incl. empty) through applySearch so
                    // clearing the box RESETS the retained search term. Calling
                    // applyFilters() on the empty case left the previous query applied
                    // (FilterValidator keeps `searchQuery`), so deleting the text stayed
                    // on "No results" instead of restoring the full list.
                    controller.applySearch(query)
                    return controller.filteredDocumentRows(all)
                } catch (_: Exception) {
                    this.documentRowsCache = Array<DocumentRow>()
                    return Array<DocumentRow>()
                }
            case None => Array<DocumentRow>()
        }
    }

    public func documentFilterSections(): Array<FilterUISection> {
        match (this.documentFilter) {
            case Some(c) => c.sections()
            case None => Array<FilterUISection>()
        }
    }

    public func documentUpdateFilter(sectionId: String, filterId: String): Unit {
        match (this.documentFilter) {
            case Some(c) => c.updateFilter(sectionId, filterId)
            case None => ()
        }
    }

    public func documentUpdateSort(filterId: String): Unit {
        match (this.documentFilter) {
            case Some(c) => c.updateSort(filterId)
            case None => ()
        }
    }

    public func documentApplyFilters(): Array<DocumentRow> {
        match (this.documentFilter) {
            case Some(c) =>
                c.applyFilters()
                c.filteredDocumentRows(this.documentRowsCache)
            case None => this.documentRowsCache
        }
    }

    public func documentResetFilters(): Array<DocumentRow> {
        match (this.documentFilter) {
            case Some(c) =>
                c.resetFilters()
                c.filteredDocumentRows(this.documentRowsCache)
            case None => this.documentRowsCache
        }
    }

    public func documentRevertFilters(): Unit {
        match (this.documentFilter) {
            case Some(c) => c.revertFilters()
            case None => ()
        }
    }

    // ── Transaction filters (mirror TransactionTabViewModel filter plumbing) ──

    /**
     * Mirrors iOS TransactionTabViewModel.fetch(): initialize the validator once,
     * then only replace its source list on later fetches before applying the
     * current snapshot/applied filters. The validator itself owns the search
     * query, so a refresh must not overwrite it.
     */
    public func loadTransactionRowsApplyingFilters(): Array<TransactionRow> {
        match (this.interactor) {
            case Some(i) =>
                // Assembling the filters reads the transaction log a second time (for
                // the date range), so a broken wallet can fail at either read. Both
                // land on the same empty list iOS shows for `.failure`, and this call
                // is reached straight from the search handler, where an escaping throw
                // would have nothing above it to catch.
                try {
                    let all = this.loadTransactionRows()
                    this.transactionRowsCache = all
                    let controller = match (this.transactionFilter) {
                        // iOS lifecycle != active: initializeFilters.
                        case None =>
                            let c = i.buildTransactionFilterController(all)
                            this.transactionFilter = Some(c)
                            c
                        // iOS lifecycle == active: updateLists. Never recreate the
                        // validator here, because it owns applied + snapshot state.
                        case Some(c) =>
                            i.updateTransactionFilterLists(c, all)
                            c
                    }
                    controller.applyFilters()
                    return controller.filteredTransactionRows(all)
                } catch (_: Exception) {
                    this.transactionRowsCache = Array<TransactionRow>()
                    return Array<TransactionRow>()
                }
            case None => Array<TransactionRow>()
        }
    }

    /** Mirrors the debounced iOS applySearch path: do not refetch/reinitialize. */
    public func transactionApplySearch(query: String): Array<TransactionRow> {
        match (this.transactionFilter) {
            case Some(c) =>
                c.applySearch(query)
                c.filteredTransactionRows(this.transactionRowsCache)
            case None => Array<TransactionRow>()
        }
    }

    public func transactionFilterSections(): Array<FilterUISection> {
        match (this.transactionFilter) {
            case Some(c) => c.sections()
            case None => Array<FilterUISection>()
        }
    }

    public func transactionDateRange(): (DateTime, DateTime) {
        match (this.transactionFilter) {
            // Keep both calendars open around today, matching the generic iOS
            // FiltersListView fallback, instead of pinning them to the dates of
            // the transactions that happened to exist when History first loaded.
            case Some(c) => (c.calendarRangeMin, c.calendarRangeMax)
            case None => (DateTime.now().addDays(-365), DateTime.now().addDays(365))
        }
    }

    public func transactionUpdateFilter(sectionId: String, filterId: String): Unit {
        match (this.transactionFilter) {
            case Some(c) => c.updateFilter(sectionId, filterId)
            case None => ()
        }
    }

    public func transactionUpdateDateFilters(sectionId: String, filterId: String, start: DateTime, end: DateTime): Unit {
        match (this.transactionFilter) {
            case Some(c) => c.updateDateFilters(sectionId, filterId, start, end)
            case None => ()
        }
    }

    public func transactionApplyFilters(): Array<TransactionRow> {
        match (this.transactionFilter) {
            case Some(c) =>
                c.applyFilters()
                c.filteredTransactionRows(this.transactionRowsCache)
            case None => this.transactionRowsCache
        }
    }

    public func transactionResetFilters(): Array<TransactionRow> {
        match (this.transactionFilter) {
            case Some(c) =>
                c.resetFilters()
                c.filteredTransactionRows(this.transactionRowsCache)
            case None => this.transactionRowsCache
        }
    }

    public func transactionRevertFilters(): Unit {
        match (this.transactionFilter) {
            case Some(c) => c.revertFilters()
            case None => ()
        }
    }

    /**
     * Pushes the add-document flow listing ALL issuable documents (mirrors iOS
     * DashboardView "+" → AddDocumentView with `.extraDocument(nil)`). Without
     * setting this flow the route defaults to NoDocument, which restricts the list
     * to PID only — so the user would never see mDL / Age / Photo ID / etc.
     */
    public func onAddDocument(): Unit {
        // iOS Documents "+" opens the "Add document" chooser (Choose from list /
        // Scan QR) first; the chooser then carries the ExtraDocument flow into the
        // issuer catalog. (Previously this jumped straight to the catalog.)
        this.router.push(AppRoutes.addDocumentOptions)
    }

    /** Pushes the side menu (mirrors the leading menu-icon toolbar action). */
    public func onSideMenu(): Unit {
        this.router.push(AppRoutes.sideMenu)
    }

    /** Pushes the document-details screen for the given id. */
    public func onDocumentDetails(documentId: String): Unit {
        DashboardNavArgs.shared.documentId = documentId
        this.router.push(AppRoutes.documentDetails)
    }

    /**
     * Deletes a deferred/failed document (mirrors iOS
     * DocumentTabViewModel.onDeleteDeferredDocument). Deferred docs have no
     * detail screen; tapping one opens a delete confirmation whose confirm path
     * lands here. Blocking; the view wraps in spawn{} and refreshes the list on
     * success. Returns true when the wallet delete succeeded.
     */
    public func onDeleteDeferredDocument(documentId: String): Bool {
        match (this.interactor) {
            case Some(i) => i.deleteDeferredDocument(documentId)
            case None => false
        }
    }

    /**
     * One deferred-issuance polling round (mirrors iOS
     * DocumentTabInteractor.requestDeferredIssuance, driven by the tab's 5s
     * deferred task). Blocking; the view wraps in spawn{}.
     */
    public func requestDeferredIssuance(): DeferredIssuanceOutcome {
        match (this.interactor) {
            case Some(i) => i.requestDeferredIssuance()
            case None => DeferredIssuanceOutcome(issued: Array<DocumentRow>(), failed: Array<String>())
        }
    }

    /** Pushes the transaction-details screen for the given id. */
    public func onTransactionDetails(transactionId: String): Unit {
        DashboardNavArgs.shared.transactionId = transactionId
        this.router.push(AppRoutes.transactionDetails)
    }
}

/**
 * Lightweight in-process carrier for detail-screen ids. The app-shell's
 * NavArgs carries route configs; the dashboard's detail routes only need a
 * single id, so this minimal singleton mirrors the same hand-off pattern
 * without coupling the feature module to the entry's NavArgs type.
 */
public class DashboardNavArgs {
    private static let instance: DashboardNavArgs = DashboardNavArgs()

    public var documentId: String = ""
    public var transactionId: String = ""

    private init() {}

    public static prop shared: DashboardNavArgs {
        get() { instance }
    }
}
