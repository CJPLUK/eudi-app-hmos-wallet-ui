/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Narrow PIN-storage seam of the EUDI
 * HarmonyOS wallet feature-common module.
 *
 * iOS counterpart: logic-authentication PinStorageController.swift +
 * KeychainPinStorageProvider.swift. logic-authentication is not delivered
 * yet, so per the module architecture (target_architecture.json
 * platform_mapping) this module owns the narrow `PinStore` interface plus an
 * emulator-safe `FilePinStore` default implementation:
 *
 *  - setPin: 32-byte random salt + PBKDF2-HMAC-SHA256-derived hash persisted
 *    via std.fs — the PIN itself is never stored and never compared as plain
 *    text (old-project rework lesson: no `pin == literal` anywhere).
 *  - isPinValid: re-derives the candidate hash with the stored salt and
 *    iteration count and compares constant-time.
 *  - I/O failure degrades to an in-memory map (PrefsControllerImpl paradigm
 *    in eudi_logic_business) — calls keep working, nothing crashes.
 *
 * PBKDF2/HMAC/SHA-256 are the pure-Cangjie implementations QA'd in the old
 * single-module project (platform/auth/pin_storage.cj): emulator has no
 * secure hardware and HUKS / crypto_framework native bindings crash at
 * startup, so no FFI crypto is imported. Iterations = 10000 (the old
 * project's 210000 took >8s of synchronous UI-thread work in the emulator
 * and tripped the APP_INPUT_BLOCK watchdog).
 */
package eudi_feature_common

import std.collection.HashMap
import std.convert.*
import std.fs.*
import std.random.Random
import eudi_logic_authentication.KeychainPinStorageProvider
import eudi_logic_business.KeyChainController

/**
 * Narrow PIN storage contract (frozen interface of fc_common_quickpin).
 * The composition root swaps in the logic-authentication implementation
 * once that module is delivered.
 */
public interface PinStore {
    /** Persists a new PIN (hashed; empty PIN ignored like iOS `guard`). */
    func setPin(pin: String): Unit
    /** True when `pin` matches the stored PIN (constant-time hash compare). */
    func isPinValid(pin: String): Bool
    /** True when a PIN has been set (salt + hash + iterations all present). */
    func hasPin(): Bool
    /**
     * Clears any stored PIN credentials (salt / hash / iterations).
     * Mirrors iOS `keyChainController.clear()` in StartupInteractor
     * `manageStorageForFirstRun` — called on first launch to remove stale
     * credentials left by a previous install.
     */
    func clearPin(): Unit
}

/**
 * std.fs-backed `PinStore` default implementation. Salt/hash are hex-encoded
 * into a flat key=value file under the app sandbox files directory; any I/O
 * failure flips the store into memory-only mode (degraded but functional).
 */
public class FilePinStore <: PinStore {
    private static let KEY_SALT: String = "devicePinSalt"
    private static let KEY_HASH: String = "devicePinHash"
    private static let KEY_ITERATIONS: String = "devicePinIterations"

    private static let SALT_SIZE: Int64 = 32
    private static let DERIVED_KEY_LENGTH: Int64 = 32
    private static let DEFAULT_ITERATIONS: Int64 = 10000

    /** Same sandbox files dir default as eudi_logic_business PrefsControllerImpl. */
    public static let DEFAULT_STORAGE_DIR = "/data/storage/el2/base/haps/entry/files"

    private let values = HashMap<String, String>()
    private let filePath: String
    private var diskAvailable: Bool

    public init(storageDir!: String = DEFAULT_STORAGE_DIR) {
        this.filePath = "${storageDir}/eudi_pin_store.txt"
        this.diskAvailable = true
        ensureDirectory(storageDir)
        loadFromDisk()
    }

