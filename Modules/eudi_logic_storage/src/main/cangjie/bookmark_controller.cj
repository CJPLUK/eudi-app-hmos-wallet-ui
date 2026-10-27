/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Controller/BookmarkStorageController.swift) to Cangjie.
 *
 * iOS pattern: `public protocol BookmarkStorageController: StorageController where Value == Bookmark`
 *              `final actor BookmarkStorageControllerImpl: BookmarkStorageController`
 *
 * Cangjie mapping:
 *   - Protocol → interface BookmarkStorageController (declared in storage_controller.cj)
 *   - actor → class (synchronous; serial isolation by design — single-threaded emulator)
 *   - SwiftDataService calls → BookmarkStorageService (std.fs JSON)
 *   - throws StorageError.itemNotFound / .itemsNotFound on lookup failures
 */
package eudi_logic_storage

/**
 * Concrete implementation of `BookmarkStorageController`.
 * Mirrors `BookmarkStorageControllerImpl` from iOS.
 */
public class BookmarkStorageControllerImpl <: BookmarkStorageController {

    private let service: BookmarkStorageService

    public init(service: BookmarkStorageService) {
        this.service = service
    }

    /** Mirrors `store(_ value: Bookmark)`. */
    public func store(value: Bookmark): Unit {
        this.service.write(value)
    }

    /** Mirrors `store(_ values: [Bookmark])`. */
    public func store(values: Array<Bookmark>): Unit {
        this.service.writeAll(values)
    }

    /** Mirrors `update(_ value: Bookmark)` — write-through overwrites by identifier. */
    public func update(value: Bookmark): Unit {
        this.service.write(value)
    }

    /**
     * Mirrors `retrieve(_ identifier: String) async throws -> Bookmark`.
     * Throws StorageError.itemNotFound when the identifier is absent.
     */
    public func retrieve(identifier: String): Bookmark {
        match (this.service.read(identifier)) {
            case Some(b) => return b
            case None => throw StorageError.itemNotFound()
        }
    }

    /**
     * Mirrors `retrieveAll() async throws -> [Bookmark]`.
     * Throws StorageError.itemsNotFound when the store is empty.
     */
    public func retrieveAll(): Array<Bookmark> {
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
