/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-proximity
 * module (UI/Connectivity/ProximityConnectionView.swift +
 * UI/Presentation/Request|Loading|Success/Proximity*View.swift) to Cangjie ArkUI.
 *
 * Four NavDestination-rooted screens (D-002):
 *  - ProximityConnectionView: the in-person engagement screen — a spinner while
 *    the BLE engagement is prepared, the device-engagement QR code once the
 *    coordinator yields the "mdoc:" payload (ArkUI QRCode component, sized like
 *    iOS: a square of screen width / 1.5), and the BLE footer (iOS nfcFooter).
 *    Engine engagement failure surfaces the error honestly.
 *  - ProximityRequestView: wraps the shared feature-common BaseRequestView.
 *  - ProximityLoaderView: sends the prepared response, waits for responseSent.
 *  - ProximitySuccessView: the generic SuccessView.
 *
 * BLE peripheral setup starts on the UI thread because ConnectivityKit binds
 * the GATT server to the caller's application event context. The coordinator
 * moves only the blocking request wait to a background thread. @State writes
 * use spawn(UIThread).
 */
package eudi_feature_proximity

import ohos.arkui.component.*
import ohos.arkui.component.qrcode.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.collection.ArrayList
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_feature_common.{
    BaseRequestView, RequestViewModel, RequestDataCell, SuccessView, LoadingView,
    SuccessUIConfig, SuccessTitle
}

// ─── ProximityConnectionView ─────────────────────────────────────────────────

@Component
public class ProximityConnectionView {
    public var viewModel: ?ProximityConnectionViewModel = Option<ProximityConnectionViewModel>.None

    @State
    var hasQr: Bool = false
    /** Device-engagement payload rendered by the QRCode component. */
    @State
    var qrPayload: String = ""
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""

    private var vm: ?ProximityConnectionViewModel = Option<ProximityConnectionViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultProximityConnectionViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.hasQr = state.hasQr
                this.qrPayload = state.qrPayload
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
            }
        })
        // aboutToAppear already runs on ArkUI's UI thread. Keep GATT server
        // creation/service registration here; the coordinator asynchronously
        // waits for the reader after the radio has been prepared.
        model.initialize()
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onCancel(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.onCancel() }
            case None => ()
        }
    }

    private func onDismissError(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.dismissError() }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            if (this.hasError) {
                ContentErrorView(
                    config: ContentErrorConfig(
                        description: LocalizableStringKey.custom(this.errorMessage),
                        cancelAction: { => this.onDismissError() }
                    )
                )
            } else {
                this.connectionContent()
            }
        }
        .hideTitleBar(true)
    }

    @Builder
    private func connectionContent() {
        Column {
            Stack(alignContent: Alignment.Center) {
                Text(LocalizableManager.get(LocalizableStringKey.scannerQrTitlePresentation))
                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                    .fontWeight(FontWeight.Medium)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Center)
                Row {
                    Row {
                        Text("‹")
                            .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .textAlign(TextAlign.Center)
                    }
                    .width(40.0)
                    .height(40.0)
                    .justifyContent(FlexAlign.Center)
                    .borderRadius(20.0)
                    .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                    .onClick({ _ => this.onCancel() })
                    Blank()
                }
                .width(100.percent)
            }
            .width(100.percent)
            .height(44.0)

            Text(LocalizableManager.get(LocalizableStringKey.proximityConnectivityCaption))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Start)
                .width(100.percent)

            Column(space: SPACING_MEDIUM) {
                if (this.hasQr) {
                    // Engagement ready: render the "mdoc:" device-engagement
                    // payload as a QR code (iOS: Image(uiImage: qrImage) in a
                    // square of screen width / 1.5).
                    QRCode(this.qrPayload)
                        .color(uiColor(ThemeManager.shared.color.primaryLabel))
                        .backgroundColor(uiColor(ThemeManager.shared.color.background))
                        .width(67.percent)
                        .aspectRatio(1.0)
                } else {
                    ContentLoaderView(showLoader: true)
                }
            }
            .width(100.percent)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Divider()
                .color(uiColor(ThemeManager.shared.color.separator))

            // iOS nfcFooter — BLE asset and engagement description.
            Column(space: SPACING_SMALL) {
                AppIcon(token: ThemeManager.shared.image.ble, size: 36.0)
                Text(LocalizableManager.get(LocalizableStringKey.proximityConnectionBleDescription))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Center)
            }
            .width(100.percent)
            .alignItems(HorizontalAlign.Center)
        }
        .width(100.percent)
        .height(100.percent)
        .padding(top: SPACING_LARGE_MEDIUM, right: ThemeManager.shared.dimension.padding,
            bottom: ThemeManager.shared.dimension.padding, left: ThemeManager.shared.dimension.padding)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }
}

// ─── ProximityRequestView ────────────────────────────────────────────────────

@Component
public class ProximityRequestView {
    public var viewModel: ?ProximityRequestViewModel = Option<ProximityRequestViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""

