/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/Dashboard/Component/FiltersListView.swift) to Cangjie.
 *
 * SwiftUI presents FiltersListView in a `.sheet`; this port has no sheet
 * primitive, so — matching the established AlertView / side-menu pattern in this
 * shell — the view is a full-screen overlay rendered conditionally inside a Stack
 * by the host tab (`if (showFilters) { FiltersListView(...) }`). The drag-to-
 * dismiss gesture of the iOS sheet maps to the leading cancel button (both
 * revert the in-progress edits), and the inline navigation bar maps to a header
 * Row with leading xmark (cancel/revert) + title + trailing checkmark (apply).
 *
 * Sections mirror iOS FilterUISection:
 *  - radio sections: a green Toggle per row + ListDividerView between rows;
 *  - the date-range section: Start date / End date inline DatePickers (range
 *    clamped to the wallet min/max via DatePicker start:/end:) + a "Reset dates"
 *    button, mirroring FiltersListView.datePickerRow + resetDates.
 *
 * Real engine: every toggle / date change is forwarded to the host VM's
 * FilterValidator-backed controller; the view re-reads the updated sections so
 * the snapshot selections render live (exactly as iOS shows the snapshot until
 * "Show Results" is tapped). Fully wired: when there is no VM (preview), the
 * view renders the sections it was handed and the action callbacks are no-ops.
 */
package eudi_feature_dashboard

import std.time.{DateTime, Month}
import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.{
    uiColor, uiFontSize, ListDividerView,
    SPACING_NONE, SPACING_EXTRA_SMALL, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, appImageSrc, EUDI_SCRIM_COLOR
}
import eudi_logic_business.{DateUtil, FilterIds}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

/**
 * Filters bottom-sheet (rendered as an overlay). Mirrors iOS FiltersListView.
 *
 * Callbacks (mirror the iOS init parameters):
 *  - onUpdateFilter(sectionID, filterID): radio toggle changed.
 *  - onUpdateDateFilters(sectionID, filterID, start, end): date range changed.
 *  - onResetSections(): "Reset dates" / reset filters (rebuilds the sections).
 *  - onApply(): apply filters + close (trailing checkmark).
 *  - onRevert(): revert in-progress edits + close (leading xmark / drag dismiss).
 *  - refreshSections(): pull the latest snapshot sections from the engine.
 */
@Component
public class FiltersListView {
    public var viewModel: ?DashboardViewModel = Option<DashboardViewModel>.None
    public var isTransaction: Bool = false
    /** min/max bounds for the date-range pickers (transaction tab). */
    public var minDate: DateTime = DateTime.now()
    public var maxDate: DateTime = DateTime.now()
    /** Initial sections (used standalone/preview; live edits re-read from the VM). */
    public var initialSections: Array<FilterUISection> = Array<FilterUISection>()
    public var onApply: () -> Unit = { => }
    public var onRevert: () -> Unit = { => }

    @State
    var sections: Array<FilterUISection> = Array<FilterUISection>()
    @State
    var startDate: DateTime = DateTime.now()
    @State
    var endDate: DateTime = DateTime.now()
    /**
     * Monotonic tick bumped on every toggle tap. Embedded in the section key so a
     * tap ALWAYS re-creates the section subtree — even when the engine's resulting
     * state is identical (e.g. tapping the sole-enabled single-select row, which
     * the engine correctly keeps ON). ArkUI already flipped the tapped Toggle
     * visually; without a forced re-create it would stay OUT of sync with the
     * engine's truth (stuck off). The tick guarantees the Toggle re-reads `isOn`.
     */
    @State
    var toggleTick: Int64 = 0
    /** 0 = closed, 1 = editing start date, 2 = editing end date. */
    @State
    var editingDate: Int64 = 0

    protected override func aboutToAppear(): Unit {
        this.sections = this.currentSections()
        this.startDate = this.minDate
        this.endDate = this.maxDate
        // Seed the start/end from the date-range item if present.
        for (section in this.sections) {
            for (item in section.filters) {
                match ((item.startDate, item.endDate)) {
                    case (Some(s), Some(e)) =>
                        this.startDate = s
                        this.endDate = e
                    case _ => ()
                }
            }
        }
    }

    private func currentSections(): Array<FilterUISection> {
        match (this.viewModel) {
            case Some(vm) =>
                if (this.isTransaction) {
                    vm.transactionFilterSections()
                } else {
                    vm.documentFilterSections()
                }
            case None => this.initialSections
        }
    }

