/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Request/Model/RequestDataUIModel.swift) to Cangjie.
 *
 * The iOS model is a generic ExpandableListItem tree over logic-core
 * DocumentElementClaim domain models. The selection semantics that the
 * shared Request screen actually owns are migrated here onto two flat
 * models (logic-core claim parsing stays with the wallet-core module):
 *
 *  - `RequestDataCell` — one disclosable claim row. Mirrors the iOS single
 *    item: groupId + overline title + value + the checkbox semantics
 *    `enabled = !isRequired && isAvailable`, `selected = isAvailable`
 *    initially. Required rows render locked-checked; unavailable rows render
 *    disabled-unchecked.
 *  - `RequestDataSection` — one document grouping (section.id / title /
 *    cells), mirrors iOS `RequestDataUiModel.section`.
 *
 * `toggleSelection` / `canShare` / `selectedCells` (the iOS Array extension
 * helpers) live on RequestViewModel (request_view_model.cj).
 */
package eudi_feature_common

import std.collection.ArrayList

/**
 * One disclosable attribute row of a presentation request.
 *
 * - `groupId`: stable row identity, selection toggles match on it.
 * - `title`: claim name (overline, e.g. "Family Name").
 * - `value`: claim value (main content, e.g. "Tzouvaras").
 * - `isRequired`: mandatory claim — checkbox locked, cannot be deselected.
 * - `isAvailable`: claim present in the wallet — unavailable rows are
 *   disabled and excluded from sharing.
 * - `selected`: current checkbox state (defaults to `isAvailable`, the iOS
 *   initial state).
 * - `isOverasked`: claim not covered by the relying party's registration
 *   certificate (iOS leaf `isOverasked`) — the row renders the
 *   "Not registered data" supporting line in the warning color.
 */
public class RequestDataCell {
    private static var idCounter: Int64 = 0

    public let groupId: String
    public let title: String
    public let value: String
    public let isRequired: Bool
    public let isAvailable: Bool
    public var selected: Bool
    // iOS `claimsAreSelectable`: proximity rows are per-claim checkboxes (true);
    // online-presentation rows are read-only (false) — selection happens at the
    // combination level, the whole selected combination is disclosed as-is.
    public let hasCheckbox: Bool
    public let isOverasked: Bool

    public init(
        groupId!: ?String = Option<String>.None,
        title!: String,
        value!: String,
        isRequired!: Bool = false,
        isAvailable!: Bool = true,
        selected!: ?Bool = Option<Bool>.None,
        hasCheckbox!: Bool = true,
        isOverasked!: Bool = false
    ) {
        this.groupId = groupId ?? RequestDataCell.nextId()
        this.title = title
        this.value = value
        this.isRequired = isRequired
        this.isAvailable = isAvailable
        this.selected = selected ?? isAvailable
        this.hasCheckbox = hasCheckbox
        this.isOverasked = isOverasked
    }

    /**
     * Copy without the over-asked marking (iOS `filterSelectedRows()` strips
     * `supportingText` so the mark never travels to the success screen).
     */
    public func strippingOveraskedMark(): RequestDataCell {
        RequestDataCell(
            groupId: this.groupId,
            title: this.title,
            value: this.value,
            isRequired: this.isRequired,
            isAvailable: this.isAvailable,
            selected: this.selected,
            hasCheckbox: this.hasCheckbox,
            isOverasked: false
        )
    }

    private static func nextId(): String {
        RequestDataCell.idCounter += 1
        return "request_cell_${RequestDataCell.idCounter}"
    }

    /**
     * Mirrors the iOS checkbox enablement:
     * `.checkbox(!status.isRequired && status.isAvailable, ...)`.
     */
    public prop selectable: Bool {
        get() { this.hasCheckbox && !this.isRequired && this.isAvailable }
    }

    /** Row participates in the shared set (selected and actually available). */
    public prop sharable: Bool {
        get() { this.selected && this.isAvailable }
    }
}

/**
 * One document grouping of the request list. Mirrors iOS
 * `RequestDataUiModel.section` (`ListItemSection`: id / title / items).
 */
public class RequestDataSection {
    public let id: String
    public let title: String
    public let cells: ArrayList<RequestDataCell>

    public init(
        id!: String,
        title!: String,
        cells!: ArrayList<RequestDataCell> = ArrayList<RequestDataCell>()
    ) {
        this.id = id
        this.title = title
        this.cells = cells
    }
}
