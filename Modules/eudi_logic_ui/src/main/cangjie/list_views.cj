/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/List/ListItemData.swift, WrapListItemView.swift,
 * ListDividerView.swift, DesignSystem/EasySpacer.swift) to Cangjie ArkUI.
 *
 * Swift enums with associated values (MainContent / TrailingContent) become
 * factory-built classes exposing `is*()` discriminators, so `build()` bodies
 * stay match-free (syntax_error R-103).
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

// ─── Spacing scale (DesignSystem/EasySpacer.swift) ──────────────────────

public let SPACING_NONE: Float64 = 0.0
public let SPACING_EXTRA_SMALL: Float64 = 4.0
public let SPACING_SMALL: Float64 = 8.0
public let SPACING_MEDIUM_SMALL: Float64 = 12.0
public let SPACING_MEDIUM: Float64 = 16.0
public let SPACING_MEDIUM_LARGE: Float64 = 20.0
public let SPACING_LARGE_MEDIUM: Float64 = 24.0
public let SPACING_LARGE: Float64 = 32.0
public let SPACING_EXTRA_LARGE: Float64 = 48.0
public let SPACING_JUMBO: Float64 = 96.0

/**
 * Fixed spacer. Mirrors the iOS `VSpacer` / `HSpacer` factories: set
 * `spacerHeight` for vertical gaps, `spacerWidth` for horizontal gaps.
 */
@Component
public class EasySpacer {
    public var spacerWidth: Float64 = 0.0
    public var spacerHeight: Float64 = 0.0

    public func build() {
        Column() {}
            .width(this.spacerWidth)
            .height(this.spacerHeight)
    }
}

// ─── ListItemData model family ──────────────────────────────────────────

/** Mirrors Swift `ListItemData.MainStyle` (plain / bold). */
public enum ListItemMainStyle {
    | MainPlain
    | MainBold

    public func isBold(): Bool {
        match (this) {
            case MainBold => true
            case MainPlain => false
        }
    }
}

/**
 * Mirrors Swift `MainContent` (.text / .image). `imageSrc` empty means the
 * text form.
 */
public class MainContentData {
    public let text: LocalizableStringKey
    public let imageSrc: String

    private init(text: LocalizableStringKey, imageSrc: String) {
        this.text = text
        this.imageSrc = imageSrc
    }

    public static func ofText(text: LocalizableStringKey): MainContentData {
        MainContentData(text, "")
    }

    public static func ofImage(imageSrc: String): MainContentData {
        MainContentData(LocalizableStringKey.custom(""), imageSrc)
    }

    public func isImage(): Bool {
        !this.imageSrc.isEmpty()
    }

    /** Mirrors Swift `MainContent.asString` (empty for images). */
    public func asString(): String {
        if (this.isImage()) {
            return ""
        }
        return LocalizableManager.get(this.text)
    }

    public operator func ==(that: MainContentData): Bool {
        this.imageSrc == that.imageSrc && this.asString() == that.asString()
    }

    public operator func !=(that: MainContentData): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `LeadingIcon` (imageUrl / image). `imageUrl` non-empty wins;
 * otherwise `iconSrc` is used as a local image source.
 */
public class LeadingIconData {
    public let imageUrl: String
    public let iconSrc: String

    public init(imageUrl!: String = "", iconSrc!: String = "") {
        this.imageUrl = imageUrl
        this.iconSrc = iconSrc
    }

    public func hasRemote(): Bool {
        !this.imageUrl.isEmpty()
    }

    public operator func ==(that: LeadingIconData): Bool {
        this.imageUrl == that.imageUrl && this.iconSrc == that.iconSrc
    }

    public operator func !=(that: LeadingIconData): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `TrailingContent` (.textWithIcon / .icon / .checkbox /
 * .empty) as a factory-built class with discriminators usable in build().
 */
public class TrailingContentData {
    public let kind: String
    public let iconSrc: String
    public let iconColor: Color
    public let text: LocalizableStringKey
    public let isChecked: Bool
    public let checkboxEnabled: Bool
    public let onToggle: (Bool) -> Unit

