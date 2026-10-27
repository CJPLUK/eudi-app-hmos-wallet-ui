/*
 * Host unit tests for KeychainPinThrottleProvider.
 * Migrated from iOS Tests/Provider/TestKeychainPinThrottleProvider.swift (15).
 */
package eudi_logic_authentication

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import eudi_logic_business.{KeyChainController, KeyChainWrapper}

let KC_ATTEMPTS = "pinFailedAttempts"
let KC_STARTED = "pinLockoutStartedAt"
let KC_ENDS = "pinLockoutEndsAt"

class FakeThrottleKeyChain <: KeyChainController {
    let storage = HashMap<String, String>()
    public func storeValue(key: KeyChainWrapper, value: String): Unit { this.storage[key.value] = value }
    public func getValue(key: KeyChainWrapper): ?String { this.storage.get(key.value) }
    public func removeObject(key: KeyChainWrapper): Unit { this.storage.remove(key.value) }
    func putRaw(k: String, v: String): Unit { this.storage[k] = v }
    func getRaw(k: String): ?String { this.storage.get(k) }
}

class FakeAuthenticationConfig <: AuthenticationConfig {
    var maxAttempts: Int64 = 3
    var durations: Array<Float64> = [30.0, 90.0, 300.0]
    public prop maxFailedPinAttempts: Int64 { get() { this.maxAttempts } }
    public prop pinLockoutDurations: Array<Float64> { get() { this.durations } }
}

func makeThrottle(durations: Array<Float64>): (KeychainPinThrottleProvider, FakeThrottleKeyChain) {
    let kc = FakeThrottleKeyChain()
    let cfg = FakeAuthenticationConfig()
    cfg.durations = durations
    return (KeychainPinThrottleProvider(kc, cfg), kc)
}

func failN(provider: KeychainPinThrottleProvider, n: Int64): PinLockoutState {
    var last = PinLockoutState.idle
    for (_ in 0..n) {
        last = provider.recordFailure()
    }
    return last
}

@Test
class TestKeychainPinThrottleProvider {
    @TestCase
    func testGetState_WhenNothingPersisted_ThenIdle(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(provider.getState(), PinLockoutState.idle)
    }

    @TestCase
    func testGetState_WhenEndsAtZero_ThenIdle(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_STARTED, "100.0")
        kc.putRaw(KC_ENDS, "0.0")
        @Expect(provider.getState(), PinLockoutState.idle)
    }

    @TestCase
    func testGetState_WhenNowExceedsEndsAt_ThenIdle(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_STARTED, "1.0")
        kc.putRaw(KC_ENDS, "2.0")
        @Expect(provider.getState(), PinLockoutState.idle)
    }

    @TestCase
    func testGetState_WhenLockoutActive_ThenReturnsRemainingAndTotal(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        failN(provider, 3)
        let state = provider.getState()
        @Expect(state.isActive(), true)
        @Expect(state.total(), 30.0)
        @Expect(state.remaining() > 0.0, true)
    }

    @TestCase
    func testGetState_WhenClockMovedBackwardBeforeStartedAt_ThenReportsFullTotal(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_STARTED, "99999999999.0")
        kc.putRaw(KC_ENDS, "100000000089.0")
        @Expect(provider.getState(), PinLockoutState.active(90.0, 90.0))
    }

    @TestCase
    func testRecordFailure_WhenBelowThreshold_ThenIdleAndCounterIncremented(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(provider.recordFailure(), PinLockoutState.idle)
        @Expect(kc.getRaw(KC_ATTEMPTS) ?? "", "1")
    }

    @TestCase
    func testRecordFailure_WhenThirdFailure_ThenStartsFirstLockoutWith30s(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(failN(provider, 3), PinLockoutState.active(30.0, 30.0))
    }

    @TestCase
    func testRecordFailure_WhenSecondLockoutBatch_ThenEscalatesTo90s(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(failN(provider, 6), PinLockoutState.active(90.0, 90.0))
    }

    @TestCase
    func testRecordFailure_WhenThirdLockoutBatch_ThenEscalatesTo300s(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(failN(provider, 9), PinLockoutState.active(300.0, 300.0))
    }

    @TestCase
    func testRecordFailure_WhenLevelExceedsDurations_ThenReusesLastDuration(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        @Expect(failN(provider, 12), PinLockoutState.active(300.0, 300.0))
    }

    @TestCase
    func testRecordFailure_WhenDurationsEmpty_ThenReturnsActiveWithZeroDuration(): Unit {
        let (provider, _) = makeThrottle(Array<Float64>())
        @Expect(failN(provider, 3), PinLockoutState.active(0.0, 0.0))
    }

    @TestCase
    func testRecordSuccess_ClearsAllPersistedState(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        failN(provider, 3)
        provider.recordSuccess()
        @Expect(provider.getState(), PinLockoutState.idle)
    }

    @TestCase
    func testRecordSuccess_AfterReset_NextLockoutStartsAt30sAgain(): Unit {
        let (provider, _) = makeThrottle([30.0, 90.0, 300.0])
        failN(provider, 3)
        provider.recordSuccess()
        @Expect(failN(provider, 3), PinLockoutState.active(30.0, 30.0))
    }

    @TestCase
    func testGetState_WhenStoredValuesAreNonNumeric_ThenIdle(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_STARTED, "abc")
        kc.putRaw(KC_ENDS, "def")
        @Expect(provider.getState(), PinLockoutState.idle)
    }

    @TestCase
    func testRecordFailure_WhenStoredCounterIsNonNumeric_ThenTreatsAsZero(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_ATTEMPTS, "abc")
        @Expect(provider.recordFailure(), PinLockoutState.idle)
        @Expect(kc.getRaw(KC_ATTEMPTS) ?? "", "1")
    }

    @TestCase
    func testGetState_WhenInvertedWindow_ThenIdle(): Unit {
        let (provider, kc) = makeThrottle([30.0, 90.0, 300.0])
        kc.putRaw(KC_STARTED, "99999999999.0")
        kc.putRaw(KC_ENDS, "2000000000.0")
        @Expect(provider.getState(), PinLockoutState.idle)
    }
}
