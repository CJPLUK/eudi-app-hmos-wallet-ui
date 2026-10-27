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
 * Port of iOS logic-authentication/Sources/Storage/KeychainPinStorageProvider.swift.
 *
 * The PIN is never stored; only a salted PBKDF2-HMAC-SHA256 derivation is kept,
 * exactly as the iOS source does via CCKeyDerivationPBKDF(kCCPBKDF2,
 * kCCPRFHmacAlgSHA256). The same parameters are preserved:
 *   - salt size            : 32 bytes
 *   - iterations           : 210_000
 *   - derived key length   : 32 bytes
 *
 * Real secure storage: the derived material is persisted through
 * eudi_logic_business.KeyChainController — the delivered file-backed secure key/value
 * store the wallet uses on HarmonyOS (the same controller iOS resolves from its
 * Keychain registration). That controller exposes only string values, so the
 * binary salt/hash are hex-encoded before storage and decoded on read (a transport
 * encoding detail; the cryptographic semantics match iOS byte-for-byte).
 *
 * SecureRandom (openssl-backed CSPRNG) replaces SecRandomCopyBytes; PBKDF2 is
 * built on stdx.crypto.digest.HMAC(HashType.SHA256) following RFC 2898 — there is
 * no ready-made PBKDF2 in the Cangjie stdlib, so it is reimplemented faithfully
 * as the real RFC 2898 construction.
 */
package eudi_logic_authentication

import std.convert.*
import stdx.crypto.digest.*
import stdx.crypto.crypto.SecureRandom
import eudi_logic_business.KeyChainController
import eudi_logic_business.KeyChainWrapper

/** Mirrors iOS `KeychainPinStorageProvider`'s nested `KeyIdentifier: KeyChainWrapper`. */
class PinStorageKeyIdentifier <: KeyChainWrapper {
    static let devicePinSalt = PinStorageKeyIdentifier("devicePinSalt")
    static let devicePinHash = PinStorageKeyIdentifier("devicePinHash")
    static let devicePinIterations = PinStorageKeyIdentifier("devicePinIterations")

    private let raw: String
    init(raw: String) { this.raw = raw }
    public prop value: String { get() { this.raw } }
}

/** Mirrors iOS `KeychainPinStorageProvider`. */
public class KeychainPinStorageProvider <: PinStorageProvider {
    // Mirrors iOS `enum Constants`.
    private static let saltSize: Int64 = 32
    private static let defaultIterations: Int64 = 210_000
    private static let derivedKeyLength: Int64 = 32

    private let keyChainController: KeyChainController

    public init(keyChainController: KeyChainController) {
        this.keyChainController = keyChainController
    }

