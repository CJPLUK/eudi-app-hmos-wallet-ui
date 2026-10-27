/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-assembly module
 * (Sources/Router/RouterHostImpl.swift — resolveView / RouterContainerView) to Cangjie
 * ArkUI for the EUDI HarmonyOS wallet.
 *
 * pageMap is the ArkUI equivalent of iOS resolveView(_ route: AppRoute) -> some View.
 * It is a top-level @Builder function (D-001: must not be a class member) with the
 * canonical signature (D-003): func pageMap(name: String, detailParam: Any).
 *
 * The function routes to feature sub-pages wrapped in NavDestination (D-002). M0 covers:
 *   startup   → StartupView  (root page, rendered directly inside Navigation{})
 *   quick_pin → QuickPinView (NavDestination)
 *   biometry  → BiometryView (NavDestination)
 * Unrecognised routes fall through to a minimal FallbackDestination (D-005 else guard).
 *
 * Each leaf view is a plain @Component (no @Entry). The NavDestination wrapper is the
 * correct root per D-002; ArkUI provides the back-gesture automatically.
 *
 * AppComposition (app_composition.cj) provides the pre-wired ViewModels accessed here
 * via the singleton AppComposition.shared.
 */
package ohos_app_cangjie_entry

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import ohos.hilog.*
import std.collection.{HashMap, ArrayList}
import eudi_logic_ui.*
import eudi_logic_core.{NotificationCenter, NotificationName}
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}
import eudi_feature_startup.{StartupView, StartupViewModel}
import eudi_feature_common.{QuickPinView, QuickPinUiConfig, QuickPinFlow, BiometryView, BiometricUiConfig, SuccessView, IssuanceFlow, IssuanceFlowUiConfig, IssuanceCodeUiConfig, QRScanView, ScannerUiConfig, ScannerFlow, DocumentSuccessUIConfig}
import eudi_feature_dashboard.{
    DashboardView, DocumentDetailsView, TransactionDetailsView, DashboardNavArgs,
    SettingsView, SideMenuView, SignDocumentView, IssuanceOptionView
}
import eudi_feature_rqes.{
    RqesRoutes, rqesResume, ServiceSelectionView, DocumentSelectionView,
    CredentialSelectionView, SignedDocumentView, DocumentViewerView
}
import eudi_feature_issuance.{
    AddDocumentView, DocumentOfferView, DocumentOfferViewModel, OfferCodeView,
    DocumentIssuanceSuccessView, DocumentIssuanceSuccessUIConfig, IssuedDocumentSummary
}
import eudi_feature_presentation.{PresentationRequestView, PresentationLoaderView, PresentationSuccessView}
import eudi_feature_proximity.{ProximityConnectionView, ProximityRequestView, ProximityLoaderView, ProximitySuccessView}

// ─── Top-level pageMap (D-001 / D-003) ────────────────────────────────────────

/**
 * Route dispatcher — top-level @Builder, canonical signature.
 * Mirrors iOS RouterHostImpl.resolveView(_ route: AppRoute).
 * Each branch wraps the feature view in a NavDestination (D-002).
 */
@Builder
public func pageMap(name: String, detailParam: Any) {
    if (name == AppRoutes.quickPin) {
        QuickPinDestination()
    } else if (name == AppRoutes.biometry) {
        BiometryDestination()
    } else if (name == AppRoutes.genericSuccess) {
        GenericSuccessDestination()
    } else if (name == AppRoutes.dashboard) {
        DashboardDestination()
    } else if (name == AppRoutes.documentDetails) {
        DocumentDetailsDestination()
    } else if (name == AppRoutes.transactionDetails) {
        TransactionDetailsDestination()
    } else if (name == AppRoutes.settingsMenu) {
        SettingsDestination()
    } else if (name == AppRoutes.sideMenu) {
        SideMenuDestination()
    } else if (name == AppRoutes.signDocument) {
        SignDocumentDestination()
    } else if (name == RqesRoutes.documentSelection) {
        RqesDocumentSelectionDestination()
    } else if (name == RqesRoutes.serviceSelection) {
        RqesServiceSelectionDestination()
    } else if (name == RqesRoutes.credentialSelection) {
        RqesCredentialSelectionDestination()
    } else if (name == RqesRoutes.signedDocument) {
        RqesSignedDocumentDestination()
    } else if (name == RqesRoutes.documentViewer) {
        RqesDocumentViewerDestination()
    } else if (name == AppRoutes.issuanceOption) {
        IssuanceOptionDestination()
    } else if (name == AppRoutes.addDocumentOptions) {
        AddDocumentOptionsDestination()
    } else if (name == AppRoutes.issuanceAddDocument) {
        IssuanceAddDocumentDestination()
    } else if (name == AppRoutes.credentialOfferRequest) {
        CredentialOfferDestination()
    } else if (name == AppRoutes.issuanceCode) {
        IssuanceCodeDestination()
    } else if (name == AppRoutes.issuanceSuccess) {
        IssuanceSuccessDestination()
    } else if (name == AppRoutes.qrScanner) {
        QrScannerDestination()
    } else if (name == AppRoutes.presentationRequest) {
        PresentationRequestDestination()
    } else if (name == AppRoutes.presentationLoader) {
        PresentationLoaderDestination()
    } else if (name == AppRoutes.presentationSuccess) {
        PresentationSuccessDestination()
    } else if (name == AppRoutes.proximityConnection) {
        ProximityConnectionDestination()
    } else if (name == AppRoutes.proximityRequest) {
        ProximityRequestDestination()
    } else if (name == AppRoutes.proximityLoader) {
        ProximityLoaderDestination()
    } else if (name == AppRoutes.proximitySuccess) {
        ProximitySuccessDestination()
    } else {
        FallbackDestination(routeName: name)
    }
}

