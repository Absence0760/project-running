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
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import com.runapp.watchwear.system.BatteryOptimization
import com.runapp.watchwear.system.BatteryStatus
import com.runapp.watchwear.system.NetworkWatcher
import java.io.File
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

enum class Stage { PreRun, Running, Paused, PostRun, SignIn }

data class UiState(
    val stage: Stage = Stage.PreRun,
    val elapsedMs: Long = 0,
    val distanceM: Double = 0.0,
    val paceSecPerKm: Double? = null,
    val bpm: Int? = null,
    val locationAvailable: Boolean = true,
    val online: Boolean = true,
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
    val batteryPercent: Int? = null,
    val pendingRecovery: Checkpoint? = null,
    val activityType: String = "run",
    val lapCount: Int = 0,
    val activeRace: ActiveRaceState? = null,
)

data class ActiveRaceState(
    val eventId: String,
    val instanceStart: String,
    val status: String,
    val startedAtMs: Long?,
    val eventTitle: String?,
) {
    val isArmed: Boolean get() = status == "armed"
    val isRunning: Boolean get() = status == "running"
}

data class FinishedSummary(
    val distanceM: Double,
    val durationS: Int,
    val avgBpm: Double?,
    val lapCount: Int = 0,
    val activityType: String = "run",
    val laps: List<FinishedLap> = emptyList(),
)

