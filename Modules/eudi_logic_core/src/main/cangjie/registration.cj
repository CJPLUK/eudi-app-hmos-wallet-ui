/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Model/RelyingPartyRegistration.swift,
 * Sources/Error/RegistrationRefusedError.swift and the ScopedDocumentsResult /
 * IssuanceResult additions to Model/ScopedDocument.swift (registration
 * certificate trust layer, wallet-kit 0.40.x).
 *
 * iOS `ClaimPath` is represented app-side as `Array<String>` (the same shape
 * `DocClaim.path` already uses); a `None` path marks the whole attestation.
 */
package eudi_logic_core

import std.collection.ArrayList

// ─────────────────────────────────────────────────────────────────────────────
// Model/RelyingPartyRegistration.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `RegistrationDetails` (decoded WRPRC subject fields). */
public struct RegistrationDetails <: Equatable<RegistrationDetails> {
    public let tradeName: String
    public let uniqueId: String
    public let logoUrl: ?String
    public let intendedUse: ?String
    public let privacyPolicyUrl: ?String
    public let serviceDescription: ?String

    public init(
        tradeName!: String,
        uniqueId!: String,
        logoUrl!: ?String = None,
        intendedUse!: ?String = None,
        privacyPolicyUrl!: ?String = None,
        serviceDescription!: ?String = None
    ) {
        this.tradeName = tradeName
        this.uniqueId = uniqueId
        this.logoUrl = logoUrl
        this.intendedUse = intendedUse
        this.privacyPolicyUrl = privacyPolicyUrl
        this.serviceDescription = serviceDescription
    }

    public operator func ==(o: RegistrationDetails): Bool {
        this.tradeName == o.tradeName && this.uniqueId == o.uniqueId
            && optStrEq(this.logoUrl, o.logoUrl) && optStrEq(this.intendedUse, o.intendedUse)
            && optStrEq(this.privacyPolicyUrl, o.privacyPolicyUrl)
            && optStrEq(this.serviceDescription, o.serviceDescription)
    }
    public operator func !=(o: RegistrationDetails): Bool { !(this == o) }
}

/**
 * Mirrors iOS `OveraskedClaim`: one claim (or whole attestation, when `path`
 * is `None`) the relying party asked for without having registered it.
 * `attestationType` is the mdoc docType or the SD-JWT vct.
 */
public struct OveraskedClaim <: Equatable<OveraskedClaim> {
    public let attestationType: String
    public let path: ?Array<String>

    public init(attestationType!: String, path!: ?Array<String> = None) {
        this.attestationType = attestationType
        this.path = path
    }

    /** Mirrors `appliesTo(attestationType:)`. */
    public func appliesTo(attestationType: String): Bool {
        this.attestationType == attestationType
    }

    public operator func ==(o: OveraskedClaim): Bool {
        this.attestationType == o.attestationType && optPathEq(this.path, o.path)
    }
    public operator func !=(o: OveraskedClaim): Bool { !(this == o) }
}

/** Mirrors iOS `RegistrationStatus` (the WRPRC verdict for a relying party). */
public enum RegistrationStatus <: Equatable<RegistrationStatus> {
    /** Registration validated; carries decoded details + over-asked claims. */
    | verified(RegistrationDetails, Array<OveraskedClaim>)
    /** Registration failed validation; details may survive partial decoding. */
    | notVerified(?RegistrationDetails)
    /** Registration was not evaluated at all (feature off / no policy). */
    | notSupported

    /** Mirrors `details` — decoded subject fields where available. */
    public prop details: ?RegistrationDetails {
        get() {
            match (this) {
                case verified(d, _) => Some(d)
                case notVerified(d) => d
                case notSupported => None
            }
        }
    }

    /** Mirrors `overaskedClaims` — empty unless `.verified`. */
    public prop overaskedClaims: Array<OveraskedClaim> {
        get() {
            match (this) {
                case verified(_, claims) => claims
                case _ => Array<OveraskedClaim>()
            }
        }
    }

    /**
     * Mirrors `resolveRequesterName(registrationName:accessCertificateName:)`.
     * A failed registration prefers the authenticated (access-certificate)
     * name over the self-declared registration name.
     */
    public func resolveRequesterName(registrationName!: ?String, accessCertificateName!: ?String): ?String {
        match (this) {
            case verified(_, _) =>
                match (registrationName) {
                    case Some(n) => Some(n)
                    case None => accessCertificateName
                }
            case notVerified(_) =>
                match (accessCertificateName) {
                    case Some(n) => Some(n)
                    case None => registrationName
                }
            case notSupported => accessCertificateName
        }
    }

    public operator func ==(o: RegistrationStatus): Bool {
        match ((this, o)) {
            case (verified(d1, c1), verified(d2, c2)) => d1 == d2 && overaskedEq(c1, c2)
            case (notVerified(d1), notVerified(d2)) =>
                match ((d1, d2)) {
                    case (Some(a), Some(b)) => a == b
                    case (None, None) => true
                    case _ => false
                }
            case (notSupported, notSupported) => true
            case _ => false
        }
    }
    public operator func !=(o: RegistrationStatus): Bool { !(this == o) }
}

/**
 * Mirrors iOS `RelyingPartyRegistration` — the combined two-layer trust verdict
 * for a verifier: `isVerified` is the access-certificate (WRPAC) verdict,
 * `registration` the registration-certificate (WRPRC) verdict.
 */
public struct RelyingPartyRegistration <: Equatable<RelyingPartyRegistration> {
    public let name: ?String
    public let uniqueId: ?String
    public let isVerified: Bool
    public let logoUrl: ?String
    public let registration: RegistrationStatus

