/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Core/NetworkRequest.swift and NetworkParameter.swift.
 */
package eudi_logic_api

import std.collection.HashMap

/**
 * HTTP method enum.
 * Mirrors iOS `enum NetworkMethod: String`.
 */
public enum NetworkMethod <: ToString {
    | GET
    | POST
    | PUT
    | DELETE
    | PATCH

    public func toString(): String {
        match (this) {
            case GET => "GET"
            case POST => "POST"
            case PUT => "PUT"
            case DELETE => "DELETE"
            case PATCH => "PATCH"
        }
    }
}

/**
 * Describes an HTTP request (path, host, method, headers, optional body).
 * Mirrors iOS `protocol NetworkRequest: Sendable`.
 * Note: iOS uses `associatedtype Response` — Cangjie does not support associated types on
 * interfaces; response type is resolved generically at the call site (NetworkManagerImpl.execute).
 */
public interface NetworkRequest {
    prop method: NetworkMethod
    prop path: String
    prop host: String
    prop additionalHeaders: HashMap<String, String>
    prop body: ?Array<UInt8>
}

/**
 * A single query-string parameter (key + value).
 * Mirrors iOS `struct NetworkParameter`.
 */
public struct NetworkParameter {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        this.key = key
        this.value = value
    }
}
