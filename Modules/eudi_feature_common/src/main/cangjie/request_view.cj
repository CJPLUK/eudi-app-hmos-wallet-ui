/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Request/BaseRequestView.swift) to Cangjie ArkUI.
 *
 * Shared presentation-request screen: the relying-party registration header
 * (registration certificate trust layer, iOS 95b71766 — replaces the old
 * ContentHeaderView + trusted-RP dialog), the per-document claim sections
 * with selectable / locked checkbox rows, and the bottom bar that stacks the
 * registration-warning acknowledgement panel (when a warning is active)
 * above the Share button. Share enables only while at least one row is
 * selected AND any active warning is acknowledged. The confirm callback
 * carries the flattened selected set. Trust-blocked requests render the
 * standard alert (presentationBlockedTitle/Message) with a single Close.
 * Empty request → ContentEmptyView with the no-document message (still
 * headed by the registration block — an unsatisfiable request must show who
 * asked); error state → ContentErrorView; loading → ContentLoaderView.
 *
 * Rows inside the ForEach item generator are drawn with built-in components
 * only (project convention, see eudi_logic_ui searchable_list/toolbar:
 * custom @Component inside an item generator breaks the macro expansion);
 * the row layout matches eudi_logic_ui WrapListItemView's checkbox row.
 *
 * Plain @Component — composition root owns navigation chrome.
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import std.collection.{ArrayList, HashMap}
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** Resolves an optional localizable key to text ("" when absent). */
func optKeyText(key: ?LocalizableStringKey): String {
    match (key) {
        case Some(k) => LocalizableManager.get(k)
        case None => ""
    }
}

/**
 * Base request screen (fc_common_request exposed symbol). Mirrors iOS
 * `BaseRequestView`, reused by the presentation and proximity flows.
 *
 * Injection points (S-017):
 *  - `viewModel`: RequestViewModel holding sections + selection (composition
 *    root feeds parsed claims through `setItems` / `onReceivedRegistration`).
 *  - `onConfirm`: Share tap callback carrying the selected cell set.
 *  - `onCancel`: leading-back callback (also fired by the trust-blocked
 *    alert's Close, mirroring iOS `onTrustBlockedClose` → pop).
 */
@Component
public class BaseRequestView {
    public var viewModel: ?RequestViewModel = Option<RequestViewModel>.None
    public var onConfirm: (Array<RequestDataCell>) -> Unit = { _ => }
    public var onCancel: () -> Unit = { => }

    private var vm: ?RequestViewModel = Option<RequestViewModel>.None

    @State
    var sections: Array<RequestDataSection> = Array<RequestDataSection>()
    @State
    var shareEnabled: Bool = false
    @State
    var isLoading: Bool = false
    @State
    var hasError: Bool = false
    @State
    var relyingPartyName: String = ""
    @State
    var relyingPartyTrusted: Bool = false
    /** Registration header snapshot (state → @State scalar convention, see
     *  view_model.cj). `hasRegistration` gates the whole block. */
    @State
    var hasRegistration: Bool = false
    @State
    var regName: String = ""
    @State
    var regIdentifier: String = ""
    @State
    var regIsVerified: Bool = false
    @State
    var regLogoUrl: String = ""
    @State
    var regPrivacyUrl: String = ""
    @State
    var regIntendedUse: String = ""
    /** Active registration warning text ("" = none — gated on initialized &&
     *  !loading by RequestViewModel.activeRegistrationWarning). */
    @State
    var warningMessage: String = ""
    @State
    var warningAcknowledgementText: String = ""
    @State
    var riskAcknowledged: Bool = false
    @State
    var showTrustBlockedAlert: Bool = false
    @State
    var showIncompleteSelectionAlert: Bool = false
    /** Per-section collapse state, keyed by stable document id. HashMap is
     *  used instead of Array<Bool>: ArkUI tracks a freshly assigned map from
     *  inside a ForEach item generator, while indexed array reads remained
     *  cached and left the card permanently collapsed. */
    @State
    var expandedSections: HashMap<String, Bool> = HashMap<String, Bool>()
    /** iOS `combinations.count` / `selectedCombinationIndex` — drives the radio
     *  card list when a request can be satisfied by more than one combination. */
    @State
    var combinationCount: Int64 = 0
    @State
    var selectedCombination: Int64 = 0
    /** Per-combination "View details" collapse (iOS WrapExpandableListView inside
     *  each combination card). Collapsed by default. */
    @State
    var comboExpanded: Array<Bool> = Array<Bool>()

