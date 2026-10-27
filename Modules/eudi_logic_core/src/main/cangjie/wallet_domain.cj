/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); ...
 *
 * Wallet-domain value types consumed by logic-core.
 *
 * On iOS these live in the external SPM packages re-exported by EudiWalletKit:
 *   - MdocDataModel18013 : DocClaim, DocClaimsDecodable, DocDataFormat, DisplayMetadata,
 *                          DocMetadata, StatusIdentifier, CredentialsUsageCounts,
 *                          CredentialPolicy, TransactionLog, TransactionLogData,
 *                          DocElements, CredentialStatus, DocumentStatus
 *   - WalletStorage      : Document
 *   - EudiWalletKit      : OfferedIssuanceModel, OfferedDocModel, RequestItem(s),
 *                          CredentialOptions, KeyOptions, TxCodeSpec
 *   - OpenID4VCI         : Display, TxCode
 * They are not yet migrated into eudi_lib_wallet_kit (skeleton), so the subset
 * logic-core touches is ported here 1:1, preserving field names and semantics.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.time.DateTime
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.RegistrationPolicyViolation

// ─────────────────────────────────────────────────────────────────────────────
// MdocDataModel18013 enums
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors MdocDataModel18013.DocDataFormat. */
public enum DocDataFormat <: Equatable<DocDataFormat> {
    | cbor
    | sdjwt

    public operator func ==(other: DocDataFormat): Bool {
        match ((this, other)) {
            case (cbor, cbor) => true
            case (sdjwt, sdjwt) => true
            case _ => false
        }
    }
    public operator func !=(other: DocDataFormat): Bool { !(this == other) }
}

/** Mirrors MdocDataModel18013.CredentialPolicy (oneTimeUse / rotateUse). */
public enum CredentialPolicy <: Equatable<CredentialPolicy> {
    | oneTimeUse
    | rotateUse

    public operator func ==(other: CredentialPolicy): Bool {
        match ((this, other)) {
            case (oneTimeUse, oneTimeUse) => true
            case (rotateUse, rotateUse) => true
            case _ => false
        }
    }
    public operator func !=(other: CredentialPolicy): Bool { !(this == other) }
}

/** Mirrors MdocDataModel18013.CredentialStatus revocation states. */
public enum CredentialStatus <: Equatable<CredentialStatus> {
    | valid
    | invalid
    | suspended
    | unknownStatus

    public operator func ==(other: CredentialStatus): Bool {
        match ((this, other)) {
            case (valid, valid) => true
            case (invalid, invalid) => true
            case (suspended, suspended) => true
            case (unknownStatus, unknownStatus) => true
            case _ => false
        }
    }
    public operator func !=(other: CredentialStatus): Bool { !(this == other) }
}

/** Mirrors WalletStorage document-status partition used by deleteDocument. */
public enum DocumentStatus <: Equatable<DocumentStatus> {
    | issued
    | deferred
    | pending

    public operator func ==(other: DocumentStatus): Bool {
        match ((this, other)) {
            case (issued, issued) => true
            case (deferred, deferred) => true
            case (pending, pending) => true
            case _ => false
        }
    }
    public operator func !=(other: DocumentStatus): Bool { !(this == other) }
}

/** Mirrors MdocDataModel18013.StatusIdentifier (status-list reference for a doc). */
public class StatusIdentifier {
    public let id: String
    public init(id: String) { this.id = id }
}