    private init(
        kind: String,
        iconSrc: String,
        iconColor: Color,
        text: LocalizableStringKey,
        isChecked: Bool,
        checkboxEnabled: Bool,
        onToggle: (Bool) -> Unit
    ) {
        this.kind = kind
        this.iconSrc = iconSrc
        this.iconColor = iconColor
        this.text = text
        this.isChecked = isChecked
        this.checkboxEnabled = checkboxEnabled
        this.onToggle = onToggle
    }

    public static func icon(iconSrc: String, color!: ?Color = None): TrailingContentData {
        TrailingContentData(
            "icon", iconSrc, TrailingContentData.tint(color),
            LocalizableStringKey.custom(""), false, true, { _ => }
        )
    }

    public static func textWithIcon(
        iconSrc: String,
        color!: ?Color = None,
        text!: LocalizableStringKey = LocalizableStringKey.custom("")
    ): TrailingContentData {
        TrailingContentData(
            "text_with_icon", iconSrc, TrailingContentData.tint(color),
            text, false, true, { _ => }
        )
    }

    public static func checkbox(
        enabled: Bool,
        isChecked: Bool,
        onToggle: (Bool) -> Unit
    ): TrailingContentData {
        TrailingContentData(
            "checkbox", "", TrailingContentData.tint(Option<Color>.None),
            LocalizableStringKey.custom(""), isChecked, enabled, onToggle
        )
    }

    public static func empty(): TrailingContentData {
        TrailingContentData(
            "empty", "", TrailingContentData.tint(Option<Color>.None),
            LocalizableStringKey.custom(""), false, true, { _ => }
        )
    }

    private static func tint(color: ?Color): Color {
        match (color) {
            case Some(c) => c
            case None => uiColor(ThemeManager.shared.color.accent)
        }
    }

    public func isIcon(): Bool {
        this.kind == "icon"
    }

    public func isTextWithIcon(): Bool {
        this.kind == "text_with_icon"
    }

    public func isCheckbox(): Bool {
        this.kind == "checkbox"
    }

    public func textValue(): String {
        LocalizableManager.get(this.text)
    }

    /** Equality ignores the callback, like the Swift `==`. */
    public operator func ==(that: TrailingContentData): Bool {
        this.kind == that.kind && this.iconSrc == that.iconSrc &&
            this.textValue() == that.textValue() &&
            this.isChecked == that.isChecked &&
            this.checkboxEnabled == that.checkboxEnabled
    }

    public operator func !=(that: TrailingContentData): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `ListItemData` field-for-field:
 * id / groupId / mainContent / mainStyle / overlineText / supportingText /
 * supportingTextColor / overlineTextColor / leadingIcon / isBlur / isEnable /
 * trailingContent. Auto-generated ids replace `UUID().uuidString`.
 */
public class ListItemData {
    private static var idCounter: Int64 = 0

    public let id: String
    public let groupId: String
    public let mainContent: MainContentData
    public let mainStyle: ListItemMainStyle
    public let overlineText: ?LocalizableStringKey
    public let supportingText: ?LocalizableStringKey
    public let supportingTextColor: Color
    public let overlineTextColor: Color
    public let leadingIcon: ?LeadingIconData
    public let isBlur: Bool
    public let isEnable: Bool
    public let trailingContent: ?TrailingContentData