// ─── QuickPin destination ──────────────────────────────────────────────────────

/**
 * NavDestination wrapper for QuickPinView (fc_common_quickpin).
 * Config is read from NavArgs using the route key (mirrors iOS via RouteConfigArgs).
 */
@Component
class QuickPinDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: QuickPinUiConfig = QuickPinUiConfig(flow: QuickPinFlow.SetWithoutActivation)

    private func resolveConfig(): QuickPinUiConfig {
        match (NavArgs.shared.take(AppRoutes.quickPin)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as QuickPinUiConfig) {
                            case Some(cfg) => cfg
                            case None => QuickPinUiConfig(flow: QuickPinFlow.SetWithoutActivation)
                        }
                    case None => QuickPinUiConfig(flow: QuickPinFlow.SetWithoutActivation)
                }
            case None => QuickPinUiConfig(flow: QuickPinFlow.SetWithoutActivation)
        }
    }

    protected override func aboutToAppear(): Unit {
        this.config = this.resolveConfig()
    }

    public func build() {
        NavDestination() {
            Column {
                QuickPinView(
                    config: this.config,
                    viewModel: Some(AppComposition.shared.quickPinViewModel(config: this.config))
                )
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
        // Auth gate: consume the system Back so it cannot unwind to the splash
        // root (which is a dead-end and froze the UI).
        .onBackPressed({ => true })
    }
}

// ─── Biometry destination ──────────────────────────────────────────────────────

/**
 * NavDestination wrapper for BiometryView (fc_common_biometry).
 * Config is read from NavArgs using the route key.
 */
@Component
class BiometryDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: BiometricUiConfig = BiometricUiConfig(
        navigationTitle: LocalizableStringKey.biometryConfirmRequest,
        caption: LocalizableStringKey.loginCaption,
        quickPinOnlyCaption: LocalizableStringKey.loginCaptionQuickPinOnly,
        navigationSuccessType: ThreeWayNavigationType.ThreeWayPop,
        navigationBackType: Option<ThreeWayNavigationType>.None,
        isPreAuthorization: true,
        shouldInitializeBiometricOnCreate: true
    )

    private func resolveConfig(): BiometricUiConfig {
        match (NavArgs.shared.take(AppRoutes.biometry)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as BiometricUiConfig) {
                            case Some(cfg) => cfg
                            case None => this.config
                        }
                    case None => this.config
                }
            case None => this.config
        }
    }

    protected override func aboutToAppear(): Unit {
        this.config = this.resolveConfig()
    }

    public func build() {
        NavDestination() {
            Column {
                BiometryView(
                    config: this.config,
                    viewModel: Some(AppComposition.shared.biometryViewModel(config: this.config))
                )
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
        // Auth gate: consume the system Back so it cannot unwind to the splash
        // root (a dead-end that froze the UI).
        .onBackPressed({ => true })
    }
}

// ─── GenericSuccess destination ────────────────────────────────────────────────

/**
 * NavDestination wrapper for SuccessView (fc_common_shared_screens).
 * Config is read from NavArgs via useNavArgs=true (SuccessView.aboutToAppear
 * reads NavArgs.shared.take(AppRoutes.genericSuccess) internally).
 * Router is captured as RouterHost in aboutToAppear() to satisfy the
 * Option<RouterHost> parameter (Option<ProdRouterHost> is not covariant).
 */
@Component
class GenericSuccessDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var successRouter: ?RouterHost = Option<RouterHost>.None

    protected override func aboutToAppear(): Unit {
        let rh: RouterHost = AppComposition.shared.router
        this.successRouter = Some(rh)
    }

    public func build() {
        NavDestination() {
            Column {
                SuccessView(
                    router: this.successRouter,
                    useNavArgs: true
                )
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
    }
}

// ─── Deep-link router ────────────────────────────────────────────────────────

/**
 * Holds a URI delivered via a registered deep-link scheme (EntryAbility
 * want.uri → index.cj handleDeepLink). The URI cannot be routed until the user
 * is past the PIN/biometry gate, so it is stashed here and consumed when the
 * authenticated Dashboard becomes current (ProdRouterHost push/popTo hooks).
 *
 * Mirrors iOS DeepLinkController.handleDeepLinkAction:
 *   - haip-vci:// / openid-credential-offer://  → credentialOfferRequest
 *     (success: popTo dashboard when documents exist, else push dashboard;
 *      cancel: pop — DeepLinkController.swift case .credential_offer/.haip_vci)
 *   - eudi-openid4vp:// family → presentationRequest (same as in-app QR path)
 */
public class DeepLinkRouter {
    private static var pending: ?String = None

    public static func set(uri: String): Unit {
        // In-app WebView auth-code callbacks (eu.europa.ec.euidi:// /
        // eudi-openid4ci://) are resumed by AddDocument/Offer interceptors.
        // If the system also delivers them as a Want, do NOT stash them —
        // consume() would mis-route them to presentation and corrupt the stack.
        if (uri.startsWith("eu.europa.ec.euidi:") || uri.startsWith("eudi-openid4ci:")) {
            Hilog.info(0, "VCI-DEBUG", "DeepLinkRouter ignoring issuance auth callback")
            return
        }
        pending = Some(uri)
    }

    public static func consume(): Unit {
        match (pending) {
            case Some(uri) =>
                pending = None
                if (uri.startsWith("haip-vci:") || uri.startsWith("openid-credential-offer:")) {
                    routeToOffer(uri)
                } else if (uri.startsWith("eu.europa.ec.euidi:") || uri.startsWith("eudi-openid4ci:")) {
                    Hilog.info(0, "VCI-DEBUG", "DeepLinkRouter consume skipped issuance auth callback")
                } else if (uri.startsWith("rqes:")) {
                    routeToRqes(uri)
                } else {
                    routeToPresentation(uri)
                }
            case None => ()
        }
    }

    private static func routeToOffer(uri: String): Unit {
        // A new offer arriving while an offer page is already up reloads it in
        // place via CredentialOfferNew (iOS DeepLinkController posts
        // NSNotification.CredentialOffer). A pop+push here ran two transitions
        // and flashed the old page's (error) state between them.
        if (AppComposition.shared.router.isScreenForeground(AppRoutes.credentialOfferRequest)) {
            let m = HashMap<String, String>()
            m["uri"] = uri
            NotificationCenter.postMap(NotificationName.CredentialOfferNew, m)
            return
        }
        let args = HashMap<String, String>()
        args["uri"] = uri
        let successNav = if (AppComposition.shared.router.userIsLoggedInWithDocuments()) {
            TwoWayNavigationType.NavPopTo(AppRoutes.dashboard)
        } else {
            TwoWayNavigationType.NavPush(AppRoutes.dashboard)
        }
        let config = UIConfigGeneric(
            arguments: args,
            navigationSuccessType: successNav,
            navigationCancelType: ThreeWayNavigationType.ThreeWayPop
        )
        NavArgs.shared.set(AppRoutes.credentialOfferRequest, RouteConfigArgs(config))
        AppComposition.shared.router.push(AppRoutes.credentialOfferRequest)
    }

    // rqes://oauth/callback?code=XYZ → resume the signing flow (iOS DeepLinkController RqesResume).
    // Advances the EudiRQESUi state with the code and pushes the route for the new state. A rqes
    // URL with no code is a no-op (iOS RqesNoCode early-returns).
    private static func routeToRqes(uri: String): Unit {
        match (extractQueryParam(uri, "code")) {
            case Some(code) => rqesResume(code, AppComposition.shared.router)
            case None => Hilog.info(0, "VCI-DEBUG", "rqes deep link without code — ignored")
        }
    }

    // Reads the first value of `key` from a URL query string (…?a=1&key=VALUE&b=2).
    private static func extractQueryParam(uri: String, key: String): ?String {
        let marker = key + "="
        let qIdx = uri.indexOf("?")
        let query = match (qIdx) {
            case Some(i) => uri[i + 1..uri.size]
            case None => uri
        }
        for (pair in query.split("&")) {
            if (pair.startsWith(marker)) {
                return Some(pair[marker.size..pair.size])
            }
        }
        return None
    }

    private static func routeToPresentation(uri: String): Unit {
        let args = HashMap<String, String>()
        args["uri"] = uri
        let config = UIConfigGeneric(
            arguments: args,
            navigationSuccessType: TwoWayNavigationType.NavPush(AppRoutes.presentationRequest),
            navigationCancelType: ThreeWayNavigationType.ThreeWayPop
        )
        NavArgs.shared.set(AppRoutes.presentationRequest, RouteConfigArgs(config))
        AppComposition.shared.router.push(AppRoutes.presentationRequest)
    }
}

// ─── Dashboard destination ─────────────────────────────────────────────────────

/**
 * Thin wrapper for DashboardView. DashboardView already owns its NavDestination
 * root (D-002: NavDestination must be the build() root for destination pages).
 * Do NOT add another NavDestination here — that would create a double-wrapping.
 * The composition root supplies a fresh DashboardViewModel with the production
 * RouterHost so the VM can push further routes (issuance / presentation).
 */
@Component
class DashboardDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        DashboardView(viewModel: Some(AppComposition.shared.dashboardViewModel()))
    }
}

