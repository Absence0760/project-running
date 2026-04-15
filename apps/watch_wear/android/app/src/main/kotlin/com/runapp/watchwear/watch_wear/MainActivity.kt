package com.runapp.watchwear.watch_wear

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HeartRatePlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
