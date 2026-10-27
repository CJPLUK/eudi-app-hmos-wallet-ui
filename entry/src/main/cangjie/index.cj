/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 */

package ohos_app_cangjie_entry

import ohos.ark_interop.JSModule
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSCallInfo
import ohos.ark_interop.JSValue
import ohos.app.ability.ui_ability.createUIAbilityContextFromJSValue
import kit.PerformanceAnalysisKit.Hilog
import std.collection.ArrayList
import std.sync.{Mutex, Monitor}
import eudi_logic_core.*
import eudi_logic_ui.{ScanBridge, FilePickerBridge}
import ohos_app_cangjie_eudi_cjrqes_kit.RqesTempDir
import eudi_logic_business.BluetoothStateBridge
import eudi_feature_common.ArkTsBiometryBridge
import ohos_app_cangjie_eudi_cjmdoc_transfer.transfer.ble.{
    ArkTsGattBridge, ArkTsGattOperations, BleBackendException, BleErrorCodes
}

/**
 * Cangjie worker threads cannot invoke a JSFunction retained from the ArkTS UI
 * scope (the runtime reports "Thread mismatch" / "Without any scope"). Radio
 * operations therefore cross the boundary as immutable command strings. ArkTS
 * drains this FIFO on its own UI event loop and performs the BLE calls there.
 */
class GattCommandQueue {
    private static let lock = Mutex()
    private static let commands = ArrayList<String>()
    private static let notifyMonitor = Monitor()
    private static var nextNotifyId: Int64 = 1
    private static var completedNotifyId: Int64 = 0
    private static var notifySucceeded: Bool = false
    private static var notifyMessage: String = ""

    static func offer(command: String): Unit {
        synchronized(GattCommandQueue.lock) { GattCommandQueue.commands.add(command) }
    }

    static func drain(): String {
        synchronized(GattCommandQueue.lock) {
            let result = StringBuilder()
            var first = true
            for (command in GattCommandQueue.commands) {
                if (!first) { result.append("\n") }
                result.append(command)
                first = false
            }
            GattCommandQueue.commands.clear()
            return result.toString()
        }
    }

    /**
     * Notify is the only queued operation whose result controls ISO 18013-5
     * framing. Wait until ArkTS has actually accepted this block so the sender
     * can retry a transient 2900099 instead of silently dropping a fragment.
     */
    static func offerNotify(command: (Int64) -> String): Unit {
        var id: Int64 = 0
        synchronized(GattCommandQueue.notifyMonitor) {
            id = GattCommandQueue.nextNotifyId
            GattCommandQueue.nextNotifyId++
        }
        GattCommandQueue.offer(command(id))
        synchronized(GattCommandQueue.notifyMonitor) {
            if (GattCommandQueue.completedNotifyId < id) {
                GattCommandQueue.notifyMonitor.wait(timeout: Duration.second * 2)
            }
            if (GattCommandQueue.completedNotifyId < id) {
                throw BleBackendException(BleErrorCodes.OPERATION_FAILED,
                    "ArkTS GATT notify acknowledgement timed out")
            }
            if (!GattCommandQueue.notifySucceeded) {
                throw BleBackendException(BleErrorCodes.OPERATION_FAILED,
                    "ArkTS GATT notify failed: " + GattCommandQueue.notifyMessage)
            }
        }
    }

    static func completeNotify(id: Int64, succeeded: Bool, message: String): Unit {
        synchronized(GattCommandQueue.notifyMonitor) {
            GattCommandQueue.completedNotifyId = id
            GattCommandQueue.notifySucceeded = succeeded
            GattCommandQueue.notifyMessage = message
            GattCommandQueue.notifyMonitor.notifyAll()
        }
    }
}

