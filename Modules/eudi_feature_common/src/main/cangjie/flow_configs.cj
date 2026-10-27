/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/Config/) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * fc_common_flow_config: every iOS UIConfigType implementation of this module
 * migrated field by field — SuccessUIConfig (Config/SuccessUiConfig.swift),
 * QuickPinUiConfig, BiometricUiConfig, ScannerUiConfig,
 * IssuanceFlowUiConfig / IssuanceCodeUiConfig (Config/Issuance/),
 * DocumentSuccessUIConfig (Config/Presentation/). Swift nested types
 * (UIConfig.Success.Title / .Button / .VisualKind, *.Flow) are flattened to
 * top-level names because Cangjie has no nested type declarations. Navigation
 * payloads reuse the delivered eudi_logic_ui types (TwoWayNavigationType /
 * ThreeWayNavigationType / DeepLinkNavigationType, AppRoutes route names).
 * Each config conforms to eudi_logic_ui.UIConfigType so it can travel through
 * NavArgs as a RouteConfigArgs payload.
 */
package eudi_feature_common

import ohos.base.*
import std.collection.ArrayList
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

// ─── QuickPinUiConfig (Config/QuickPinUiConfig.swift) ───────────────────

/** Mirrors Swift `QuickPinUiConfig.Flow` (raw values kept for `log`). */
public enum QuickPinFlow {
    | SetWithActivation
    | SetWithoutActivation
    | Update

    public func rawValue(): String {
        match (this) {
            case SetWithActivation => "setWithActivation"
            case SetWithoutActivation => "setWithoutActivation"
            case Update => "update"
        }
    }
}

/** Mirrors Swift `QuickPinUiConfig` (UIConfigType with a Flow payload). */
public class QuickPinUiConfig <: UIConfigType {
    public let flow: QuickPinFlow

    public init(flow!: QuickPinFlow) {
        this.flow = flow
    }

    public prop log: String {
        get() { "flow: ${this.flow.rawValue()}" }
    }

    public prop isSetFlowWithActivation: Bool {
        get() {
            match (this.flow) {
                case SetWithActivation => true
                case _ => false
            }
        }
    }

    public prop isSetFlowWithoutActivation: Bool {
        get() {
            match (this.flow) {
                case SetWithoutActivation => true
                case _ => false
            }
        }
    }

    public prop isSetFlow: Bool {
        get() { this.isSetFlowWithActivation || this.isSetFlowWithoutActivation }
    }

    public prop isUpdateFlow: Bool {
        get() {
            match (this.flow) {
                case Update => true
                case _ => false
            }
        }
    }
}

// ─── BiometricUiConfig (Config/BiometricUiConfig.swift) ─────────────────

/**
 * Mirrors Swift `UIConfig.Biometry`, field for field. `navigationSuccessType`
 * / `navigationBackType` are `eudi_logic_ui.ThreeWayNavigationType` over
 * `AppRoutes` route-name constants.
 */
public class BiometricUiConfig <: UIConfigType {
    public let navigationTitle: LocalizableStringKey
    public let displayLogo: Bool
    public let title: ?LocalizableStringKey
    public let caption: LocalizableStringKey
    public let quickPinOnlyCaption: LocalizableStringKey
    public let pinTextFieldTitle: ?LocalizableStringKey
    public let navigationSuccessType: ThreeWayNavigationType
    public let navigationBackType: ?ThreeWayNavigationType
    public let isPreAuthorization: Bool
    public let shouldInitializeBiometricOnCreate: Bool
    public let displayNavigationBar: Bool

