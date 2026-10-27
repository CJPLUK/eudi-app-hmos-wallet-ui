/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-assembly module
 * (Sources/Router/RouterHostImpl.swift — RouterContainerView / composeApplication)
 * to Cangjie ArkUI for the EUDI HarmonyOS wallet.
 *
 * AppRoot is the composition root component (= iOS RouterContainerView wrapped by
 * composeApplication()). It is the @HybridComponentEntry that ArkTS loads via:
 *   CJHybridComponent({ library: "ohos_app_cangjie_entry", component: "AppRoot" })
 *
 * Responsibilities (mirroring iOS Application.body + RouterContainerView):
 *   1. Create the NavPathStack and @Provide it so all descendant pages can @Consume.
 *   2. Initialise AppComposition (DI container) once with the NavPathStack.
 *   3. Render Navigation(appStack){ StartupView() }.navDestination(bind(pageMap, this))
 *      — StartupView is the root page (iOS rootRoute = .featureStartupModule(.startup)).
 *   4. StartupView has its viewModel injected from AppComposition (real RouterHost wired).
 *
 * D-001: pageMap is a top-level @Builder (defined in app_page_map.cj).
 * D-004: .navDestination(bind(pageMap, this)) — bind is mandatory.
 * D-009: @Provide/@Consume for the shared NavPathStack.
 */
package ohos_app_cangjie_entry

import ohos.arkui.component.*
import ohos.arkui.state_macro_manage.*
import ohos.arkui.state_management.*
import ohos.base.*
import kit.ArkUI.*
import eudi_feature_startup.StartupView

/**
 * EUDI Wallet composition root. Mirrors iOS RouterContainerView:
 *   NavigationStack(path: $host.pathElements) {
 *     host.resolveView(host.rootRoute)
 *       .navigationDestination(for: AppRoute.self) { route in host.resolveView(route) }
 *   }
 *
 * The ArkUI equivalent uses Navigation(NavPathStack) + navDestination(@Builder).
 */
@HybridComponentEntry
@Component
public class AppRoot {
    /** Shared navigation stack — @Provide makes it available to all @Consume descendants. */
    @Provide
    var appStack: NavPathStack = NavPathStack()

    @State
    var compositionReady: Bool = false

    protected override func aboutToAppear(): Unit {
        AppComposition.setup(this.appStack)
        this.compositionReady = true
    }

    public func build() {
        if (this.compositionReady) {
            Navigation(this.appStack) {
                Column {
                    StartupView(
                        viewModel: Some(AppComposition.shared.startupViewModel)
                    )
                }
                .width(100.percent)
                .height(100.percent)
            }
            .hideTitleBar(true)
            .navDestination(bind(pageMap, this))
            .width(100.percent)
            .height(100.percent)
        } else {
            Stack {
            }
            .width(100.percent)
            .height(100.percent)
        }
    }
}
