// Assertion helper for the migrated iOS-parity suites (package eudi_unit_tests).
//
// ohosTest HAP compiles this package as a cjpm dependency of
// libeudi_unit_tests.so (see entry/src/ohosTest/cangjie). The app HAP does
// not depend on it. suites_test.cj is ignored by cjpm build / assembleHap and
// is only for `cjpm test --no-run`.
package eudi_unit_tests

import std.collection.ArrayList

class DeviceTestRun {
    var passed = 0
    var failed = 0
    var errored = 0
    let failures = ArrayList<String>()
    let errors = ArrayList<String>()

    func check(cond: Bool, name: String): Unit {
        if (cond) { this.passed++ } else { this.failed++; this.failures.add(name) }
    }
    func eqInt(actual: Int64, expected: Int64, name: String): Unit {
        this.check(actual == expected, "${name} (got ${actual}, want ${expected})")
    }
    func eqStr(actual: String, expected: String, name: String): Unit {
        this.check(actual == expected, "${name} (got '${actual}', want '${expected}')")
    }

    // Runs one suite with its throws contained. Without this, a suite that raises
    // instead of returning a false assertion takes the whole process down: every
    // later suite is skipped and no summary reaches the bridge, so the run reads
    // as "no failures" rather than as a failure. Containing the throw here turns
    // it into a counted `error` and lets the remaining suites still report.
    //
    // Deliberately catches `Exception` only. Cangjie's other throwable hierarchy,
    // `Error` (OutOfMemoryError / StackOverflowError), is raised by the runtime for
    // internal or resource-exhaustion faults; the language guidance is to terminate
    // safely rather than recover, and an OOM stack does not identify the culprit
    // anyway. Those runs die without printing a summary, which run_device_tests.sh
    // reports as INCONCLUSIVE (exit 1) — so the gap is covered at the script layer,
    // not by widening this catch.
    func suite(name: String, body: (DeviceTestRun) -> Unit): Unit {
        try {
            body(this)
        } catch (e: Exception) {
            this.errored++
            this.errors.add("${name} threw ${e}")
        }
    }
}

public func runAllUnitSuites(): String {
    let t = DeviceTestRun()
    // feature-startup (iOS TestStartupInteractor → Cangjie StartupInteractorImpl)
    t.suite("startup", runStartupTests)
    // logic-authentication XCTest (PIN + keychain + biometry) runs on host:
    //   ./run_tests.sh eudi_logic_authentication
    // feature-common ViewModel (with full fake DI — headless-safe)
    t.suite("featureCommon", runFeatureCommonTests)
    // feature-issuance interactors (AddDocument + DocumentOffer)
    t.suite("featureIssuance", runFeatureIssuanceTests)
    // feature-dashboard interactors (DocumentTab/Details/TransactionTab/Settings/Home/TxDetails)
    t.suite("featureDashboard", runFeatureDashboardTests)
    // feature-presentation interactor + ViewModel (online presentation)
    t.suite("featurePresentation", runFeaturePresentationTests)
    // feature-proximity interactor (BLE proximity presentation; platform-limited)
    t.suite("featureProximity", runFeatureProximityTests)
    // logic-ui DeepLinkController (iOS TestDeepLinkController → Cangjie port, 21)
    t.suite("deepLink", runDeepLinkTests)
    // logic-core issuer-trust classifier (iOS TestErrorIssuerTrust, 10)
    t.suite("errorIssuerTrust", runErrorIssuerTrustTests)
    // registration-certificate (WRPRC) trust layer (iOS TestRelyingPartyRegistrationUiModel 17
    // + TestPresentationPolicyViolationOverasking 10 + TestPolicyPurposeLocalized 4
    // + TestRequestDataUiModelSelection 3)
    t.suite("registrationTrust", runRegistrationTrustTests)

    var detail = ""
    for (f in t.failures) { detail += " | ${f}" }
    for (e in t.errors) { detail += " | ERROR ${e}" }
    return "passed=${t.passed} failed=${t.failed} error=${t.errored}${detail}"
}
