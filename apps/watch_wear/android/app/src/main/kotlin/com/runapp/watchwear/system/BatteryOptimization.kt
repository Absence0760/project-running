package com.runapp.watchwear.system

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/// Helpers for asking the OS to exempt this app from battery optimisation.
/// Android's Doze + App Standby will throttle the foreground service
/// after ~10 minutes if the user hasn't whitelisted us — fatal for a
/// 60-minute run.
///
/// `isExempt` is a cheap synchronous check; `requestExemption` launches
/// the system settings prompt that asks the user to allow it.
object BatteryOptimization {

    fun isExempt(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /// Launches the system "Allow X to run in the background?" dialog.
    /// Falls back to the broader battery-optimisation settings list on
    /// devices that block the direct prompt.
    fun requestExemption(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivity(intent)
        } catch (_: Throwable) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Throwable) {
                // OEM with no settings activity exposed; nothing more we
                // can do programmatically. The pre-run banner remains so
                // the user knows recordings may be unreliable.
            }
        }
    }
}
