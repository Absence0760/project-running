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
///   - the ids that were removed from the queue this pass (the runs that
///     uploaded successfully)
///   - whether any transient failure occurred (drives the
///     `DrainBackoff.onFailure` / `onSuccess` decision in the caller)
///   - the last error message (used as the UI's `syncError` banner)
///
/// The loop short-circuits on the first transient failure so a
/// down-network state can't hammer the backend with every run in the
/// queue. Permanent failures (`SkipAndContinue`) keep iterating
/// because retrying them would just re-skip — the queue entry is
/// stuck, and [rejectedIds] is what carries that fact out to a surface
/// the runner can act on (decisions § 1347).

data class DrainQueueLoopResult(
    /// Run ids removed from the persistent queue this pass — the runs
    /// whose upload succeeded (200).
    val drainedIds: List<String>,
    /// Run ids the server permanently REFUSED this pass (`SkipAndContinue`
    /// — 400/404/409/422 and unknown). They are still in the queue and no
    /// retry will ever move them.
    ///
    /// Separate from [lastError] rather than folded into it, because the two
    /// have different lifetimes on purpose. `lastError` is the transient
    /// banner and a later success in the same pass clears it — a decision
    /// `DrainQueueLoopTest` states twice and this does not reverse. A
    /// permanent rejection is not a banner: it is a standing fact about a
    /// queue entry that outlives every later success, and folding it into a
    /// field designed to be cleared is exactly how "Sync" reported success
    /// on every tap while the queue count never fell.
    val rejectedIds: List<String>,
    /// Every run whose upload was ATTEMPTED this pass, in order.
    ///
    /// The loop breaks on the first transient failure, so this is a prefix of
    /// the snapshot and the runs after it were not judged at all. A caller
    /// carrying [rejectedIds] across passes needs to know which entries this
    /// pass has an opinion about: one it never reached must keep the verdict
    /// of the last pass that did reach it, and one it reached and did not
    /// reject must lose an older rejection rather than keep it.
    val attemptedIds: List<String>,
    /// True iff at least one classification was `StopAndRetryLater`
    /// or `RetryAfterRefresh` followed by another transient failure.
    /// Caller arms backoff when set.
    val anyTransientFailure: Boolean,
    /// Last user-readable error message — sticks on the UI as
    /// `syncError` until the next success clears it.
    val lastError: String?,
)

/// Fold one pass's verdicts into the set of queue entries known to be
/// permanently rejected.
///
/// Pure so it can be tested: the state it maintains lives on `RunViewModel`,
/// which needs an Android runtime to construct.
///
/// Three rules, and each exists for a case the other two get wrong:
///   - a run this pass ATTEMPTED takes this pass's verdict, so a rejection
///     that has since become a success or a transient stops being claimed;
///   - a run this pass never reached keeps the verdict it already had, so a
///     server that goes down before the loop reaches the stuck entry does not
///     take the only notice of it off the screen;
///   - anything no longer in the queue is dropped, so a drained or discarded
///     run cannot leave a rejection behind for an id that no longer exists.
internal fun rejectedAfterPass(
    previouslyRejected: Set<String>,
    queuedIdsBeforePass: List<String>,
    result: DrainQueueLoopResult,
): Set<String> {
    val stillQueued = queuedIdsBeforePass.toSet() - result.drainedIds.toSet()
    val carried = previouslyRejected - result.attemptedIds.toSet()
    return (carried + result.rejectedIds).intersect(stillQueued)
}

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
    val rejected = mutableListOf<String>()
    val attempted = mutableListOf<String>()
    var anyTransientFailure = false
    var lastError: String? = null

    for (run in snapshot) {
        attempted += run.id
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
                DrainAction.StopAndRetryLater -> {
                    // Transient (timeout / 5xx / network drop). Stop
                    // iterating so we don't hammer the backend, keep
                    // the queue intact for the next drain trigger,
                    // and arm backoff.
                    anyTransientFailure = true
                    break
                }
                DrainAction.SkipAndContinue -> {
                    // Permanent (400/404/409/422 / unknown). Move on to
                    // the next run — retrying would just re-skip. The run
                    // stays in the queue, and recording it here is what
                    // gives the PreRun chip something to say about it: the
                    // loop's own comment used to point at a manual discard
                    // that only ever existed on the screen the runner had
                    // just left (decisions § 1347).
                    rejected += run.id
                }
            }
        }
    }
    return DrainQueueLoopResult(
        drainedIds = drained,
        rejectedIds = rejected,
        attemptedIds = attempted,
        anyTransientFailure = anyTransientFailure,
        lastError = lastError,
    )
}
