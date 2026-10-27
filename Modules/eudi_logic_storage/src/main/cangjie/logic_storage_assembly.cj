/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/DI/LogicStorageAssembly.swift) to Cangjie.
 *
 * iOS pattern: Swinject Assembly registers StorageConfig, SwiftDataService,
 * and four StorageControllerImpl instances into a DI container.
 *
 * Cangjie/HarmonyOS has no Swinject. Following the same factory function pattern
 * established by eudi_logic_business (createPrefsController()), this file exposes
 * free factory functions for each storage controller, wiring the shared StorageConfig
 * and the concrete StorageService implementations. Callers (assembly / app shell)
 * hold the resulting controller references.
 *
 * The StorageConfig is injectable so the app shell can supply the real ability
 * context path (same pattern as PrefsControllerImpl.DEFAULT_STORAGE_DIR).
 */
package eudi_logic_storage

/** Creates a StorageConfig backed by the default HarmonyOS sandbox path. */
public func createStorageConfig(): StorageConfig {
    return StorageConfigImpl()
}

/** Creates a StorageConfig with a custom storage directory (e.g., for tests). */
public func createStorageConfig(baseDir: String): StorageConfig {
    return StorageConfigImpl(baseDir: baseDir)
}

/**
 * Mirrors iOS `container.register((any BookmarkStorageController).self)`.
 * Creates a fully wired BookmarkStorageControllerImpl.
 */
public func createBookmarkStorageController(config: StorageConfig): BookmarkStorageController {
    let service = BookmarkStorageService(config.storageDir)
    return BookmarkStorageControllerImpl(service)
}

/**
 * Mirrors iOS `container.register((any TransactionLogStorageController).self)`.
 */
public func createTransactionLogStorageController(config: StorageConfig): TransactionLogStorageController {
    let service = TransactionLogStorageService(config.storageDir)
    return TransactionLogStorageControllerImpl(service)
}

/**
 * Mirrors iOS `container.register((any RevokedDocumentStorageController).self)`.
 */
public func createRevokedDocumentStorageController(config: StorageConfig): RevokedDocumentStorageController {
    let service = RevokedDocumentStorageService(config.storageDir)
    return RevokedDocumentStorageControllerImpl(service)
}

/**
 * Mirrors iOS `container.register((any FailedReIssuedDocStorageController).self)`.
 */
public func createFailedReIssuedDocStorageController(config: StorageConfig): FailedReIssuedDocStorageController {
    let service = FailedReIssuedDocStorageService(config.storageDir)
    return FailedReIssuedDocStorageControllerImpl(service)
}
