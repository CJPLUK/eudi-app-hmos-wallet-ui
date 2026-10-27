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
 * Port of iOS logic-authentication/Sources/Provider/PinStorageProvider.swift +
 * PinThrottleProvider.swift.
 *
 * iOS `protocol` → Cangjie interface; the `PinLockoutState` enum (with associated
 * values on the `.active` case) → Cangjie enum. `TimeInterval` (seconds) →
 * `Float64`.
 */
package eudi_logic_authentication

/** Mirrors iOS `enum PinLockoutState: Sendable, Equatable`. */
public enum PinLockoutState <: Equatable<PinLockoutState> {
    | idle
    | active(Float64, Float64) // (remaining, total)

    /** Convenience accessor for the remaining lockout seconds (0 when idle). */
    public func remaining(): Float64 {
        match (this) {
            case idle => 0.0
            case active(r, _) => r
        }
    }

    /** Convenience accessor for the total lockout seconds (0 when idle). */
    public func total(): Float64 {
        match (this) {
            case idle => 0.0
            case active(_, t) => t
        }
    }

    public func isActive(): Bool {
        match (this) {
            case idle => false
            case active(_, _) => true
        }
    }

    public operator func ==(o: PinLockoutState): Bool {
        match ((this, o)) {
            case (idle, idle) => true
            case (active(r1, t1), active(r2, t2)) => r1 == r2 && t1 == t2
            case _ => false
        }
    }
    public operator func !=(o: PinLockoutState): Bool { !(this == o) }
}

/** Mirrors iOS `protocol PinStorageProvider: Sendable`. */
public interface PinStorageProvider {
    func hasPin(): Bool
    func setPin(pin: String): Unit
    func isPinValid(pin: String): Bool
}

/** Mirrors iOS `protocol PinThrottleProvider: Sendable`. */
public interface PinThrottleProvider {
    /** Returns the current lockout state, evaluating wall-clock time against persisted values. */
    func getState(): PinLockoutState

    /**
     * Records a failed PIN attempt. If the failure count reaches the configured
     * threshold, a new lockout is started using the next duration from the
     * configured list.
     *
     * @return The resulting `PinLockoutState` after recording the failure.
     */
    func recordFailure(): PinLockoutState

    /**
     * Clears all throttle state (counters, lockout level, timestamps).
     * Called after a successful authentication (PIN or biometric).
     */
    func recordSuccess(): Unit
}
