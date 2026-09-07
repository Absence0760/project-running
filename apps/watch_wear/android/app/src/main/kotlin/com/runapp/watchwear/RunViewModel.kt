package com.runapp.watchwear

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runapp.watchwear.recording.Checkpoint
import com.runapp.watchwear.recording.CheckpointStore
import com.runapp.watchwear.recording.checkpointActiveDurationS
import com.runapp.watchwear.recording.heartRateClaim
import com.runapp.watchwear.recording.RecordingRepository
import com.runapp.watchwear.recording.RecoveryAction
import com.runapp.watchwear.recording.recoveryActionFor
import com.runapp.watchwear.recording.sealTrackFileOrNull
import com.runapp.watchwear.recording.RunRecordingService
import com.runapp.watchwear.recording.TrackStorage
import com.runapp.watchwear.recording.sweepOrphanTracks
import com.runapp.watchwear.system.BatteryOptimization
import com.runapp.watchwear.system.BatteryStatus
import com.runapp.watchwear.system.NetworkWatcher
import java.io.File
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.retryWhen
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.util.UUID

enum class Stage { PreRun, Running, Paused, PostRun, SignIn, RoutePicker }

/// What `drainQueue` should do with a single failed run.
internal sealed class DrainAction {
    /// 401 — refresh access token, then retry this run once.
    data object RetryAfterRefresh : DrainAction()
    /// 5xx / network drop / timeout. Bail out of the loop; let the next
    /// drain signal retry the whole queue.
    data object StopAndRetryLater : DrainAction()
    /// 400 / 404 / 409 / 422 / unknown 4xx — leave queued, skip to next run.
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
            e.code in 500..599 -> DrainAction.StopAndRetryLater
            // 409 sits with the other permanent 4xx (decisions.md §17): a
            // duplicate-key insert leaves the queued run in place to be
            // discarded manually, never silently dropped. It is NOT an
            // idempotent-success signal — the watch's own retries never 409
            // (same run id re-POSTs merge on the PK via
            // `Prefer: resolution=merge-duplicates`, returning 200), so the
            // only 409 the drain path can see is a genuine conflict whose row
            // may never have been inserted.
            e.code == 400 || e.code == 404 || e.code == 409 || e.code == 422 ->
                DrainAction.SkipAndContinue
            else -> DrainAction.SkipAndContinue
        }
    }
    // Network-layer failures must classify transient so the drain loop
    // short-circuits and arms backoff, mirroring the Go worker's isTransient
    // (apps/job_worker/internal/worker.go). OkHttp / java.net surface a
    // dropped connection as "Failed to connect to …", "ECONNREFUSED
    // (Connection refused)", "Connection reset", or a truncated body as
    // "unexpected end of stream" — none of which match a bare "timeout", so
    // without these markers a real outage was mis-classified permanent,
    // hammered every queued run, and reset backoff via onSuccess.
    val msg = e.message.orEmpty()
    val transientMarkers = listOf(
        "timeout",
        "Unable to resolve",
        "Software caused",
        "connection refused",
        "connection reset",
        "failed to connect",
        "no such host",
        "unexpected end of stream",
    )
    val transient = transientMarkers.any { msg.contains(it, ignoreCase = true) }
    return if (transient) DrainAction.StopAndRetryLater else DrainAction.SkipAndContinue
}

