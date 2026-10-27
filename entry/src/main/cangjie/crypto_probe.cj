/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 */

package ohos_app_cangjie_entry

import eudi_lib_core_crypto.*

/*
 * iOS 对齐 KAT(Known-Answer Test)套件 — 16 用例。
 * iOS 侧(CryptoKit/JOSESwift)的行为全部锚定 RFC/NIST 标准,因此逐字节命中标准向量
 * 即等价于与 iOS 对齐:SHA-2=FIPS 180-2, HMAC=RFC 4231, HKDF=RFC 5869,
 * AES-GCM=NIST GCM spec, Base64Url=RFC 4648 §5(无填充), ECDSA raw r||s 64B=
 * CryptoKit P256 rawRepresentation, JWS compact=RFC 7515。
 */

// FIPS 180-2: SHA-256("abc")
let V_SHA256_ABC: Array<UInt8> = [
    0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
    0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
]
// SHA-256("")
let V_SHA256_EMPTY: Array<UInt8> = [
    0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
    0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55
]
// FIPS 180-2: SHA-384("abc")
let V_SHA384_ABC: Array<UInt8> = [
    0xcb, 0x00, 0x75, 0x3f, 0x45, 0xa3, 0x5e, 0x8b, 0xb5, 0xa0, 0x3d, 0x69, 0x9a, 0xc6, 0x50, 0x07,
    0x27, 0x2c, 0x32, 0xab, 0x0e, 0xde, 0xd1, 0x63, 0x1a, 0x8b, 0x60, 0x5a, 0x43, 0xff, 0x5b, 0xed,
    0x80, 0x86, 0x07, 0x2b, 0xa1, 0xe7, 0xcc, 0x23, 0x58, 0xba, 0xec, 0xa1, 0x34, 0xc8, 0x25, 0xa7
]
// FIPS 180-2: SHA-512("abc")
let V_SHA512_ABC: Array<UInt8> = [
    0xdd, 0xaf, 0x35, 0xa1, 0x93, 0x61, 0x7a, 0xba, 0xcc, 0x41, 0x73, 0x49, 0xae, 0x20, 0x41, 0x31,
    0x12, 0xe6, 0xfa, 0x4e, 0x89, 0xa9, 0x7e, 0xa2, 0x0a, 0x9e, 0xee, 0xe6, 0x4b, 0x55, 0xd3, 0x9a,
    0x21, 0x92, 0x99, 0x2a, 0x27, 0x4f, 0xc1, 0xa8, 0x36, 0xba, 0x3c, 0x23, 0xa3, 0xfe, 0xeb, 0xbd,
    0x45, 0x4d, 0x44, 0x23, 0x64, 0x3c, 0xe8, 0x0e, 0x2a, 0x9a, 0xc9, 0x4f, 0xa5, 0x4c, 0xa4, 0x9f
]
// RFC 4231 Test Case 1: HMAC-SHA256(key=0x0b*20, "Hi There")
let V_HMAC_TC1: Array<UInt8> = [
    0xb0, 0x34, 0x4c, 0x61, 0xd8, 0xdb, 0x38, 0x53, 0x5c, 0xa8, 0xaf, 0xce, 0xaf, 0x0b, 0xf1, 0x2b,
    0x88, 0x1d, 0xc2, 0x00, 0xc9, 0x83, 0x3d, 0xa7, 0x26, 0xe9, 0x37, 0x6c, 0x2e, 0x32, 0xcf, 0xf7
]
// RFC 5869 Test Case 1: HKDF-SHA256 OKM(42B)
let V_HKDF_TC1: Array<UInt8> = [
    0x3c, 0xb2, 0x5f, 0x25, 0xfa, 0xac, 0xd5, 0x7a, 0x90, 0x43, 0x4f, 0x64, 0xd0, 0x36, 0x2f, 0x2a,
    0x2d, 0x2d, 0x0a, 0x90, 0xcf, 0x1a, 0x5a, 0x4c, 0x5d, 0xb0, 0x2d, 0x56, 0xec, 0xc4, 0xc5, 0xbf,
    0x34, 0x00, 0x72, 0x08, 0xd5, 0xb8, 0x87, 0x18, 0x58, 0x65
]
// NIST GCM spec Case 14: AES-256-GCM(key=0*32, iv=0*12, P=0*16, AAD 空) → C || T
let V_GCM14_CT: Array<UInt8> = [
    0xce, 0xa7, 0x40, 0x3d, 0x4d, 0x60, 0x6b, 0x6e, 0x07, 0x4e, 0xc5, 0xd3, 0xba, 0xf3, 0x9d, 0x18,
    0xd0, 0xd1, 0xc8, 0xa7, 0x99, 0x99, 0x6b, 0xf0, 0x26, 0x5b, 0x98, 0xb5, 0xd4, 0x8a, 0xb9, 0x19
]

func katEq(a: Array<UInt8>, b: Array<UInt8>): Bool {
    if (a.size != b.size) {
        return false
    }
    var i = 0
    while (i < a.size) {
        if (a[i] != b[i]) {
            return false
        }
        i++
    }
    return true
}

func runCase(name: String, body: () -> Bool): (Int64, String) {
    try {
        if (body()) {
            return (1, "${name}:ok ")
        }
        return (0, "${name}:BAD ")
    } catch (e: Exception) {
        return (0, "${name}:ERR(${e.message}) ")
    }
}

