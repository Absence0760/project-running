package com.runapp.watchwear.recording

/// Pure string-formatting helpers for the watch's TTS announcements.
///
/// Extracted from [TtsAnnouncer] (which is tied to Android's
/// `TextToSpeech` engine) so the phrasing — the user-audible string —
/// can be unit-tested without the platform dependency.
///
/// Same wording as `apps/mobile_android/lib/audio_cues.dart` so a
/// runner carrying both devices hears the same cues from each. Pinning
/// the strings in source means a future copy-edit can't accidentally
/// diverge the dialect across platforms.

/// "Pace 5 minutes 30 seconds per kilometre" — the conventional tail
/// appended to split announcements. Returns the empty string when
/// pace is unknown or non-positive so callers can append it
/// unconditionally without producing a "Pace 0 minutes 0 seconds"
/// awkward read-out.
internal fun formatPaceTail(secondsPerKm: Double?): String {
    if (secondsPerKm == null || secondsPerKm <= 0) return ""
    val m = (secondsPerKm / 60).toInt()
    val s = (secondsPerKm % 60).toInt()
    return "Pace $m minutes $s seconds per kilometre"
}

/// "1 kilometre. Pace 5 minutes 30 seconds per kilometre" / "2
/// kilometres. ...". The singular / plural switch matters because
/// English TTS engines mispronounce the wrong form for the count
/// distinctly enough that the runner notices.
internal fun formatSplitPhrase(km: Int, paceSecPerKm: Double?): String {
    val unitWord = if (km == 1) "kilometre" else "kilometres"
    val paceTail = formatPaceTail(paceSecPerKm)
    return "$km $unitWord. $paceTail"
}

/// "Run complete. 5.32 kilometres in 27 minutes." — final summary
/// spoken when the runner taps Stop. Distance is shown to two
/// decimal places; minutes truncate (no half-minute rounding —
/// "27 minutes" reads cleaner than "27.5 minutes").
internal fun formatFinishPhrase(distanceM: Double, durationS: Int): String {
    val km = distanceM / 1000.0
    val mins = durationS / 60
    return "Run complete. %.2f kilometres in %d minutes.".format(km, mins)
}

/// Pace-drift cue — short and distinct so a runner can recognise the
/// direction without listening to a full sentence. The haptic
/// pattern (single vs double pulse) gives the direction redundantly.
internal fun formatPaceAlert(tooSlow: Boolean): String =
    if (tooSlow) "Pick up the pace" else "Slow down"

/// "Run started" — the announcement at the end of the 3-2-1
/// countdown when recording actually begins. Pinned so a future
/// refactor doesn't drift it to "Recording started" or similar
/// (the runner's muscle memory associates the exact words).
internal const val RUN_STARTED_PHRASE = "Run started"
