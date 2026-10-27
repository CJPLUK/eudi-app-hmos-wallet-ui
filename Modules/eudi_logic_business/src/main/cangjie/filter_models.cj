/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Validator/Model/Filters.swift, Filterable.swift, FilterAction.swift,
 * FilterIds.swift) to Cangjie.
 *
 * Mapping decisions:
 * - Swift protocol FilterGroup + 4 struct conformers -> open base class with 4
 *   subclasses; `copyWithFilters` virtualizes the Swift "mutate filters on a
 *   value copy" pattern.
 * - @Copyable copy(...) -> explicit with* methods covering every call shape the
 *   engine uses.
 * - Sort<T, R: Comparable> -> SortAction with a string key selector (dates are
 *   compared through sortable ISO keys); Filter<T> / FilterMultipleAction<T>
 *   keep their predicate shape over FilterableAttributes.
 * - Combine-free: FilterResult / FilterResultPartialState stay enums consumed
 *   by the single-slot listener in FilterValidator.
 */
package eudi_logic_business

import std.collection.ArrayList
import std.sort.*
import std.time.DateTime

/** Mirrors iOS `SortOrderType`. */
public enum SortOrderType <: Equatable<SortOrderType> {
    | ascending
    | descending

    public operator func ==(other: SortOrderType): Bool {
        match ((this, other)) {
            case (ascending, ascending) => true
            case (descending, descending) => true
            case _ => false
        }
    }

    public operator func !=(other: SortOrderType): Bool {
        return !(this == other)
    }
}

/** Mirrors iOS `FilterGroupType`. */
public enum FilterGroupType <: Equatable<FilterGroupType> {
    | issuer
    | documentCategory
    | relyingParty
    | attestation
    | other
    | orderBy
    | dateRange

    public prop rawValue: Int64 {
        get() {
            match (this) {
                case issuer => 0
                case documentCategory => 1
                case relyingParty => 2
                case attestation => 3
                case other => 4
                case orderBy => 5
                case dateRange => 6
            }
        }
    }

    public operator func ==(other: FilterGroupType): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: FilterGroupType): Bool {
        return !(this == other)
    }
}

/** Mirrors iOS `DateRangeType`. */
public enum DateRangeType {
    | start
    | end
}

/** Mirrors iOS `FilterElementType`. */
public enum FilterElementType {
    | radio
    | datePicker
}

/** Mirrors iOS `FilterableItemPayload`. */
public interface FilterableItemPayload {
    prop id: String
}

/** Mirrors iOS `FilterableAttributes`. */
public interface FilterableAttributes {
    prop sortingKey: String
    prop searchTags: Array<String>
}

/** Mirrors iOS `FilterableItem`. */
public class FilterableItem {
    public let payload: FilterableItemPayload
    public let attributes: FilterableAttributes

    public init(payload: FilterableItemPayload, attributes: FilterableAttributes) {
        this.payload = payload
        this.attributes = attributes
    }
}

/** Mirrors iOS `FilterableList`. */
public class FilterableList {
    public let items: Array<FilterableItem>

    public init(items: Array<FilterableItem>) {
        this.items = items
    }

    /** Mirrors `@Copyable copy(items:)`. */
    public func withItems(newItems: Array<FilterableItem>): FilterableList {
        return FilterableList(newItems)
    }

    /** Mirrors `sortedByOrder(sortOrder:selector:)`. */
    public func sortedByOrder(sortOrder: SortOrderType, selector: (FilterableItem) -> String): FilterableList {
        let sorted = this.items.clone()
        let ascendingOrder = sortOrder == SortOrderType.ascending
        sort<FilterableItem>(
            sorted,
            lessThan: {
                a, b =>
                if (ascendingOrder) {
                    selector(a) < selector(b)
                } else {
                    selector(a) > selector(b)
                }
            },
            stable: true
        )
        return FilterableList(sorted)
    }

