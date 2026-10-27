/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Error/NetworkError.swift to Cangjie.
 */
package eudi_logic_api

/**
 * Network-layer errors.
 * Mirrors iOS `enum NetworkError: Error`.
 * - invalidResponse: response is not a valid HTTP response
 * - httpStatus(code, data): non-2xx HTTP status code received
 * - decoding(message): JSON decoding / deserialisation failure
 *
 * Cangjie requires `throw` targets to extend Exception.
 * NetworkError wraps itself in NetworkException for throw sites.
 */
public enum NetworkError <: ToString {
    | invalidResponse
    | httpStatus(Int64, Array<UInt8>)
    | decoding(String)

    public func toString(): String {
        match (this) {
            case invalidResponse => "NetworkError.invalidResponse"
            case httpStatus(code, _) => "NetworkError.httpStatus(${code})"
            case decoding(msg) => "NetworkError.decoding(${msg})"
        }
    }
}

/**
 * Exception wrapper for NetworkError so it can be used with `throw`.
 * Cangjie requires thrown types to extend Exception.
 */
public class NetworkException <: Exception {
    public let networkError: NetworkError

    public init(error: NetworkError) {
        super(error.toString())
        this.networkError = error
    }
}
