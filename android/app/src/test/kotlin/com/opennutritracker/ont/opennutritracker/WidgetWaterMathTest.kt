package com.opennutritracker.ont.opennutritracker

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetWaterMathTest {
    private val zone = ZoneId.of("Africa/Nairobi")
    private fun at(iso: String) = Instant.parse(iso).toEpochMilli()

    @Test fun respectsLocalTimeAndMinuteDayBoundary() {
        assertEquals("2026-9-21", WidgetWaterMath.day(at("2026-09-22T01:29:00Z"), 270, zone))
        assertEquals("2026-9-22", WidgetWaterMath.day(at("2026-09-22T01:30:00Z"), 270, zone))
    }

    @Test fun queuedWaterBelongsToItsProfileAndOriginalLogicalDay() {
        val taps = listOf(
            WidgetWaterTap("a", "first", at("2026-09-22T01:29:00Z"), 250),
            WidgetWaterTap("b", "first", at("2026-09-22T01:30:00Z"), 300),
            WidgetWaterTap("c", "other", at("2026-09-22T02:00:00Z"), 500),
        )
        assertEquals(250, WidgetWaterMath.pendingMl(taps, "first", "2026-9-21", 270, zone))
        assertEquals(300, WidgetWaterMath.pendingMl(taps, "first", "2026-9-22", 270, zone))
    }

    @Test fun aReplayedTapIsNotDisplayedTwice() {
        val tap = WidgetWaterTap("same-id", "first", at("2026-09-22T06:00:00Z"), 250)
        assertEquals(250, WidgetWaterMath.pendingMl(listOf(tap, tap), "first", "2026-9-22", 0, zone))
    }

    @Test fun theNextDayStartsAtTheConfiguredBoundary() {
        val start = WidgetWaterMath.nextDayStart(at("2026-09-22T01:29:00Z"), 270, zone)
        assertEquals(at("2026-09-22T01:30:00Z"), start)
        assertEquals("2026-9-22", WidgetWaterMath.day(start, 270, zone))
        assertEquals(at("2026-09-23T01:30:00Z"), WidgetWaterMath.nextDayStart(start, 270, zone))
    }

    @Test fun theNextDayStartFollowsDaylightSaving() {
        val berlin = ZoneId.of("Europe/Berlin")
        // 2026-10-25 has 25 hours in Berlin.
        assertEquals(at("2026-10-24T22:00:00Z"),
            WidgetWaterMath.nextDayStart(at("2026-10-24T12:00:00Z"), 0, berlin))
        assertEquals(at("2026-10-25T23:00:00Z"),
            WidgetWaterMath.nextDayStart(at("2026-10-25T12:00:00Z"), 0, berlin))
    }

    @Test fun changingTimezoneChangesTheLogicalDay() {
        val time = at("2026-09-22T01:00:00Z")
        assertEquals("2026-9-22", WidgetWaterMath.day(time, 0, zone))
        assertEquals("2026-9-21", WidgetWaterMath.day(time, 0, ZoneId.of("America/New_York")))
    }
}
