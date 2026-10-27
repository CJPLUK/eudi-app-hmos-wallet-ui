/*
 * Region-aware phone-number validation, ported from PhoneNumberKit (the library
 * the iOS app uses) so `Rule.ValidatePhoneNumber(countryCode, _)` behaves the
 * same on both sides.
 *
 * iOS calls `PhoneNumberUtility.parse(phone, withRegion: countryCode,
 * ignoreType: false)` and treats a thrown error as invalid. The parts of that
 * pipeline that decide validity are, per PhoneNumberKit's ParseManager
 * .validPhoneNumber:
 *   1. strip the region's national prefix (PhoneNumberParser.stripNationalPrefix)
 *   2. reject unless the result fully matches generalDesc.nationalNumberPattern
 *   3. with ignoreType == false, reject unless the number matches at least one
 *      concrete type pattern (fixedLine / mobile / tollFree / ...), because
 *      PhoneNumberKit throws when the resolved type is `.unknown`
 *   4. when the region shares its calling code with others (NANP), retry against
 *      the sibling regions (ParseManager.tryTerritoriesWithCode)
 *
 * Deliberately NOT ported (not reachable from the validator's use of parse):
 *   - phone-extension parsing, alpha-number (vanity) conversion
 *   - formatting / AsYouType, carrier and geocoding lookups
 * The metadata table lives in the generated `phone_metadata.cj`.
 */
package eudi_logic_business

import std.collection.*
import std.regex.*

/** One libphonenumber territory, as parsed from a PHONE_METADATA_RECORDS row. */
struct PhoneRegionMeta {
    let id: String
    let countryCode: String
    let nationalPrefixForParsing: String
    let nationalPrefixTransformRule: String
    let generalPattern: String
    let typePatterns: Array<String>

    init(
        id!: String,
        countryCode!: String,
        nationalPrefixForParsing!: String,
        nationalPrefixTransformRule!: String,
        generalPattern!: String,
        typePatterns!: Array<String>
    ) {
        this.id = id
        this.countryCode = countryCode
        this.nationalPrefixForParsing = nationalPrefixForParsing
        this.nationalPrefixTransformRule = nationalPrefixTransformRule
        this.generalPattern = generalPattern
        this.typePatterns = typePatterns
    }
}

public class PhoneNumberValidator {

    // Parsed lazily on first use: 254 records is cheap but pointless to redo
    // per keystroke, and form validation runs on every field change.
    private static var regionIndex: ?HashMap<String, PhoneRegionMeta> = None
    private static var codeIndex: ?HashMap<String, ArrayList<PhoneRegionMeta>> = None

    private static func load(): Unit {
        if (PhoneNumberValidator.regionIndex.isSome()) {
            return
        }
        let byRegion = HashMap<String, PhoneRegionMeta>()
        let byCode = HashMap<String, ArrayList<PhoneRegionMeta>>()
        for (record in PHONE_METADATA_RECORDS) {
            let f = record.split("\t", removeEmpty: false)
            if (f.size < 15) {
                continue
            }
            let types = ArrayList<String>()
            for (i in 5..15) {
                if (!f[i].isEmpty()) {
                    types.add(f[i])
                }
            }
            let meta = PhoneRegionMeta(
                id: f[0],
                countryCode: f[1],
                nationalPrefixForParsing: f[2],
                nationalPrefixTransformRule: f[3],
                generalPattern: f[4],
                typePatterns: types.toArray()
            )
            // "001" (non-geographic entities) legitimately repeats; first wins,
            // which only matters if a caller passes "001" as the region.
            if (!byRegion.contains(meta.id)) {
                byRegion[meta.id] = meta
            }
            if (!byCode.contains(meta.countryCode)) {
                byCode[meta.countryCode] = ArrayList<PhoneRegionMeta>()
            }
            byCode[meta.countryCode].add(meta)
        }
        PhoneNumberValidator.regionIndex = Some(byRegion)
        PhoneNumberValidator.codeIndex = Some(byCode)
    }

