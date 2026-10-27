/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-assembly module
 * (Sources/Extension/DIGraph+Extensions.swift — assembleDependenciesGraph) to Cangjie
 * for the EUDI HarmonyOS wallet.
 *
 * AppComposition is the manual dependency injection container, mirroring the role of
 * iOS DIGraph.assembleDependenciesGraph(). It wires the concrete RouterHost
 * (ProdRouterHost) with all delivered feature ViewModels:
 *   - StartupViewModel  (eudi_feature_startup)
 *   - QuickPinViewModel (eudi_feature_common)
 *   - BiometryViewModel (eudi_feature_common)
 *
 * Design: process-wide singleton accessed via AppComposition.shared. AppRoot creates
 * the singleton after constructing the NavPathStack, then injects the NavPathStack
 * into ProdRouterHost so that NavigationStack state and RouterHost are consistent.
 *
 * Only already-delivered modules are referenced (no import of undelivered modules).
 * Per M0 scope, walletKitController (logic-core documents check) is not wired.
 */
package ohos_app_cangjie_entry

import kit.ArkUI.*
import eudi_logic_ui.*
import eudi_feature_startup.{StartupViewModel, StartupInteractorImpl, StartupInteractor}
import eudi_feature_common.{
    PinStore, FilePinStore, KeychainPinStore,
    QuickPinViewModel, QuickPinUiConfig, QuickPinFlow,
    BiometryViewModel, BiometricUiConfig,
    BiometryController, createBiometryController
}
import eudi_feature_dashboard.{
    DashboardViewModel, DashboardInteractor,
    DocumentDetailsViewModel, TransactionDetailsViewModel,
    SettingsViewModel, SettingsInteractor,
    SideMenuViewModel,
    SignDocumentViewModel, DocumentSignInteractorImpl, RqesSigningLauncher,
    IssuanceOptionViewModel
}
import ohos.bundle.bundle_manager.{BundleManager, BundleFlag}
import eudi_logic_business.{PrefsController, PrefsControllerImpl, ConfigLogic, ConfigLogicImpl, createConfigLogic, ReachabilityController, AppVersionSource, AppBuildVariantSource}
import eudi_feature_common.{IssuanceFlow, IssuanceCodeUiConfig}
import eudi_feature_issuance.{
    AddDocumentViewModel, AddDocumentInteractorImpl,
    DocumentOfferViewModel, DocumentOfferInteractorImpl,
    OfferCodeViewModel,
    DocumentIssuanceSuccessViewModel, DocumentIssuanceSuccessUIConfig
}
import eudi_feature_presentation.{
    PresentationRequestViewModel, PresentationLoaderViewModel, PresentationSuccessViewModel,
    PresentationInteractor, PresentationInteractorImpl
}
import eudi_feature_proximity.{
    ProximityConnectionViewModel, ProximityRequestViewModel,
    ProximityLoaderViewModel, ProximitySuccessViewModel,
    ProximityInteractor, ProximityInteractorImpl
}
import eudi_feature_rqes.{
    RqesBrowser, ensureRqesUi, rqesRouteForState,
    ServiceSelectionViewModel, DocumentSelectionViewModel,
    CredentialSelectionViewModel, SignedDocumentViewModel, DocumentViewerViewModel
}
import ohos_app_cangjie_eudi_cjrqes_ui.{EudiRQESUi, makeRQESInteractor}
import ohos.app.ability.want.Want
import eudi_feature_common.{ScannerUiConfig, ScannerFlow, DocumentSuccessUIConfig}
import eudi_logic_core.{WalletKitController, RemoteSessionCoordinator, ProximitySessionCoordinator, HuksKeyChainController, AppContextHolder}
import eudi_logic_assembly.LogicAssembly
import eudi_logic_authentication.{LogicAuthAssembly, PinThrottleController}

/**
 * Reads a module-level metadata value declared in `entry/src/main/module.json5`
 * — the HarmonyOS counterpart of an Info.plist key. Returns "" when the entry
 * is absent, which the ConfigLogic seam reads as "not declared".
 */
func readBundleMetadata(name: String): String {
    let flags = BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE | BundleFlag.GET_BUNDLE_INFO_WITH_METADATA
    let info = BundleManager.getBundleInfoForSelf(flags)
    for (hapModule in info.hapModulesInfo) {
        for (entry in hapModule.metadata) {
            if (entry.name == name) {
                return entry.value
            }
        }
    }
    return ""
}