class EntryQueuedGattOperations <: ArkTsGattOperations {
    public func open(serviceUuid: String, identHex: String): Unit {
        GattCommandQueue.offer("OPEN|" + serviceUuid + "|" + identHex)
    }
    public func startAdvertise(serviceUuid: String): Unit {
        GattCommandQueue.offer("START|" + serviceUuid)
    }
    public func stopAdvertise(): Unit { GattCommandQueue.offer("STOP") }
    public func notify(deviceId: String, serviceUuid: String, characteristicUuid: String, valueHex: String): Unit {
        GattCommandQueue.offerNotify({ id =>
            "NOTIFY|" + id.toString() + "|" + deviceId + "|" + serviceUuid + "|" + characteristicUuid + "|" + valueHex
        })
    }
    public func respond(deviceId: String, transId: Int32, status: Int32, offset: Int32, valueHex: String): Unit {
        GattCommandQueue.offer("RESPOND|" + deviceId + "|" + transId.toString() + "|" + status.toString() + "|" + offset.toString() + "|" + valueHex)
    }
    public func close(serviceUuid: String): Unit {
        GattCommandQueue.offer("CLOSE|" + serviceUuid)
    }
}

// entry 直接消费 third_party cbor 的自检,结果串回传 ArkTS 显示/打日志。
func cborSelfTest(runtime: JSContext, _: JSCallInfo): JSValue {
    runtime.string(entry_cbor_selftest()).toJSValue()
}

// entry 直接消费 third_party core-crypto 的 iOS 对齐 KAT 套件(16 用例)。
func cryptoSelfTest(runtime: JSContext, _: JSCallInfo): JSValue {
    runtime.string(entry_crypto_kat()).toJSValue()
}

// Receives the ETS EntryAbility's UIAbilityContext (getContext(this)) and stashes
// it for the wallet engine's persistent RDB document store. Must be called by the
// ETS layer before the Cangjie AppRoot is mounted (Index.ets aboutToAppear).
func setAbilityContext(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let ctx = createUIAbilityContextFromJSValue(runtime, callInfo[0])
    AppContextHolder.set(ctx)
    // RQES signing writes signed PDFs to a temp path; the SDK has no app context of its
    // own (iOS uses NSTemporaryDirectory), so seed its process-global dir from filesDir.
    RqesTempDir.set(ctx.filesDir)
    runtime.string("ok").toJSValue()
}

// Receives a deep-link URI (haip-vci:// / openid-credential-offer:// /
// eudi-openid4vp://...) captured by the ETS EntryAbility from the launch/new
// want, and stashes it in DeepLinkRouter. Cold start: the authenticated
// Dashboard consumes it once the auth gate is passed. Warm start (user already
// authenticated, e.g. browser "Use EUDIW" while the app is alive): route
// immediately, mirroring iOS DeepLinkController.handleDeepLinkAction.
func handleDeepLink(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let uri = callInfo[0].toString()
    DeepLinkRouter.set(uri)
    // Cold start: Index.ets forwards the pending URI BEFORE AppRoot.aboutToAppear
    // runs AppComposition.setup(), so touching .shared here would throw — leave
    // the URI pending for the Dashboard hook. Warm start (composition ready):
    // route immediately, mirroring iOS DeepLinkController.
    try {
        if (AppComposition.shared.router.userIsLoggedInWithDocuments() ||
            AppComposition.shared.router.userIsLoggedInWithNoDocuments()) {
            AppComposition.shared.router.runOnUi({ => DeepLinkRouter.consume() })
        }
    } catch (_: Exception) {
        // Composition not set up yet (cold start) — pending URI stays for the
        // Dashboard consume hook.
    }
    runtime.string("ok").toJSValue()
}

// ── Camera QR scan bridge ───────────────────────────────────────────────────
// HMS Scan Kit has ArkTS bindings only, so the camera scan runs over there.
// ArkTS hands us a launcher function once; ScanBridge calls it when a Cangjie
// screen asks for a scan, and ArkTS reports the outcome back through
// deliverScanResult / cancelScanResult.
//
// The launcher JSValue is retained for the process lifetime, which is what the
// ArkTS side expects: Index.ets registers exactly one closure, bound to the
// page context Scan Kit requires (`startScanForResult` must run in an ArkUI
// page context — it cannot be called from an arbitrary Cangjie thread).
func registerScanLauncher(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let launcher = callInfo[0].asFunction()
    ScanBridge.setLauncher({
        =>
        launcher.call(thisArg: runtime.undefined().toJSValue())
        ()
    })
    Hilog.info(0, "SCAN", "scan launcher registered")
    runtime.string("ok").toJSValue()
}