    public func setPin(pin: String): Unit {
        if (pin.isEmpty()) {
            return
        }
        let salt = randomSalt(FilePinStore.SALT_SIZE)
        let hash = Pbkdf2HmacSha256.derive(
            pin.toArray(), salt, FilePinStore.DEFAULT_ITERATIONS, FilePinStore.DERIVED_KEY_LENGTH
        )
        this.values[FilePinStore.KEY_SALT] = hexEncode(salt)
        this.values[FilePinStore.KEY_HASH] = hexEncode(hash)
        this.values[FilePinStore.KEY_ITERATIONS] = "${FilePinStore.DEFAULT_ITERATIONS}"
        persist()
    }

    public func isPinValid(pin: String): Bool {
        if (pin.isEmpty()) {
            return false
        }
        let iterations = readIterations()
        if (iterations <= 0) {
            return false
        }
        let saltOpt = decodeStored(FilePinStore.KEY_SALT)
        let hashOpt = decodeStored(FilePinStore.KEY_HASH)
        match ((saltOpt, hashOpt)) {
            case (Some(salt), Some(expected)) =>
                if (salt.isEmpty() || expected.isEmpty()) {
                    return false
                }
                let candidate = Pbkdf2HmacSha256.derive(pin.toArray(), salt, iterations, expected.size)
                return constantTimeEquals(expected, candidate)
            case _ => return false
        }
    }

    public func hasPin(): Bool {
        let saltOpt = decodeStored(FilePinStore.KEY_SALT)
        let hashOpt = decodeStored(FilePinStore.KEY_HASH)
        match ((saltOpt, hashOpt)) {
            case (Some(salt), Some(hash)) =>
                return !salt.isEmpty() && !hash.isEmpty() && readIterations() > 0
            case _ => return false
        }
    }

    /**
     * Removes all stored PIN entries (salt, hash, iterations) and deletes the
     * backing file, mirroring iOS `KeychainController.clear()` semantics for
     * the PIN portion. Leaves the store in memory-only degraded mode if the
     * file deletion fails, but still clears the in-memory map so `hasPin()`
     * returns false immediately.
     */
    public func clearPin(): Unit {
        this.values.remove(FilePinStore.KEY_SALT)
        this.values.remove(FilePinStore.KEY_HASH)
        this.values.remove(FilePinStore.KEY_ITERATIONS)
        if (this.diskAvailable) {
            try {
                // std.fs.removeIfExists: delete file only if present (no error if absent).
                removeIfExists(this.filePath, recursive: false)
            } catch (_: Exception) {
                this.diskAvailable = false
            }
        }
    }

    // ── internal: storage ───────────────────────────────────────────────

    private func readIterations(): Int64 {
        match (this.values.get(FilePinStore.KEY_ITERATIONS)) {
            case Some(raw) => return Int64.tryParse(raw) ?? 0
            case None => return 0
        }
    }

    private func decodeStored(key: String): Option<Array<Byte>> {
        match (this.values.get(key)) {
            case Some(hex) => return Some(hexDecode(hex))
            case None => return None
        }
    }

