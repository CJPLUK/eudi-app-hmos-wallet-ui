/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2.
 *
 * HuksKeyChainController — KeyChainController backed by HUKS-wrapped blobs.
 *
 * iOS stores PIN salt/hash and other small secrets in the Keychain. HarmonyOS
 * has no Keychain; this controller keeps the same string k/v interface but
 * encrypts the map with HuksSecureKeyStorage (AES wrap key inside HUKS, blob
 * on disk). Host unit tests keep using KeyChainControllerImpl / fakes in
 * eudi_logic_business so they do not pull the ohos-only HUKS graph.
 */
package eudi_logic_core

import std.collection.HashMap
import std.sync.Mutex
import std.fs.{Directory, exists}
import eudi_logic_business.KeyChainController
import eudi_logic_business.KeyChainWrapper
import ohos_app_cangjie_eudi_cjwallet_storage.storage.keystore.HuksSecureKeyStorage

/** HUKS-wrapped string store implementing KeyChainController. */
public class HuksKeyChainController <: KeyChainController {
    private let lock = Mutex()
    private let storage: HuksSecureKeyStorage
    private static let SLOT_ID: String = "kv"

    public init(service!: String, storageDir!: String) {
        if (!exists(storageDir)) {
            try {
                Directory.create(storageDir, recursive: true)
            } catch (_: Exception) {
                ()
            }
        }
        this.storage = HuksSecureKeyStorage(service, storageDir)
    }

    public func storeValue(key: KeyChainWrapper, value: String): Unit {
        synchronized(lock) {
            let dict = this.storage.readKeyInfo(HuksKeyChainController.SLOT_ID)
            dict[key.value] = value.toArray()
            this.storage.writeKeyInfo(HuksKeyChainController.SLOT_ID, dict)
        }
    }

    public func getValue(key: KeyChainWrapper): ?String {
        synchronized(lock) {
            let dict = this.storage.readKeyInfo(HuksKeyChainController.SLOT_ID)
            if (dict.contains(key.value)) {
                return Some(String.fromUtf8(dict[key.value]))
            }
            return None
        }
    }

    public func removeObject(key: KeyChainWrapper): Unit {
        synchronized(lock) {
            let dict = this.storage.readKeyInfo(HuksKeyChainController.SLOT_ID)
            dict.remove(key.value)
            this.storage.writeKeyInfo(HuksKeyChainController.SLOT_ID, dict)
        }
    }
}
