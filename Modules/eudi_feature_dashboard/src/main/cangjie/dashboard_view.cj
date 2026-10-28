/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (DashboardView.swift) to Cangjie.
 *
 * DashboardView is the landing page after startup → quickPin completion.
 * It mounts as a NavDestination in the app-shell's pageMap under the route
 * key AppRoutes.dashboard. The view owns a Tabs (bottom navigation) with
 * three TabContent items: Home / Documents / History.
 *
 * The dashboard layer also hosts the bottom sheets that must cover the tab
 * bar: filters, "Documents issued" and the revoked-documents modal raised by
 * the revocation worker (iOS DashboardView.sheetDialog).
 */
package eudi_feature_dashboard

import std.collection.HashMap
import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.time.DateTime
import kit.PerformanceAnalysisKit.Hilog
import std.collection.ArrayList
import eudi_logic_ui.{uiColor, uiFontSize, RouterHost, InMemoryRouterHost, AppRoutes, appImageSrc, AppIcon,
    SPACING_NONE, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, EUDI_SCRIM_COLOR}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_logic_core.{NotificationCenter, NotificationName}

/**
 * Dashboard landing page.
 *
 * Mirrors Swift `DashboardView<Router>: View` structure:
 *  - Outer NavDestination (D-002: NavDestination must be the build() root for
 *    destination pages registered in the app-shell pageMap).
 *  - ContentScreenView with canScroll: false, no padding (mirrors iOS
 *    `padding: .zero`).
 *  - Inner Tabs(barPosition: BarPosition.End) with three TabContent items
 *    (Home / Documents / History), mirroring iOS TabView.
 *
 * Injection:
 *  - `viewModel`: pre-built DashboardViewModel supplied by the composition
 *    root (app-shell). Defaults to an emulator-safe self-contained instance.
 */
@Component
public class DashboardView {
    public var viewModel: ?DashboardViewModel = Option<DashboardViewModel>.None

    @State
    var isPaused: Bool = false

    @State
    var selectedIndex: Int32 = 0

    // Shared-toolbar filter gating (mirrors iOS `disabled: filterUIModel.isEmpty`):
    // the trailing filter in the ONE shared nav bar is enabled/blue only when the
    // active tab actually has rows. Each tab posts DashboardToolbarSync with its
    // current count so the bar can update these without owning the tab's data.
    @State
    var docHasAny: Bool = false
    @State
    var txHasAny: Bool = false

    // Overlays owned by the DASHBOARD layer so they cover the shared nav bar
    // AND the floating tab bar (iOS presents these as sheets above everything).
    @State
    var showDocFilters: Bool = false
    @State
    var showTxFilters: Bool = false
    @State
    var showIssuedSheet: Bool = false
    @State
    var issuedRows: Array<DocumentRow> = Array<DocumentRow>()
    // iOS `isRevokedModalShowing` + `viewState.revokedDocuments`: raised by the
    // revocation worker's RevocationDashboard post.
    @State
    var showRevokedSheet: Bool = false
    @State
    var revokedRows: Array<RevokedDocumentRow> = Array<RevokedDocumentRow>()

