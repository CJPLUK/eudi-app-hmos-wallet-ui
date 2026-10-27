/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Service/SwiftDataService.swift) to Cangjie.
 *
 * Platform reshaping (SwiftData → std.fs JSON):
 * iOS uses SwiftData (PersistentModel, ModelContainer, ModelContext) which is an
 * Apple-exclusive declarative persistence framework unavailable on HarmonyOS.
 * The Cangjie replacement uses std.fs for file I/O, writing one JSON file per
 * entity collection (e.g., "bookmarks.json", "transaction_logs.json").
 *
 * Design mirrors PrefsControllerImpl (eudi_logic_business/prefs_controller.cj):
 *   - diskAvailable flag: any I/O failure degrades to in-memory only mode
 *   - loadFromDisk() on init, persist() on every write
 *   - Hand-rolled JSON parser/serialiser (flat object / array of objects)
 *   - Directory created with Directory.create(recursive: true) if absent
 *
 * iOS actor SerialContext → synchronous class methods (single-threaded emulator target).
 *
 * Generic type parameter T on the iOS SwiftDataService is replaced by four concrete
 * StorageService subclasses, one per entity, each managing its own JSON file and
 * in-memory map (HashMap<String, *>). This avoids Cangjie generics constraints
 * on interface methods while keeping the same separation of concerns.
 */
package eudi_logic_storage

import std.collection.ArrayList
import std.collection.HashMap
import std.fs.*

// ─────────────────────────────────────────────────────────────────────────────
// Internal JSON helpers (shared across all StorageService implementations)
// Mirrors the helpers in PrefsControllerImpl — same escaping rules, same parser.
// ─────────────────────────────────────────────────────────────────────────────

/** Escapes a string value as a JSON string literal (with enclosing quotes). */
func jsonEscapeString(value: String): String {
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
            sb.append(jsonHex4(Int64(UInt32(r))))
        } else {
            sb.append(r)
        }
    }
    sb.append("\"")
    return sb.toString()
}

func jsonHex4(value: Int64): String {
    let digits = "0123456789abcdef".toRuneArray()
    let sb = StringBuilder()
    var shift = 12
    while (shift >= 0) {
        sb.append(digits[(value >> shift) & 15])
        shift -= 4
    }
    return sb.toString()
}