    protected override func aboutToAppear(): Unit {
        let model = this.viewModel ?? RequestViewModel(router: InMemoryRouterHost())
        this.vm = Some(model)
        // Request loading/preparation runs on worker threads in both feature
        // flows. ArkUI @State must only be updated from UIThread; otherwise a
        // rendered section can retain a stale interaction subtree.
        model.onStateChange({ state =>
            spawn(UIThread) { => this.syncFromState(state) }
        })
        this.syncFromState(model.viewState)
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func syncFromState(state: RequestViewState): Unit {
        this.sections = state.sections.toArray()
        this.isLoading = state.isLoading
        this.hasError = state.hasError
        this.relyingPartyName = state.relyingParty
        this.relyingPartyTrusted = state.relyingPartyIsTrusted
        this.riskAcknowledged = state.isRiskAcknowledged
        this.showTrustBlockedAlert = state.isTrustBlockedAlertShowing
        this.showIncompleteSelectionAlert = state.isIncompleteSelectionAlertShowing
        this.syncRegistration(state)
        match (this.vm) {
            case Some(model) =>
                this.shareEnabled = model.canShare()
                match (model.activeRegistrationWarning()) {
                    case Some(warning) =>
                        this.warningMessage = LocalizableManager.get(warning.message)
                        this.warningAcknowledgementText = LocalizableManager.get(warning.acknowledgement)
                    case None =>
                        this.warningMessage = ""
                        this.warningAcknowledgementText = ""
                }
                this.combinationCount = model.combinationCount()
                this.selectedCombination = model.selectedCombination()
                if (this.comboExpanded.size != this.combinationCount) {
                    this.comboExpanded = Array<Bool>(this.combinationCount, { _ => false })
                }
            case None => ()
        }
    }

    private func handleCombinationSelected(index: Int64): Unit {
        match (this.vm) {
            case Some(model) => model.onCombinationSelected(index)
            case None => ()
        }
    }

    private func isComboExpanded(index: Int64): Bool {
        if (index >= 0 && index < this.comboExpanded.size) {
            return this.comboExpanded[index]
        }
        return false
    }

    private func toggleCombo(index: Int64): Unit {
        if (index < 0 || index >= this.comboExpanded.size) { return }
        let next = Array<Bool>(this.comboExpanded.size, { i => this.comboExpanded[i] })
        next[index] = !next[index]
        this.comboExpanded = next
    }

    /** Copies the registration header into @State scalars. Flows not yet
     *  feeding `onReceivedRegistration` (rewired by the feature tier) fall
     *  back to a minimal header from the plain relying-party fields, so the
     *  screen never loses the "who asks" block. */
    private func syncRegistration(state: RequestViewState): Unit {
        match (state.relyingPartyRegistration) {
            case Some(data) =>
                this.hasRegistration = true
                this.regName = LocalizableManager.get(data.primary.name)
                this.regIdentifier = optKeyText(data.primary.identifier)
                this.regIsVerified = data.primary.isVerified
                this.regLogoUrl = data.primary.logoUrl
                this.regPrivacyUrl = data.privacyPolicyUrl
                this.regIntendedUse = optKeyText(data.intendedUse)
            case None =>
                this.hasRegistration = !state.relyingParty.isEmpty()
                this.regName = state.relyingParty
                this.regIdentifier = ""
                this.regIsVerified = state.relyingPartyIsTrusted
                this.regLogoUrl = ""
                this.regPrivacyUrl = ""
                this.regIntendedUse = ""
        }
    }

    /** Rebuilds the header payload from the @State snapshot (plain-prop
     *  passing driven by @State scalars, same as the old header config). */
    private func registrationData(): RelyingPartyRegistrationData {
        let identifier: ?LocalizableStringKey = if (this.regIdentifier.isEmpty()) {
            None
        } else {
            Some(LocalizableStringKey.custom(this.regIdentifier))
        }
        let intendedUse: ?LocalizableStringKey = if (this.regIntendedUse.isEmpty()) {
            None
        } else {
            Some(LocalizableStringKey.custom(this.regIntendedUse))
        }
        RelyingPartyRegistrationData(
            primary: RegisteredParty(
                name: LocalizableStringKey.custom(this.regName),
                identifier: identifier,
                isVerified: this.regIsVerified,
                logoUrl: this.regLogoUrl
            ),
            privacyPolicyUrl: this.regPrivacyUrl,
            intendedUse: intendedUse
        )
    }

    private func hasWarning(): Bool {
        !this.warningMessage.isEmpty()
    }

    private func isSectionExpanded(id: String): Bool {
        if (this.expandedSections.contains(id)) {
            return this.expandedSections[id]
        }
        return false
    }

    private func toggleSection(id: String): Unit {
        let next = HashMap<String, Bool>()
        for ((key, value) in this.expandedSections) {
            next[key] = value
        }
        next[id] = !this.isSectionExpanded(id)
        this.expandedSections = next
    }

    private func handleToggle(groupId: String): Unit {
        match (this.vm) {
            case Some(model) =>
                if (model.toggleSelection(groupId)) {
                    // listener already resynced; nothing else to do
                }
            case None => ()
        }
    }

    private func handleAcknowledgementChange(isAcknowledged: Bool): Unit {
        match (this.vm) {
            case Some(model) => model.setRiskAcknowledged(isAcknowledged)
            case None => ()
        }
    }

    private func handleShare(): Unit {
        match (this.vm) {
            case Some(model) =>
                if (model.canShare()) {
                    this.onConfirm(model.selectedCells().toArray())
                }
            case None => ()
        }
    }

    /** iOS `onTrustBlockedClose`: dismiss the alert, then pop. */
    private func handleTrustBlockedClose(): Unit {
        match (this.vm) {
            case Some(model) => model.onTrustBlockedClose()
            case None => ()
        }
        this.onCancel()
    }

    private func isEmptyState(): Bool {
        this.sections.size == 0
    }

    private func cellValueText(cell: RequestDataCell): String {
        if (!cell.isAvailable) {
            return LocalizableManager.get(LocalizableStringKey.unavailableField)
        }
        return cell.value
    }

    private func handleIncompleteSelectionClose(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissIncompleteSelectionAlert()
            case None => ()
        }
    }

