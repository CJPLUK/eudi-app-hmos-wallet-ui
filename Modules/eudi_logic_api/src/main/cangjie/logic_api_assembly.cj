/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/DI/LogicApiAssembly.swift.
 * iOS Swinject `Assembly` → Cangjie factory functions.
 */
package eudi_logic_api

/**
 * Factory: create a default NetworkSessionProvider.
 * Mirrors iOS: container.register(NetworkSessionProvider.self) { _ in NetworkSessionProviderImpl() }
 */
public func makeNetworkSessionProvider(): NetworkSessionProvider {
    return NetworkSessionProviderImpl()
}

/**
 * Factory: create a NetworkManager backed by the given session provider.
 * Mirrors iOS: container.register(NetworkManager.self) { r in
 *     NetworkManagerImpl(with: r.force(NetworkSessionProvider.self)) }
 */
public func makeNetworkManager(sessionProvider: NetworkSessionProvider): NetworkManager {
    return NetworkManagerImpl(sessionProvider)
}

/**
 * Factory: create a WalletAttestationRepository backed by the given network manager.
 * Mirrors iOS: container.register(WalletAttestationRepository.self) { r in
 *     WalletAttestationRepositoryImpl(networkManager: r.force(NetworkManager.self)) }
 */
public func makeWalletAttestationRepository(networkManager: NetworkManager): WalletAttestationRepository {
    return WalletAttestationRepositoryImpl(networkManager)
}

/**
 * Convenience: assemble the full default network stack in one call.
 */
public func makeDefaultWalletAttestationRepository(): WalletAttestationRepository {
    let sessionProvider = makeNetworkSessionProvider()
    let networkManager = makeNetworkManager(sessionProvider)
    return makeWalletAttestationRepository(networkManager)
}
