/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/Content/ContentHeader/RelyingPartyRegistrationView.swift,
 * DesignSystem/Component/Warning/WarningAcknowledgementView.swift) to Cangjie
 * ArkUI (registration certificate trust layer, wallet-kit 0.40.x).
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.app.ability.want.Want
import eudi_logic_core.AppContextHolder
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Opens `url` in the system browser (mirrors iOS `Link` / `url.open()`; same
 * Want the dashboard settings screen uses for the changelog link). Failures
 * are swallowed — a dead link must not take the request screen down.
 */
public func openExternalUrl(url: String): Unit {
    if (url.isEmpty()) {
        return
    }
    match (AppContextHolder.get()) {
        case Some(ctx) =>
            try {
                ctx.startAbility(Want(
                    action: "ohos.want.action.viewData",
                    uri: url,
                    entities: ["entity.system.browsable"]
                ))
            } catch (_: Exception) {}
        case None => ()
    }
}

/**
 * Mirrors Swift `RegisteredParty`: one registered party row of the
 * registration header. `logoUrl` follows the module's string-URL convention
 * (`""` = no logo, see RelyingPartyData).
 */
public class RegisteredParty {
    public let name: LocalizableStringKey
    public let identifier: ?LocalizableStringKey
    public let isVerified: Bool
    public let logoUrl: String

    public init(
        name!: LocalizableStringKey,
        identifier!: ?LocalizableStringKey = None,
        isVerified!: Bool,
        logoUrl!: String = ""
    ) {
        this.name = name
        this.identifier = identifier
        this.isVerified = isVerified
        this.logoUrl = logoUrl
    }
}

/**
 * Mirrors Swift `RelyingPartyRegistrationData`: the registration header
 * payload (party row + optional privacy-policy link + optional intended use).
 * `privacyPolicyUrl` uses the string-URL convention (`""` = absent).
 */
public class RelyingPartyRegistrationData {
    public let primary: RegisteredParty
    public let privacyPolicyUrl: String
    public let intendedUse: ?LocalizableStringKey

    public init(
        primary!: RegisteredParty,
        privacyPolicyUrl!: String = "",
        intendedUse!: ?LocalizableStringKey = None
    ) {
        this.primary = primary
        this.privacyPolicyUrl = privacyPolicyUrl
        this.intendedUse = intendedUse
    }
}

/**
 * Mirrors Swift `RelyingPartyRegistrationView`: leading column with the party
 * row (verified seal only when `isVerified`, bold name, optional "(ID: …)"
 * subline, optional trailing 40vp circular remote logo), an optional
 * "Privacy policy" external link and an optional "Intended use" free-text
 * section. REPLACES ContentHeaderView on the request/offer screens.
 * `onOpenUrl` defaults to the system browser (`openExternalUrl`).
 */
@Component
public class RelyingPartyRegistrationView {
    public var data: RelyingPartyRegistrationData = RelyingPartyRegistrationData(
        primary: RegisteredParty(name: LocalizableStringKey.custom(""), isVerified: false)
    )
    public var onOpenUrl: (String) -> Unit = { url => openExternalUrl(url) }

    private func nameText(): String {
        LocalizableManager.get(this.data.primary.name)
    }

    private func identifierText(): String {
        ListItemData.optText(this.data.primary.identifier)
    }

    private func intendedUseText(): String {
        ListItemData.optText(this.data.intendedUse)
    }

    private func hasLogo(): Bool {
        !this.data.primary.logoUrl.isEmpty()
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            // Party row: seal + name (+ ID subline) leading, circular logo trailing.
            Row(space: SPACING_SMALL) {
                Column(space: SPACING_EXTRA_SMALL) {
                    Row(space: SPACING_SMALL) {
                        if (this.data.primary.isVerified) {
                            // iOS relyingPartyVerified seal at 20pt: drawn with
                            // built-ins like RelyingPartyView's badge (the
                            // rasterised PNG data-URI is near-invisible at 20pt).
                            Stack {
                                Text("✓")
                                    .fontSize(12.0)
                                    .fontWeight(FontWeight.Bold)
                                    .fontColor(uiColor(ThemeManager.shared.color.white))
                            }
                            .width(20.0)
                            .height(20.0)
                            .borderRadius(10.0)
                            .backgroundColor(uiColor(ThemeManager.shared.color.success))
                        }
                        Text(this.nameText())
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .textAlign(TextAlign.Start)
                            .layoutWeight(1)
                    }
                    .width(100.percent)
                    if (!this.identifierText().isEmpty()) {
                        Text(this.identifierText())
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                            .textAlign(TextAlign.Start)
                            .width(100.percent)
                    }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.hasLogo()) {
                    // iOS 40pt RemoteImageView clipped to a circle; the clip
                    // lives on a wrapping container (Column .borderRadius +
                    // .clip pattern, see ExpandableCardView).
                    Column {
                        Image(this.data.primary.logoUrl)
                            .width(40.0)
                            .height(40.0)
                            .objectFit(ImageFit.Cover)
                    }
                    .width(40.0)
                    .height(40.0)
                    .borderRadius(20.0)
                    .clip(true)
                }
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Top)

            if (!this.data.privacyPolicyUrl.isEmpty()) {
                this.buildPrivacyPolicySection()
            }

            if (!this.intendedUseText().isEmpty()) {
                this.buildIntendedUseSection()
            }
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }

