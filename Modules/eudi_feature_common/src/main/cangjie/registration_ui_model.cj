/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS feature-common
 * module (Sources/UI/Request/Model/RelyingPartyRegistrationUiModel.swift) to
 * Cangjie (registration certificate trust layer, wallet-kit 0.40.x).
 *
 * The iOS extensions on `RelyingPartyRegistration` and
 * `Optional<IssuerRegistration>` become top-level mapping funcs (Cangjie has
 * no extensions-on-Option); the issuer variant carries a distinct name so
 * overload resolution never has to disambiguate on named parameters.
 */
package eudi_feature_common

import eudi_logic_core.{RelyingPartyRegistration, RegistrationStatus, RegistrationDetails, IssuerRegistration}
import eudi_logic_ui.{RegisteredParty, RelyingPartyRegistrationData}
import eudi_logic_resources.{LocalizableStringKey}

/**
 * Mirrors iOS `RegistrationWarning`: which registration verdict gates the
 * Share button behind an explicit risk acknowledgement.
 */
public enum RegistrationWarning <: Equatable<RegistrationWarning> {
    | relyingPartyNotVerified
    | relyingPartyOverasked

    /** Mirrors `message` — the warning banner text. */
    public prop message: LocalizableStringKey {
        get() {
            match (this) {
                case relyingPartyNotVerified => LocalizableStringKey.relyingPartyNotVerifiedWarning
                case relyingPartyOverasked => LocalizableStringKey.relyingPartyOveraskedWarning
            }
        }
    }

    /** Mirrors `acknowledgement` — the toggle label. */
    public prop acknowledgement: LocalizableStringKey {
        get() { LocalizableStringKey.understandRisksAgree }
    }

    public operator func ==(o: RegistrationWarning): Bool {
        match ((this, o)) {
            case (relyingPartyNotVerified, relyingPartyNotVerified) => true
            case (relyingPartyOverasked, relyingPartyOverasked) => true
            case _ => false
        }
    }
    public operator func !=(o: RegistrationWarning): Bool { !(this == o) }
}

/**
 * Mirrors iOS `RelyingPartyRegistration.toRegistrationData(fallbackName:)`:
 * even a failed registration still describes the requester (details survive
 * partial decoding), so privacy policy / intended use come from
 * `registration.details` regardless of the verdict.
 */
public func toRegistrationData(
    registration: RelyingPartyRegistration,
    fallbackName!: LocalizableStringKey
): RelyingPartyRegistrationData {
    let details = registration.registration.details
    let name = match (registration.name) {
        case Some(n) => LocalizableStringKey.custom(n)
        case None => fallbackName
    }
    let identifier: ?LocalizableStringKey = match (registration.uniqueId) {
        case Some(id) => Some(LocalizableStringKey.relyingPartyId([id]))
        case None => None
    }
    let intendedUse: ?LocalizableStringKey = match (details) {
        case Some(d) =>
            match (d.intendedUse) {
                case Some(use) => Some(LocalizableStringKey.custom(use))
                case None => None
            }
        case None => None
    }
    let privacyPolicyUrl = match (details) {
        case Some(d) => d.privacyPolicyUrl ?? ""
        case None => ""
    }
    return RelyingPartyRegistrationData(
        primary: RegisteredParty(
            name: name,
            identifier: identifier,
            isVerified: registration.isFullyVerified,
            logoUrl: registration.logoUrl ?? ""
        ),
        privacyPolicyUrl: privacyPolicyUrl,
        intendedUse: intendedUse
    )
}

/**
 * Mirrors iOS `RelyingPartyRegistration.toWarning()`: verified with
 * over-asked claims warns about over-asking, a failed registration warns
 * about the unverified party, `notSupported` (feature off) never warns.
 */
public func toWarning(registration: RelyingPartyRegistration): ?RegistrationWarning {
    match (registration.registration) {
        case RegistrationStatus.verified(_, overaskedClaims) =>
            if (overaskedClaims.size > 0) {
                return Some(RegistrationWarning.relyingPartyOverasked)
            }
            return None
        case RegistrationStatus.notVerified(_) => Some(RegistrationWarning.relyingPartyNotVerified)
        case RegistrationStatus.notSupported => None
    }
}

/**
 * Mirrors iOS `Optional<IssuerRegistration>.toRegistrationData(issuerName:
 * issuerLogo:)` — the issuance-side header data: an absent/blocked
 * registration keeps the issuer name but drops the seal and details.
 */
public func issuerToRegistrationData(
    issuerRegistration!: ?IssuerRegistration,
    issuerName!: String,
    issuerLogo!: ?String = None
): RelyingPartyRegistrationData {
    let details: ?RegistrationDetails = match (issuerRegistration) {
        case Some(r) => r.details
        case None => None
    }
    let identifier: ?LocalizableStringKey = match (details) {
        case Some(d) => Some(LocalizableStringKey.relyingPartyId([d.uniqueId]))
        case None => None
    }
    let isVerified = match (details) {
        case Some(_) => true
        case None => false
    }
    let logoUrl = match (details) {
        case Some(d) => d.logoUrl ?? (issuerLogo ?? "")
        case None => issuerLogo ?? ""
    }
    let privacyPolicyUrl = match (details) {
        case Some(d) => d.privacyPolicyUrl ?? ""
        case None => ""
    }
    let intendedUse: ?LocalizableStringKey = match (details) {
        case Some(d) =>
            match (d.intendedUse) {
                case Some(use) => Some(LocalizableStringKey.custom(use))
                case None => None
            }
        case None => None
    }
    return RelyingPartyRegistrationData(
        primary: RegisteredParty(
            name: LocalizableStringKey.custom(issuerName),
            identifier: identifier,
            isVerified: isVerified,
            logoUrl: logoUrl
        ),
        privacyPolicyUrl: privacyPolicyUrl,
        intendedUse: intendedUse
    )
}
