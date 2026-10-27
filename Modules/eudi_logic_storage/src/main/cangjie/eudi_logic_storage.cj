/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * eudi_logic_storage — Cangjie HAR. Provides persistent storage for the EUDI
 * HarmonyOS wallet. Migrated from iOS logic-storage (SwiftData) to std.fs JSON
 * file persistence following the PrefsControllerImpl pattern.
 *
 * Public surface:
 *   Models:      Bookmark, TransactionLog, RevokedDocument, FailedReIssuedDocument
 *   Interfaces:  BookmarkStorageController, TransactionLogStorageController,
 *                RevokedDocumentStorageController, FailedReIssuedDocStorageController,
 *                StorageConfig
 *   Error:       StorageError
 *   Factories:   createStorageConfig(), createBookmarkStorageController(),
 *                createTransactionLogStorageController(),
 *                createRevokedDocumentStorageController(),
 *                createFailedReIssuedDocStorageController()
 */
package eudi_logic_storage
