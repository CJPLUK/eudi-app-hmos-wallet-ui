/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Extension/String+Extensions.swift, Int+Extensions.swift) to Cangjie.
 *
 * Swift `String` extensions become `StringUtil` static functions because Cangjie
 * extensions cannot be re-exported across package boundaries the way the iOS
 * module exposes them. Bundle-dependent members (`loadFileFromBundle`,
 * `valueFromBundle`, `optionalValueFromBundle`, `toJSON`) have no HarmonyOS
 * bundle counterpart in a logic HAR and are intentionally not migrated; their
 * config duties live in ConfigLogic instead.
 */
package eudi_logic_business

import std.convert.*
import std.math.*
import std.regex.*
import std.collection.ArrayList

/** String helper set mirroring the cross-module consumed iOS String extensions. */
public class StringUtil {

    /** Mirrors `capitalizedFirst()`: first rune uppercased, remainder lowercased (ASCII). */
    public static func capitalizedFirst(value: String): String {
        if (value.isEmpty()) {
            return ""
        }
        let runes = value.toRuneArray()
        var head = String(runes[0]).toAsciiUpper()
        let sb = StringBuilder()
        sb.append(head)
        var index = 1
        while (index < runes.size) {
            sb.append(String(runes[index]).toAsciiLower())
            index++
        }
        return sb.toString()
    }

    /**
     * Mirrors Swift `Int(self)` / `toInteger()`: optional leading `-` then one
     * or more decimal digits. `Int64.tryParse` also accepts `0x`/`0b`/`0o` and
     * a leading `+`; those must be `None` to match iOS.
     */
    public static func toInteger(value: String): ?Int64 {
        if (!isSwiftDecimalIntText(value)) {
            return None
        }
        return Int64.tryParse(value)
    }

    private static func isSwiftDecimalIntText(value: String): Bool {
        if (value.isEmpty()) {
            return false
        }
        let runes = value.toRuneArray()
        var i: Int64 = 0
        if (runes[0] == r'-') {
            if (runes.size == 1) {
                return false
            }
            i = 1
        }
        while (i < runes.size) {
            let r = runes[i]
            if (r < r'0' || r > r'9') {
                return false
            }
            i++
        }
        return true
    }

    /** Mirrors `Int.string`. */
    public static func intToString(value: Int64): String {
        return "${value}"
    }

    /** Mirrors `toNumeric()`: value when already an integer, else all non-digit runes stripped. */
    public static func toNumeric(value: String): String {
        if (toInteger(value).isSome()) {
            return value
        }
        let sb = StringBuilder()
        for (r in value.runes()) {
            if (r >= r'0' && r <= r'9') {
                sb.append(r)
            }
        }
        return sb.toString()
    }

    /**
     * Mirrors `toAmount()`: decimal formatting with 1..2 fraction digits,
     * '.' separator, floor rounding, no grouping. Returns None when the
     * input is not parseable as a decimal number.
     */
    public static func toAmount(value: String): ?String {
        let parsed = Float64.tryParse(value.trimAscii())
        let number: Float64
        match (parsed) {
            case Some(v) => number = v
            case None => return None
        }
        // floor rounding at 2 fraction digits (rounds toward negative infinity, like NumberFormatter .floor)
        let scaled = floor(number * 100.0)
        var cents: Int64
        try {
            cents = Int64(scaled)
        } catch (_: OverflowException) {
            return None
        } catch (_: Exception) {
            return None
        }
        let negative = cents < 0
        if (negative) {
            cents = -cents
        }
        let intPart = cents / 100
        let fracPart = cents % 100
        let sign = if (negative) { "-" } else { "" }
        if (fracPart % 10 == 0) {
            // minimumFractionDigits = 1
            return "${sign}${intPart}.${fracPart / 10}"
        }
        let fracText = "${fracPart}".padStart(2, padding: "0")
        return "${sign}${intPart}.${fracText}"
    }

    /** Mirrors `countInstances(of:)`: non-overlapping occurrence count. */
    public static func countInstances(value: String, stringToFind: String): Int64 {
        if (stringToFind.isEmpty()) {
            return 0
        }
        return value.count(stringToFind)
    }

