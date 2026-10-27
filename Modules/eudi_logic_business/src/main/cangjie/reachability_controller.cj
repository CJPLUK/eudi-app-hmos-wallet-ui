/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Controller/ReachabilityController.swift) to Cangjie.
 *
 * Internet: report reachable so issuance / OpenID4VP keep working (same
 * observable result as a satisfied NWPath).
 *
 * BLE: iOS observes BluetoothKit's `BKAvailability` and maps it to
 * `Reachability.BleAvailibity`. HarmonyOS splits that signal in two real parts:
 *  - the runtime `ohos.permission.ACCESS_BLUETOOTH` grant (AtManager) — the
 *    iOS `.unauthorized` cause. It is requested on demand from the proximity
 *    entry path (Home → Authenticate → In person), the way the camera scanner
 *    asks for CAMERA;
 *  - the radio state. The Cangjie SDK ships no `ohos.bluetooth.access`
 *    binding (no `getState()`), so the radio is probed with the cheapest
 *    ConnectivityKit BLE operation that reports it: `createGattServer()` +
 *    `close()`, whose BusinessException codes carry the cause (2900003
 *    Bluetooth disabled → poweredOff, 201 → unauthorized, 801 → unsupported).
 * `openBleSettings` deep-links into the system Bluetooth settings page.
 *
 * Structural note (deliberate deviation from iOS): iOS keeps
 * ReachabilityControllerImpl in logic-business. This module is host-runnable
 * (run_tests.sh HOST_MODULES compiles it for darwin), so the device-only
 * implementation — AtManager permission prompt, Want settings deep link —
 * lives in `entry` (reachability_impl.cj), the same split biometry uses
 * (interface here, device impl outside the host set). This file keeps the
 * platform-free halves: enums, state mappings, the ArkTS state bridge and the
 * ReachabilityController interface.
 */
package eudi_logic_business

/** The runtime permission the BLE proximity flow needs (module.json5 requestPermissions). */
public const BLE_PERMISSION: String = "ohos.permission.ACCESS_BLUETOOTH"

/** Mirrors iOS `Reachability.BleAvailibity` (flattened; Cangjie has no nested types). */
public enum BleAvailibity <: ToString & Equatable<BleAvailibity> {
    | available
    | noPermission
    | disabled
    | unavailable

    public prop rawValue: String {
        get() {
            match (this) {
                case available => "available"
                case noPermission => "noPermission"
                case disabled => "disabled"
                case unavailable => "unavailable"
            }
        }
    }

    public func toString(): String {
        return this.rawValue
    }

    public operator func ==(other: BleAvailibity): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: BleAvailibity): Bool {
        return !(this == other)
    }
}

/**
 * Mirrors iOS BluetoothKit `BKAvailability` / `BKUnavailabilityCause`
 * flattened into one enum: the raw radio + permission signal that
 * `mapBleAvailability` turns into the iOS `BleAvailibity`.
 */
public enum BleRadioState <: ToString & Equatable<BleRadioState> {
    /** `BKAvailability.available` — radio on. */
    | poweredOn
    /** `.unavailable(cause: .poweredOff)` — radio switched off. */
    | poweredOff
    /** `.unavailable(cause: .resetting)` — radio turning on/off. */
    | resetting
    /** `.unavailable(cause: .unsupported)` — no BLE capability. */
    | unsupported
    /** `.unavailable(cause: .unauthorized)` — ACCESS_BLUETOOTH not granted. */
    | unauthorized
    /** `.unavailable(cause: .any)` / nil availability — state unreadable. */
    | unknown

    public prop rawValue: String {
        get() {
            match (this) {
                case poweredOn => "poweredOn"
                case poweredOff => "poweredOff"
                case resetting => "resetting"
                case unsupported => "unsupported"
                case unauthorized => "unauthorized"
                case unknown => "unknown"
            }
        }
    }

    public func toString(): String {
        return this.rawValue
    }

    public operator func ==(other: BleRadioState): Bool {
        return this.rawValue == other.rawValue
    }

    public operator func !=(other: BleRadioState): Bool {
        return !(this == other)
    }
}