    private var vm: ?ProximityRequestViewModel = Option<ProximityRequestViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultProximityRequestViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.isLoading = state.isLoading
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
            }
        })
        spawn { => model.doWork() }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onConfirm(selected: Array<RequestDataCell>): Unit {
        match (this.vm) {
            case Some(model) =>
                let list = ArrayList<RequestDataCell>()
                for (c in selected) { list.add(c) }
                spawn { => model.onShare(list) }
            case None => ()
        }
    }

    private func onCancel(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.onCancel() }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            if (this.hasError) {
                ContentErrorView(
                    config: ContentErrorConfig(
                        description: LocalizableStringKey.custom(this.errorMessage),
                        cancelAction: { => this.onCancel() }
                    )
                )
            } else if (this.isLoading) {
                LoadingView(
                    title: LocalizableStringKey.dataSharingRequest,
                    isCancellable: true,
                    onCancel: { => this.onCancel() }
                )
            } else {
                this.requestContent()
            }
        }
        .hideTitleBar(true)
    }

    @Builder
    private func requestContent() {
        Column {
            BaseRequestView(
                viewModel: this.requestModelOf(),
                onConfirm: { selected => this.onConfirm(selected) },
                onCancel: { => this.onCancel() }
            )
        }
        .width(100.percent)
        .height(100.percent)
    }

    private func requestModelOf(): ?RequestViewModel {
        match (this.vm) {
            case Some(model) => Some(model.requestModel)
            case None => None
        }
    }
}

// ─── ProximityLoaderView ─────────────────────────────────────────────────────

@Component
public class ProximityLoaderView {
    public var viewModel: ?ProximityLoaderViewModel = Option<ProximityLoaderViewModel>.None

    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""

    private var vm: ?ProximityLoaderViewModel = Option<ProximityLoaderViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultProximityLoaderViewModel()
        this.vm = Some(model)
        model.onStateChange({ state =>
            spawn(UIThread) {
                =>
                this.hasError = state.hasError
                this.errorMessage = state.errorMessage
            }
        })
        spawn { => model.doWork() }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onCancel(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.onCancel() }
            case None => ()
        }
    }

    private func onDismissError(): Unit {
        match (this.vm) {
            case Some(model) => spawn { => model.dismissError() }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            if (this.hasError) {
                ContentErrorView(
                    config: ContentErrorConfig(
                        description: LocalizableStringKey.custom(this.errorMessage),
                        cancelAction: { => this.onDismissError() }
                    )
                )
            } else {
                // iOS BaseLoadingView: wallet mark + "Please wait" header,
                // centred loader, with the flow cancellation affordance.
                Column {
                    Row {
                        Row {
                            Text("‹")
                                .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .textAlign(TextAlign.Center)
                        }
                        .width(40.0)
                        .height(40.0)
                        .justifyContent(FlexAlign.Center)
                        .borderRadius(20.0)
                        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                        .onClick({ _ => this.onCancel() })
                        Blank()
                    }
                    .width(100.percent)
                    .height(44.0)

                    ContentHeaderView(config: ContentHeaderConfig(
                        appIconAndTextData: AppIconAndTextData(
                            appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                            appTextSrc: ""
                        ),
                        description: Some(LocalizableStringKey.pleaseWait)
                    ))
                    Blank()
                    ContentLoaderView(showLoader: true)
                    Blank()
                }
                .width(100.percent)
                .height(100.percent)
                .padding(ThemeManager.shared.dimension.padding)
                .backgroundColor(uiColor(ThemeManager.shared.color.background))
            }
        }
        .hideTitleBar(true)
    }
}

// ─── ProximitySuccessView ────────────────────────────────────────────────────

@Component
public class ProximitySuccessView {
    public var viewModel: ?ProximitySuccessViewModel = Option<ProximitySuccessViewModel>.None

    private var vm: ?ProximitySuccessViewModel = Option<ProximitySuccessViewModel>.None

    protected override func aboutToAppear(): Unit {
        this.vm = this.viewModel
    }

    public func build() {
        NavDestination() {
            Column {
                SuccessView(
                    config: this.successConfig(),
                    router: this.routerOf(),
                    useNavArgs: false
                )
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
    }

    private func successConfig(): SuccessUIConfig {
        match (this.vm) {
            case Some(model) => model.viewState.config
            case None => defaultProximitySuccessConfig()
        }
    }

    private func routerOf(): ?RouterHost {
        match (this.vm) {
            case Some(model) => Some(model.router)
            case None => None
        }
    }
}

// ─── standalone-render fallbacks ──────────────────────────────────────────────

func defaultProximitySuccessConfig(): SuccessUIConfig {
    SuccessUIConfig(
        title: SuccessTitle(value: LocalizableStringKey.success),
        subtitle: LocalizableStringKey.dataShared
    )
}

func makeDefaultProximityConnectionViewModel(): ProximityConnectionViewModel {
    ProximityConnectionViewModel(router: InMemoryRouterHost(), interactor: NoopProximityInteractor())
}

func makeDefaultProximityRequestViewModel(): ProximityRequestViewModel {
    ProximityRequestViewModel(router: InMemoryRouterHost(), interactor: NoopProximityInteractor())
}

func makeDefaultProximityLoaderViewModel(): ProximityLoaderViewModel {
    ProximityLoaderViewModel(router: InMemoryRouterHost(), interactor: NoopProximityInteractor())
}
