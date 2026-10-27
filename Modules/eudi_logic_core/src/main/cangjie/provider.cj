/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Provider/WalletKitAttestationProvider.swift +
 * DocumentRegistrationManager/(all).swift.
 */
package eudi_logic_core

import std.collection.HashMap
import std.time.DateTime
import eudi_logic_api.WalletAttestationRepository

// ─────────────────────────────────────────────────────────────────────────────
// Provider/WalletKitAttestationProvider.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `SigningKeyProxy` (the signing key whose public JWK is attested).
 * EudiWalletKit owns the real proxy; the surface the provider touches is
 * `getPublicJWK().toDictionary()`, modelled here as the already-serialised JWK
 * key/value map the wallet engine hands to the provider.
 */
public class SigningKeyProxy {
    public let publicJwk: HashMap<String, String>
    public init(publicJwk: HashMap<String, String>) {
        this.publicJwk = publicJwk
    }
    public func getPublicJWKDictionary(): HashMap<String, String> {
        return this.publicJwk
    }
}

/** Mirrors a JOSESwift `JWK` reduced to its dictionary form. */
public class JWK {
    public let dictionary: HashMap<String, String>
    public init(dictionary: HashMap<String, String>) {
        this.dictionary = dictionary
    }
    public func toDictionary(): HashMap<String, String> {
        return this.dictionary
    }
}

/**
 * Mirrors iOS `protocol WalletKitAttestationProvider: WalletAttestationsProvider`.
 * `WalletAttestationsProvider` is the EudiWalletKit protocol the wallet engine
 * calls to obtain wallet/key attestations during issuance; its two methods are
 * exactly `getWalletAttestation` / `getKeysAttestation`.
 */
public interface WalletKitAttestationProvider {
    prop baseUrl: String
    func getWalletAttestation(signingKey: SigningKeyProxy): String
    func getKeysAttestation(keys: Array<JWK>, nonce: ?String): String
}

/** Mirrors iOS `final class WalletKitAttestationProviderImpl`. */
public class WalletKitAttestationProviderImpl <: WalletKitAttestationProvider {
    private let repository: WalletAttestationRepository
    private let _baseUrl: String

    public init(repository!: WalletAttestationRepository, configLogic!: WalletProviderAttestationConfig) {
        this.repository = repository
        this._baseUrl = configLogic.walletProviderAttestationUrl
    }

    public prop baseUrl: String {
        get() { this._baseUrl }
    }

    /**
     * Mirrors `getWalletAttestation(signingKey:)`: builds `{"jwk": <publicJWK>}`,
     * JSON-encodes it, and calls the repository's instance-attestation endpoint.
     */
    public func getWalletAttestation(signingKey: SigningKeyProxy): String {
        let jwkDict = signingKey.getPublicJWKDictionary()
        let payload = jsonObject([("jwk", jsonFromStringMap(jwkDict))])
        let encoded = utf8Bytes(payload)
        let response = this.repository.issueWalletInstanceAttestation(this._baseUrl, encoded)
        return response.walletInstanceAttestation
    }

    /**
     * Mirrors `getKeysAttestation(keys:nonce:)`: builds `{"jwkSet": {"keys": [...]}}`
     * (+ optional nonce), JSON-encodes it, and calls the unit-attestation endpoint.
     */
    public func getKeysAttestation(keys: Array<JWK>, nonce: ?String): String {
        let keysJson = jsonArray(mapJwks(keys))
        var fields = [("jwkSet", jsonObject([("keys", keysJson)]))]
        if (let Some(n) <- nonce) {
            fields = concatFields(fields, ("nonce", jsonString(n)))
        }
        let payload = jsonObject(fields)
        let encoded = utf8Bytes(payload)
        let response = this.repository.issueWalletUnitAttestation(this._baseUrl, encoded)
        return response.walletUnitAttestation
    }
}

func mapJwks(keys: Array<JWK>): Array<String> {
    let out = Array<String>(keys.size, repeat: "")
    var i = 0
    while (i < keys.size) {
        out[i] = jsonFromStringMap(keys[i].toDictionary())
        i++
    }
    return out
}

// ─────────────────────────────────────────────────────────────────────────────
// DocumentRegistrationManager/(all).swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `protocol DocumentRegistrationManager: Sendable`.
 *
 * On iOS the real implementation talks to Apple's IdentityDocumentServices (iOS
 * 26+) to register mdoc documents with the OS wallet; pre-26 it is a no-op. There
 * is no HarmonyOS equivalent of IdentityDocumentServices, so the platform-backed
 * registration is unavailable — exactly the iOS `< 26` situation — and the
 * delivered implementation is the faithful no-op the iOS source already ships for
 * that case (`DocumentRegistrationManagerNoOp`). This is behaviour-preserving for
 * every device that lacks the OS document store, not a degraded no-result path.
 */
public interface DocumentRegistrationManager {
    func addRegistration(
        mobileDocumentType: String,
        supportedAuthorityKeyIdentifiers: Array<Array<UInt8>>,
        documentIdentifier: String,
        invalidationDate: ?DateTime
    ): Unit
    func removeRegistration(documentIdentifiers: Array<String>): Unit
}

/** Mirrors iOS `DocumentRegistrationManagerNoOp` (the unavailable-platform path). */
public class DocumentRegistrationManagerNoOp <: DocumentRegistrationManager {
    public init() {}
    public func addRegistration(
        mobileDocumentType: String,
        supportedAuthorityKeyIdentifiers: Array<Array<UInt8>>,
        documentIdentifier: String,
        invalidationDate: ?DateTime
    ): Unit {
        // No-op: OS document registration services not available on this platform.
    }
    public func removeRegistration(documentIdentifiers: Array<String>): Unit {
        // No-op.
    }
}