    /** iOS `privacyPolicyView`: section title + accent link with the
     *  arrow.up.right.square glyph, opening the external URL on tap. */
    @Builder
    func buildPrivacyPolicySection() {
        Column(space: SPACING_SMALL) {
            Text(LocalizableManager.get(LocalizableStringKey.privacyPolicy))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Start)
                .width(100.percent)
            Row(space: SPACING_EXTRA_SMALL) {
                Text(this.data.privacyPolicyUrl)
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.accent))
                    .textAlign(TextAlign.Start)
                Image(appImageSrc(ThemeManager.shared.image.arrowUpRightSquare))
                    .width(16.0)
                    .height(16.0)
                    .objectFit(ImageFit.Contain)
            }
            .alignItems(VerticalAlign.Center)
            .onClick({ _ => this.onOpenUrl(this.data.privacyPolicyUrl) })
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }

    /** iOS `section(title: .intendedUse)`: section title + free text. */
    @Builder
    func buildIntendedUseSection() {
        Column(space: SPACING_SMALL) {
            Text(LocalizableManager.get(LocalizableStringKey.intendedUse))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Start)
                .width(100.percent)
            Text(this.intendedUseText())
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Start)
                .width(100.percent)
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }
}

/**
 * Mirrors Swift `WarningAcknowledgementView`: red-tinted (0.2 alpha, baked
 * into the ARGB byte — container `.opacity()` would fade the content too, see
 * ButtonViewStyle.error) rounded panel with a warning glyph + message, a
 * divider and the acknowledgement toggle. Presentational only: the host owns
 * `isAcknowledged` and receives changes via `onAcknowledgementChange` (the
 * repo's Toggle two-way pattern, see settings_view / filters_list_view).
 */
@Component
public class WarningAcknowledgementView {
    public var message: LocalizableStringKey = LocalizableStringKey.custom("")
    public var acknowledgementText: LocalizableStringKey = LocalizableStringKey.understandRisksAgree
    public var isAcknowledged: Bool = false
    public var onAcknowledgementChange: (Bool) -> Unit = { _ => }

    private func messageText(): String {
        LocalizableManager.get(this.message)
    }

    private func acknowledgementDisplayText(): String {
        LocalizableManager.get(this.acknowledgementText)
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            Row(space: SPACING_SMALL) {
                // iOS exclamationmarkTriangleFill tinted red at 20pt; no
                // bundled triangle asset, so the Unicode glyph carries it
                // (glyph-fallback convention, see image_resolver).
                Text("⚠")
                    .fontSize(20.0)
                    .fontColor(uiColor(ThemeManager.shared.color.red))
                Text(this.messageText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Start)
                    .layoutWeight(1)
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Center)

            ListDividerView(spacing: 0.0)

            Row(space: SPACING_SMALL) {
                Text(this.acknowledgementDisplayText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Start)
                    .layoutWeight(1)
                Toggle(ToggleType.Switch, isOn: this.isAcknowledged)
                    .selectedColor(uiColor(ThemeManager.shared.color.green))
                    .width(51.0)
                    .height(31.0)
                    .onChange({ isOn => this.onAcknowledgementChange(isOn) })
            }
            .width(100.percent)
            // iOS indents the toggle row past the warning icon (iconSize + spacing).
            .padding(top: 0.0, right: 0.0, bottom: 0.0, left: 20.0 + SPACING_SMALL)
            .alignItems(VerticalAlign.Center)
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
        // Theme red 0xFFFF0000 at iOS backgroundOpacity 0.2 → alpha byte 0x33.
        .backgroundColor(Color(0x33FF0000u32))
        .borderRadius(SPACING_SMALL)
        .alignItems(HorizontalAlign.Start)
    }
}
