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
 * Port of iOS logic-core/Sources/Extension/Error+IssuerTrust.swift
 * (isIssuerNotTrusted → isTrustBlocked, registration certificate trust layer).
 */
package eudi_logic_core

import ohos_app_cangjie_eudi_cjmdoc_security.security.issuer_auth.MsoValidationError
import ohos_app_cangjie_eudi_cjmdoc_security.security.issuer_auth.MsoValidationErrorKind
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.{WalletError, WalletErrorCode}
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.error.WRPRCError
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vp.error.VpValidationError

/**
 * Mirrors iOS `Error.isTrustBlocked` (renamed from `isIssuerNotTrusted`).
 *
 * Callers use this to turn a caught exception into a dedicated "blocked because
 * the other side could not be verified" outcome instead of a generic failure.
 *
 * Five signals count as trust-blocked, matching the five iOS branches:
 *
 *  - `WRPRCError` — the OpenID4VCI registration-certificate extraction /
 *    enforcement errors (missing issuer_info, missing/multiple WRPRC, missing
 *    WRPAC, policy not met).
 *  - `RegistrationRefusedError` — thrown by `reIssueDocument` when the issuer
 *    registration is `.blocked`.
 *  - `WalletError` whose `code` is `TrustError` OR `InvalidWrprc`.
 *  - `WalletError` whose `innerError` is an OpenID4VP `VpValidationError` with
 *    `isAuthorizationPolicyNotMet()` (the Enforce-policy presentation refusal).
 *  - `MsoValidationError` whose kind is `IssuerTrustFailed`, including one
 *    nested arbitrarily deep inside `MultipleErrors` (unchanged from before).
 *
 * An extra app-level signal is also accepted: `WalletCoreError.issuerNotTrusted`.
 * Issuance / presentation fakes raise that kind so UI wiring can be tested
 * without driving the engine. It is not an iOS branch.
 *
 * Everything else — other error kinds, other engine codes, plain exceptions —
 * is not a trust failure and must keep flowing down the generic error path.
 */
public func isTrustBlocked(error: Exception): Bool {
    match (error) {
        case _: WRPRCError => return true
        case _: RegistrationRefusedError => return true
        case walletError: WalletError =>
            match (walletError.code) {
                case Some(code) =>
                    match (code) {
                        case WalletErrorCode.TrustError => return true
                        case WalletErrorCode.InvalidWrprc => return true
                        case _ => ()
                    }
                case None => ()
            }
            match (walletError.innerError) {
                case Some(inner) =>
                    match (inner) {
                        case vpError: VpValidationError => return vpError.isAuthorizationPolicyNotMet()
                        case _ => return false
                    }
                case None => return false
            }
        case walletCoreError: WalletCoreError =>
            return walletCoreError.kind == WalletCoreErrorKind.issuerNotTrusted
        case msoError: MsoValidationError =>
            return containsIssuerTrustFailure(msoError)
        case _ => return false
    }
}

/**
 * Mirrors iOS `MsoValidationError.containsIssuerTrustFailure`: a trust failure
 * anywhere in the tree makes the whole validation a trust failure, so
 * `MultipleErrors` is walked recursively rather than one level deep.
 */
func containsIssuerTrustFailure(error: MsoValidationError): Bool {
    match (error.kind) {
        case MsoValidationErrorKind.IssuerTrustFailed(_) => return true
        case MsoValidationErrorKind.MultipleErrors(nested) =>
            for (child in nested) {
                if (containsIssuerTrustFailure(child)) {
                    return true
                }
            }
            return false
        case _ => return false
    }
}
