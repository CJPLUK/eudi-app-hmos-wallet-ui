/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * The `WalletKit` facade — the in-tree seam over EudiWalletKit's `EudiWallet`.
 *
 * iOS `WalletKitController` is a thin wrapper over `EudiWallet` (the external
 * eudi-lib-ios-wallet-kit engine). The corresponding Cangjie package
 * `ohos_app_cangjie_eudi_cjwallet_kit` ships the real `EudiWallet` facade, so
 * `WalletKitImpl` now holds a real `EudiWallet` instance and delegates every
 * engine operation to it — issuance (OpenID4VCI), document storage, status-list
 * lookups, issuer metadata, transaction-log parsing, and presentation
 * (OpenID4VP / BLE) — mapping logic-core's domain types ↔ the wallet-kit types
 * at the boundary. No operation is stubbed.
 *
 * The `WalletKit` interface (and the logic-core wallet-domain value types in
 * wallet_domain.cj) remain the stable seam the controller and coordinators
 * consume; `WalletKitImpl` translates between that seam and the real engine.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.DateTime
import eudi_logic_business.ParsedUrl

// ── Real wallet-kit engine (aliased to avoid clashing with logic-core's own
//    same-named domain types reconstructed in wallet_domain.cj/config.cj). ─────
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.facade.EudiWallet as WKEudiWallet
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.EudiWalletConfiguration as WKEudiWalletConfiguration
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.OpenId4VciConfiguration as WKOpenId4VciConfiguration
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.OpenId4VpConfiguration as WKOpenId4VpConfiguration
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.ClientIdScheme as WKClientIdScheme
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DocTypeIdentifier as WKDocTypeIdentifier
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.OfferedDocModel as WKOfferedDocModel
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.OfferedIssuanceModel as WKOfferedIssuanceModel
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.support.FlowType as WKFlowType
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.support.SdJwtUtils
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.support.DisclosedClaim
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.presentation.PresentationSession as WKPresentationSession
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.presentation.PresentationStatus as WKPresentationStatus
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.support.TransactionLogEntry as WKTransactionLogEntry
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.KeyAttestationConfiguration as WKKeyAttestationConfiguration
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WalletAttestationsProvider as WKWalletAttestationsProvider
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.ConfigurationCredentialMetadata as WKConfigurationCredentialMetadata
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.IssuerResponse as WKIssuerResponse
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.WrpRegistrationPolicy
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.RegistrationPolicyViolation
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DocElements as WKDocElements
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.PresentationPolicyViolation
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.DisclosedDocumentSet
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.SdJwtElement as WKSdJwtElement
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.entity.credential.Claim as WKClaim

import ohos_app_cangjie_eudi_cjwallet_storage.storage.types.Document as WKDocument
import ohos_app_cangjie_eudi_cjwallet_storage.storage.types.DocumentStatus as WKDocumentStatus
import ohos_app_cangjie_eudi_cjwallet_storage.storage.types.DocDataFormat as WKDocDataFormat
import ohos_app_cangjie_eudi_cjwallet_storage.storage.docstore.RdbStorageService
import ohos_app_cangjie_eudi_cjwallet_storage.storage.docstore.DataStorageService
import ohos_app_cangjie_eudi_cjcbor.cbor.decodeCbor
import ohos_app_cangjie_eudi_cjcbor.cbor.CborValue
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.response.IssuerSigned

import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.KeyOptions as WKKeyOptions
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.CoseEcCurve as WKCoseEcCurve
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.KeyAccessProtection as WKKeyAccessProtection
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.KeyAccessControl as WKKeyAccessControl
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.KeyPurpose as WKKeyPurpose
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.CredentialOptions as WKCredentialOptions
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.CredentialPolicy as WKCredentialPolicy
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.issuerauth.StatusIdentifier as WKStatusIdentifier

import ohos_app_cangjie_eudi_cjstatium.statium.model.CredentialStatus as WKCredentialStatus

import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.entity.issuer.CredentialIssuerMetadata as WKCredentialIssuerMetadata
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.entity.config.AuthorizeIssuanceConfig as WKAuthorizeIssuanceConfig
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.entity.config.IssuerMetadataPolicy as WKIssuerMetadataPolicy
import ohos_app_cangjie_eudi_cjopenid4vp_vci.openid4vci.entity.config.IssuerTrust as WKIssuerTrust
import ohos_app_cangjie_eudi_cjmdoc_transfer.transfer.framing.BleTransferMode as WKBleTransferMode
import ohos_app_cangjie_eudi_cjmdoc_transfer.transfer.framing.RequestItem as WKRequestItem
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.models.RequestItems as WKRequestItems
import ohos_app_cangjie_eudi_cjwallet_kit.wallet.support.TrustedChainValidator
import ohos_app_cangjie_eudi_cjmdoc_security.security.device_auth.DeviceAuthMethod as WKDeviceAuthMethod
import ohos_app_cangjie_eudi_cjmdoc_security.security.secure_area.HuksSecureArea
import ohos_app_cangjie_eudi_cjwallet_storage.storage.keystore.HuksSecureKeyStorage
import ohos_app_cangjie_eudi_cjmdoc_data_model.mdoc.securearea.SecureAreaRegistry

import stdx.encoding.json.{JsonString, JsonObject, JsonValue, JsonArray, JsonInt, JsonFloat, JsonBool}
import ohos_app_cangjie_eudi_cjetsi_1196x2.etsi_trust.{TrustConfiguration, TrustPolicy}
import kit.PerformanceAnalysisKit.Hilog

/** Mirrors `EudiWalletConfiguration` (the wallet engine init parameters). */
public class EudiWalletConfiguration {
    public let serviceName: String
    public let accessGroup: String
    public let userAuthenticationRequired: Bool
    public let trustedReaderRootCertificates: Array<Array<X5Chain>>
    public let trustedIssuerRootCertificates: Array<Array<X5Chain>>
    public let trustConfiguration: TrustConfiguration
    public let logFileName: String
    public init(
        serviceName!: String,
        accessGroup!: String,
        userAuthenticationRequired!: Bool,
        trustedReaderRootCertificates!: Array<Array<X5Chain>>,
        trustedIssuerRootCertificates!: Array<Array<X5Chain>>,
        trustConfiguration!: TrustConfiguration,
        logFileName!: String
    ) {
        this.serviceName = serviceName
        this.accessGroup = accessGroup
        this.userAuthenticationRequired = userAuthenticationRequired
        this.trustedReaderRootCertificates = trustedReaderRootCertificates
        this.trustedIssuerRootCertificates = trustedIssuerRootCertificates
        this.trustConfiguration = trustConfiguration
        this.logFileName = logFileName
    }
}

/** Mirrors the presentation transport flow (`.ble` / `.openid4vp(qrCode:)`). */
public enum PresentationFlow {
    | ble
    | openid4vp(Array<UInt8>)   // qrCode bytes
}

/**
 * Mirrors `EudiWallet.storage` (the `StorageManager` view). Holds the wallet's
 * document collections; the controller reads these for its fetch/(all) methods.
 *
 * The contents are kept in sync from the real `EudiWallet.storage` after each
 * engine operation (`refreshFromEngine`).
 */
public class WalletStorageView {
    private let lock = Mutex()
    private let issued = ArrayList<IssuedDocument>()
    private let deferred = ArrayList<WalletStorageDocument>()
    private let pending = ArrayList<WalletStorageDocument>()

    public init() {}

    /** Mirrors `storage.docModels`. */
    public prop docModels: Array<DocClaimsDecodable> {
        get() {
            synchronized(lock) {
                let out = ArrayList<DocClaimsDecodable>()
                for (d in this.issued) { out.add(d) }
                return out.toArray()
            }
        }
    }

    /** Mirrors `storage.deferredDocuments`. */
    public prop deferredDocuments: Array<WalletStorageDocument> {
        get() {
            synchronized(lock) {
                let out = ArrayList<WalletStorageDocument>()
                for (d in this.deferred) { out.add(d) }
                return out.toArray()
            }
        }
    }

    /** Mirrors `storage.pendingDocuments`. */
    public prop pendingDocuments: Array<WalletStorageDocument> {
        get() {
            synchronized(lock) {
                let out = ArrayList<WalletStorageDocument>()
                for (d in this.pending) { out.add(d) }
                return out.toArray()
            }
        }
    }

    /** Mirrors `storage.getDocumentModel(id:)`. */
    public func getDocumentModel(id: String): ?DocClaimsDecodable {
        synchronized(lock) {
            for (d in this.issued) {
                if (d.id == id) { return d }
            }
            return None
        }
    }

    /** Replace all collections with the freshly-mapped engine snapshot. */
    public func replaceAll(
        issuedDocs: Array<IssuedDocument>,
        deferredDocs: Array<WalletStorageDocument>,
        pendingDocs: Array<WalletStorageDocument>
    ): Unit {
        synchronized(lock) {
            this.issued.clear()
            this.deferred.clear()
            this.pending.clear()
            for (d in issuedDocs) { this.issued.add(d) }
            for (d in deferredDocs) { this.deferred.add(d) }
            for (d in pendingDocs) { this.pending.add(d) }
        }
    }

    public func clearAll(): Unit {
        synchronized(lock) {
            this.issued.clear()
            this.deferred.clear()
            this.pending.clear()
        }
    }
}

/**
 * Mirrors the `EudiWallet` surface consumed by WalletKitController.
 * `WalletKitImpl` implements every method by delegating to a real `EudiWallet`.
 */
public interface WalletKit {
    /** Mirrors `wallet.storage`. */
    prop storage: WalletStorageView

    // ── issuance ──────────────────────────────────────────────────────────────
    func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel
    func issueDocumentsByOfferUrl(offerUri: String, docTypes: Array<OfferedDocModel>, txCodeValue: ?String): EngineIssuerResponse
    func issueDocuments(issuerName: String, docTypeIdentifiers: Array<String>, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): EngineIssuerResponse
    func reissueDocument(documentId: String, keyOptions: ?KeyOptions, backgroundOnly: Bool): EngineIssuerResponse
    /** Mirrors `EudiWallet.resolveIssuerRegistration(issuerName:credentialConfigurationIds:)`. */
    func resolveIssuerRegistration(issuerName: String, credentialConfigurationIds: Array<String>): EngineIssuerResponse
    func requestDeferredIssuance(issuerName: String, deferredDoc: WalletStorageDocument, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): DeferredIssuanceResult
    func resumePendingIssuance(issuerName: String, pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): Array<WalletStorageDocument>
    func getIssuerMetadata(issuerName: String): IssuerMetadata
    func getDocumentStatus(statusIdentifier: StatusIdentifier): CredentialStatus
    func refreshUsageCounters(): Unit

    // ── storage lifecycle ──────────────────────────────────────────────────────
    func loadAllDocuments(): ?Array<WalletStorageDocument>
    func deleteAllDocuments(): Unit
    func deleteDocument(id: String, status: DocumentStatus): Unit

    // ── presentation ────────────────────────────────────────────────────────────
    func beginPresentation(flow: PresentationFlow): PresentationSession
    /** Mirrors `EudiWallet.stopPresentation()`: stop the active presentation
     *  (transport stop + ephemeral-key deletion). No-op when none is active. */
    func stopPresentation(): Unit
    /** Mirrors the mutable `wallet.openID4VpConfig` — reassigned immediately
     *  before beginPresentation so the Settings toggle applies per session. */
    func setOpenId4VpConfig(vpConfig: OpenId4VpConfiguration): Unit
    /** Mirrors `wallet.wrpRegistrationValidator.wrpVpRegistrationPolicy` — the
     *  policy captured for the current/last presentation request (per-session). */
    prop wrpVpRegistrationPolicy: ?WrpRegistrationPolicy

    // ── transaction log ───────────────────────────────────────────────────────
    func parseTransactionLog(log: CoreTransactionLog): TransactionLogData
}

/** A parsed-URL reference passed to resumePendingIssuance (iOS `webUrl: URL?`). */
public type ParsedUrlRef = ParsedUrl

/**
 * Mirrors EudiWalletKit `IssuerResponse` (wallet-kit 0.40.x) at the WalletKit
 * seam: the issued/stored documents plus the issuer's WRPRC verdict inputs.
 * The controller maps this into the app-level `IssuanceResult` via
 * `makeIssuerRegistration(policy:warnings:)`.
 */
