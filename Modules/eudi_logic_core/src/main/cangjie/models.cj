/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Model/(all).swift:
 *   DocumentIdentifier, DocumentCategory, DocumentElement, DocumentJsonKeys,
 *   DeferrredDocument, DynamicIssuancePendingData, RequestItemConvertible,
 *   ScopedDocument, TransactionLogItem.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import eudi_logic_business.ParsedUrl
import eudi_logic_resources.LocalizableStringKey
import eudi_logic_resources.LocalizableManager

// ─────────────────────────────────────────────────────────────────────────────
// Model/DocumentJsonKeys.swift
// ─────────────────────────────────────────────────────────────────────────────

public class DocumentJsonKeys {
    public static let PORTRAIT = "portrait"
    public static let SIGNATURE = "signature_usual_mark"
    public static let FIRST_NAME = "given_name"
    public static let LAST_NAME = "family_name"
    public static let USER_PSEUDONYM = "user_pseudonym"
    public static let EXPIRY_DATE = "expiry_date"
    // SD-JWT VC credentials (e.g. EHIC) carry the expiry under date_of_expiry,
    // not the mdoc expiry_date key; getExpiryDate checks both.
    public static let DATE_OF_EXPIRY = "date_of_expiry"
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/DocumentIdentifier.swift  (DocumentTypeIdentifier)
// ─────────────────────────────────────────────────────────────────────────────

let MDOC_PID_DOCTYPE = "eu.europa.ec.eudi.pid.1"
let SDJWT_PID_DOCTYPE = "urn:eudi:pid:1"

/** Mirrors iOS `DocumentTypeIdentifier` (RawRepresentable, Equatable, Hashable). */
public enum DocumentTypeIdentifier <: Equatable<DocumentTypeIdentifier> & Hashable {
    | mDocPid
    | sdJwtPid
    | other(String)

    public prop rawValue: String {
        get() {
            match (this) {
                case mDocPid => MDOC_PID_DOCTYPE
                case sdJwtPid => SDJWT_PID_DOCTYPE
                case other(formatType) => formatType
            }
        }
    }

    /** Mirrors `init(rawValue:)` (Cangjie enums use a static factory). */
    public static func fromRawValue(rawValue: String): DocumentTypeIdentifier {
        if (rawValue == MDOC_PID_DOCTYPE) { return mDocPid }
        if (rawValue == SDJWT_PID_DOCTYPE) { return sdJwtPid }
        return other(rawValue)
    }

    public operator func ==(o: DocumentTypeIdentifier): Bool { this.rawValue == o.rawValue }
    public operator func !=(o: DocumentTypeIdentifier): Bool { !(this == o) }
    public func hashCode(): Int64 { this.rawValue.hashCode() }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/DocumentCategory.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `DocumentCategory`. */
public enum DocumentCategory <: Equatable<DocumentCategory> & Hashable {
    | government
    | travel
    | finance
    | education
    | health
    | socialSecurity
    | retail
    | other

    public prop title: LocalizableStringKey {
        get() {
            match (this) {
                case government => LocalizableStringKey.categoryGovernment
                case travel => LocalizableStringKey.categoryTravel
                case finance => LocalizableStringKey.categoryFinance
                case education => LocalizableStringKey.categoryEducation
                case health => LocalizableStringKey.categoryHealth
                case socialSecurity => LocalizableStringKey.categorySocialSecurity
                case retail => LocalizableStringKey.categoryRetail
                case other => LocalizableStringKey.categoryOther
            }
        }
    }

    public prop filterAttribute: String {
        get() { LocalizableManager.get(this.title) }
    }

    public prop order: Int64 {
        get() {
            match (this) {
                case government => 1
                case travel => 2
                case finance => 3
                case education => 4
                case health => 5
                case socialSecurity => 6
                case retail => 7
                case other => 8
            }
        }
    }

    public operator func ==(o: DocumentCategory): Bool { this.order == o.order }
    public operator func !=(o: DocumentCategory): Bool { !(this == o) }
    public func hashCode(): Int64 { this.order }
}

/**
 * Mirrors `typealias DocumentCategories = OrderedDictionary<DocumentCategory, [DocumentTypeIdentifier]>`.
 * Cangjie has no ordered dictionary, so insertion order is preserved by holding
 * the (key, value) pairs in an ArrayList. `getDocumentCategories()` sorts by
 * `DocumentCategory.order` exactly like the iOS controller.
 */
public class DocumentCategories {
    public let entries: ArrayList<(DocumentCategory, Array<DocumentTypeIdentifier>)>

