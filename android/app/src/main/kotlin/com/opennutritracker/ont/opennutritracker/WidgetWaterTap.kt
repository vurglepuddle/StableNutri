package com.opennutritracker.ont.opennutritracker

import java.time.Instant
import java.time.ZoneId

data class WidgetWaterTap(
    val id: String,
    val profileId: String,
    val time: Long,
    val amountMl: Int,
)

/** Uses the same elapsed-minute day offset as Dart's DayBoundaryCalc. */
object WidgetWaterMath {
    fun day(time: Long, offsetMinutes: Int, zone: ZoneId = ZoneId.systemDefault()): String {
        val date = Instant.ofEpochMilli(time).atZone(zone)
            .minusMinutes(offsetMinutes.coerceIn(0, 1439).toLong()).toLocalDate()
        return "${date.year}-${date.monthValue}-${date.dayOfMonth}"
    }

    /** When the logical day after the one containing [time] begins. */
    fun nextDayStart(time: Long, offsetMinutes: Int, zone: ZoneId = ZoneId.systemDefault()): Long {
        val offset = offsetMinutes.coerceIn(0, 1439).toLong()
        val date = Instant.ofEpochMilli(time).atZone(zone).minusMinutes(offset).toLocalDate()
        return date.plusDays(1).atStartOfDay(zone).plusMinutes(offset).toInstant().toEpochMilli()
    }

    fun pendingMl(taps: List<WidgetWaterTap>, profile: String, day: String, offset: Int,
                  zone: ZoneId = ZoneId.systemDefault()): Int = taps
        .distinctBy { it.id }
        .filter { it.profileId == profile && day(it.time, offset, zone) == day }
        .sumOf { it.amountMl }
}
