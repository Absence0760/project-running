package com.threkir.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity, not FlutterActivity. The `health` plugin registers
// its Health Connect permission launcher with
// `(activity as ComponentActivity).registerForActivityResult(...)`, and
// FlutterActivity extends android.app.Activity — the cast threw,
// GeneratedPluginRegistrant swallowed it, and every requestAuthorization then
// answered false without ever showing a sheet. HealthRoutePermissionBridge
// needs the same ComponentActivity contract.
class MainActivity : FlutterFragmentActivity() {
    // registerForActivityResult has to run before the activity is CREATED, so
    // the bridge is built here rather than in configureFlutterEngine.
    private val healthRoutePermission = HealthRoutePermissionBridge(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WearAuthBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        WearRoutesBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        RunNotificationBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        BatterySettingsBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        healthRoutePermission.attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
