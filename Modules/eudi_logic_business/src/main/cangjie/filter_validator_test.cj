/*
 * filter_validator_test.cj — Cangjie unit tests for FilterValidator, migrated
 * from the iOS logic-business test suite (Tests/TestFilterValidator.swift).
 *
 * iOS source: 23 test functions in TestFilterValidator.swift + TestData.swift.
 * All 23 semantics are represented here; numbering in comments refers to their
 * position in the iOS file for traceability.
 *
 * Cangjie port notes:
 * - iOS uses Combine async streams; Cangjie uses a synchronous listener
 *   (setFilterResultListener) and the appliedFiltersForTesting testing hook.
 * - iOS SingleSelectionGroup with no selection historically returned an empty
 *   list; the Cangjie production code was intentionally changed to return the
 *   original list (matches ReversibleSingleSelection semantics and avoids
 *   filtering out all documents when "Document State" group is all-unselected).
 *   Tests 18-20 reflect the Cangjie production behaviour.
 * - No mock framework: hand-written TPayload / TAttrs / ResultBox replace Cuckoo.
 *
 * Layout: co-located with production source (*_test.cj), same package
 * eudi_logic_business. cjpm test discovers this file; cjpm build ignores it.
 * Run on macOS host: ./run_tests.sh eudi_logic_business
 */
package eudi_logic_business

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.time.DateTime

// ── Minimal test-doubles for the two payload/attributes interfaces ──────────

class TPayload <: FilterableItemPayload {
    let id_: String
    public init(id!: String) { this.id_ = id }
    public prop id: String { get() { this.id_ } }
}

class TAttrs <: FilterableAttributes {
    let key_: String
    let tags_: Array<String>
    let name_: String
    public init(key!: String, tags!: Array<String>, name!: String) {
        this.key_ = key
        this.tags_ = tags
        this.name_ = name
    }
    public prop sortingKey: String { get() { this.key_ } }
    public prop searchTags: Array<String> { get() { this.tags_ } }
    public prop name: String { get() { this.name_ } }
}

// Captures the last FilterResult emitted by the validator's listener.
// Uses Option<...>.None (not bare None) to stay unambiguous when consolidated
// into the entry package which has `import kit.ArkUI.*`.
class ResultBox {
    var result: Option<FilterResult> = Option<FilterResult>.None
}

// Keeps every emission in arrival order. ResultBox overwrites on each emission,
// which is enough for the single-emission tests but cannot see a sequence — iOS
// asserts on results[0] / results[1] of its AsyncStream, so the sequence tests
// need the full history.
class CaptureBox {
    let states = ArrayList<FilterResultPartialState>()

    func attach(v: FilterValidatorImpl): Unit {
        v.setFilterResultListener({ s => this.states.add(s) })
    }

    // Payload of the nth emission; None when it is absent or terminal.
    func resultAt(index: Int64): Option<FilterResult> {
        if (index >= this.states.size) {
            return Option<FilterResult>.None
        }
        match (this.states[index]) {
            case FilterResultPartialState.success(r) => Some(r)
            case _ => Option<FilterResult>.None
        }
    }
}

func isApplyResult(r: Option<FilterResult>): Bool {
    match (r) {
        case Some(FilterResult.filterApplyResult(_, _, _)) => true
        case _ => false
    }
}

// ── Test data, mirroring TestData.swift ────────────────────────────────────

// Predicate matching attribute name == filter name (mirrors iOS Filter<TestAttributes>)
func namePredicate(): (FilterableAttributes, FilterItem) -> Bool {
    return { attrs, filterItem =>
        if (attrs is TAttrs) {
            return (attrs as TAttrs).getOrThrow().name == filterItem.name
        }
        return false
    }
}

// filterItemsSingle[0..2] — mirrors iOS filterItemSingle1/2/3
func makeFilterItemsSingle(): Array<FilterItem> {
    return [
        FilterItem(
            id: "1",
            name: "PID",
            selected: true,
            isDefault: true,
            filterableAction: Filter(predicate: namePredicate())
        ),
        FilterItem(
            id: "2",
            name: "mDL",
            selected: false,
            filterableAction: Filter(predicate: namePredicate())
        ),
        FilterItem(
            id: "3",
            name: "Age Verification",
            selected: false,
            filterableAction: Filter(predicate: namePredicate())
        )
    ]
}

