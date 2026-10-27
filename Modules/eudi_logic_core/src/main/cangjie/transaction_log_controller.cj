/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Controller/WalletKitTransactionLogController.swift
 * plus the SessionCoordinator factory (iOS resolves coordinators through
 * DIGraph.shared.resolver.force(_:argument:); reproduced as an explicit factory).
 */
package eudi_logic_core

import eudi_logic_storage.TransactionLogStorageController
import eudi_logic_storage.TransactionLog as StorageTransactionLog

/**
 * Mirrors iOS `final actor WalletKitTransactionLogControllerImpl: TransactionLogger`.
 * EudiWallet calls `log(transaction:)` after each presentation; this persists the
 * JSON-encoded log through the storage controller.
 */
public class WalletKitTransactionLogControllerImpl <: TransactionLogger {
    private let transactionLogStorageController: TransactionLogStorageController

    public init(transactionLogStorageController: TransactionLogStorageController) {
        this.transactionLogStorageController = transactionLogStorageController
    }

    public func log(transaction: CoreTransactionLog): Unit {
        // iOS encode+store can throw; a failed write must not unwind the engine.
        try {
            let value = encodeCoreTransactionLog(transaction)
            this.transactionLogStorageController.store(
                StorageTransactionLog(newTransactionLogIdentifier(), value)
            )
            NotificationCenter.post(NotificationName.TransactionTabRefresh)
        } catch (_: Exception) {}
    }
}

/** JSON-encodes a CoreTransactionLog (timestamp + value). */
func encodeCoreTransactionLog(log: CoreTransactionLog): String {
    return jsonObject([
        ("timestamp", "${log.timestamp}"),
        ("value", jsonString(log.value))
    ])
}

/**
 * Mirrors the iOS `DIGraph.shared.resolver.force(ProximitySessionCoordinator.self,
 * argument: session)` resolution: a factory the controller uses to build the
 * transient session coordinators from a PresentationSession.
 */
public interface SessionCoordinatorFactory {
    func makeProximity(session: PresentationSession): ProximitySessionCoordinator
    func makeRemote(session: PresentationSession): RemoteSessionCoordinator
}

/** Default factory wiring the concrete coordinator implementations. */
public class SessionCoordinatorFactoryImpl <: SessionCoordinatorFactory {
    public init() {}
    public func makeProximity(session: PresentationSession): ProximitySessionCoordinator {
        return ProximitySessionCoordinatorImpl(session)
    }
    public func makeRemote(session: PresentationSession): RemoteSessionCoordinator {
        return RemoteSessionCoordinatorImpl(session)
    }
}
