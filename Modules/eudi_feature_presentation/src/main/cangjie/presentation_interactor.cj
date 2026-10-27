/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-presentation
 * module (Interactor/PresentationInteractor.swift) to Cangjie for the EUDI
 * HarmonyOS wallet.
 *
 * Pure business-logic seam over a RemoteSessionCoordinator (logic-core) + the
 * WalletKitController. UI-free (no kit.ArkUI.* import — keeps bare `None`
 * un-polluted, matching the Interactor/Model convention).
 *
 * The request decode (PresentationRequest → selectable RequestDataSection rows)
 * and the response build (selected cells → RequestItemConvertible) are shared
 * with feature-proximity through the feature-common request bridge
 * (buildRequestReceivedModel / buildRequestConvertible).
 */
package eudi_feature_presentation

import std.collection.{ArrayList, HashMap}
import eudi_logic_core.*
import eudi_feature_common.{
    RequestDataCell, RequestDataSection, RequestReceivedModel, ClaimRef,
    buildRequestReceivedModel, buildRequestConvertible
}

/** Mirrors iOS `RemoteSentResponsePartialState`. */
public enum SentResponseResult {
    | ResponseSent
    | ResponseFailure(String)
}

/**
 * Mirrors iOS `RemotePublisherPartialState` — the Result of asking the active
 * coordinator for its state stream. success = got the stream, failure = the
 * coordinator threw while producing it.
 */
public enum PublisherResult {
    | PublisherSuccess(SendableCurrentValueSubject<PresentationState>)
    | PublisherFailure(String)
}

/**
 * Mirrors iOS `PresentationCoordinatorPartialState` — the Result of resolving the
 * active coordinator. In the iOS design the coordinator is fetched through a
 * SessionCoordinatorHolder that can throw; Cangjie injects the coordinator
 * directly, so "failure" here means the injected coordinator is non-operational
 * (its liveness probe throws), which is the direct-injection equivalent of iOS's
 * "holder failed to hand back a coordinator".
 */
public enum CoordinatorResult {
    | CoordinatorSuccess(RemoteSessionCoordinator)
    | CoordinatorFailure(String)
}

/** Mirrors iOS `PresentationInteractor` protocol. */
public interface PresentationInteractor {
    /** The active coordinator's state stream (iOS getSessionStatePublisher). */
    func getStream(): ?SendableCurrentValueSubject<PresentationState>
    /**
     * Result-style equivalent of iOS `getSessionStatePublisher()`: success wraps
     * the coordinator's state stream, failure carries the error text when the
     * coordinator throws while producing it.
     */
    func getSessionStatePublisher(): PublisherResult
    /**
     * Result-style equivalent of iOS `getCoordinator()`: success wraps the active
     * coordinator, failure carries the error text when the coordinator is
     * non-operational. See CoordinatorResult for the direct-injection mapping.
     */
    func getCoordinator(): CoordinatorResult
    /** iOS onDeviceEngagement + onRequestReceived — initialise then read request. */
    func onDeviceEngagement(): RequestReceivedModel
    /** iOS `registrationForFailedRequest()`: the verifier registration for a
     *  request that failed to resolve — shows WHO asked even when the request
     *  is unsatisfiable. `None` when no registration policy was captured. */
    func registrationForFailedRequest(): ?RelyingPartyRegistration
    /** iOS onResponsePrepare — stash the selected disclosure as responseToSend. */
    func onResponsePrepare(selected: ArrayList<RequestDataCell>): Bool
    /** iOS onSendResponse — send the previously-prepared response. */
    func onSendResponse(): SentResponseResult
    /**
     * iOS `storeDynamicIssuancePendingUrl(with:)` — the interactor forwards a
     * pending dynamic-issuance deep link straight to the WalletKitController.
     */
    func storeDynamicIssuancePendingUrl(url: ParsedUrlRef): Unit
    /** iOS stopPresentation. */
    func stopPresentation(): Unit
    /** Verifier display name captured from the last resolved request (for the
     *  document-list success page). "" before any request resolves. */
    func lastRelyingPartyName(): String
    /** Whether that verifier's reader cert chain validated (trust badge). */
    func lastRelyingPartyTrusted(): Bool
    /** Titles of the documents disclosed in the last request (success card). */
    func lastDisclosedDocLabels(): Array<String>
    /** Selected fields grouped by document for the expandable success cards. */
    func lastDisclosedSections(): Array<RequestDataSection>
}

