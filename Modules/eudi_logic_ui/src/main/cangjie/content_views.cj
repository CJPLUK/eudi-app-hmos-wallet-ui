/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/Content/ContentScreenView.swift,
 * Content/ContentEmptyView.swift, ContentHeader/ContentHeaderView.swift,
 * ContentTitleView.swift, ContentLoaderView.swift, ContentErrorView.swift,
 * ContentSheetView.swift, Unavailable/ContentUnavailableView.swift) to
 * Cangjie.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import std.collection.{HashMap, ArrayList}
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Mirrors Swift `ContentHeaderConfig`: app icon/wordmark pair, description,
 * main text, optional icon (remote with local fallback) and relying-party
 * block, each with optional text styling.
 */
public class ContentHeaderConfig {
    public let appIconAndTextData: AppIconAndTextData
    public let description: ?LocalizableStringKey
    public let descriptionTextConfig: ?TextConfig
    public let mainText: ?LocalizableStringKey
    public let mainTextConfig: ?TextConfig
    public let iconUrl: String
    public let iconSrc: String
    public let relyingPartyData: ?RelyingPartyData

    public init(
        appIconAndTextData!: AppIconAndTextData,
        description!: ?LocalizableStringKey = None,
        descriptionTextConfig!: ?TextConfig = None,
        mainText!: ?LocalizableStringKey = None,
        mainTextConfig!: ?TextConfig = None,
        iconUrl!: String = "",
        iconSrc!: String = "",
        relyingPartyData!: ?RelyingPartyData = None
    ) {
        this.appIconAndTextData = appIconAndTextData
        this.description = description
        this.descriptionTextConfig = descriptionTextConfig
        this.mainText = mainText
        this.mainTextConfig = mainTextConfig
        this.iconUrl = iconUrl
        this.iconSrc = iconSrc
        this.relyingPartyData = relyingPartyData
    }
}

/** Mirrors Swift `ContentHeaderView`. */
@Component
public class ContentHeaderView {
    public var config: ContentHeaderConfig = ContentHeaderConfig(
        appIconAndTextData: AppIconAndTextData(appIconSrc: "", appTextSrc: "")
    )

    private func descriptionText(): String {
        ListItemData.optText(this.config.description)
    }

    private func descriptionConfig(): TextConfig {
        this.config.descriptionTextConfig ?? TextConfig(
            font: ThemeManager.shared.font.bodyLarge,
            weightOverride: FontWeight.Medium
        )
    }

    private func mainTextValue(): String {
        ListItemData.optText(this.config.mainText)
    }

    private func mainConfig(): TextConfig {
        this.config.mainTextConfig ?? TextConfig(
            font: ThemeManager.shared.font.headlineMedium,
            weightOverride: FontWeight.Medium
        )
    }

    private func hasIcon(): Bool {
        !this.config.iconUrl.isEmpty() || !this.config.iconSrc.isEmpty()
    }

    private func relyingParty(): RelyingPartyData {
        this.config.relyingPartyData ?? RelyingPartyData(isVerified: false)
    }

    private func hasRelyingParty(): Bool {
        match (this.config.relyingPartyData) {
            case Some(_) => true
            case None => false
        }
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            AppIconAndTextView(data: this.config.appIconAndTextData)
            if (!this.descriptionText().isEmpty()) {
                WrapTextView(
                    text: this.config.description ?? LocalizableStringKey.custom(""),
                    textConfig: this.descriptionConfig()
                )
            }
            if (!this.mainTextValue().isEmpty()) {
                WrapTextView(
                    text: this.config.mainText ?? LocalizableStringKey.custom(""),
                    textConfig: this.mainConfig()
                )
            }
            if (this.hasIcon()) {
                RemoteImageView(
                    url: this.config.iconUrl,
                    iconSrc: this.config.iconSrc,
                    imageWidth: 120.0,
                    imageHeight: ThemeManager.shared.dimension.remoteImageIconSize
                )
            }
            if (this.hasRelyingParty()) {
                RelyingPartyView(
                    relyingPartyData: this.relyingParty(),
                    verifiedIconSrc: ThemeManager.shared.image.relyingPartyVerified
                )
            }
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Center)
    }
}

