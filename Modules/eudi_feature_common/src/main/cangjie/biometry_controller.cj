/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Biometry seam of the EUDI HarmonyOS
 * wallet feature-common module.
 *
 * iOS counterpart: logic-authentication SystemBiometryController.swift
 * (LAContext). The Cangjie SDK does not expose userIAM, so production uses a
 * small queued bridge to ArkTS UserAuthenticationKit. The emulator controller
 * remains available to tests and reports honest unavailability.
 */
package eudi_feature_common

import kit.PerformanceAnalysisKit.Hilog

/**
 * Mirrors the iOS `SystemBiometryError` enum; each case is a distinct
 * user-visible reason.
 */
public enum BiometryError {
    | DeniedAccess
    | NoFaceIdEnrolled
    | NoFingerprintEnrolled
    | BiometricError
    | BiometryNotSupported

    /** User-facing description (mirrors iOS `errorDescription`). */
    public func message(): String {
        match (this) {
            case DeniedAccess =>
                "You have denied access. Please go to the settings, locate this application and turn the biometry on"
            case NoFaceIdEnrolled => "You have not enabled Face ID yet"
            case NoFingerprintEnrolled => "You have not enabled fingerprint yet"
            case BiometricError => "Your biometric method has not been recognized"
            case BiometryNotSupported => "This device does not support biometry"
        }
    }
}

/** Mirrors iOS `LABiometryType` (none / touch / face). */
public enum BiometryType {
    | BiometryNone
    | TouchID
    | FaceID
}

/** Availability query result of `BiometryController.canEvaluate`. */
public enum BiometryAvailability {
    | Available
    | Unavailable(BiometryError)

    public func isAvailable(): Bool {
        match (this) {
            case Available => true
            case Unavailable(_) => false
        }
    }
}

/** Unlock result; Cangjie has no `throws`, so failures travel as payload. */
public enum BiometryUnlockResult {
    | UnlockSuccess
    | UnlockFailure(BiometryError)
}

/**
 * Narrow biometry contract (frozen interface of fc_common_biometry).
 * Mirrors the iOS `SystemBiometryController` protocol surface consumed by
 * BiometryViewModel: type query, availability check, unlock request, and the
 * settings deep-link delegate (iOS `openSettings(action:)`).
 */
public interface BiometryController {
    func getBiometryType(): BiometryType
    func canEvaluate(): BiometryAvailability
    func requestBiometricUnlock(): BiometryUnlockResult
    /**
     * Mirrors iOS `SystemBiometryController.openSettings(action:)`: open the app
     * settings page and invoke `action` only on a successful open. There is no
     * app-settings deep link exposed to this layer on the emulator seam, so the
     * default impl reproduces the iOS `guard ... else { return }` no-success path
     * by not invoking the continuation.
     */
    func openSettings(action: () -> Unit): Unit
}

/**
 * Emulator-safe default: no biometric hardware binding → honest
 * unavailability, never a fake success. The consuming UI must offer the PIN
 * fallback path (BiometryView does).
 */
public class EmulatorBiometryController <: BiometryController {
    public init() {}

    public func getBiometryType(): BiometryType {
        BiometryType.BiometryNone
    }

    public func canEvaluate(): BiometryAvailability {
        BiometryAvailability.Unavailable(BiometryError.BiometryNotSupported)
    }

    public func requestBiometricUnlock(): BiometryUnlockResult {
        BiometryUnlockResult.UnlockFailure(BiometryError.BiometryNotSupported)
    }

    public func openSettings(action: () -> Unit): Unit {
        // No app-settings deep link reachable here; mirror the iOS no-success
        // path (do not invoke the continuation).
        return
    }
}

/** Production controller backed by ArkTS UserAuthenticationKit. */
public class ArkTsBiometryController <: BiometryController {
    public init() {}

    public func getBiometryType(): BiometryType {
        match (ArkTsBiometryBridge.currentAuthType()) {
            case ARKTS_AUTH_TYPE_FACE => BiometryType.FaceID
            case ARKTS_AUTH_TYPE_FINGERPRINT => BiometryType.TouchID
            case _ => BiometryType.BiometryNone
        }
    }

    public func canEvaluate(): BiometryAvailability {
        let status = ArkTsBiometryBridge.currentAvailabilityCode()
        if (status == ARKTS_AUTH_SUCCESS) {
            return BiometryAvailability.Available
        }
        return BiometryAvailability.Unavailable(this.errorFor(status))
    }

    public func requestBiometricUnlock(): BiometryUnlockResult {
        let result = ArkTsBiometryBridge.authenticate()
        if (result == ARKTS_AUTH_SUCCESS) {
            return BiometryUnlockResult.UnlockSuccess
        }
        return BiometryUnlockResult.UnlockFailure(this.errorFor(result))
    }

    public func openSettings(action: () -> Unit): Unit {
        ArkTsBiometryBridge.requestOpenSettings()
        action()
    }

    private func errorFor(code: Int32): BiometryError {
        if (code == ARKTS_AUTH_PERMISSION_DENIED) {
            return BiometryError.DeniedAccess
        }
        if (code == ARKTS_AUTH_NOT_ENROLLED) {
            // iOS LAError -7 splits by the platform biometry type.
            match (this.getBiometryType()) {
                case FaceID => return BiometryError.NoFaceIdEnrolled
                case _ => return BiometryError.NoFingerprintEnrolled
            }
        }
        if (code == ARKTS_AUTH_TYPE_NOT_SUPPORTED) {
            return BiometryError.BiometryNotSupported
        }
        match (this.getBiometryType()) {
            case BiometryNone => return BiometryError.BiometryNotSupported
            case _ =>
                // iOS folds every unrecognised LAError into `biometricError`,
                // which the screens deliberately swallow (the platform sheet
                // already spoke). A platform *parameter* error would then be
                // invisible, so keep the raw code in the device log.
                if (code != ARKTS_AUTH_FAIL && code != ARKTS_AUTH_CANCELED &&
                    code != ARKTS_AUTH_TIMEOUT) {
                    Hilog.error(0, "Biometry",
                        "unmapped UserAuth result code=${code}; reported as biometricError")
                }
                return BiometryError.BiometricError
        }
    }
}

/** Factory mirroring the Swinject registration (composition-root seam). */
public func createBiometryController(): BiometryController {
    return ArkTsBiometryController()
}
