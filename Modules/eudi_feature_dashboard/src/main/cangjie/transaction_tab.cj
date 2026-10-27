/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (Tab/Transaction/TransactionTabView.swift) to Cangjie.
 *
 * Renders the real transaction log (grouped by month/year, newest first)
 * fetched via DashboardInteractor → WalletKitController.fetchTransactionLogs().
 * Empty wallets / no-history users see the authentic empty state. Same own-
 * isLoading gating as DocumentTabView (starts true, cleared after fetch) so the
 * tab never sticks on a loader. Blocking fetch in spawn{}, @State writeback via
 * spawn(UIThread) (S-001).
 */
package eudi_feature_dashboard

import std.time.DateTime
import std.collection.HashMap
import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.{
    ContentUnavailableView, uiColor, uiFontSize, ContentLoaderView,
    SPACING_NONE, SPACING_SMALL, SPACING_MEDIUM, AppIcon, appImageSrc
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_logic_core.{NotificationCenter, NotificationName}

/**
 * History (Transaction) Tab view: real transaction list + empty state.
 * Mounted as TabContent content inside DashboardView; receives the shared
 * DashboardViewModel so it can load transactions and push details routes.
 */
@Component
public class TransactionTabView {
    public var viewModel: ?DashboardViewModel = Option<DashboardViewModel>.None

    @State
    var rows: Array<TransactionRow> = Array<TransactionRow>()
    @State
    var isLoading: Bool = true
    /** Whether the wallet has ANY transactions (drives the filter bar). */
    @State
    var hasAnyTransactions: Bool = false
    /** Date-range bounds for the filter pickers (from the wallet's logs). */
    @State
    var minDate: DateTime = DateTime.now()
    @State
    var maxDate: DateTime = DateTime.now()
    /** Live search query (mirrors iOS TransactionTabViewModel applySearch). */
    @State
    var searchQuery: String = ""

    /** Guards against double-registration if aboutToAppear fires more than once. */
    private var observerRegistered: Bool = false

    protected override func aboutToAppear(): Unit {
        // The Filters sheet + its date bounds are owned by the Dashboard layer
        // (rendered above the tab bar); this tab re-pulls its rows when the
        // dashboard applies filters.
        if (!this.observerRegistered) {
            this.observerRegistered = true
            NotificationCenter.addObserver(NotificationName.TransactionTabRefresh, { _ =>
                this.reload()
            })
        }
        this.reload()
    }

    /** Re-fetch rows applying the engine's current filters. */
    private func reload(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                spawn {
                    =>
                    // Build the filter controller from real logs + load the
                    // applied (default) filtered rows (mirrors TransactionTabViewModel.fetch).
                    // A load failure already degrades to the empty list inside the
                    // view model (mirrors iOS .failure → isLoading:false,
                    // transactions:[]); this try is a backstop so that anything
                    // else raising here still clears isLoading rather than
                    // leaving the spinner spinning.
                    var loadedTmp = Array<TransactionRow>()
                    var totalTmp = Array<TransactionRow>()
                    var rangeTmp = (DateTime.now(), DateTime.now())
                    try {
                        loadedTmp = model.loadTransactionRowsApplyingFilters()
                        totalTmp = model.loadTransactionRows()
                        rangeTmp = model.transactionDateRange()
                    } catch (_: Exception) {
                        // fall through to render empty state with isLoading cleared
                    }
                    // immutable bindings for the UI-thread lambda capture
                    let loaded = loadedTmp
                    let total = totalTmp
                    let range = rangeTmp
                    let hasAny = total.size > 0
                    spawn(UIThread) {
                        =>
                        this.rows = loaded
                        this.hasAnyTransactions = hasAny
                        this.minDate = range[0]
                        this.maxDate = range[1]
                        // The Dashboard renders the filter sheet; hand the
                        // date-picker bounds up through the overlay carrier.
                        DashboardOverlayData.shared.txMinDate = range[0]
                        DashboardOverlayData.shared.txMaxDate = range[1]
                        this.isLoading = false
                        // Report the count up so the shared nav bar can enable/gray
                        // its trailing filter (iOS disabled:isEmpty).
                        let m = HashMap<String, String>()
                        m.add("key", "tx")
                        m.add("value", if (hasAny) { "true" } else { "false" })
                        NotificationCenter.postMap(NotificationName.DashboardToolbarSync, m)
                    }
                }
            case None =>
                this.isLoading = false
        }
    }

    private func onRowTap(row: TransactionRow): Unit {
        if (row.isHeader) {
            return
        }
        match (this.viewModel) {
            case Some(model) => model.onTransactionDetails(row.id)
            case None => ()
        }
    }


    private func onSearchChange(value: String): Unit {
        this.searchQuery = value
        match (this.viewModel) {
            case Some(model) => this.rows = model.transactionApplySearch(value)
            case None => ()
        }
    }

    public func build() {
        Stack(alignContent: Alignment.TopStart) {
            Column {
                // The nav bar (menu + "History" title + trailing filter) is the
                // Dashboard's shared top bar now. This tab renders search + content.
                this.searchBar()
                if (this.isLoading) {
                    this.loaderContent()
                } else if (!this.hasAnyTransactions) {
                    this.emptyContent()
                } else if (this.rows.size == 0) {
                    this.emptyContent()
                } else {
                    this.listContent()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .justifyContent(FlexAlign.Start)
        }
        .width(100.percent)
        .height(100.percent)
    }

    /** Search bar — full-width (iOS keeps the filter in the nav bar, not here). */
    @Builder
    private func searchBar() {
        Row(space: SPACING_SMALL) {
            // Leading magnifier inside the gray field, tight to the hint text
            // (mirrors iOS .searchable) — same layout as the Documents tab.
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
            // Match iOS .searchable rounding (see Documents tab).
            .borderRadius(22.0)
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
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
        Column {
            ContentUnavailableView(
                title: LocalizableStringKey.noResults,
                description: LocalizableStringKey.noResultsTransactionsDescription
            )
        }
        .width(100.percent)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        // No extra top inset: ContentUnavailableView already carries the iOS
        // SPACING_LARGE_MEDIUM top padding (matching the Documents empty state).
    }

    @Builder
    private func listContent() {
        Scroll {
            // iOS renders every month's rows inside one WrapCardView. A zero-gap
            // column plus per-row edge radii reproduces that shared card.
            Column(space: SPACING_NONE) {
                ForEach(
                    this.rows,
                    itemGenerator: { row: TransactionRow, _: Int64 =>
                        // Built-in components only (R-102).
                        if (row.isHeader) {
                            Text(row.groupTitle)
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .width(100.percent)
                                .textAlign(TextAlign.Start)
                                .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
                        } else {
                            Column(space: SPACING_NONE) {
                                Row(space: SPACING_MEDIUM) {
                                    Column(space: 4.0) {
                                        // iOS ListItemData.overlineText: transaction status.
                                        Text(row.statusLabel)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                            .fontColor(if (row.isCompleted) {
                                                uiColor(ThemeManager.shared.color.green)
                                            } else {
                                                uiColor(ThemeManager.shared.color.red)
                                            })
                                            .width(100.percent)
                                            .textAlign(TextAlign.Start)
                                        Text(row.title)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                            .fontWeight(FontWeight.Medium)
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .width(100.percent)
                                            .textAlign(TextAlign.Start)
                                        Text(row.dateText)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                            // iOS explicitly uses primaryLabel for the date.
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .width(100.percent)
                                            .textAlign(TextAlign.Start)
                                    }
                                    .layoutWeight(1)
                                    Row(space: SPACING_SMALL) {
                                        Text(row.typeLabel)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                            .maxLines(1)
                                        Image(appImageSrc(ThemeManager.shared.image.chevronRight))
                                            .width(16.0)
                                            .height(16.0)
                                            .objectFit(ImageFit.Contain)
                                            .fillColor(uiColor(ThemeManager.shared.color.accent))
                                    }
                                }
                                .width(100.percent)
                                .padding(SPACING_MEDIUM)
                                .onClick({ _ => this.onRowTap(row) })

                                if (!row.isCardBottom) {
                                    Row {
                                        Divider()
                                            .color(dividerHairline())
                                            .strokeWidth(1.0)
                                            .layoutWeight(1)
                                    }
                                    .width(100.percent)
                                    .padding(left: SPACING_MEDIUM, right: SPACING_MEDIUM)
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
                            .margin(left: SPACING_MEDIUM, right: SPACING_MEDIUM)
                        }
                    },
                    keyGenerator: { row: TransactionRow, _: Int64 =>
                        let top = if (row.isCardTop) { "t" } else { "" }
                        let bottom = if (row.isCardBottom) { "b" } else { "" }
                        // Timestamp/title are intentionally part of the identity
                        // for backwards compatibility with logs written by older
                        // builds, whose process-local `group-N` ids may collide.
                        // A replaced legacy record must be rendered as new data.
                        row.id + "_" + row.timestamp.toString() + "_" + row.title + "_" +
                            row.statusLabel + "_" + top + bottom
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

    private func rowTopRadius(row: TransactionRow): Float64 {
        if (row.isCardTop) { return 18.0 }
        return 0.0
    }

    private func rowBottomRadius(row: TransactionRow): Float64 {
        if (row.isCardBottom) { return 18.0 }
        return 0.0
    }
}
