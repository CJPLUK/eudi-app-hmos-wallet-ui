/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Small internal helpers for logic-core: locale resolution, base64, byte/array
 * equality, and the String+Extensions / URLComponents+Extensions ports.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import eudi_logic_business.StringUtil
import eudi_logic_business.UrlUtil
import eudi_logic_business.ParsedUrl
import eudi_logic_resources.LocalizableStringKey
import eudi_logic_resources.LocalizableManager

/** Localized "Verifier" fallback (LocalizableStringKey.unknownVerifier). */
func LocalizableManagerUnknownVerifier(): String {
    return LocalizableManager.get(LocalizableStringKey.unknownVerifier)
}

/** Localized "Why we need your data?" notice (LocalizableStringKey.requestDataInfoNotice). */
func LocalizableManagerRequestDataInfoNotice(): String {
    return LocalizableManager.get(LocalizableStringKey.requestDataInfoNotice)
}

/**
 * Mirrors iOS `Locale.current.systemLanguageCode`. The HarmonyOS logic HAR has
 * no per-process locale; eudi_logic_resources ships English-default literals and
 * the emulator target runs in English, so the wallet's UI culture is "en"
 * (the iOS source falls back to the first display entry when no locale matches,
 * which this value reproduces).
 */
public func systemLanguageCode(): String {
    return "en"
}

/** Base64 of a UTF-8 string (delegates to the delivered StringUtil). */
func encodeBase64(value: String): String {
    return StringUtil.toBase64(value)
}

/** Base64 of a raw byte buffer. */
func encodeBase64Bytes(bytes: Array<UInt8>): String {
    return StringUtil.toBase64(String.fromUtf8(bytes))
}

/** Byte-buffer equality. */
func bytesEqual(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) { return false }
        i++
    }
    return true
}

/** String-array equality. */
func arraysEqual(a: Array<String>, b: Array<String>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) { return false }
        i++
    }
    return true
}

// ─────────────────────────────────────────────────────────────────────────────
// String+Extensions.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors String.toBool() — `Bool(self) ?? false`. */
public func stringToBool(value: String): Bool {
    match (value) {
        case "true" => true
        case _ => false
    }
}

/** Mirrors String.toCompatibleUrl() used by getDynamicIssuancePendingData. */
public func toCompatibleUrl(value: String): ?ParsedUrl {
    return UrlUtil.toCompatibleUrl(value)
}

// ─────────────────────────────────────────────────────────────────────────────
// URLComponents+Extensions.swift : removeSchemeFromComponents()
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `URLComponents.removeSchemeFromComponents()`: drops the scheme and
 * the two leading slashes, returning the remaining URL string (or None when the
 * input cannot be re-parsed). Used by WalletKitController.decodeDeeplink.
 */
public func removeSchemeFromComponents(urlString: String): ?String {
    // Find "://" and strip everything up to and including the scheme separator,
    // then drop the leading "//" the iOS code removes via dropFirst(2).
    let marker = "://"
    if (let Some(idx) <- indexOf(urlString, marker)) {
        let rest = urlString[idx + marker.size..urlString.size]
        // rest is already past "//"; re-validate via the URL parser.
        if (let Some(_) <- UrlUtil.parse("scheme://" + rest)) {
            return rest
        }
        return None
    }
    // No scheme present: return the string as-is if parseable.
    if (let Some(_) <- UrlUtil.parse("scheme://" + urlString)) {
        return urlString
    }
    return None
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal JSON value builders (Provider attestation payloads).
// The attestation payloads are flat JSON objects/arrays of strings; a small
// deterministic serialiser avoids a heavyweight dependency while producing valid
// JSON identical in shape to the iOS JSONSerialization output.
// ─────────────────────────────────────────────────────────────────────────────

/** Escapes a string and wraps it in JSON quotes. */
func jsonString(value: String): String {
    let sb = StringBuilder()
    sb.append("\"")
    for (c in value.toRuneArray()) {
        match (c) {
            case r'\"' => sb.append("\\\"")
            case r'\\' => sb.append("\\\\")
            case r'\n' => sb.append("\\n")
            case r'\r' => sb.append("\\r")
            case r'\t' => sb.append("\\t")
            case _ => sb.append(c)
        }
    }
    sb.append("\"")
    return sb.toString()
}

/** Builds a JSON object from already-serialised (key, valueJson) pairs. */
func jsonObject(fields: Array<(String, String)>): String {
    let sb = StringBuilder()
    sb.append("{")
    var i = 0
    while (i < fields.size) {
        if (i > 0) { sb.append(",") }
        sb.append(jsonString(fields[i][0]))
        sb.append(":")
        sb.append(fields[i][1])
        i++
    }
    sb.append("}")
    return sb.toString()
}

/** Builds a JSON array from already-serialised element JSON strings. */
func jsonArray(elements: Array<String>): String {
    let sb = StringBuilder()
    sb.append("[")
    var i = 0
    while (i < elements.size) {
        if (i > 0) { sb.append(",") }
        sb.append(elements[i])
        i++
    }
    sb.append("]")
    return sb.toString()
}

/** Serialises a String→String map as a JSON object. */
func jsonFromStringMap(map: HashMap<String, String>): String {
    let fields = ArrayList<(String, String)>()
    for ((k, v) in map) {
        fields.add((k, jsonString(v)))
    }
    return jsonObject(fields.toArray())
}

/** Appends one (key, valueJson) field to an existing field array. */
func concatFields(fields: Array<(String, String)>, extra: (String, String)): Array<(String, String)> {
    let out = ArrayList<(String, String)>()
    for (f in fields) { out.add(f) }
    out.add(extra)
    return out.toArray()
}

/** UTF-8 byte buffer of a string. */
func utf8Bytes(value: String): Array<UInt8> {
    return value.toArray()
}

/** First index of `needle` in `haystack`, or None. */
func indexOf(haystack: String, needle: String): ?Int64 {
    if (needle.size == 0 || needle.size > haystack.size) { return None }
    var i = 0
    let limit = haystack.size - needle.size
    while (i <= limit) {
        var j = 0
        var matched = true
        while (j < needle.size) {
            if (haystack[i + j] != needle[j]) {
                matched = false
                break
            }
            j++
        }
        if (matched) { return i }
        i++
    }
    return None
}
