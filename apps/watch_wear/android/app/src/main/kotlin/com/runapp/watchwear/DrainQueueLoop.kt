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
///     plus a write to `SessionStore`); returns `true` on success and
///     THROWS on failure, so the reason reaches [report] rather than
///     being flattened into a bare `false`
///   - an `onSuccess` lambda to remove a successfully-uploaded id from
///     the persistent queue
///   - a `report` sink every failure is handed to as it happens
///   - the `classify` strategy (defaults to the production
///     [classifyDrainError]; tests inject deterministic mappings)
///
/// And get back a [DrainQueueLoopResult] capturing:
///   - the ids that were removed from the queue this pass (the runs that
///     uploaded successfully)
///   - whether any transient failure occurred (drives the
///     `DrainBackoff.onFailure` / `onSuccess` decision in the caller)
///   - the classified fault the wrist states
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
    /// Separate from [lastFault] rather than folded into it, because the two
    /// have different lifetimes on purpose. `lastFault` is the transient
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
    /// The fault that STOPPED this pass, or null if the loop reached the end
    /// of the snapshot.
    ///
    /// A fault rather than a flag, because the two questions a caller asks of
    /// a stopped pass have different answers: backoff wants to know THAT it
    /// stopped, and the PreRun arc wants to know ON WHAT — a 5xx the runner
    /// retries and a session the server will not renew are the same boolean
    /// and different sentences (decisions § 1544). Deriving the second from
    /// [lastFault] at the call site would work only because every stop breaks
    /// immediately, which is an invariant of this loop that nothing outside it
    /// could see.
    ///
    /// Distinct from [lastFault], which is the banner: that one is cleared by
    /// a trailing success and set by a permanent rejection the loop then
    /// carries on past. This one is set only where the pass ends.
    val blockedBy: SyncFault?,
    /// The fault the wrist states — sticks on the UI as `syncFault` until the
    /// next success clears it.
    ///
    /// A classification rather than the throwable's own message, because the
    /// message is English, technical and unbounded, and this is the only
    /// user-facing string on the watch that never went through a catalogue
    /// (decisions § 1490). The raw text is not lost: it goes to [report].
    val lastFault: SyncFault?,
) {
    /// Backoff's own question, answered off [blockedBy] so the two can never
    /// disagree about whether the pass got through.
    val anyTransientFailure: Boolean get() = blockedBy != null
}

/// One failed upload attempt, as the log needs it.
data class DrainFailure(
    val runId: String,
    val fault: SyncFault,
    val error: Throwable,
)

