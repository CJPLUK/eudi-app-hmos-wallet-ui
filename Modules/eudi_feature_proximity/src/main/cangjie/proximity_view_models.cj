/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-proximity
 * module (UI/Connectivity/ProximityConnectionViewModel.swift,
 * UI/Presentation/Request|Loading|Success/Proximity*ViewModel.swift) to Cangjie.
 *
 * ViewModels extend eudi_logic_ui.BaseViewModel<S>. UI-free seam; views
 * subscribe through onStateChange and marshal @State writes with spawn(UIThread).
 * BLE peripheral setup for the connection screen runs on the UI thread. The
 * coordinator moves its blocking request wait to a background thread.
 */
package eudi_feature_proximity

import std.collection.ArrayList
import eudi_logic_ui.{
    BaseViewModel, ViewState, RouterHost, AppRoutes, NavArgs,
    RouteConfigArgs, DeepLinkNavigationType, ThreeWayNavigationType
}
import eudi_logic_core.PresentationState
import eudi_feature_common.{
    RequestViewModel, RequestDataCell, RequestDataSection,
    DocumentSuccessUIConfig, SuccessUIConfig, SuccessTitle, SuccessButton, SuccessButtonStyle,
    BiometricUiConfig
}
import eudi_logic_resources.LocalizableStringKey

// ─── ProximityConnection ─────────────────────────────────────────────────────

/**
 * Mirrors iOS `ProxmityConnectivityState` (qrImage / error). iOS holds the
 * rendered UIImage; here `qrPayload` is the device-engagement string
 * ("mdoc:" + base64url(CBOR)) the ArkUI QRCode component renders.
 */
public class ProximityConnectionState <: ViewState {
    public let hasQr: Bool
    public let qrPayload: String
    public let hasError: Bool
    public let errorMessage: String

    public init(
        hasQr!: Bool = false,
        qrPayload!: String = "",
        hasError!: Bool = false,
        errorMessage!: String = ""
    ) {
        this.hasQr = hasQr
        this.qrPayload = qrPayload
        this.hasError = hasError
        this.errorMessage = errorMessage
    }
}

/**
 * Mirrors iOS `ProximityConnectionViewModel`: initialise the BLE engagement and
 * subscribe to the coordinator state stream. `.prepareQr` → generate the QR
 * payload; `.qrReady` → show it; `.requestReceived` → push the request screen;
 * `.error` → error state.
 */
public class ProximityConnectionViewModel <: BaseViewModel<ProximityConnectionState> {
    private let interactor: ProximityInteractor

    public init(router!: RouterHost, interactor!: ProximityInteractor) {
        super(router, ProximityConnectionState())
        this.interactor = interactor
    }

    /** Mirrors iOS `initialize()`. Returns after BLE engagement is prepared. */
    public func initialize(): Unit {
        match (this.interactor.getStream()) {
            case Some(stream) =>
                let self0 = this
                stream.sink({ state => self0.handleState(state) })
            case None => ()
        }
        match (this.interactor.onDeviceEngagement()) {
            case EngagementSuccess => ()
            case EngagementFailure(message) =>
                this.setState({ _ => ProximityConnectionState(hasError: true, errorMessage: message) })
        }
    }

    private func handleState(state: PresentationState): Unit {
        match (state) {
            case prepareQr => this.generateQr()
            case qrReady(payload) => this.setState({ _ => ProximityConnectionState(hasQr: true, qrPayload: payload) })
            case requestReceived(_) => this.onConnectionSuccess()
            case error(e) =>
                this.setState({ _ => ProximityConnectionState(hasError: true, errorMessage: proximityErrorText(e)) })
            case _ => ()
        }
    }

    private func generateQr(): Unit {
        match (this.interactor.onQRGeneration()) {
            case QrSuccess(payload) => this.setState({ _ => ProximityConnectionState(hasQr: true, qrPayload: payload) })
            case QrFailure(message) =>
                this.setState({ _ => ProximityConnectionState(hasError: true, errorMessage: message) })
        }
    }

    private func onConnectionSuccess(): Unit {
        this.router.push(AppRoutes.proximityRequest)
    }

    public func onCancel(): Unit {
        this.interactor.stopPresentation()
        this.router.pop()
    }

    public func dismissError(): Unit {
        this.interactor.stopPresentation()
        this.router.pop()
    }
}

// ─── ProximityRequest ────────────────────────────────────────────────────────

/** Mirrors iOS proximity request `ViewState`. */
public class ProximityRequestState <: ViewState {
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

/** Mirrors iOS `ProximityRequestViewModel`. */
public class ProximityRequestViewModel <: BaseViewModel<ProximityRequestState> {
    private let interactor: ProximityInteractor
    public let requestModel: RequestViewModel

    public init(router!: RouterHost, interactor!: ProximityInteractor) {
        super(router, ProximityRequestState(isLoading: true))
        this.interactor = interactor
        this.requestModel = RequestViewModel(router: router)
    }