/**
 * Authoritative Bluetooth adapter state supplied by the ArkTS
 * `ohos.bluetooth.access` API. The Cangjie ConnectivityKit currently exposes
 * GATT but not `access.getState()`, so entry installs this tiny reader bridge.
 *
 * Keeping the adapter-state query separate from GATT setup is important:
 * `createGattServer`/`close` may fail for service/runtime reasons while the
 * radio is already on. iOS makes the same separation through BKAvailability.
 */
public class BluetoothStateBridge {
    private static var reader: ?() -> Int32 = None
    private static var latestRawState: ?Int32 = None

    public static func setReader(reader: () -> Int32): Unit {
        BluetoothStateBridge.reader = Some(reader)
    }

    /** Called by the ArkTS stateChange observer. */
    public static func update(rawState: Int32): Unit {
        BluetoothStateBridge.latestRawState = Some(rawState)
        println("[eudi_logic_business] BluetoothStateBridge: state=${rawState}")
    }

    public static func read(): BleRadioState {
        match (BluetoothStateBridge.reader) {
            case Some(readState) =>
                try {
                    let raw = readState()
                    BluetoothStateBridge.latestRawState = Some(raw)
                    return bleRadioStateFromRawState(raw)
                } catch (e: Exception) {
                    println("[eudi_logic_business] BluetoothStateBridge: getState failed: ${e.message}")
                }
            case None => ()
        }
        return match (BluetoothStateBridge.latestRawState) {
            case Some(raw) => bleRadioStateFromRawState(raw)
            case None => BleRadioState.unknown
        }
    }
}

/** Maps `ohos.bluetooth.access.BluetoothState` numeric values. */
public func bleRadioStateFromRawState(rawState: Int32): BleRadioState {
    match (rawState) {
        case 0 => BleRadioState.poweredOff
        case 2 => BleRadioState.poweredOn
        // BLE-only mode is sufficient for ISO 18013-5 proximity.
        case 5 => BleRadioState.poweredOn
        case 1 => BleRadioState.resetting
        case 3 => BleRadioState.resetting
        case 4 => BleRadioState.resetting
        case 6 => BleRadioState.resetting
        case _ => BleRadioState.unknown
    }
}

/** Mirrors iOS `ReachabilityControllerImpl.mapAvailability(_:)`. */
public func mapBleAvailability(state: BleRadioState): BleAvailibity {
    match (state) {
        case poweredOn => BleAvailibity.available
        case poweredOff => BleAvailibity.disabled
        case unauthorized => BleAvailibity.noPermission
        case resetting => BleAvailibity.unavailable
        case unsupported => BleAvailibity.unavailable
        case unknown => BleAvailibity.unavailable
    }
}

/**
 * Maps a ConnectivityKit BusinessException code raised by the radio probe to
 * the radio state it implies: 201 permission denied → unauthorized, 801
 * capability not supported → unsupported, 2900003 Bluetooth disabled →
 * poweredOff; anything else (2900001 service stopped, 2900099 operation
 * failed, ...) → unknown.
 */
public func bleRadioStateFromErrorCode(code: Int32): BleRadioState {
    match (code) {
        case 201 => BleRadioState.unauthorized
        case 801 => BleRadioState.unsupported
        case 2900003 => BleRadioState.poweredOff
        case _ => BleRadioState.unknown
    }
}

/** True when every entry of a `PermissionRequestResult.authResults` is 0 (granted). */
public func allPermissionsGranted(authResults: Array<Int32>): Bool {
    if (authResults.isEmpty()) {
        return false
    }
    for (r in authResults) {
        if (r != 0) {
            return false
        }
    }
    return true
}

/** Read adapter state without creating or closing a GATT server. */
public func probeBleRadio(): BleRadioState {
    return BluetoothStateBridge.read()
}

/** Mirrors the iOS `ReachabilityController` protocol. */
public interface ReachabilityController {
    /** Mirrors `hasInternet()`. */
    func hasInternet(): Bool
    /**
     * Replaces the Combine publisher: delivers one availability value to the
     * callback. The delivery is asynchronous when the ACCESS_BLUETOOTH runtime
     * permission dialog has to be shown first; otherwise it is synchronous.
     */
    func getBleAvailibity(callback: (BleAvailibity) -> Unit): Unit
    /** Mirrors `openBleSettings()`. */
    func openBleSettings(): Unit
}

// Device implementation + factories: entry/src/main/cangjie/reachability_impl.cj
// (see the structural note in this file's header).
