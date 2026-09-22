package com.opennutritracker.ont.opennutritracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.NumberFormat
import java.math.RoundingMode
import java.util.Locale

class QuickAddWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == WATER_ACTION) {
            // Never report an increment unless the durable write succeeded.
            if (QuickAddWidgetStore.addWater(context)) {
                updateAll(context)
                MainActivity.widgetChannel?.invokeMethod("waterQueued", null)
            }
        } else if (intent.action in setOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            updateAll(context)
        }
    }

    companion object {
        const val WATER_ACTION = "com.opennutritracker.ont.QUICK_ADD_WATER"
        const val ACTION_EXTRA = "stable_widget_action"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, QuickAddWidgetProvider::class.java))
                .forEach { update(context, manager, it) }
        }

        private fun launch(context: Context, action: String): PendingIntent = PendingIntent.getActivity(
            context, action.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                putExtra(ACTION_EXTRA, action)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val data = QuickAddWidgetStore.snapshot(context)
            val systemDark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            val dark = when (data?.optString("theme")) { "dark" -> true; "light" -> false; else -> systemDark }
            val options = manager.getAppWidgetOptions(id)
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val width = options.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 300)
            val height = options.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 160)
            val stacked = height >= 260 && (width < 320 || context.resources.configuration.fontScale > 1.3f)
            val views = RemoteViews(context.packageName, if (stacked) R.layout.quick_add_widget_stacked else R.layout.quick_add_widget)
            val strong = Color.parseColor(if (dark) "#ECE8E1" else "#2B2A27")
            val muted = Color.parseColor(if (dark) "#A39E94" else "#6E685E")
            var accent = Color.parseColor(if (dark) "#34D08A" else "#0E7A4D")
            if (data != null && !data.isNull("accent")) accent = data.getLong("accent").toInt()
            else if (Build.VERSION.SDK_INT >= 31 && data?.optBoolean("materialYou") == true) {
                accent = context.getColor(if (dark) android.R.color.system_accent1_200 else android.R.color.system_accent1_600)
            }
            views.setInt(R.id.widget_root, "setBackgroundResource", if (dark) R.drawable.widget_surface_dark else R.drawable.widget_surface)
            val profile = data?.optString("profileId") ?: ""
            val locale = Locale.forLanguageTag(data?.optString("locale") ?: Locale.getDefault().toLanguageTag())
            val format = NumberFormat.getNumberInstance(locale).apply {
                maximumFractionDigits = 1
                roundingMode = RoundingMode.HALF_UP
            }
            fun litres(ml: Int) = "${format.format(ml / 1000.0)} l"
            val offset = data?.optInt("offsetMinutes") ?: 0
            val today = WidgetWaterMath.day(System.currentTimeMillis(), offset)
            val fresh = data?.optString("day") == today
            val pending = WidgetWaterMath.pendingMl(QuickAddWidgetStore.pending(context), profile, today, offset)
            val water = (if (fresh) data?.optInt("waterMl") ?: 0 else 0) + pending
            val open = data?.optString("openLabel") ?: context.getString(R.string.widget_open_stable)
            val waterLabel = data?.optString("waterLabel") ?: context.getString(R.string.widget_water)
            val foodLabel = data?.optString("foodLabel") ?: context.getString(R.string.widget_food)
            val exerciseLabel = data?.optString("exerciseLabel") ?: context.getString(R.string.widget_exercise)
            val add = data?.optString("addLabel") ?: context.getString(R.string.widget_add)
            val foodValue = if (fresh) data?.optString("foodValue") ?: open else open
            val exerciseValue = if (fresh) data?.optString("exerciseValue") ?: open else open
            val waterValue = if (fresh || pending > 0) litres(water) else open
            views.setTextViewText(R.id.widget_profile, if (profile.isEmpty()) "Stable" else "Stable · ${data?.optString("profileName")}")
            views.setViewVisibility(R.id.widget_profile, if (height >= 200) View.VISIBLE else View.GONE)
            views.setTextColor(R.id.widget_profile, muted)
            val waterAction = if (profile.isEmpty()) launch(context, "home") else PendingIntent.getBroadcast(
                context, 0, Intent(context, QuickAddWidgetProvider::class.java).setAction(WATER_ACTION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val sections = listOf(
                Section(R.id.widget_water, R.id.water_label, R.id.water_value, R.id.water_status, R.id.water_add,
                    waterLabel, waterValue, if (fresh) "/ ${litres(data?.optInt("waterGoalMl") ?: 0)}" else "",
                    "$add: ${data?.optInt("cupMl", 250) ?: 250} ml $waterLabel. $waterValue", waterAction,
                    Color.parseColor(if (dark) "#6BB4EC" else "#2E74B5")),
                Section(R.id.widget_food, R.id.food_label, R.id.food_value, R.id.food_status, R.id.food_add,
                    foodLabel, foodValue, if (fresh) data?.optString("foodStatus") ?: "" else "",
                    "$add: $foodLabel. $foodValue", launch(context, "food"), accent),
                Section(R.id.widget_exercise, R.id.exercise_label, R.id.exercise_value, R.id.exercise_status, R.id.exercise_add,
                    exerciseLabel, exerciseValue, if (fresh) data?.optString("exerciseStatus") ?: "" else "",
                    "$add: $exerciseLabel. $exerciseValue", launch(context, "exercise"),
                    Color.parseColor(if (dark) "#F2B45A" else "#B87410")),
            )
            for (section in sections) {
                views.setTextViewText(section.labelId, section.label)
                views.setTextViewText(section.valueId, section.value)
                views.setTextViewText(section.statusId, section.status)
                views.setViewVisibility(section.statusId, if (stacked || context.resources.configuration.fontScale < 1.5f) View.VISIBLE else View.GONE)
                views.setTextColor(section.labelId, section.color)
                views.setTextColor(section.valueId, strong)
                views.setTextColor(section.statusId, muted)
                views.setInt(section.addId, "setColorFilter", accent)
                views.setInt(section.addId, "setBackgroundResource", if (dark) R.drawable.widget_button_dark else R.drawable.widget_button)
                views.setContentDescription(section.addId, section.description)
                views.setOnClickPendingIntent(section.addId, section.action)
            }
            manager.updateAppWidget(id, views)
        }

        private data class Section(val root: Int, val labelId: Int, val valueId: Int, val statusId: Int, val addId: Int,
            val label: String, val value: String, val status: String, val description: String,
            val action: PendingIntent, val color: Int)
    }
}