public func entry_crypto_kat(): String {
    var passed: Int64 = 0
    var total: Int64 = 0
    var report = ""
    let abc: Array<UInt8> = [0x61, 0x62, 0x63]

    let cases: Array<(String, () -> Bool)> = [
        // —— 摘要族(FIPS 180-2,iOS CryptoKit SHA256/384/512 同源)——
        ("sha256-abc", { => katEq(Digest.sha256(abc), V_SHA256_ABC) }),
        ("sha256-empty", { => katEq(Digest.sha256(Array<UInt8>()), V_SHA256_EMPTY) }),
        ("sha384-abc", { => katEq(Digest.sha384(abc), V_SHA384_ABC) }),
        ("sha512-abc", { => katEq(Digest.sha512(abc), V_SHA512_ABC) }),
        // —— HMAC(RFC 4231 TC1,iOS CryptoKit HMAC<SHA256> 同源)——
        ("hmac-rfc4231", { =>
            let key = Array<UInt8>(20, repeat: 0x0b)
            katEq(Hmac.sha256(key, "Hi There".toArray()), V_HMAC_TC1)
        }),
        // —— HKDF(RFC 5869 TC1 全 42B OKM,iOS CryptoKit HKDF 同源)——
        ("hkdf-rfc5869", { =>
            let ikm = Array<UInt8>(22, repeat: 0x0b)
            var salt = Array<UInt8>(13, repeat: 0)
            var i: Int64 = 0
            while (i < 13) {
                salt[i] = UInt8(i)
                i++
            }
            var info = Array<UInt8>(10, repeat: 0)
            i = 0
            while (i < 10) {
                info[i] = UInt8(0xf0 + i)
                i++
            }
            katEq(Hkdf.derive(salt, ikm, info, 42), V_HKDF_TC1)
        }),
        // —— AES-256-GCM(NIST Case 14 逐字节,iOS CryptoKit AES.GCM 同源)——
        ("gcm-nist14", { =>
            let k = Array<UInt8>(32, repeat: 0)
            let iv = Array<UInt8>(12, repeat: 0)
            let p = Array<UInt8>(16, repeat: 0)
            katEq(AesGcm.seal(k, iv, Array<UInt8>(), p), V_GCM14_CT)
        }),
        ("gcm-tamper-reject", { =>
            let k = Array<UInt8>(32, repeat: 0x42)
            let iv = Array<UInt8>(12, repeat: 0x24)
            let aad: Array<UInt8> = [0x01]
            var ct = AesGcm.seal(k, iv, aad, abc)
            ct[0] = ct[0] ^ 0xff   // 篡改密文首字节
            match (AesGcm.open(k, iv, aad, ct)) {
                case Some(_) => false   // 篡改后仍解出 = 失败
                case None => true       // 正确拒收
            }
        }),
        // —— Base64Url(RFC 4648 §5: URL-safe 字符、无填充;JWS 编码基础)——
        ("b64url-urlsafe", { =>
            // 0xfb,0xff → 标准 b64 "+/8=",URL-safe 无填充应为 "-_8"
            Base64Url.encode([0xfb, 0xff]) == "-_8"
        }),
        ("b64url-roundtrip", { =>
            katEq(Base64Url.decode(Base64Url.encode(V_SHA512_ABC)), V_SHA512_ABC)
        }),
        // —— ECDSA P-256(raw r||s 64B = iOS CryptoKit rawRepresentation)——
        ("ecdsa-roundtrip", { =>
            let priv = EcdsaP256.generate()
            let pub = EcdsaP256.publicKeyOf(priv)
            let sig = EcdsaP256.sign(priv, abc)
            sig.size == 64 && EcdsaP256.verify(pub, abc, sig)
        }),
        ("ecdsa-tamper-reject", { =>
            let priv = EcdsaP256.generate()
            let pub = EcdsaP256.publicKeyOf(priv)
            let sig = EcdsaP256.sign(priv, abc)
            let other: Array<UInt8> = [0x61, 0x62, 0x64]   // "abd"
            !EcdsaP256.verify(pub, other, sig)
        }),
        ("ecdsa-der-raw", { =>
            let priv = EcdsaP256.generate()
            let raw = EcdsaP256.sign(priv, abc)
            katEq(EcdsaP256.derToRaw(EcdsaP256.rawToDer(raw)), raw)
        }),
        // —— JWS ES256(RFC 7515 compact,iOS JOSESwift 同源)——
        ("jws-roundtrip", { =>
            let priv = EcdsaP256.generate()
            let pub = EcdsaP256.publicKeyOf(priv)
            let compact = Jws.signEs256("{\"alg\":\"ES256\"}", abc, priv)
            Jws.verifyEs256(compact, pub)
        }),
        ("jws-wrongkey-reject", { =>
            let priv = EcdsaP256.generate()
            let otherPub = EcdsaP256.publicKeyOf(EcdsaP256.generate())
            let compact = Jws.signEs256("{\"alg\":\"ES256\"}", abc, priv)
            !Jws.verifyEs256(compact, otherPub)
        }),
        // —— Rng ——
        ("rng", { =>
            let a = Rng.bytes(32)
            let b = Rng.bytes(32)
            a.size == 32 && b.size == 32 && !katEq(a, b)
        })
    ]

    for ((name, body) in cases) {
        total++
        let (p, r) = runCase(name, body)
        passed += p
        report += r
    }
    "${passed}/${total} | ${report}"
}


