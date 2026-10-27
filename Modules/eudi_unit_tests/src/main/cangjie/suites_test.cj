/*
 * std.unittest driver for the migrated iOS-parity suites.
 *
 * The suites themselves still use DeviceTestRun (named assertions, per-suite
 * Exception isolation). This file is what `cjpm test` discovers: one @TestCase
 * per suite, failed=0/error=0 required. The app HAP does not compile this
 * package — entry no longer imports it.
 */
package eudi_unit_tests

import std.unittest.*
import std.unittest.testmacro.*

func expectClean(label: String, body: (DeviceTestRun) -> Unit): Unit {
    let t = DeviceTestRun()
    t.suite(label, body)
    @Expect(t.failed, 0)
    @Expect(t.errored, 0)
}

@Test
class MigratedIosParityTests {
    @TestCase
    func startup(): Unit { expectClean("startup", runStartupTests) }

    @TestCase
    func featureCommon(): Unit { expectClean("featureCommon", runFeatureCommonTests) }

    @TestCase
    func featureIssuance(): Unit { expectClean("featureIssuance", runFeatureIssuanceTests) }

    @TestCase
    func featureDashboard(): Unit { expectClean("featureDashboard", runFeatureDashboardTests) }

    @TestCase
    func featurePresentation(): Unit { expectClean("featurePresentation", runFeaturePresentationTests) }

    @TestCase
    func featureProximity(): Unit { expectClean("featureProximity", runFeatureProximityTests) }

    @TestCase
    func deepLink(): Unit { expectClean("deepLink", runDeepLinkTests) }

    @TestCase
    func errorIssuerTrust(): Unit { expectClean("errorIssuerTrust", runErrorIssuerTrustTests) }
}