// ─── Dashboard: Document Details destination ────────────────────────────────────

/**
 * Thin wrapper for DocumentDetailsView (the view owns its NavDestination root,
 * D-002). The selected document id is handed off via DashboardNavArgs.shared
 * (set by DashboardViewModel.onDocumentDetails before the push), mirroring the
 * NavArgs hand-off used by the issuance destinations.
 */
@Component
class DocumentDetailsDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var documentId: String = ""

    protected override func aboutToAppear(): Unit {
        this.documentId = DashboardNavArgs.shared.documentId
    }

    public func build() {
        DocumentDetailsView(
            viewModel: Some(AppComposition.shared.documentDetailsViewModel(documentId: this.documentId))
        )
    }
}

// ─── Dashboard: Transaction Details destination ─────────────────────────────────

/** Thin wrapper for TransactionDetailsView (view owns NavDestination root). */
@Component
class TransactionDetailsDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var transactionId: String = ""

    protected override func aboutToAppear(): Unit {
        this.transactionId = DashboardNavArgs.shared.transactionId
    }

    public func build() {
        TransactionDetailsView(
            viewModel: Some(AppComposition.shared.transactionDetailsViewModel(transactionId: this.transactionId))
        )
    }
}

// ─── Dashboard: Settings destination ────────────────────────────────────────

