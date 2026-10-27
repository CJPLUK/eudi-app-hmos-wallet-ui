/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Extension/(all).swift:
 *   DocClaim+, DocClaimsDecodable+, TransactionLog+, WalletStorage.Document+,
 *   OfferedDocModel+ (documentTypeIdentifier).
 * (DocElements+ / OfferedIssuanceModel+ / OpenID4VCI.* equality live on the
 *  types themselves in wallet_domain.cj; String+/URLComponents+ live in core_util.cj.)
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import eudi_logic_resources.LocalizableStringKey
import eudi_logic_resources.LocalizableManager
import eudi_logic_business.DateUtil
import eudi_logic_storage.TransactionLog as StorageTransactionLog

// ─────────────────────────────────────────────────────────────────────────────
// Extension/DocClaim+Extensions.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `DocClaim.parseDate(parser:)`. */
public func parseDate(claim: DocClaim, parser: (String) -> String): DocClaim {
    match (claim.dataValue) {
        case date(_) =>
            let updated = DocClaim(
                name: claim.name,
                displayName: claim.displayName,
                dataValue: claim.dataValue,
                stringValue: parser(claim.stringValue),
                isOptional: claim.isOptional,
                order: claim.order,
                namespace: claim.namespace,
                children: claim.children,
                path: claim.path
            )
            return updated
        case _ => return claim
    }
}