    /** Mirrors `equals(_:ignoreCase:)`. */
    public static func equalsString(value: String, valueToMatch: String, ignoreCase!: Bool = false): Bool {
        if (ignoreCase) {
            return value.equalsIgnoreAsciiCase(valueToMatch)
        }
        return value == valueToMatch
    }

    /** Mirrors `match(_:)` count usage: number of regex matches found anywhere in the value. */
    public static func regexMatchCount(value: String, pattern: String): Int64 {
        try {
            let regex = Regex(pattern)
            let found = regex.findAll(value)
            return Int64(found.size)
        } catch (_: Exception) {
            return 0
        }
    }

    /**
     * True when the pattern matches the entire value (NSPredicate MATCHES
     * semantics). Regex.matches() performs a substring search despite its doc
     * comment (verified at runtime), so the match has to be anchored.
     *
     * The anchors are written into the pattern rather than relying on
     * Matcher.fullMatch(): that only reports whether the engine's match happened
     * to span the whole input, and the engine stops at the leftmost alternative
     * that matches. So `(?:6|8\d\d)\d{7}|[1-9]\d{6}(?:\d{2})?` against
     * "641234567" settled on branch 1 (8 of 9 characters) and reported no full
     * match, never backtracking into branch 2, which does match all 9. Wrapping
     * as `^(?:...)$` makes the engine itself responsible for reaching the end,
     * so it backtracks across alternatives. Wrapping is safe for patterns that
     * already carry their own anchors, since anchors are zero-width.
     */
    public static func fullMatches(value: String, pattern: String): Bool {
        try {
            let regex = Regex("^(?:${pattern})$")
            return regex.matcher(value).fullMatch().isSome()
        } catch (_: Exception) {
            return false
        }
    }

    /** Mirrors `String?.orEmpty`. */
    public static func orEmpty(value: ?String): String {
        return value ?? ""
    }

    /** Mirrors `String?.ifNil(_:)`. */
    public static func ifNil(value: ?String, fallback: () -> String): String {
        match (value) {
            case Some(v) => return v
            case None =>
                try {
                    return fallback()
                } catch (_: Exception) {
                    return ""
                }
        }
    }

    /** Mirrors `String?.ifNilOrEmpty(_:)`. */
    public static func ifNilOrEmpty(value: ?String, fallback: () -> String): String {
        match (value) {
            case Some(v) => if (v.isEmpty()) { return fallback() } else { return v }
            case None => return fallback()
        }
    }

    /** Mirrors `String?.isNilOrEmpty()`. */
    public static func isNilOrEmpty(value: ?String): Bool {
        match (value) {
            case Some(v) => return v.isEmpty()
            case None => return true
        }
    }

    /** Mirrors `padded(toWidth:withPad:)`: left-pads up to `width` runes. */
    public static func paddedToWidth(value: String, width: Int64, pad!: String = " "): String {
        let length = Int64(value.toRuneArray().size)
        let padLength = width - length
        if (padLength <= 0) {
            return value
        }
        return repeatString(pad, padLength) + value
    }

    /** Mirrors `padded(withPad:padLength:)`: appends `padLength` copies of `pad`. */
    public static func paddedBy(value: String, padLength: Int64, pad!: String = " "): String {
        if (padLength <= 0) {
            return value
        }
        return value + repeatString(pad, padLength)
    }

    private static func repeatString(pad: String, count: Int64): String {
        let sb = StringBuilder()
        var i: Int64 = 0
        while (i < count) {
            sb.append(pad)
            i++
        }
        return sb.toString()
    }

    /** Mirrors `urlEncode()`: percent-encodes every byte outside the URL-query-allowed set. */
    public static func urlEncode(value: String): String {
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$&'()*+,-./:;=?@_~"
        let allowedBytes = allowed.toArray()
        let sb = StringBuilder()
        for (b in value.toArray()) {
            var isAllowed = false
            for (a in allowedBytes) {
                if (a == b) {
                    isAllowed = true
                    break
                }
            }
            if (isAllowed) {
                sb.append(Rune(UInt32(b)))
            } else {
                sb.append("%")
                sb.append(byteToHex(b))
            }
        }
        return sb.toString()
    }