// ArkTS → Cangjie: Scan Kit decoded a barcode. Delivered on the ArkTS/UI
// thread, which is the same thread the requesting screen renders on.
func deliverScanResult(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let text = callInfo[0].toString()
    Hilog.info(0, "SCAN", "scan result len=${text.size}")
    ScanBridge.deliver(text)
    runtime.string("ok").toJSValue()
}

// ArkTS → Cangjie: the user dismissed the scanner, or Scan Kit failed. Clears
// the pending callback so the next scan is not routed to a dead screen.
func cancelScanResult(runtime: JSContext, _: JSCallInfo): JSValue {
    ScanBridge.cancel()
    runtime.string("ok").toJSValue()
}

// ── RQES document picker bridge (DocumentViewPicker is ArkTS-only) ───────────
// ArkTS registers a launcher; FilePickerBridge invokes it when the Sign-document
// screen asks to pick a PDF. ArkTS opens the picker, copies the chosen file into
// the app sandbox, and reports the readable path back via deliverFilePickerResult.
func registerFilePickerLauncher(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let launcher = callInfo[0].asFunction()
    FilePickerBridge.setLauncher({
        =>
        launcher.call(thisArg: runtime.undefined().toJSValue())
        ()
    })
    Hilog.info(0, "RQES", "file picker launcher registered")
    runtime.string("ok").toJSValue()
}

// ArkTS → Cangjie: a document was picked; `path` is a readable local file path.
func deliverFilePickerResult(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let path = callInfo[0].toString()
    Hilog.info(0, "RQES", "file picked len=${path.size}")
    FilePickerBridge.deliver(path)
    runtime.string("ok").toJSValue()
}

// ArkTS → Cangjie: the user dismissed the picker, or it failed.
func cancelFilePickerResult(runtime: JSContext, _: JSCallInfo): JSValue {
    FilePickerBridge.cancel()
    runtime.string("ok").toJSValue()
}

// ── Bluetooth adapter-state bridge ──────────────────────────────────────────────
// Cangjie ConnectivityKit lacks ohos.bluetooth.access.getState(), so ArkTS
// provides the authoritative synchronous reader used by ReachabilityController.
func registerBluetoothStateReader(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let reader = callInfo[0].asFunction()
    BluetoothStateBridge.setReader({ => Int32(reader.call().toNumber()) })
    Hilog.info(0, "BLE", "Bluetooth state reader registered")
    runtime.string("ok").toJSValue()
}

func deliverBluetoothState(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    BluetoothStateBridge.update(Int32(callInfo[0].toNumber()))
    runtime.string("ok").toJSValue()
}

func registerGattOperations(runtime: JSContext, _: JSCallInfo): JSValue {
    // Keep the arguments for source/API compatibility, but do not retain their
    // JSFunction values beyond this interop scope.
    ArkTsGattBridge.install(EntryQueuedGattOperations())
    Hilog.info(0, "BLE", "queued ArkTS GATT operations registered")
    runtime.string("ok").toJSValue()
}

func drainGattCommands(runtime: JSContext, _: JSCallInfo): JSValue {
    runtime.string(GattCommandQueue.drain()).toJSValue()
}

func deliverGattNotifyResult(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    GattCommandQueue.completeNotify(Int64(callInfo[0].toNumber()),
        callInfo[1].toBoolean(), callInfo[2].toString())
    runtime.string("ok").toJSValue()
}

private func hexNibble(c: UInt8): UInt8 {
    if (c >= 48u8 && c <= 57u8) { return c - 48u8 }
    if (c >= 97u8 && c <= 102u8) { return c - 87u8 }
    if (c >= 65u8 && c <= 70u8) { return c - 55u8 }
    return 0u8
}

private func hexBytes(text: String): Array<UInt8> {
    let input = text.toArray()
    let out = Array<UInt8>(input.size / 2, repeat: 0u8)
    var i: Int64 = 0
    while (i + 1 < input.size) {
        out[i / 2] = (hexNibble(input[i]) << 4) | hexNibble(input[i + 1])
        i += 2
    }
    return out
}

