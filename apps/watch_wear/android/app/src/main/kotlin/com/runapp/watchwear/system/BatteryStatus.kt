package com.runapp.watchwear.system

import android.content.Context
import android.os.BatteryManager

/// Point-in-time battery level, used to warn the user before they start
/// an ultra-length run on a half-drained watch. This is the single most
/// common cause of a lost 10-hour effort — the user didn't notice the
/// watch was at 30% when they hit Start.
///
/// `percent` returns null when the platform refuses to answer (older
/// emulators, missing permissions); callers should treat that as
/// "unknown, don't block the start".
object BatteryStatus {
    const val LOW_THRESHOLD_PERCENT = 40

    fun percent(context: Context): Int? {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            ?: return null
        val raw = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (raw in 0..100) raw else null
    }

    fun isLow(context: Context): Boolean {
        val p = percent(context) ?: return false
        return p < LOW_THRESHOLD_PERCENT
    }
}
