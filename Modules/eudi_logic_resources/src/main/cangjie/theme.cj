/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Theme/AppTheme.swift, Manager/ThemeManager.swift, Manager/ThemeConfiguration.swift)
 * to Cangjie for the EUDI HarmonyOS wallet.
 */
package eudi_logic_resources

/**
 * Bundle of design-system managers. Mirrors Swift `ThemeConfiguration`, which
 * defaulted every manager when not injected.
 */
public class ThemeConfiguration {
    public let color: ColorManager
    public let image: ImageManager
    public let shape: ShapeManager
    public let font: TypographyManager
    public let dimension: DimensionManager

    public init(
        color!: ColorManager = ColorManager(),
        image!: ImageManager = ImageManager(),
        shape!: ShapeManager = ShapeManager(),
        font!: TypographyManager = TypographyManager(),
        dimension!: DimensionManager = DimensionManager()
    ) {
        this.color = color
        this.image = image
        this.shape = shape
        this.font = font
        this.dimension = dimension
    }
}

/**
 * Aggregate theme exposing every manager. Mirrors Swift `AppTheme`.
 */
public class AppTheme {
    public let themeConfiguration: ThemeConfiguration

    public init(themeConfiguration!: ThemeConfiguration = ThemeConfiguration()) {
        this.themeConfiguration = themeConfiguration
    }

    public prop color: ColorManager {
        get() { this.themeConfiguration.color }
    }
    public prop image: ImageManager {
        get() { this.themeConfiguration.image }
    }
    public prop shape: ShapeManager {
        get() { this.themeConfiguration.shape }
    }
    public prop font: TypographyManager {
        get() { this.themeConfiguration.font }
    }
    public prop dimension: DimensionManager {
        get() { this.themeConfiguration.dimension }
    }
}

/**
 * Global theme access point. Mirrors Swift `ThemeManager` (aliased `Theme`),
 * holding a mutable shared `AppTheme` reconfigurable via `config`.
 */
public class ThemeManager {
    private static var sharedTheme: AppTheme = AppTheme()

    public static prop shared: AppTheme {
        get() { ThemeManager.sharedTheme }
    }

    public static func config(themeConfiguration: ThemeConfiguration): Unit {
        ThemeManager.sharedTheme = AppTheme(themeConfiguration: themeConfiguration)
    }
}