    public init(
        id!: String = ListItemData.nextId(),
        groupId!: ?String = None,
        mainContent!: MainContentData,
        mainStyle!: ListItemMainStyle = ListItemMainStyle.MainPlain,
        overlineText!: ?LocalizableStringKey = None,
        supportingText!: ?LocalizableStringKey = None,
        supportingTextColor!: Color = uiColor(ThemeManager.shared.color.secondaryLabel),
        overlineTextColor!: Color = uiColor(ThemeManager.shared.color.secondaryLabel),
        leadingIcon!: ?LeadingIconData = None,
        isBlur!: Bool = false,
        isEnable!: Bool = true,
        trailingContent!: ?TrailingContentData = None
    ) {
        this.id = id
        this.groupId = groupId ?? id
        this.mainContent = mainContent
        this.mainStyle = mainStyle
        this.overlineText = overlineText
        this.supportingText = supportingText
        this.supportingTextColor = supportingTextColor
        this.overlineTextColor = overlineTextColor
        this.leadingIcon = leadingIcon
        this.isBlur = isBlur
        this.isEnable = isEnable
        this.trailingContent = trailingContent
    }

    private static func nextId(): String {
        ListItemData.idCounter += 1
        return "list_item_${ListItemData.idCounter}"
    }

    static func optText(key: ?LocalizableStringKey): String {
        match (key) {
            case Some(k) => LocalizableManager.get(k)
            case None => ""
        }
    }

    /** Content equality; id/groupId excluded like Swift `@EquatableNoop`. */
    public operator func ==(that: ListItemData): Bool {
        if (this.mainContent != that.mainContent) {
            return false
        }
        if (this.mainStyle.isBold() != that.mainStyle.isBold()) {
            return false
        }
        if (ListItemData.optText(this.overlineText) != ListItemData.optText(that.overlineText)) {
            return false
        }
        if (ListItemData.optText(this.supportingText) != ListItemData.optText(that.supportingText)) {
            return false
        }
        if ((this.leadingIcon ?? LeadingIconData()) != (that.leadingIcon ?? LeadingIconData())) {
            return false
        }
        if ((this.trailingContent ?? TrailingContentData.empty()) != (that.trailingContent ?? TrailingContentData.empty())) {
            return false
        }
        if (this.supportingTextColor.toUInt32() != that.supportingTextColor.toUInt32() ||
            this.overlineTextColor.toUInt32() != that.overlineTextColor.toUInt32()) {
            return false
        }
        return this.isBlur == that.isBlur && this.isEnable == that.isEnable
    }

    public operator func !=(that: ListItemData): Bool {
        !(this == that)
    }
}

// ─── WrapListItemView ───────────────────────────────────────────────────

/**
 * Mirrors Swift `WrapListItemView`: a `ListItemData`-driven row with leading
 * icon, overline / main / supporting texts and trailing icon / text+icon /
 * checkbox content. `clickableEntireRow == false` reproduces
 * `ClickableArea.trailingContent` (only the checkbox toggles).
 */
@Component
public class WrapListItemView {
    public var listItem: ListItemData = ListItemData(mainContent: MainContentData.ofText(LocalizableStringKey.custom("")))
    public var clickableEntireRow: Bool = true
    public var isLoading: Bool = false
    public var rowPadding: Float64 = SPACING_MEDIUM
    public var onItemAction: () -> Unit = { => }

    private func overline(): String {
        ListItemData.optText(this.listItem.overlineText)
    }

    private func supporting(): String {
        ListItemData.optText(this.listItem.supportingText)
    }

    private func leading(): LeadingIconData {
        this.listItem.leadingIcon ?? LeadingIconData()
    }

    private func hasLeading(): Bool {
        match (this.listItem.leadingIcon) {
            case Some(icon) => icon.hasRemote() || !icon.iconSrc.isEmpty()
            case None => false
        }
    }

    private func leadingSrc(): String {
        if (this.leading().hasRemote()) {
            return this.leading().imageUrl
        }
        return this.leading().iconSrc
    }

    private func trailing(): TrailingContentData {
        this.listItem.trailingContent ?? TrailingContentData.empty()
    }

    private func mainWeight(): FontWeight {
        if (this.listItem.mainStyle.isBold()) {
            return FontWeight.Bold
        }
        return FontWeight.Medium
    }

    private func blurRadius(): Float64 {
        if (this.listItem.isBlur) {
            return 4.0
        }
        return 0.0
    }