public class EngineIssuerResponse {
    public let documents: Array<WalletStorageDocument>
    /** WRPRC violations keyed by credential configuration id ("" = request-wide). */
    public let wrpIssuerWarnings: ?HashMap<String, Array<RegistrationPolicyViolation>>
    /** The issuer's decoded WRPRC policy (None when validation is off / absent). */
    public let wrpIssuerPolicy: ?WrpRegistrationPolicy

    public init(
        documents!: Array<WalletStorageDocument>,
        wrpIssuerWarnings!: ?HashMap<String, Array<RegistrationPolicyViolation>> = None,
        wrpIssuerPolicy!: ?WrpRegistrationPolicy = None
    ) {
        this.documents = documents
        this.wrpIssuerWarnings = wrpIssuerWarnings
        this.wrpIssuerPolicy = wrpIssuerPolicy
    }
}

/**
 * Mirrors `requestDeferredIssuance` result: either still deferred (returns the
 * deferred document) or completed (returns the issued document id).
 */
public class DeferredIssuanceResult {
    public let isDeferred: Bool
    public let id: String
    public let deferredDocument: ?WalletStorageDocument
    public init(isDeferred!: Bool, id!: String, deferredDocument!: ?WalletStorageDocument = None) {
        this.isDeferred = isDeferred
        this.id = id
        this.deferredDocument = deferredDocument
    }
    /** Mirrors `result.transformToDeferredDecodable()`. */
    public func transformToDeferredDecodable(): DocClaimsDecodable {
        match (this.deferredDocument) {
            case Some(d) => transformToDeferredDecodableImpl(d)
            case None => throw WalletCoreError.unableFetchDocument()
        }
    }
}

func transformToDeferredDecodableImpl(d: WalletStorageDocument): DocClaimsDecodable {
    return transformToDeferredDecodable(d)
}

/** Mirrors `getIssuerMetadata(issuerName:)` result (credentialsSupported + issuer id). */
public class IssuerMetadata {
    public let credentialIssuerIdentifier: String
    public let credentialsSupported: HashMap<String, SupportedCredential>
    public init(credentialIssuerIdentifier!: String, credentialsSupported!: HashMap<String, SupportedCredential>) {
        this.credentialIssuerIdentifier = credentialIssuerIdentifier
        this.credentialsSupported = credentialsSupported
    }
}

/** A supported-credential config entry (msoMdoc / sdJwtVc / other). */
public enum SupportedCredential {
    | msoMdoc(MsoMdocConfig)
    | sdJwtVc(SdJwtVcConfig)
    | otherFormat
}

public class CredentialMetadata {
    public let display: Array<Display>
    public init(display: Array<Display>) { this.display = display }
}

public class MsoMdocConfig {
    public let docType: String
    public let credentialMetadata: ?CredentialMetadata
    public init(docType!: String, credentialMetadata!: ?CredentialMetadata = None) {
        this.docType = docType
        this.credentialMetadata = credentialMetadata
    }
}

public class SdJwtVcConfig {
    public let vct: ?String
    public let credentialMetadata: ?CredentialMetadata
    public init(vct!: ?String, credentialMetadata!: ?CredentialMetadata = None) {
        this.vct = vct
        this.credentialMetadata = credentialMetadata
    }
}

/**
 * Default WalletKit implementation — delegates to a real `EudiWallet` engine.
 */
public class WalletKitImpl <: WalletKit {
    private let _storage = WalletStorageView()
    private let config: EudiWalletConfiguration
    private let openID4VpConfig: OpenId4VpConfiguration
    private let openID4VciConfigurations: HashMap<String, OpenId4VciConfiguration>
    private let transactionLoggerRef: TransactionLogger
    private let engine: WKEudiWallet

    public init(
        eudiWalletConfig!: EudiWalletConfiguration,
        openID4VpConfig!: OpenId4VpConfiguration,
        openID4VciConfigurations!: HashMap<String, OpenId4VciConfiguration>,
        transactionLogger!: TransactionLogger
    ) {
        this.config = eudiWalletConfig
        this.openID4VpConfig = openID4VpConfig
        this.openID4VciConfigurations = openID4VciConfigurations
        this.transactionLoggerRef = transactionLogger

        // Register a SecureArea once so beginIssueDocument/createKeyBatch works.
        // iOS registers SecureEnclaveSecureArea; Harmony equivalent is
        // HuksSecureArea (P-256 keys generated inside HUKS, only the alias +
        // public key go through HuksSecureKeyStorage). Do not also register
        // SoftwareSecureArea: defaultSecurityArea() prefers "Software" over
        // any other name, which would silently keep issuing software keys.
        // WalletKitConfig.keyOptions.secureAreaName must be "HUKS" (see
        // HuksSecureArea.NAME) so lookup hits this area rather than falling
        // back through the iOS leftover name "SecureEnclave".
        if (SecureAreaRegistry.shared.names().isEmpty()) {
            let keyStore = HuksSecureKeyStorage(
                eudiWalletConfig.serviceName,
                "/data/storage/el2/base/haps/entry/files"
            )
            SecureAreaRegistry.shared.register(HuksSecureArea.create(keyStore))
        }

        // Build the real EudiWallet from logic-core config.
        let wkConfig = WKEudiWalletConfiguration(
            eudiWalletConfig.serviceName,
            Option<String>.Some(eudiWalletConfig.accessGroup),
            eudiWalletConfig.userAuthenticationRequired,
            toWKTrustedRoots(eudiWalletConfig.trustedReaderRootCertificates),
            WKDeviceAuthMethod.DeviceSignature,
            Option<String>.None,
            Option<String>.Some(eudiWalletConfig.logFileName),
            WKBleTransferMode.Server,
            trustConfiguration: Option<TrustConfiguration>.Some(eudiWalletConfig.trustConfiguration)
        )
        // Trust anchors (LoTE) resolve lazily on first issuance / presentation.
        // Do not touch them here: this runs on the UI thread during AppRoot
        // setup, and a slow LoTE download blocked it long enough (> 6 s) for
        // the system to kill the app at cold start.
        // Persistent encrypted RDB document store (mirrors iOS Keychain-backed
        // WalletStorage). Requires the UIAbilityContext bridged from the ETS
        // EntryAbility (see AppContextHolder). When the context is present we hand
        // a real RdbStorageService to the engine so issued credentials survive an
        // app relaunch; otherwise the engine's in-memory fallback is used (so the
        // app still starts in contexts where the bridge has not run, e.g. tests).
        let wallet = match (AppContextHolder.get()) {
            case Some(abilityCtx) =>
                let docStore: DataStorageService = RdbStorageService(abilityCtx, eudiWalletConfig.serviceName + ".db")
                WKEudiWallet(wkConfig, Option<DataStorageService>.Some(docStore))
            case None =>
                WKEudiWallet(wkConfig)
        }
        wallet.openId4VpConfig = toWKVpConfig(openID4VpConfig)
        // Register every VCI configuration keyed by issuer name.
        for ((name, vci) in openID4VciConfigurations) {
            wallet.addOpenId4VciConfiguration(name, toWKVciConfig(vci, eudiWalletConfig.trustConfiguration))
        }
        this.engine = wallet
        this.refreshFromEngine()
    }

    public prop storage: WalletStorageView {
        get() { this._storage }
    }

    // ── issuance ──────────────────────────────────────────────────────────────

    public func resolveOfferUrlDocTypes(offerUri: String): OfferedIssuanceModel {
        return fromWKOfferedIssuanceModel(this.engine.resolveOfferUrlDocTypes(offerUri))
    }

    public func issueDocumentsByOfferUrl(offerUri: String, docTypes: Array<OfferedDocModel>, txCodeValue: ?String): EngineIssuerResponse {
        let mapped = ArrayList<WKOfferedDocModel>()
        for (dt in docTypes) { mapped.add(toWKOfferedDocModel(dt)) }
        let response = this.engine.issueDocumentsByOfferUrl(offerUri, mapped.toArray(), txCodeValue)
        this.refreshFromEngine()
        return fromWKIssuerResponse(response)
    }

    public func issueDocuments(issuerName: String, docTypeIdentifiers: Array<String>, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): EngineIssuerResponse {
        let ids = ArrayList<WKDocTypeIdentifier>()
        // The feature passes real credential_configuration_id strings (e.g.
        // "eu.europa.ec.eudi.pid_mdoc"), so match them directly against the
        // issuer metadata config keys (Identifier), not by mdoc doctype.
        for (id in docTypeIdentifiers) { ids.add(WKDocTypeIdentifier.Identifier(id)) }
        let response = this.engine.issueDocuments(
            issuerName,
            ids.toArray(),
            toWKCredentialOptions(credentialOptions),
            toWKKeyOptionsOpt(keyOptions),
            Option<String>.None
        )
        this.refreshFromEngine()
        return fromWKIssuerResponse(response)
    }

    public func reissueDocument(documentId: String, keyOptions: ?KeyOptions, backgroundOnly: Bool): EngineIssuerResponse {
        let response = this.engine.reissueDocument(
            documentId,
            Option<WKCredentialOptions>.None,
            toWKKeyOptionsOpt(keyOptions),
            Option<String>.None
        )
        this.refreshFromEngine()
        return fromWKIssuerResponse(response)
    }

    /** Mirrors `EudiWallet.resolveIssuerRegistration` — resolves the issuer's
     *  WRPRC verdict for the given configuration ids without issuing anything. */
    public func resolveIssuerRegistration(issuerName: String, credentialConfigurationIds: Array<String>): EngineIssuerResponse {
        return fromWKIssuerResponse(this.engine.resolveIssuerRegistration(issuerName, credentialConfigurationIds))
    }

    public func requestDeferredIssuance(issuerName: String, deferredDoc: WalletStorageDocument, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): DeferredIssuanceResult {
        let wkDeferred = lookupEngineDocument(deferredDoc.id, WKDocumentStatus.Deferred)
        let updated = this.engine.requestDeferredIssuance(
            issuerName,
            wkDeferred,
            toWKCredentialOptions(credentialOptions),
            toWKKeyOptionsOpt(keyOptions)
        )
        this.refreshFromEngine()
        // Still deferred → return the (re-mapped) deferred document; else issued id.
        if (updated.status.rawValue() == WKDocumentStatus.Deferred.rawValue()) {
            return DeferredIssuanceResult(isDeferred: true, id: updated.id, deferredDocument: toWalletStorageDocument(updated))
        }
        return DeferredIssuanceResult(isDeferred: false, id: updated.id, deferredDocument: None)
    }

    public func resumePendingIssuance(issuerName: String, pendingDoc: WalletStorageDocument, webUrl: ?ParsedUrlRef, credentialOptions: CredentialOptions, keyOptions: ?KeyOptions): Array<WalletStorageDocument> {
        let wkPending = lookupEngineDocument(pendingDoc.id, WKDocumentStatus.Pending)
        let urlString: String = match (webUrl) {
            case Some(u) => parsedUrlToString(u)
            case None => ""
        }
        let updated = this.engine.resumePendingIssuance(
            issuerName,
            wkPending,
            urlString,
            toWKCredentialOptions(credentialOptions),
            toWKKeyOptionsOpt(keyOptions)
        )
        this.refreshFromEngine()
        // Mirrors the [WalletStorage.Document] array iOS issueDocuments returns:
        // combined issuance yields one document per authorized config.
        let out = ArrayList<WalletStorageDocument>()
        for (doc in updated) {
            out.add(toWalletStorageDocument(doc))
        }
        return out.toArray()
    }

    public func getIssuerMetadata(issuerName: String): IssuerMetadata {
        let raw = this.engine.getIssuerMetadata(issuerName)
        match (raw) {
            case md: WKCredentialIssuerMetadata => return fromWKIssuerMetadata(md)
            case _ => throw WalletCoreError.unableFetchDocument()
        }
    }

    public func getDocumentStatus(statusIdentifier: StatusIdentifier): CredentialStatus {
        // logic-core's StatusIdentifier carries an opaque id string; the engine
        // needs idx + uri. The id encodes "uri#idx" when both are present.
        let (uri, idx) = splitStatusIdentifier(statusIdentifier.id)
        let wkStatus = this.engine.getDocumentStatus(WKStatusIdentifier(idx, uri))
        return fromWKCredentialStatus(wkStatus)
    }