/**
 * Manual DI container. Mirrors iOS DIGraph.assembleDependenciesGraph().
 *
 * All dependencies are resolved eagerly at init time. ViewModels are created fresh
 * for each destination instantiation (QuickPin/Biometry) because their config varies
 * per route invocation; only the shared infrastructure (router, pinStore, etc.)
 * is kept as singleton members.
 */
public class AppComposition {
    private static var _shared: ?AppComposition = None

    /** The production router host, backed by the NavPathStack owned by AppRoot. */
    public let router: ProdRouterHost

    // ── Shared infrastructure (singleton, iOS DIGraph.shared.resolver equivalent) ──
    private let pinStore: PinStore
    private let pinThrottle: PinThrottleController
    private let prefsController: PrefsController
    private let configLogic: ConfigLogic
    private let biometryController: BiometryController
    /** Reachability seam (BLE availability / settings) for the Home tab. */
    private let reachabilityController: ReachabilityController

    /**
     * WalletKitController — the wallet-kit engine facade (logic-core). Built once
     * from a fully wired LogicCoreAssembly (mirrors iOS DIGraph assembling the
     * logic-core graph). Consumed by the feature-issuance interactors.
     */
    private let walletController: WalletKitController

    /** StartupViewModel — singleton because Startup is the root page. */
    public let startupViewModel: StartupViewModel

    /**
     * The active presentation coordinators, mirroring iOS where the coordinator
     * created by the entry flow (onShare / onShowScanner) is threaded through the
     * subsequent route arguments. Here the connection/scanner factory starts the
     * presentation and stashes the coordinator; the request/loader factories
     * reuse the same one so they drive the same session.
     */
    private var activeProximityCoordinator: ?ProximitySessionCoordinator = None
    private var activeRemoteCoordinator: ?RemoteSessionCoordinator = None
    // Interactor shared between the proximity connection / request / loader VMs
    // so the verifier name + disclosed-document titles captured on the request
    // screen reach the transaction log written after the response is sent.
    private var activeProximityInteractor: ?ProximityInteractor = None
    // Interactor shared between the presentation request + loader VMs so the
    // captured verifier name / trust / doc titles reach the success page.
    private var activePresentationInteractor: ?PresentationInteractor = None

