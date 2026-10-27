/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/Detail/Transaction/TransactionDetailsView.swift +
 * Component/TransactionCardView.swift + TransactionDetailsListItemsView.swift +
 * TransactionDetailsViewModel.swift) to Cangjie.
 *
 * Shows a single transaction-log entry, mirroring the iOS layout top-to-bottom:
 *  - transaction card (type label, relying party + verified badge, date,
 *    success/failure status pill)
 *  - "DATA SHARED" grouped sections (the disclosed claims)
 *  - "Request data deletion" (error style, disabled — future feature)
 *  - "Report suspicious transaction" (secondary style, disabled — future feature)
 *
 * The wallet engine in this port persists only a flat transaction value string
 * (no structured relying-party / status / per-document partition); those fields
 * are degraded honestly in the interactor (see DashboardInteractor.
 * fetchTransactionDetails). NavDestination root (registered route
 * transactionDetails). Blocking fetch in spawn{}, @State writeback via
 * spawn(UIThread) (S-001); rows built with built-in components only (R-102).
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_logic_ui.{
    uiColor, uiFontSize, ContentLoaderView, ContentUnavailableView, WrapCardView,
    WrapButtonView, ButtonViewStyle,
    SPACING_NONE, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, SPACING_LARGE_MEDIUM,
    SPACING_EXTRA_SMALL, appImageSrc
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

@Component
public class TransactionDetailsView {
    public var viewModel: ?TransactionDetailsViewModel = Option<TransactionDetailsViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var hasTransaction: Bool = false
    @State
    var errorMessage: String = ""
    @State
    var typeLabel: String = ""
    @State
    var relyingPartyName: String = ""
    @State
    var relyingPartyVerified: Bool = false
    @State
    var dateText: String = ""
    @State
    var statusLabel: String = ""
    @State
    var isCompleted: Bool = true
    @State
    var sections: Array<ClaimSection> = Array<ClaimSection>()

    private var vm: ?TransactionDetailsViewModel = Option<TransactionDetailsViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.errorMessage = state.errorMessage ?? ""
                        match (state.details) {
                            case Some(d) =>
                                this.hasTransaction = true
                                this.typeLabel = d.transactionTypeLabel
                                this.relyingPartyName = d.relyingPartyName
                                this.relyingPartyVerified = d.relyingPartyIsVerified
                                this.dateText = d.dateText
                                this.statusLabel = d.statusLabel
                                this.isCompleted = d.isCompleted
                                this.sections = d.sections
                            case None =>
                                this.hasTransaction = false
                        }
                    }
                })
                spawn {
                    =>
                    model.fetchDetails()
                }
            case None =>
                this.isLoading = false
        }
    }

    protected override func aboutToDisappear(): Unit {
        match (this.vm) {
            case Some(model) => model.clearStateListener()
            case None => ()
        }
    }

    private func onBack(): Unit {
        match (this.vm) {
            case Some(model) => model.onBack()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                this.toolbar()
                if (this.isLoading) {
                    Column {
                        ContentLoaderView(showLoader: true)
                    }
                    .width(100.percent)
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Center)
                } else if (!this.errorMessage.isEmpty()) {
                    // A failed lookup reads differently from "nothing to show":
                    // iOS surfaces the error text, and the toolbar back button
                    // stands in for its dialog's cancel-and-pop.
                    Column {
                        ContentUnavailableView(
                            title: LocalizableStringKey.genericErrorTitle,
                            description: LocalizableStringKey.custom(this.errorMessage)
                        )
                    }
                    .width(100.percent)
                    .layoutWeight(1)
                } else if (!this.hasTransaction) {
                    Column {
                        ContentUnavailableView(
                            title: LocalizableStringKey.noResults,
                            description: LocalizableStringKey.noResultsTransactionsDescription
                        )
                    }
                    .width(100.percent)
                    .layoutWeight(1)
                } else {
                    this.detailContent()
                }
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    @Builder
    private func toolbar() {
        // iOS uses an inline NavigationStack title: visually centred in the
        // screen, independent of the leading chevron's width.
        Stack(alignContent: Alignment.Center) {
            Text(LocalizableManager.get(LocalizableStringKey.transactionInformation))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .textAlign(TextAlign.Center)
                .maxLines(1)
            Row {
                Row {
                    Image(appImageSrc(ThemeManager.shared.image.chevronLeft))
                        .width(22.0)
                        .height(22.0)
                        .objectFit(ImageFit.Contain)
                        .fillColor(uiColor(ThemeManager.shared.color.primaryLabel))
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .onClick({ _ => this.onBack() })
                Row {}.layoutWeight(1)
                // Symmetric trailing footprint keeps the native inline title
                // centred, matching SwiftUI's navigation bar geometry.
                Row {}.width(40.0).height(40.0)
            }
            .width(100.percent)
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }

    @Builder
    private func detailContent() {
        Scroll {
            Column(space: SPACING_LARGE_MEDIUM) {
                // Transaction card.
                WrapCardView(content: this.cardBody)

                // "DATA SHARED" sections + the two intentionally-disabled
                // follow-up actions. iOS only renders this entire area when the
                // transaction has disclosed-document items.
                if (this.sections.size > 0) {
                    this.sectionTitle(LocalizableManager.get(LocalizableStringKey.transactionDetailsDataShare))
                    this.dataSharedSections()
                    Column(space: SPACING_MEDIUM) {
                        // Both actions are also disabled in iOS 2026 source; its
                        // onShowDeleteModal/onReportModal handlers are empty.
                        Column(space: SPACING_SMALL) {
                            Text(LocalizableManager.get(LocalizableStringKey.transactionDetailsRequestDeletionMessage))
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .width(100.percent)
                                .textAlign(TextAlign.Start)
                            WrapButtonView(
                                title: LocalizableStringKey.transactionDetailsRequestDeletionButton,
                                style: ButtonViewStyle.error(),
                                isEnabled: false
                            )
                        }
                        .width(100.percent)

                        Column(space: SPACING_SMALL) {
                            Text(LocalizableManager.get(LocalizableStringKey.transactionDetailsReportTransactionMessage))
                                .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                .width(100.percent)
                                .textAlign(TextAlign.Start)
                            WrapButtonView(
                                title: LocalizableStringKey.transactionDetailsReportTransactionButton,
                                style: ButtonViewStyle.secondary(),
                                isEnabled: false
                            )
                        }
                        .width(100.percent)
                    }
                    .width(100.percent)
                }
            }
            .width(100.percent)
            // SwiftUI: VStack.padding(Theme.padding).padding(.bottom)
            .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_LARGE, left: SPACING_MEDIUM)
        }
        .align(Alignment.TopStart)
        .layoutWeight(1)
    }

    @Builder
    private func sectionTitle(text: String) {
        Text(text)
            .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
            .fontWeight(FontWeight.Bold)
            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
            .width(100.percent)
            .textAlign(TextAlign.Start)
    }

    // ── Transaction card ──

    @Builder
    private func cardBody() {
        Column(space: SPACING_MEDIUM) {
            // Type label + relying party name (+ verified badge).
            Column(space: SPACING_EXTRA_SMALL) {
                Text(this.typeLabel)
                    // iOS TransactionCardView uses labelSmall (11pt).
                    .fontSize(uiFontSize(ThemeManager.shared.font.labelSmall))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
                if (!this.relyingPartyName.isEmpty()) {
                    Row(space: SPACING_EXTRA_SMALL) {
                        Text(this.relyingPartyName)
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .textAlign(TextAlign.Start)
                        if (this.relyingPartyVerified) {
                            Image(appImageSrc(ThemeManager.shared.image.verified))
                                .width(16.0)
                                .height(16.0)
                                .objectFit(ImageFit.Contain)
                                .fillColor(uiColor(ThemeManager.shared.color.success))
                        }
                    }
                    .width(100.percent)
                }
            }
            .width(100.percent)

            // Date + status pill.
            Row {
                Column(space: SPACING_EXTRA_SMALL) {
                    Text(LocalizableManager.get(LocalizableStringKey.transactionDetailsScreenCardDateLabel))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                    Text(this.dateText)
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (!this.statusLabel.isEmpty()) {
                    Text(this.statusLabel)
                        // iOS uses labelMedium (12pt), primaryLabel and 8pt on
                        // every edge. The previous 16pt horizontal inset made
                        // this pill oversized and forced the date onto two lines.
                        .fontSize(uiFontSize(ThemeManager.shared.font.labelMedium))
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .padding(SPACING_SMALL)
                        .backgroundColor(this.statusColor())
                        .borderRadius(8.0)
                }
            }
            .width(100.percent)
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
    }

    private func statusColor(): Color {
        if (this.isCompleted) {
            return uiColor(ThemeManager.shared.color.green)
        }
        return uiColor(ThemeManager.shared.color.red)
    }

    // ── Data shared sections ──

    @Builder
    private func dataSharedSections() {
        Column(space: SPACING_MEDIUM) {
            ForEach(
                this.sections,
                itemGenerator: { section: ClaimSection, _: Int64 =>
                    Column(space: SPACING_NONE) {
                        Text(section.title)
                            .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                            .fontWeight(FontWeight.Bold)
                            .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                            .width(100.percent)
                            .textAlign(TextAlign.Start)
                            .padding(bottom: SPACING_SMALL, top: 0.0, left: 0.0, right: 0.0)
                        ForEach(
                            section.rows,
                            itemGenerator: { row: ClaimRow, _: Int64 =>
                                Column(space: SPACING_EXTRA_SMALL) {
                                    Text(row.title)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                        .width(100.percent)
                                        .textAlign(TextAlign.Start)
                                    Text(row.value)
                                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                        .width(100.percent)
                                        .textAlign(TextAlign.Start)
                                }
                                .width(100.percent)
                                .padding(top: SPACING_SMALL, bottom: SPACING_SMALL, left: 0.0, right: 0.0)
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(SPACING_MEDIUM)
                    .backgroundColor(uiColor(ThemeManager.shared.color.groupedElevatedBackground))
                    .borderRadius(18.0)
                }
            )
        }
        .width(100.percent)
    }
}
