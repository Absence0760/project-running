package com.runapp.watchwear

import androidx.annotation.StringRes

/// Why the last sync attempt did not get through, as something the wrist can
/// say in the runner's own language.
///
/// The field this rides on used to hold `e.message ?: e.javaClass.simpleName`
/// — the only user-facing string on this watch that never went through a
/// catalogue. A runner in any of the seven locales could be shown
/// `Unable to resolve host "…supabase.co"` or `SocketTimeoutException` on a
/// 1.4-inch display: English, technical, and unbounded in length where every
/// other caption on that screen is a `caption3` resource (decisions § 1490).
///
/// The vocabulary is the runner's next move, not the wire's status code. Two
/// faults are one member wherever the runner would do the same thing about
/// them, and separate members wherever they would not: [Offline] and
/// [ServerBusy] both clear themselves, but one is fixed by walking somewhere
/// with signal and the other by nothing at all.
enum class SyncFault {
    /// The queue file could not be read. Nothing was attempted and the count
    /// on screen may no longer stand (§ 1104).
    QueueUnreadable,

    /// The request never reached the server — DNS, a refused connection, a
    /// reset socket, a timeout. Transient: the drain arms backoff and retries.
    Offline,

    /// The server answered 5xx. Transient in the same way, and nothing the
    /// runner can do differently.
    ServerBusy,

    /// A 401 whose refresh did not succeed. The one fault whose remedy is an
    /// action on the wrist rather than waiting.
    SignInRequired,

    /// The server refused the run permanently — 400/404/409/422. No retry will
    /// move it; the queue entry stays and the PreRun discard chip is the exit
    /// (§ 1347).
    Refused,

    /// Something threw that none of the above describes. Deliberately its own
    /// member rather than folded into [Refused]: `classifyDrainError` treats an
    /// unrecognised throwable as permanent so the loop keeps going, but telling
    /// the runner the server refused their run is a claim about a server that
    /// may never have been reached.
    Unknown,
}

/// Classify a drain failure into what the runner is told about it.
///
/// Reads the same two discriminants `classifyDrainError` reads — the
/// [HttpException] status, then the transient markers in the message — because
/// a fault that says "will retry" while the loop treats the error as permanent
/// (or the reverse) is worse than either sentence alone. `SyncFaultTest` runs
/// both over one set of throwables and fails when they disagree.
internal fun syncFaultFor(e: Throwable): SyncFault = when (classifyDrainError(e)) {
    DrainAction.RetryAfterRefresh -> SyncFault.SignInRequired
    DrainAction.StopAndRetryLater ->
        if (e is HttpException) SyncFault.ServerBusy else SyncFault.Offline
    DrainAction.SkipAndContinue ->
        if (e is HttpException) SyncFault.Refused else SyncFault.Unknown
}

/// The caption the PostRun banner renders for a fault.
///
/// A `when` over the enum rather than a nullable lookup, so the compiler is
/// what makes the mapping total: a member added without a sentence to say does
/// not build. [SyncFaultTest] additionally pins that no two members share a
/// string, which is the way a classification quietly stops classifying.
@StringRes
fun syncFaultMessage(fault: SyncFault): Int = when (fault) {
    SyncFault.QueueUnreadable -> R.string.sync_queue_unreadable
    SyncFault.Offline -> R.string.sync_fault_offline
    SyncFault.ServerBusy -> R.string.sync_fault_server
    SyncFault.SignInRequired -> R.string.sync_fault_sign_in
    SyncFault.Refused -> R.string.sync_fault_refused
    SyncFault.Unknown -> R.string.sync_fault_unknown
}
