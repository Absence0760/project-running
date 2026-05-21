package com.runapp.watchwear.recording

/// Pure rate-limited pace-drift trigger. Extracted from
/// `RunRecordingService.onGps` so the contract — fire when current
/// pace drifts > 30 s/km from target AND we haven't fired in the
/// last 30 s — is unit-testable without booting a foreground
/// service.
///
/// The two thresholds are tuned for safety:
///   - 30 s/km drift = a meaningful "you're off pace" signal,
///     not noise from a single GPS jitter
///   - 30 s rate-limit = the runner gets at most one alert per
///     half-minute, so a wobbly pace can't strobe the haptic
///
/// Decision shape mirrors the call site: callers check `fire`,
/// branch on `tooSlow` for the haptic pattern, and overwrite
/// `lastPaceAlertAtMs` with `newLastAlertAtMs` on a fire.
data class PaceAlertDecision(
    val fire: Boolean,
    /// Meaningful only when `fire == true`. True when the runner is
    /// SLOWER than target (positive drift); false when faster.
    val tooSlow: Boolean,
    /// The mutated rate-limit timestamp the caller persists. Equal
    /// to the input `lastAlertAtMs` when `fire == false`.
    val newLastAlertAtMs: Long,
) {
    companion object {
        /// "No fire" outcome — preserves the rate-limit timestamp.
        fun noFire(lastAlertAtMs: Long) =
            PaceAlertDecision(fire = false, tooSlow = false, newLastAlertAtMs = lastAlertAtMs)
    }
}

/// Drift threshold in seconds-per-km. Tuned to ignore single-sample
/// GPS jitter while still catching meaningful pace drift on a
/// stabilised reading.
internal const val PACE_DRIFT_THRESHOLD_S_PER_KM = 30

/// Minimum interval between consecutive pace alerts. The user has 30
/// seconds to react to one alert before another fires — long enough
/// that a wobbly pace doesn't trigger a haptic strobe, short enough
/// that a runner who's stayed off-pace for a minute knows it.
internal const val PACE_ALERT_RATE_LIMIT_MS = 30_000L

/// Decide whether a pace-drift alert should fire and which direction.
///
/// Pre-conditions checked by callers before reaching this function
/// (kept out of the gate so the gate stays pure):
///   - target pace is set + positive (run has a target pace at all)
///   - current pace is computed (the stabilisation gate has been
///     met — `RunRecordingService` requires ≥50 m of distance)
///   - the runner isn't paused
///
/// Inside the gate we check:
///   - the absolute drift exceeds [PACE_DRIFT_THRESHOLD_S_PER_KM]
///   - the elapsed time since the last fire exceeds
///     [PACE_ALERT_RATE_LIMIT_MS]
///
/// Both must hold. Returns the decision; the caller is responsible
/// for the side effects (vibration, TTS, state write).
internal fun shouldFirePaceAlert(
    targetPaceSecPerKm: Int,
    currentPaceSecPerKm: Double,
    nowMs: Long,
    lastAlertAtMs: Long,
): PaceAlertDecision {
    val diff = currentPaceSecPerKm - targetPaceSecPerKm
    val driftExceeded = kotlin.math.abs(diff) > PACE_DRIFT_THRESHOLD_S_PER_KM
    val rateLimitCleared = nowMs - lastAlertAtMs > PACE_ALERT_RATE_LIMIT_MS
    return if (driftExceeded && rateLimitCleared) {
        PaceAlertDecision(
            fire = true,
            tooSlow = diff > 0,
            newLastAlertAtMs = nowMs,
        )
    } else {
        PaceAlertDecision.noFire(lastAlertAtMs)
    }
}