    private init(navStack: NavPathStack) {
        AppVersionSource.setReader({ =>
            BundleManager.getBundleInfoForSelf(BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName
        })
        // iOS reads the build variant from the app bundle ("Build Variant" in
        // Info.plist); the HarmonyOS counterpart is the module's metadata in
        // module.json5, so the packaged artifact decides which issuers the
        // wallet talks to instead of a constant compiled into the graph.
        AppBuildVariantSource.setReader({ => readBundleMetadata("BuildVariant") })
        let configUiLogic = ConfigUiLogicImpl()
        this.router = ProdRouterHost(navStack: navStack, configLogic: configUiLogic)
        this.prefsController = PrefsControllerImpl()
        // Variant comes from the packaged module metadata (DEV when absent).
        this.configLogic = ConfigLogicImpl()
        // iOS DocumentSignInteractor semantics, installed as the dashboard's
        // signing launcher (seam keeps feature_rqes out of the dashboard build,
        // see RqesSigningLauncher): lazily register the shared EudiRQESUi from
        // the packaged build variant, initialise the session with the picked
        // file, and present the flow's first route.
        // Capture the (already-initialized) configLogic + router into locals so the
        // escaping launcher closure closes over those rather than `this` — Cangjie
        // forbids a constructor's escaping closure from capturing `this` until every
        // member is initialized, and several members below are still unassigned here.
        let rqesConfigLogic = this.configLogic
        let rqesRouter = this.router
        RqesSigningLauncher.setLauncher({ filePath =>
            ensureRqesUi(rqesConfigLogic)
            // iOS: `try? await eudiRQESUi.initiate(on:fileUrl:)` — a failed
            // initiation (session init or presentation) is silently dropped,
            // never crashes the sign entry point. Mirror that here around the
            // initiate + first-route push.
            try {
                let facade = EudiRQESUi.instance()
                facade.initiate(filePath)
                rqesRouter.push(rqesRouteForState(facade.getState()))
            } catch (_: Exception) {
                ()
            }
        })
        // Install the RQES external-browser opener (the feature stays core/native-free; the
        // Want + ability context live here). iOS: UIApplication.openURLIfPossible.
        RqesBrowser.setOpener({ url =>
            match (AppContextHolder.get()) {
                case Some(ctx) =>
                    try {
                        ctx.startAbility(Want(uri: url, action: "ohos.want.action.viewData"))
                        true
                    } catch (_: Exception) {
                        false
                    }
                case None => false
            }
        })
        // PIN storage and the lockout throttle share ONE HUKS-backed keychain,
        // mirroring iOS (LogicAuthAssembly's single keyChainController feeds both
        // KeychainPinStorageProvider and KeychainPinThrottleProvider). One instance
        // = one Mutex over the ".pin" HUKS blob, so PIN keys (devicePin*) and
        // throttle keys (pinFailedAttempts / pinLockout*) never race on
        // read-modify-write.
        let pinKeyChain = HuksKeyChainController(
            service: this.configLogic.keyChainConfig.documentStorageServiceName + ".pin",
            storageDir: FilePinStore.DEFAULT_STORAGE_DIR
        )
        this.pinStore = KeychainPinStore(pinKeyChain)
        this.pinThrottle = LogicAuthAssembly(pinKeyChain).resolvePinThrottleController()
        this.biometryController = createBiometryController()
        // The ability context (set by the ETS bridge before the graph is built)
        // backs the ACCESS_BLUETOOTH runtime prompt and the Bluetooth settings
        // deep link of the in-person entry path.
        this.reachabilityController = createReachabilityController({ => AppContextHolder.get() })
        this.walletController = AppComposition.buildWalletController(
            this.configLogic,
            this.prefsController
        )
        let interactor: StartupInteractor = StartupInteractorImpl(
            pinStore: this.pinStore,
            prefsController: this.prefsController,
            configLogic: this.configLogic,
            walletController: this.walletController
        )
        this.startupViewModel = StartupViewModel(router: this.router, interactor: interactor)
    }

    /**
     * Resolves the WalletKitController by delegating to the logic-assembly
     * composition root (LogicAssembly.resolveWalletController), which owns the
     * UI-independent half of the DI graph — mirroring iOS DIGraph+Extensions
     * assembleDependenciesGraph. The entry keeps only the RouterHost wiring
     * (NavPathStack-bound), exactly as iOS keeps RouterHostImpl bound to the
     * SwiftUI navigation path.
     */
    private static func buildWalletController(
        configLogic: ConfigLogic,
        prefsController: PrefsController
    ): WalletKitController {
        return LogicAssembly(
            configLogic: configLogic,
            prefsController: prefsController
        ).resolveWalletController()
    }

    /**
     * Initialise and cache the singleton. Must be called once by AppRoot before
     * any destination attempts to access AppComposition.shared.
     */
    public static func setup(navStack: NavPathStack): Unit {
        AppComposition._shared = Some(AppComposition(navStack))
    }

    /**
     * Returns the singleton.
     *
     * Fails fast (panic) if setup() was not called before the first access.
     * Mirrors the iOS pattern where DIGraph is assembled once at app start and
     * every subsequent resolver call assumes the graph is ready. A silent
     * fallback (creating an orphan NavPathStack-backed composition) would produce
     * a navigation hollow that is impossible to diagnose at runtime (P2 fix).
     */
    public static prop shared: AppComposition {
        get() {
            match (AppComposition._shared) {
                case Some(c) => c
                case None => throw Exception("AppComposition.setup() must be called in AppRoot.aboutToAppear() before any access to AppComposition.shared")
            }
        }
    }

    /**
     * Creates a fresh QuickPinViewModel for the given config.
     * Mirrors iOS CommonRouter.resolve QuickPin branch wiring.
     */
    public func quickPinViewModel(config!: QuickPinUiConfig): QuickPinViewModel {
        QuickPinViewModel(router: this.router, config: config, pinStore: this.pinStore, pinThrottle: this.pinThrottle)
    }

    /**
     * Creates a fresh BiometryViewModel for the given config.
     * Mirrors iOS CommonRouter.resolve Biometry branch wiring.
     */
    public func biometryViewModel(config!: BiometricUiConfig): BiometryViewModel {
        BiometryViewModel(router: this.router, config: config, pinStore: this.pinStore, pinThrottle: this.pinThrottle)
    }

    /**
     * Creates a fresh DashboardViewModel wired with a DashboardInteractor over
     * the shared WalletKitController, so the Documents / History tabs load real
     * data. Mirrors iOS DashboardRouter.resolve Dashboard branch wiring.
     */
    public func dashboardViewModel(): DashboardViewModel {
        DashboardViewModel(
            router: this.router,
            interactor: DashboardInteractor(
                walletController: this.walletController,
                reachability: this.reachabilityController,
                // Same PrefsController instance Settings writes to: the document
                // cards gate their usage badge on PrefsKey.batchCounter (iOS
                // resolves one PrefsController for every interactor).
                prefs: this.prefsController
            )
        )
    }

    /** Fresh DocumentDetailsViewModel for the given document id. */
    public func documentDetailsViewModel(documentId!: String): DocumentDetailsViewModel {
        DocumentDetailsViewModel(
            router: this.router,
            interactor: DashboardInteractor(
                walletController: this.walletController,
                prefs: this.prefsController
            ),
            documentId: documentId
        )
    }

    /** Fresh TransactionDetailsViewModel for the given transaction id. */
    public func transactionDetailsViewModel(transactionId!: String): TransactionDetailsViewModel {
        TransactionDetailsViewModel(
            router: this.router,
            interactor: DashboardInteractor(walletController: this.walletController, prefs: this.prefsController),
            transactionId: transactionId
        )
    }

    // ── dashboard sub-screen ViewModels (iOS DashboardRouter) ──────────────────

    /** Fresh SettingsViewModel wired over config/prefs/biometry seams. */
    public func settingsViewModel(): SettingsViewModel {
        SettingsViewModel(
            router: this.router,
            interactor: SettingsInteractor(
                configLogic: this.configLogic,
                prefsController: this.prefsController,
                biometryController: this.biometryController
            )
        )
    }

    /** Fresh SideMenuViewModel (no interactor; pure navigation). */
    public func sideMenuViewModel(): SideMenuViewModel {
        SideMenuViewModel(router: this.router)
    }

    /** Fresh SignDocumentViewModel wired over the document-sign seam. */
    public func signDocumentViewModel(): SignDocumentViewModel {
        SignDocumentViewModel(
            router: this.router,
            // iOS: DocumentSignInteractorImpl(configLogic:) — the lazy EudiRQESUi
            // registration + initiate + present live in the RqesSigningLauncher
            // closure installed in init above.
            interactor: DocumentSignInteractorImpl()
        )
    }

    // ── RQES signing flow ViewModels (eudi_feature_rqes). Each wraps a fresh RQESInteractor
    //    over the shared EudiRQESUi (lazily registered by DocumentSignInteractor
    //    on the first signing initiation); iOS builds these in RouterGraph.nextView.
    public func rqesDocumentSelectionViewModel(): DocumentSelectionViewModel {
        DocumentSelectionViewModel(router: this.router, interactor: makeRQESInteractor())
    }
    public func rqesServiceSelectionViewModel(): ServiceSelectionViewModel {
        ServiceSelectionViewModel(router: this.router, interactor: makeRQESInteractor())
    }
    public func rqesCredentialSelectionViewModel(): CredentialSelectionViewModel {
        CredentialSelectionViewModel(router: this.router, interactor: makeRQESInteractor())
    }
    public func rqesSignedDocumentViewModel(): SignedDocumentViewModel {
        SignedDocumentViewModel(router: this.router, interactor: makeRQESInteractor())
    }
    public func rqesDocumentViewerViewModel(): DocumentViewerViewModel {
        DocumentViewerViewModel(router: this.router, interactor: makeRQESInteractor())
    }

    /** Fresh IssuanceOptionViewModel (no interactor; pure navigation). */
    public func issuanceOptionViewModel(): IssuanceOptionViewModel {
        IssuanceOptionViewModel(router: this.router)
    }

    // ── feature-issuance ViewModels (iOS FeatureIssuanceAssembly) ──────────────

    /** Fresh AddDocumentViewModel for the given issuance flow. */
    public func addDocumentViewModel(flow!: IssuanceFlow): AddDocumentViewModel {
        AddDocumentViewModel(
            router: this.router,
            interactor: AddDocumentInteractorImpl(walletController: this.walletController),
            flow: flow
        )
    }

    /** Fresh DocumentOfferViewModel for a resolved credential-offer URI. */
    public func documentOfferViewModel(offerUri!: String): DocumentOfferViewModel {
        DocumentOfferViewModel(
            router: this.router,
            interactor: DocumentOfferInteractorImpl(
                walletController: this.walletController,
                configLogic: this.configLogic
            ),
            offerUri: offerUri
        )
    }

    /** Fresh OfferCodeViewModel for a tx-code issuance config. */
    public func offerCodeViewModel(config!: IssuanceCodeUiConfig): OfferCodeViewModel {
        OfferCodeViewModel(
            router: this.router,
            interactor: DocumentOfferInteractorImpl(
                walletController: this.walletController,
                configLogic: this.configLogic
            ),
            config: config
        )
    }

    /** Fresh DocumentIssuanceSuccessViewModel from the issuance-success config. */
    public func documentIssuanceSuccessViewModel(
        config!: DocumentIssuanceSuccessUIConfig
    ): DocumentIssuanceSuccessViewModel {
        DocumentIssuanceSuccessViewModel(router: this.router, config: config)
    }

    // ── feature-presentation ViewModels (iOS FeaturePresentationAssembly) ──────

    /** The presentation scanner config (online OpenID4VP). */
    public func presentationScannerConfig(): ScannerUiConfig {
        ScannerUiConfig(flow: ScannerFlow.FlowPresentation)
    }

    /**
     * Online presentation entry: start a cross-device OpenID4VP presentation from
     * the scanned request URL, stash the coordinator and build the request VM.
     * Mirrors iOS PresentationRouter.presentationRequest wiring.
     */
    public func presentationRequestViewModel(requestUri!: String): PresentationRequestViewModel {
        let coordinator = this.walletController.startCrossDevicePresentation(requestUri)
        this.activeRemoteCoordinator = Some(coordinator)
        // Share this interactor with the loader VM so the verifier name / trust /
        // disclosed-document titles captured in onDeviceEngagement survive to the
        // success page (they are cached on the interactor, not the coordinator).
        let interactor = PresentationInteractorImpl(
            coordinator: coordinator,
            walletController: this.walletController
        )
        this.activePresentationInteractor = Some(interactor)
        return PresentationRequestViewModel(router: this.router, interactor: interactor)
    }

    /** Loader VM reusing the active remote coordinator (iOS presentationLoader). */
    public func presentationLoaderViewModel(): PresentationLoaderViewModel {
        let coordinator = this.requireRemoteCoordinator()
        let interactor: PresentationInteractor = match (this.activePresentationInteractor) {
            case Some(itr) => itr
            case None => PresentationInteractorImpl(
                coordinator: coordinator,
                walletController: this.walletController
            )
        }
        return PresentationLoaderViewModel(router: this.router, interactor: interactor)
    }

    /** Success VM from the loader's DocumentSuccessUIConfig. */
    public func presentationSuccessViewModel(config!: DocumentSuccessUIConfig): PresentationSuccessViewModel {
        PresentationSuccessViewModel(router: this.router, config: config)
    }

    private func requireRemoteCoordinator(): RemoteSessionCoordinator {
        match (this.activeRemoteCoordinator) {
            case Some(c) => c
            // No active session — start a fresh empty cross-device flow so the
            // loader fails honestly (invalid state) rather than crashing.
            case None =>
                let c = this.walletController.startCrossDevicePresentation("")
                this.activeRemoteCoordinator = Some(c)
                c
        }
    }

    // ── feature-proximity ViewModels (iOS FeatureProximityAssembly) ────────────

    /**
     * In-person presentation entry: start a BLE proximity presentation, stash the
     * coordinator and build the connection VM. Mirrors iOS
     * ProximityRouter.proximityConnection wiring.
     */
    public func proximityConnectionViewModel(): ProximityConnectionViewModel {
        let coordinator = this.walletController.startProximityPresentation()
        this.activeProximityCoordinator = Some(coordinator)
        let interactor = ProximityInteractorImpl(
            coordinator: coordinator,
            walletController: this.walletController
        )
        this.activeProximityInteractor = Some(interactor)
        return ProximityConnectionViewModel(router: this.router, interactor: interactor)
    }

    /** Request VM reusing the active proximity coordinator + interactor. */
    public func proximityRequestViewModel(): ProximityRequestViewModel {
        ProximityRequestViewModel(router: this.router, interactor: this.requireProximityInteractor())
    }

    /** Loader VM reusing the active proximity coordinator + interactor. */
    public func proximityLoaderViewModel(): ProximityLoaderViewModel {
        ProximityLoaderViewModel(router: this.router, interactor: this.requireProximityInteractor())
    }

    /** Success VM from the loader's DocumentSuccessUIConfig. */
    public func proximitySuccessViewModel(config!: DocumentSuccessUIConfig): ProximitySuccessViewModel {
        ProximitySuccessViewModel(router: this.router, config: config)
    }

    private func requireProximityInteractor(): ProximityInteractor {
        match (this.activeProximityInteractor) {
            case Some(itr) => itr
            case None =>
                let itr = ProximityInteractorImpl(
                    coordinator: this.requireProximityCoordinator(),
                    walletController: this.walletController
                )
                this.activeProximityInteractor = Some(itr)
                itr
        }
    }

    private func requireProximityCoordinator(): ProximitySessionCoordinator {
        match (this.activeProximityCoordinator) {
            case Some(c) => c
            case None =>
                let c = this.walletController.startProximityPresentation()
                this.activeProximityCoordinator = Some(c)
                c
        }
    }
}
