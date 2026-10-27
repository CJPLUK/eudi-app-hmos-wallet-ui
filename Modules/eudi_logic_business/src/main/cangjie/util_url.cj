/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Extension/URL+Extensions.swift, String+Extensions.swift
 * `toCompatibleUrl()`) to Cangjie.
 *
 * iOS relies on Foundation `URL` / `URLComponents`; this file provides the
 * equivalent component decomposition used by `FormValidator.ValidateUrl` and by
 * cross-module URL consumers. `UIApplication.open` has no counterpart inside a
 * logic HAR and is intentionally not migrated (UI shell owns deep-link opening).
 */
package eudi_logic_business

/** Decomposed URL, mirroring the URLComponents fields the wallet consumes. */
public class ParsedUrl {
    public let scheme: ?String
    public let host: ?String
    public let path: String
    public let query: ?String
    public let fragment: ?String

    public init(scheme: ?String, host: ?String, path: String, query: ?String, fragment: ?String) {
        this.scheme = scheme
        this.host = host
        this.path = path
        this.query = query
        this.fragment = fragment
    }
}

/** URL helper set mirroring the iOS URL extension surface consumed across modules. */
public class UrlUtil {

    /**
     * Mirrors `URL(string:)` + `URLComponents(url:resolvingAgainstBaseURL:)`:
     * splits scheme / host / path / query / fragment. Returns None when the
     * value has no RFC3986-style scheme or contains whitespace.
     */
    public static func parse(value: String): ?ParsedUrl {
        if (value.isEmpty() || value.contains(" ")) {
            return None
        }
        var rest = value
        var fragment: ?String = None
        match (rest.indexOf("#")) {
            case Some(idx) =>
                let frag = rest[(idx + 1)..rest.size]
                fragment = if (frag.isEmpty()) { None } else { frag }
                rest = rest[0..idx]
            case None => ()
        }
        var query: ?String = None
        match (rest.indexOf("?")) {
            case Some(idx) =>
                let q = rest[(idx + 1)..rest.size]
                query = if (q.isEmpty()) { None } else { q }
                rest = rest[0..idx]
            case None => ()
        }
        let schemeEnd: Int64
        match (rest.indexOf(":")) {
            case Some(idx) => schemeEnd = idx
            case None => return None
        }
        let schemeText = rest[0..schemeEnd]
        if (!isValidScheme(schemeText)) {
            return None
        }
        var afterScheme = rest[(schemeEnd + 1)..rest.size]
        var host: ?String = None
        var path = ""
        if (afterScheme.startsWith("//")) {
            let authorityAndPath = afterScheme[2..afterScheme.size]
            match (authorityAndPath.indexOf("/")) {
                case Some(slash) =>
                    let authority = authorityAndPath[0..slash]
                    host = if (authority.isEmpty()) { None } else { stripUserInfoAndPort(authority) }
                    path = authorityAndPath[slash..authorityAndPath.size]
                case None =>
                    host = if (authorityAndPath.isEmpty()) { None } else { stripUserInfoAndPort(authorityAndPath) }
                    path = ""
            }
        } else {
            // opaque form like mailto:user@host — everything is the path
            path = afterScheme
        }
        return ParsedUrl(schemeText, host, path, query, fragment)
    }

    /**
     * Mirrors `String.toCompatibleUrl()`: percent-decode first, try to parse,
     * then retry with the query-allowed percent-encoded form.
     */
    public static func toCompatibleUrl(value: String): ?ParsedUrl {
        let decoded: String
        match (StringUtil.removingPercentEncoding(value)) {
            case Some(d) => decoded = d
            case None => return None
        }
        match (parse(decoded)) {
            case Some(url) => return url
            case None => ()
        }
        return parse(StringUtil.urlEncode(decoded))
    }

    private static func isValidScheme(scheme: String): Bool {
        if (scheme.isEmpty()) {
            return false
        }
        var first = true
        for (r in scheme.runes()) {
            let isAlpha = (r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z')
            let isDigit = r >= r'0' && r <= r'9'
            if (first) {
                if (!isAlpha) {
                    return false
                }
                first = false
            } else {
                if (!isAlpha && !isDigit && r != r'+' && r != r'-' && r != r'.') {
                    return false
                }
            }
        }
        return true
    }

    private static func stripUserInfoAndPort(authority: String): String {
        var host = authority
        match (host.lastIndexOf("@")) {
            case Some(at) => host = host[(at + 1)..host.size]
            case None => ()
        }
        match (host.lastIndexOf(":")) {
            case Some(colon) => host = host[0..colon]
            case None => ()
        }
        return host
    }
}
