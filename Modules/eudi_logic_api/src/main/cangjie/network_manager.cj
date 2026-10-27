/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * Ported from iOS logic-api/Sources/Core/NetworkManager.swift.
 *
 * Platform mapping:
 *   iOS URLSession          → stdx.net.http Client (via ClientBuilder.build())
 *   iOS async/await execute → synchronous execute (Client.send is blocking;
 *                             callers may wrap in spawn{} for concurrency)
 *   iOS actor isolation     → removed; NetworkManagerImpl is a plain class
 *   iOS throws NetworkError → throws NetworkException (wraps NetworkError;
 *                             Cangjie throw requires Exception subclass)
 */
package eudi_logic_api

import std.collection.HashMap
import std.io.*
import std.time.*
import stdx.net.http.*
import stdx.encoding.json.*
import stdx.encoding.url.*
import stdx.serialization.serialization.*

/**
 * High-level network gateway.
 * Mirrors iOS `protocol NetworkManager: Sendable`.
 */
public interface NetworkManager {

    /**
     * Execute an HTTP request and decode the JSON response body into T.
     * Mirrors iOS `func execute<R, T: Decodable>(with request: R, parameters: [NetworkParameter]?) async throws -> T`.
     * Throws NetworkException on transport or decode failure.
     */
    func execute<T>(request: NetworkRequest, parameters: ?Array<NetworkParameter>): T
        where T <: Serializable<T>

    /**
     * Build the full URL string from request descriptor and optional query parameters.
     * Mirrors iOS `func prepare(request: R, parameters: [NetworkParameter]?, baseHost: String) -> URLRequest`.
     */
    func prepareUrl(request: NetworkRequest, parameters: ?Array<NetworkParameter>, baseHost: String): String

    /**
     * Log request info and optional response bytes.
     * Mirrors iOS `func log(request: URLRequest, responseData: Data?)`.
     */
    func logRequest(url: String, method: String, responseData: ?Array<UInt8>): Unit
}

/**
 * Concrete implementation backed by stdx.net.http Client.
 * Mirrors iOS `actor NetworkManagerImpl`.
 */
public class NetworkManagerImpl <: NetworkManager {

    private let _client: Client

    public init(sessionProvider: NetworkSessionProvider) {
        _client = sessionProvider.httpClient
    }

    /**
     * Build the full URL: baseHost + "/" + path + optional "?key=value&..." query string.
     * Mirrors iOS URLComponents construction.
     */
    public func prepareUrl(request: NetworkRequest, parameters: ?Array<NetworkParameter>, baseHost: String): String {
        var url = baseHost
        if (!url.endsWith("/")) {
            url = url + "/"
        }
        let p = request.path
        var pathPart = p
        while (pathPart.startsWith("/")) {
            if (pathPart.size <= 1) {
                pathPart = ""
                break
            }
            pathPart = pathPart[1..pathPart.size]
        }
        url = url + pathPart

        match (parameters) {
            case Some(params) =>
                if (params.size > 0) {
                    url = url + "?"
                    var first = true
                    for (param in params) {
                        if (!first) {
                            url = url + "&"
                        }
                        url = url + URL.encodeComponent(param.key) + "=" + URL.encodeComponent(param.value)
                        first = false
                    }
                }
            case None => ()
        }
        return url
    }

    /**
     * Debug logging — mirrors iOS `nonisolated func log(request:responseData:)`.
     * Query string is dropped so tokens in the URL never reach hilog.
     */
    public func logRequest(url: String, method: String, responseData: ?Array<UInt8>): Unit {
        println("Request: " + urlWithoutQuery(url))
        println("Request Http Method: " + method)
        match (responseData) {
            case Some(data) =>
                println("Response Body size: " + data.size.toString() + " bytes")
            case None => ()
        }
    }

    private func urlWithoutQuery(url: String): String {
        let parts = url.split("?")
        if (parts.size > 0) {
            return parts[0]
        }
        return url
    }