/** Thin wrapper for SettingsView (view owns its NavDestination root, D-002). */
@Component
class SettingsDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        SettingsView(viewModel: Some(AppComposition.shared.settingsViewModel()))
    }
}

// ─── Dashboard: Side Menu destination ───────────────────────────────────────

/** Thin wrapper for SideMenuView (view owns its NavDestination root, D-002). */
@Component
class SideMenuDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        SideMenuView(viewModel: Some(AppComposition.shared.sideMenuViewModel()))
    }
}

// ─── Dashboard: Sign Document destination ───────────────────────────────────

/**
 * Thin wrapper for SignDocumentView (view owns its NavDestination root, D-002).
 * This is the destination the Home tab "Sign document" card pushes
 * (AppRoutes.signDocument); it previously fell through to FallbackDestination.
 */
@Component
class SignDocumentDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        SignDocumentView(viewModel: Some(AppComposition.shared.signDocumentViewModel()))
    }
}

// ── RQES signing flow destinations (eudi_feature_rqes). Each view owns its NavDestination root. ──
@Component
class RqesDocumentSelectionDestination {
    @Consume var appStack: NavPathStack
    public func build() {
        DocumentSelectionView(viewModel: Some(AppComposition.shared.rqesDocumentSelectionViewModel()))
    }
}
@Component
class RqesServiceSelectionDestination {
    @Consume var appStack: NavPathStack
    public func build() {
        ServiceSelectionView(viewModel: Some(AppComposition.shared.rqesServiceSelectionViewModel()))
    }
}
@Component
class RqesCredentialSelectionDestination {
    @Consume var appStack: NavPathStack
    public func build() {
        CredentialSelectionView(viewModel: Some(AppComposition.shared.rqesCredentialSelectionViewModel()))
    }
}
@Component
class RqesSignedDocumentDestination {
    @Consume var appStack: NavPathStack
    public func build() {
        SignedDocumentView(viewModel: Some(AppComposition.shared.rqesSignedDocumentViewModel()))
    }
}
@Component
class RqesDocumentViewerDestination {
    @Consume var appStack: NavPathStack
    public func build() {
        DocumentViewerView(viewModel: Some(AppComposition.shared.rqesDocumentViewerViewModel()))
    }
}

