/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-proximity
 * module (Interactor/ProximityInteractor.swift) to Cangjie for the EUDI
 * HarmonyOS wallet.
 *
 * Pure business-logic seam over a ProximitySessionCoordinator (logic-core) + the
 * WalletKitController. UI-free. The QR engagement + BLE transfer are driven by
 * the real wallet-kit BLE presentation service through the coordinator
 * (initialize / startQrEngagement / requestReceived / sendResponse). The request
 * decode and response build are shared with feature-presentation via the
 * feature-common request bridge. One interactor instance is shared by the
 * connection / request / loader view-models (composition root) so the verifier
 * name + disclosed-document titles captured on the request screen reach the
 * transaction log written once the response is sent.
 */
package eudi_feature_proximity

import std.collection.{ArrayList, HashMap}
import eudi_logic_core.*
import eudi_feature_common.{
    RequestDataCell, RequestReceivedModel, ClaimRef,
    buildRequestReceivedModel, buildRequestConvertible
}

/** Mirrors iOS `ProximityQrCodePartialState` — success carries the
 *  device-engagement payload the ArkUI QRCode component renders (iOS: UIImage). */
public enum QrGenerationResult {
    | QrSuccess(String)
    | QrFailure(String)
}

/** Mirrors iOS `ProximityDeviceEngagementPartialState`. */
public enum DeviceEngagementResult {
    | EngagementSuccess
    | EngagementFailure(String)
}

/** Mirrors iOS `ProximityResponsePartialState`. */
public enum ProximitySentResult {
    | ProximitySent
    | ProximitySendFailure(String)
}

/**
 * Mirrors iOS `ProximityPublisherPartialState` — the Result of asking the active
 * coordinator for its state stream. success = got the stream, failure = the
 * coordinator threw while producing it.
 */
public enum ProximityPublisherResult {
    | ProximityPublisherSuccess(SendableCurrentValueSubject<PresentationState>)
    | ProximityPublisherFailure(String)
}

/**
 * Mirrors iOS `ProximityCoordinatorPartialState` — the Result of resolving the
 * active coordinator. iOS fetches it through a SessionCoordinatorHolder that can
 * throw; Cangjie injects the coordinator directly, so "failure" here means the
 * injected coordinator is non-operational (its liveness probe throws) — the
 * direct-injection equivalent of iOS's holder failing to hand back a coordinator.
 */
public enum ProximityCoordinatorResult {
    | ProximityCoordinatorSuccess(ProximitySessionCoordinator)
    | ProximityCoordinatorFailure(String)
}

/** Mirrors iOS `ProximityInteractor` protocol. */
public interface ProximityInteractor {
    func getStream(): ?SendableCurrentValueSubject<PresentationState>
    /**
     * Result-style equivalent of iOS `getSessionStatePublisher()`: success wraps
     * the coordinator's state stream, failure carries the error text.
     */
    func getSessionStatePublisher(): ProximityPublisherResult
    /**
     * Result-style equivalent of iOS `getCoordinator()`: success wraps the active
     * coordinator, failure carries the error text when it is non-operational.
     */
    func getCoordinator(): ProximityCoordinatorResult
    func onDeviceEngagement(): DeviceEngagementResult
    func onQRGeneration(): QrGenerationResult
    func onRequestReceived(): RequestReceivedModel
    /** iOS `registrationForFailedRequest()`: the verifier registration for a
     *  request that failed to resolve — shows WHO asked even when the request
     *  is unsatisfiable. `None` when no registration policy was captured. */
    func registrationForFailedRequest(): ?RelyingPartyRegistration
    func onResponsePrepare(selected: ArrayList<RequestDataCell>): Bool
    func onSendResponse(): ProximitySentResult
    func stopPresentation(): Unit
}

