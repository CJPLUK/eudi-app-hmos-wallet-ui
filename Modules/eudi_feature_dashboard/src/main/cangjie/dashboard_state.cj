/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (DashboardViewModel.swift: DashboardState, SelectedTab) to Cangjie.
 *
 * M1 scope: state carries toolbar/title only; document/transaction tabs render
 * the real empty state (no data source yet — logic-storage/wallet-kit pending).
 */
package eudi_feature_dashboard

import eudi_logic_ui.{ViewState, ToolBarContent}
import eudi_logic_resources.{LocalizableStringKey}

/**
 * Mirrors Swift `SelectedTab` enum (home / documents / history).
 * Integers map to Tabs index (0=Home, 1=Documents, 2=History).
 */
public enum SelectedTab {
    | Home
    | Documents
    | History

    /** Int32 index for Tabs.index / onChange mapping. */
    public func toIndex(): Int32 {
        match (this) {
            case SelectedTab.Home      => 0
            case SelectedTab.Documents => 1
            case SelectedTab.History   => 2
        }
    }
}

/** Construct SelectedTab from a Tabs onChange Int32 index. */
public func selectedTabFromIndex(index: Int32): SelectedTab {
    match (index) {
        case 0  => SelectedTab.Home
        case 1  => SelectedTab.Documents
        case 2  => SelectedTab.History
        case _  => SelectedTab.Home
    }
}

/**
 * Mirrors Swift `DashboardState<Router>: ViewState`.
 * M1: navigationTitle always empty (title driven by selected tab internally);
 * toolBarContent empty (no settings/side-menu actions yet).
 * isPaused tracks scene foreground/background transitions.
 */
public class DashboardState <: ViewState {
    public let navigationTitle: LocalizableStringKey
    public let toolBarContent: ToolBarContent
    public let isPaused: Bool

    public init(
        navigationTitle!: LocalizableStringKey = LocalizableStringKey.custom(""),
        toolBarContent!: ToolBarContent = ToolBarContent(),
        isPaused!: Bool = false
    ) {
        this.navigationTitle = navigationTitle
        this.toolBarContent = toolBarContent
        this.isPaused = isPaused
    }
}
