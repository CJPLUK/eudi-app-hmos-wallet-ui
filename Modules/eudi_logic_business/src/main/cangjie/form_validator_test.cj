/*
 * form_validator_test.cj — Cangjie unit tests for FormValidator, migrated
 * from the iOS logic-business test suite (Tests/Validator/TestFormValidator.swift).
 *
 * iOS source: 20 test functions in TestFormValidator.swift.
 * All 20 semantics are represented below.
 *
 * Cangjie port notes:
 * - iOS uses XCTest + Cuckoo; Cangjie uses std.unittest with hand-written helpers.
 * - FormValidator methods are synchronous in Cangjie (iOS is async actor); no
 *   await / listener plumbing required.
 * - ValidatePhoneNumber is region-aware on both sides: iOS parses via
 *   PhoneNumberKit, Cangjie ports the same libphonenumber algorithm and table
 *   (see phone_number_validator.cj). Test 3 asserts iOS's original expectations
 *   verbatim; tests 3b/3c add region-awareness and a sweep over every
 *   libphonenumber example number.
 * - ValidatableForm in Cangjie: Array<FormInput>; each FormInput = (Array<Rule>, String).
 *   The iOS [[Rule]: String] dict is reproduced as a single-element FormInput array.
 * - Rule enum in Cangjie uses positional payloads (no labels):
 *     ValidateUrl(errorMessage, host, schema, query, path)
 *     iOS defaults: host=true, schema=true, query=true, path=true.
 *
 * Layout: co-located with production source (*_test.cj), same package
 * eudi_logic_business. cjpm test discovers this file; cjpm build ignores it.
 * Run on macOS host: ./run_tests.sh eudi_logic_business
 */
package eudi_logic_business

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// ── Helpers ─────────────────────────────────────────────────────────────────

let PLAIN_ERROR = "generic_error_description"

func makeFormValidator(): FormValidatorImpl {
    return FormValidatorImpl()
}

// Construct a single-input ValidatableForm (one rule list + one value string).
func form1(rules: Array<Rule>, value: String): ValidatableForm {
    return ValidatableForm([FormInput(rules, value)])
}

// Check one validateForm call: assert isValid and message match expected.
func assertForm(
    v: FormValidatorImpl,
    rules: Array<Rule>,
    value: String,
    expectValid: Bool,
    expectMsg: String
): Unit {
    let result = v.validateForm(form1(rules, value))
    @Expect(result.isValid, expectValid)
    if (!expectValid) {
        @Expect(result.message, expectMsg)
    }
}

// ════════════════════════════════════════════════════════════════════════════
@Test
class FormValidatorTest {

