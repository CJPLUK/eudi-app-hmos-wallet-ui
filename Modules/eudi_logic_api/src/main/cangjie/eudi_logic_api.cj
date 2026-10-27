/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * eudi_logic_api — EUDI network layer (Cangjie HAR).
 * Ported from iOS logic-api module (Sources/).
 *
 * Public surface:
 *   Enum     NetworkMethod                     (network_request.cj)
 *   Struct   NetworkParameter                  (network_request.cj)
 *   Interface NetworkRequest                   (network_request.cj)
 *   Enum     NetworkError                      (network_error.cj)
 *   Interface NetworkSessionProvider           (network_session_provider.cj)
 *   Class    NetworkSessionProviderImpl        (network_session_provider.cj)
 *   Interface NetworkManager                   (network_manager.cj)
 *   Class    NetworkManagerImpl                (network_manager.cj)
 *   Class    WalletInstanceAttestationApi      (wallet_attestation_api.cj)
 *   Class    WalletUnitAttestationApi          (wallet_attestation_api.cj)
 *   Class    WalletInstanceAttestation         (wallet_instance_attestation.cj)
 *   Class    WalletUnitAttestation             (wallet_unit_attestation.cj)
 *   Interface WalletAttestationRepository      (wallet_attestation_repository.cj)
 *   Class    WalletAttestationRepositoryImpl   (wallet_attestation_repository.cj)
 *   Func     makeNetworkSessionProvider        (logic_api_assembly.cj)
 *   Func     makeNetworkManager                (logic_api_assembly.cj)
 *   Func     makeWalletAttestationRepository   (logic_api_assembly.cj)
 *   Func     makeDefaultWalletAttestationRepository (logic_api_assembly.cj)
 */
package eudi_logic_api
