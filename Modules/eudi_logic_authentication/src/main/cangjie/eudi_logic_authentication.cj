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
 * eudi_logic_authentication — Cangjie port of the iOS logic-authentication module.
 *
 * Surface (see the per-file ports):
 *   - AuthenticationConfig / AuthenticationConfigImpl   (config.cj)
 *   - PinStorageProvider / PinThrottleProvider          (provider.cj)
 *   - PinLockoutState                                   (provider.cj)
 *   - KeychainPinStorageProvider                        (keychain_pin_storage_provider.cj)
 *   - KeychainPinThrottleProvider                       (keychain_pin_throttle_provider.cj)
 *   - PinStorageController / PinThrottleController       (controller.cj)
 *   - SystemBiometryController + SystemBiometryError     (system_biometry_controller.cj)
 *   - AuthenticationError                               (error.cj)
 *   - LogicAuthAssembly                                 (assembly.cj)
 */
package eudi_logic_authentication