// ─── Dashboard: Issuance Option destination ─────────────────────────────────

/** Thin wrapper for IssuanceOptionView (view owns its NavDestination root, D-002). */
@Component
class IssuanceOptionDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        IssuanceOptionView(viewModel: Some(AppComposition.shared.issuanceOptionViewModel()))
    }
}

// ─── Issuance: Add Document chooser (Choose from list / Scan QR) ────────────────

/**
 * iOS "Add document" chooser shown when Documents "+" is tapped: a centered title
 * + subtitle and two large cards (Choose from list / Scan QR). "Choose from list"
 * carries the ExtraDocument flow into the issuer catalog; "Scan QR" opens the
 * scanner. Mirrors iOS AddDocumentView's selection screen (PX-09).
 */
@Component
class AddDocumentOptionsDestination {
    private func onChooseList(): Unit {
        let config = IssuanceFlowUiConfig(flow: IssuanceFlow.ExtraDocument(Option<String>.None))
        NavArgs.shared.set(AppRoutes.issuanceAddDocument, RouteConfigArgs(config))
        AppComposition.shared.router.push(AppRoutes.issuanceAddDocument)
    }

    private func onScanQr(): Unit {
        // Issuing scan → "Scan QR" title/caption (iOS scannerQrTitleIssuing).
        let config = ScannerUiConfig(
            flow: ScannerFlow.FlowIssuing(
                TwoWayNavigationType.NavPopTo(AppRoutes.dashboard),
                ThreeWayNavigationType.ThreeWayPopTo(AppRoutes.issuanceOption)
            )
        )
        NavArgs.shared.set(AppRoutes.qrScanner, RouteConfigArgs(config))
        AppComposition.shared.router.push(AppRoutes.qrScanner)
    }

    @Builder
    private func optionCard(illustration: String, label: LocalizableStringKey, action: () -> Unit) {
        // iOS ActionCard: centered 64pt accent icon over an accent title on a
        // GROUPED-background card (light blue-gray, visible on the white page —
        // secondaryGroupedBackground is pure white and rendered the card
        // invisible), minHeight 180, corner SPACING_MEDIUM.
        Column(space: SPACING_MEDIUM) {
            Image(appImageSrc(illustration))
                .width(64.0)
                .height(64.0)
                .objectFit(ImageFit.Contain)
            Text(LocalizableManager.get(label))
                .fontSize(uiFontSize(ThemeManager.shared.font.labelLarge))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.accent))
                .textAlign(TextAlign.Center)
        }
        .width(100.percent)
        .height(180.0)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
        .borderRadius(SPACING_MEDIUM)
        .onClick({ _ => action() })
    }

    public func build() {
        NavDestination() {
            Column(space: SPACING_MEDIUM) {
                // Toolbar: circular back + centered title (mirrors other screens).
                Stack(alignContent: Alignment.Center) {
                    Text(LocalizableManager.get(LocalizableStringKey.addDocumentTitle))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontWeight(FontWeight.Bold)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    Row {
                        Row {
                            AppIcon(
                                token: ThemeManager.shared.image.chevronLeft,
                                size: 25.0,
                                color: uiColor(ThemeManager.shared.color.primaryLabel)
                            )
                        }
                        .width(40.0)
                        .height(40.0)
                        .justifyContent(FlexAlign.Center)
                        .borderRadius(20.0)
                        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                        .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
                        .onClick({ _ => AppComposition.shared.router.pop() })
                        Row {}.layoutWeight(1)
                        Row {}.width(40.0).height(40.0)
                    }
                    .width(100.percent)
                    .alignItems(VerticalAlign.Center)
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)

                // iOS: black (primaryLabel) bodyLarge copy, top-leading; 24 above
                // the card stack, cards 12 apart.
                Column(space: SPACING_LARGE_MEDIUM) {
                    Text(LocalizableManager.get(LocalizableStringKey.addDocumentsToWallet))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .width(100.percent)
                        .textAlign(TextAlign.Start)

                    Column(space: SPACING_MEDIUM_SMALL) {
                        this.optionCard(ThemeManager.shared.image.chooseDocumentImage, LocalizableStringKey.chooseFromList, { => this.onChooseList() })
                        this.optionCard(ThemeManager.shared.image.scanDocumentImage, LocalizableStringKey.scanQrCode, { => this.onScanQr() })
                    }
                    .width(100.percent)
                }
                .width(100.percent)
                .padding(right: SPACING_MEDIUM, left: SPACING_MEDIUM, top: 0.0, bottom: 0.0)
            }
            .width(100.percent)
            .height(100.percent)
            // Horizontal insets are applied per-section (toolbar + content column)
            // at SPACING_MEDIUM, so the outer column stays flush to avoid doubling.
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }
}

