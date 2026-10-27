/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (Config/ConfigUiLogic.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * The theme tokens themselves (`ThemeManager` / `AppTheme` / `ColorManager` /
 * `TypographyManager`) are owned by the delivered `eudi_logic_resources`
 * module; this file bridges those platform-neutral tokens into ArkUI values
 * (`Color`, font size/weight) and ports the `ConfigUiLogic` screen→toolbar
 * lookup.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Resolves a `ThemeColor` token (light variant) into an ArkUI `Color`.
 *
 * Alpha guard: a token whose high byte (alpha) is 0x00 would render fully
 * transparent (`Color(UInt32)` is ARGB). Tokens with a deliberate partial
 * alpha (e.g. secondaryLabel 0x99...) are preserved; only a zero alpha is
 * promoted to opaque 0xFF.
 */
public func uiColor(token: ThemeColor): Color {
    return Color(guardAlpha(token.light))
}

/** Dark-variant counterpart of `uiColor`, with the same alpha guard. */
public func uiColorDark(token: ThemeColor): Color {
    return Color(guardAlpha(token.dark))
}

func guardAlpha(argb: UInt32): UInt32 {
    if ((argb >> 24) == 0) {
        return argb | 0xFF000000u32
    }
    return argb
}

/** Font size (vp) for a design-system typography style. */
public func uiFontSize(style: TypographyStyle): Float64 {
    style.size
}

/**
 * Maps the design-system weight bucket ("bold" / "medium" / "regular",
 * see eudi_logic_resources `FontWeight.name()`) onto the ArkUI `FontWeight`.
 */
public func uiFontWeight(style: TypographyStyle): FontWeight {
    match (style.weight.name()) {
        case "bold" => FontWeight.Bold
        case "medium" => FontWeight.Medium
        case _ => FontWeight.Normal
    }
}

/**
 * Mirrors Swift `ConfigUiLogic`: entry routes of the two main flows plus the
 * per-screen toolbar background lookup. Route values are `AppRoutes` names.
 */
public interface ConfigUiLogic {
    prop dashboardRoute: String
    prop issuanceRoute: String
    func toolBarConfigFor(routeKey: String): ?UIConfigToolBar
}

/**
 * Mirrors Swift `ConfigUiLogicImpl`. The Swift initializer applied a
 * `ThemeConfiguration` to the global theme; the optional parameter keeps that
 * behaviour while defaulting to the already-configured shared theme.
 */
public class ConfigUiLogicImpl <: ConfigUiLogic {
    public init(themeConfiguration!: ?ThemeConfiguration = None) {
        match (themeConfiguration) {
            case Some(cfg) => ThemeManager.config(cfg)
            case None => ()
        }
    }

    public prop dashboardRoute: String {
        get() { AppRoutes.dashboard }
    }

    public prop issuanceRoute: String {
        get() { AppRoutes.issuanceAddDocument }
    }

    /**
     * Swift seeded the dictionary with Dashboard and DocumentDetails mapped to
     * the theme background color; every other screen has no override.
     */
    public func toolBarConfigFor(routeKey: String): ?UIConfigToolBar {
        if (routeKey == AppRoutes.dashboard || routeKey == AppRoutes.documentDetails) {
            return UIConfigToolBar(uiColor(ThemeManager.shared.color.background))
        }
        return None
    }
}
