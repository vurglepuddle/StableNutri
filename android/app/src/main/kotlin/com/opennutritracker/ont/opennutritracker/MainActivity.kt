package com.opennutritracker.ont.opennutritracker

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private lateinit var healthConnect: HealthConnectBridge
    private var pendingWidgetAction: String? = null

    companion object {
        var widgetChannel: MethodChannel? = null
            private set
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) readWidgetAction(intent)
        else pendingWidgetAction = savedInstanceState.getString("pendingWidgetAction")
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("pendingWidgetAction", pendingWidgetAction)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readWidgetAction(intent)
    }

    private fun readWidgetAction(intent: Intent) {
        val action = intent.getStringExtra(QuickAddWidgetProvider.ACTION_EXTRA)
        if (action in setOf("home", "food", "exercise")) {
            pendingWidgetAction = action
            intent.removeExtra(QuickAddWidgetProvider.ACTION_EXTRA)
            widgetChannel?.invokeMethod("actionAvailable", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        healthConnect = HealthConnectBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stable/quick_add_widget").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "consumeAction" -> {
                            val action = pendingWidgetAction
                            pendingWidgetAction = null
                            result.success(action)
                        }
                        "pendingWater" -> result.success(QuickAddWidgetStore.pending(this@MainActivity)
                            .filter { it.profileId == call.arguments as? String }
                            .map { mapOf("id" to it.id, "profileId" to it.profileId, "time" to it.time, "amountMl" to it.amountMl) })
                        "publish" -> {
                            QuickAddWidgetStore.publish(this@MainActivity, call.arguments as Map<*, *>)
                            QuickAddWidgetProvider.updateAll(this@MainActivity)
                            result.success(true)
                        }
                        "clear" -> {
                            QuickAddWidgetStore.clear(this@MainActivity, call.arguments as Map<*, *>)
                            QuickAddWidgetProvider.updateAll(this@MainActivity)
                            result.success(true)
                        }
                        "discardProfile" -> {
                            QuickAddWidgetStore.discardProfile(this@MainActivity, call.arguments as String)
                            QuickAddWidgetProvider.updateAll(this@MainActivity)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("widget_error", error.message, null)
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        widgetChannel?.setMethodCallHandler(null)
        widgetChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
