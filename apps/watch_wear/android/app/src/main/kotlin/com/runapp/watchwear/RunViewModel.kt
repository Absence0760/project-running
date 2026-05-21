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
import java.time.Instant
import java.util.UUID

enum class Stage { PreRun, Running, Paused, PostRun, SignIn, RoutePicker }

/// What `drainQueue` should do with a single failed run.
internal sealed class DrainAction {
    /// 401 — refresh access token, then retry this run once.
    data object RetryAfterRefresh : DrainAction()
    /// 409 — already in the DB (idempotent upload). Drop and move on.
    data object DropAndContinue : DrainAction()
    /// 5xx / network drop / timeout. Bail out of the loop; let the next
    /// drain signal retry the whole queue.
    data object StopAndRetryLater : DrainAction()
    /// 400 / 404 / 422 / unknown 4xx — leave queued, skip to next run.
    data object SkipAndContinue : DrainAction()
}

/// Classify a drain failure by its type, not its stringified message.
/// 401s previously fell into `SkipAndContinue` because the substring
/// match in `drainQueue` was looking for `"HTTP 401"` while
/// `SupabaseClient` was throwing the body's `msg` field instead — so
/// the refresh-and-retry path never fired. With `HttpException` carrying
/// the status code, we can branch correctly.
internal fun classifyDrainError(e: Throwable): DrainAction {
    if (e is HttpException) {
        return when {
            e.code == 401 -> DrainAction.RetryAfterRefresh
            e.code == 409 -> DrainAction.DropAndContinue
            e.code in 500..599 -> DrainAction.StopAndRetryLater
            e.code == 400 || e.code == 404 || e.code == 422 -> DrainAction.SkipAndContinue
            else -> DrainAction.SkipAndContinue
        }
    }
    val msg = e.message.orEmpty()
    val transient = msg.contains("timeout", ignoreCase = true) ||
        msg.contains("Unable to resolve", ignoreCase = true) ||
        msg.contains("Software caused", ignoreCase = true)
    return if (transient) DrainAction.StopAndRetryLater else DrainAction.SkipAndContinue
}

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
    /// Routes the user has saved, populated from `LocalRouteStore` on
    /// launch and refreshed from Supabase whenever PreRun is entered.
    val routes: List<SavedRoute> = emptyList(),
    /// The route the runner picked on the PreRun screen, if any. Flows
    /// into `RunRecordingService` at `start()` time so the off-route
    /// banner + "X to go" badge have a polyline to work against.
    val selectedRoute: SavedRoute? = null,
    val routesLoading: Boolean = false,
    /// Live off-route distance in metres (perpendicular distance to the
    /// nearest segment). Null when no route is loaded. Published by the
    /// recording service per GPS sample via `RouteMath.offRouteDistanceM`.
    val offRouteDistanceM: Double? = null,
    /// Live "distance to end of route" in metres. Null when no route.
    val routeRemainingM: Double? = null,
    /// Resolved zone upper-bound cutoffs (5 strictly-ascending BPMs).
    /// Null until `applyUniversalPrefsAsync` lands the user's
    /// `hr_zones` / `max_hr_bpm` / `date_of_birth` from the bag.
    /// Drives the "Z3" badge next to the live BPM on the RunningScreen.
    val hrZoneCutoffs: List<Int>? = null,
    /// Latest GPS fix during this run, or null until the first fix
    /// lands. Drives the runner-position dot on the on-watch mini-map.
    val latestPoint: GpsPoint? = null,
    /// Route polyline currently loaded into the recording service. The
    /// mini-map gates on this being non-empty; free-form runs render
    /// no map.
    val routeWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng> = emptyList(),
    /// Downsampled rolling buffer of recent GPS points for the
    /// "where I've been" overlay on the in-run mini-map. Bounded so
    /// memory is O(cap) regardless of run length.
    val trackOverlayPoints: List<com.runapp.watchwear.recording.RouteMath.LatLng> = emptyList(),
    /// User-picked target pace for this run, in seconds per kilometre.
    /// Null means "no target — don't fire pace alerts". Set via the
    /// pre-run Pace chip; flows through `ACTION_START` to the service.
    val targetPaceSecPerKm: Int? = null,
    /// Live step count for the current run from the pedometer. Null
    /// when the device has no step sensor or no samples have arrived.
    val steps: Int? = null,
    /// Last-known GPS fix from `FusedLocationProviderClient.lastLocation`,
    /// captured during the start countdown so the countdown screen
    /// can render a preview of the running-screen map under the
    /// digit. By the time `start()` flips the stage to Running, the
    /// map's already drawn — no flash of empty midnight.
    val lastKnownLatLng: com.runapp.watchwear.recording.RouteMath.LatLng? = null,
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
    /// Lat/lng samples from the recorded track. Populated by reading
    /// the on-disk track JSON in `handleFinishedRun`. Used by
    /// `PostRunScreen` to render a thumbnail of the actual shape the
    /// runner ran. Empty when the run had no GPS fixes (indoor).
    val trackLatLngs: List<com.runapp.watchwear.recording.RouteMath.LatLng> = emptyList(),
)