// filterItemsMultipleNoSelections
func makeFilterItemsMultipleNoSelections(): Array<FilterItem> {
    return [
        FilterItem(id: "1", name: "PID", selected: false),
        FilterItem(id: "2", name: "mDL", selected: false),
        FilterItem(id: "3", name: "Age Verification", selected: false),
        FilterItem(id: "4", name: "Search Test", selected: false),
        FilterItem(id: "5", name: "NO OP", selected: false)
    ]
}

// filterItemsMultiple (for reset/revert tests)
func makeFilterItemsMultiple(): Array<FilterItem> {
    return [
        FilterItem(id: "1", name: "PID", selected: false),
        FilterItem(id: "2", name: "mDL", selected: true),
        FilterItem(id: "3", name: "Age Verification", selected: true),
        FilterItem(id: "4", name: "Search Test", selected: false),
        FilterItem(id: "5", name: "NO OP", selected: false)
    ]
}

// filterItemsMultipleAllSelected
func makeFilterItemsMultipleAllSelected(): Array<FilterItem> {
    return [
        FilterItem(id: "1", name: "PID", selected: true),
        FilterItem(id: "2", name: "mDL", selected: true),
        FilterItem(id: "3", name: "Age Verification", selected: true),
        FilterItem(id: "4", name: "Search Test", selected: true),
        FilterItem(id: "5", name: "NO OP", selected: true)
    ]
}

// filterItemsMultipleSize3 / Size4
func makeFilterItemsMultipleSize3(): Array<FilterItem> {
    return [
        FilterItem(id: "1", name: "PID", selected: false),
        FilterItem(id: "2", name: "mDL", selected: true),
        FilterItem(id: "3", name: "Age Verification", selected: true)
    ]
}

func makeFilterItemsMultipleSize4(): Array<FilterItem> {
    return [
        FilterItem(id: "1", name: "PID", selected: true),
        FilterItem(id: "2", name: "mDL", selected: true),
        FilterItem(id: "3", name: "Age Verification", selected: true),
        FilterItem(id: "4", name: "New Filter", selected: true)
    ]
}

// singleSelectionGroup
func makeSingleSelectionGroup(): SingleSelectionFilterGroup {
    return SingleSelectionFilterGroup(
        id: "single_filter",
        name: "Document Selection",
        filters: makeFilterItemsSingle(),
        filterType: FilterGroupType.other
    )
}

