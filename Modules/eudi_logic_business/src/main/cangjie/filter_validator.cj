/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Validator/FilterValidator.swift) to Cangjie.
 *
 * The Combine `SendablePassthroughSubject` / `getFilterResultStream()` pair is
 * replaced by the project-standard single-slot listener
 * (`setFilterResultListener`); every state mutation emits the same
 * `FilterResultPartialState` values the iOS stream publishes. The Swift actor
 * methods become synchronous (pure in-memory engine).
 */
package eudi_logic_business

import std.collection.ArrayList
import std.time.DateTime

/** Mirrors the iOS `FilterValidator` protocol. */
public interface FilterValidator {
    /** Replaces `getFilterResultStream()`: at most one active observer. */
    func setFilterResultListener(listener: (FilterResultPartialState) -> Unit): Unit
    func initializeValidator(filters: Filters, filterableList: FilterableList): Unit
    func updateLists(sortOrder: SortOrderType, filterableList: FilterableList): Unit
    func applyFilters(sortOrder: SortOrderType): Unit
    func applySearch(query: String): Unit
    func resetFilters(): Unit
    func revertFilters(): Unit
    func updateFilter(filterGroupId: String, filterId: String): Unit
    func updateDateFilters(filterGroupId: String, filterId: String, startDate: DateTime, endDate: DateTime): Unit
    func updateSortOrder(sortOrder: SortOrderType): Unit
    func updateSort(filterId: String): Unit
}

/** Mirrors iOS `FilterValidatorImpl` (444-line engine, ported 1:1). */
public class FilterValidatorImpl <: FilterValidator {

    private var appliedFilters: Filters
    private var defaultFilters: Filters
    private var searchQuery: String = ""
    private var initialList: FilterableList
    private var snapshotFilters: Filters = Filters.emptyFilters()
    private var hasDefaultFilters: Bool = false
    private var listener: Option<(FilterResultPartialState) -> Unit> = None

    public init(
        filters!: ?Filters = None,
        initialFilters!: ?Filters = None,
        initialList!: ?FilterableList = None
    ) {
        this.appliedFilters = filters ?? Filters.emptyFilters()
        this.defaultFilters = initialFilters ?? Filters.emptyFilters()
        this.initialList = initialList ?? FilterableList(Array<FilterableItem>())
    }

    public func setFilterResultListener(listener: (FilterResultPartialState) -> Unit): Unit {
        this.listener = listener
    }

    /** Mirrors the iOS deinit stream completion for explicit teardown. */
    public func complete(): Unit {
        send(FilterResultPartialState.completion)
        this.listener = None
    }

    public func initializeValidator(filters: Filters, filterableList: FilterableList): Unit {
        this.defaultFilters = filters
        let mergedFilterGroups = ArrayList<FilterGroup>()

        for (newFilterGroup in filters.filterGroups) {
            var existing: ?FilterGroup = None
            for (group in this.appliedFilters.filterGroups) {
                if (group.id == newFilterGroup.id) {
                    existing = group
                    break
                }
            }
            match (existing) {
                case Some(existingFilterGroup) =>
                    mergedFilterGroups.add(mergeFilters(newFilterGroup, existingFilterGroup))
                case None =>
                    mergedFilterGroups.add(newFilterGroup)
            }
        }

        let mergedSort: ?FilterSort = if (this.appliedFilters.isEmpty) {
            filters.sort
        } else {
            mergeSort(filters.sort, this.appliedFilters.sort)
        }

        let sortOrder = if (this.appliedFilters.isEmpty) {
            this.defaultFilters.sortOrder
        } else {
            this.appliedFilters.sortOrder
        }

        this.appliedFilters = Filters(
            filterGroups: mergedFilterGroups.toArray(),
            sortOrder: sortOrder,
            sort: mergedSort
        )

        this.initialList = filterableList
    }

