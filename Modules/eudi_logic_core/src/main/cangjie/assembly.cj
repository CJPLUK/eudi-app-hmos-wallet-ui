/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/DI/LogicCoreAssembly.swift.
 *
 * iOS Swinject `Assembly` registrations → Cangjie factory functions, matching the
 * pattern already established by eudi_logic_business / eudi_logic_storage /
 * eudi_logic_api (createX / makeX free functions). Object scopes are reproduced:
 *   .container  → a single shared instance held by LogicCoreAssembly
 *   .graph/.transient → freshly built per call
 */
package eudi_logic_core

import std.collection.HashMap
import eudi_logic_business.{ConfigLogic, PrefsController}
import eudi_logic_business.KeyChainController
import eudi_logic_storage.BookmarkStorageController
import eudi_logic_storage.TransactionLogStorageController
import eudi_logic_storage.RevokedDocumentStorageController
import eudi_logic_storage.FailedReIssuedDocStorageController
import eudi_logic_api.WalletAttestationRepository
import eudi_logic_api.NetworkSessionProvider

/**
 * Mirrors iOS `LogicCoreAssembly` — assembles the core wallet object graph.
 *
 * Consumers (the app shell / feature assemblies) construct one LogicCoreAssembly,
 * supplying the cross-module dependencies the iOS container resolved from sibling
 * assemblies (ConfigLogic, the four storage controllers, the network/attestation
 * stack). The container-scoped singletons are then exposed through accessors.
 */
public class LogicCoreAssembly {
    private let configLogic: ConfigLogic
    private let prefsController: PrefsController
    private let storageDir: String

    // .container-scoped singletons (lazily built, then cached)
    private var cachedTransactionLogger: ?TransactionLogger = None
    private var cachedAttestationProvider: ?WalletKitAttestationProvider = None
    private var cachedWalletProviderAttestationConfig: ?WalletProviderAttestationConfig = None
    private var cachedWalletKitConfig: ?WalletKitConfig = None
    private var cachedDocumentRegistrationManager: ?DocumentRegistrationManager = None
    private var cachedKeyChainController: ?KeyChainController = None
    private var cachedSessionCoordinatorHolder: ?SessionCoordinatorHolder = None
    private var cachedWalletKitController: ?WalletKitController = None

    private let bookmarkStorageController: BookmarkStorageController
    private let transactionLogStorageController: TransactionLogStorageController
    private let revokedDocumentStorageController: RevokedDocumentStorageController
    private let failedReIssuedDocStorageController: FailedReIssuedDocStorageController
    private let walletAttestationRepository: WalletAttestationRepository
    private let networkSessionProvider: NetworkSessionProvider

    public init(
        configLogic: ConfigLogic,
        prefsController: PrefsController,
        storageDir: String,
        bookmarkStorageController: BookmarkStorageController,
        transactionLogStorageController: TransactionLogStorageController,
        revokedDocumentStorageController: RevokedDocumentStorageController,
        failedReIssuedDocStorageController: FailedReIssuedDocStorageController,
        walletAttestationRepository: WalletAttestationRepository,
        networkSessionProvider: NetworkSessionProvider
    ) {
        this.configLogic = configLogic
        this.prefsController = prefsController
        this.storageDir = storageDir
        this.bookmarkStorageController = bookmarkStorageController
        this.transactionLogStorageController = transactionLogStorageController
        this.revokedDocumentStorageController = revokedDocumentStorageController
        this.failedReIssuedDocStorageController = failedReIssuedDocStorageController
        this.walletAttestationRepository = walletAttestationRepository
        this.networkSessionProvider = networkSessionProvider
    }

    /** .graph TransactionLogger (one per assembly). */
    public func resolveTransactionLogger(): TransactionLogger {
        match (this.cachedTransactionLogger) {
            case Some(v) => return v
            case None =>
                let v = WalletKitTransactionLogControllerImpl(this.transactionLogStorageController)
                this.cachedTransactionLogger = v
                return v
        }
    }

