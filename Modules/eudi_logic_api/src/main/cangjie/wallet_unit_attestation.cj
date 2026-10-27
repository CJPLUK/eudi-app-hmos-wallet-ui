/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Model/Response/WalletUnitAttestation.swift.
 * iOS `Decodable` → Cangjie `Serializable<T>` (stdx.serialization).
 */
package eudi_logic_api

import stdx.serialization.serialization.*

/**
 * Response model for the wallet Key Attestation endpoint.
 * Mirrors iOS `public struct WalletKeyAttestation: Sendable, Decodable`
 * (renamed from WalletUnitAttestation, app commit b3f9259b 2026-07-06).
 *
 * JSON shape: { "keyAttestation": "<jwt-string>" }
 * (The wire field moved wallet-unit-attestation → key-attestation; the local
 * `walletUnitAttestation` property name is retained to limit churn.)
 */
public class WalletUnitAttestation <: Serializable<WalletUnitAttestation> {

    public let walletUnitAttestation: String

    public init(walletUnitAttestation: String) {
        this.walletUnitAttestation = walletUnitAttestation
    }

    /**
     * Serialize to DataModel.
     */
    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<String>("keyAttestation", walletUnitAttestation))
    }

    /**
     * Deserialize from DataModel (mirrors Swift `init(from decoder: Decoder)`).
     */
    public static func deserialize(dm: DataModel): WalletUnitAttestation {
        let dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("WalletUnitAttestation: expected DataModelStruct")
        }
        let attestation = String.deserialize(dms.get("keyAttestation"))
        return WalletUnitAttestation(attestation)
    }
}
