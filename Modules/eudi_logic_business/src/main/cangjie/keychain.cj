/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved ...
 *
 * KeyChainController — the secure key/value store the wallet uses for PIN
 * throttle/storage and that WalletKitController uses to persist the
 * dynamic-issuance pending URL.
 *
 * On iOS this protocol lives in logic-business (KeyChainAccess-backed Keychain).
 * HarmonyOS has no Keychain; the consumed subset (storeValue / getValue /
 * removeObject keyed by a KeyChainWrapper) is backed by a per-key file under the
 * wallet service directory — the same file-backed-secure-store pattern
 * eudi_logic_storage uses. One file per key keeps the value opaque (no escaping)
 * and avoids any in-process cache coherence concerns.
 *
 * Host `cjpm test` for eudi_logic_authentication imports these types; they must
 * live here (not in eudi_logic_core) so that module does not pull the ohos-only
 * wallet-kit graph.
 */
package eudi_logic_business

import std.collection.HashMap
import std.sync.Mutex
import std.fs.{File, Directory, exists, remove}

/** Mirrors iOS `protocol KeyChainWrapper` (a key carrying its string value). */
public interface KeyChainWrapper {
    prop value: String
}

/** Mirrors iOS `protocol KeyChainController: Sendable` (consumed subset). */
public interface KeyChainController {
    func storeValue(key: KeyChainWrapper, value: String): Unit
    func getValue(key: KeyChainWrapper): ?String
    func removeObject(key: KeyChainWrapper): Unit
}

/**
 * Mirrors iOS `KeyChainControllerImpl`, scoped by the wallet's keychain service
 * name + access group. Each key is persisted to
 * `<storageDir>/<service>.keychain/<key>` and mirrored in an in-memory cache.
 */
public class KeyChainControllerImpl <: KeyChainController {
    private let lock = Mutex()
    private let dir: String
    private let cache: HashMap<String, String>

    public init(service!: String, accessGroup!: String, storageDir!: String) {
        let safeService = keychainSanitize(service)
        this.dir = keychainJoinPath(storageDir, safeService + ".keychain")
        this.cache = HashMap<String, String>()
    }

    public func storeValue(key: KeyChainWrapper, value: String): Unit {
        synchronized(lock) {
            this.cache.add(key.value, value)
            this.persist(key.value, value)
        }
    }

    public func getValue(key: KeyChainWrapper): ?String {
        synchronized(lock) {
            match (this.cache.get(key.value)) {
                case Some(v) => return v
                case None => return this.readFromDisk(key.value)
            }
        }
    }

    public func removeObject(key: KeyChainWrapper): Unit {
        synchronized(lock) {
            this.cache.remove(key.value)
            let path = this.keyPath(key.value)
            if (exists(path)) {
                try { remove(path) } catch (_: Exception) {}
            }
        }
    }

    private func keyPath(key: String): String {
        return keychainJoinPath(this.dir, keychainSanitize(key))
    }

    private func persist(key: String, value: String): Unit {
        try {
            if (!exists(this.dir)) {
                Directory.create(this.dir, recursive: true)
            }
            File.writeTo(this.keyPath(key), value.toArray())
        } catch (_: Exception) {
            // Best-effort persistence; the in-memory cache remains authoritative.
        }
    }

    private func readFromDisk(key: String): ?String {
        let path = this.keyPath(key)
        try {
            if (!exists(path)) { return None }
        } catch (_: Exception) {
            return None
        }
        try {
            let bytes = File.readFrom(path)
            let value = String.fromUtf8(bytes)
            this.cache.add(key, value)
            return value
        } catch (_: Exception) {
            return None
        }
    }
}

func keychainSanitize(value: String): String {
    let sb = StringBuilder()
    for (c in value.toRuneArray()) {
        if (c == r'\0' || c == r'/' || c == r'\\' || c == r':') {
            sb.append(r'_')
        } else {
            sb.append(c)
        }
    }
    return sb.toString()
}

func keychainJoinPath(dir: String, name: String): String {
    if (dir.isEmpty()) { return name }
    if (dir.endsWith("/")) { return dir + name }
    return dir + "/" + name
}
