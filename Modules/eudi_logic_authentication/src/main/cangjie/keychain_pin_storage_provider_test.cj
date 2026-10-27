/*
 * Host unit tests for KeychainPinStorageProvider.
 * Migrated from iOS Tests/Provider/TestKeychainPinStorageProvider.swift (19).
 */
package eudi_logic_authentication

import std.collection.HashMap
import std.unittest.*
import std.unittest.testmacro.*
import eudi_logic_business.{KeyChainController, KeyChainWrapper}

let KC_SALT = "devicePinSalt"
let KC_HASH = "devicePinHash"
let KC_ITER = "devicePinIterations"

class FakeKeyChainController <: KeyChainController {
    let storage = HashMap<String, String>()
    public func storeValue(key: KeyChainWrapper, value: String): Unit { this.storage[key.value] = value }
    public func getValue(key: KeyChainWrapper): ?String { this.storage.get(key.value) }
    public func removeObject(key: KeyChainWrapper): Unit { this.storage.remove(key.value) }
    func putRaw(k: String, v: String): Unit { this.storage[k] = v }
    func dropRaw(k: String): Unit { this.storage.remove(k) }
    func getRaw(k: String): ?String { this.storage.get(k) }
    func count(): Int64 { this.storage.size }
}

@Test
class TestKeychainPinStorageProvider {
    @TestCase
    func testHasPin_WhenNothingStored_ThenFalse(): Unit {
        @Expect(KeychainPinStorageProvider(FakeKeyChainController()).hasPin(), false)
    }

    @TestCase
    func testHasPin_AfterSetPin_ThenTrue(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        @Expect(provider.hasPin(), true)
    }

    @TestCase
    func testHasPin_WhenIterationsMissing_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.dropRaw(KC_ITER)
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testHasPin_WhenSaltMissing_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.dropRaw(KC_SALT)
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testHasPin_WhenHashMissing_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.dropRaw(KC_HASH)
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testHasPin_WhenIterationsIsZero_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.putRaw(KC_ITER, "0")
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testHasPin_WhenIterationsIsNotNumeric_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.putRaw(KC_ITER, "abc")
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testSetPin_WhenEmptyString_ThenNothingStored(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("")
        @Expect(provider.hasPin(), false)
        @Expect(kc.count(), 0)
    }

    @TestCase
    func testSetPin_StoresSaltHashAndIterations(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        @Expect(kc.getRaw(KC_SALT).isSome(), true)
        @Expect(kc.getRaw(KC_HASH).isSome(), true)
        @Expect(kc.getRaw(KC_ITER).isSome(), true)
    }

    @TestCase
    func testSetPin_UsesFreshSaltOnEverySet(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        let first = kc.getRaw(KC_SALT) ?? ""
        provider.setPin("1234")
        let second = kc.getRaw(KC_SALT) ?? ""
        @Expect(first != second, true)
    }

    @TestCase
    func testIsPinValid_WhenEmptyPin_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        @Expect(provider.isPinValid(""), false)
    }

    @TestCase
    func testIsPinValid_WhenNoStoredPin_ThenFalse(): Unit {
        @Expect(KeychainPinStorageProvider(FakeKeyChainController()).isPinValid("1234"), false)
    }

    @TestCase
    func testIsPinValid_WhenCorrectPin_ThenTrue(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        @Expect(provider.isPinValid("1234"), true)
    }

    @TestCase
    func testIsPinValid_WhenWrongPin_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        @Expect(provider.isPinValid("0000"), false)
    }

    @TestCase
    func testIsPinValid_AfterPinChange_OldPinFailsNewPinSucceeds(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1111")
        provider.setPin("2222")
        @Expect(provider.isPinValid("1111"), false)
        @Expect(provider.isPinValid("2222"), true)
    }

    @TestCase
    func testIsPinValid_WhenIterationsMissing_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.dropRaw(KC_ITER)
        @Expect(provider.isPinValid("1234"), false)
    }

    @TestCase
    func testIsPinValid_WhenIterationsIsZero_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.putRaw(KC_ITER, "0")
        @Expect(provider.isPinValid("1234"), false)
    }

    @TestCase
    func testHasPin_WhenSaltIsEmptyData_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.putRaw(KC_SALT, "")
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testHasPin_WhenHashIsEmptyData_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        let provider = KeychainPinStorageProvider(kc)
        provider.setPin("1234")
        kc.putRaw(KC_HASH, "")
        @Expect(provider.hasPin(), false)
    }

    @TestCase
    func testIsPinValid_WhenStoredHexHasOddRuneCount_ThenFalse(): Unit {
        let kc = FakeKeyChainController()
        kc.putRaw(KC_SALT, "abé")
        kc.putRaw(KC_HASH, "aa")
        kc.putRaw(KC_ITER, "210000")
        let provider = KeychainPinStorageProvider(kc)
        @Expect(provider.isPinValid("123456"), false)
    }
}