    /** Mirrors `applySort(filters:)`: applies the selected SortAction sort item, if any. */
    public func applySort(filters: Filters): FilterableList {
        let sort: FilterSort
        match (filters.sort) {
            case Some(s) => sort = s
            case None => return this
        }
        for (item in sort.filters) {
            if (item.selected && item.filterableAction is SortFilterAction) {
                return item.filterableAction.applyFilter(filters.sortOrder, this, item)
            }
        }
        return this
    }
}

/** Mirrors the iOS `FilterAction` protocol. */
public interface FilterAction {
    func applyFilter(sortOrder: SortOrderType, filterableItems: FilterableList, filter: FilterItem): FilterableList
    func applyFilterGroup(filterableItems: FilterableList, filterGroup: FilterGroup): FilterableList
}

/** Marker interface identifying sort actions, mirrors iOS `SortFilterAction`. */
public interface SortFilterAction <: FilterAction {}

/** Mirrors iOS `FilterItem`. */
public class FilterItem {
    public let id: String
    public let name: String
    public let selected: Bool
    public let isDefault: Bool
    public let startDate: ?DateTime
    public let endDate: ?DateTime
    public let filterElementType: FilterElementType
    public let filterableAction: FilterAction

    public init(
        id!: String,
        name!: String,
        selected!: Bool,
        isDefault!: Bool = false,
        startDate!: ?DateTime = None,
        endDate!: ?DateTime = None,
        filterElementType!: FilterElementType = FilterElementType.radio,
        filterableAction!: FilterAction = DefaultFilterAction()
    ) {
        this.id = id
        this.name = name
        this.selected = selected
        this.isDefault = isDefault
        this.startDate = startDate
        this.endDate = endDate
        this.filterElementType = filterElementType
        this.filterableAction = filterableAction
    }

    /** Mirrors `copy(selected:)`. */
    public func withSelected(newSelected: Bool): FilterItem {
        return FilterItem(
            id: this.id,
            name: this.name,
            selected: newSelected,
            isDefault: this.isDefault,
            startDate: this.startDate,
            endDate: this.endDate,
            filterElementType: this.filterElementType,
            filterableAction: this.filterableAction
        )
    }

    /** Mirrors `copy(startDate:endDate:)`. */
    public func withDates(newStartDate: ?DateTime, newEndDate: ?DateTime): FilterItem {
        return FilterItem(
            id: this.id,
            name: this.name,
            selected: this.selected,
            isDefault: this.isDefault,
            startDate: newStartDate,
            endDate: newEndDate,
            filterElementType: this.filterElementType,
            filterableAction: this.filterableAction
        )
    }

    /** Mirrors `copy(selected:startDate:endDate:)`. */
    public func withSelectedAndDates(newSelected: Bool, newStartDate: ?DateTime, newEndDate: ?DateTime): FilterItem {
        return FilterItem(
            id: this.id,
            name: this.name,
            selected: newSelected,
            isDefault: this.isDefault,
            startDate: newStartDate,
            endDate: newEndDate,
            filterElementType: this.filterElementType,
            filterableAction: this.filterableAction
        )
    }
}

/** Mirrors iOS `FilterSort`. */
public class FilterSort {
    public let id: String
    public let name: String
    public let filters: Array<FilterItem>

    public init(id!: String, name!: String, filters!: Array<FilterItem>) {
        this.id = id
        this.name = name
        this.filters = filters
    }

    /** Mirrors `copy(filters:)`. */
    public func withFilters(newFilters: Array<FilterItem>): FilterSort {
        return FilterSort(id: this.id, name: this.name, filters: newFilters)
    }
}

/**
 * Mirrors the iOS `FilterGroup` protocol. The base class also serves as the
 * "unknown group" passthrough of the Swift switch default branches.
 */
public open class FilterGroup {
    public let id: String
    public let name: String
    public let filters: Array<FilterItem>
    public let filterType: FilterGroupType

    public init(id!: String, name!: String, filters!: Array<FilterItem>, filterType!: FilterGroupType) {
        this.id = id
        this.name = name
        this.filters = filters
        this.filterType = filterType
    }