/// Where every failure goes, as it happens.
///
/// Required rather than defaulted, and a seam rather than a field on
/// [DrainQueueLoopResult], because the raw throwable is the only diagnostic a
/// wrist ever produces now that the runner is told a catalogued fault instead
/// (decisions § 1490) — and a list on the result is something a caller can
/// simply stop reading. It was: nothing held `drainQueueLocked` to iterating
/// it, so the whole diagnostic could be refactored away with every test still
/// green. A parameter with no default cannot be dropped in silence.
///
/// Reported as the pass runs rather than collected and handed back, so a queue
/// that fails fifty entries logs fifty times rather than buffering them behind
/// a return that a `break` might make late.
fun interface DrainFailureReport {
    operator fun invoke(failure: DrainFailure)
}

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
/// false, or throws, on refresh failure — caller stops + arms backoff.
///
/// Throwing is the production shape and a bare `false` is the poorer one:
/// the loop hands whatever comes out of here to [DrainFailureReport], and a
/// `false` carries no throwable to hand over. The live lambda used to catch
/// and discard its own error before returning, which left the one failure on
/// this path — a session the server would not renew — with no diagnostic at
/// all.
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
    report: DrainFailureReport,
    classify: (Throwable) -> DrainAction = ::classifyDrainError,
): DrainQueueLoopResult {
    val drained = mutableListOf<String>()
    val rejected = mutableListOf<String>()
    val attempted = mutableListOf<String>()
    var blockedBy: SyncFault? = null
    var lastFault: SyncFault? = null

    fun record(runId: String, fault: SyncFault, error: Throwable) {
        try {
            report(DrainFailure(runId, fault, error))
        } catch (_: Throwable) {
            // Nowhere left to say it: the sink that just threw IS where this
            // pass's failures are said. The drain carries the runner's only
            // copy of the run, so a diagnostic must not be what ends it.
        }
    }

    for (run in snapshot) {
        attempted += run.id
        try {
            push(run)
            onSuccessfulDrain.invoke(run.id)
            drained += run.id
            lastFault = null
        } catch (e: Throwable) {
            lastFault = syncFaultFor(e)
            record(run.id, lastFault, e)
            when (classify(e)) {
                DrainAction.RetryAfterRefresh -> {
                    // One-shot refresh-then-retry. A refresh that fails stops
                    // the loop and arms backoff — the next drain trigger
                    // (network flap, manual sync) retries from this run
                    // forward. A retry that fails is judged like any other
                    // attempt: the refresh has already spent its one shot, so
                    // what remains is the same three-way verdict the outer
                    // `when` acts on.
                    val refreshFault: SyncFault? = try {
                        if (refresh()) {
                            null
                        } else {
                            // No throwable, so nothing to classify: a refresh
                            // that reported failure without saying why leaves
                            // the 401's own verdict standing.
                            SyncFault.SignInRequired
                        }
                    } catch (inner: Throwable) {
                        // The refresh's OWN error, not the 401 that provoked
                        // it. The 401 proves the server answered moments
                        // earlier, so a refresh that dies on a dropped socket
                        // or a `SessionStore` write that throws is not a
                        // session the server refused to renew — and since
                        // § 1544 that is an affordance, not a caption: the arc
                        // offers a sign-in for `SignInRequired` and would cost
                        // the runner a password they did not need to retype.
                        val fault = syncFaultForRefresh(inner)
                        record(run.id, fault, inner)
                        fault
                    }
                    if (refreshFault != null) {
                        lastFault = refreshFault
                        blockedBy = refreshFault
                        break
                    }
                    try {
                        push(run)
                        onSuccessfulDrain.invoke(run.id)
                        drained += run.id
                        lastFault = null
                    } catch (inner: Throwable) {
                        // The retry's OWN fault, not the 401 that provoked it:
                        // the refresh worked, so telling the runner to sign in
                        // again names the one thing that has just succeeded.
                        lastFault = syncFaultFor(inner)
                        record(run.id, lastFault, inner)
                        // And the retry's own VERDICT, for the same reason the
                        // fault is its own. This branch used to break on every
                        // failure, so a 400/404/409/422 here left the entry
                        // queued, armed backoff as though it were transient,
                        // and put the arc on `RetryQueued` for a run no retry
                        // will ever move — the exact state § 1347 built
                        // `rejectedIds` and the two-press discard chip to
                        // escape, reached through the one branch that bypassed
                        // them.
                        when (classify(inner)) {
                            // A refusal is not a stop: the queue's later
                            // entries may be perfectly acceptable, and the
                            // permanent verdict is what the chip acts on.
                            DrainAction.SkipAndContinue -> rejected += run.id
                            // A second 401 with a token minted seconds ago is
                            // not a refresh this loop may repeat — the
                            // one-shot contract is what keeps a rejecting
                            // server from being asked twice per run — so it
                            // stops the pass exactly as a transient does.
                            DrainAction.RetryAfterRefresh,
                            DrainAction.StopAndRetryLater -> {
                                blockedBy = lastFault
                                break
                            }
                        }
                    }
                }
                DrainAction.StopAndRetryLater -> {
                    // Transient (timeout / 5xx / network drop). Stop
                    // iterating so we don't hammer the backend, keep
                    // the queue intact for the next drain trigger,
                    // and arm backoff.
                    blockedBy = lastFault
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
        blockedBy = blockedBy,
        lastFault = lastFault,
    )
}
