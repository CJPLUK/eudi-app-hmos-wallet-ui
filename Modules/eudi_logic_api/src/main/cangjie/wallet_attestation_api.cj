/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Api/WalletAttestationApi.swift.
 */
package eudi_logic_api

import std.collection.HashMap

/**
 * API descriptor for the Wallet Instance Attestation endpoint.
 * Mirrors iOS `struct WalletInstanceAttestationApi: NetworkRequest`.
 * iOS `typealias Response = WalletInstanceAttestation` is resolved generically at call site.
 */
public class WalletInstanceAttestationApi <: NetworkRequest {

    public prop method: NetworkMethod { get() { NetworkMethod.POST } }
    public prop path: String { get() { "wallet-instance-attestation/jwk" } }
    public prop host: String { get() { _host } }
    public prop additionalHeaders: HashMap<String, String> { get() { HashMap<String, String>() } }
    public prop body: ?Array<UInt8> { get() { Some(_request) } }

    private let _request: Array<UInt8>
    private let _host: String

    public init(request: Array<UInt8>, host: String) {
        _request = request
        _host = host
    }
}

/**
 * API descriptor for the Wallet Unit Attestation endpoint.
 * Mirrors iOS `struct WalletUnitAttestationApi: NetworkRequest`.
 */
public class WalletUnitAttestationApi <: NetworkRequest {

    public prop method: NetworkMethod { get() { NetworkMethod.POST } }
    public prop path: String { get() { "key-attestation/jwk-set" } }
    public prop host: String { get() { _host } }
    public prop additionalHeaders: HashMap<String, String> { get() { HashMap<String, String>() } }
    public prop body: ?Array<UInt8> { get() { Some(_request) } }

    private let _request: Array<UInt8>
    private let _host: String

    public init(request: Array<UInt8>, host: String) {
        _request = request
        _host = host
    }
}
