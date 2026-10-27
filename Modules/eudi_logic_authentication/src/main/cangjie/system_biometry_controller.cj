/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 *
 * Port of iOS logic-authentication/Sources/Controller/SystemBiometryController.swift.
 *
 * iOS uses LAContext (LocalAuthentication) for biometric evaluation and
 * KeyChainController.validateKeyChainBiometry()/clearKeyChainBiometry() to confirm
 * the biometry-protected keychain item is still usable.
 *
 * On HarmonyOS there is currently NO Cangjie binding for the biometric stack:
 * neither @ohos.userIAM.userAuth nor the biometry-gated HUKS keys are exposed
 * through arkui_cangjie_wrapper or the Cangjie SDK (verified — only the HUKS
 * key-management surface exists, no userAuth). The pre-existing feature-common
 * biometry seam (eudi_feature_common.EmulatorBiometryController) records the same
 * finding: the userIAM/userAuth + HUKS native path crashes at startup on the
 * emulator. Therefore the PRODUCTION default provider mirrors the iOS *failure*
 * branch faithfully — it reports honest unavailability and never fakes a
 * successful unlock. The consuming UI takes the exact same PIN-fallback route the
 * iOS biometry-error → PIN flow takes.
 *
 * To make the iOS branching (canEvaluatePolicy error codes, biometry-type
 * dispatch, keychain validate/clear) exercisable on-device without real hardware,
 * the LAContext + KeyChainController pair is abstracted behind a
 * `SystemBiometryProvider` seam. `SystemBiometryControllerImpl` keeps the full iOS
 * `canEvaluateForBiometrics()` + keychain logic and drives it through the provider,
 * so a device-track build only has to supply a userAuth-backed provider, and unit
 * tests can inject a fake provider to drive every branch. The default provider
 * (`EmulatorBiometryProvider`) is the honest degraded implementation described
 * above — real unavailability, never a fabricated success.
 */
package eudi_logic_authentication

/** Mirrors iOS `LABiometryType` (none / touchID / faceID). */
public enum LABiometryType <: Equatable<LABiometryType> {
    | none
    | touchID
    | faceID

    public operator func ==(o: LABiometryType): Bool {
        match ((this, o)) {
            case (none, none) => true
            case (touchID, touchID) => true
            case (faceID, faceID) => true
            case _ => false
        }
    }
    public operator func !=(o: LABiometryType): Bool { !(this == o) }
}

/** The discriminant of SystemBiometryError, mirroring the iOS enum cases 1:1. */
public enum SystemBiometryErrorKind <: Equatable<SystemBiometryErrorKind> {
    | deniedAccess
    | noFaceIdEnrolled
    | noFingerprintEnrolled
    | biometricError
    | biometryNotSupported

    /** Mirrors iOS `errorDescription`. */
    public func errorDescription(): String {
        match (this) {
            case deniedAccess =>
                "You have denied access. Please go to the settings, locate this application and turn the Face ID on"
            case noFaceIdEnrolled => "You have not enabled Face ID yet"
            case noFingerprintEnrolled => "You have not enabled fingerprint yet"
            case biometricError => "Your biometric method has not been recognized"
            case biometryNotSupported => "This device does not support biometry"
        }
    }

    public operator func ==(o: SystemBiometryErrorKind): Bool {
        match ((this, o)) {
            case (deniedAccess, deniedAccess) => true
            case (noFaceIdEnrolled, noFaceIdEnrolled) => true
            case (noFingerprintEnrolled, noFingerprintEnrolled) => true
            case (biometricError, biometricError) => true
            case (biometryNotSupported, biometryNotSupported) => true
            case _ => false
        }
    }
    public operator func !=(o: SystemBiometryErrorKind): Bool { !(this == o) }
}

/** Mirrors iOS `enum SystemBiometryError: Error, LocalizedError, Identifiable, Sendable`. */
public class SystemBiometryError <: Exception {
    public let kind: SystemBiometryErrorKind

    public init(kind: SystemBiometryErrorKind) {
        super(kind.errorDescription())
        this.kind = kind
    }

    /** Mirrors iOS `var id: String { localizedDescription }`. */
    public prop id: String {
        get() { this.kind.errorDescription() }
    }

    public prop errorDescription: String {
        get() { this.kind.errorDescription() }
    }

