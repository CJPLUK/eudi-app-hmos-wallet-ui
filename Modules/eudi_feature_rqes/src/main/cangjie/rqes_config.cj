/*
 * rqes_config.cj — the EudiRQESUiConfig the RQES flow runs against.
 *
 * Mirrors iOS logic-business/Config/RQESConfig.swift 1:1: the QTSP list is keyed
 * on the app build variant (DEV → walletcentric dev signer, DEMO → walletcentric
 * demo signer; only the rsspId differs) and printLogs follows the build type.
 *
 * Structural note (deliberate deviation from iOS): iOS declares this class in
 * logic-business next to ConfigLogic. Here it lives in the RQES feature because
 * eudi_logic_business is a host-runnable module (run_tests.sh HOST_MODULES) and
 * must not pick up the cjrqes_csc dependency, whose PoDoFo FFI only links on
 * device. The inputs (buildVariant/buildType) still come from ConfigLogic, so
 * the variant source and switching semantics match iOS exactly.
 */
package eudi_feature_rqes

import eudi_logic_business.{ConfigLogic, AppBuildVariant, AppBuildType}
import ohos_app_cangjie_eudi_cjrqes_ui.{EudiRQESUi, EudiRQESUiConfig, QTSPData}
import ohos_app_cangjie_eudi_cjrqes_csc.HashAlgorithmOID

public class RqesConfig <: EudiRQESUiConfig {
    private let buildVariant: AppBuildVariant
    private let buildType: AppBuildType

    public init(buildVariant!: AppBuildVariant, buildType!: AppBuildType) {
        this.buildVariant = buildVariant
        this.buildType = buildType
    }

    // iOS RQESConfig.rssps: switch on the build variant; every field except the
    // rsspId is shared between the DEV and DEMO Wallet-Centric signers.
    public prop rssps: Array<QTSPData> {
        get() {
            // iOS RQESConfig only has .DEV / .DEMO. HMOS additionally has PROD
            // (declared outside the enum on iOS, via the build scheme); with no
            // iOS-side PROD QTSP to mirror, PROD reuses the non-dev DEMO signer
            // rather than inventing a third endpoint.
            let rsspId = match (this.buildVariant) {
                case DEV => "https://walletcentric.signer.dev.eudiw.dev/csc/v2"
                case DEMO | PROD => "https://walletcentric.signer.eudiw.dev/csc/v2"
            }
            [
                QTSPData(
                    name: "Wallet-Centric",
                    rsspId: rsspId,
                    tsaUrl: Some("https://timestamp.sectigo.com/qualified"),
                    clientId: "wallet-client",
                    clientSecret: "somesecret2",
                    authFlowRedirectionURI: "rqes://oauth/callback",
                    hashAlgorithm: HashAlgorithmOID.SHA256,
                    includeRevocationInfo: false
                )
            ]
        }
    }

    // iOS: printLogs = (buildType == .DEBUG).
    public prop printLogs: Bool {
        get() { this.buildType == AppBuildType.DEBUG }
    }
}

/**
 * Lazy singleton registration — iOS DocumentSignInteractor:
 * `do { try .instance() } catch { .init(config: configLogic.rqesConfig) }`.
 * The first signing initiation registers the shared EudiRQESUi with a config
 * built from the app's build variant/type; later calls reuse the instance.
 */
public func ensureRqesUi(configLogic: ConfigLogic): Unit {
    try {
        let _ = EudiRQESUi.instance()
    } catch (_: Exception) {
        EudiRQESUi(RqesConfig(
            buildVariant: configLogic.appBuildVariant,
            buildType: configLogic.appBuildType
        ))
    }
}
