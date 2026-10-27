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
 * Mirrors iOS AnalyticsConfig protocol (logic-analytics/Sources/Config/AnalyticsConfig.swift).
 * iOS `var analyticsProviders: [String: AnalyticsProvider]` → Cangjie HashMap<String, AnalyticsProvider>.
 * The host application supplies a concrete implementation; this module only declares the contract.
 */
package eudi_logic_analytics

import std.collection.HashMap

/**
 * Configuration contract for the analytics subsystem.
 * Mirrors iOS `protocol AnalyticsConfig`.
 *
 * The host application provides a concrete implementation (e.g. `AnalyticsConfigImpl`)
 * that registers one or more `AnalyticsProvider` instances keyed by a provider name.
 * The key is forwarded to `AnalyticsProvider.initialize(key:)` at startup.
 */
public interface AnalyticsConfig {
    /**
     * Supported analytics providers keyed by their registration name.
     * Mirrors iOS `var analyticsProviders: [String: AnalyticsProvider]`.
     */
    prop analyticsProviders: HashMap<String, AnalyticsProvider>
}