/** Mirrors MdocDataModel18013.CredentialsUsageCounts (total / remaining). */
public class CredentialsUsageCounts {
    public let total: Int64
    public let remaining: Int64
    public init(total: Int64, remaining: Int64) {
        this.total = total
        this.remaining = remaining
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Display metadata (MdocDataModel18013.DisplayMetadata + OpenID4VCI.Display)
// ─────────────────────────────────────────────────────────────────────────────

/** A logo reference carried by display metadata. */
public class DisplayLogo {
    public let uri: ?String
    public init(uri: ?String) { this.uri = uri }
}

/** Mirrors MdocDataModel18013.DisplayMetadata. */
public class DisplayMetadata {
    public let name: ?String
    public let localeIdentifier: ?String
    public let logo: ?DisplayLogo
    public init(name!: ?String = None, localeIdentifier!: ?String = None, logo!: ?DisplayLogo = None) {
        this.name = name
        this.localeIdentifier = localeIdentifier
        this.logo = logo
    }
}

/** Mirrors OpenID4VCI.Display (credential-config display entry). */
public class Display {
    public let name: ?String
    public let locale: ?String
    public init(name!: ?String = None, locale!: ?String = None) {
        this.name = name
        this.locale = locale
    }
}

/** getName(fallback:) over [Display] — Extension/OpenID4VCI.Display+Extensions.swift. */
public func getDisplayName(displays: Array<Display>, fallback: String): String {
    let currentLocale = systemLanguageCode()
    for (d in displays) {
        if (let Some(loc) <- d.locale && loc == currentLocale) {
            if (let Some(n) <- d.name) { return n }
        }
    }
    if (displays.size > 0) {
        if (let Some(n) <- displays[0].name) { return n }
    }
    return fallback
}

// ─────────────────────────────────────────────────────────────────────────────
// DocClaim (MdocDataModel18013.DocClaim) + its data value
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors MdocDataModel18013.DocDataValue (the parsed primitive value of a claim).
 * The iOS enum carries many cases; logic-core only inspects `.date`, `.image`
 * and the base64 representation, so those are modelled explicitly with a generic
 * `text` carrier for everything else.
 */
public enum DocDataValue <: Equatable<DocDataValue> {
    | text(String)
    | date(String)
    | imageValue(Array<UInt8>)

    /** Mirrors `dataValue.image` (nil unless this is an image value). */
    public prop image: ?Array<UInt8> {
        get() {
            match (this) {
                case imageValue(bytes) => bytes
                case _ => None
            }
        }
    }

    /** Mirrors `dataValue.base64` (base64 of the raw value, used for pseudonyms). */
    public prop base64: ?String {
        get() {
            match (this) {
                case text(s) => encodeBase64(s)
                case date(s) => encodeBase64(s)
                case imageValue(bytes) => encodeBase64Bytes(bytes)
            }
        }
    }

    public operator func ==(other: DocDataValue): Bool {
        match ((this, other)) {
            case (text(a), text(b)) => a == b
            case (date(a), date(b)) => a == b
            case (imageValue(a), imageValue(b)) => bytesEqual(a, b)
            case _ => false
        }
    }
    public operator func !=(other: DocDataValue): Bool { !(this == other) }
}

/**
 * Mirrors MdocDataModel18013.DocClaim. `children` carries nested claims (mdoc/
 * sd-jwt structured claims). `path` is mutable in iOS (set after init).
 */
public class DocClaim {
    public let name: String
    public let displayName: ?String
    public let dataValue: DocDataValue
    public let stringValue: String
    public let isOptional: Bool
    public let order: Int64
    public let namespace: ?String
    public let children: ?Array<DocClaim>
    public var path: Array<String>

    public init(
        name!: String,
        displayName!: ?String = None,
        dataValue!: DocDataValue,
        stringValue!: String,
        isOptional!: Bool = false,
        order!: Int64 = 0,
        namespace!: ?String = None,
        children!: ?Array<DocClaim> = None,
        path!: Array<String> = Array<String>()
    ) {
        this.name = name
        this.displayName = displayName
        this.dataValue = dataValue
        this.stringValue = stringValue
        this.isOptional = isOptional
        this.order = order
        this.namespace = namespace
        this.children = children
        this.path = path
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DocClaimsDecodable (MdocDataModel18013 protocol) — the issued/deferred doc view
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors the MdocDataModel18013.DocClaimsDecodable protocol surface logic-core
 * relies on. iOS models it as a protocol with many conformers; here it is an
 * interface plus the two concrete conformers logic-core constructs
 * (`DeferredDocument`, and the issued-document model held by the wallet store).
 */
public interface DocClaimsDecodable {
    prop id: String
    prop statusIdentifier: ?StatusIdentifier
    prop createdAt: DateTime
    prop modifiedAt: ?DateTime
    prop displayName: ?String
    prop docType: String
    prop docClaims: Array<DocClaim>
    prop docDataFormat: DocDataFormat
    prop ageOverXX: HashMap<Int64, Bool>
    prop display: ?Array<DisplayMetadata>
    prop issuerDisplay: ?Array<DisplayMetadata>
    prop credentialIssuerIdentifier: ?String
    prop configurationIdentifier: ?String
    prop validFrom: ?DateTime
    prop validUntil: ?DateTime
    prop secureAreaName: ?String
    prop credentialsUsageCounts: ?CredentialsUsageCounts
    prop credentialPolicy: CredentialPolicy
}

// ─────────────────────────────────────────────────────────────────────────────
// WalletStorage.Document  + DocMetadata
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors MdocDataModel18013.DocMetadata (decoded from a Document.metadata blob).
 * iOS exposes `init?(from:)`, `getDisplayName(_:)`, `display`, `issuerDisplay`,
 * `credentialIssuerIdentifier`, `configurationIdentifier`.
 */
public class DocMetadata {
    public let display: ?Array<DisplayMetadata>
    public let issuerDisplay: ?Array<DisplayMetadata>
    public let credentialIssuerIdentifier: String
    public let configurationIdentifier: ?String

    public init(
        credentialIssuerIdentifier!: String,
        display!: ?Array<DisplayMetadata> = None,
        issuerDisplay!: ?Array<DisplayMetadata> = None,
        configurationIdentifier!: ?String = None
    ) {
        this.credentialIssuerIdentifier = credentialIssuerIdentifier
        this.display = display
        this.issuerDisplay = issuerDisplay
        this.configurationIdentifier = configurationIdentifier
    }

    /**
     * Mirrors `DocMetadata(from: doc.metadata)`. Returns None when no metadata
     * blob is present, exactly like the failable iOS initialiser.
     */
    public static func fromBlob(metadata: ?DocMetadataBlob): ?DocMetadata {
        match (metadata) {
            case Some(blob) => DocMetadata(
                credentialIssuerIdentifier: blob.credentialIssuerIdentifier,
                display: blob.display,
                issuerDisplay: blob.issuerDisplay,
                configurationIdentifier: blob.configurationIdentifier
            )
            case None => None
        }
    }

    /** Mirrors `getDisplayName(_ locale:)`. */
    public func getDisplayName(locale: String): ?String {
        if (let Some(ds) <- this.display) {
            for (d in ds) {
                if (let Some(loc) <- d.localeIdentifier && loc == locale) {
                    return d.name
                }
            }
            if (ds.size > 0) { return ds[0].name }
        }
        return None
    }
}

/**
 * The raw metadata blob carried by a WalletStorage.Document. iOS stores an
 * opaque `metadata: Data?`; the in-tree wallet store keeps the already-decoded
 * fields so DocMetadata.fromBlob can rehydrate them faithfully.
 */
public class DocMetadataBlob {
    public let credentialIssuerIdentifier: String
    public let display: ?Array<DisplayMetadata>
    public let issuerDisplay: ?Array<DisplayMetadata>
    public let configurationIdentifier: ?String
    /**
     * For a Pending document awaiting authorization-code (browser) issuance, the
     * https authorization URL the wallet UI must open. Mirrors iOS
     * Document.authorizePresentationUrl. None for non-pending documents.
     */
    public let pendingAuthorizationUrl: ?String
    public init(
        credentialIssuerIdentifier!: String,
        display!: ?Array<DisplayMetadata> = None,
        issuerDisplay!: ?Array<DisplayMetadata> = None,
        configurationIdentifier!: ?String = None,
        pendingAuthorizationUrl!: ?String = None
    ) {
        this.credentialIssuerIdentifier = credentialIssuerIdentifier
        this.display = display
        this.issuerDisplay = issuerDisplay
        this.configurationIdentifier = configurationIdentifier
        this.pendingAuthorizationUrl = pendingAuthorizationUrl
    }
}

/** Mirrors WalletStorage.Document (the persisted, possibly-deferred document). */
public class WalletStorageDocument {
    public let id: String
    public let docType: String
    public let docDataFormat: DocDataFormat
    public let createdAt: DateTime
    public let metadata: ?DocMetadataBlob
    public let status: DocumentStatus

    public init(
        id!: String,
        docType!: String,
        docDataFormat!: DocDataFormat,
        createdAt!: DateTime,
        metadata!: ?DocMetadataBlob = None,
        status!: DocumentStatus = DocumentStatus.issued
    ) {
        this.id = id
        this.docType = docType
        this.docDataFormat = docDataFormat
        this.createdAt = createdAt
        this.metadata = metadata
        this.status = status
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// EudiWalletKit issuance value types
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors EudiWalletKit.KeyOptions (curve + secure area + access control). */
public class KeyOptions {
    public let curve: String
    public let secureAreaName: String
    public init(curve!: String, secureAreaName!: String) {
        this.curve = curve
        this.secureAreaName = secureAreaName
    }
}

/** Mirrors EudiWalletKit.CredentialOptions (policy + batch size). */
public class CredentialOptions {
    public let credentialPolicy: CredentialPolicy
    public let batchSize: Int64
    public init(credentialPolicy!: CredentialPolicy, batchSize!: Int64) {
        this.credentialPolicy = credentialPolicy
        this.batchSize = batchSize
    }
}

/** Mirrors OpenID4VCI.TxCode (transaction-code spec for an offer). */
public class TxCode <: Equatable<TxCode> {
    public let inputMode: String
    public let length: ?Int64
    public init(inputMode!: String, length!: ?Int64 = None) {
        this.inputMode = inputMode
        this.length = length
    }
    // Extension/OpenID4VCI.TxCode+Extensions.swift
    public operator func ==(other: TxCode): Bool {
        this.inputMode == other.inputMode && this.length == other.length
    }
    public operator func !=(other: TxCode): Bool { !(this == other) }
}

/** Mirrors EudiWalletKit.OfferedDocModel (one offered credential in an offer). */
public class OfferedDocModel <: Equatable<OfferedDocModel> {
    public let credentialConfigurationIdentifier: String
    public let docType: ?String
    /** SD-JWT VC type (vct) — carried so the round-trip back into wallet-kit
     *  keeps the credential's identity (docType covers only mso_mdoc; dropping
     *  vct made SD-JWT issuance fail with an empty doc-type list). */
    public let vct: ?String
    public let scope: ?String
    public let displayName: String
    public let algValuesSupported: Array<String>
    public let docTypeOrVct: ?String
    public let credentialOptions: ?CredentialOptions
    public let keyOptions: ?KeyOptions

    public init(
        credentialConfigurationIdentifier!: String,
        docType!: ?String = None,
        vct!: ?String = None,
        scope!: ?String = None,
        displayName!: String = "",
        algValuesSupported!: Array<String> = Array<String>(),
        docTypeOrVct!: ?String = None,
        credentialOptions!: ?CredentialOptions = None,
        keyOptions!: ?KeyOptions = None
    ) {
        this.credentialConfigurationIdentifier = credentialConfigurationIdentifier
        this.vct = vct
        this.docType = docType
        this.scope = scope
        this.displayName = displayName
        this.algValuesSupported = algValuesSupported
        this.docTypeOrVct = docTypeOrVct
        this.credentialOptions = credentialOptions
        this.keyOptions = keyOptions
    }

    /** Extension/OfferedDocModel+Extensions.swift: documentTypeIdentifier. */
    public prop documentTypeIdentifier: DocumentTypeIdentifier {
        get() { DocumentTypeIdentifier.fromRawValue(this.docTypeOrVct ?? "") }
    }

    /** WalletKitController.issueDocumentsByOfferUrl copy(credentialOptions:keyOptions:). */
    public func copy(credentialOptions!: CredentialOptions, keyOptions!: ?KeyOptions): OfferedDocModel {
        return OfferedDocModel(
            credentialConfigurationIdentifier: this.credentialConfigurationIdentifier,
            docType: this.docType,
            vct: this.vct,
            scope: this.scope,
            displayName: this.displayName,
            algValuesSupported: this.algValuesSupported,
            docTypeOrVct: this.docTypeOrVct,
            credentialOptions: credentialOptions,
            keyOptions: keyOptions
        )
    }

    public operator func ==(other: OfferedDocModel): Bool {
        this.credentialConfigurationIdentifier == other.credentialConfigurationIdentifier
            && this.docType == other.docType
            && this.scope == other.scope
            && this.displayName == other.displayName
            && arraysEqual(this.algValuesSupported, other.algValuesSupported)
    }
    public operator func !=(other: OfferedDocModel): Bool { !(this == other) }
}

/** Mirrors EudiWalletKit.OfferedIssuanceModel (resolved offer descriptor). */
public class OfferedIssuanceModel <: Equatable<OfferedIssuanceModel> {
    public let issuerName: String
    public let issuerLogoUrl: ?String
    public let docModels: Array<OfferedDocModel>
    public let txCodeSpec: ?TxCode
    /** Mirrors `wrpVciRegistrationPolicy` — the issuer's WRPRC decoded while the
     *  offer was resolved (kept even when validation failed, so the issuer
     *  identity can still be inspected). None when validation is off. */
    public let wrpVciRegistrationPolicy: ?WrpRegistrationPolicy
    /** Mirrors `wrpVciWarnings` — WRPRC violations keyed by credential
     *  configuration id ("" = request-wide). None when validation is off. */
    public let wrpVciWarnings: ?HashMap<String, Array<RegistrationPolicyViolation>>

    public init(
        issuerName!: String,
        issuerLogoUrl!: ?String = None,
        docModels!: Array<OfferedDocModel> = Array<OfferedDocModel>(),
        txCodeSpec!: ?TxCode = None,
        wrpVciRegistrationPolicy!: ?WrpRegistrationPolicy = None,
        wrpVciWarnings!: ?HashMap<String, Array<RegistrationPolicyViolation>> = None
    ) {
        this.issuerName = issuerName
        this.issuerLogoUrl = issuerLogoUrl
        this.docModels = docModels
        this.txCodeSpec = txCodeSpec
        this.wrpVciRegistrationPolicy = wrpVciRegistrationPolicy
        this.wrpVciWarnings = wrpVciWarnings
    }

    public operator func ==(other: OfferedIssuanceModel): Bool {
        this.issuerName == other.issuerName
            && this.issuerLogoUrl == other.issuerLogoUrl
            && offeredDocModelsEqual(this.docModels, other.docModels)
            && txCodeOptEqual(this.txCodeSpec, other.txCodeSpec)
    }
    public operator func !=(other: OfferedIssuanceModel): Bool { !(this == other) }
}

func offeredDocModelsEqual(a: Array<OfferedDocModel>, b: Array<OfferedDocModel>): Bool {
    if (a.size != b.size) { return false }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) { return false }
        i++
    }
    return true
}

func txCodeOptEqual(a: ?TxCode, b: ?TxCode): Bool {
    match ((a, b)) {
        case (Some(x), Some(y)) => x == y
        case (None, None) => true
        case _ => false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RequestItem / DocElements (MdocDataTransfer18013 presentation request shapes)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors MdocDataTransfer18013.RequestItem (a single requested element). */
public class RequestItem <: Equatable<RequestItem> {
    public let elementIdentifier: String
    /** Full claim path. mdoc rows contain the element identifier here (the
     * namespace is the surrounding map key); SD-JWT rows retain every nested
     * path component, matching wallet-kit/iOS. */
    public let elementPath: Array<String>
    public let intentToRetain: ?Bool
    public init(
        elementIdentifier!: String,
        intentToRetain!: ?Bool = None,
        elementPath!: Array<String> = Array<String>()
    ) {
        this.elementIdentifier = elementIdentifier
        this.elementPath = if (elementPath.isEmpty()) { [elementIdentifier] } else { elementPath }
        this.intentToRetain = intentToRetain
    }
    public operator func ==(other: RequestItem): Bool {
        this.elementIdentifier == other.elementIdentifier
    }
    public operator func !=(other: RequestItem): Bool { !(this == other) }
}

/** One claim exactly as requested by the verifier. Keeping this information at
 * the presentation seam prevents the UI from expanding a request into every
 * claim stored in the credential. */
public class RequestedClaim {
    public let namespace: String
    public let elementPath: Array<String>
    public let isOptional: Bool
    public let intentToRetain: Bool
    public let isAvailable: Bool

    public init(
        namespace!: String,
        elementPath!: Array<String>,
        isOptional!: Bool,
        intentToRetain!: Bool = false,
        isAvailable!: Bool = true
    ) {
        this.namespace = namespace
        this.elementPath = elementPath
        this.isOptional = isOptional
        this.intentToRetain = intentToRetain
        this.isAvailable = isAvailable
    }

    public prop elementIdentifier: String {
        get() {
            if (this.elementPath.isEmpty()) { return "" }
            return this.elementPath[this.elementPath.size - 1]
        }
    }
}

/**
 * Mirrors EudiWalletKit.DocElements (one disclosed document in a session).
 * Equatable by id — Extension/DocElements+Extensions.swift.
 */
public class DocElements <: Equatable<DocElements> {
    public let id: String
    public let docType: String
    public let requestedClaims: Array<RequestedClaim>
    public init(
        id: String,
        docType!: String = "",
        requestedClaims!: Array<RequestedClaim> = Array<RequestedClaim>()
    ) {
        this.id = id
        this.docType = docType
        this.requestedClaims = requestedClaims
    }
    public operator func ==(other: DocElements): Bool { this.id == other.id }
    public operator func !=(other: DocElements): Bool { !(this == other) }
}

// ─────────────────────────────────────────────────────────────────────────────
// TransactionLog / TransactionLogData (MdocDataModel18013)
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors MdocDataModel18013.TransactionLog (the core, JSON-encodable log). */
public class CoreTransactionLog {
    public let timestamp: Int64
    public let value: String
    public let documents: String
    public let status: String
    public let logType: String
    public init(
        timestamp!: Int64,
        value!: String,
        documents!: String = "",
        status!: String = "completed",
        logType!: String = "presentation"
    ) {
        this.timestamp = timestamp
        this.value = value
        this.documents = documents
        this.status = status
        this.logType = logType
    }
}

/** Mirrors MdocDataModel18013.TransactionLogData (parsed, presentable log). */
public class TransactionLogData {
    public let timestamp: Int64
    public let value: String
    public let documents: String
    public let status: String
    public let logType: String
    public init(
        timestamp!: Int64,
        value!: String,
        documents!: String = "",
        status!: String = "completed",
        logType!: String = "presentation"
    ) {
        this.timestamp = timestamp
        this.value = value
        this.documents = documents
        this.status = status
        this.logType = logType
    }
}
