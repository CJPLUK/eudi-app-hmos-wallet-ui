/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-resources module
 * (Manager/ImageManager.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * iOS resolved each accessor to a SwiftUI `Image`, either from the asset catalog
 * (bundled SVG/PNG) or from an SF Symbol system name. Here every accessor returns
 * the underlying string reference (the Swift `ImageEnum` rawValue), so consumers
 * can resolve it against bundled assets or a symbol mapping.
 */
package eudi_logic_resources

/**
 * Symbol/asset name tokens. Each accessor returns the string ref used on iOS
 * (asset-catalog name or SF Symbol name), ported 1:1 from `ImageManager.ImageEnum`.
 */
public class ImageManager {
    public init() {}

    public let faceId: String = "face-id"
    public let faceIdMenu: String = "faceid"
    public let id: String = "id"
    public let ble: String = "ble"
    public let touchId: String = "touch-id"
    public let logo: String = "logo"
    public let arrowLeft: String = "arrow.left"
    public let chevronUp: String = "chevron.up"
    public let chevronDown: String = "chevron.down"
    public let chevronRight: String = "chevron.right"
    public let chevronRightAccent: String = "chevron.right.accent"   // pre-tinted accent (fillColor doesn't tint PNGs)
    public let chevronUpAccent: String = "chevron.up.accent"
    public let chevronDownAccent: String = "chevron.down.accent"
    public let eyeAccent: String = "eye.accent"
    public let eyeSlashAccent: String = "eye.slash.accent"
    public let chevronLeft: String = "chevron.left"
    public let xmark: String = "xmark"
    public let xmarkBold: String = "xmark.bold"                // bolder xmark (filter-sheet close)
    public let exclamationmarkCircle: String = "exclamationmark.circle"
    public let circle: String = "circle.fill"
    public let eye: String = "eye"
    public let eyeSlash: String = "eye.slash"
    public let checkmarkCircleFill: String = "checkmark.circle.fill"
    public let checkmarkCircle: String = "checkmark.circle"
    public let checkmarkSquareFill: String = "checkmark.square.fill"
    public let square: String = "square"
    public let plus: String = "plus"
    public let share: String = "square.and.arrow.up"
    public let checkMarkSealFill: String = "checkmark.seal.fill"
    public let photo: String = "photo.fill"
    public let trash: String = "trash"
    public let viewFinder: String = "viewfinder"
    public let clock: String = "ic-clock"
    public let clockIndicator: String = "clock.fill"
    public let errorIndicator: String = "exclamationmark.circle.fill"
    public let signDocument: String = "doc"
    public let euditext: String = "EUDI-text"
    public let walletVerified: String = "wallet-verified"
    public let bell: String = "bell"
    public let menuIcon: String = "line.3.horizontal"
    public let filterMenuIcon: String = "slider.horizontal.3"
    // Pre-tinted SF-symbol variants (AppIcon renders bitmap tokens as-is; the
    // `color` param only tints the glyph fallback, so toolbar icons that need a
    // specific tint ship a colored PNG — same pattern as the tab bar's `.selected`).
    public let plusAccent: String = "plus.accent"                          // blue add
    public let filterMenuIconAccent: String = "slider.horizontal.3.accent"   // enabled filter (blue)
    public let filterMenuIconBlack: String = "slider.horizontal.3.black"     // enabled filter (black, iOS default nav tint)
    public let filterMenuIconDisabled: String = "slider.horizontal.3.disabled" // disabled filter (gray)
    public let searchIcon: String = "magnifyingglass"                      // black search glyph (iOS)
    public let bookmarkIcon: String = "bookmark"
    public let bookmarkIconFill: String = "bookmark.fill"
    public let gearshape: String = "gearshape"
    public let checkmark: String = "checkmark"
    public let checkmarkWhite: String = "checkmark.white"       // pre-tinted white (filter-sheet apply)
    public let hourglassImage: String = "hourglassImage"
    public let chooseDocumentImage: String = "choose-document-image"
    public let scanDocumentImage: String = "scan-document-image"
    public let qrCodeViewfinder: String = "qrcode.viewfinder"
    public let infoCircle: String = "info.circle"
    public let relyingPartyVerified: String = "relying-party-verified"
    public let docFill: String = "doc.fill"
    public let houseFill: String = "house.fill"
    public let logoEuDigitalIndentityWallet: String = "logo-eu-digital-indentity-wallet"
    public let homeContract: String = "home-contract"
    public let homeIdentity: String = "home-identity"
    public let successSecuredWallet: String = "success-secured-wallet"
    public let digitalIdIssuance: String = "digital-id-issuance"
    public let documentSuccessPending: String = "document-success-pending"
    public let verified: String = "verified"
    public let ellipsisVertical: String = "elipsis-vertical"
    public let copy: String = "doc.on.doc"
    public let changePin: String = "123.rectangle"
    public let batchCounter: String = "number"
    public let retrieveLogs: String = "arrow.up.forward.square"
    public let changelog: String = "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
    // Registration certificate trust layer (iOS 95b71766). Both reuse tokens
    // that already ship an asset/glyph: iOS `checkmark.seal` maps onto the
    // bundled seal check, `arrow.up.right.square` onto the up-forward square
    // (same glyph, mirrored naming across platforms).
    public let issuerRegistration: String = "checkmark.seal.fill"
    public let arrowUpRightSquare: String = "arrow.up.forward.square"
}