    /** Returns the same concrete group type with a replaced filter array. */
    public open func copyWithFilters(newFilters: Array<FilterItem>): FilterGroup {
        return FilterGroup(id: this.id, name: this.name, filters: newFilters, filterType: this.filterType)
    }
}

/** Mirrors iOS `SingleSelectionFilterGroup`. */
public class SingleSelectionFilterGroup <: FilterGroup {
    public init(id!: String, name!: String, filters!: Array<FilterItem>, filterType!: FilterGroupType) {
        super(id: id, name: name, filters: filters, filterType: filterType)
    }

    public override func copyWithFilters(newFilters: Array<FilterItem>): FilterGroup {
        return SingleSelectionFilterGroup(
            id: this.id, name: this.name, filters: newFilters, filterType: this.filterType
        )
    }
}

/** Mirrors iOS `ReversibleSingleSelectionFilterGroup`. */
public class ReversibleSingleSelectionFilterGroup <: FilterGroup {
    public init(id!: String, name!: String, filters!: Array<FilterItem>, filterType!: FilterGroupType) {
        super(id: id, name: name, filters: filters, filterType: filterType)
    }

    public override func copyWithFilters(newFilters: Array<FilterItem>): FilterGroup {
        return ReversibleSingleSelectionFilterGroup(
            id: this.id, name: this.name, filters: newFilters, filterType: this.filterType
        )
    }
}

/** Mirrors iOS `MultipleSelectionFilterGroup`. */
public class MultipleSelectionFilterGroup <: FilterGroup {
    public let filterableAction: FilterAction

    public init(
        id!: String,
        name!: String,
        filters!: Array<FilterItem>,
        filterableAction!: FilterAction,
        filterType!: FilterGroupType
    ) {
        super(id: id, name: name, filters: filters, filterType: filterType)
        this.filterableAction = filterableAction
    }

    public override func copyWithFilters(newFilters: Array<FilterItem>): FilterGroup {
        return MultipleSelectionFilterGroup(
            id: this.id,
            name: this.name,
            filters: newFilters,
            filterableAction: this.filterableAction,
            filterType: this.filterType
        )
    }
}

/** Mirrors iOS `ReversibleMultipleSelectionFilterGroup`. */
public class ReversibleMultipleSelectionFilterGroup <: FilterGroup {
    public let filterableAction: FilterAction

    public init(
        id!: String,
        name!: String,
        filters!: Array<FilterItem>,
        filterableAction!: FilterAction,
        filterType!: FilterGroupType
    ) {
        super(id: id, name: name, filters: filters, filterType: filterType)
        this.filterableAction = filterableAction
    }

    public override func copyWithFilters(newFilters: Array<FilterItem>): FilterGroup {
        return ReversibleMultipleSelectionFilterGroup(
            id: this.id,
            name: this.name,
            filters: newFilters,
            filterableAction: this.filterableAction,
            filterType: this.filterType
        )
    }
}

/** Mirrors iOS `Filters`. */
public class Filters {
    public let filterGroups: Array<FilterGroup>
    public let sortOrder: SortOrderType
    public let sort: ?FilterSort

    public init(filterGroups!: Array<FilterGroup>, sortOrder!: SortOrderType, sort!: ?FilterSort = None) {
        this.filterGroups = filterGroups
        this.sortOrder = sortOrder
        this.sort = sort
    }

    public prop isEmpty: Bool {
        get() { this.filterGroups.isEmpty() && this.sort.isNone() }
    }

    public prop isNotEmpty: Bool {
        get() { !this.isEmpty }
    }

    public static func emptyFilters(sortOrder!: SortOrderType = SortOrderType.ascending): Filters {
        return Filters(filterGroups: Array<FilterGroup>(), sortOrder: sortOrder, sort: None)
    }

    /** Mirrors `copy()` (full snapshot copy; members are immutable). */
    public func copyAll(): Filters {
        return Filters(filterGroups: this.filterGroups, sortOrder: this.sortOrder, sort: this.sort)
    }

