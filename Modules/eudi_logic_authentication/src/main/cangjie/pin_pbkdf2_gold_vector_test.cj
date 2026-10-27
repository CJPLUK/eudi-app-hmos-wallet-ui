/*
 * Same-input PBKDF2 check: CommonCrypto (iOS) vs Cangjie KeychainPinStorageProvider.
 *
 * Salt = 32 bytes of 0x01, PIN = "123456", rounds = 210000, dkLen = 32.
 * Swift CCKeyDerivationPBKDF(kCCPBKDF2, kCCPRFHmacAlgSHA256) and Python
 * hashlib.pbkdf2_hmac both produced:
 *   e3e88f978f4f5119270410c8ba625959c1ea0db4b778d0457836c0800136db9a
 *
 * The production setPin() path uses a random salt, so hashes never match
 * across runs. This seeds FakeKeyChain with the fixed salt/hash and asks
 * isPinValid — the same code path the wallet uses after a store.
 */
package eudi_logic_authentication

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TestPinPbkdf2GoldVector {
    @TestCase
    func testIsPinValid_AgainstSwiftCommonCryptoHash_ThenTrue(): Unit {
        let kc = FakeKeyChainController()
        kc.putRaw(KC_SALT, "0101010101010101010101010101010101010101010101010101010101010101")
        kc.putRaw(KC_HASH, "e3e88f978f4f5119270410c8ba625959c1ea0db4b778d0457836c0800136db9a")
        kc.putRaw(KC_ITER, "210000")
        let provider = KeychainPinStorageProvider(kc)
        @Expect(provider.isPinValid("123456"), true)
    }

    @TestCase
    func testIsPinValid_AgainstSwiftCommonCryptoHash_WrongPinThenFalse(): Unit {
        let kc = FakeKeyChainController()
        kc.putRaw(KC_SALT, "0101010101010101010101010101010101010101010101010101010101010101")
        kc.putRaw(KC_HASH, "e3e88f978f4f5119270410c8ba625959c1ea0db4b778d0457836c0800136db9a")
        kc.putRaw(KC_ITER, "210000")
        let provider = KeychainPinStorageProvider(kc)
        @Expect(provider.isPinValid("000000"), false)
        @Expect(provider.isPinValid("1234567"), false)
    }
}