    private func ensureDirectory(storageDir: String): Unit {
        try {
            if (!exists(storageDir)) {
                Directory.create(storageDir, recursive: true)
            }
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    private func loadFromDisk(): Unit {
        if (!this.diskAvailable) {
            return
        }
        try {
            if (!exists(this.filePath)) {
                return
            }
            let raw = String.fromUtf8(File.readFrom(this.filePath))
            for (line in raw.split("\n")) {
                match (line.indexOf("=")) {
                    case Some(idx) =>
                        let key = line[0..idx]
                        let value = line[(idx + 1)..line.size]
                        if (!key.isEmpty()) {
                            this.values[key] = value
                        }
                    case None => ()
                }
            }
        } catch (_: Exception) {
            // Unreadable store: degrade to memory-only but keep serving calls.
            this.diskAvailable = false
        }
    }

    private func persist(): Unit {
        if (!this.diskAvailable) {
            return
        }
        try {
            let sb = StringBuilder()
            for ((key, value) in this.values) {
                sb.append(key)
                sb.append("=")
                sb.append(value)
                sb.append("\n")
            }
            File.writeTo(this.filePath, sb.toString().toArray())
        } catch (_: Exception) {
            this.diskAvailable = false
        }
    }

    // ── internal: crypto helpers ────────────────────────────────────────

    private func randomSalt(length: Int64): Array<Byte> {
        let rng = Random()
        let buf = Array<Byte>(length, repeat: 0)
        rng.nextBytes(buf)
        return buf
    }

    /** Constant-time compare: accumulate XOR over all bytes, no short-circuit. */
    private func constantTimeEquals(lhs: Array<Byte>, rhs: Array<Byte>): Bool {
        if (lhs.size != rhs.size) {
            return false
        }
        var diff: Byte = 0
        for (i in 0..lhs.size) {
            diff |= (lhs[i] ^ rhs[i])
        }
        return diff == 0
    }

    private func hexEncode(bytes: Array<Byte>): String {
        let table = "0123456789abcdef".toArray()
        let out = Array<Byte>(bytes.size * 2, repeat: 0)
        for (i in 0..bytes.size) {
            out[i * 2] = table[Int64((bytes[i] >> 4) & 0x0F)]
            out[i * 2 + 1] = table[Int64(bytes[i] & 0x0F)]
        }
        return String.fromUtf8(out)
    }

    private func hexDecode(s: String): Array<Byte> {
        let src = s.toArray()
        let n = src.size / 2
        let out = Array<Byte>(n, repeat: 0)
        for (i in 0..n) {
            let hi = hexNibble(src[i * 2])
            let lo = hexNibble(src[i * 2 + 1])
            out[i] = UInt8(((hi << 4) | lo) & 0xFF)
        }
        return out
    }

    private func hexNibble(c: Byte): Int64 {
        if (c >= b'0' && c <= b'9') {
            return Int64(c - b'0')
        }
        if (c >= b'a' && c <= b'f') {
            return Int64(c - b'a') + 10
        }
        if (c >= b'A' && c <= b'F') {
            return Int64(c - b'A') + 10
        }
        return 0
    }
}

/** Factory mirroring the Swinject registration (composition-root seam). */
public func createPinStore(): PinStore {
    return FilePinStore()
}

/**
 * Production PinStore: iOS KeychainPinStorageProvider over a HUKS-wrapped
 * KeyChainController. PBKDF2 iterations stay at 210_000 (iOS gold vector).
 * FilePinStore (10000 rounds, plaintext file) remains the host-test default.
 */
public class KeychainPinStore <: PinStore {
    private let provider: KeychainPinStorageProvider

    public init(keyChainController: KeyChainController) {
        this.provider = KeychainPinStorageProvider(keyChainController)
    }

    public func setPin(pin: String): Unit {
        this.provider.setPin(pin)
    }

    public func isPinValid(pin: String): Bool {
        this.provider.isPinValid(pin)
    }

    public func hasPin(): Bool {
        this.provider.hasPin()
    }

    public func clearPin(): Unit {
        this.provider.clearPin()
    }
}

/**
 * PBKDF2-HMAC-SHA256 (RFC 8018), pure Cangjie. Equivalent to the iOS
 * CommonCrypto `CCKeyDerivationPBKDF(kCCPBKDF2, ..., kCCPRFHmacAlgSHA256)`.
 */
class Pbkdf2HmacSha256 {
    static func derive(password: Array<Byte>, salt: Array<Byte>, iterations: Int64, outputLength: Int64): Array<Byte> {
        let hLen: Int64 = 32
        let blockCount = (outputLength + hLen - 1) / hLen
        let derived = Array<Byte>(outputLength, repeat: 0)
        var offset: Int64 = 0
        var blockIndex: Int64 = 1
        while (blockIndex <= blockCount) {
            let block = deriveBlock(password, salt, iterations, blockIndex)
            var j: Int64 = 0
            while (j < hLen && offset < outputLength) {
                derived[offset] = block[j]
                offset += 1
                j += 1
            }
            blockIndex += 1
        }
        return derived
    }

    /** F(P, S, c, i) = U1 ^ U2 ^ ... ^ Uc with U1 = HMAC(P, S || INT_32_BE(i)). */
    private static func deriveBlock(password: Array<Byte>, salt: Array<Byte>, iterations: Int64, blockIndex: Int64): Array<Byte> {
        let saltWithIndex = Array<Byte>(salt.size + 4, repeat: 0)
        for (k in 0..salt.size) {
            saltWithIndex[k] = salt[k]
        }
        saltWithIndex[salt.size] = UInt8((blockIndex >> 24) & 0xFF)
        saltWithIndex[salt.size + 1] = UInt8((blockIndex >> 16) & 0xFF)
        saltWithIndex[salt.size + 2] = UInt8((blockIndex >> 8) & 0xFF)
        saltWithIndex[salt.size + 3] = UInt8(blockIndex & 0xFF)

        var u = HmacSha256.mac(password, saltWithIndex)
        let result = Array<Byte>(u.size, repeat: 0)
        for (k in 0..u.size) {
            result[k] = u[k]
        }
        var iter: Int64 = 1
        while (iter < iterations) {
            u = HmacSha256.mac(password, u)
            for (k in 0..result.size) {
                result[k] ^= u[k]
            }
            iter += 1
        }
        return result
    }
}

/** HMAC-SHA256 (RFC 2104), pure Cangjie. */
class HmacSha256 {
    private static let blockSize: Int64 = 64

    static func mac(key: Array<Byte>, message: Array<Byte>): Array<Byte> {
        var k = key
        if (k.size > blockSize) {
            k = Sha256.hash(k)
        }
        let keyBlock = Array<Byte>(blockSize, repeat: 0)
        for (i in 0..k.size) {
            keyBlock[i] = k[i]
        }
        let ipad = Array<Byte>(blockSize, repeat: 0)
        let opad = Array<Byte>(blockSize, repeat: 0)
        for (i in 0..blockSize) {
            ipad[i] = keyBlock[i] ^ 0x36
            opad[i] = keyBlock[i] ^ 0x5c
        }
        let inner = Array<Byte>(blockSize + message.size, repeat: 0)
        for (i in 0..blockSize) {
            inner[i] = ipad[i]
        }
        for (i in 0..message.size) {
            inner[blockSize + i] = message[i]
        }
        let innerHash = Sha256.hash(inner)
        let outer = Array<Byte>(blockSize + innerHash.size, repeat: 0)
        for (i in 0..blockSize) {
            outer[i] = opad[i]
        }
        for (i in 0..innerHash.size) {
            outer[blockSize + i] = innerHash[i]
        }
        return Sha256.hash(outer)
    }
}

/** SHA-256 (FIPS 180-4), pure Cangjie over UInt32 words. */
class Sha256 {
    private static let k: Array<UInt32> = [
        0x428a2f98u32, 0x71374491u32, 0xb5c0fbcfu32, 0xe9b5dba5u32,
        0x3956c25bu32, 0x59f111f1u32, 0x923f82a4u32, 0xab1c5ed5u32,
        0xd807aa98u32, 0x12835b01u32, 0x243185beu32, 0x550c7dc3u32,
        0x72be5d74u32, 0x80deb1feu32, 0x9bdc06a7u32, 0xc19bf174u32,
        0xe49b69c1u32, 0xefbe4786u32, 0x0fc19dc6u32, 0x240ca1ccu32,
        0x2de92c6fu32, 0x4a7484aau32, 0x5cb0a9dcu32, 0x76f988dau32,
        0x983e5152u32, 0xa831c66du32, 0xb00327c8u32, 0xbf597fc7u32,
        0xc6e00bf3u32, 0xd5a79147u32, 0x06ca6351u32, 0x14292967u32,
        0x27b70a85u32, 0x2e1b2138u32, 0x4d2c6dfcu32, 0x53380d13u32,
        0x650a7354u32, 0x766a0abbu32, 0x81c2c92eu32, 0x92722c85u32,
        0xa2bfe8a1u32, 0xa81a664bu32, 0xc24b8b70u32, 0xc76c51a3u32,
        0xd192e819u32, 0xd6990624u32, 0xf40e3585u32, 0x106aa070u32,
        0x19a4c116u32, 0x1e376c08u32, 0x2748774cu32, 0x34b0bcb5u32,
        0x391c0cb3u32, 0x4ed8aa4au32, 0x5b9cca4fu32, 0x682e6ff3u32,
        0x748f82eeu32, 0x78a5636fu32, 0x84c87814u32, 0x8cc70208u32,
        0x90befffau32, 0xa4506cebu32, 0xbef9a3f7u32, 0xc67178f2u32
    ]

    // SHA-256 is mod-2^32 arithmetic; Cangjie default arithmetic is
    // overflow-checked, so wrap the whole routine (FIPS 180-4 semantics).
    @OverflowWrapping
    static func hash(message: Array<Byte>): Array<Byte> {
        var h0: UInt32 = 0x6a09e667u32
        var h1: UInt32 = 0xbb67ae85u32
        var h2: UInt32 = 0x3c6ef372u32
        var h3: UInt32 = 0xa54ff53au32
        var h4: UInt32 = 0x510e527fu32
        var h5: UInt32 = 0x9b05688cu32
        var h6: UInt32 = 0x1f83d9abu32
        var h7: UInt32 = 0x5be0cd19u32

        let padded = pad(message)
        let blockCount = padded.size / 64
        let w = Array<UInt32>(64, repeat: 0u32)

        var blockNo: Int64 = 0
        while (blockNo < blockCount) {
            let base = blockNo * 64
            for (t in 0..16) {
                let i = base + t * 4
                w[t] = (UInt32(padded[i]) << 24) | (UInt32(padded[i + 1]) << 16) |
                    (UInt32(padded[i + 2]) << 8) | UInt32(padded[i + 3])
            }
            for (t in 16..64) {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] + s0 + w[t - 7] + s1
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            var f = h5
            var g = h6
            var hh = h7

            for (t in 0..64) {
                let bigS1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((!e) & g)
                let temp1 = hh + bigS1 + ch + k[t] + w[t]
                let bigS0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = bigS0 + maj
                hh = g
                g = f
                f = e
                e = d + temp1
                d = c
                c = b
                b = a
                a = temp1 + temp2
            }

            h0 += a
            h1 += b
            h2 += c
            h3 += d
            h4 += e
            h5 += f
            h6 += g
            h7 += hh
            blockNo += 1
        }

        let digest = Array<Byte>(32, repeat: 0)
        writeWord(digest, 0, h0)
        writeWord(digest, 4, h1)
        writeWord(digest, 8, h2)
        writeWord(digest, 12, h3)
        writeWord(digest, 16, h4)
        writeWord(digest, 20, h5)
        writeWord(digest, 24, h6)
        writeWord(digest, 28, h7)
        return digest
    }

    private static func writeWord(buf: Array<Byte>, offset: Int64, value: UInt32): Unit {
        buf[offset] = UInt8((value >> 24) & 0xFFu32)
        buf[offset + 1] = UInt8((value >> 16) & 0xFFu32)
        buf[offset + 2] = UInt8((value >> 8) & 0xFFu32)
        buf[offset + 3] = UInt8(value & 0xFFu32)
    }

    private static func rotr(x: UInt32, n: UInt32): UInt32 {
        return (x >> n) | (x << (32u32 - n))
    }

    /** Append 0x80, zero-pad to 56 mod 64, then the 64-bit big-endian bit length. */
    private static func pad(message: Array<Byte>): Array<Byte> {
        let msgLen = message.size
        let bitLen = Int64(msgLen) * 8
        var padLen = 64 - ((msgLen + 8) % 64)
        if (padLen == 0) {
            padLen = 64
        }
        let totalLen = msgLen + padLen + 8
        let out = Array<Byte>(totalLen, repeat: 0)
        for (i in 0..msgLen) {
            out[i] = message[i]
        }
        out[msgLen] = 0x80
        var len = bitLen
        var idx = totalLen - 1
        var b: Int64 = 0
        while (b < 8) {
            out[idx] = UInt8(len & 0xFF)
            len = len >> 8
            idx -= 1
            b += 1
        }
        return out
    }
}
