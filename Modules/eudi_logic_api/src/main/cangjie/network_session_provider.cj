/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Provider/NetworkSessionProvider.swift.
 * iOS `URLSession` is replaced with stdx.net.http `ClientBuilder`/`HttpClient`.
 */
package eudi_logic_api

import std.time.*
import stdx.net.http.*
import stdx.net.tls.TlsClientConfig

/**
 * Provides a configured HTTP client for the network layer.
 * Mirrors iOS `protocol NetworkSessionProvider: Sendable`.
 * iOS exposes `urlSession: URLSession`; Cangjie exposes `httpClient: Client`
 * (stdx.net.http.Client returned by ClientBuilder.build()).
 */
public interface NetworkSessionProvider {
    prop httpClient: Client
}

/**
 * Default implementation using stdx.net.http ClientBuilder with default settings.
 * Mirrors iOS `final class NetworkSessionProviderImpl` (using URLSession.shared).
 */
public class NetworkSessionProviderImpl <: NetworkSessionProvider {

    private let _client: Client

    public init() {
        // HTTPS requires an explicit TLS config or stdx throws
        // "TLS must be configured when HTTPS requests are sent."
        // Default TlsClientConfig verifies against the system cert store.
        // Bounded timeouts so a black-holed connection fails fast and the
        // NetworkManager transport-retry loop can re-send (same bounds as the
        // openid4vci http_client.cj clients).
        _client = ClientBuilder()
            .tlsConfig(TlsClientConfig())
            .readTimeout(Duration.second * 45)
            .writeTimeout(Duration.second * 30)
            .build()
    }

    public prop httpClient: Client {
        get() { _client }
    }
}
