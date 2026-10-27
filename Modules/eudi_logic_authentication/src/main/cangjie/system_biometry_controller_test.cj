/*
 * Host unit tests for SystemBiometryControllerImpl.
 * Migrated from iOS logic-authentication/Tests/Controller/TestSystemBiometryController.swift (11).
 *
 * FakeSystemBiometryProvider injects LAContext + keychain branches. The
 * no-arg constructor uses EmulatorBiometryProvider (honest unavailability).
 */
package eudi_logic_authentication

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*

let LA_ERROR_USER_FALLBACK: Int64 = -3

class FakeSystemBiometryProvider <: SystemBiometryProvider {
    var typeToReturn: LABiometryType = LABiometryType.touchID
    var policy: PolicyEvaluation = PolicyEvaluation.success()
    var keychainThrows: Bool = false
    var clearKeychainCalls: Int64 = 0
    var validateKeychainCalls: Int64 = 0

    public func biometryType(): LABiometryType { this.typeToReturn }

    public func evaluatePolicy(): PolicyEvaluation { this.policy }

    public func validateKeychain(): Unit {
        this.validateKeychainCalls += 1
        if (this.keychainThrows) {
            throw SystemBiometryError.biometricError()
        }
    }

    public func clearKeychain(): Unit {
        this.clearKeychainCalls += 1
    }
}

func unlockKind(controller: SystemBiometryController): ?SystemBiometryErrorKind {
    try {
        controller.requestBiometricUnlock()
        return Option<SystemBiometryErrorKind>.None
    } catch (e: SystemBiometryError) {
        return Some(e.kind)
    } catch (_: Exception) {
        return Option<SystemBiometryErrorKind>.None
    }
}

func unlockError(controller: SystemBiometryController): ?SystemBiometryError {
    try {
        controller.requestBiometricUnlock()
        return Option<SystemBiometryError>.None
    } catch (e: SystemBiometryError) {
        return Some(e)
    } catch (_: Exception) {
        return Option<SystemBiometryError>.None
    }
}

