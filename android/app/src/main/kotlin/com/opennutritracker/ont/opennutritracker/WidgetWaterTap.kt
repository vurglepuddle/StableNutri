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

    fun pendingMl(taps: List<WidgetWaterTap>, profile: String, day: String, offset: Int,
                  zone: ZoneId = ZoneId.systemDefault()): Int = taps
        .distinctBy { it.id }
        .filter { it.profileId == profile && day(it.time, offset, zone) == day }
        .sumOf { it.amountMl }
}
