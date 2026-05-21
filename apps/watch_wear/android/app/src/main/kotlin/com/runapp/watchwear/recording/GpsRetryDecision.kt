package com.runapp.watchwear.recording

/// "Should I re-subscribe the GPS source?" — pure decision lifted
/// from `RunRecordingService.gpsRetryJob` so the two trigger paths
/// (dead subscription / mid-run silence) can be unit-tested.
///
/// Why this matters: `FusedLocationProviderClient` on Wear OS can
/// keep a callback registered while silently emitting nothing —
/// Geolocator's stream-error surface that we rely on for self-heal
/// on the phone doesn't fire. Without the mid-run-silence trigger,
/// a runner would lose distance + pace for an indeterminate window
/// and only notice on Stop.
///
/// Pre-conditions checked by the caller (not the decision):
///   - the recording is in `Stage.Recording` (not idle / paused /
///     recovering — we don't resubscribe on those)
///   - `lastPointAtMs` is the wall-clock time of the latest GPS
///     emission, or 0 if no fix has landed yet
///
/// Two trigger conditions, EITHER fires a resubscribe:
///   1. Subscription is dead (`jobAlive == false`) — primary
///      trigger, matches Android's `_positionSub == null` shape.
///   2. Subscription is alive BUT we've been silent for longer
///      than [GPS_STALL_MS] AND we've had at least one fix already
///      (`lastPointAtMs > 0`). Initial no-fix is NOT a stall —
///      it's a legitimate indoor / cold-acquire state.

/// 30 second silence threshold. Tuned to ignore the normal 1–3 s
/// gap between samples but catch a stuck subscription within half
/// a minute — the runner gets pace updates restored before they've
/// completed a full kilometre.
internal const val GPS_STALL_MS = 30_000L

data class GpsRetryDecision(
    val shouldResubscribe: Boolean,
    /// True iff the resubscribe was triggered by mid-run silence
    /// (vs a dead subscription). Caller resets `lastPointAtMs =
    /// nowMs` on this branch to prevent thrashing if the fresh
    /// subscription also takes a few seconds to start emitting.
    val triggeredByStall: Boolean,
)

/// Decide whether the GPS subscription needs a kick. See file
/// kdoc for the trigger contract.
internal fun shouldResubscribeGps(
    jobAlive: Boolean,
    lastPointAtMs: Long,
    nowMs: Long,
): GpsRetryDecision {
    if (!jobAlive) {
        return GpsRetryDecision(shouldResubscribe = true, triggeredByStall = false)
    }
    val silentMidRun =
        lastPointAtMs > 0 && (nowMs - lastPointAtMs) > GPS_STALL_MS
    return GpsRetryDecision(
        shouldResubscribe = silentMidRun,
        triggeredByStall = silentMidRun,
    )
}
