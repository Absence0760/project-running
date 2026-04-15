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

    enum class PromptResult {
        /// A system Activity was launched. The user returns via back/swipe;
        /// `onResume` re-checks status.
        LaunchedSystemPrompt,

        /// No activity could handle the request. Common on Wear OS, where
        /// battery-optimisation settings are usually on the paired phone's
        /// Watch companion app rather than in the watch's own Settings.
        NotSupportedOnThisWatch,

        /// Handler claimed to resolve but threw when launched.
        Failed,
    }

    /// Asks the OS to whitelist this app from battery optimisation.
    /// Returns a [PromptResult] so the caller can render appropriate
    /// feedback — tapping the chip with no visible result was the
    /// original complaint.
    fun requestExemption(activity: Activity): PromptResult {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return PromptResult.NotSupportedOnThisWatch
        }
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        if (direct.resolveActivity(activity.packageManager) != null) {
            return try {
                activity.startActivity(direct)
                PromptResult.LaunchedSystemPrompt
            } catch (_: Throwable) {
                PromptResult.Failed
            }
        }
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (fallback.resolveActivity(activity.packageManager) != null) {
            return try {
                activity.startActivity(fallback)
                PromptResult.LaunchedSystemPrompt
            } catch (_: Throwable) {
                PromptResult.Failed
            }
        }
        return PromptResult.NotSupportedOnThisWatch
    }
}
