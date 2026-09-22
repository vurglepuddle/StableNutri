package com.opennutritracker.ont.opennutritracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
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

        /** One launcher row is well below this height; two rows are above it. */
        private const val TALL_MIN_HEIGHT_DP = 130

        // The app palette's deep tones, so white text reads on every tile.
        private const val WATER_COLOR = 0xFF2E74B5.toInt()
        private const val FOOD_COLOR = 0xFF0E7A4D.toInt()
        private const val EXERCISE_COLOR = 0xFFD05536.toInt()
        private const val DARK_INK = 0xFF1B1A18.toInt()

        private val WATER = TileIds(R.id.water_tile, R.id.water_background, R.id.water_label,
            R.id.water_number, R.id.water_unit, R.id.water_add)
        private val FOOD = TileIds(R.id.food_tile, R.id.food_background, R.id.food_label,
            R.id.food_number, R.id.food_unit, R.id.food_add)
        private val EXERCISE = TileIds(R.id.exercise_tile, R.id.exercise_background, R.id.exercise_label,
            R.id.exercise_number, R.id.exercise_unit, R.id.exercise_add)

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
            val content = content(context)
            val views = if (Build.VERSION.SDK_INT >= 31) {
                // The launcher picks the tallest layout that fits, and switches
                // on resize or rotation without waiting for another update.
                RemoteViews(mapOf(
                    SizeF(0f, 0f) to render(context, R.layout.quick_add_widget, content),
                    SizeF(0f, TALL_MIN_HEIGHT_DP.toFloat()) to render(context, R.layout.quick_add_widget_tall, content),
                ))
            } else {
                // Launchers report the portrait height as the maximum.
                val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                render(context, if (height >= TALL_MIN_HEIGHT_DP) R.layout.quick_add_widget_tall
                    else R.layout.quick_add_widget, content)
            }
            manager.updateAppWidget(id, views)
        }

        private fun content(context: Context): Content {
            val data = QuickAddWidgetStore.snapshot(context)
            var accent = FOOD_COLOR
            if (data != null && !data.isNull("accent")) accent = data.getLong("accent").toInt()
            else if (Build.VERSION.SDK_INT >= 31 && data?.optBoolean("materialYou") == true) {
                accent = context.getColor(android.R.color.system_accent1_600)
            }
            val profile = data?.optString("profileId") ?: ""
            val locale = Locale.forLanguageTag(data?.optString("locale") ?: Locale.getDefault().toLanguageTag())
            val format = NumberFormat.getNumberInstance(locale).apply {
                maximumFractionDigits = 1
                roundingMode = RoundingMode.HALF_UP
            }
            val offset = data?.optInt("offsetMinutes") ?: 0
            val today = WidgetWaterMath.day(System.currentTimeMillis(), offset)
            val fresh = data?.optString("day") == today
            val pending = WidgetWaterMath.pendingMl(QuickAddWidgetStore.pending(context), profile, today, offset)
            val water = (if (fresh) data?.optInt("waterMl") ?: 0 else 0) + pending
            val cupMl = data?.optInt("cupMl", 250) ?: 250
            val waterLabel = data?.optString("waterLabel") ?: context.getString(R.string.widget_water)
            val foodLabel = data?.optString("foodLabel") ?: context.getString(R.string.widget_food)
            val exerciseLabel = data?.optString("exerciseLabel") ?: context.getString(R.string.widget_exercise)
            val add = data?.optString("addLabel") ?: context.getString(R.string.widget_add)
            val energyUnit = data?.optString("energyUnit").orEmpty()
            // After a logical day change, unrefreshed totals are yesterday's.
            fun energy(key: String) = if (fresh) data?.optString(key).orEmpty() else ""
            val waterAction = if (profile.isEmpty()) launch(context, "home") else PendingIntent.getBroadcast(
                context, 0, Intent(context, QuickAddWidgetProvider::class.java).setAction(WATER_ACTION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return Content(
                open = data?.optString("openLabel") ?: context.getString(R.string.widget_open_stable),
                tiles = listOf(
                    Tile(WATER, waterLabel, if (fresh || pending > 0) format.format(water / 1000.0) else "", "l",
                        "$add: $cupMl ml $waterLabel", waterAction, WATER_COLOR),
                    Tile(FOOD, foodLabel, energy("foodAmount"), energyUnit,
                        "$add: $foodLabel", launch(context, "food"), accent),
                    Tile(EXERCISE, exerciseLabel, energy("exerciseAmount"), energyUnit,
                        "$add: $exerciseLabel", launch(context, "exercise"), EXERCISE_COLOR),
                ),
            )
        }

        private fun render(context: Context, layout: Int, content: Content): RemoteViews {
            val views = RemoteViews(context.packageName, layout)
            val tall = layout == R.layout.quick_add_widget_tall
            val resources = context.resources
            // Text follows the system font scale up to a cap. Past it, a single
            // row would push the plus out of the tile.
            val shrink = minOf(1f, (if (tall) 1.5f else 1.2f) / resources.configuration.fontScale)
            fun size(view: Int, dimen: Int) =
                views.setTextViewTextSize(view, TypedValue.COMPLEX_UNIT_PX, resources.getDimension(dimen) * shrink)
            for (tile in content.tiles) {
                val ids = tile.ids
                // White reads best on the deep palette tones; a light custom
                // accent gets dark ink instead.
                val ink = if (Color.luminance(tile.color) > 0.3f) DARK_INK else Color.WHITE
                val soft = (ink and 0xFFFFFF) or (0xD9 shl 24)
                val hasValue = tile.number.isNotEmpty()
                views.setInt(ids.background, "setColorFilter", tile.color)
                views.setInt(ids.add, "setColorFilter", ink)
                views.setTextViewText(ids.label, tile.label)
                views.setTextViewText(ids.number, if (hasValue) tile.number else content.open)
                views.setTextViewText(ids.unit, tile.unit)
                views.setViewVisibility(ids.unit, if (hasValue) View.VISIBLE else View.GONE)
                views.setTextColor(ids.label, soft)
                views.setTextColor(ids.number, ink)
                views.setTextColor(ids.unit, soft)
                size(ids.label, if (tall) R.dimen.widget_label_text_tall else R.dimen.widget_label_text)
                size(ids.number, when {
                    !hasValue -> R.dimen.widget_message_text
                    tall -> R.dimen.widget_number_text_tall
                    else -> R.dimen.widget_number_text
                })
                size(ids.unit, if (tall) R.dimen.widget_unit_text_tall else R.dimen.widget_unit_text)
                val value = if (hasValue) "${tile.number} ${tile.unit}" else content.open
                views.setContentDescription(ids.tile, "${tile.description}. $value")
                views.setOnClickPendingIntent(ids.tile, tile.action)
            }
            return views
        }

        private class TileIds(val tile: Int, val background: Int, val label: Int, val number: Int,
            val unit: Int, val add: Int)

        /** An empty [number] means there is no current value to show. */
        private class Tile(val ids: TileIds, val label: String, val number: String, val unit: String,
            val description: String, val action: PendingIntent, val color: Int)

        private class Content(val open: String, val tiles: List<Tile>)
    }
}
