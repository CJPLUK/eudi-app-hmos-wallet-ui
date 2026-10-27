/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/List/ExpandableCardView.swift, HomeCardView.swift,
 * ActionCardView.swift, CardViewWithLogoView.swift,
 * Content/ContentHeader/RelyingPartyView.swift, AppIconAndTextView.swift,
 * Image/RemoteImageView.swift, Blur/BlurView.swift) to Cangjie ArkUI.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Mirrors Swift `RemoteImageView` (SDWebImage): renders `url` when present;
 * otherwise degrades to the local `iconSrc`; with neither, a neutral rounded
 * box is drawn so layouts keep their footprint (fc failure mode
 * `remote_image_fail` → fallback).
 */
@Component
public class RemoteImageView {
    public var url: String = ""
    public var iconSrc: String = ""
    public var imageWidth: Float64 = ThemeManager.shared.dimension.remoteImageIconSize
    public var imageHeight: Float64 = ThemeManager.shared.dimension.remoteImageIconSize

    private func hasUrl(): Bool {
        !this.url.isEmpty()
    }

    private func hasIcon(): Bool {
        !this.iconSrc.isEmpty()
    }

    public func build() {
        if (this.hasUrl()) {
            Image(this.url)
                .width(this.imageWidth)
                .height(this.imageHeight)
                .objectFit(ImageFit.Contain)
        } else if (this.hasIcon()) {
            Image(appImageSrc(this.iconSrc))
                .width(this.imageWidth)
                .height(this.imageHeight)
                .objectFit(ImageFit.Contain)
        } else {
            Column() {}
                .width(this.imageWidth)
                .height(this.imageHeight)
                .backgroundColor(uiColor(ThemeManager.shared.color.tertiaryFill))
                .borderRadius(ThemeManager.shared.shape.extraSmall)
        }
    }
}

/** Mirrors Swift `AppIconAndTextData` (app icon + wordmark image pair). */
public class AppIconAndTextData {
    public let appIconSrc: String
    public let appTextSrc: String
    public let appIconSize: Float64
    public let appTextSize: Float64

    public init(
        appIconSrc!: String,
        appTextSrc!: String,
        appIconSize!: Float64 = 60.0,
        appTextSize!: Float64 = 60.0
    ) {
        this.appIconSrc = appIconSrc
        this.appTextSrc = appTextSrc
        this.appIconSize = appIconSize
        this.appTextSize = appTextSize
    }
}

/** Mirrors Swift `AppIconAndTextView`: centered icon + wordmark row. */
@Component
public class AppIconAndTextView {
    public var data: AppIconAndTextData = AppIconAndTextData(appIconSrc: "", appTextSrc: "")

    public func build() {
        Row(space: SPACING_SMALL) {
            if (!this.data.appIconSrc.isEmpty()) {
                Image(appImageSrc(this.data.appIconSrc))
                    .width(this.data.appIconSize)
                    .height(this.data.appIconSize)
                    .objectFit(ImageFit.Contain)
            }
            if (!this.data.appTextSrc.isEmpty()) {
                Image(appImageSrc(this.data.appTextSrc))
                    .width(this.data.appTextSize)
                    .height(this.data.appTextSize)
                    .objectFit(ImageFit.Contain)
            }
        }
        .width(100.percent)
        .justifyContent(FlexAlign.Center)
        // Keep the logo level with the wordmark (mirrors iOS, where they are
        // vertically centred side by side).
        .alignItems(VerticalAlign.Center)
    }
}

/** Mirrors Swift `RelyingPartyData` (logo / verified badge / name / description).
 *  `alignment` mirrors the iOS addition (default center; offer/request headers
 *  pass leading). */
public class RelyingPartyData {
    public let logoUrl: String
    public let logoSrc: String
    public let isVerified: Bool
    public let name: ?LocalizableStringKey
    public let nameTextConfig: ?TextConfig
    public let description: ?LocalizableStringKey
    public let descriptionTextConfig: ?TextConfig
    public let alignment: HorizontalAlign

