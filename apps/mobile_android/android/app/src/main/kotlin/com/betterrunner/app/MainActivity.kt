package com.betterrunner.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WearAuthBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        RunNotificationBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