    public func hasPin(): Bool {
        let salt = decodeData(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinSalt))
        let hash = decodeData(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinHash))
        let iterations = parseInt(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinIterations))

        match ((salt, hash, iterations)) {
            case (Some(s), Some(h), Some(it)) => return !s.isEmpty() && !h.isEmpty() && it > 0
            case _ => return false
        }
    }

    public func setPin(pin: String): Unit {
        if (pin.isEmpty()) {
            return
        }

        let salt = randomSalt(KeychainPinStorageProvider.saltSize)

        let hash = derivePinHash(
            pin,
            salt,
            KeychainPinStorageProvider.defaultIterations,
            KeychainPinStorageProvider.derivedKeyLength
        )

        this.keyChainController.storeValue(PinStorageKeyIdentifier.devicePinSalt, encodeData(salt))
        this.keyChainController.storeValue(PinStorageKeyIdentifier.devicePinHash, encodeData(hash))
        this.keyChainController.storeValue(
            PinStorageKeyIdentifier.devicePinIterations,
            "${KeychainPinStorageProvider.defaultIterations}"
        )
    }

    public func clearPin(): Unit {
        this.keyChainController.removeObject(PinStorageKeyIdentifier.devicePinSalt)
        this.keyChainController.removeObject(PinStorageKeyIdentifier.devicePinHash)
        this.keyChainController.removeObject(PinStorageKeyIdentifier.devicePinIterations)
    }

    public func isPinValid(pin: String): Bool {
        if (pin.isEmpty()) {
            return false
        }

        let saltOpt = decodeData(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinSalt))
        let expectedHashOpt = decodeData(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinHash))
        let iterationsOpt = parseInt(this.keyChainController.getValue(PinStorageKeyIdentifier.devicePinIterations))

        let salt: Array<UInt8>
        let expectedHash: Array<UInt8>
        let iterations: Int64
        match ((saltOpt, expectedHashOpt, iterationsOpt)) {
            case (Some(s), Some(h), Some(it)) where it > 0 =>
                salt = s
                expectedHash = h
                iterations = it
            case _ => return false
        }

        let candidateHash = derivePinHash(pin, salt, iterations, expectedHash.size)

        return constantTimeEquals(expectedHash, candidateHash)
    }

    // ── crypto primitives (mirror the iOS private extension) ──────────────────

    private func randomSalt(length: Int64): Array<UInt8> {
        let random = SecureRandom()
        return random.nextBytes(Int32(length))
    }

    private func derivePinHash(
        pin: String,
        salt: Array<UInt8>,
        iterations: Int64,
        outputLength: Int64
    ): Array<UInt8> {
        let passwordData = pin.toArray()
        return pbkdf2SHA256(passwordData, salt, iterations, outputLength)
    }

    private func constantTimeEquals(lhs: Array<UInt8>, rhs: Array<UInt8>): Bool {
        if (lhs.size != rhs.size) {
            return false
        }
        var diff: UInt8 = 0
        var i: Int64 = 0
        while (i < lhs.size) {
            diff |= (lhs[i] ^ rhs[i])
            i++
        }
        return diff == 0
    }

    /**
     * PBKDF2-HMAC-SHA256 (RFC 2898). Reproduces CCKeyDerivationPBKDF with
     * kCCPRFHmacAlgSHA256: DK = T_1 || T_2 || ... truncated to outputLength,
     * where T_i = F(password, salt, c, i) and
     * F = U_1 xor U_2 xor ... xor U_c, U_1 = PRF(password, salt || INT_32_BE(i)).
     */
    private func pbkdf2SHA256(
        password: Array<UInt8>,
        salt: Array<UInt8>,
        rounds: Int64,
        outputLength: Int64
    ): Array<UInt8> {
        let hLen: Int64 = 32 // SHA-256 output length
        let derived = Array<UInt8>(outputLength, repeat: 0)

        let blocks = (outputLength + hLen - 1) / hLen
        var written: Int64 = 0

        var blockIndex: Int64 = 1
        while (blockIndex <= blocks) {
            let t = deriveBlock(password, salt, rounds, blockIndex, hLen)
            var j: Int64 = 0
            while (j < hLen && written < outputLength) {
                derived[written] = t[j]
                written++
                j++
            }
            blockIndex++
        }
        return derived
    }

    private func deriveBlock(
        password: Array<UInt8>,
        salt: Array<UInt8>,
        rounds: Int64,
        blockIndex: Int64,
        hLen: Int64
    ): Array<UInt8> {
        // U_1 = PRF(password, salt || INT_32_BE(blockIndex))
        let saltWithIndex = Array<UInt8>(salt.size + 4, repeat: 0)
        var k: Int64 = 0
        while (k < salt.size) {
            saltWithIndex[k] = salt[k]
            k++
        }
        saltWithIndex[salt.size] = UInt8((blockIndex >> 24) & 0xFF)
        saltWithIndex[salt.size + 1] = UInt8((blockIndex >> 16) & 0xFF)
        saltWithIndex[salt.size + 2] = UInt8((blockIndex >> 8) & 0xFF)
        saltWithIndex[salt.size + 3] = UInt8(blockIndex & 0xFF)

        var u = hmacSha256(password, saltWithIndex)
        let result = Array<UInt8>(hLen, repeat: 0)
        var c: Int64 = 0
        while (c < hLen) {
            result[c] = u[c]
            c++
        }

        var iter: Int64 = 1
        while (iter < rounds) {
            u = hmacSha256(password, u)
            var idx: Int64 = 0
            while (idx < hLen) {
                result[idx] = result[idx] ^ u[idx]
                idx++
            }
            iter++
        }
        return result
    }

    private func hmacSha256(key: Array<UInt8>, message: Array<UInt8>): Array<UInt8> {
        let hmac = HMAC(key, HashType.SHA256)
        hmac.write(message)
        return hmac.finish()
    }

    // ── transport encoding (string-only KeyChainController) ───────────────────

    private func encodeData(bytes: Array<UInt8>): String {
        let sb = StringBuilder()
        for (b in bytes) {
            let hi = Int64(b) / 16
            let lo = Int64(b) % 16
            sb.append(hexDigit(hi))
            sb.append(hexDigit(lo))
        }
        return sb.toString()
    }

    private func hexDigit(v: Int64): Rune {
        if (v < 10) {
            return Rune(UInt32(48 + v)) // '0'..'9'
        }
        return Rune(UInt32(97 + (v - 10))) // 'a'..'f'
    }

    private func decodeData(value: ?String): ?Array<UInt8> {
        match (value) {
            case None => return None
            case Some(s) =>
                let runes = s.toRuneArray()
                if (runes.size % 2 != 0) {
                    return None
                }
                let out = Array<UInt8>(runes.size / 2, repeat: 0)
                var i: Int64 = 0
                while (i < runes.size) {
                    let hi = hexValue(runes[i])
                    let lo = hexValue(runes[i + 1])
                    match ((hi, lo)) {
                        case (Some(h), Some(l)) => out[i / 2] = UInt8(h * 16 + l)
                        case _ => return None
                    }
                    i += 2
                }
                return out
        }
    }

    private func hexValue(c: Rune): ?Int64 {
        let code = UInt32(c)
        if (code >= 48 && code <= 57) { return Int64(code - 48) }       // '0'..'9'
        if (code >= 97 && code <= 102) { return Int64(code - 97 + 10) } // 'a'..'f'
        if (code >= 65 && code <= 70) { return Int64(code - 65 + 10) }  // 'A'..'F'
        return None
    }

    private func parseInt(value: ?String): ?Int64 {
        match (value) {
            case None => return None
            case Some(s) => return Int64.tryParse(s)
        }
    }
}