    public static func deniedAccess(): SystemBiometryError { SystemBiometryError(SystemBiometryErrorKind.deniedAccess) }
    public static func noFaceIdEnrolled(): SystemBiometryError { SystemBiometryError(SystemBiometryErrorKind.noFaceIdEnrolled) }
    public static func noFingerprintEnrolled(): SystemBiometryError { SystemBiometryError(SystemBiometryErrorKind.noFingerprintEnrolled) }
    public static func biometricError(): SystemBiometryError { SystemBiometryError(SystemBiometryErrorKind.biometricError) }
    public static func biometryNotSupported(): SystemBiometryError { SystemBiometryError(SystemBiometryErrorKind.biometryNotSupported) }
}

/**
 * Result of the iOS `context.canEvaluatePolicy(_:error:)` call.
 *
 * iOS returns a `Bool` plus an out `NSError?`; when evaluation fails the error's
 * numeric `code` selects the SystemBiometryError branch (`-6` → deniedAccess,
 * `-7` (`biometryNotEnrolled`) → noFaceIdEnrolled/noFingerprintEnrolled by type,
 * any other code → biometricError, `nil` error → deniedAccess). This value type
 * carries exactly that pair so the controller can reproduce the branch dispatch
 * verbatim, driven by whatever provider (real userAuth or fake) supplies it.
 */
public struct PolicyEvaluation {
    /** iOS `canEvaluatePolicy` return value. */
    public let canEvaluate: Bool
    /** iOS out-`NSError?.code`; None mirrors a `nil` NSError. */
    public let errorCode: ?Int64

    public init(canEvaluate: Bool, errorCode!: ?Int64 = Option<Int64>.None) {
        this.canEvaluate = canEvaluate
        this.errorCode = errorCode
    }

    /** iOS success: canEvaluatePolicy returned true with no error. */
    public static func success(): PolicyEvaluation { PolicyEvaluation(true) }

    /** iOS failure with a specific LAError-domain code. */
    public static func failure(code: Int64): PolicyEvaluation {
        PolicyEvaluation(false, errorCode: Some(code))
    }

    /** iOS failure with a `nil` NSError (falls through to deniedAccess). */
    public static func failureNoError(): PolicyEvaluation {
        PolicyEvaluation(false, errorCode: Option<Int64>.None)
    }
}

/** iOS LAError code for `biometryNotEnrolled` (`-7`). */
public let LA_ERROR_BIOMETRY_NOT_ENROLLED: Int64 = -7
/** iOS LAError code observed as denied access (`-6`). */
public let LA_ERROR_DENIED_ACCESS: Int64 = -6

/**
 * Injectable biometry backend seam abstracting the iOS `LAContext` +
 * `KeyChainController` pair.
 *
 *   - `biometryType()`      ↔ `LAContext.biometryType`
 *   - `evaluatePolicy()`    ↔ `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error:)`
 *   - `validateKeychain()`  ↔ `KeyChainController.validateKeyChainBiometry()` (throws SystemBiometryError on failure)
 *   - `clearKeychain()`     ↔ `KeyChainController.clearKeyChainBiometry()`
 *
 * The production default is `EmulatorBiometryProvider` (honest unavailability).
 * Unit tests inject a fake provider to drive every iOS branch on-device without
 * real biometric hardware.
 */
public interface SystemBiometryProvider {
    func biometryType(): LABiometryType
    func evaluatePolicy(): PolicyEvaluation
    func validateKeychain(): Unit
    func clearKeychain(): Unit
}

/**
 * Production default provider: HarmonyOS exposes no biometric binding to this
 * layer, so evaluation always fails as `biometryNotSupported` — biometry type is
 * `none` and `evaluatePolicy()` reports it cannot evaluate. `validateKeychain()`
 * is never reached on this path (the controller throws before the keychain step);
 * it mirrors the iOS success no-op so a device-track provider swap is drop-in.
 */
public class EmulatorBiometryProvider <: SystemBiometryProvider {
    public init() {}

    public func biometryType(): LABiometryType {
        // iOS: context.biometryType. No biometric hardware binding available → none.
        return LABiometryType.none
    }

