/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * Compile-time gallery probe for the eudi_logic_ui design system: a
 * component whose build() composes every delivered @Component once (DSL
 * usage validated by the compiler), plus a top-level function exercising
 * every model / logic type so nothing in this HAR is left unreferenced.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import std.collection.HashMap
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** Sample reducer state for the BaseViewModel probe (public per R-104). */
public class GalleryViewState <: ViewState {
    public let counter: Int64

    public init(counter: Int64) {
        this.counter = counter
    }
}

/** Sample view model proving BaseViewModel<S> is consumable. */
public class GalleryViewModel <: BaseViewModel<GalleryViewState> {
    public init(router: RouterHost) {
        super(router, GalleryViewState(0))
    }

    public func increment(): Unit {
        this.setState({ previous => GalleryViewState(previous.counter + 1) })
    }
}

// ── Top-level @Builder slot fillers ─────────────────────────────────────
// Custom components reject inline trailing-closure DSL on this binding;
// @BuilderParam slots are filled by passing top-level @Builder references
// (gallery usage below doubles as the consumer-side example).

func gallerySampleHeader(): ContentHeaderConfig {
    ContentHeaderConfig(
        appIconAndTextData: AppIconAndTextData(appIconSrc: "", appTextSrc: ""),
        description: LocalizableStringKey.custom("Description"),
        relyingPartyData: RelyingPartyData(
            isVerified: true,
            name: LocalizableStringKey.custom("Relying Party")
        )
    )
}

@Builder
public func galleryScreenBody() {
    ContentHeaderView(config: gallerySampleHeader())
    ContentTitleView(
        title: LocalizableStringKey.custom("Title"),
        caption: LocalizableStringKey.custom("Caption")
    )
    ContentLoaderView(showLoader: true)
    ContentEmptyView(
        title: LocalizableStringKey.noResults,
        onClick: galleryEmptyStateTap
    )
    ContentUnavailableView(
        title: LocalizableStringKey.noResults,
        description: LocalizableStringKey.custom("Nothing here")
    )
}

/** Real tap target for the gallery's empty state (observable side effect). */
func galleryEmptyStateTap(): Unit {
    UiNotificationCenter.shared.post("gallery.empty_state_tap")
}

/**
 * Sample notification wiring for the screen probe: mirrors the iOS
 * Dashboard revocation subscription; the callback forwards the payload
 * into the NavArgs channel (observable side effect, no dead callback).
 */
func galleryNotificationActions(): Array<NotificationAction> {
    [
        NotificationAction(
            name: "gallery.revocation",
            callback: { payload =>
                match (payload) {
                    case Some(map) => NavArgs.shared.set("gallery.revocation", map)
                    case None => ()
                }
            }
        )
    ]
}

@Builder
public func gallerySheetBody() {
    Text("Sheet body")
}

@Builder
public func galleryCardBody() {
    Text("Card body")
}

@Builder
public func galleryExpandedBody() {
    Text("Expanded content")
}

/**
 * Renders one instance of every design-system component. Never routed in
 * production; exists so the whole component surface stays compiled.
 */
@Component
public class GalleryProbe {
    private func sampleItem(): ListItemData {
        ListItemData(
            mainContent: MainContentData.ofText(LocalizableStringKey.custom("Main Text")),
            overlineText: LocalizableStringKey.custom("Overline"),
            supportingText: LocalizableStringKey.custom("Supporting"),
            trailingContent: TrailingContentData.icon("")
        )
    }

    private func sampleToolbar(): ToolBarContent {
        ToolBarContent(
            trailingActions: [
                ToolBarAction(title: LocalizableStringKey.custom("Proceed"))
            ]
        )
    }