// ─── Issuance: Add Document destination ────────────────────────────────────────

/**
 * Thin wrapper for AddDocumentView. The view owns its NavDestination root
 * (D-002). The active issuance flow is read from NavArgs (RouteConfigArgs ->
 * IssuanceFlowUiConfig); defaults to the no-document flow (first onboarding add).
 */
@Component
class IssuanceAddDocumentDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var flow: IssuanceFlow = IssuanceFlow.NoDocument

    private func resolveFlow(): IssuanceFlow {
        match (NavArgs.shared.take(AppRoutes.issuanceAddDocument)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as IssuanceFlowUiConfig) {
                            case Some(cfg) => cfg.flow
                            case None => IssuanceFlow.NoDocument
                        }
                    case None => IssuanceFlow.NoDocument
                }
            case None => IssuanceFlow.NoDocument
        }
    }

    protected override func aboutToAppear(): Unit {
        this.flow = this.resolveFlow()
    }

    public func build() {
        AddDocumentView(viewModel: Some(AppComposition.shared.addDocumentViewModel(flow: this.flow)))
    }
}

// ─── Issuance: Credential Offer destination ────────────────────────────────────

/**
 * Thin wrapper for DocumentOfferView. The offer URI travels via NavArgs
 * (UIConfigGeneric arguments["uri"]).
 */
@Component
class CredentialOfferDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var offerUri: String = ""

    private func resolveUri(): String {
        match (NavArgs.shared.take(AppRoutes.credentialOfferRequest)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as UIConfigGeneric) {
                            case Some(cfg) =>
                                if (cfg.arguments.contains("uri")) {
                                    cfg.arguments["uri"]
                                } else {
                                    ""
                                }
                            case None => ""
                        }
                    case None => ""
                }
            case None => ""
        }
    }

    // Cache the VM across rebuilds: build() runs more than once (parent state
    // changes re-execute it), and constructing a FRESH VM/interactor pair each
    // time let a later rebuild hand the view an instance whose initialize never
    // ran — its empty resolved-offer list then made "Issue" fail with
    // "Unable to issue and store the document".
    private var cachedVm: ?DocumentOfferViewModel = None

    protected override func aboutToAppear(): Unit {
        this.offerUri = this.resolveUri()
        this.cachedVm = Some(AppComposition.shared.documentOfferViewModel(offerUri: this.offerUri))
    }

    public func build() {
        DocumentOfferView(viewModel: this.cachedVm)
    }
}

// ─── Issuance: Transaction Code destination ────────────────────────────────────

/** Thin wrapper for OfferCodeView. Config (offer uri / issuer / tx-code len)
 *  travels via NavArgs (RouteConfigArgs -> IssuanceCodeUiConfig). */
@Component
class IssuanceCodeDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: IssuanceCodeUiConfig = IssuanceCodeUiConfig(
        offerUri: "",
        issuerName: "",
        txCodeLength: 6,
        successNavigation: TwoWayNavigationType.NavPush(AppRoutes.dashboard),
        navigationCancelType: ThreeWayNavigationType.ThreeWayPop
    )

    private func resolveConfig(): IssuanceCodeUiConfig {
        match (NavArgs.shared.take(AppRoutes.issuanceCode)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as IssuanceCodeUiConfig) {
                            case Some(cfg) => cfg
                            case None => this.config
                        }
                    case None => this.config
                }
            case None => this.config
        }
    }

    protected override func aboutToAppear(): Unit {
        this.config = this.resolveConfig()
    }

    public func build() {
        OfferCodeView(viewModel: Some(AppComposition.shared.offerCodeViewModel(config: this.config)))
    }
}

// ─── Issuance success destination (document-details-style success) ──────────────

/**
 * Thin wrapper for DocumentIssuanceSuccessView. The DocumentIssuanceSuccessUIConfig
 * (issuer header + issued documents + Done navigation) travels via NavArgs under
 * AppRoutes.issuanceSuccess. The view owns its NavDestination root (D-002).
 */
@Component
class IssuanceSuccessDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: DocumentIssuanceSuccessUIConfig = DocumentIssuanceSuccessUIConfig(
        relyingParty: "",
        issuerLogoUrl: "",
        documents: ArrayList<IssuedDocumentSummary>(),
        successNavigation: DeepLinkNavigationType.DeepLinkPush(AppRoutes.dashboard)
    )

    private func resolveConfig(): DocumentIssuanceSuccessUIConfig {
        match (NavArgs.shared.take(AppRoutes.issuanceSuccess)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as DocumentIssuanceSuccessUIConfig) {
                            case Some(cfg) => cfg
                            case None => this.config
                        }
                    case None => this.config
                }
            case None => this.config
        }
    }

    protected override func aboutToAppear(): Unit {
        this.config = this.resolveConfig()
    }

    public func build() {
        DocumentIssuanceSuccessView(
            viewModel: Some(AppComposition.shared.documentIssuanceSuccessViewModel(config: this.config))
        )
    }
}

