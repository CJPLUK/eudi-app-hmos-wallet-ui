/*
 * Wallet-side DEMO LoTE support for the gitcode eudi_cjetsi_1196x2 API.
 *
 * Holds the DEMO LoTE download locations, a PEM encoder for the resolved trust
 * anchors, and the JWT-signature verifier the wallet injects into the etsi
 * trust source. The DEMO build accepts LoTE JWTs WITHOUT verifying their
 * signature (DemoAcceptAllLoteJwtSignature), mirroring the EUDI iOS reference
 * wallet's DEMO build; production verifies for real (see config.cj,
 * makeProductionLoteVerifier). The real trust wiring lives in config.cj's
 * `trustConfiguration`.
 */
package eudi_logic_core

import stdx.encoding.base64.*
import ohos_app_cangjie_eudi_cjetsi_1196x2.lote_consultation.*

public class DemoLoteLocations {
    public let pidProviders: String
    public let wrpacProviders: String
    public let wrprcProviders: String
    public let pubEaaProviders: String

    public init(pidProviders: String, wrpacProviders: String, wrprcProviders: String, pubEaaProviders: String) {
        this.pidProviders = pidProviders
        this.wrpacProviders = wrpacProviders
        this.wrprcProviders = wrprcProviders
        this.pubEaaProviders = pubEaaProviders
    }

    public static func eudiwDemo(): DemoLoteLocations {
        return DemoLoteLocations(
            "https://trustedlist.serviceproviders.eudiw.dev/LOTE/json/PIDProviders.jwt",
            "https://trustedlist.serviceproviders.eudiw.dev/LOTE/json/WRPACProviders.jwt",
            "https://trustedlist.serviceproviders.eudiw.dev/LOTE/json/WRPRCProviders.jwt",
            "https://trustedlist.serviceproviders.eudiw.dev/LOTE/json/PubEAAProviders.jwt"
        )
    }
}

public class LoteParser {
    public static func pemEncodeCertificates(ders: Array<Array<UInt8>>): String {
        var pem = ""
        for (der in ders) {
            if (der.size == 0) {
                continue
            }
            pem = pem + "-----BEGIN CERTIFICATE-----\n"
            pem = pem + wrap64(toBase64String(der))
            pem = pem + "-----END CERTIFICATE-----\n"
        }
        return pem
    }
}

func wrap64(b64: String): String {
    let bytes = b64.toArray()
    var out = ""
    var i: Int64 = 0
    while (i < bytes.size) {
        let end = if (i + 64 < bytes.size) { i + 64 } else { bytes.size }
        out = out + String.fromUtf8(bytes[i..end]) + "\n"
        i = end
    }
    return out
}

/*
 * INSECURE — accepts any LoTE JWT WITHOUT verifying its JWS signature.
 * DEMO builds only. This mirrors the EUDI iOS reference wallet, whose DEMO
 * build injects an accept-all verifier (KMP InsecureAcceptAllJwtSignature)
 * because it runs against the preprod EUDIW infrastructure.
 *
 * A production wallet MUST replace this with a real verifier — config.cj's
 * makeProductionLoteVerifier() does exactly that, PKIX-anchoring the JWT x5c
 * chain against the embedded PID Issuer CA anchors so LoadLoTEAndPointers
 * fails closed on an unverifiable list.
 */
public class DemoAcceptAllLoteJwtSignature <: VerifyJwtSignature {
    public func invoke(jwt: String): VerifyJwtSignatureOutcome {
        return VerifyJwtSignatureOutcome.Verified(jwt)
    }
}
