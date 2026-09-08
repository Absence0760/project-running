package com.runapp.watchwear.ui

import com.runapp.watchwear.SyncFault

/// Which of the PreRun top arc's mutually exclusive status slots renders.
///
/// The arc has room for one line above the Start button, and six different
/// facts compete for it — a queue that could not be read, entries the server
/// has permanently refused, a queue waiting to drain, a drain that stopped on
/// a fault the runner retries, a drain that stopped on a session the server
/// will not renew, and no network at all. They arrived one at a time
/// (§ 1104, § 1347, § 1390, § 1544) as arms of one `if`/`else` chain in the
/// composable, where the precedence between them was expressible only as the
/// order of the source lines and assertable only by reading those lines back.
/// Three separate test files did exactly that, in three different ways, and
/// none of them could evaluate the decision for a given state.
///
/// So the decision lives here instead and the composable is a `when` over the
/// result. [SyncChipStateTest] runs the whole 96-tuple state space through it.
enum class SyncChipState {
    /// The queue read failed. The retry chip, stating no count it cannot
    /// support (§ 1104).
    Unreadable,

    /// The server has permanently refused at least one queued entry. The
    /// two-press discard chip (§ 1347).
    Rejected,

    /// Runs are queued and the last completed pass stopped on a fault another
    /// attempt can clear. The counted chip, relabelled to name the retry
    /// (§ 1390).
    RetryQueued,

    /// Runs are queued and the last completed pass stopped on a 401 the
    /// refresh could not repair. The sign-in chip (§ 1544).
    ///
    /// The one stop whose remedy is not another attempt: every tap on `Retry`
    /// re-runs the same drain, 401s again, and fails the same refresh. It
    /// takes the counted chip's slot rather than relabelling it, because
    /// unlike a transient the drain is no longer the useful affordance here —
    /// signing in is, and the drain that follows it is automatic.
    SignInRequired,

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
    syncBlockedBy: SyncFault?,
    online: Boolean,
    authed: Boolean,
): SyncChipState = when {
    // The count is known wrong, so every claim below it is a claim about a
    // stale figure.
    queueUnreadable && authed -> SyncChipState.Unreadable
    // The count is right and the sentence around it is not: `Sync N` offers a
    // drain that reports success on every tap while N never falls.
    rejectedCount > 0 && authed -> SyncChipState.Rejected
    // A queue that can be acted on: which of the three the chip becomes turns
    // on what stopped the last pass. Conjoined with `online` and `authed`
    // because without either the chip is already disabled, and a dimmed
    // control reading "Retry" — or offering a sign-in — invites a tap that
    // cannot fire.
    queuedCount > 0 && online && authed -> when (syncBlockedBy) {
        // Nothing known to be wrong.
        null -> SyncChipState.Queued
        // Sync is still the useful affordance during a fault another attempt
        // can clear, so it relabels the chip rather than taking its slot.
        // The exception is the one fault no attempt can clear.
        SyncFault.SignInRequired -> SyncChipState.SignInRequired
        else -> SyncChipState.RetryQueued
    }
    queuedCount > 0 -> SyncChipState.Queued
    !online && authed -> SyncChipState.Offline
    else -> SyncChipState.Silent
}
