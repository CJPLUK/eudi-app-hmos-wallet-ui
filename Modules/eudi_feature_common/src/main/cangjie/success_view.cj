/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Success/Generic/GenericSuccessView.swift +
 * GenericSuccessViewModel.swift) to Cangjie ArkUI.
 *
 * The generic result screen behind ~56 iOS consumer sites, fully driven by
 * `SuccessUIConfig`: centre icon (visualKind), tinted title, subtitle and
 * the action button group. Every button click fires `onButtonClicked` (host
 * callback) and dispatches the button's DeepLinkNavigationType through the
 * injected RouterHost — mirroring iOS `onButtonClicked(with:)` →
 * navigationType dispatch.
 *
 * Buttons render inside the ForEach item generator with built-in components
 * only (project convention), styled from eudi_logic_ui ButtonViewStyle so
 * primary/secondary match WrapButtonView visuals.
 *
 * Plain @Component — composition root owns navigation chrome.
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.app.ability.want.Want
import eudi_logic_ui.*
import eudi_logic_core.AppContextHolder
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Dispatches a DeepLinkNavigationType through a RouterHost.
 *
 * DeepLinkPop / DeepLinkOpen use incremental popTo. ProdRouterHost peels the
 * real NavPathStack first and keeps pathNames in lockstep (see that file).
 */
public func dispatchDeepLinkNavigation(router: RouterHost, navigation: DeepLinkNavigationType): Unit {
    match (navigation) {
        case DeepLinkPush(route) => router.push(route)
        case DeepLinkPop(route, _) => router.popTo(route)
        case DeepLinkOpen(link, route) =>
            // Mirrors iOS `.deepLink(link:popToScreen:)` on the RQES service /
            // credential authorization: pop back to the anchor screen, then hand
            // the verifier redirect to the system browser. The QTSP callback
            // 302-continues the OAuth to rqes://oauth/callback?code, which
            // deep-links the app back into the signing flow.
            router.popTo(route)
            match (AppContextHolder.get()) {
                case Some(ctx) =>
                    try {
                        ctx.startAbility(Want(
                            action: "ohos.want.action.viewData",
                            uri: link,
                            entities: ["entity.system.browsable"]
                        ))
                    } catch (_: Exception) {
                        // Non-fatal: already popped to the anchor screen; the
                        // RQES flow simply won't continue, matching a cancelled
                        // authorization.
                        ()
                    }
                case None => ()
            }
        case DeepLinkNone => ()
    }
}

/** Dispatches TwoWayNavigationType. */
public func dispatchTwoWayNavigation(router: RouterHost, navigation: TwoWayNavigationType): Unit {
    match (navigation) {
        case NavPush(route) => router.push(route)
        case NavPopTo(route) => router.popTo(route)
    }
}

/**
 * Dispatches ThreeWayNavigationType. ThreeWayPush clears auth pages then
 * pushes (login landing). ThreeWayPopTo uses incremental popTo.
 */
public func dispatchThreeWayNavigation(router: RouterHost, navigation: ThreeWayNavigationType): Unit {
    match (navigation) {
        case ThreeWayPopTo(route) => router.popTo(route)
        case ThreeWayPop => router.pop()
        case ThreeWayPush(route) =>
            router.popTo(AppRoutes.startup)
            router.push(route)
        case ThreeWayPushInFlow(route) => router.push(route)
    }
}

/** Default config so an uninjected instance still renders honestly. */
func defaultSuccessUIConfig(): SuccessUIConfig {
    SuccessUIConfig(
        title: SuccessTitle(value: LocalizableStringKey.successTitlePunctuated),
        subtitle: LocalizableStringKey.custom("")
    )
}

/**
 * Generic success screen (fc_common_shared_screens exposed symbol
 * `SuccessView`).
 *
 * Injection points (S-017):
 *  - `config`: the SuccessUIConfig driving icon/title/subtitle/buttons
 *    (also deliverable through NavArgs under AppRoutes.genericSuccess as a
 *    RouteConfigArgs — pass `useNavArgs: true` for router-pushed instances).
 *  - `router`: RouterHost used for button navigation dispatch.
 *  - `onButtonClicked`: per-button host callback (fires before dispatch).
 */
@Component
public class SuccessView {
    public var config: SuccessUIConfig = defaultSuccessUIConfig()
    public var router: ?RouterHost = Option<RouterHost>.None
    public var onButtonClicked: (SuccessButton) -> Unit = { _ => }
    public var useNavArgs: Bool = false

