/*
 * document_selection_view.cj — ports eudi-lib-ios-rqes-ui DocumentSelectionView.
 * The flow hub (.initial / .credentials): shows the document + service + certificate step
 * rows; taps navigate to preview / service selection / credential selection.
 *
 * 1:1 with iOS: centered inline nav title (.signDocument); a leading Cancel (X) action that
 * raises the "Cancel signing process?" alert (AlertView overlay); rows are SelectionItemView
 * (step badge + overline/main/subtitle + View + chevron) separated by ListDividerView — NO
 * card background. Step badge tint mirrors iOS leadingIconTint: color.success (done) vs
 * color.primaryLabel (pending) — the iOS stepOne/Two/Three glyphs are a numbered rounded
 * square, reproduced in-code (the @r/$r bundled-resource macro is unusable in this build,
 * and a numbered badge is fully theme-tintable without an asset).
 */
package eudi_feature_rqes

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import ohos.resource.*
import kit.ArkUI.*
import eudi_logic_ui.{
    uiColor, uiFontSize, SPACING_EXTRA_SMALL, SPACING_SMALL, SPACING_MEDIUM,
    ContentErrorView, ContentErrorConfig, ContentLoaderView, ListDividerView,
    AlertView, AlertAction
}
import eudi_logic_resources.{ThemeManager, ThemeColor, LocalizableStringKey, LocalizableManager}

@Component
public class DocumentSelectionView {
    public var viewModel: ?DocumentSelectionViewModel = Option<DocumentSelectionViewModel>.None

    @State var isLoading: Bool = true
    @State var hasError: Bool = false
    @State var errorConfig: ContentErrorConfig = ContentErrorConfig()
    @State var documentRow: ?RqesSelectionRow = Option<RqesSelectionRow>.None
    @State var serviceRow: ?RqesSelectionRow = Option<RqesSelectionRow>.None
    @State var certificateRow: ?RqesSelectionRow = Option<RqesSelectionRow>.None
    @State var showCancelDialog: Bool = false

    private var vm: ?DocumentSelectionViewModel = Option<DocumentSelectionViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.documentRow = state.documentRow
                        this.serviceRow = state.serviceRow
                        this.certificateRow = state.certificateRow
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

    private func onCancelSigning(): Unit {
        this.showCancelDialog = false
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
                        Scroll {
                            Column(space: SPACING_MEDIUM) {
                                if (this.documentRow.isSome()) {
                                    this.stepRow(this.documentRow.getOrThrow())
                                    ListDividerView(spacing: 0.0)
                                }
                                if (this.serviceRow.isSome()) {
                                    this.stepRow(this.serviceRow.getOrThrow())
                                }
                                if (this.certificateRow.isSome()) {
                                    ListDividerView(spacing: 0.0)
                                    this.stepRow(this.certificateRow.getOrThrow())
                                }
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                        }
                        .align(Alignment.TopStart)
                        .layoutWeight(1)
                    }
                }
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(uiColor(ThemeManager.shared.color.background))

                // iOS .dialogCompat(.cancelSigningProcessTitle) — overlay alert.
                if (this.showCancelDialog) {
                    AlertView(
                        title: LocalizableStringKey.custom("Cancel signing process?"),
                        message: LocalizableStringKey.custom(
                            "Cancel will redirect you back to the document list without signing your document."),
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.custom("Continue signing"),
                                callback: { => this.showCancelDialog = false }),
                            AlertAction(
                                title: LocalizableStringKey.custom("Cancel signing"),
                                isDestructive: true,
                                callback: { => this.onCancelSigning() })
                        ],
                        onDismiss: { => this.showCancelDialog = false }
                    )
                }
            }
        }
        .hideTitleBar(true)
    }

    // iOS leadingIconTint: color.success (step done) vs color.onSurface (pending) — HMOS onSurface≈primaryLabel.
    private func badgeColor(row: RqesSelectionRow): ThemeColor {
        if (row.done) {
            return ThemeManager.shared.color.success
        }
        return ThemeManager.shared.color.primaryLabel
    }

    // iOS Image(.stepOne/.stepTwo/.stepThree) tinted leadingIconTint — the actual iOS SVG
    // badges migrated to entry/resources/base/media, tinted at runtime via fillColor
    // (success green when done / primaryLabel dark when active). @r needs `ohos.resource`.
    @Builder
    private func stepBadge(row: RqesSelectionRow) {
        if (row.step == 1) {
            Image(@r(app.media.step_one))
                .width(20.0).height(20.0)
                .fillColor(uiColor(this.badgeColor(row)))
        } else if (row.step == 2) {
            Image(@r(app.media.step_two))
                .width(20.0).height(20.0)
                .fillColor(uiColor(this.badgeColor(row)))
        } else {
            Image(@r(app.media.step_three))
                .width(20.0).height(20.0)
                .fillColor(uiColor(this.badgeColor(row)))
        }
    }

    // iOS SelectionItemView: HStack(top) [ leadingIcon(20) | VStack(overline/main/subtitle) | actionText + chevron ].
    @Builder
    private func stepRow(row: RqesSelectionRow) {
        Row(space: SPACING_SMALL) {
            this.stepBadge(row)
            Column(space: SPACING_EXTRA_SMALL) {
                if (row.overline.isSome()) {
                    Text(LocalizableManager.get(row.overline.getOrThrow()))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .width(100.percent)
                        .textAlign(TextAlign.Start)
                }
                Text(LocalizableManager.get(row.mainText))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                if (row.subtitle.isSome()) {
                    Text(LocalizableManager.get(row.subtitle.getOrThrow()))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .width(100.percent)
                        .textAlign(TextAlign.Start)
                }
            }
            .layoutWeight(1)
            Row(space: SPACING_SMALL) {
                if (row.actionText.isSome()) {
                    Text(LocalizableManager.get(row.actionText.getOrThrow()))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.accent))
                }
                Text("\u{203A}")
                    .fontSize(22.0)
                    .fontColor(uiColor(ThemeManager.shared.color.accent))
            }
        }
        .width(100.percent)
        .alignItems(VerticalAlign.Top)
        .padding(top: SPACING_MEDIUM, bottom: SPACING_MEDIUM)
        .onClick({ _ => if (row.enabled) { row.action() } })
    }

    @Builder
    private func toolbar() {
        // iOS ContentScreenView: centered inline title + leading Cancel (X) → cancel-signing alert.
        Row {
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
            .onClick({ _ => this.showCancelDialog = true })
            Text(LocalizableManager.get(LocalizableStringKey.custom("Sign document")))
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
