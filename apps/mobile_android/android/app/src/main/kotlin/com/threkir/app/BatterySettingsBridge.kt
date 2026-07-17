package com.threkir.app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Opens the system battery-optimisation settings so the runner can exempt
/// the app from the OEM app-killer (Samsung Stamina, Xiaomi, OnePlus — the
/// dontkillmyapp.com pattern). Dart side (`lib/battery_optimisation_hint.dart`)
/// calls through the `run_app/battery_settings` method channel and falls back
/// to the generic App Info page when this returns false.
class BatterySettingsBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(messenger, "run_app/battery_settings")

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBatteryOptimisationSettings" -> {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }
}
