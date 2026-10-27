/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (DesignSystem/Component/Alert/AlertView.swift + Sheet usage) to Cangjie.
 *
 * SwiftUI `.alert` is a system dialog; here it is a self-drawn overlay:
 * a scrim with the alpha baked into the color (a container-level
 * `.opacity()` would also fade the dialog card — QA-confirmed trap) and an
 * opaque card with title / message / action buttons. Host pages show it
 * conditionally: `if (showAlert) { AlertView(...) }` inside a Stack.
 */
package eudi_logic_ui

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/** One alert button: label + callback + optional destructive tint. */
public class AlertAction {
    public let title: LocalizableStringKey
    public let isDestructive: Bool
    public let callback: () -> Unit

    public init(
        title!: LocalizableStringKey,
        isDestructive!: Bool = false,
        callback!: () -> Unit = { => }
    ) {
        this.title = title
        this.isDestructive = isDestructive
        this.callback = callback
    }

    public func titleText(): String {
        LocalizableManager.get(this.title)
    }
}

/** Baked-alpha scrim color shared by AlertView and sheet hosts. */
public let EUDI_SCRIM_COLOR: UInt32 = 0x99000000

/**
 * Mirrors Swift `alertView(isPresented:title:message:actions:)` as a
 * component: scrim + opaque dialog card. Tapping the scrim invokes
 * `onDismiss`; actions render as horizontally laid-out buttons.
 */
