/*
 * signed_document_view.cj — ports eudi-lib-ios-rqes-ui SignedDocument/SignedDocumentView.
 * Runs the remote sign on appear, then shows the iOS success screen: wallet logo +
 * "You have successfully signed your document." + ✓ <qtsp> (ContentHeader) + a success
 * card (green shield gpdGood + file name, tap → preview). The toolbar close (X) raises the
 * "Sharing document / Closing will redirect…" alert (Done → back to dashboard / Share → preview).
 */
package eudi_feature_rqes

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.resource.*
import kit.ArkUI.*
import eudi_logic_ui.{
    uiColor, uiFontSize, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE,
    ContentErrorView, ContentErrorConfig, ContentLoaderView,
    ContentHeaderView, ContentHeaderConfig, AppIconAndTextData, RelyingPartyData,
    AlertView, AlertAction
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

@Component
public class SignedDocumentView {
    public var viewModel: ?SignedDocumentViewModel = Option<SignedDocumentViewModel>.None

    @State var isLoading: Bool = true
    @State var hasError: Bool = false
    @State var errorConfig: ContentErrorConfig = ContentErrorConfig()
    @State var documentName: String = ""
    @State var qtspName: String = ""
    @State var showSharingDialog: Bool = false

    private var vm: ?SignedDocumentViewModel = Option<SignedDocumentViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.documentName = state.documentName
                        this.qtspName = state.qtspName
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

    private func onViewDocument(): Unit {
        match (this.vm) {
            case Some(model) => model.viewDocument()
            case None => ()
        }
    }

    private func onCloseConfirmed(): Unit {
        this.showSharingDialog = false
        match (this.vm) {
            case Some(model) => model.onCancel()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Center) {
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

                // iOS .dialogCompat(.sharingDocument) — close confirmation overlay.
                if (this.showSharingDialog) {
                    AlertView(
                        title: LocalizableStringKey.custom("Sharing document"),
                        message: LocalizableStringKey.custom(
                            "Closing will redirect you back to the dashboard without saving or sharing the document."),
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.custom("Done"),
                                isDestructive: true,
                                callback: { => this.onCloseConfirmed() }),
                            AlertAction(
                                title: LocalizableStringKey.custom("Share"),
                                callback: { => this.showSharingDialog = false; this.onViewDocument() })
                        ],
                        onDismiss: { => this.showSharingDialog = false }
                    )
                }
            }
        }
        .hideTitleBar(true)
    }

    @Builder
    private func content() {
        Column(space: SPACING_LARGE) {
            // iOS ContentHeader: wallet logo/wordmark + success text + ✓ <qtsp>.
            ContentHeaderView(
                config: ContentHeaderConfig(
                    appIconAndTextData: AppIconAndTextData(
                        appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                        appTextSrc: ThemeManager.shared.image.euditext
                    ),
                    description: LocalizableStringKey.custom("You have successfully signed your document."),
                    relyingPartyData: RelyingPartyData(
                        isVerified: true,
                        name: LocalizableStringKey.custom(this.qtspName)
                    )
                )
            )
            this.fileCard()
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
    }

    // iOS CardView(type: .success, leadingIcon: gpdGood): green shield + file name, tap → preview.
    @Builder
    private func fileCard() {
        Row(space: SPACING_MEDIUM) {
            Image(@r(app.media.gpd_good))
                .width(24.0).height(24.0)
                .fillColor(uiColor(ThemeManager.shared.color.success))
            Text(this.documentName)
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
                .maxLines(1)
            Text("\u{203A}")
                .fontSize(22.0)
                .fontColor(uiColor(ThemeManager.shared.color.accent))
        }
        .width(100.percent)
        .alignItems(VerticalAlign.Center)
        .padding(SPACING_MEDIUM)
        // iOS .success card: light green fill (success at ~8% alpha).
        .backgroundColor(Color(0x142C7E0Au32))
        .borderRadius(18.0)
        .onClick({ _ => this.onViewDocument() })
    }

    @Builder
    private func toolbar() {
        // iOS ContentScreenView: centered inline title (.dataShared) + trailing close (X) → alert.
        Row {
            Row {}.width(40.0)
            Text(LocalizableManager.get(LocalizableStringKey.custom("Data shared")))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Column {
                Text("\u{2715}")
                    .fontSize(20.0)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
            .onClick({ _ => this.showSharingDialog = true })
        }
        .width(100.percent)
        .alignItems(VerticalAlign.Center)
        .padding(SPACING_MEDIUM)
    }
}
