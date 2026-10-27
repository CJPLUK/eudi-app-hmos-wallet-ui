/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Model/DeferrredDocument.swift plus the concrete
 * issued-document model the wallet store holds (iOS gets this conformer from
 * MdocDataModel18013; reproduced here as a DocClaimsDecodable conformer).
 */
package eudi_logic_core

import std.collection.HashMap
import std.time.DateTime

/**
 * Mirrors iOS `public struct DeferrredDocument: DocClaimsDecodable`.
 * (Spelling kept readable as `DeferredDocument` in Cangjie.)
 */
public class DeferredDocument <: DocClaimsDecodable {
    private let _id: String
    private let _statusIdentifier: ?StatusIdentifier
    private let _createdAt: DateTime
    private let _modifiedAt: ?DateTime
    private let _displayName: ?String
    private let _docType: String
    private let _docClaims: Array<DocClaim>
    private let _docDataFormat: DocDataFormat
    private let _ageOverXX: HashMap<Int64, Bool>
    private let _display: ?Array<DisplayMetadata>
    private let _issuerDisplay: ?Array<DisplayMetadata>
    private let _credentialIssuerIdentifier: ?String
    private let _configurationIdentifier: ?String
    private let _validFrom: ?DateTime
    private let _validUntil: ?DateTime
    private let _secureAreaName: ?String
    private let _credentialsUsageCounts: ?CredentialsUsageCounts
    private let _credentialPolicy: CredentialPolicy

    public init(
        id!: String,
        statusIdentifier!: ?StatusIdentifier = None,
        createdAt!: DateTime,
        modifiedAt!: ?DateTime = None,
        displayName!: ?String = None,
        docType!: String,
        docClaims!: Array<DocClaim> = Array<DocClaim>(),
        docDataFormat!: DocDataFormat,
        ageOverXX!: HashMap<Int64, Bool> = HashMap<Int64, Bool>(),
        display!: ?Array<DisplayMetadata> = None,
        issuerDisplay!: ?Array<DisplayMetadata> = None,
        credentialIssuerIdentifier!: ?String = None,
        configurationIdentifier!: ?String = None,
        validFrom!: ?DateTime = None,
        validUntil!: ?DateTime = None,
        secureAreaName!: ?String = None,
        credentialsUsageCounts!: ?CredentialsUsageCounts = None,
        credentialPolicy!: CredentialPolicy = CredentialPolicy.oneTimeUse
    ) {
        this._id = id
        this._statusIdentifier = statusIdentifier
        this._createdAt = createdAt
        this._modifiedAt = modifiedAt
        this._displayName = displayName
        this._docType = docType
        this._docClaims = docClaims
        this._docDataFormat = docDataFormat
        this._ageOverXX = ageOverXX
        this._display = display
        this._issuerDisplay = issuerDisplay
        this._credentialIssuerIdentifier = credentialIssuerIdentifier
        this._configurationIdentifier = configurationIdentifier
        this._validFrom = validFrom
        this._validUntil = validUntil
        this._secureAreaName = secureAreaName
        this._credentialsUsageCounts = credentialsUsageCounts
        this._credentialPolicy = credentialPolicy
    }

    public prop id: String { get() { this._id } }
    public prop statusIdentifier: ?StatusIdentifier { get() { this._statusIdentifier } }
    public prop createdAt: DateTime { get() { this._createdAt } }
    public prop modifiedAt: ?DateTime { get() { this._modifiedAt } }
    public prop displayName: ?String { get() { this._displayName } }
    public prop docType: String { get() { this._docType } }
    public prop docClaims: Array<DocClaim> { get() { this._docClaims } }
    public prop docDataFormat: DocDataFormat { get() { this._docDataFormat } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { this._ageOverXX } }
    public prop display: ?Array<DisplayMetadata> { get() { this._display } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { this._issuerDisplay } }
    public prop credentialIssuerIdentifier: ?String { get() { this._credentialIssuerIdentifier } }
    public prop configurationIdentifier: ?String { get() { this._configurationIdentifier } }
    public prop validFrom: ?DateTime { get() { this._validFrom } }
    public prop validUntil: ?DateTime { get() { this._validUntil } }
    public prop secureAreaName: ?String { get() { this._secureAreaName } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { this._credentialsUsageCounts } }
    public prop credentialPolicy: CredentialPolicy { get() { this._credentialPolicy } }
}

