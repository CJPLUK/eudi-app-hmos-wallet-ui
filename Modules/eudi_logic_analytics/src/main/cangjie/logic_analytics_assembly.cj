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
 * Mirrors iOS LogicAnalyticsAssembly (logic-analytics/Sources/DI/LogicAnalyticsAssembly.swift).
 *
 * iOS uses Swinject:
 *   container.register(AnalyticsController.self) { r in
 *       AnalyticsControllerImpl(analyticsConfig: r.resolve(AnalyticsConfig.self))
 *   }
 *   registerConfig: NSClassFromString("AnalyticsConfigImpl") — host app reflection injection.
 *
 * Cangjie: Swinject → plain factory function.
 * `makeAnalyticsController` accepts an optional config (mirrors the iOS optional resolve).
 * Host application passes its own AnalyticsConfig implementation (or None if no SDK configured).
 * The NSClassFromString reflection trick has no Cangjie equivalent; the host passes the
 * config object directly — same runtime effect (None when no SDK, Some(cfg) when SDK present).
 */
package eudi_logic_analytics

/**
 * Factory that assembles an `AnalyticsController`.
 * Mirrors iOS `LogicAnalyticsAssembly.assemble(container:)`.
 *
 * @param analyticsConfig  Host-supplied config, or `None` when no analytics SDK is configured.
 *                         Mirrors Swift `r.resolve(AnalyticsConfig.self)` which may return nil.
 * @return A ready-to-use `AnalyticsController` instance.
 */
public func makeAnalyticsController(analyticsConfig!: ?AnalyticsConfig): AnalyticsController {
    return AnalyticsControllerImpl(analyticsConfig: analyticsConfig)
}
