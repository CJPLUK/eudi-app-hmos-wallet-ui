/*
 * Host unit tests for PinStorageControllerImpl.
 * Migrated from iOS logic-authentication/Tests/Controller/TestPinStorageController.swift (3).
 *
 * Layout: co-located *_test.cj, package eudi_logic_authentication.
 * cjpm test discovers this file; cjpm build ignores it.
 */
package eudi_logic_authentication

import std.unittest.*
import std.unittest.testmacro.*

class FakePinStorageProvider <: PinStorageProvider {
    var stored: Bool = false
    var validResult: Bool = false
    var setCount: Int64 = 0
    var lastPin: String = ""
    public func hasPin(): Bool { this.stored }
    public func setPin(pin: String): Unit {
        this.setCount += 1
        this.lastPin = pin
        this.stored = true
    }
    public func isPinValid(_pin: String): Bool { this.validResult }
}

@Test
class TestPinStorageController {
    @TestCase
    func testhasPin(): Unit {
        let provider = FakePinStorageProvider()
        provider.stored = true
        @Expect(PinStorageControllerImpl(provider).hasPin(), true)
        @Expect(PinStorageControllerImpl(FakePinStorageProvider()).hasPin(), false)
    }

    @TestCase
    func testSetPin(): Unit {
        let provider = FakePinStorageProvider()
        let controller = PinStorageControllerImpl(provider)
        controller.setPin("1111")
        @Expect(provider.setCount, 1)
        @Expect(provider.lastPin, "1111")
    }

    @TestCase
    func testIsPinValid(): Unit {
        let provider = FakePinStorageProvider()
        provider.validResult = true
        @Expect(PinStorageControllerImpl(provider).isPinValid("1111"), true)
        let other = FakePinStorageProvider()
        other.validResult = false
        @Expect(PinStorageControllerImpl(other).isPinValid("0000"), false)
    }
}