// ─── QR Scanner destination (presentation online entry) ────────────────────────

/**
 * Thin wrapper for QRScanView (feature-common). Mirrors iOS
 * CommonRouter.qrScanner with the presentation flow: a validated scan result
 * (an OpenID4VP request URL) is stashed in NavArgs under presentationRequest and
 * drives the cross-device presentation. The view owns its own chrome; a
 * NavDestination wraps it as the destination root (D-002).
 */
@Component
class QrScannerDestination {
    @Consume
    var appStack: NavPathStack

    // Flow read from NavArgs (issuing callers set FlowIssuing → "Scan QR" title;
    // the presentation entry leaves it unset → default FlowPresentation →
    // "Authenticate my identity"). Mirrors iOS's flow-specific ScannerView title.
    @State
    var scanFlow: ScannerFlow = ScannerFlow.FlowPresentation
    /** Per-instance latch: one scan routes exactly once (see onScan). */
    var routed: Bool = false

    private func resolveFlow(): ScannerFlow {
        match (NavArgs.shared.take(AppRoutes.qrScanner)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as ScannerUiConfig) {
                            case Some(cfg) => cfg.flow
                            case None => ScannerFlow.FlowPresentation
                        }
                    case None => ScannerFlow.FlowPresentation
                }
            case None => ScannerFlow.FlowPresentation
        }
    }

    protected override func aboutToAppear(): Unit {
        this.scanFlow = this.resolveFlow()
    }

    // Mirrors iOS ScannerViewModel.onScanResultValidated: the scanned URL is
    // routed by the scanner's flow — presentation → presentationRequest,
    // issuing → credentialOfferRequest (DocumentOfferView) carrying the
    // issuance flow's success / cancel navigation.
    //
    // One scan → one route (iOS onScanResultValidated semantics). The manual-
    // input fallback can fire twice for a single entry (TextInput onSubmit +
    // button click race); stacking a second DocumentOffer page made the first
    // flash its error state during the push transition. `routed` is a per-
    // destination-instance latch — a fresh scanner push gets a fresh instance,
    // so it cannot go stale across sessions (a router back-stack query here
    // once dead-locked scanning when the mirrored stack kept a phantom entry).
    private func onScan(url: String): Unit {
        if (this.routed) {
            return
        }
        this.routed = true
        let args = HashMap<String, String>()
        args["uri"] = url
        match (this.scanFlow) {
            case FlowIssuing(successNav, cancelNav) =>
                let config = UIConfigGeneric(
                    arguments: args,
                    navigationSuccessType: successNav,
                    navigationCancelType: cancelNav
                )
                NavArgs.shared.set(AppRoutes.credentialOfferRequest, RouteConfigArgs(config))
                AppComposition.shared.router.push(AppRoutes.credentialOfferRequest)
            case FlowPresentation =>
                let config = UIConfigGeneric(
                    arguments: args,
                    navigationSuccessType: TwoWayNavigationType.NavPush(AppRoutes.presentationRequest),
                    navigationCancelType: ThreeWayNavigationType.ThreeWayPop
                )
                NavArgs.shared.set(AppRoutes.presentationRequest, RouteConfigArgs(config))
                AppComposition.shared.router.push(AppRoutes.presentationRequest)
        }
    }

    public func build() {
        NavDestination() {
            Column {
                QRScanView(
                    config: ScannerUiConfig(flow: this.scanFlow),
                    onScanResult: { url => this.onScan(url) },
                    onClose: { => AppComposition.shared.router.pop() }
                )
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }
}

// ─── Presentation: Request destination ──────────────────────────────────────────

/** Wrapper for PresentationRequestView. The OpenID4VP request URL travels via
 *  NavArgs (UIConfigGeneric arguments["uri"]); the composition root starts the
 *  cross-device presentation from it. */
@Component
class PresentationRequestDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var requestUri: String = ""

    private func resolveUri(): String {
        match (NavArgs.shared.take(AppRoutes.presentationRequest)) {
            case Some(raw) =>
                match (raw as RouteConfigArgs) {
                    case Some(args) =>
                        match (args.config as UIConfigGeneric) {
                            case Some(cfg) =>
                                if (cfg.arguments.contains("uri")) { cfg.arguments["uri"] } else { "" }
                            case None => ""
                        }
                    case None => ""
                }
            case None => ""
        }
    }

    protected override func aboutToAppear(): Unit {
        this.requestUri = this.resolveUri()
    }

    public func build() {
        PresentationRequestView(
            viewModel: Some(AppComposition.shared.presentationRequestViewModel(requestUri: this.requestUri))
        )
    }
}

