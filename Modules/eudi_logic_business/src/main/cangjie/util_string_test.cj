/*
 * Host unit tests for StringUtil.toInteger. Must match Swift Int(self):
 * decimal digits with an optional leading '-', never 0x/0b/0o or '+'.
 */
package eudi_logic_business

import std.unittest.*
import std.unittest.testmacro.*

@Test
class StringUtilToIntegerTest {

    @TestCase
    func decimalLiteralsParse(): Unit {
        match (StringUtil.toInteger("10")) {
            case Some(v) => @Expect(v, 10)
            case None => @Expect(false, true)
        }
        match (StringUtil.toInteger("-10")) {
            case Some(v) => @Expect(v, -10)
            case None => @Expect(false, true)
        }
        match (StringUtil.toInteger("0")) {
            case Some(v) => @Expect(v, 0)
            case None => @Expect(false, true)
        }
        match (StringUtil.toInteger("010")) {
            case Some(v) => @Expect(v, 10)
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func hexAndOtherRadixPrefixesAreNone(): Unit {
        @Expect(StringUtil.toInteger("0x10").isNone(), true)
        @Expect(StringUtil.toInteger("0X10").isNone(), true)
        @Expect(StringUtil.toInteger("0b10").isNone(), true)
        @Expect(StringUtil.toInteger("0o10").isNone(), true)
    }

    @TestCase
    func plusPrefixWhitespaceAndJunkAreNone(): Unit {
        @Expect(StringUtil.toInteger("+5").isNone(), true)
        @Expect(StringUtil.toInteger(" 5").isNone(), true)
        @Expect(StringUtil.toInteger("5 ").isNone(), true)
        @Expect(StringUtil.toInteger("").isNone(), true)
        @Expect(StringUtil.toInteger("-").isNone(), true)
        @Expect(StringUtil.toInteger("5.0").isNone(), true)
    }

    @TestCase
    func toNumericStripsWhenNotASwiftInt(): Unit {
        // iOS: toInteger("0x10") is nil, then non-digits are stripped → "010"
        @Expect(StringUtil.toNumeric("0x10"), "010")
    }

    @TestCase
    func toAmountHugeExponentIsNone(): Unit {
        @Expect(StringUtil.toAmount("1e20").isNone(), true)
    }
}