    private var vm: ?DashboardViewModel = Option<DashboardViewModel>.None
    private var toolbarObserverRegistered: Bool = false

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultDashboardViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.isPaused = state.isPaused
            }
        })
        this.selectedIndex = model.selectedTab.toIndex()
        // The tabs report their row counts here so the shared bar can gray/enable
        // its filter. Registered once, before the child tabs mount + post.
        if (!this.toolbarObserverRegistered) {
            this.toolbarObserverRegistered = true
            NotificationCenter.addObserver(NotificationName.DashboardToolbarSync, { n =>
                match (n.map) {
                    case Some(m) =>
                        let key = m.get("key") ?? ""
                        let has = (m.get("value") ?? "false") == "true"
                        // Posts always originate on the UI thread (the tabs'
                        // reload UIThread callbacks), so assign directly —
                        // spawn(UIThread) from inside a UIThread task silently
                        // never fired, leaving the filter permanently gray.
                        let hasStr = if (has) { "1" } else { "0" }
                        Hilog.info(0, "ToolbarSync", "recv key=" + key + " has=" + hasStr)
                        if (key == "doc") {
                            this.docHasAny = has
                        } else if (key == "tx") {
                            this.txHasAny = has
                        }
                    case None => ()
                }
            })
            // Filter buttons in the shared bar open the sheets at THIS layer
            // (above nav bar + tab bar, mirroring the iOS .sheet presentation).
            NotificationCenter.addObserver(NotificationName.DocumentOpenFilters, { _ =>
                this.showDocFilters = true
            })
            NotificationCenter.addObserver(NotificationName.TransactionOpenFilters, { _ =>
                this.showTxFilters = true
            })
            // Deferred docs converted → present the "Documents issued" sheet
            // above the tab bar; rows travel via the dashboard-layer carrier.
            NotificationCenter.addObserver(NotificationName.DeferredDocsIssued, { _ =>
                this.issuedRows = DashboardOverlayData.shared.issuedRows
                this.showIssuedSheet = true
            })
            // A credential added in a PRIOR session persists, so the tab that owns
            // it may not re-post on this mount. Seed the counts directly here (and
            // refresh on issuance) so the shared bar's filter starts enabled when
            // the wallet already has rows — the "sort button stuck disabled" fix.
            NotificationCenter.addObserver(NotificationName.DocumentTabRefresh, { _ => this.reloadToolbarCounts() })
            // The revocation worker posts displayName -> id from its background
            // loop, so hop to the UI thread before touching @State.
            NotificationCenter.addObserver(NotificationName.RevocationDashboard, { n =>
                match (n.map) {
                    case Some(m) =>
                        let rows = revokedRowsFrom(m)
                        spawn(UIThread) {
                            => this.handleRevocationNotification(rows)
                        }
                    case None => ()
                }
            })
        }
        model.onCreate()
        this.reloadToolbarCounts()
    }

    /** Load doc/tx counts directly so docHasAny/txHasAny are correct even when the
     *  owning tab isn't mounted or doesn't re-post (persisted credentials). */
    private func reloadToolbarCounts(): Unit {
        match (this.vm) {
            case Some(model) =>
                spawn {
                    =>
                    var docs = 0
                    var txs = 0
                    try {
                        docs = model.loadDocumentRows().size
                    } catch (_: Exception) {}
                    try {
                        txs = model.loadTransactionRows().size
                    } catch (_: Exception) {}
                    let d = docs > 0
                    let t = txs > 0
                    spawn(UIThread) {
                        =>
                        this.docHasAny = d
                        this.txHasAny = t
                    }
                }
            case None => ()
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) =>
                model.onPause()
                model.clearStateListener()
            case None => ()
        }
    }

    private func onTabChange(index: Int32): Unit {
        this.selectedIndex = index
        match (this.vm) {
            case Some(model) => model.selectedTab = selectedTabFromIndex(index)
            case None => ()
        }
        // A presentation can finish while Dashboard is covered by the request /
        // PIN / success route. Always refresh on entering History as a lifecycle
        // backstop, even if the write-time notification happened while this tab
        // was not mounted.
        if (index == 2) {
            NotificationCenter.post(NotificationName.TransactionTabRefresh)
            this.reloadToolbarCounts()
        }
    }

    private func currentRouter(): ?RouterHost {
        match (this.vm) {
            case Some(model) => Some(model.router)
            case None => Option<RouterHost>.None
        }
    }

    private func currentViewModel(): ?DashboardViewModel {
        this.vm
    }

    private func onSideMenu(): Unit {
        match (this.vm) {
            case Some(model) => model.onSideMenu()
            case None => ()
        }
    }

    private func onAddDocument(): Unit {
        match (this.vm) {
            case Some(model) => model.onAddDocument()
            case None => ()
        }
    }

    // ── Shared nav bar (ONE instance across all tabs) ─────────────────────────
    // Mirrors iOS: DashboardView owns the nav bar; switching tabs only swaps the
    // centered title + trailing actions — the leading menu button is the same
    // persistent element, never rebuilt per tab.

    private func titleText(): String {
        match (this.selectedIndex) {
            case 1 => LocalizableManager.get(LocalizableStringKey.documents)
            case 2 => LocalizableManager.get(LocalizableStringKey.historyTitle)
            case _ => LocalizableManager.get(LocalizableStringKey.home)
        }
    }

    @Builder
    func trailingActions() {
        // Home (0): no trailing actions. Documents (1): +/filter pill.
        // History (2): filter-only pill. Filter grays out when the tab has no rows.
        if (this.selectedIndex == 1) {
            Row(space: 0.0) {
                Row {
                    AppIcon(token: ThemeManager.shared.image.plusAccent, size: 22.0)
                }
                .width(46.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .onClick({ _ => this.onAddDocument() })
                NavFilterButton(enabledFlag: this.docHasAny, forDocuments: true)
            }
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
        } else if (this.selectedIndex == 2) {
            Row(space: 0.0) {
                NavFilterButton(enabledFlag: this.txHasAny, forDocuments: false)
            }
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
        }
    }

    @Builder
    func sharedTopBar() {
        Stack(alignContent: Alignment.Center) {
            Text(this.titleText())
                // iOS uses an inline nav title (~17pt), not a large title. Match
                // bodyLarge (Body ~17) like the other screens' nav bars; 22 was
                // noticeably bigger than iOS.
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            Row {
                Row {
                    AppIcon(
                        token: ThemeManager.shared.image.menuIcon,
                        size: 25.0,
                        color: uiColor(ThemeManager.shared.color.primaryLabel)
                    )
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
                .onClick({ _ => this.onSideMenu() })
                Row {}.layoutWeight(1)
                this.trailingActions()
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Center)
        }
        .width(100.percent)
        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }

    /** Apply + close for the Documents filter sheet (list refreshes via notify). */
    private func applyDocFilters(): Unit {
        this.showDocFilters = false
        match (this.vm) {
            case Some(model) =>
                let _ = model.documentApplyFilters()
                NotificationCenter.post(NotificationName.DocumentTabRefresh)
            case None => ()
        }
    }

    /** Apply + close for the History filter sheet. */
    private func applyTxFilters(): Unit {
        this.showTxFilters = false
        match (this.vm) {
            case Some(model) =>
                // iOS confirmation calls TransactionTabViewModel.fetch(); that
                // path updates the list and then commits/applies the snapshot.
                NotificationCenter.post(NotificationName.TransactionTabRefresh)
            case None => ()
        }
    }

    /** iOS handleRevocationNotification: ignored while the modal is already up or the dashboard is paused. */
    private func handleRevocationNotification(rows: Array<RevokedDocumentRow>): Unit {
        if (rows.size == 0 || this.showRevokedSheet || this.isPaused) {
            return
        }
        this.revokedRows = rows
        this.showRevokedSheet = true
    }

    private func dismissRevokedSheet(): Unit {
        this.showRevokedSheet = false
        this.revokedRows = Array<RevokedDocumentRow>()
    }

    private func dismissIssuedSheet(): Unit {
        this.showIssuedSheet = false
        this.issuedRows = Array<DocumentRow>()
        DashboardOverlayData.shared.issuedRows = Array<DocumentRow>()
    }

    /**
     * "Documents issued" bottom sheet — mirrors iOS DocumentTabView.sheetDialog.
     * Rendered at the dashboard layer so it covers the floating tab bar.
     */
    @Builder
    private func issuedSheet() {
        Stack(alignContent: Alignment.Bottom) {
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                .transition(TransitionEffect.OPACITY.animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))
                .onClick({ _ => this.dismissIssuedSheet() })
            Column(space: SPACING_SMALL) {
                Text(LocalizableManager.get(LocalizableStringKey.deferredDocumentsIssuedModalTitle))
                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                Text(LocalizableManager.get(LocalizableStringKey.defferedDocumentsIssuedModalCaption))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                Column(space: SPACING_SMALL) {
                    ForEach(
                        this.issuedRows,
                        itemGenerator: { row: DocumentRow, _: Int64 =>
                            Row {
                                Text(row.title)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .layoutWeight(1)
                                    .textAlign(TextAlign.Start)
                                Image(appImageSrc(ThemeManager.shared.image.chevronRight))
                                    .width(16.0)
                                    .height(16.0)
                                    .objectFit(ImageFit.Contain)
                                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                            .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                            .borderRadius(8.0)
                            .onClick({ _ =>
                                let id = row.id
                                this.dismissIssuedSheet()
                                match (this.vm) {
                                    case Some(model) => model.onDocumentDetails(id)
                                    case None => ()
                                }
                            })
                        },
                        keyGenerator: { row: DocumentRow, _: Int64 => "issued_" + row.id }
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)
            }
            .width(100.percent)
            .padding(SPACING_LARGE)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .borderRadius(topLeft: 24.0, topRight: 24.0, bottomLeft: 0.0, bottomRight: 0.0)
            .transition(TransitionEffect.move(TransitionEdge.Bottom).animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))
        }
        .width(100.percent)
        .height(100.percent)
    }

    /**
     * "Revoked documents" bottom sheet — mirrors iOS DashboardView.sheetDialog
     * (ContentTitleView + revokedNotificationList). A row opens the document
     * details, closing the sheet first (iOS onDocumentDetails).
     */
    @Builder
    private func revokedSheet() {
        Stack(alignContent: Alignment.Bottom) {
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                .transition(TransitionEffect.OPACITY.animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))
                .onClick({ _ => this.dismissRevokedSheet() })
            Column(space: SPACING_SMALL) {
                Text(LocalizableManager.get(LocalizableStringKey.revokedModalTitle))
                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                Text(LocalizableManager.get(LocalizableStringKey.revokedModalDescription))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                Column(space: SPACING_SMALL) {
                    ForEach(
                        this.revokedRows,
                        itemGenerator: { row: RevokedDocumentRow, _: Int64 =>
                            Row {
                                Text(row.name)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .layoutWeight(1)
                                    .textAlign(TextAlign.Start)
                                Image(appImageSrc(ThemeManager.shared.image.chevronRight))
                                    .width(16.0)
                                    .height(16.0)
                                    .objectFit(ImageFit.Contain)
                                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                            .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                            .borderRadius(8.0)
                            .onClick({ _ =>
                                let id = row.id
                                this.dismissRevokedSheet()
                                match (this.vm) {
                                    case Some(model) => model.onDocumentDetails(id)
                                    case None => ()
                                }
                            })
                        },
                        keyGenerator: { row: RevokedDocumentRow, _: Int64 => "revoked_" + row.id }
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)
            }
            .width(100.percent)
            .padding(SPACING_LARGE)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .borderRadius(topLeft: 24.0, topRight: 24.0, bottomLeft: 0.0, bottomRight: 0.0)
            .transition(TransitionEffect.move(TransitionEdge.Bottom).animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))
        }
        .width(100.percent)
        .height(100.percent)
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Bottom) {
                Column {
                    // ONE shared nav bar for all three tabs.
                    this.sharedTopBar()
                    Stack(alignContent: Alignment.Bottom) {
                        Tabs(barPosition: BarPosition.End, index: this.selectedIndex) {
                            TabContent() {
                                HomeTabView(viewModel: this.currentViewModel(), router: this.currentRouter())
                            }

                            TabContent() {
                                DocumentTabView(viewModel: this.currentViewModel())
                            }

                            TabContent() {
                                TransactionTabView(viewModel: this.currentViewModel())
                            }
                        }
                        .barHeight(0.0)
                        .scrollable(false)
                        .onChange({ index: Int32 =>
                            this.onTabChange(index)
                        })
                        .width(100.percent)
                        .height(100.percent)

                        FloatingTabBar(
                            selectedIndex: this.selectedIndex,
                            onTabTap: { idx: Int32 => this.onTabChange(idx) }
                        )
                    }
                    .layoutWeight(1)
                    .width(100.percent)
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(uiColor(ThemeManager.shared.color.background))

                // Sheets presented ABOVE the nav bar + floating tab bar
                // (mirrors iOS .sheet, which always covers the TabView).
                if (this.showDocFilters) {
                    FiltersListView(
                        viewModel: this.currentViewModel(),
                        isTransaction: false,
                        onApply: { => this.applyDocFilters() },
                        onRevert: { => this.showDocFilters = false }
                    )
                }
                if (this.showTxFilters) {
                    FiltersListView(
                        viewModel: this.currentViewModel(),
                        isTransaction: true,
                        minDate: DashboardOverlayData.shared.txMinDate,
                        maxDate: DashboardOverlayData.shared.txMaxDate,
                        onApply: { => this.applyTxFilters() },
                        onRevert: { => this.showTxFilters = false }
                    )
                }
                if (this.showIssuedSheet) {
                    this.issuedSheet()
                }
                if (this.showRevokedSheet) {
                    this.revokedSheet()
                }
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
        // Home root: consume the system Back so it cannot pop back to the PIN /
        // splash screens (mirrors iOS, where the dashboard is the root and Back
        // does nothing). Without this, Back unwound to the dead-end splash.
        .onBackPressed({ => true })
    }
}

/** One row of the revoked-documents sheet (iOS `revokedDocuments` entry: displayName -> id). */
public class RevokedDocumentRow {
    public let name: String
    public let id: String

    public init(name: String, id: String) {
        this.name = name
        this.id = id
    }
}

/** iOS lists `revokedDocuments.sorted(by: >)`: descending by display name. */
public func revokedRowsFrom(map: HashMap<String, String>): Array<RevokedDocumentRow> {
    let rows = ArrayList<RevokedDocumentRow>()
    for ((name, id) in map) {
        rows.add(RevokedDocumentRow(name, id))
    }
    rows.sortBy(stable: true, comparator: { a: RevokedDocumentRow, b: RevokedDocumentRow => b.name.compare(a.name) })
    return rows.toArray()
}

/**
 * Default DashboardViewModel factory for emulator / preview use.
 * The composition root (app-shell) supplies a properly wired instance;
 * this fallback uses InMemoryRouterHost so the page can be launched
 * standalone without crashing.
 */
func makeDefaultDashboardViewModel(): DashboardViewModel {
    return DashboardViewModel(router: InMemoryRouterHost())
}

// Floating tab-bar geometry (vp). Each of the 3 tab slots is TABBAR_ITEM_W wide;
// the sliding highlight pill is TABBAR_PILL_W wide, centred within a slot.
let TABBAR_ITEM_W: Float64 = 100.0
let TABBAR_PILL_W: Float64 = 88.0
let TABBAR_BAR_H: Float64 = 46.0

/**
 * Floating capsule bottom navigation bar (mirrors iOS 18/26's default floating
 * TabView). The default ArkUI Tabs bar renders a flat full-width strip, which does
 * not match iOS — so the built-in bar is hidden (barHeight 0) and this capsule is
 * overlaid at the bottom of the dashboard Stack.
 *
 * This is a standalone @Component (not an inline @Builder) on purpose: `selectedIndex`
 * is a @Prop, so when the parent's selection changes the component re-renders and the
 * highlight reliably moves to exactly the active tab. An inline @Builder was cached by
 * ArkUI and left the highlight stuck on the previously-selected tab even though the
 * page content had switched.
 *
 * The selected tab gets a rounded accent-tinted pill and switches its icon to the
 * `.selected` (accent-blue) PNG variant; the change is animated. Icons are clean
 * monochrome PNGs resolved via appImageSrc() — the iOS SF-symbol tokens
 * (house.fill / doc.fill / clock.fill) themselves resolve to nothing on ArkUI.
 */
@Component
class FloatingTabBar {
    @Prop
    var selectedIndex: Int32

    var onTabTap: (Int32) -> Unit = { _ => }

    // X-translation (vp) of the single pill so it sits under the selected slot.
    func pillX(): Int64 {
        return Int64(Float64(this.selectedIndex) * TABBAR_ITEM_W + (TABBAR_ITEM_W - TABBAR_PILL_W) / 2.0)
    }

    @Builder
    func barItem(index: Int32, iconToken: String, label: String) {
        Column(space: 0.0) {
            Image(appImageSrc(if (this.selectedIndex == index) {
                iconToken + ".selected"
            } else {
                iconToken
            }))
                .width(34.0)
                .height(34.0)
                .objectFit(ImageFit.Contain)
            Text(label)
                .fontSize(uiFontSize(ThemeManager.shared.font.labelSmall))
                .fontWeight(FontWeight.Medium)
                .margin(top: -6.0, right: 0.0, bottom: 0.0, left: 0.0)
                // iOS: selected label is blue (accent), unselected is pure black.
                .fontColor(if (this.selectedIndex == index) {
                    uiColor(ThemeManager.shared.color.accent)
                } else {
                    uiColor(ThemeManager.shared.color.primaryLabel)
                })
        }
        .layoutWeight(1)
        .height(TABBAR_BAR_H)
        .justifyContent(FlexAlign.Center)
        .onClick({ _ => this.onTabTap(index) })
    }

    public func build() {
        Stack(alignContent: Alignment.TopStart) {
            // Single highlight pill (behind the items). Only one ever exists, so a
            // selection change SLIDES it to the new slot via the translate
            // animation — no cross-fade of two pills (which looked like two tabs
            // highlighted at once).
            Column() {}
                .width(TABBAR_PILL_W)
                .height(TABBAR_BAR_H)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.fill))
                .translate(x: this.pillX().vp, y: 0.vp)
                .animation(AnimateParam(duration: 260, curve: Curve.Smooth))

            Row(space: 0.0) {
                this.barItem(0, ThemeManager.shared.image.houseFill,
                    LocalizableManager.get(LocalizableStringKey.home))
                this.barItem(1, ThemeManager.shared.image.docFill,
                    LocalizableManager.get(LocalizableStringKey.documents))
                this.barItem(2, ThemeManager.shared.image.clockIndicator,
                    LocalizableManager.get(LocalizableStringKey.historyTitle))
            }
            .width(TABBAR_ITEM_W * 3.0)
            .height(TABBAR_BAR_H)
        }
        .padding(top: 5.0, right: 6.0, bottom: 5.0, left: 6.0)
        // iOS floating TabView bar material (verified by screen recording):
        // content passes UNDER the bar and shows through the blur — no white
        // fade layer, just a translucent blurred capsule.
        .backgroundColor(Color(0xB8FFFFFFu32))
        .backdropBlur(28.0)
        .borderRadius(28.0)
        .shadow(radius: 16.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 4.0)
        .margin(left: 0.0, right: 0.0, top: 0.0, bottom: 4.0)
    }
}


