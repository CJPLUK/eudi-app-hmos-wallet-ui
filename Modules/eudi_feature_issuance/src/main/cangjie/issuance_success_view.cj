/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-issuance
 * module (UI/Success/DocumentIssuanceSuccessView.swift, which reuses
 * feature-common DocumentSuccessView / DocumentSuccessViewModel) to Cangjie.
 *
 * The document-issuance success screen, mirroring the iOS DocumentSuccessView
 * layout top-to-bottom:
 *  - ContentHeader: the EUDI app icon/wordmark + a success description +
 *    the issuer (logo + name) of the issued document(s)
 *  - per-document field-detail sections (document name + its claim list,
 *    rendered as a built-in success-tinted card; built-ins only inside the
 *    ForEach generator, R-102)
 *  - a pinned "Done" primary button that dispatches the success navigation
 *
 * This replaces the previous generic-success routing for issuance: routeToSuccess
 * now builds a DocumentIssuanceSuccessUIConfig (carrying the issued documents
 * with their issuer + fields) and pushes AppRoutes.issuanceSuccess.
 *
 * Blocking is not needed here (the documents are already fetched by the VM
 * before routing); the view renders the config directly. Rows inside ForEach
 * generators use built-in components only (R-102).
 */
package eudi_feature_issuance

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import std.collection.ArrayList
import std.collection.HashMap
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, LocalizableStringKey, LocalizableManager}
import eudi_feature_common.dispatchDeepLinkNavigation

/**
 * Config driving the issuance-success screen — the Cangjie analogue of the iOS
 * DocumentSuccessUIConfig + requestItems pair: the issuer header data plus the
 * list of issued documents (name + fields). Travels through NavArgs under
 * AppRoutes.issuanceSuccess as a RouteConfigArgs.
 */
public class DocumentIssuanceSuccessUIConfig <: UIConfigType {
    public let relyingParty: String
    public let issuerLogoUrl: String
    public let documents: ArrayList<IssuedDocumentSummary>
    public let successNavigation: DeepLinkNavigationType

    public init(
        relyingParty!: String,
        issuerLogoUrl!: String,
        documents!: ArrayList<IssuedDocumentSummary>,
        successNavigation!: DeepLinkNavigationType
    ) {
        this.relyingParty = relyingParty
        this.issuerLogoUrl = issuerLogoUrl
        this.documents = documents
        this.successNavigation = successNavigation
    }

    public prop log: String {
        get() { "issuanceSuccess relyingParty: ${this.relyingParty} docs: ${this.documents.size}" }
    }
}

/** Holds the resolved issuance-success config + the router for Done dispatch. */
public class DocumentIssuanceSuccessViewModel <: BaseViewModel<EmptyViewState> {
    public let config: DocumentIssuanceSuccessUIConfig

    public init(router!: RouterHost, config!: DocumentIssuanceSuccessUIConfig) {
        super(router, EmptyViewState())
        this.config = config
    }

    public func onDone(): Unit {
        dispatchDeepLinkNavigation(this.router, this.config.successNavigation)
    }
}

/** Trivial state (the success screen is config-driven, no async state). */
public class EmptyViewState <: ViewState {
    public init() {}
}

@Component
public class DocumentIssuanceSuccessView {
    public var viewModel: ?DocumentIssuanceSuccessViewModel = Option<DocumentIssuanceSuccessViewModel>.None

    private var vm: ?DocumentIssuanceSuccessViewModel = Option<DocumentIssuanceSuccessViewModel>.None

    /** Per-document expanded flag — iOS WrapExpandableListView collapses each
     *  document card by default ("View details" + chevron toggles it open). */
    @State
    var expandedDocs: HashMap<String, Bool> = HashMap<String, Bool>()

    protected override func aboutToAppear(): Unit {
        this.vm = this.viewModel
    }

    private func isDocExpanded(id: String): Bool {
        if (this.expandedDocs.contains(id)) {
            return this.expandedDocs[id]
        }
        return false
    }

    // Rebuild the map so ArkUI @State observes the mutation (assignment, not
    // in-place update — same pattern as DocumentDetails.expandedGroups).
    private func toggleDoc(id: String): Unit {
        let next = HashMap<String, Bool>()
        for ((k, v) in this.expandedDocs) {
            next[k] = v
        }
        next[id] = !this.isDocExpanded(id)
        this.expandedDocs = next
    }

    private func docChevron(id: String): String {
        if (this.isDocExpanded(id)) {
            return ThemeManager.shared.image.chevronUp
        }
        return ThemeManager.shared.image.chevronDown
    }

    private func relyingParty(): String {
        match (this.vm) {
            case Some(model) => model.config.relyingParty
            case None => ""
        }
    }

    private func issuerLogoUrl(): String {
        match (this.vm) {
            case Some(model) => model.config.issuerLogoUrl
            case None => ""
        }
    }

    private func documents(): Array<IssuedDocumentSummary> {
        match (this.vm) {
            case Some(model) => model.config.documents.toArray()
            case None => Array<IssuedDocumentSummary>()
        }
    }

