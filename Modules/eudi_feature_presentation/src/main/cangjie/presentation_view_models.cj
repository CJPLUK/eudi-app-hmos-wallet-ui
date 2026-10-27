/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-presentation
 * module (UI/Presentation/Request/PresentationRequestViewModel.swift,
 * UI/Presentation/Loading/PresentationLoadingViewModel.swift,
 * UI/Presentation/Success/PresentationSuccessViewModel.swift) to Cangjie.
 *
 * ViewModels extend eudi_logic_ui.BaseViewModel<S> exactly like the delivered
 * features. Each holds an immutable ViewState reduced via setState; views
 * subscribe through onStateChange and marshal @State writes with spawn(UIThread).
 * No ArkUI import here (UI-free seam). Blocking engine calls run on a background
 * thread (the view wraps the VM call in spawn{}); the VM stays synchronous and
 * pushes routes / sets state.
 */
package eudi_feature_presentation

import std.collection.ArrayList
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, NavArgs,
    RouteConfigArgs, DeepLinkNavigationType, ThreeWayNavigationType
}
import eudi_logic_core.PresentationState
import eudi_feature_common.{
    RequestViewModel, RequestViewState, RequestDataCell, RequestDataSection,
    DocumentSuccessUIConfig, SuccessUIConfig, SuccessTitle, SuccessButton,
    SuccessButtonStyle, BiometricUiConfig, dispatchDeepLinkNavigation
}
import eudi_logic_resources.LocalizableStringKey

// ─── PresentationRequest ─────────────────────────────────────────────────────

/** Mirrors iOS presentation `RequestViewState` (subset the screen renders). */
public class PresentationRequestState <: ViewState {
    public let isLoading: Bool
    public let hasError: Bool
    public let errorMessage: String
    /** Blocking "Presentation blocked" sheet: the relying party could not be
     *  verified (iOS `.notSecuredRequest`). Not a retryable error. */
    public let isNotSecuredRequest: Bool

    public init(
        isLoading!: Bool = true,
        hasError!: Bool = false,
        errorMessage!: String = "",
        isNotSecuredRequest!: Bool = false
    ) {
        this.isLoading = isLoading
        this.hasError = hasError
        this.errorMessage = errorMessage
        this.isNotSecuredRequest = isNotSecuredRequest
    }
}

/**
 * Mirrors iOS `PresentationRequestViewModel` (a BaseRequestViewModel subclass).
 * Owns the shared feature-common RequestViewModel that drives BaseRequestView,
 * plus the interactor that talks to the RemoteSessionCoordinator.
 */
public class PresentationRequestViewModel <: BaseViewModel<PresentationRequestState> {
    private let interactor: PresentationInteractor
    /** The shared request screen model (sections + selection). */
    public let requestModel: RequestViewModel

    public init(router!: RouterHost, interactor!: PresentationInteractor) {
        super(router, PresentationRequestState(isLoading: true))
        this.interactor = interactor
        this.requestModel = RequestViewModel(router: router)
    }

    /** Mirrors iOS `doWork()`: device-engagement → request-received → render. */
    public func doWork(): Unit {
        this.setState({ _ => PresentationRequestState(isLoading: true) })
        let result = this.interactor.onDeviceEngagement()
        if (result.isSuccess) {
            // iOS presentation → onReceivedCombinations (may be > 1 combination → radio).
            this.requestModel.onReceivedCombinations(
                relyingParty: result.relyingParty,
                relyingPartyIsTrusted: result.isTrusted,
                combinations: result.combinations
            )
            // iOS: onReceivedItems then onReceivedRegistration — the registration
            // header/warning override the raw reader-cert name/badge.
            match (result.relyingPartyRegistration) {
                case Some(registration) => this.requestModel.onReceivedRegistration(registration)
                case None => ()
            }
            this.setState({ _ => PresentationRequestState(isLoading: false) })
        } else if (result.isNotSecuredRequest) {
            // iOS onTrustBlocked(): the shared request model clears its payload
            // and raises the trust-blocked alert (rendered by BaseRequestView);
            // stopping the presentation session belongs to this feature VM.
            this.requestModel.onTrustBlocked()
            this.interactor.stopPresentation()
            this.setState({ _ => PresentationRequestState(isLoading: false, isNotSecuredRequest: true) })
        } else {
            this.setState({ _ => PresentationRequestState(isLoading: false, hasError: true, errorMessage: result.errorMessage) })
            // iOS: a failed request still shows WHO asked when the verifier's
            // registration policy was captured.
            match (this.interactor.registrationForFailedRequest()) {
                case Some(registration) => this.requestModel.onReceivedRegistration(registration)
                case None => ()
            }
        }
    }

