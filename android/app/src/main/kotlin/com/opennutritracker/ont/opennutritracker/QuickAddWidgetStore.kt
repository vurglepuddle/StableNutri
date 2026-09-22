package com.opennutritracker.ont.opennutritracker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** A single private preference holds the snapshot and durable water outbox.
 *  Writes are committed before the launcher displays an added cup. The app
 *  acknowledges IDs only with totals that include them, in the same write. */
object QuickAddWidgetStore {
    private fun prefs(context: Context) = context.getSharedPreferences("stable_quick_add", Context.MODE_PRIVATE)
    private fun read(context: Context): JSONObject = try {
        JSONObject(prefs(context).getString("state", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }
    private fun write(context: Context, state: JSONObject) {
        check(prefs(context).edit().putString("state", state.toString()).commit()) {
            "Could not save widget water entry"
        }
    }

    @Synchronized fun snapshot(context: Context): JSONObject? = read(context).optJSONObject("snapshot")

    @Synchronized fun pending(context: Context): List<WidgetWaterTap> {
        val array = read(context).optJSONArray("water") ?: JSONArray()
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            WidgetWaterTap(item.getString("id"), item.getString("profileId"), item.getLong("time"), item.getInt("amountMl"))
        }
    }

    @Synchronized fun addWater(context: Context): Boolean {
        val state = read(context)
        val snapshot = state.optJSONObject("snapshot") ?: return false
        val profile = snapshot.optString("profileId")
        if (profile.isEmpty()) return false
        val entries = state.optJSONArray("water") ?: JSONArray()
        entries.put(JSONObject().apply {
            put("id", "widget-water-${UUID.randomUUID()}")
            put("profileId", profile)
            put("time", System.currentTimeMillis())
            put("amountMl", snapshot.optInt("cupMl", 250).coerceAtLeast(1))
        })
        state.put("water", entries)
        write(context, state)
        return true
    }

    @Synchronized fun publish(context: Context, data: Map<*, *>) {
        val state = read(context)
        val applied = (data["appliedWaterIds"] as? List<*>)?.toSet() ?: emptySet<Any>()
        state.put("water", remaining(state, applied, null))
        state.put("snapshot", JSONObject(data))
        write(context, state)
    }

    @Synchronized fun clear(context: Context, data: Map<*, *>) {
        val state = read(context)
        val applied = (data["appliedWaterIds"] as? List<*>)?.toSet() ?: emptySet<Any>()
        val discardProfile = if (data["discardWater"] == true) data["profileId"] as? String else null
        state.put("water", remaining(state, applied, discardProfile))
        state.remove("snapshot")
        write(context, state)
    }

    @Synchronized fun discardProfile(context: Context, profile: String) {
        val state = read(context)
        state.put("water", remaining(state, emptySet<String>(), profile))
        if (state.optJSONObject("snapshot")?.optString("profileId") == profile) state.remove("snapshot")
        write(context, state)
    }

    private fun remaining(state: JSONObject, applied: Set<*>, discardProfile: String?): JSONArray {
        val old = state.optJSONArray("water") ?: JSONArray()
        return JSONArray().apply {
            for (index in 0 until old.length()) {
                val item = old.getJSONObject(index)
                if (item.getString("id") !in applied && item.getString("profileId") != discardProfile) put(item)
            }
        }
    }
}
