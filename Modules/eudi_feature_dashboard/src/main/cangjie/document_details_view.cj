/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-dashboard
 * module (UI/Detail/Document/DocumentDetailsView.swift +
 * Component/IssuerDetailsCardView.swift + Component/DocumentCredentialsInfo.swift +
 * DocumentDetailsViewModel.swift) to Cangjie.
 *
 * Shows a single issued document, mirroring the iOS layout top-to-bottom:
 *  - toolbar (back + bookmark toggle + overflow menu → reissue / remove)
 *  - largeTitle document name
 *  - "ISSUER DETAILS" section: an expandable issuer card (logo + name +
 *    "View details" / expiry, expanded body = issued/revoked message + reissue)
 *  - "DOCUMENT DATA" section: a Show/Hide eye toggle that blur-masks the
 *    sensitive claim values + grouped, expandable claim sections
 *  - "Remove from wallet" error button + confirmation dialog (real delete via
 *    WalletKitController.deleteDocument)
 *  - credential-usage footer ("Instances remaining X/Y")
 *
 * NavDestination root (registered route documentDetails). Blocking interactor
 * calls run in spawn{}, @State writeback marshalled via spawn(UIThread) (S-001).
 * Rows inside ForEach generators are built with built-in components only
 * (R-102); expandable cards reuse eudi_logic_ui ExpandableCardView.
 */
package eudi_feature_dashboard

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.collection.{HashMap, ArrayList}
import eudi_logic_ui.{
    uiColor, uiFontSize, appImageSrc, ContentLoaderView, ContentUnavailableView, WrapCardView,
    WrapButtonView, ButtonViewStyle, ExpandableCardView, ListItemData, MainContentData,
    LeadingIconData, AlertView, AlertAction, ListDividerView,
    SPACING_NONE, SPACING_SMALL, SPACING_MEDIUM, SPACING_LARGE, SPACING_LARGE_MEDIUM,
    SPACING_EXTRA_SMALL
}
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}

@Component
public class DocumentDetailsView {
    public var viewModel: ?DocumentDetailsViewModel = Option<DocumentDetailsViewModel>.None

    @State
    var isLoading: Bool = true
    @State
    var hasDocument: Bool = false
    @State
    var title: String = ""
    @State
    var issuerName: String = ""
    @State
    var issuerLogoUrl: String = ""
    @State
    var issuerSupporting: String = ""
    @State
    var issuerIssuedOn: String = ""
    @State
    var isRevoked: Bool = false
    /** iOS DocumentState.expired (issuer card): red date + expired message. */
    @State
    var isExpired: Bool = false
    @State
    var sections: Array<ClaimSection> = Array<ClaimSection>()
    @State
    var documentFields: Array<DocumentField> = Array<DocumentField>()
    // Per-group expand state (keyed by field id). Nested groups start collapsed,
    // mirroring iOS WrapExpandableListView (.nested isExpanded = false default).
    @State
    var expandedGroups: HashMap<String, Bool> = HashMap<String, Bool>()
    @State
    var hasCredentialUsage: Bool = false
    @State
    var credentialUsageText: String = ""
    // Show/Hide sensitive masking (iOS isVisible — true = shown). Mirrors the
    // eye / eye.slash toggle; when false claim values render blurred. Defaults to
    // HIDDEN (privacy-first, matching iOS) so PII is masked until the user taps Show.
    @State
    var isVisible: Bool = false
    // Overflow (reissue/remove) menu + delete-confirmation dialog visibility.
    @State
    var showMenu: Bool = false
    @State
    var showDeleteDialog: Bool = false
    /** Blocking "Issuance blocked" alert (iOS `isTrustBlockedAlertShowing`):
     *  re-issuance refused because the issuer could not be verified or its
     *  registration is blocked. */
    @State
    var showTrustBlockedAlert: Bool = false
    /** iOS `viewState.isBookmarked`: filled / outline bookmark in the toolbar. */
    @State
    var isBookmarked: Bool = false
    /** iOS `showBookmarkAlert`: "Saved to / Removed from favorites". */
    @State
    var showBookmarkAlert: Bool = false
    /** Latch so rapid Confirm taps cannot double-delete / double-pop. */
    private var deleteInFlight: Bool = false

    private var vm: ?DocumentDetailsViewModel = Option<DocumentDetailsViewModel>.None