    private func refresh(): Unit {
        this.sections = this.currentSections()
    }

    private func titleText(): String {
        LocalizableManager.get(LocalizableStringKey.filters)
    }

    // ── Engine bridge ─────────────────────────────────────────────────────────

    private func onToggle(sectionId: String, filterId: String): Unit {
        match (this.viewModel) {
            case Some(vm) =>
                if (this.isTransaction) {
                    vm.transactionUpdateFilter(sectionId, filterId)
                } else if (sectionId == FilterIds.FILTER_SORT_GROUP_ID) {
                    // Document sort lives in the dedicated FilterSort, not a group.
                    vm.documentUpdateSort(filterId)
                } else {
                    vm.documentUpdateFilter(sectionId, filterId)
                }
            case None => ()
        }
        this.toggleTick = this.toggleTick + 1
        this.refresh()
    }

    private func onDatesChanged(sectionId: String, filterId: String): Unit {
        match (this.viewModel) {
            case Some(vm) =>
                if (this.isTransaction) {
                    vm.transactionUpdateDateFilters(sectionId, filterId, this.startDate, this.endDate)
                }
            case None => ()
        }
        this.refresh()
    }

    private func onResetDates(sectionId: String, filterId: String): Unit {
        this.startDate = this.minDate
        this.endDate = this.maxDate
        this.onDatesChanged(sectionId, filterId)
    }

    private func updateDateFilter(): Unit {
        for (section in this.sections) {
            for (item in section.filters) {
                if (this.isDatePicker(item)) {
                    this.onDatesChanged(section.id, item.id)
                    return
                }
            }
        }
    }

    private func cancel(): Unit {
        match (this.viewModel) {
            case Some(vm) =>
                if (this.isTransaction) {
                    vm.transactionRevertFilters()
                } else {
                    vm.documentRevertFilters()
                }
            case None => ()
        }
        this.onRevert()
    }

    private func apply(): Unit {
        this.onApply()
    }

