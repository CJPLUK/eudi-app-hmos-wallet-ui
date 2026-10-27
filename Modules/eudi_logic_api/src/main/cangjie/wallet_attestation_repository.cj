/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Repository/WalletAttestationRepository.swift.
 */
package eudi_logic_api

/**
 * Repository for wallet attestation operations.
 * Mirrors iOS `public protocol WalletAttestationRepository: Sendable`.
 */
public interface WalletAttestationRepository {
    /**
     * Issue a Wallet Unit Attestation by calling the remote API.
     * Mirrors iOS `func issueWalletUnitAttestation(host: String, payload: Data) async throws -> WalletUnitAttestation`.
     * Throws NetworkException on failure.
     */
    func issueWalletUnitAttestation(host: String, payload: Array<UInt8>): WalletUnitAttestation

    /**
     * Issue a Wallet Instance Attestation by calling the remote API.
     * Mirrors iOS `func issueWalletInstanceAttestation(host: String, payload: Data) async throws -> WalletInstanceAttestation`.
     * Throws NetworkException on failure.
     */
    func issueWalletInstanceAttestation(host: String, payload: Array<UInt8>): WalletInstanceAttestation
}

/**
 * Concrete repository implementation.
 * Mirrors iOS `final class WalletAttestationRepositoryImpl: WalletAttestationRepository`.
 */
public class WalletAttestationRepositoryImpl <: WalletAttestationRepository {

    private let networkManager: NetworkManager

    public init(networkManager: NetworkManager) {
        this.networkManager = networkManager
    }

    /**
     * Delegates to networkManager.execute with WalletUnitAttestationApi descriptor.
     * Mirrors iOS:
     *   try await networkManager.execute(with: WalletUnitAttestationApi(request: payload, host: host), parameters: nil)
     */
    public func issueWalletUnitAttestation(host: String, payload: Array<UInt8>): WalletUnitAttestation {
        let api = WalletUnitAttestationApi(payload, host)
        return networkManager.execute<WalletUnitAttestation>(api, None)
    }

    /**
     * Delegates to networkManager.execute with WalletInstanceAttestationApi descriptor.
     * Mirrors iOS:
     *   try await networkManager.execute(with: WalletInstanceAttestationApi(request: payload, host: host), parameters: nil)
     */
    public func issueWalletInstanceAttestation(host: String, payload: Array<UInt8>): WalletInstanceAttestation {
        let api = WalletInstanceAttestationApi(payload, host)
        return networkManager.execute<WalletInstanceAttestation>(api, None)
    }
}