    public init(
        logoUrl!: String = "",
        logoSrc!: String = "",
        isVerified!: Bool,
        name!: ?LocalizableStringKey = None,
        nameTextConfig!: ?TextConfig = None,
        description!: ?LocalizableStringKey = None,
        descriptionTextConfig!: ?TextConfig = None,
        alignment!: HorizontalAlign = HorizontalAlign.Center
    ) {
        this.logoUrl = logoUrl
        this.logoSrc = logoSrc
        this.isVerified = isVerified
        this.name = name
        this.nameTextConfig = nameTextConfig
        this.description = description
        this.descriptionTextConfig = descriptionTextConfig
        this.alignment = alignment
    }

    /** Row-axis equivalent of `alignment` for the name row / description. */
    public func rowAlign(): FlexAlign {
        match (this.alignment) {
            case HorizontalAlign.Start => FlexAlign.Start
            case HorizontalAlign.End => FlexAlign.End
            case _ => FlexAlign.Center
        }
    }

    /** Text-axis equivalent of `alignment` for the description block. */
    public func textAlign(): TextAlign {
        match (this.alignment) {
            case HorizontalAlign.Start => TextAlign.Start
            case HorizontalAlign.End => TextAlign.End
            case _ => TextAlign.Center
        }
    }
}

/**
 * Mirrors Swift `RelyingPartyView`: logo, name (with verified badge) and
 * description, centered. The iOS `leftImage` verified-badge modifier has no
 * ArkUI equivalent; the badge renders as a leading image in the name row.
 */
@Component
public class RelyingPartyView {
    public var relyingPartyData: RelyingPartyData = RelyingPartyData(isVerified: false)
    public var verifiedIconSrc: String = ""

    private func nameConfig(): TextConfig {
        this.relyingPartyData.nameTextConfig ?? TextConfig(
            font: ThemeManager.shared.font.bodyLarge,
            maxLines: 1,
            weightOverride: FontWeight.Medium
        )
    }

    private func descriptionConfig(): TextConfig {
        this.relyingPartyData.descriptionTextConfig ?? TextConfig(
            font: ThemeManager.shared.font.bodyMedium,
            maxLines: 2
        )
    }

    private func nameText(): String {
        ListItemData.optText(this.relyingPartyData.name)
    }

    private func descriptionText(): String {
        ListItemData.optText(this.relyingPartyData.description)
    }

    private func hasLogo(): Bool {
        !this.relyingPartyData.logoUrl.isEmpty() || !this.relyingPartyData.logoSrc.isEmpty()
    }

    private func showBadge(): Bool {
        this.relyingPartyData.isVerified && !this.verifiedIconSrc.isEmpty()
    }

