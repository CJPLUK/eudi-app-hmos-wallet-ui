/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-assembly module
 * (Sources/Router/RouterHost.swift — RouterHostImpl) to Cangjie for the
 * EUDI HarmonyOS wallet.
 *
 * ProdRouterHost is the composition-root implementation of RouterHost that drives
 * navigation through a shared NavPathStack. It mirrors RouterHostImpl's 10 methods:
 * push / pop / popTo(inclusive) / popTo / getCurrentScreen / getToolbarConfig /
 * userIsLoggedInWithDocuments / userIsLoggedInWithNoDocuments / isScreenForeground /
 * isScreenOnBackStack.
 *
 * Stack sync contract:
 *   - pathNames is a mirror of NavPathStack used for queries (Cangjie bindings
 *     expose only pushPath / pop — not getAllPathName / size).
 *   - Every mutation is under navLock and must keep the two at the same depth.
 *   - pop() / popTo() call navStack.pop() FIRST; only on Some(_) do they trim
 *     pathNames. If pop returns None the real stack is already empty — pathNames
 *     is wiped to match (never keep phantom entries that would drive extra pops).
 *   - pushPath runs before pathNames.add so a failed push cannot leave a phantom.
 *   - popTo keeps incremental "peel until route" semantics; it does NOT clear+push
 *     dashboard on every home return. If peeling empties the real stack before
 *     landing on dashboard, a single push(dashboard) repairs go-home intent.
 */
package ohos_app_cangjie_entry

import kit.ArkUI.*
import std.collection.ArrayList
import std.sync.*
import ohos.hilog.*
import eudi_logic_ui.*
import eudi_logic_resources.{ThemeManager, ThemeColor}

/**
 * Production implementation of RouterHost backed by the ArkUI NavPathStack.
 */
public class ProdRouterHost <: RouterHost {
    private var navStack: NavPathStack
    private let configLogic: ConfigUiLogic
    private let pathNames: ArrayList<String> = ArrayList<String>()
    private let navLock = Mutex()

    public init(navStack!: NavPathStack, configLogic!: ConfigUiLogic) {
        this.navStack = navStack
        this.configLogic = configLogic
    }

    public func push(route: String): Unit {
        var drainDeepLink = false
        synchronized(this.navLock) {
            Hilog.info(0, "NavDebug", "push route=${route} depthBefore=${this.pathNames.size}")
            // Real stack first — never record a phantom mirror entry.
            this.navStack.pushPath(NavPathInfo(name: route, param: Option<String>.None))
            this.pathNames.add(route)
            drainDeepLink = (route == AppRoutes.dashboard)
        }
        if (drainDeepLink) {
            DeepLinkRouter.consume()
        }
    }

    public func pop(): Unit {
        synchronized(this.navLock) {
            this.popRealAndMirror()
        }
    }

    /**
     * Incremental popTo (iOS semantics): peel until `route` is on top.
     * startup → clear all pushed destinations.
     * Missing target → no-op.
     * If the real stack empties mid-peel (mirror was deeper), sync mirror to
     * empty; for dashboard go-home, push once to repair.
     */
    public func popTo(route: String, inclusive: Bool): Unit {
        var drainDeepLink = false
        var repairDashboard = false
        synchronized(this.navLock) {
            var dbg = ""
            for (n in this.pathNames) { dbg = dbg + n + "," }
            Hilog.info(0, "NavDebug", "popTo route=${route} inclusive=${inclusive} stack=[${dbg}]")
            if (route == AppRoutes.startup) {
                this.clearRealAndMirror()
                return
            }
            if (!this.isScreenOnBackStackUnlocked(route)) {
                Hilog.warn(0, "NavDebug", "popTo target not on stack — no-op route=${route}")
                return
            }
            while (this.pathNames.size > 0 && this.pathNames[this.pathNames.size - 1] != route) {
                if (!this.popRealAndMirror()) {
                    // Real stack empty; mirror wiped inside popRealAndMirror.
                    break
                }
            }
            if (inclusive && this.pathNames.size > 0 &&
                this.pathNames[this.pathNames.size - 1] == route) {
                this.popRealAndMirror()
            }
            if (route == AppRoutes.dashboard && !inclusive) {
                // Mirror can still claim dashboard while the real stack is
                // empty (desync). Probe the real stack; repair if empty or
                // mirror top is wrong.
                if (this.probeRealStackEmptyUnlocked() ||
                    this.pathNames.size == 0 ||
                    this.pathNames[this.pathNames.size - 1] != AppRoutes.dashboard) {
                    Hilog.warn(0, "NavDebug", "popTo dashboard unmet/empty-real — push repair")
                    while (this.pathNames.size > 0) {
                        this.pathNames.remove(at: this.pathNames.size - 1)
                    }
                    repairDashboard = true
                } else {
                    drainDeepLink = true
                }
            }
        }
        if (repairDashboard) {
            this.push(AppRoutes.dashboard)
        } else if (drainDeepLink) {
            DeepLinkRouter.consume()
        }
    }

