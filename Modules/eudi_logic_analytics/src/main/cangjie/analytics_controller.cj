/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */

/*
 * Mirrors iOS AnalyticsController protocol + AnalyticsControllerImpl class
 * (logic-analytics/Sources/Controller/AnalyticsController.swift).
 *
 * iOS class is `final class AnalyticsControllerImpl: AnalyticsController`.
 * Accepts an optional AnalyticsConfig (may be absent when no SDK is configured).
 * All three methods fan-out to every registered AnalyticsProvider.
 *
 * Cangjie: `?AnalyticsConfig` mirrors Swift `AnalyticsConfig?`.
 * HashMap iteration uses `for (key, provider) in map` (no direct forEach on HashMap).
 */
package eudi_logic_analytics

import std.collection.HashMap

/**
 * High-level analytics facade.  Mirrors iOS `public protocol AnalyticsController`.
 */
public interface AnalyticsController {
    /**
     * Initialises all registered analytics providers.
     * Mirrors iOS `func initialize()`.
     */
    func initialize(): Unit

    /**
     * Records a screen view across all providers.
     * Mirrors iOS `func logScreen(screen: String, arguments: [String: String])`.
     */
    func logScreen(screen: String, arguments: HashMap<String, String>): Unit

    /**
     * Records a named event across all providers.
     * Mirrors iOS `func logEvent(event: String, arguments: [String: String])`.
     */
    func logEvent(event: String, arguments: HashMap<String, String>): Unit
}

/**
 * Concrete implementation.  Mirrors iOS `final class AnalyticsControllerImpl`.
 *
 * Holds an optional config; when no config is provided (host did not register any SDK)
 * all calls are no-ops — identical to the iOS behaviour where `analyticsConfig?.forEach`
 * short-circuits on a nil optional.
 */
public class AnalyticsControllerImpl <: AnalyticsController {

    private let analyticsConfig: ?AnalyticsConfig

    /**
     * Mirrors iOS `init(analyticsConfig: AnalyticsConfig?)`.
     */
    public init(analyticsConfig!: ?AnalyticsConfig) {
        this.analyticsConfig = analyticsConfig
    }

    /**
     * Iterates over all registered providers and calls `initialize(key:)`.
     * Mirrors iOS `analyticsConfig?.analyticsProviders.forEach { (key, provider) in provider.initialize(key: key) }`.
     */
    public func initialize(): Unit {
        match (this.analyticsConfig) {
            case Some(cfg) =>
                for ((key, provider) in cfg.analyticsProviders) {
                    try { provider.initialize(key) } catch (_: Exception) {}
                }
            case None => ()
        }
    }

    /**
     * Fans out a screen-view event to every registered provider.
     * Mirrors iOS `analyticsConfig?.analyticsProviders.forEach { (_, provider) in provider.logScreen(...) }`.
     */
    public func logScreen(screen: String, arguments: HashMap<String, String>): Unit {
        match (this.analyticsConfig) {
            case Some(cfg) =>
                for ((_, provider) in cfg.analyticsProviders) {
                    try { provider.logScreen(screen, arguments) } catch (_: Exception) {}
                }
            case None => ()
        }
    }

    /**
     * Fans out a named event to every registered provider.
     * Mirrors iOS `analyticsConfig?.analyticsProviders.forEach { (_, provider) in provider.logEvent(...) }`.
     */
    public func logEvent(event: String, arguments: HashMap<String, String>): Unit {
        match (this.analyticsConfig) {
            case Some(cfg) =>
                for ((_, provider) in cfg.analyticsProviders) {
                    try { provider.logEvent(event, arguments) } catch (_: Exception) {}
                }
            case None => ()
        }
    }
}