    public func dismissNotSecuredRequest(): Unit {
        this.setState({ _ => PresentationRequestState(isLoading: false) })
        this.onCancel()
    }

    /** Mirrors iOS `onShare()`: prepare the selected disclosure, then require
     * biometric/PIN authentication before the loader sends the response. */
    public func onShare(selected: ArrayList<RequestDataCell>): Unit {
        if (!this.interactor.onResponsePrepare(selected)) {
            this.setState({ s => PresentationRequestState(isLoading: false, hasError: true, errorMessage: presentationInvalidStateText()) })
            return
        }
        let authConfig = BiometricUiConfig(
            navigationTitle: LocalizableStringKey.biometryConfirmRequest,
            caption: LocalizableStringKey.requestDataShareBiometryCaption,
            quickPinOnlyCaption: LocalizableStringKey.requestDataShareQuickPinCaption,
            pinTextFieldTitle: Some(LocalizableStringKey.enterYourPin),
            navigationSuccessType: ThreeWayNavigationType.ThreeWayPushInFlow(
                AppRoutes.presentationLoader
            ),
            navigationBackType: Some(ThreeWayNavigationType.ThreeWayPop),
            isPreAuthorization: false,
            shouldInitializeBiometricOnCreate: true
        )
        NavArgs.shared.set(AppRoutes.biometry, RouteConfigArgs(authConfig))
        this.router.push(AppRoutes.biometry)
    }

    public func onCancel(): Unit {
        this.interactor.stopPresentation()
        this.router.pop()
    }

    public func dismissError(): Unit {
        this.setState({ _ => PresentationRequestState(isLoading: false) })
    }
}

// ─── PresentationLoader ──────────────────────────────────────────────────────

/** Mirrors iOS presentation loading `ViewState`. */
public class PresentationLoaderState <: ViewState {
    public let isLoading: Bool
    public let hasError: Bool
    public let errorMessage: String

    public init(isLoading!: Bool = true, hasError!: Bool = false, errorMessage!: String = "") {
        this.isLoading = isLoading
        this.hasError = hasError
        this.errorMessage = errorMessage
    }
}

/**
 * Mirrors iOS `PresentationLoadingViewModel`: sends the prepared response and
 * subscribes to the coordinator state stream; `.responseSent` → success route,
 * `.error` → error state. The stream subscription replays the current value, so
 * registering the sink before/after sendResponse both observe the transition.
 */
public class PresentationLoaderViewModel <: BaseViewModel<PresentationLoaderState> {
    private let interactor: PresentationInteractor

    public init(router!: RouterHost, interactor!: PresentationInteractor) {
        super(router, PresentationLoaderState(isLoading: true))
        this.interactor = interactor
    }

    /** Mirrors iOS `doWork()` + `subscribeToCoordinatorPublisher()`. Blocking;
     *  view wraps in spawn. */
    public func doWork(): Unit {
        match (this.interactor.getStream()) {
            case Some(stream) =>
                let self0 = this
                stream.sink({ state =>
                    self0.handleState(state)
                })
            case None => ()
        }
        let result = this.interactor.onSendResponse()
        match (result) {
            case ResponseSent => ()
            case ResponseFailure(message) =>
                this.setState({ _ => PresentationLoaderState(isLoading: false, hasError: true, errorMessage: message) })
        }
    }

