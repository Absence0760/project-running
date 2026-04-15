package com.runapp.watchwear

import android.app.Application
import android.location.Location
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.UUID
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

enum class Stage { PreRun, Running, PostRun }

data class UiState(
    val stage: Stage = Stage.PreRun,
    val elapsedMs: Long = 0,
    val distanceM: Double = 0.0,
    val paceSecPerKm: Double? = null,
    val bpm: Int? = null,
    val queuedCount: Int = 0,
    val authed: Boolean = false,
    val syncing: Boolean = false,
    val syncError: String? = null,
    val thisRunId: String? = null,
    val thisRunSynced: Boolean = false,
    val lastRunSummary: FinishedSummary? = null,
)

data class FinishedSummary(
    val distanceM: Double,
    val durationS: Int,
    val avgBpm: Double?,
)

class RunViewModel(application: Application) : AndroidViewModel(application) {
    private val supabase = SupabaseClient(
        baseUrl = BuildConfig.SUPABASE_URL,
        anonKey = BuildConfig.SUPABASE_ANON_KEY,
    )
    private val gps = GpsRecorder(application)
    private val hr = HeartRateMonitor(application)
    private val store = LocalRunStore(application)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var recordingJob: Job? = null
    private var hrJob: Job? = null
    private var tickerJob: Job? = null
    private var queueWatchJob: Job? = null

    private val track = mutableListOf<GpsPoint>()
    private val bpmSamples = mutableListOf<Int>()
    private var lastLocation: Location? = null
    private var startMs = 0L

    init {
        viewModelScope.launch {
            try {
                supabase.signIn("runner@test.com", "testtest")
                _state.value = _state.value.copy(authed = true)
                drainQueue()
            } catch (_: Throwable) {
                _state.value = _state.value.copy(authed = false)
            }
        }
        queueWatchJob = viewModelScope.launch {
            store.queue.collect { list ->
                _state.value = _state.value.copy(
                    queuedCount = list.size,
                    thisRunSynced = _state.value.thisRunId?.let { id ->
                        list.none { it.id == id }
                    } ?: _state.value.thisRunSynced,
                )
            }
        }
    }

    fun start() {
        if (_state.value.stage != Stage.PreRun) return
        track.clear()
        bpmSamples.clear()
        lastLocation = null
        startMs = System.currentTimeMillis()

        _state.value = _state.value.copy(
            stage = Stage.Running,
            elapsedMs = 0,
            distanceM = 0.0,
            paceSecPerKm = null,
            bpm = null,
            syncError = null,
        )

        recordingJob = viewModelScope.launch {
            gps.stream().collect { p ->
                onGps(p)
            }
        }
        hrJob = viewModelScope.launch {
            hr.stream().collect { bpm ->
                bpmSamples.add(bpm)
                _state.value = _state.value.copy(bpm = bpm)
            }
        }
        tickerJob = viewModelScope.launch {
            while (true) {
                kotlinx.coroutines.delay(500)
                val elapsed = System.currentTimeMillis() - startMs
                _state.value = _state.value.copy(elapsedMs = elapsed)
            }
        }
    }

    fun stop() {
        if (_state.value.stage != Stage.Running) return
        recordingJob?.cancel(); recordingJob = null
        hrJob?.cancel(); hrJob = null
        tickerJob?.cancel(); tickerJob = null

        val durationS = ((System.currentTimeMillis() - startMs) / 1000).toInt()
        val avgBpm = if (bpmSamples.isEmpty()) null
            else bpmSamples.sum().toDouble() / bpmSamples.size
        val runId = UUID.randomUUID().toString()
        val startedAtIso = Instant.ofEpochMilli(startMs).toString()
        val trackJson = encodeTrack(track)

        _state.value = _state.value.copy(
            stage = Stage.PostRun,
            thisRunId = runId,
            thisRunSynced = false,
            lastRunSummary = FinishedSummary(_state.value.distanceM, durationS, avgBpm),
        )

        viewModelScope.launch {
            store.save(
                QueuedRun(
                    id = runId,
                    startedAtIso = startedAtIso,
                    durationS = durationS,
                    distanceM = _state.value.distanceM,
                    trackJson = trackJson,
                    avgBpm = avgBpm,
                )
            )
            drainQueue()
        }
    }

    fun sync() {
        viewModelScope.launch {
            _state.value = _state.value.copy(syncing = true, syncError = null)
            drainQueue()
            _state.value = _state.value.copy(syncing = false)
        }
    }

    fun startNextRun() {
        _state.value = _state.value.copy(
            stage = Stage.PreRun,
            thisRunId = null,
            thisRunSynced = false,
            syncError = null,
        )
    }

    fun discard() {
        val id = _state.value.thisRunId
        viewModelScope.launch {
            if (id != null) store.remove(id)
            startNextRun()
        }
    }

    // ----- Internals -----

    private suspend fun drainQueue() {
        val snapshot = store.queue.first()
        for (run in snapshot) {
            try {
                val metadata: JsonObject? = run.avgBpm?.let {
                    buildJsonObject { put("avg_bpm", it) }
                }
                supabase.saveRun(
                    runId = run.id,
                    startedAtIso = run.startedAtIso,
                    durationS = run.durationS,
                    distanceM = run.distanceM,
                    trackJson = run.trackJson,
                    metadata = metadata,
                )
                store.remove(run.id)
            } catch (e: Throwable) {
                _state.value = _state.value.copy(syncError = e.message)
                break
            }
        }
    }

    private fun onGps(p: GpsPoint) {
        val asLoc = Location("").apply {
            latitude = p.lat; longitude = p.lng; time = p.epochMs
        }
        lastLocation?.let { prev ->
            val delta = haversineM(prev.latitude, prev.longitude, p.lat, p.lng)
            // Same jitter gate as the Dart run_recorder: 2m floor, 100m ceiling.
            if (delta in 2.0..100.0) {
                val newDist = _state.value.distanceM + delta
                _state.value = _state.value.copy(
                    distanceM = newDist,
                    paceSecPerKm = computePace(newDist),
                )
            }
        }
        lastLocation = asLoc
        track.add(p)
    }

    private fun computePace(distanceM: Double): Double? {
        if (distanceM < 50) return null
        val elapsedS = (System.currentTimeMillis() - startMs) / 1000.0
        if (elapsedS <= 0) return null
        return elapsedS / distanceM * 1000.0
    }

    private fun encodeTrack(points: List<GpsPoint>): String {
        val sb = StringBuilder("[")
        points.forEachIndexed { i, p ->
            if (i > 0) sb.append(",")
            sb.append("{\"lat\":").append(p.lat)
                .append(",\"lng\":").append(p.lng)
                .append(",\"ele\":").append(p.ele ?: "null")
                .append(",\"ts\":\"").append(Instant.ofEpochMilli(p.epochMs)).append("\"}")
        }
        sb.append("]")
        return sb.toString()
    }

    private fun haversineM(
        aLat: Double, aLng: Double, bLat: Double, bLng: Double,
    ): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(bLat - aLat)
        val dLng = Math.toRadians(bLng - aLng)
        val a = sin(dLat / 2).pow(2.0) +
            cos(Math.toRadians(aLat)) * cos(Math.toRadians(bLat)) *
            sin(dLng / 2).pow(2.0)
        val c = 2 * Math.asin(sqrt(a))
        return r * c
    }

    class Factory(private val application: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            RunViewModel(application) as T
    }
}