    /**
     * True when `phone` is a valid number for `regionCode` (an ISO 3166-1 alpha-2
     * code such as "GR"). Mirrors iOS `isPhoneNumberValid(phone:countryCode:)`.
     *
     * Unknown region codes fall back to a permissive E.164 shape check so a
     * caller passing an unsupported region still gets digit/length validation
     * rather than a blanket rejection.
     */
    public static func isValid(phone: String, regionCode: String): Bool {
        PhoneNumberValidator.load()
        let digits = PhoneNumberValidator.normalize(phone)
        match (digits) {
            case None => return false
            case Some((national, wasInternational)) =>
                let region = regionCode.toAsciiUpper()
                let byRegion = PhoneNumberValidator.regionIndex.getOrThrow()
                if (!byRegion.contains(region)) {
                    return PhoneNumberValidator.isE164Shaped(national)
                }
                let meta = byRegion[region]
                var candidate = national
                if (wasInternational) {
                    // "+30 694..." → drop the calling code, and only accept it
                    // when it is the calling code of the requested region.
                    if (!candidate.startsWith(meta.countryCode)) {
                        return false
                    }
                    candidate = candidate[meta.countryCode.size..candidate.size]
                }
                if (PhoneNumberValidator.matchesRegion(candidate, meta)) {
                    return true
                }
                // NANP and friends: several territories share one calling code,
                // so a number rejected by the requested region may belong to a
                // sibling (iOS ParseManager.tryTerritoriesWithCode).
                let byCode = PhoneNumberValidator.codeIndex.getOrThrow()
                if (byCode.contains(meta.countryCode)) {
                    for (sibling in byCode[meta.countryCode]) {
                        if (sibling.id == meta.id) {
                            continue
                        }
                        if (PhoneNumberValidator.matchesRegion(candidate, sibling)) {
                            return true
                        }
                    }
                }
                return false
        }
    }

    /** Steps 1–3 of the iOS validity decision for one territory. */
    private static func matchesRegion(national: String, meta: PhoneRegionMeta): Bool {
        let stripped = PhoneNumberValidator.stripNationalPrefix(national, meta)
        if (!StringUtil.fullMatches(stripped, meta.generalPattern)) {
            return false
        }
        for (typePattern in meta.typePatterns) {
            if (StringUtil.fullMatches(stripped, typePattern)) {
                return true
            }
        }
        // Matched the general shape but no concrete type → iOS resolves
        // PhoneNumberType.unknown and throws, i.e. invalid.
        return false
    }

    /**
     * Port of PhoneNumberParser.stripNationalPrefix. Applies
     * nationalPrefixTransformRule when the prefix regex captured a group,
     * otherwise drops the matched prefix. Keeps the original number when
     * stripping would break a number that already matched generalDesc — the
     * same guard iOS applies.
     */
    private static func stripNationalPrefix(number: String, meta: PhoneRegionMeta): String {
        if (meta.nationalPrefixForParsing.isEmpty()) {
            return number
        }
        try {
            let prefixPattern = "^(?:${meta.nationalPrefixForParsing})"
            let found = Regex(prefixPattern).find(number, group: true)
            match (found) {
                case None => return number
                case Some(data) =>
                    let matched = data.matchString()
                    if (matched.isEmpty()) {
                        return number
                    }
                    var transformed = number[matched.size..number.size]
                    if (!meta.nationalPrefixTransformRule.isEmpty()) {
                        // iOS uses the LAST capture group of the prefix match.
                        let groups = data.groupCount()
                        if (groups >= 1) {
                            let captured = data.matchString(groups)
                            if (!captured.isEmpty()) {
                                transformed = meta.nationalPrefixTransformRule
                                    .replace("$1", captured)
                            }
                        }
                    }
                    // Do not strip if the untouched number is already valid and
                    // the stripped one is not.
                    if (StringUtil.fullMatches(number, meta.generalPattern) &&
                        !StringUtil.fullMatches(transformed, meta.generalPattern)) {
                        return number
                    }
                    return transformed
            }
        } catch (_: Exception) {
            return number
        }
    }

    /**
     * Reduce user input to digits. Returns the digits plus whether the input was
     * in international form; None when the input holds a character that is
     * neither a digit nor an accepted separator.
     */
    private static func normalize(phone: String): ?(String, Bool) {
        var value = phone.trimAscii()
        if (value.isEmpty()) {
            return None
        }
        var international = false
        if (value.startsWith("+")) {
            international = true
            value = value[1..value.size]
        } else if (value.startsWith("00")) {
            international = true
            value = value[2..value.size]
        }
        let sb = StringBuilder()
        for (r in value.runes()) {
            if (r >= r'0' && r <= r'9') {
                sb.append(r)
            } else if (r == r' ' || r == r'-' || r == r'(' || r == r')' || r == r'.') {
                continue
            } else {
                return None
            }
        }
        let digits = sb.toString()
        if (digits.isEmpty()) {
            return None
        }
        return Some((digits, international))
    }

    /** Fallback for regions absent from the table: E.164 national-number length. */
    private static func isE164Shaped(digits: String): Bool {
        return digits.size >= 4 && digits.size <= 15
    }
}
