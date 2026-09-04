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

/// Delay before re-subscribing to the DataStore-backed run queue after a read
/// failed, doubling per consecutive attempt from 1 s to a 60 s ceiling.
///
/// A different curve from [DrainBackoff] because it throttles a different cost.
/// The drain reaches the network and a third party, so it waits a minute and
/// settles at half an hour. This is a local file open costing microseconds, and
/// what its failure takes off screen is the only affordance that can recover
/// it — so the first retry is immediate enough to ride out a transient I/O blip
/// unnoticed, and a file that is genuinely corrupt costs one failed open a
/// minute for the life of the process.
///
/// [attempt] is the count of retries already made, as `Flow.retryWhen` supplies
/// it. Shifted by at most 20 so a stream that has been failing for days cannot
/// overflow the shift.
internal fun queueReadRetryDelayMs(attempt: Long): Long {
    val shift = min(attempt, 20L).toInt()
    return min(QUEUE_READ_RETRY_BASE_MS shl shift, QUEUE_READ_RETRY_MAX_MS)
}

private const val QUEUE_READ_RETRY_BASE_MS = 1_000L
private const val QUEUE_READ_RETRY_MAX_MS = 60_000L