/** Mirrors iOS `final actor PresentationInteractorImpl`. */
public class PresentationInteractorImpl <: PresentationInteractor {
    private let coordinator: RemoteSessionCoordinator
    private let walletController: WalletKitController
    // The groupId → ClaimRef map of the last request, so a selected
    // RequestDataCell can be reverse-mapped to a RequestItem.
    private let claimIndex: HashMap<String, ClaimRef> = HashMap<String, ClaimRef>()
    // Verifier identity + disclosed document labels captured from the request,
    // recorded into the transaction log once the response is sent (iOS logs the
    // presentation in PresentationSession.sendResponse via TransactionLogger).
    private var lastRelyingParty: String = ""
    private var lastIsTrusted: Bool = false
    private var lastDocLabels: Array<String> = Array<String>()
    private var lastRequestSections: Array<RequestDataSection> = Array<RequestDataSection>()
    private var lastSharedSections: Array<RequestDataSection> = Array<RequestDataSection>()

    public init(coordinator!: RemoteSessionCoordinator, walletController!: WalletKitController) {
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

    public func getSessionStatePublisher(): PublisherResult {
        try {
            return PublisherResult.PublisherSuccess(this.coordinator.getStream())
        } catch (e: Exception) {
            return PublisherResult.PublisherFailure(presentationErrorText(e))
        }
    }

    public func getCoordinator(): CoordinatorResult {
        // Direct-injection design: the coordinator is held from init, so there is
        // no holder that can fail to return it. Probe the coordinator's liveness
        // (getStream) to distinguish an operational coordinator (success) from a
        // non-operational injected one (failure) — the equivalent of iOS's
        // holder.getActiveRemoteCoordinator() succeeding vs. throwing.
        try {
            this.coordinator.getStream()
            return CoordinatorResult.CoordinatorSuccess(this.coordinator)
        } catch (e: Exception) {
            return CoordinatorResult.CoordinatorFailure(presentationErrorText(e))
        }
    }

    public func onDeviceEngagement(): RequestReceivedModel {
        try {
            this.coordinator.initialize()
            let request = this.coordinator.requestReceived()
            // Registration-certificate layer (iOS onRequestReceived): the
            // over-asked leaf paths mark the "Not registered data" rows, and the
            // combined verdict travels with the success payload. An unsatisfiable
            // request (empty sections) still succeeds so the RP shows.
            let overaskedPaths = this.coordinator.overaskedLeafPathsByDocId()
            let model = buildRequestReceivedModel(
                request, this.walletController, this.claimIndex,
                overaskedPaths: Some(overaskedPaths)
            )
            let registration = this.walletController.getVerifierRegistration(
                this.coordinator.relyingPartyRegistration,
                this.coordinator.relyingPartyWarningViolations,
                request.overaskedClaims,
                Some(request.relyingParty),
                request.isTrusted
            )
            // Capture verifier name + disclosed document titles for the tx log /
            // success page. The registration-resolved name and the combined badge
            // (isFullyVerified) win over the raw reader-cert values, mirroring
            // iOS onReceivedRegistration.
            this.lastRelyingParty = registration.name ?? model.relyingParty
            this.lastIsTrusted = registration.isFullyVerified
            let labels = ArrayList<String>()
            for (section in model.sections) {
                labels.add(section.title)
            }
            this.lastDocLabels = labels.toArray()
            // Every combination's sections (deduped by doc id): the share filter
            // in onResponsePrepare matches selected cells by groupId, and the
            // holder may share any combination — not just the first.
            let requestSections = ArrayList<RequestDataSection>()
            let seenDocIds = HashMap<String, Bool>()
            for (combination in model.combinations) {
                for (section in combination) {
                    if (!seenDocIds.contains(section.id)) {
                        seenDocIds[section.id] = true
                        requestSections.add(section)
                    }
                }
            }
            this.lastRequestSections = requestSections.toArray()
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
            return RequestReceivedModel.failure(presentationErrorText(e))
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
        // Preserve only the rows the holder actually chose. These are carried
        // through the loader into PresentationSuccessView, matching iOS's
        // filterSelectedRows() result used by DocumentSuccessView.
        let selectedIds = HashMap<String, Bool>()
        for (cell in selected) {
            selectedIds[cell.groupId] = true
        }
        let sharedSections = ArrayList<RequestDataSection>()
        let sharedLabels = ArrayList<String>()
        for (section in this.lastRequestSections) {
            let cells = ArrayList<RequestDataCell>()
            for (cell in section.cells) {
                if (selectedIds.contains(cell.groupId)) {
                    cells.add(cell.strippingOveraskedMark())
                }
            }
            if (!cells.isEmpty()) {
                sharedSections.add(RequestDataSection(id: section.id, title: section.title, cells: cells))
                sharedLabels.add(section.title)
            }
        }
        this.lastSharedSections = sharedSections.toArray()
        this.lastDocLabels = sharedLabels.toArray()
        try {
            this.coordinator.setState(PresentationState.responseToSend(convertible))
            return true
        } catch (_: Exception) {
            return false
        }
    }

    public func onSendResponse(): SentResponseResult {
        try {
            let state = this.coordinator.getState()
            match (state) {
                case responseToSend(item) =>
                    this.coordinator.sendResponse(item)
                    // Record the completed presentation so it appears in History
                    // (iOS logs it in PresentationSession.sendResponse). The
                    // relying-party is read from the shared coordinator (not an
                    // interactor field) because onDeviceEngagement and this call
                    // run on different interactor instances (request vs loading
                    // view-model). Failure to log must not fail the presentation.
                    try {
                        this.walletController.logPresentation(this.coordinator.currentRelyingParty(), this.lastDocLabels)
                    } catch (_: Exception) {}
                    return SentResponseResult.ResponseSent
                case _ =>
                    return SentResponseResult.ResponseFailure(presentationInvalidStateText())
            }
        } catch (e: Exception) {
            return SentResponseResult.ResponseFailure(presentationErrorText(e))
        }
    }

    public func storeDynamicIssuancePendingUrl(url: ParsedUrlRef): Unit {
        this.walletController.storeDynamicIssuancePendingUrl(url)
    }

    public func stopPresentation(): Unit {
        this.walletController.stopPresentation()
        try {
            this.coordinator.stopPresentation()
        } catch (_: Exception) {}
    }

    public func lastRelyingPartyName(): String { this.lastRelyingParty }
    public func lastRelyingPartyTrusted(): Bool { this.lastIsTrusted }
    public func lastDisclosedDocLabels(): Array<String> { this.lastDocLabels }
    public func lastDisclosedSections(): Array<RequestDataSection> { this.lastSharedSections }
}

// ─── localized text (iOS WalletCoreError.errorDescription subset) ────────────

func presentationErrorText(e: Exception): String {
    let msg = e.message
    if (msg.isEmpty()) {
        return unableToPresentText()
    }
    return msg
}

func unableToPresentText(): String { "Unable to present and share data" }
func presentationInvalidStateText(): String { "Invalid presentation state" }

// ─── standalone-render fallback (no engine wired) ────────────────────────────

/** A no-op interactor for emulator/preview rendering (composition root supplies
 *  the wired instance). Returns a failure so the screen shows the empty/error
 *  state honestly rather than a fake request. */
public class NoopPresentationInteractor <: PresentationInteractor {
    public func getStream(): ?SendableCurrentValueSubject<PresentationState> { None }
    public func getSessionStatePublisher(): PublisherResult {
        PublisherResult.PublisherFailure(unableToPresentText())
    }
    public func getCoordinator(): CoordinatorResult {
        CoordinatorResult.CoordinatorFailure(unableToPresentText())
    }
    public func onDeviceEngagement(): RequestReceivedModel {
        RequestReceivedModel.failure(unableToPresentText())
    }
    public func registrationForFailedRequest(): ?RelyingPartyRegistration { None }
    public func onResponsePrepare(_: ArrayList<RequestDataCell>): Bool { false }
    public func onSendResponse(): SentResponseResult { SentResponseResult.ResponseFailure(unableToPresentText()) }
    public func storeDynamicIssuancePendingUrl(_: ParsedUrlRef): Unit {}
    public func stopPresentation(): Unit {}
    public func lastRelyingPartyName(): String { "" }
    public func lastRelyingPartyTrusted(): Bool { false }
    public func lastDisclosedDocLabels(): Array<String> { Array<String>() }
    public func lastDisclosedSections(): Array<RequestDataSection> { Array<RequestDataSection>() }
}