@Test
class TestSystemBiometryController {
    @TestCase
    func testRequestUnlock_WhenPolicyDenied_ThenDeniedAccess(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.policy = PolicyEvaluation.failureNoError()
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        match (unlockError(controller)) {
            case Some(e) =>
                @Expect(e.kind, SystemBiometryErrorKind.deniedAccess)
                @Expect(
                    e.errorDescription,
                    "You have denied access. Please go to the settings, locate this application and turn the Face ID on"
                )
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func testRequestBiometricUnlock_WhenFaceID_ThenNoFaceIdEnrolled(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.faceID
        provider.policy = PolicyEvaluation.failure(LA_ERROR_BIOMETRY_NOT_ENROLLED)
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        match (unlockError(controller)) {
            case Some(e) =>
                @Expect(e.kind, SystemBiometryErrorKind.noFaceIdEnrolled)
                @Expect(e.errorDescription, "You have not enabled Face ID yet")
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func testRequestBiometricUnlock_WhenTouchID_ThenNoFingerprintEnrolled(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.touchID
        provider.policy = PolicyEvaluation.failure(LA_ERROR_BIOMETRY_NOT_ENROLLED)
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        match (unlockError(controller)) {
            case Some(e) =>
                @Expect(e.kind, SystemBiometryErrorKind.noFingerprintEnrolled)
                @Expect(e.errorDescription, "You have not enabled fingerprint yet")
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func testRequestBiometricUnlock_WhenBiometryNotSupported_yieldsBiometryNotSupported(): Unit {
        let controller: SystemBiometryController = SystemBiometryControllerImpl()
        match (unlockError(controller)) {
            case Some(e) =>
                @Expect(e.kind, SystemBiometryErrorKind.biometryNotSupported)
                @Expect(e.errorDescription, "This device does not support biometry")
            case None => @Expect(false, true)
        }

        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.none
        provider.policy = PolicyEvaluation.success()
        let viaProvider: SystemBiometryController = SystemBiometryControllerImpl(provider)
        @Expect(unlockKind(viaProvider), Some(SystemBiometryErrorKind.biometryNotSupported))
    }

    @TestCase
    func testRequestBiometricUnlock_WhenKeychainValidates_ThenReturnSuccess(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.touchID
        provider.policy = PolicyEvaluation.success()
        provider.keychainThrows = false
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        var crashed = false
        try {
            controller.requestBiometricUnlock()
        } catch (_: Exception) {
            crashed = true
        }
        @Expect(crashed, false)
        @Expect(provider.validateKeychainCalls, 1)
        @Expect(provider.clearKeychainCalls, 0)
    }

    @TestCase
    func testRequestBiometricUnlock_WhenKeychainThrows_ThenReturnBiometricError(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.touchID
        provider.policy = PolicyEvaluation.success()
        provider.keychainThrows = true
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        match (unlockError(controller)) {
            case Some(e) =>
                @Expect(e.kind, SystemBiometryErrorKind.biometricError)
                @Expect(e.errorDescription, "Your biometric method has not been recognized")
            case None => @Expect(false, true)
        }
        @Expect(provider.clearKeychainCalls, 1)
    }

    @TestCase
    func testRequestBiometricUnlock_WhenLAContextErrorIsMinus6_ThenDeniedAccess(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.touchID
        provider.policy = PolicyEvaluation.failure(LA_ERROR_DENIED_ACCESS)
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        @Expect(unlockKind(controller), Some(SystemBiometryErrorKind.deniedAccess))
    }

    @TestCase
    func testRequestBiometricUnlock_WhenLAContextErrorIsUserFallback_ThenBiometricError(): Unit {
        let provider = FakeSystemBiometryProvider()
        provider.typeToReturn = LABiometryType.touchID
        provider.policy = PolicyEvaluation.failure(LA_ERROR_USER_FALLBACK)
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)
        @Expect(unlockKind(controller), Some(SystemBiometryErrorKind.biometricError))
    }

    @TestCase
    func testSystemBiometryError_id_ReturnsLocalizedDescription(): Unit {
        let allErrors: Array<SystemBiometryError> = [
            SystemBiometryError.deniedAccess(),
            SystemBiometryError.noFaceIdEnrolled(),
            SystemBiometryError.noFingerprintEnrolled(),
            SystemBiometryError.biometricError(),
            SystemBiometryError.biometryNotSupported()
        ]
        for (err in allErrors) {
            @Expect(err.id, err.errorDescription)
            @Expect(err.id.isEmpty(), false)
        }
        @Expect(
            SystemBiometryError.deniedAccess().errorDescription,
            "You have denied access. Please go to the settings, locate this application and turn the Face ID on"
        )
        @Expect(SystemBiometryError.noFaceIdEnrolled().errorDescription, "You have not enabled Face ID yet")
        @Expect(SystemBiometryError.noFingerprintEnrolled().errorDescription, "You have not enabled fingerprint yet")
        @Expect(SystemBiometryError.biometricError().errorDescription, "Your biometric method has not been recognized")
        @Expect(SystemBiometryError.biometryNotSupported().errorDescription, "This device does not support biometry")
    }

    @TestCase
    func testBiometryType_ReturnsContextBiometryType(): Unit {
        let provider = FakeSystemBiometryProvider()
        let controller: SystemBiometryController = SystemBiometryControllerImpl(provider)

        provider.typeToReturn = LABiometryType.faceID
        @Expect(controller.getBiometryType(), LABiometryType.faceID)

        provider.typeToReturn = LABiometryType.touchID
        @Expect(controller.getBiometryType(), LABiometryType.touchID)

        provider.typeToReturn = LABiometryType.none
        @Expect(controller.getBiometryType(), LABiometryType.none)

        let prod: SystemBiometryController = SystemBiometryControllerImpl()
        @Expect(prod.getBiometryType(), LABiometryType.none)
    }

    @TestCase
    func testOpenSettings_WhenCalled_ThenDoesNotCrash(): Unit {
        let controller: SystemBiometryController = SystemBiometryControllerImpl()
        let actionInvoked = ArrayList<Bool>()
        var crashed = false
        try {
            controller.openSettings({ => actionInvoked.add(true) })
        } catch (_: Exception) {
            crashed = true
        }
        @Expect(crashed, false)
        @Expect(actionInvoked.isEmpty(), true)
    }
}