    public func applyFilters(sortOrder: SortOrderType): Unit {
        if (!this.snapshotFilters.isEmpty) {
            this.appliedFilters = this.snapshotFilters.copyAll()
            this.snapshotFilters = Filters.emptyFilters(sortOrder: sortOrder)
        }

        var filteredList = this.initialList
        for (group in this.appliedFilters.filterGroups) {
            if (group is MultipleSelectionFilterGroup) {
                filteredList = applyMultipleSelectionFilter(filteredList, (group as MultipleSelectionFilterGroup).getOrThrow())
            } else if (group is ReversibleMultipleSelectionFilterGroup) {
                filteredList = applyReversibleMultipleSelectionFilter(filteredList, (group as ReversibleMultipleSelectionFilterGroup).getOrThrow())
            } else if (group is SingleSelectionFilterGroup) {
                filteredList = applySingleSelectionFilter(filteredList, (group as SingleSelectionFilterGroup).getOrThrow())
            } else if (group is ReversibleSingleSelectionFilterGroup) {
                filteredList = applyReversibleSingleSelectionFilter(filteredList, (group as ReversibleSingleSelectionFilterGroup).getOrThrow())
            }
        }

        // Apply the active sort last so the reduce above does not disturb its ordering.
        filteredList = filteredList.applySort(this.appliedFilters)

        this.hasDefaultFilters = checkIfDefaultFiltersApplied(
            this.appliedFilters.filterGroups,
            this.appliedFilters.sort
        )

        if (!this.searchQuery.isEmpty()) {
            let query = this.searchQuery.toAsciiLower()
            let kept = ArrayList<FilterableItem>()
            for (item in filteredList.items) {
                var matched = false
                for (tag in item.attributes.searchTags) {
                    if (tag.toAsciiLower().contains(query)) {
                        matched = true
                        break
                    }
                }
                if (matched) {
                    kept.add(item)
                }
            }
            filteredList = filteredList.withItems(kept.toArray())
        }

        send(
            FilterResultPartialState.success(
                FilterResult.filterApplyResult(filteredList, this.appliedFilters, this.hasDefaultFilters)
            )
        )
    }

    public func resetFilters(): Unit {
        this.appliedFilters = this.defaultFilters
        this.snapshotFilters = Filters.emptyFilters()
        applyFilters(SortOrderType.ascending)
    }

    public func updateFilter(filterGroupId: String, filterId: String): Unit {
        let filtersUpdate = if (this.snapshotFilters.isEmpty) { this.appliedFilters } else { this.snapshotFilters }

        let updatedFilterGroups = ArrayList<FilterGroup>()
        for (group in filtersUpdate.filterGroups) {
            if (group.id == filterGroupId) {
                updatedFilterGroups.add(updateFilterInGroup(group, filterId, None, None))
            } else {
                updatedFilterGroups.add(group)
            }
        }

        let sortOrder = resolveSortOrder(updatedFilterGroups)
        this.snapshotFilters = filtersUpdate.withGroupsAndOrder(updatedFilterGroups.toArray(), sortOrder)

        send(
            FilterResultPartialState.success(
                FilterResult.filterUpdateResult(this.snapshotFilters)
            )
        )
    }

    public func updateDateFilters(
        filterGroupId: String,
        filterId: String,
        startDate: DateTime,
        endDate: DateTime
    ): Unit {
        let filtersUpdate = if (this.snapshotFilters.isEmpty) { this.appliedFilters } else { this.snapshotFilters }

        let updatedFilterGroups = ArrayList<FilterGroup>()
        for (group in filtersUpdate.filterGroups) {
            if (group.id == filterGroupId) {
                updatedFilterGroups.add(updateFilterInGroup(group, filterId, startDate, endDate))
            } else {
                updatedFilterGroups.add(group)
            }
        }

        let sortOrder = resolveSortOrder(updatedFilterGroups)
        this.snapshotFilters = filtersUpdate.withGroupsAndOrder(updatedFilterGroups.toArray(), sortOrder)

        send(
            FilterResultPartialState.success(
                FilterResult.filterUpdateResult(this.snapshotFilters)
            )
        )
    }

    public func revertFilters(): Unit {
        this.snapshotFilters = Filters.emptyFilters()
        send(
            FilterResultPartialState.success(
                FilterResult.filterUpdateResult(this.appliedFilters)
            )
        )
    }

    public func applySearch(query: String): Unit {
        this.searchQuery = query
        applyFilters(SortOrderType.ascending)
    }

