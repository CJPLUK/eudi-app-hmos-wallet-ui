/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/SideMenu/SideMenuView.swift + SideMenuViewModel.swift +
 * UI/SideMenu/Model/SideMenuItemUIModel.swift) to Cangjie.
 *
 * The side menu is the "My EU Wallet" drawer reached from the dashboard toolbar.
 * It lists two actions, mirroring iOS exactly:
 *   - Change quick-PIN  → push the QuickPin update flow (AppRoutes.quickPin)
 *   - Settings          → push the settings screen (AppRoutes.settingsMenu)
 * NavDestination root (D-002), registered under AppRoutes.sideMenu.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.collection.ArrayList
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, ToolBarContent, ToolBarAction,
    uiColor, uiFontSize, NavArgs, RouteConfigArgs,
    SPACING_SMALL, SPACING_MEDIUM, SPACING_MEDIUM_SMALL, SPACING_LARGE_MEDIUM, appImageSrc, AppIcon,
    ListDividerView
}
import eudi_feature_common.{QuickPinUiConfig, QuickPinFlow}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

// Stable side-menu row ids (used by the view to route taps).
let SIDEMENU_ID_PIN: String = "changePin"
let SIDEMENU_ID_SETTINGS: String = "settings"

/** Flat, render-ready side-menu row. Mirrors iOS SideMenuItemUIModel. */
public class SideMenuItem {
    public let id: String
    public let title: LocalizableStringKey
    public let iconSrc: String
    public let showDivider: Bool

    public init(id!: String, title!: LocalizableStringKey, iconSrc!: String, showDivider!: Bool = true) {
        this.id = id
        this.title = title
        this.iconSrc = iconSrc
        this.showDivider = showDivider
    }
}

/** Mirrors Swift `SideMenuViewState`. */
public class SideMenuViewState <: ViewState {
    public let items: Array<SideMenuItem>

    public init(items!: Array<SideMenuItem> = Array<SideMenuItem>()) {
        this.items = items
    }
}

/** Mirrors Swift `SideMenuViewModel<Router>`. */
public class SideMenuViewModel <: BaseViewModel<SideMenuViewState> {
    public init(router!: RouterHost) {
        super(router, SideMenuViewState())
        this.buildMenuItems()
    }

    public func toolbarContent(): ToolBarContent {
        ToolBarContent(
            leadingActions: [
                ToolBarAction(
                    iconSrc: ThemeManager.shared.image.chevronLeft,
                    callback: { => this.router.pop() }
                )
            ]
        )
    }

    /** Mirrors iOS updatePin(): push the QuickPin **update** flow (verify the
     *  current PIN first, cancellable with a leading back). Without an explicit
     *  Update config the route falls back to a Set flow (no back, wrong copy). */
    public func onUpdatePin(): Unit {
        NavArgs.shared.set(
            AppRoutes.quickPin,
            RouteConfigArgs(QuickPinUiConfig(flow: QuickPinFlow.Update))
        )
        this.router.push(AppRoutes.quickPin)
    }

    /** Mirrors iOS settings(): push the settings screen. */
    public func onSettings(): Unit {
        this.router.push(AppRoutes.settingsMenu)
    }

    private func buildMenuItems(): Unit {
        let items = ArrayList<SideMenuItem>()
        items.add(
            SideMenuItem(
                id: SIDEMENU_ID_PIN,
                title: LocalizableStringKey.changeQuickPinOption,
                iconSrc: ThemeManager.shared.image.changePin,
                showDivider: true
            )
        )
        items.add(
            SideMenuItem(
                id: SIDEMENU_ID_SETTINGS,
                title: LocalizableStringKey.settings,
                iconSrc: ThemeManager.shared.image.gearshape,
                showDivider: false
            )
        )
        this.setState({ _ => SideMenuViewState(items: items.toArray()) })
    }
}

/** Side-menu screen. NavDestination root (D-002), route key AppRoutes.sideMenu. */
@Component
public class SideMenuView {
    public var viewModel: ?SideMenuViewModel = Option<SideMenuViewModel>.None

    @State
    var items: Array<SideMenuItem> = Array<SideMenuItem>()

    private var vm: ?SideMenuViewModel = Option<SideMenuViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.items = state.items
                    }
                })
                this.items = model.viewState.items
            case None => ()
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    private func onRowTap(item: SideMenuItem): Unit {
        match (this.vm) {
            case Some(model) =>
                if (item.id == SIDEMENU_ID_PIN) {
                    model.onUpdatePin()
                } else if (item.id == SIDEMENU_ID_SETTINGS) {
                    model.onSettings()
                }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                Scroll {
                    // iOS side menu is a plain grouped list: flat rows on the page
                    // background with a hairline divider between rows (no per-row
                    // card). Mirror that instead of individual rounded cards.
                    Column(space: 0.0) {
                        ForEach(
                            this.items,
                            itemGenerator: { item: SideMenuItem, idx: Int64 =>
                                Column(space: 0.0) {
                                    Row(space: SPACING_MEDIUM) {
                                        // iOS renders these as accent (blue) SF
                                        // symbols; tint the icon accent to match.
                                        AppIcon(
                                            token: item.iconSrc,
                                            size: 24.0,
                                            color: uiColor(ThemeManager.shared.color.accent)
                                        )
                                        Text(LocalizableManager.get(item.title))
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .textAlign(TextAlign.Start)
                                            // Constrain the line box so the label cannot
                                            // stretch the row (Row + big Text trap).
                                            .height(24.0)
                                            .layoutWeight(1)
                                        Image(appImageSrc(ThemeManager.shared.image.chevronRightAccent))
                                            .width(18.0)
                                            .height(18.0)
                                            .objectFit(ImageFit.Contain)
                                    }
                                    .width(100.percent)
                                    .height(44.0)
                                    .onClick({ _ => this.onRowTap(item) })
                                    if (idx < Int64(this.items.size) - 1) {
                                        // iOS Divider spans the full cell width.
                                        ListDividerView(spacing: 0.0)
                                    }
                                }
                                .width(100.percent)
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(
                        top: 0.0,
                        right: SPACING_MEDIUM,
                        bottom: SPACING_LARGE_MEDIUM,
                        left: SPACING_MEDIUM
                    )
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    @Builder
    private func toolbar() {
        Row(space: SPACING_SMALL) {
            // iOS back affordance: chevron inside a circular white button with a
            // soft shadow (matches the Home menu button), not a bare glyph.
            Row {
                Image(appImageSrc(ThemeManager.shared.image.chevronLeft))
                    .width(20.0)
                    .height(20.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
            .onClick({ _ => this.onBack() })
            Text(LocalizableManager.get(LocalizableStringKey.myEuWallet))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .height(40.0)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            // Transparent 40-wide spacer mirrors the leading circular back button
            // so the centered title sits at the true screen center.
            Row {}
                .width(40.0)
                .height(40.0)
        }
        .width(100.percent)
        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }
}
