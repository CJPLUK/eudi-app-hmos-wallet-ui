/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Toolbar/ToolBarContent.swift) to Cangjie ArkUI.
 *
 * SwiftUI `ToolbarContent` hangs off the navigation bar; this HAR ships no
 * NavDestination chrome (the navigation shell belongs to the composition
 * root), so pages draw their own chrome: `ToolBarContent` stays the data
 * model and `ToolBarView` renders it as a leading/trailing action row.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Mirrors Swift `ToolBarContent.Action`: title and/or image, optional
 * notification indicator, disabled flag, tint and prominence, plus callback.
 */
public class ToolBarAction {
    public let title: ?LocalizableStringKey
    public let iconSrc: String
    public let hasIndicator: Bool
    public let disabled: Bool
    public let tintColor: ?Color
    public let isBorderedProminent: Bool
    public let callback: () -> Unit

    public init(
        title!: ?LocalizableStringKey = None,
        iconSrc!: String = "",
        hasIndicator!: Bool = false,
        disabled!: Bool = false,
        tintColor!: ?Color = None,
        isBorderedProminent!: Bool = false,
        callback!: () -> Unit = { => }
    ) {
        this.title = title
        this.iconSrc = iconSrc
        this.hasIndicator = hasIndicator
        this.disabled = disabled
        this.tintColor = tintColor
        this.isBorderedProminent = isBorderedProminent
        this.callback = callback
    }

    public func titleText(): String {
        ListItemData.optText(this.title)
    }

    public func resolvedTint(): Color {
        match (this.tintColor) {
            case Some(color) => color
            case None => uiColor(ThemeManager.shared.color.accent)
        }
    }

    public func backgroundFill(): Color {
        if (this.isBorderedProminent) {
            return this.resolvedTint()
        }
        return Color.Transparent
    }

    public func foregroundFill(): Color {
        if (this.isBorderedProminent) {
            return uiColor(ThemeManager.shared.color.white)
        }
        return this.resolvedTint()
    }
}

/**
 * Mirrors Swift `ToolBarContent`: leading + trailing action groups.
 */
public class ToolBarContent {
    public let leadingActions: Array<ToolBarAction>
    public let trailingActions: Array<ToolBarAction>

    public init(
        leadingActions!: Array<ToolBarAction> = Array<ToolBarAction>(),
        trailingActions!: Array<ToolBarAction> = Array<ToolBarAction>()
    ) {
        this.leadingActions = leadingActions
        this.trailingActions = trailingActions
    }

    public func isEmpty(): Bool {
        this.leadingActions.size == 0 && this.trailingActions.size == 0
    }
}

/**
 * Self-drawn toolbar row for `ContentScreenView` (this HAR renders no
 * system title bar — pages draw their own chrome). Actions are
 * rendered with built-in components only — no custom @Component inside the
 * ForEach item generator (syntax_error R-102).
 */
@Component
public class ToolBarView {
    public var content: ToolBarContent = ToolBarContent()
    public var isEnabled: Bool = true
    public var toolbarBackgroundColor: Color = uiColor(ThemeManager.shared.color.background)

    private func runAction(action: ToolBarAction): Unit {
        if (this.isEnabled && !action.disabled) {
            action.callback()
        }
    }

    private func actionOpacity(action: ToolBarAction): Float64 {
        if (action.disabled || !this.isEnabled) {
            return 0.38
        }
        return 1.0
    }

    public func build() {
        Row(space: SPACING_SMALL) {
            ForEach(
                this.content.leadingActions,
                itemGenerator: { action: ToolBarAction, _: Int64 =>
                    Row(space: SPACING_EXTRA_SMALL) {
                        if (!action.iconSrc.isEmpty()) {
                            Image(action.iconSrc)
                                .width(24.0)
                                .height(24.0)
                                .objectFit(ImageFit.Contain)
                                .fillColor(action.foregroundFill())
                        }
                        if (!action.titleText().isEmpty()) {
                            Text(action.titleText())
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                .fontColor(action.foregroundFill())
                        }
                        if (action.hasIndicator) {
                            Column() {}
                                .width(10.0)
                                .height(10.0)
                                .borderRadius(5.0)
                                .backgroundColor(uiColor(ThemeManager.shared.color.accent))
                        }
                    }
                    .padding(SPACING_EXTRA_SMALL)
                    .backgroundColor(action.backgroundFill())
                    .borderRadius(ThemeManager.shared.shape.extraSmall)
                    .opacity(this.actionOpacity(action))
                    .onClick({ _ => this.runAction(action) })
                }
            )
            Blank()
            ForEach(
                this.content.trailingActions,
                itemGenerator: { action: ToolBarAction, _: Int64 =>
                    Row(space: SPACING_EXTRA_SMALL) {
                        if (!action.iconSrc.isEmpty()) {
                            Image(action.iconSrc)
                                .width(24.0)
                                .height(24.0)
                                .objectFit(ImageFit.Contain)
                                .fillColor(action.foregroundFill())
                        }
                        if (!action.titleText().isEmpty()) {
                            Text(action.titleText())
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                .fontColor(action.foregroundFill())
                        }
                        if (action.hasIndicator) {
                            Column() {}
                                .width(10.0)
                                .height(10.0)
                                .borderRadius(5.0)
                                .backgroundColor(uiColor(ThemeManager.shared.color.accent))
                        }
                    }
                    .padding(SPACING_EXTRA_SMALL)
                    .backgroundColor(action.backgroundFill())
                    .borderRadius(ThemeManager.shared.shape.extraSmall)
                    .opacity(this.actionOpacity(action))
                    .onClick({ _ => this.runAction(action) })
                }
            )
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
        .backgroundColor(this.toolbarBackgroundColor)
    }
}
