/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Request/BaseRequestViewModel.swift + the Array helpers
 * of Model/RequestDataUIModel.swift) to Cangjie.
 *
 * Selection semantics migrated 1:1:
 *  - toggleSelection(groupId): flips only rows whose checkbox is enabled
 *    (`!isRequired && isAvailable` — iOS `guard isEnabled else break`).
 *  - canShare(): at least one selected row exists (iOS Array.canShare()) AND
 *    the registration warning — when one is active — has been acknowledged
 *    (iOS `allowShare && (registrationWarning == nil || isRiskAcknowledged)`).
 *  - selectedCells(): flattens the currently shared set (iOS
 *    prepareRequest / filterSelectedRows selection step) — the confirm
 *    callback of RequestView carries exactly this set, with the over-asked
 *    marking stripped (iOS filterSelectedRows: the mark must not travel to
 *    the success screen).
 *  - empty `sections` renders the no-document empty state (iOS
 *    `.requestDataNoDocument`).
 *
 * Registration certificate trust layer (iOS 95b71766): the state carries the
 * relying-party registration header data + warning, the trust-blocked alert
 * flag and the per-request risk acknowledgement (never remembered — reset in
 * resetState and onReceivedRegistration).
 */
package eudi_feature_common

import std.collection.ArrayList
import eudi_logic_core.{RelyingPartyRegistration}
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** Reducer state (core subset of iOS `RequestViewState`). */
public class RequestViewState <: ViewState {
    public let isLoading: Bool
    public let hasError: Bool
    public let relyingParty: String
    public let relyingPartyIsTrusted: Bool
    public let sections: ArrayList<RequestDataSection>
    // iOS `combinations: [[RequestDataUiModel]]` + `selectedCombinationIndex`:
    // every satisfying combination; `sections` holds the selected one (iOS `items`).
    // Empty for single-set flows (proximity) — the view then renders sections only.
    public let combinations: ArrayList<ArrayList<RequestDataSection>>
    public let selectedCombinationIndex: Int64
    /** iOS `relyingPartyRegistration` — the registration header payload. */
    public let relyingPartyRegistration: ?RelyingPartyRegistrationData
    /** iOS `registrationWarning` — gates Share behind acknowledgement. */
    public let registrationWarning: ?RegistrationWarning
    /** iOS `isTrustBlockedAlertShowing` (VM-held there; state-held here so the
     *  page's single state listener can sync it, see view_model.cj). */
    public let isTrustBlockedAlertShowing: Bool
    /** iOS `isRiskAcknowledged` — per-request, never remembered. */
    public let isRiskAcknowledged: Bool
    /** iOS `initialized` — request payload received (setItems/onTrustBlocked). */
    public let initialized: Bool

    public init(
        isLoading!: Bool = false,
        hasError!: Bool = false,
        relyingParty!: String = "",
        relyingPartyIsTrusted!: Bool = false,
        sections!: ArrayList<RequestDataSection> = ArrayList<RequestDataSection>(),
        combinations!: ArrayList<ArrayList<RequestDataSection>> = ArrayList<ArrayList<RequestDataSection>>(),
        selectedCombinationIndex!: Int64 = 0,
        relyingPartyRegistration!: ?RelyingPartyRegistrationData = None,
        registrationWarning!: ?RegistrationWarning = None,
        isTrustBlockedAlertShowing!: Bool = false,
        isRiskAcknowledged!: Bool = false,
        initialized!: Bool = false
    ) {
        this.isLoading = isLoading
        this.hasError = hasError
        this.relyingParty = relyingParty
        this.relyingPartyIsTrusted = relyingPartyIsTrusted
        this.sections = sections
        this.combinations = combinations
        this.selectedCombinationIndex = selectedCombinationIndex
        this.relyingPartyRegistration = relyingPartyRegistration
        this.registrationWarning = registrationWarning
        this.isTrustBlockedAlertShowing = isTrustBlockedAlertShowing
        this.isRiskAcknowledged = isRiskAcknowledged
        this.initialized = initialized
    }

