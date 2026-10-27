/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Manager/ShapeManager.swift) to Cangjie for the EUDI HarmonyOS wallet.
 */
package eudi_logic_resources

/**
 * Corner-radius / shape tokens of the design system.
 * Ported 1:1 from Swift `ShapeManager`. `.infinity` (SwiftUI `.full`) is
 * represented by a large sentinel value, since Cangjie has no Float infinity token here.
 */
public class ShapeManager {
    public static let fullSentinel: Float64 = 1.0e9

    public let none: Float64 = 0.0
    public let extraSmall: Float64 = 8.0
    public let small: Float64 = 16.0
    public let medium: Float64 = 18.0
    public let large: Float64 = 20.0
    public let extraLarge: Float64 = 24.0
    public let xxLarge: Float64 = 32.0
    public let xxxLarge: Float64 = 48.0
    public let xxxxLarge: Float64 = 56.0
    public let full: Float64 = ShapeManager.fullSentinel

    public init() {}
}
