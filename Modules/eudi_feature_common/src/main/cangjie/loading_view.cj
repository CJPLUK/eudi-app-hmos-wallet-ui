/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Loading/BaseLoadingView.swift + BaseLoadingViewModel)
 * to Cangjie ArkUI.
 *
 * Unified flow-transition loading screen: centred spinner (the delivered
 * eudi_logic_ui ContentLoaderView) above the "Please wait..." caption, with
 * an optional title and an optional cancel/back affordance. The actual
 * background work (iOS `doWork`) belongs to the flow that pushes this
 * screen; this shared component only renders the loading state.
 *
 * Plain @Component — composition root owns navigation chrome.
 */
package eudi_feature_common

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Loading screen (fc_common_shared_screens exposed symbol `LoadingView`).
 *
 * Injection points:
 *  - `title`: optional headline (iOS `getTitle()`; empty hides the row).
 *  - `caption`: loading message (defaults to `.pleaseWait`).
 *  - `isCancellable`: shows the leading back affordance (iOS
 *    `viewState.isCancellable`).
 *  - `onCancel`: back-tap callback (S-017: pass a real one when cancellable).
 */
@Component
public class LoadingView {
    public var title: LocalizableStringKey = LocalizableStringKey.custom("")
    public var caption: LocalizableStringKey = LocalizableStringKey.pleaseWait
    public var isCancellable: Bool = false
    public var onCancel: () -> Unit = { => }

    private func titleText(): String {
        LocalizableManager.get(this.title)
    }

    private func captionText(): String {
        LocalizableManager.get(this.caption)
    }

    public func build() {
        Column {
            Row {
                if (this.isCancellable) {
                    Text("‹")
                        .fontSize(uiFontSize(ThemeManager.shared.font.titleLarge))
                        .fontWeight(FontWeight.Bold)
                        .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                        .width(44.0)
                        .height(44.0)
                        .textAlign(TextAlign.Center)
                        .onClick({ _ => this.onCancel() })
                }
            }
            .width(100.percent)
            .height(44.0)
            .justifyContent(FlexAlign.Start)

            if (!this.titleText().isEmpty()) {
                Text(this.titleText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.headlineMedium))
                    .fontWeight(FontWeight.Medium)
                    .fontColor(uiColor(ThemeManager.shared.color.primaryLabel))
                    .textAlign(TextAlign.Center)
                    .width(100.percent)
            }

            Column(space: SPACING_MEDIUM) {
                ContentLoaderView(showLoader: true)
                Text(this.captionText())
                    .fontSize(uiFontSize(ThemeManager.shared.font.bodyLarge))
                    .fontColor(uiColor(ThemeManager.shared.color.secondaryLabel))
                    .textAlign(TextAlign.Center)
                    .width(100.percent)
            }
            .width(100.percent)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
        }
        .width(100.percent)
        .height(100.percent)
        .padding(ThemeManager.shared.dimension.padding)
        .backgroundColor(uiColor(ThemeManager.shared.color.background))
    }
}