@Component
public class AlertView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var message: LocalizableStringKey = LocalizableStringKey.custom("")
    public var actions: Array<AlertAction> = Array<AlertAction>()
    public var onDismiss: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func messageText(): String {
        LocalizableManager.get(this.message)
    }

    private func actionColor(action: AlertAction): Color {
        if (action.isDestructive) {
            return uiColor(ThemeManager.shared.color.red)
        }
        // iOS alert capsule button: black label on a gray fill (not accent blue).
        return uiColor(ThemeManager.shared.color.primaryLabel)
    }

    public func build() {
        Stack(alignContent: Alignment.Center) {
            // Scrim: alpha baked into the color, card stays opaque.
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                .expandSafeArea(types: [SafeAreaType.System], edges: [SafeAreaEdge.Bottom])
                .onClick({ _ => this.onDismiss() })
            // Frosted-glass card (translucent fill + backdrop blur), mirroring the
            // iOS system alert: left-aligned title/message and gray capsule buttons.
            Column(space: SPACING_MEDIUM) {
                if (!this.titleText().isEmpty()) {
                    Text(this.titleText())
                        .fontSize(uiFontSize(ThemeManager.shared.font.labelLarge))
                        .fontWeight(FontWeight.Bold)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }
                if (!this.messageText().isEmpty()) {
                    Text(this.messageText())
                        .fontSize(uiFontSize(ThemeManager.shared.font.bodySmall))
                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                        .textAlign(TextAlign.Start)
                        .width(100.percent)
                }
                // iOS two-button alerts sit side by side; 3+ stack vertically.
                if (this.actions.size == 2) {
                    Row(space: SPACING_SMALL) {
                        ForEach(
                            this.actions,
                            itemGenerator: { action: AlertAction, _: Int64 =>
                                Button(action.titleText())
                                    .fontColor(this.actionColor(action))
                                    .fontWeight(FontWeight.Medium)
                                    .backgroundColor(uiColor(ThemeManager.shared.color.fill))
                                    .borderRadius(22.0)
                                    .layoutWeight(1)
                                    .height(44.0)
                                    .onClick({ _ => action.callback() })
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(top: SPACING_SMALL, right: 0.0, bottom: 0.0, left: 0.0)
                } else {
                    Column(space: SPACING_SMALL) {
                        ForEach(
                            this.actions,
                            itemGenerator: { action: AlertAction, _: Int64 =>
                                Button(action.titleText())
                                    .fontColor(this.actionColor(action))
                                    .fontWeight(FontWeight.Medium)
                                    .backgroundColor(uiColor(ThemeManager.shared.color.fill))
                                    .borderRadius(22.0)
                                    .width(100.percent)
                                    .height(44.0)
                                    .onClick({ _ => action.callback() })
                            }
                        )
                    }
                    .width(100.percent)
                    .padding(top: SPACING_SMALL, right: 0.0, bottom: 0.0, left: 0.0)
                }
            }
            .width(280.0)
            .alignItems(HorizontalAlign.Start)
            .padding(SPACING_MEDIUM_LARGE)
            // Near-opaque light fill (no backdrop blur): the blur bled past the
            // rounded clip and left a gray halo on the corners. Clean rounded card.
            .backgroundColor(Color(0xF7F2F5FCu32))
            .borderRadius(ThemeManager.shared.shape.large)
            .clip(true)
            .transition(TransitionEffect.OPACITY)
        }
        .width(100.percent)
        .height(100.percent)
    }
}

/**
 * Mirrors Swift `.confirmationDialog` (iOS action sheet): a bottom-anchored,
 * full-width sheet with the title/message header + non-cancel actions in one
 * rounded group and the destructive Cancel in its own group below. Use this for
 * choice prompts (e.g. Authenticate In-person / Online); keep AlertView for true
 * `.alert` dialogs (Learn more / errors).
 */
@Component
public class ConfirmationSheetView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var message: LocalizableStringKey = LocalizableStringKey.custom("")
    public var actions: Array<AlertAction> = Array<AlertAction>()
    public var onDismiss: () -> Unit = { => }
    // Default clears the dashboard's floating tab bar; screens without one
    // (e.g. Settings) pass a small inset so the sheet sits on the bottom edge.
    public var bottomInset: Float64 = 110.0
    // Header title color/font overrides (e.g. a file-preview header uses a
    // primaryLabel small-type name line).
    public var titleColor: ?Color = None
    public var titleFont: ?TypographyStyle = None
    public var messageFont: ?TypographyStyle = None
    // Leading header icon (iOS share-preview file thumbnail). When set, the
    // header lays out as icon + left-aligned title/message instead of centered.
    public var titleIconSrc: String = ""

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func messageText(): String {
        LocalizableManager.get(this.message)
    }

    private func hasDestructiveAction(): Bool {
        for (action in this.actions) {
            if (action.isDestructive) {
                return true
            }
        }
        return false
    }

    @Builder
    private func sheetButton(action: AlertAction) {
        Button(action.titleText())
            .fontColor(
                if (action.isDestructive) {
                    uiColor(ThemeManager.shared.color.red)
                } else {
                    uiColor(ThemeManager.shared.color.accent)
                }
            )
            .fontWeight(FontWeight.Medium)
            .backgroundColor(Color.Transparent)
            .width(100.percent)
            .height(50.0)
            .onClick({ _ => action.callback() })
    }

    public func build() {
        Stack(alignContent: Alignment.Bottom) {
            // Scrim: alpha baked into the color, card stays opaque.
            Column() {}
                .width(100.percent)
                .height(100.percent)
                .backgroundColor(Color(EUDI_SCRIM_COLOR))
                .expandSafeArea(types: [SafeAreaType.System], edges: [SafeAreaEdge.Bottom])
                .onClick({ _ => this.onDismiss() })
            Column(space: SPACING_SMALL) {
                // Main group: header (title + message) + non-cancel actions.
                Column(space: SPACING_NONE) {
                    if (!this.titleText().isEmpty() || !this.messageText().isEmpty()) {
                        if (!this.titleIconSrc.isEmpty()) {
                            // iOS share-preview header: file icon + left-aligned
                            // name/subtitle pair.
                            Row(space: SPACING_MEDIUM_SMALL) {
                                Image(appImageSrc(this.titleIconSrc))
                                    .width(36.0)
                                    .height(36.0)
                                    .objectFit(ImageFit.Contain)
                                Column(space: SPACING_EXTRA_SMALL) {
                                    if (!this.titleText().isEmpty()) {
                                        Text(this.titleText())
                                            .fontSize(uiFontSize(this.titleFont ?? ThemeManager.shared.font.bodyMedium))
                                            .fontWeight(FontWeight.Bold)
                                            .fontColor(this.titleColor ?? uiColor(ThemeManager.shared.color.secondaryLabel))
                                            .textAlign(TextAlign.Start)
                                            .width(100.percent)
                                    }
                                    if (!this.messageText().isEmpty()) {
                                        Text(this.messageText())
                                            .fontSize(uiFontSize(this.messageFont ?? ThemeManager.shared.font.bodySmall))
                                            .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                            .textAlign(TextAlign.Start)
                                            .width(100.percent)
                                    }
                                }
                                .layoutWeight(1)
                                .alignItems(HorizontalAlign.Start)
                            }
                            .width(100.percent)
                            .alignItems(VerticalAlign.Center)
                            .padding(SPACING_MEDIUM)
                            ListDividerView(spacing: 0.0)
                        } else {
                            Column(space: SPACING_EXTRA_SMALL) {
                                if (!this.titleText().isEmpty()) {
                                    Text(this.titleText())
                                        .fontSize(uiFontSize(this.titleFont ?? ThemeManager.shared.font.bodyMedium))
                                        .fontWeight(FontWeight.Bold)
                                        .fontColor(this.titleColor ?? uiColor(ThemeManager.shared.color.secondaryLabel))
                                        .textAlign(TextAlign.Center)
                                        .width(100.percent)
                                }
                                if (!this.messageText().isEmpty()) {
                                    Text(this.messageText())
                                        .fontSize(uiFontSize(this.messageFont ?? ThemeManager.shared.font.bodySmall))
                                        .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                                        .textAlign(TextAlign.Center)
                                        .width(100.percent)
                                }
                            }
                            .width(100.percent)
                            .padding(SPACING_MEDIUM)
                            ListDividerView(spacing: 0.0)
                        }
                    }
                    ForEach(
                        this.actions,
                        itemGenerator: { action: AlertAction, idx: Int64 =>
                            Column(space: SPACING_NONE) {
                                if (!action.isDestructive) {
                                    this.sheetButton(action)
                                    if (idx < this.actions.size - 1 && !this.actions[idx + 1].isDestructive) {
                                        ListDividerView(spacing: 0.0)
                                    }
                                }
                            }
                            .width(100.percent)
                        }
                    )
                }
                .width(100.percent)
                .backgroundColor(Color(0xF7F2F5FCu32))
                .borderRadius(ThemeManager.shared.shape.large)
                .clip(true)
                // Cancel group (destructive actions), separated below. One
                // shared container — per-action wrappers left zero-height
                // styled columns for non-destructive actions (stray hairlines).
                if (this.hasDestructiveAction()) {
                    Column(space: SPACING_NONE) {
                        ForEach(
                            this.actions,
                            itemGenerator: { action: AlertAction, _: Int64 =>
                                Column(space: SPACING_NONE) {
                                    if (action.isDestructive) {
                                        this.sheetButton(action)
                                    }
                                }
                                .width(100.percent)
                            }
                        )
                    }
                    .width(100.percent)
                    .backgroundColor(Color(0xF7F2F5FCu32))
                    .borderRadius(ThemeManager.shared.shape.large)
                    .clip(true)
                }
            }
            .width(100.percent)
            // Bottom inset clears the floating tab bar (it overlays content) so the
            // separated Cancel group stays fully visible above it.
            .padding(top: 0.0, right: SPACING_MEDIUM, bottom: this.bottomInset, left: SPACING_MEDIUM)
        }
        .width(100.percent)
        .height(100.percent)
        // Let the scrim paint under the bottom system bar; otherwise a white
        // strip survives below the sheet.
        .expandSafeArea(types: [SafeAreaType.System], edges: [SafeAreaEdge.Bottom])
    }
}
