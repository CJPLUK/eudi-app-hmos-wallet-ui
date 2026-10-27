/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * eudi_logic_core — EUDI core wallet module (Cangjie HAR).
 *
 * Faithful port of the iOS `logic-core` module (Modules/logic-core/Sources):
 * Config/ Controller/ Coordinator/ DI/ DocumentRegistrationManager/ Error/
 * Extension/ Model/ Provider/ Worker/.
 *
 * Architectural note on the wallet-kit dependency
 * ───────────────────────────────────────────────
 * On iOS this module is a thin facade over the external `EudiWalletKit` SPM
 * package (re-exported via LogicCore.swift) which itself re-exports
 * MdocDataModel18013 / MdocSecurity18013 / MdocDataTransfer18013 / WalletStorage /
 * StatiumSwift. In the HarmonyOS tree the corresponding Cangjie package
 * `eudi_lib_wallet_kit` (and eudi_lib_mdoc / eudi_lib_sdjwt / eudi_lib_openid4vp_vci)
 * are still empty skeletons that export no wallet-domain types
 * (no EudiWallet, no WalletStorage.Document, no DocClaim, no PresentationSession,
 * no OfferedIssuanceModel, no CredentialStatus, …).
 *
 * To migrate logic-core faithfully without depending on types that do not yet
 * exist, the wallet-domain model types this module consumes are reimplemented
 * here (Model/wallet_domain.cj) — these are exactly the iOS MdocDataModel18013 /
 * WalletStorage / EudiWalletKit value types logic-core touches, ported 1:1. The
 * iOS `EudiWallet` engine is represented by the `WalletKit` interface
 * (Controller/wallet_kit.cj); its default implementation performs every
 * orchestration the iOS controller performs over the (real) storage/config layers,
 * and surfaces a typed `WalletCoreError` for the operations that require the
 * not-yet-migrated cryptographic issuance/presentation engine — no silent
 * degradation, no stubs returning empty success.
 */
package eudi_logic_core
