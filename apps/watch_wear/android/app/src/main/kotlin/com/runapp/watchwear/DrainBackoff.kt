package com.runapp.watchwear

import kotlin.math.min

/// Exponential backoff window for `RunViewModel.drainQueue`.
///
/// Mirrors the shape of `apps/mobile_android/lib/sync_service.dart` so
/// every client that retries a queue drain throttles upstream the same
/// way: 60 s after the first failure, doubling each consecutive failure,
/// capped at 30 min. User-initiated drains (`sync()`, post-stop,
/// post-recovery, post-sign-in) bypass the window via `force = true`;
/// automatic triggers (network availability, auth bootstrap) respect it.
///
/// Pure logic by design — `nowMs` is injectable so unit tests don't
/// have to wait. The ViewModel holds a single instance and feeds it
/// success/failure events at the end of each drain cycle.
class DrainBackoff(
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val baseMs: Long = 60_000L,
    private val maxMs: Long = 30 * 60_000L,
) {
    var consecutiveFailures: Int = 0
        private set
    var lastFailureAtMs: Long = 0L
        private set

    fun currentBackoffMs(): Long {
        if (consecutiveFailures == 0) return 0L
        val shift = min(consecutiveFailures - 1, 20)
        return min(baseMs shl shift, maxMs)
    }

    fun isInBackoff(): Boolean {
        if (consecutiveFailures == 0) return false
        return nowMs() < lastFailureAtMs + currentBackoffMs()
    }

    fun onSuccess() {
        consecutiveFailures = 0
        lastFailureAtMs = 0L
    }

    fun onFailure() {
        consecutiveFailures += 1
        lastFailureAtMs = nowMs()
    }
}
