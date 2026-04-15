package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

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
        val avgBpm: Double? = null,
        val trackPointCount: Int = 0,
        val latestPoint: GpsPoint? = null,
        val trackFilePath: String? = null,
        val locationAvailable: Boolean = true,
        val activityType: String = "run",
        val laps: List<Lap> = emptyList(),
    ) {
        val isActive: Boolean get() = stage == Stage.Recording || stage == Stage.Paused
    }

    private val _metrics = MutableStateFlow(Metrics())
    val metrics: StateFlow<Metrics> = _metrics.asStateFlow()

    fun update(transform: (Metrics) -> Metrics) {
        _metrics.value = transform(_metrics.value)
    }

    fun reset() {
        _metrics.value = Metrics()
    }
}