    public func updateSortOrder(sortOrder: SortOrderType): Unit {
        let filterToUpdateOrderChange = if (this.snapshotFilters.isEmpty) { this.appliedFilters } else { this.snapshotFilters }
        this.snapshotFilters = filterToUpdateOrderChange.withSortOrder(sortOrder)

        send(
            FilterResultPartialState.success(
                FilterResult.filterUpdateResult(this.snapshotFilters)
            )
        )
    }

    public func updateSort(filterId: String): Unit {
        let filtersToUpdate = if (this.snapshotFilters.isEmpty) { this.appliedFilters } else { this.snapshotFilters }

        let currentSort: FilterSort
        match (filtersToUpdate.sort) {
            case Some(s) => currentSort = s
            case None => return
        }

        let updatedSortFilters = ArrayList<FilterItem>()
        for (filter in currentSort.filters) {
            updatedSortFilters.add(filter.withSelected(filter.id == filterId))
        }
        let updatedSort = currentSort.withFilters(updatedSortFilters.toArray())

        this.snapshotFilters = filtersToUpdate.withSort(updatedSort)

        send(
            FilterResultPartialState.success(
                FilterResult.filterUpdateResult(this.snapshotFilters)
            )
        )
    }

    public func updateLists(sortOrder: SortOrderType, filterableList: FilterableList): Unit {
        this.initialList = filterableList.sortedByOrder(sortOrder) { item => item.attributes.sortingKey }
    }

    /** Exposed for tests, mirrors `appliedFiltersForTesting`. */
    public prop appliedFiltersForTesting: Filters {
        get() { this.appliedFilters }
    }

    private func send(state: FilterResultPartialState): Unit {
        match (this.listener) {
            case Some(notify) =>
                try { notify(state) } catch (_: Exception) {}
            case None => ()
        }
    }

    private func resolveSortOrder(groups: ArrayList<FilterGroup>): SortOrderType {
        // Mirrors the iOS orderBy-group scan: ascending when the selected order filter is ORDER_BY_ASCENDING.
        for (group in groups) {
            if (group.filterType != FilterGroupType.orderBy) {
                continue
            }
            for (filter in group.filters) {
                if (filter.selected) {
                    return if (filter.id == FilterIds.ORDER_BY_ASCENDING) {
                        SortOrderType.ascending
                    } else {
                        SortOrderType.descending
                    }
                }
            }
        }
        return SortOrderType.descending
    }

    private func applyMultipleSelectionFilter(
        currentList: FilterableList,
        group: MultipleSelectionFilterGroup
    ): FilterableList {
        var anySelected = false
        for (filter in group.filters) {
            if (filter.selected) {
                anySelected = true
                break
            }
        }
        if (anySelected) {
            return group.filterableAction.applyFilterGroup(currentList, group)
        }
        return FilterableList(Array<FilterableItem>())
    }

    private func applyReversibleMultipleSelectionFilter(
        currentList: FilterableList,
        group: ReversibleMultipleSelectionFilterGroup
    ): FilterableList {
        var anySelected = false
        for (filter in group.filters) {
            if (filter.selected) {
                anySelected = true
                break
            }
        }
        if (anySelected) {
            return group.filterableAction.applyFilterGroup(currentList, group)
        }
        return currentList
    }

    private func applySingleSelectionFilter(
        currentList: FilterableList,
        group: SingleSelectionFilterGroup
    ): FilterableList {
        let selectedFilter: FilterItem
        match (firstSelected(group.filters)) {
            case Some(filter) => selectedFilter = filter
            // No selection in a single-selection group means "no constraint"
            // (show all), matching applyReversibleSingleSelectionFilter. The
            // document "Filter by state" group defaults to all-unselected, so
            // returning an empty list here wrongly filtered out every document
            // once the wallet actually held one.
            case None => return currentList
        }

        // Sorting is handled by applySort after the group reduce; skip sort actions here.
        if (selectedFilter.filterableAction is SortFilterAction) {
            return currentList
        }

        return selectedFilter.filterableAction.applyFilter(
            this.appliedFilters.sortOrder,
            currentList,
            selectedFilter
        )
    }

