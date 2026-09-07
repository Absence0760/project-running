package com.runapp.watchwear

/// What the PostRun `×` managed to do, so the caller knows what to say and
/// still knows to advance.
sealed class DiscardOutcome {
    /// The queue entry and its track file are gone.
    data object Dropped : DiscardOutcome()

    /// There was nothing to drop. `thisRunId` names a run the queue no longer
    /// holds — an already-synced one, whose entry and file the drain dropped
    /// together when it uploaded — or no run at all. Not a failure: there is
    /// no file left to delete (§ 1388).
    data object NothingQueued : DiscardOutcome()

    /// The queue could not be read, or the removal could not be written. The
    /// run is still queued and will drain later, which is the safe direction
    /// for a destructive action that did not happen — but the runner asked for
    /// it to be gone and it is not, so somebody has to say so.
    data class Failed(val error: Throwable) : DiscardOutcome()
}

/// The PostRun discard, as the ordered decision it is.
///
/// Extracted from `RunViewModel.discard` for the reason `drainQueueLoop` was
/// extracted from `drainQueue`: the method needs an Android runtime, so the one
/// thing that matters about it could not be exercised at all. And that one
/// thing was wrong — the whole body ran under `launchGuarded`, whose handler
/// only logs, so a DataStore fault aborted the coroutine before the stage
/// advanced and left the runner on PostRun with a confirm they had already
/// given and no visible result (decisions § 1491).
///
/// The advance is the caller's, deliberately: this returns what happened and
/// never decides whether to move, so the caller cannot express "advance only on
/// success" without saying so in the branch where a reader would look for it.
internal suspend fun discardRun(
    runId: String?,
    drop: suspend (String) -> Unit,
): DiscardOutcome {
    if (runId == null) return DiscardOutcome.NothingQueued
    return try {
        drop(runId)
        DiscardOutcome.Dropped
    } catch (e: Throwable) {
        DiscardOutcome.Failed(e)
    }
}