    public init() {
        this.entries = ArrayList<(DocumentCategory, Array<DocumentTypeIdentifier>)>()
    }
    public init(entries: ArrayList<(DocumentCategory, Array<DocumentTypeIdentifier>)>) {
        this.entries = entries
    }

    /** Append a category → identifiers pair, preserving insertion order. */
    public func addEntry(category: DocumentCategory, ids: Array<DocumentTypeIdentifier>): Unit {
        this.entries.add((category, ids))
    }

    /** Returns a copy ordered by DocumentCategory.order. */
    public func sortedByOrder(): DocumentCategories {
        let copy = ArrayList<(DocumentCategory, Array<DocumentTypeIdentifier>)>()
        for (e in this.entries) { copy.add(e) }
        // stable insertion sort on category.order
        var i = 1
        while (i < copy.size) {
            let cur = copy[i]
            var j = i - 1
            while (j >= 0 && copy[j][0].order > cur[0].order) {
                copy[j + 1] = copy[j]
                j--
            }
            copy[j + 1] = cur
            i++
        }
        return DocumentCategories(copy)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/DocumentElement.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `DocumentElementType`. */
public enum DocumentElementType <: Equatable<DocumentElementType> {
    | mdoc
    | sdjwt
    public operator func ==(o: DocumentElementType): Bool {
        match ((this, o)) {
            case (mdoc, mdoc) => true
            case (sdjwt, sdjwt) => true
            case _ => false
        }
    }
    public operator func !=(o: DocumentElementType): Bool { !(this == o) }
}

/**
 * Mirrors iOS `DocumentElementValue`. SwiftUI `Image` becomes raw image bytes
 * (logic layer never imports ArkUI), preserving `.string` / `.image` accessors.
 */
public enum DocumentElementValue <: Equatable<DocumentElementValue> {
    | string(String)
    | unavailable(String)
    | image(Array<UInt8>)

    public prop stringValue: ?String {
        get() {
            match (this) {
                case string(s) => s
                case unavailable(s) => s
                case _ => None
            }
        }
    }
    public prop imageValue: ?Array<UInt8> {
        get() {
            match (this) {
                case image(b) => b
                case _ => None
            }
        }
    }
    public operator func ==(o: DocumentElementValue): Bool {
        match ((this, o)) {
            case (string(a), string(b)) => a == b
            case (unavailable(a), unavailable(b)) => a == b
            case (image(a), image(b)) => bytesEqual(a, b)
            case _ => false
        }
    }
    public operator func !=(o: DocumentElementValue): Bool { !(this == o) }
}

/** Mirrors iOS `DocumentElementClaim.Status`. */
public enum DocumentElementClaimStatus <: Equatable<DocumentElementClaimStatus> {
    | available(Bool)   // isRequired
    | notAvailable

    public prop isRequired: Bool {
        get() {
            match (this) {
                case available(r) => r
                case notAvailable => false
            }
        }
    }
    public prop isAvailable: Bool {
        get() {
            match (this) {
                case available(_) => true
                case notAvailable => false
            }
        }
    }
    public operator func ==(o: DocumentElementClaimStatus): Bool {
        match ((this, o)) {
            case (available(a), available(b)) => a == b
            case (notAvailable, notAvailable) => true
            case _ => false
        }
    }
    public operator func !=(o: DocumentElementClaimStatus): Bool { !(this == o) }
}

/** Mirrors iOS `DocumentElementClaim` (group / primitive). */
public enum DocumentElementClaim {
    | group(String, String, Array<DocumentElementClaim>)                                                  // id, title, items
    | primitive(String, String, String, ?String, Array<String>, DocumentElementType, DocumentElementValue, DocumentElementClaimStatus) // id, title, documentId, nameSpace, path, type, value, status

    public prop id: String {
        get() {
            match (this) {
                case group(id, _, _) => id
                case primitive(id, _, _, _, _, _, _, _) => id
            }
        }
    }
    public prop title: String {
        get() {
            match (this) {
                case group(_, t, _) => t
                case primitive(_, t, _, _, _, _, _, _) => t
            }
        }
    }
    public prop path: ?Array<String> {
        get() {
            match (this) {
                case group(_, _, _) => None
                case primitive(_, _, _, _, p, _, _, _) => p
            }
        }
    }
    public prop documentId: ?String {
        get() {
            match (this) {
                case group(_, _, _) => None
                case primitive(_, _, d, _, _, _, _, _) => d
            }
        }
    }
    public prop nameSpace: ?String {
        get() {
            match (this) {
                case group(_, _, _) => None
                case primitive(_, _, _, ns, _, _, _, _) => ns
            }
        }
    }
    public prop elementType: ?DocumentElementType {
        get() {
            match (this) {
                case group(_, _, _) => None
                case primitive(_, _, _, _, _, t, _, _) => t
            }
        }
    }
}

/** Extension/DocumentElementClaim+Extensions.swift: sortByName(). */
public func sortByName(claims: Array<DocumentElementClaim>): Array<DocumentElementClaim> {
    let list = ArrayList<DocumentElementClaim>()
    for (c in claims) { list.add(c) }
    var i = 1
    while (i < list.size) {
        let cur = list[i]
        var j = i - 1
        while (j >= 0 && list[j].title > cur.title) {
            list[j + 1] = list[j]
            j--
        }
        list[j + 1] = cur
        i++
    }
    return list.toArray()
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/ScopedDocument.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `ScopedDocument`. */
public struct ScopedDocument <: Equatable<ScopedDocument> {
    public let name: String
    public let issuer: String
    public let order: Int64
    public let configId: String
    public let isPid: Bool
    public let docTypeIdentifier: DocumentTypeIdentifier

    public init(name!: String, issuer!: String, order!: Int64, configId!: String, isPid!: Bool, docTypeIdentifier!: DocumentTypeIdentifier) {
        this.name = name
        this.issuer = issuer
        this.order = order
        this.configId = configId
        this.isPid = isPid
        this.docTypeIdentifier = docTypeIdentifier
    }

    /** Mirrors `ScopedDocument.empty()`. */
    public static func empty(): ScopedDocument {
        return ScopedDocument(
            name: "", issuer: "", order: 0, configId: "", isPid: false,
            docTypeIdentifier: DocumentTypeIdentifier.mDocPid
        )
    }

    public operator func ==(o: ScopedDocument): Bool {
        this.name == o.name && this.issuer == o.issuer && this.order == o.order
            && this.configId == o.configId && this.isPid == o.isPid
            && this.docTypeIdentifier == o.docTypeIdentifier
    }
    public operator func !=(o: ScopedDocument): Bool { !(this == o) }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/TransactionLogItem.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `TransactionLogItem`. */
public struct TransactionLogItem {
    public let id: String
    public let transactionLogData: TransactionLogData
    public init(id!: String, transactionLogData!: TransactionLogData) {
        this.id = id
        this.transactionLogData = transactionLogData
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/DynamicIssuancePendingData.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `DynamicIssuancePendingData` (pendingDoc + url). */
public struct DynamicIssuancePendingData {
    public let pendingDoc: WalletStorageDocument
    public let url: ParsedUrl
    public init(pendingDoc!: WalletStorageDocument, url!: ParsedUrl) {
        this.pendingDoc = pendingDoc
        this.url = url
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/RequestItemConvertible.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors `typealias RequestConvertibleItems = [String: [String: [RequestItem]]]`.
 * docId → nameSpace → [RequestItem].
 */
public type RequestConvertibleItems = HashMap<String, HashMap<String, Array<RequestItem>>>

/** Mirrors iOS `protocol RequestItemConvertible`. */
public interface RequestItemConvertible {
    prop items: RequestConvertibleItems
}

/** Mirrors iOS `struct RequestItemsWrapper`. */
public class RequestItemsWrapper <: RequestItemConvertible {
    private let _items: RequestConvertibleItems
    public init() { this._items = RequestConvertibleItems() }
    public init(dictionary: RequestConvertibleItems) { this._items = dictionary }
    public prop items: RequestConvertibleItems {
        get() { this._items }
    }
}
