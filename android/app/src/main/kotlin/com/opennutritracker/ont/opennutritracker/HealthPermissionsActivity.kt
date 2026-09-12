package com.opennutritracker.ont.opennutritracker

import android.app.Activity
import android.os.Bundle
import android.widget.TextView
import android.widget.ScrollView

/** Available from Android's permission screen without starting the diary. */
class HealthPermissionsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val disclosure = TextView(this).apply {
            text = "Health Connect in Stable\n\n" +
                "When you enable step import for a profile, Stable reads daily step totals " +
                "when the app opens or resumes and catches up missed days.\n\n" +
                "Imported steps stay in the local encrypted diary. Stable does not upload " +
                "this health data or write anything to Health Connect. Your own diary exports " +
                "include imported steps. Step counts do not change calorie targets.\n\n" +
                "You can revoke access in Health Connect at any time. This stops future reads; " +
                "steps already imported remain in the diary until you delete them."
            textSize = 18f
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        setContentView(ScrollView(this).apply { addView(disclosure) })
    }
}
