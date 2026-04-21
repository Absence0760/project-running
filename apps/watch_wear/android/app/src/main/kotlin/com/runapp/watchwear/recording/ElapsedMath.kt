package com.runapp.watchwear.recording

/// Pure active-elapsed-time computation, factored out of
/// `RunRecordingService.activeElapsedMs()` so it's directly unit-testable.
///
/// - `nowMs`: caller's current clock reading (System.currentTimeMillis()).
/// - `startedAtMs`: wall-clock time recording started.
/// - `pausedAccumulatedMs`: sum of all complete pause intervals.
/// - `pausedSinceMs`: start of the *current* pause interval; 0 when
///   not paused.
///
/// Returns non-negative elapsed milliseconds, excluding pause intervals.
/// Over a 10-hour ultra with a dozen aid-station pauses, this is the
/// function every finish time depends on.
fun activeElapsedMs(
    nowMs: Long,
    startedAtMs: Long,
    pausedAccumulatedMs: Long,
    pausedSinceMs: Long,
): Long {
    val total = nowMs - startedAtMs
    val currentPauseMs = if (pausedSinceMs > 0) nowMs - pausedSinceMs else 0
    val active = total - pausedAccumulatedMs - currentPauseMs
    return if (active < 0) 0 else active
}