    private func applyReversibleSingleSelectionFilter(
        currentList: FilterableList,
        group: ReversibleSingleSelectionFilterGroup
    ): FilterableList {
        let selectedFilter: FilterItem
        match (firstSelected(group.filters)) {
            case Some(filter) => selectedFilter = filter
            case None => return currentList
        }

        if (selectedFilter.filterableAction is SortFilterAction) {
            return currentList
        }

        return selectedFilter.filterableAction.applyFilter(
            this.appliedFilters.sortOrder,
            currentList,
            selectedFilter
        )
    }

    private func firstSelected(filters: Array<FilterItem>): ?FilterItem {
        for (filter in filters) {
            if (filter.selected) {
                return filter
            }
        }
        return None
    }

    private func mergeFilters(newFilterGroup: FilterGroup, existingFilterGroup: FilterGroup): FilterGroup {
        let mergedFilters = ArrayList<FilterItem>()
        for (newFilter in newFilterGroup.filters) {
            var existing: ?FilterItem = None
            for (filter in existingFilterGroup.filters) {
                if (filter.id == newFilter.id) {
                    existing = filter
                    break
                }
            }
            match (existing) {
                case Some(existingFilter) =>
                    mergedFilters.add(
                        newFilter.withSelectedAndDates(
                            existingFilter.selected,
                            existingFilter.startDate,
                            existingFilter.endDate
                        )
                    )
                case None =>
                    mergedFilters.add(newFilter)
            }
        }
        return newFilterGroup.copyWithFilters(mergedFilters.toArray())
    }

    private func updateFilterInGroup(
        group: FilterGroup,
        filterId: String,
        startDate: ?DateTime,
        endDate: ?DateTime
    ): FilterGroup {
        if (group is MultipleSelectionFilterGroup || group is ReversibleMultipleSelectionFilterGroup ||
            group is ReversibleSingleSelectionFilterGroup) {
            // Toggle semantics shared by multiple-selection and reversible-single groups.
            let updated = ArrayList<FilterItem>()
            for (filter in group.filters) {
                if (filter.id == filterId) {
                    updated.add(filter.withSelected(!filter.selected))
                } else {
                    updated.add(filter)
                }
            }
            return group.copyWithFilters(updated.toArray())
        }

        if (group is SingleSelectionFilterGroup) {
            let updated = ArrayList<FilterItem>()
            for (filter in group.filters) {
                if (filter.id == FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE) {
                    updated.add(filter.withDates(startDate, endDate))
                } else {
                    updated.add(filter.withSelected(filter.id == filterId))
                }
            }
            return group.copyWithFilters(updated.toArray())
        }

        return group
    }

    private func checkIfDefaultFiltersApplied(groups: Array<FilterGroup>, sort: ?FilterSort): Bool {
        let allFilters = ArrayList<FilterItem>()
        for (group in groups) {
            for (filter in group.filters) {
                allFilters.add(filter)
            }
        }
        match (sort) {
            case Some(s) =>
                for (filter in s.filters) {
                    allFilters.add(filter)
                }
            case None => ()
        }

        var allSelectedAreDefault = true
        var allUnselectedAreNotDefault = true
        for (filter in allFilters) {
            if (filter.selected && !filter.isDefault) {
                allSelectedAreDefault = false
            }
            if (!filter.selected && filter.isDefault) {
                allUnselectedAreNotDefault = false
            }
        }
        return allSelectedAreDefault && allUnselectedAreNotDefault
    }

    private func mergeSort(newSort: ?FilterSort, existingSort: ?FilterSort): ?FilterSort {
        let target: FilterSort
        match (newSort) {
            case Some(s) => target = s
            case None => return None
        }
        let existing: FilterSort
        match (existingSort) {
            case Some(s) => existing = s
            case None => return target
        }

        let mergedFilters = ArrayList<FilterItem>()
        for (newFilter in target.filters) {
            var found: ?FilterItem = None
            for (filter in existing.filters) {
                if (filter.id == newFilter.id) {
                    found = filter
                    break
                }
            }
            match (found) {
                case Some(existingFilter) =>
                    mergedFilters.add(newFilter.withSelected(existingFilter.selected))
                case None =>
                    mergedFilters.add(newFilter)
            }
        }
        return target.withFilters(mergedFilters.toArray())
    }
}

/** Factory replacing the iOS Swinject assembly registration for FilterValidator. */
public func createFilterValidator(): FilterValidator {
    return FilterValidatorImpl()
}