data class FinishedLap(
    val number: Int,
    val splitSeconds: Int,
    val splitDistanceM: Double,
    val cumulativeSeconds: Int,
    val cumulativeDistanceM: Double,
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
    private val raceClient = RaceSessionClient(
        baseUrl = BuildConfig.SUPABASE_URL,
        anonKey = BuildConfig.SUPABASE_ANON_KEY,
    )

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
    private var racePollJob: Job? = null
    private var racePingJob: Job? = null
    private var lastRacePingAtMs: Long = 0L

    init {
        observeRecording()
        observeQueue()
        observeConnectivity()
        observeRace()
        bootstrapAuth()
        checkBatteryOptimisation()
        checkBatteryLevel()
        checkRecovery()
    }

    private fun observeRecording() {
        recordingObserverJob = viewModelScope.launch {
            RecordingRepository.metrics.collect { m ->
                when (m.stage) {
                    RecordingRepository.Stage.Recording,
                    RecordingRepository.Stage.Paused -> {
                        _state.value = _state.value.copy(
                            stage = if (m.stage == RecordingRepository.Stage.Paused)
                                Stage.Paused else Stage.Running,
                            elapsedMs = m.elapsedMs,
                            distanceM = m.distanceM,
                            paceSecPerKm = m.paceSecPerKm,
                            bpm = m.bpm,
                            locationAvailable = m.locationAvailable,
                            activityType = m.activityType,
                            lapCount = m.laps.size,
                        )
                        maybePushRacePing(m)
                    }
                    RecordingRepository.Stage.Finished -> handleFinishedRun(m)
                    RecordingRepository.Stage.Idle -> Unit
                }
            }
        }
    }

    private fun maybePushRacePing(m: RecordingRepository.Metrics) {
        val race = _state.value.activeRace ?: return
        if (!race.isRunning) return
        val point = m.latestPoint ?: return
        val now = System.currentTimeMillis()
        if (now - lastRacePingAtMs < 10_000) return
        lastRacePingAtMs = now
        val token = supabase.currentAccessToken ?: return
        val uid = supabase.authedUserId ?: return
        racePingJob = viewModelScope.launch {
            try {
                raceClient.pushPing(
                    accessToken = token,
                    userId = uid,
                    eventId = race.eventId,
                    instanceStart = race.instanceStart,
                    lat = point.lat,
                    lng = point.lng,
                    distanceM = m.distanceM,
                    elapsedS = (m.elapsedMs / 1000).toInt(),
                    bpm = m.bpm,
                )
            } catch (_: Throwable) {
                // ignore — pings are best-effort.
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
            var seeded = false
            networkWatcher.availability().collect { online ->
                _state.value = _state.value.copy(online = online)
                if (!seeded) { seeded = true; return@collect }
                if (online && _state.value.authed) drainQueue()
            }
        }
    }

    /// Poll for an armed / running race the user is RSVP'd to. The watch
    /// has no realtime client today so we poll — 30s cadence is fine
    /// because the organiser usually arms a few minutes before GO.
    private fun observeRace() {
        racePollJob = viewModelScope.launch {
            while (true) {
                kotlinx.coroutines.delay(5_000)
                if (authReady.value) refreshRace()
                kotlinx.coroutines.delay(25_000)
            }
        }
    }

    private suspend fun refreshRace() {
        val token = supabase.currentAccessToken ?: return
        val uid = supabase.authedUserId ?: return
        try {
            val active = raceClient.fetchActive(token, uid)
            val newState = active?.let {
                ActiveRaceState(
                    eventId = it.eventId,
                    instanceStart = it.instanceStart,
                    status = it.status,
                    startedAtMs = it.startedAtIso?.let { iso ->
                        runCatching { java.time.Instant.parse(iso).toEpochMilli() }
                            .getOrNull()
                    },
                    eventTitle = it.eventTitle,
                )
            }
            if (newState != _state.value.activeRace) {
                _state.value = _state.value.copy(activeRace = newState)
            }
        } catch (_: Throwable) {
            // Polling is advisory; swallow failures so a flaky connection
            // doesn't spam the UI with errors.
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

    fun refreshBatteryOptimisation() {
        checkBatteryOptimisation()
        checkBatteryLevel()
    }

    private fun checkBatteryLevel() {
        _state.value = _state.value.copy(
            batteryPercent = BatteryStatus.percent(getApplication()),
        )
    }

    private fun checkRecovery() {
        viewModelScope.launch {
            val cp = checkpoints.current()
            if (cp != null) {
                _state.value = _state.value.copy(pendingRecovery = cp)
            }
        }
    }

    /// User accepted the recovery prompt. Treat the checkpointed run as
    /// finished-as-of-savedAt and queue it for upload. The track file is
    /// already sealed on disk (the writer closes on service destroy), but
    /// may be an unclosed JSON array if the process was killed mid-flush;
    /// we re-seal it defensively before queueing.
    fun recoverCheckpoint() {
        val cp = _state.value.pendingRecovery ?: return
        viewModelScope.launch {
            val durationS = ((cp.savedAtMs - cp.startedAtMs) / 1000).toInt()
            val avgBpm = if (cp.bpmCount == 0L) null
                else cp.bpmSum.toDouble() / cp.bpmCount
            val sealed = sealTrackFile(cp.trackFilePath)
            store.save(
                QueuedRun(
                    id = cp.runId,
                    startedAtIso = Instant.ofEpochMilli(cp.startedAtMs).toString(),
                    durationS = durationS,
                    distanceM = cp.distanceM,
                    trackFilePath = sealed.absolutePath,
                    avgBpm = avgBpm,
                    activityType = cp.activityType,
                    laps = cp.laps.map { QueuedLap(it.number, it.atMs, it.distanceM) },
                )
            )
            checkpoints.clear()
            _state.value = _state.value.copy(
                pendingRecovery = null,
                lastRunSummary = FinishedSummary(
                    distanceM = cp.distanceM,
                    durationS = durationS,
                    avgBpm = avgBpm,
                    lapCount = cp.laps.size,
                    activityType = cp.activityType,
                ),
                stage = Stage.PostRun,
                thisRunId = cp.runId,
                thisRunSynced = false,
            )
            drainQueue()
        }
    }

    /// If a track file is missing a closing `]` (process killed before
    /// `TrackWriter.close` ran), append one so it parses as JSON. Missing
    /// file → write an empty array stub so downstream code still has a
    /// path to upload.
    private suspend fun sealTrackFile(path: String): File =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val f = File(path)
            if (!f.exists()) {
                f.parentFile?.mkdirs()
                f.writeText("[]")
                return@withContext f
            }
            val len = f.length()
            if (len == 0L) {
                f.writeText("[]")
                return@withContext f
            }
            val last = java.io.RandomAccessFile(f, "r").use { raf ->
                raf.seek((len - 1).coerceAtLeast(0))
                raf.read()
            }
            if (last != ']'.code) f.appendText("]")
            f
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
        checkBatteryLevel()
        val runId = UUID.randomUUID().toString()
        _state.value = _state.value.copy(
            stage = Stage.Running,
            elapsedMs = 0,
            distanceM = 0.0,
            paceSecPerKm = null,
            bpm = null,
            lapCount = 0,
            syncError = null,
            thisRunId = runId,
            thisRunSynced = false,
        )
        RunRecordingService.start(getApplication(), runId, _state.value.activityType)
    }

    fun setActivityType(type: String) {
        if (_state.value.stage != Stage.PreRun) return
        _state.value = _state.value.copy(activityType = type)
    }

    fun markLap() {
        if (_state.value.stage != Stage.Running && _state.value.stage != Stage.Paused) return
        RunRecordingService.lap(getApplication())
    }

    fun stop() {
        if (_state.value.stage != Stage.Running && _state.value.stage != Stage.Paused) return
        RunRecordingService.stop(getApplication())
    }

    fun pause() {
        if (_state.value.stage != Stage.Running) return
        RunRecordingService.pause(getApplication())
    }

    fun resume() {
        if (_state.value.stage != Stage.Paused) return
        RunRecordingService.resume(getApplication())
    }

    /// Called from the recording observer when the service publishes a
    /// `Finished` state. Persists the run to LocalRunStore + drains.
    private fun handleFinishedRun(m: RecordingRepository.Metrics) {
        val runId = m.runId ?: return
        val trackPath = m.trackFilePath ?: return
        val durationS = (m.elapsedMs / 1000).toInt()
        // Snapshot race context before we reset; we need it below to
        // submit the result after the upload drains.
        val race = _state.value.activeRace
            ?.takeIf { it.isRunning }
        val laps = buildFinishedLaps(m, durationS)
        val summary = FinishedSummary(
            distanceM = m.distanceM,
            durationS = durationS,
            avgBpm = m.avgBpm,
            lapCount = m.laps.size,
            activityType = m.activityType,
            laps = laps,
        )
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
                    trackFilePath = trackPath,
                    avgBpm = m.avgBpm,
                    activityType = m.activityType,
                    laps = m.laps.map { QueuedLap(it.number, it.atMs, it.distanceM) },
                )
            )
            RecordingRepository.reset()
            drainQueue()
            if (race != null) {
                val token = supabase.currentAccessToken
                val uid = supabase.authedUserId
                if (token != null && uid != null) {
                    try {
                        raceClient.submitResult(
                            accessToken = token,
                            userId = uid,
                            eventId = race.eventId,
                            instanceStart = race.instanceStart,
                            runId = runId,
                            durationS = durationS,
                            distanceM = m.distanceM,
                        )
                    } catch (_: Throwable) {
                        // Leaderboard write is best-effort; the run is queued.
                    }
                }
                // Clear the active race once we've reported. If the race
                // is still running on the server, the next poll will
                // re-populate it — but at that point the user isn't on
                // it anymore (they've finished).
                _state.value = _state.value.copy(activeRace = null)
            }
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
        if (!awaitAuth()) return
        val snapshot = store.queue.first()
        var lastError: String? = null
        var anyAuthFailure = false
        for (run in snapshot) {
            try {
                pushRun(run)
                store.remove(run.id)
                lastError = null
            } catch (e: Throwable) {
                val msg = e.message.orEmpty()
                // Permanent-ish errors: 400/404/409/422 — the run is
                // malformed or already exists. Leave it queued (the user
                // can Discard from the UI if they want) but move on.
                // 409 is now safe to remove: every run carries external_id so
                // a 409 means the row is already in the DB (idempotent upload).
                val alreadyPersisted = msg.contains("HTTP 409")
                val permanent = Regex("HTTP 4(00|04|22)").containsMatchIn(msg)
                // Transient: timeouts, 5xx, network loss. Stop iterating
                // so we don't hammer the backend, but keep the queue
                // intact. Next drain trigger (network-back-online,
                // manual sync) retries.
                val transient = Regex("HTTP 5\\d\\d").containsMatchIn(msg) ||
                    msg.contains("timeout", ignoreCase = true) ||
                    msg.contains("Unable to resolve", ignoreCase = true) ||
                    msg.contains("Software caused", ignoreCase = true)

                if (msg.contains("HTTP 401")) {
                    anyAuthFailure = true
                    // One 401 retry: refresh token + try this run again.
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
                        lastError = null
                        continue
                    } catch (inner: Throwable) {
                        lastError = inner.message ?: msg
                        break  // refresh failed → stop, next auth signal retries
                    }
                }

                when {
                    alreadyPersisted -> {
                        store.remove(run.id)
                        lastError = null
                        continue
                    }
                    transient -> {
                        lastError = msg
                        break  // try again later; don't thrash
                    }
                    permanent -> {
                        lastError = msg
                        continue  // skip to next; this one is stuck
                    }
                    else -> {
                        lastError = msg
                        continue  // unknown — optimistically try next
                    }
                }
            }
        }
        _state.value = _state.value.copy(syncError = lastError)
    }

    private suspend fun pushRun(run: QueuedRun) {
        val metadata: JsonObject = buildJsonObject {
            put("activity_type", run.activityType)
            if (run.avgBpm != null) put("avg_bpm", run.avgBpm)
            if (run.laps.isNotEmpty()) {
                put("laps", buildJsonArray {
                    var prevMs = 0L
                    var prevDist = 0.0
                    for (lap in run.laps) {
                        addJsonObject {
                            put("index", lap.number)
                            put("start_offset_s", (lap.atMs / 1000).toInt())
                            put("distance_m", (lap.distanceM - prevDist).coerceAtLeast(0.0))
                            put("duration_s", ((lap.atMs - prevMs) / 1000).toInt().coerceAtLeast(0))
                        }
                        prevMs = lap.atMs
                        prevDist = lap.distanceM
                    }
                })
            }
        }
        val trackFile = File(run.trackFilePath)
        supabase.saveRun(
            runId = run.id,
            startedAtIso = run.startedAtIso,
            durationS = run.durationS,
            distanceM = run.distanceM,
            trackFile = trackFile,
            metadata = metadata,
        )
        // Once the track is safely in Storage, clear the cache file. On
        // retry paths we'll already be past this line (pushRun threw) so
        // the file stays on disk until the next successful drain.
        runCatching { trackFile.delete() }
    }

    /// Turn the service's raw lap list (cumulative marks) into split-per-lap
    /// rows suitable for the post-run table. The final "bonus" row is the
    /// partial between the last lap mark and the stop — only included when
    /// it's non-trivial (≥ 1s and ≥ 1m).
    private fun buildFinishedLaps(
        m: RecordingRepository.Metrics,
        totalDurationS: Int,
    ): List<FinishedLap> {
        if (m.laps.isEmpty()) return emptyList()
        val out = mutableListOf<FinishedLap>()
        var prevMs = 0L
        var prevDist = 0.0
        for (lap in m.laps) {
            val split = ((lap.atMs - prevMs) / 1000).toInt().coerceAtLeast(0)
            val splitDist = (lap.distanceM - prevDist).coerceAtLeast(0.0)
            out += FinishedLap(
                number = lap.number,
                splitSeconds = split,
                splitDistanceM = splitDist,
                cumulativeSeconds = (lap.atMs / 1000).toInt(),
                cumulativeDistanceM = lap.distanceM,
            )
            prevMs = lap.atMs
            prevDist = lap.distanceM
        }
        val finalSplitS = totalDurationS - out.last().cumulativeSeconds
        val finalSplitM = m.distanceM - out.last().cumulativeDistanceM
        if (finalSplitS >= 1 && finalSplitM >= 1.0) {
            out += FinishedLap(
                number = out.size + 1,
                splitSeconds = finalSplitS,
                splitDistanceM = finalSplitM,
                cumulativeSeconds = totalDurationS,
                cumulativeDistanceM = m.distanceM,
            )
        }
        return out
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
