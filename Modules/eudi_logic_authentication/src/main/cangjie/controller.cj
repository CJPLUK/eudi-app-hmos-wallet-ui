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
 * Port of iOS logic-authentication/Sources/Controller/PinStorageController.swift +
 * PinThrottleController.swift. Both controllers are thin pass-throughs delegating
 * to their provider, exactly like the iOS source.
 */
package eudi_logic_authentication

/** Mirrors iOS `public protocol PinStorageController: Sendable`. */
public interface PinStorageController {
    func hasPin(): Bool
    func setPin(pin: String): Unit
    func isPinValid(pin: String): Bool
}

/** Mirrors iOS `final class PinStorageControllerImpl`. */
public class PinStorageControllerImpl <: PinStorageController {
    private let provider: PinStorageProvider

    public init(provider: PinStorageProvider) {
        this.provider = provider
    }

    public func hasPin(): Bool {
        this.provider.hasPin()
    }

    public func setPin(pin: String): Unit {
        this.provider.setPin(pin)
    }

    public func isPinValid(pin: String): Bool {
        this.provider.isPinValid(pin)
    }
}

/** Mirrors iOS `public protocol PinThrottleController: Sendable`. */
public interface PinThrottleController {
    func getState(): PinLockoutState
    func recordFailure(): PinLockoutState
    func recordSuccess(): Unit
}

/** Mirrors iOS `final class PinThrottleControllerImpl`. */
public class PinThrottleControllerImpl <: PinThrottleController {
    private let provider: PinThrottleProvider

    public init(provider: PinThrottleProvider) {
        this.provider = provider
    }

    public func getState(): PinLockoutState {
        this.provider.getState()
    }

    public func recordFailure(): PinLockoutState {
        this.provider.recordFailure()
    }

    public func recordSuccess(): Unit {
        this.provider.recordSuccess()
    }
}