data class UiState(
    val stage: Stage = Stage.PreRun,
    val elapsedMs: Long = 0,
    val distanceM: Double = 0.0,
    val paceSecPerKm: Double? = null,
    val bpm: Int? = null,
    /// Why [bpm] is what it is. Threaded through so `RunningScreen` can
    /// tell "waiting for the first sample" from "there will be none"
    /// (decisions § 1052).
    val hrAvailability: HeartRateAvailability = HeartRateAvailability.Off,
    val locationAvailable: Boolean = true,
    val online: Boolean = true,
    val queuedCount: Int = 0,
    /// The last read of the run queue failed, so [queuedCount] is stale rather
    /// than current. DataStore reports a corrupt or unreadable file by failing
    /// the read, and the two facts are orthogonal: the count is the last figure
    /// anyone saw, this is whether it still stands (decisions § 1104).
    val queueUnreadable: Boolean = false,
    /// Queue entries the server has permanently REFUSED — a 400/404/409/422
    /// that no retry will ever move. They stay in the queue by design (§ 17:
    /// dropping one silently loses a run), so without this the count on the
    /// PreRun chip never falls while every Sync tap reports success
    /// (decisions § 1347).
    ///
    /// Ids rather than a count, because the only remedy is destructive and a
    /// discard must name exactly the entries the last pass judged — not
    /// "however many are queued now", which would take a run that has never
    /// been tried with it.
    ///
    /// Not persisted. A cold start starts empty and the first drain pass
    /// re-derives it, which is honest: the fact is a server verdict, not a
    /// property of the file.
    val rejectedRunIds: Set<String> = emptySet(),
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
    /// The last attempt to load the route list did not produce one — no
    /// session yet, or the fetch threw. Distinct from "this runner has
    /// saved no routes", which is what the picker used to say either way:
    /// a signed-out or offline watch told a runner with fifty saved routes
    /// to go and build one.
    val routesUnavailable: Boolean = false,
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
    /// Body weight (kg) from `user_settings.prefs.body_weight_kg`, for
    /// the PostRun calorie estimate (persona samsung #34). Null → the
    /// shared 70 kg default applies, and the figure renders with the
    /// "(est)" cue so the guess is never presented as measured.
    val bodyWeightKg: Double? = null,
    /// Universal `show_calories` opt-out (default on). When false the
    /// PostRun summary renders no calorie line at all.
    val showCalories: Boolean = true,
    /// Distance-display unit resolved from `user_settings.prefs
    /// .preferred_unit`. Drives the distance / pace read-outs on the
    /// running + post-run screens and the route "to go" badge. Defaults
    /// to kilometres until `applyUniversalPrefsAsync` lands the pref.
    val preferredUnit: com.runapp.watchwear.recording.DistanceUnit =
        com.runapp.watchwear.recording.DistanceUnit.KM,
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
/// `docs/backend/metadata.md`; this helper feeds the FinishedLap shape that
/// `WatchRunMetadata.buildRunMetadata` later writes through to the
/// row's `metadata.laps` jsonb.
/// Map a universal `privacy_default` ("public" / "followers" / "private")
/// to the wrist's `is_public` boolean snapshot. Null in → null out (the
/// prefs bag never loaded), so the caller omits the column and the DB
/// default (`false`, non-public) applies. `public → true`, everything
/// else → false — the `followers` nuance lives in the phone/web social
/// layer. The single source of truth for BOTH the normal stop path
/// (`snapshotIsPublic`) and crash recovery (`recoverCheckpoint`), so a
/// recovered run can't drift from a normally-stopped one.
internal fun isPublicFromPrivacyDefault(privacyDefault: String?): Boolean? =
    privacyDefault?.let { it == "public" }

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
    private val routesBridge = RoutesBridge(application)
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

    /// Serialises `drainQueue`. Cold start alone fires two — the cached-
    /// session restore and the phone-bridge restore — and neither is held
    /// off by backoff at zero failures. Two passes over the same snapshot
    /// upload every queued run twice (a multi-MB ultra track over LTE) and
    /// race each other's queue removal and track-file deletion. Whoever
    /// arrives second now waits and re-reads the queue, which by then is
    /// drained.
    private val drainMutex = Mutex()

    /// Set once the cache→files track migration + orphan sweep have run.
    /// Guarded by `drainMutex`, which is what orders it ahead of the first
    /// upload: a drain must never read a queue entry whose path still points
    /// at the purgeable location.
    private var trackStorageReconciled = false

    /// Last-resort net under every coroutine this view model starts.
    ///
    /// `viewModelScope` carries a `SupervisorJob`, which stops one failing
    /// child from cancelling its siblings but does NOT stop an unhandled throw
    /// from reaching the thread's uncaught handler — and on Android that ends
    /// the process the recording service is in. Twenty-three `launch` sites
    /// each had to remember their own `try` for a run not to die of a route
    /// cache write; § 1055 closed the one that had already cost a run, and the
    /// residual was every site nobody had reached yet.
    ///
    /// It is a net, not a substitute. A site whose failure the runner should
    /// hear about still catches and says so — this only decides what happens
    /// to the ones that say nothing, and "logged" beats "process gone".
    private val crashGuard = CoroutineExceptionHandler { _, e ->
        Log.e(TAG, "unhandled failure in a view-model coroutine", e)
    }

    /// Every `launch` in this class goes through here. `ViewModelStreamResilienceTest`
    /// fails the build on a bare `viewModelScope.launch`, because a handler
    /// installed on 22 of 23 sites is the same defect with better odds.
    private fun launchGuarded(block: suspend CoroutineScope.() -> Unit): Job =
        viewModelScope.launch(crashGuard, block = block)

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
        observeRoutesBridge()
    }

    /// Tracks the `updated_at_ms` of the last phone push the watch
    /// actually applied. A Wearable Data Layer reconnect after a
    /// watch reboot can deliver an older DataItem after a newer one;
    /// without the gate, the watch would roll its starred set back
    /// to the older state. `shouldApplyRoutesPush` decides per
    /// arrival whether to apply or drop.
    private var lastAppliedRoutesPushMs: Long = 0L

    /// Listen for starred-route pushes from the paired phone. Phone-side
    /// `WearRoutesBridge` forwards the user's starred subset on every
    /// `LocalRouteStore` change; the watch overwrites its DataStore cache
    /// + the live picker so a watch out of network range stays current
    /// with whatever was last starred on the phone. Supabase fetch in
    /// `refreshRoutes()` remains the canonical refresh path when the
    /// watch has its own connectivity.
    private fun observeRoutesBridge() {
        launchGuarded {
            try {
                routesBridge.current()?.let { push ->
                    if (push.routes.isNotEmpty() &&
                        shouldApplyRoutesPush(lastAppliedRoutesPushMs, push.updatedAtMs)
                    ) {
                        routeStore.save(push.routes)
                        val recents = routeStore.recentIds.first()
                        _state.value = _state.value.copy(
                            routes = sortByRecency(push.routes, recents),
                        )
                        lastAppliedRoutesPushMs = push.updatedAtMs
                    }
                }
            } catch (_: Throwable) { /* best-effort cold-start hydrate */ }
        }
        launchGuarded {
            routesBridge.events
                .catch { e -> Log.w(TAG, "routes bridge stream failed", e) }
                .collect { push ->
                    try {
                        if (!shouldApplyRoutesPush(lastAppliedRoutesPushMs, push.updatedAtMs)) {
                            // Stale or out-of-order delivery — keep the
                            // current state, don't roll back.
                            return@collect
                        }
                        routeStore.save(push.routes)
                        val recents = routeStore.recentIds.first()
                        _state.value = _state.value.copy(
                            routes = sortByRecency(push.routes, recents),
                        )
                        lastAppliedRoutesPushMs = push.updatedAtMs
                    } catch (e: Throwable) {
                        Log.w(TAG, "routes bridge event failed", e)
                    }
                }
        }
    }

    private fun observeRecording() {
        recordingObserverJob = launchGuarded {
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
                            hrAvailability = m.hrAvailability,
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
        racePingJob = launchGuarded {
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

    /// `Flow.catch` was the wrong operator here and its cost was total: catch
    /// COMPLETES the flow, so one failed read froze `queuedCount` at its last
    /// value for the life of the process — 0 on a cold start — and the pre-run
    /// "Sync N runs" chip, gated on `queuedCount > 0`, never appeared again. A
    /// runner rebooting into a corrupt queue was shown nothing at all. Catching
    /// is not a judgement about corruption; it is a judgement that the FIRST
    /// failure is the LAST one, which nothing establishes. Retrying makes the
    /// cheap distinguishing test — read it again — and costs one file open
    /// (decisions § 1104).
    private fun observeQueue() {
        queueWatchJob = launchGuarded {
            store.queue
                .retryWhen { e, attempt ->
                    Log.w(TAG, "run queue stream failed, retry $attempt", e)
                    _state.value = _state.value.copy(queueUnreadable = true)
                    delay(queueReadRetryDelayMs(attempt))
                    true
                }
                .collect { list ->
                val wasUnreadable = _state.value.queueUnreadable
                _state.value = _state.value.copy(
                    queuedCount = list.size,
                    queueUnreadable = false,
                    thisRunSynced = _state.value.thisRunId?.let { id ->
                        list.none { it.id == id }
                    } ?: _state.value.thisRunSynced,
                )
                onQueueBecameReadable(wasUnreadable)
            }
        }
    }

    private fun observeConnectivity() {
        connectivityJob = launchGuarded {
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
        racePollJob = launchGuarded {
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
        launchGuarded {
            val cached = sessionStore.current()
            if (cached != null) {
                applySession(cached)
                refreshIfExpired(cached)
                drainQueue()
                return@launchGuarded
            }
            if (BuildConfig.BYPASS_LOGIN) {
                try {
                    signInWithEmailInternal("runner@test.com", "testtest")
                } catch (_: Throwable) { /* sign-in screen will surface */ }
            }
        }
        launchGuarded {
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
        launchGuarded {
            sessionBridge.events
                .catch { e -> Log.w(TAG, "session bridge stream failed", e) }
                .collect { event ->
                    try {
                        when (event) {
                            is SessionEvent.Updated -> {
                                val stored = StoredSession.fromPayload(event.payload)
                                sessionStore.save(stored)
                                applySession(stored)
                                drainQueue()
                            }
                            SessionEvent.Cleared -> tearDownSession()
                        }
                    } catch (e: Throwable) {
                        // Encrypted-store I/O, the route + run + tile wipes and
                        // the drain all run from here. The sibling one-shot
                        // read of the same payload was already guarded; this
                        // one was not, so a throw reached the thread's
                        // uncaught handler and took the recording service
                        // down with the process. `launchGuarded` is the net
                        // under that now; this stays because a failure the
                        // runner's session depends on is worth naming here
                        // rather than reading as an anonymous crash.
                        Log.w(TAG, "session bridge event failed", e)
                    }
                }
        }
    }

    /// Shared teardown for both the user-initiated `signOut` and the
    /// phone-side sign-out signal that arrives on the SessionBridge as
    /// `SessionEvent.Cleared`. Mirrors `signOut`'s state mutation so the
    /// two paths can't drift.
    ///
    /// Sign-out is the single point where every per-user cache on the
    /// watch is wiped so nothing carries over to the next user:
    ///   - in-memory Supabase credentials (`clearCredentials`)
    ///   - the encrypted session (`sessionStore`)
    ///   - the route cache (`routeStore`)
    ///   - the upload queue + its on-disk track files (`store`) — see
    ///     `LocalRunStore.clear` for why this is fail-closed against
    ///     cross-user upload
    ///   - the crash checkpoint + its track file (`checkpoints`), which is
    ///     the SAME payload on a parallel path and used to outlive the
    ///     queue wipe entirely
    ///   - cached map tiles (`TileSource`)
    private suspend fun tearDownSession() {
        supabase.clearCredentials()
        sessionStore.clear()
        routeStore.clear()
        // Drop unsynced runs (+ their track files) so they can't upload
        // under the next user's credentials. See LocalRunStore.clear.
        store.clear()
        // And the crash checkpoint, on exactly the same reasoning. It is the
        // same run payload — distance, start, laps, steps, privacy default and
        // a track file — reached by a different door, and it survived the wipe
        // above: `sweepOrphanTracks` deliberately KEEPS the file a checkpoint
        // names, so after a sign-out `gradeRecovery` still graded `Offer` (no
        // live recording, nothing queued, the file present) and the next user
        // to sign in was shown a prompt carrying the previous user's distance.
        // Accepting it queued that run and drained it under the NEW
        // credentials — user A's GPS trace into user B's account and Storage
        // prefix, public if A's privacy default was public. Fail-closed, at
        // the cost of a crashed run that is never recovered because the runner
        // signed out before recovering it (decisions § 1301).
        val stranded = checkpoints.current()
        checkpoints.clear()
        if (stranded != null) {
            withContext(Dispatchers.IO) {
                runCatching { File(stranded.trackFilePath).delete() }
            }
        }
        // Drop cached map tiles too — prefetched route tiles reveal where
        // the signed-out user runs, so they don't carry over to the next
        // user on this watch.
        try {
            com.runapp.watchwear.ui.TileSource.get(getApplication()).clear()
        } catch (e: Throwable) {
            // Not cosmetic: the cache that survives is a map of where the
            // signed-out user runs. Nothing here can force it, but a
            // silent failure left no trace that it had happened.
            Log.w(TAG, "tile cache not cleared on sign-out", e)
        }
        authReady.value = false
        _state.value = _state.value.copy(
            authed = false,
            authError = null,
            stage = Stage.PreRun,
            routes = emptyList(),
            selectedRoute = null,
            // The prompt may already be on screen — `checkRecovery` runs from
            // `init` — and it outlived the checkpoint it was raised for, so a
            // tap after sign-out would have queued a run the store above just
            // dropped.
            pendingRecovery = null,
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

    /// Re-raise the recovery prompt `checkRecovery` withheld because the queue
    /// could not be read. Called from wherever the unreadable flag is CLEARED,
    /// which is both readers of that one file — the stream, which retries on
    /// its own backoff, and the drain, which is what the runner's own retry
    /// goes through.
    ///
    /// Until the read recovers there is nothing to re-raise: `gradeRecovery`
    /// answers `Ignore` and changes nothing, deliberately, because the queue
    /// is the only thing that can say whether the run is already banked
    /// somewhere better than this snapshot (decisions § 1107). The checkpoint
    /// survives to the next launch either way, so this is not what makes the
    /// run safe — it is what stops a runner being made to relaunch the app for
    /// a fault that has already cleared underneath them.
    ///
    /// Gated on the TRANSITION so the ordinary per-save emission does not
    /// re-read the checkpoint store on every queue change, and skipped while a
    /// prompt is already up so an arriving emission cannot swap the checkpoint
    /// under a decision the runner is mid-way through making (decisions § 1154).
    private fun onQueueBecameReadable(wasUnreadable: Boolean) {
        if (!wasUnreadable) return
        if (_state.value.pendingRecovery != null) return
        checkRecovery()
    }

    private fun checkRecovery() {
        launchGuarded {
            val cp = checkpoints.current() ?: return@launchGuarded
            when (gradeRecovery(cp)) {
                RecoveryAction.Offer ->
                    _state.value = _state.value.copy(pendingRecovery = cp)
                RecoveryAction.Discard -> checkpoints.clear()
                RecoveryAction.Ignore -> Unit
            }
        }
    }

    /// `store.contains` reads the same DataStore-backed queue the drain and the
    /// pre-run count read, and it fails the same way: a corrupt file THROWS
    /// rather than reads empty. It threw straight out of both callers into
    /// `launchGuarded`, which logs and swallows — so a cold start into an
    /// unreadable queue silently withheld the recovery prompt for a crashed
    /// run whose checkpoint is its only durable record, and a tap on that
    /// prompt did nothing at all (decisions § 1107).
    ///
    /// The two answers the failure could stand in for are not symmetric and
    /// the destructive one is not the cautious one: reading it as "already
    /// queued" grades `Discard`, which DELETES the checkpoint on precisely the
    /// condition under which the queue cannot be holding the run instead.
    /// Reading it as "not queued" grades `Offer`, and the recovery it offers
    /// cannot complete — `store.save` reads the same file. So the failure is
    /// its own answer: `Ignore` already means "leave it completely alone,
    /// neither prompt nor clear", the net stays armed, and the grade is retaken
    /// on the next launch.
    private suspend fun gradeRecovery(cp: Checkpoint): RecoveryAction {
        val alreadyQueued = try {
            store.contains(cp.runId)
        } catch (e: Throwable) {
            Log.e(TAG, "run queue unreadable — checkpoint left armed, ungraded", e)
            _state.value = _state.value.copy(queueUnreadable = true)
            return RecoveryAction.Ignore
        }
        return recoveryActionFor(
            activeRecording = RecordingRepository.metrics.value.stage !=
                RecordingRepository.Stage.Idle,
            alreadyQueued = alreadyQueued,
            trackFileExists = withContext(Dispatchers.IO) { File(cp.trackFilePath).exists() },
        )
    }

    /// User accepted the recovery prompt. Treat the checkpointed run as
    /// finished-as-of-savedAt and queue it for upload. The track file is
    /// already sealed on disk (the writer closes on service destroy), but
    /// may be an unclosed JSON array if the process was killed mid-flush;
    /// we re-seal it defensively before queueing.
    ///
    /// The grade is taken again here, not just when the prompt was raised:
    /// `bootstrapAuth` drains the queue on the same cold start, so a run that
    /// was merely queued when the prompt appeared can be uploaded — and its
    /// track file deleted — while the prompt sits on screen waiting for a tap.
    fun recoverCheckpoint() {
        val cp = _state.value.pendingRecovery ?: return
        launchGuarded {
            when (gradeRecovery(cp)) {
                RecoveryAction.Offer -> Unit
                // The run is captured somewhere strictly better than this
                // snapshot, so the snapshot goes. This is the only grade that
                // may clear it.
                RecoveryAction.Discard -> {
                    checkpoints.clear()
                    _state.value = _state.value.copy(pendingRecovery = null)
                    return@launchGuarded
                }
                // Nothing may be destroyed on this one. `Ignore` is either a
                // live recording whose crash-safety net this checkpoint IS, or
                // a queue that could not be read at all — and the old
                // `!= Offer` branch cleared the checkpoint on both, disarming
                // the net in the first case and dropping the run's only
                // durable record in the second. The prompt stays up too, so
                // the affordance is not silently taken away; the tap does
                // nothing until the read recovers, which is filed
                // (decisions § 1107).
                RecoveryAction.Ignore -> return@launchGuarded
            }
            val durationS = checkpointActiveDurationS(cp)
            // A recovered run is graded the same way the normal stop path
            // grades one; a checkpoint carrying no coverage measurement claims
            // none and keeps its average (decisions § 1083).
            val hr = heartRateClaim(
                bpmSum = cp.bpmSum,
                bpmCount = cp.bpmCount,
                hrAvailableMs = cp.hrAvailableMs,
                activeElapsedMs = durationS * 1000L,
            )
            val avgBpm = hr.avgBpm
            val sealed = sealTrackFile(cp.trackFilePath) ?: run {
                checkpoints.clear()
                _state.value = _state.value.copy(pendingRecovery = null)
                return@launchGuarded
            }
            store.save(
                QueuedRun(
                    id = cp.runId,
                    startedAtIso = Instant.ofEpochMilli(cp.startedAtMs).toString(),
                    durationS = durationS,
                    distanceM = cp.distanceM,
                    trackFilePath = sealed.absolutePath,
                    avgBpm = avgBpm,
                    hrCoverage = hr.coverage,
                    activityType = cp.activityType,
                    laps = cp.laps.map { QueuedLap(it.number, it.atMs, it.distanceM) },
                    steps = cp.steps,
                    // Same snapshot the normal stop path stamps — the
                    // checkpoint carried the privacy default from record
                    // time, so a recovered run uploads with the runner's
                    // visibility, not the always-non-public DB default.
                    isPublic = isPublicFromPrivacyDefault(cp.privacyDefault),
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
    /// `TrackWriter.close` ran), append one so it parses as JSON. Null when
    /// the file is gone — see `sealTrackFileOrNull` for why that is not
    /// stubbed into an empty array.
    private suspend fun sealTrackFile(path: String): File? =
        withContext(Dispatchers.IO) { sealTrackFileOrNull(File(path)) }

    fun discardCheckpoint() {
        launchGuarded {
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
        launchGuarded {
            val settings = supabase.fetchUniversalSettings() ?: return@launchGuarded
            // privacy_default — stash regardless of stage; the snapshot
            // matters at handleFinishedRun, which can run minutes or
            // hours after the fetch returns.
            universalPrivacyDefault = settings.privacyDefault
            // hr-zone cutoffs — resolved in priority order (explicit
            // hr_zones > max_hr_bpm > Tanaka 208−0.7×age from DOB). Stored on the
            // VM state so the RunningScreen can render "Z3" next to
            // BPM. Updated regardless of stage; null cutoffs disable
            // the badge silently.
            val resolved = resolveZoneCutoffs(settings, System.currentTimeMillis())
            _state.value = _state.value.copy(
                hrZoneCutoffs = resolved,
                bodyWeightKg = settings.bodyWeightKg,
                showCalories = settings.showCalories,
                preferredUnit = com.runapp.watchwear.recording.DistanceUnit
                    .fromPref(settings.preferredUnit),
            )
            // default_activity_type — only prime; never override a
            // started run or a manual chip choice.
            val preferred = settings.defaultActivityType ?: return@launchGuarded
            val s = _state.value
            if (s.stage != Stage.PreRun) return@launchGuarded
            if (s.activityType != "run") return@launchGuarded
            _state.value = s.copy(activityType = preferred)
        }
    }

    /// Map the universal `privacy_default` ("public" / "followers" /
    /// "private") to the wrist's boolean snapshot. Null when the bag
    /// fetch hasn't returned or returned no value — caller omits the
    /// column and the DB default (`false`) applies.
    internal fun snapshotIsPublic(): Boolean? =
        isPublicFromPrivacyDefault(universalPrivacyDefault)

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
                authError = getApplication<Application>().getString(
                    R.string.token_refresh_failed,
                    e.message ?: e.javaClass.simpleName,
                ),
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
            hrAvailability = HeartRateAvailability.Off,
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
            preferredUnit = _state.value.preferredUnit,
            privacyDefault = universalPrivacyDefault,
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
        launchGuarded {
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
        if (!authReady.value) {
            _state.value = _state.value.copy(routesUnavailable = true)
            return
        }
        _state.value = _state.value.copy(routesLoading = true)
        launchGuarded {
            try {
                val fresh = supabase.fetchRoutes()
                routeStore.save(fresh)
                _state.value = _state.value.copy(
                    routes = sortByRecency(fresh, routeStore.recentIds.first()),
                    routesLoading = false,
                    routesUnavailable = false,
                )
            } catch (_: Throwable) {
                _state.value = _state.value.copy(
                    routesLoading = false,
                    routesUnavailable = true,
                )
            }
        }
    }

    /// Stable-sort: routes whose IDs appear in `recentIds` first,
    /// in LRU order; everything else preserves its incoming
    /// (`updated_at desc`) order. Thin wrapper around the file-level
    /// [sortRoutesByRecency] so test code can exercise the math
    /// without instantiating the ViewModel.
    private fun sortByRecency(
        routes: List<SavedRoute>,
        recentIds: List<String>,
    ): List<SavedRoute> = sortRoutesByRecency(routes, recentIds)

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
        launchGuarded {
            try {
                val fix = gpsForPrefetch.lastLocation() ?: return@launchGuarded
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
        launchGuarded {
            // Bump LRU so the next picker open puts this route at
            // the top regardless of `updated_at` on the server.
            try {
                routeStore.pushRecent(route.id)
            } catch (e: Throwable) {
                Log.w(TAG, "route LRU not updated", e)
            }
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
    private suspend fun handleFinishedRun(m: RecordingRepository.Metrics) {
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
        // The graded claim, and there is no ungraded one to read by mistake:
        // `Metrics` carries the finished pair or nothing (decisions § 1105).
        // Null is a `Finished` transition made by something other than
        // `stopRecording`, and it claims no heart rate rather than falling
        // back to a figure nothing measured.
        val hr = m.finishedHr
        val summary = FinishedSummary(
            distanceM = m.distanceM,
            durationS = durationS,
            avgBpm = hr?.avgBpm,
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
        launchGuarded {
            store.save(
                QueuedRun(
                    id = runId,
                    startedAtIso = Instant.ofEpochMilli(m.startedAtMs).toString(),
                    durationS = durationS,
                    distanceM = m.distanceM,
                    trackFilePath = trackPath,
                    avgBpm = hr?.avgBpm,
                    hrCoverage = hr?.coverage,
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
            // Only now is the run recorded somewhere the checkpoint is no
            // longer needed for, so only now may the checkpoint go. The
            // service used to clear it as it tore itself down, in parallel
            // with this write: a kill between the two — likeliest right
            // there, since the process has just left foreground-service
            // state — erased the queue entry and the snapshot that would
            // have rebuilt it. Clearing after the write means the worst
            // case is a checkpoint outliving a banked run, which
            // `recoveryActionFor` discards without prompting.
            checkpoints.clear()
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
        launchGuarded {
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
        launchGuarded {
            if (id != null) store.remove(id)
            startNextRun()
        }
    }

    // ----- Sign in / out -----

    fun signOut() {
        launchGuarded { tearDownSession() }
    }

    fun openSignIn() {
        _state.value = _state.value.copy(stage = Stage.SignIn, authError = null)
    }

    fun cancelSignIn() {
        _state.value = _state.value.copy(stage = Stage.PreRun)
    }

    fun signInWithEmail(email: String, password: String) {
        launchGuarded {
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
        // Outside the lock: a 3 s wait for a session that may never arrive
        // must not make a runner's manual Sync chip queue behind it.
        if (!awaitAuth()) return
        drainMutex.withLock { drainQueueLocked(force) }
    }

    private suspend fun drainQueueLocked(force: Boolean) {
        reconcileTrackStorage()
        if (!force && drainBackoff.isInBackoff()) {
            // Auto-trigger (network-flap, auth-bootstrap) inside the backoff
            // window — don't hammer the backend. User-initiated drains pass
            // force=true so a manual Sync chip always fires.
            return
        }
        // An unreadable queue is not an empty one, and the three things this
        // could do are not equivalent. DataStore reports a corrupt or
        // unreadable file by FAILING the read, so treating the failure as an
        // empty list drains nothing, arms no backoff and clears the error
        // banner — the runner is told their runs are synced by the same code
        // path that could not open the file holding them. Letting it throw is
        // worse still: this runs under `drainMutex` inside a coroutine, and
        // before `launchGuarded` it ended the process the recording service
        // was in. So it is reported, and it arms backoff because the condition
        // persists — every network flap would otherwise retry a read that
        // cannot succeed — while a `force` drain (the Sync chip, a fresh
        // sign-in) still gets through, which is the one thing that makes a
        // retry after a reboot possible.
        val snapshot = try {
            store.queue.first()
        } catch (e: Throwable) {
            Log.e(TAG, "run queue unreadable — drain skipped", e)
            drainBackoff.onFailure()
            // The same flag the stream raises. Two readers of one file, so
            // whichever read last decides whether the count on screen still
            // stands — otherwise tapping the retry chip could fix the drain
            // and leave the chip claiming the queue is still unreadable, or
            // the reverse.
            _state.value = _state.value.copy(
                queueUnreadable = true,
                syncError = getApplication<Application>()
                    .getString(R.string.sync_queue_unreadable),
            )
            return
        }
        val wasUnreadable = _state.value.queueUnreadable
        _state.value = _state.value.copy(queueUnreadable = false)
        onQueueBecameReadable(wasUnreadable)
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
            onSuccessfulDrain = OnSuccessfulDrain { id -> dropQueuedRun(id, snapshot) },
        )
        if (result.anyTransientFailure) {
            drainBackoff.onFailure()
        } else {
            drainBackoff.onSuccess()
        }
        // `syncError` keeps its clear-on-success semantics — a trailing
        // success clearing the banner is a stated decision, pinned twice in
        // `DrainQueueLoopTest`, and this does not reverse it. The permanent
        // rejections ride a separate field precisely because they must
        // survive that clear: the banner is about this pass, a refused entry
        // is about the queue (decisions § 1347).
        _state.value = _state.value.copy(
            syncError = result.lastError,
            rejectedRunIds = rejectedAfterPass(
                previouslyRejected = _state.value.rejectedRunIds,
                queuedIdsBeforePass = snapshot.map { it.id },
                result = result,
            ),
        )
    }

    /// Drop the queue entries the server has permanently refused, and their
    /// tracks with them.
    ///
    /// The only exit from a stuck entry. `drainQueue` cannot clear it — the
    /// server refuses it on every pass — and the PostRun `discard` acts on
    /// `thisRunId`, the run the runner just finished, so it stops being
    /// reachable the moment they leave that screen. Guarded by the estate's
    /// two-press confirm at the call site (decisions § 1347).
    ///
    /// Scoped to the ids the last drain pass judged rather than to the queue
    /// as it stands: a run saved between the pass and the tap has never been
    /// tried, and clearing "everything queued" would destroy it unasked.
    ///
    /// Entry first, file second — the same ordering the drain uses, so a
    /// process death between the two leaves a stranded file for
    /// `sweepOrphanTracks` rather than an entry pointing at a payload that is
    /// gone.
    fun discardRejectedRuns() {
        val ids = _state.value.rejectedRunIds
        if (ids.isEmpty()) return
        launchGuarded {
            val snapshot = try {
                store.queue.first()
            } catch (e: Throwable) {
                // Same surface the drain raises for the same fault, so the two
                // readers of one file cannot leave the screen claiming
                // different things about it.
                Log.e(TAG, "run queue unreadable — discard skipped", e)
                _state.value = _state.value.copy(
                    queueUnreadable = true,
                    syncError = getApplication<Application>()
                        .getString(R.string.sync_queue_unreadable),
                )
                return@launchGuarded
            }
            for (id in ids) {
                dropQueuedRun(id, snapshot)
            }
            _state.value = _state.value.copy(
                rejectedRunIds = emptySet(),
                syncError = null,
            )
        }
    }

    /// Drop one queue entry and the track file it points at, in that order.
    ///
    /// Queue entry first, file second. The reverse order lets a process death
    /// between the two leave an entry pointing at a payload that is gone,
    /// which the next drain would then re-post with a null `track_url` —
    /// clobbering the track it had in fact already uploaded. This way the only
    /// crash residue is a stranded file, swept by `reconcileTrackStorage`.
    ///
    /// One home for that ordering because both callers need it and neither is
    /// the obvious owner: the drain drops a run it has just uploaded, the
    /// rejected-queue discard drops one that never will. It was two
    /// byte-identical copies until § 1347 added the second caller.
    ///
    /// `snapshot` is the queue as the caller read it — the path is looked up
    /// there rather than re-read, so a concurrent write cannot make the delete
    /// miss the file the entry named.
    private suspend fun dropQueuedRun(id: String, snapshot: List<QueuedRun>) {
        store.remove(id)
        snapshot.firstOrNull { it.id == id }?.let { run ->
            withContext(Dispatchers.IO) {
                runCatching { File(run.trackFilePath).delete() }
            }
        }
    }

    private suspend fun pushRun(run: QueuedRun) {
        val metadata: JsonObject = buildRunMetadata(
            activityType = run.activityType,
            avgBpm = run.avgBpm,
            hrCoverage = run.hrCoverage,
            steps = run.steps,
            laps = run.laps,
            lastModifiedAtIso = Instant.now().toString(),
        )
        // A queued run whose payload is gone is uploaded without one rather
        // than left in the queue promising a sync that can never happen. The
        // file is only ever deleted after the entry is removed, so a missing
        // file means the track was never uploaded — posting a null
        // `track_url` cannot erase one already in Storage.
        val trackFile = withContext(Dispatchers.IO) {
            File(run.trackFilePath).takeIf { it.exists() }
        }
        supabase.saveRun(
            runId = run.id,
            startedAtIso = run.startedAtIso,
            durationS = run.durationS,
            distanceM = run.distanceM,
            trackFile = trackFile,
            metadata = metadata,
            isPublic = run.isPublic,
        )
    }

    /// Bring the track directory and the upload queue back into agreement.
    /// Runs once per process, under `drainMutex` so no upload can observe a
    /// half-migrated queue.
    private suspend fun reconcileTrackStorage() {
        if (trackStorageReconciled) return
        trackStorageReconciled = true
        val app = getApplication<Application>()
        val durableDir = TrackStorage.durableDir(app)
        val queued = try {
            store.migrateTrackFiles(TrackStorage.legacyCacheDir(app), durableDir)
        } catch (_: Throwable) {
            // A failed migration must not block the drain — the entries that
            // did move are already persisted, the rest retry next launch.
            return
        }
        // Sweeping while a recording is live would race the open writer, whose
        // file is not in the queue yet — leave it to a later launch.
        if (RecordingRepository.metrics.value.stage != RecordingRepository.Stage.Idle) return
        val keep = buildSet {
            queued.forEach { add(it.trackFilePath) }
            // The crash checkpoint's track is the payload a pending recovery
            // rebuilds the run from; it is not queued until the runner
            // accepts the prompt.
            checkpoints.current()?.trackFilePath?.let { add(it) }
            RecordingRepository.metrics.value.trackFilePath?.let { add(it) }
        }
        withContext(Dispatchers.IO) {
            sweepOrphanTracks(durableDir, keep, System.currentTimeMillis())
        }
    }

    /// Read the just-finished track JSON off disk so the post-run
    /// screen can render a preview thumbnail. Decimates to ≤ 256
    /// points (geometric every-other halving, same shape-preserving
    /// strategy as the in-run track overlay) so a 4-hour run with
    /// thousands of points still draws cheaply on a 96 dp canvas.
    /// Returns empty on any failure — caller treats that as
    /// "indoor / no track to preview".
    ///
    /// On `Dispatchers.IO`, like every other disk touch in this class. It was
    /// the one that was not, and it is the largest: `handleFinishedRun` runs
    /// in the `RecordingRepository.metrics` collect body, which is
    /// `Dispatchers.Main.immediate`, so a 100-hour ultra's ~36,000-record,
    /// ~2.8 MB track was read AND fully materialised as a `JsonArray` on the
    /// UI thread between the runner pressing Stop and the post-run screen
    /// appearing (decisions § 1302). The decimation runs here too — it is
    /// the parse that is expensive, and there is nothing to hand back until
    /// it is done.
    private suspend fun readTrackForPreview(
        path: String,
    ): List<com.runapp.watchwear.recording.RouteMath.LatLng> = withContext(Dispatchers.IO) {
        try {
            val raw = File(path).takeIf { it.exists() }?.readText()
                ?: return@withContext emptyList()
            val arr = (kotlinx.serialization.json.Json.parseToJsonElement(raw)
                as? kotlinx.serialization.json.JsonArray) ?: return@withContext emptyList()
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

    /// Turn the service's raw lap list (cumulative marks) into split-per-lap
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
        private const val TAG = "RunViewModel"
    }

    class Factory(private val application: Application) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            RunViewModel(application) as T
    }
}
