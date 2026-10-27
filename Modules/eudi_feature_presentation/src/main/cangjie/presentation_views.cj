/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-presentation
 * module (UI/Presentation Request/Loading/Success views) to Cangjie ArkUI.
 *
 * Three NavDestination-rooted screens (D-002):
 *  - PresentationRequestView: wraps the shared feature-common BaseRequestView,
 *    driven by the VM's requestModel; runs the device-engagement work on a
 *    background thread (spawn{}) and confirms the selected disclosure.
 *  - PresentationLoaderView: sends the prepared response and waits for the
 *    coordinator state stream to report responseSent/error.
 *  - PresentationSuccessView: the generic SuccessView from the success config.
 *
 * Blocking engine calls run in spawn{}; @State writes are marshalled with
 * spawn(UIThread) (S-001).
 */
package eudi_feature_presentation

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.collection.{ArrayList, HashMap}
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_feature_common.{
    BaseRequestView, RequestViewModel, RequestDataCell, RequestDataSection, SuccessView, LoadingView,
    SuccessUIConfig, SuccessTitle
}

// ─── PresentationRequestView ─────────────────────────────────────────────────

@Component
public class PresentationRequestView {
    public var viewModel: ?PresentationRequestViewModel = Option<PresentationRequestViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""

    private var vm: ?PresentationRequestViewModel = Option<PresentationRequestViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultPresentationRequestViewModel()
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

    private func onDismissError(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissError()
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

// ─── PresentationLoaderView ──────────────────────────────────────────────────

@Component
public class PresentationLoaderView {
    public var viewModel: ?PresentationLoaderViewModel = Option<PresentationLoaderViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var hasError: Bool = false
    @State
    var errorMessage: String = ""

    private var vm: ?PresentationLoaderViewModel = Option<PresentationLoaderViewModel>.None

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? makeDefaultPresentationLoaderViewModel()
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
                LoadingView(
                    title: LocalizableStringKey.dataSharingRequest,
                    isCancellable: true,
                    onCancel: { => this.onCancel() }
                )
            }
        }
        .hideTitleBar(true)
    }
}

// ─── PresentationSuccessView ─────────────────────────────────────────────────

@Component
public class PresentationSuccessView {
    public var viewModel: ?PresentationSuccessViewModel = Option<PresentationSuccessViewModel>.None

    private var vm: ?PresentationSuccessViewModel = Option<PresentationSuccessViewModel>.None

    @State
    var expandedDocs: HashMap<String, Bool> = HashMap<String, Bool>()

    protected override func aboutToAppear(): Unit {
        this.vm = this.viewModel
    }

