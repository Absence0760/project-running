package com.runapp.watchwear.recording

import kotlin.math.round

/// The Wear OS half of watchOS's `HeartRateCoverage` / `HeartRateClaim`
/// (`apps/watch_ios/WatchApp/HealthKitManager.swift`). Not a registered parity
/// pair — the registries pair web with mobile, and the two watch clients are
/// additive surfaces under decisions § 24 — but both write the same
/// `runs.avg_bpm` and `runs.metadata.hr_coverage` on the same account, so the
/// two constants below have to mean the same thing on either wrist.
///
/// That much IS enforced: claim (12) of `scripts/check_watch_ios_source.mjs`
/// reads both files, converts the milliseconds-versus-seconds difference, and
/// fails the PR on a disagreement — or on a rename that leaves either figure
/// unreadable, because a rename is the edit most likely to take them apart
/// unobserved (decisions § 1348). The guard lives on the watchOS side because
/// that tier already has one; a change HERE is what it most often catches.

/// The share of a run's active time the wrist sensor must have been delivering
/// for the mean of its samples to be saved as THE RUN'S average heart rate.
///
/// Half, and the number is the sentence rather than a tuning knob: a mean taken
/// over less of the run than not is not the run's average, and `avg_bpm` is
/// read everywhere — run detail, the coach context, every client — as though it
/// were. `MeasureClient` is documented foreground-only (decisions § 1015), so on
/// a twelve-hour ultra the samples reaching `bpmSum` can be the minutes the
/// runner spent looking at the watch.
const val MIN_AVG_BPM_COVERAGE = 0.5

/// A sample older than this is not evidence that the sensor is delivering NOW.
///
/// Coverage is advanced on the recording ticker against the age of the last
/// usable sample, not by closing an interval on an availability event, because
/// the failure this exists to measure need not raise one: a client the platform
/// stops feeding in the background can go quiet without ever reporting
/// `UNAVAILABLE`, and an interval left open across that gap credits the whole
/// silence as covered — over-reporting exactly the runs the figure is about.
/// Thirty seconds is loose enough that a slow or batching sensor is not punished
/// and short enough that a suspension measured in minutes is not counted.
const val HR_SAMPLE_FRESH_MS = 30_000L

/// What a finished run may say about its heart rate.
data class HeartRateClaim(
    /// The mean of the samples, or null when there were none — or when there
    /// were, but over too little of the run to call it the run's average.
    val avgBpm: Double?,
    /// Fraction of active elapsed time the sensor was delivering, 0..1 to two
    /// decimals. Null when nothing measured it: heart rate was off for the
    /// build, or the run predates the measurement and is being recovered from a
    /// checkpoint that never carried it.
    val coverage: Double?,
)

/// Grade the rolling heart-rate pair against how much of the run it covered.
///
/// `hrAvailableMs` null is "unmeasured", NOT "zero" — the absence of a
/// measurement is no evidence of absent coverage, so the mean passes through
/// unqualified exactly as it did before coverage existed. That is what keeps a
/// checkpoint written by an older build recovering the run it would have.
///
/// The threshold is applied to the ROUNDED figure, which is the one that gets
/// stored: grading on the raw fraction lets a run persist a coverage of 0.5
/// beside a suppressed average, and a record that contradicts itself is worse
/// than either answer.
internal fun heartRateClaim(
    bpmSum: Long,
    bpmCount: Long,
    hrAvailableMs: Long?,
    activeElapsedMs: Long,
): HeartRateClaim {
    val mean = if (bpmCount <= 0L) null else bpmSum.toDouble() / bpmCount
    if (hrAvailableMs == null || activeElapsedMs <= 0L) return HeartRateClaim(mean, null)
    val raw = (hrAvailableMs.toDouble() / activeElapsedMs).coerceIn(0.0, 1.0)
    val coverage = round(raw * 100.0) / 100.0
    return HeartRateClaim(
        avgBpm = if (coverage >= MIN_AVG_BPM_COVERAGE) mean else null,
        coverage = coverage,
    )
}
