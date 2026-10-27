/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Manager/ColorManager.swift + Color.xcassets colorsets) to Cangjie for the
 * EUDI HarmonyOS wallet.
 *
 * iOS resolved colors from an asset catalog (light/dark appearances) with a
 * fall-back to SwiftUI/UIKit system colors. Here every token is a concrete ARGB
 * value pair. Brand colors and the base palette use the exact values found in the
 * .colorset JSON files; SwiftUI/UIKit system + semantic colors that resolve
 * dynamically on iOS use their standard platform ARGB equivalents.
 */
package eudi_logic_resources

/**
 * An ARGB color with a light and a dark appearance, mirroring the asset-catalog
 * "universal" + "luminosity:dark" entries. Values are 0xAARRGGBB.
 */
public struct ThemeColor {
    public let light: UInt32
    public let dark: UInt32

    public init(light!: UInt32, dark!: UInt32) {
        this.light = light
        this.dark = dark
    }

    // Convenience constructor for colors that do not vary by appearance.
    public init(value!: UInt32) {
        this.light = value
        this.dark = value
    }

    // Hex string of the light appearance, e.g. "#FF2C7E0A".
    public func lightHex(): String {
        ThemeColor.toHex(this.light)
    }

    public func darkHex(): String {
        ThemeColor.toHex(this.dark)
    }

    private static func toHex(argb: UInt32): String {
        let digits = "0123456789ABCDEF"
        var out = "#"
        var shift: Int64 = 28
        while (shift >= 0) {
            let nibble = Int64((argb >> UInt32(shift)) & 0xFu32)
            out += digits[nibble..nibble + 1]
            shift -= 4
        }
        return out
    }
}

/**
 * Design-system color palette. Ported from Swift `ColorManager`.
 *
 * - System palette: SwiftUI system colors. `blue` is overridden by the catalog
 *   (EUDI brand blue 26,67,143); the rest use standard platform RGB.
 * - Brand colors: exact ARGB pairs from the .colorset JSON.
 * - Semantic colors: UIKit adaptive colors, mapped to their standard
 *   light/dark RGB equivalents.
 */
public class ColorManager {
    public init() {}

    // MARK: - System palette
    // blue is catalog-overridden (R26 G67 B143) per Base/blue.colorset.
    public let blue: ThemeColor = ThemeColor(value: 0xFF1A438F)
    public let green: ThemeColor = ThemeColor(value: 0xFF34C759)
    public let indigo: ThemeColor = ThemeColor(value: 0xFF5856D6)
    public let orange: ThemeColor = ThemeColor(value: 0xFFFF9500)
    public let pink: ThemeColor = ThemeColor(value: 0xFFFF2D55)
    public let purple: ThemeColor = ThemeColor(value: 0xFFAF52DE)
    public let red: ThemeColor = ThemeColor(value: 0xFFFF0000)
    public let teal: ThemeColor = ThemeColor(value: 0xFF30B0C7)
    public let yellow: ThemeColor = ThemeColor(value: 0xFFFFCC00)
    public let mint: ThemeColor = ThemeColor(value: 0xFF00C7BE)
    public let cyan: ThemeColor = ThemeColor(value: 0xFF32ADE6)
    public let brown: ThemeColor = ThemeColor(value: 0xFFA2845E)
    public let black: ThemeColor = ThemeColor(value: 0xFF000000)
    public let white: ThemeColor = ThemeColor(value: 0xFFFFFFFF)
    public let gray: ThemeColor = ThemeColor(value: 0xFFC2C4C4)

    // Additional base-palette entries present in the catalog.
    public let darkGrey: ThemeColor = ThemeColor(value: 0xFF303030)
    public let grey: ThemeColor = ThemeColor(value: 0xFFC2C4C4)

    // MARK: - Brand (exact light/dark from .colorset JSON)
    public let success: ThemeColor = ThemeColor(light: 0xFF2C7E0A, dark: 0xFF93D875)
    public let successBackground: ThemeColor = ThemeColor(light: 0xFFE4EEE7, dark: 0xFF1F2B25)
    public let pending: ThemeColor = ThemeColor(light: 0xFFAB5200, dark: 0xFFCC8B3F)
    public let warning: ThemeColor = ThemeColor(light: 0xFFF39626, dark: 0xFFFFB689)
    public let groupedBackground: ThemeColor = ThemeColor(light: 0xFFEBF1FD, dark: 0xFF1A282E)
    public let groupedElevatedBackground: ThemeColor = ThemeColor(light: 0xFFE2E8F3, dark: 0xFF22323C)
    public let separator: ThemeColor = ThemeColor(light: 0xFFCAC4D0, dark: 0xFF79747F)

    // MARK: - Semantic (UIKit adaptive -> standard light/dark RGB)
    public let primaryLabel: ThemeColor = ThemeColor(light: 0xFF000000, dark: 0xFFFFFFFF)
    public let secondaryLabel: ThemeColor = ThemeColor(light: 0x993C3C43, dark: 0x99EBEBF5)
    public let tertiaryLabel: ThemeColor = ThemeColor(light: 0x4C3C3C43, dark: 0x4CEBEBF5)
    public let quaternaryLabel: ThemeColor = ThemeColor(light: 0x2D3C3C43, dark: 0x28EBEBF5)
    public let background: ThemeColor = ThemeColor(light: 0xFFFFFFFF, dark: 0xFF000000)
    public let secondaryBackground: ThemeColor = ThemeColor(light: 0xFFF2F2F7, dark: 0xFF1C1C1E)
    public let tertiaryBackground: ThemeColor = ThemeColor(light: 0xFFFFFFFF, dark: 0xFF2C2C2E)
    public let secondaryGroupedBackground: ThemeColor = ThemeColor(light: 0xFFFFFFFF, dark: 0xFF1C1C1E)
    public let tertiaryGroupedBackground: ThemeColor = ThemeColor(light: 0xFFF2F2F7, dark: 0xFF2C2C2E)
    public let opaqueSeparator: ThemeColor = ThemeColor(light: 0xFFC6C6C8, dark: 0xFF38383A)
    public let fill: ThemeColor = ThemeColor(light: 0x33787880, dark: 0x5C787880)
    public let secondaryFill: ThemeColor = ThemeColor(light: 0x28787880, dark: 0x51787880)
    public let tertiaryFill: ThemeColor = ThemeColor(light: 0x1E767680, dark: 0x3D767680)
    public let quaternaryFill: ThemeColor = ThemeColor(light: 0x14747480, dark: 0x2E767680)
    public let accent: ThemeColor = ThemeColor(value: 0xFF007AFF)
}