    private func incompleteSelectionActions(): Array<AlertAction> {
        [
            AlertAction(
                title: LocalizableStringKey.okButton,
                callback: { => this.handleIncompleteSelectionClose() }
            )
        ]
    }

    private func trustBlockedActions(): Array<AlertAction> {
        [
            AlertAction(
                title: LocalizableStringKey.close,
                callback: { => this.handleTrustBlockedClose() }
            )
        ]
    }

    public func build() {
        Stack(alignContent: Alignment.Center) {
            Column {
                // Navigation bar: centered title + circular leading back button,
                // mirroring iOS ContentScreenView's toolbar (title in the nav bar,
                // back button as a circular elevated chip on the left).
                Stack(alignContent: Alignment.Center) {
                    Text(LocalizableManager.get(LocalizableStringKey.dataSharingRequest))
                        .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .textAlign(TextAlign.Center)
                    Row {
                        Row {
                            Text("‹")
                                .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .textAlign(TextAlign.Center)
                        }
                        .width(40.0)
                        .height(40.0)
                        .justifyContent(FlexAlign.Center)
                        .borderRadius(20.0)
                        .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                        .onClick({ _ => this.onCancel() })
                        Blank()
                    }
                    .width(100.percent)
                }
                .width(100.percent)
                .height(44.0)

                if (this.hasError) {
                    ContentErrorView(
                        config: ContentErrorConfig(cancelAction: { => this.onCancel() })
                    )
                } else if (this.isLoading) {
                    Column {
                        ContentLoaderView(showLoader: true)
                    }
                    .width(100.percent)
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Center)
                } else if (this.isEmptyState()) {
                    // iOS noDocumentsFound branch: an unsatisfiable request
                    // still shows who asked (registration header on top).
                    Column(space: SPACING_MEDIUM) {
                        if (this.hasRegistration) {
                            RelyingPartyRegistrationView(data: this.registrationData())
                        }
                        Column {
                            ContentEmptyView(title: LocalizableStringKey.requestDataNoDocument)
                        }
                        .width(100.percent)
                        .layoutWeight(1)
                        .justifyContent(FlexAlign.Center)
                    }
                    .width(100.percent)
                    .layoutWeight(1)
                } else {
                    this.buildLoadedContent()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .padding(ThemeManager.shared.dimension.padding)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))

            if (this.showTrustBlockedAlert) {
                // iOS trust-blocked alertView (replaces the removed sheet):
                // presentationBlockedTitle/Message + single Close.
                AlertView(
                    title: LocalizableStringKey.presentationBlockedTitle,
                    message: LocalizableStringKey.presentationBlockedMessage,
                    actions: this.trustBlockedActions(),
                    onDismiss: { => this.handleTrustBlockedClose() }
                )
            }
            if (this.showIncompleteSelectionAlert) {
                // iOS itemsChanged alertView: empty title, OK only.
                AlertView(
                    message: LocalizableStringKey.incompleteRequestDataSelection,
                    actions: this.incompleteSelectionActions(),
                    onDismiss: { => this.handleIncompleteSelectionClose() }
                )
            }
        }
        .width(100.percent)
        .height(100.percent)
    }

    @Builder
    func buildLoadedContent() {
        Column {
            Scroll {
                Column(space: SPACING_MEDIUM) {
                    // iOS RelyingPartyRegistrationView header (replaces
                    // ContentHeaderView): registered party + optional privacy
                    // policy link + optional intended use, leading-aligned.
                    if (this.hasRegistration) {
                        RelyingPartyRegistrationView(data: this.registrationData())
                    }

                    // iOS: combinations.count > 1 → radio-selectable cards; else the
                    // single combination's document sections.
                    if (this.combinationCount > 1) {
                        this.buildCombinations()
                    } else {
                        this.buildSections()
                    }
                }
                .width(100.percent)
            }
            .align(Alignment.TopStart)
            .layoutWeight(1)

            // iOS bottomBar: the warning acknowledgement panel stacks above
            // the Share button while a registration warning is active.
            if (this.hasWarning()) {
                Column {
                    // if/else remount keyed on the acknowledged flag: the
                    // Toggle's plain isOn prop does not refresh on parent
                    // rebuild (ExpandableCardView convention), and the reset
                    // on a new request must visually clear the switch.
                    if (this.riskAcknowledged) {
                        WarningAcknowledgementView(
                            message: LocalizableStringKey.custom(this.warningMessage),
                            acknowledgementText: LocalizableStringKey.custom(this.warningAcknowledgementText),
                            isAcknowledged: true,
                            onAcknowledgementChange: { isOn => this.handleAcknowledgementChange(isOn) }
                        )
                    } else {
                        WarningAcknowledgementView(
                            message: LocalizableStringKey.custom(this.warningMessage),
                            acknowledgementText: LocalizableStringKey.custom(this.warningAcknowledgementText),
                            isAcknowledged: false,
                            onAcknowledgementChange: { isOn => this.handleAcknowledgementChange(isOn) }
                        )
                    }
                }
                .width(100.percent)
                .padding(top: 0.0, right: 0.0, bottom: SPACING_MEDIUM, left: 0.0)
            }

            Column {
                WrapButtonView(
                    title: LocalizableStringKey.shareButton,
                    style: ButtonViewStyle.primary(),
                    isLoading: this.isLoading,
                    isEnabled: this.shareEnabled,
                    onAction: { => this.handleShare() }
                )
            }
            .width(100.percent)
            .padding(bottom: SPACING_LARGE_MEDIUM)
        }
        .width(100.percent)
        .layoutWeight(1)
    }

    @Builder
    func buildSections() {
        ForEach(
            this.sections,
            itemGenerator: { section: RequestDataSection, _: Int64 =>
                Column(space: SPACING_EXTRA_SMALL) {
                    // Collapsible header (iOS WrapExpandableListView /
                    // ExpandableCardView): document title + "View details"
                    // supporting line + a chevron that toggles the claim rows.
                    // Collapsed by default; the whole header is tappable.
                    Row(space: SPACING_MEDIUM_SMALL) {
                        Column(space: SPACING_EXTRA_SMALL) {
                            Text(section.title)
                                .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .textAlign(TextAlign.Start)
                                .width(100.percent)
                            Text(LocalizableManager.get(LocalizableStringKey.viewDetails))
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .textAlign(TextAlign.Start)
                                .width(100.percent)
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)

                        Image(appImageSrc(this.chevronIcon(section.id)))
                            .width(24.0)
                            .height(24.0)
                            .objectFit(ImageFit.Contain)
                    }
                    .width(100.percent)
                    .padding(top: SPACING_EXTRA_SMALL, bottom: SPACING_EXTRA_SMALL)
                    .onClick({ _ => this.toggleSection(section.id) })

                    if (this.isSectionExpanded(section.id)) {
                        ForEach(
                            section.cells.toArray(),
                            itemGenerator: { cell: RequestDataCell, _: Int64 =>
                                // Built-in row mirroring WrapListItemView's
                                // checkbox layout (no custom @Component inside
                                // the item generator).
                                Row(space: SPACING_MEDIUM_SMALL) {
                                    Column(space: SPACING_EXTRA_SMALL) {
                                        Text(cell.title)
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                            .textAlign(TextAlign.Start)
                                        Text(this.cellValueText(cell))
                                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                            .textAlign(TextAlign.Start)
                                        if (cell.isOverasked) {
                                            // iOS over-asked leaf: supporting
                                            // "Not registered data" line in the
                                            // warning color.
                                            Text(LocalizableManager.get(LocalizableStringKey.notRegisteredData))
                                                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                                .fontColor(uiColor(ThemeManager.shared.color.warning))
                                                .textAlign(TextAlign.Start)
                                        }
                                    }
                                    .alignItems(HorizontalAlign.Start)
                                    .layoutWeight(1)

                                    // iOS: proximity rows carry a checkbox; online-presentation
                                    // rows are read-only (selection at the combination level).
                                    if (cell.hasCheckbox) {
                                        Checkbox()
                                            .select(cell.selected)
                                            .selectedColor(uiColor(ThemeManager.shared.color.accent))
                                            .enabled(cell.selectable)
                                            .onChange({ _ => this.handleToggle(cell.groupId) })
                                    }
                                }
                                .width(100.percent)
                                .padding(top: SPACING_SMALL, right: 0.0, bottom: SPACING_SMALL, left: 0.0)
                                .opacity(this.cellOpacity(cell))
                            },
                            // Force a row remount when its selection changes;
                            // otherwise ArkUI can retain the old checked state.
                            keyGenerator: { cell: RequestDataCell, _: Int64 =>
                                cell.groupId + "_" + cell.selected.toString()
                            }
                        )
                    }
                }
                .width(100.percent)
                .padding(SPACING_MEDIUM)
                .backgroundColor(uiColor(ThemeManager.shared.color.groupedElevatedBackground))
                .borderRadius(ThemeManager.shared.shape.medium)
                .alignItems(HorizontalAlign.Start)
            },
            keyGenerator: { section: RequestDataSection, _: Int64 => section.id }
        )
    }

    private func chevronIcon(id: String): String {
        if (this.isSectionExpanded(id)) {
            return ThemeManager.shared.image.chevronUpAccent
        }
        return ThemeManager.shared.image.chevronDownAccent
    }

    private func cellOpacity(cell: RequestDataCell): Float64 {
        if (!cell.isAvailable) {
            return 0.38
        }
        return 1.0
    }

    // ── Combinations (iOS combinationsContent + WrapSelectableCardView) ──

    private func combinationIndices(): Array<Int64> {
        Array<Int64>(this.combinationCount, { i => i })
    }

    private func combinationSections(index: Int64): Array<RequestDataSection> {
        match (this.vm) {
            case Some(model) => model.combinationSectionsAt(index).toArray()
            case None => Array<RequestDataSection>()
        }
    }

    private func combinationLabel(index: Int64): String {
        // iOS `.requestCombinationTitle(["N", "M"])`.
        LocalizableManager.get(LocalizableStringKey.requestCombinationTitle(
            [(index + 1).toString(), this.combinationCount.toString()]
        ))
    }

    private func radioColor(index: Int64): Color {
        if (index == this.selectedCombination) {
            return uiColor(ThemeManager.shared.color.accent)
        }
        return uiColor(ThemeManager.shared.color.separator)
    }

    private func cardBorderColor(index: Int64): Color {
        if (index == this.selectedCombination) {
            return uiColor(ThemeManager.shared.color.accent)
        }
        return Color(0x00000000u32)
    }

    /** iOS combinationsContent(): one WrapSelectableCardView (radio + "Option N of M"
     *  + the combination's read-only document sections) per combination. */
    @Builder
    func buildCombinations() {
        ForEach(
            this.combinationIndices(),
            itemGenerator: { index: Int64, _: Int64 =>
                Column(space: SPACING_MEDIUM) {
                    Row(space: SPACING_MEDIUM_SMALL) {
                        // Radio: 20px ring + inner dot when selected.
                        Stack(alignContent: Alignment.Center) {
                            Column {}
                                .width(20.0)
                                .height(20.0)
                                .border(width: 2.0, color: this.radioColor(index), radius: 10.0, style: BorderStyle.Solid)
                            if (index == this.selectedCombination) {
                                Column {}
                                    .width(10.0)
                                    .height(10.0)
                                    .borderRadius(5.0)
                                    .backgroundColor(uiColor(ThemeManager.shared.color.accent))
                            }
                        }
                        .width(20.0)
                        .height(20.0)
                        Text(this.combinationLabel(index))
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .layoutWeight(1)
                            .textAlign(TextAlign.Start)
                    }
                    .width(100.percent)
                    .onClick({ _ => this.handleCombinationSelected(index) })

                    this.buildCombinationSections(index)
                }
                .width(100.percent)
                .padding(SPACING_MEDIUM)
                .backgroundColor(uiColor(ThemeManager.shared.color.groupedElevatedBackground))
                .border(width: 1.0, color: this.cardBorderColor(index), radius: ThemeManager.shared.shape.medium, style: BorderStyle.Solid)
                .alignItems(HorizontalAlign.Start)
                .onClick({ _ => this.handleCombinationSelected(index) })
            },
            keyGenerator: { index: Int64, _: Int64 =>
                "combo_" + index.toString() + "_" + (index == this.selectedCombination).toString()
                    + "_" + this.isComboExpanded(index).toString()
            }
        )
    }

    /** Read-only document sections inside a combination card (iOS documentSection,
     *  claimsAreSelectable=false → no checkboxes). Collapsible "View details" —
     *  collapsed by default like iOS WrapExpandableListView. */
    @Builder
    func buildCombinationSections(index: Int64) {
        ForEach(
            this.combinationSections(index),
            itemGenerator: { section: RequestDataSection, _: Int64 =>
                Column(space: SPACING_EXTRA_SMALL) {
                    // Collapsible header: document title + "View details" + chevron.
                    Row(space: SPACING_MEDIUM_SMALL) {
                        Column(space: SPACING_EXTRA_SMALL) {
                            Text(section.title)
                                .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                                .fontWeight(FontWeight.Bold)
                                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                .textAlign(TextAlign.Start)
                                .width(100.percent)
                            Text(LocalizableManager.get(LocalizableStringKey.viewDetails))
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .textAlign(TextAlign.Start)
                                .width(100.percent)
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                        Text(this.comboChevron(index))
                            .fontSize(uiFontSize(ThemeManager.shared.font.titleSmall))
                            .fontColor(uiColor(ThemeManager.shared.color.accent))
                            .width(24.0)
                            .textAlign(TextAlign.Center)
                    }
                    .width(100.percent)
                    .onClick({ _ => this.toggleCombo(index) })

                    if (this.isComboExpanded(index)) {
                        ForEach(
                            section.cells.toArray(),
                            itemGenerator: { cell: RequestDataCell, _: Int64 =>
                                Column(space: SPACING_EXTRA_SMALL) {
                                    Text(cell.title)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                        .textAlign(TextAlign.Start)
                                        .width(100.percent)
                                    Text(this.cellValueText(cell))
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                        .textAlign(TextAlign.Start)
                                        .width(100.percent)
                                }
                                .width(100.percent)
                                .padding(top: SPACING_SMALL, right: 0.0, bottom: SPACING_SMALL, left: 0.0)
                            }
                        )
                    }
                }
                .width(100.percent)
                .alignItems(HorizontalAlign.Start)
            }
        )
    }

    private func comboChevron(index: Int64): String {
        if (this.isComboExpanded(index)) {
            return "\u{25B4}"
        }
        return "\u{25BE}"
    }
}

/**
 * Concrete request screen wrapper (iOS `RequestView` naming kept for the 22+
 * consumer sites). Same surface as BaseRequestView with the shared default
 * title; flows that need to specialise keep using BaseRequestView directly.
 */
@Component
public class RequestView {
    public var viewModel: ?RequestViewModel = Option<RequestViewModel>.None
    public var onConfirm: (Array<RequestDataCell>) -> Unit = { _ => }
    public var onCancel: () -> Unit = { => }

    public func build() {
        // Build root must be a built-in container (StateManageMacro rule:
        // a custom component cannot be the single root node).
        Column {
            BaseRequestView(
                viewModel: this.viewModel,
                onConfirm: this.onConfirm,
                onCancel: this.onCancel
            )
        }
        .width(100.percent)
        .height(100.percent)
    }
}
