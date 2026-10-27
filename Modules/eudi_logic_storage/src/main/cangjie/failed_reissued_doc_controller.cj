/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Controller/FailedReIssuedDocStorageController.swift) to Cangjie.
 *
 * iOS pattern: `public protocol FailedReIssuedDocStorageController: StorageController where Value == FailedReIssuedDocument`
 *              `final actor FailedReIssuedDocStorageControllerImpl: FailedReIssuedDocStorageController`
 *
 * Cangjie mapping:
 *   - actor → class (synchronous; serial isolation by design)
 *   - SwiftDataService → FailedReIssuedDocStorageService (std.fs JSON)
 */
package eudi_logic_storage

/**
 * Concrete implementation of `FailedReIssuedDocStorageController`.
 * Mirrors `FailedReIssuedDocStorageControllerImpl` from iOS.
 */
public class FailedReIssuedDocStorageControllerImpl <: FailedReIssuedDocStorageController {

    private let service: FailedReIssuedDocStorageService

    public init(service: FailedReIssuedDocStorageService) {
        this.service = service
    }

    /** Mirrors `store(_ value: FailedReIssuedDocument)`. */
    public func store(value: FailedReIssuedDocument): Unit {
        this.service.write(value)
    }

    /** Mirrors `store(_ values: [FailedReIssuedDocument])`. */
    public func store(values: Array<FailedReIssuedDocument>): Unit {
        this.service.writeAll(values)
    }

    /** Mirrors `update(_ value: FailedReIssuedDocument)`. */
    public func update(value: FailedReIssuedDocument): Unit {
        this.service.write(value)
    }

    /**
     * Mirrors `retrieve(_ identifier: String) async throws -> FailedReIssuedDocument`.
     * Throws StorageError.itemNotFound when absent.
     */
    public func retrieve(identifier: String): FailedReIssuedDocument {
        match (this.service.read(identifier)) {
            case Some(d) => return d
            case None => throw StorageError.itemNotFound()
        }
    }

    /**
     * Mirrors `retrieveAll() async throws -> [FailedReIssuedDocument]`.
     * Throws StorageError.itemsNotFound when empty.
     */
    public func retrieveAll(): Array<FailedReIssuedDocument> {
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
