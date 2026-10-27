/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * Port of iOS logic-core/Sources/Config/(all).swift:
 *   VciConfig, DocumentIssuanceConfig, WalletKitConfig(+Impl),
 *   WalletProviderAttestationConfig(+Impl).
 *
 * The OpenId4Vci/Vp configuration value types are owned by EudiWalletKit on iOS
 * (not yet migrated into eudi_lib_wallet_kit); the subset the wallet's config
 * builds is reproduced here so issuersConfig / vpConfig are constructed for real.
 */
package eudi_logic_core

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import eudi_logic_business.{ConfigLogic, PrefsController, PrefsKey}
import eudi_logic_business.AppBuildVariant
import kit.PerformanceAnalysisKit.Hilog
import ohos_app_cangjie_eudi_cjetsi_1196x2.etsi_trust.*
import ohos_app_cangjie_eudi_cjetsi_1196x2.lote_consultation_platform.StdxCryptoJwtSignature
import ohos_app_cangjie_eudi_cjetsi_1196x2.lote_consultation.VerifyJwtSignature

// ─────────────────────────────────────────────────────────────────────────────
// EudiWalletKit OpenId4Vci / OpenId4Vp configuration value types
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors EudiWalletKit `KeyAttestationsConfig` (wallet attestations provider). */
public class KeyAttestationsConfig {
    public let walletAttestationsProvider: WalletKitAttestationProvider
    public init(walletAttestationsProvider: WalletKitAttestationProvider) {
        this.walletAttestationsProvider = walletAttestationsProvider
    }
}

/** Mirrors EudiWalletKit `OpenId4VciConfiguration`. */
public class OpenId4VciConfiguration {
    public let credentialIssuerURL: ?String
    public let clientId: String
    public let keyAttestationsConfig: ?KeyAttestationsConfig
    public let authFlowRedirectionURI: String
    public let requirePAR: Bool
    public let requireDpop: Bool
    public let cacheIssuerMetadata: Bool
    public let validateRegistrationCertificate: Bool

    public init(
        credentialIssuerURL!: ?String,
        clientId!: String,
        keyAttestationsConfig!: ?KeyAttestationsConfig = None,
        authFlowRedirectionURI!: String,
        requirePAR!: Bool = false,
        requireDpop!: Bool = false,
        cacheIssuerMetadata!: Bool = false,
        validateRegistrationCertificate!: Bool = false
    ) {
        this.credentialIssuerURL = credentialIssuerURL
        this.clientId = clientId
        this.keyAttestationsConfig = keyAttestationsConfig
        this.authFlowRedirectionURI = authFlowRedirectionURI
        this.requirePAR = requirePAR
        this.requireDpop = requireDpop
        this.cacheIssuerMetadata = cacheIssuerMetadata
        this.validateRegistrationCertificate = validateRegistrationCertificate
    }
}

/** Mirrors EudiWalletKit clientId scheme cases used by vpConfig. */
public enum ClientIdScheme <: Equatable<ClientIdScheme> {
    | x509SanDns
    | x509Hash
    public operator func ==(o: ClientIdScheme): Bool {
        match ((this, o)) {
            case (x509SanDns, x509SanDns) => true
            case (x509Hash, x509Hash) => true
            case _ => false
        }
    }
    public operator func !=(o: ClientIdScheme): Bool { !(this == o) }
}

/** Mirrors EudiWalletKit `OpenId4VpConfiguration`. */
public class OpenId4VpConfiguration {
    public let clientIdSchemes: Array<ClientIdScheme>
    public let allowPresentingPartialClaims: Bool
    public let validateRegistrationCertificate: Bool
    public init(
        clientIdSchemes!: Array<ClientIdScheme>,
        allowPresentingPartialClaims!: Bool,
        validateRegistrationCertificate!: Bool = false
    ) {
        this.clientIdSchemes = clientIdSchemes
        this.allowPresentingPartialClaims = allowPresentingPartialClaims
        this.validateRegistrationCertificate = validateRegistrationCertificate
    }
}

/**
 * Mirrors a trusted reader root certificate chain (`[x5chain]` element). On iOS a
 * `SecCertificate` loaded from a bundled .der; here a DER byte buffer keyed by
 * the bundled resource name, loaded by WalletKitConfigImpl.loadCertificate.
 */