    private func onDone(): Unit {
        match (this.vm) {
            case Some(model) => model.onDone()
            case None => ()
        }
    }

    public func build() {
        NavDestination() {
            Column {
                // Centered inline navigation title — iOS ContentScreenView
                // navigationTitle: .documentAdded ("Add Document").
                Text(LocalizableManager.get(LocalizableStringKey.documentAdded))
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontWeight(FontWeight.Bold)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .width(100.percent)
                    .textAlign(TextAlign.Center)
                    .padding(top: SPACING_MEDIUM, bottom: SPACING_SMALL, left: SPACING_MEDIUM, right: SPACING_MEDIUM)
                Scroll {
                    // iOS: ContentHeaderView + VSpacer.large() + documents (SPACING_LARGE = 32).
                    Column(space: SPACING_LARGE) {
                        this.contentHeader()
                        this.documentSections()
                    }
                    .width(100.percent)
                    .padding(ThemeManager.shared.dimension.padding)
                }
                .align(Alignment.TopStart)
                .layoutWeight(1)
                // Pinned Done button (iOS safeAreaInset bottom).
                Column {
                    WrapButtonView(
                        title: LocalizableStringKey.doneButton,
                        style: ButtonViewStyle.primary(),
                        onAction: { => this.onDone() }
                    )
                }
                .width(100.percent)
                .padding(top: SPACING_MEDIUM, right: SPACING_MEDIUM, bottom: SPACING_LARGE_MEDIUM, left: SPACING_MEDIUM)
            }
            .width(100.percent)
            .height(100.percent)
            .backgroundColor(uiColor(ThemeManager.shared.color.background))
        }
        .hideTitleBar(true)
    }

    // ── ContentHeader (app icon/wordmark + description + issuer) ──

    @Builder
    private func contentHeader() {
        ContentHeaderView(
            config: ContentHeaderConfig(
                appIconAndTextData: AppIconAndTextData(
                    appIconSrc: ThemeManager.shared.image.logoEuDigitalIndentityWallet,
                    appTextSrc: ThemeManager.shared.image.euditext
                ),
                description: LocalizableStringKey.issuanceSuccessHeaderDescription,
                relyingPartyData: RelyingPartyData(
                    logoUrl: this.issuerLogoUrl(),
                    isVerified: false,
                    name: LocalizableStringKey.custom(this.relyingParty())
                )
            )
        )
    }

    // ── Per-document field-detail sections ──
    //
    // Each issued document renders as a success-tinted expandable card,
    // mirroring the iOS WrapExpandableListView: header row = document name
    // (headlineMedium bold) over a "View details" supporting line, trailing
    // chevron; collapsed by default, tap toggles the claim rows open. Header
    // typography/spacing replicates WrapListItemView (MainBold + supporting).
    // Built-in components only inside the ForEach generator (R-102).

    @Builder
    private func documentSections() {
        Column(space: SPACING_MEDIUM) {
            ForEach(
                this.documents(),
                itemGenerator: { doc: IssuedDocumentSummary, _: Int64 =>
                    Column(space: SPACING_NONE) {
                        // Header (WrapListItemView layout: main + supporting, chevron trailing)
                        Row(space: SPACING_MEDIUM) {
                            Column(space: SPACING_EXTRA_SMALL) {
                                Text(doc.name)
                                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                                    .fontWeight(FontWeight.Bold)
                                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                                Text(LocalizableManager.get(LocalizableStringKey.viewDetails))
                                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyMedium))
                                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                    .width(100.percent)
                                    .textAlign(TextAlign.Start)
                            }
                            .alignItems(HorizontalAlign.Start)
                            .layoutWeight(1)
                            // Trailing chevron — accent tint (WrapListItemView
                            // TrailingContentData.icon default, matches iOS).
                            Image(appImageSrc(this.docChevron(doc.id)))
                                .width(16.0)
                                .height(16.0)
                                .objectFit(ImageFit.Contain)
                                .fillColor(uiColor(ThemeManager.shared.color.accent))
                        }
                        .width(100.percent)
                        .padding(SPACING_MEDIUM)
                        .onClick({ _ => this.toggleDoc(doc.id) })
                        // Expanded body: claim rows (document-details typography).
                        if (this.isDocExpanded(doc.id)) {
                            Column(space: SPACING_NONE) {
                                ForEach(
                                    doc.fields,
                                    itemGenerator: { field: SuccessFieldRow, _: Int64 =>
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
                                        }
                                        .width(100.percent)
                                        .padding(top: SPACING_SMALL, bottom: SPACING_SMALL, left: 0.0, right: 0.0)
                                    }
                                )
                            }
                            .width(100.percent)
                            .padding(top: 0.0, bottom: SPACING_MEDIUM, left: SPACING_MEDIUM, right: SPACING_MEDIUM)
                        }
                    }
                    .width(100.percent)
                    .backgroundColor(uiColor(ThemeManager.shared.color.successBackground))
                    .borderRadius(18.0)
                    .clip(true)
                },
                keyGenerator: { doc: IssuedDocumentSummary, _: Int64 => doc.id }
            )
        }
        .width(100.percent)
    }
}
