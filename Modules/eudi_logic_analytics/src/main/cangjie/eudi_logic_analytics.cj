/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * eudi_logic_analytics — EUDI analytics module (Cangjie HAR).
 * Ported from iOS logic-analytics module (Modules/logic-analytics/Sources/).
 *
 * Public surface:
 *   interface AnalyticsProvider  — low-level sink (analytics_provider.cj)
 *   interface AnalyticsConfig    — provider registry (analytics_config.cj)
 *   interface AnalyticsController
 *   class     AnalyticsControllerImpl  (analytics_controller.cj)
 *   func      makeAnalyticsController  (logic_analytics_assembly.cj)
 *
 * iOS provider nature: AnalyticsProvider is a pure protocol with no concrete implementation
 * in this module.  Real SDK adapters (e.g. Firebase) are injected by the host application.
 * Cangjie faithfully mirrors this — no no-op shim is added.
 */
package eudi_logic_analytics