    public func build() {
        Scroll {
            Column(space: SPACING_MEDIUM) {
                Column {
                    ContentScreenView(
                        navigationTitle: LocalizableStringKey.custom("Gallery"),
                        hasToolBar: true,
                        toolbarContent: this.sampleToolbar(),
                        notificationActions: galleryNotificationActions(),
                        content: galleryScreenBody
                    )
                }
                .height(480.0)
                Column {
                    ContentErrorView(config: ContentErrorConfig(hasRetry: true))
                }
                .height(240.0)
                ContentSheetView(content: gallerySheetBody)
                ToolBarView(content: this.sampleToolbar())
                WrapButtonView(
                    title: LocalizableStringKey.custom("Primary"),
                    style: ButtonViewStyle.primary()
                )
                WrapButtonView(
                    title: LocalizableStringKey.custom("Secondary"),
                    style: ButtonViewStyle.secondary(),
                    gravity: WrapButtonGravity.GravityStart,
                    isLoading: true
                )
                WrapCardView(content: galleryCardBody)
                WrapTextView(
                    text: LocalizableStringKey.custom("Wrapped text"),
                    textConfig: TextConfig(font: ThemeManager.shared.font.bodyLarge)
                )
                WrapIconView(
                    title: LocalizableStringKey.custom("Icon row"),
                    textColor: uiColor(ThemeManager.shared.color.primaryLabel)
                )
                WrapImageView(imageSrc: "")
                WrapListItemView(listItem: this.sampleItem())
                ListDividerView()
                EasySpacer(spacerHeight: SPACING_MEDIUM)
                ExpandableCardView(header: this.sampleItem(), content: galleryExpandedBody)
                HomeCardView(
                    text: LocalizableStringKey.custom("Home card"),
                    buttonText: LocalizableStringKey.custom("Go")
                )
                ActionCardView(title: LocalizableStringKey.custom("Action"))
                CardViewWithLogoView(title: LocalizableStringKey.custom("Organization"))
                RelyingPartyView(
                    relyingPartyData: RelyingPartyData(
                        isVerified: true,
                        name: LocalizableStringKey.custom("Verifier")
                    )
                )
                AppIconAndTextView(data: AppIconAndTextData(appIconSrc: "", appTextSrc: ""))
                RemoteImageView(url: "", iconSrc: "")
                PinTextFieldView(maxDigits: 4, isSecureEntry: true)
                SearchableList(items: [this.sampleItem()])
                Stack {
                    Text("Blurred backdrop")
                    BlurView(blurRadius: 8.0)
                }
                .height(60.0)
                Column {
                    AlertView(
                        title: LocalizableStringKey.custom("Alert"),
                        message: LocalizableStringKey.custom("Message"),
                        actions: [AlertAction(title: LocalizableStringKey.okButton)]
                    )
                }
                .height(240.0)
            }
            .width(100.percent)
        }
        .align(Alignment.TopStart)
    }
}

/**
 * Top-level probe touching every public model/logic symbol of this HAR.
 * Returns a checksum of the exercised behaviours (non-zero on success).
 */