    public func build() {
        Column(space: SPACING_SMALL) {
            if (!this.relyingPartyData.logoUrl.isEmpty()) {
                // iOS RelyingPartyView .remoteImage branch: width = screen/2.5
                // (40%), height follows the image's aspect ratio. iOS's
                // RemoteImageView falls back to the app logo while/if the
                // remote image fails (the dev issuer's logo URL 404s), so the
                // offer header still shows a logo block — mirror with .alt.
                Image(this.relyingPartyData.logoUrl)
                    .alt(appImageSrc("logo-eu-digital-indentity-wallet"))
                    .width(40.percent)
                    .objectFit(ImageFit.Contain)
            } else if (this.hasLogo()) {
                // iOS .image (local) branch: fixed 40×40.
                RemoteImageView(
                    url: this.relyingPartyData.logoUrl,
                    iconSrc: this.relyingPartyData.logoSrc,
                    imageWidth: 40.0,
                    imageHeight: 40.0
                )
            }
            if (!this.nameText().isEmpty()) {
                Row(space: ThemeManager.shared.dimension.verifiedBadgeSpacing) {
                    if (this.showBadge()) {
                        // iOS relyingPartyVerified badge: a filled green
                        // (success) disc with a white check. Drawn with
                        // built-ins so it renders crisply at 20pt (the
                        // rasterised SVG data-URI shows up near-invisible).
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
                        .fontSize(uiFontSize(this.nameConfig().font))
                        .fontWeight(this.nameConfig().resolvedWeight())
                        .fontColor(this.nameConfig().color)
                        .maxLines(this.nameConfig().maxLines)
                        .textOverflow(TextOverflow.Ellipsis)
                }
                .justifyContent(this.relyingPartyData.rowAlign())
            }
            if (!this.descriptionText().isEmpty()) {
                Text(this.descriptionText())
                    .fontSize(uiFontSize(this.descriptionConfig().font))
                    .fontColor(this.descriptionConfig().color)
                    .textAlign(this.relyingPartyData.textAlign())
                    .maxLines(this.descriptionConfig().maxLines)
                    .textOverflow(TextOverflow.Ellipsis)
            }
        }
        .width(100.percent)
        // iOS addition: the whole block follows `alignment` (default center).
        .alignItems(this.relyingPartyData.alignment)
    }
}

/**
 * Mirrors Swift `ExpandableCardView`: a card whose header row toggles the
 * expanded content slot (chevron up/down via `collapsedIconSrc` /
 * `expandedIconSrc`).
 */
@Component
public class ExpandableCardView {
    public var header: ListItemData = ListItemData(mainContent: MainContentData.ofText(LocalizableStringKey.custom("")))
    public var cardBackgroundColor: Color = uiColor(ThemeManager.shared.color.groupedBackground)
    public var collapsedIconSrc: String = ""
    public var expandedIconSrc: String = ""
    public var isLoading: Bool = false
    @State
    var isExpanded: Bool = false
    @BuilderParam
    var content: () -> Unit = eudiEmptyBuilder

    private func headerItem(): ListItemData {
        ListItemData(
            id: this.header.id,
            mainContent: this.header.mainContent,
            mainStyle: ListItemMainStyle.MainBold,
            supportingText: this.header.supportingText,
            supportingTextColor: this.header.supportingTextColor,
            leadingIcon: this.header.leadingIcon,
            trailingContent: TrailingContentData.icon(this.toggleIcon())
        )
    }

    private func toggleIcon(): String {
        if (this.isExpanded) {
            return this.expandedIconSrc
        }
        return this.collapsedIconSrc
    }

    private func toggle(): Unit {
        if (!this.isLoading) {
            this.isExpanded = !this.isExpanded
        }
    }

    public func build() {
        Column {
            // if/else remount: WrapListItemView's plain props don't refresh on
            // parent rebuild, so the expanded/collapsed chevron never flipped.
            if (this.isExpanded) {
                WrapListItemView(
                    listItem: this.headerItem(),
                    onItemAction: { => this.toggle() }
                )
            } else {
                WrapListItemView(
                    listItem: this.headerItem(),
                    onItemAction: { => this.toggle() }
                )
            }
            if (this.isExpanded) {
                this.content()
            }
        }
        .backgroundColor(this.cardBackgroundColor)
        .borderRadius(18.0)
        .clip(true)
    }
}

/**
 * Mirrors Swift `HomeCardView`: text + optional illustration, a primary
 * action button and an optional "learn more" secondary button.
 */
@Component
public class HomeCardView {
    public var text: LocalizableStringKey = LocalizableStringKey.custom("")
    public var buttonText: LocalizableStringKey = LocalizableStringKey.custom("")
    public var illustrationSrc: String = ""
    public var buttonViewStyle: ButtonViewStyle = ButtonViewStyle.primary()
    public var learnMoreText: ?LocalizableStringKey = None
    public var learnMoreIconSrc: String = ""
    public var hasLearnMore: Bool = false
    public var onLearnMore: () -> Unit = { => }
    public var onCardAction: () -> Unit = { => }

    private func mainText(): String {
        LocalizableManager.get(this.text)
    }

    private func learnMoreKey(): LocalizableStringKey {
        this.learnMoreText ?? LocalizableStringKey.custom("")
    }

