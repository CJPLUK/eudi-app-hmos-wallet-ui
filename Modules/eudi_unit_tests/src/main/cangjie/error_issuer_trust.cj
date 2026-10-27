// Device unit tests for the issuer-trust error classifier, migrated 1:1 from
//   iOS TestErrorIssuerTrust.swift (10 cases)
//
// Runs via the device bridge (DeviceTestRun in dev_unit_driver.cj) rather than
// host `cjpm test`, because the classifier pattern-matches MsoValidationError
// from the vendored mdoc-security library, which only builds for the device
// target.
//
// iOS ↔ Cangjie signal mapping:
//   WalletError(code: .trustError)  → WalletError.withCode(_, TrustError)
//   MsoValidationError.issuerTrustFailed → MsoValidationErrorKind.IssuerTrustFailed
//   MsoValidationError.multipleErrors    → MsoValidationErrorKind.MultipleErrors
package eudi_unit_tests

import std.collection.ArrayList
import eudi_logic_core.{isTrustBlocked, WalletCoreError}
import ohos_app_cangjie_eudi_cjmdoc_security.security.issuer_auth.{
    MsoValidationError, MsoValidationErrorKind
}
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.{WalletError, WalletErrorCode}

func msoTrustFailed(reason: String): MsoValidationError {
    MsoValidationError(MsoValidationErrorKind.IssuerTrustFailed(reason))
}

func msoSignatureFailed(reason: String): MsoValidationError {
    MsoValidationError(MsoValidationErrorKind.SignatureVerificationFailed(reason))
}

func msoValidityInfo(reason: String): MsoValidationError {
    MsoValidationError(MsoValidationErrorKind.ValidityInfoError(reason))
}

func msoMultiple(errors: Array<MsoValidationError>): MsoValidationError {
    let list = ArrayList<MsoValidationError>()
    for (e in errors) {
        list.add(e)
    }
    return MsoValidationError(MsoValidationErrorKind.MultipleErrors(list))
}

func runErrorIssuerTrustTests(t: DeviceTestRun): Unit {
    // ── WalletError-equivalent signal ────────────────────────────────────────

    // iOS: testIsIssuerNotTrusted_whenWalletErrorTrustError_thenReturnsTrue
    // Same type and code as iOS: WalletError(description: "trust", code: .trustError).
    t.check(isTrustBlocked(WalletError.withCode("trust", WalletErrorCode.TrustError)),
        "issuerTrust.walletErrorTrustError_isTrue")
    // App-level stand-in used by issuance / presentation fakes. Not an iOS branch.
    t.check(isTrustBlocked(WalletCoreError.issuerNotTrusted()),
        "issuerTrust.appErrorIssuerNotTrusted_isTrue")

    // iOS: testIsIssuerNotTrusted_whenWalletErrorOtherCode_thenReturnsFalse
    // Same shape as iOS: the engine's own error type, carrying a code that is not
    // about trust, must not be read as an untrusted issuer. iOS picks
    // .internalError; the vendored WalletErrorCode has a different case list, so
    // this uses one of its non-trust codes.
    t.check(!isTrustBlocked(WalletError.withCode("boom", WalletErrorCode.ClaimNotFound)),
        "issuerTrust.walletErrorOtherCode_isFalse")
    // An engine error with no code at all must not classify as trust either.
    t.check(!isTrustBlocked(WalletError.withDescription("boom")),
        "issuerTrust.walletErrorNoCode_isFalse")
    // The app-level error type behaves the same for its non-trust kinds.
    t.check(!isTrustBlocked(WalletCoreError.unableToIssueAndStore()),
        "issuerTrust.appErrorOtherKind_isFalse")

    // iOS: testIsIssuerNotTrusted_whenWalletErrorNotSecuredRequest_thenReturnsFalse
    // iOS asserts on WalletError(code: .notSecuredRequest) — a refused request, the
    // error sitting closest to trust without being it. The vendored WalletErrorCode
    // has no such code, so this uses the nearest engine code about a request that
    // could not be satisfied, plus the app-level "refused to present" kind. Both
    // must stay off the untrusted-issuer path.
    t.check(!isTrustBlocked(WalletError.withCode("refused", WalletErrorCode.DcqlQueryNotSatisfied)),
        "issuerTrust.walletErrorNotSecuredRequest_isFalse")
    t.check(!isTrustBlocked(WalletCoreError.unableToPresentAndShare()),
        "issuerTrust.appErrorUnableToPresent_isFalse")

    // ── MsoValidationError ───────────────────────────────────────────────────

    // iOS: testIsIssuerNotTrusted_whenMsoIssuerTrustFailed_thenReturnsTrue
    t.check(isTrustBlocked(msoTrustFailed("untrusted issuer")),
        "issuerTrust.msoIssuerTrustFailed_isTrue")

    // iOS: testIsIssuerNotTrusted_whenMsoOtherCase_thenReturnsFalse
    t.check(!isTrustBlocked(msoSignatureFailed("bad signature")),
        "issuerTrust.msoOtherCase_isFalse")

    // iOS: testIsIssuerNotTrusted_whenMsoMultipleErrorsContainsTrustFailure_thenReturnsTrue
    t.check(
        isTrustBlocked(
            msoMultiple([msoSignatureFailed("bad signature"), msoTrustFailed("untrusted issuer")])
        ),
        "issuerTrust.msoMultipleErrorsContainsTrustFailure_isTrue"
    )

    // iOS: testIsIssuerNotTrusted_whenMsoMultipleErrorsNoTrustFailure_thenReturnsFalse
    t.check(
        !isTrustBlocked(
            msoMultiple([msoSignatureFailed("bad signature"), msoValidityInfo("expired")])
        ),
        "issuerTrust.msoMultipleErrorsNoTrustFailure_isFalse"
    )

    // iOS: testIsIssuerNotTrusted_whenMsoMultipleErrorsEmpty_thenReturnsFalse
    t.check(!isTrustBlocked(msoMultiple(Array<MsoValidationError>())),
        "issuerTrust.msoMultipleErrorsEmpty_isFalse")

    // iOS: testIsIssuerNotTrusted_whenMsoNestedMultipleErrorsContainsTrustFailure_thenReturnsTrue
    // Exercises the recursive walk: the trust failure sits two levels down.
    t.check(
        isTrustBlocked(
            msoMultiple([
                msoMultiple([msoValidityInfo("expired"), msoTrustFailed("untrusted issuer")])
            ])
        ),
        "issuerTrust.msoNestedMultipleErrorsContainsTrustFailure_isTrue"
    )

    // ── Unrelated errors ─────────────────────────────────────────────────────

    // iOS: testIsIssuerNotTrusted_whenGenericError_thenReturnsFalse
    t.check(!isTrustBlocked(Exception("com.eudi.test")),
        "issuerTrust.genericError_isFalse")
}
