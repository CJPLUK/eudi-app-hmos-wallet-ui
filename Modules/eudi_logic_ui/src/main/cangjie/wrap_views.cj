/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/Wrap/WrapButtonView.swift, WrapTextView.swift,
 * WrapIconView.swift, DesignSystem/Component/List/WrapCardView.swift,
 * DesignSystem/Button/ButtonViewStyle.swift) to Cangjie ArkUI.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Shared empty slot builder. @BuilderParam defaults must point at a
 * top-level @Builder function (dev_pattern: member @Builder defaults are
 * unstable with the @Component macro), so every container component in this
 * module defaults its content slot to this function.
 */
@Builder
public func eudiEmptyBuilder() {}

/**
 * Text styling bundle. Mirrors Swift `TextConfig` (ContentHeaderView.swift):
 * typography style + color + alignment + max lines + optional weight override.
 */
public class TextConfig {
    public let font: TypographyStyle
    public let color: Color
    public let textAlign: TextAlign
    public let maxLines: Int32
    public let weightOverride: ?FontWeight

    public init(
        font!: TypographyStyle,
        color!: Color = uiColor(ThemeManager.shared.color.primaryLabel),
        textAlign!: TextAlign = TextAlign.Center,
        maxLines!: Int32 = 2,
        weightOverride!: ?FontWeight = None
    ) {
        this.font = font
        this.color = color
        this.textAlign = textAlign
        this.maxLines = maxLines
        this.weightOverride = weightOverride
    }

    public func resolvedWeight(): FontWeight {
        match (this.weightOverride) {
            case Some(weight) => weight
            case None => uiFontWeight(this.font)
        }
    }
}

/**
 * Mirrors Swift `WrapTextView`: a Text driven entirely by a `TextConfig`.
 */
@Component
public class WrapTextView {
    public var text: LocalizableStringKey = LocalizableStringKey.custom("")
    public var textConfig: TextConfig = TextConfig(font: ThemeManager.shared.font.bodyLarge)

    private func displayText(): String {
        LocalizableManager.get(this.text)
    }

    public func build() {
        Text(this.displayText())
            .fontSize(uiFontSize(this.textConfig.font))
            .fontWeight(this.textConfig.resolvedWeight())
            .fontColor(this.textConfig.color)
            .textAlign(this.textConfig.textAlign)
            .maxLines(this.textConfig.maxLines)
            .textOverflow(TextOverflow.Ellipsis)
    }
}

/**
 * Mirrors Swift `ButtonViewStyle` (primary / secondary / error / success /
 * custom). `error` background bakes the iOS `red.opacity(0.14)` into the
 * ARGB alpha byte (0x24) — container-level `.opacity()` would also fade the
 * label (QA: alpha belongs in the color, not the container).
 */
public class ButtonViewStyle {
    public let textColor: Color
    public let backgroundColor: Color
    public let borderWidth: Float64
    public let borderColor: Color

    public init(
        textColor!: Color,
        backgroundColor!: Color,
        borderWidth!: Float64 = 0.0,
        borderColor!: Color = Color.Transparent
    ) {
        this.textColor = textColor
        this.backgroundColor = backgroundColor
        this.borderWidth = borderWidth
        this.borderColor = borderColor
    }

    public static func primary(): ButtonViewStyle {
        ButtonViewStyle(
            textColor: uiColor(ThemeManager.shared.color.white),
            backgroundColor: uiColor(ThemeManager.shared.color.accent)
        )
    }

    public static func secondary(): ButtonViewStyle {
        // iOS secondary button: gray fill, NO border (blue text/icon carry the
        // accent). The visible blue border was a migration artifact.
        ButtonViewStyle(
            textColor: uiColor(ThemeManager.shared.color.accent),
            backgroundColor: uiColor(ThemeManager.shared.color.tertiaryFill)
        )
    }

    public static func error(): ButtonViewStyle {
        // No border — the rendered iOS reference shows a plain light-red fill.
        ButtonViewStyle(
            textColor: uiColor(ThemeManager.shared.color.red),
            backgroundColor: Color(0x24FF0000u32)
        )
    }

    public static func success(): ButtonViewStyle {
        ButtonViewStyle(
            textColor: uiColor(ThemeManager.shared.color.white),
            backgroundColor: uiColor(ThemeManager.shared.color.success),
            borderWidth: 1.0,
            borderColor: Color.Transparent
        )
    }
}

/**
 * Horizontal gravity of the button label. Mirrors Swift
 * `WrapButtonView.Gravity` (center / start / end / none — `none` hugs).
 */
public enum WrapButtonGravity {
    | GravityCenter
    | GravityStart
    | GravityEnd
    | GravityNone

    public func isNone(): Bool {
        match (this) {
            case GravityNone => true
            case _ => false
        }
    }

    public func contentAlign(): FlexAlign {
        match (this) {
            case GravityStart => FlexAlign.Start
            case GravityEnd => FlexAlign.End
            case _ => FlexAlign.Center
        }
    }
}

/**
 * Mirrors Swift `WrapButtonView`: styled button with optional icon and a
 * loading shimmer degraded to an inline LoadingProgress. Disabled state
 * mirrors the iOS restyle: explicit secondaryBackground fill +
 * secondaryLabel text instead of a blanket opacity.
 * Old-project PrimaryButton paradigm: `.enabled(...)` really blocks clicks.
 */