    /**
     * Optional-of-optional params for the two nullable fields: outer `None`
     * keeps the current value, `Some(None)` clears it (copyWith's plain `??`
     * could never write `None` back).
     */
    public func copyWith(
        isLoading!: ?Bool = Option<Bool>.None,
        hasError!: ?Bool = Option<Bool>.None,
        relyingParty!: ?String = Option<String>.None,
        relyingPartyIsTrusted!: ?Bool = Option<Bool>.None,
        sections!: ?ArrayList<RequestDataSection> = Option<ArrayList<RequestDataSection>>.None,
        combinations!: ?ArrayList<ArrayList<RequestDataSection>> = Option<ArrayList<ArrayList<RequestDataSection>>>.None,
        selectedCombinationIndex!: ?Int64 = Option<Int64>.None,
        relyingPartyRegistration!: Option<Option<RelyingPartyRegistrationData>> = Option<Option<RelyingPartyRegistrationData>>.None,
        registrationWarning!: Option<Option<RegistrationWarning>> = Option<Option<RegistrationWarning>>.None,
        isTrustBlockedAlertShowing!: ?Bool = Option<Bool>.None,
        isRiskAcknowledged!: ?Bool = Option<Bool>.None,
        initialized!: ?Bool = Option<Bool>.None
    ): RequestViewState {
        let nextRegistration = match (relyingPartyRegistration) {
            case Some(v) => v
            case None => this.relyingPartyRegistration
        }
        let nextWarning = match (registrationWarning) {
            case Some(v) => v
            case None => this.registrationWarning
        }
        RequestViewState(
            isLoading: isLoading ?? this.isLoading,
            hasError: hasError ?? this.hasError,
            relyingParty: relyingParty ?? this.relyingParty,
            relyingPartyIsTrusted: relyingPartyIsTrusted ?? this.relyingPartyIsTrusted,
            sections: sections ?? this.sections,
            combinations: combinations ?? this.combinations,
            selectedCombinationIndex: selectedCombinationIndex ?? this.selectedCombinationIndex,
            relyingPartyRegistration: nextRegistration,
            registrationWarning: nextWarning,
            isTrustBlockedAlertShowing: isTrustBlockedAlertShowing ?? this.isTrustBlockedAlertShowing,
            isRiskAcknowledged: isRiskAcknowledged ?? this.isRiskAcknowledged,
            initialized: initialized ?? this.initialized
        )
    }

    /** No-document empty state (iOS `requestDataNoDocument` branch). */
    public func isEmpty(): Bool {
        this.sections.isEmpty()
    }
}

/** Mirrors iOS `BaseRequestViewModel` (shared base of presentation/proximity). */
public class RequestViewModel <: BaseViewModel<RequestViewState> {
    public init(
        router!: RouterHost,
        initialState!: RequestViewState = RequestViewState()
    ) {
        super(router, initialState)
    }

    /**
     * iOS `onReceivedCombinations`: feed all combinations; select the first.
     * (Online presentation calls this — may be > 1 combination.)
     */
    public func onReceivedCombinations(
        relyingParty!: String,
        relyingPartyIsTrusted!: Bool,
        combinations!: ArrayList<ArrayList<RequestDataSection>>
    ): Unit {
        this.setState({ s =>
            s.copyWith(
                isLoading: Some(false),
                relyingParty: Some(relyingParty),
                relyingPartyIsTrusted: Some(relyingPartyIsTrusted),
                sections: Some(if (combinations.size > 0) { combinations[0] } else { ArrayList<RequestDataSection>() }),
                combinations: Some(combinations),
                selectedCombinationIndex: Some(0),
                initialized: Some(true)
            )
        })
    }

    /**
     * iOS `onReceivedItems`: wrap a single combination's sections. Proximity uses
     * this (always exactly one combination, per-claim checkboxes).
     */
    public func onReceivedItems(
        relyingParty!: String,
        relyingPartyIsTrusted!: Bool,
        sections!: ArrayList<RequestDataSection>
    ): Unit {
        let combos = ArrayList<ArrayList<RequestDataSection>>()
        combos.add(sections)
        this.onReceivedCombinations(
            relyingParty: relyingParty,
            relyingPartyIsTrusted: relyingPartyIsTrusted,
            combinations: combos
        )
    }

    /** Backward-compatible alias for `onReceivedItems`. */
    public func setItems(
        relyingParty!: String,
        relyingPartyIsTrusted!: Bool,
        sections!: ArrayList<RequestDataSection>
    ): Unit {
        this.onReceivedItems(
            relyingParty: relyingParty,
            relyingPartyIsTrusted: relyingPartyIsTrusted,
            sections: sections
        )
    }

    /** iOS `onCombinationSelected(index:)` — radio-switch the active combination
     *  (items follow the selection: `items = combinations[index]`). */
    public func onCombinationSelected(index: Int64): Unit {
        if (index < 0 || index >= this.viewState.combinations.size) { return }
        this.setState({ s =>
            s.copyWith(
                sections: Some(s.combinations[index]),
                selectedCombinationIndex: Some(index)
            )
        })
    }

    /** Number of combinations (iOS `combinations.count`). */
    public func combinationCount(): Int64 {
        this.viewState.combinations.size
    }

    /** Sections of a given combination (for rendering the selectable cards). */
    public func combinationSectionsAt(index: Int64): ArrayList<RequestDataSection> {
        if (index < 0 || index >= this.viewState.combinations.size) {
            return ArrayList<RequestDataSection>()
        }
        return this.viewState.combinations[index]
    }

    /** Index of the currently-selected combination. */
    public func selectedCombination(): Int64 {
        this.viewState.selectedCombinationIndex
    }

