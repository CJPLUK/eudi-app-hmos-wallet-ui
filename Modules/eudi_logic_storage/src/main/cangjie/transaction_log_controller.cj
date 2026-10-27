/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Controller/TransactionLogStorageController.swift) to Cangjie.
 *
 * iOS pattern: `public protocol TransactionLogStorageController: StorageController where Value == TransactionLog`
 *              `final actor TransactionLogStorageControllerImpl: TransactionLogStorageController`
 *
 * Cangjie mapping:
 *   - actor → class (synchronous; serial isolation by design)
 *   - SwiftDataService → TransactionLogStorageService (std.fs JSON)
 */
package eudi_logic_storage

/**
 * Concrete implementation of `TransactionLogStorageController`.
 * Mirrors `TransactionLogStorageControllerImpl` from iOS.
 */
public class TransactionLogStorageControllerImpl <: TransactionLogStorageController {

    private let service: TransactionLogStorageService

    public init(service: TransactionLogStorageService) {
        this.service = service
    }

    /** Mirrors `store(_ value: TransactionLog)`. */
    public func store(value: TransactionLog): Unit {
        this.service.write(value)
    }

    /** Mirrors `store(_ values: [TransactionLog])`. */
    public func store(values: Array<TransactionLog>): Unit {
        this.service.writeAll(values)
    }

    /** Mirrors `update(_ value: TransactionLog)`. */
    public func update(value: TransactionLog): Unit {
        this.service.write(value)
    }

    /**
     * Mirrors `retrieve(_ identifier: String) async throws -> TransactionLog`.
     * Throws StorageError.itemNotFound when absent.
     */
    public func retrieve(identifier: String): TransactionLog {
        match (this.service.read(identifier)) {
            case Some(l) => return l
            case None => throw StorageError.itemNotFound()
        }
    }

    /**
     * Mirrors `retrieveAll() async throws -> [TransactionLog]`.
     * Throws StorageError.itemsNotFound when empty.
     */
    public func retrieveAll(): Array<TransactionLog> {
        let items = this.service.readAll()
        if (items.size == 0) {
            throw StorageError.itemsNotFound()
        }
        return items
    }

    /** Mirrors `delete(_ identifier: String)`. */
    public func delete(identifier: String): Unit {
        this.service.delete(identifier)
    }

    /** Mirrors `deleteAll()`. */
    public func deleteAll(): Unit {
        this.service.deleteAll()
    }
}