    public init(
        navigationTitle!: LocalizableStringKey,
        displayLogo!: Bool = true,
        title!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        caption!: LocalizableStringKey,
        quickPinOnlyCaption!: LocalizableStringKey,
        pinTextFieldTitle!: ?LocalizableStringKey = Option<LocalizableStringKey>.None,
        navigationSuccessType!: ThreeWayNavigationType,
        navigationBackType!: ?ThreeWayNavigationType,
        isPreAuthorization!: Bool,
        shouldInitializeBiometricOnCreate!: Bool,
        displayNavigationBar!: Bool = true
    ) {
        this.navigationTitle = navigationTitle
        this.displayLogo = displayLogo
        this.title = title
        this.caption = caption
        this.quickPinOnlyCaption = quickPinOnlyCaption
        this.pinTextFieldTitle = pinTextFieldTitle
        this.navigationSuccessType = navigationSuccessType
        this.navigationBackType = navigationBackType
        this.isPreAuthorization = isPreAuthorization
        this.shouldInitializeBiometricOnCreate = shouldInitializeBiometricOnCreate
        this.displayNavigationBar = displayNavigationBar
    }

    private func backTypeKey(): String {
        match (this.navigationBackType) {
            case Some(backType) => backType.key()
            case None => "none"
        }
    }

    private func titleKeyText(): String {
        match (this.title) {
            case Some(key) => LocalizableManager.get(key)
            case None => "none"
        }
    }

    public prop log: String {
        get() {
            "navigationTitle: ${LocalizableManager.get(this.navigationTitle)}" +
                "displayLogo: ${this.displayLogo}" +
                "title: ${this.titleKeyText()}" +
                " onSuccessNav: ${this.navigationSuccessType.key()}" +
                " onBackNav: ${this.backTypeKey()}" +
                " isPreAuthorization: ${this.isPreAuthorization}" +
                " shouldInitializeBiometricOnCreate: ${this.shouldInitializeBiometricOnCreate}" +
                " displayNavigationBar: ${this.displayNavigationBar}"
        }
    }
}

// ─── ScannerUiConfig (Config/ScannerUiConfig.swift) ─────────────────────

/**
 * Mirrors Swift `ScannerUiConfig.Flow`: presentation, or issuing with the
 * success / cancel navigation of the issuance flow it belongs to.
 */
public enum ScannerFlow {
    | FlowPresentation
    | FlowIssuing(TwoWayNavigationType, ThreeWayNavigationType)

    public func rawValue(): String {
        match (this) {
            case FlowPresentation => "presentation"
            case FlowIssuing(successNav, cancelNav) =>
                "type: issuing successNavigation: ${successNav.key()} cancelNavigation: ${cancelNav.key()}"
        }
    }

    /** Mirrors Swift `Flow.title`. */
    public func title(): LocalizableStringKey {
        match (this) {
            case FlowPresentation => LocalizableStringKey.scannerQrTitlePresentation
            case FlowIssuing(_, _) => LocalizableStringKey.scannerQrTitleIssuing
        }
    }

    /** Mirrors Swift `Flow.caption`. */
    public func caption(): LocalizableStringKey {
        match (this) {
            case FlowPresentation => LocalizableStringKey.scannerQrCaptionPresentation
            case FlowIssuing(_, _) => LocalizableStringKey.scannerQrCaptionIssuing
        }
    }

    /** Mirrors Swift `Flow.informativeText`. */
    public func informativeText(): LocalizableStringKey {
        LocalizableStringKey.qrScanInformativeText
    }

    public func isIssuing(): Bool {
        match (this) {
            case FlowIssuing(_, _) => true
            case _ => false
        }
    }
}

/** Mirrors Swift `ScannerUiConfig`. */
public class ScannerUiConfig <: UIConfigType {
    public let flow: ScannerFlow

    public init(flow!: ScannerFlow) {
        this.flow = flow
    }

    public prop log: String {
        get() { "flow: ${this.flow.rawValue()}" }
    }
}

// ─── SuccessUIConfig (Config/SuccessUiConfig.swift) ─────────────────────

/** Mirrors Swift `UIConfig.Success.Title` (value + color). */
public class SuccessTitle {
    public let value: LocalizableStringKey
    public let color: Color

    public init(
        value!: LocalizableStringKey,
        color!: Color = uiColor(ThemeManager.shared.color.success)
    ) {
        this.value = value
        this.color = color
    }
}

/** Mirrors Swift `UIConfig.Success.Button.Style` (primary / secondary). */
public enum SuccessButtonStyle {
    | StylePrimary
    | StyleSecondary