    // iOS PresentationSuccessView == DocumentSuccessView: the document-list
    // success (header + trusted-verifier badge + shared-document cards + Done),
    // mirroring the issuance DocumentIssuanceSuccessView layout.
    public func build() {
        NavDestination() {
            Column {
                Scroll {
                    Column(space: SPACING_LARGE_MEDIUM) {
                        this.contentHeader()
                        this.documentSections()
                    }
                    .width(100.percent)
                    .padding(ThemeManager.shared.dimension.padding)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
                Column {
                    WrapButtonView(
                        title: LocalizableStringKey.doneButton,
                        style: ButtonViewStyle.primary(),
                        onAction: { => this.onDone() }
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_LARGE_MEDIUM, left: SPACING_MEDIUM)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    private func relyingPartyName(): String {
        match (this.vm) {
            case Some(model) => match (model.docConfig.relyingParty) {
                case Some(n) => n
                case None => ""
            }
            case None => ""
        }
    }

    private func isTrusted(): Bool {
        match (this.vm) {
            case Some(model) => model.docConfig.relyingPartyIsTrusted
            case None => false
        }
    }

    private func docTitles(): Array<String> {
        match (this.vm) {
            case Some(model) => model.docConfig.docTitles
            case None => Array<String>()
        }
    }

    private func docSections(): Array<RequestDataSection> {
        match (this.vm) {
            case Some(model) => model.docConfig.docSections
            case None => Array<RequestDataSection>()
        }
    }

    private func isDocExpanded(id: String): Bool {
        if (this.expandedDocs.contains(id)) {
            return this.expandedDocs[id]
        }
        return false
    }

    private func toggleDoc(id: String): Unit {
        let next = HashMap<String, Bool>()
        for ((key, value) in this.expandedDocs) {
            next[key] = value
        }
        next[id] = !this.isDocExpanded(id)
        this.expandedDocs = next
    }

    private func docChevron(id: String): String {
        if (this.isDocExpanded(id)) {
            return ThemeManager.shared.image.chevronUpAccent
        }
        return ThemeManager.shared.image.chevronDownAccent
    }

    private func onDone(): Unit {
        match (this.vm) {
            case Some(model) => model.onDone()
            case None => ()
        }
    }

    // Header: app icon/wordmark + "You successfully shared … with" + verifier
    // (green ✓ when the reader cert chain validated).
    @Builder
    private func contentHeader() {
        ContentHeaderView(
            config: ContentHeaderConfig(
                appIconAndTextData: AppIconAndTextData(
                    appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                    appTextSrc: ThemeManager.shared.image.euditext
                ),
                description: LocalizableStringKey.custom("You successfully shared the following information with"),
                relyingPartyData: RelyingPartyData(
                    logoUrl: "",
                    isVerified: this.isTrusted(),
                    name: LocalizableStringKey.custom(this.relyingPartyName())
                )
            )
        )
    }

    // One card per shared document. This is intentionally the same interaction
    // as the request/selectable-items screen: tap the trailing triangle to
    // expand/collapse the exact fields that were shared.
    @Builder
    private func documentSections() {
        Column(space: SPACING_MEDIUM) {
            ForEach(
                this.docSections(),
                itemGenerator: { section: RequestDataSection, _: Int64 =>
                    Column(space: SPACING_NONE) {
                        Row(space: SPACING_MEDIUM) {
                            Column(space: SPACING_EXTRA_SMALL) {
                                Text(section.title)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                    .fontWeight(FontWeight.Bold)
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                                Text(LocalizableManager.get(LocalizableStringKey.viewDetails))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                            }
                            .alignItems(HorizontalAlign.Start)
                            .layoutWeight(1)
                            Image(appImageSrc(this.docChevron(section.id)))
                                .width(24.0)
                                .height(24.0)
                                .objectFit(ImageFit.Contain)
                        }
                        .width(100.percent)
                        .padding(SPACING_MEDIUM)
                        .onClick({ _ => this.toggleDoc(section.id) })

                        if (this.isDocExpanded(section.id)) {
                            ForEach(
                                section.cells.toArray(),
                                itemGenerator: { cell: RequestDataCell, index: Int64 =>
                                    Column(space: SPACING_NONE) {
                                        Column(space: SPACING_EXTRA_SMALL) {
                                            Text(cell.title)
                                                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                                .width(100.percent)
                                                .textAlign(TextAlign.Start)
                                            Text(cell.value)
                                                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                                .fontWeight(FontWeight.Medium)
                                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                                .width(100.percent)
                                                .textAlign(TextAlign.Start)
                                        }
                                        .width(100.percent)
                                        // iOS WrapListItemView applies SPACING_MEDIUM
                                        // on all four sides of every expanded row.
                                        .padding(SPACING_MEDIUM)

                                        if (index < section.cells.size - 1) {
                                            Row {
                                                Divider()
                                                    .color(uiColor(ThemeManager.shared.color.separator))
                                                    .strokeWidth(1.0)
                                                    .layoutWeight(1)
                                            }
                                            .padding(left: SPACING_MEDIUM, right: SPACING_MEDIUM)
                                        }
                                    }
                                    .width(100.percent)
                                },
                                keyGenerator: { cell: RequestDataCell, _: Int64 => cell.groupId }
                            )
                        }
                    }
                    .width(100.percent)
                    .backgroundColor(uiColor(ThemeManager.shared.color.successBackground))
                    .borderRadius(18.0)
                    .clip(true)
                },
                keyGenerator: { section: RequestDataSection, _: Int64 => section.id }
            )
        }
        .width(100.percent)
    }
}

// ─── standalone-render fallbacks (composition root supplies wired instances) ──

func defaultPresentationSuccessConfig(): SuccessUIConfig {
    SuccessUIConfig(
        title: SuccessTitle(value: LocalizableStringKey.success),
        subtitle: LocalizableStringKey.dataShared
    )
}

func makeDefaultPresentationRequestViewModel(): PresentationRequestViewModel {
    PresentationRequestViewModel(
        router: InMemoryRouterHost(),
        interactor: NoopPresentationInteractor()
    )
}

func makeDefaultPresentationLoaderViewModel(): PresentationLoaderViewModel {
    PresentationLoaderViewModel(
        router: InMemoryRouterHost(),
        interactor: NoopPresentationInteractor()
    )
}