/**
 * The concrete issued-document model the wallet store holds. On iOS this is a
 * MdocDataModel18013 conformer (MdocDecodable / DocClaimsDecodable); reproduced
 * here as a mutable DocClaimsDecodable so the wallet store can update usage
 * counts / revocation status the way the wallet engine does.
 */
public class IssuedDocument <: DocClaimsDecodable {
    private let _id: String
    private var _statusIdentifier: ?StatusIdentifier
    private let _createdAt: DateTime
    private var _modifiedAt: ?DateTime
    private let _displayName: ?String
    private let _docType: String
    private let _docClaims: Array<DocClaim>
    private let _docDataFormat: DocDataFormat
    private let _ageOverXX: HashMap<Int64, Bool>
    private let _display: ?Array<DisplayMetadata>
    private let _issuerDisplay: ?Array<DisplayMetadata>
    private let _credentialIssuerIdentifier: ?String
    private let _configurationIdentifier: ?String
    private let _validFrom: ?DateTime
    private var _validUntil: ?DateTime
    private let _secureAreaName: ?String
    private var _credentialsUsageCounts: ?CredentialsUsageCounts
    private let _credentialPolicy: CredentialPolicy

    public init(
        id!: String,
        statusIdentifier!: ?StatusIdentifier = None,
        createdAt!: DateTime,
        modifiedAt!: ?DateTime = None,
        displayName!: ?String = None,
        docType!: String,
        docClaims!: Array<DocClaim> = Array<DocClaim>(),
        docDataFormat!: DocDataFormat = DocDataFormat.cbor,
        ageOverXX!: HashMap<Int64, Bool> = HashMap<Int64, Bool>(),
        display!: ?Array<DisplayMetadata> = None,
        issuerDisplay!: ?Array<DisplayMetadata> = None,
        credentialIssuerIdentifier!: ?String = None,
        configurationIdentifier!: ?String = None,
        validFrom!: ?DateTime = None,
        validUntil!: ?DateTime = None,
        secureAreaName!: ?String = None,
        credentialsUsageCounts!: ?CredentialsUsageCounts = None,
        credentialPolicy!: CredentialPolicy = CredentialPolicy.oneTimeUse
    ) {
        this._id = id
        this._statusIdentifier = statusIdentifier
        this._createdAt = createdAt
        this._modifiedAt = modifiedAt
        this._displayName = displayName
        this._docType = docType
        this._docClaims = docClaims
        this._docDataFormat = docDataFormat
        this._ageOverXX = ageOverXX
        this._display = display
        this._issuerDisplay = issuerDisplay
        this._credentialIssuerIdentifier = credentialIssuerIdentifier
        this._configurationIdentifier = configurationIdentifier
        this._validFrom = validFrom
        this._validUntil = validUntil
        this._secureAreaName = secureAreaName
        this._credentialsUsageCounts = credentialsUsageCounts
        this._credentialPolicy = credentialPolicy
    }

    public prop id: String { get() { this._id } }
    public prop statusIdentifier: ?StatusIdentifier { get() { this._statusIdentifier } }
    public prop createdAt: DateTime { get() { this._createdAt } }
    public prop modifiedAt: ?DateTime { get() { this._modifiedAt } }
    public prop displayName: ?String { get() { this._displayName } }
    public prop docType: String { get() { this._docType } }
    public prop docClaims: Array<DocClaim> { get() { this._docClaims } }
    public prop docDataFormat: DocDataFormat { get() { this._docDataFormat } }
    public prop ageOverXX: HashMap<Int64, Bool> { get() { this._ageOverXX } }
    public prop display: ?Array<DisplayMetadata> { get() { this._display } }
    public prop issuerDisplay: ?Array<DisplayMetadata> { get() { this._issuerDisplay } }
    public prop credentialIssuerIdentifier: ?String { get() { this._credentialIssuerIdentifier } }
    public prop configurationIdentifier: ?String { get() { this._configurationIdentifier } }
    public prop validFrom: ?DateTime { get() { this._validFrom } }
    public prop validUntil: ?DateTime { get() { this._validUntil } }
    public prop secureAreaName: ?String { get() { this._secureAreaName } }
    public prop credentialsUsageCounts: ?CredentialsUsageCounts { get() { this._credentialsUsageCounts } }
    public prop credentialPolicy: CredentialPolicy { get() { this._credentialPolicy } }

    /** Wallet-engine mutation: refresh remaining-usage counters. */
    public func setUsageCounts(counts: ?CredentialsUsageCounts): Unit {
        this._credentialsUsageCounts = counts
    }
}