    public func evaluatePolicy(): PolicyEvaluation {
        // iOS: context.canEvaluatePolicy(...). Cannot evaluate; with a nil error and
        // biometryType == .none the controller resolves this to biometryNotSupported
        // (the exact iOS guard for a device without biometry).
        return PolicyEvaluation.success()
    }

    public func validateKeychain(): Unit {
        // Unreachable while biometry is unavailable; on a device-track build this
        // would validate the biometry-gated HUKS/keychain item.
        return
    }

    public func clearKeychain(): Unit {
        return
    }
}

/**
 * Mirrors iOS `public protocol SystemBiometryController: Sendable`.
 *
 * iOS `async` methods become synchronous (Cangjie has no async surface in this
 * layer); `async throws` becomes plain `throws` via the SystemBiometryError
 * exception. `openSettings(action:)` takes a `() -> Unit` continuation matching
 * the iOS `@escaping @Sendable () -> Void`.
 */
public interface SystemBiometryController {
    func getBiometryType(): LABiometryType
    func requestBiometricUnlock(): Unit
    func openSettings(action: () -> Unit): Unit
}

/**
 * Mirrors iOS `final actor SystemBiometryControllerImpl`.
 *
 * The full iOS `canEvaluateForBiometrics()` branch dispatch plus the keychain
 * validate/clear step are preserved verbatim and driven through the injected
 * `SystemBiometryProvider`. With the default `EmulatorBiometryProvider` the flow
 * resolves to `biometryNotSupported` (biometry type `none`), so callers fall back
 * to PIN exactly as on iOS — no fake success is ever returned. A device-track
 * build or a unit test supplies a different provider to exercise the other
 * branches.
 */
public class SystemBiometryControllerImpl <: SystemBiometryController {
    private let provider: SystemBiometryProvider

    /** Production seam: defaults to the honest degraded provider. */
    public init() {
        this.provider = EmulatorBiometryProvider()
    }

    /** Injection seam (device-track provider or test fake). */
    public init(provider: SystemBiometryProvider) {
        this.provider = provider
    }

    public func getBiometryType(): LABiometryType {
        // iOS: context.biometryType.
        return this.provider.biometryType()
    }

    public func requestBiometricUnlock(): Unit {
        // iOS: try canEvaluateForBiometrics(); then validate the keychain item and,
        // on failure, clear it and surface .biometricError.
        canEvaluateForBiometrics()
        try {
            this.provider.validateKeychain()
        } catch (e: SystemBiometryError) {
            this.provider.clearKeychain()
            throw SystemBiometryError.biometricError()
        }
    }

    public func openSettings(action: () -> Unit): Unit {
        // iOS opens UIApplication.openSettingsURLString then invokes `action` on
        // success. There is no equivalent app-settings deep link exposed to this
        // logic layer; mirror the iOS `guard ... else { return }` no-success path
        // by not invoking the continuation (the UI keeps its current screen).
        return
    }

    /**
     * Verbatim port of iOS `canEvaluateForBiometrics()`.
     *
     * 1. `evaluatePolicy()` mirrors `context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error:)`.
     * 2. On !canEvaluate, the LAError code selects the branch:
     *    -6 → deniedAccess, -7 (biometryNotEnrolled) → noFaceIdEnrolled/noFingerprintEnrolled
     *    by biometry type, any other code → biometricError, nil code → deniedAccess.
     * 3. On canEvaluate but biometry type `none` → biometryNotSupported.
     */
    private func canEvaluateForBiometrics(): Unit {
        let evaluation = this.provider.evaluatePolicy()

        if (!evaluation.canEvaluate) {
            match (evaluation.errorCode) {
                case Some(code) =>
                    if (code == LA_ERROR_DENIED_ACCESS) {
                        throw SystemBiometryError.deniedAccess()
                    } else if (code == LA_ERROR_BIOMETRY_NOT_ENROLLED) {
                        if (this.provider.biometryType() == LABiometryType.faceID) {
                            throw SystemBiometryError.noFaceIdEnrolled()
                        } else {
                            throw SystemBiometryError.noFingerprintEnrolled()
                        }
                    } else {
                        throw SystemBiometryError.biometricError()
                    }
                case None =>
                    throw SystemBiometryError.deniedAccess()
            }
        }

        if (this.provider.biometryType() == LABiometryType.none) {
            throw SystemBiometryError.biometryNotSupported()
        }
    }
}