    /**
     * Mirrors iOS `onReceivedRegistration(_:)`: resets the per-request risk
     * acknowledgement, resolves the display name (registration name wins,
     * else keep what setItems provided), takes the badge from
     * `isFullyVerified` and derives header data + warning.
     */
    public func onReceivedRegistration(registration: RelyingPartyRegistration): Unit {
        this.setState({ s =>
            s.copyWith(
                relyingParty: Some(registration.name ?? s.relyingParty),
                relyingPartyIsTrusted: Some(registration.isFullyVerified),
                relyingPartyRegistration: Some(Some(toRegistrationData(
                    registration,
                    fallbackName: LocalizableStringKey.unknownVerifier
                ))),
                registrationWarning: Some(toWarning(registration)),
                isRiskAcknowledged: Some(false)
            )
        })
    }

    /**
     * Mirrors iOS `onTrustBlocked()`: clears the request payload, marks the
     * screen initialized (empty state shows behind the alert) and raises the
     * trust-blocked alert. Stopping the presentation session stays with the
     * feature view model (it owns the interactor).
     */
    public func onTrustBlocked(): Unit {
        this.setState({ s =>
            s.copyWith(
                isLoading: Some(false),
                hasError: Some(false),
                sections: Some(ArrayList<RequestDataSection>()),
                combinations: Some(ArrayList<ArrayList<RequestDataSection>>()),
                selectedCombinationIndex: Some(0),
                isTrustBlockedAlertShowing: Some(true),
                initialized: Some(true)
            )
        })
    }

    /** Mirrors iOS `onTrustBlockedClose()` minus the pop — the page's
     *  `onCancel` callback owns navigation (repo convention). */
    public func onTrustBlockedClose(): Unit {
        this.setState({ s => s.copyWith(isTrustBlockedAlertShowing: Some(false)) })
    }

    /** Two-way seam of the WarningAcknowledgementView toggle. */
    public func setRiskAcknowledged(isAcknowledged: Bool): Unit {
        this.setState({ s => s.copyWith(isRiskAcknowledged: Some(isAcknowledged)) })
    }

    /** Mirrors iOS `resetState()`: back to a fresh request (acknowledgement
     *  and registration fields included — never remembered). */
    public func resetState(): Unit {
        this.setState({ _ => RequestViewState() })
    }

    /**
     * The warning the screen actually shows: only once the request payload is
     * in and not while loading (iOS BaseRequestViewContainer gating).
     */
    public func activeRegistrationWarning(): ?RegistrationWarning {
        let s = this.viewState
        if (!s.initialized || s.isLoading) {
            return None
        }
        return s.registrationWarning
    }

    /**
     * Flips the row matching `groupId` when its checkbox is enabled; locked
     * (required) and unavailable rows ignore the request. Returns whether a
     * change happened so the page can refresh its @State snapshot.
     */
    public func toggleSelection(groupId: String): Bool {
        for (section in this.viewState.sections) {
            for (cell in section.cells) {
                if (cell.groupId == groupId && cell.selectable) {
                    cell.selected = !cell.selected
                    // Re-emit the state so the page listener refreshes.
                    this.setState({ s => s })
                    return true
                }
            }
        }
        return false
    }

    /**
     * At least one sharable row is selected (iOS `canShare()`), and an active
     * registration warning — if any — has been acknowledged (iOS
     * `allowShare && (registrationWarning == nil || isRiskAcknowledged)`).
     */
    public func canShare(): Bool {
        match (this.activeRegistrationWarning()) {
            case Some(_) =>
                if (!this.viewState.isRiskAcknowledged) {
                    return false
                }
            case None => ()
        }
        for (section in this.viewState.sections) {
            for (cell in section.cells) {
                if (cell.sharable) {
                    return true
                }
            }
        }
        return false
    }

    /**
     * Flattened selected set — payload of the confirm callback. Rows are
     * rebuilt without the over-asked marking (iOS `filterSelectedRows()`:
     * the "Not registered data" mark must not travel to the success screen).
     */
    public func selectedCells(): ArrayList<RequestDataCell> {
        let result = ArrayList<RequestDataCell>()
        for (section in this.viewState.sections) {
            for (cell in section.cells) {
                if (cell.sharable) {
                    result.add(cell.strippingOveraskedMark())
                }
            }
        }
        return result
    }

    /**
     * Header title text (iOS `requestDataTitle("%@ requests the following")`
     * with the unknown-verifier fallback).
     */
    public func requestTitleText(): String {
        var rp = this.viewState.relyingParty
        if (rp.isEmpty()) {
            rp = LocalizableManager.get(LocalizableStringKey.unknownVerifier)
        }
        return LocalizableManager.get(LocalizableStringKey.requestDataTitle([rp]))
    }
}
