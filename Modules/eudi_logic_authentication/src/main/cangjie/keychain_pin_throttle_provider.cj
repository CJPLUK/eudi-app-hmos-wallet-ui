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
 * Port of iOS logic-authentication/Sources/Storage/KeychainPinThrottleProvider.swift.
 *
 * Failed-attempt counters, lockout level and lockout timestamps are persisted
 * through eudi_logic_business.KeyChainController (the wallet's real secure key/value
 * store on HarmonyOS). `Date().timeIntervalSince1970` (Float64 seconds) maps to
 * `DateTime.now().toUnixTimeStamp()` converted to fractional seconds. All
 * lockout-arithmetic and threshold logic is preserved 1:1.
 */
package eudi_logic_authentication

import std.convert.*
import std.time.DateTime
import eudi_logic_business.KeyChainController
import eudi_logic_business.KeyChainWrapper

/** Mirrors iOS `KeychainPinThrottleProvider`'s nested `KeyIdentifier: KeyChainWrapper`. */
class PinThrottleKeyIdentifier <: KeyChainWrapper {
    static let pinFailedAttempts = PinThrottleKeyIdentifier("pinFailedAttempts")
    static let pinLockoutLevel = PinThrottleKeyIdentifier("pinLockoutLevel")
    static let pinLockoutStartedAt = PinThrottleKeyIdentifier("pinLockoutStartedAt")
    static let pinLockoutEndsAt = PinThrottleKeyIdentifier("pinLockoutEndsAt")

    private let raw: String
    init(raw: String) { this.raw = raw }
    public prop value: String { get() { this.raw } }
}

/** Mirrors iOS `KeychainPinThrottleProvider`. */
public class KeychainPinThrottleProvider <: PinThrottleProvider {
    private let keyChainController: KeyChainController
    private let authenticationConfig: AuthenticationConfig

    public init(keyChainController: KeyChainController, authenticationConfig: AuthenticationConfig) {
        this.keyChainController = keyChainController
        this.authenticationConfig = authenticationConfig
    }

    public func getState(): PinLockoutState {
        let startedAt = getDouble(PinThrottleKeyIdentifier.pinLockoutStartedAt)
        let endsAt = getDouble(PinThrottleKeyIdentifier.pinLockoutEndsAt)

        if (!(startedAt > 0.0) || !(endsAt > 0.0) || endsAt <= startedAt) {
            return PinLockoutState.idle
        }

        let rawTotal = endsAt - startedAt
        let total = if (rawTotal > 0.0) { rawTotal } else { 0.0 }
        let now = nowSeconds()

        if (now >= endsAt) {
            return PinLockoutState.idle
        }

        if (now < startedAt) {
            return PinLockoutState.active(total, total)
        }

        return PinLockoutState.active(endsAt - now, total)
    }

    public func recordFailure(): PinLockoutState {
        let currentAttempts = getInt(PinThrottleKeyIdentifier.pinFailedAttempts)
        let newAttempts = currentAttempts + 1
        let maxAttempts = this.authenticationConfig.maxFailedPinAttempts

        if (newAttempts < maxAttempts) {
            setInt(newAttempts, PinThrottleKeyIdentifier.pinFailedAttempts)
            return PinLockoutState.idle
        }

        let currentLevel = getInt(PinThrottleKeyIdentifier.pinLockoutLevel)
        let durations = this.authenticationConfig.pinLockoutDurations
        let duration: Float64
        if (durations.isEmpty()) {
            duration = 0.0
        } else {
            let lastIndex = durations.size - 1
            let idx = if (currentLevel < lastIndex) { currentLevel } else { lastIndex }
            duration = durations[idx]
        }

        let now = nowSeconds()
        let endsAt = now + duration

        setInt(0, PinThrottleKeyIdentifier.pinFailedAttempts)
        setInt(currentLevel + 1, PinThrottleKeyIdentifier.pinLockoutLevel)
        setDouble(now, PinThrottleKeyIdentifier.pinLockoutStartedAt)
        setDouble(endsAt, PinThrottleKeyIdentifier.pinLockoutEndsAt)

        return PinLockoutState.active(duration, duration)
    }

    public func recordSuccess(): Unit {
        setInt(0, PinThrottleKeyIdentifier.pinFailedAttempts)
        setInt(0, PinThrottleKeyIdentifier.pinLockoutLevel)
        setDouble(0.0, PinThrottleKeyIdentifier.pinLockoutStartedAt)
        setDouble(0.0, PinThrottleKeyIdentifier.pinLockoutEndsAt)
    }

    // ── persistence helpers (mirror the iOS private extension) ────────────────

    private func nowSeconds(): Float64 {
        // Mirrors `Date().timeIntervalSince1970`: fractional seconds since UnixEpoch.
        let millis = DateTime.now().toUnixTimeStamp().toMilliseconds()
        return Float64(millis) / 1000.0
    }

    private func getInt(key: KeyChainWrapper): Int64 {
        match (this.keyChainController.getValue(key)) {
            case None => return 0
            case Some(raw) => return Int64.tryParse(raw) ?? 0
        }
    }

    private func getDouble(key: KeyChainWrapper): Float64 {
        match (this.keyChainController.getValue(key)) {
            case None => return 0.0
            case Some(raw) => return Float64.tryParse(raw) ?? 0.0
        }
    }

    private func setInt(value: Int64, key: KeyChainWrapper): Unit {
        this.keyChainController.storeValue(key, "${value}")
    }

    private func setDouble(value: Float64, key: KeyChainWrapper): Unit {
        let stored = if (value == value) { value } else { 0.0 }
        this.keyChainController.storeValue(key, "${stored}")
    }
}
