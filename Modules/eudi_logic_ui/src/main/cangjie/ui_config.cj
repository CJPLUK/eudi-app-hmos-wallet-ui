/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-ui module
 * (Config/UIConfig.swift) to Cangjie for the EUDI HarmonyOS wallet.
 *
 * Swift nested types (UIConfig.ToolBar, UIConfig.TwoWayNavigationType, ...)
 * are flattened to top-level `UIConfig*` names because Cangjie has no nested
 * type declarations. Route associated values (`AppRoute`) become route-name
 * strings from `AppRoutes` (see app_routes.cj).
 */
package eudi_logic_ui

import ohos.base.*
import std.collection.HashMap

/**
 * Marker protocol for every screen configuration model.
 * Mirrors Swift `UIConfigType` (`var log: String { get }`).
 */
public interface UIConfigType {
    prop log: String
}

/**
 * Empty configuration. Mirrors Swift `NoConfig` (Equatable: all instances equal).
 */
public class NoConfig <: UIConfigType {
    public init() {}

    public prop log: String {
        get() { "" }
    }

    public operator func ==(that: NoConfig): Bool {
        true
    }

    public operator func !=(that: NoConfig): Bool {
        false
    }
}

/**
 * Toolbar (navigation chrome) configuration. Mirrors Swift `UIConfig.ToolBar`
 * which carries only the toolbar background color.
 */
public class UIConfigToolBar {
    public let backgroundColor: Color

    public init(backgroundColor: Color) {
        this.backgroundColor = backgroundColor
    }

    public operator func ==(that: UIConfigToolBar): Bool {
        this.backgroundColor.toUInt32() == that.backgroundColor.toUInt32()
    }

    public operator func !=(that: UIConfigToolBar): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `UIConfig.TwoWayNavigationType` — either pop back to a route
 * or push a new route. The payload is an `AppRoutes` route-name constant.
 */
public enum TwoWayNavigationType {
    | NavPopTo(String)
    | NavPush(String)

    public func key(): String {
        match (this) {
            case NavPopTo(route) => "pop to ${route}"
            case NavPush(route) => "push to ${route}"
        }
    }

    public operator func ==(that: TwoWayNavigationType): Bool {
        this.key() == that.key()
    }

    public operator func !=(that: TwoWayNavigationType): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `UIConfig.ThreeWayNavigationType` — pop-to / plain pop / push.
 */
public enum ThreeWayNavigationType {
    | ThreeWayPopTo(String)
    | ThreeWayPop
    | ThreeWayPush(String)
    /** Push without clearing the active flow (iOS `.push` from request auth). */
    | ThreeWayPushInFlow(String)

    public func key(): String {
        match (this) {
            case ThreeWayPopTo(route) => "pop to ${route}"
            case ThreeWayPush(route) => "push to ${route}"
            case ThreeWayPushInFlow(route) => "push in flow to ${route}"
            case ThreeWayPop => "pop back"
        }
    }

    public operator func ==(that: ThreeWayNavigationType): Bool {
        this.key() == that.key()
    }

    public operator func !=(that: ThreeWayNavigationType): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `UIConfig.DeepLinkNavigationType`. The deep-link case carries
 * the link URL string plus the route to pop back to before opening it.
 */
public enum DeepLinkNavigationType {
    | DeepLinkPop(String, Bool)
    | DeepLinkPush(String)
    | DeepLinkOpen(String, String)
    | DeepLinkNone

    public func typeKey(): String {
        match (this) {
            case DeepLinkPop(route, _) => "pop to ${route}"
            case DeepLinkPush(route) => "push to ${route}"
            case DeepLinkOpen(link, _) => "open ${link}"
            case DeepLinkNone => "none"
        }
    }

    public operator func ==(that: DeepLinkNavigationType): Bool {
        this.typeKey() == that.typeKey()
    }

    public operator func !=(that: DeepLinkNavigationType): Bool {
        !(this == that)
    }
}

/**
 * Mirrors Swift `UIConfig.Generic`: free-form string arguments plus the
 * success/cancel navigation behaviour of the hosting screen.
 */
public class UIConfigGeneric <: UIConfigType {
    public let arguments: HashMap<String, String>
    public let navigationSuccessType: TwoWayNavigationType
    public let navigationCancelType: ThreeWayNavigationType

    public init(
        arguments!: HashMap<String, String> = HashMap<String, String>(),
        navigationSuccessType!: TwoWayNavigationType,
        navigationCancelType!: ThreeWayNavigationType
    ) {
        this.arguments = arguments
        this.navigationSuccessType = navigationSuccessType
        this.navigationCancelType = navigationCancelType
    }

    public prop log: String {
        get() {
            var joined = ""
            for ((_, v) in this.arguments) {
                if (!joined.isEmpty()) {
                    joined += ","
                }
                joined += v
            }
            return "arguments: '${joined}" +
                " onSuccessNav: ${this.navigationSuccessType.key()}" +
                " onCancelNav: ${this.navigationCancelType.key()}"
        }
    }

    public operator func ==(that: UIConfigGeneric): Bool {
        this.log == that.log
    }

    public operator func !=(that: UIConfigGeneric): Bool {
        !(this == that)
    }
}