    public func refreshUsageCounters(): Unit {
        this.engine.refreshUsageCounters()
        this.refreshFromEngine()
    }

    // ── storage lifecycle ──────────────────────────────────────────────────────

    public func loadAllDocuments(): ?Array<WalletStorageDocument> {
        let loaded = this.engine.loadAllDocuments()
        this.refreshFromEngine()
        match (loaded) {
            case Some(docs) =>
                let out = ArrayList<WalletStorageDocument>()
                for (d in docs) { out.add(toWalletStorageDocument(d)) }
                return out.toArray()
            case None => return None
        }
    }

    public func deleteAllDocuments(): Unit {
        this.engine.deleteAllDocuments()
        this._storage.clearAll()
    }

    public func deleteDocument(id: String, status: DocumentStatus): Unit {
        this.engine.deleteDocument(id, toWKDocumentStatus(status))
        this.refreshFromEngine()
    }

    // ── presentation ────────────────────────────────────────────────────────────

    public func beginPresentation(flow: PresentationFlow): PresentationSession {
        let wkFlow: WKFlowType = match (flow) {
            case ble => WKFlowType.Ble
            // Forward the authorization-request URI bytes — dropping them left
            // the engine's OpenId4VpService without a URI, so every remote
            // presentation died with the generic unableToPresentAndShare.
            case openid4vp(uriBytes) => WKFlowType.OpenId4Vp(uriBytes)
        }
        let wkSession = this.engine.beginPresentation(wkFlow)
        return EnginePresentationSession(wkSession)
    }

    /** Mirrors `EudiWallet.stopPresentation()` — stops the active BLE/OpenID4VP
     *  presentation on the engine (advertising / GATT server teardown +
     *  ephemeral EDeviceKey deletion). */
    public func stopPresentation(): Unit {
        this.engine.stopPresentation()
    }

    /** Mirrors the mutable `wallet.openID4VpConfig` assignment — the controller
     *  calls this immediately before beginPresentation so the Settings toggle
     *  (validateRegistrationCertificate) applies per session. */
    public func setOpenId4VpConfig(vpConfig: OpenId4VpConfiguration): Unit {
        this.engine.openId4VpConfig = toWKVpConfig(vpConfig)
    }

    /** Mirrors `wallet.wrpRegistrationValidator.wrpVpRegistrationPolicy`. */
    public prop wrpVpRegistrationPolicy: ?WrpRegistrationPolicy {
        get() { this.engine.wrpRegistrationValidator.wrpVpRegistrationPolicy }
    }

    // ── transaction log ───────────────────────────────────────────────────────

    public func parseTransactionLog(log: CoreTransactionLog): TransactionLogData {
        // The engine parses a TransactionLogEntry into a human-readable string;
        // logic-core's CoreTransactionLog carries the already-stored value, which
        // is the presentable form here (the engine entry graph is not persisted by
        // logic-core's storage controller — it stores timestamp+value JSON).
        return TransactionLogData(
            timestamp: log.timestamp,
            value: log.value,
            documents: log.documents,
            status: log.status,
            logType: log.logType
        )
    }

    /** Mirrors the static `EudiWallet.getLogFileURL(_:)` accessor. */
    public static func getLogFileURL(logFileName: String): ?String {
        // HarmonyOS routes wallet logs through Hilog (no file path); iOS returns
        // nil when the log file is absent — mirror nil.
        return None
    }

    // ── private: engine ↔ view sync ─────────────────────────────────────────────

    private func refreshFromEngine(): Unit {
        let issuedDocs = ArrayList<IssuedDocument>()
        match (this.engine.loadDocuments(WKDocumentStatus.Issued)) {
            case Some(docs) =>
                for (d in docs) {
                    // remaining/total badge (iOS credentialsUsageCounts, "30/30").
                    var usage: ?CredentialsUsageCounts = None
                    try {
                        let (rem, tot) = this.engine.credentialsUsageCounts(d.id)
                        usage = Some(CredentialsUsageCounts(tot, rem))
                    } catch (_: Exception) {
                        ()
                    }
                    issuedDocs.add(toIssuedDocument(d, usage: usage))
                }
            case None => ()
        }
        let deferredDocs = ArrayList<WalletStorageDocument>()
        match (this.engine.loadDocuments(WKDocumentStatus.Deferred)) {
            case Some(docs) => for (d in docs) { deferredDocs.add(toWalletStorageDocument(d)) }
            case None => ()
        }
        let pendingDocs = ArrayList<WalletStorageDocument>()
        match (this.engine.loadDocuments(WKDocumentStatus.Pending)) {
            case Some(docs) => for (d in docs) { pendingDocs.add(toWalletStorageDocument(d)) }
            case None => ()
        }
        this._storage.replaceAll(issuedDocs.toArray(), deferredDocs.toArray(), pendingDocs.toArray())
        // Notify the dashboard so a freshly issued/deferred/resumed credential
        // appears without an app relaunch (iOS posts DocumentTabRefresh the same
        // way from its wallet workers). Cheap + idempotent; observers re-read the
        // synced mirror. The initial constructor call has no observers yet (no-op).
        NotificationCenter.post(NotificationName.DocumentTabRefresh)
    }