    public init(
        name!: ?String,
        uniqueId!: ?String,
        isVerified!: Bool,
        logoUrl!: ?String,
        registration!: RegistrationStatus
    ) {
        this.name = name
        this.uniqueId = uniqueId
        this.isVerified = isVerified
        this.logoUrl = logoUrl
        this.registration = registration
    }

    /**
     * Mirrors `isFullyVerified` — the badge rule: a `notVerified` registration
     * always withholds the badge; otherwise the access-certificate verdict
     * alone decides (so `notSupported` + trusted WRPAC still shows it).
     */
    public prop isFullyVerified: Bool {
        get() {
            match (this.registration) {
                case notVerified(_) => false
                case _ => this.isVerified
            }
        }
    }

    public operator func ==(o: RelyingPartyRegistration): Bool {
        optStrEq(this.name, o.name) && optStrEq(this.uniqueId, o.uniqueId)
            && this.isVerified == o.isVerified && optStrEq(this.logoUrl, o.logoUrl)
            && this.registration == o.registration
    }
    public operator func !=(o: RelyingPartyRegistration): Bool { !(this == o) }
}

/** Mirrors iOS `IssuerRegistration.BlockedReason` (top-level: no nested types). */
public enum IssuerRegistrationBlockedReason <: Equatable<IssuerRegistrationBlockedReason> {
    | notRegisteredAsProvider
    | attestationNotRegistered

    public operator func ==(o: IssuerRegistrationBlockedReason): Bool {
        match ((this, o)) {
            case (notRegisteredAsProvider, notRegisteredAsProvider) => true
            case (attestationNotRegistered, attestationNotRegistered) => true
            case _ => false
        }
    }
    public operator func !=(o: IssuerRegistrationBlockedReason): Bool { !(this == o) }
}

/** Mirrors iOS `IssuerRegistration` — the issuer-side WRPRC verdict. */
public enum IssuerRegistration <: Equatable<IssuerRegistration> {
    | verified(RegistrationDetails)
    | blocked(IssuerRegistrationBlockedReason)

    /** Mirrors `details` — `None` unless `.verified`. */
    public prop details: ?RegistrationDetails {
        get() {
            match (this) {
                case verified(d) => Some(d)
                case blocked(_) => None
            }
        }
    }

    public operator func ==(o: IssuerRegistration): Bool {
        match ((this, o)) {
            case (verified(d1), verified(d2)) => d1 == d2
            case (blocked(r1), blocked(r2)) => r1 == r2
            case _ => false
        }
    }
    public operator func !=(o: IssuerRegistration): Bool { !(this == o) }
}

/**
 * Mirrors iOS `Optional<IssuerRegistration>.vouchesForIssuer`: an absent
 * registration (not evaluated) VOUCHES; a `.blocked` one does not.
 */
public func vouchesForIssuer(registration: ?IssuerRegistration): Bool {
    match (registration) {
        case None => true
        case Some(r) =>
            match (r.details) {
                case Some(_) => true
                case None => false
            }
    }
}

/** Mirrors iOS `IssuanceResult` — issued documents plus the issuer verdict. */
public struct IssuanceResult {
    public let documents: Array<WalletStorageDocument>
    public let issuerRegistration: ?IssuerRegistration

    public init(documents!: Array<WalletStorageDocument>, issuerRegistration!: ?IssuerRegistration = None) {
        this.documents = documents
        this.issuerRegistration = issuerRegistration
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error/RegistrationRefusedError.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `RegistrationRefusedError` — thrown by `reIssueDocument` when the
 * issuer registration is `.blocked`. Recognised by `isTrustBlocked`.
 */
public class RegistrationRefusedError <: Exception {
    public init() {
        super("RegistrationRefusedError")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model/ScopedDocument.swift — ScopedDocumentsResult addition
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors iOS `ScopedDocumentsResult`: partial failure is tolerated — one
 * failing issuer no longer kills the whole Add-document list.
 */
public struct CoreScopedDocumentsResult {
    public let documents: Array<ScopedDocument>
    public let errors: Array<Exception>
    public let totalIssuers: Int64

    public init(documents!: Array<ScopedDocument>, errors!: Array<Exception>, totalIssuers!: Int64) {
        this.documents = documents
        this.errors = errors
        this.totalIssuers = totalIssuers
    }

    /** Mirrors `allIssuersFailed`. */
    public prop allIssuersFailed: Bool {
        get() { this.totalIssuers > 0 && Int64(this.errors.size) == this.totalIssuers }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local helpers
// ─────────────────────────────────────────────────────────────────────────────

func optStrEq(a: ?String, b: ?String): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => x == y
        case (None, None) => true
        case _ => false
    }
}

func optPathEq(a: ?Array<String>, b: ?Array<String>): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => pathEq(x, y)
        case (None, None) => true
        case _ => false
    }
}

func pathEq(a: Array<String>, b: Array<String>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) { return false }
        i++
    }
    return true
}

func overaskedEq(a: Array<OveraskedClaim>, b: Array<OveraskedClaim>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) { return false }
        i++
    }
    return true
}

/**
 * Mirrors `[PresentationPolicyViolation].toOveraskedClaims()` de-duplication:
 * append `claim` unless an equal one is already present (order-preserving).
 */
public func appendUniqueOveraskedClaim(list: ArrayList<OveraskedClaim>, claim: OveraskedClaim): Unit {
    for (existing in list) {
        if (existing == claim) { return }
    }
    list.add(claim)
}