    /** .container WalletProviderAttestationConfig. */
    public func resolveWalletProviderAttestationConfig(): WalletProviderAttestationConfig {
        match (this.cachedWalletProviderAttestationConfig) {
            case Some(v) => return v
            case None =>
                let v = WalletProviderAttestationConfigImpl(this.configLogic)
                this.cachedWalletProviderAttestationConfig = v
                return v
        }
    }

    /** .graph WalletKitAttestationProvider. */
    public func resolveWalletKitAttestationProvider(): WalletKitAttestationProvider {
        match (this.cachedAttestationProvider) {
            case Some(v) => return v
            case None =>
                let v = WalletKitAttestationProviderImpl(
                    repository: this.walletAttestationRepository,
                    configLogic: this.resolveWalletProviderAttestationConfig()
                )
                this.cachedAttestationProvider = v
                return v
        }
    }

    /** .container WalletKitConfig. */
    public func resolveWalletKitConfig(): WalletKitConfig {
        match (this.cachedWalletKitConfig) {
            case Some(v) => return v
            case None =>
                let v = WalletKitConfigImpl(
                    configLogic: this.configLogic,
                    transactionLogger: this.resolveTransactionLogger(),
                    walletKitAttestationProvider: this.resolveWalletKitAttestationProvider(),
                    prefsController: this.prefsController
                )
                this.cachedWalletKitConfig = v
                return v
        }
    }

    /** .container DocumentRegistrationManager (platform path = NoOp). */
    public func resolveDocumentRegistrationManager(): DocumentRegistrationManager {
        match (this.cachedDocumentRegistrationManager) {
            case Some(v) => return v
            case None =>
                let v = DocumentRegistrationManagerNoOp()
                this.cachedDocumentRegistrationManager = v
                return v
        }
    }

    /** KeyChainController (mirrors logic-business container registration). */
    public func resolveKeyChainController(): KeyChainController {
        match (this.cachedKeyChainController) {
            case Some(v) => return v
            case None =>
                let v = HuksKeyChainController(
                    service: this.configLogic.keyChainConfig.documentStorageServiceName,
                    storageDir: this.storageDir
                )
                this.cachedKeyChainController = v
                return v
        }
    }

    /** .transient SessionCoordinatorHolder (iOS registers transient; one cached
     *  holder is sufficient since the controller holds a single reference). */
    public func resolveSessionCoordinatorHolder(): SessionCoordinatorHolder {
        match (this.cachedSessionCoordinatorHolder) {
            case Some(v) => return v
            case None =>
                let v = SessionCoordinatorHolderImpl()
                this.cachedSessionCoordinatorHolder = v
                return v
        }
    }

    /** .container WalletKitController. */
    public func resolveWalletKitController(): WalletKitController {
        match (this.cachedWalletKitController) {
            case Some(v) => return v
            case None =>
                let v = WalletKitControllerImpl(
                    walletKitConfig: this.resolveWalletKitConfig(),
                    configLogic: this.configLogic,
                    keyChainController: this.resolveKeyChainController(),
                    sessionCoordinatorHolder: this.resolveSessionCoordinatorHolder(),
                    bookmarkStorageController: this.bookmarkStorageController,
                    transactionLogStorageController: this.transactionLogStorageController,
                    revokedDocumentStorageController: this.revokedDocumentStorageController,
                    failedReIssuedDocStorageController: this.failedReIssuedDocStorageController,
                    networkSessionProvider: this.networkSessionProvider,
                    documentRegistrationManager: this.resolveDocumentRegistrationManager(),
                    coordinatorFactory: SessionCoordinatorFactoryImpl()
                )
                this.cachedWalletKitController = v
                return v
        }
    }

    /** .graph RevocationWorkManager (fresh per call). */
    public func resolveRevocationWorkManager(): RevocationWorkManager {
        return RevocationWorkManagerImpl(
            configLogic: this.resolveWalletKitConfig(),
            walletKitController: this.resolveWalletKitController()
        )
    }

    /** .graph ReIssuanceWorkManager (fresh per call). */
    public func resolveReIssuanceWorkManager(): ReIssuanceWorkManager {
        return ReIssuanceWorkManagerImpl(
            configLogic: this.resolveWalletKitConfig(),
            walletKitController: this.resolveWalletKitController()
        )
    }
}