    private func lookupEngineDocument(id: String, status: WKDocumentStatus): WKDocument {
        match (this.engine.loadDocument(id, status)) {
            case Some(d) => return d
            case None => throw WalletCoreError.unableFetchDocument()
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Boundary mapping: real wallet-kit types  ↔  logic-core domain types
// ═════════════════════════════════════════════════════════════════════════════

func toWKTrustedRoots(roots: Array<Array<X5Chain>>): ?Array<Array<UInt8>> {
    // Engine accepts a flat list of DER chains; flatten logic-core's chain-of-chains.
    let out = ArrayList<Array<UInt8>>()
    for (chain in roots) {
        for (cert in chain) { out.add(cert.der) }
    }
    if (out.isEmpty()) { return None }
    return Some(out.toArray())
}

func toWKVpConfig(vp: OpenId4VpConfiguration): WKOpenId4VpConfiguration {
    let schemes = ArrayList<WKClientIdScheme>()
    for (s in vp.clientIdSchemes) {
        match (s) {
            case x509SanDns => schemes.add(WKClientIdScheme.X509SanDns)
            case x509Hash => schemes.add(WKClientIdScheme.X509Hash)
        }
    }
    return WKOpenId4VpConfiguration(
        schemes.toArray(), vp.allowPresentingPartialClaims,
        validateRegistrationCertificate: vp.validateRegistrationCertificate
    )
}

// Base64url (RFC 4648 §5, no padding) — pure Cangjie so logic-core needs no
// extra crypto/jose dependency. Used to encode P-256 X/Y coordinates for the JWK.
let B64URL_TABLE: Array<UInt8> = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".toArray()

func base64UrlNoPad(input: Array<UInt8>): String {
    let out = ArrayList<UInt8>()
    let sz = input.size
    var i = 0
    while (i + 3 <= sz) {
        let n = (UInt32(input[i]) << 16) | (UInt32(input[i + 1]) << 8) | UInt32(input[i + 2])
        out.add(B64URL_TABLE[Int64((n >> 18) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64((n >> 12) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64((n >> 6) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64(n & 0x3Fu32)])
        i += 3
    }
    let rem = sz - i
    if (rem == 1) {
        let n = UInt32(input[i]) << 16
        out.add(B64URL_TABLE[Int64((n >> 18) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64((n >> 12) & 0x3Fu32)])
    } else if (rem == 2) {
        let n = (UInt32(input[i]) << 16) | (UInt32(input[i + 1]) << 8)
        out.add(B64URL_TABLE[Int64((n >> 18) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64((n >> 12) & 0x3Fu32)])
        out.add(B64URL_TABLE[Int64((n >> 6) & 0x3Fu32)])
    }
    return String.fromUtf8(out.toArray())
}

/**
 * Adapts the app-level WalletKitAttestationProvider (JWK-based getKeysAttestation,
 * posts to the wallet-provider unit-attestation endpoint) to the wallet-kit
 * WalletAttestationsProvider interface (raw uncompressed public-key bytes). This
 * wires key attestation into the OpenID4VCI proof for key_attestations_required
 * credentials (e.g. EHIC), mirroring iOS WalletKitAttestationProvider.
 */
class WalletKitAttestationAdapter <: WKWalletAttestationsProvider {
    private let inner: WalletKitAttestationProvider
    init(inner: WalletKitAttestationProvider) {
        this.inner = inner
    }
    public func getWalletAttestation(publicJwkJson: String): String {
        // OAuth attestation-based client authentication (`attest_jwt_client_auth`):
        // the wallet-kit hands over the public JWK JSON of the key it will sign
        // the client-attestation PoP with; the wallet-provider attests it. iOS
        // passes the equivalent SigningKeyProxy to getWalletAttestation(signingKey:).
        let dict = HashMap<String, String>()
        match (JsonValue.fromStr(publicJwkJson)) {
            case obj: JsonObject =>
                for (k in ["kty", "crv", "x", "y"]) {
                    match (obj.get(k)) {
                        case Some(v: JsonString) => dict.add(k, v.getValue())
                        case _ => ()
                    }
                }
            case _ => throw Exception("getWalletAttestation: public JWK must be a JSON object")
        }
        return this.inner.getWalletAttestation(SigningKeyProxy(dict))
    }
    public func getKeysAttestation(publicKeyBytes: Array<Array<UInt8>>, nonce: ?String): String {
        let jwks = ArrayList<JWK>()
        for (bytes in publicKeyBytes) {
            // Uncompressed P-256 public point: 0x04 || X(32) || Y(32).
            let d = HashMap<String, String>()
            d.add("kty", "EC")
            d.add("crv", "P-256")
            // Match iOS makePublicJwks: the wallet-provider attestation service
            // expects signing-key metadata in addition to the EC coordinates.
            d.add("use", "sig")
            d.add("alg", "ES256")
            // `kid` is opaque; deriving it from the public point keeps it unique
            // per HUKS key without introducing a second random identifier.
            d.add("kid", base64UrlNoPad(bytes))
            if (bytes.size >= 65) {
                d.add("x", base64UrlNoPad(bytes[1..33]))
                d.add("y", base64UrlNoPad(bytes[33..65]))
            }
            jwks.add(JWK(d))
        }
        return this.inner.getKeysAttestation(jwks.toArray(), nonce)
    }
}

func toWKVciConfig(vci: OpenId4VciConfiguration, trustCfg: TrustConfiguration): WKOpenId4VciConfiguration {
    let attestConfig: Option<WKKeyAttestationConfiguration> = match (vci.keyAttestationsConfig) {
        case Some(kac) => Option<WKKeyAttestationConfiguration>.Some(
            WKKeyAttestationConfiguration(
                WalletKitAttestationAdapter(kac.walletAttestationsProvider),
                None,
                None
            )
        )
        case None => Option<WKKeyAttestationConfiguration>.None
    }
    // iOS issuerMetadataPolicy is derived from accessTrustManager (WRPAC) +
    // requireSignedMetadata / defaultPolicy. PreferSigned keeps DEMO
    // issuer.eudiw.dev JSON metadata working under Warning. WRPRC validation
    // needs the signed-metadata WRPAC, so the toggle upgrades to RequireSigned
    // (the kit refuses with WalletError(InvalidWrprc) otherwise).
    let metadataPolicy = toWKIssuerMetadataPolicy(trustCfg, vci.validateRegistrationCertificate)
    return WKOpenId4VciConfiguration(
        vci.credentialIssuerURL,
        vci.clientId,
        attestConfig,
        vci.authFlowRedirectionURI,
        WKAuthorizeIssuanceConfig.FavorScopes,
        vci.requirePAR,
        vci.requireDpop,
        metadataPolicy,
        false,
        Option<WKKeyOptions>.None,
        validateRegistrationCertificate: vci.validateRegistrationCertificate,
        cacheIssuerMetadata: vci.cacheIssuerMetadata
    )
}

func toWKIssuerMetadataPolicy(trustCfg: TrustConfiguration, requireSignedForWrprc: Bool): WKIssuerMetadataPolicy {
    if (!trustCfg.requireSignedMetadata) {
        return WKIssuerMetadataPolicy.IgnoreSigned
    }
    // Inject a lazy validator instead of eagerly resolving PEM at startup:
    // accessTrustManager.trustAnchorsDer() (which pulls LoTE over the network) is
    // only invoked when an issuer's signed metadata is actually verified. A
    // network failure inside the closure degrades to an empty root set, handled
    // fail-closed by TrustedChainValidator.isValid — never a startup crash. This
    // mirrors iOS, which injects a CertificateChainTrust evaluator, not bytes.
    let validator = TrustedChainValidator({ =>
        try {
            trustCfg.accessTrustManager.trustAnchorsDer()
        } catch (_: Exception) {
            Array<Array<UInt8>>()
        }
    })
    let trust = WKIssuerTrust.ByValidator(validator)
    // WRPRC validation needs the signed-metadata WRPAC: upgrade to RequireSigned
    // regardless of the default policy (the kit refuses with InvalidWrprc
    // otherwise). Anchors still resolve lazily via the validator above.
    if (requireSignedForWrprc) {
        return WKIssuerMetadataPolicy.RequireSigned(trust)
    }
    match (trustCfg.defaultPolicy) {
        case TrustPolicy.Warning => WKIssuerMetadataPolicy.PreferSigned(trust)
        case TrustPolicy.Enforce => WKIssuerMetadataPolicy.RequireSigned(trust)
    }
}

func toWKCredentialPolicy(p: CredentialPolicy): WKCredentialPolicy {
    match (p) {
        case oneTimeUse => return WKCredentialPolicy.OneTimeUse
        case rotateUse => return WKCredentialPolicy.RotateUse
    }
}

func toWKCredentialOptions(co: CredentialOptions): WKCredentialOptions {
    return WKCredentialOptions(toWKCredentialPolicy(co.credentialPolicy), co.batchSize)
}

func toWKCurve(curve: String): WKCoseEcCurve {
    match (curve) {
        case "P384" => return WKCoseEcCurve.P384
        case "P521" => return WKCoseEcCurve.P521
        case _ => return WKCoseEcCurve.P256
    }
}

func toWKKeyOptions(ko: KeyOptions): WKKeyOptions {
    return WKKeyOptions(
        toWKCurve(ko.curve),
        Option<String>.Some(ko.secureAreaName),
        Option<WKKeyAccessProtection>.None,
        Option<WKKeyAccessControl>.None,
        Option<Array<WKKeyPurpose>>.None,
        Option<Array<UInt8>>.None
    )
}

func toWKKeyOptionsOpt(ko: ?KeyOptions): ?WKKeyOptions {
    match (ko) {
        case Some(k) => return Some(toWKKeyOptions(k))
        case None => return None
    }
}

func toWKDocumentStatus(s: DocumentStatus): WKDocumentStatus {
    match (s) {
        case issued => return WKDocumentStatus.Issued
        case deferred => return WKDocumentStatus.Deferred
        case pending => return WKDocumentStatus.Pending
    }
}

func fromWKDocumentStatus(s: WKDocumentStatus): DocumentStatus {
    match (s.rawValue()) {
        case "deferred" => return DocumentStatus.deferred
        case "pending" => return DocumentStatus.pending
        case _ => return DocumentStatus.issued
    }
}

func fromWKDocDataFormat(f: WKDocDataFormat): DocDataFormat {
    match (f) {
        case Sdjwt => return DocDataFormat.sdjwt
        case _ => return DocDataFormat.cbor
    }
}

func toWKOfferedDocModel(m: OfferedDocModel): WKOfferedDocModel {
    let credOpts: WKCredentialOptions = match (m.credentialOptions) {
        case Some(co) => toWKCredentialOptions(co)
        case None => WKCredentialOptions(WKCredentialPolicy.OneTimeUse, 1)
    }
    return WKOfferedDocModel(
        m.credentialConfigurationIdentifier,
        m.docType,
        m.vct,
        m.scope,
        Option<String>.None,                 // identifier
        m.displayName,
        m.algValuesSupported,
        ArrayList<WKClaim>(),
        Option<WKConfigurationCredentialMetadata>.None,
        credOpts,
        toWKKeyOptionsOpt(m.keyOptions)
    )
}

func fromWKCredentialPolicy(p: WKCredentialPolicy): CredentialPolicy {
    match (p) {
        case OneTimeUse => CredentialPolicy.oneTimeUse
        case RotateUse => CredentialPolicy.rotateUse
    }
}

func fromWKOfferedDocModel(m: WKOfferedDocModel): OfferedDocModel {
    return OfferedDocModel(
        credentialConfigurationIdentifier: m.credentialConfigurationIdentifier,
        docType: m.docType,
        vct: m.vct,
        scope: m.scope,
        displayName: m.displayName,
        algValuesSupported: m.algValuesSupported,
        docTypeOrVct: m.docTypeOrVct(),
        // Preserve the issuer-derived batch options resolved by the engine
        // (buildOfferedDocModel). Previously dropped to None, which forced the
        // controller to substitute the app-config batch size and diverge from iOS.
        credentialOptions: Some(CredentialOptions(
            credentialPolicy: fromWKCredentialPolicy(m.credentialOptions.credentialPolicy),
            batchSize: m.credentialOptions.batchSize
        )),
        keyOptions: None
    )
}

func fromWKOfferedIssuanceModel(m: WKOfferedIssuanceModel): OfferedIssuanceModel {
    let docs = ArrayList<OfferedDocModel>()
    for (d in m.docModels) { docs.add(fromWKOfferedDocModel(d)) }
    let tx: ?TxCode = match (m.txCodeSpec) {
        // Keep the real spec: hard-coding length=None made the tx-code screen
        // configure a 0-length input (the prod issuer's pre-auth offers carry
        // length=5).
        case Some(spec) => Some(TxCode(inputMode: spec.inputMode.rawValue(), length: spec.length))
        case None => None
    }
    return OfferedIssuanceModel(
        issuerName: m.issuerName,
        issuerLogoUrl: m.issuerLogoUrl,
        docModels: docs.toArray(),
        txCodeSpec: tx,
        // Registration-certificate verdict inputs captured during offer
        // resolution (getIssuerRegistration(for:) reads them with no network).
        wrpVciRegistrationPolicy: m.wrpVciRegistrationPolicy,
        wrpVciWarnings: m.wrpVciWarnings
    )
}

/** Real wallet-kit IssuerResponse → the WalletKit seam's EngineIssuerResponse. */
func fromWKIssuerResponse(response: WKIssuerResponse): EngineIssuerResponse {
    return EngineIssuerResponse(
        documents: toWalletStorageDocuments(response.documents),
        wrpIssuerWarnings: response.wrpIssuerWarnings,
        wrpIssuerPolicy: response.wrpIssuerPolicy
    )
}

/** Real storage Document → logic-core WalletStorageDocument (lifecycle view). */
func toWalletStorageDocument(d: WKDocument): WalletStorageDocument {
    return WalletStorageDocument(
        id: d.id,
        docType: d.docType,
        docDataFormat: fromWKDocDataFormat(d.docDataFormat),
        createdAt: d.createdAt,
        metadata: decodeMetadataBlob(d.metadata),
        status: fromWKDocumentStatus(d.status)
    )
}

func toWalletStorageDocuments(docs: Array<WKDocument>): Array<WalletStorageDocument> {
    let out = ArrayList<WalletStorageDocument>()
    for (d in docs) { out.add(toWalletStorageDocument(d)) }
    return out.toArray()
}

/** Real storage Document → logic-core IssuedDocument (claims-decodable view). */
func toIssuedDocument(d: WKDocument, usage!: ?CredentialsUsageCounts = None): IssuedDocument {
    // Per-claim display-name metadata persisted by the engine (path → name); empty
    // for legacy documents → claim decoders fall back to raw keys.
    let claimMetaTable = decodeClaimMetaTable(d.metadata)
    let claims = decodeDocClaims(d, claimMetaTable)
    // The RDB persistence round-trip can lose the real mdoc docType (it comes back
    // as the document id, a "doc-" placeholder). For mso_mdoc the namespace key
    // equals the docType (e.g. "eu.europa.ec.eudi.pid.1"), so recover it from the
    // decoded claims when the stored docType is unusable.
    var realDocType = d.docType
    // SD-JWT VC: the type identifier is the `vct` (dropped by the RDB round-trip
    // and filtered from the display claims). Recover it so the document
    // categorizes correctly (EHIC → Health) instead of "Other". Returns None for
    // mdoc, which then recovers its docType from the namespace claim.
    match (sdJwtVct(d)) {
        case Some(v) where !v.isEmpty() => realDocType = v
        case _ =>
            if (realDocType.isEmpty() || realDocType.startsWith("doc-")) {
                for (c in claims) {
                    match (c.namespace) {
                        case Some(ns) where !ns.isEmpty() =>
                            realDocType = ns
                            break
                        case _ => ()
                    }
                }
            }
    }
    // Decode the persisted metadata blob once. Documents issued after the
    // encodeIssuedMetadata fix carry the real credential-config display / issuer
    // display (iOS DocMetadata parity); older documents have only the issuer id
    // (or nothing) and fall back to claim-derived names below.
    let blob = decodeMetadataBlob(d.metadata)

    // Document display name: persisted credential-config display wins, then the
    // engine displayName, then a docType-derived title.
    let blobDisplayName: ?String = match (blob) {
        case Some(b) => match (b.display) {
            case Some(ds) => firstDisplayName(ds)
            case None => None
        }
        case None => None
    }
    let dn: ?String = match (blobDisplayName) {
        case Some(n) where !n.isEmpty() => Some(n)
        case _ => match (d.displayName) {
            case Some(s) where !s.isEmpty() && s != d.id && !s.startsWith("doc-") => Some(s)
            case _ => Some(prettyDocType(realDocType))
        }
    }
    // Issuer display: persisted issuerDisplay (real name + logo) wins; otherwise
    // surface the mdoc `issuing_authority` claim (e.g. "Test PID issuer"); finally
    // fall back to the credential issuer host from the metadata blob.
    var issuerDisp: ?Array<DisplayMetadata> = match (blob) {
        case Some(b) => b.issuerDisplay
        case None => None
    }
    if (issuerDisp.isNone()) {
        for (c in claims) {
            if (c.name == "issuing_authority" && !c.stringValue.isEmpty()) {
                issuerDisp = Some([DisplayMetadata(name: Some(c.stringValue))])
                break
            }
        }
    }
    let issuerId: ?String = match (blob) {
        case Some(b) where !b.credentialIssuerIdentifier.isEmpty() => Some(b.credentialIssuerIdentifier)
        case _ => None
    }
    match ((issuerDisp, issuerId)) {
        case (None, Some(id)) => issuerDisp = Some([DisplayMetadata(name: Some(id))])
        case _ => ()
    }
    // Validity: mdoc → MSO validityInfo (IssuerAuth payload; iOS reads the
    // same source, so Employee ID etc. show "Valid until …"); SD-JWT → the
    // decoded `exp` claim's ISO dataValue.
    var vFrom: ?DateTime = None
    var vUntil: ?DateTime = None
    match (fromWKDocDataFormat(d.docDataFormat)) {
        case DocDataFormat.sdjwt =>
            vUntil = sdJwtValidUntil(claims)
        case _ =>
            let validity = mdocValidity(d)
            vFrom = validity[0]
            vUntil = validity[1]
    }

    return IssuedDocument(
        id: d.id,
        createdAt: d.createdAt,
        modifiedAt: d.modifiedAt,
        displayName: dn,
        docType: realDocType,
        docClaims: claims,
        docDataFormat: fromWKDocDataFormat(d.docDataFormat),
        issuerDisplay: issuerDisp,
        credentialIssuerIdentifier: issuerId,
        validFrom: vFrom,
        validUntil: vUntil,
        credentialsUsageCounts: usage
    )
}

/**
 * mdoc validity from the MSO validityInfo (RFC 3339 tdate strings inside the
 * IssuerAuth COSE payload). Any decode failure degrades to (None, None) — the
 * list simply shows no "Valid until", never crashes.
 */
func mdocValidity(d: WKDocument): (?DateTime, ?DateTime) {
    if (d.data.isEmpty()) {
        return (None, None)
    }
    try {
        let cborRaw = if (lcLooksLikeBase64UrlTextBytes(d.data)) {
            base64UrlDecodeToBytes(String.fromUtf8(d.data))
        } else { d.data }
        let cbor = decodeCbor(cborRaw)
        let issuerSigned = IssuerSigned.fromCbor(cbor)
        let vi = issuerSigned.issuerAuth.mso.validityInfo
        var from: ?DateTime = None
        var until: ?DateTime = None
        try { from = DateTime.parse(vi.validFrom) } catch (_: Exception) { () }
        try { until = DateTime.parse(vi.validUntil) } catch (_: Exception) { () }
        return (from, until)
    } catch (_: Exception) {
        return (None, None)
    }
}

/** SD-JWT validUntil from the decoded `exp` claim (date-only ISO dataValue). */
func sdJwtValidUntil(claims: Array<DocClaim>): ?DateTime {
    for (c in claims) {
        if (c.name == "exp") {
            match (c.dataValue) {
                case DocDataValue.date(iso) where !iso.isEmpty() =>
                    try {
                        return DateTime.parse(iso + "T00:00:00Z")
                    } catch (_: Exception) {
                        try {
                            return DateTime.parse(iso)
                        } catch (_: Exception) {
                            return None
                        }
                    }
                case _ => ()
            }
        }
    }
    return None
}

/**
 * Decode the stored credential bytes into displayable claims. For mso_mdoc the
 * engine stores the raw IssuerSigned CBOR in Document.data (verified by the
 * presentation services in wallet-kit); each namespace's IssuerSignedItem becomes
 * a DocClaim. SD-JWT claim decoding is not yet wired (returns empty). Failures to
 * decode never crash the document list — they degrade to no-claims.
 */
let SDJWT_WEEKDAYS: Array<String> = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
let SDJWT_MONTHS: Array<String> = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"]

/**
 * Decode an SD-JWT VC credential into DocClaims. Ports the iOS chain
 * SdJwtUtils.toSdJwtDocModel → recreateSdJwtClaims/resolveNestedSdClaims +
 * JSON.toClaimsArray/toDocClaim/getDataValue (eudi-lib-ios-wallet-kit). Display
 * names use the prettified key until the credential claim metadata is persisted
 * (then they will come from claimMetadata, as iOS does).
 */
func decodeSdJwtClaims(d: WKDocument, metaTable: HashMap<String, String>): Array<DocClaim> {
    Hilog.info(0, "VCI-DEBUG", "decodeSdJwtClaims begin bytes=${d.data.size}")
    match (recreateSdJwtClaims(d)) {
        case Some(json) =>
            match (sdJwtToClaimsArray(json, Array<String>(), metaTable)) {
                case Some((claims, _)) =>
                    Hilog.info(0, "VCI-DEBUG", "decodeSdJwtClaims done claims=${claims.size}")
                    return claims
                case None =>
                    Hilog.info(0, "VCI-DEBUG", "decodeSdJwtClaims: no claims array")
                    return Array<DocClaim>()
            }
        case None =>
            Hilog.warn(0, "VCI-DEBUG", "decodeSdJwtClaims: recreate returned None")
            return Array<DocClaim>()
    }
}

/** Ports SdJwtUtils.recreateSdJwtClaims + resolveNestedSdClaims. */
func recreateSdJwtClaims(d: WKDocument): ?JsonValue {
    try {
        let compact = String.fromUtf8(d.data)
        let root = match (JsonValue.fromStr(SdJwtUtils.extractJwtPayload(compact))) {
            case o: JsonObject => o
            case _ => return None
        }
        // digest → disclosure name / value-fragment, from the engine resolver.
        let hashToName = HashMap<String, String>()
        let hashToValue = HashMap<String, String>()
        for (dc in SdJwtUtils.resolveDisclosures(compact)) {
            hashToValue[dc.digest] = dc.value
            match (dc.name) { case Some(n) => hashToName[dc.digest] = n; case None => () }
        }
        return resolveSdNode(root, hashToName, hashToValue)
    } catch (_: Exception) { return None }
}

/**
 * SD-JWT VC type identifier: the `vct` from the resolved credential JSON. It is
 * filtered out of the display claims (sdJwtToDocClaim skips "vct"), and the RDB
 * round-trip drops it from the stored docType — so recover it directly here to
 * categorize SD-JWT documents (e.g. EHIC → Health instead of the "Other"
 * fallback). mdoc uses the namespace/docType and yields None here.
 */
func sdJwtVct(d: WKDocument): ?String {
    match (recreateSdJwtClaims(d)) {
        case Some(v) =>
            match (v) {
                case o: JsonObject => jsonObjString(o, "vct")
                case _ => None
            }
        case None => None
    }
}

/** Parse a disclosure value-fragment back into JSON (string fragment stays string). */
func parseFragmentOrString(frag: ?String): JsonValue {
    match (frag) {
        case Some(f) => try { return JsonValue.fromStr(f) } catch (_: Exception) { return JsonString(f) }
        case None => return JsonString("")
    }
}

/** Ports SdJwtUtils.resolveNode: recursively resolve `_sd`/`...` digests, strip `_sd`/`_sd_alg`. */
func resolveSdNode(json: JsonValue, hashToName: HashMap<String, String>, hashToValue: HashMap<String, String>): JsonValue {
    return resolveSdNodeAt(json, hashToName, hashToValue, 0)
}

/**
 * Depth-bounded worker. A disclosure fragment that resolves back into another
 * `_sd` digest recurses; without a bound a malformed / adversarial credential
 * blows the stack, and a StackOverflowError is an `Error` — NOT caught by the
 * `catch (_: Exception)` in recreateSdJwtClaims — so it unwinds through the UI
 * callback and silently aborts navigation (same failure class as the mso_mdoc
 * OutOfMemoryError noted in decodeDocClaims). Real SD-JWTs nest only a few
 * levels; 64 is far above any legitimate credential.
 */
func resolveSdNodeAt(
    json: JsonValue,
    hashToName: HashMap<String, String>,
    hashToValue: HashMap<String, String>,
    depth: Int64
): JsonValue {
    if (depth > 64) {
        Hilog.warn(0, "VCI-DEBUG", "resolveSdNode: depth limit hit — truncating branch")
        return json
    }
    let resolveSdNode = { j: JsonValue, hn: HashMap<String, String>, hv: HashMap<String, String> =>
        resolveSdNodeAt(j, hn, hv, depth + 1)
    }
    match (json) {
        case obj: JsonObject =>
            let result = JsonObject()
            match (obj.get("_sd")) {
                case Some(sdArr: JsonArray) =>
                    for (h in sdArr.getItems()) {
                        match (h) {
                            case hs: JsonString =>
                                let digest = hs.getValue()
                                match (hashToName.get(digest)) {
                                    case Some(nm) =>
                                        result.put(nm, resolveSdNode(parseFragmentOrString(hashToValue.get(digest)), hashToName, hashToValue))
                                    case None => ()
                                }
                            case _ => ()
                        }
                    }
                case _ => ()
            }
            for ((k, v) in obj.getFields()) {
                if (k == "_sd" || k == "_sd_alg") { continue }
                result.put(k, resolveSdNode(v, hashToName, hashToValue))
            }
            return result
        case arr: JsonArray =>
            let out = JsonArray()
            for (el in arr.getItems()) {
                match (el) {
                    case eo: JsonObject =>
                        match (eo.get("...")) {
                            case Some(dss: JsonString) =>
                                match (hashToValue.get(dss.getValue())) {
                                    case Some(vfrag) => out.add(resolveSdNode(parseFragmentOrString(vfrag), hashToName, hashToValue))
                                    case None => ()
                                }
                            case _ => out.add(resolveSdNode(eo, hashToName, hashToValue))
                        }
                    case _ => out.add(resolveSdNode(el, hashToName, hashToValue))
                }
            }
            return out
        case _ => return json
    }
}

/** Ports JSON.toClaimsArray. Recurses into objects/arrays building DocClaims. */
func sdJwtToClaimsArray(json: JsonValue, pathPrefix: Array<String>, metaTable: HashMap<String, String>): ?(Array<DocClaim>, String) {
    match (json) {
        case obj: JsonObject =>
            let a = ArrayList<DocClaim>()
            var n: Int64 = 0
            for ((key, subJson) in obj.getFields()) {
                match (sdJwtToDocClaim(subJson, key, n, pathPrefix, metaTable)) {
                    case Some(dc) => a.add(dc)
                    case None => ()
                }
                n++
            }
            // iOS displays object claims alphabetically by label (SwiftyJSON dict order).
            let sorted = sortClaimsByDisplay(a.toArray())
            return Some((sorted, jsonSummary(sorted, true)))
        case arr: JsonArray =>
            let a = ArrayList<DocClaim>()
            var n: Int64 = 0
            for (subJson in arr.getItems()) {
                match (sdJwtToDocClaim(subJson, n.toString(), n, pathPrefix, metaTable)) {
                    case Some(dc) => a.add(dc)
                    case None => ()
                }
                n++
            }
            return Some((a.toArray(), jsonSummary(a.toArray(), false)))
        case _ => return None
    }
}

/** Ports JSON.toDocClaim (internal-key skips + nested children + getDataValue). */
func sdJwtToDocClaim(json: JsonValue, key: String, order: Int64, pathPrefix: Array<String>, metaTable: HashMap<String, String>): ?DocClaim {
    if (key == "_sd" || key == "_sd_alg" || key == "...") { return None }
    let isDict = match (json) { case _: JsonObject => true; case _ => false }
    let isStr = match (json) { case _: JsonString => true; case _ => false }
    if (key == "cnf" && isDict) { return None }
    if (key == "status" && isDict) {
        match (json) {
            case o: JsonObject =>
                match (o.get("status_list")) {
                    case Some(_: JsonObject) => return None
                    case _ => ()
                }
            case _ => ()
        }
    }
    if ((key == "assurance_level" || key == "iss" || key == "aud") && isStr) { return None }
    if (key == "vct" && isStr) { return None }

    let path = appendPath(pathPrefix, key)
    let pair = match (sdJwtGetDataValue(json, key)) { case Some(p) => p; case None => return None }
    let (dv, scalarStr) = pair
    let ch = sdJwtToClaimsArray(json, path, metaTable)
    let children: ?Array<DocClaim> = match (ch) {
        case Some((cs, _)) where cs.size > 0 => Some(cs)
        case _ => None
    }
    let strVal = match (ch) { case Some((_, s)) => s; case None => scalarStr }
    // Display name from issuer claim metadata (by exact path); None → the view
    // falls back to the raw key, exactly as iOS does for unlabelled claims
    // (e.g. exp/iat). No prettify (that was a self-invented deviation).
    let displayName = lookupClaimName(metaTable, path)
    return DocClaim(
        name: key, displayName: displayName,
        dataValue: dv, stringValue: strVal, isOptional: true,
        order: order, namespace: None, children: children, path: path
    )
}

/** Ports JSON.getDataValue (number/string/bool; iat/exp → date). */
func sdJwtGetDataValue(json: JsonValue, name: String): ?(DocDataValue, String) {
    match (json) {
        case n: JsonInt =>
            if (name == "iat" || name == "exp") {
                // Local-timezone calendar date — iOS formats these epoch claims
                // with Date.formatted (local calendar), so a UTC date here shows
                // one day early east of Greenwich (e.g. exp 22:00Z → next local day).
                let dt = DateTime.fromUnixTimeStamp(n.getValue() * Duration.second).inLocal()
                return Some((DocDataValue.date(sdJwtIsoDate(dt)), sdJwtCompleteDate(dt)))
            }
            let s = n.getValue().toString()
            return Some((DocDataValue.text(s), s))
        case f: JsonFloat =>
            let s = f.getValue().toString()
            return Some((DocDataValue.text(s), s))
        case s: JsonString =>
            return Some((DocDataValue.text(s.getValue()), s.getValue()))
        case b: JsonBool =>
            let yn = if (b.getValue()) { "Y" } else { "N" }
            return Some((DocDataValue.text(yn), yn))
        case _: JsonArray => return Some((DocDataValue.text(""), ""))
        case _: JsonObject => return Some((DocDataValue.text(""), ""))
        case _ => return None
    }
}

func appendPath(prefix: Array<String>, key: String): Array<String> {
    let out = ArrayList<String>()
    for (p in prefix) { out.add(p) }
    out.add(key)
    return out.toArray()
}

func sdJwtIsoDate(dt: DateTime): String {
    let m = if (dt.monthValue < 10) { "0${dt.monthValue}" } else { "${dt.monthValue}" }
    let d = if (dt.dayOfMonth < 10) { "0${dt.dayOfMonth}" } else { "${dt.dayOfMonth}" }
    return "${dt.year}-${m}-${d}"
}

func sdJwtCompleteDate(dt: DateTime): String {
    let wd = SDJWT_WEEKDAYS[dt.dayOfWeek.toInteger()]
    let mo = SDJWT_MONTHS[dt.monthValue - 1]
    return "${wd}, ${dt.dayOfMonth} ${mo} ${dt.year}"
}

/** Stable insertion sort of DocClaims by display label (case-insensitive). */
func sortClaimsByDisplay(claims: Array<DocClaim>): Array<DocClaim> {
    let arr = claims
    var i = 1
    while (i < arr.size) {
        let key = arr[i]
        let keyLabel = (key.displayName ?? key.name).toAsciiLower()
        var j = i - 1
        while (j >= 0 && (arr[j].displayName ?? arr[j].name).toAsciiLower() > keyLabel) {
            arr[j + 1] = arr[j]
            j--
        }
        arr[j + 1] = key
        i++
    }
    return arr
}

/** A compact string summary of a claim group (iOS toClaimsArray's joined value). */
func jsonSummary(claims: Array<DocClaim>, isDict: Bool): String {
    let sb = StringBuilder()
    if (isDict) { sb.append("{") }
    var first = true
    for (c in claims) {
        if (!first) { sb.append(",") }
        if (isDict) { sb.append("${c.name}: ${c.stringValue}") } else { sb.append(c.stringValue) }
        first = false
    }
    if (isDict) { sb.append("}") }
    return sb.toString()
}

/** Join a claim path into a single map key (unit-separator joined). */
func joinClaimPath(path: Array<String>): String {
    var key = ""
    var first = true
    for (p in path) {
        if (first) { key = p; first = false } else { key = key + "\u{1f}" + p }
    }
    return key
}

/**
 * Look up the issuer-provided display name for a claim path. Mirrors iOS
 * convertToJsonClaimMetadata: the display name is the metadata entry whose
 * claimPath equals this exact path. Returns None when absent → callers fall
 * back to the raw key (iOS shows the raw key for claims without metadata,
 * e.g. exp/iat).
 */
func lookupClaimName(metaTable: HashMap<String, String>, path: Array<String>): ?String {
    let key = joinClaimPath(path)
    if (metaTable.contains(key)) { return Some(metaTable[key]) }
    return None
}

/**
 * Decode the compact per-claim display-name metadata persisted by the engine
 * (encodeIssuedMetadata "claims": [{"path":[...],"name":"..."}]) into a
 * path→name lookup table. Empty when the blob carries no claim metadata
 * (legacy documents) so callers fall back to raw keys.
 */
func decodeClaimMetaTable(bytes: ?Array<UInt8>): HashMap<String, String> {
    let table = HashMap<String, String>()
    match (bytes) {
        case Some(b) where b.size > 0 =>
            try {
                match (JsonValue.fromStr(String.fromUtf8(b))) {
                    case obj: JsonObject =>
                        match (obj.get("claims")) {
                            case Some(arr: JsonArray) =>
                                for (item in arr.getItems()) {
                                    match (item) {
                                        case o: JsonObject =>
                                            let nm = match (o.get("name")) {
                                                case Some(js: JsonString) => js.getValue()
                                                case _ => ""
                                            }
                                            match (o.get("path")) {
                                                case Some(pa: JsonArray) where !nm.isEmpty() =>
                                                    let segs = ArrayList<String>()
                                                    for (seg in pa.getItems()) {
                                                        match (seg) {
                                                            case s: JsonString => segs.add(s.getValue())
                                                            case _ => ()
                                                        }
                                                    }
                                                    if (segs.size > 0) { table[joinClaimPath(segs.toArray())] = nm }
                                                case _ => ()
                                            }
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                    case _ => ()
                }
            } catch (_: Exception) { () }
        case _ => ()
    }
    return table
}

func decodeDocClaims(d: WKDocument, metaTable: HashMap<String, String>): Array<DocClaim> {
    if (d.data.isEmpty()) {
        return Array<DocClaim>()
    }
    // SD-JWT VC credentials are JWT strings ("eyJ…~disclosure~…"), NOT CBOR
    // IssuerSigned. Decode them via the SD-JWT compact parser (disclosures →
    // claim name/value); the mso_mdoc CBOR path below must NOT run on them — it
    // would base64-decode the JWT into garbage and hand it to the CBOR decoder,
    // which can read a bogus multi-gigabyte length field and raise OutOfMemoryError
    // (an Error, not caught by the try/catch below → whole document reload aborts).
    match (fromWKDocDataFormat(d.docDataFormat)) {
        case DocDataFormat.sdjwt =>
            // Keep Errors (OOM / stack overflow on malformed SD-JWT) from
            // unwinding through UI navigation — degrade to no claims.
            try {
                return decodeSdJwtClaims(d, metaTable)
            } catch (_: Exception) {
                Hilog.warn(0, "VCI-DEBUG", "decodeSdJwtClaims threw; returning empty claims")
                return Array<DocClaim>()
            }
        case _ => ()
    }
    let out = ArrayList<DocClaim>()
    try {
        // The engine stores mso_mdoc credentials as the base64url credential
        // STRING bytes (Credential.StringCredential -> s.toArray()), not decoded
        // binary. Try a raw CBOR parse first (in case it is already binary), then
        // fall back to base64url-decoding the text into IssuerSigned CBOR.
        let cborRaw = if (lcLooksLikeBase64UrlTextBytes(d.data)) {
            base64UrlDecodeToBytes(String.fromUtf8(d.data))
        } else { d.data }
        let cbor = decodeCbor(cborRaw)
        let issuerSigned = IssuerSigned.fromCbor(cbor)
        match (issuerSigned.issuerNameSpaces) {
            case Some(ns) =>
                var ord: Int64 = 0
                for ((namespace, items) in ns.nameSpaces) {
                    for (item in items) {
                        let (dv, sv) = cborValueToDocData(item.elementValue)
                        // Issuer claim-metadata display name (path [namespace, key] or
                        // [key]); else prettified raw key. iOS DocClaimMetadata parity.
                        let msoDisplay: ?String = match (lookupClaimName(metaTable, [namespace, item.elementIdentifier])) {
                            case Some(nm) => Some(nm)
                            case None => match (lookupClaimName(metaTable, [item.elementIdentifier])) {
                                case Some(nm) => Some(nm)
                                case None => Some(prettifyClaimKey(item.elementIdentifier))
                            }
                        }
                        out.add(DocClaim(
                            name: item.elementIdentifier,
                            displayName: msoDisplay,
                            dataValue: dv,
                            stringValue: formatClaimValue(sv),
                            order: ord,
                            namespace: Some(namespace)
                        ))
                        ord++
                    }
                }
            case None => ()
        }
    } catch (_: Exception) {
        // undecodable credential bytes → render the document with no claim fields
        // rather than dropping it from the list.
    }
    return out.toArray()
}

/** Map a CBOR element value to logic-core's DocDataValue + a display string. */
func cborValueToDocData(v: CborValue): (DocDataValue, String) {
    match (v) {
        case CborValue.TextStringVal(s) => return (DocDataValue.text(s), s)
        case CborValue.UInt64Val(n) =>
            let s = n.toString()
            return (DocDataValue.text(s), s)
        case CborValue.NInt64Val(n) =>
            let s = "-" + (n + 1).toString()
            return (DocDataValue.text(s), s)
        case CborValue.BoolVal(b) =>
            let s = b.toString()
            return (DocDataValue.text(s), s)
        case CborValue.DoubleVal(x) =>
            let s = x.toString()
            return (DocDataValue.text(s), s)
        case CborValue.FloatVal(x) =>
            let s = x.toString()
            return (DocDataValue.text(s), s)
        case CborValue.HalfVal(x) =>
            let s = x.toString()
            return (DocDataValue.text(s), s)
        case CborValue.ByteStringVal(bytes) => return (DocDataValue.imageValue(bytes), "")
        // Tag-wrapped values (e.g. full-date tag 1004 / date-time tag 0) carry their
        // payload inside; surface the inner value.
        case CborValue.TaggedVal(_, inner) => return cborValueToDocData(inner)
        case _ => return (DocDataValue.text(""), "")
    }
}

/**
 * Lenient base64 / base64url decoder to raw bytes. Accepts both alphabets
 * (`+/` and `-_`), ignores padding and whitespace. Used to turn the stored
 * base64url credential string back into binary IssuerSigned CBOR.
 */
func base64UrlDecodeToBytes(s: String): Array<UInt8> {
    let out = ArrayList<UInt8>()
    var acc: UInt32 = 0
    var bits: Int64 = 0
    for (ch in s.toArray()) {
        var v: Int64 = -1
        if (ch >= 65 && ch <= 90) {        // A-Z
            v = Int64(ch) - 65
        } else if (ch >= 97 && ch <= 122) { // a-z
            v = Int64(ch) - 97 + 26
        } else if (ch >= 48 && ch <= 57) {  // 0-9
            v = Int64(ch) - 48 + 52
        } else if (ch == 43 || ch == 45) {  // + or -
            v = 62
        } else if (ch == 47 || ch == 95) {  // / or _
            v = 63
        } else {
            continue                        // skip '=', whitespace, anything else
        }
        acc = (acc << 6) | UInt32(v)
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out.add(UInt8((acc >> UInt32(bits)) & UInt32(0xFF)))
        }
    }
    return out.toArray()
}

/** Human-readable fallback document title derived from the mdoc docType. */
func prettyDocType(docType: String): String {
    // Map the known EUDI credential doc-types / VCTs to readable names (the
    // issuer-metadata display name is lost across the storage round-trip, so we
    // resolve a friendly title from the doc-type identifier — see toIssuedDocument).
    if (docType.contains("pid")) {
        return "Personal ID"
    }
    if (docType.contains("mdl") || docType.contains("driving") || docType.contains("iso.18013")) {
        return "Driving Licence"
    }
    if (docType.contains("cor")) {
        return "Certificate of Residence"
    }
    if (docType.contains("ehic")) {
        return "EHIC"
    }
    if (docType.contains("diploma")) {
        return "Diploma"
    }
    if (docType.contains("employee")) {
        return "Employee ID"
    }
    if (docType.contains("hiid") || docType.contains("health")) {
        return "Health ID"
    }
    if (docType.contains("iban")) {
        return "IBAN"
    }
    if (docType.contains("pseudonym")) {
        return "Pseudonym"
    }
    if (docType.contains("tax")) {
        return "Tax ID"
    }
    if (docType.contains("age")) {
        return "Age Verification"
    }
    // Unknown type → prettify the trailing identifier segment rather than show
    // the raw reverse-DNS doc-type.
    return prettifyClaimKey(lastDocTypeSegment(docType))
}

/** Last meaningful segment of a doc-type/vct (strip reverse-DNS prefix + format
 *  suffix), e.g. "eu.europa.ec.eudi.cor_mdoc" → "cor". */
func lastDocTypeSegment(docType: String): String {
    var s = docType
    let dot = s.toArray()
    // take substring after the final '.' if present
    var idx = -1
    var i = 0
    for (b in dot) {
        if (b == b'.') { idx = i }
        i++
    }
    if (idx >= 0 && idx + 1 < dot.size) {
        let tail = ArrayList<Byte>()
        var j = idx + 1
        while (j < dot.size) { tail.add(dot[j]); j++ }
        s = String.fromUtf8(tail.toArray())
    }
    return s
}

/** ISO date value (YYYY-MM-DD, optionally with a T… time) → "D Mon YYYY"
 *  (iOS claim value style, e.g. "2026-09-22" → "22 Sep 2026"); other values
 *  pass through unchanged. */
func formatClaimValue(v: String): String {
    let b = v.toArray()
    if (b.size < 10 || b[4] != b'-' || b[7] != b'-'
        || !allDigits(b, 0, 4) || !allDigits(b, 5, 7) || !allDigits(b, 8, 10)) {
        return v
    }
    // Exact YYYY-MM-DD, or ISO datetime whose date prefix is followed by T/space.
    // "2023-01-05extra" must stay unchanged.
    if (b.size > 10 && b[10] != b'T' && b[10] != b' ') {
        return v
    }
    let year = String.fromUtf8([b[0], b[1], b[2], b[3]])
    let mo = Int64(b[5] - b'0') * 10 + Int64(b[6] - b'0')
    let day = Int64(b[8] - b'0') * 10 + Int64(b[9] - b'0')
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    if (mo >= 1 && mo <= 12) {
        return "${day} ${months[mo - 1]} ${year}"
    }
    return v
}

func allDigits(b: Array<Byte>, start: Int64, end: Int64): Bool {
    var i = start
    while (i < end) {
        if (b[i] < b'0' || b[i] > b'9') {
            return false
        }
        i++
    }
    return true
}

/** snake_case / dotted claim key → Title Case label (given_name → "Given Name").
 *  Pragmatic stand-in for the per-claim metadata display name (not persisted). */
func prettifyClaimKey(key: String): String {
    let bytes = key.toArray()
    let out = ArrayList<Byte>()
    var capNext = true
    for (b in bytes) {
        if (b == b'_' || b == b'.' || b == b'-') {
            if (!out.isEmpty()) {
                out.add(b' ')
            }
            capNext = true
        } else {
            var c = b
            if (capNext && c >= b'a' && c <= b'z') {
                c = c - 32
            }
            capNext = false
            out.add(c)
        }
    }
    if (out.isEmpty()) {
        return key
    }
    return String.fromUtf8(out.toArray())
}

/**
 * Decode the engine Document's opaque metadata bytes into logic-core's
 * DocMetadataBlob. The bytes are UTF-8 JSON with a credentialIssuerIdentifier
 * field when present; absent/undecodable metadata → None (iOS-faithful).
 */
func decodeMetadataBlob(bytes: ?Array<UInt8>): ?DocMetadataBlob {
    match (bytes) {
        case Some(b) where b.size > 0 =>
            let text = String.fromUtf8(b)
            let issuer = jsonStringField(text, "credentialIssuerIdentifier")
            // For Pending (authorization-code) documents the engine stores the https
            // authorization URL under "pending_reason_url" — surface it as the
            // pendingAuthorizationUrl accessor (iOS authorizePresentationUrl parity).
            let authUrl = jsonStringField(text, "pending_reason_url")
            let configId = jsonStringField(text, "configurationIdentifier")
            // Issued documents persist the credential-config display / issuer display
            // (engine encodeIssuedMetadata, iOS DocMetadata parity) so the wallet UI
            // shows the real document & issuer names and logos instead of names
            // reconstructed from raw claims. Best-effort: legacy/pending blobs without
            // these arrays simply leave them None.
            var disp: ?Array<DisplayMetadata> = None
            var issDisp: ?Array<DisplayMetadata> = None
            try {
                match (JsonValue.fromStr(text)) {
                    case obj: JsonObject =>
                        disp = parseDisplayMetadataArray(obj, "display")
                        issDisp = parseDisplayMetadataArray(obj, "issuerDisplay")
                    case _ => ()
                }
            } catch (_: Exception) { () }
            match ((issuer, authUrl)) {
                case (Some(id), _) =>
                    return Some(DocMetadataBlob(
                        credentialIssuerIdentifier: id,
                        display: disp,
                        issuerDisplay: issDisp,
                        configurationIdentifier: configId,
                        pendingAuthorizationUrl: authUrl
                    ))
                case (None, Some(_)) =>
                    return Some(DocMetadataBlob(
                        credentialIssuerIdentifier: "",
                        pendingAuthorizationUrl: authUrl
                    ))
                case _ => return None
            }
        case _ => return None
    }
}

/** Locale-preferred display name from a DisplayMetadata list (else first). */
func firstDisplayName(ds: Array<DisplayMetadata>): ?String {
    let locale = systemLanguageCode()
    for (d in ds) {
        if (let Some(loc) <- d.localeIdentifier && loc == locale) {
            if (let Some(n) <- d.name) { return Some(n) }
        }
    }
    if (ds.size > 0) { return ds[0].name }
    return None
}

/**
 * Parse a JSON array of display entries ({name, locale, logo:{uri}}) under `key`
 * into logic-core DisplayMetadata. Returns None when the key is absent/empty so
 * callers fall back to claim-derived display. Mirrors the engine
 * displayListToJson encoder.
 */
func parseDisplayMetadataArray(obj: JsonObject, key: String): ?Array<DisplayMetadata> {
    match (obj.get(key)) {
        case Some(arr: JsonArray) =>
            let out = ArrayList<DisplayMetadata>()
            for (item in arr.getItems()) {
                match (item) {
                    case o: JsonObject =>
                        let nm = jsonObjString(o, "name")
                        let loc = jsonObjString(o, "locale")
                        var logo: ?DisplayLogo = None
                        match (o.get("logo")) {
                            case Some(lo: JsonObject) =>
                                match (jsonObjString(lo, "uri")) {
                                    case Some(u) where !u.isEmpty() => logo = Some(DisplayLogo(Some(u)))
                                    case _ => ()
                                }
                            case _ => ()
                        }
                        out.add(DisplayMetadata(name: nm, localeIdentifier: loc, logo: logo))
                    case _ => ()
                }
            }
            if (out.size > 0) { return Some(out.toArray()) }
            return None
        case _ => return None
    }
}

/**
 * Extract a top-level JSON string field value, JSON-unescaped.
 *
 * Uses the real JSON parser so escape sequences are decoded — critically
 * `&`, which the engine's JSON serializer emits for `&` in the
 * authorization URL (`pending_reason_url`). A naive substring grab would
 * return the literal `&`, corrupting `?a=1&b=2` into a single query
 * param and making the issuer reject the request ("Missing required
 * parameters"). Falls back to a manual-unescape substring scan if the blob
 * is not cleanly parseable.
 */
func jsonStringField(json: String, key: String): ?String {
    try {
        match (JsonValue.fromStr(json)) {
            case obj: JsonObject =>
                match (obj.get(key)) {
                    case Some(js: JsonString) => return Some(js.getValue())
                    case _ => ()
                }
            case _ => ()
        }
    } catch (_: Exception) { () }
    return jsonStringFieldRaw(json, key)
}

/** Substring fallback that still unescapes JSON string escapes. */
func jsonStringFieldRaw(json: String, key: String): ?String {
    let needle = "\"" + key + "\""
    if (let Some(ki) <- json.indexOf(needle)) {
        let rest = json[ki + needle.size..json.size]
        if (let Some(ci) <- rest.indexOf(":")) {
            var after = rest[ci + 1..rest.size]
            // skip whitespace
            var start = 0
            while (start < after.size && (after[start] == b' ' || after[start] == b'\t')) { start++ }
            if (start < after.size && after[start] == b'"') {
                let valRest = after[start + 1..after.size]
                if (let Some(endq) <- valRest.indexOf("\"")) {
                    return Some(jsonUnescape(valRest[0..endq]))
                }
            }
        }
    }
    return None
}

/** Decode JSON string escapes (\\u + 4 hex digits, \\", \\\\, \\/, \\n, ...) in a value with no embedded quotes. */
func jsonUnescape(s: String): String {
    if (!s.contains("\\")) { return s }
    // Rune walk: a `\` in an otherwise UTF-8 value (e.g. pending URL with
    // `\&` plus a non-ASCII issuer path, or a lone `\é`) must not feed a
    // single continuation/lead byte to String.fromUtf8.
    let runes = s.toRuneArray()
    var out = ""
    var i: Int64 = 0
    while (i < runes.size) {
        if (runes[i] == r'\\' && i + 1 < runes.size) {
            let c = runes[i + 1]
            if (c == r'u' && i + 5 < runes.size) {
                let hex = String(runes[i + 2]) + String(runes[i + 3]) +
                    String(runes[i + 4]) + String(runes[i + 5])
                out = out + codePointToString(parseHex16(hex))
                i += 6
            } else if (c == r'n') {
                out = out + "\n"
                i += 2
            } else if (c == r't') {
                out = out + "\t"
                i += 2
            } else if (c == r'r') {
                out = out + "\r"
                i += 2
            } else if (c == r'b') {
                out = out + "\b"
                i += 2
            } else if (c == r'f') {
                out = out + "\f"
                i += 2
            } else {
                out = out + String(c)
                i += 2
            }
        } else {
            out = out + String(runes[i])
            i++
        }
    }
    return out
}

/** Parse 4 hex digits into a UInt32 code point; 0 on any non-hex digit. */
func parseHex16(hex: String): UInt32 {
    var acc: UInt32 = 0
    for (b in hex.toArray()) {
        var d: UInt32 = 0
        if (b >= b'0' && b <= b'9') { d = UInt32(b - b'0') }
        else if (b >= b'a' && b <= b'f') { d = UInt32(b - b'a') + 10 }
        else if (b >= b'A' && b <= b'F') { d = UInt32(b - b'A') + 10 }
        else { return 0 }
        acc = acc * 16 + d
    }
    return acc
}

/** Encode a BMP code point as a UTF-8 String. */
func codePointToString(cp: UInt32): String {
    if (cp >= 0xD800 && cp <= 0xDFFF) {
        return ""
    }
    if (cp < 0x80) {
        return String.fromUtf8([UInt8(cp)])
    } else if (cp < 0x800) {
        return String.fromUtf8([UInt8(0xC0 | (cp >> 6)), UInt8(0x80 | (cp & 0x3F))])
    } else if (cp < 0x10000) {
        return String.fromUtf8([
            UInt8(0xE0 | (cp >> 12)),
            UInt8(0x80 | ((cp >> 6) & 0x3F)),
            UInt8(0x80 | (cp & 0x3F))
        ])
    }
    return ""
}

func fromWKCredentialStatus(s: WKCredentialStatus): CredentialStatus {
    match (s) {
        case Valid => return CredentialStatus.valid
        case Invalid => return CredentialStatus.invalid
        case Suspended => return CredentialStatus.suspended
        case _ => return CredentialStatus.unknownStatus
    }
}

/** Split a logic-core StatusIdentifier "uri#idx" into (uri, idx). */
func splitStatusIdentifier(id: String): (String, Int64) {
    if (let Some(hi) <- id.indexOf("#")) {
        let uri = id[0..hi]
        let idxStr = id[hi + 1..id.size]
        return (uri, parseIntOrZero(idxStr))
    }
    return (id, 0)
}

/** Parse a non-negative integer from its decimal digits; 0 on any non-digit. */
func parseIntOrZero(s: String): Int64 {
    if (s.isEmpty()) { return 0 }
    var acc: Int64 = 0
    for (b in s.toArray()) {
        if (b < b'0' || b > b'9') { return 0 }
        try {
            acc = acc * 10 + Int64(b - b'0')
        } catch (_: OverflowException) {
            return 0
        }
    }
    return acc
}

/** Real CredentialIssuerMetadata → logic-core IssuerMetadata (scoped-doc view). */
func fromWKIssuerMetadata(md: WKCredentialIssuerMetadata): IssuerMetadata {
    let supported = HashMap<String, SupportedCredential>()
    for ((configId, obj) in md.credentialConfigurationsRaw) {
        let format = jsonObjString(obj, "format")
        let docType = jsonObjString(obj, "doctype")
        let vct = jsonObjString(obj, "vct")
        // Parse the credential-config display so the AddDocument "Choose from list"
        // screen shows the friendly document name (e.g. "Certificate of Residence")
        // instead of the raw configuration id. iOS shows the metadata display name.
        let displays = parseConfigDisplays(obj)
        let credMeta: ?CredentialMetadata = if (displays.size > 0) {
            Some(CredentialMetadata(displays))
        } else {
            None
        }
        match (docType) {
            case Some(dt) =>
                supported.add(configId, SupportedCredential.msoMdoc(MsoMdocConfig(docType: dt, credentialMetadata: credMeta)))
            case None =>
                match (vct) {
                    case Some(v) =>
                        supported.add(configId, SupportedCredential.sdJwtVc(SdJwtVcConfig(vct: Some(v), credentialMetadata: credMeta)))
                    case None =>
                        let _ = format
                        supported.add(configId, SupportedCredential.otherFormat)
                }
        }
    }
    return IssuerMetadata(
        credentialIssuerIdentifier: md.credentialIssuerIdentifier.url,
        credentialsSupported: supported
    )
}

/**
 * Parse credential-config `display` entries (name/locale) for AddDocument naming.
 * Newer OID4VCI drafts (eudiw.dev) nest per-credential display under
 * `credential_metadata.display`; older drafts use a top-level `display`. Try the
 * nested location first, then fall back.
 */
func parseConfigDisplays(obj: JsonObject): Array<Display> {
    let out = ArrayList<Display>()
    var displayVal: ?JsonValue = None
    match (obj.get("credential_metadata")) {
        case Some(cm: JsonObject) => displayVal = cm.get("display")
        case _ => ()
    }
    if (displayVal.isNone()) { displayVal = obj.get("display") }
    match (displayVal) {
        case Some(arr: JsonArray) =>
            for (item in arr.getItems()) {
                match (item) {
                    case o: JsonObject =>
                        out.add(Display(name: jsonObjString(o, "name"), locale: jsonObjString(o, "locale")))
                    case _ => ()
                }
            }
        case _ => ()
    }
    return out.toArray()
}

/** Read a top-level string field from a stdx JsonObject; None when absent/non-string. */
func jsonObjString(obj: JsonObject, key: String): ?String {
    match (obj.get(key)) {
        case Some(js: JsonString) => return Some(js.getValue())
        case _ => return None
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// EnginePresentationSession — adapts the real wallet-kit PresentationSession to
// the logic-core PresentationSession interface the coordinators consume.
// ═════════════════════════════════════════════════════════════════════════════

class EnginePresentationSession <: PresentationSession {
    private let session: WKPresentationSession
    private let observers = ArrayList<(PresentationSessionStatus) -> Unit>()
    private let lock = Mutex()
    /** The `onSent` of the in-flight sendResponse; fired once by the engine's
     *  ResponseSent transition (its onSuccess), cleared on error/disconnect. */
    private var pendingOnSent: Option<(?String) -> Unit> = None

    init(session: WKPresentationSession) {
        this.session = session
        let self0 = this
        this.session.onStatusChange = Some({ st: WKPresentationStatus =>
            self0.notify(mapStatus(st))
            match (st) {
                // Carry the verifier redirect (recorded by the engine's
                // sendResponse success before it flips ResponseSent) out to the
                // caller — iOS `.responseSent(url)`. The RQES service/credential
                // authorization needs it to continue the QTSP OAuth flow
                // (walletcentric → rqes://…?code); None for ordinary presentations.
                case ResponseSent => self0.fireOnSent(self0.session.lastRedirect)
                case SessionError(_) => self0.clearOnSent()
                case Disconnected => self0.clearOnSent()
                case _ => ()
            }
        })
    }

    public prop status: PresentationSessionStatus {
        get() { mapStatus(this.session.status) }
    }

    public prop disclosedDocuments: Array<DocElements> {
        get() {
            // The engine has already resolved the verifier's exact requested
            // elements against stored documents. Preserve that selection
            // metadata through the logic-core seam; rebuilding from docClaims
            // would show (and potentially disclose) non-requested fields.
            let out = ArrayList<DocElements>()
            for (set in this.session.disclosedDocumentSets) {
                for (elements in set.docElements) {
                    out.add(toSeamDocElements(elements))
                }
            }
            return out.toArray()
        }
    }

    /**
     * iOS `itemSets: session.disclosedDocumentSets.map(\.docElements)`.
     *
     * A set is one way to satisfy the whole request and holds every document
     * that takes part in it. `PresentationSession.decodeRequest` walks all
     * stored documents and appends one DocElements per document whose type
     * matches — so four PIDs against one requested docType land in a single
     * set, and the request screen shows four cards with per-claim checkboxes.
     * Separate sets only arise when the service emits several
     * UserRequestInfo (DCQL credential sets); this port's services emit one,
     * so the mapping is a straight per-set conversion — never a split of one
     * set into one-document alternatives.
     */
    public prop disclosedItemSets: Array<Array<DocElements>> {
        get() {
            let out = ArrayList<Array<DocElements>>()
            for (set in this.session.disclosedDocumentSets) {
                let converted = ArrayList<DocElements>()
                for (elements in set.docElements) {
                    converted.add(toSeamDocElements(elements))
                }
                out.add(converted.toArray())
            }
            return out.toArray()
        }
    }

    public prop readerCertIssuer: ?String {
        get() { this.session.readerCertIssuer }
    }

    public prop readerCertValidationMessage: ?String {
        get() {
            match (this.session.uiError) {
                case Some(e) => return Some(e.message)
                case None => return None
            }
        }
    }

    public prop readerCertIssuerValid: ?Bool {
        get() { Some(this.session.readerCertIssuerValid) }
    }

    /** "mdoc:" + base64url(DeviceEngagement CBOR) once QR engagement is ready
     *  (the engine keeps the raw encoding for the SessionTranscript). */
    public prop deviceEngagement: ?String {
        get() { this.session.deviceEngagement }
    }

    public prop uiErrorDescription: ?String {
        get() {
            match (this.session.uiError) {
                case Some(e) => return Some(e.message)
                case None =>
                    match (this.session.status) {
                        case SessionError(msg) => return Some(msg)
                        case _ => return None
                    }
            }
        }
    }

    /** Registration-certificate layer (wallet-kit 0.40.x) — populated by the
     *  engine on receiveRequest, surfaced verbatim through the seam. */
    public prop disclosedDocumentSets: Array<DisclosedDocumentSet> {
        get() { this.session.disclosedDocumentSets }
    }

    public prop wrpVerifierPolicy: ?WrpRegistrationPolicy {
        get() { this.session.wrpVerifierPolicy }
    }

    public prop wrpVerifierWarnings: ?HashMap<String, Array<PresentationPolicyViolation>> {
        get() { this.session.wrpVerifierWarnings }
    }

    public prop readerCertificateChain: ?Array<Array<UInt8>> {
        get() { this.session.readerCertificateChain }
    }

    public func observeStatus(observer: (PresentationSessionStatus) -> Unit): Unit {
        synchronized(lock) { this.observers.add(observer) }
        observer(this.status)
    }

    public func startQrEngagement(): Unit {
        let _ = this.session.startQrEngagement()
    }

    public func receiveRequest(): Unit {
        this.session.receiveRequest()
    }

    /**
     * `onSent` is not invoked here: the engine fires its onSuccess only after the
     * transport reports ResponseSent, which arrives through onStatusChange and
     * releases the pending callback (see `fireOnSent`). A declined request is
     * cancelled on the session (no response is written), so onSent never fires.
     */
    public func sendResponse(userAccepted: Bool, itemsToSend: RequestConvertibleItems, onSent: (?String) -> Unit): Unit {
        if (!userAccepted) {
            this.session.cancel("user declined the request")
            return
        }
        synchronized(lock) { this.pendingOnSent = Some(onSent) }
        try {
            this.session.sendResponse(toWKRequestItems(itemsToSend))
        } catch (e: Exception) {
            this.clearOnSent()
            throw e
        }
    }

    /** Blocks on the engine transport until the reader disconnects (deadline-bounded by the service). */
    public func waitForDisconnect(): Unit {
        this.session.service.waitForDisconnect()
    }

    /** Engine `PresentationSession.stop()`: transport stop + ephemeral-key deletion. */
    public func stop(): Unit {
        this.clearOnSent()
        this.session.stop()
    }

    private func notify(s: PresentationSessionStatus): Unit {
        var snapshot = ArrayList<(PresentationSessionStatus) -> Unit>()
        synchronized(lock) { for (o in this.observers) { snapshot.add(o) } }
        for (o in snapshot) { o(s) }
    }

    /** Release the in-flight sendResponse callback exactly once (engine onSuccess → ResponseSent). */
    private func fireOnSent(url: ?String): Unit {
        var cb: Option<(?String) -> Unit> = None
        synchronized(lock) {
            cb = this.pendingOnSent
            this.pendingOnSent = None
        }
        match (cb) {
            case Some(f) => f(url)
            case None => ()
        }
    }

    private func clearOnSent(): Unit {
        synchronized(lock) { this.pendingOnSent = None }
    }
}

func appendSdJwtRequestedClaims(
    elements: ArrayList<WKSdJwtElement>,
    out: ArrayList<RequestedClaim>
): Unit {
    for (item in elements) {
        out.add(RequestedClaim(
            namespace: "",
            elementPath: item.elementPath,
            isOptional: item.isOptional,
            intentToRetain: item.intentToRetain,
            isAvailable: item.isValid
        ))
        match (item.nestedElements) {
            case Some(children) => appendSdJwtRequestedClaims(children, out)
            case None => ()
        }
    }
}

/**
 * Engine `PresentationStatus` → logic-core `PresentationSessionStatus`, one to
 * one over the full ISO 18013-5 sequence so no transport step is dropped.
 */
/** Engine → logic-core seam element conversion (one DocElements value). The
 *  engine has already matched the verifier's request against stored documents;
 *  this preserves that selection metadata (paths, optionality, availability). */
func toSeamDocElements(elements: WKDocElements): DocElements {
    match (elements) {
        case MsoMdoc(mdocElements) =>
            let requested = ArrayList<RequestedClaim>()
            for (group in mdocElements.nameSpacedElements) {
                for (item in group.elements) {
                    requested.add(RequestedClaim(
                        namespace: group.nameSpace,
                        elementPath: [item.elementIdentifier],
                        isOptional: item.isOptional,
                        intentToRetain: item.intentToRetain,
                        isAvailable: item.isValid
                    ))
                }
            }
            return DocElements(
                mdocElements.docId,
                docType: mdocElements.docType,
                requestedClaims: requested.toArray()
            )
        case SdJwt(sdJwtElements) =>
            let requested = ArrayList<RequestedClaim>()
            appendSdJwtRequestedClaims(sdJwtElements.sdJwtElements, requested)
            return DocElements(
                sdJwtElements.docId,
                docType: sdJwtElements.vct,
                requestedClaims: requested.toArray()
            )
    }
}

func mapStatus(s: WKPresentationStatus): PresentationSessionStatus {
    match (s) {
        case Initializing => return PresentationSessionStatus.initializing
        case Initialized => return PresentationSessionStatus.initialized
        case PoweredOn => return PresentationSessionStatus.poweredOn
        case QrEngagementReady(_) => return PresentationSessionStatus.qrEngagementReady
        case Connected => return PresentationSessionStatus.connected
        case Started => return PresentationSessionStatus.started
        case RequestReceived => return PresentationSessionStatus.requestReceived
        case UserSelected => return PresentationSessionStatus.userSelected
        case ResponseSent => return PresentationSessionStatus.responseSent
        case Disconnected => return PresentationSessionStatus.disconnected
        case SessionError(_) => return PresentationSessionStatus.sessionError
    }
}

/**
 * Convert logic-core's RequestConvertibleItems (docId → namespace → [logic-core
 * RequestItem]) into the engine's RequestItems (docId → namespace →
 * [mdoc-transfer RequestItem]). The two maps are structurally identical; only the
 * leaf RequestItem element type differs, so each leaf is re-mapped.
 */
func toWKRequestItems(items: RequestConvertibleItems): WKRequestItems {
    let out = HashMap<String, HashMap<String, Array<WKRequestItem>>>()
    for ((docId, namespaces) in items) {
        let nsOut = HashMap<String, Array<WKRequestItem>>()
        for ((namespace, reqItems) in namespaces) {
            let leaf = ArrayList<WKRequestItem>()
            for (ri in reqItems) {
                leaf.add(WKRequestItem(ri.elementPath, ri.intentToRetain, Option<Bool>.None))
            }
            nsOut[namespace] = leaf.toArray()
        }
        out[docId] = nsOut
    }
    return out
}


// Detect base64url TEXT bytes: issuers commonly deliver mso_mdoc credentials
// as base64url strings. Feeding that text straight to the CBOR decoder can
// mis-read a byte as a huge length header and hang cbor4cj's reader instead
// of throwing, so the format is sniffed BEFORE decoding (an IssuerSigned map
// always starts with a byte >= 0xA0, never within the base64url alphabet).
func lcLooksLikeBase64UrlTextBytes(bytes: Array<UInt8>): Bool {
    if (bytes.isEmpty()) { return false }
    for (b in bytes) {
        let ok = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
            (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x3D
        if (!ok) { return false }
    }
    return true
}