/** Mirrors Swift `ContentTitleView`: title + optional caption block. */
@Component
public class ContentTitleView {
    public var title: ?LocalizableStringKey = None
    public var caption: ?LocalizableStringKey = None
    public var titleColor: Color = uiColor(ThemeManager.shared.color.primaryLabel)
    public var captionColor: Color = uiColor(ThemeManager.shared.color.primaryLabel)
    public var titleFont: TypographyStyle = ThemeManager.shared.font.titleLarge
    public var onTitleTap: () -> Unit = { => }

    private func titleText(): String {
        ListItemData.optText(this.title)
    }

    private func captionText(): String {
        ListItemData.optText(this.caption)
    }

    public func build() {
        Column(space: SPACING_SMALL) {
            if (!this.titleText().isEmpty()) {
                Text(this.titleText())
                    .fontSize(uiFontSize(this.titleFont))
                    .fontWeight(uiFontWeight(this.titleFont))
                    .fontColor(this.titleColor)
                    .textAlign(TextAlign.Start)
                    .width(100.percent)
                    .onClick({ _ => this.onTitleTap() })
            }
            if (!this.captionText().isEmpty()) {
                Text(this.captionText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(this.captionColor)
                    .textAlign(TextAlign.Start)
                    .width(100.percent)
            }
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Start)
    }
}

/** Mirrors Swift `ContentLoaderView` (ActivityIndicatorView → LoadingProgress). */
@Component
public class ContentLoaderView {
    public var showLoader: Bool = true
    public var loaderWidth: Float64 = 50.0
    public var loaderHeight: Float64 = 50.0

    public func build() {
        if (this.showLoader) {
            LoadingProgress()
                .width(this.loaderWidth)
                .height(this.loaderHeight)
                .color(uiColor(ThemeManager.shared.color.accent))
        }
    }
}

/**
 * Mirrors Swift `ContentErrorView.Config`: texts plus retry/cancel actions.
 * `hasRetry == false` reproduces the Swift `action == nil` case.
 */
public class ContentErrorConfig {
    public let title: LocalizableStringKey
    public let description: LocalizableStringKey
    public let button: LocalizableStringKey
    public let cancelAction: () -> Unit
    public let hasRetry: Bool
    public let retryAction: () -> Unit

    public init(
        title!: LocalizableStringKey = LocalizableStringKey.genericErrorTitle,
        description!: LocalizableStringKey = LocalizableStringKey.genericErrorDesc,
        button!: LocalizableStringKey = LocalizableStringKey.tryAgain,
        cancelAction!: () -> Unit = { => },
        hasRetry!: Bool = false,
        retryAction!: () -> Unit = { => }
    ) {
        this.title = title
        this.description = description
        this.button = button
        this.cancelAction = cancelAction
        this.hasRetry = hasRetry
        this.retryAction = retryAction
    }
}

/**
 * Mirrors Swift `ContentErrorView`: full-screen error with dismiss icon,
 * title/description and an optional primary retry button.
 */
@Component
public class ContentErrorView {
    public var config: ContentErrorConfig = ContentErrorConfig()
    public var dismissIconSrc: String = ""