    public func popTo(route: String): Unit {
        this.popTo(route, false)
    }

    public func getCurrentScreen(): ?String {
        synchronized(this.navLock) {
            if (this.pathNames.size > 0) {
                return Some(this.pathNames[this.pathNames.size - 1])
            }
            return None
        }
    }

    public func getToolbarConfig(): UIConfigToolBar {
        match (this.getCurrentScreen()) {
            case Some(screen) =>
                match (this.configLogic.toolBarConfigFor(screen)) {
                    case Some(cfg) => cfg
                    case None => UIConfigToolBar(uiColor(ThemeManager.shared.color.background))
                }
            case None => UIConfigToolBar(uiColor(ThemeManager.shared.color.primaryLabel))
        }
    }

    public func userIsLoggedInWithDocuments(): Bool {
        isForegroundOrBackStack(AppRoutes.dashboard)
    }

    public func userIsLoggedInWithNoDocuments(): Bool {
        isForegroundOrBackStack(AppRoutes.issuanceAddDocument)
    }

    public func isScreenForeground(route: String): Bool {
        match (this.getCurrentScreen()) {
            case Some(current) => current == route
            case None => false
        }
    }

    public func isScreenOnBackStack(route: String): Bool {
        synchronized(this.navLock) {
            return this.isScreenOnBackStackUnlocked(route)
        }
    }

    /**
     * Probe whether NavPathStack is empty without relying on pathNames.
     * Pops one entry and pushes it back when present.
     */
    public func realStackIsEmpty(): Bool {
        synchronized(this.navLock) {
            return this.probeRealStackEmptyUnlocked()
        }
    }

    public func runOnUi(work: () -> Unit): Unit {
        spawn(UIThread) { => work() }
    }

    // ── Private helpers ─────────────────────────────────────────────────────

    private func isScreenOnBackStackUnlocked(route: String): Bool {
        for (name in this.pathNames) {
            if (name == route) {
                return true
            }
        }
        return false
    }

    private func isForegroundOrBackStack(route: String): Bool {
        isScreenForeground(route) || isScreenOnBackStack(route)
    }

    /**
     * Returns true when the real stack is empty. If a page is present it is
     * immediately pushed back so the probe is non-destructive for go-home.
     */
    private func probeRealStackEmptyUnlocked(): Bool {
        match (this.navStack.pop()) {
            case None =>
                if (this.pathNames.size > 0) {
                    Hilog.warn(0, "NavDebug", "probe: real empty, wiping mirror depth=${this.pathNames.size}")
                    while (this.pathNames.size > 0) {
                        this.pathNames.remove(at: this.pathNames.size - 1)
                    }
                }
                return true
            case Some(info) =>
                this.navStack.pushPath(info)
                return false
        }
    }

    /**
     * Pop the real NavPathStack; only trim pathNames when pop returns Some.
     * When pop returns None the real stack is empty — wipe pathNames so the
     * mirror cannot drive further phantom peels. Returns true if a real page
     * was popped.
     */
    private func popRealAndMirror(): Bool {
        match (this.navStack.pop()) {
            case Some(_) =>
                if (this.pathNames.size > 0) {
                    this.pathNames.remove(at: this.pathNames.size - 1)
                }
                return true
            case None =>
                if (this.pathNames.size > 0) {
                    Hilog.warn(0, "NavDebug", "real stack empty with mirror depth=${this.pathNames.size} — wiping mirror")
                    while (this.pathNames.size > 0) {
                        this.pathNames.remove(at: this.pathNames.size - 1)
                    }
                }
                return false
        }
    }

    private func clearRealAndMirror(): Unit {
        while (this.popRealAndMirror()) {
            ()
        }
        while (this.pathNames.size > 0) {
            this.pathNames.remove(at: this.pathNames.size - 1)
        }
    }
}