    /** Mirrors `copy(filterGroups:sortOrder:)`. */
    public func withGroupsAndOrder(newGroups: Array<FilterGroup>, newSortOrder: SortOrderType): Filters {
        return Filters(filterGroups: newGroups, sortOrder: newSortOrder, sort: this.sort)
    }

    /** Mirrors `copy(sortOrder:)`. */
    public func withSortOrder(newSortOrder: SortOrderType): Filters {
        return Filters(filterGroups: this.filterGroups, sortOrder: newSortOrder, sort: this.sort)
    }

    /** Mirrors `copy(sort:)`. */
    public func withSort(newSort: ?FilterSort): Filters {
        return Filters(filterGroups: this.filterGroups, sortOrder: this.sortOrder, sort: newSort)
    }
}

/** Mirrors iOS `DefaultFilterAction` (identity passthrough). */
public class DefaultFilterAction <: FilterAction {
    public init() {}

    public func applyFilter(sortOrder: SortOrderType, filterableItems: FilterableList, filter: FilterItem): FilterableList {
        let _ = sortOrder
        let _ = filter
        return filterableItems
    }

    public func applyFilterGroup(filterableItems: FilterableList, filterGroup: FilterGroup): FilterableList {
        let _ = filterGroup
        return filterableItems
    }
}

/**
 * Mirrors iOS `Filter<T>`: keeps the predicate shape over attributes; consumers
 * downcast inside the predicate where iOS used the generic constraint.
 */
public class Filter <: FilterAction {
    public let predicate: (FilterableAttributes, FilterItem) -> Bool

    public init(predicate!: (FilterableAttributes, FilterItem) -> Bool) {
        this.predicate = predicate
    }

    public func applyFilter(sortOrder: SortOrderType, filterableItems: FilterableList, filter: FilterItem): FilterableList {
        let _ = sortOrder
        let kept = ArrayList<FilterableItem>()
        for (item in filterableItems.items) {
            if (predicate(item.attributes, filter)) {
                kept.add(item)
            }
        }
        return filterableItems.withItems(kept.toArray())
    }

    public func applyFilterGroup(filterableItems: FilterableList, filterGroup: FilterGroup): FilterableList {
        let _ = filterGroup
        return filterableItems
    }
}

/** Mirrors iOS `FilterMultipleAction<T>`: any selected filter matching keeps the item. */
public class FilterMultipleAction <: FilterAction {
    public let predicate: (FilterableAttributes, FilterItem) -> Bool

    public init(predicate!: (FilterableAttributes, FilterItem) -> Bool) {
        this.predicate = predicate
    }

    public func applyFilter(sortOrder: SortOrderType, filterableItems: FilterableList, filter: FilterItem): FilterableList {
        let _ = sortOrder
        let _ = filter
        return filterableItems
    }

    public func applyFilterGroup(filterableItems: FilterableList, filterGroup: FilterGroup): FilterableList {
        let selectedFilters = ArrayList<FilterItem>()
        for (filter in filterGroup.filters) {
            if (filter.selected) {
                selectedFilters.add(filter)
            }
        }
        if (selectedFilters.isEmpty()) {
            return filterableItems
        }
        let matching = ArrayList<FilterableItem>()
        for (item in filterableItems.items) {
            var matched = false
            for (filter in selectedFilters) {
                if (predicate(item.attributes, filter)) {
                    matched = true
                    break
                }
            }
            if (matched) {
                matching.add(item)
            }
        }
        return FilterableList(matching.toArray())
    }
}

/**
 * Mirrors iOS `Sort<T, R>`: items whose key selector yields None sink to the
 * end (Swift nil-handling preserved); string keys compare case-insensitively
 * like localizedCaseInsensitiveCompare.
 */
public class SortAction <: SortFilterAction {
    public let keySelector: (FilterableAttributes) -> ?String

    public init(keySelector!: (FilterableAttributes) -> ?String) {
        this.keySelector = keySelector
    }