    /**
     * Full HTTP round-trip + JSON decode.
     *
     * Flow mirrors iOS NetworkManagerImpl.execute:
     *   1. Build URL via prepareUrl
     *   2. Build HttpRequest (method, Content-Type, headers, optional body)
     *   3. Client.send(req) — synchronous blocking call
     *   4. Read response body bytes from InputStream
     *   5. logRequest
     *   6. Check HTTP status 200-299; else throw NetworkException(.httpStatus)
     *   7. JsonValue.fromStr → DataModel.fromJson → T.deserialize
     */
    public func execute<T>(request: NetworkRequest, parameters: ?Array<NetworkParameter>): T
        where T <: Serializable<T>
    {
        let url = prepareUrl(request, parameters, request.host)

        // Transport-level retry: the shared pooled client can hand out a
        // keep-alive connection the server already closed (the app idles for
        // tens of seconds during the issuance web-auth step), and the first
        // write on that stale socket fails with SocketException ECONNABORTED.
        // iOS URLSession.shared retransmits this transparently; stdx.net.http
        // does not, so re-send (fresh connection) — same policy as the
        // openid4vci http_client.cj transport-retry loop. HTTP-status and
        // decode outcomes are handled after the loop and are never retried.
        var statusCode: Int64 = 0
        var bodyBytes = Array<UInt8>(0, repeat: 0)
        var attempt = 0
        while (true) {
            try {
                var reqBuilder = HttpRequestBuilder()
                    .url(url)
                    .method(request.method.toString())
                    .header("Content-Type", "application/json")

                // Additional headers from the request descriptor
                for ((name, value) in request.additionalHeaders) {
                    reqBuilder = reqBuilder.header(name, value)
                }

                // Optional body bytes
                match (request.body) {
                    case Some(b) =>
                        reqBuilder = reqBuilder.body(b)
                    case None => ()
                }

                let resp = _client.send(reqBuilder.build())
                bodyBytes = readAllBytes(resp.body)
                statusCode = Int64(resp.status)
                break
            } catch (e: Exception) {
                attempt++
                if (attempt >= 3) {
                    throw e
                }
                println("Transport retry " + attempt.toString() + " for " + urlWithoutQuery(url) + ": " + e.message)
                sleep(Duration.millisecond * 300)
            }
        }

        // Log after data received (mirrors iOS log after session.data)
        logRequest(url, request.method.toString(), Some(bodyBytes))

        // Validate HTTP status (mirrors iOS guard statusCode in 200...299)
        if (statusCode < 200 || statusCode > 299) {
            throw NetworkException(NetworkError.httpStatus(statusCode, bodyBytes))
        }

        // Decode JSON: bytes → String → JsonValue → DataModel → T
        let bodyStr = String.fromUtf8(bodyBytes)
        let jsonValue: JsonValue
        try {
            jsonValue = JsonValue.fromStr(bodyStr)
        } catch (e: Exception) {
            throw NetworkException(NetworkError.decoding("JSON parse error: " + e.message))
        }

        let dataModel: DataModel
        try {
            dataModel = DataModel.fromJson(jsonValue)
        } catch (e: Exception) {
            throw NetworkException(NetworkError.decoding("DataModel conversion error: " + e.message))
        }

        try {
            return T.deserialize(dataModel)
        } catch (e: Exception) {
            throw NetworkException(NetworkError.decoding("Deserialization error: " + e.message))
        }
    }
}

/**
 * Read all remaining bytes from an InputStream into a single Array<UInt8>.
 * Mirrors Swift Data accumulation from URLSession data task.
 */
func readAllBytes(stream: InputStream): Array<UInt8> {
    let buf = Array<UInt8>(4096, repeat: 0)
    var result = Array<UInt8>(0, repeat: 0)
    var n = stream.read(buf)
    while (n > 0) {
        let newResult = Array<UInt8>(result.size + n, repeat: 0)
        result.copyTo(newResult, 0, 0, result.size)
        buf.copyTo(newResult, 0, result.size, n)
        result = newResult
        n = stream.read(buf)
    }
    return result
}
