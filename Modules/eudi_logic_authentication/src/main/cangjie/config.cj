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
 * Port of iOS logic-authentication/Sources/Config/AuthenticationConfig.swift.
 *
 * iOS `protocol AuthenticationConfig` → Cangjie interface; `struct
 * AuthenticationConfigImpl` → class. `[TimeInterval]` (seconds, Double) →
 * `Array<Float64>`, preserving the exact default values.
 */
package eudi_logic_authentication

/** Mirrors iOS `protocol AuthenticationConfig: Sendable`. */
public interface AuthenticationConfig {
    /** Number of consecutive wrong PIN attempts allowed before the user is locked out. */
    prop maxFailedPinAttempts: Int64

    /**
     * Lockout durations (in seconds) applied each time the user reaches
     * `maxFailedPinAttempts`. The list indexes by lockout level (0 = first
     * lockout). Once the user exceeds the size of the list, the last entry is
     * reused for every subsequent lockout.
     */
    prop pinLockoutDurations: Array<Float64>
}

/** Mirrors iOS `struct AuthenticationConfigImpl`. */
public class AuthenticationConfigImpl <: AuthenticationConfig {
    public init() {}

    public prop maxFailedPinAttempts: Int64 {
        get() { 3 }
    }

    public prop pinLockoutDurations: Array<Float64> {
        get() { [30.0, 90.0, 300.0] }
    }
}
