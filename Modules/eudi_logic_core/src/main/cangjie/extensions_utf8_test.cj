/*
 * Host unit tests for transaction-log JSON and wallet-kit jsonUnescape.
 * Multi-byte UTF-8 (café, Ministère) must round-trip without
 * String.fromUtf8([single-byte]) throwing.
 */
package eudi_logic_core

import std.unittest.*
import std.unittest.testmacro.*

@Test
class Utf8JsonCodecTest {

    @TestCase
    func txnRoundTripAccentedRelyingParty(): Unit {
        let json = encodePresentationTransactionValue(1710000000, "Ministère", "PID")
        match (decodeStoredTransactionLog(json)) {
            case Some(log) =>
                @Expect(log.value, "Ministère")
                @Expect(log.timestamp, 1710000000)
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func txnRoundTripCafe(): Unit {
        let json = encodePresentationTransactionValue(1, "café", "docs")
        match (decodeStoredTransactionLog(json)) {
            case Some(log) => @Expect(log.value, "café")
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func jsonUnescapePlainUtf8Passthrough(): Unit {
        @Expect(jsonUnescape("café"), "café")
    }

    @TestCase
    func jsonUnescapeUnicodeEscape(): Unit {
        let escaped = "caf" + "\\" + "u00e9"
        @Expect(jsonUnescape(escaped), "café")
    }

    @TestCase
    func jsonUnescapeBackslashThenUtf8Char(): Unit {
        let raw = "\\" + "é"
        @Expect(jsonUnescape(raw), "é")
    }

    @TestCase
    func jsonUnescapeAmpersandEscapeWithUtf8(): Unit {
        let raw = "https://x?a=1" + "\\" + "&b=" + "café"
        @Expect(jsonUnescape(raw), "https://x?a=1&b=café")
    }

    @TestCase
    func jsonUnescapeUnpairedSurrogateDoesNotThrow(): Unit {
        let escaped = "\\" + "ud800"
        @Expect(jsonUnescape(escaped), "")
    }

    @TestCase
    func formatClaimValueLeavesNonExactDateUnchanged(): Unit {
        @Expect(formatClaimValue("2023-01-05extra"), "2023-01-05extra")
        @Expect(formatClaimValue("2023-01-05"), "5 Jan 2023")
    }
}
