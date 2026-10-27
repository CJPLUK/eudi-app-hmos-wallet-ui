/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from iOS logic-storage module
 * (Sources/Config/StorageConfig.swift) to Cangjie.
 *
 * iOS StorageConfig holds SwiftData ModelConfiguration (schema version, DB URL etc.).
 * On Cangjie/HarmonyOS there is no SwiftData; persistence uses std.fs JSON files,
 * one per entity type (bookmarks.json, transaction_logs.json, etc.).
 * StorageConfig is simplified to carry the storage directory path and database name,
 * mirroring the intent of iOS databaseFolder + databaseName fields.
 */
package eudi_logic_storage

/** Mirrors iOS `StorageConfig` protocol (schema-related fields simplified for std.fs). */
public interface StorageConfig {
    /** Mirrors `schemaVersion`. */
    prop schemaVersion: UInt64
    /** Mirrors `databaseName`. */
    prop databaseName: String
    /** Mirrors `databaseFolder`. */
    prop databaseFolder: String
    /** Resolved absolute path to the storage directory. Mirrors intent of `storeURL`. */
    prop storageDir: String
}

/**
 * Mirrors iOS `StorageConfigImpl`.
 * The storage directory defaults to the HarmonyOS app sandbox files path;
 * it is injectable so callers can override in tests or when the ability context
 * provides a concrete path (same pattern as PrefsControllerImpl.DEFAULT_STORAGE_DIR).
 */
public class StorageConfigImpl <: StorageConfig {

    public static let DEFAULT_BASE_DIR = "/data/storage/el2/base/haps/entry/files"

    private let _baseDir: String

    public init(baseDir!: String = DEFAULT_BASE_DIR) {
        this._baseDir = baseDir
    }

    public prop schemaVersion: UInt64 {
        get() { 1 }
    }

    public prop databaseName: String {
        get() { "eudi_wallet" }
    }

    public prop databaseFolder: String {
        get() { "Storage" }
    }

    public prop storageDir: String {
        get() { "${this._baseDir}/${this.databaseFolder}" }
    }
}
