// Device-side fakes for feature-common ViewModel tests.
//
// PIN controller / keychain-provider XCTest suites now live as host
// `*_test.cj` next to eudi_logic_authentication (matching iOS XCTest).
// Feature suites still construct FakePinThrottleProvider here.
package eudi_unit_tests

import eudi_logic_authentication.{PinThrottleProvider, PinLockoutState}

class FakePinThrottleProvider <: PinThrottleProvider {
    var state: PinLockoutState = PinLockoutState.idle
    var failureResult: PinLockoutState = PinLockoutState.idle
    var successCount: Int64 = 0
    public func getState(): PinLockoutState { this.state }
    public func recordFailure(): PinLockoutState { this.failureResult }
    public func recordSuccess(): Unit { this.successCount += 1 }
}
