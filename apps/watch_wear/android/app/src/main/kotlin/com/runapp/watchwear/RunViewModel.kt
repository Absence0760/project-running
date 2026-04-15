package com.runapp.watchwear

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runapp.watchwear.recording.Checkpoint
import com.runapp.watchwear.recording.CheckpointStore
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.recording.RunRecordingService
import com.runapp.watchwear.system.BatteryOptimization
import com.runapp.watchwear.system.NetworkWatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.UUID

enum class Stage { PreRun, Running, PostRun, SignIn }

data class UiState(
    val stage: Stage = Stage.PreRun,
    val elapsedMs: Long = 0,
    val distanceM: Double = 0.0,
    val paceSecPerKm: Double? = null,
    val bpm: Int? = null,
    val locationAvailable: Boolean = true,
    val queuedCount: Int = 0,
    val authed: Boolean = false,
    val authError: String? = null,
    val signInLoading: Boolean = false,
    val syncing: Boolean = false,
    val syncError: String? = null,
    val thisRunId: String? = null,
    val thisRunSynced: Boolean = false,
    val lastRunSummary: FinishedSummary? = null,
    val batteryOptimised: Boolean = true,
    val pendingRecovery: Checkpoint? = null,
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
    private val store = LocalRunStore(application)
    private val sessionStore = SessionStore(application)
    private val sessionBridge = SessionBridge(application)
    private val checkpoints = CheckpointStore(application)
    private val networkWatcher = NetworkWatcher(application)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    /// Latches when a session has been applied to `supabase`. `drainQueue`
    /// awaits this with a short timeout so the cold-start race (recording
    /// stops before the cached session restore completes) doesn't surface
    /// as a "not authenticated" error.
    private val authReady = MutableStateFlow(false)

    private var queueWatchJob: Job? = null
    private var recordingObserverJob: Job? = null
    private var connectivityJob: Job? = null

    init {
        observeRecording()
        observeQueue()
        observeConnectivity()
        bootstrapAuth()
        checkBatteryOptimisation()
        checkRecovery()
    }

    private fun observeRecording() {
        recordingObserverJob = viewModelScope.launch {
            RecordingRepository.metrics.collect { m ->
                when (m.stage) {
                    RecordingRepository.Stage.Recording -> {
                        _state.value = _state.value.copy(
                            stage = Stage.Running,
                            elapsedMs = m.elapsedMs,
                            distanceM = m.distanceM,
                            paceSecPerKm = m.paceSecPerKm,
                            bpm = m.bpm,
                            locationAvailable = m.locationAvailable,
                        )
                    }
                    RecordingRepository.Stage.Finished -> handleFinishedRun(m)
                    RecordingRepository.Stage.Idle -> Unit
                }
            }
        }
    }

    private fun observeQueue() {
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

    private fun observeConnectivity() {
        connectivityJob = viewModelScope.launch {
            // Skip the seed "true" emission so we don't fire drainQueue
            // duplicately with the auth bootstrap path.
            var seeded = false
            networkWatcher.availability().collect { online ->
                if (!seeded) { seeded = true; return@collect }
                if (online && _state.value.authed) drainQueue()
            }
        }
    }

    private fun bootstrapAuth() {
        viewModelScope.launch {
            val cached = sessionStore.current()
            if (cached != null) {
                applySession(cached)
                refreshIfExpired(cached)
                drainQueue()
                return@launch
            }
            if (BuildConfig.BYPASS_LOGIN) {
                try {
                    signInWithEmailInternal("runner@test.com", "testtest")
                } catch (_: Throwable) { /* sign-in screen will surface */ }
            }
        }
        viewModelScope.launch {
            try {
                sessionBridge.current()?.let { payload ->
                    val stored = StoredSession.fromPayload(payload)
                    sessionStore.save(stored)
                    applySession(stored)
                    refreshIfExpired(stored)
                    drainQueue()
                }
            } catch (_: Throwable) { /* no paired phone, fine */ }
        }
        viewModelScope.launch {
            sessionBridge.sessions.collect { payload ->
                val stored = StoredSession.fromPayload(payload)
                sessionStore.save(stored)
                applySession(stored)
                drainQueue()
            }
        }
    }

    private fun checkBatteryOptimisation() {
        _state.value = _state.value.copy(
            batteryOptimised = !BatteryOptimization.isExempt(getApplication()),
        )
    }

    fun refreshBatteryOptimisation() = checkBatteryOptimisation()

    private fun checkRecovery() {
        viewModelScope.launch {
            val cp = checkpoints.current()
            if (cp != null) {
                _state.value = _state.value.copy(pendingRecovery = cp)
            }
        }
    }

    /// User accepted the recovery prompt. Treat the checkpointed run as
    /// finished-as-of-savedAt and queue it for upload.
    fun recoverCheckpoint() {
        val cp = _state.value.pendingRecovery ?: return
        viewModelScope.launch {
            val durationS = ((cp.savedAtMs - cp.startedAtMs) / 1000).toInt()
            val avgBpm = if (cp.bpmSamples.isEmpty()) null
                else cp.bpmSamples.sum().toDouble() / cp.bpmSamples.size
            val trackJson = encodeCheckpointTrack(cp)
            store.save(
                QueuedRun(
                    id = cp.runId,
                    startedAtIso = Instant.ofEpochMilli(cp.startedAtMs).toString(),
                    durationS = durationS,
                    distanceM = cp.distanceM,
                    trackJson = trackJson,
                    avgBpm = avgBpm,
                )
            )
            checkpoints.clear()
            _state.value = _state.value.copy(
                pendingRecovery = null,
                lastRunSummary = FinishedSummary(cp.distanceM, durationS, avgBpm),
                stage = Stage.PostRun,
                thisRunId = cp.runId,
                thisRunSynced = false,
            )
            drainQueue()
        }
    }

    fun discardCheckpoint() {
        viewModelScope.launch {
            checkpoints.clear()
            _state.value = _state.value.copy(pendingRecovery = null)
        }
    }

    // ----- Auth helpers -----

    private fun applySession(s: StoredSession) {
        supabase.applyCredentials(
            accessToken = s.accessToken,
            refreshToken = s.refreshToken,
            userId = s.userId,
            baseUrl = s.baseUrl,
            anonKey = s.anonKey,
        )
        _state.value = _state.value.copy(authed = true, authError = null)
        authReady.value = true
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

    // ----- Recording controls (delegate to the foreground service) -----

    fun start() {
        if (_state.value.stage != Stage.PreRun) return
        val runId = UUID.randomUUID().toString()
        _state.value = _state.value.copy(
            stage = Stage.Running,
            elapsedMs = 0,
            distanceM = 0.0,
            paceSecPerKm = null,
            bpm = null,
            syncError = null,
            thisRunId = runId,
            thisRunSynced = false,
        )
        RunRecordingService.start(getApplication(), runId)
    }

    fun stop() {
        if (_state.value.stage != Stage.Running) return
        RunRecordingService.stop(getApplication())
    }

    /// Called from the recording observer when the service publishes a
    /// `Finished` state. Persists the run to LocalRunStore + drains.
    private fun handleFinishedRun(m: RecordingRepository.Metrics) {
        val runId = m.runId ?: return
        val durationS = (m.elapsedMs / 1000).toInt()
        val trackJson = encodeTrack(m.track)
        val summary = FinishedSummary(m.distanceM, durationS, m.avgBpm)
        _state.value = _state.value.copy(
            stage = Stage.PostRun,
            thisRunId = runId,
            thisRunSynced = false,
            lastRunSummary = summary,
        )
        viewModelScope.launch {
            store.save(
                QueuedRun(
                    id = runId,
                    startedAtIso = Instant.ofEpochMilli(m.startedAtMs).toString(),
                    durationS = durationS,
                    distanceM = m.distanceM,
                    trackJson = trackJson,
                    avgBpm = m.avgBpm,
                )
            )
            // Reset the repo so the next run starts from a clean slate.
            RecordingRepository.reset()
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

    // ----- Sign in / out -----

    fun signOut() {
        viewModelScope.launch {
            supabase.clearCredentials()
            sessionStore.clear()
            authReady.value = false
            _state.value = _state.value.copy(
                authed = false,
                authError = null,
                stage = Stage.PreRun,
            )
        }
    }

    fun openSignIn() {
        _state.value = _state.value.copy(stage = Stage.SignIn, authError = null)
    }

    fun cancelSignIn() {
        _state.value = _state.value.copy(stage = Stage.PreRun)
    }

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

    // ----- Queue drain -----

    /// Wait briefly for the auth bootstrap to land before bailing out
    /// with "not authenticated". Eliminates the race where a fresh
    /// activity launch fires `drainQueue` (e.g. via a network-available
    /// callback) before the cached session has been restored.
    private suspend fun awaitAuth(): Boolean {
        if (authReady.value) return true
        return withTimeoutOrNull(AUTH_WAIT_MS) {
            authReady.first { it }
        } != null
    }

    private suspend fun drainQueue() {
        if (!awaitAuth()) {
            // Not signed in yet — runs stay queued; next signal (network
            // online, sign-in success, app foreground) will retry.
            return
        }
        val snapshot = store.queue.first()
        for (run in snapshot) {
            try {
                pushRun(run)
                store.remove(run.id)
            } catch (e: Throwable) {
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
                    } catch (_: Throwable) { /* fall through */ }
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

    private fun encodeCheckpointTrack(cp: Checkpoint): String {
        val sb = StringBuilder("[")
        cp.track.forEachIndexed { i, p ->
            if (i > 0) sb.append(",")
            sb.append("{\"lat\":").append(p.lat)
                .append(",\"lng\":").append(p.lng)
                .append(",\"ele\":").append(p.ele ?: "null")
                .append(",\"ts\":\"").append(Instant.ofEpochMilli(p.epochMs)).append("\"}")
        }
        sb.append("]")
        return sb.toString()
    }

    companion object {
        private const val AUTH_WAIT_MS = 3_000L
    }

    class Factory(private val application: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            RunViewModel(application) as T
    }
}