    public func build() {
        // iOS presents FiltersListView in a .sheet: a bottom card with rounded
        // top corners that leaves a strip of the underlying page visible and
        // covers the tab bar. Tapping the scrim reverts+dismisses (drag-dismiss).
        // Entrance mirrors iOS SheetContainerView: slide-up + scrim fade, 0.25s.
        Stack(alignContent: Alignment.Bottom) {
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                // Scrim fades in/out with the sheet (iOS: 0→0.35 black, 0.25s).
                .transition(TransitionEffect.OPACITY.animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))
                .onClick({ _ => this.cancel() })
            Column {
                // iOS sheet grabber.
                Column() {}
                    .width(36.0)
                    .height(5.0)
                    .borderRadius(2.5)
                    .backgroundColor(uiColor(ThemeManager.shared.color.tertiaryLabel))
                    .margin(top: 8.0, right: 0.0, bottom: 0.0, left: 0.0)
                this.header()
                Scroll {
                    Column(space: SPACING_MEDIUM) {
                        ForEach(
                            this.sections,
                            itemGenerator: { section: FilterUISection, _: Int64 =>
                                // Built-in components only (R-102).
                                Column(space: SPACING_NONE) {
                                    Text(section.sectionTitle)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.labelLarge))
                                        .fontWeight(FontWeight.Medium)
                                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                        .width(100.percent)
                                        .textAlign(TextAlign.Start)
                                        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: 0.0, left: SPACING_MEDIUM)

                                    ForEach(
                                        section.filters,
                                        itemGenerator: { item: FilterUIItem, index: Int64 =>
                                            Column {
                                                if (index > 0) {
                                                    // iOS insets the divider to SPACING_LARGE so it aligns
                                                    // with the row's left/right padding (not full-bleed).
                                                    ListDividerView(spacing: SPACING_LARGE)
                                                }
                                                if (this.isDatePicker(item)) {
                                                    this.dateRangeRow(section.id, item.id)
                                                } else {
                                                    this.radioRow(section.id, item)
                                                }
                                            }
                                            .width(100.percent)
                                        },
                                        // Encode the selected state in the key so a
                                        // single-select change (Default → off) actually
                                        // re-creates the row: ArkUI's Toggle keeps its own
                                        // internal on/off and won't re-read `isOn` on a
                                        // plain data refresh, so untapped rows stayed on.
                                        keyGenerator: { item: FilterUIItem, _: Int64 =>
                                            item.id + (if (item.selected) { "_on" } else { "_off" })
                                        }
                                    )
                                }
                                .width(100.percent)
                                .padding(top: 0.0, right: 0.0, bottom: 0.0, left: 0.0)
                                .backgroundColor(uiColor(ThemeManager.shared.color.groupedBackground))
                                .borderRadius(18.0)
                            },
                            // Encode every filter's selected state in the SECTION key
                            // too. Without this the outer ForEach reuses the section
                            // node at the same index and its itemGenerator closure keeps
                            // the STALE `section` — so the inner rows never see a
                            // single-select flip (Default stayed on). Rebuilding the
                            // section subtree on any selection change fixes it.
                            keyGenerator: { section: FilterUISection, _: Int64 =>
                                var key = section.id + "#" + this.toggleTick.toString()
                                for (f in section.filters) {
                                    key = key + "|" + f.id + (if (f.selected) { "1" } else { "0" })
                                }
                                key
                            }
                        )
                    }
                    .width(100.percent)
                    // 顶部改用 SPACING_SMALL（对齐 iOS 的 ScrollView vertical
                    // SPACING_SMALL），减小 Expiry Period 卡片到标题栏的距离。
                    .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_MEDIUM, left: SPACING_MEDIUM)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
            }
            .width(100.percent)
            .height(92.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .borderRadius(topLeft: 24.0, topRight: 24.0, bottomLeft: 0.0, bottomRight: 0.0)
            .clip(true)
            // iOS SheetContainerView entrance: slide up from the bottom edge
            // (0.25s easeInOut) when the host inserts this view, reverse on exit.
            .transition(TransitionEffect.move(TransitionEdge.Bottom).animation(AnimateParam(duration: 250, curve: Curve.EaseInOut)))

            if (this.editingDate != 0) {
                this.datePickerOverlay()
            }
        }
        .width(100.percent)
        .height(100.percent)
    }

    private func isDatePicker(item: FilterUIItem): Bool {
        match (item.sectionType) {
            case FilterUISectionType.datePicker => true
            case FilterUISectionType.radio => false
        }
    }

    @Builder
    private func header() {
        Row {
            // Leading: cancel — a bigger black X on a WHITE circular button (the
            // light-blue circle read inconsistent; fillColor cannot tint the PNG,
            // so use the pre-tinted bold xmark).
            Stack(alignContent: Alignment.Center) {
                Image(appImageSrc(ThemeManager.shared.image.xmarkBold))
                    .width(28.0)
                    .height(28.0)
                    .objectFit(ImageFit.Contain)
            }
            // 与右侧确认按钮保持相同的正圆尺寸（对称）。
            .width(44.0)
            .height(44.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .borderRadius(22.0)
            .shadow(radius: 10.0, color: Color(0x14000000u32), offsetX: 0.0, offsetY: 3.0)
            .onClick({ _ => this.cancel() })

            Text(this.titleText())
                .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Center)
                .layoutWeight(1)

            // Trailing: apply → a bigger WHITE checkmark on the filled accent
            // circle (iOS borderedProminent). fillColor cannot tint the PNG, so use
            // the pre-tinted white checkmark (it was rendering black).
            Stack(alignContent: Alignment.Center) {
                Image(appImageSrc(ThemeManager.shared.image.checkmarkWhite))
                    .width(24.0)
                    .height(24.0)
                    .objectFit(ImageFit.Contain)
            }
            // iOS 的 .borderedProminent 用 capsule 形状；内容是单个对勾（近正方形），
            // 宽≈高时 capsule 退化成正圆 —— 所以 iOS 上看着是个蓝色实心圆。
            .width(44.0)
            .height(44.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.accent))
            .borderRadius(22.0)
            .onClick({ _ => this.apply() })
        }
        .width(100.percent)
        // 底部收紧，让第一个筛选卡片更贴近标题栏（iOS 的 header 下方无额外留白）。
        .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }

    @Builder
    private func radioRow(sectionId: String, item: FilterUIItem) {
        Row(space: SPACING_MEDIUM) {
            Text(item.title)
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Start)
                .layoutWeight(1)
            // Green-tinted Toggle, mirroring iOS `.tint(Theme.shared.color.green)`.
            // Sized to the iOS switch (~51x31) — the default track read too small.
            Toggle(ToggleType.Switch, isOn: item.selected)
                .width(50.0)
                .height(30.0)
                .selectedColor(uiColor(ThemeManager.shared.color.green))
                .onChange({ _ => this.onToggle(sectionId, item.id) })
        }
        .width(100.percent)
        // The switch already provides a 30-point visual target. A four-point
        // inset keeps the filter cards compact enough to fit on one screen.
        .padding(top: SPACING_EXTRA_SMALL, right: SPACING_LARGE, bottom: SPACING_EXTRA_SMALL, left: SPACING_LARGE)
    }

    private func compactDateText(date: DateTime): String {
        DateUtil.formatDate(date, "dd MMM yyyy")
    }

    @Builder
    private func compactDateField(date: DateTime, mode: Int64) {
        Row {
            Text(this.compactDateText(date))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                .fontColor(uiColor(ThemeManager.shared.color.accent))
                .maxLines(1)
        }
        .height(36.0)
        .padding(top: 0.0, right: SPACING_SMALL, bottom: 0.0, left: SPACING_SMALL)
        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
        .borderRadius(8.0)
        .onClick({ _ => this.editingDate = mode })
    }

    /**
     * The current Cangjie ArkUI SDK only exposes the wheel DatePicker, not the
     * inline CalendarPicker available to ArkTS. Keep that wheel out of the list
     * layout and present it on demand, matching iOS `.datePickerStyle(.compact)`:
     * one-line value in the row, picker UI only after tapping it.
     */
    @Builder
    private func datePickerOverlay() {
        Stack(alignContent: Alignment.Center) {
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                .onClick({ _ => this.editingDate = 0 })

            Column(space: SPACING_MEDIUM) {
                Row {
                    Text(if (this.editingDate == 1) {
                        LocalizableManager.get(LocalizableStringKey.startDate)
                    } else {
                        LocalizableManager.get(LocalizableStringKey.endDate)
                    })
                        .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                        .fontWeight(FontWeight.Bold)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .layoutWeight(1)

                    Text(LocalizableManager.get(LocalizableStringKey.doneButton))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(uiColor(ThemeManager.shared.color.accent))
                        .onClick({ _ => this.editingDate = 0 })
                }
                .width(100.percent)

                if (this.editingDate == 1) {
                    DatePicker(start: this.minDate, end: this.endDate, selected: this.startDate)
                        .width(100.percent)
                        .height(200.0)
                        .onDateChange({ d =>
                            this.startDate = d
                            this.updateDateFilter()
                        })
                } else {
                    DatePicker(start: this.startDate, end: this.maxDate, selected: this.endDate)
                        .width(100.percent)
                        .height(200.0)
                        .onDateChange({ d =>
                            this.endDate = d
                            this.updateDateFilter()
                        })
                }
            }
            .width(88.percent)
            .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_MEDIUM, left: SPACING_MEDIUM)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
            .borderRadius(18.0)
        }
        .width(100.percent)
        .height(100.percent)
    }

    @Builder
    private func dateRangeRow(sectionId: String, filterId: String) {
        Column {
            // Start date row (min..endDate clamp, mirrors iOS range minStartDate...endDate).
            Row(space: SPACING_MEDIUM) {
                Text(LocalizableManager.get(LocalizableStringKey.startDate))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .layoutWeight(1)
                this.compactDateField(this.startDate, 1)
            }
            .width(100.percent)

            Column {
                ListDividerView(spacing: 0.0)
            }
            .width(100.percent)
            .padding(top: SPACING_MEDIUM, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)

            // End date row (startDate..max clamp, mirrors iOS range startDate...maxEndDate).
            Row(space: SPACING_MEDIUM) {
                Text(LocalizableManager.get(LocalizableStringKey.endDate))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .layoutWeight(1)
                this.compactDateField(this.endDate, 2)
            }
            .width(100.percent)

            // Reset dates button (mirrors iOS resetDates → min/max).
            Row {
                Text(LocalizableManager.get(LocalizableStringKey.resetDates))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.accent))
                    .textAlign(TextAlign.Center)
                    .width(100.percent)
                    .onClick({ _ => this.onResetDates(sectionId, filterId) })
            }
            .width(100.percent)
            .padding(top: SPACING_MEDIUM, right: 0.0, bottom: 0.0, left: 0.0)
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_LARGE, bottom: SPACING_SMALL, left: SPACING_LARGE)
    }
}
