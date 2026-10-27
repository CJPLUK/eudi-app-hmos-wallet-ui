/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Model/Response/WalletInstanceAttestation.swift.
 * iOS `Decodable` → Cangjie `Serializable<T>` (stdx.serialization).
 */
package eudi_logic_api

import stdx.serialization.serialization.*

/**
 * Response model for the Wallet Instance Attestation endpoint.
 * Mirrors iOS `public struct WalletInstanceAttestation: Sendable, Decodable`.
 *
 * JSON shape: { "walletInstanceAttestation": "<jwt-string>" }
 */
public class WalletInstanceAttestation <: Serializable<WalletInstanceAttestation> {

    public let walletInstanceAttestation: String

    public init(walletInstanceAttestation: String) {
        this.walletInstanceAttestation = walletInstanceAttestation
    }

    /**
     * Serialize to DataModel (mirrors Swift Encodable, provided for completeness).
     */
    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<String>("walletInstanceAttestation", walletInstanceAttestation))
    }

    /**
     * Deserialize from DataModel (mirrors Swift `init(from decoder: Decoder)`).
     */
    public static func deserialize(dm: DataModel): WalletInstanceAttestation {
        let dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("WalletInstanceAttestation: expected DataModelStruct")
        }
        let attestation = String.deserialize(dms.get("walletInstanceAttestation"))
        return WalletInstanceAttestation(attestation)
    }
}