    public func build() {
        Column(space: SPACING_NONE) {
            Row(space: SPACING_MEDIUM) {
                // Mirrors iOS: text flows in the flexible leading space (wraps full
                // lines, ~60%), the illustration is a fixed square pinned top-right
                // and Contain-fitted so the whole image is always shown (no clip).
                Text(this.mainText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineSmall))
                    .fontWeight(uiFontWeight(ThemeManager.shared.font.headlineSmall))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Start)
                    .layoutWeight(1)
                if (!this.illustrationSrc.isEmpty()) {
                    Image(appImageSrc(this.illustrationSrc))
                        .width(115.0)
                        .height(115.0)
                        .objectFit(ImageFit.Contain)
                }
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Top)
            Column {
                WrapButtonView(
                    title: this.buttonText,
                    style: this.buttonViewStyle,
                    verticalPadding: 12.0,
                    onAction: this.onCardAction
                )
            }
            .width(100.percent)
            .padding(top: SPACING_SMALL, right: 0.0, bottom: 0.0, left: 0.0)
            if (this.hasLearnMore) {
                Column {
                    WrapButtonView(
                        title: this.learnMoreKey(),
                        style: ButtonViewStyle.secondary(),
                        iconSrc: this.learnMoreIconSrc,
                        iconSize: 26.0,
                        verticalPadding: 12.0,
                        onAction: this.onLearnMore
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: 0.0, bottom: 0.0, left: 0.0)
            }
        }
        .padding(SPACING_MEDIUM)
        .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
        .borderRadius(13.0)
    }
}

/**
 * Mirrors Swift `ActionCard`: large icon + accent label on a grouped
 * background, fully tappable.
 */
@Component
public class ActionCardView {
    public var iconSrc: String = ""
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var onCardAction: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            if (!this.iconSrc.isEmpty()) {
                Image(appImageSrc(this.iconSrc))
                    .width(64.0)
                    .height(64.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(uiColor(ThemeManager.shared.color.accent))
            }
            Text(this.titleText())
                .fontSize(uiFontSize(ThemeManager.shared.font.labelLarge))
                .fontWeight(uiFontWeight(ThemeManager.shared.font.labelLarge))
                .fontColor(uiColor(ThemeManager.shared.color.accent))
        }
        .width(100.percent)
        .height(180.0)
        .justifyContent(FlexAlign.Center)
        .padding(top: SPACING_MEDIUM, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)
        .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
        .borderRadius(SPACING_MEDIUM)
        .onClick({ _ => this.onCardAction() })
    }
}

/**
 * Mirrors Swift `CardViewWithLogoView`: logo (remote with local fallback),
 * title with optional verified badge, tappable card.
 */
@Component
public class CardViewWithLogoView {
    public var cornerRadius: Float64 = 13.0
    public var cardBackgroundColor: Color = uiColor(ThemeManager.shared.color.groupedBackground)
    public var logoUrl: String = ""
    public var logoSrc: String = ""
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var isVerified: Bool = false
    public var verifiedIconSrc: String = ""
    public var onCardAction: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func hasLogo(): Bool {
        !this.logoUrl.isEmpty() || !this.logoSrc.isEmpty()
    }

    private func showBadge(): Bool {
        this.isVerified && !this.verifiedIconSrc.isEmpty()
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            if (this.hasLogo()) {
                Row {
                    RemoteImageView(url: this.logoUrl, iconSrc: this.logoSrc)
                }
                .width(100.percent)
                .justifyContent(FlexAlign.Start)
            }
            Row(space: ThemeManager.shared.dimension.verifiedBadgeSpacing) {
                if (this.showBadge()) {
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
                Text(this.titleText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Start)
                    .layoutWeight(1)
            }
            .width(100.percent)
        }
        .padding(SPACING_MEDIUM)
        .backgroundColor(this.cardBackgroundColor)
        .borderRadius(this.cornerRadius)
        .onClick({ _ => this.onCardAction() })
    }
}

/**
 * Mirrors Swift `BlurView` (UIVisualEffectView): an ArkUI `backdropBlur`
 * surface; place it inside a Stack above the content to be frosted.
 */
@Component
public class BlurView {
    public var blurRadius: Float64 = 12.0
    public var tintColor: Color = Color(0x33FFFFFFu32)

    public func build() {
        Column() {}
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(this.tintColor)
            .backdropBlur(this.blurRadius)
    }
}
