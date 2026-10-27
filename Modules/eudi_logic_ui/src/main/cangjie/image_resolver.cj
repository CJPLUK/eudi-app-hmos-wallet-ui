/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * iOS carried image references as SF Symbol names ("line.3.horizontal", "plus",
 * "chevron.right", ...) or asset-catalog names ("logo", ...) — see
 * eudi_logic_resources.ImageManager. On HarmonyOS those raw strings resolve to
 * nothing (ArkUI treats a bare string src as a file path), so every icon
 * rendered blank.
 *
 * The Cangjie bundled-resource macro (@r/$r app.media.x) is not usable in this
 * build (its runtime __GenerateResource__ intrinsic is not linked), so glyph
 * icons (the SF-symbol family) are rendered as Unicode text via the system
 * font, which needs no media resource. Remote URLs (issuer logos) and any other
 * string fall through to a plain Image(src). Bitmap illustrations/logos that
 * have no glyph equivalent are handled at their own call sites.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*

/**
 * Resolve an image token to a renderable Image src: the bundled PNG data-URI
 * when one exists, otherwise the token unchanged (remote URLs pass through).
 * Use for direct Image(...) call sites that carry their own sizing/layout
 * (logos, illustrations) where the square AppIcon component does not fit.
 */
public func appImageSrc(token: String): String {
    let uri = imageDataUri(token)
    if (uri != "") {
        return uri
    }
    return token
}

/** Unicode glyph for an iOS SF-symbol token, or "" when there is no glyph. */
public func iconGlyph(token: String): String {
    match (token) {
        case "line.3.horizontal" => "\u{2630}"        // ☰ menu / side menu
        case "gearshape" => "\u{2699}"                 // ⚙ settings
        case "gearshape.fill" => "\u{2699}"            // ⚙ settings
        case "123.rectangle" => "\u{1F522}"            // 🔢 change PIN
        case "lock.rotation" => "\u{1F511}"            // 🔑 change PIN (alt)
        case "key" => "\u{1F511}"                      // 🔑
        case "key.fill" => "\u{1F511}"                 // 🔑
        case "plus" => "+"
        case "magnifyingglass" => "\u{1F50D}"          // 🔍 search
        case "slider.horizontal.3" => "\u{2263}"       // ≣ filter
        case "chevron.right" => "\u{203A}"             // ›
        case "chevron.left" => "\u{2039}"              // ‹
        case "chevron.up" => "\u{2303}"                // ⌃
        case "chevron.down" => "\u{2304}"              // ⌄
        case "xmark" => "\u{2715}"                     // ✕
        case "checkmark" => "\u{2713}"                 // ✓
        case "checkmark.circle.fill" => "\u{2705}"     // ✅
        case "checkmark.seal.fill" => "\u{2713}"       // ✓
        case "bell" => "\u{1F514}"                     // 🔔
        case "trash" => "\u{1F5D1}"                    // 🗑
        case "doc" => "\u{1F4C4}"                      // 📄
        case "doc.fill" => "\u{1F4C4}"                 // 📄
        case "house.fill" => "\u{1F3E0}"               // 🏠
        case "clock.fill" => "\u{1F551}"               // 🕑
        case "ic-clock" => "\u{1F551}"                 // 🕑
        case "elipsis-vertical" => "\u{22EE}"          // ⋮
        case "info.circle" => "\u{2139}"               // ℹ
        case "eye" => "\u{1F441}"                      // 👁
        case "eye.slash" => "\u{1F441}"                // 👁 (slashed unavailable)
        case "qrcode.viewfinder" => "\u{2317}"         // ⌗
        case "ble" => "\u{1F4F6}"                       // 📶 Bluetooth/BLE proximity
        case "face-id" => "\u{1F464}"                   // 👤 Face ID trigger
        case "faceid" => "\u{1F464}"                    // 👤 Face ID (menu row)
        case "touch-id" => "\u{261D}"                   // ☝ Touch ID trigger
        case "share" => "\u{1F4E4}"                    // 📤
        case "square.and.arrow.up" => "\u{1F4E4}"      // 📤
        case _ => ""
    }
}

/**
 * Renders an iOS image token. SF-symbol tokens become a Unicode glyph (Text);
 * everything else (remote URLs, file paths) is rendered as a plain Image.
 */
@Component
public class AppIcon {
    public var token: String = ""
    public var size: Float64 = 24.0
    public var color: ResourceColor = Color.Black

    public func build() {
        // Prefer a real bitmap (data-URI) over the Unicode-glyph fallback so
        // tokens that ship an actual icon (gearshape, magnifyingglass, plus,
        // slider.horizontal.3, …) render the bitmap instead of an emoji — only
        // glyph-only tokens fall through to the Unicode character.
        if (imageDataUri(this.token) != "") {
            Image(imageDataUri(this.token))
                .width(this.size)
                .height(this.size)
                .objectFit(ImageFit.Contain)
        } else if (iconGlyph(this.token) != "") {
            Text(iconGlyph(this.token))
                .fontSize(this.size)
                .fontColor(this.color)
                .width(this.size + 6.0)
                .height(this.size + 6.0)
                .textAlign(TextAlign.Center)
        } else {
            Image(this.token)
                .width(this.size)
                .height(this.size)
                .objectFit(ImageFit.Contain)
        }
    }
}
