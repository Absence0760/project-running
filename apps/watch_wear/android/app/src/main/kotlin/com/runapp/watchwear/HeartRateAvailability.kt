package com.runapp.watchwear

/// What the wrist's heart-rate sensor is currently doing, as far as the
/// recorder can tell.
///
/// `RecordingRepository.Metrics.bpm` alone cannot carry this: a null bpm
/// is four different situations — the runner declined BODY_SENSORS, the
/// watch has no optical sensor, Health Services refused the registration,
/// or the first sample simply has not landed yet — and the running screen
/// rendered all four as the same blank space.
enum class HeartRateAvailability {
    /// Not monitoring at all. `BuildConfig.ENABLE_HR` is off for this
    /// build, so there is nothing to report and the screen says nothing.
    Off,

    /// Registered and waiting. Either no sample has arrived yet or the
    /// sensor itself reports `ACQUIRING`.
    Acquiring,

    /// Reporting usable samples.
    Available,

    /// The watch is off the runner's wrist. Distinct from [Unavailable]
    /// because it is the one state the runner can fix mid-run.
    OffWrist,

    /// No heart rate this run: the registration was refused, the stream
    /// threw, or the sensor reports `UNAVAILABLE`. Collapsed into one
    /// state deliberately — the causes differ but none of them is
    /// actionable from a running screen, and the permission case is
    /// covered at the moment the runner CAN act on it by the pre-run
    /// notice (decisions § 1018).
    Unavailable,
}

/// One element of `HeartRateMonitor.stream()`. Carries the availability
/// on every emission and a bpm only when there is one, so a state change
/// is a first-class event rather than the absence of samples.
data class HeartRateUpdate(
    val availability: HeartRateAvailability,
    val bpm: Int? = null,
)

/// What the running screen's heart-rate slot should carry. Separate from
/// [HeartRateAvailability] because the two answer different questions:
/// one is what the sensor says, the other is what the runner is told.
enum class HeartRateCaptionKind {
    /// Render nothing — the slot collapses out of the secondary row.
    None,

    /// Render the bpm figure (with the zone badge when cutoffs resolve).
    Reading,

    Acquiring,
    OffWrist,
    Unavailable,
}

/// Decide the heart-rate caption from the sensor state and the last
/// sample.
///
/// The state wins over the number in every disagreement. A watch that
/// went off the wrist at minute three used to keep rendering its last
/// reading for the rest of a twelve-hour run, because nothing ever
/// cleared `bpm` once it had been set; here an availability that is not
/// [HeartRateAvailability.Available] reports itself even if a stale
/// figure is still in hand.
///
/// `Available` with no sample yet is [HeartRateCaptionKind.Acquiring],
/// not a blank: between registration and the first sample the sensor is
/// working and the runner is owed the difference between "wait" and
/// "there will be none".
fun heartRateCaption(
    availability: HeartRateAvailability,
    bpm: Int?,
): HeartRateCaptionKind = when (availability) {
    HeartRateAvailability.Off -> HeartRateCaptionKind.None
    HeartRateAvailability.Acquiring -> HeartRateCaptionKind.Acquiring
    HeartRateAvailability.Available ->
        if (bpm == null) HeartRateCaptionKind.Acquiring else HeartRateCaptionKind.Reading
    HeartRateAvailability.OffWrist -> HeartRateCaptionKind.OffWrist
    HeartRateAvailability.Unavailable -> HeartRateCaptionKind.Unavailable
}
