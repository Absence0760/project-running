package com.runapp.watchwear.system

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/// Route to this app's own permission screen, for the runner who declined
/// a permission once too often for the system to keep prompting.
///
/// `ACTION_APPLICATION_DETAILS_SETTINGS` is not universal on Wear OS —
/// some builds ship no per-app settings activity at all — so the caller
/// asks [canOpen] first and hides the affordance rather than offering a
/// chip that does nothing. Same shape, and the same reason, as
/// `BatteryOptimization.requestExemption`.
object AppSettings {

    private fun intentFor(activity: Activity): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }

    fun canOpen(activity: Activity): Boolean =
        runCatching {
            intentFor(activity).resolveActivity(activity.packageManager) != null
        }.getOrDefault(false)

    /// Returns false when nothing was launched, so a caller that showed
    /// the chip on a stale [canOpen] still has something to say.
    fun open(activity: Activity): Boolean = runCatching {
        activity.startActivity(intentFor(activity))
        true
    }.getOrDefault(false)
}