    private func handleState(state: PresentationState): Unit {
        match (state) {
            case responseSent(url) =>
                this.interactor.stopPresentation()
                this.routeToSuccess(url)
            case error(e) =>
                this.setState({ _ => PresentationLoaderState(isLoading: false, hasError: true, errorMessage: presentationErrorText(e)) })
            case _ => ()
        }
    }

    private func routeToSuccess(redirectUrl: ?String): Unit {
        // Surface the verifier name + trust + shared-document titles so the
        // success page renders the iOS DocumentSuccessView-style document list
        // ("You successfully shared … with ✓ <verifier>" + doc cards).
        //
        // Mirrors iOS `PresentationLoadingViewModel.getOnSuccessRoute(with:)` →
        // `DocumentSuccessViewModel.onDone` `.deepLink` case: when the verifier
        // returns a redirect (the RQES service/credential authorization's
        // wallet-centric OpenID4VP), Done pops to dashboard AND opens the
        // redirect. The QTSP callback (walletcentric …/oid4vp/callback?
        // response_code) 302-continues the OAuth to rqes://oauth/callback?code,
        // which deep-links the app back → handleDeepLink → rqesResume → next
        // RQES step. A plain presentation (no redirect) just pops to dashboard.
        let successNavigation = match (redirectUrl) {
            case Some(u) where !u.isEmpty() =>
                DeepLinkNavigationType.DeepLinkOpen(u, AppRoutes.dashboard)
            case _ =>
                DeepLinkNavigationType.DeepLinkPop(AppRoutes.dashboard, false)
        }
        let name = this.interactor.lastRelyingPartyName()
        let config = DocumentSuccessUIConfig(
            successNavigation: successNavigation,
            relyingParty: if (name.isEmpty()) { Option<String>.None } else { Some(name) },
            relyingPartyIsTrusted: this.interactor.lastRelyingPartyTrusted(),
            isIssuingDocument: false,
            docTitles: this.interactor.lastDisclosedDocLabels(),
            docSections: this.interactor.lastDisclosedSections()
        )
        NavArgs.shared.set(AppRoutes.presentationSuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.presentationSuccess)
    }

    public func onCancel(): Unit {
        this.interactor.stopPresentation()
        this.router.popTo(AppRoutes.dashboard)
    }

    public func dismissError(): Unit {
        this.interactor.stopPresentation()
        this.router.popTo(AppRoutes.dashboard)
    }
}

// ─── PresentationSuccess ─────────────────────────────────────────────────────

/** Mirrors iOS presentation success `ViewState`. */
public class PresentationSuccessState <: ViewState {
    public let config: SuccessUIConfig
    public init(config!: SuccessUIConfig) {
        this.config = config
    }
}

/**
 * Mirrors iOS `PresentationSuccessViewModel` (a DocumentSuccessViewModel
 * subclass). Drives the generic SuccessView from the DocumentSuccessUIConfig
 * left in NavArgs by the loader.
 */
public class PresentationSuccessViewModel <: BaseViewModel<PresentationSuccessState> {
    // Retained so the view can render the iOS DocumentSuccessView-style document
    // list (verifier + trust badge + shared-document cards).
    public let docConfig: DocumentSuccessUIConfig

    public init(router!: RouterHost, config!: DocumentSuccessUIConfig) {
        super(router, PresentationSuccessState(config: presentationSuccessConfig(config)))
        this.docConfig = config
    }

    public func onDone(): Unit {
        dispatchDeepLinkNavigation(this.router, this.docConfig.successNavigation)
    }
}

/** Builds the generic success config (icon/title/button) from the presentation
 *  DocumentSuccessUIConfig, mirroring iOS DocumentSuccessView mapping. */
func presentationSuccessConfig(doc: DocumentSuccessUIConfig): SuccessUIConfig {
    SuccessUIConfig(
        title: SuccessTitle(value: LocalizableStringKey.success),
        subtitle: LocalizableStringKey.dataShared,
        buttons: [
            SuccessButton(
                title: LocalizableStringKey.okButton,
                style: SuccessButtonStyle.StylePrimary,
                navigationType: doc.successNavigation
            )
        ]
    )
}
