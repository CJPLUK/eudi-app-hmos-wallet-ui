/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Controller/PrefsController.swift) to Cangjie.
 *
 * iOS persists through UserDefaults; per the project dev pattern the emulator
 * forbids ohos.data.preferences (SIGSEGV), so this implementation keeps an
 * in-memory map written through to a flat JSON object file via std.fs. Any I/O
 * failure degrades to memory-only mode without crashing, matching the module
 * contract's io_failure fallback. The iOS `Prefs.Key` nested enum becomes the
 * top-level `PrefsKey` (Cangjie has no nested type declarations).
 */
package eudi_logic_business

import std.collection.ArrayList
import std.collection.HashMap
import std.convert.*
import std.fs.*

/** Mirrors iOS `Prefs.Key`. */
public enum PrefsKey <: ToString & Equatable<PrefsKey> & Hashable {
    | biometryEnabled
    | cachedDeepLink
    | runAtLeastOnce
    | language
    | batchCounter
    | validateIssuerRegistrationCertificate

    public prop rawValue: String {
        get() {
            match (this) {
                case biometryEnabled => "biometryEnabled"
                case cachedDeepLink => "cachedDeepLink"
                case runAtLeastOnce => "runAtLeastOnce"
                case language => "language"
                case batchCounter => "batchCounter"
                case validateIssuerRegistrationCertificate => "validateIssuerRegistrationCertificate"
            }
        }
    }

    public func toString(): String {
        return this.rawValue
    }

    public func hashCode(): Int64 {
        return this.rawValue.hashCode()
    }

    public operator func ==(other: PrefsKey): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: PrefsKey): Bool {
        return !(this == other)
    }
}

/**
 * Mirrors the iOS `PrefsController` protocol. Values are stored as strings;
 * typed getters parse with UserDefaults-equivalent zero defaults.
 */
public interface PrefsController {
    /** Mirrors `setValue(_:forKey:)`. */
    func setValue(value: ToString, forKey: PrefsKey): Unit
    /** Mirrors `getString(forKey:)`. */
    func getString(forKey: PrefsKey): ?String
    /** Mirrors `getOptionalString(forKey:)` (empty string when absent). */
    func getOptionalString(forKey: PrefsKey): String
    /** Mirrors `getBool(forKey:)` (false when absent, like UserDefaults). */
    func getBool(forKey: PrefsKey): Bool
    /** Mirrors `getFloat(forKey:)` (0.0 when absent). */
    func getFloat(forKey: PrefsKey): Float64
    /** Mirrors `getInt(forKey:)` (0 when absent). */
    func getInt(forKey: PrefsKey): Int64
    /** Mirrors `remove(forKey:)`. */
    func remove(forKey: PrefsKey): Unit
    /** Mirrors `getValue(forKey:)` (raw stored representation). */
    func getValue(forKey: PrefsKey): ?String
    /** Mirrors `getUserLocale()` ("en_GB" fallback). */
    func getUserLocale(): String
}

/**
 * File-backed preferences store (write-through). The storage directory is
 * injectable so the app shell can point it at the real ability files dir;
 * the default matches the HarmonyOS app sandbox files path of this bundle.
 */
public class PrefsControllerImpl <: PrefsController {

    /** SharedPrefs registered defaults from iOS: batchCounter defaults to true. */
    private static let REGISTERED_DEFAULTS: Array<(String, String)> = [("batchCounter", "true")]

    public static let DEFAULT_STORAGE_DIR = "/data/storage/el2/base/haps/entry/files"

    private let values = HashMap<String, String>()
    private let filePath: String
    private var diskAvailable: Bool