/** Mirrors `DocClaim.parseUserPseudonym()`. */
public func parseUserPseudonym(claim: DocClaim): DocClaim {
    if (claim.name == DocumentJsonKeys.USER_PSEUDONYM) {
        let pseudonym = claim.dataValue.base64 ?? ""
        return DocClaim(
            name: claim.name,
            displayName: claim.displayName,
            dataValue: claim.dataValue,
            stringValue: pseudonym,
            isOptional: claim.isOptional,
            order: claim.order,
            namespace: claim.namespace,
            children: claim.children,
            path: claim.path
        )
    }
    return claim
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension/DocClaimsDecodable+Extensions.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `DocClaimsDecodable.issuerName`. */
public func issuerName(doc: DocClaimsDecodable): String {
    if (let Some(displays) <- doc.issuerDisplay) {
        let locale = systemLanguageCode()
        for (d in displays) {
            if (let Some(loc) <- d.localeIdentifier && loc == locale) {
                if (let Some(n) <- d.name) { return n }
            }
        }
        if (displays.size > 0) {
            if (let Some(n) <- displays[0].name) { return n }
        }
    }
    return LocalizableManager.get(LocalizableStringKey.unknown)
}

/** Mirrors `DocClaimsDecodable.issuerLogo`. */
public func issuerLogo(doc: DocClaimsDecodable): ?String {
    if (let Some(displays) <- doc.issuerDisplay) {
        if (displays.size > 0) {
            if (let Some(logo) <- displays[0].logo) {
                return logo.uri
            }
        }
    }
    return None
}

/** Mirrors `DocClaimsDecodable.documentTypeIdentifier`. */
public func documentTypeIdentifier(doc: DocClaimsDecodable): DocumentTypeIdentifier {
    return DocumentTypeIdentifier.fromRawValue(doc.docType)
}

/** Mirrors `DocClaimsDecodable.getExpiryDate(parser:)`. */
public func getExpiryDate(doc: DocClaimsDecodable, parser: (DateTime) -> String): ?String {
    match (doc.validUntil) {
        case Some(d) => parser(d)
        case None =>
            // validUntil is not populated from the stored credential round-trip;
            // fall back to the expiry claim (already display-formatted) so the
            // list "Valid until …" and issuer-card "Expires on …" still render.
            // mso_mdoc uses expiry_date; SD-JWT VC (EHIC etc.) uses date_of_expiry.
            for (c in doc.docClaims) {
                if ((c.name == DocumentJsonKeys.EXPIRY_DATE || c.name == DocumentJsonKeys.DATE_OF_EXPIRY)
                    && !c.stringValue.isEmpty()) {
                    return Some(c.stringValue)
                }
            }
            // Generic SD-JWT VCs (Diploma etc.) carry expiry only as the JWT
            // `exp` claim. Prefer its ISO dataValue (date("2026-09-30")) — the
            // caller re-formats it to the short "dd MMM yyyy" list form; the
            // long stringValue ("Wednesday, 30 September 2026") is the fallback.
            for (c in doc.docClaims) {
                if (c.name == "exp") {
                    match (c.dataValue) {
                        case DocDataValue.date(iso) where !iso.isEmpty() => return Some(iso)
                        case _ =>
                            if (!c.stringValue.isEmpty()) {
                                return Some(c.stringValue)
                            }
                    }
                }
            }
            return None
    }
}

/** Mirrors `DocClaimsDecodable.hasExpired`. */
public func hasExpired(doc: DocClaimsDecodable): Bool {
    match (doc.validUntil) {
        case Some(d) => DateUtil.isBeforeToday(d)
        case None => false
    }
}

/** Mirrors `DocClaimsDecodable.getBearersName()`. */
public func getBearersName(doc: DocClaimsDecodable): ?(String, String) {
    var firstName: ?String = None
    var lastName: ?String = None
    for (c in doc.docClaims) {
        if (c.name == DocumentJsonKeys.FIRST_NAME) { firstName = c.stringValue }
        if (c.name == DocumentJsonKeys.LAST_NAME) { lastName = c.stringValue }
    }
    match ((firstName, lastName)) {
        case (Some(f), Some(l)) => (f, l)
        case _ => None
    }
}

/** Mirrors `DocClaimsDecodable.getPortrait()` (raw image bytes; no SwiftUI Image). */
public func getPortrait(doc: DocClaimsDecodable): ?Array<UInt8> {
    for (c in doc.docClaims) {
        if (c.name == DocumentJsonKeys.PORTRAIT) {
            return c.dataValue.image
        }
    }
    return None
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension/WalletStorage.Document+Extensions.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `WalletStorage.Document.documentTypeIdentifier`. */
public func documentTypeIdentifier(doc: WalletStorageDocument): DocumentTypeIdentifier {
    return DocumentTypeIdentifier.fromRawValue(doc.docType)
}

/** Mirrors `WalletStorage.Document.transformToDeferredDecodable()`. */
public func transformToDeferredDecodable(doc: WalletStorageDocument): DeferredDocument {
    let metadata = DocMetadata.fromBlob(doc.metadata)
    var displayName: ?String = None
    var display: ?Array<DisplayMetadata> = None
    var issuerDisplay: ?Array<DisplayMetadata> = None
    var credentialIssuerIdentifier: ?String = None
    var configurationIdentifier: ?String = None
    if (let Some(m) <- metadata) {
        displayName = m.getDisplayName(systemLanguageCode())
        display = m.display
        issuerDisplay = m.issuerDisplay
        credentialIssuerIdentifier = m.credentialIssuerIdentifier
        configurationIdentifier = m.configurationIdentifier
    }
    return DeferredDocument(
        id: doc.id,
        createdAt: doc.createdAt,
        displayName: displayName,
        docType: "",
        docDataFormat: doc.docDataFormat,
        display: display,
        issuerDisplay: issuerDisplay,
        credentialIssuerIdentifier: credentialIssuerIdentifier,
        configurationIdentifier: configurationIdentifier
    )
}

/** Mirrors `[WalletStorage.Document].transformToDeferredDecodables()`. */
public func transformToDeferredDecodables(docs: Array<WalletStorageDocument>): Array<DocClaimsDecodable> {
    let out = ArrayList<DocClaimsDecodable>()
    for (d in docs) {
        out.add(transformToDeferredDecodable(d))
    }
    return out.toArray()
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension/TransactionLog+Extensions.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors `logic_storage.TransactionLog.toTransactionLogItem(id:parse:)`.
 * Decodes the stored value back into a CoreTransactionLog, runs the wallet's
 * parser, and wraps the result. Throws WalletCoreError.unableToFetchTransactionLog
 * when the stored value cannot be decoded — exactly the iOS guard.
 */
public func toTransactionLogItem(
    stored: StorageTransactionLog,
    id: String,
    parse: (CoreTransactionLog) -> TransactionLogData
): TransactionLogItem {
    let coreLog = decodeStoredTransactionLog(stored.value)
    match (coreLog) {
        case Some(log) => return TransactionLogItem(id: id, transactionLogData: parse(log))
        case None => throw WalletCoreError.unableToFetchTransactionLog()
    }
}

/**
 * Decodes the JSON the TransactionLogger stored. The logger encodes a
 * CoreTransactionLog (timestamp + value); decoding restores it. A non-decodable
 * value yields None, mirroring the iOS `try? JSONDecoder().decode(...)`.
 */
func decodeStoredTransactionLog(value: String): ?CoreTransactionLog {
    // App-authored presentation logs use {ts,rp,docs,status}; the injected
    // TransactionLogger uses {timestamp,value}. Decode both. Previously the
    // standard format fell through with timestamp=0, hiding recent entries under
    // January 1970 in History.
    if (value.isEmpty()) { return None }
    let ts = presentationTransactionField(value, "ts")
    // A JSON presentation log is recognised by its `ts` field; recover the real
    // timestamp regardless of whether a relying-party name was captured (empty
    // rp → the UI falls back to its "Data shared" label, never the raw JSON).
    if (!ts.isEmpty()) {
        let rp = presentationTransactionStringField(value, "rp")
        let docs = presentationTransactionStringField(value, "docs")
        let status = presentationTransactionStringField(value, "status")
        return CoreTransactionLog(
            timestamp: parseDigits(ts),
            value: rp,
            documents: docs,
            status: if (status.isEmpty()) { "completed" } else { status },
            logType: "presentation"
        )
    }
    let timestamp = presentationTransactionField(value, "timestamp")
    if (!timestamp.isEmpty()) {
        return CoreTransactionLog(
            timestamp: parseDigits(timestamp),
            value: presentationTransactionStringField(value, "value"),
            status: "completed",
            logType: "presentation"
        )
    }
    return CoreTransactionLog(timestamp: 0, value: value)
}

/**
 * Presentation transaction-log value codec (JSON `{ts, rp, docs, status}`).
 * Kept deliberately small — the History tab only needs timestamp + relying
 * party name; the docs/status fields are carried for future transaction detail.
 */
public func encodePresentationTransactionValue(ts: Int64, relyingParty: String, docs: String): String {
    return "{\"ts\":" + ts.toString() +
        ",\"rp\":\"" + jsonEscapeTxn(relyingParty) +
        "\",\"docs\":\"" + jsonEscapeTxn(docs) +
        "\",\"status\":\"completed\"}"
}

/** Parse a run of ASCII digits into Int64 (no std.convert dependency). */
func parseDigits(s: String): Int64 {
    var n: Int64 = 0
    for (c in s.toArray()) {
        if (c >= b'0' && c <= b'9') {
            try {
                n = n * 10 + Int64(c - b'0')
            } catch (_: OverflowException) {
                return 0
            }
        }
    }
    return n
}

func jsonEscapeTxn(s: String): String {
    // Walk runes, not UTF-8 bytes: String.fromUtf8([one byte]) throws on é/ä/中文
    // (reader-cert CN and document labels are often non-ASCII).
    var out = ""
    for (r in s.runes()) {
        if (r == r'"') {
            out += "\\\""
        } else if (r == r'\\') {
            out += "\\\\"
        } else if (r == r'\n') {
            out += " "
        } else {
            out += String(r)
        }
    }
    return out
}

/** Extract a bare (numeric) JSON field value by key; "" when absent. */
func presentationTransactionField(json: String, key: String): String {
    let needle = "\"" + key + "\":"
    match (json.indexOf(needle)) {
        case Some(idx) =>
            var i = idx + needle.size
            let bytes = json.toArray()
            var out = ""
            while (i < bytes.size) {
                let c = bytes[i]
                if (c >= b'0' && c <= b'9') {
                    out += String.fromUtf8([c])
                    i++
                } else {
                    break
                }
            }
            return out
        case None => return ""
    }
}

/** Extract a quoted JSON string field value by key; "" when absent. */
func presentationTransactionStringField(json: String, key: String): String {
    let needle = "\"" + key + "\":\""
    match (json.indexOf(needle)) {
        case Some(idx) =>
            // `indexOf`/`size` are byte offsets; the needle is ASCII so the
            // slice starts on a UTF-8 character boundary. Decode the value as
            // runes so a multi-byte RP name (café, Ministério, …) does not
            // hit String.fromUtf8([lead-byte]).
            let rest = json[idx + needle.size..json.size]
            let runes = rest.toRuneArray()
            var out = ""
            var i: Int64 = 0
            while (i < runes.size) {
                let c = runes[i]
                if (c == r'\\' && i + 1 < runes.size) {
                    out += String(runes[i + 1])
                    i += 2
                } else if (c == r'"') {
                    break
                } else {
                    out += String(c)
                    i++
                }
            }
            return out
        case None => return ""
    }
}
