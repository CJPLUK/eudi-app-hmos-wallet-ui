/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Coordinator/(all).swift:
 *   PresentationRequest, PresentationState, SessionCoordinatorHolder,
 *   ProximitySessionCoordinator, RemoteSessionCoordinator and the
 *   SendableCurrentValueSubject / SendableAnyCancellable Combine shims.
 *
 * iOS `SendableCurrentValueSubject` (a Combine CurrentValueSubject wrapper from
 * logic-business that is not yet migrated) is reimplemented here as a
 * thread-safe current-value holder with listener callbacks; the iOS `$status`
 * Combine pipeline becomes an explicit observer registered on the PresentationSession.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, AtomicBool}
import kit.PerformanceAnalysisKit.Hilog
import eudi_logic_business.RuntimeError
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.PresentationPolicyViolation
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DisclosedDocumentSet

// ─────────────────────────────────────────────────────────────────────────────
// Combine shims (SendableCurrentValueSubject / SendableAnyCancellable)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `SendableCurrentValueSubject<T>`: holds the latest value, notifies
 * registered sinks on change, and replays the current value to new subscribers.
 */
public class SendableCurrentValueSubject<T> {
    private let lock = Mutex()
    private var value: T
    private var completed = false
    private let listeners = ArrayList<(T) -> Unit>()

    public init(initial: T) {
        this.value = initial
    }

    public func getValue(): T {
        synchronized(lock) { return this.value }
    }

    public func setValue(newValue: T): Unit {
        var snapshot = ArrayList<(T) -> Unit>()
        synchronized(lock) {
            if (this.completed) { return }
            this.value = newValue
            for (l in this.listeners) { snapshot.add(l) }
        }
        for (l in snapshot) {
            try { l(newValue) } catch (_: Exception) {}
        }
    }

    /** Registers a sink, replaying the current value immediately (Combine semantics). */
    public func sink(listener: (T) -> Unit): Unit {
        var current: T
        synchronized(lock) {
            this.listeners.add(listener)
            current = this.value
        }
        listener(current)
    }

    public func complete(): Unit {
        synchronized(lock) {
            this.completed = true
            this.listeners.clear()
        }
    }

    /**
     * Mirrors `getAsyncStream()`. Cangjie has no AsyncStream; the consumer pattern
     * in logic-core only ever reads the latest value, so the stream is represented
     * by the subject itself (subscribe via `sink`). Returns self for fluent use.
     */
    public func getAsyncStream(): SendableCurrentValueSubject<T> {
        return this
    }
}