    /** Decodes %XX percent escapes; returns None on malformed escapes or invalid UTF-8. */
    public static func removingPercentEncoding(value: String): ?String {
        let bytes = value.toArray()
        let out = ArrayList<UInt8>()
        var i: Int64 = 0
        while (i < bytes.size) {
            let b = bytes[i]
            if (b == UInt8(37)) { // '%'
                if (i + 2 >= bytes.size) {
                    return None
                }
                let hi = hexValue(bytes[i + 1])
                let lo = hexValue(bytes[i + 2])
                match ((hi, lo)) {
                    case (Some(h), Some(l)) =>
                        out.add(UInt8(h * 16 + l))
                        i += 3
                    case _ => return None
                }
            } else {
                out.add(b)
                i++
            }
        }
        try {
            return String.fromUtf8(out.toArray())
        } catch (_: Exception) {
            return None
        }
    }

    private static func hexValue(b: UInt8): ?Int64 {
        let c = Int64(b)
        if (c >= 48 && c <= 57) { // 0-9
            return c - 48
        }
        if (c >= 65 && c <= 70) { // A-F
            return c - 55
        }
        if (c >= 97 && c <= 102) { // a-f
            return c - 87
        }
        return None
    }

    private static func byteToHex(b: UInt8): String {
        let digits = "0123456789ABCDEF"
        let chars = digits.toRuneArray()
        let hi = Int64(b) / 16
        let lo = Int64(b) % 16
        return String(chars[hi]) + String(chars[lo])
    }

    private static let BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    /** Mirrors `toBase64`: standard base64 of the UTF-8 bytes. */
    public static func toBase64(value: String): String {
        let alphabet = BASE64_ALPHABET.toRuneArray()
        let data = value.toArray()
        let sb = StringBuilder()
        var i: Int64 = 0
        while (i + 2 < data.size) {
            let n = (Int64(data[i]) << 16) | (Int64(data[i + 1]) << 8) | Int64(data[i + 2])
            sb.append(alphabet[(n >> 18) & 63])
            sb.append(alphabet[(n >> 12) & 63])
            sb.append(alphabet[(n >> 6) & 63])
            sb.append(alphabet[n & 63])
            i += 3
        }
        let remaining = data.size - i
        if (remaining == 1) {
            let n = Int64(data[i]) << 16
            sb.append(alphabet[(n >> 18) & 63])
            sb.append(alphabet[(n >> 12) & 63])
            sb.append("==")
        } else if (remaining == 2) {
            let n = (Int64(data[i]) << 16) | (Int64(data[i + 1]) << 8)
            sb.append(alphabet[(n >> 18) & 63])
            sb.append(alphabet[(n >> 12) & 63])
            sb.append(alphabet[(n >> 6) & 63])
            sb.append("=")
        }
        return sb.toString()
    }

    /** Mirrors `decodeBase64`: returns None on invalid alphabet/padding or non-UTF-8 payload. */
    public static func decodeBase64(value: String): ?String {
        if (value.isEmpty() || value.size % 4 != 0) {
            return None
        }
        let out = ArrayList<UInt8>()
        var buffer: Int64 = 0
        var bits: Int64 = 0
        var padding: Int64 = 0
        for (b in value.toArray()) {
            if (b == UInt8(61)) { // '='
                padding++
                continue
            }
            if (padding > 0) {
                return None // data after padding
            }
            let v = base64Value(b)
            match (v) {
                case Some(idx) =>
                    buffer = (buffer << 6) | idx
                    bits += 6
                    if (bits >= 8) {
                        bits -= 8
                        out.add(UInt8((buffer >> bits) & 255))
                    }
                case None => return None
            }
        }
        if (padding > 2) {
            return None
        }
        try {
            return String.fromUtf8(out.toArray())
        } catch (_: Exception) {
            return None
        }
    }

    private static func base64Value(b: UInt8): ?Int64 {
        let c = Int64(b)
        if (c >= 65 && c <= 90) { // A-Z
            return c - 65
        }
        if (c >= 97 && c <= 122) { // a-z
            return c - 71
        }
        if (c >= 48 && c <= 57) { // 0-9
            return c + 4
        }
        if (c == 43) { // '+'
            return 62
        }
        if (c == 47) { // '/'
            return 63
        }
        return None
    }
}