    public func applyFilter(sortOrder: SortOrderType, filterableItems: FilterableList, filter: FilterItem): FilterableList {
        let _ = filter
        let sorted = filterableItems.items.clone()
        let ascendingOrder = sortOrder == SortOrderType.ascending
        sort<FilterableItem>(
            sorted,
            lessThan: {
                a, b =>
                let lhs = keySelector(a.attributes)
                let rhs = keySelector(b.attributes)
                match ((lhs, rhs)) {
                    case (None, None) => false
                    case (None, Some(_)) => false
                    case (Some(_), None) => true
                    case (Some(l), Some(r)) =>
                        let left = l.toAsciiLower()
                        let right = r.toAsciiLower()
                        if (ascendingOrder) {
                            left < right
                        } else {
                            left > right
                        }
                }
            },
            stable: true
        )
        return FilterableList(sorted)
    }

    public func applyFilterGroup(filterableItems: FilterableList, filterGroup: FilterGroup): FilterableList {
        let _ = filterGroup
        return filterableItems
    }
}

/** Mirrors iOS `FilterResult`. */
public enum FilterResult {
    | filterApplyResult(FilterableList, Filters, Bool) // filteredList, updatedFilters, hasDefaultFilters
    | filterUpdateResult(Filters)                      // updatedFilters
}

/** Mirrors iOS `FilterResultPartialState`. */
public enum FilterResultPartialState {
    | success(FilterResult)
    | completion
}

/** Mirrors iOS `FilterIds`. */
public class FilterIds {
    public static let ASCENDING_DESCENDING_GROUP = "ascending_descending_group"
    public static let DOCUMENT_SIGNING_GROUP = "document_signing_group"
    public static let ORDER_BY_ASCENDING = "order_by_ascending"
    public static let ORDER_BY_DESCENDING = "order_by_descending"
    public static let FILTER_BY_STATE_GROUP_ID = "state_group_id"
    public static let FILTER_BY_STATUS_ID = "status_id"
    public static let FILTER_BY_TYPE_ID = "type_id"
    public static let FILTER_BY_RELYING_PARY_NAME = "relying_party_name"
    public static let FILTER_BY_ATTESTATION_NAME = "attestation_name"
    public static let FILTER_BY_DOCUMENT_SIGNING = "document_signing"
    public static let FILTER_BY_STATE_VALID = "state_valid"
    public static let FILTER_BY_STATE_EXPIRED = "state_expired"
    public static let FILTER_BY_STATUS_COMPLETED = "status_completed"
    public static let FILTER_BY_TRANSACTION_DATE_GROUP_ID = "transaction_date_group_id"
    public static let FILTER_BY_TRANSACTION_DATE_RANGE = "by_transaction_date_range"
    public static let FILTER_BY_STATUS_FAILED = "status_failed"
    public static let FILTER_BY_STATE_REVOKED = "state_revoked"
    public static let FILTER_BY_DOCUMENT_CATEGORY_GROUP_ID = "category_group_id"
    public static let FILTER_BY_ISSUER_GROUP_ID = "issuer_group_id"
    public static let FILTER_BY_PERIOD_GROUP_ID = "by_period_group_id"
    public static let FILTER_BY_PERIOD_DEFAULT = "by_period_default"
    public static let FILTER_BY_PERIOD_NEXT_7 = "by_period_next_7"
    public static let FILTER_BY_PERIOD_NEXT_30 = "by_period_next_30"
    public static let FILTER_BY_PERIOD_BEYOND_30 = "by_period_beyond_30"
    public static let FILTER_BY_PERIOD_EXPIRED = "by_period_expired"
    public static let FILTER_SORT_GROUP_ID = "sort_group_id"
    public static let FILTER_SORT_DEFAULT = "sort_default"
    public static let FILTER_SORT_DATE_ISSUED = "sort_date_issued"
    public static let FILTER_SORT_EXPIRY_DATE = "sort_expiry_date"
    public static let FILTER_BY_TYPE_PRESENTATION = "presentation"
    public static let FILTER_BY_TYPE_SIGNING = "signing"
    public static let FILTER_BY_TYPE_ISSUANCE = "issuance"
    public static let FILTER_BY_RELYING_PARTY_NONE = "relying_party_name_none"
}
