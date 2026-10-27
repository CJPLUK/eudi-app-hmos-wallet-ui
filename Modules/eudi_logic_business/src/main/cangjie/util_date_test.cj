/*
 * Host unit tests for DateUtil.startOfDay / endOfDay / isSameDay.
 * Guards the iOS Calendar.current.startOfDay(for:) contract: midnight of the
 * device-local civil day, which is never later than the original instant.
 */
package eudi_logic_business

import std.time.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DateUtilStartOfDayTest {

    @TestCase
    func startOfDayIsNotAfterInputEvenWithPositiveOffset(): Unit {
        // 2026-01-01T00:30:00+14:00 == 2025-12-31T10:30:00Z. Taking Y-M-D from
        // the +14 civil fields would build 2026-01-01T00:00:00Z, which is AFTER
        // the instant. Local-calendar startOfDay must stay <= the input.
        let utc = DateTime.ofUTC(
            year: 2025,
            month: 12,
            dayOfMonth: 31,
            hour: 10,
            minute: 30,
            second: 0
        )
        let start = DateUtil.startOfDay(utc)
        @Expect(start <= utc, true)
    }

    @TestCase
    func startOfDayMatchesLocalCivilDateAndMidnight(): Unit {
        let utc = DateTime.ofUTC(
            year: 2025,
            month: 12,
            dayOfMonth: 31,
            hour: 10,
            minute: 30,
            second: 0
        )
        let local = utc.inLocal()
        let start = DateUtil.startOfDay(utc)
        let startLocal = start.inLocal()
        @Expect(startLocal.year, local.year)
        @Expect(startLocal.monthValue, local.monthValue)
        @Expect(startLocal.dayOfMonth, local.dayOfMonth)
        @Expect(startLocal.hour, 0)
        @Expect(startLocal.minute, 0)
        @Expect(startLocal.second, 0)
    }

    @TestCase
    func startOfDayIsIdempotent(): Unit {
        let now = DateTime.now()
        let once = DateUtil.startOfDay(now)
        let twice = DateUtil.startOfDay(once)
        @Expect(once == twice, true)
    }

    @TestCase
    func isSameDayUsesLocalCalendarDay(): Unit {
        let now = DateTime.now()
        @Expect(DateUtil.isSameDay(now, DateUtil.startOfDay(now)), true)
        @Expect(DateUtil.isSameDay(now, now.addDays(1)), false)
    }
}
