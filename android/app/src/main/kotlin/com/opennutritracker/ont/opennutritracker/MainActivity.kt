package com.opennutritracker.ont.opennutritracker

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterFragmentActivity() {
    private lateinit var healthConnect: HealthConnectBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        healthConnect = HealthConnectBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