    private func handleRowClick(): Unit {
        if (this.isLoading || !this.listItem.isEnable) {
            return
        }
        if (this.clickableEntireRow) {
            this.onItemAction()
        }
    }

    private func handleCheckboxChange(checked: Bool): Unit {
        if (this.clickableEntireRow) {
            this.onItemAction()
        } else {
            this.trailing().onToggle(checked)
        }
    }

    public func build() {
        Row(space: SPACING_MEDIUM) {
            if (this.hasLeading()) {
                // appImageSrc resolves SF-symbol tokens to their bitmaps and passes
                // remote URLs through unchanged, so both leading-icon kinds render.
                Image(appImageSrc(this.leadingSrc()))
                    .width(ThemeManager.shared.dimension.remoteImageIconSize)
                    .height(ThemeManager.shared.dimension.remoteImageIconSize)
                    .objectFit(ImageFit.Contain)
                    .blur(this.blurRadius())
            }
            Column(space: SPACING_EXTRA_SMALL) {
                if (!this.overline().isEmpty()) {
                    Text(this.overline())
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                        .fontColor(this.listItem.overlineTextColor)
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }
                Row(space: SPACING_SMALL) {
                    if (this.listItem.mainContent.isImage()) {
                        Image(this.listItem.mainContent.imageSrc)
                            .height(ThemeManager.shared.dimension.remoteImageIconSize)
                            .objectFit(ImageFit.Contain)
                            .blur(this.blurRadius())
                    } else {
                        Text(this.listItem.mainContent.asString())
                            .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                            .fontWeight(this.mainWeight())
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .textAlign(TextAlign.Start)
                            .blur(this.blurRadius())
                            .layoutWeight(1)
                    }
                    if (this.trailing().isTextWithIcon()) {
                        Text(this.trailing().textValue())
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                            .maxLines(1)
                        Image(appImageSrc(this.trailing().iconSrc))
                            .width(16.0)
                            .height(16.0)
                            .objectFit(ImageFit.Contain)
                            .fillColor(this.trailing().iconColor)
                    }
                }
                .width(100.percent)
                if (!this.supporting().isEmpty()) {
                    Text(this.supporting())
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(this.listItem.supportingTextColor)
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (this.trailing().isIcon()) {
                // iOS trailing chevrons render at ~20pt.
                Image(appImageSrc(this.trailing().iconSrc))
                    .width(20.0)
                    .height(20.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(this.trailing().iconColor)
            }
            if (this.trailing().isCheckbox()) {
                Checkbox()
                    .select(this.trailing().isChecked)
                    .selectedColor(uiColor(ThemeManager.shared.color.accent))
                    .enabled(this.trailing().checkboxEnabled && !this.isLoading)
                    .onChange({ checked => this.handleCheckboxChange(checked) })
            }
        }
        .padding(this.rowPadding)
        .opacity(this.rowOpacity())
        .enabled(!this.isLoading && this.listItem.isEnable)
        .onClick({ _ => this.handleRowClick() })
    }

    private func rowOpacity(): Float64 {
        if (!this.listItem.isEnable) {
            return 0.38
        }
        return 1.0
    }
}

/**
 * Mirrors Swift `ListDividerView`: a thin separator line with horizontal
 * inset. Separator token alpha 0.8 is baked into the color (0xCC).
 */
@Component
public class ListDividerView {
    public var dividerColor: Color = Color((ThemeManager.shared.color.separator.light & 0x00FFFFFFu32) | 0xCC000000u32)
    public var dividerHeight: Float64 = 1.0
    public var spacing: Float64 = SPACING_MEDIUM

    public func build() {
        Row {
            Divider()
                .color(this.dividerColor)
                .strokeWidth(this.dividerHeight)
                .layoutWeight(1)
        }
        .padding(left: this.spacing, right: this.spacing, top: 0.0, bottom: 0.0)
    }
}