    public func build() {
        Column {
            Row {
                if (!this.dismissIconSrc.isEmpty()) {
                    Image(this.dismissIconSrc)
                        .width(24.0)
                        .height(24.0)
                        .objectFit(ImageFit.Contain)
                        .onClick({ _ => this.config.cancelAction() })
                } else {
                    Text("✕")
                        .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .onClick({ _ => this.config.cancelAction() })
                }
                Blank()
            }
            .width(100.percent)
            // Scrollable body so a long title/description never pushes the retry
            // button off-screen (iOS ContentScreenView + bottom button). The X row
            // stays pinned at the top and the button pinned at the bottom; only
            // the message scrolls between them.
            Scroll {
                ContentTitleView(
                    title: this.config.title,
                    caption: this.config.description
                )
            }
            .align(Alignment.TopStart)
            .width(100.percent)
            .layoutWeight(1)
            if (this.config.hasRetry) {
                WrapButtonView(
                    title: this.config.button,
                    style: ButtonViewStyle.primary(),
                    onAction: this.config.retryAction
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
        .padding(ThemeManager.shared.dimension.padding)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
        .alignItems(HorizontalAlign.Start)
    }
}

/**
 * Mirrors Swift `Unavailable/ContentUnavailableView.swift` (same name as
 * its iOS counterpart): bold title + centered description, pinned to the
 * top with large-medium top padding.
 */
@Component
public class ContentUnavailableView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var description: LocalizableStringKey = LocalizableStringKey.custom("")

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func descriptionText(): String {
        LocalizableManager.get(this.description)
    }

    public func build() {
        Column(space: SPACING_SMALL) {
            Text(this.titleText())
                .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            Text(this.descriptionText())
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Center)
        }
        .width(100.percent)
        .padding(top: SPACING_LARGE_MEDIUM, right: SPACING_MEDIUM, bottom: 0.0, left: SPACING_MEDIUM)
        .justifyContent(FlexAlign.Start)
    }
}

/**
 * Mirrors Swift `Content/ContentEmptyView.swift`: centered empty-state
 * block — an icon sized to a quarter of the container width above a
 * centered title — with an optional whole-block tap action. iOS defaults
 * the image to the exclamationmark-circle system glyph; HarmonyOS ships no
 * built-in glyph set (see featureX.md icon note), so an empty `iconSrc`
 * falls back to a self-drawn circled "!" tinted with `iconColor`.
 */
@Component
public class ContentEmptyView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var iconSrc: String = ""
    public var iconColor: Color = uiColor(ThemeManager.shared.color.primaryLabel)
    public var textColor: Color = uiColor(ThemeManager.shared.color.primaryLabel)
    public var onClick: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    public func build() {
        Column(space: SPACING_MEDIUM) {
            if (!this.iconSrc.isEmpty()) {
                // iOS: image.resizable().scaledToFit().frame(screen width / 4)
                Image(appImageSrc(this.iconSrc))
                    .width(25.percent)
                    .aspectRatio(1.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(this.iconColor)
            } else {
                Stack {
                    Text("!")
                        .fontSize(56.0)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.iconColor)
                }
                .width(96.0)
                .height(96.0)
                .borderWidth(4.0)
                .borderColor(this.iconColor)
                .borderRadius(48.0)
            }
            Text(this.titleText())
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontColor(this.textColor)
                .textAlign(TextAlign.Center)
                .width(100.percent)
        }
        .width(100.percent)
        .alignItems(HorizontalAlign.Center)
        .onClick({ _ => this.onClick() })
    }
}

/**
 * Mirrors the Swift nested type `ContentScreenView.NotificationAction`
 * (notification name + callback fired with the notification's userInfo),
 * flattened to a top-level class (Cangjie has no nested types).
 */
public class NotificationAction {
    public let name: String
    public let callback: (?HashMap<String, Any>) -> Unit

    public init(
        name!: String,
        callback!: (?HashMap<String, Any>) -> Unit
    ) {
        this.name = name
        this.callback = callback
    }
}

/** Token + callback pair stored by `UiNotificationCenter`. */
class NotificationSubscription {
    public let token: Int64
    public let callback: (?HashMap<String, Any>) -> Unit

    public init(token: Int64, callback: (?HashMap<String, Any>) -> Unit) {
        this.token = token
        this.callback = callback
    }
}

/**
 * In-process notification bus standing in for iOS `NotificationCenter`
 * (ContentScreenView.swift merges one publisher per NotificationAction and
 * dispatches the matching callback on receive). Process-wide singleton:
 * posters publish a named notification with an optional userInfo payload;
 * subscribers — registered by `ContentScreenView` from its
 * `notificationActions` parameter — receive that payload. The SDK offers
 * no in-process equivalent (ohos.common_event_manager is the cross-process
 * CES); decision recorded in unresolved_api_decisions.
 */
public class UiNotificationCenter {
    private static let instance: UiNotificationCenter = UiNotificationCenter()
    private let subscriptions: HashMap<String, ArrayList<NotificationSubscription>> =
        HashMap<String, ArrayList<NotificationSubscription>>()
    private var nextToken: Int64 = 0

    private init() {}

    public static prop shared: UiNotificationCenter {
        get() { instance }
    }

    /** Registers `callback` for `name`; returns the unsubscribe token. */
    public func subscribe(name: String, callback: (?HashMap<String, Any>) -> Unit): Int64 {
        this.nextToken += 1
        let token = this.nextToken
        if (!this.subscriptions.contains(name)) {
            this.subscriptions[name] = ArrayList<NotificationSubscription>()
        }
        this.subscriptions[name].add(NotificationSubscription(token, callback))
        return token
    }

    /** Drops the subscription registered under `token` for `name`. */
    public func unsubscribe(name: String, token: Int64): Unit {
        if (this.subscriptions.contains(name)) {
            let kept = ArrayList<NotificationSubscription>()
            for (sub in this.subscriptions[name]) {
                if (sub.token != token) {
                    kept.add(sub)
                }
            }
            this.subscriptions[name] = kept
        }
    }

