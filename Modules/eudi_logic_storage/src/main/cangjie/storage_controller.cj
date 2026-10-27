/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-storage module
 * (Sources/Type/StorageController.swift + Sources/Error/StorageError.swift) to Cangjie.
 *
 * iOS uses a generic protocol with associated type `Value: Sendable`.
 * Cangjie has no associated types on interfaces; each concrete controller interface
 * declares its concrete Value type explicitly (matching the iOS where-clause pattern).
 *
 * iOS `actor` is replaced by plain `class`; serial isolation is achieved by keeping
 * all I/O calls synchronous (the std.fs write-through in StorageService serialises
 * naturally on the call stack). No concurrency primitives are needed for the emulator
 * target, matching the iOS actor's single-threaded serial execution guarantee.
 */
package eudi_logic_storage

import eudi_logic_resources.LocalizableManager
import eudi_logic_resources.LocalizableStringKey

// ─────────────────────────────────────────────────────────────────────────────
// StorageError  (mirrors iOS StorageError enum + LocalizedError)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `StorageError`.
 * `itemNotFound` — a single requested item was absent.
 * `itemsNotFound` — retrieveAll found no items.
 */
public class StorageError <: Exception {

    public init(msg: String) {
        super(msg)
    }

    /** Factory: mirrors `StorageError.itemNotFound`. */
    public static func itemNotFound(): StorageError {
        return StorageError(LocalizableManager.get(LocalizableStringKey.itemNotFoundInStorage))
    }

    /** Factory: mirrors `StorageError.itemsNotFound`. */
    public static func itemsNotFound(): StorageError {
        return StorageError(LocalizableManager.get(LocalizableStringKey.itemsNotFoundInStorage))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// StorageController  (mirrors iOS generic StorageController protocol)
//
// Because Cangjie interfaces cannot declare associated types, we define
// one interface per concrete Value type (mirroring the iOS `where Value == X`
// protocol refinements in each concrete controller file).
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `BookmarkStorageController: StorageController where Value == Bookmark`. */
public interface BookmarkStorageController {
    func store(value: Bookmark): Unit
    func store(values: Array<Bookmark>): Unit
    func update(value: Bookmark): Unit
    func retrieve(identifier: String): Bookmark
    func retrieveAll(): Array<Bookmark>
    func delete(identifier: String): Unit
    func deleteAll(): Unit
}

/** Mirrors iOS `TransactionLogStorageController: StorageController where Value == TransactionLog`. */
public interface TransactionLogStorageController {
    func store(value: TransactionLog): Unit
    func store(values: Array<TransactionLog>): Unit
    func update(value: TransactionLog): Unit
    func retrieve(identifier: String): TransactionLog
    func retrieveAll(): Array<TransactionLog>
    func delete(identifier: String): Unit
    func deleteAll(): Unit
}

/** Mirrors iOS `RevokedDocumentStorageController: StorageController where Value == RevokedDocument`. */
public interface RevokedDocumentStorageController {
    func store(value: RevokedDocument): Unit
    func store(values: Array<RevokedDocument>): Unit
    func update(value: RevokedDocument): Unit
    func retrieve(identifier: String): RevokedDocument
    func retrieveAll(): Array<RevokedDocument>
    func delete(identifier: String): Unit
    func deleteAll(): Unit
}

/** Mirrors iOS `FailedReIssuedDocStorageController: StorageController where Value == FailedReIssuedDocument`. */
public interface FailedReIssuedDocStorageController {
    func store(value: FailedReIssuedDocument): Unit
    func store(values: Array<FailedReIssuedDocument>): Unit
    func update(value: FailedReIssuedDocument): Unit
    func retrieve(identifier: String): FailedReIssuedDocument
    func retrieveAll(): Array<FailedReIssuedDocument>
    func delete(identifier: String): Unit
    func deleteAll(): Unit
}