func jsonSkipWhitespace(runes: Array<Rune>, start: Int64): Int64 {
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

func jsonHexDigit(r: Rune): ?Int64 {
    if (r >= r'0' && r <= r'9') { return Int64(UInt32(r)) - 48 }
    if (r >= r'a' && r <= r'f') { return Int64(UInt32(r)) - 87 }
    if (r >= r'A' && r <= r'F') { return Int64(UInt32(r)) - 55 }
    return None
}

func jsonParseHex4(runes: Array<Rune>, start: Int64): ?Int64 {
    if (start + 3 >= runes.size) {
        return None
    }
    var code: Int64 = 0
    var k: Int64 = 0
    while (k < 4) {
        match (jsonHexDigit(runes[start + k])) {
            case Some(v) => code = code * 16 + v
            case None => return None
        }
        k++
    }
    return code
}

/**
 * Decode a JSON `\uXXXX` (and a following low-surrogate `\uXXXX` when the
 * first unit is a UTF-16 high surrogate). Unpaired surrogates such as
 * `\ud800` are invalid Unicode scalars: return None instead of constructing
 * `Rune`, which would throw OverflowException.
 * `pos` points at the backslash of `\u`.
 */
func jsonParseUnicodeEscape(runes: Array<Rune>, pos: Int64): ?(Rune, Int64) {
    match (jsonParseHex4(runes, pos + 2)) {
        case None => return None
        case Some(code) =>
            if (code >= 0xD800 && code <= 0xDBFF) {
                let next = pos + 6
                if (next + 5 >= runes.size || runes[next] != r'\\' || runes[next + 1] != r'u') {
                    return None
                }
                match (jsonParseHex4(runes, next + 2)) {
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

/** Parses one JSON string literal starting at `start`; returns (text, indexAfterClosingQuote). */
func jsonParseString(runes: Array<Rune>, start: Int64): ?(String, Int64) {
    if (start >= runes.size || runes[start] != r'"') { return None }
    let sb = StringBuilder()
    var i = start + 1
    while (i < runes.size) {
        let r = runes[i]
        if (r == r'"') { return (sb.toString(), i + 1) }
        if (r == r'\\') {
            if (i + 1 >= runes.size) { return None }
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
                match (jsonParseUnicodeEscape(runes, i)) {
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
 * Parses a JSON array of flat objects: [{"k1":"v1","k2":"v2"}, ...].
 * Returns an ArrayList of HashMaps (field name → value string).
 * Used to deserialise entity collections from their JSON files.
 */
func jsonParseObjectArray(raw: String): ArrayList<HashMap<String, String>> {
    let result = ArrayList<HashMap<String, String>>()
    let runes = raw.toRuneArray()
    var i: Int64 = 0
    i = jsonSkipWhitespace(runes, i)
    if (i >= runes.size || runes[i] != r'[') { return result }
    i++
    while (i < runes.size) {
        i = jsonSkipWhitespace(runes, i)
        if (i >= runes.size) { break }
        if (runes[i] == r']') { break }
        if (runes[i] != r'{') { break }
        i++
        let obj = HashMap<String, String>()
        var closed = false
        while (i < runes.size) {
            i = jsonSkipWhitespace(runes, i)
            if (i >= runes.size) { break }
            if (runes[i] == r'}') { i++; closed = true; break }
            let keyParse = jsonParseString(runes, i)
            match (keyParse) {
                case Some((key, afterKey)) =>
                    var j = jsonSkipWhitespace(runes, afterKey)
                    if (j >= runes.size || runes[j] != r':') { break }
                    j = jsonSkipWhitespace(runes, j + 1)
                    let valParse = jsonParseString(runes, j)
                    match (valParse) {
                        case Some((value, afterValue)) =>
                            obj.add(key, value)
                            var k = jsonSkipWhitespace(runes, afterValue)
                            if (k < runes.size && runes[k] == r',') {
                                i = k + 1
                            } else {
                                i = k
                            }
                        case None => break
                    }
                case None => break
            }
        }
        if (!closed) { break }
        result.add(obj)
        i = jsonSkipWhitespace(runes, i)
        if (i < runes.size && runes[i] == r',') { i++ }
    }
    return result
}

/**
 * Serialises an ArrayList of flat string-map objects as a JSON array.
 * Each object has exactly the fields provided in the list of (key, value) pairs.
 */
func jsonSerializeObjectArray(items: ArrayList<Array<(String, String)>>): String {
    let sb = StringBuilder()
    sb.append("[")
    var firstItem = true
    for (fields in items) {
        if (!firstItem) { sb.append(",") }
        firstItem = false
        sb.append("{")
        var firstField = true
        for ((k, v) in fields) {
            if (!firstField) { sb.append(",") }
            firstField = false
            sb.append(jsonEscapeString(k))
            sb.append(":")
            sb.append(jsonEscapeString(v))
        }
        sb.append("}")
    }
    sb.append("]")
    return sb.toString()
}

// ─────────────────────────────────────────────────────────────────────────────
// BookmarkStorageService
// Mirrors iOS SwiftDataServiceImpl scoped to SDBookmark / Bookmark.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * File-backed store for Bookmark entities.
 * Persistence: <storageDir>/bookmarks.json  — JSON array of {identifier} objects.
 * In-memory: HashMap<String, Bookmark> keyed by identifier.
 * I/O failure → diskAvailable=false → memory-only, no crash.
 */
public class BookmarkStorageService {

    private let filePath: String
    private var diskAvailable: Bool
    private let store: HashMap<String, Bookmark>

    public init(storageDir: String) {
        this.filePath = "${storageDir}/bookmarks.json"
        this.diskAvailable = true
        this.store = HashMap<String, Bookmark>()
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func write(b: Bookmark): Unit {
        this.store.add(b.identifier, b)
        persist()
    }

    public func writeAll(bs: Array<Bookmark>): Unit {
        for (b in bs) { this.store.add(b.identifier, b) }
        persist()
    }

    public func read(identifier: String): ?Bookmark {
        return this.store.get(identifier)
    }

    public func readAll(): Array<Bookmark> {
        let result = ArrayList<Bookmark>()
        for ((_, b) in this.store) { result.add(b) }
        return result.toArray()
    }

    public func delete(identifier: String): Unit {
        this.store.remove(identifier)
        persist()
    }

    public func deleteAll(): Unit {
        this.store.clear()
        persist()
    }

    private func ensureDirectory(dir: String): Unit {
        try {
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) { return }
        try {
            if (!exists(this.filePath)) { return }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            let items = jsonParseObjectArray(raw)
            for (obj in items) {
                match (obj.get("identifier")) {
                    case Some(id) =>
                        this.store.add(id, Bookmark(id))
                    case None => ()
                }
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) { return }
        try {
            let items = ArrayList<Array<(String, String)>>()
            for ((_, b) in this.store) {
                items.add([("identifier", b.identifier)])
            }
            let payload = jsonSerializeObjectArray(items)
            File.writeTo(this.filePath, payload.toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// TransactionLogStorageService
// Mirrors iOS SwiftDataServiceImpl scoped to SDTransactionLog / TransactionLog.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * File-backed store for TransactionLog entities.
 * Persistence: <storageDir>/transaction_logs.json — JSON array of {identifier,value} objects.
 */
public class TransactionLogStorageService {

    private let filePath: String
    private var diskAvailable: Bool
    private let store: HashMap<String, TransactionLog>

    public init(storageDir: String) {
        this.filePath = "${storageDir}/transaction_logs.json"
        this.diskAvailable = true
        this.store = HashMap<String, TransactionLog>()
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func write(l: TransactionLog): Unit {
        this.store.add(l.identifier, l)
        persist()
    }

    public func writeAll(ls: Array<TransactionLog>): Unit {
        for (item in ls) { this.store.add(item.identifier, item) }
        persist()
    }

    public func read(identifier: String): ?TransactionLog {
        return this.store.get(identifier)
    }

    public func readAll(): Array<TransactionLog> {
        let result = ArrayList<TransactionLog>()
        for ((_, l) in this.store) { result.add(l) }
        return result.toArray()
    }

    public func delete(identifier: String): Unit {
        this.store.remove(identifier)
        persist()
    }

    public func deleteAll(): Unit {
        this.store.clear()
        persist()
    }

    private func ensureDirectory(dir: String): Unit {
        try {
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) { return }
        try {
            if (!exists(this.filePath)) { return }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            let items = jsonParseObjectArray(raw)
            for (obj in items) {
                match (obj.get("identifier")) {
                    case Some(id) =>
                        let val = obj.get("value") ?? ""
                        this.store.add(id, TransactionLog(id, val))
                    case None => ()
                }
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) { return }
        try {
            let items = ArrayList<Array<(String, String)>>()
            for ((_, l) in this.store) {
                items.add([("identifier", l.identifier), ("value", l.value)])
            }
            let payload = jsonSerializeObjectArray(items)
            File.writeTo(this.filePath, payload.toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RevokedDocumentStorageService
// ─────────────────────────────────────────────────────────────────────────────

/**
 * File-backed store for RevokedDocument entities.
 * Persistence: <storageDir>/revoked_documents.json — JSON array of {identifier} objects.
 */
public class RevokedDocumentStorageService {

    private let filePath: String
    private var diskAvailable: Bool
    private let store: HashMap<String, RevokedDocument>

    public init(storageDir: String) {
        this.filePath = "${storageDir}/revoked_documents.json"
        this.diskAvailable = true
        this.store = HashMap<String, RevokedDocument>()
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func write(d: RevokedDocument): Unit {
        this.store.add(d.identifier, d)
        persist()
    }

    public func writeAll(ds: Array<RevokedDocument>): Unit {
        for (doc in ds) { this.store.add(doc.identifier, doc) }
        persist()
    }

    public func read(identifier: String): ?RevokedDocument {
        return this.store.get(identifier)
    }

    public func readAll(): Array<RevokedDocument> {
        let result = ArrayList<RevokedDocument>()
        for ((_, d) in this.store) { result.add(d) }
        return result.toArray()
    }

    public func delete(identifier: String): Unit {
        this.store.remove(identifier)
        persist()
    }

    public func deleteAll(): Unit {
        this.store.clear()
        persist()
    }

    private func ensureDirectory(dir: String): Unit {
        try {
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) { return }
        try {
            if (!exists(this.filePath)) { return }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            let items = jsonParseObjectArray(raw)
            for (obj in items) {
                match (obj.get("identifier")) {
                    case Some(id) =>
                        this.store.add(id, RevokedDocument(id))
                    case None => ()
                }
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) { return }
        try {
            let items = ArrayList<Array<(String, String)>>()
            for ((_, d) in this.store) {
                items.add([("identifier", d.identifier)])
            }
            let payload = jsonSerializeObjectArray(items)
            File.writeTo(this.filePath, payload.toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FailedReIssuedDocStorageService
// ─────────────────────────────────────────────────────────────────────────────

/**
 * File-backed store for FailedReIssuedDocument entities.
 * Persistence: <storageDir>/failed_reissued_docs.json — JSON array of {identifier} objects.
 */
public class FailedReIssuedDocStorageService {

    private let filePath: String
    private var diskAvailable: Bool
    private let store: HashMap<String, FailedReIssuedDocument>

    public init(storageDir: String) {
        this.filePath = "${storageDir}/failed_reissued_docs.json"
        this.diskAvailable = true
        this.store = HashMap<String, FailedReIssuedDocument>()
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func write(d: FailedReIssuedDocument): Unit {
        this.store.add(d.identifier, d)
        persist()
    }

    public func writeAll(ds: Array<FailedReIssuedDocument>): Unit {
        for (doc in ds) { this.store.add(doc.identifier, doc) }
        persist()
    }

    public func read(identifier: String): ?FailedReIssuedDocument {
        return this.store.get(identifier)
    }

    public func readAll(): Array<FailedReIssuedDocument> {
        let result = ArrayList<FailedReIssuedDocument>()
        for ((_, d) in this.store) { result.add(d) }
        return result.toArray()
    }

    public func delete(identifier: String): Unit {
        this.store.remove(identifier)
        persist()
    }

    public func deleteAll(): Unit {
        this.store.clear()
        persist()
    }

    private func ensureDirectory(dir: String): Unit {
        try {
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) { return }
        try {
            if (!exists(this.filePath)) { return }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            let items = jsonParseObjectArray(raw)
            for (obj in items) {
                match (obj.get("identifier")) {
                    case Some(id) =>
                        this.store.add(id, FailedReIssuedDocument(id))
                    case None => ()
                }
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) { return }
        try {
            let items = ArrayList<Array<(String, String)>>()
            for ((_, d) in this.store) {
                items.add([("identifier", d.identifier)])
            }
            let payload = jsonSerializeObjectArray(items)
            File.writeTo(this.filePath, payload.toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }
}