/** Mirrors iOS `final actor ProximityInteractorImpl`. */
public class ProximityInteractorImpl <: ProximityInteractor {
    private let coordinator: ProximitySessionCoordinator
    private let walletController: WalletKitController
    private let claimIndex: HashMap<String, ClaimRef> = HashMap<String, ClaimRef>()
    // Captured on the request screen for the transaction log (WP7): the
    // registration-resolved verifier name (WRPRC name, else the reader-cert
    // name) and the disclosed-document titles.
    private var lastRelyingParty: String = ""
    private var lastDocLabels: Array<String> = Array<String>()

    public init(coordinator!: ProximitySessionCoordinator, walletController!: WalletKitController) {
        this.coordinator = coordinator
        this.walletController = walletController
    }

    public func getStream(): ?SendableCurrentValueSubject<PresentationState> {
        try {
            return Some(this.coordinator.getStream())
        } catch (_: Exception) {
            return None
        }
    }

    public func getSessionStatePublisher(): ProximityPublisherResult {
        try {
            return ProximityPublisherResult.ProximityPublisherSuccess(this.coordinator.getStream())
        } catch (e: Exception) {
            return ProximityPublisherResult.ProximityPublisherFailure(proximityErrorText(e))
        }
    }

    public func getCoordinator(): ProximityCoordinatorResult {
        // Direct-injection design: no holder can fail to return the coordinator.
        // Probe its liveness (getStream) to distinguish an operational coordinator
        // (success) from a non-operational injected one (failure) — the equivalent
        // of iOS's holder.getActiveProximityCoordinator() succeeding vs. throwing.
        try {
            this.coordinator.getStream()
            return ProximityCoordinatorResult.ProximityCoordinatorSuccess(this.coordinator)
        } catch (e: Exception) {
            return ProximityCoordinatorResult.ProximityCoordinatorFailure(proximityErrorText(e))
        }
    }

    public func onDeviceEngagement(): DeviceEngagementResult {
        try {
            this.coordinator.initialize()
            return DeviceEngagementResult.EngagementSuccess
        } catch (e: Exception) {
            return DeviceEngagementResult.EngagementFailure(proximityErrorText(e))
        }
    }

    public func onQRGeneration(): QrGenerationResult {
        try {
            let payload = this.coordinator.startQrEngagement()
            return QrGenerationResult.QrSuccess(payload)
        } catch (e: Exception) {
            return QrGenerationResult.QrFailure(proximityErrorText(e))
        }
    }

    public func onRequestReceived(): RequestReceivedModel {
        try {
            let request = this.coordinator.requestReceived()
            // Registration-certificate layer (iOS onRequestReceived, mirroring
            // feature-presentation; claims stay selectable in proximity): the
            // over-asked leaf paths mark the "Not registered data" rows, and the
            // combined verdict travels with the success payload. An unsatisfiable
            // request (empty sections) still succeeds so the RP shows.
            let overaskedPaths = this.coordinator.overaskedLeafPathsByDocId()
            let model = buildRequestReceivedModel(
                request, this.walletController, this.claimIndex,
                overaskedPaths: Some(overaskedPaths),
                claimsAreSelectable: true
            )
            let registration = this.walletController.getVerifierRegistration(
                this.coordinator.relyingPartyRegistration,
                this.coordinator.relyingPartyWarningViolations,
                request.overaskedClaims,
                Some(request.relyingParty),
                request.isTrusted
            )
            // Transaction-log inputs (iOS RelyingParty.name = WRPRC name ??
            // reader-cert name): the registration-resolved name wins over the
            // raw reader-cert value, as on the request header.
            this.lastRelyingParty = registration.name ?? model.relyingParty
            let labels = ArrayList<String>()
            for (section in model.sections) {
                labels.add(section.title)
            }
            this.lastDocLabels = labels.toArray()
            return RequestReceivedModel.success(
                relyingParty: model.relyingParty,
                dataRequestInfo: model.dataRequestInfo,
                isTrusted: model.isTrusted,
                combinations: model.combinations,
                relyingPartyRegistration: Some(registration)
            )
        } catch (e: Exception) {
            if (isTrustBlocked(e)) {
                return RequestReceivedModel.notSecuredRequest()
            }
            return RequestReceivedModel.failure(proximityErrorText(e))
        }
    }

