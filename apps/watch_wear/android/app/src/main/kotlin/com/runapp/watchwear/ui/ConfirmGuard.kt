package com.runapp.watchwear.ui

/// Seconds an armed destructive control waits for the press that commits it.
///
/// Five, and the number is doing two jobs at once: long enough that a runner
/// who meant it does not have to hurry on a wrist, short enough that an arm
/// left behind by a distraction is gone before they look again. Matches the
/// custom watch's own two-press windows (`ERASE_CONFIRM_WINDOW_S`,
/// decisions § 378) so one dwell is learned across the estate's watches.
const val CONFIRM_WINDOW_MS: Long = 5_000

/// What a press on a two-press destructive control produced.
enum class ConfirmPress {
    /// The guard armed. Nothing has happened yet; a second press inside
    /// [CONFIRM_WINDOW_MS] commits.
    Armed,

    /// A second press inside the window. Do the thing.
    Confirmed,
}

/// Grade a press on a control guarded by a two-press confirm.
///
/// `armedAtMs` is when the guard was armed, or null when it is not armed.
/// Everything that is not a live arm re-arms rather than commits: no arm, an
/// arm older than the window, and — deliberately — an arm stamped in the
/// reader's future, which is a clock that moved rather than a runner who
/// pressed twice. A destructive action must never be reachable in one press by
/// a device disagreeing with itself about the time.
fun confirmPress(
    armedAtMs: Long?,
    nowMs: Long,
    windowMs: Long = CONFIRM_WINDOW_MS,
): ConfirmPress {
    if (armedAtMs == null) return ConfirmPress.Armed
    val age = nowMs - armedAtMs
    return if (age in 0..windowMs) ConfirmPress.Confirmed else ConfirmPress.Armed
}
