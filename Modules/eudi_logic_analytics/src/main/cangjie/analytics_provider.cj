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
 * Mirrors iOS AnalyticsProvider protocol (logic-analytics/Sources/Provider/AnalyticsProvider.swift).
 * iOS declares only the protocol interface; no concrete implementation exists in this module —
 * real SDK providers (e.g. Firebase) are injected by the host application via AnalyticsConfig.
 * Cangjie: faithful 1:1 interface — no no-op shim added, matching iOS honesty.
 */
package eudi_logic_analytics

import std.collection.HashMap

/**
 * Low-level analytics sink.  Mirrors iOS `AnalyticsProvider` protocol.
 * Concrete implementations are provided by the host application (e.g. a Firebase adapter)
 * and registered through `AnalyticsConfig.analyticsProviders`.
 */
public interface AnalyticsProvider {
    /**
     * Initialises the provider with the key it was registered under.
     * Mirrors iOS `func initialize(key: String)`.
     */
    func initialize(key: String): Unit

    /**
     * Records a screen view event.
     * Mirrors iOS `func logScreen(screen: String, arguments: [String: String])`.
     */
    func logScreen(screen: String, arguments: HashMap<String, String>): Unit

    /**
     * Records a named analytics event.
     * Mirrors iOS `func logEvent(event: String, arguments: [String: String])`.
     */
    func logEvent(event: String, arguments: HashMap<String, String>): Unit
}
