/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * file_picker_bridge.cj — document (PDF) picker seam.
 *
 * iOS picks a document with UIDocumentPicker inside SwiftUI. HarmonyOS's DocumentViewPicker
 * (`@ohos.file.picker`) has ArkTS bindings only, so the picker runs on the ArkTS side and hands
 * the chosen file's local path back over the JSModule bridge. Mirrors ScanBridge exactly.
 *
 * The ArkTS launcher is expected to copy the picked file into the app sandbox (cache/files dir)
 * and deliver that readable path, so the native signer (which takes a filesystem path) can read
 * it. `entry` installs the launcher at startup (index.cj registerFilePickerLauncher).
 */
package eudi_logic_ui

public class FilePickerBridge {
    /** Installed by `entry` — invokes the ArkTS DocumentViewPicker. */
    private static var launcher: ?() -> Unit = None
    /** Set for the duration of one pick request. */
    private static var pending: ?(String) -> Unit = None

    /**
     * Called by the ArkTS bridge at startup. `launch` must open the picker and eventually call
     * `deliver` (a file was chosen) or `cancel` (dismissed / failed).
     */
    public static func setLauncher(launch: () -> Unit): Unit {
        FilePickerBridge.launcher = Some(launch)
    }

    /** True once the ArkTS side has registered a launcher. */
    public static func isAvailable(): Bool {
        return !FilePickerBridge.launcher.isNone()
    }

    /**
     * Open the document picker. `onResult` fires with the chosen file's local path on the UI
     * thread. Returns false when no launcher is installed, so the caller can report unavailability
     * instead of leaving the user on a dead button.
     */
    public static func requestPick(onResult: (String) -> Unit): Bool {
        match (FilePickerBridge.launcher) {
            case Some(launch) =>
                FilePickerBridge.pending = Some(onResult)
                try {
                    launch()
                    return true
                } catch (_: Exception) {
                    FilePickerBridge.pending = None
                    return false
                }
            case None => return false
        }
    }

    /** ArkTS → Cangjie: a document was chosen; `path` is a readable local filesystem path. */
    public static func deliver(path: String): Unit {
        let cb = FilePickerBridge.pending
        FilePickerBridge.pending = None
        match (cb) {
            case Some(f) => f(path)
            case None => ()
        }
    }

    /** ArkTS → Cangjie: the user dismissed the picker, or it failed. */
    public static func cancel(): Unit {
        FilePickerBridge.pending = None
    }
}
