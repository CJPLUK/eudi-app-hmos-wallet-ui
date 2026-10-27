/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/SignDocument/SignDocumentView.swift + SignDocumentViewModel.swift +
 * Interactor/DocumentSignInteractor.swift) to Cangjie.
 *
 * The screen lets a user pick a local PDF to remotely sign (QES). iOS delegates
 * the actual signing to the EudiRQESUi SDK: DocumentSignInteractor lazily
 * registers the shared EudiRQESUi (config from ConfigLogic's build variant) and
 * calls initiate(fileUrl), after which the SDK presents its first screen. Here
 * the same interactor seam initialises the Cangjie EudiRQESUi facade and pushes
 * the flow's first route (eudi_feature_rqes) on the shared NavPathStack — the
 * HarmonyOS equivalent of the SDK presenting itself on the top view controller.
 *
 * NavDestination root (D-002), registered under AppRoutes.signDocument. This is
 * the route the Home tab "Sign document" card pushes (HomeTabView.onSignDocument
 * → AppRoutes.signDocument), so the card now lands on a real screen instead of
 * the fallback destination.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, ToolBarContent, ToolBarAction,
    uiColor, uiFontSize, AppRoutes, FilePickerBridge,
    SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, appImageSrc
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

// ─── Interactor (mirrors iOS DocumentSignInteractor) ────────────────────────

/**
 * Entry-installed launcher that starts the RQES signing flow. The installed
 * closure carries the full iOS DocumentSignInteractor semantics — lazily
 * register the shared EudiRQESUi (config from ConfigLogic's build variant),
 * facade.initiate(fileUrl), then present the flow's first route.
 *
 * Routed through a seam (same pattern as RqesBrowser / FilePickerBridge)
 * instead of a direct eudi_feature_rqes dependency: hvigor compiles each
 * module's Cangjie against that module's OWN resource map, so pulling
 * feature_rqes into this module's build would re-expand its `@r(app.media.…)`
 * macros against the dashboard resource table and fail. iOS has no such
 * per-module resource scoping, so it imports EudiRQESUi directly.
 */
public class RqesSigningLauncher {
    private static var launch: ?(String) -> Unit = None

    /** Installed by `entry` (AppComposition) at startup. */
    public static func setLauncher(l: (String) -> Unit): Unit {
        RqesSigningLauncher.launch = Some(l)
    }

    /** Starts the signing flow; false when no launcher is installed. */
    public static func launchSigning(filePath: String): Bool {
        match (RqesSigningLauncher.launch) {
            case Some(f) =>
                f(filePath)
                return true
            case None => return false
        }
    }
}

/** Mirrors the iOS `DocumentSignInteractor` protocol. */
public interface DocumentSignInteractor {
    func initiateSigning(filePath: String): Unit
}

/**
 * Mirrors iOS `DocumentSignInteractorImpl` (a final actor). The heavy lifting
 * (lazy EudiRQESUi registration + initiate + present) lives in the launcher
 * closure installed by the composition root; iOS silently returns when it
 * cannot present (`guard topViewController`), and a missing launcher is the
 * seam's equivalent.
 */
public class DocumentSignInteractorImpl <: DocumentSignInteractor {
    public init() {}

    public func initiateSigning(filePath: String): Unit {
        let _ = RqesSigningLauncher.launchSigning(filePath)
    }
}

// ─── State (mirrors iOS SignDocumentState) ──────────────────────────────────

/** Mirrors Swift `SignDocumentState` (listItem) plus the honest status line. */
public class SignDocumentState <: ViewState {
    public let selectLabel: LocalizableStringKey
    public let statusMessage: ?String

    public init(
        selectLabel!: LocalizableStringKey = LocalizableStringKey.selectDocument,
        statusMessage!: ?String = Option<String>.None
    ) {
        this.selectLabel = selectLabel
        this.statusMessage = statusMessage
    }
}

// ─── View model (mirrors iOS SignDocumentViewModel) ─────────────────────────

/** Mirrors Swift `SignDocumentViewModel<Router>`. */
public class SignDocumentViewModel <: BaseViewModel<SignDocumentState> {
    private let interactor: DocumentSignInteractor

    public init(router!: RouterHost, interactor!: DocumentSignInteractor) {
        super(router, SignDocumentState())
        this.interactor = interactor
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

    // iOS onFileSelection(with:) → interactor.initiateSigning(url:) — the
    // interactor lazily registers EudiRQESUi, initialises the session with the
    // picked file, and presents the signing flow's first screen.
    public func onFileSelection(filePath: String): Unit {
        if (filePath.isEmpty()) {
            this.setState({ s =>
                SignDocumentState(selectLabel: s.selectLabel, statusMessage: Some("No document selected."))
            })
            return
        }
        this.interactor.initiateSigning(filePath)
    }
}

// ─── View (mirrors iOS SignDocumentView) ────────────────────────────────────

/**
 * Sign-document screen. NavDestination root (D-002), route AppRoutes.signDocument.
 * Owns its own toolbar (back) + subtitle + a "select document" card. The
 * platform file picker is not bridged in this build; the card publishes the
 * honest backend status (mirrors iOS surfacing an RQES initiation failure).
 */
@Component
public class SignDocumentView {
    public var viewModel: ?SignDocumentViewModel = Option<SignDocumentViewModel>.None

    @State
    var statusMessage: String = ""
    @State
    var hasStatus: Bool = false

    private var vm: ?SignDocumentViewModel = Option<SignDocumentViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        match (state.statusMessage) {
                            case Some(m) =>
                                this.statusMessage = m
                                this.hasStatus = true
                            case None =>
                                this.hasStatus = false
                        }
                    }
                })
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

    private func onSelectDocument(): Unit {
        // Open the platform document picker (ArkTS DocumentViewPicker via FilePickerBridge);
        // the chosen PDF's cache path is handed to the view model, which pushes into the RQES
        // flow. If no picker is installed, report unavailability through the same state channel.
        match (this.vm) {
            case Some(model) =>
                let started = FilePickerBridge.requestPick({ path =>
                    spawn(UIThread) { => model.onFileSelection(path) }
                })
                if (!started) {
                    spawn(UIThread) { => model.onFileSelection("") }
                }
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                Scroll {
                    Column(space: SPACING_LARGE) {
                        Text(LocalizableManager.get(LocalizableStringKey.signDocumentSubtitle))
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                            .textAlign(TextAlign.Start)

                        // Select-document card (built-in components).
                        Row(space: SPACING_MEDIUM) {
                            Text(LocalizableManager.get(LocalizableStringKey.selectDocument))
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .layoutWeight(1)
                                .textAlign(TextAlign.Start)
                            Image(appImageSrc(ThemeManager.shared.image.plus))
                                .width(20.0)
                                .height(20.0)
                                .objectFit(ImageFit.Contain)
                                .fillColor(uiColor(ThemeManager.shared.color.accent))
                        }
                        .width(100.percent)
                        .padding(SPACING_MEDIUM)
                        .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                        .borderRadius(18.0)
                        .onClick({ _ => this.onSelectDocument() })

                        if (this.hasStatus) {
                            Text(this.statusMessage)
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .width(100.percent)
                                .textAlign(TextAlign.Start)
                        }
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
        // iOS ContentScreenView: centered inline title, flanked by a circular back
        // "bubble" (same style as the Home top-bar menu button).
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
            Text(LocalizableManager.get(LocalizableStringKey.signDocument))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Row {}.width(40.0)
        }
        .width(100.percent)
        .alignItems(VerticalAlign.Center)
        .padding(SPACING_MEDIUM)
    }
}
