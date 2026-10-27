/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Model/{Bookmark,TransactionLog,RevokedDocument,FailedReIssuedDocument}.swift)
 * to Cangjie.
 *
 * iOS pattern: each model file defines a `public struct` (the domain model) +
 * a `@Model final class SD*` (the SwiftData persistence class) plus extension
 * conversion helpers. On Cangjie/HarmonyOS there is no SwiftData; persistence is
 * handled by StorageService (std.fs JSON). Therefore only the public domain structs
 * are needed here. Conversion helpers (toSdModel / toBookmark etc.) become internal
 * JSON serialisation/deserialisation logic inside StorageService.
 */
package eudi_logic_storage

// ─────────────────────────────────────────────────────────────────────────────
// Bookmark  (mirrors iOS Bookmark struct)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `public struct Bookmark: Sendable`. */
public struct Bookmark {
    public let identifier: String

    public init(identifier: String) {
        this.identifier = identifier
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// TransactionLog  (mirrors iOS TransactionLog struct)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `public struct TransactionLog: Sendable`. */
public struct TransactionLog {
    public let identifier: String
    public let value: String

    public init(identifier: String, value: String) {
        this.identifier = identifier
        this.value = value
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RevokedDocument  (mirrors iOS RevokedDocument struct)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `public struct RevokedDocument: Sendable`. */
public struct RevokedDocument {
    public let identifier: String

    public init(identifier: String) {
        this.identifier = identifier
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FailedReIssuedDocument  (mirrors iOS FailedReIssuedDocument struct)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `public struct FailedReIssuedDocument: Sendable`. */
public struct FailedReIssuedDocument {
    public let identifier: String

    public init(identifier: String) {
        this.identifier = identifier
    }
}