    @State
    var titleText: String = ""
    @State
    var captionText: String = ""
    @State
    var iconText: String = ""
    @State
    var iconImageSrc: String = ""
    @State
    var buttons: Array<SuccessButton> = Array<SuccessButton>()

    private var resolvedConfig: SuccessUIConfig = defaultSuccessUIConfig()

    protected override func aboutToAppear(): Unit {
        var cfg = this.config
        if (this.useNavArgs) {
            // Router-pushed instances read the config payload left by the
            // pusher (QuickPinViewModel.routeToSuccess and friends).
            match (NavArgs.shared.take(AppRoutes.genericSuccess)) {
                case Some(payload) =>
                    match (payload as RouteConfigArgs) {
                        case Some(args) =>
                            match (args.config as SuccessUIConfig) {
                                case Some(successCfg) => cfg = successCfg
                                case None => ()
                            }
                        case None => ()
                    }
                case None => ()
            }
        }
        this.resolvedConfig = cfg
        this.titleText = LocalizableManager.get(cfg.title.value)
        this.captionText = LocalizableManager.get(cfg.subtitle)
        this.iconText = cfg.visualKind.iconText()
        // iOS getCenteredIcon: a customIcon image renders the bundled
        // illustration (success-secured-wallet etc.); only fall back to the
        // glyph when the token is not an embedded image asset.
        let imgTok = cfg.visualKind.customIconToken()
        this.iconImageSrc = if (!imgTok.isEmpty() && !imageDataUri(imgTok).isEmpty()) {
            imgTok
        } else {
            ""
        }
        this.buttons = cfg.buttons
    }

    /** iOS GenericSuccessView ContentHeaderView (logo + EUDI wordmark). */
    private func headerConfig(): ContentHeaderConfig {
        ContentHeaderConfig(
            appIconAndTextData: AppIconAndTextData(
                appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                appTextSrc: ThemeManager.shared.image.euditext
            )
        )
    }

    private func handleButton(button: SuccessButton): Unit {
        this.onButtonClicked(button)
        match (this.router) {
            case Some(host) => dispatchDeepLinkNavigation(host, button.navigationType)
            case None => ()
        }
    }

    private func titleColor(): Color {
        this.resolvedConfig.title.color
    }

    private func iconColor(): Color {
        this.resolvedConfig.visualKind.iconTint()
    }

    private func buttonStyle(button: SuccessButton): ButtonViewStyle {
        if (button.style.isPrimary()) {
            return ButtonViewStyle.primary()
        }
        return ButtonViewStyle.secondary()
    }

    private func hasCaption(): Bool {
        !this.captionText.isEmpty()
    }

    public func build() {
        Column(space: SPACING_LARGE_MEDIUM) {
            ContentHeaderView(config: this.headerConfig())
            Blank()
            // iOS getCenteredIcon: bundled illustration for image visualKinds,
            // glyph otherwise (frame ≈ screen width / 2.5).
            if (!this.iconImageSrc.isEmpty()) {
                AppIcon(token: this.iconImageSrc, size: 160.0)
            } else {
                Text(this.iconText)
                    .fontSize(uiFontSize(ThemeManager.shared.font.displayLarge))
                    .fontColor(this.iconColor())
                    .textAlign(TextAlign.Center)
            }
            Text(this.titleText)
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.titleColor())
                .textAlign(TextAlign.Center)
                .width(100.percent)
            if (this.hasCaption()) {
                Text(this.captionText)
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .textAlign(TextAlign.Center)
                    .width(100.percent)
            }
            Blank()
            Column(space: SPACING_SMALL) {
                ForEach(
                    this.buttons,
                    itemGenerator: { button: SuccessButton, _: Int64 =>
                        // Built-in Button styled like WrapButtonView (no
                        // custom @Component inside the item generator).
                        Button(button.titleText())
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontColor(this.buttonStyle(button).textColor)
                            .backgroundColor(this.buttonStyle(button).backgroundColor)
                            .borderWidth(this.buttonStyle(button).borderWidth)
                            .borderColor(this.buttonStyle(button).borderColor)
                            .borderRadius(ThemeManager.shared.shape.extraSmall)
                            .height(48.0)
                            .width(100.percent)
                            .onClick({ _ => this.handleButton(button) })
                    }
                )
            }
            .width(100.percent)
        }
        .width(100.percent)
        .height(100.percent)
        .padding(ThemeManager.shared.dimension.padding)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
        .alignItems(HorizontalAlign.Center)
    }
}
