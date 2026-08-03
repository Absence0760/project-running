package com.runapp.watchwear.recording

/// Pure decomposition helpers for the watch's TTS announcements.
///
/// The user-audible wording lives in `res/values*/strings.xml` (same dialect
/// as `apps/mobile_android/lib/l10n/app_*.arb`, so a runner carrying both
/// devices hears the same cues from each) and is assembled by [TtsAnnouncer]
/// via the active locale's resources. These helpers only carry the
/// platform-independent numeric decomposition — splitting a seconds-per-km
/// value into integer minutes + seconds — so the truncation contract is
/// unit-testable without the Android resource layer.

/// Integer minutes + seconds (floor, not round-half-up) for a
/// seconds-per-km pace. Returns null when pace is unknown or non-positive,
/// so the split caller can omit the pace tail entirely rather than speak a
/// "0 minutes 0 seconds" awkward read-out.
internal fun paceMinSec(secondsPerKm: Double?): Pair<Int, Int>? {
    if (secondsPerKm == null || secondsPerKm <= 0) return null
    val m = (secondsPerKm / 60).toInt()
    val s = (secondsPerKm % 60).toInt()
    return m to s
}

/// [paceMinSec] for a runner on [unit]: the recorder's seconds-per-km is
/// scaled to the mile first, so a mi-mode runner hears the pace their face
/// already shows instead of the metric figure under a mile label.
internal fun paceMinSecFor(secondsPerKm: Double?, unit: DistanceUnit): Pair<Int, Int>? =
    paceMinSec(secondsPerKm?.let { paceSecPerUnit(it, unit) })

/// Whole minutes (floor) spoken for the run-complete summary. Matches the
/// phone's "27 minutes" read-out — no half-minute rounding.
internal fun finishMinutes(durationS: Int): Int = durationS / 60

/// Distance for the run-complete phrase in the runner's [unit], formatted
/// with a period decimal regardless of locale. The spoken distance must use
/// a period: a comma would be read aloud as the literal word "comma" by most
/// TTS engines.
internal fun finishDistanceSpoken(distanceM: Double, unit: DistanceUnit): String {
    val value = when (unit) {
        DistanceUnit.KM -> distanceM / 1000.0
        DistanceUnit.MI -> distanceM / METRES_PER_MILE
    }
    return "%.2f".format(java.util.Locale.US, value)
}
