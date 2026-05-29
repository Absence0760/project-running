package com.runapp.watchwear.system

/// Pure decision for how to steer the user toward whitelisting the app
/// from battery optimisation (persona #35).
///
/// On Samsung One UI Watch the system
/// `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` intent *resolves* but is
/// effectively a no-op — the real toggle lives in the paired Galaxy
/// Wearable app, not in the watch's own settings. Offering an "auto-open"
/// button that silently does nothing is the original complaint. So on
/// Samsung we lead with the manual Galaxy Wearable path and suppress the
/// dead auto-open affordance; everywhere else the system prompt works and
/// stays the primary action.
enum class BatteryFixStrategy {
    /// Stock Wear OS — the system whitelist prompt works; offer it.
    SystemPrompt,

    /// Samsung One UI Watch — the auto-open is a no-op; show the Galaxy
    /// Wearable manual steps as the primary (and only) path.
    SamsungManualGuidance,
}

/// True for Samsung's One UI Watch. `Build.MANUFACTURER` reports
/// `"samsung"` (case varies by device) on Galaxy Watch 4+ running Wear
/// OS / One UI Watch.
internal fun isSamsungOneUiWatch(manufacturer: String?): Boolean {
    val m = manufacturer?.trim()?.lowercase() ?: return false
    return m == "samsung"
}

internal fun batteryFixStrategy(manufacturer: String?): BatteryFixStrategy =
    if (isSamsungOneUiWatch(manufacturer)) {
        BatteryFixStrategy.SamsungManualGuidance
    } else {
        BatteryFixStrategy.SystemPrompt
    }
