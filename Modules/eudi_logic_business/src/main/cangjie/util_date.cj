/*
 * Copyright (c) 2026 European Commission
 * Modifications Copyright (c) 2026 CJPLUK contributors (HarmonyOS / Cangjie port)
 *
 * Licensed under the EUPL, Version 1.2. Ported from the iOS logic-business module
 * (Sources/Extension/Date+Extensions.swift, Locale+Extensions.swift,
 * TimeInterval+Extensions.swift) to Cangjie.
 *
 * Swift `Date` maps to `std.time.DateTime`. The iOS service date parsing
 * (`Locale.serviceDateFormatters`) is reimplemented as a deterministic manual
 * parser over the same six formats so behaviour does not depend on platform
 * formatter token dialects.
 */
package eudi_logic_business

import std.time.*
import std.convert.*
import std.collection.ArrayList

/** Date helper set mirroring the cross-module consumed iOS Date/Locale extensions. */
public class DateUtil {

    public static let MONTH_NAMES: Array<String> = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    /** Abbreviated month names for the `MMM` pattern (iOS short date style). */
    public static let MONTH_ABBR: Array<String> = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    /** Mirrors `Locale.serviceDateFormatters` (documentation of the accepted formats). */
    public static let SERVICE_DATE_FORMATS: Array<String> = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd",
        "dd/MM/yyyy"
    ]

    /** Mirrors `isWithinNextDays(_:)`: now <= self <= now + days. */
    public static func isWithinNextDays(date: DateTime, days: Int64): Bool {
        let now = DateTime.now()
        let future = now.addDays(days)
        return date >= now && date <= future
    }

    /** Mirrors `isWithinNextHours(_:)`. */
    public static func isWithinNextHours(date: DateTime, hours: Int64): Bool {
        let now = DateTime.now()
        let future = now.addHours(hours)
        return date >= now && date <= future
    }

    /** Mirrors `isBeyondNextDays(_:)`: self > now + days. */
    public static func isBeyondNextDays(date: DateTime, days: Int64): Bool {
        let now = DateTime.now()
        let future = now.addDays(days)
        return date > future
    }

    /** Mirrors `isBeforeToday()`: calendar-day comparison, not instant comparison. */
    public static func isBeforeToday(date: DateTime): Bool {
        let today = startOfDay(DateTime.now())
        return date < today
    }

    /** Mirrors `isValid()`: not yet expired relative to now. */
    public static func isValid(date: DateTime): Bool {
        return date >= DateTime.now()
    }

    /** Mirrors `isExpired()`. */
    public static func isExpired(date: DateTime): Bool {
        return date < DateTime.now()
    }

    /**
     * Mirrors `isBetween(_:_:)`:
     * both bounds nil -> None; one bound nil or start > end -> false;
     * otherwise inclusive check from start-of-day(start) to 23:59:59 of end.
     */
    public static func isBetween(date: DateTime, startDate: ?DateTime, endDate: ?DateTime): ?Bool {
        let start: DateTime
        let end: DateTime
        match ((startDate, endDate)) {
            case (Some(s), Some(e)) =>
                start = s
                end = e
            case (None, None) => return None
            case _ => return false
        }
        if (start > end) {
            return false
        }
        let startOfDayStart = startOfDay(start)
        let endOfDayEnd = endOfDay(end)
        if (startOfDayStart == endOfDayEnd) {
            return isSameDay(date, startOfDayStart)
        }
        return date >= startOfDayStart && date <= endOfDayEnd
    }

    /** Mirrors `isToday()`. */
    public static func isToday(date: DateTime): Bool {
        return isSameDay(date, DateTime.now())
    }

    /** Mirrors `isThisWeek()` (ISO-like week starting Monday, local time). */
    public static func isThisWeek(date: DateTime): Bool {
        let now = DateTime.now()
        let weekday = dayOfWeekMonday0(now)
        let startOfWeek = startOfDay(now.addDays(-weekday))
        let endOfWeek = startOfWeek.addDays(7)
        return date >= startOfWeek && date < endOfWeek
    }

    /** Mirrors `formattedAsDayMonthYearTime()`: "d MMMM yyyy hh:mm a". */
    public static func formattedAsDayMonthYearTime(date: DateTime): String {
        let hour24 = date.hour
        var hour12 = hour24 % 12
        if (hour12 == 0) {
            hour12 = 12
        }
        let meridiem = if (hour24 < 12) { "AM" } else { "PM" }
        let minuteText = "${date.minute}".padStart(2, padding: "0")
        let hourText = "${hour12}".padStart(2, padding: "0")
        return "${date.dayOfMonth} ${monthName(date)} ${date.year} ${hourText}:${minuteText} ${meridiem}"
    }

    /** Mirrors `formattedMonthYear()`: "MMMM yyyy" uppercased. */
    public static func formattedMonthYear(date: DateTime): String {
        return "${monthName(date)} ${date.year}".toAsciiUpper()
    }

    /** Mirrors `monthYearOrder`: year * 12 + month. */
    public static func monthYearOrder(date: DateTime): Int64 {
        return date.year * 12 + date.monthValue
    }

    /**
     * Mirrors `Locale.parseDate(date:formatters:)`: tries the six iOS service
     * formats in order and returns the first hit (local time zone; trailing
     * `Z`/`+hh:mm` offsets are honoured as UTC offsets).
     */
    public static func parseServiceDate(text: String): ?DateTime {
        let value = text.trimAscii()
        if (value.isEmpty()) {
            return None
        }
        if (value.contains("T")) {
            return parseIsoDateTime(value)
        }
        if (value.contains("/")) {
            // dd/MM/yyyy
            let parts = value.split("/")
            if (parts.size != 3) {
                return None
            }
            return makeDate(parts[2], parts[1], parts[0])
        }
        // yyyy-MM-dd
        let parts = value.split("-")
        if (parts.size != 3) {
            return None
        }
        return makeDate(parts[0], parts[1], parts[2])
    }

    /**
     * Mirrors `Locale.localizedDateTime(date:uiFormatter:)` for service inputs:
     * parses with the six service formats, then formats with `formatDate`.
     * Unparseable input echoes back unchanged, like the iOS source.
     */
    public static func localizedDateTime(text: String, uiFormat: String): String {
        match (parseServiceDate(text)) {
            case Some(parsed) => return formatDate(parsed, uiFormat)
            case None => return text
        }
    }

    /**
     * Formats with the iOS-style pattern subset used by the wallet:
     * yyyy, MMMM, MM, M, dd, d, HH, hh, mm, ss, a. Other characters pass through.
     */
    public static func formatDate(date: DateTime, pattern: String): String {
        let sb = StringBuilder()
        let runes = pattern.toRuneArray()
        var i: Int64 = 0
        while (i < runes.size) {
            let c = runes[i]
            var runLength: Int64 = 1
            while (i + runLength < runes.size && runes[i + runLength] == c) {
                runLength++
            }
            sb.append(formatToken(date, c, runLength))
            i += runLength
        }
        return sb.toString()
    }

    /** Mirrors `TimeInterval.seconds`. */
    public static func intervalSeconds(interval: Float64): Int64 {
        if (interval >= 0.0) {
            return Int64(interval + 0.5)
        }
        return -Int64(-interval + 0.5)
    }

    /** Mirrors `TimeInterval.milliseconds`. */
    public static func intervalMilliseconds(interval: Float64): Int64 {
        return Int64(interval * 1000.0)
    }

    /** Mirrors `TimeInterval.nanoseconds`. */
    public static func intervalNanoseconds(interval: Float64): UInt64 {
        return UInt64(interval * 1_000_000_000.0)
    }

    /**
     * Mirrors `Calendar.current.startOfDay(for:)`: convert `date` to the device
     * local zone first, then take that civil day's 00:00:00. Using the raw
     * Y-M-D fields of a non-local `DateTime` (e.g. `00:30` at UTC+14) would
     * build a midnight that is later than the original instant.
     */
    public static func startOfDay(date: DateTime): DateTime {
        let local = date.inLocal()
        return DateTime.of(year: local.year, month: local.monthValue, dayOfMonth: local.dayOfMonth)
    }

    /** 23:59:59 of the device-local calendar day. Mirrors iOS `date(bySettingHour: 23, ...)`. */
    public static func endOfDay(date: DateTime): DateTime {
        let local = date.inLocal()
        return DateTime.of(
            year: local.year,
            month: local.monthValue,
            dayOfMonth: local.dayOfMonth,
            hour: 23,
            minute: 59,
            second: 59
        )
    }

    /** Same device-local calendar day. Mirrors `calendar.isDate(_:inSameDayAs:)`. */
    public static func isSameDay(a: DateTime, b: DateTime): Bool {
        let la = a.inLocal()
        let lb = b.inLocal()
        return la.year == lb.year && la.monthValue == lb.monthValue && la.dayOfMonth == lb.dayOfMonth
    }

    private static func monthName(date: DateTime): String {
        let index = date.monthValue - 1
        if (index < 0 || index >= MONTH_NAMES.size) {
            return "${date.monthValue}"
        }
        return MONTH_NAMES[index]
    }

    private static func monthAbbr(date: DateTime): String {
        let index = date.monthValue - 1
        if (index < 0 || index >= MONTH_ABBR.size) {
            return "${date.monthValue}"
        }
        return MONTH_ABBR[index]
    }

    private static func dayOfWeekMonday0(date: DateTime): Int64 {
        // DayOfWeek.toInteger(): Sunday == 0 ... Saturday == 6
        let sunday0 = date.dayOfWeek.toInteger()
        return (sunday0 + 6) % 7
    }

    private static func formatToken(date: DateTime, token: Rune, runLength: Int64): String {
        if (token == r'y') {
            return "${date.year}"
        }
        if (token == r'M') {
            if (runLength >= 4) {
                return monthName(date)
            }
            // MMM → abbreviated month name (e.g. "Sep"), iOS short date style.
            if (runLength == 3) {
                return monthAbbr(date)
            }
            if (runLength >= 2) {
                return "${date.monthValue}".padStart(2, padding: "0")
            }
            return "${date.monthValue}"
        }
        if (token == r'd') {
            if (runLength >= 2) {
                return "${date.dayOfMonth}".padStart(2, padding: "0")
            }
            return "${date.dayOfMonth}"
        }
        if (token == r'H') {
            return "${date.hour}".padStart(2, padding: "0")
        }
        if (token == r'h') {
            var hour12 = date.hour % 12
            if (hour12 == 0) {
                hour12 = 12
            }
            return "${hour12}".padStart(2, padding: "0")
        }
        if (token == r'm') {
            return "${date.minute}".padStart(2, padding: "0")
        }
        if (token == r's') {
            return "${date.second}".padStart(2, padding: "0")
        }
        if (token == r'a') {
            return if (date.hour < 12) { "AM" } else { "PM" }
        }
        let sb = StringBuilder()
        var i: Int64 = 0
        while (i < runLength) {
            sb.append(token)
            i++
        }
        return sb.toString()
    }

    private static func parseIsoDateTime(value: String): ?DateTime {
        let pieces = value.split("T")
        if (pieces.size != 2) {
            return None
        }
        let dateParts = pieces[0].split("-")
        if (dateParts.size != 3) {
            return None
        }
        var timeText = pieces[1]
        var offsetMinutes: ?Int64 = None
        if (timeText.endsWith("Z")) {
            offsetMinutes = 0
            timeText = timeText.removeSuffix("Z")
        } else {
            match (findOffsetIndex(timeText)) {
                case Some(idx) =>
                    let offsetText = timeText[idx..timeText.size]
                    timeText = timeText[0..idx]
                    match (parseOffsetMinutes(offsetText)) {
                        case Some(m) => offsetMinutes = m
                        case None => return None
                    }
                case None => ()
            }
        }
        var millisText = "0"
        if (timeText.contains(".")) {
            let fracParts = timeText.split(".")
            if (fracParts.size != 2) {
                return None
            }
            timeText = fracParts[0]
            millisText = fracParts[1]
        }
        let timeParts = timeText.split(":")
        if (timeParts.size != 3) {
            return None
        }
        let year = Int64.tryParse(dateParts[0])
        let month = Int64.tryParse(dateParts[1])
        let day = Int64.tryParse(dateParts[2])
        let hour = Int64.tryParse(timeParts[0])
        let minute = Int64.tryParse(timeParts[1])
        let second = Int64.tryParse(timeParts[2])
        let millis = Int64.tryParse(millisText) ?? 0
        match ((year, month, day)) {
            case (Some(y), Some(mo), Some(d)) =>
                match ((hour, minute, second)) {
                    case (Some(h), Some(mi), Some(s)) =>
                        return buildDateTime(y, mo, d, h, mi, s, millis, offsetMinutes)
                    case _ => return None
                }
            case _ => return None
        }
    }

    private static func buildDateTime(
        year: Int64,
        month: Int64,
        day: Int64,
        hour: Int64,
        minute: Int64,
        second: Int64,
        millis: Int64,
        offsetMinutes: ?Int64
    ): ?DateTime {
        try {
            match (offsetMinutes) {
                case Some(offset) =>
                    let utc = DateTime.ofUTC(
                        year: year,
                        month: month,
                        dayOfMonth: day,
                        hour: hour,
                        minute: minute,
                        second: second,
                        nanosecond: millis * 1_000_000
                    )
                    return utc - Duration.minute * offset
                case None =>
                    return DateTime.of(
                        year: year,
                        month: month,
                        dayOfMonth: day,
                        hour: hour,
                        minute: minute,
                        second: second,
                        nanosecond: millis * 1_000_000
                    )
            }
        } catch (_: Exception) {
            return None
        }
    }

    private static func findOffsetIndex(timeText: String): ?Int64 {
        // An explicit +hh:mm / -hh:mm zone suffix appears after the seconds block.
        let bytes = timeText.toArray()
        var i = bytes.size - 1
        while (i > 0) {
            let b = bytes[i]
            if (b == UInt8(43) || b == UInt8(45)) { // '+' or '-'
                return i
            }
            if (b == UInt8(58) || (b >= UInt8(48) && b <= UInt8(57))) { // ':' or digit
                i--
                continue
            }
            return None
        }
        return None
    }

    private static func parseOffsetMinutes(offsetText: String): ?Int64 {
        if (offsetText.size < 3) {
            return None
        }
        let sign: Int64 = if (offsetText.startsWith("-")) { -1 } else { 1 }
        let body = offsetText[1..offsetText.size].replace(":", "")
        if (body.size != 4 && body.size != 2) {
            return None
        }
        let hours = Int64.tryParse(body[0..2])
        let minutes: ?Int64 = if (body.size == 4) { Int64.tryParse(body[2..4]) } else { 0 }
        match ((hours, minutes)) {
            case (Some(h), Some(m)) => return sign * (h * 60 + m)
            case _ => return None
        }
    }

    private static func makeDate(yearText: String, monthText: String, dayText: String): ?DateTime {
        let year = Int64.tryParse(yearText.trimAscii())
        let month = Int64.tryParse(monthText.trimAscii())
        let day = Int64.tryParse(dayText.trimAscii())
        match ((year, month, day)) {
            case (Some(y), Some(m), Some(d)) =>
                try {
                    return DateTime.of(year: y, month: m, dayOfMonth: d)
                } catch (_: Exception) {
                    return None
                }
            case _ => return None
        }
    }
}
