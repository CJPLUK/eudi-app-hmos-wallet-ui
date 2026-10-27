/*
 * Host unit tests for PrefsControllerImpl JSON loading. Unpaired UTF-16
 * surrogates in `\uXXXX` must not throw; the store degrades to "key absent".
 */
package eudi_logic_business

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class PrefsJsonUnicodeTest {

    @TestCase
    func unpairedSurrogateDoesNotThrowAndSkipsEntry(): Unit {
        let dir = "/tmp/eudi_prefs_surrogate_test"
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        File.writeTo("${dir}/eudi_prefs.json", "{\"language\":\"\\ud800\"}".toArray())
        let prefs = PrefsControllerImpl(storageDir: dir)
        @Expect(prefs.getUserLocale(), "en_GB")
        @Expect(prefs.getString(PrefsKey.language).isNone(), true)
    }

    @TestCase
    func bmpUnicodeEscapeLoads(): Unit {
        let dir = "/tmp/eudi_prefs_bmp_test"
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        // \u0041 = 'A'
        File.writeTo("${dir}/eudi_prefs.json", "{\"language\":\"\\u0041\"}".toArray())
        let prefs = PrefsControllerImpl(storageDir: dir)
        @Expect(prefs.getString(PrefsKey.language), Option<String>.Some("A"))
    }

    @TestCase
    func surrogatePairLoadsAsOneScalar(): Unit {
        let dir = "/tmp/eudi_prefs_pair_test"
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        // U+1F600 GRINNING FACE as UTF-16 \uD83D\uDE00
        File.writeTo("${dir}/eudi_prefs.json", "{\"language\":\"\\uD83D\\uDE00\"}".toArray())
        let prefs = PrefsControllerImpl(storageDir: dir)
        match (prefs.getString(PrefsKey.language)) {
            case Some(v) => @Expect(v.toRuneArray().size, 1)
            case None => @Expect(false, true)
        }
    }
}