    /** Delivers `userInfo` to every live subscriber of `name`. */
    public func post(name: String, userInfo!: ?HashMap<String, Any> = None): Unit {
        if (this.subscriptions.contains(name)) {
            for (sub in this.subscriptions[name]) {
                sub.callback(userInfo)
            }
        }
    }
}

/**
 * Mirrors Swift `ContentScreenView`: the screen skeleton used by ~50 iOS
 * screens. Renders the error state when `hasError`, otherwise an optional
 * self-drawn toolbar row (this HAR ships no NavDestination chrome — the
 * navigation shell belongs to the composition root) above the content
 * slot, optionally scrollable. The Scroll content is pinned to the top
 * (this binding's Scroll centers undersized content vertically —
 * QA-confirmed trap). `notificationActions` reproduces the iOS
 * NotificationCenter wiring: each action is subscribed on
 * `aboutToAppear` via `UiNotificationCenter` and released on
 * `aboutToDisappear`.
 */
@Component
public class ContentScreenView {
    public var screenPadding: Float64 = ThemeManager.shared.dimension.padding
    public var canScroll: Bool = false
    public var spacing: Float64 = 0.0
    public var background: Color = uiColor(ThemeManager.shared.color.background)
    public var navigationTitle: ?LocalizableStringKey = None
    public var isLoading: Bool = false
    public var hasError: Bool = false
    public var errorConfig: ContentErrorConfig = ContentErrorConfig()
    public var hasToolBar: Bool = false
    public var toolbarContent: ToolBarContent = ToolBarContent()
    public var notificationActions: Array<NotificationAction> = Array<NotificationAction>()
    private let notificationTokens: ArrayList<(String, Int64)> = ArrayList<(String, Int64)>()
    @BuilderParam
    var content: () -> Unit = eudiEmptyBuilder

    protected override func aboutToAppear(): Unit {
        for (action in this.notificationActions) {
            let token = UiNotificationCenter.shared.subscribe(action.name, action.callback)
            this.notificationTokens.add((action.name, token))
        }
    }

    protected override func aboutToDisappear(): Unit {
        for (entry in this.notificationTokens) {
            UiNotificationCenter.shared.unsubscribe(entry[0], entry[1])
        }
        this.notificationTokens.clear()
    }

    private func navTitleText(): String {
        ListItemData.optText(this.navigationTitle)
    }

    public func build() {
        if (this.hasError) {
            ContentErrorView(config: this.errorConfig)
        } else {
            Column {
                if (this.hasToolBar) {
                    ToolBarView(
                        content: this.toolbarContent,
                        isEnabled: !this.isLoading,
                        toolbarBackgroundColor: this.background
                    )
                }
                if (!this.navTitleText().isEmpty()) {
                    Text(this.navTitleText())
                        .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                        .fontWeight(uiFontWeight(ThemeManager.shared.font.headlineMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .textAlign(TextAlign.Center)
                        .width(100.percent)
                        .padding(top: SPACING_SMALL, right: 0.0, bottom: SPACING_SMALL, left: 0.0)
                }
                if (this.canScroll) {
                    Scroll {
                        Column(space: this.spacing) {
                            this.content()
                        }
                        .width(100.percent)
                        .padding(top: 0.0, right: this.screenPadding, bottom: 0.0, left: this.screenPadding)
                    }
                    .align(Alignment.TopStart)
                    .layoutWeight(1)
                } else {
                    Column(space: this.spacing) {
                        this.content()
                    }
                    .width(100.percent)
                    .padding(this.screenPadding)
                    .justifyContent(FlexAlign.Start)
                    .layoutWeight(1)
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(this.background)
        }
    }
}

/**
 * Mirrors Swift `ContentSheetView`: padded sheet body container; pair it
 * with the AlertView scrim or a panel anchored by the host page.
 */
@Component
public class ContentSheetView {
    @BuilderParam
    var content: () -> Unit = eudiEmptyBuilder

    public func build() {
        Column {
            this.content()
        }
        .width(100.percent)
        .padding(top: SPACING_LARGE, right: SPACING_MEDIUM, bottom: SPACING_MEDIUM, left: SPACING_MEDIUM)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
        .borderRadius(topLeft: ThemeManager.shared.shape.large, topRight: ThemeManager.shared.shape.large, bottomLeft: 0.0, bottomRight: 0.0)
    }
}
