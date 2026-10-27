/*
 * service_selection_view.cj — ports eudi-lib-ios-rqes-ui ServiceSelection/ServiceSelectionView.
 * Lists the configured QTSPs; picking one + Proceed creates the RQES service and opens the
 * external browser for service authorization. NavDestination root; mirrors the repo's ArkUI
 * view idiom (sign_document_view.cj) — onStateChange → spawn(UIThread) → @State; blocking VM
 * calls via spawn{}.
 */
package eudi_feature_rqes

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.resource.*
import kit.ArkUI.*
import std.collection.ArrayList
import eudi_logic_ui.{
    uiColor, uiFontSize, SPACING_MEDIUM, SPACING_EXTRA_LARGE,
    ContentErrorView, ContentErrorConfig, ContentLoaderView,
    ListDividerView
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import ohos_app_cangjie_eudi_cjrqes_ui.QTSPData

@Component
public class ServiceSelectionView {
    public var viewModel: ?ServiceSelectionViewModel = Option<ServiceSelectionViewModel>.None

    @State var isLoading: Bool = false
    @State var hasError: Bool = false
    @State var errorConfig: ContentErrorConfig = ContentErrorConfig()
    @State var services: Array<QTSPData> = Array<QTSPData>()
    @State var selectedRsspId: String = ""
    @State var lastAuthUrl: String = ""

    private var vm: ?ServiceSelectionViewModel = Option<ServiceSelectionViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.services = state.services
                        match (state.error) {
                            case Some(cfg) => this.hasError = true; this.errorConfig = cfg
                            case None => this.hasError = false
                        }
                        if (!state.authUrl.isEmpty() && this.lastAuthUrl != state.authUrl) {
                            this.lastAuthUrl = state.authUrl
                            // iOS openURLIfPossible failure closure → setErrorState(.unableToOpenBrowser).
                            if (!RqesBrowser.open(state.authUrl)) {
                                match (this.vm) {
                                    case Some(m) => m.onBrowserOpenFailed()
                                    case None => ()
                                }
                            }
                        }
                    }
                })
                spawn { => model.initiate() }
            case None => ()
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onSelect(item: QTSPData): Unit {
        match (this.vm) {
            case Some(model) =>
                if (this.selectedRsspId == item.rsspId) {
                    this.selectedRsspId = ""
                    model.selectedItem = Option<QTSPData>.None
                } else {
                    this.selectedRsspId = item.rsspId
                    model.selectedItem = Some(item)
                }
            case None => ()
        }
    }

    private func onProceed(): Unit {
        if (this.selectedRsspId.isEmpty()) { return }
        match (this.vm) {
            case Some(model) => spawn { => model.nextStep() }
            case None => ()
        }
    }

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                if (this.hasError) {
                    Column {
                        ContentErrorView(config: this.errorConfig)
                    }.layoutWeight(1).width(100.percent)
                } else if (this.isLoading) {
                    ContentLoaderView(showLoader: true)
                } else {
                    this.content()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    @Builder
    private func content() {
        Column {
            Scroll {
                Column(space: 0.0) {
                    ForEach(
                        this.services,
                        itemGenerator: { item: QTSPData, _: Int64 =>
                            Column {
                                Row {
                                    Text(item.name)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                        .layoutWeight(1)
                                        .textAlign(TextAlign.Start)
                                    if (this.selectedRsspId == item.rsspId) {
                                        // iOS Image(systemName: "checkmark") tinted accent — migrated
                                        // fill-path SVG tinted at runtime via fillColor (@r needs ohos.resource).
                                        Image(@r(app.media.checkmark))
                                            .width(20.0)
                                            .height(20.0)
                                            .fillColor(uiColor(ThemeManager.shared.color.accent))
                                    }
                                }
                                .width(100.percent)
                                .padding(top: SPACING_MEDIUM, bottom: SPACING_MEDIUM)
                                .onClick({ _ => this.onSelect(item) })
                                ListDividerView(spacing: 0.0)
                            }
                        }
                    )
                }
                .width(100.percent)
                .padding(left: SPACING_MEDIUM, right: SPACING_MEDIUM, top: SPACING_MEDIUM, bottom: 0.0)
            }
            .align(Alignment.TopStart)
            .layoutWeight(1)

            // Built-in Button (not WrapButtonView): its .enabled/.opacity react to
            // the @State selection change; a custom @Component's plain params do not
            // update on parent re-render, so WrapButtonView stayed stuck disabled.
            Column {
                Button(LocalizableManager.get(LocalizableStringKey.custom("Proceed")))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(Color.White)
                    .backgroundColor(uiColor(ThemeManager.shared.color.accent))
                    .opacity(if (this.selectedRsspId.isEmpty()) { 0.38 } else { 1.0 })
                    .borderRadius(ThemeManager.shared.shape.small)
                    .height(48.0)
                    .width(100.percent)
                    .enabled(!this.selectedRsspId.isEmpty())
                    .onClick({ _ => this.onProceed() })
            }
            .width(100.percent)
            .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_EXTRA_LARGE, left: SPACING_MEDIUM)
        }
        .width(100.percent)
        .height(100.percent)
    }

    @Builder
    private func toolbar() {
        // iOS ContentScreenView inline nav title: centered + bold, flanked by the
        // back chevron. Equal-width (40) left/right flanks keep the title centered.
        Row {
            Column {
                Text("‹")
                    .fontSize(28.0)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
            .onClick({ _ => this.onBack() })
            Text(LocalizableManager.get(LocalizableStringKey.custom("Select signing service")))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Row {}.width(40.0)
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
    }
}
