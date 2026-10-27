/*
 * Host unit tests for PinThrottleControllerImpl.
 * Migrated from iOS logic-authentication/Tests/Controller/TestPinThrottleController.swift (5).
 */
package eudi_logic_authentication

import std.unittest.*
import std.unittest.testmacro.*

class FakePinThrottleProvider <: PinThrottleProvider {
    var state: PinLockoutState = PinLockoutState.idle
    var failureResult: PinLockoutState = PinLockoutState.idle
    var successCount: Int64 = 0
    public func getState(): PinLockoutState { this.state }
    public func recordFailure(): PinLockoutState { this.failureResult }
    public func recordSuccess(): Unit { this.successCount += 1 }
}

@Test
class TestPinThrottleController {
    @TestCase
    func testGetState_WhenProviderReturnsIdle_ThenReturnsIdle(): Unit {
        let provider = FakePinThrottleProvider()
        provider.state = PinLockoutState.idle
        @Expect(PinThrottleControllerImpl(provider).getState(), PinLockoutState.idle)
    }

    @TestCase
    func testGetState_WhenProviderReturnsActiveLockout_ThenReturnsActiveLockout(): Unit {
        let expected = PinLockoutState.active(30.0, 90.0)
        let provider = FakePinThrottleProvider()
        provider.state = expected
        @Expect(PinThrottleControllerImpl(provider).getState(), expected)
    }

    @TestCase
    func testRecordFailure_WhenProviderReturnsIdle_ThenForwardsIdle(): Unit {
        let provider = FakePinThrottleProvider()
        provider.failureResult = PinLockoutState.idle
        @Expect(PinThrottleControllerImpl(provider).recordFailure(), PinLockoutState.idle)
    }

    @TestCase
    func testRecordFailure_WhenProviderReturnsActiveLockout_ThenForwardsLockout(): Unit {
        let expected = PinLockoutState.active(60.0, 300.0)
        let provider = FakePinThrottleProvider()
        provider.failureResult = expected
        @Expect(PinThrottleControllerImpl(provider).recordFailure(), expected)
    }

    @TestCase
    func testRecordSuccess_WhenCalled_ThenDelegatesToProvider(): Unit {
        let provider = FakePinThrottleProvider()
        PinThrottleControllerImpl(provider).recordSuccess()
        @Expect(provider.successCount, 1)
    }
}