    // ── Test 1 (iOS: testValidateNotEmptyRule) ───────────────────────────
    // Empty string fails; non-empty passes.
    @TestCase
    func testValidateNotEmptyRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateNotEmpty(PLAIN_ERROR)]
        assertForm(v, rules, "", false, PLAIN_ERROR)
        assertForm(v, rules, "test", true, "")
    }

    // ── Test 2 (iOS: testValidateEmailRule) ──────────────────────────────
    // Valid email passes; incomplete address fails.
    @TestCase
    func testValidateEmailRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateEmail(PLAIN_ERROR)]
        assertForm(v, rules, "test@test.com", true, "")
        assertForm(v, rules, "test@", false, PLAIN_ERROR)
    }

    // ── Test 3 (iOS: testValidatePhoneNumberRule) ─────────────────────────
    // Same five expectations as iOS, which validates through PhoneNumberKit.
    // The region actually matters: "6941111111" is a valid Greek mobile but not
    // a valid US number (694 is not an assigned NANP area code), so a port that
    // ignored countryCode could not tell these two apart.
    @TestCase
    func testValidatePhoneNumberRule(): Unit {
        let v = makeFormValidator()
        let grRule = [Rule.ValidatePhoneNumber("GR", PLAIN_ERROR)]
        let usRule = [Rule.ValidatePhoneNumber("US", PLAIN_ERROR)]
        assertForm(v, grRule, "1111111111", false, PLAIN_ERROR)   // not a GR prefix
        assertForm(v, grRule, "15223433333", false, PLAIN_ERROR)  // 11 digits, no GR match
        assertForm(v, grRule, "6941111111", true, "")             // GR mobile 69x
        assertForm(v, usRule, "6941111111", false, PLAIN_ERROR)   // 694 unassigned in NANP
        assertForm(v, usRule, "6102458772", true, "")             // US area code 610
    }

    // ── Test 3b (Cangjie-only) region awareness + fallback ────────────────
    // Guards the two properties most likely to regress if someone "simplifies"
    // the validator back into a digit-count check.
    @TestCase
    func testValidatePhoneNumberRegionAwareness(): Unit {
        let v = makeFormValidator()
        // Same digits, opposite verdicts depending on the region.
        assertForm(v, [Rule.ValidatePhoneNumber("GR", PLAIN_ERROR)], "2101234567", true, "")
        assertForm(v, [Rule.ValidatePhoneNumber("US", PLAIN_ERROR)], "2101234567", false, PLAIN_ERROR)
        // International form is accepted when the calling code matches the region.
        assertForm(v, [Rule.ValidatePhoneNumber("GR", PLAIN_ERROR)], "+306941111111", true, "")
        // ...and rejected when it does not (US calling code against GR).
        assertForm(v, [Rule.ValidatePhoneNumber("GR", PLAIN_ERROR)], "+16102458772", false, PLAIN_ERROR)
        // Separators are tolerated, letters are not.
        assertForm(v, [Rule.ValidatePhoneNumber("US", PLAIN_ERROR)], "(610) 245-8772", true, "")
        assertForm(v, [Rule.ValidatePhoneNumber("US", PLAIN_ERROR)], "610245877X", false, PLAIN_ERROR)
        // Unknown region falls back to an E.164 shape check rather than rejecting all.
        assertForm(v, [Rule.ValidatePhoneNumber("ZZ", PLAIN_ERROR)], "6102458772", true, "")
        assertForm(v, [Rule.ValidatePhoneNumber("ZZ", PLAIN_ERROR)], "12", false, PLAIN_ERROR)
    }

    // ── Test 3c (Cangjie-only) sweep every libphonenumber example number ──
    // libphonenumber ships a canonical example per region and number type; by
    // definition each must validate for its own region. Running all of them
    // exercises the whole metadata table and the national-prefix stripping,
    // rather than only the handful of regions the iOS test happens to cover.
    @TestCase
    func testValidatePhoneNumberExampleNumbers(): Unit {
        var checked = 0
        let failures = ArrayList<String>()
        for (record in PHONE_EXAMPLE_NUMBERS) {
            let parts = record.split("\t", removeEmpty: false)
            if (parts.size != 2) {
                continue
            }
            let region = parts[0]
            let number = parts[1]
            // "001" is libphonenumber's non-geographic bucket (satellite, shared
            // cost, ...) and is not a region a caller can pass; skip it.
            if (region == "001") {
                continue
            }
            checked += 1
            if (!PhoneNumberValidator.isValid(number, region)) {
                failures.add("${region}:${number}")
            }
        }
        @Expect(checked > 1000, true)
        if (!failures.isEmpty()) {
            println("example-number failures (${failures.size}): ${failures}")
        }
        @Expect(failures.size, 0)
    }

    // ── Test 3d (Cangjie-only) anchored full match across alternatives ────
    // Regression guard for StringUtil.fullMatches: an earlier alternative that
    // matches only a prefix used to make the whole pattern report "no match",
    // because the engine stopped there instead of backtracking into a branch
    // that reaches the end. Here branch 1 consumes 8 of the 9 digits.
    @TestCase
    func testValidateRegexRuleBacktracksAcrossAlternatives(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateRegex("(?:6|8\\d\\d)\\d{7}|[1-9]\\d{6}(?:\\d{2})?", PLAIN_ERROR)]
        assertForm(v, rules, "641234567", true, "")   // only branch 2 spans all 9
        assertForm(v, rules, "61234567", true, "")    // branch 1 spans all 8
        assertForm(v, rules, "6412345678", false, PLAIN_ERROR) // 10 digits: neither
    }

    // ── Test 4 (iOS: testValidateStringMaxLengthRule) ────────────────────
    // Strings beyond the max length fail; within pass.
    @TestCase
    func testValidateStringMaxLengthRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateStringMaxLength(10, PLAIN_ERROR)]
        assertForm(v, rules, "aaaaaaaaaaa", false, PLAIN_ERROR)   // 11 chars
        assertForm(v, rules, "aaaaaaaaaaaaaaa", false, PLAIN_ERROR) // 15 chars
        assertForm(v, rules, "aaaaaaaaa", true, "")                // 9 chars
    }

    // ── Test 5 (iOS: testValidateStringMinLengthRule) ────────────────────
    // Strings shorter than min length fail; at or above pass.
    @TestCase
    func testValidateStringMinLengthRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateStringMinLength(5, PLAIN_ERROR)]
        assertForm(v, rules, "aaaa", false, PLAIN_ERROR)  // 4 chars
        assertForm(v, rules, "a", false, PLAIN_ERROR)     // 1 char
        assertForm(v, rules, "aaaaa", true, "")           // 5 chars
    }

    // ── Test 6 (iOS: testValidateRegexRule) ──────────────────────────────
    // Various regex patterns: capital letter, digit, special char, IBAN-like.
    @TestCase
    func testValidateRegexRule(): Unit {
        let v = makeFormValidator()
        let capitalRule = [Rule.ValidateRegex(".*[A-Z].*", PLAIN_ERROR)]
        let digitRule   = [Rule.ValidateRegex(".*(\\d).*", PLAIN_ERROR)]
        let specialRule = [Rule.ValidateRegex(".*[^a-zA-Z0-9].*", PLAIN_ERROR)]
        let ibanRule    = [Rule.ValidateRegex("^[a-zA-Z0-9-\\s]+$", PLAIN_ERROR)]

        // At least one capital letter
        assertForm(v, capitalRule, "test", false, PLAIN_ERROR)
        assertForm(v, capitalRule, "Test", true, "")

        // At least one digit
        assertForm(v, digitRule, "test", false, PLAIN_ERROR)
        assertForm(v, digitRule, "test1", true, "")

        // At least one special char
        assertForm(v, specialRule, "test", false, PLAIN_ERROR)
        assertForm(v, specialRule, "test1@", true, "")

        // IBAN-like: letters, digits, space, dash only
        assertForm(v, ibanRule, "NL86INGB7482085033", true, "")
        assertForm(v, ibanRule, "CY82947517727631922532755722", true, "")
        assertForm(v, ibanRule, "GB57BARC20040114216837", true, "")
        assertForm(v, ibanRule, "123456789", true, "")
        assertForm(v, ibanRule, "327821737812367126712", true, "")
        assertForm(v, ibanRule, "3278 2173781 23671 26712", true, "")
        assertForm(v, ibanRule, "3278-2173781-23671-26712", true, "")
        assertForm(v, ibanRule, "3278-2173781 23671-26712", true, "")
        assertForm(v, ibanRule, "3278-2173781&23671-26712", false, PLAIN_ERROR)
        assertForm(v, ibanRule, "3278-21\u{a3}73781\u{a3}23671-26712", false, PLAIN_ERROR)
    }

    // ── Test 7 (iOS: testValidateStringRangeRule) ─────────────────────────
    // Strings outside [minLength, maxLength] fail; within pass (empty OK).
    @TestCase
    func testValidateStringRangeRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateStringRange(0, 10, PLAIN_ERROR)]
        assertForm(v, rules, "aaaaaaaaaaa", false, PLAIN_ERROR)  // 11 chars
        assertForm(v, rules, "aaaaaaaaaa", true, "")             // 10 chars
        assertForm(v, rules, "", true, "")                       // 0 chars
    }

    // ── Test 8 (iOS: testValidateStringMatchRule) ─────────────────────────
    // Case-insensitive: matches regardless of case; case-sensitive: exact only.
    @TestCase
    func testValidateStringMatchRule(): Unit {
        let v = makeFormValidator()
        let ciRule = [Rule.ValidateStringMatch("test", PLAIN_ERROR, false)]
        let csRule = [Rule.ValidateStringMatch("test", PLAIN_ERROR, true)]

        // Case-insensitive failures
        assertForm(v, ciRule, "testt", false, PLAIN_ERROR)
        assertForm(v, ciRule, "t!@#$", false, PLAIN_ERROR)
        assertForm(v, ciRule, "", false, PLAIN_ERROR)
        // Case-insensitive pass (uppercase equivalent)
        assertForm(v, ciRule, "TEST", true, "")
        // Case-sensitive: "TEST" ≠ "test"
        assertForm(v, csRule, "TEST", false, PLAIN_ERROR)
        assertForm(v, csRule, "", false, PLAIN_ERROR)
        // Case-sensitive pass (exact match)
        assertForm(v, csRule, "test", true, "")
    }

    // ── Test 9 (iOS: testValidateStringNotMatchRule) ──────────────────────
    // Case-insensitive: "test"/"TEST" fail; non-match passes.
    // Case-sensitive: "test" fails; "TEST"/"Testss" pass.
    @TestCase
    func testValidateStringNotMatchRule(): Unit {
        let v = makeFormValidator()
        let ciRule = [Rule.ValidateStringNotMatch("test", PLAIN_ERROR, false)]
        let csRule = [Rule.ValidateStringNotMatch("test", PLAIN_ERROR, true)]

        // Case-insensitive: same string (any case) fails
        assertForm(v, ciRule, "test", false, PLAIN_ERROR)
        assertForm(v, ciRule, "TEST", false, PLAIN_ERROR)
        // Case-insensitive passes
        assertForm(v, ciRule, "", true, "")
        assertForm(v, ciRule, "testt", true, "")
        // Case-sensitive: exact "test" fails; different case passes
        assertForm(v, csRule, "test", false, PLAIN_ERROR)
        assertForm(v, csRule, "Testss", true, "")
        assertForm(v, csRule, "TEST", true, "")
        assertForm(v, csRule, "", true, "")
    }

    // ── Test 10 (iOS: testValidateDuplicateCharacterNotInConsecutiveOrderRule)
    // Runs of identical word chars < maxTimes pass; ≥ maxTimes fail.
    @TestCase
    func testValidateDuplicateCharacterNotInConsecutiveOrderRule(): Unit {
        let v = makeFormValidator()
        let max2 = [Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(2, PLAIN_ERROR)]
        let max4 = [Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(4, PLAIN_ERROR)]

        // max=2: no run of 2+ identical word chars
        assertForm(v, max2, "1313", true, "")
        assertForm(v, max2, "4356754", true, "")
        assertForm(v, max2, "0191", true, "")
        // max=2: fails (has "22" or "11" run)
        assertForm(v, max2, "1225", false, PLAIN_ERROR)
        assertForm(v, max2, "2332", false, PLAIN_ERROR)
        assertForm(v, max2, "454545454545454555444455455", false, PLAIN_ERROR)
        assertForm(v, max2, "0024", false, PLAIN_ERROR)
        // max=4: "0024" has run of 2 zeros < 4 → passes
        assertForm(v, max4, "0024", true, "")
        // max=4: "0004" has run of 3 zeros < 4 → passes
        assertForm(v, max4, "0004", true, "")
        // max=4: "0000" has run of 4 zeros = 4 → fails
        assertForm(v, max4, "0000", false, PLAIN_ERROR)
        // max=4: "35523456337777" has "7777" (4) → fails
        assertForm(v, max4, "35523456337777", false, PLAIN_ERROR)
    }

    // ── Test 11 (iOS: testValidateNumericNotInConsecutiveSequenceOrderRule)
    // Ascending/descending digit sequences of the given length fail; others pass.
    @TestCase
    func testValidateNumericNotInConsecutiveSequenceOrderRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateNumericNotInConsecutiveSequenceOrder(4, PLAIN_ERROR)]

        // Known consecutive sequences — all fail
        assertForm(v, rules, "1234", false, PLAIN_ERROR)
        assertForm(v, rules, "4321", false, PLAIN_ERROR)
        assertForm(v, rules, "9876", false, PLAIN_ERROR)
        assertForm(v, rules, "3210", false, PLAIN_ERROR)
        assertForm(v, rules, "0123", false, PLAIN_ERROR)
        // Non-consecutive — all pass
        assertForm(v, rules, "1235", true, "")
        assertForm(v, rules, "9875", true, "")
        assertForm(v, rules, "0124", true, "")
        assertForm(v, rules, "0923", true, "")
        // Non-numeric or wrong length → short-circuit to pass
        assertForm(v, rules, "8834834835939534", true, "")
        assertForm(v, rules, "TEST", true, "")
        assertForm(v, rules, "", true, "")
    }

    // ── Test 12 (iOS: testValidateMultipleForms) ──────────────────────────
    // Three forms each with one input (multiple rules); validateForms collects
    // ALL rule failures across all forms and returns them in order.
    //
    // Expected errors (Cangjie, matching iOS for these inputs):
    //   Form 1 "4412": DuplicateChar(2) fails ("44"), Email fails
    //   Form 2 "test@test.gr": PhoneNumber("GR") fails (non-digit chars),
    //                           Regex(".*\d.*") fails (no digit in "test@test.gr")
    //   Form 3 "6991111111": Email fails, StringNotMatch("6991111111") fails,
    //                         DuplicateChar(2) fails ("99"/"1111"), Regex("[^alnum]") fails
    @TestCase
    func testValidateMultipleForms(): Unit {
        let v = makeFormValidator()
        let forms = [
            ValidatableForm([FormInput(
                [
                    Rule.ValidateNumericNotInConsecutiveSequenceOrder(2, "ValidateNumericNotInConsecutiveSequenceOrder"),
                    Rule.ValidateNotEmpty("ValidateNotEmpty"),
                    Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(2, "ValidateDuplicateCharacterNotInConsecutiveOrder"),
                    Rule.ValidateEmail("ValidateEmail"),
                    Rule.ValidateRegex(".*(\\d).*", "ValidateRegex")
                ],
                "4412"
            )]),
            ValidatableForm([FormInput(
                [
                    Rule.ValidateEmail("ValidateEmail"),
                    Rule.ValidateNotEmpty("ValidateNotEmpty"),
                    Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(2, "ValidateDuplicateCharacterNotInConsecutiveOrder"),
                    Rule.ValidatePhoneNumber("GR", "ValidatePhoneNumber"),
                    Rule.ValidateRegex(".*(\\d).*", "ValidateRegex")
                ],
                "test@test.gr"
            )]),
            ValidatableForm([FormInput(
                [
                    Rule.ValidateEmail("ValidateEmail"),
                    Rule.ValidateStringNotMatch("6991111111", "ValidateStringNotMatch", false),
                    Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(2, "ValidateDuplicateCharacterNotInConsecutiveOrder"),
                    Rule.ValidatePhoneNumber("GR", "ValidatePhoneNumber"),
                    Rule.ValidateRegex(".*[^a-zA-Z0-9].*", "ValidateRegex")
                ],
                "6991111111"
            )])
        ]

        let result = v.validateForms(forms)
        @Expect(result.isValid, false)
        let expected = [
            "ValidateDuplicateCharacterNotInConsecutiveOrder",
            "ValidateEmail",
            "ValidatePhoneNumber",
            "ValidateRegex",
            "ValidateEmail",
            "ValidateStringNotMatch",
            "ValidateDuplicateCharacterNotInConsecutiveOrder",
            "ValidateRegex"
        ]
        @Expect(result.messages.size, expected.size)
        var i = 0
        while (i < expected.size && i < result.messages.size) {
            @Expect(result.messages[i], expected[i])
            i++
        }
    }

    // ── Test 13 (iOS: testValidateMaximumAmountRule) ──────────────────────
    // Values above max fail; at/below pass; non-numeric fails.
    @TestCase
    func testValidateMaximumAmountRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateMaximumAmount(5, PLAIN_ERROR)]
        assertForm(v, rules, "6", false, PLAIN_ERROR)
        assertForm(v, rules, "12", false, PLAIN_ERROR)
        assertForm(v, rules, "malformed", false, PLAIN_ERROR)
        assertForm(v, rules, "5", true, "")
        assertForm(v, rules, "2", true, "")
        assertForm(v, rules, "-100", false, PLAIN_ERROR)
    }

    // ── Test 14 (iOS: testValidateMinimumAmountRule) ──────────────────────
    // Values below min fail; at/above pass; non-numeric fails.
    @TestCase
    func testValidateMinimumAmountRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateMinimumAmount(2, PLAIN_ERROR)]
        assertForm(v, rules, "0", false, PLAIN_ERROR)
        assertForm(v, rules, "1", false, PLAIN_ERROR)
        assertForm(v, rules, "malformed", false, PLAIN_ERROR)
        assertForm(v, rules, "2", true, "")
        assertForm(v, rules, "5", true, "")
        assertForm(v, rules, "-5", true, "")
    }

    // ── Test 15 (iOS: testValidateNoWhiteSpaces) ──────────────────────────
    // Any space (leading/trailing/embedded) fails; non-space strings pass.
    @TestCase
    func testValidateNoWhiteSpaces(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateNoWhiteSpaces(PLAIN_ERROR)]
        assertForm(v, rules, " ", false, PLAIN_ERROR)
        assertForm(v, rules, " test", false, PLAIN_ERROR)
        assertForm(v, rules, "tes t", false, PLAIN_ERROR)
        assertForm(v, rules, "test ", false, PLAIN_ERROR)
        assertForm(v, rules, "test", true, "")
        assertForm(v, rules, "test1!@#$1", true, "")
    }

    // ── Test 16 (iOS: testValidateUrl) ────────────────────────────────────
    // iOS default: shouldValidateHost=true, shouldValidateSchema=true,
    // shouldValidateQuery=true, shouldValidatePath=true.
    // Test uses shouldValidatePath: false → host=true, schema=true, query=true, path=false.
    // URLs without a query string fail; custom-scheme URLs with query pass.
    @TestCase
    func testValidateUrl(): Unit {
        let v = makeFormValidator()
        // host=true, schema=true, query=true, path=false (iOS: shouldValidatePath: false)
        let rules = [Rule.ValidateUrl(PLAIN_ERROR, true, true, true, false)]

        // No scheme / unparseable
        assertForm(v, rules, "", false, PLAIN_ERROR)
        assertForm(v, rules, "invalid_url", false, PLAIN_ERROR)
        assertForm(v, rules, "123456789", false, PLAIN_ERROR)

        // Standard http/https — no query string → fails query check
        assertForm(v, rules, "http://example.com", false, PLAIN_ERROR)
        assertForm(v, rules, "https://notarealproject.com/otherpath", false, PLAIN_ERROR)
        // Trailing "?" but empty query → None → fails
        assertForm(v, rules, "https://notarealproject.com/bad_query_param?", false, PLAIN_ERROR)
        assertForm(v, rules, "ftp://projectsite.com", false, PLAIN_ERROR)

        // Custom-scheme URLs with query → pass
        assertForm(v, rules, "mocked-scheme://mocked-host?mocked-query-param=some-value", true, "")
        assertForm(v, rules, "mocked.scheme://mocked.host?mocked.query.param=some.value", true, "")

        // Percent-encoded deep-link URLs (eudi-openid4vp / openid-credential-offer)
        assertForm(
            v, rules,
            "eudi-openid4vp%3A%2F%2Fdev.verifier-backend.eudiw.dev%3Fclient_id%3Ddev.verifier-backend.eudiw.dev%26request_uri%3Dhttps%3A%2F%2Fdev.verifier-backend.eudiw.dev%2Fwallet%2Frequest.jwt%2F1234",
            true, ""
        )
        assertForm(
            v, rules,
            "openid-credential-offer://credential_offer?credential_offer=%7B%22credential_issuer%22:%20%22https://dev.issuer.eudiw.dev%22%2C%20%22credential_configuration_ids%22:%20%5B%22eu.europa.ec.eudi.pid_mdoc%22%5D%2C%20%22grants%22:%20%7B%22urn:ietf:params:oauth:grant-type:pre-authorized_code%22:%20%7B%22pre-authorized_code%22:%20%22some_code%22%2C%20%22tx_code%22:%20%7B%22length%22:%205%2C%20%22input_mode%22:%20%22numeric%22%2C%20%22description%22:%20%22Please%20provide%20the%20one-time%20code.%22%7D%7D%7D%7D",
            true, ""
        )
        assertForm(
            v, rules,
            "eudi-openid4vp://dev.verifier-backend.eudiw.dev?client_id=dev.verifier-backend.eudiw.dev&request_uri=https://dev.verifier-backend.eudiw.dev/wallet/request.jwt/1234",
            true, ""
        )
        assertForm(
            v, rules,
            "openid-credential-offer://credential_offer?credential_offer={\"credential_issuer\": \"https://dev.issuer.eudiw.dev\", \"credential_configuration_ids\": [\"eu.europa.ec.eudi.pid_mdoc\"], \"grants\": {\"urn:ietf:params:oauth:grant-type:pre-authorized_code\": {\"pre-authorized_code\": \"some_code\", \"tx_code\": {\"length\": 5, \"input_mode\": \"numeric\", \"description\": \"Please provide the one-time code.\"}}}}",
            true, ""
        )

        // shouldValidateHost=true → URL with empty host fails
        let hostRequired = [Rule.ValidateUrl(PLAIN_ERROR, true, true, true, false)]
        assertForm(
            v, hostRequired,
            "openid-credential-offer://?credential_offer=%7B%22credential_issuer%22:%20%22https://dev.issuer.eudiw.dev%22%2C%20%22credential_configuration_ids%22:%20%5B%22eu.europa.ec.eudi.pid_mdoc%22%5D%2C%20%22grants%22:%20%7B%22urn:ietf:params:oauth:grant-type:pre-authorized_code%22:%20%7B%22pre-authorized_code%22:%20%22some_code%22%2C%20%22tx_code%22:%20%7B%22length%22:%205%2C%20%22input_mode%22:%20%22numeric%22%2C%20%22description%22:%20%22Please%20provide%20the%20one-time%20code.%22%7D%7D%7D%7D",
            false, PLAIN_ERROR
        )

        // shouldValidatePath=true → URL with path component passes
        let pathRequired = [Rule.ValidateUrl(PLAIN_ERROR, true, true, true, true)]
        assertForm(
            v, pathRequired,
            "openid-credential-offer://credential_offer/path1/path2?credential_offer=%7B%22credential_issuer%22:%20%22https://dev.issuer.eudiw.dev%22%2C%20%22credential_configuration_ids%22:%20%5B%22eu.europa.ec.eudi.pid_mdoc%22%5D%2C%20%22grants%22:%20%7B%22urn:ietf:params:oauth:grant-type:pre-authorized_code%22:%20%7B%22pre-authorized_code%22:%20%22some_code%22%2C%20%22tx_code%22:%20%7B%22length%22:%205%2C%20%22input_mode%22:%20%22numeric%22%2C%20%22description%22:%20%22Please%20provide%20the%20one-time%20code.%22%7D%7D%7D%7D",
            true, ""
        )
    }

    // ── Test 17 (iOS: testValidateStringLengthsRule) ──────────────────────
    // Only lengths in the allowed set (4, 6, 8) pass; all others fail.
    @TestCase
    func testValidateStringLengthsRule(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateStringLengths([4, 6, 8], PLAIN_ERROR)]
        assertForm(v, rules, "ab", false, PLAIN_ERROR)        // 2
        assertForm(v, rules, "abc", false, PLAIN_ERROR)       // 3
        assertForm(v, rules, "abcd", true, "")               // 4
        assertForm(v, rules, "abcde", false, PLAIN_ERROR)     // 5
        assertForm(v, rules, "abcdef", true, "")             // 6
        assertForm(v, rules, "abcdefgh", true, "")           // 8
        assertForm(v, rules, "abcdefghi", false, PLAIN_ERROR) // 9
        assertForm(v, rules, "", false, PLAIN_ERROR)          // 0
    }

    // ── Test 18 (iOS: testValidateNumericNotInConsecutiveSequenceOrder_WhenLengthIsLessThanTwo_ThenAlwaysSuccess)
    // length < 2 short-circuits to true regardless of input.
    @TestCase
    func testValidateNumericNotInConsecutiveSequenceOrder_LengthLessThanTwo(): Unit {
        let v = makeFormValidator()
        let rules = [Rule.ValidateNumericNotInConsecutiveSequenceOrder(1, PLAIN_ERROR)]
        assertForm(v, rules, "1", true, "")
        assertForm(v, rules, "9", true, "")
        assertForm(v, rules, "", true, "")
    }

    // ── Test 19 (iOS: testValidateDuplicateCharacter_WhenMaxConsecutiveOrderIsLessThanTwo_ThenAlwaysSuccess)
    // maxTimesOfConsecutiveOrder < 2 → always returns true (even "1111" or "0000").
    @TestCase
    func testValidateDuplicateCharacter_MaxLessThanTwo(): Unit {
        let v = makeFormValidator()
        let rules1 = [Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(1, PLAIN_ERROR)]
        let rules0 = [Rule.ValidateDuplicateCharacterNotInConsecutiveOrder(0, PLAIN_ERROR)]
        assertForm(v, rules1, "1111", true, "")
        assertForm(v, rules1, "aaaa", true, "")
        assertForm(v, rules0, "0000", true, "")
    }

    // ── Test 20 (iOS: testValidateUrl_WhenPathIsEmptyAndShouldValidatePath_ThenFailsValidation)
    // shouldValidatePath=true + URL with no path → fails.
    @TestCase
    func testValidateUrl_EmptyPathWithShouldValidatePathFails(): Unit {
        let v = makeFormValidator()
        // host=false, schema=false, query=false, path=true
        let rules = [Rule.ValidateUrl(PLAIN_ERROR, false, false, false, true)]
        assertForm(v, rules, "https://example.com", false, PLAIN_ERROR)
    }
}
