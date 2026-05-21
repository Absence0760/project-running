package com.runapp.watchwear

/// Pure orchestration of the offline-runs drain loop. Extracted from
/// `RunViewModel.drainQueue` so the loop semantics — per-classification
/// `DrainAction` handling, the one-shot 401 refresh-then-retry, the
/// transient-vs-permanent split that drives backoff — can be unit-tested
/// in isolation without booting a `SupabaseClient`, a `LocalRunStore`,
/// or the full ViewModel.
///
/// The runner is stateless. Callers pass:
///   - the snapshot of queued runs to drain
///   - a `push` lambda (typically wrapping `SupabaseClient.saveRun`)
///   - a `refresh` lambda (typically `SupabaseClient.refreshAccessToken`
///     plus a write to `SessionStore`); returns `true` on success
///   - an `onSuccess` lambda to remove a successfully-uploaded id from
///     the persistent queue
///   - the `classify` strategy (defaults to the production
///     [classifyDrainError]; tests inject deterministic mappings)
///
/// And get back a [DrainQueueLoopResult] capturing:
///   - the ids that were removed from the queue this pass (combination
///     of full successes and 409-style idempotent drops)
///   - whether any transient failure occurred (drives the
///     `DrainBackoff.onFailure` / `onSuccess` decision in the caller)
///   - the last error message (used as the UI's `syncError` banner)
///
/// The loop short-circuits on the first transient failure so a
/// down-network state can't hammer the backend with every run in the
/// queue. Permanent failures (`SkipAndContinue`) keep iterating
/// because retrying them would just re-skip — the queue entry is
/// stuck and the user can clear it manually.

data class DrainQueueLoopResult(
    /// Run ids removed from the persistent queue this pass — either
    /// a fresh upload (200) or an idempotent 409 (already in DB).
    val drainedIds: List<String>,
    /// True iff at least one classification was `StopAndRetryLater`
    /// or `RetryAfterRefresh` followed by another transient failure.
    /// Caller arms backoff when set.
    val anyTransientFailure: Boolean,
    /// Last user-readable error message — sticks on the UI as
    /// `syncError` until the next success clears it.
    val lastError: String?,
)

/// Test seam: lets a fake mock the SupabaseClient.saveRun call.
fun interface PushQueuedRun {
    suspend operator fun invoke(run: QueuedRun)
}

/// Test seam: lets a fake mock the refresh-token-then-save path.
/// Returns true on success — caller retries the failing run; returns
/// false on refresh failure — caller stops + arms backoff.
fun interface RefreshAuthForDrain {
    suspend operator fun invoke(): Boolean
}

/// Test seam matching `LocalRunStore.remove` — suspend so the live
/// implementation (DataStore-backed disk write) can await without
/// blocking the loop on the calling thread.
fun interface OnSuccessfulDrain {
    suspend operator fun invoke(runId: String)
}

internal suspend fun drainQueueLoop(
    snapshot: List<QueuedRun>,
    push: PushQueuedRun,
    refresh: RefreshAuthForDrain,
    onSuccessfulDrain: OnSuccessfulDrain,
    classify: (Throwable) -> DrainAction = ::classifyDrainError,
): DrainQueueLoopResult {
    val drained = mutableListOf<String>()
    var anyTransientFailure = false
    var lastError: String? = null

    for (run in snapshot) {
        try {
            push(run)
            onSuccessfulDrain.invoke(run.id)
            drained += run.id
            lastError = null
        } catch (e: Throwable) {
            lastError = e.message ?: e.javaClass.simpleName
            when (classify(e)) {
                DrainAction.RetryAfterRefresh -> {
                    // One-shot refresh-then-retry. If refresh fails OR
                    // the retry itself fails, stop the loop and arm
                    // backoff — the next drain trigger (network flap,
                    // manual sync) will retry from this run forward.
                    val refreshed = try {
                        refresh()
                    } catch (inner: Throwable) {
                        lastError = inner.message ?: lastError
                        false
                    }
                    if (!refreshed) {
                        anyTransientFailure = true
                        break
                    }
                    try {
                        push(run)
                        onSuccessfulDrain.invoke(run.id)
                        drained += run.id
                        lastError = null
                    } catch (inner: Throwable) {
                        lastError = inner.message ?: lastError
                        anyTransientFailure = true
                        break
                    }
                }
                DrainAction.DropAndContinue -> {
                    // 409: already in the DB. Removing is the correct
                    // outcome — the upload was effectively idempotent.
                    onSuccessfulDrain.invoke(run.id)
                    drained += run.id
                    lastError = null
                }
                DrainAction.StopAndRetryLater -> {
                    // Transient (timeout / 5xx / network drop). Stop
                    // iterating so we don't hammer the backend, keep
                    // the queue intact for the next drain trigger,
                    // and arm backoff.
                    anyTransientFailure = true
                    break
                }
                DrainAction.SkipAndContinue -> {
                    // Permanent (400/404/422 / unknown). Move on to
                    // the next run — retrying would just re-skip. The
                    // run stays in the queue until the user manually
                    // discards it from the UI.
                }
            }
        }
    }
    return DrainQueueLoopResult(
        drainedIds = drained,
        anyTransientFailure = anyTransientFailure,
        lastError = lastError,
    )
}