    public func isPrimary(): Bool {
        match (this) {
            case StylePrimary => true
            case StyleSecondary => false
        }
    }
}

/**
 * Mirrors Swift `UIConfig.Success.VisualKind`: the default success icon or a
 * custom glyph + tint. HarmonyOS ships no SF-Symbol set, so the image payload
 * is a glyph / resource string ("" → checkmark fallback at render time).
 */
public enum SuccessVisualKind {
    | DefaultIcon
    | CustomIcon(String, Color)

    public func iconText(): String {
        match (this) {
            case DefaultIcon => "✓"
            case CustomIcon(glyph, _) =>
                if (glyph.isEmpty()) {
                    "✓"
                } else {
                    glyph
                }
        }
    }

    public func iconTint(): Color {
        match (this) {
            case DefaultIcon => uiColor(ThemeManager.shared.color.success)
            case CustomIcon(_, tint) => tint
        }
    }

    /** Raw CustomIcon token (for image-asset detection); "" otherwise.
     *  iOS getCenteredIcon renders a bundled illustration when visualKind is a
     *  customIcon image (e.g. success-secured-wallet) rather than a glyph. */
    public func customIconToken(): String {
        match (this) {
            case CustomIcon(token, _) => token
            case _ => ""
        }
    }
}

/**
 * Mirrors Swift `UIConfig.Success.Button`: title + style + the deep-link
 * navigation dispatched when it is clicked (Swift `navigationType`).
 */
public class SuccessButton {
    public let title: LocalizableStringKey
    public let style: SuccessButtonStyle
    public let navigationType: DeepLinkNavigationType

    public init(
        title!: LocalizableStringKey,
        style!: SuccessButtonStyle = SuccessButtonStyle.StylePrimary,
        navigationType!: DeepLinkNavigationType
    ) {
        this.title = title
        this.style = style
        this.navigationType = navigationType
    }

    public func titleText(): String {
        LocalizableManager.get(this.title)
    }
}

/**
 * Mirrors Swift `UIConfig.Success` — the config that drives SuccessView
 * (56 consumer sites on iOS): title (+color), subtitle, action buttons and
 * the visual kind of the centre icon.
 */
public class SuccessUIConfig <: UIConfigType {
    public let title: SuccessTitle
    public let subtitle: LocalizableStringKey
    public let buttons: Array<SuccessButton>
    public let visualKind: SuccessVisualKind

    public init(
        title!: SuccessTitle,
        subtitle!: LocalizableStringKey,
        buttons!: Array<SuccessButton> = Array<SuccessButton>(),
        visualKind!: SuccessVisualKind = SuccessVisualKind.DefaultIcon
    ) {
        this.title = title
        this.subtitle = subtitle
        this.buttons = buttons
        this.visualKind = visualKind
    }

    public prop log: String {
        get() {
            var buttonTitles = ""
            var buttonActions = ""
            for (button in this.buttons) {
                if (!buttonTitles.isEmpty()) {
                    buttonTitles += ","
                    buttonActions += ","
                }
                buttonTitles += button.titleText()
                buttonActions += button.navigationType.typeKey()
            }
            return "title: ${LocalizableManager.get(this.title.value)}" +
                " caption: ${LocalizableManager.get(this.subtitle)}" +
                " buttons: ${buttonTitles}" +
                " actions: ${buttonActions}"
        }
    }
}

// ─── IssuanceFlowUiConfig (Config/Issuance/IssuanceFlowUiConfig.swift) ──

/**
 * Mirrors Swift `IssuanceFlowUiConfig.Flow`: noDocument, or extraDocument
 * with an optional document-type-identifier filter. The iOS payload type
 * `DocumentTypeIdentifier` lives in logic-core (not yet delivered), so the
 * raw identifier string is carried instead.
 */
public enum IssuanceFlow {
    | NoDocument
    | ExtraDocument(Option<String>)
}

/** Mirrors Swift `IssuanceFlowUiConfig`. */
public class IssuanceFlowUiConfig <: UIConfigType {
    public let flow: IssuanceFlow

    public init(flow!: IssuanceFlow) {
        this.flow = flow
    }