data class FinishedLap(
    val number: Int,
    val splitSeconds: Int,
    val splitDistanceM: Double,
    val cumulativeSeconds: Int,
    val cumulativeDistanceM: Double,
)

/// Pure helper: turn the recording service's cumulative-mark lap list
/// into per-lap split rows suitable for the post-run table.
///
/// Each input [RecordingRepository.Lap] carries the CUMULATIVE position
/// at the moment the user pressed the lap button (`atMs` since start,
/// `distanceM` total). The output [FinishedLap] rows carry both the
/// cumulative figures AND the SPLIT (per-lap delta) figures the table
/// renders.
///
/// The final "bonus" row covers the partial between the last lap mark
/// and the stop. It's only included when it's non-trivial (≥1 s and
/// ≥1 m) so a "lap-then-immediately-stop" doesn't produce a phantom
/// 0/0 row.
///
/// Extracted from `RunViewModel.buildFinishedLaps` so the lap-shape
/// contract — particularly the per-lap split math, the
/// cumulative-vs-split distinction, and the bonus-row gate — is
/// unit-testable without booting the ViewModel. The
/// `start_offset_s = cumulative-BEFORE` shape is registered in
/// `docs/metadata.md`; this helper feeds the FinishedLap shape that
/// `WatchRunMetadata.buildRunMetadata` later writes through to the
/// row's `metadata.laps` jsonb.
internal fun buildFinishedLapsList(
    laps: List<RecordingRepository.Lap>,
    totalDistanceM: Double,
    totalDurationS: Int,
): List<FinishedLap> {
    if (laps.isEmpty()) return emptyList()
    val out = mutableListOf<FinishedLap>()
    var prevMs = 0L
    var prevDist = 0.0
    for (lap in laps) {
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
    val finalSplitM = totalDistanceM - out.last().cumulativeDistanceM
    if (finalSplitS >= 1 && finalSplitM >= 1.0) {
        out += FinishedLap(
            number = out.size + 1,
            splitSeconds = finalSplitS,
            splitDistanceM = finalSplitM,
            cumulativeSeconds = totalDurationS,
            cumulativeDistanceM = totalDistanceM,
        )
    }
    return out
}

class RunViewModel(application: Application) : AndroidViewModel(application) {
    private val supabase = SupabaseClient(
        baseUrl = BuildConfig.SUPABASE_URL,
        anonKey = BuildConfig.SUPABASE_ANON_KEY,
    )
    private val store = LocalRunStore(application)
    private val sessionStore = SessionStore(application)
    private val sessionBridge = SessionBridge(application)
    private val routeStore = LocalRouteStore(application)
    private val checkpoints = CheckpointStore(application)
    private val networkWatcher = NetworkWatcher(application)
    /// MapTiler tile source — process-wide singleton shared with
    /// every `RouteMiniMap` composable. Decoded `ImageBitmap`s sit
    /// in the singleton's LRU so a freshly-mounted RouteMiniMap
    /// (e.g., the running screen mounting after the countdown
    /// unmounts) doesn't flash midnight while it re-decodes from
    /// disk.
    private val tileSource by lazy {
        com.runapp.watchwear.ui.TileSource.get(application)
    }
    /// One-shot GPS reader, used by the countdown overlay to fetch
    /// tiles around the runner's last-known location during the
    /// 3-second start countdown. The recording service runs its own
    /// `GpsRecorder` for the streaming case; this is a separate
    /// instance scoped to the foreground ViewModel.
    private val gpsForPrefetch by lazy { GpsRecorder(application) }
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

    /// Exponential-backoff window for drainQueue. Mirrors the shape of
    /// the Dart `SyncService` on phones — see `DrainBackoff` for details.
    private val drainBackoff = DrainBackoff()

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
        loadCachedRoutes()
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
                            offRouteDistanceM = m.offRouteDistanceM,
                            routeRemainingM = m.routeRemainingM,
                            latestPoint = m.latestPoint,
                            routeWaypoints = m.routeWaypoints,
                            trackOverlayPoints = m.trackOverlayPoints,
                            steps = m.steps,
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
            sessionBridge.events.collect { event ->
                when (event) {
                    is SessionEvent.Updated -> {
                        val stored = StoredSession.fromPayload(event.payload)
                        sessionStore.save(stored)
                        applySession(stored)
                        drainQueue()
                    }
                    SessionEvent.Cleared -> tearDownSession()
                }
            }
        }
    }

    /// Shared teardown for both the user-initiated `signOut` and the
    /// phone-side sign-out signal that arrives on the SessionBridge as
    /// `SessionEvent.Cleared`. Mirrors `signOut`'s state mutation so the
    /// two paths can't drift.
    private suspend fun tearDownSession() {
        supabase.clearCredentials()
        sessionStore.clear()
        routeStore.clear()
        authReady.value = false
        _state.value = _state.value.copy(
            authed = false,
            authError = null,
            stage = Stage.PreRun,
            routes = emptyList(),
            selectedRoute = null,
        )
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
            drainQueue(force = true)
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
        // Pull the universal prefs bag once per session restore so the
        // pre-run activity picker opens on the user's phone-side
        // default (run / walk / hike / cycle) instead of the hardcoded
        // "run". Read-only on the wrist by design — the user edits
        // this from the phone or web. See parity.md row
        // `default_activity_type` + watch_wear/CLAUDE.md "Don't build
        // settings panels on the wrist."
        applyUniversalPrefsAsync()
    }

    /// Latest universal `privacy_default` ("public" / "followers" /
    /// "private"), set after every session restore. Snapshotted onto
    /// QueuedRun.isPublic at run-stop time so a later pref change can't
    /// retroactively flip an already-recorded run's visibility.
    /// `@Volatile` because reads land on the recording's coroutine
    /// continuation and writes land on the universal-prefs fetch
    /// continuation — they're never the same thread.
    @Volatile
    private var universalPrivacyDefault: String? = null

    /// Fetches the universal-prefs bag and applies the relevant fields:
    ///   - `default_activity_type` primes the pre-run picker chip (PreRun
    ///     stage only, and only when the user hasn't already moved off
    ///     the hardcoded default).
    ///   - `privacy_default` is cached on the VM; `handleFinishedRun`
    ///     reads it at stop-time so a watch-saved run respects the
    ///     user's universal visibility default. The wrist can only
    ///     write `is_public` (boolean), so `public → true` and
    ///     `followers` / `private` → false. The phone/web social layer
    ///     is the authoritative path for the `followers` nuance.
    private fun applyUniversalPrefsAsync() {
        viewModelScope.launch {
            val settings = supabase.fetchUniversalSettings() ?: return@launch
            // privacy_default — stash regardless of stage; the snapshot
            // matters at handleFinishedRun, which can run minutes or
            // hours after the fetch returns.
            universalPrivacyDefault = settings.privacyDefault
            // hr-zone cutoffs — resolved in priority order (explicit
            // hr_zones > max_hr_bpm > 220-age from DOB). Stored on the
            // VM state so the RunningScreen can render "Z3" next to
            // BPM. Updated regardless of stage; null cutoffs disable
            // the badge silently.
            val resolved = resolveZoneCutoffs(settings, System.currentTimeMillis())
            _state.value = _state.value.copy(hrZoneCutoffs = resolved)
            // default_activity_type — only prime; never override a
            // started run or a manual chip choice.
            val preferred = settings.defaultActivityType ?: return@launch
            val s = _state.value
            if (s.stage != Stage.PreRun) return@launch
            if (s.activityType != "run") return@launch
            _state.value = s.copy(activityType = preferred)
        }
    }

    /// Map the universal `privacy_default` ("public" / "followers" /
    /// "private") to the wrist's boolean snapshot. Null when the bag
    /// fetch hasn't returned or returned no value — caller omits the
    /// column and the DB default (`false`) applies.
    internal fun snapshotIsPublic(): Boolean? {
        val v = universalPrivacyDefault ?: return null
        return v == "public"
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
        val route = _state.value.selectedRoute
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
            offRouteDistanceM = null,
            routeRemainingM = null,
        )
        RunRecordingService.start(
            context = getApplication(),
            runId = runId,
            activityType = _state.value.activityType,
            routeWaypointsJson = route?.waypointsAsJson(),
            targetPaceSecPerKm = _state.value.targetPaceSecPerKm,
        )
    }

    fun setActivityType(type: String) {
        if (_state.value.stage != Stage.PreRun) return
        _state.value = _state.value.copy(activityType = type)
    }

    /// Cycle the pre-run target pace through the standard options.
    /// `null` means "no target"; the chip label renders "Pace: off".
    /// The other values were picked to cover the common marathon +
    /// half-marathon + parkrun training paces a club runner cares about
    /// — it's not a configurable list, because typing numbers on a 46mm
    /// screen is miserable. If a runner wants a custom target, they
    /// should set it on the phone once the universal-bag integration
    /// lands and ride it across devices.
    fun cycleTargetPace() {
        if (_state.value.stage != Stage.PreRun) return
        val order = listOf<Int?>(null, 240, 270, 300, 330, 360, 390, 420)
        val idx = order.indexOf(_state.value.targetPaceSecPerKm)
        val next = order[(idx + 1) % order.size]
        _state.value = _state.value.copy(targetPaceSecPerKm = next)
    }

    // ----- Routes -----

    /// Populate the initial route list from the DataStore cache so the
    /// picker has something to show during a cold-launch offline. The
    /// network refresh in `refreshRoutes` fires when the user opens
    /// the picker.
    private fun loadCachedRoutes() {
        viewModelScope.launch {
            try {
                val cached = routeStore.current()
                if (cached.isNotEmpty()) {
                    _state.value = _state.value.copy(routes = cached)
                }
            } catch (_: Throwable) { /* empty cache is fine */ }
        }
    }

    /// Pull saved routes from Supabase and overwrite the local cache.
    /// Called when the user opens the picker; failures leave the
    /// cached list intact so the UI doesn't blank out. The wire
    /// query is starred-first (`is_starred=eq.true`, limit 30) with
    /// a recent-10 fallback for un-curated users — see
    /// `SupabaseClient.fetchRoutes`. Result is re-ordered so routes
    /// the user has tapped recently on this watch float to the top:
    /// "starred + recently-tapped-here" is a stronger signal than
    /// either dimension alone.
    fun refreshRoutes() {
        if (!authReady.value) return
        _state.value = _state.value.copy(routesLoading = true)
        viewModelScope.launch {
            try {
                val fresh = supabase.fetchRoutes()
                routeStore.save(fresh)
                _state.value = _state.value.copy(
                    routes = sortByRecency(fresh, routeStore.recentIds.first()),
                    routesLoading = false,
                )
            } catch (_: Throwable) {
                _state.value = _state.value.copy(routesLoading = false)
            }
        }
    }

    /// Stable-sort: routes whose IDs appear in `recentIds` first,
    /// in LRU order; everything else preserves its incoming
    /// (`updated_at desc`) order. Pure helper so it's testable
    /// without booting the ViewModel.
    private fun sortByRecency(
        routes: List<SavedRoute>,
        recentIds: List<String>,
    ): List<SavedRoute> {
        if (recentIds.isEmpty()) return routes
        val byId = routes.associateBy { it.id }
        val recents = recentIds.mapNotNull { byId[it] }
        val recentSet = recents.map { it.id }.toSet()
        val rest = routes.filter { it.id !in recentSet }
        return recents + rest
    }

    fun openRoutePicker() {
        _state.value = _state.value.copy(stage = Stage.RoutePicker)
        refreshRoutes()
    }

    /// Warm-fetch tiles around the device's last-known GPS location.
    /// Invoked from the UI when the 3-second start countdown begins
    /// so tile downloads ride the countdown instead of stalling the
    /// running screen's first frame on HTTP latency. No-op when no
    /// fix is available (indoor, GPS off) or when a planned route is
    /// already selected (its tiles were prefetched on selectRoute).
    fun prefetchTilesForRunStart() {
        viewModelScope.launch {
            try {
                val fix = gpsForPrefetch.lastLocation() ?: return@launch
                val latLng = com.runapp.watchwear.recording.RouteMath.LatLng(fix.lat, fix.lng)
                // Publish the fix so the countdown screen can render
                // a preview of the running-screen map under the digit
                // — instant transition to Running with no map flash.
                _state.value = _state.value.copy(lastKnownLatLng = latLng)
                // Skip the radial prefetch when a route is already
                // selected — its tiles were prefetched on selectRoute.
                if (_state.value.selectedRoute == null) {
                    tileSource.prefetch(listOf(latLng))
                }
            } catch (e: Exception) {
                android.util.Log.w("RunViewModel", "countdown tile prefetch failed", e)
            }
        }
    }

    fun closeRoutePicker() {
        if (_state.value.stage != Stage.RoutePicker) return
        _state.value = _state.value.copy(stage = Stage.PreRun)
    }

    fun selectRoute(route: SavedRoute) {
        _state.value = _state.value.copy(
            selectedRoute = route,
            stage = Stage.PreRun,
        )
        viewModelScope.launch {
            // Bump LRU so the next picker open puts this route at
            // the top regardless of `updated_at` on the server.
            try { routeStore.pushRecent(route.id) } catch (_: Throwable) { }
            // Eagerly download street-zoom tiles along the route
            // while we still have connectivity (paired phone, wifi).
            try {
                tileSource.prefetch(route.toLatLngs())
            } catch (e: Exception) {
                // Pre-fetch is L3 best-effort. A failure here just means
                // the running screen falls back to on-demand fetching,
                // which still works as long as connectivity holds.
                android.util.Log.w("RunViewModel", "tile prefetch failed", e)
            }
        }
    }

    fun clearSelectedRoute() {
        _state.value = _state.value.copy(
            selectedRoute = null,
            stage = Stage.PreRun,
        )
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
        // Parse the on-disk track JSON to lat/lng pairs so the post-run
        // screen can preview the shape the runner ran. Falls back to
        // an empty list if the file is missing or malformed (indoor
        // mode produces a `[]` stub via TrackWriter.close).
        val trackPoints = readTrackForPreview(trackPath)
        val summary = FinishedSummary(
            distanceM = m.distanceM,
            durationS = durationS,
            avgBpm = m.avgBpm,
            lapCount = m.laps.size,
            activityType = m.activityType,
            laps = laps,
            trackLatLngs = trackPoints,
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
                    steps = m.steps,
                    // Snapshot the universal privacy default at stop time
                    // so an in-flight queued run keeps its visibility
                    // even if the user toggles the pref while the upload
                    // is pending or while the watch is offline.
                    isPublic = snapshotIsPublic(),
                )
            )
            RecordingRepository.reset()
            drainQueue(force = true)
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
            drainQueue(force = true)
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
        viewModelScope.launch { tearDownSession() }
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
        drainQueue(force = true)
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

    private suspend fun drainQueue(force: Boolean = false) {
        if (!awaitAuth()) return
        if (!force && drainBackoff.isInBackoff()) {
            // Auto-trigger (network-flap, auth-bootstrap) inside the backoff
            // window — don't hammer the backend. User-initiated drains pass
            // force=true so a manual Sync chip always fires.
            return
        }
        val snapshot = store.queue.first()
        // The loop body itself is in the pure `drainQueueLoop` helper
        // so the per-error-class semantics, refresh-then-retry shape,
        // and transient-vs-permanent split can be unit-tested in
        // isolation (see DrainQueueLoopTest.kt). This wrapper handles
        // the side-channel concerns the loop is intentionally
        // unaware of: auth-await, backoff window, persisting the
        // refreshed session, and posting the UI banner.
        val result = drainQueueLoop(
            snapshot = snapshot,
            push = { run -> pushRun(run) },
            refresh = {
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
                    true
                } catch (_: Throwable) {
                    false
                }
            },
            onSuccessfulDrain = OnSuccessfulDrain { id -> store.remove(id) },
        )
        if (result.anyTransientFailure) {
            drainBackoff.onFailure()
        } else {
            drainBackoff.onSuccess()
        }
        _state.value = _state.value.copy(syncError = result.lastError)
    }

    private suspend fun pushRun(run: QueuedRun) {
        val metadata: JsonObject = buildRunMetadata(
            activityType = run.activityType,
            avgBpm = run.avgBpm,
            steps = run.steps,
            laps = run.laps,
            lastModifiedAtIso = Instant.now().toString(),
        )
        val trackFile = File(run.trackFilePath)
        supabase.saveRun(
            runId = run.id,
            startedAtIso = run.startedAtIso,
            durationS = run.durationS,
            distanceM = run.distanceM,
            trackFile = trackFile,
            metadata = metadata,
            isPublic = run.isPublic,
        )
        // Once the track is safely in Storage, clear the cache file. On
        // retry paths we'll already be past this line (pushRun threw) so
        // the file stays on disk until the next successful drain.
        runCatching { trackFile.delete() }
    }

    /// Turn the service's raw lap list (cumulative marks) into split-per-lap
    /// Read the just-finished track JSON off disk so the post-run
    /// screen can render a preview thumbnail. Decimates to ≤ 256
    /// points (geometric every-other halving, same shape-preserving
    /// strategy as the in-run track overlay) so a 4-hour run with
    /// thousands of points still draws cheaply on a 96 dp canvas.
    /// Returns empty on any failure — caller treats that as
    /// "indoor / no track to preview".
    private fun readTrackForPreview(
        path: String,
    ): List<com.runapp.watchwear.recording.RouteMath.LatLng> {
        return try {
            val raw = File(path).takeIf { it.exists() }?.readText() ?: return emptyList()
            val arr = (kotlinx.serialization.json.Json.parseToJsonElement(raw)
                as? kotlinx.serialization.json.JsonArray) ?: return emptyList()
            val all = arr.mapNotNull { el ->
                val obj = el as? kotlinx.serialization.json.JsonObject ?: return@mapNotNull null
                val lat = (obj["lat"] as? kotlinx.serialization.json.JsonPrimitive)
                    ?.content?.toDoubleOrNull() ?: return@mapNotNull null
                val lng = (obj["lng"] as? kotlinx.serialization.json.JsonPrimitive)
                    ?.content?.toDoubleOrNull() ?: return@mapNotNull null
                com.runapp.watchwear.recording.RouteMath.LatLng(lat, lng)
            }.toMutableList()
            while (all.size > 256) {
                com.runapp.watchwear.recording.TrackOverlayBuffer.halveIfOverflowing(all, 256)
            }
            all
        } catch (_: Throwable) {
            emptyList()
        }
    }

    /// rows suitable for the post-run table. The final "bonus" row is the
    /// partial between the last lap mark and the stop — only included when
    /// it's non-trivial (≥ 1s and ≥ 1m).
    private fun buildFinishedLaps(
        m: RecordingRepository.Metrics,
        totalDurationS: Int,
    ): List<FinishedLap> = buildFinishedLapsList(
        laps = m.laps,
        totalDistanceM = m.distanceM,
        totalDurationS = totalDurationS,
    )

    companion object {
        private const val AUTH_WAIT_MS = 3_000L
    }

    class Factory(private val application: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            RunViewModel(application) as T
    }
}
