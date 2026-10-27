/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/Issuance/IssuanceOptionView.swift + IssuanceOptionViewModel.swift)
 * to Cangjie.
 *
 * The "Add document" option screen offers two ways to add a credential, mirroring
 * iOS exactly:
 *   - Choose from list → push the extra-document issuance flow
 *     (AppRoutes.issuanceAddDocument with IssuanceFlow.ExtraDocument(None))
 *   - Scan QR code      → push the issuing QR scanner
 *     (AppRoutes.qrScanner with ScannerFlow.FlowIssuing(success→dashboard,
 *      cancel→issuanceOption))
 * Route payloads travel through NavArgs as RouteConfigArgs (same channel the
 * app-shell destinations consume). NavDestination root (D-002), route key
 * AppRoutes.issuanceOption.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, ToolBarContent, ToolBarAction,
    NavArgs, RouteConfigArgs, TwoWayNavigationType, ThreeWayNavigationType,
    uiColor, uiFontSize,
    SPACING_SMALL, SPACING_MEDIUM, SPACING_MEDIUM_SMALL, SPACING_LARGE_MEDIUM, appImageSrc
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_feature_common.{ScannerUiConfig, ScannerFlow, IssuanceFlowUiConfig, IssuanceFlow}

/** Mirrors Swift `IssuanceOptionViewState` (delivered fields). */
public class IssuanceOptionViewState <: ViewState {
    public let title: LocalizableStringKey

    public init(title!: LocalizableStringKey = LocalizableStringKey.addDocumentsToWallet) {
        this.title = title
    }
}

/** Mirrors Swift `IssuanceOptionViewModel<Router>`. */
public class IssuanceOptionViewModel <: BaseViewModel<IssuanceOptionViewState> {
    public init(router!: RouterHost) {
        super(router, IssuanceOptionViewState())
    }

    public func toolbarContent(): ToolBarContent {
        ToolBarContent(
            leadingActions: [
                ToolBarAction(
                    iconSrc: ThemeManager.shared.image.chevronLeft,
                    callback: { => this.router.pop() }
                )
            ]
        )
    }

    /** Mirrors iOS onAddDocumentClick(): push the extra-document issuance flow. */
    public func onAddDocumentClick(): Unit {
        let config = IssuanceFlowUiConfig(flow: IssuanceFlow.ExtraDocument(Option<String>.None))
        NavArgs.shared.set(AppRoutes.issuanceAddDocument, RouteConfigArgs(config))
        this.router.push(AppRoutes.issuanceAddDocument)
    }

    /** Mirrors iOS onScanClick(): push the issuing QR scanner. */
    public func onScanClick(): Unit {
        let config = ScannerUiConfig(
            flow: ScannerFlow.FlowIssuing(
                TwoWayNavigationType.NavPopTo(AppRoutes.dashboard),
                ThreeWayNavigationType.ThreeWayPopTo(AppRoutes.issuanceOption)
            )
        )
        NavArgs.shared.set(AppRoutes.qrScanner, RouteConfigArgs(config))
        this.router.push(AppRoutes.qrScanner)
    }
}

/** Issuance-option screen. NavDestination root (D-002), route AppRoutes.issuanceOption. */
@Component
public class IssuanceOptionView {
    public var viewModel: ?IssuanceOptionViewModel = Option<IssuanceOptionViewModel>.None

    private var vm: ?IssuanceOptionViewModel = Option<IssuanceOptionViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) => this.vm = Some(model)
            case None => ()
        }
    }

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    private func onAddDocument(): Unit {
        match (this.vm) {
            case Some(model) => model.onAddDocumentClick()
            case None => ()
        }
    }

    private func onScan(): Unit {
        match (this.vm) {
            case Some(model) => model.onScanClick()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                Scroll {
                    Column(space: SPACING_LARGE_MEDIUM) {
                        Text(LocalizableManager.get(LocalizableStringKey.addDocumentsToWallet))
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                            .textAlign(TextAlign.Start)

                        Column(space: SPACING_MEDIUM_SMALL) {
                            Row(space: SPACING_MEDIUM) {
                                Image(appImageSrc(ThemeManager.shared.image.chooseDocumentImage))
                                    .width(40.0)
                                    .height(40.0)
                                    .objectFit(ImageFit.Contain)
                                Text(LocalizableManager.get(LocalizableStringKey.chooseFromList))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .layoutWeight(1)
                                    .textAlign(TextAlign.Start)
                                Image(appImageSrc(ThemeManager.shared.image.chevronRight))
                                    .width(18.0)
                                    .height(18.0)
                                    .objectFit(ImageFit.Contain)
                                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                            .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                            .borderRadius(18.0)
                            .onClick({ _ => this.onAddDocument() })

                            Row(space: SPACING_MEDIUM) {
                                Image(appImageSrc(ThemeManager.shared.image.scanDocumentImage))
                                    .width(40.0)
                                    .height(40.0)
                                    .objectFit(ImageFit.Contain)
                                Text(LocalizableManager.get(LocalizableStringKey.scanQrCode))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .layoutWeight(1)
                                    .textAlign(TextAlign.Start)
                                Image(appImageSrc(ThemeManager.shared.image.chevronRight))
                                    .width(18.0)
                                    .height(18.0)
                                    .objectFit(ImageFit.Contain)
                                    .fillColor(uiColor(ThemeManager.shared.color.accent))
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                            .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                            .borderRadius(18.0)
                            .onClick({ _ => this.onScan() })
                        }
                        .width(100.percent)
                    }
                    .width(100.percent)
                    .padding(SPACING_MEDIUM)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    @Builder
    private func toolbar() {
        Row(space: SPACING_SMALL) {
            Text("‹")
                .fontSize(28.0)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .onClick({ _ => this.onBack() })
            Text(LocalizableManager.get(LocalizableStringKey.addDocumentTitle))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .maxLines(1)
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
    }
}