    public prop isNoDocumentFlow: Bool {
        get() {
            match (this.flow) {
                case NoDocument => true
                case _ => false
            }
        }
    }

    public prop isExtraDocumentFlow: Bool {
        get() {
            match (this.flow) {
                case ExtraDocument(_) => true
                case _ => false
            }
        }
    }

    public prop log: String {
        get() {
            match (this.flow) {
                case NoDocument => "flow: noDocument"
                case ExtraDocument(filterType) =>
                    "flow: extraDocument(${filterType ?? ""})"
            }
        }
    }
}

// ─── IssuanceCodeUiConfig (Config/Issuance/IssuanceCodeUiConfig.swift) ──

/**
 * Mirrors Swift `IssuanceCodeUiConfig`. The iOS `docOffers: [OfferedDocModel]`
 * payload type belongs to logic-core (not yet delivered); the display names
 * are carried as strings, which is the only field `log`/UI consume.
 */
public class IssuanceCodeUiConfig <: UIConfigType {
    public let offerUri: String
    public let issuerName: String
    public let txCodeLength: Int64
    public let docOffers: Array<String>
    public let successNavigation: TwoWayNavigationType
    public let navigationCancelType: ThreeWayNavigationType

    public init(
        offerUri!: String,
        issuerName!: String,
        txCodeLength!: Int64,
        docOffers!: Array<String> = Array<String>(),
        successNavigation!: TwoWayNavigationType,
        navigationCancelType!: ThreeWayNavigationType
    ) {
        this.offerUri = offerUri
        this.issuerName = issuerName
        this.txCodeLength = txCodeLength
        this.docOffers = docOffers
        this.successNavigation = successNavigation
        this.navigationCancelType = navigationCancelType
    }

    public prop log: String {
        get() {
            var offers = ""
            for (offer in this.docOffers) {
                if (!offers.isEmpty()) {
                    offers += ","
                }
                offers += offer
            }
            return "offerUri: ${this.offerUri}" +
                " issuerName: ${this.issuerName}" +
                " txCodeLength: ${this.txCodeLength}" +
                " docOffers ${offers}" +
                " onSuccessNav: ${this.successNavigation.key()}" +
                " onBackNav: ${this.navigationCancelType.key()}"
        }
    }
}

// ─── DocumentSuccessUIConfig (Config/Presentation/DocumentSuccessUIConfig.swift) ──

/** Mirrors Swift `DocumentSuccessUIConfig` (presentation/issuance success). */
public class DocumentSuccessUIConfig <: UIConfigType {
    public let successNavigation: DeepLinkNavigationType
    public let relyingParty: ?String
    public let issuerLogoUrl: String
    public let relyingPartyIsTrusted: Bool
    public let isIssuingDocument: Bool
    // Titles of the shared documents, so the presentation success page can
    // render the document-list layout (iOS DocumentSuccessView). Empty for the
    // generic success cases.
    public let docTitles: Array<String>
    // The exact rows disclosed by the holder, grouped by document. Presentation
    // success uses these to render the same expandable detail list as the
    // request screen instead of a non-interactive "View details" label.
    public let docSections: Array<RequestDataSection>

    public init(
        successNavigation!: DeepLinkNavigationType,
        relyingParty!: ?String = Option<String>.None,
        issuerLogoUrl!: String = "",
        relyingPartyIsTrusted!: Bool,
        isIssuingDocument!: Bool,
        docTitles!: Array<String> = Array<String>(),
        docSections!: Array<RequestDataSection> = Array<RequestDataSection>()
    ) {
        this.successNavigation = successNavigation
        this.relyingParty = relyingParty
        this.issuerLogoUrl = issuerLogoUrl
        this.relyingPartyIsTrusted = relyingPartyIsTrusted
        this.isIssuingDocument = isIssuingDocument
        this.docTitles = docTitles
        this.docSections = docSections
    }

    public prop log: String {
        get() {
            "onSuccessNav: ${this.successNavigation.typeKey()}" +
                " relyingParty: ${this.relyingParty ?? ""}"
        }
    }
}
