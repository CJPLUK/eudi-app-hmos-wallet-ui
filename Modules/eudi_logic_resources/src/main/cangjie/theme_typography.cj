/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Manager/TypographyManager.swift) to Cangjie for the EUDI HarmonyOS wallet.
 */
package eudi_logic_resources

/**
 * Font weight keys, mirroring the PostScript-name weight buckets used by the
 * Swift `TypographyManager` ("bold" / "medium" / "regular").
 */
public enum FontWeight {
    | Regular
    | Medium
    | Bold

    public func name(): String {
        match (this) {
            case Regular => "regular"
            case Medium => "medium"
            case Bold => "bold"
        }
    }
}

/**
 * Base point sizes of the iOS `Font.TextStyle` scale.
 * Values ported from `Font.TextStyle.defaultSize` in TypographyManager.swift.
 */
public enum TextStyle {
    | LargeTitle
    | Title
    | Title2
    | Title3
    | Headline
    | Subheadline
    | Body
    | Callout
    | Caption
    | Caption2
    | Footnote

    public func defaultSize(): Float64 {
        match (this) {
            case LargeTitle => 34.0
            case Title => 28.0
            case Title2 => 22.0
            case Title3 => 20.0
            case Headline => 17.0
            case Subheadline => 15.0
            case Body => 17.0
            case Callout => 16.0
            case Caption => 12.0
            case Caption2 => 11.0
            case Footnote => 13.0
        }
    }
}

/**
 * A resolved typography style: a size (points), a weight and a letter spacing.
 * Mirrors Swift `TypographyStyle` (which wrapped a `Font` + `spacing`); here the
 * font is decomposed into its size + weight tokens so the value is platform-neutral.
 */
public struct TypographyStyle {
    public let size: Float64
    public let weight: FontWeight
    public let spacing: Float64

    public init(size!: Float64, weight!: FontWeight, spacing!: Float64) {
        this.size = size
        this.weight = weight
        this.spacing = spacing
    }
}

/**
 * The design-system type scale. Each accessor reproduces the (weight, textStyle)
 * pairing from Swift `TypographyManager`; spacing is 0 there, as here.
 */
public class TypographyManager {
    public init() {}

    private static func style(weight!: FontWeight, style!: TextStyle): TypographyStyle {
        TypographyStyle(size: style.defaultSize(), weight: weight, spacing: 0.0)
    }

    public prop displayLarge: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Bold, style: TextStyle.LargeTitle) }
    }
    public prop displayMedium: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Bold, style: TextStyle.Title) }
    }
    public prop displaySmall: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Bold, style: TextStyle.Title2) }
    }

    public prop headlineLarge: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Title3) }
    }
    public prop headlineMedium: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Headline) }
    }
    public prop headlineSmall: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Subheadline) }
    }

    public prop titleLarge: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Title) }
    }
    public prop titleMedium: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Title2) }
    }
    public prop titleSmall: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Title3) }
    }

    public prop bodyLarge: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Regular, style: TextStyle.Body) }
    }
    public prop bodyMedium: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Regular, style: TextStyle.Callout) }
    }
    public prop bodySmall: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Regular, style: TextStyle.Footnote) }
    }

    public prop labelLarge: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Medium, style: TextStyle.Headline) }
    }
    public prop labelMedium: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Regular, style: TextStyle.Caption) }
    }
    public prop labelSmall: TypographyStyle {
        get() { TypographyManager.style(weight: FontWeight.Regular, style: TextStyle.Caption2) }
    }
}