    public func registrationForFailedRequest(): ?RelyingPartyRegistration {
        return this.walletController.getVerifierRegistrationForFailedRequest()
    }

    public func onResponsePrepare(selected: ArrayList<RequestDataCell>): Bool {
        let convertible = buildRequestConvertible(selected, this.claimIndex)
        if (convertible.items.isEmpty()) {
            return false
        }
        try {
            this.coordinator.setState(PresentationState.responseToSend(convertible))
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public func onSendResponse(): ProximitySentResult {
        try {
            let state = this.coordinator.getState()
            match (state) {
                case responseToSend(item) =>
                    this.coordinator.sendResponse(item)
                    // Record the completed presentation so it appears in History
                    // (iOS logs it in PresentationSession.sendResponse after the
                    // transport reports ResponseSent; sendResponse above returns
                    // only after that / the reader disconnects). The controller
                    // resolves the presenter CN from the reader chain. Failure
                    // to log must not fail the presentation.
                    let relyingParty = if (this.lastRelyingParty.isEmpty()) {
                        this.coordinator.currentRelyingParty()
                    } else {
                        this.lastRelyingParty
                    }
                    try {
                        this.walletController.logPresentation(relyingParty, this.lastDocLabels)
                    } catch (_: Exception) {}
                    return ProximitySentResult.ProximitySent
                case _ =>
                    return ProximitySentResult.ProximitySendFailure(proximityInvalidStateText())
            }
        } catch (e: Exception) {
            return ProximitySentResult.ProximitySendFailure(proximityErrorText(e))
        }
    }

    public func stopPresentation(): Unit {
        this.walletController.stopPresentation()
        try {
            this.coordinator.stopPresentation()
        } catch (_: Exception) {}
    }
}

// ─── localized text ───────────────────────────────────────────────────────────

func proximityErrorText(e: Exception): String {
    let msg = e.message
    if (msg.isEmpty()) {
        return proximityUnavailableText()
    }
    return msg
}

func proximityUnavailableText(): String { "Proximity sharing is unavailable on this device" }
func proximityInvalidStateText(): String { "Invalid presentation state" }

// ─── standalone-render fallback (no engine wired) ────────────────────────────

/** A no-op interactor for emulator/preview rendering. Mirrors the iOS
 *  "capability unavailable" degradation (no BLE binding) — surfaces a QR/engage
 *  failure rather than faking success. */
public class NoopProximityInteractor <: ProximityInteractor {
    public func getStream(): ?SendableCurrentValueSubject<PresentationState> { None }
    public func getSessionStatePublisher(): ProximityPublisherResult {
        ProximityPublisherResult.ProximityPublisherFailure(proximityUnavailableText())
    }
    public func getCoordinator(): ProximityCoordinatorResult {
        ProximityCoordinatorResult.ProximityCoordinatorFailure(proximityUnavailableText())
    }
    public func onDeviceEngagement(): DeviceEngagementResult {
        DeviceEngagementResult.EngagementFailure(proximityUnavailableText())
    }
    public func onQRGeneration(): QrGenerationResult { QrGenerationResult.QrFailure(proximityUnavailableText()) }
    public func onRequestReceived(): RequestReceivedModel { RequestReceivedModel.failure(proximityUnavailableText()) }
    public func registrationForFailedRequest(): ?RelyingPartyRegistration { None }
    public func onResponsePrepare(_: ArrayList<RequestDataCell>): Bool { false }
    public func onSendResponse(): ProximitySentResult { ProximitySentResult.ProximitySendFailure(proximityUnavailableText()) }
    public func stopPresentation(): Unit {}
}