    public init(storageDir!: String = DEFAULT_STORAGE_DIR) {
        this.filePath = "${storageDir}/eudi_prefs.json"
        this.diskAvailable = true
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func setValue(value: ToString, forKey: PrefsKey): Unit {
        this.values.add(forKey.rawValue, value.toString())
        persist()
    }

    public func getString(forKey: PrefsKey): ?String {
        match (this.values.get(forKey.rawValue)) {
            case Some(v) => return v
            case None => return registeredDefault(forKey.rawValue)
        }
    }

    public func getOptionalString(forKey: PrefsKey): String {
        return getString(forKey) ?? ""
    }

    public func getBool(forKey: PrefsKey): Bool {
        match (getString(forKey)) {
            case Some(v) =>
                let lowered = v.toAsciiLower()
                return lowered == "true" || lowered == "1"
            case None => return false
        }
    }

    public func getFloat(forKey: PrefsKey): Float64 {
        match (getString(forKey)) {
            case Some(v) => return Float64.tryParse(v) ?? 0.0
            case None => return 0.0
        }
    }

    public func getInt(forKey: PrefsKey): Int64 {
        match (getString(forKey)) {
            case Some(v) => return Int64.tryParse(v) ?? 0
            case None => return 0
        }
    }

    public func remove(forKey: PrefsKey): Unit {
        this.values.remove(forKey.rawValue)
        persist()
    }

    public func getValue(forKey: PrefsKey): ?String {
        return getString(forKey)
    }

    public func getUserLocale(): String {
        return getString(PrefsKey.language) ?? "en_GB"
    }

    private func registeredDefault(rawKey: String): ?String {
        for ((key, value) in REGISTERED_DEFAULTS) {
            if (key == rawKey) {
                return value
            }
        }
        return None
    }

    private func ensureDirectory(storageDir: String): Unit {
        try {
            if (!exists(storageDir)) {
                Directory.create(storageDir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) {
            return
        }
        try {
            if (!exists(this.filePath)) {
                return
            }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            for ((key, value) in parseFlatJsonObject(raw)) {
                this.values.add(key, value)
            }
        } catch (_: Exception) {
            // Unreadable store: degrade to memory-only but keep serving requests.
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) {
            return
        }
        try {
            let payload = serializeFlatJsonObject(this.values)
            File.writeTo(this.filePath, payload.toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    /** Serializes a flat string map as a JSON object with full string escaping. */
    private static func serializeFlatJsonObject(map: HashMap<String, String>): String {
        let sb = StringBuilder()
        sb.append("{")
        var first = true
        for ((key, value) in map) {
            if (!first) {
                sb.append(",")
            }
            first = false
            sb.append(escapeJsonString(key))
            sb.append(":")
            sb.append(escapeJsonString(value))
        }
        sb.append("}")
        return sb.toString()
    }

    private static func escapeJsonString(value: String): String {
        let sb = StringBuilder()
        sb.append("\"")
        for (r in value.runes()) {
            if (r == r'"') {
                sb.append("\\\"")
            } else if (r == r'\\') {
                sb.append("\\\\")
            } else if (r == r'\n') {
                sb.append("\\n")
            } else if (r == r'\r') {
                sb.append("\\r")
            } else if (r == r'\t') {
                sb.append("\\t")
            } else if (UInt32(r) < 0x20) {
                sb.append("\\u")
                sb.append(hex4(Int64(UInt32(r))))
            } else {
                sb.append(r)
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    private static func hex4(value: Int64): String {
        let digits = "0123456789abcdef".toRuneArray()
        let sb = StringBuilder()
        var shift = 12
        while (shift >= 0) {
            sb.append(digits[(value >> shift) & 15])
            shift -= 4
        }
        return sb.toString()
    }

    /**
     * Parses the flat {"key":"value",...} object this controller writes.
     * Tolerates whitespace; unknown structures terminate parsing gracefully.
     */
    private static func parseFlatJsonObject(raw: String): ArrayList<(String, String)> {
        let result = ArrayList<(String, String)>()
        let runes = raw.toRuneArray()
        var i: Int64 = 0
        i = skipWhitespace(runes, i)
        if (i >= runes.size || runes[i] != r'{') {
            return result
        }
        i++
        while (i < runes.size) {
            i = skipWhitespace(runes, i)
            if (i < runes.size && runes[i] == r'}') {
                break
            }
            let keyParse = parseJsonString(runes, i)
            match (keyParse) {
                case Some((key, afterKey)) =>
                    var j = skipWhitespace(runes, afterKey)
                    if (j >= runes.size || runes[j] != r':') {
                        return result
                    }
                    j = skipWhitespace(runes, j + 1)
                    let valueParse = parseJsonString(runes, j)
                    match (valueParse) {
                        case Some((value, afterValue)) =>
                            result.add((key, value))
                            var k = skipWhitespace(runes, afterValue)
                            if (k < runes.size && runes[k] == r',') {
                                i = k + 1
                            } else {
                                i = k
                            }
                        case None => return result
                    }
                case None => return result
            }
        }
        return result
    }

    private static func skipWhitespace(runes: Array<Rune>, start: Int64): Int64 {
        var i = start
        while (i < runes.size) {
            let r = runes[i]
            if (r == r' ' || r == r'\n' || r == r'\r' || r == r'\t') {
                i++
            } else {
                break
            }
        }
        return i
    }

    /** Parses one JSON string literal starting at `start`; returns (text, indexAfterClosingQuote). */
    private static func parseJsonString(runes: Array<Rune>, start: Int64): ?(String, Int64) {
        if (start >= runes.size || runes[start] != r'"') {
            return None
        }
        let sb = StringBuilder()
        var i = start + 1
        while (i < runes.size) {
            let r = runes[i]
            if (r == r'"') {
                return (sb.toString(), i + 1)
            }
            if (r == r'\\') {
                if (i + 1 >= runes.size) {
                    return None
                }
                let esc = runes[i + 1]
                if (esc == r'"') {
                    sb.append("\"")
                } else if (esc == r'\\') {
                    sb.append("\\")
                } else if (esc == r'/') {
                    sb.append("/")
                } else if (esc == r'n') {
                    sb.append("\n")
                } else if (esc == r'r') {
                    sb.append("\r")
                } else if (esc == r't') {
                    sb.append("\t")
                } else if (esc == r'u') {
                    match (parseJsonUnicodeEscape(runes, i)) {
                        case Some((ch, after)) =>
                            sb.append(ch)
                            i = after
                            continue
                        case None => return None
                    }
                } else {
                    return None
                }
                i += 2
                continue
            }
            sb.append(r)
            i++
        }
        return None
    }

    /**
     * Decode a JSON `\uXXXX` (and a following low-surrogate `\uXXXX` when the
     * first unit is a UTF-16 high surrogate). Unpaired surrogates such as
     * `\ud800` are invalid Unicode scalars: return None instead of constructing
     * `Rune`, which would throw OverflowException.
     * `pos` points at the backslash of `\u`.
     */
    private static func parseJsonUnicodeEscape(runes: Array<Rune>, pos: Int64): ?(Rune, Int64) {
        match (parseHex4(runes, pos + 2)) {
            case None => return None
            case Some(code) =>
                if (code >= 0xD800 && code <= 0xDBFF) {
                    let next = pos + 6
                    if (next + 5 >= runes.size || runes[next] != r'\\' || runes[next + 1] != r'u') {
                        return None
                    }
                    match (parseHex4(runes, next + 2)) {
                        case Some(low) =>
                            if (low < 0xDC00 || low > 0xDFFF) {
                                return None
                            }
                            let scalar = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            return (Rune(UInt32(scalar)), next + 6)
                        case None => return None
                    }
                }
                if (code >= 0xDC00 && code <= 0xDFFF) {
                    return None
                }
                return (Rune(UInt32(code)), pos + 6)
        }
    }

    private static func parseHex4(runes: Array<Rune>, start: Int64): ?Int64 {
        if (start + 3 >= runes.size) {
            return None
        }
        var code: Int64 = 0
        var k: Int64 = 0
        while (k < 4) {
            match (hexDigit(runes[start + k])) {
                case Some(v) => code = code * 16 + v
                case None => return None
            }
            k++
        }
        return code
    }

    private static func hexDigit(r: Rune): ?Int64 {
        if (r >= r'0' && r <= r'9') {
            return Int64(UInt32(r)) - 48
        }
        if (r >= r'a' && r <= r'f') {
            return Int64(UInt32(r)) - 87
        }
        if (r >= r'A' && r <= r'F') {
            return Int64(UInt32(r)) - 55
        }
        return None
    }
}

/** Factory replacing the iOS Swinject assembly registration for PrefsController. */
public func createPrefsController(): PrefsController {
    return PrefsControllerImpl()
}