/**
 * Dashboard-layer overlay payload carrier: the tabs produce data on their own
 * threads/scopes and the DashboardView (which owns the full-screen overlays)
 * consumes it after a NotificationCenter signal. Mirrors the DashboardNavArgs
 * hand-off pattern.
 */
public class DashboardOverlayData {
    private static let instance: DashboardOverlayData = DashboardOverlayData()

    /** Rows for the "Documents issued" sheet (DeferredDocsIssued). */
    public var issuedRows: Array<DocumentRow> = Array<DocumentRow>()
    /** History filter sheet date-picker bounds (computed by the History tab). */
    public var txMinDate: DateTime = DateTime.now()
    public var txMaxDate: DateTime = DateTime.now()

    private init() {}

    public static prop shared: DashboardOverlayData {
        get() { instance }
    }
}


/**
 * Shared-nav-bar trailing filter button. A standalone @Component with @Prop —
 * NOT an inline @Builder: ArkUI cached the nested builder output, so the icon
 * stayed on the disabled (gray) art even after docHasAny flipped true (the
 * same caching bug FloatingTabBar hit with its highlight pill).
 */
@Component
class NavFilterButton {
    @Prop
    var enabledFlag: Bool
    /** true → Documents filter; false → History filter. */
    var forDocuments: Bool = true

    private func iconToken(): String {
        if (this.enabledFlag) {
            // iOS: the filter action has no explicit tint → it renders in the
            // default nav-bar tint (black label), NOT accent blue (the '+' is the
            // only accent-tinted action).
            return ThemeManager.shared.image.filterMenuIconBlack
        }
        return ThemeManager.shared.image.filterMenuIconDisabled
    }

    private func fire(): Unit {
        if (this.forDocuments) {
            NotificationCenter.post(NotificationName.DocumentOpenFilters)
        } else {
            NotificationCenter.post(NotificationName.TransactionOpenFilters)
        }
    }

    public func build() {
        Row {
            // Slightly larger than the '+' — the filter glyph reads smaller than
            // iOS at 22.
            Image(appImageSrc(this.iconToken()))
                .width(25.0)
                .height(25.0)
                .objectFit(ImageFit.Contain)
        }
        .width(46.0)
        .height(40.0)
        .justifyContent(FlexAlign.Center)
        .enabled(this.enabledFlag)
        .onClick({ _ => this.fire() })
    }
}