    public func doWork(): Unit {
        this.setState({ _ => ProximityRequestState(isLoading: true) })
        let result = this.interactor.onRequestReceived()
        if (result.isSuccess) {
            // iOS proximity uses itemSets.first (always a single combination, per-claim
            // checkboxes) — no combination radio.
            let firstCombination = if (result.combinations.size > 0) {
                result.combinations[0]
            } else {
                ArrayList<RequestDataSection>()
            }
            this.requestModel.onReceivedItems(
                relyingParty: result.relyingParty,
                relyingPartyIsTrusted: result.isTrusted,
                sections: firstCombination
            )
            // iOS: onReceivedItems then onReceivedRegistration — the registration
            // header/warning override the raw reader-cert name/badge.
            match (result.relyingPartyRegistration) {
                case Some(registration) => this.requestModel.onReceivedRegistration(registration)
                case None => ()
            }
            this.setState({ _ => ProximityRequestState(isLoading: false) })
        } else if (result.isNotSecuredRequest) {
            // iOS onTrustBlocked(): the shared request model clears its payload
            // and raises the trust-blocked alert (rendered by BaseRequestView);
            // stopping the presentation session belongs to this feature VM.
            this.requestModel.onTrustBlocked()
            this.interactor.stopPresentation()
            this.setState({ _ => ProximityRequestState(isLoading: false, isNotSecuredRequest: true) })
        } else {
            this.setState({ _ => ProximityRequestState(isLoading: false, hasError: true, errorMessage: result.errorMessage) })
            // iOS: a failed request still shows WHO asked when the verifier's
            // registration policy was captured.
            match (this.interactor.registrationForFailedRequest()) {
                case Some(registration) => this.requestModel.onReceivedRegistration(registration)
                case None => ()
            }
        }
    }

    public func dismissNotSecuredRequest(): Unit {
        this.interactor.stopPresentation()
        this.router.pop()
    }

    public func onShare(selected: ArrayList<RequestDataCell>): Unit {
        if (!this.interactor.onResponsePrepare(selected)) {
            this.setState({ _ => ProximityRequestState(isLoading: false, hasError: true, errorMessage: proximityInvalidStateText()) })
            return
        }
        // iOS prepares the filtered disclosure, then routes through the shared
        // biometric/PIN gate before the loader is allowed to send it.
        let authConfig = BiometricUiConfig(
            navigationTitle: LocalizableStringKey.biometryConfirmRequest,
            caption: LocalizableStringKey.requestDataShareBiometryCaption,
            quickPinOnlyCaption: LocalizableStringKey.requestDataShareQuickPinCaption,
            pinTextFieldTitle: Some(LocalizableStringKey.enterYourPin),
            navigationSuccessType: ThreeWayNavigationType.ThreeWayPushInFlow(AppRoutes.proximityLoader),
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
        this.setState({ _ => ProximityRequestState(isLoading: false) })
    }
}

// ─── ProximityLoader ─────────────────────────────────────────────────────────

/** Mirrors iOS proximity loading `ViewState`. */
public class ProximityLoaderState <: ViewState {
    public let isLoading: Bool
    public let hasError: Bool
    public let errorMessage: String

    public init(isLoading!: Bool = true, hasError!: Bool = false, errorMessage!: String = "") {
        this.isLoading = isLoading
        this.hasError = hasError
        this.errorMessage = errorMessage
    }
}

/** Mirrors iOS `ProximityLoadingViewModel`. */
public class ProximityLoaderViewModel <: BaseViewModel<ProximityLoaderState> {
    private let interactor: ProximityInteractor

    public init(router!: RouterHost, interactor!: ProximityInteractor) {
        super(router, ProximityLoaderState(isLoading: true))
        this.interactor = interactor
    }

    public func doWork(): Unit {
        match (this.interactor.getStream()) {
            case Some(stream) =>
                let self0 = this
                stream.sink({ state => self0.handleState(state) })
            case None => ()
        }
        match (this.interactor.onSendResponse()) {
            case ProximitySent => ()
            case ProximitySendFailure(message) =>
                this.setState({ _ => ProximityLoaderState(isLoading: false, hasError: true, errorMessage: message) })
        }
    }

    private func handleState(state: PresentationState): Unit {
        match (state) {
            case responseSent(_) =>
                this.interactor.stopPresentation()
                this.routeToSuccess()
            case error(e) =>
                this.setState({ _ => ProximityLoaderState(isLoading: false, hasError: true, errorMessage: proximityErrorText(e)) })
            case _ => ()
        }
    }

    private func routeToSuccess(): Unit {
        let config = DocumentSuccessUIConfig(
            successNavigation: DeepLinkNavigationType.DeepLinkPop(AppRoutes.dashboard, false),
            relyingParty: Option<String>.None,
            relyingPartyIsTrusted: false,
            isIssuingDocument: false
        )
        NavArgs.shared.set(AppRoutes.proximitySuccess, RouteConfigArgs(config))
        this.router.push(AppRoutes.proximitySuccess)
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

// ─── ProximitySuccess ────────────────────────────────────────────────────────

/** Mirrors iOS proximity success `ViewState`. */
public class ProximitySuccessState <: ViewState {
    public let config: SuccessUIConfig
    public init(config!: SuccessUIConfig) {
        this.config = config
    }
}

/** Mirrors iOS `ProximitySuccessViewModel`. */
public class ProximitySuccessViewModel <: BaseViewModel<ProximitySuccessState> {
    public init(router!: RouterHost, config!: DocumentSuccessUIConfig) {
        super(router, ProximitySuccessState(config: proximitySuccessConfig(config)))
    }
}

func proximitySuccessConfig(doc: DocumentSuccessUIConfig): SuccessUIConfig {
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