public func eudiLogicUiGalleryProbe(): Int64 {
    var checks: Int64 = 0

    // theme: config models constructible & comparable, theme bridge opaque.
    let toolBar = UIConfigToolBar(uiColor(ThemeManager.shared.color.background))
    if (toolBar == UIConfigToolBar(uiColor(ThemeManager.shared.color.background))) {
        checks += 1
    }
    if (NoConfig() == NoConfig() && NoConfig().log.isEmpty()) {
        checks += 1
    }
    if ((uiColor(ThemeManager.shared.color.background).toUInt32() >> 24) != 0) {
        checks += 1
    }
    let generic = UIConfigGeneric(
        arguments: HashMap<String, String>([("flow", "issuance")]),
        navigationSuccessType: TwoWayNavigationType.NavPush(AppRoutes.dashboard),
        navigationCancelType: ThreeWayNavigationType.ThreeWayPop
    )
    if (!generic.log.isEmpty() && generic == generic) {
        checks += 1
    }
    if (DeepLinkNavigationType.DeepLinkNone.typeKey() == "none") {
        checks += 1
    }

    // navigation: route set, ConfigUiLogic, router double behaviour.
    if (AppRoutes.allRoutes().size == 24) {
        checks += 1
    }
    let configLogic: ConfigUiLogic = ConfigUiLogicImpl()
    if (configLogic.dashboardRoute == AppRoutes.dashboard &&
        configLogic.issuanceRoute == AppRoutes.issuanceAddDocument) {
        checks += 1
    }
    let router = InMemoryRouterHost(configLogic)
    router.push(AppRoutes.startup)
    router.push(AppRoutes.dashboard)
    router.push(AppRoutes.documentDetails)
    if (router.isScreenOnBackStack(AppRoutes.dashboard) &&
        router.isScreenForeground(AppRoutes.documentDetails)) {
        checks += 1
    }
    router.popTo(AppRoutes.dashboard, false)
    // Incremental pop: [startup, dashboard, details] → [startup, dashboard]
    if ((router.getCurrentScreen() ?? "") == AppRoutes.dashboard && router.stackSize() == 2) {
        checks += 1
    }
    router.popTo(AppRoutes.startup, true)
    router.pop() // empty stack: no-op
    if (router.stackSize() == 0) {
        checks += 1
    }
    NavArgs.shared.set(AppRoutes.documentDetails, RouteIdArgs("doc-1"))
    match (NavArgs.shared.take(AppRoutes.documentDetails)) {
        case Some(payload) =>
            match (payload as RouteIdArgs) {
                case Some(args) => if (args.id == "doc-1") { checks += 1 }
                case None => ()
            }
        case None => ()
    }
    let loaderArgs = RouteLoaderArgs(
        relyingParty: "Verifier",
        relyingPartyIsTrusted: true,
        originator: AppRoutes.dashboard,
        items: [RouteConfigArgs(NoConfig()), RouteSuccessArgs(config: NoConfig()), RouteOriginatorArgs(AppRoutes.dashboard)]
    )
    if (!loaderArgs.log.isEmpty()) {
        checks += 1
    }

    // mvvm: reducer updates state, single-slot listener observes it.
    let box = GalleryListenerBox()
    let viewModel = GalleryViewModel(router)
    viewModel.onStateChange({ state => box.lastCounter = state.counter })
    viewModel.increment()
    viewModel.increment()
    if (viewModel.viewState.counter == 2 && box.lastCounter == 2) {
        checks += 1
    }
    viewModel.clearStateListener()

    // models: list item family equality + toolbar emptiness.
    let item = ListItemData(
        mainContent: MainContentData.ofText(LocalizableStringKey.custom("A")),
        leadingIcon: LeadingIconData(iconSrc: "icon"),
        trailingContent: TrailingContentData.checkbox(true, false, { _ => })
    )
    let same = ListItemData(
        mainContent: MainContentData.ofText(LocalizableStringKey.custom("A")),
        leadingIcon: LeadingIconData(iconSrc: "icon"),
        trailingContent: TrailingContentData.checkbox(true, false, { _ => })
    )
    let different = ListItemData(
        mainContent: MainContentData.ofText(LocalizableStringKey.custom("B"))
    )
    if (item == same && item != different && item.groupId == item.id) {
        checks += 1
    }
    if (ToolBarContent().isEmpty()) {
        checks += 1
    }

    // notifications: NotificationAction subscribe → post(payload) delivers,
    // unsubscribe → later posts are no longer delivered (iOS NotificationCenter
    // semantics reproduced by UiNotificationCenter).
    let notificationBox = GalleryListenerBox()
    notificationBox.lastCounter = 0
    let revocation = NotificationAction(
        name: "gallery.probe_revocation",
        callback: { payload =>
            match (payload) {
                case Some(map) => if (map.contains("ids")) { notificationBox.lastCounter += 1 }
                case None => ()
            }
        }
    )
    let token = UiNotificationCenter.shared.subscribe(revocation.name, revocation.callback)
    let userInfo = HashMap<String, Any>()
    userInfo["ids"] = "doc-1"
    UiNotificationCenter.shared.post("gallery.probe_revocation", userInfo: userInfo)
    if (notificationBox.lastCounter == 1) {
        checks += 1
    }
    UiNotificationCenter.shared.post("gallery.probe_revocation") // no userInfo: callback sees None
    UiNotificationCenter.shared.unsubscribe(revocation.name, token)
    UiNotificationCenter.shared.post("gallery.probe_revocation", userInfo: userInfo)
    if (notificationBox.lastCounter == 1) {
        checks += 1
    }

    // components: reference every @Component type.
    let gallery: ?GalleryProbe = None
    let screen: ?ContentScreenView = None
    let pin: ?PinTextFieldView = None
    let searchable: ?SearchableList = None
    let alert: ?AlertView = None
    if (gallery.isNone() && screen.isNone() && pin.isNone() &&
        searchable.isNone() && alert.isNone()) {
        checks += 1
    }

    return checks
}

/** Listener capture box (R-101: lambdas must not capture mutable locals). */
class GalleryListenerBox {
    public var lastCounter: Int64 = -1
}