/** Mirrors iOS `SendableAnyCancellable` (cancels its registered subscriptions). */
public class SendableAnyCancellable {
    private let cancelled = AtomicBool(false)
    public init() {}
    public func cancel(): Unit {
        this.cancelled.store(true)
    }
    public func isCancelled(): Bool {
        return this.cancelled.load()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinator/Model/PresentationRequest.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `PresentationRequest`. */
public struct PresentationRequest <: Equatable<PresentationRequest> {
    public let items: Array<DocElements>
    // iOS `PresentationRequest.itemSets: [[DocElements]]` — each inner array is one
    // "combination" (one candidate document per requested query) that fully satisfies
    // the request. Single-combination requests have exactly one set == `items`.
    public let itemSets: Array<Array<DocElements>>
    public let relyingParty: String
    public let dataRequestInfo: String
    public let isTrusted: Bool
    /** Registration-certificate layer: claims requested beyond the WRPRC. */
    public let overaskedClaims: Array<OveraskedClaim>
    public init(
        items!: Array<DocElements>, relyingParty!: String, dataRequestInfo!: String, isTrusted!: Bool,
        overaskedClaims!: Array<OveraskedClaim> = Array<OveraskedClaim>(),
        itemSets!: Array<Array<DocElements>> = Array<Array<DocElements>>()
    ) {
        this.items = items
        this.itemSets = itemSets
        this.relyingParty = relyingParty
        this.dataRequestInfo = dataRequestInfo
        this.isTrusted = isTrusted
        this.overaskedClaims = overaskedClaims
    }
    public operator func ==(o: PresentationRequest): Bool {
        if (this.relyingParty != o.relyingParty || this.dataRequestInfo != o.dataRequestInfo || this.isTrusted != o.isTrusted) {
            return false
        }
        if (this.items.size != o.items.size) { return false }
        var i = 0
        while (i < this.items.size) {
            if (this.items[i] != o.items[i]) { return false }
            i++
        }
        return true
    }
    public operator func !=(o: PresentationRequest): Bool { !(this == o) }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinator/Model/PresentationState.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `PresentationState`. */
public enum PresentationState {
    | loading
    | prepareQr
    | qrReady(String)                   // device-engagement payload ("mdoc:" + base64url(CBOR)); the view renders it as a QR code
    | requestReceived(PresentationRequest)
    | responseToSend(RequestItemConvertible)
    | responseSent(?String)             // optional redirect URL
    | error(Exception)

    /** Mirrors the iOS `Equatable` conformance. */
    public func equalsState(o: PresentationState): Bool {
        match ((this, o)) {
            case (loading, loading) => true
            case (prepareQr, prepareQr) => true
            case (qrReady(a), qrReady(b)) => a == b
            case (requestReceived(a), requestReceived(b)) => a == b
            case (responseSent(a), responseSent(b)) => optStringEqual(a, b)
            case (error(a), error(b)) => a.message == b.message
            case _ => false
        }
    }
}

func optStringEqual(a: ?String, b: ?String): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => x == y
        case (None, None) => true
        case _ => false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PresentationSession (MdocDataTransfer18013) — the wallet session the coordinators wrap
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors MdocDataTransfer18013 `TransferStatus` — the full ISO 18013-5 session
 * sequence the engine emits: initializing → initialized → poweredOn →
 * qrEngagementReady → connected → started → requestReceived → userSelected →
 * responseSent → disconnected | sessionError. Every step is surfaced here so
 * nothing is dropped at the seam; the coordinators reduce it to the 4-case
 * `PresentationState` UI contract (qrEngagementReady → prepareQr,
 * requestReceived → requestReceived, responseSent → responseSent,
 * sessionError → error), exactly like the iOS `$status` pipeline.
 */
public enum PresentationSessionStatus <: ToString & Equatable<PresentationSessionStatus> {
    | initializing
    | initialized
    | poweredOn
    | qrEngagementReady
    | connected
    | started
    | requestReceived
    | userSelected
    | responseSent
    | disconnected
    | sessionError

    public prop rawValue: String {
        get() {
            match (this) {
                case initializing => "initializing"
                case initialized => "initialized"
                case poweredOn => "poweredOn"
                case qrEngagementReady => "qrEngagementReady"
                case connected => "connected"
                case started => "started"
                case requestReceived => "requestReceived"
                case userSelected => "userSelected"
                case responseSent => "responseSent"
                case disconnected => "disconnected"
                case sessionError => "sessionError"
            }
        }
    }

    public func toString(): String { this.rawValue }

    public operator func ==(o: PresentationSessionStatus): Bool { this.rawValue == o.rawValue }
    public operator func !=(o: PresentationSessionStatus): Bool { !(this == o) }
}

/**
 * Mirrors MdocDataTransfer18013.PresentationSession — the engagement/transfer
 * session the wallet engine drives. eudi_lib_wallet_kit owns both transports
 * (BlePresentationService over the mdoc-transfer GATT server for ISO 18013-5
 * proximity, OpenId4VpService for remote); `EnginePresentationSession`
 * (wallet_kit.cj) adapts the engine session to this interface, which captures
 * exactly the surface the two coordinators consume.
 */
public interface PresentationSession {
    prop status: PresentationSessionStatus
    prop disclosedDocuments: Array<DocElements>
    /**
     * iOS `disclosedDocumentSets.map(\.docElements)` in seam types: one inner
     * array per combination (candidate documents that jointly satisfy the
     * request). Default derives a single combination from the flat list so
     * simple/fake sessions keep working; the engine session overrides it with
     * the real per-set conversion.
     */
    prop disclosedItemSets: Array<Array<DocElements>> {
        get() {
            let d = this.disclosedDocuments
            if (d.size == 0) { return Array<Array<DocElements>>() }
            return [d]
        }
    }
    prop readerCertIssuer: ?String
    prop readerCertValidationMessage: ?String
    prop readerCertIssuerValid: ?Bool
    /** Device-engagement payload ("mdoc:" + base64url(CBOR)) once QR engagement is ready; rendered as the QR code. */
    prop deviceEngagement: ?String
    prop uiErrorDescription: ?String
    /** Registration-certificate layer (wallet-kit 0.40.x): the disclosed
     *  document sets with their per-set WRPRC violations. */
    prop disclosedDocumentSets: Array<DisclosedDocumentSet>
    /** The verifier's decoded WRPRC policy (None when validation is off / absent). */
    prop wrpVerifierPolicy: ?WrpRegistrationPolicy
    /** WRPRC violations keyed by docType/vct; "" holds request-level violations. */
    prop wrpVerifierWarnings: ?HashMap<String, Array<PresentationPolicyViolation>>
    /** Reader/verifier DER certificate chain, leaf first (presenter-name source). */
    prop readerCertificateChain: ?Array<Array<UInt8>>

    /** Combine `$status` analogue: register a status observer. */
    func observeStatus(observer: (PresentationSessionStatus) -> Unit): Unit
    func startQrEngagement(): Unit
    func receiveRequest(): Unit
    /**
     * Send the response; `onSent` fires once — only after the transport reports
     * ResponseSent (the engine's onSuccess), with the optional redirect URL.
     */
    func sendResponse(userAccepted: Bool, itemsToSend: RequestConvertibleItems, onSent: (?String) -> Unit): Unit
    /** Block until the reader disconnects (the engine bounds the wait with a deadline). */
    func waitForDisconnect(): Unit
    /**
     * Stop the session: transport teardown (advertising / GATT server) and
     * ephemeral-key deletion. iOS leaves this to ARC when the session is
     * released; HarmonyOS has no such release, so it is explicit.
     */
    func stop(): Unit
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinator/Wrapper/SessionCoordinatorHolder.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol SessionCoordinatorHolder: Sendable`. */
public interface SessionCoordinatorHolder {
    func clear(): Unit
    func setActiveRemoteCoordinator(coordinator: RemoteSessionCoordinator): Unit
    func setActiveProximityCoordinator(coordinator: ProximitySessionCoordinator): Unit
    func getActiveRemoteCoordinator(): RemoteSessionCoordinator
    func getActiveProximityCoordinator(): ProximitySessionCoordinator
}

/** Mirrors iOS `final actor SessionCoordinatorHolderImpl`. */
public class SessionCoordinatorHolderImpl <: SessionCoordinatorHolder {
    private let lock = Mutex()
    private var activeRemoteCoordinator: ?RemoteSessionCoordinator = None
    private var activeProximityCoordinator: ?ProximitySessionCoordinator = None

    public init() {}

    public func clear(): Unit {
        synchronized(lock) {
            this.activeRemoteCoordinator = None
            this.activeProximityCoordinator = None
        }
    }
    public func setActiveRemoteCoordinator(coordinator: RemoteSessionCoordinator): Unit {
        synchronized(lock) { this.activeRemoteCoordinator = coordinator }
    }
    public func setActiveProximityCoordinator(coordinator: ProximitySessionCoordinator): Unit {
        synchronized(lock) { this.activeProximityCoordinator = coordinator }
    }
    public func getActiveRemoteCoordinator(): RemoteSessionCoordinator {
        synchronized(lock) {
            match (this.activeRemoteCoordinator) {
                case Some(c) => return c
                case None => throw WalletCoreError.unableToPresentAndShare()
            }
        }
    }
    public func getActiveProximityCoordinator(): ProximitySessionCoordinator {
        synchronized(lock) {
            match (this.activeProximityCoordinator) {
                case Some(c) => return c
                case None => throw WalletCoreError.unableToPresentAndShare()
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinator/ProximitySessionCoordinator.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol ProximitySessionCoordinator: Sendable`. */
public interface ProximitySessionCoordinator {
    prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState>
    /** Mirrors `relyingPartyRegistration` — the verifier's WRPRC policy (None
     *  when registration validation is off or no certificate was delivered). */
    prop relyingPartyRegistration: ?WrpRegistrationPolicy
    /** Mirrors `relyingPartyWarningViolations` — the messages of the ""-keyed
     *  (request-level) WRPRC violations: the registration itself failed. */
    prop relyingPartyWarningViolations: Array<String>
    /** Reader DER certificate chain (leaf first), for presenter-name resolution. */
    prop readerCertificateChain: ?Array<Array<UInt8>>
    func initialize(): Unit
    /** Mirrors `startQrEngagement()`: publishes `qrReady` and returns the
     *  device-engagement payload the connection view renders as a QR code. */
    func startQrEngagement(): String
    func requestReceived(): PresentationRequest
    func sendResponse(response: RequestItemConvertible): Unit
    func getState(): PresentationState
    func setState(presentationState: PresentationState): Unit
    func getStream(): SendableCurrentValueSubject<PresentationState>
    func stopPresentation(): Unit
    /** Current verifier display name (for the transaction log); read from the
     *  shared coordinator so it survives the request→loading view-model handoff. */
    func currentRelyingParty(): String
    /** Mirrors iOS `[DocElements].overaskedPaths(from:)` over the session's
     *  disclosed document sets: docId → over-asked leaf claim paths, in the
     *  shape the feature tier hands to request_bridge. */
    func overaskedLeafPathsByDocId(): HashMap<String, Array<Array<String>>>
}

/** Mirrors iOS `final class ProximitySessionCoordinatorImpl`. */
public class ProximitySessionCoordinatorImpl <: ProximitySessionCoordinator {
    private let subject = SendableCurrentValueSubject<PresentationState>(PresentationState.loading)
    private let session: PresentationSession
    private let sendableAnyCancellable = SendableAnyCancellable()

    public init(session: PresentationSession) {
        this.session = session
        let self0 = this
        // iOS `$status` pipeline: the full TransferStatus sequence arrives here;
        // only the four UI-relevant steps become PresentationState values. The
        // transport-level steps (initialized / poweredOn / connected / started /
        // userSelected / disconnected) are observed but carry no UI state.
        this.session.observeStatus({ status =>
            if (self0.sendableAnyCancellable.isCancelled()) { return }
            match (status) {
                case qrEngagementReady => self0.subject.setValue(PresentationState.prepareQr)
                case requestReceived => self0.subject.setValue(PresentationState.requestReceived(self0.createRequest()))
                case responseSent => self0.emitResponseSent(None)
                case sessionError =>
                    match (self0.session.uiErrorDescription) {
                        case Some(msg) => self0.subject.setValue(PresentationState.error(Exception(RuntimeError.customError(msg).localizedDescription)))
                        case None => self0.subject.setValue(PresentationState.error(WalletCoreError.unableToPresentAndShare()))
                    }
                case initializing => ()
                case initialized => ()
                case poweredOn => ()
                case connected => ()
                case started => ()
                case userSelected => ()
                case disconnected => ()
            }
        })
    }

    public prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState> {
        get() { this.subject }
    }

    /** Mirrors `relyingPartyRegistration` = session.wrpVerifierPolicy. */
    public prop relyingPartyRegistration: ?WrpRegistrationPolicy {
        get() { this.session.wrpVerifierPolicy }
    }

    /** Mirrors `relyingPartyWarningViolations` — ""-keyed violation messages. */
    public prop relyingPartyWarningViolations: Array<String> {
        get() { sessionWarningViolationMessages(this.session) }
    }

    public prop readerCertificateChain: ?Array<Array<UInt8>> {
        get() { this.session.readerCertificateChain }
    }

    public func overaskedLeafPathsByDocId(): HashMap<String, Array<Array<String>>> {
        return overaskedPathsByDocId(this.session.disclosedDocumentSets, sessionOveraskedClaims(this.session))
    }

    /**
     * Mirrors `initialize()`: prepare BLE engagement on the caller thread, then
     * wait for the reader off-thread. ConnectivityKit GATT server registration
     * must retain the UI/application event context, while receiveRequest may
     * block for the whole presentation timeout.
     */
    public func initialize(): Unit {
        this.session.startQrEngagement()
        let activeSession = this.session
        spawn { => activeSession.receiveRequest() }
    }

    /**
     * Mirrors `startQrEngagement()`: iOS turns `session.deviceEngagement` into a
     * UIImage here; the ArkUI QRCode component renders the payload string
     * directly, so the string itself travels in `qrReady`.
     */
    public func startQrEngagement(): String {
        match (this.session.deviceEngagement) {
            case Some(payload) where !payload.isEmpty() =>
                this.subject.setValue(PresentationState.qrReady(payload))
                return payload
            case _ =>
                throw WalletCoreError.unableToPresentAndShare()
        }
    }

    /** Mirrors `requestReceived()`. */
    public func requestReceived(): PresentationRequest {
        if (this.session.disclosedDocuments.size == 0) {
            throw WalletCoreError.unableToPresentAndShare()
        }
        return this.createRequest()
    }

    /**
     * Mirrors `sendResponse(response:)`. `responseSent` is driven by the
     * transport: the session's `onSent` (the engine's onSuccess, fired after
     * ResponseSent) and the `responseSent` status both converge on
     * `emitResponseSent`, which publishes the state exactly once. The call then
     * blocks in `waitForDisconnect` until the reader ends the session.
     */
    public func sendResponse(response: RequestItemConvertible): Unit {
        let self0 = this
        this.session.sendResponse(true, response.items, { url => self0.emitResponseSent(url) })
        this.session.waitForDisconnect()
    }

    public func getState(): PresentationState { this.subject.getValue() }
    public func setState(presentationState: PresentationState): Unit { this.subject.setValue(presentationState) }
    public func getStream(): SendableCurrentValueSubject<PresentationState> { this.subject.getAsyncStream() }

    /**
     * Mirrors `stopPresentation()` (complete the subject, cancel the status
     * subscription) and, HarmonyOS-specific, stops the engine session so
     * cancel/back tears the radio down instead of waiting for object release.
     */
    public func stopPresentation(): Unit {
        this.subject.complete()
        this.sendableAnyCancellable.cancel()
        try {
            this.session.stop()
        } catch (e: Exception) {
            Hilog.error(0, "VPFLOW", "proximity stopPresentation: session stop failed: " + e.message)
        }
    }

    public func currentRelyingParty(): String {
        return this.session.readerCertIssuer ?? LocalizableManagerUnknownVerifier()
    }

    /** Publish `responseSent` once; later transport/onSent echoes are no-ops. */
    private func emitResponseSent(url: ?String): Unit {
        match (this.subject.getValue()) {
            case responseSent(_) => ()
            case _ => this.subject.setValue(PresentationState.responseSent(url))
        }
    }

    private func createRequest(): PresentationRequest {
        PresentationRequest(
            items: this.session.disclosedDocuments,
            relyingParty: this.session.readerCertIssuer ?? LocalizableManagerUnknownVerifier(),
            dataRequestInfo: this.session.readerCertValidationMessage ?? LocalizableManagerRequestDataInfoNotice(),
            isTrusted: this.session.readerCertIssuerValid == Some(true),
            overaskedClaims: sessionOveraskedClaims(this.session),
            // iOS: itemSets: session.disclosedDocumentSets.map(\.docElements) —
            // the combination sets for the combination-selection UI.
            itemSets: sessionItemSets(this.session)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinator/RemoteSessionCoordinator.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol RemoteSessionCoordinator: Sendable`. */
public interface RemoteSessionCoordinator {
    prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState>
    /** Mirrors `relyingPartyRegistration` — the verifier's WRPRC policy (None
     *  when registration validation is off or no certificate was delivered). */
    prop relyingPartyRegistration: ?WrpRegistrationPolicy
    /** Mirrors `relyingPartyWarningViolations` — the messages of the ""-keyed
     *  (request-level) WRPRC violations: the registration itself failed. */
    prop relyingPartyWarningViolations: Array<String>
    /** Reader DER certificate chain (leaf first), for presenter-name resolution. */
    prop readerCertificateChain: ?Array<Array<UInt8>>
    func initialize(): Unit
    func requestReceived(): PresentationRequest
    func sendResponse(response: RequestItemConvertible): Unit
    func getState(): PresentationState
    func getStream(): SendableCurrentValueSubject<PresentationState>
    func setState(presentationState: PresentationState): Unit
    func stopPresentation(): Unit
    /** Current verifier display name (for the transaction log); read from the
     *  shared coordinator so it survives the request→loading view-model handoff. */
    func currentRelyingParty(): String
    /** Mirrors iOS `[DocElements].overaskedPaths(from:)` over the session's
     *  disclosed document sets: docId → over-asked leaf claim paths, in the
     *  shape the feature tier hands to request_bridge. */
    func overaskedLeafPathsByDocId(): HashMap<String, Array<Array<String>>>
}

/** Mirrors iOS `final class RemoteSessionCoordinatorImpl`. */
public class RemoteSessionCoordinatorImpl <: RemoteSessionCoordinator {
    private let subject = SendableCurrentValueSubject<PresentationState>(PresentationState.loading)
    private let sendableAnyCancellable = SendableAnyCancellable()
    private let session: PresentationSession

    public init(session: PresentationSession) {
        this.session = session
        let self0 = this
        this.session.observeStatus({ status =>
            if (self0.sendableAnyCancellable.isCancelled()) { return }
            match (status) {
                case sessionError =>
                    match (self0.session.uiErrorDescription) {
                        case Some(msg) =>
                            Hilog.error(0, "VPFLOW", "remote sessionError: " + msg)
                            self0.subject.setValue(PresentationState.error(Exception(RuntimeError.customError(msg).localizedDescription)))
                        case None =>
                            Hilog.error(0, "VPFLOW", "remote sessionError: (no uiErrorDescription)")
                            self0.subject.setValue(PresentationState.error(WalletCoreError.unableToPresentAndShare()))
                    }
                case requestReceived => self0.subject.setValue(PresentationState.requestReceived(self0.createRequest()))
                case _ => ()
            }
        })
    }

    public prop sendableCurrentValueSubject: SendableCurrentValueSubject<PresentationState> {
        get() { this.subject }
    }

    /** Mirrors `relyingPartyRegistration` = session.wrpVerifierPolicy. */
    public prop relyingPartyRegistration: ?WrpRegistrationPolicy {
        get() { this.session.wrpVerifierPolicy }
    }

    /** Mirrors `relyingPartyWarningViolations` — ""-keyed violation messages. */
    public prop relyingPartyWarningViolations: Array<String> {
        get() { sessionWarningViolationMessages(this.session) }
    }

    public prop readerCertificateChain: ?Array<Array<UInt8>> {
        get() { this.session.readerCertificateChain }
    }

    public func overaskedLeafPathsByDocId(): HashMap<String, Array<Array<String>>> {
        return overaskedPathsByDocId(this.session.disclosedDocumentSets, sessionOveraskedClaims(this.session))
    }

    public func initialize(): Unit {
        Hilog.info(0, "VPFLOW", "remote initialize -> session.receiveRequest")
        this.session.receiveRequest()
    }

    public func requestReceived(): PresentationRequest {
        Hilog.info(0, "VPFLOW", "remote requestReceived disclosed=" + this.session.disclosedDocuments.size.toString())
        if (this.session.disclosedDocuments.size == 0) {
            throw WalletCoreError.unableToPresentAndShare()
        }
        return this.createRequest()
    }

    public func sendResponse(response: RequestItemConvertible): Unit {
        let self0 = this
        this.session.sendResponse(true, response.items, { url =>
            self0.subject.setValue(PresentationState.responseSent(url))
        })
    }

    public func getState(): PresentationState { this.subject.getValue() }
    public func setState(presentationState: PresentationState): Unit { this.subject.setValue(presentationState) }
    public func getStream(): SendableCurrentValueSubject<PresentationState> { this.subject.getAsyncStream() }

    public func stopPresentation(): Unit {
        this.subject.complete()
        this.sendableAnyCancellable.cancel()
    }

    private func createRequest(): PresentationRequest {
        PresentationRequest(
            items: this.session.disclosedDocuments,
            relyingParty: this.session.readerCertIssuer ?? LocalizableManagerUnknownVerifier(),
            dataRequestInfo: this.session.readerCertValidationMessage ?? LocalizableManagerRequestDataInfoNotice(),
            isTrusted: this.session.readerCertIssuerValid == Some(true),
            overaskedClaims: sessionOveraskedClaims(this.session),
            // iOS: itemSets: session.disclosedDocumentSets.map(\.docElements) —
            // the combination sets for the combination-selection UI.
            itemSets: sessionItemSets(this.session)
        )
    }

    public func currentRelyingParty(): String {
        return this.session.readerCertIssuer ?? LocalizableManagerUnknownVerifier()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared registration-layer session accessors (both coordinators)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors `(session.wrpVerifierWarnings?[""] ?? []).map(\.message)` — the
 * request-level violation messages (the "" key holds the failures of the
 * registration itself; per-docType keys hold over-asking).
 */
func sessionWarningViolationMessages(session: PresentationSession): Array<String> {
    match (session.wrpVerifierWarnings) {
        case Some(map) =>
            match (map.get("")) {
                case Some(violations) =>
                    let out = ArrayList<String>()
                    for (v in violations) { out.add(v.message) }
                    return out.toArray()
                case None => return Array<String>()
            }
        case None => return Array<String>()
    }
}

/**
 * Mirrors the coordinators' private `overaskedClaims`:
 * `(session.wrpVerifierWarnings?.values.flatMap { $0 } ?? []).toOveraskedClaims()`.
 */
/** iOS `session.disclosedDocumentSets.map(\.docElements)` — the combination sets
 *  (each inner array is one candidate document per requested query) carried on
 *  PresentationRequest.itemSets for the combination-selection UI. The session
 *  surfaces them already converted to seam DocElements (disclosedItemSets). */
func sessionItemSets(session: PresentationSession): Array<Array<DocElements>> {
    session.disclosedItemSets
}

func sessionOveraskedClaims(session: PresentationSession): Array<OveraskedClaim> {
    match (session.wrpVerifierWarnings) {
        case Some(map) =>
            let all = ArrayList<PresentationPolicyViolation>()
            for ((_, violations) in map) {
                for (v in violations) { all.add(v) }
            }
            return toOveraskedClaims(all.toArray())
        case None => return Array<OveraskedClaim>()
    }
}
