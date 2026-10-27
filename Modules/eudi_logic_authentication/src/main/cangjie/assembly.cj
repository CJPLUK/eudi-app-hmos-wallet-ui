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
 * Port of iOS logic-authentication/Sources/DI/LogicAuthAssembly.swift.
 *
 * iOS Swinject `Assembly.assemble(container:)` → Cangjie factory class, matching
 * the pattern established by eudi_logic_core.LogicCoreAssembly (resolveX accessors,
 * object scopes reproduced):
 *   .container  → a single shared instance held by this assembly
 *   .graph      → one instance per assembly (cached here, the wallet builds one
 *                 LogicAuthAssembly per object graph)
 *   .transient  → freshly built per call (SystemBiometryController)
 *
 * The cross-module `KeyChainController` the iOS container resolved from the
 * logic-business registration is supplied at construction (it is owned by
 * eudi_logic_core.LogicCoreAssembly on the Cangjie side; the type itself lives
 * in eudi_logic_business, matching iOS logic-business).
 */
package eudi_logic_authentication

import eudi_logic_business.KeyChainController

/** Mirrors iOS `final class LogicAuthAssembly: Assembly`. */
public class LogicAuthAssembly {
    private let keyChainController: KeyChainController

    // .container-scoped singleton (lazily built, then cached).
    private var cachedAuthenticationConfig: ?AuthenticationConfig = None

    // .graph-scoped instances (one per assembly).
    private var cachedPinStorageProvider: ?PinStorageProvider = None
    private var cachedPinStorageController: ?PinStorageController = None
    private var cachedPinThrottleProvider: ?PinThrottleProvider = None
    private var cachedPinThrottleController: ?PinThrottleController = None

    public init(keyChainController: KeyChainController) {
        this.keyChainController = keyChainController
    }

    /** .container AuthenticationConfig. */
    public func resolveAuthenticationConfig(): AuthenticationConfig {
        match (this.cachedAuthenticationConfig) {
            case Some(v) => return v
            case None =>
                let v = AuthenticationConfigImpl()
                this.cachedAuthenticationConfig = v
                return v
        }
    }

    /** .graph PinStorageProvider (KeychainPinStorageProvider). */
    public func resolvePinStorageProvider(): PinStorageProvider {
        match (this.cachedPinStorageProvider) {
            case Some(v) => return v
            case None =>
                let v = KeychainPinStorageProvider(this.keyChainController)
                this.cachedPinStorageProvider = v
                return v
        }
    }

    /** .graph PinStorageController. */
    public func resolvePinStorageController(): PinStorageController {
        match (this.cachedPinStorageController) {
            case Some(v) => return v
            case None =>
                let v = PinStorageControllerImpl(this.resolvePinStorageProvider())
                this.cachedPinStorageController = v
                return v
        }
    }

    /** .graph PinThrottleProvider (KeychainPinThrottleProvider). */
    public func resolvePinThrottleProvider(): PinThrottleProvider {
        match (this.cachedPinThrottleProvider) {
            case Some(v) => return v
            case None =>
                let v = KeychainPinThrottleProvider(
                    this.keyChainController,
                    this.resolveAuthenticationConfig()
                )
                this.cachedPinThrottleProvider = v
                return v
        }
    }

    /** .graph PinThrottleController. */
    public func resolvePinThrottleController(): PinThrottleController {
        match (this.cachedPinThrottleController) {
            case Some(v) => return v
            case None =>
                let v = PinThrottleControllerImpl(this.resolvePinThrottleProvider())
                this.cachedPinThrottleController = v
                return v
        }
    }

    /** .transient SystemBiometryController (fresh per call, mirroring iOS). */
    public func resolveSystemBiometryController(): SystemBiometryController {
        return SystemBiometryControllerImpl()
    }
}