// multipleSelectionGroup (for reset/revert)
func makeMultipleSelectionGroup(): MultipleSelectionFilterGroup {
    return MultipleSelectionFilterGroup(
        id: "multi_filter",
        name: "Multi Document Selection",
        filters: makeFilterItemsMultiple(),
        filterableAction: FilterMultipleAction(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

// multipleSelectionGroupSize3 / Size4
func makeMultipleSelectionGroupSize3(): MultipleSelectionFilterGroup {
    return MultipleSelectionFilterGroup(
        id: "multi_filter",
        name: "Multi Document Selection",
        filters: makeFilterItemsMultipleSize3(),
        filterableAction: Filter(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

func makeMultipleSelectionGroupSize4(): MultipleSelectionFilterGroup {
    return MultipleSelectionFilterGroup(
        id: "multi_filter",
        name: "Multi Document Selection",
        filters: makeFilterItemsMultipleSize4(),
        filterableAction: FilterMultipleAction(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

// multipleSelectionGroupNoSelection
func makeMultipleSelectionGroupNoSelection(): MultipleSelectionFilterGroup {
    return MultipleSelectionFilterGroup(
        id: "multi_filter_noselection",
        name: "Multi Document Selection",
        filters: makeFilterItemsMultipleNoSelections(),
        filterableAction: FilterMultipleAction(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

// multipleSelectionGroupAllSelected
func makeMultipleSelectionGroupAllSelected(): MultipleSelectionFilterGroup {
    return MultipleSelectionFilterGroup(
        id: "multi_filter_all",
        name: "Multi Document Selection All",
        filters: makeFilterItemsMultipleAllSelected(),
        filterableAction: FilterMultipleAction(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

// reversibleSelectionGroup (reversible single)
func makeReversibleSingleSelectionGroup(): ReversibleSingleSelectionFilterGroup {
    return ReversibleSingleSelectionFilterGroup(
        id: "reversible_filter",
        name: "Reversible Document Selection",
        filters: makeFilterItemsSingle(),
        filterType: FilterGroupType.other
    )
}

// reversibleMultiSelectionGroup
func makeReversibleMultiSelectionGroup(): ReversibleMultipleSelectionFilterGroup {
    return ReversibleMultipleSelectionFilterGroup(
        id: "reversible_multi_filter",
        name: "Reversible Multi Document Selection",
        filters: makeFilterItemsMultiple(),
        filterableAction: FilterMultipleAction(predicate: namePredicate()),
        filterType: FilterGroupType.other
    )
}

// Pre-built Filters bundles
func filtersWithSingleSelection(): Filters {
    return Filters(filterGroups: [makeSingleSelectionGroup()], sortOrder: SortOrderType.ascending)
}

func filtersWithMultipleSelectionSize3(): Filters {
    return Filters(filterGroups: [makeMultipleSelectionGroupSize3()], sortOrder: SortOrderType.descending)
}

func filtersWithMultipleSelectionSize4(): Filters {
    return Filters(filterGroups: [makeMultipleSelectionGroupSize4()], sortOrder: SortOrderType.descending)
}

func filtersWithMultipleSelection(): Filters {
    return Filters(filterGroups: [makeMultipleSelectionGroup()], sortOrder: SortOrderType.descending)
}

func filtersWithReversibleSingleSelection(): Filters {
    return Filters(filterGroups: [makeReversibleSingleSelectionGroup()], sortOrder: SortOrderType.descending)
}

func filtersWithReversibleMultipleSelection(): Filters {
    return Filters(filterGroups: [makeReversibleMultiSelectionGroup()], sortOrder: SortOrderType.descending)
}

func filtersWithMultipleSelectionNoSelection(): Filters {
    return Filters(filterGroups: [makeMultipleSelectionGroupNoSelection()], sortOrder: SortOrderType.descending)
}

func filtersWithMultipleSelectionAllSelected(): Filters {
    return Filters(filterGroups: [makeMultipleSelectionGroupAllSelected()], sortOrder: SortOrderType.ascending)
}

// filterableList — 7 items mirroring iOS TestData.swift
func makeFilterableList(): FilterableList {
    return FilterableList([
        FilterableItem(
            TPayload(id: "item1"),
            TAttrs(key: "PID", tags: ["PID"], name: "PID")
        ),
        FilterableItem(
            TPayload(id: "item2"),
            TAttrs(key: "PID", tags: ["mDL"], name: "mDL")
        ),
        FilterableItem(
            TPayload(id: "item3"),
            TAttrs(key: "PID", tags: ["Age Verification"], name: "Age Verification")
        ),
        FilterableItem(
            TPayload(id: "item4"),
            TAttrs(key: "PID", tags: ["PID", "PIDIssuer"], name: "PID")
        ),
        FilterableItem(
            TPayload(id: "item5"),
            TAttrs(key: "PID", tags: [], name: "PID")
        ),
        FilterableItem(
            TPayload(id: "item6"),
            TAttrs(key: "PID", tags: ["search text", "secondary text"], name: "Search Test")
        ),
        FilterableItem(
            TPayload(id: "item7"),
            TAttrs(key: "PID", tags: ["no op"], name: "NO OP")
        )
    ])
}

// Helper: create a validator, initialize it, attach listener, return both.
func newValidatorWith(f: Filters): (FilterValidatorImpl, ResultBox) {
    let v = FilterValidatorImpl()
    v.initializeValidator(f, makeFilterableList())
    let box = ResultBox()
    v.setFilterResultListener({ s =>
        match (s) {
            case FilterResultPartialState.success(r) => box.result = Some(r)
            case _ => ()
        }
    })
    return (v, box)
}

// ── Empty-group helpers (used by the original 7 tests) ─────────────────────

func emptyGroupFilters(): Filters {
    return Filters(filterGroups: Array<FilterGroup>(), sortOrder: SortOrderType.ascending)
}

func oneGroupFilters(): Filters {
    let fi = FilterItem(id: "x", name: "X", selected: true, isDefault: true)
    let g = SingleSelectionFilterGroup(id: "g1", name: "G1", filters: [fi], filterType: FilterGroupType.other)
    return Filters(filterGroups: [g], sortOrder: SortOrderType.ascending)
}

func mkItem(id: String, tags: Array<String>): FilterableItem {
    return FilterableItem(TPayload(id: id), TAttrs(key: id, tags: tags, name: id))
}

func sampleList(): FilterableList {
    return FilterableList([mkItem("a", ["alpha"]), mkItem("b", ["beta"]), mkItem("c", ["alphabet"])])
}

func newSimpleValidatorWith(filters: Filters): (FilterValidatorImpl, ResultBox) {
    let v = FilterValidatorImpl()
    v.initializeValidator(filters, sampleList())
    let box = ResultBox()
    v.setFilterResultListener({ s =>
        match (s) {
            case FilterResultPartialState.success(r) => box.result = Some(r)
            case _ => ()
        }
    })
    return (v, box)
}

// ════════════════════════════════════════════════════════════════════════════
@Test
class FilterValidatorTest {

    // ── Test 1 (iOS: testInitializeValidator) ────────────────────────────
    // initializeValidator merges the supplied groups into appliedFilters.
    @TestCase
    func testInitializeSetsAppliedGroups(): Unit {
        let v = FilterValidatorImpl()
        v.initializeValidator(oneGroupFilters(), sampleList())
        @Expect(v.appliedFiltersForTesting.filterGroups.size, 1)
    }

    // ── Test 2 (iOS: testInitializeValidator_whenApplyFilters_ThenEmitsFilterApplyResult)
    // init + applyFilters emits filterApplyResult with same group count.
    @TestCase
    func testInitializeThenApplyFiltersEmitsFilterApplyResult(): Unit {
        let expectedFilters = filtersWithSingleSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 3 (iOS: testInitializeValidator_WhenCalledTwiceWithSameAppliedFilters_ThenEmitsMergedFilterUpdate)
    // Two identical inits → applyFilters yields same group count (merge is idempotent).
    @TestCase
    func testInitializeTwiceSameFiltersGroupCountPreserved(): Unit {
        let expectedFilters = filtersWithSingleSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        // Second init with same filters — validator already initialized
        v.initializeValidator(expectedFilters, makeFilterableList())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 4 (iOS: testInitializeValidator_WhenCalledTwiceWithDifferentFilters_ThenEmitsMergedFilterUpdate)
    // Init with 3-item group, then re-init with 4-item group having same id →
    // merged selection of first item == original first item's selected value.
    @TestCase
    func testInitializeTwiceDifferentFiltersPreservesFirstSelection(): Unit {
        let initialFilters = filtersWithMultipleSelectionSize3()
        let updatedFilters = filtersWithMultipleSelectionSize4()
        let (v, box) = newValidatorWith(initialFilters)
        // Re-initialize with different (size-4) filters having the same group id
        v.initializeValidator(updatedFilters, makeFilterableList())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, resultFilters, _)) =>
                // First filter's selected flag should be preserved from initialFilters
                let firstFromResult = resultFilters.filterGroups[0].filters[0].selected
                let firstFromInitial = initialFilters.filterGroups[0].filters[0].selected
                @Expect(firstFromResult, firstFromInitial)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 5 (iOS: testUpdateList_WhenApplyFiltersCalled_ThenEmitsCorrectFilterUpdate)
    // updateLists + applyFilters → filter count preserved.
    @TestCase
    func testUpdateListsThenApplyFiltersPreservesFilterCount(): Unit {
        let expectedFilters = filtersWithSingleSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        v.updateLists(SortOrderType.ascending, makeFilterableList())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(
                    updatedFilters.filterGroups[0].filters.size,
                    expectedFilters.filterGroups[0].filters.size
                )
            case _ => @Expect(false, true)
        }
    }

    // ── Test 6 (iOS: testUpdateFilters_WhenCalledAppliedFilters_ThenEmitsCorrectFilterUpdate)
    // updateFilter with singleSelection group id + filter[2].id → that item selected.
    @TestCase
    func testUpdateFilterSelectsCorrectItem(): Unit {
        let expectedFilters = filtersWithSingleSelection()
        let items = makeFilterItemsSingle()
        let group = makeSingleSelectionGroup()
        let (v, box) = newValidatorWith(expectedFilters)
        v.updateFilter(group.id, items[2].id)
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                let updated = updatedFilters.filterGroups[0]
                var found = false
                for (f in updated.filters) {
                    if (f.id == items[2].id && f.selected) {
                        found = true
                        break
                    }
                }
                @Expect(found, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 7 (iOS: testUpdateDateFilters_WhenCalledAppliedFilters_ThenEmitsCorrectFilterUpdate)
    // updateDateFilters → the target filter becomes selected.
    @TestCase
    func testUpdateDateFiltersSelectsCorrectItem(): Unit {
        let expectedFilters = filtersWithSingleSelection()
        let items = makeFilterItemsSingle()
        let group = makeSingleSelectionGroup()
        let (v, box) = newValidatorWith(expectedFilters)
        let now = DateTime.now()
        v.updateDateFilters(group.id, items[2].id, now, now)
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                let updated = updatedFilters.filterGroups[0]
                var found = false
                for (f in updated.filters) {
                    if (f.id == items[2].id && f.selected) {
                        found = true
                        break
                    }
                }
                @Expect(found, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 8 (iOS: testApplyFilters_WhenFiltersHaveZeroSelections_ThenEmitsFilterApplyResult)
    // MultipleSelection group with no selected items → applyFilters emits filterApplyResult.
    @TestCase
    func testApplyFiltersZeroSelectionsEmitsFilterApplyResult(): Unit {
        let expectedFilters = filtersWithMultipleSelectionNoSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, _, _)) => @Expect(true, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 9 (iOS: testApplySearch_WhenInvalidSearchQuery_ThenEmitsFilterListEmptyResult)
    // Invalid search query → filtered list is empty.
    @TestCase
    func testApplySearchNoMatchIsEmpty(): Unit {
        let (v, box) = newSimpleValidatorWith(emptyGroupFilters())
        v.applySearch("zzz")
        match (box.result) {
            case Some(FilterResult.filterApplyResult(list, _, _)) => @Expect(list.items.size, 0)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 10 (iOS: testApplySearchWhenQueryProvidedThenEmitsFilterApplyResult)
    // "secondary text" matches exactly 1 item (item6).
    @TestCase
    func testApplySearchKeepsMatchingItems(): Unit {
        let (v, box) = newSimpleValidatorWith(emptyGroupFilters())
        v.applySearch("alpha") // matches "alpha" and "alphabet"
        match (box.result) {
            case Some(FilterResult.filterApplyResult(list, _, _)) => @Expect(list.items.size, 2)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 10b (iOS: testApplySearchWhenQueryProvidedThenEmitsFilterApplyResult — exact)
    // "secondary text" matches 1 item in the full 7-item filterableList.
    @TestCase
    func testApplySearchSecondaryTextMatchesOneItem(): Unit {
        let expectedFilters = filtersWithMultipleSelectionAllSelected()
        let (v, box) = newValidatorWith(expectedFilters)
        v.applySearch("secondary text")
        match (box.result) {
            case Some(FilterResult.filterApplyResult(list, _, _)) => @Expect(list.items.size, 1)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 11 (iOS: testUpdateSortOrder_WhenUpdateSortOrderIsCalled_ThenFilterUpdateResultIsEmitted)
    // updateSortOrder emits filterUpdateResult with the new sort order.
    @TestCase
    func testUpdateSortOrderEmitsDescendingUpdate(): Unit {
        let (v, box) = newSimpleValidatorWith(emptyGroupFilters())
        v.updateSortOrder(SortOrderType.descending)
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(f)) => @Expect(f.sortOrder == SortOrderType.descending, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 12 (iOS: testResetFilters_WhenResetFiltersIsCalled_ThenFiltersReset)
    // After reset, appliedFilters group count equals original and filterApplyResult is emitted.
    @TestCase
    func testResetFiltersRestoresDefaults(): Unit {
        let expectedFilters = filtersWithMultipleSelection()
        let group = makeMultipleSelectionGroup()
        let items = makeFilterItemsMultiple()
        let (v, box) = newValidatorWith(expectedFilters)
        v.updateFilter(group.id, items[2].id)
        v.applyFilters(SortOrderType.ascending)
        v.resetFilters()
        @Expect(v.appliedFiltersForTesting.filterGroups.size, expectedFilters.filterGroups.size)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 13 (iOS: testRevertFilters_WhenRevertFilterIsCalled_ThenFiltersResetToPreviousState)
    // revertFilters discards the snapshot and emits filterUpdateResult with applied filters.
    @TestCase
    func testRevertFiltersEmitsUpdateResult(): Unit {
        let (v, box) = newSimpleValidatorWith(emptyGroupFilters())
        v.updateSortOrder(SortOrderType.descending)
        v.revertFilters()
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(f)) => @Expect(f.sortOrder == SortOrderType.ascending, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 13b (iOS: testRevertFilters_WhenRevertFilterIsCalled_ThenFiltersResetToPreviousState — with real multi-selection group)
    // revertFilters after updateFilter emits group count from applied filters.
    @TestCase
    func testRevertFiltersAfterUpdateEmitsCorrectGroupCount(): Unit {
        let expectedFilters = filtersWithMultipleSelection()
        let group = makeMultipleSelectionGroup()
        let items = makeFilterItemsMultiple()
        let (v, box) = newValidatorWith(expectedFilters)
        v.updateFilter(group.id, items[2].id)
        v.applyFilters(SortOrderType.ascending)
        v.revertFilters()
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 14 (iOS: testApplyFilters_WhenReversibleWithMultipleSelection_ThenFilterApplyResultIsEmitted)
    // ReversibleMultipleSelection group → applyFilters emits filterApplyResult
    // with same group count.
    @TestCase
    func testApplyFiltersReversibleMultipleSelectionEmitsResult(): Unit {
        let expectedFilters = filtersWithReversibleMultipleSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 15 (iOS: testApplyFilters_WhenReversibleWithSingleSelection_ThenFilterApplyResultIsEmitted)
    // ReversibleSingleSelection group → applyFilters emits filterApplyResult
    // with same group count.
    @TestCase
    func testApplyFiltersReversibleSingleSelectionEmitsResult(): Unit {
        let expectedFilters = filtersWithReversibleSingleSelection()
        let (v, box) = newValidatorWith(expectedFilters)
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, expectedFilters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 16 (iOS: testUpdateFilters_WhenCalledAppliedFiltersWithReversibleSelection_ThenEmitsCorrectFilterUpdate)
    // updateFilter on a ReversibleSingleSelection group → target item becomes selected.
    @TestCase
    func testUpdateFilterReversibleSingleSelectsItem(): Unit {
        let expectedFilters = filtersWithReversibleSingleSelection()
        let items = makeFilterItemsSingle()
        let group = makeReversibleSingleSelectionGroup()
        let (v, box) = newValidatorWith(expectedFilters)
        v.updateFilter(group.id, items[2].id)
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                var found = false
                for (f in updatedFilters.filterGroups[0].filters) {
                    if (f.id == items[2].id && f.selected) {
                        found = true
                        break
                    }
                }
                @Expect(found, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 17 (iOS: testUpdateFilters_WhenCalledAppliedFiltersWithReversibleMultiSelection_ThenEmitsCorrectFilterUpdate)
    // iOS test uses reversibleSelectionGroup.id ("reversible_filter") — a single-selection group id —
    // to call updateFilter on a validator initialized with filtersWithReversibleMultipleSelection
    // (group id "reversible_multi_filter"). The ids don't match, so no group gets updated.
    // The snapshot emits the applied filters unchanged. In filterItemsMultiple, item id "3"
    // (Age Verification) has selected: true by construction, so the assert holds.
    @TestCase
    func testUpdateFilterReversibleMultiSelectsItem(): Unit {
        let expectedFilters = filtersWithReversibleMultipleSelection()
        let items = makeFilterItemsSingle()
        // Use reversible SINGLE group id (mirrors iOS reversibleSelectionGroup.id = "reversible_filter")
        let singleGroupId = makeReversibleSingleSelectionGroup().id  // "reversible_filter"
        let (v, box) = newValidatorWith(expectedFilters)
        // id mismatch → no toggle; snapshot = applied filters unchanged
        v.updateFilter(singleGroupId, items[2].id)
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                // In filterItemsMultiple, id "3" = Age Verification, selected: true
                var found = false
                for (f in updatedFilters.filterGroups[0].filters) {
                    if (f.id == items[2].id && f.selected) {
                        found = true
                        break
                    }
                }
                @Expect(found, true)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 18 (iOS: testApplyFilters_WhenSingleSelectionGroupHasNoSelectedFilter_ThenEmitsEmptyList)
    // iOS expects an empty list; Cangjie production code intentionally returns
    // the original list when no filter is selected (mirrors reversible semantics,
    // avoids filtering out all documents). Cangjie assertion: list is NOT empty.
    @TestCase
    func testApplyFiltersSingleSelectionNoSelectionReturnsOriginalList(): Unit {
        let items = [
            FilterItem(
                id: "1", name: "PID", selected: false,
                filterableAction: Filter(predicate: namePredicate())
            ),
            FilterItem(
                id: "2", name: "mDL", selected: false,
                filterableAction: Filter(predicate: namePredicate())
            )
        ]
        let group = SingleSelectionFilterGroup(
            id: "single_no_selection",
            name: "Empty Single Selection",
            filters: items,
            filterType: FilterGroupType.other
        )
        let filters = Filters(filterGroups: [group], sortOrder: SortOrderType.ascending)
        let list = makeFilterableList()
        let v = FilterValidatorImpl()
        v.initializeValidator(filters, list)
        let box = ResultBox()
        v.setFilterResultListener({ s =>
            match (s) {
                case FilterResultPartialState.success(r) => box.result = Some(r)
                case _ => ()
            }
        })
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(filteredList, _, _)) =>
                // Cangjie: no-selection in SingleSelectionGroup returns original list
                @Expect(filteredList.items.size, list.items.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 19 (iOS: testApplyFilters_WhenReversibleSingleSelectionHasNoSelectedFilter_ThenReturnsOriginalList)
    // Reversible single selection with no selected filter → original list returned.
    @TestCase
    func testApplyFiltersReversibleSingleNoSelectionReturnsOriginalList(): Unit {
        let items = [
            FilterItem(
                id: "1", name: "PID", selected: false,
                filterableAction: Filter(predicate: namePredicate())
            ),
            FilterItem(
                id: "2", name: "mDL", selected: false,
                filterableAction: Filter(predicate: namePredicate())
            )
        ]
        let group = ReversibleSingleSelectionFilterGroup(
            id: "rev_single_none",
            name: "Reversible Single Empty",
            filters: items,
            filterType: FilterGroupType.other
        )
        let filters = Filters(filterGroups: [group], sortOrder: SortOrderType.ascending)
        let list = makeFilterableList()
        let v = FilterValidatorImpl()
        v.initializeValidator(filters, list)
        let box = ResultBox()
        v.setFilterResultListener({ s =>
            match (s) {
                case FilterResultPartialState.success(r) => box.result = Some(r)
                case _ => ()
            }
        })
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(filteredList, _, _)) =>
                @Expect(filteredList.items.size, list.items.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 20 (iOS: testApplyFilters_WhenReversibleMultipleSelectionHasNoSelectedFilter_ThenReturnsOriginalList)
    // Reversible multiple selection with no selected filter → original list returned.
    @TestCase
    func testApplyFiltersReversibleMultiNoSelectionReturnsOriginalList(): Unit {
        let group = ReversibleMultipleSelectionFilterGroup(
            id: "rev_multi_none",
            name: "Reversible Multi Empty",
            filters: makeFilterItemsMultipleNoSelections(),
            filterableAction: FilterMultipleAction(predicate: namePredicate()),
            filterType: FilterGroupType.other
        )
        let filters = Filters(filterGroups: [group], sortOrder: SortOrderType.ascending)
        let list = makeFilterableList()
        let v = FilterValidatorImpl()
        v.initializeValidator(filters, list)
        let box = ResultBox()
        v.setFilterResultListener({ s =>
            match (s) {
                case FilterResultPartialState.success(r) => box.result = Some(r)
                case _ => ()
            }
        })
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(filteredList, _, _)) =>
                @Expect(filteredList.items.size, list.items.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 21 (iOS: testInitializeValidator_WhenCalledTwiceWithReversibleSingle_ThenMergesSelections)
    // Two identical inits with reversible-single group → group count preserved.
    @TestCase
    func testInitializeTwiceReversibleSingleMergesSelections(): Unit {
        let filters = filtersWithReversibleSingleSelection()
        let (v, box) = newValidatorWith(filters)
        v.initializeValidator(filters, makeFilterableList())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, filters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 22 (iOS: testInitializeValidator_WhenCalledTwiceWithReversibleMultiple_ThenMergesSelections)
    // Two identical inits with reversible-multiple group → group count preserved.
    @TestCase
    func testInitializeTwiceReversibleMultipleMergesSelections(): Unit {
        let filters = filtersWithReversibleMultipleSelection()
        let (v, box) = newValidatorWith(filters)
        v.initializeValidator(filters, makeFilterableList())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(_, updatedFilters, _)) =>
                @Expect(updatedFilters.filterGroups.size, filters.filterGroups.size)
            case _ => @Expect(false, true)
        }
    }

    // ── Test 23 (iOS: testUpdateDateFilters_WhenFilterIdMatchesTransactionDateRange_ThenStartAndEndDatesAreSet)
    // updateDateFilters with FILTER_BY_TRANSACTION_DATE_RANGE id → startDate and endDate set.
    @TestCase
    func testUpdateDateFiltersTransactionDateRangeSetsStartAndEnd(): Unit {
        let startDate = DateTime.of(year: 2024, month: 1, dayOfMonth: 1)
        let endDate = DateTime.of(year: 2024, month: 12, dayOfMonth: 31)
        let dateRangeFilter = FilterItem(
            id: FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE,
            name: "Date Range",
            selected: false,
            filterableAction: DefaultFilterAction()
        )
        let group = SingleSelectionFilterGroup(
            id: FilterIds.FILTER_BY_TRANSACTION_DATE_GROUP_ID,
            name: "Date Group",
            filters: [dateRangeFilter],
            filterType: FilterGroupType.other
        )
        let filters = Filters(filterGroups: [group], sortOrder: SortOrderType.ascending)
        let v = FilterValidatorImpl()
        v.initializeValidator(filters, makeFilterableList())
        let box = ResultBox()
        v.setFilterResultListener({ s =>
            match (s) {
                case FilterResultPartialState.success(r) => box.result = Some(r)
                case _ => ()
            }
        })
        v.updateDateFilters(
            group.id,
            FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE,
            startDate,
            endDate
        )
        match (box.result) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                var updatedFilter: Option<FilterItem> = Option<FilterItem>.None
                for (f in updatedFilters.filterGroups[0].filters) {
                    if (f.id == FilterIds.FILTER_BY_TRANSACTION_DATE_RANGE) {
                        updatedFilter = Some(f)
                        break
                    }
                }
                match (updatedFilter) {
                    case Some(f) =>
                        match (f.startDate) {
                            case Some(sd) => @Expect(sd, startDate)
                            case None => @Expect(false, true)
                        }
                        match (f.endDate) {
                            case Some(ed) => @Expect(ed, endDate)
                            case None => @Expect(false, true)
                        }
                    case None => @Expect(false, true)
                }
            case _ => @Expect(false, true)
        }
    }

    // ── Retained originals (no-groups variants) ──────────────────────────

    // No groups + no search → applyFilters returns the whole list.
    @TestCase
    func testApplyFiltersReturnsAllWhenNoFilters(): Unit {
        let (v, box) = newSimpleValidatorWith(emptyGroupFilters())
        v.applyFilters(SortOrderType.ascending)
        match (box.result) {
            case Some(FilterResult.filterApplyResult(list, _, _)) => @Expect(list.items.size, 3)
            case _ => @Expect(false, true)
        }
    }

    // ── Emission sequence ────────────────────────────────────────────────

    // iOS: TestDocumentTabInteractor.testOnFilterChangeState_WhenStreamEmitsResults_ThenProcessesResultsCorrectly
    // iOS: TestTransactionTabInteractor.testOnFilterChangeState_WhenStreamEmitsResults_ThenProcessesResultsAsExpected
    // iOS stubs the stream to yield filterApplyResult then filterUpdateResult and
    // asserts the consumer saw exactly those two, in that order, each matching its
    // own case. Here the real engine produces the pair: applyFilters emits the
    // apply result, updateFilter emits the update result. Same fixture as iOS —
    // no groups, empty list — so the apply result carries an empty list and zero
    // groups. Note the iOS assertions sit inside a non-awaited `Task {}` and so
    // may never run before XCTest ends the case; these run synchronously.
    @TestCase
    func testEngineEmitsApplyThenUpdateInOrder(): Unit {
        let v = FilterValidatorImpl()
        v.initializeValidator(emptyGroupFilters(), FilterableList(Array<FilterableItem>()))
        let cap = CaptureBox()
        cap.attach(v)

        v.applyFilters(SortOrderType.ascending)
        v.updateFilter("any_group", "any_filter")

        @Expect(cap.states.size, 2)
        match (cap.resultAt(0)) {
            case Some(FilterResult.filterApplyResult(list, updatedFilters, _)) =>
                @Expect(list.items.size, 0)
                @Expect(updatedFilters.filterGroups.size, 0)
            case _ => @Expect(false, true)
        }
        match (cap.resultAt(1)) {
            case Some(FilterResult.filterUpdateResult(updatedFilters)) =>
                @Expect(updatedFilters.filterGroups.size, 0)
            case _ => @Expect(false, true)
        }
    }

    // Four operations must surface as four emissions in issue order, each tagged
    // with its own kind. Guards the listener against ever coalescing to "latest
    // value only", which is what made the two iOS cases above unobservable.
    @TestCase
    func testEngineEmitsEveryOperationWithoutCoalescing(): Unit {
        let v = FilterValidatorImpl()
        v.initializeValidator(emptyGroupFilters(), sampleList())
        let cap = CaptureBox()
        cap.attach(v)

        v.applyFilters(SortOrderType.ascending)
        v.updateFilter("any_group", "any_filter")
        v.updateSortOrder(SortOrderType.descending)
        v.applyFilters(SortOrderType.descending)

        @Expect(cap.states.size, 4)
        @Expect(isApplyResult(cap.resultAt(0)), true)
        @Expect(isApplyResult(cap.resultAt(1)), false)
        @Expect(isApplyResult(cap.resultAt(2)), false)
        @Expect(isApplyResult(cap.resultAt(3)), true)
        // Only the apply case carries a list; the update case structurally cannot.
        // That is the distinction the dashboard controller leans on when it leaves
        // an already-applied list untouched on update events.
        match (cap.resultAt(3)) {
            case Some(FilterResult.filterApplyResult(list, _, _)) => @Expect(list.items.size, 3)
            case _ => @Expect(false, true)
        }
    }
}