func deliverGattConnection(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    ArkTsGattBridge.connectionChanged(callInfo[0].toString(), callInfo[1].toBoolean())
    runtime.string("ok").toJSValue()
}
func deliverGattMtu(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    ArkTsGattBridge.mtuChanged(Int32(callInfo[0].toNumber()))
    runtime.string("ok").toJSValue()
}
func deliverGattWrite(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let descriptor = callInfo[5].toString()
    ArkTsGattBridge.writeRequest(callInfo[0].toString(), Int32(callInfo[1].toNumber()),
        Int32(callInfo[2].toNumber()), callInfo[3].toBoolean(), callInfo[4].toString(),
        if (descriptor.isEmpty()) { None } else { Some(descriptor) }, hexBytes(callInfo[6].toString()))
    runtime.string("ok").toJSValue()
}
func deliverGattRead(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let descriptor = callInfo[4].toString()
    ArkTsGattBridge.readRequest(callInfo[0].toString(), Int32(callInfo[1].toNumber()),
        Int32(callInfo[2].toNumber()), callInfo[3].toString(),
        if (descriptor.isEmpty()) { None } else { Some(descriptor) })
    runtime.string("ok").toJSValue()
}

// ── UserAuthenticationKit bridge ─────────────────────────────────────────────
// Authentication UI belongs to ArkTS. As with BLE, commands are polled on the
// ArkTS UI event loop so Cangjie worker threads never invoke retained JS values.
func deliverBiometryCapability(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    ArkTsBiometryBridge.updateCapability(Int32(callInfo[0].toNumber()),
        Int32(callInfo[1].toNumber()))
    runtime.string("ok").toJSValue()
}

func drainBiometryCommands(runtime: JSContext, _: JSCallInfo): JSValue {
    runtime.string(ArkTsBiometryBridge.drainCommands()).toJSValue()
}

func deliverBiometryResult(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    ArkTsBiometryBridge.completeAuthentication(Int64(callInfo[0].toNumber()),
        Int32(callInfo[1].toNumber()))
    runtime.string("ok").toJSValue()
}

// JSModule 保留探针导出以维持 ArkTS 向后兼容;UI 入口已切换到 AppRoot (@HybridComponentEntry)。
let EXPORT_MODULE = JSModule.registerModule {
    runtime, exports =>
        exports["cborSelfTest"] = runtime.function(cborSelfTest).toJSValue()
        exports["cryptoSelfTest"] = runtime.function(cryptoSelfTest).toJSValue()
        exports["setAbilityContext"] = runtime.function(setAbilityContext).toJSValue()
        exports["handleDeepLink"] = runtime.function(handleDeepLink).toJSValue()
        exports["registerScanLauncher"] = runtime.function(registerScanLauncher).toJSValue()
        exports["deliverScanResult"] = runtime.function(deliverScanResult).toJSValue()
        exports["cancelScanResult"] = runtime.function(cancelScanResult).toJSValue()
        exports["registerFilePickerLauncher"] = runtime.function(registerFilePickerLauncher).toJSValue()
        exports["deliverFilePickerResult"] = runtime.function(deliverFilePickerResult).toJSValue()
        exports["cancelFilePickerResult"] = runtime.function(cancelFilePickerResult).toJSValue()
        exports["registerBluetoothStateReader"] = runtime.function(registerBluetoothStateReader).toJSValue()
        exports["deliverBluetoothState"] = runtime.function(deliverBluetoothState).toJSValue()
        exports["registerGattOperations"] = runtime.function(registerGattOperations).toJSValue()
        exports["drainGattCommands"] = runtime.function(drainGattCommands).toJSValue()
        exports["deliverGattNotifyResult"] = runtime.function(deliverGattNotifyResult).toJSValue()
        exports["deliverGattConnection"] = runtime.function(deliverGattConnection).toJSValue()
        exports["deliverGattMtu"] = runtime.function(deliverGattMtu).toJSValue()
        exports["deliverGattWrite"] = runtime.function(deliverGattWrite).toJSValue()
        exports["deliverGattRead"] = runtime.function(deliverGattRead).toJSValue()
        exports["deliverBiometryCapability"] = runtime.function(deliverBiometryCapability).toJSValue()
        exports["drainBiometryCommands"] = runtime.function(drainBiometryCommands).toJSValue()
        exports["deliverBiometryResult"] = runtime.function(deliverBiometryResult).toJSValue()
}
