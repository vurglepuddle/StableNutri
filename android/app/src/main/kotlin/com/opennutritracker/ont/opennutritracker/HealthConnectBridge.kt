package com.opennutritracker.ont.opennutritracker

import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Foreground step reads only. No exercise/calorie reads, writes or network client. */
class HealthConnectBridge(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
) {
    private val permissions = setOf(HealthPermission.getReadPermission(StepsRecord::class))
    private var permissionResult: MethodChannel.Result? = null
    private val permissionLauncher = activity.registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        permissionResult?.success(granted.containsAll(permissions))
        permissionResult = null
    }

    init {
        MethodChannel(messenger, "stable/health_connect").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(when (HealthConnectClient.getSdkStatus(activity)) {
                    HealthConnectClient.SDK_AVAILABLE -> "available"
                    HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "updateRequired"
                    else -> "unavailable"
                })
                "requestReadPermissions" -> {
                    if (permissionResult != null) {
                        result.error("busy", "A permission request is already open.", null)
                    } else if (HealthConnectClient.getSdkStatus(activity) != HealthConnectClient.SDK_AVAILABLE) {
                        result.error("unavailable", "Health Connect is unavailable.", null)
                    } else {
                        permissionResult = result
                        try {
                            permissionLauncher.launch(permissions)
                        } catch (_: Exception) {
                            permissionResult = null
                            result.error("permission", "Could not open Health Connect permissions.", null)
                        }
                    }
                }
                "openSettings" -> {
                    try {
                        activity.startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("unavailable", "Open Health Connect from Android Settings.", null)
                    }
                }
                "hasReadPermission", "readRecentStepTotals" -> activity.lifecycleScope.launch {
                    try {
                        val client = HealthConnectClient.getOrCreate(activity)
                        val granted = client.permissionController.getGrantedPermissions().containsAll(permissions)
                        if (call.method == "hasReadPermission") {
                            result.success(granted)
                        } else {
                            if (!granted) throw SecurityException()
                            val offset = call.argument<Int>("offsetMinutes") ?: 0
                            val days = call.argument<Int>("days") ?: 7
                            require(offset in 0..1439 && days in 1..30)
                            result.success(readRecentStepTotals(client, offset, days))
                        }
                    } catch (cancelled: CancellationException) {
                        result.error("cancelled", "Step import was interrupted.", null)
                        throw cancelled
                    } catch (_: SecurityException) {
                        result.error("permission", "Allow step access in Health Connect, then retry.", null)
                    } catch (_: Exception) {
                        // Health values and exception payloads never enter logs or error replies.
                        result.error("read_failed", "Could not read steps. Please retry.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private suspend fun readRecentStepTotals(
        client: HealthConnectClient, offsetMinutes: Int, days: Int,
    ): List<Map<String, Any>> {
        val now = Instant.now()
        val zone = ZoneId.systemDefault()
        val boundary = LocalTime.of(offsetMinutes / 60, offsetMinutes % 60)
        val today = now.atZone(zone).toLocalDate()
        val todayStart = today.atTime(boundary).atZone(zone).toInstant()
        val currentDay = if (now.isBefore(todayStart)) today.minusDays(1) else today
        val totals = mutableListOf<Map<String, Any>>()
        for (daysAgo in 0 until days) {
            val day = currentDay.minusDays(daysAgo.toLong())
            // Calendar boundaries, not fixed 24-hour durations: handles DST.
            val start = day.atTime(boundary).atZone(zone).toInstant()
            val next = day.plusDays(1).atTime(boundary).atZone(zone).toInstant()
            val end = if (next.isAfter(now)) now else next
            if (!end.isAfter(start)) continue
            // Health Connect applies the user's source priorities and removes
            // overlapping phone/watch steps. Do not sum raw source records.
            val aggregate = client.aggregate(AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(start, end),
            ))
            val count = aggregate[StepsRecord.COUNT_TOTAL] ?: continue
            if (count < 0) continue
            totals.add(mapOf(
                "day" to day.toString(), "steps" to count,
                "readAtMs" to now.toEpochMilli(), "offsetMinutes" to offsetMinutes,
            ))
        }
        return totals
    }
}