// ─── Presentation: Loader destination ───────────────────────────────────────────

/** Wrapper for PresentationLoaderView, reusing the active remote coordinator. */
@Component
class PresentationLoaderDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        PresentationLoaderView(
            viewModel: Some(AppComposition.shared.presentationLoaderViewModel())
        )
    }
}

// ─── Presentation: Success destination ──────────────────────────────────────────

/** Wrapper for PresentationSuccessView. The DocumentSuccessUIConfig travels via
 *  NavArgs (set by the loader VM). */
@Component
class PresentationSuccessDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: DocumentSuccessUIConfig = defaultDocumentSuccessConfig()

    protected override func aboutToAppear(): Unit {
        this.config = resolveDocumentSuccessConfig(AppRoutes.presentationSuccess)
    }

    public func build() {
        PresentationSuccessView(
            viewModel: Some(AppComposition.shared.presentationSuccessViewModel(config: this.config))
        )
    }
}

// ─── Proximity: Connection destination ──────────────────────────────────────────

/** Wrapper for ProximityConnectionView. Starts the BLE proximity presentation
 *  (composition root) and shows the QR engagement screen. */
@Component
class ProximityConnectionDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        ProximityConnectionView(
            viewModel: Some(AppComposition.shared.proximityConnectionViewModel())
        )
    }
}

// ─── Proximity: Request destination ─────────────────────────────────────────────

/** Wrapper for ProximityRequestView, reusing the active proximity coordinator. */
@Component
class ProximityRequestDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        ProximityRequestView(
            viewModel: Some(AppComposition.shared.proximityRequestViewModel())
        )
    }
}

// ─── Proximity: Loader destination ──────────────────────────────────────────────

/** Wrapper for ProximityLoaderView, reusing the active proximity coordinator. */
@Component
class ProximityLoaderDestination {
    @Consume
    var appStack: NavPathStack

    public func build() {
        ProximityLoaderView(
            viewModel: Some(AppComposition.shared.proximityLoaderViewModel())
        )
    }
}

// ─── Proximity: Success destination ─────────────────────────────────────────────

/** Wrapper for ProximitySuccessView. The DocumentSuccessUIConfig travels via
 *  NavArgs (set by the loader VM). */
@Component
class ProximitySuccessDestination {
    @Consume
    var appStack: NavPathStack

    @State
    var config: DocumentSuccessUIConfig = defaultDocumentSuccessConfig()

    protected override func aboutToAppear(): Unit {
        this.config = resolveDocumentSuccessConfig(AppRoutes.proximitySuccess)
    }

    public func build() {
        ProximitySuccessView(
            viewModel: Some(AppComposition.shared.proximitySuccessViewModel(config: this.config))
        )
    }
}

// ─── shared success-config resolution ────────────────────────────────────────────

func defaultDocumentSuccessConfig(): DocumentSuccessUIConfig {
    DocumentSuccessUIConfig(
        successNavigation: DeepLinkNavigationType.DeepLinkPop(AppRoutes.dashboard, false),
        relyingPartyIsTrusted: false,
        isIssuingDocument: false
    )
}

func resolveDocumentSuccessConfig(routeKey: String): DocumentSuccessUIConfig {
    match (NavArgs.shared.take(routeKey)) {
        case Some(raw) =>
            match (raw as RouteConfigArgs) {
                case Some(args) =>
                    match (args.config as DocumentSuccessUIConfig) {
                        case Some(cfg) => cfg
                        case None => defaultDocumentSuccessConfig()
                    }
                case None => defaultDocumentSuccessConfig()
            }
        case None => defaultDocumentSuccessConfig()
    }
}

// ─── Fallback destination (D-005) ─────────────────────────────────────────────

/**
 * Catch-all NavDestination for unrecognised route names.
 * Prevents white-screen crashes on unknown routes (D-005 else guard).
 * Emits a HiLog warn with the unrecognised route name to aid debugging.
 */
@Component
class FallbackDestination {
    var routeName: String = ""

    protected override func aboutToAppear(): Unit {
        Hilog.warn(0x0001, "AppPageMap", "FallbackDestination: unrecognised route '%{public}s'", [this.routeName])
    }

    public func build() {
        NavDestination() {
            Stack {
                Text("...")
                    .fontSize(16.0)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }
}
