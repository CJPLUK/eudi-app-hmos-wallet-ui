/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * Thread-safe bridge between the Cangjie authentication flows and ArkTS
 * UserAuthenticationKit. ArkTS owns the platform UI and drains commands on its
 * event loop; Cangjie callers wait on a Monitor and never retain/call a JS
 * function from a worker thread (which would raise "Thread mismatch").
 */
package eudi_feature_common

import std.collection.ArrayList
import std.sync.{Mutex, Monitor}

/** Numeric values from userAuth.UserAuthType. */
public let ARKTS_AUTH_TYPE_NONE: Int32 = 0
public let ARKTS_AUTH_TYPE_FACE: Int32 = 2
public let ARKTS_AUTH_TYPE_FINGERPRINT: Int32 = 4

/** Numeric values from userAuth.UserAuthResultCode / BusinessError. */
public let ARKTS_AUTH_SUCCESS: Int32 = 12500000
public let ARKTS_AUTH_FAIL: Int32 = 12500001
public let ARKTS_AUTH_CANCELED: Int32 = 12500003
public let ARKTS_AUTH_TIMEOUT: Int32 = 12500004
public let ARKTS_AUTH_TYPE_NOT_SUPPORTED: Int32 = 12500005
public let ARKTS_AUTH_LOCKED: Int32 = 12500009
public let ARKTS_AUTH_NOT_ENROLLED: Int32 = 12500010
public let ARKTS_AUTH_PERMISSION_DENIED: Int32 = 201

public class ArkTsBiometryBridge {
    private static let lock = Mutex()
    private static let resultMonitor = Monitor()
    private static let commands = ArrayList<String>()

    private static var authType: Int32 = ARKTS_AUTH_TYPE_NONE
    private static var availabilityCode: Int32 = ARKTS_AUTH_TYPE_NOT_SUPPORTED
    private static var nextRequestId: Int64 = 1
    private static var completedRequestId: Int64 = 0
    private static var completedResultCode: Int32 = ARKTS_AUTH_FAIL

    /** ArkTS publishes the hardware/enrolment probe before AppRoot is mounted. */
    public static func updateCapability(authKind: Int32, status: Int32): Unit {
        synchronized(ArkTsBiometryBridge.lock) {
            ArkTsBiometryBridge.authType = authKind
            ArkTsBiometryBridge.availabilityCode = status
        }
    }

    public static func currentAuthType(): Int32 {
        synchronized(ArkTsBiometryBridge.lock) { ArkTsBiometryBridge.authType }
    }

    public static func currentAvailabilityCode(): Int32 {
        synchronized(ArkTsBiometryBridge.lock) { ArkTsBiometryBridge.availabilityCode }
    }

    /** Called from a Cangjie worker; blocks only that worker until ArkTS responds. */
    public static func authenticate(): Int32 {
        var id: Int64 = 0
        synchronized(ArkTsBiometryBridge.resultMonitor) {
            id = ArkTsBiometryBridge.nextRequestId
            ArkTsBiometryBridge.nextRequestId++
        }
        ArkTsBiometryBridge.offer("AUTH|${id}")
        synchronized(ArkTsBiometryBridge.resultMonitor) {
            if (ArkTsBiometryBridge.completedRequestId < id) {
                ArkTsBiometryBridge.resultMonitor.wait(timeout: Duration.second * 120)
            }
            if (ArkTsBiometryBridge.completedRequestId < id) {
                return ARKTS_AUTH_TIMEOUT
            }
            return ArkTsBiometryBridge.completedResultCode
        }
    }

    public static func requestOpenSettings(): Unit {
        ArkTsBiometryBridge.offer("SETTINGS")
    }

    private static func offer(command: String): Unit {
        synchronized(ArkTsBiometryBridge.lock) {
            ArkTsBiometryBridge.commands.add(command)
        }
    }

    /** ArkTS calls this from its timer on the UI event loop. */
    public static func drainCommands(): String {
        synchronized(ArkTsBiometryBridge.lock) {
            let result = StringBuilder()
            var first = true
            for (command in ArkTsBiometryBridge.commands) {
                if (!first) { result.append("\n") }
                result.append(command)
                first = false
            }
            ArkTsBiometryBridge.commands.clear()
            return result.toString()
        }
    }

    /** ArkTS completes an authentication request from UserAuthInstance.onResult. */
    public static func completeAuthentication(id: Int64, resultCode: Int32): Unit {
        synchronized(ArkTsBiometryBridge.resultMonitor) {
            ArkTsBiometryBridge.completedRequestId = id
            ArkTsBiometryBridge.completedResultCode = resultCode
            ArkTsBiometryBridge.resultMonitor.notifyAll()
        }
    }
}
