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

enum class Stage { PreRun, Running, PostRun, SignIn }

data class UiState(
    val stage: Stage = Stage.PreRun,
    val elapsedMs: Long = 0,
    val distanceM: Double = 0.0,
    val paceSecPerKm: Double? = null,
    val bpm: Int? = null,
    val queuedCount: Int = 0,
    val authed: Boolean = false,
    val authError: String? = null,
    val signInLoading: Boolean = false,
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
    private val sessionStore = SessionStore(application)
    private val sessionBridge = SessionBridge(application)

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
        // 1. Restore any previously-handed-over session from disk. Runs even
        //    when the phone is out of range — so a cold start while offline
        //    still has credentials to drain the queue once the network
        //    returns. If nothing is cached and BYPASS_LOGIN is on (dev-only
        //    flag in .env.local), sign in with the seed creds so the
        //    sign-in screen doesn't get in the way during local testing.
        viewModelScope.launch {
            val cached = sessionStore.current()
            if (cached != null) {
                applySession(cached)
                refreshIfExpired(cached)
                return@launch
            }
            if (BuildConfig.BYPASS_LOGIN) {
                try {
                    signInWithEmailInternal("runner@test.com", "testtest")
                } catch (_: Throwable) {
                    // Local Supabase probably isn't running; the sign-in
                    // screen will surface the error if the user opens it.
                }
            }
        }
        // 2. One-shot pull from the Data Layer in case the phone pushed
        //    while the watch app was closed.
        viewModelScope.launch {
            try {
                sessionBridge.current()?.let { payload ->
                    val stored = StoredSession.fromPayload(payload)
                    sessionStore.save(stored)
                    applySession(stored)
                    refreshIfExpired(stored)
                    drainQueue()
                }
            } catch (_: Throwable) {
                // Data Layer not available (e.g. emulator without paired phone).
                // The cached session path above is our fallback.
            }
        }
        // 3. Live subscription for future pushes (token refresh on the phone,
        //    account switch, sign-out).
        viewModelScope.launch {
            sessionBridge.sessions.collect { payload ->
                val stored = StoredSession.fromPayload(payload)
                sessionStore.save(stored)
                applySession(stored)
                drainQueue()
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

    private fun applySession(s: StoredSession) {
        supabase.applyCredentials(
            accessToken = s.accessToken,
            refreshToken = s.refreshToken,
            userId = s.userId,
            baseUrl = s.baseUrl,
            anonKey = s.anonKey,
        )
        _state.value = _state.value.copy(authed = true, authError = null)
    }

    private suspend fun refreshIfExpired(s: StoredSession) {
        if (!s.isExpired()) return
        try {
            val refreshed = supabase.refreshAccessToken()
            sessionStore.save(
                s.copy(
                    accessToken = refreshed.accessToken,
                    refreshToken = refreshed.refreshToken,
                    expiresAtMs = refreshed.expiresAtMs,
                )
            )
        } catch (e: Throwable) {
            _state.value = _state.value.copy(
                authError = "Token refresh failed: ${e.message ?: e.javaClass.simpleName}",
            )
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
        // HR is gated by the ENABLE_HR flag in `.env.local`. The Wear OS
        // emulator produces synthetic BPM samples that look real — we don't
        // want them polluting production runs, so the sensor stays off
        // unless a developer has explicitly enabled it for a real device.
        if (BuildConfig.ENABLE_HR) {
            hrJob = viewModelScope.launch {
                hr.stream().collect { bpm ->
                    bpmSamples.add(bpm)
                    _state.value = _state.value.copy(bpm = bpm)
                }
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

    // ----- Sign out -----

    /// Clear the cached session + in-memory credentials. The user lands
    /// back on PreRun with `authed = false`. Any queued runs stay in the
    /// local store — they'll attempt to upload against whichever account
    /// signs in next, which is usually what you want for dev dogfooding
    /// but is a flag to keep in mind if multi-user support lands later.
    ///
    /// Does NOT override `BYPASS_LOGIN`: if that flag is true and the
    /// activity restarts, the auto-sign-in path in `init` will pick the
    /// session back up. Flip the flag to `false` in `.env.local` before
    /// rebuilding to actually see the sign-in screen.
    fun signOut() {
        viewModelScope.launch {
            supabase.clearCredentials()
            sessionStore.clear()
            _state.value = _state.value.copy(
                authed = false,
                authError = null,
                stage = Stage.PreRun,
            )
        }
    }

    // ----- Direct sign-in (no paired phone) -----

    fun openSignIn() {
        _state.value = _state.value.copy(stage = Stage.SignIn, authError = null)
    }

    fun cancelSignIn() {
        _state.value = _state.value.copy(stage = Stage.PreRun)
    }

    /// Sign in directly against Supabase from the watch. Used by standalone
    /// users without a paired Android phone. The resulting session is saved
    /// to `SessionStore` so subsequent launches and reboots don't require
    /// re-typing; the same refresh-on-expiry path used for phone-handed
    /// sessions applies after this.
    fun signInWithEmail(email: String, password: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                authed = false,
                authError = null,
                signInLoading = true,
            )
            try {
                signInWithEmailInternal(email, password)
                _state.value = _state.value.copy(
                    stage = Stage.PreRun,
                    signInLoading = false,
                )
            } catch (e: Throwable) {
                _state.value = _state.value.copy(
                    authError = e.message ?: e.javaClass.simpleName,
                    signInLoading = false,
                )
            }
        }
    }

    /// Core sign-in logic shared by the user-facing [signInWithEmail] and
    /// the BYPASS_LOGIN auto-sign-in path in [init]. Throws on failure so
    /// each caller can surface the error however it wants.
    private suspend fun signInWithEmailInternal(email: String, password: String) {
        val result = supabase.signIn(email, password)
        val (baseUrl, anonKey) = supabase.environment
        val stored = StoredSession(
            accessToken = result.accessToken,
            refreshToken = result.refreshToken,
            userId = result.userId,
            baseUrl = baseUrl,
            anonKey = anonKey,
            expiresAtMs = result.expiresAtMs,
        )
        sessionStore.save(stored)
        applySession(stored)
        drainQueue()
    }

    // ----- Internals -----

    private suspend fun drainQueue() {
        val snapshot = store.queue.first()
        for (run in snapshot) {
            try {
                pushRun(run)
                store.remove(run.id)
            } catch (e: Throwable) {
                // One retry on 401 — access token probably expired while the
                // run was queued. Burn a refresh and re-try once; if that
                // still fails, leave the queue intact for the next trigger.
                if (e.message?.contains("HTTP 401") == true) {
                    try {
                        val refreshed = supabase.refreshAccessToken()
                        val cached = sessionStore.current()
                        if (cached != null) {
                            sessionStore.save(
                                cached.copy(
                                    accessToken = refreshed.accessToken,
                                    refreshToken = refreshed.refreshToken,
                                    expiresAtMs = refreshed.expiresAtMs,
                                )
                            )
                        }
                        pushRun(run)
                        store.remove(run.id)
                        continue
                    } catch (_: Throwable) {
                        // fall through to the error state below
                    }
                }
                _state.value = _state.value.copy(syncError = e.message)
                break
            }
        }
    }

    private suspend fun pushRun(run: QueuedRun) {
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
