/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (Navigation/RouterHost.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * The 11 Swift protocol methods map 1:1 except `composeApplication()` which
 * is the composition root's job (it builds the ArkUI `Navigation` shell) and
 * is therefore not part of this interface. Routes are `AppRoutes` constants.
 */
package eudi_logic_ui

import std.collection.ArrayList
import eudi_logic_resources.{ThemeManager, ThemeColor, TypographyStyle, ThemeConfiguration, LocalizableStringKey, LocalizableManager}

/**
 * Navigation host consumed by feature view models. The production
 * implementation (backed by `NavPathStack`) belongs to the composition root;
 * this module owns the contract plus the `InMemoryRouterHost` test double.
 */
public interface RouterHost {
    /** Swift: push(with route: AppRoute) */
    func push(route: String): Unit
    /** Swift: pop() */
    func pop(): Unit
    /** Swift: popTo(with route: AppRoute, inclusive: Bool) */
    func popTo(route: String, inclusive: Bool): Unit
    /** Swift: popTo(with route: AppRoute) — inclusive defaults to false */
    func popTo(route: String): Unit
    /** Swift: getCurrentScreen() -> AppRoute? */
    func getCurrentScreen(): ?String
    /** Swift: getToolbarConfig() -> UIConfig.ToolBar */
    func getToolbarConfig(): UIConfigToolBar
    /** Swift: userIsLoggedInWithDocuments() -> Bool */
    func userIsLoggedInWithDocuments(): Bool
    /** Swift: userIsLoggedInWithNoDocuments() -> Bool */
    func userIsLoggedInWithNoDocuments(): Bool
    /** Swift: isScreenForeground(with route: AppRoute) -> Bool */
    func isScreenForeground(route: String): Bool
    /** Swift: isScreenOnBackStack(with route: AppRoute) -> Bool */
    func isScreenOnBackStack(route: String): Bool

    /**
     * True when ArkUI NavPathStack has no pushed destinations (Startup root
     * is showing). Must probe the real stack — the pathNames mirror can lie
     * after a desync and claim dashboard is still present.
     */
    func realStackIsEmpty(): Bool

    /**
     * Runs `work` on the ArkUI UI thread. View models perform blocking engine
     * work (e.g. auth-code resume) on background threads via spawn{}; any
     * navigation (push/pop/popTo) that follows must be marshalled back to the
     * UI thread through this method, otherwise NavPathStack mutations off the
     * UI thread silently corrupt the navigation stack (symptom: the app snaps
     * back to the splash root). The production host marshals via spawn(UIThread);
     * the in-memory test double runs synchronously.
     */
    func runOnUi(work: () -> Unit): Unit
}

/**
 * In-memory test double (mirrors the role of Swift `PreviewRouter`, but with
 * real stack behaviour so push/pop/popTo/isOnBackStack are assertable).
 */
public class InMemoryRouterHost <: RouterHost {
    private let stack: ArrayList<String> = ArrayList<String>()
    private var loggedInWithDocuments: Bool = false
    private var loggedInWithNoDocuments: Bool = true
    private let configLogic: ConfigUiLogic

    public init() {
        this.configLogic = ConfigUiLogicImpl()
    }

    public init(configLogic: ConfigUiLogic) {
        this.configLogic = configLogic
    }

    public func push(route: String): Unit {
        this.stack.add(route)
    }

    /** Pop is a no-op on an empty stack (fc failure mode `pop_empty`). */
    public func pop(): Unit {
        if (this.stack.size > 0) {
            this.stack.remove(at: this.stack.size - 1)
        }
    }

    /**
     * Pops until `route` is on top; with `inclusive` also pops `route`
     * itself. A route that is not on the stack leaves it untouched.
     * `startup` clears the in-memory stack (mirrors ProdRouterHost).
     */
    public func popTo(route: String, inclusive: Bool): Unit {
        if (route == AppRoutes.startup) {
            while (this.stack.size > 0) {
                this.stack.remove(at: this.stack.size - 1)
            }
            return
        }
        if (!this.isScreenOnBackStack(route)) {
            return
        }
        while (this.stack.size > 0 && this.stack[this.stack.size - 1] != route) {
            this.stack.remove(at: this.stack.size - 1)
        }
        if (inclusive && this.stack.size > 0) {
            this.stack.remove(at: this.stack.size - 1)
        }
    }

    public func popTo(route: String): Unit {
        this.popTo(route, false)
    }

    public func getCurrentScreen(): ?String {
        if (this.stack.size > 0) {
            return this.stack[this.stack.size - 1]
        }
        return None
    }

    /**
     * Per-screen toolbar override from `ConfigUiLogic`; default is the theme
     * background (Swift PreviewRouter returned `.init(.clear)`, but an
     * opaque theme background avoids the all-transparent Color trap).
     */
    public func getToolbarConfig(): UIConfigToolBar {
        match (this.getCurrentScreen()) {
            case Some(screen) =>
                match (this.configLogic.toolBarConfigFor(screen)) {
                    case Some(cfg) => cfg
                    case None => UIConfigToolBar(uiColor(ThemeManager.shared.color.background))
                }
            case None => UIConfigToolBar(uiColor(ThemeManager.shared.color.background))
        }
    }

    public func userIsLoggedInWithDocuments(): Bool {
        this.loggedInWithDocuments
    }

    public func userIsLoggedInWithNoDocuments(): Bool {
        this.loggedInWithNoDocuments
    }

    public func isScreenForeground(route: String): Bool {
        match (this.getCurrentScreen()) {
            case Some(current) => current == route
            case None => false
        }
    }

    public func isScreenOnBackStack(route: String): Bool {
        for (entry in this.stack) {
            if (entry == route) {
                return true
            }
        }
        return false
    }

    public func realStackIsEmpty(): Bool {
        this.stack.size == 0
    }

    /** Test double: no UI thread — run synchronously so assertions see the effect. */
    public func runOnUi(work: () -> Unit): Unit {
        work()
    }

    // ── test-double controls ────────────────────────────────────────────

    public func setLoggedInWithDocuments(value: Bool): Unit {
        this.loggedInWithDocuments = value
    }

    public func setLoggedInWithNoDocuments(value: Bool): Unit {
        this.loggedInWithNoDocuments = value
    }

    /** Current stack depth, for assertions. */
    public func stackSize(): Int64 {
        this.stack.size
    }
}
