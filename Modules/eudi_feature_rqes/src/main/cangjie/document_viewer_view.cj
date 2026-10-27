/*
 * document_viewer_view.cj — ports eudi-lib-ios-rqes-ui DocumentView/DocumentViewer.
 * Previews the (un)signed PDF from the session document path. iOS uses PDFKit; HarmonyOS loads
 * the local file into an ArkWeb Web component (file:// URL) — the reused issuance auth-web idiom.
 */
package eudi_feature_rqes

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import ohos.arkui.component.web.*
import ohos.web.webview.*
import eudi_logic_ui.{
    uiColor, uiFontSize, SPACING_SMALL, SPACING_MEDIUM,
    ContentErrorView, ContentErrorConfig, ContentLoaderView
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

@Component
public class DocumentViewerView {
    public var viewModel: ?DocumentViewerViewModel = Option<DocumentViewerViewModel>.None

    @State var isLoading: Bool = true
    @State var hasError: Bool = false
    @State var errorConfig: ContentErrorConfig = ContentErrorConfig()
    @State var pdfPath: String = ""

    private var vm: ?DocumentViewerViewModel = Option<DocumentViewerViewModel>.None
    private let webController: WebviewController = WebviewController()

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.pdfPath = state.pdfPath
                        match (state.error) {
                            case Some(cfg) => this.hasError = true; this.errorConfig = cfg
                            case None => this.hasError = false
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

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.router.pop()
            case None => ()
        }
    }

    private func fileUrl(): String {
        if (this.pdfPath.startsWith("file://") || this.pdfPath.startsWith("http")) {
            return this.pdfPath
        }
        return "file://" + this.pdfPath
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                if (this.hasError) {
                    Column {
                        ContentErrorView(config: this.errorConfig)
                    }.layoutWeight(1).width(100.percent)
                } else if (this.isLoading || this.pdfPath.isEmpty()) {
                    ContentLoaderView(showLoader: true)
                } else {
                    Web(src: this.fileUrl(), controller: this.webController)
                        .domStorageAccess(true)
                        .width(100.percent)
                        .layoutWeight(1)
                }
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
            Text(LocalizableManager.get(LocalizableStringKey.custom("Document")))
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
