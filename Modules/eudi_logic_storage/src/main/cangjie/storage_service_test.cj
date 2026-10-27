/*
 * Host unit tests for storage JSON string decoding. Unpaired UTF-16
 * surrogates in `\uXXXX` must not throw; the parser returns None and
 * loadFromDisk degrades (skips the field) instead of crashing.
 */
package eudi_logic_storage

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class StorageJsonUnicodeTest {

    @TestCase
    func unpairedSurrogateDoesNotThrow(): Unit {
        let raw = "\"\\ud800\""
        @Expect(jsonParseString(raw.toRuneArray(), 0).isNone(), true)
    }

    @TestCase
    func bmpUnicodeEscapeLoads(): Unit {
        let raw = "\"\\u0041\""
        match (jsonParseString(raw.toRuneArray(), 0)) {
            case Some((v, _)) => @Expect(v, "A")
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func surrogatePairLoadsAsOneScalar(): Unit {
        // U+1F600 GRINNING FACE as UTF-16 \uD83D\uDE00
        let raw = "\"\\uD83D\\uDE00\""
        match (jsonParseString(raw.toRuneArray(), 0)) {
            case Some((v, _)) => @Expect(v.toRuneArray().size, 1)
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func unpairedSurrogateInObjectArrayDoesNotThrow(): Unit {
        let items = jsonParseObjectArray("[{\"identifier\":\"\\ud800\"}]")
        @Expect(items.size >= 0, true)
    }

    @TestCase
    func truncatedLastObjectIsDropped(): Unit {
        let items = jsonParseObjectArray("[{\"identifier\":\"A\"},{\"identifier\":\"B\"")
        @Expect(items.size, 1)
        match (items[0].get("identifier")) {
            case Some(id) => @Expect(id, "A")
            case None => @Expect(false, true)
        }
    }

    @TestCase
    func unpairedSurrogateBookmarkFileDoesNotThrow(): Unit {
        let dir = "/tmp/eudi_storage_surrogate_test"
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        File.writeTo("${dir}/bookmarks.json", "[{\"identifier\":\"\\ud800\"}]".toArray())
        let svc = BookmarkStorageService(dir)
        @Expect(svc.readAll().size, 0)
    }
}
