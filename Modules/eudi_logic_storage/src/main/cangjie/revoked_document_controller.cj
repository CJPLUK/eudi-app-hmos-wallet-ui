/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Controller/RevokedDocumentStorageController.swift) to Cangjie.
 *
 * iOS pattern: `public protocol RevokedDocumentStorageController: StorageController where Value == RevokedDocument`
 *              `final actor RevokedDocumentStorageControllerImpl: RevokedDocumentStorageController`
 *
 * Cangjie mapping:
 *   - actor → class (synchronous; serial isolation by design)
 *   - SwiftDataService → RevokedDocumentStorageService (std.fs JSON)
 */
package eudi_logic_storage

/**
 * Concrete implementation of `RevokedDocumentStorageController`.
 * Mirrors `RevokedDocumentStorageControllerImpl` from iOS.
 */
public class RevokedDocumentStorageControllerImpl <: RevokedDocumentStorageController {

    private let service: RevokedDocumentStorageService

    public init(service: RevokedDocumentStorageService) {
        this.service = service
    }

    /** Mirrors `store(_ value: RevokedDocument)`. */
    public func store(value: RevokedDocument): Unit {
        this.service.write(value)
    }

    /** Mirrors `store(_ values: [RevokedDocument])`. */
    public func store(values: Array<RevokedDocument>): Unit {
        this.service.writeAll(values)
    }

    /** Mirrors `update(_ value: RevokedDocument)`. */
    public func update(value: RevokedDocument): Unit {
        this.service.write(value)
    }

    /**
     * Mirrors `retrieve(_ identifier: String) async throws -> RevokedDocument`.
     * Throws StorageError.itemNotFound when absent.
     */
    public func retrieve(identifier: String): RevokedDocument {
        match (this.service.read(identifier)) {
            case Some(d) => return d
            case None => throw StorageError.itemNotFound()
        }
    }

    /**
     * Mirrors `retrieveAll() async throws -> [RevokedDocument]`.
     * Throws StorageError.itemsNotFound when empty.
     */
    public func retrieveAll(): Array<RevokedDocument> {
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
