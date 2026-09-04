package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import com.runapp.watchwear.HeartRateAvailability
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/// Process-wide singleton holding live recording state. Owned by
/// `RunRecordingService` (which writes), observed by `RunViewModel`
/// (which only reads + emits user-action callbacks back through the
/// service). Decoupling recording from UI lifecycle is what lets a
/// run survive the activity being destroyed for ambient, screen off,
/// or low memory.
///
/// The full GPS track is *not* held here — it's streamed to disk by
/// `TrackWriter`. Only the latest point (for map/UI display) and a
/// count live in `Metrics`. This is what lets a 10-hour run fit in
/// constant memory instead of growing linearly with every GPS fix.
object RecordingRepository {

    enum class Stage { Idle, Recording, Paused, Finished }

    data class Lap(
        val number: Int,
        val atMs: Long,
        val distanceM: Double,
    )

    data class Metrics(
        val stage: Stage = Stage.Idle,
        val runId: String? = null,
        val startedAtMs: Long = 0L,
        val elapsedMs: Long = 0L,
        val distanceM: Double = 0.0,
        val paceSecPerKm: Double? = null,
        val bpm: Int? = null,
        /// What the FINISHED run may claim about its heart rate: the graded
        /// average and the share of active elapsed time the sensor covered
        /// (decisions § 1083). Written once, by whichever party makes the
        /// `Finished` transition, and null at every other stage.
        ///
        /// There is deliberately no ungraded live average beside it. This
        /// field used to be a bare `avgBpm` that the heart-rate collect
        /// updated on every sample and `stopRecording` then overwrote with
        /// the graded figure, so one name carried two different claims at two
        /// different times and `handleFinishedRun` was correct only because
        /// the overwrite happened first — an ordering, pinned by a source
        /// guard, between two writers on a CAS loop that exists precisely
        /// because writes here can land out of order. The live rolling mean
        /// had no reader at all: the running screen renders the INSTANTANEOUS
        /// [bpm], and the grader takes the raw `bpmSum`/`bpmCount` off the
        /// service rather than off this state. So the write was dead and its
        /// only effect was the hazard (decisions § 1105).
        val finishedHr: HeartRateClaim? = null,
        /// Why there is (or is not) a live [bpm]. A null bpm is four
        /// different situations and the running screen rendered them as
        /// one blank space; this is what lets it say which
        /// (decisions § 1052). `Off` on a build with `ENABLE_HR` false,
        /// so a build that deliberately has no heart rate does not
        /// caption every run with its absence.
        val hrAvailability: HeartRateAvailability = HeartRateAvailability.Off,
        val trackPointCount: Int = 0,
        val latestPoint: GpsPoint? = null,
        val trackFilePath: String? = null,
        val locationAvailable: Boolean = true,
        val activityType: String = "run",
        val laps: List<Lap> = emptyList(),
        /// Populated by `RunRecordingService` on every GPS sample when a
        /// route was passed to `ACTION_START`. Null when no route is
        /// loaded for this run.
        val offRouteDistanceM: Double? = null,
        val routeRemainingM: Double? = null,
        /// The full route polyline parsed from the start-action intent.
        /// Set once on `startRecording`, cleared on stop. Drives the
        /// on-watch mini-map; otherwise it's read-only display data and
        /// the off-route / remaining math doesn't depend on what's
        /// stored here (the service holds its own copy).
        val routeWaypoints: List<RouteMath.LatLng> = emptyList(),
        /// Bounded rolling buffer of GPS samples for the on-watch
        /// mini-map's "where I've been" overlay. Capped at
        /// `RunRecordingService.MAX_TRACK_OVERLAY_POINTS`; the service
        /// halves the list on overflow so density stays
        /// geometrically uniform across the whole run regardless of
        /// duration. Don't use this for distance / pace math — that
        /// flows from `latestPoint` + `distanceM`. The full,
        /// undownsampled track is on disk via `TrackWriter`.
        val trackOverlayPoints: List<RouteMath.LatLng> = emptyList(),
        /// Cumulative step count since this run started. Null when the
        /// device has no pedometer (or before the first sensor sample).
        /// Writes to `metadata.steps` on save when non-null.
        val steps: Int? = null,
        /// Distance-display unit for this run, stamped once at
        /// `startRecording` from the runner's `preferred_unit` pref. Lets
        /// the active-run tile (a separate process reading this StateFlow)
        /// render distance / pace in the runner's chosen unit.
        val preferredUnit: DistanceUnit = DistanceUnit.KM,
    ) {
        val isActive: Boolean get() = stage == Stage.Recording || stage == Stage.Paused
    }

    private val _metrics = MutableStateFlow(Metrics())
    val metrics: StateFlow<Metrics> = _metrics.asStateFlow()

    /// Atomic read-modify-write. This MUST stay a CAS loop
    /// (`MutableStateFlow.update`), not `_metrics.value = transform(...)`:
    /// five writers hit it concurrently — the GPS, HR, steps and ticker jobs
    /// on `Dispatchers.Default`, plus pause/resume/lap/stop on the main
    /// thread via `onStartCommand`.
    ///
    /// A plain read-then-assign loses whichever write lands second. The worst
    /// case is losing the run: the ticker reads a `Recording` snapshot,
    /// `stopRecording()` writes `stage = Finished`, the ticker's stale
    /// assignment reverts it, and `stopRecording` then clears the checkpoint —
    /// so `RunViewModel.observeRecording` never sees `Finished`, never queues
    /// the run, and recovery has just been deleted. Cancelling the ticker does
    /// not help: cancellation cannot interrupt a non-suspending call already
    /// in flight. The same clobber silently un-pauses a paused run and
    /// permanently under-counts distance (the accumulator is read back out of
    /// the repository on each fix, so a lost write is never made up).
    ///
    /// With a CAS loop the transform re-runs against the latest value, so a
    /// concurrent `stage` change survives — none of the per-metric transforms
    /// writes `stage` itself.
    fun update(transform: (Metrics) -> Metrics) {
        _metrics.update(transform)
    }

    fun reset() {
        _metrics.value = Metrics()
    }
}
