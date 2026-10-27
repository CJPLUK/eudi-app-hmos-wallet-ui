/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/SearchableList/SearchableListView.swift) to
 * Cangjie ArkUI.
 *
 * The SwiftUI `searchable` modifier (UISearchBar over arbitrary content)
 * becomes a self-contained component: a Search field above a filtered
 * ListItemData list. Rows are drawn with built-in components only —
 * no custom @Component inside the ForEach item generator (R-102).
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import std.collection.ArrayList
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Searchable list over `ListItemData` rows. Filtering is ASCII
 * case-insensitive (S-008: toAsciiLower) across overline / main /
 * supporting texts. `onSearchTextChange` mirrors the iOS callback;
 * `onItemClick` receives the tapped row. Pass real callbacks (S-017).
 */
@Component
public class SearchableList {
    public var items: Array<ListItemData> = Array<ListItemData>()
    public var searchPlaceholder: LocalizableStringKey = LocalizableStringKey.search
    public var onSearchTextChange: (String) -> Unit = { _ => }
    public var onItemClick: (ListItemData) -> Unit = { _ => }
    @State
    var query: String = ""

    private func placeholderText(): String {
        LocalizableManager.get(this.searchPlaceholder)
    }

    private func matches(item: ListItemData, needle: String): Bool {
        if (needle.isEmpty()) {
            return true
        }
        let haystack = (
            item.mainContent.asString() + " " +
            ListItemData.optText(item.overlineText) + " " +
            ListItemData.optText(item.supportingText)
        ).toAsciiLower()
        return haystack.contains(needle)
    }

    private func filtered(): Array<ListItemData> {
        let needle = this.query.toAsciiLower()
        let out = ArrayList<ListItemData>()
        for (item in this.items) {
            if (this.matches(item, needle)) {
                out.add(item)
            }
        }
        return out.toArray()
    }

    private func handleQuery(value: String): Unit {
        this.query = value
        this.onSearchTextChange(value)
    }

    public func build() {
        Column(space: SPACING_SMALL) {
            Search(value: this.query, placeholder: this.placeholderText())
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryBackground))
                .onChange({ value => this.handleQuery(value) })
                .onSubmit({ value => this.handleQuery(value) })
            Column {
                ForEach(
                    this.filtered(),
                    itemGenerator: { item: ListItemData, _: Int64 =>
                        Column(space: SPACING_EXTRA_SMALL) {
                            if (!ListItemData.optText(item.overlineText).isEmpty()) {
                                Text(ListItemData.optText(item.overlineText))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                    .fontColor(item.overlineTextColor)
                                    .textAlign(TextAlign.Start)
                                    .width(100.percent)
                            }
                            if (!item.mainContent.asString().isEmpty()) {
                                Text(item.mainContent.asString())
                                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                    .fontWeight(FontWeight.Medium)
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .textAlign(TextAlign.Start)
                                    .width(100.percent)
                            }
                            if (!ListItemData.optText(item.supportingText).isEmpty()) {
                                Text(ListItemData.optText(item.supportingText))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                    .fontColor(item.supportingTextColor)
                                    .textAlign(TextAlign.Start)
                                    .width(100.percent)
                            }
                            Divider()
                                .color(uiColor(ThemeManager.shared.color.separator))
                                .strokeWidth(1.0)
                        }
                        .width(100.percent)
                        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: 0.0, left: SPACING_MEDIUM)
                        .onClick({ _ => this.onItemClick(item) })
                    },
                    keyGenerator: { item: ListItemData, _: Int64 => item.id }
                )
            }
            .width(100.percent)
            .justifyContent(FlexAlign.Start)
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }
}
