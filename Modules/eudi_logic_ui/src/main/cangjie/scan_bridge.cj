/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * scan_bridge.cj — camera QR scanning seam.
 *
 * iOS scans with CodeScanner inside its own SwiftUI screen. HarmonyOS keeps
 * barcode decoding in HMS Scan Kit, which ships ArkTS bindings only (there is
 * no Cangjie `@kit.ScanKit`), so the camera scan runs on the ArkTS side and
 * hands the decoded text back over the JSModule bridge.
 *
 * This file is the language-neutral half: the feature layer asks for a scan and
 * receives the decoded string, without importing ark_interop. `entry` installs
 * the real launcher at startup (index.cj registerScanLauncher); until it does —
 * or on a device where Scan Kit is unavailable — `isAvailable()` stays false and
 * the caller keeps the manual-URL fallback.
 */
package eudi_logic_ui

/**
 * Camera-scan seam. Single-shot by construction: one pending result callback at
 * a time, cleared as soon as it fires, so a stale scanner screen can never
 * receive a later scan's result.
 */
public class ScanBridge {
    /** Installed by `entry` — invokes the ArkTS Scan Kit page. */
    private static var launcher: ?() -> Unit = None
    /** Set for the duration of one scan request. */
    private static var pending: ?(String) -> Unit = None

    /**
     * Called by the ArkTS bridge at startup. `launch` must open the scan UI and
     * eventually call `deliver` (success) or `cancel` (dismissed / failed).
     */
    public static func setLauncher(launch: () -> Unit): Unit {
        ScanBridge.launcher = Some(launch)
    }

    /** True once the ArkTS side has registered a launcher. */
    public static func isAvailable(): Bool {
        return !ScanBridge.launcher.isNone()
    }

    /**
     * Open the camera scanner. `onResult` fires with the decoded text on the UI
     * thread. Returns false when no launcher is installed, so the caller can
     * fall back to manual entry instead of leaving the user on a dead button.
     */
    public static func requestScan(onResult: (String) -> Unit): Bool {
        match (ScanBridge.launcher) {
            case Some(launch) =>
                ScanBridge.pending = Some(onResult)
                try {
                    launch()
                    return true
                } catch (_: Exception) {
                    // Launcher blew up (Scan Kit missing, no camera permission):
                    // drop the pending callback so a later scan is not mis-routed.
                    ScanBridge.pending = None
                    return false
                }
            case None => return false
        }
    }

    /** ArkTS → Cangjie: a barcode was decoded. */
    public static func deliver(text: String): Unit {
        let cb = ScanBridge.pending
        ScanBridge.pending = None
        match (cb) {
            case Some(f) => f(text)
            case None => ()
        }
    }

    /** ArkTS → Cangjie: the user dismissed the scanner, or it failed. */
    public static func cancel(): Unit {
        ScanBridge.pending = None
    }
}