    protected override func aboutToAppear(): Unit {
        match (this.viewModel) {
            case Some(model) =>
                this.vm = Some(model)
                model.onStateChange({ state =>
                    spawn(UIThread) {
                        =>
                        this.isLoading = state.isLoading
                        this.showTrustBlockedAlert = state.isTrustBlockedAlertShowing
                        this.isBookmarked = state.isBookmarked
                        this.showBookmarkAlert = state.isBookmarkAlertShowing
                        match (state.details) {
                            case Some(d) =>
                                this.hasDocument = true
                                this.title = d.title
                                this.issuerName = d.issuer
                                this.issuerLogoUrl = d.issuerLogoUrl
                                this.issuerSupporting = d.issuerCard.supportingText
                                this.issuerIssuedOn = d.issuerCard.issuedOnText
                                this.isRevoked = d.isRevoked
                                this.isExpired = d.issuerCard.isExpired
                                this.sections = d.sections
                                this.documentFields = d.documentFields
                                match (d.credentialUsage) {
                                    case Some(usage) =>
                                        this.hasCredentialUsage = true
                                        this.credentialUsageText = usage.text()
                                    case None =>
                                        this.hasCredentialUsage = false
                                }
                            case None =>
                                this.hasDocument = false
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

    private func toggleVisible(): Unit {
        this.isVisible = !this.isVisible
    }

    private func confirmDelete(): Unit {
        if (this.deleteInFlight) {
            return
        }
        this.deleteInFlight = true
        this.showDeleteDialog = false
        match (this.vm) {
            case Some(model) =>
                spawn {
                    =>
                    let ok = model.deleteDocument()
                    if (ok) {
                        // Navigation must run on the UI thread; popping from the
                        // background spawn is a no-op (the screen "did nothing").
                        // DocumentTabRefresh is posted by WalletKitController.refresh
                        // after delete — DocumentTab must tolerate a mid-ForEach
                        // rows shrink (see rowIsCardTop bounds checks).
                        spawn(UIThread) {
                            =>
                            model.onBack()
                        }
                    } else {
                        this.deleteInFlight = false
                    }
                }
            case None =>
                this.deleteInFlight = false
        }
    }

    private func reissue(): Unit {
        this.showMenu = false
        match (this.vm) {
            case Some(model) =>
                spawn {
                    =>
                    let _ = model.reIssueDocument()
                }
            case None => ()
        }
    }

    private func toggleBookmark(): Unit {
        match (this.vm) {
            case Some(model) =>
                spawn {
                    =>
                    model.toggleBookmark()
                }
            case None => ()
        }
    }

    private func onBookmarkAlertClose(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissBookmarkAlert()
            case None => ()
        }
    }

    private func onTrustBlockedClose(): Unit {
        match (this.vm) {
            case Some(model) => model.dismissTrustBlockedAlert()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Stack(alignContent: Alignment.Center) {
                Column {
                    this.toolbar()
                    if (this.isLoading) {
                        Column {
                            ContentLoaderView(showLoader: true)
                        }
                        .width(100.percent)
                        .layoutWeight(1)
                        .justifyContent(FlexAlign.Center)
                    } else if (!this.hasDocument) {
                        Column {
                            ContentUnavailableView(
                                title: LocalizableStringKey.noResults,
                                description: LocalizableStringKey.noResultsDocumentsDescription
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
                if (this.showMenu) {
                    this.menuDialog()
                }
                if (this.showDeleteDialog) {
                    AlertView(
                        title: LocalizableStringKey.removeFromWallet,
                        message: LocalizableStringKey.deleteDocumentConfirmDialog,
                        actions: [
                            AlertAction(title: LocalizableStringKey.cancelButton, callback: { => this.showDeleteDialog = false }),
                            AlertAction(
                                title: LocalizableStringKey.documentDetailsRemoveButton,
                                isDestructive: true,
                                callback: { => this.confirmDelete() }
                            )
                        ],
                        onDismiss: { => this.showDeleteDialog = false }
                    )
                }
                // iOS alertView(bookmarkAlertTitle/bookmarkAlertMessage): the
                // state is already flipped, so it names what just happened.
                if (this.showBookmarkAlert) {
                    AlertView(
                        title: if (this.isBookmarked) { LocalizableStringKey.savedToFavorites } else { LocalizableStringKey.removedFromFavorites },
                        message: if (this.isBookmarked) { LocalizableStringKey.savedToFavoritesMessage } else { LocalizableStringKey.removedFromFavoritesMessages },
                        actions: [
                            AlertAction(title: LocalizableStringKey.close, callback: { => this.onBookmarkAlertClose() })
                        ],
                        onDismiss: { => this.onBookmarkAlertClose() }
                    )
                }
                // iOS alertView(.issuanceBlockedTitle/.issuanceBlockedMessage):
                // the re-issuance was refused — single Close, no retry.
                if (this.showTrustBlockedAlert) {
                    AlertView(
                        title: LocalizableStringKey.issuanceBlockedTitle,
                        message: LocalizableStringKey.issuanceBlockedMessage,
                        actions: [
                            AlertAction(
                                title: LocalizableStringKey.close,
                                callback: { => this.onTrustBlockedClose() }
                            )
                        ],
                        onDismiss: { => this.onTrustBlockedClose() }
                    )
                }
            }
            .width(100.percent)
            .height(100.percent)
        }
        .hideTitleBar(true)
    }

    @Builder
    private func toolbar() {
        Row(space: SPACING_SMALL) {
            // Circular back button — same affordance as the other screens.
            Row {
                Text("‹")
                    .fontSize(28.0)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
            .onClick({ _ => this.onBack() })
            Text(LocalizableManager.get(LocalizableStringKey.details))
                .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                .fontWeight(FontWeight.Medium)
                .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                .layoutWeight(1)
                // iOS centers the inline nav title (back ‹ and menu ⋮ flank it).
                .textAlign(TextAlign.Center)
                .maxLines(1)
            // Bookmark toggle (iOS bookmark / bookmark.fill trailing action).
            if (this.hasDocument) {
                Row {
                    Image(appImageSrc(if (this.isBookmarked) {
                        ThemeManager.shared.image.bookmarkIconFill
                    } else {
                        ThemeManager.shared.image.bookmarkIcon
                    }))
                        .width(22.0)
                        .height(22.0)
                        .objectFit(ImageFit.Contain)
                }
                .width(40.0)
                .height(40.0)
                .justifyContent(FlexAlign.Center)
                .borderRadius(20.0)
                .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
                .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
                .onClick({ _ => this.toggleBookmark() })
            }
            // Overflow menu (iOS ellipsis.vertical → reissue / remove).
            Row {
                Text("⋮")
                    .fontSize(24.0)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
            }
            .width(40.0)
            .height(40.0)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20.0)
            .backgroundColor(uiColor(ThemeManager.shared.color.secondaryGroupedBackground))
            .shadow(radius: 8.0, color: uiColor(ThemeManager.shared.color.tertiaryLabel), offsetX: 0.0, offsetY: 2.0)
            .onClick({ _ => this.showMenu = true })
        }
        .width(100.percent)
        .padding(top: SPACING_SMALL, right: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM)
    }

    @Builder
    private func detailContent() {
        Scroll {
            Column(space: SPACING_LARGE_MEDIUM) {
                // largeTitle document name.
                Text(this.title)
                    .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)

                // ── "ISSUER DETAILS" section (iOS: tight SPACING_SMALL between
                // the section caption and its card) ──
                Column(space: SPACING_SMALL) {
                    this.sectionTitle(LocalizableManager.get(LocalizableStringKey.genericIssuer))
                    this.issuerCard()
                }
                .width(100.percent)

                // ── "DOCUMENT DATA" section ──
                Column(space: SPACING_SMALL) {
                    this.documentDataHeader()
                    this.claimsSections()
                }
                .width(100.percent)

                // Remove from wallet (real delete via WalletKitController).
                WrapButtonView(
                    title: LocalizableStringKey.removeFromWallet,
                    style: ButtonViewStyle.error(),
                    isLoading: this.isLoading,
                    onAction: { => this.showDeleteDialog = true }
                )

                // Credential-usage footer ("Instances remaining X/Y").
                if (this.hasCredentialUsage) {
                    Text(this.credentialUsageText)
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .width(100.percent)
                        .textAlign(TextAlign.Center)
                }
            }
            .width(100.percent)
            .padding(top: 0.0, right: SPACING_MEDIUM, bottom: SPACING_LARGE, left: SPACING_MEDIUM)
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

    // ── Issuer card (expandable: logo + name + supporting / expanded body) ──

    @Builder
    private func issuerCard() {
        ExpandableCardView(
            header: ListItemData(
                mainContent: MainContentData.ofText(LocalizableStringKey.custom(this.issuerName)),
                supportingText: LocalizableStringKey.custom(this.issuerSupporting),
                supportingTextColor: this.issuerSupportingColor(),
                leadingIcon: this.issuerLeadingIcon()
            ),
            collapsedIconSrc: ThemeManager.shared.image.chevronDownAccent,
            expandedIconSrc: ThemeManager.shared.image.chevronUpAccent,
            content: this.issuerCardExpanded
        )
    }

    private func issuerLeadingIcon(): LeadingIconData {
        if (!this.issuerLogoUrl.isEmpty()) {
            return LeadingIconData(imageUrl: this.issuerLogoUrl)
        }
        return LeadingIconData(iconSrc: ThemeManager.shared.image.id)
    }

    private func issuerSupportingColor(): Color {
        // iOS dateTextColor: .revoked / .expired → red, .issued → secondaryLabel.
        if (this.isRevoked || this.isExpired) {
            return uiColor(ThemeManager.shared.color.red)
        }
        return uiColor(ThemeManager.shared.color.secondaryLabel)
    }

    private func issuerMessage(): String {
        // iOS expandedMessageText: .issued / .revoked / .expired.
        if (this.isRevoked) {
            return LocalizableManager.get(LocalizableStringKey.documentDetailsIssuerCardRevokedMessageText)
        }
        if (this.isExpired) {
            return LocalizableManager.get(LocalizableStringKey.documentDetailsIssuerCardExpiredMessageText)
        }
        return LocalizableManager.get(LocalizableStringKey.documentDetailsIssuerCardIssuedMessageText)
    }

    @Builder
    private func issuerCardExpanded() {
        Column(space: SPACING_SMALL) {
            if (!this.issuerIssuedOn.isEmpty()) {
                Text(this.issuerIssuedOn)
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Start)
            }
            // iOS: message on the left, accent Reissue action on the right.
            Row(space: SPACING_SMALL) {
                Text(this.issuerMessage())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .textAlign(TextAlign.Start)
                    .layoutWeight(1)
                // Reissue action — only for non-revoked documents (iOS issued state).
                if (!this.isRevoked) {
                    Text(LocalizableManager.get(LocalizableStringKey.documentDetailsIssuerCardIssuedActionButtonText))
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                        .fontWeight(FontWeight.Medium)
                        .fontColor(uiColor(ThemeManager.shared.color.accent))
                        .onClick({ _ => this.reissue() })
                }
            }
            .width(100.percent)
            .alignItems(VerticalAlign.Center)
        }
        .width(100.percent)
        .padding(top: 0.0, right: SPACING_MEDIUM, bottom: SPACING_MEDIUM, left: SPACING_MEDIUM)
    }

    // ── Document data header (section title + Show/Hide eye toggle) ──

    @Builder
    private func documentDataHeader() {
        Row {
            Text(LocalizableManager.get(LocalizableStringKey.documentData))
                .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                .fontWeight(FontWeight.Bold)
                .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
            // iOS shows only the eye / eye.slash icon (no "Show" text).
            // The raw token must go through appImageSrc or the Image renders blank.
            Row(space: SPACING_EXTRA_SMALL) {
                Image(appImageSrc(this.eyeIcon()))
                    .width(24.0)
                    .height(24.0)
                    .objectFit(ImageFit.Contain)
                    .fillColor(uiColor(ThemeManager.shared.color.accent))
            }
            .padding(SPACING_EXTRA_SMALL)
            .onClick({ _ => this.toggleVisible() })
        }
        .width(100.percent)
    }

    private func eyeIcon(): String {
        if (this.isVisible) {
            return ThemeManager.shared.image.eyeAccent
        }
        return ThemeManager.shared.image.eyeSlashAccent
    }

    // ── Grouped, expandable claim sections ──

    // Single ordered document-data list — mirrors iOS WrapExpandableListView:
    // one card holding scalar rows and nested expandable groups interleaved in
    // claim order, separated by dividers.
    @Builder
    private func claimsSections() {
        Column(space: SPACING_NONE) {
            ForEach(
                this.documentFields,
                itemGenerator: { field: DocumentField, idx: Int64 =>
                    Column(space: SPACING_NONE) {
                        if (field.isGroup) {
                            // Nested group: collapsible header (bold title + chevron)
                            // then its child rows. Mirrors iOS WrapExpandableListView
                            // .nested branch — collapsed by default, toggles on tap.
                            Row(space: SPACING_SMALL) {
                                Text(field.title)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                    .fontWeight(FontWeight.Bold)
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .layoutWeight(1)
                                    .textAlign(TextAlign.Start)
                                Image(appImageSrc(this.groupChevron(field.id)))
                                    .width(20.0)
                                    .height(20.0)
                                    .objectFit(ImageFit.Contain)
                            }
                            .width(100.percent)
                            .padding(top: SPACING_SMALL, bottom: SPACING_SMALL, left: 0.0, right: 0.0)
                            .onClick({ _ => this.toggleGroup(field.id) })
                            if (this.isGroupExpanded(field.id)) {
                                ForEach(
                                    field.rows,
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
                                                .blur(this.maskBlur())
                                        }
                                        .width(100.percent)
                                        .padding(top: SPACING_SMALL, bottom: SPACING_SMALL, left: SPACING_MEDIUM, right: 0.0)
                                    },
                                    keyGenerator: { row: ClaimRow, ridx: Int64 => "${field.id}_r_${ridx}" }
                                )
                            }
                        } else {
                            Column(space: SPACING_EXTRA_SMALL) {
                                Text(field.title)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                                Text(field.value)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                                    .blur(this.maskBlur())
                            }
                            .width(100.percent)
                            .padding(top: SPACING_SMALL, bottom: SPACING_SMALL, left: 0.0, right: 0.0)
                        }
                        if (idx < this.documentFields.size - 1) {
                            ListDividerView()
                        }
                    }
                    .width(100.percent)
                },
                keyGenerator: { field: DocumentField, _: Int64 => field.id }
            )
        }
        .width(100.percent)
        .padding(SPACING_MEDIUM)
        .backgroundColor(uiColor(ThemeManager.shared.color.groupedElevatedBackground))
        .borderRadius(18.0)
    }

    private func isGroupExpanded(id: String): Bool {
        if (this.expandedGroups.contains(id)) {
            return this.expandedGroups[id]
        }
        return false
    }

    // Reassign a fresh map so @State observes the change and re-renders the list.
    private func toggleGroup(id: String): Unit {
        let cur = this.isGroupExpanded(id)
        let next = HashMap<String, Bool>()
        for ((k, v) in this.expandedGroups) {
            next[k] = v
        }
        next[id] = !cur
        this.expandedGroups = next
    }

    private func groupChevron(id: String): String {
        if (this.isGroupExpanded(id)) {
            return ThemeManager.shared.image.chevronUp
        }
        return ThemeManager.shared.image.chevronDown
    }

    private func maskBlur(): Float64 {
        if (this.isVisible) {
            return 0.0
        }
        // Strong enough that the value is genuinely unreadable (6.0 left text
        // legible). iOS obscures the value entirely when hidden.
        return 20.0
    }

    // ── Overflow menu (reissue / remove) ──

    /** iOS reissuance alert actions: Reissue (issued only) / Remove / Cancel. */
    private func menuActions(): Array<AlertAction> {
        let actions = ArrayList<AlertAction>()
        if (!this.isRevoked) {
            actions.add(
                AlertAction(
                    title: LocalizableStringKey.documentDetailsReIssueButton,
                    callback: { => this.reissue() }
                )
            )
        }
        actions.add(
            AlertAction(
                title: LocalizableStringKey.documentDetailsRemoveButton,
                isDestructive: true,
                callback: { =>
                    this.showMenu = false
                    this.showDeleteDialog = true
                }
            )
        )
        actions.add(
            AlertAction(
                title: LocalizableStringKey.cancelButton,
                callback: { => this.showMenu = false }
            )
        )
        return actions.toArray()
    }

    @Builder
    private func menuDialog() {
        AlertView(
            title: LocalizableStringKey.custom(""),
            message: LocalizableStringKey.custom(""),
            actions: this.menuActions(),
            onDismiss: { => this.showMenu = false }
        )
    }
}