@Component
public class WrapButtonView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var style: ButtonViewStyle = ButtonViewStyle.primary()
    public var iconSrc: String = ""
    public var iconSize: Float64 = 22.0
    public var gravity: WrapButtonGravity = WrapButtonGravity.GravityCenter
    public var isLoading: Bool = false
    public var isEnabled: Bool = true
    public var cornerRadius: Float64 = ThemeManager.shared.shape.small
    public var verticalPadding: ?Float64 = None
    public var onAction: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func hasIcon(): Bool {
        !this.iconSrc.isEmpty()
    }

    private func interactive(): Bool {
        this.isEnabled && !this.isLoading
    }

    private func isDisabledLook(): Bool {
        !this.isEnabled && !this.isLoading
    }

    /** iOS disabled restyle: secondaryLabel text (no blanket opacity). */
    private func currentTextColor(): Color {
        if (this.isDisabledLook()) {
            return uiColor(ThemeManager.shared.color.secondaryLabel)
        }
        return this.style.textColor
    }

    /** iOS disabled restyle: secondaryBackground fill (no blanket opacity). */
    private func currentBackgroundColor(): Color {
        if (this.isDisabledLook()) {
            return uiColor(ThemeManager.shared.color.secondaryBackground)
        }
        return this.style.backgroundColor
    }

    private func expandWeight(): ?Int32 {
        if (this.gravity.isNone()) {
            return None
        }
        return 1
    }

    public func build() {
        Row {
            Button {
                Row(space: 8.0) {
                    if (this.hasIcon()) {
                        Image(appImageSrc(this.iconSrc))
                            .width(this.iconSize)
                            .height(this.iconSize)
                            .objectFit(ImageFit.Contain)
                    }
                    Text(this.titleText())
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.currentTextColor())
                    if (this.isLoading) {
                        LoadingProgress()
                            .width(20.0)
                            .height(20.0)
                            .color(this.currentTextColor())
                    }
                }
                .width(100.percent)
                .padding(
                    top: this.verticalPadding ?? ThemeManager.shared.shape.extraSmall,
                    right: ThemeManager.shared.shape.extraSmall,
                    bottom: this.verticalPadding ?? ThemeManager.shared.shape.extraSmall,
                    left: ThemeManager.shared.shape.extraSmall
                )
                .justifyContent(this.gravity.contentAlign())
            }
            .backgroundColor(this.currentBackgroundColor())
            // Combined border() with an explicit Solid style — split
            // borderWidth/borderColor never painted on Button.
            .border(
                width: this.style.borderWidth,
                color: this.style.borderColor,
                radius: this.cornerRadius,
                style: BorderStyle.Solid
            )
            .enabled(this.interactive())
            .onClick({ _ => this.onAction() })
            .layoutWeight(this.expandWeight())
        }
    }
}

/**
 * Mirrors Swift `WrapCardView`: rounded background container with a content
 * slot. Fill the slot with inline DSL (dev_pattern: container @BuilderParam
 * cannot be filled from a member @Builder).
 */
@Component
public class WrapCardView {
    public var cornerRadius: Float64 = 18.0
    public var cardBackgroundColor: Color = uiColor(ThemeManager.shared.color.groupedBackground)
    @BuilderParam
    var content: () -> Unit = eudiEmptyBuilder

    public func build() {
        Column {
            this.content()
        }
        .backgroundColor(this.cardBackgroundColor)
        .borderRadius(this.cornerRadius)
        .clip(true)
    }
}

/**
 * Mirrors Swift `WrapIconView`: icon + optional title on a rounded
 * background with gravity.
 */
@Component
public class WrapIconView {
    public var title: ?LocalizableStringKey = None
    public var textColor: Color = uiColor(ThemeManager.shared.color.white)
    public var iconBackgroundColor: Color = uiColor(ThemeManager.shared.color.background)
    public var iconSrc: String = ""
    public var iconSize: Float64 = 22.0
    public var gravity: WrapButtonGravity = WrapButtonGravity.GravityCenter
    public var cornerRadius: Float64 = ThemeManager.shared.shape.large

    private func hasTitle(): Bool {
        match (this.title) {
            case Some(_) => true
            case None => false
        }
    }

    private func titleText(): String {
        match (this.title) {
            case Some(key) => LocalizableManager.get(key)
            case None => ""
        }
    }

    public func build() {
        Row(space: 8.0) {
            if (!this.iconSrc.isEmpty()) {
                Image(appImageSrc(this.iconSrc))
                    .width(25.0)
                    .height(25.0)
                    .objectFit(ImageFit.Contain)
            }
            if (this.hasTitle()) {
                Text(this.titleText())
                    .fontColor(this.textColor)
            }
        }
        .padding(16.0)
        .backgroundColor(this.iconBackgroundColor)
        .borderRadius(this.cornerRadius)
        .justifyContent(this.gravity.contentAlign())
    }
}

/**
 * Image wrapper companion to WrapIconView (contract `components_core`
 * symbol). Renders a sized, aspect-fit image from any `ResourceStr` source.
 */
@Component
public class WrapImageView {
    public var imageSrc: String = ""
    public var imageWidth: Float64 = 50.0
    public var imageHeight: Float64 = 50.0

    public func build() {
        Row {
            AppIcon(token: this.imageSrc, size: this.imageWidth)
        }
    }
}