public class X5Chain {
    public let name: String
    public let der: Array<UInt8>
    public init(name: String, der: Array<UInt8>) {
        this.name = name
        this.der = der
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Config/VciConfig.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `VciConfig` (config + order). */
public struct VciConfig {
    public let config: OpenId4VciConfiguration
    public let order: Int64
    public init(config!: OpenId4VciConfiguration, order!: Int64) {
        this.config = config
        this.order = order
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Config/DocumentIssuanceConfig.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `DocumentIssuanceRule`. */
public struct DocumentIssuanceRule {
    public let policy: CredentialPolicy
    public let numberOfCredentials: Int64
    public init(policy!: CredentialPolicy, numberOfCredentials!: Int64) {
        this.policy = policy
        this.numberOfCredentials = numberOfCredentials
    }
}

/** Mirrors iOS `ReIssuanceRule`. */
public struct ReIssuanceRule {
    public let minNumberOfCredentials: Int64
    public let minExpirationHours: Int64
    public let backgroundIntervalSeconds: Float64
    public init(minNumberOfCredentials!: Int64, minExpirationHours!: Int64, backgroundIntervalSeconds!: Float64) {
        this.minNumberOfCredentials = minNumberOfCredentials
        this.minExpirationHours = minExpirationHours
        this.backgroundIntervalSeconds = backgroundIntervalSeconds
    }
}

/** Mirrors iOS `DocumentIssuanceConfig`. */
public class DocumentIssuanceConfig {
    public let defaultRule: DocumentIssuanceRule
    public let documentSpecificRules: HashMap<DocumentTypeIdentifier, DocumentIssuanceRule>
    public let reIssuanceRule: ReIssuanceRule

    public init(
        defaultRule!: DocumentIssuanceRule,
        documentSpecificRules!: HashMap<DocumentTypeIdentifier, DocumentIssuanceRule>,
        reIssuanceRule!: ReIssuanceRule
    ) {
        this.defaultRule = defaultRule
        this.documentSpecificRules = documentSpecificRules
        this.reIssuanceRule = reIssuanceRule
    }

    /** Mirrors `rule(for:)`. */
    public func rule(documentIdentifier: ?DocumentTypeIdentifier): DocumentIssuanceRule {
        match (documentIdentifier) {
            case Some(id) =>
                if (let Some(r) <- this.documentSpecificRules.get(id)) {
                    return r
                }
                return this.defaultRule
            case None => this.defaultRule
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MdocDataModel18013.TransactionLogger (the protocol implemented by the tx log ctrl)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mirrors MdocDataModel18013.TransactionLogger. EudiWallet calls `log(transaction:)`
 * after each presentation/issuance; WalletKitTransactionLogControllerImpl conforms.
 */
public interface TransactionLogger {
    func log(transaction: CoreTransactionLog): Unit
}

// ─────────────────────────────────────────────────────────────────────────────
// Config/WalletKitConfig.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol WalletKitConfig: Sendable`. */
public interface WalletKitConfig {
    prop issuersConfig: HashMap<String, VciConfig>
    prop vpConfig: OpenId4VpConfiguration
    prop trustConfiguration: TrustConfiguration
    /** Mirrors `validateIssuerRegistrationCertificate` — the Settings toggle
     *  gating the whole registration-certificate (WRPRC) trust layer. */
    prop validateIssuerRegistrationCertificate: Bool
    prop trustedReaderRootCertificates: Array<Array<X5Chain>>
    prop trustedIssuerRootCertificates: Array<Array<X5Chain>>
    prop userAuthenticationRequired: Bool
    prop keyOptions: ?KeyOptions
    prop logFileName: String
    prop documentsCategories: DocumentCategories
    prop transactionLogger: TransactionLogger
    prop revocationIntervalSeconds: Float64
    prop documentIssuanceConfig: DocumentIssuanceConfig
}

/** Mirrors iOS `struct WalletKitConfigImpl: WalletKitConfig`. */
public class WalletKitConfigImpl <: WalletKitConfig {
    private let configLogic: ConfigLogic
    private let transactionLoggerImpl: TransactionLogger
    private let walletKitAttestationProvider: WalletKitAttestationProvider
    private let prefsController: PrefsController
    private let loteLock = Mutex()
    private var cachedTrustConfiguration: ?TrustConfiguration = None

    public init(
        configLogic!: ConfigLogic,
        transactionLogger!: TransactionLogger,
        walletKitAttestationProvider!: WalletKitAttestationProvider,
        prefsController!: PrefsController
    ) {
        this.configLogic = configLogic
        this.transactionLoggerImpl = transactionLogger
        this.walletKitAttestationProvider = walletKitAttestationProvider
        this.prefsController = prefsController
    }

    public prop userAuthenticationRequired: Bool {
        get() { false }
    }

    public prop keyOptions: ?KeyOptions {
        get() {
            // iOS: KeyOptions(curve: .P256, secureAreaName: SecureEnclaveSecureArea.name, accessControl: [])
            // Harmony: HuksSecureArea.NAME == "HUKS". The leftover iOS string
            // "SecureEnclave" is not a registered name; get() would then fall
            // through to defaultSecurityArea() and miss this hardware area.
            KeyOptions(curve: "P256", secureAreaName: "HUKS")
        }
    }

    public prop issuersConfig: HashMap<String, VciConfig> {
        get() {
            let configs = ArrayList<VciConfig>()
            let redirect = "eu.europa.ec.euidi://authorization"
            let attest = KeyAttestationsConfig(this.walletKitAttestationProvider)
            // Both issuer families authenticate the client with
            // `attest_jwt_client_auth` under the same registration (`eudiw-abca`,
            // the `sub` of the wallet-provider's client attestation). Keycloak
            // additionally requires a challenge from its challenge_endpoint in the
            // attestation PoP; without it the PAR is rejected 401 regardless of
            // client id.
            let clientId = "eudiw-abca"
            match (this.configLogic.appBuildVariant) {
                case DEMO =>
                    configs.add(VciConfig(
                        config: OpenId4VciConfiguration(
                            credentialIssuerURL: "https://issuer.eudiw.dev",
                            clientId: clientId,
                            keyAttestationsConfig: attest,
                            authFlowRedirectionURI: redirect,
                            // iOS DEMO uses required PAR with authorization-code
                            // DPoP binding and requireDpop=true.
                            // iOS 0.40.x: cacheIssuerMetadata false — registration
                            // certificates / trust policies may change between runs.
                            requirePAR: true, requireDpop: true, cacheIssuerMetadata: false,
                            validateRegistrationCertificate: this.validateRegistrationCertificate
                        ), order: 1))
                    configs.add(VciConfig(
                        config: OpenId4VciConfiguration(
                            credentialIssuerURL: "https://issuer-backend.eudiw.dev",
                            clientId: clientId,
                            keyAttestationsConfig: attest,
                            authFlowRedirectionURI: redirect,
                            // iOS 0.40.x: cacheIssuerMetadata false — registration
                            // certificates / trust policies may change between runs.
                            requirePAR: true, requireDpop: true, cacheIssuerMetadata: false,
                            validateRegistrationCertificate: this.validateRegistrationCertificate
                        ), order: 0))
                case DEV =>
                    configs.add(VciConfig(
                        config: OpenId4VciConfiguration(
                            credentialIssuerURL: "https://ec.dev.issuer.eudiw.dev",
                            clientId: clientId,
                            keyAttestationsConfig: attest,
                            authFlowRedirectionURI: redirect,
                            // iOS 0.40.x: cacheIssuerMetadata false — registration
                            // certificates / trust policies may change between runs.
                            requirePAR: true, requireDpop: true, cacheIssuerMetadata: false,
                            validateRegistrationCertificate: this.validateRegistrationCertificate
                        ), order: 1))
                    configs.add(VciConfig(
                        config: OpenId4VciConfiguration(
                            credentialIssuerURL: "https://dev.issuer-backend.eudiw.dev",
                            clientId: clientId,
                            keyAttestationsConfig: attest,
                            authFlowRedirectionURI: redirect,
                            // iOS 0.40.x: cacheIssuerMetadata false — registration
                            // certificates / trust policies may change between runs.
                            requirePAR: true, requireDpop: true, cacheIssuerMetadata: false,
                            validateRegistrationCertificate: this.validateRegistrationCertificate
                        ), order: 0))
                case _ =>
                    // PROD variant has no iOS counterpart in this config; mirror DEV.
                    configs.add(VciConfig(
                        config: OpenId4VciConfiguration(
                            credentialIssuerURL: "https://ec.dev.issuer.eudiw.dev",
                            clientId: clientId,
                            keyAttestationsConfig: attest,
                            authFlowRedirectionURI: redirect,
                            // iOS 0.40.x: cacheIssuerMetadata false — registration
                            // certificates / trust policies may change between runs.
                            requirePAR: true, requireDpop: true, cacheIssuerMetadata: false,
                            validateRegistrationCertificate: this.validateRegistrationCertificate
                        ), order: 1))
            }

            // iOS: reduce into [host: VciConfig] keyed by the issuer URL host.
            let dict = HashMap<String, VciConfig>()
            for (c in configs) {
                if (let Some(issuer) <- c.config.credentialIssuerURL) {
                    if (let Some(parsed) <- toCompatibleUrl(issuer)) {
                        if (let Some(host) <- parsed.host) {
                            dict.add(host, c)
                        }
                    }
                }
            }
            return dict
        }
    }

    public prop vpConfig: OpenId4VpConfiguration {
        get() {
            OpenId4VpConfiguration(
                clientIdSchemes: [ClientIdScheme.x509SanDns, ClientIdScheme.x509Hash],
                allowPresentingPartialClaims: true,
                validateRegistrationCertificate: this.validateRegistrationCertificate
            )
        }
    }

    /** Mirrors iOS `validateIssuerRegistrationCertificate` — read from prefs on
     *  every access (default false), so a Settings change is picked up wherever
     *  the config is re-read. */
    public prop validateIssuerRegistrationCertificate: Bool {
        get() { this.prefsController.getBool(PrefsKey.validateIssuerRegistrationCertificate) }
    }

    private prop validateRegistrationCertificate: Bool {
        get() { this.validateIssuerRegistrationCertificate }
    }

    /**
     * iOS `WalletKitConfig.trustConfiguration`: DEMO LoTE URLs + static PID CA
     * fallback. Managers fetch on first `trustAnchorsDer` / validate, not here.
     */
    public prop trustConfiguration: TrustConfiguration {
        get() {
            synchronized(this.loteLock) {
                match (this.cachedTrustConfiguration) {
                    case Some(cfg) => return cfg
                    case None => ()
                }
                let loc = DemoLoteLocations.eudiwDemo()
                // LoTE JWT signature verification is selected by build variant,
                // mirroring iOS (which switches on configLogic.appBuildVariant).
                // DEMO accepts LoTE JWTs without verifying their signature — the
                // same posture as the iOS reference wallet's DEMO build. Any
                // non-DEMO variant verifies for real (see makeProductionLoteVerifier).
                //
                // TODO(prod alignment): appBuildVariant is currently hard-coded to
                // DEMO in app_composition.cj. iOS reads "Build Variant" from the
                // bundle (Info.plist, injected by the build config). To fully match
                // iOS, feed AppBuildVariant.fromRawValue() from a build-config field
                // (e.g. app.json5) instead of hard-coding it; the verifier switch
                // below is already environment-driven and needs no further change.
                let loteVerifier: VerifyJwtSignature = match (this.configLogic.appBuildVariant) {
                    case DEMO => DemoAcceptAllLoteJwtSignature()
                    case _ => this.makeProductionLoteVerifier()
                }
                let etsi = EtsiTrustSource(
                    pidProviders: Some(loc.pidProviders),
                    wrpacProviders: Some(loc.wrpacProviders),
                    wrprcProviders: Some(loc.wrprcProviders),
                    pubEaaProviders: Some(loc.pubEaaProviders),
                    contextTypeMappings: Some(defaultEtsiContextTypeMappings()),
                    customJwtSignatureVerifier: Some(loteVerifier)
                )
                let fallback = StaticListTrustSource.withRootCertificates(this.staticRootDers())
                let cfg = TrustConfiguration(
                    TrustSource.Etsi(etsi),
                    fallbackTrustSource: Some(TrustSource.StaticList(fallback)),
                    defaultPolicy: TrustPolicy.Warning,
                    requireSignedMetadata: true,
                    statusTrustPolicy: TrustPolicy.Warning,
                    // iOS 0.40.x registration-certificate policies: presentation
                    // WARNS, issuance REFUSES (the deliberate asymmetry).
                    wrprcVpTrustPolicy: TrustPolicy.Warning,
                    wrprcVciTrustPolicy: TrustPolicy.Enforce
                )
                this.cachedTrustConfiguration = Some(cfg)
                return cfg
            }
        }
    }

    /*
     * Production LoTE JWT verifier: PKIX-anchor the JWT x5c chain against trusted
     * signer certificates. Today these are the embedded PID Issuer CA anchors
     * (preprod EUDIW PKI); the current DEMO LoTE leaves chain to them
     * (openssl-verified), so an unverifiable list fails closed and the wallet
     * falls back to the static anchors. For a real member-state deployment,
     * replace staticRootDers() with that scheme operator's LoTE signer / CA
     * certificates and swap the DEMO LoTE URLs.
     */
    private func makeProductionLoteVerifier(): VerifyJwtSignature {
        let anchors = ArrayList<Array<Byte>>()
        for (der in this.staticRootDers()) {
            anchors.add(der)
        }
        return StdxCryptoJwtSignature(trustedSignerCertificates: anchors)
    }

    public prop trustedReaderRootCertificates: Array<Array<X5Chain>> {
        get() {
            // Static PID CAs are the eager seed handed to the engine at startup.
            // Live WRPAC anchors are fetched lazily by the engine at presentation
            // time via trustConfiguration.accessTrustManager (see eudi_wallet.cj
            // runLiveTrustPathProbes), so startup must not touch the network here
            // — mirrors iOS, where WalletKitConfig holds no eager trusted-roots.
            return staticRootCertificates()
        }
    }

    public prop trustedIssuerRootCertificates: Array<Array<X5Chain>> {
        get() {
            // Static PID CAs only at startup; LoTE issuer anchors are supplied
            // lazily by the engine via trustConfiguration.issuerTrustManager,
            // so startup never blocks on the network (mirrors iOS lazy trust).
            return staticRootCertificates()
        }
    }

    public prop logFileName: String {
        get() { "eudi-ios-wallet-logs" }
    }

    public prop documentsCategories: DocumentCategories {
        get() {
            let dc = DocumentCategories()
            dc.addEntry(DocumentCategory.government, [
                DocumentTypeIdentifier.mDocPid,
                DocumentTypeIdentifier.sdJwtPid,
                DocumentTypeIdentifier.other("org.iso.18013.5.1.mDL"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.pseudonym.age_over_18.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:pseudonym_age_over_18:1"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.tax.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:tax:1"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.pseudonym.age_over_18.deferred_endpoint"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.cor.1"),
                // Newer EUDI reference-issuer short-form vcts.
                DocumentTypeIdentifier.other("urn:eudi:pid:1"),
                DocumentTypeIdentifier.other("urn:eudi:mdl:1"),
                DocumentTypeIdentifier.other("urn:eudi:tax:1"),
                DocumentTypeIdentifier.other("urn:eudi:cor:1"),
                DocumentTypeIdentifier.other("urn:eudi:pseudonym_age_over_18:1"),
                DocumentTypeIdentifier.other("urn:eudi:age_over_18:1")
            ])
            dc.addEntry(DocumentCategory.travel, [
                DocumentTypeIdentifier.other("org.iso.23220.2.photoid.1"),
                DocumentTypeIdentifier.other("org.iso.23220.photoID.1"),
                DocumentTypeIdentifier.other("org.iso.18013.5.1.reservation"),
                DocumentTypeIdentifier.other("urn:eudi:photoid:1")
            ])
            dc.addEntry(DocumentCategory.finance, [
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.iban.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:iban:1"),
                DocumentTypeIdentifier.other("urn:eudi:iban:1")
            ])
            dc.addEntry(DocumentCategory.education, Array<DocumentTypeIdentifier>())
            dc.addEntry(DocumentCategory.health, [
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.hiid.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:hiid:1"),
                DocumentTypeIdentifier.other("urn:eudi:hiid:1"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.ehic.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:ehic:1"),
                // Newer EUDI reference-issuer short-form vct (issuer.eudiw.dev).
                DocumentTypeIdentifier.other("urn:eudi:ehic:1")
            ])
            dc.addEntry(DocumentCategory.socialSecurity, [
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.pda1.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:pda1:1"),
                DocumentTypeIdentifier.other("urn:eudi:pda1:1")
            ])
            dc.addEntry(DocumentCategory.retail, [
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.loyalty.1"),
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.msisdn.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:msisdn:1"),
                DocumentTypeIdentifier.other("urn:eudi:loyalty:1"),
                DocumentTypeIdentifier.other("urn:eudi:msisdn:1")
            ])
            dc.addEntry(DocumentCategory.other, [
                DocumentTypeIdentifier.other("eu.europa.ec.eudi.por.1"),
                DocumentTypeIdentifier.other("urn:eu.europa.ec.eudi:por:1"),
                DocumentTypeIdentifier.other("urn:eudi:por:1")
            ])
            return dc
        }
    }

    public prop transactionLogger: TransactionLogger {
        get() { this.transactionLoggerImpl }
    }

    public prop revocationIntervalSeconds: Float64 {
        get() { 300.0 }
    }

    public prop documentIssuanceConfig: DocumentIssuanceConfig {
        get() {
            match (this.configLogic.appBuildVariant) {
                case DEMO =>
                    let specific = HashMap<DocumentTypeIdentifier, DocumentIssuanceRule>()
                    specific.add(DocumentTypeIdentifier.mDocPid, DocumentIssuanceRule(policy: CredentialPolicy.oneTimeUse, numberOfCredentials: 10))
                    specific.add(DocumentTypeIdentifier.sdJwtPid, DocumentIssuanceRule(policy: CredentialPolicy.oneTimeUse, numberOfCredentials: 10))
                    return DocumentIssuanceConfig(
                        defaultRule: DocumentIssuanceRule(policy: CredentialPolicy.rotateUse, numberOfCredentials: 1),
                        documentSpecificRules: specific,
                        reIssuanceRule: ReIssuanceRule(minNumberOfCredentials: 2, minExpirationHours: 14, backgroundIntervalSeconds: 300.0)
                    )
                case _ =>
                    // DEV (and PROD-fallback): mirrors iOS WalletKitConfig .DEV (batchSize 60
                    // for both PIDs). Historically lowered to 30 because the dev issuer used
                    // to 500 on 60-proof batches; verified 2026-07-10 that issuer.eudiw.dev
                    // accepts 60 again (iOS live run issued 60/60), so keep parity at 60.
                    let specific = HashMap<DocumentTypeIdentifier, DocumentIssuanceRule>()
                    specific.add(DocumentTypeIdentifier.mDocPid, DocumentIssuanceRule(policy: CredentialPolicy.oneTimeUse, numberOfCredentials: 60))
                    specific.add(DocumentTypeIdentifier.sdJwtPid, DocumentIssuanceRule(policy: CredentialPolicy.oneTimeUse, numberOfCredentials: 60))
                    return DocumentIssuanceConfig(
                        defaultRule: DocumentIssuanceRule(policy: CredentialPolicy.rotateUse, numberOfCredentials: 1),
                        documentSpecificRules: specific,
                        reIssuanceRule: ReIssuanceRule(minNumberOfCredentials: 2, minExpirationHours: 14, backgroundIntervalSeconds: 300.0)
                    )
            }
        }
    }

    /**
     * Mirrors `loadCertificate(_:)`. iOS reads `<name>.der` from the main bundle.
     * Embedded DER lives in certificates_data.cj (same public PID Issuer CA set).
     */
    private func loadCertificate(name: String): ?X5Chain {
        match (trustedReaderCertDer(name)) {
            case Some(der) => Some(X5Chain(name, der))
            case None => None
        }
    }

    private func staticRootCertificates(): Array<Array<X5Chain>> {
        let result = ArrayList<Array<X5Chain>>()
        for (der in this.staticRootDers()) {
            result.add([X5Chain("static-pid-ca", der)])
        }
        return result.toArray()
    }

    private func staticRootDers(): Array<Array<UInt8>> {
        let names = [
            "pidissuerca02_cz", "pidissuerca02_ee", "pidissuerca02_eu",
            "pidissuerca02_lu", "pidissuerca02_nl", "pidissuerca02_pt",
            "pidissuerca02_ut", "r45_staging"
        ]
        let result = ArrayList<Array<UInt8>>()
        for (n in names) {
            if (let Some(cert) <- loadCertificate(n)) {
                result.add(cert.der)
            }
        }
        return result.toArray()
    }

}

// ─────────────────────────────────────────────────────────────────────────────
// Config/WalletProviderAttestationConfig.swift
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors iOS `protocol WalletProviderAttestationConfig: Sendable`. */
public interface WalletProviderAttestationConfig {
    prop walletProviderAttestationUrl: String
}

/** Mirrors iOS `final class WalletProviderAttestationConfigImpl`. */
public class WalletProviderAttestationConfigImpl <: WalletProviderAttestationConfig {
    private let configLogic: ConfigLogic
    public init(configLogic: ConfigLogic) {
        this.configLogic = configLogic
    }
    public prop walletProviderAttestationUrl: String {
        get() {
            match (this.configLogic.appBuildVariant) {
                case DEMO => "https://wallet-provider.eudiw.dev"
                case _ => "https://dev.wallet-provider.eudiw.dev"
            }
        }
    }
}
