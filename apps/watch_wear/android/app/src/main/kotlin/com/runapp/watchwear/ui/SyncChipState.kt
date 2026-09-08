package com.runapp.watchwear.ui

/// Which of the PreRun top arc's mutually exclusive status slots renders.
///
/// The arc has room for one line above the Start button, and five different
/// facts compete for it — a queue that could not be read, entries the server
/// has permanently refused, a queue waiting to drain, a drain that stopped on
/// a transient failure, and no network at all. They arrived one at a time
/// (§ 1104, § 1347, § 1390) as arms of one `if`/`else` chain in the
/// composable, where the precedence between them was expressible only as the
/// order of the source lines and assertable only by reading those lines back.
/// Three separate test files did exactly that, in three different ways, and
/// none of them could evaluate the decision for a given state.
///
/// So the decision lives here instead and the composable is a `when` over the
/// result. [SyncChipStateTest] runs the whole 64-tuple state space through it.
enum class SyncChipState {
    /// The queue read failed. The retry chip, stating no count it cannot
    /// support (§ 1104).
    Unreadable,

    /// The server has permanently refused at least one queued entry. The
    /// two-press discard chip (§ 1347).
    Rejected,

    /// Runs are queued and the last completed pass stopped on a transient
    /// failure. The counted chip, relabelled to name the retry (§ 1390).
    RetryQueued,

    /// Runs are queued and nothing is known to be wrong. The counted chip.
    Queued,

    /// Nothing queued and no network. The "Offline" caption.
    Offline,

    /// The arc says nothing.
    Silent,
}

/// Resolve the one slot the PreRun top arc renders.
///
/// The three `authed` conjunctions are not decoration. `drainQueue` returns
/// before reading anything without a session, so on a signed-out watch the
/// unreadable retry and the rejected discard are both affordances that cannot
/// fire, and the offline caption is the wrong sentence entirely — a runner who
/// has never signed in on the wrist is usually online, and the sign-in chip
/// immediately below is the thing they need. [queuedCount] carries no such
/// gate on purpose: a queue that survived a sign-out is a fact whether or not
/// there is a session to drain it with, and the chip disables itself.
fun syncChipState(
    queueUnreadable: Boolean,
    rejectedCount: Int,
    queuedCount: Int,
    syncFailed: Boolean,
    online: Boolean,
    authed: Boolean,
): SyncChipState = when {
    // The count is known wrong, so every claim below it is a claim about a
    // stale figure.
    queueUnreadable && authed -> SyncChipState.Unreadable
    // The count is right and the sentence around it is not: `Sync N` offers a
    // drain that reports success on every tap while N never falls.
    rejectedCount > 0 && authed -> SyncChipState.Rejected
    // Sync is still the useful affordance during a transient, so the failure
    // relabels this chip rather than taking its slot. Conjoined with `online`
    // because offline the chip is already disabled, and a dimmed control
    // reading "Retry" invites a tap that cannot fire.
    queuedCount > 0 ->
        if (syncFailed && online && authed) SyncChipState.RetryQueued else SyncChipState.Queued
    !online && authed -> SyncChipState.Offline
    else -> SyncChipState.Silent
}
