package com.runapp.watchwear.recording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.runapp.watchwear.BuildConfig
import com.runapp.watchwear.GpsEvent
import com.runapp.watchwear.GpsPoint
import com.runapp.watchwear.GpsRecorder
import com.runapp.watchwear.HeartRateAvailability
import com.runapp.watchwear.HeartRateMonitor
import com.runapp.watchwear.MainActivity
import com.runapp.watchwear.Pedometer
import com.runapp.watchwear.R
import com.runapp.watchwear.tiles.formatElapsed
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/// Foreground service that owns the GPS + HR streams during a run.
///
/// Engineered for ultra-marathon duration:
///   - Track points stream to a file on disk (`TrackWriter`) rather
///     than into an unbounded in-memory list.
///   - HR uses a running sum/count, not a list, so 10 hours of 1Hz
///     samples is O(1) memory instead of 36,000 allocations.
///   - Checkpoints save only a small summary — the actual track data
///     is already on disk via the streaming writer.
///   - Notification refresh throttles to every 5s instead of every
///     500ms, so a 10h run is ~7,200 refreshes, not 72,000.
///
/// State machine (Start → Recording → [Pause → Paused → Resume →
/// Recording]* → Stop → Finished) plus lap markers.
class RunRecordingService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var gpsJob: Job? = null
    private var gpsRetryJob: Job? = null
    private var hrJob: Job? = null
    private var stepsJob: Job? = null
    private var tickerJob: Job? = null
    private var checkpointJob: Job? = null

    private lateinit var gps: GpsRecorder
    private lateinit var hr: HeartRateMonitor
    private lateinit var pedometer: Pedometer
    private lateinit var checkpoints: CheckpointStore
    private var wakeLock: PowerManager.WakeLock? = null
    private var trackWriter: TrackWriter? = null
    private var tts: TtsAnnouncer? = null
    /// Highest split we've already spoken. `completedSplits(dist, unit) >
    /// lastAnnouncedSplit` triggers an announcement, so the cue lands on the
    /// runner's own unit — a mi-mode runner is told at each mile, not at each
    /// kilometre. Resets to 0 at the start of each run.
    private var lastAnnouncedSplit = 0
    /// Rate-limit for pace alerts: do not re-fire within this window.
    /// Matches the 30 s gap used on Android.
    private var lastPaceAlertAtMs = 0L

    private var lastLocation: Location? = null
    /// Wall-clock timestamp of the most recent GPS point delivered while
    /// Recording. Used by the self-heal watchdog to re-subscribe if the
    /// FusedLocationProviderClient stream goes silent despite availability
    /// reporting true. `0L` means "no point received yet in this run" —
    /// the indoor / no-GPS case, which is a legitimate state.
    private var lastPointAtMs = 0L
    private val laps = mutableListOf<RecordingRepository.Lap>()
    private var startedAtMs = 0L
    private var runId: String = ""
    private var activityType: String = "run"
    /// Planned route waypoints for this run, parsed once from the
    /// ACTION_START intent. Empty when the runner didn't pick a route;
    /// `RouteMath` helpers below skip when this is empty.
    private var routeWaypoints: List<com.runapp.watchwear.recording.RouteMath.LatLng> =
        emptyList()
    /// Downsampled rolling buffer of recent GPS points for the on-watch
    /// mini-map's "where I've been" overlay. Capped at
    /// `MAX_TRACK_OVERLAY_POINTS` — when we'd overflow, drop every
    /// other point so density halves and the buffer is geometrically
    /// uniform across the whole run. Memory is therefore O(cap)
    /// regardless of run length, which is what makes this safe to
    /// hold in memory alongside the disk-backed full track.
    private val trackOverlay = mutableListOf<com.runapp.watchwear.recording.RouteMath.LatLng>()
    /// Seconds-per-km target set via the pre-run pace chip. Null means
    /// no target; the pace-alert branch in `onGps` is a no-op in that
    /// case. Non-null values fire a haptic + TTS alert whenever the
    /// live pace drifts >30 s from the target.
    private var targetPaceSecPerKm: Int? = null

    /// Distance-display unit for this run, parsed once from the
    /// ACTION_START intent. Stamped into `RecordingRepository.Metrics` so
    /// the active-run tile renders in the runner's chosen unit.
    private var preferredUnit: DistanceUnit = DistanceUnit.KM

    /// Monotonic stamp of the last accepted/rebased anchor. See the re-anchor
    /// escape in onGps.
    private var lastAnchorRealtimeMs: Long = 0L

    /// Runner's universal `privacy_default` ("public" / "followers" /
    /// "private"), passed once from the ACTION_START intent and written
    /// into every checkpoint so a crash-recovered run honours the same
    /// visibility the normal stop path (`RunViewModel.snapshotIsPublic`)
    /// would apply. Null when the prefs bag hadn't loaded at run start —
    /// recovery then falls back to the fail-closed DB default (non-public).
    private var privacyDefault: String? = null

    // Rolling HR aggregation instead of a list of every sample.
    // `bpmSum` / `bpmCount` let us compute avg in O(1) regardless of
    // how many samples have arrived.
    private var bpmSum = 0L
    private var bpmCount = 0L

    // How much of the run the sensor actually covered. `bpmSum`/`bpmCount`
    // alone say what the samples averaged, not what share of the run produced
    // them, and `avg_bpm` is read as the run's average either way
    // (decisions § 1083). `hrAvailableMs` accumulates on the ticker against
    // `lastHrSampleAtMs`; `lastHrTickElapsedMs` is the previous tick's ACTIVE
    // elapsed, so a paused stretch advances neither.
    private var hrAvailableMs = 0L
    private var lastHrSampleAtMs = 0L
    private var lastHrTickElapsedMs = 0L

    private var pausedAccumulatedMs = 0L
    private var pausedSinceMs = 0L

    // Tick counter for notification throttling — we update the repo
    // every 500ms (UI needs live elapsed), but the notification only
    // every 10 ticks (5s).
    private var tickIndex = 0

    override fun onCreate() {
        super.onCreate()
        gps = GpsRecorder(this)
        hr = HeartRateMonitor(this)
        pedometer = Pedometer(this)
        checkpoints = CheckpointStore(this)
        ensureChannel()
        if (BuildConfig.ENABLE_TTS) {
            tts = TtsAnnouncer(this)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording(
                runId = intent.getStringExtra(EXTRA_RUN_ID) ?: UUID.randomUUID().toString(),
                activity = intent.getStringExtra(EXTRA_ACTIVITY_TYPE) ?: "run",
                routeWaypointsJson = intent.getStringExtra(EXTRA_ROUTE_WAYPOINTS_JSON),
                targetPaceSecPerKm = intent
                    .getIntExtra(EXTRA_TARGET_PACE_SEC_PER_KM, 0)
                    .takeIf { it > 0 },
                unit = runCatching {
                    DistanceUnit.valueOf(intent.getStringExtra(EXTRA_PREFERRED_UNIT) ?: "KM")
                }.getOrDefault(DistanceUnit.KM),
                privacyDefault = intent.getStringExtra(EXTRA_PRIVACY_DEFAULT),
            )
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_LAP -> markLap()
            ACTION_STOP -> stopRecording()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        releaseWakeLock()
        trackWriter?.close()
        tts?.shutdown()
        tts = null
    }

    // ----- Lifecycle -----

    private fun startRecording(
        runId: String,
        activity: String,
        routeWaypointsJson: String?,
        targetPaceSecPerKm: Int?,
        unit: DistanceUnit,
        privacyDefault: String?,
    ) {
        if (RecordingRepository.metrics.value.isActive) return

        this.runId = runId
        this.activityType = activity
        this.targetPaceSecPerKm = targetPaceSecPerKm
        this.preferredUnit = unit
        this.privacyDefault = privacyDefault
        startedAtMs = System.currentTimeMillis()
        pausedAccumulatedMs = 0
        pausedSinceMs = 0
        laps.clear()
        lastLocation = null
        lastPointAtMs = 0L
        trackOverlay.clear()
        bpmSum = 0
        bpmCount = 0
        hrAvailableMs = 0
        lastHrSampleAtMs = 0
        lastHrTickElapsedMs = 0
        tickIndex = 0
        lastAnnouncedSplit = 0
        lastPaceAlertAtMs = 0L
        routeWaypoints = parseRouteWaypoints(routeWaypointsJson)
        tts?.announceStart()

        val file = TrackWriter.fileFor(applicationContext, runId)
        trackWriter = TrackWriter(file).also { it.open() }

        startForegroundCompat(buildNotification(elapsedMs = 0L, distanceM = 0.0, paused = false))
        acquireWakeLock()

        RecordingRepository.update {
            RecordingRepository.Metrics(
                stage = RecordingRepository.Stage.Recording,
                runId = runId,
                startedAtMs = startedAtMs,
                elapsedMs = 0L,
                activityType = activityType,
                trackFilePath = file.absolutePath,
                routeWaypoints = routeWaypoints,
                preferredUnit = preferredUnit,
                hrAvailability = if (BuildConfig.ENABLE_HR) {
                    HeartRateAvailability.Acquiring
                } else {
                    HeartRateAvailability.Off
                },
            )
        }
        com.runapp.watchwear.tiles.ActiveRunTileService.requestUpdate(this)

        subscribeToGps()
        // Self-healing GPS retry loop. Mirrors Android's
        // `_startGpsRetryLoop` in `packages/run_recorder/lib/src/run_recorder.dart`:
        // a periodic timer that (re-)opens the stream whenever the
        // subscription is dead. Two triggers, in priority order:
        //
        // 1. **Subscription died** (`gpsJob?.isActive != true`). Same
        //    shape as Android's `_positionSub == null` check. Covers
        //    service-level crashes, explicit cancellation, scope
        //    teardown, and the future "we'll null it on error" path.
        //
        // 2. **Stream silent mid-run** (Wear-specific). On the mobile
        //    Geolocator, a dead stream errors and we see it as
        //    `_positionSub == null`. FusedLocationProviderClient on Wear
        //    doesn't — the callback can stay registered while silently
        //    emitting nothing. So we additionally treat a recording
        //    that's received at least one point but nothing for
        //    [GPS_STALL_MS] as degenerate and force a resubscribe.
        //
        // Indoor / never-had-a-fix (`lastPointAtMs == 0L`) is NOT a
        // stall — it's a legitimate state and Android's loop would also
        // noop on it (the subscription is alive, just no fix yet).
        gpsRetryJob = scope.launch {
            while (true) {
                delay(GPS_RETRY_INTERVAL_MS)
                if (RecordingRepository.metrics.value.stage !=
                    RecordingRepository.Stage.Recording) continue

                val now = System.currentTimeMillis()
                // Decision in `shouldResubscribeGps` — unit-tested
                // independently (see `GpsRetryDecisionTest`).
                val decision = shouldResubscribeGps(
                    jobAlive = gpsJob?.isActive == true,
                    lastPointAtMs = lastPointAtMs,
                    nowMs = now,
                )
                if (decision.shouldResubscribe) {
                    subscribeToGps()
                    // Reset the staleness window so we don't thrash if
                    // the fresh subscription also takes a few seconds
                    // to start emitting.
                    if (decision.triggeredByStall) lastPointAtMs = now
                }
            }
        }
        if (BuildConfig.ENABLE_HR) {
            hrJob = scope.launch {
                hr.stream()
                    .catch { e ->
                        // The asynchronous half of "there will be no heart
                        // rate this run". `HeartRateMonitor` reports the
                        // refusal it can see and closes; a throw that gets
                        // past it lands here, and leaving the state at
                        // Acquiring would spin a caption forever.
                        android.util.Log.w(TAG, "heart rate stream failed", e)
                        RecordingRepository.update {
                            it.copy(
                                hrAvailability = HeartRateAvailability.Unavailable,
                                bpm = null,
                            )
                        }
                    }
                    .collect { update ->
                        val live = update.availability == HeartRateAvailability.Available
                        val sample = update.bpm
                        val paused = isPaused()
                        if (live && sample != null && !paused) {
                            bpmSum += sample
                            bpmCount++
                            lastHrSampleAtMs = SystemClock.elapsedRealtime()
                        }
                        RecordingRepository.update {
                            it.copy(
                                hrAvailability = update.availability,
                                // A sensor that is no longer reporting must
                                // not leave its last figure on screen: a watch
                                // that slipped off the wrist at minute three
                                // used to render that reading for the rest of
                                // the run.
                                bpm = when {
                                    !live -> null
                                    paused -> it.bpm
                                    else -> sample ?: it.bpm
                                },
                            )
                        }
                    }
            }
        }
        // Pedometer — subscribed regardless of HR flag because it has
        // no emulator-synthesis worry. `Pedometer.stream()` closes
        // silently on devices without `TYPE_STEP_COUNTER`, so this is
        // a no-op on hardware that doesn't support it.
        stepsJob = scope.launch {
            pedometer.stream()
                .catch { e -> android.util.Log.w(TAG, "step stream failed", e) }
                .collect { stepsThisRun ->
                    if (isPaused()) return@collect
                    RecordingRepository.update { it.copy(steps = stepsThisRun) }
                }
        }
        tickerJob = scope.launch {
            while (true) {
                delay(500)
                val elapsed = activeElapsedMs()
                advanceHrCoverage(elapsed)
                RecordingRepository.update { it.copy(elapsedMs = elapsed) }
                tickIndex++
                if (tickIndex % NOTIFICATION_THROTTLE_TICKS == 0) {
                    refreshNotification(elapsed, RecordingRepository.metrics.value.distanceM)
                }
            }
        }
        checkpointJob = scope.launch {
            delay(CHECKPOINT_INITIAL_DELAY_MS)
            while (true) {
                writeCheckpoint()
                delay(CHECKPOINT_INTERVAL_MS)
            }
        }
    }

    private fun markLap() {
        if (!RecordingRepository.metrics.value.isActive) return
        val lap = RecordingRepository.Lap(
            number = laps.size + 1,
            atMs = activeElapsedMs(),
            distanceM = RecordingRepository.metrics.value.distanceM,
        )
        laps.add(lap)
        RecordingRepository.update { it.copy(laps = laps.toList()) }
    }

    private fun pauseRecording() {
        if (RecordingRepository.metrics.value.stage != RecordingRepository.Stage.Recording) return
        pausedSinceMs = System.currentTimeMillis()
        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Paused) }
        val elapsed = activeElapsedMs()
        refreshNotification(elapsed, RecordingRepository.metrics.value.distanceM, paused = true)
        com.runapp.watchwear.tiles.ActiveRunTileService.requestUpdate(this)
    }

    private fun resumeRecording() {
        if (RecordingRepository.metrics.value.stage != RecordingRepository.Stage.Paused) return
        if (pausedSinceMs > 0) {
            pausedAccumulatedMs += System.currentTimeMillis() - pausedSinceMs
            pausedSinceMs = 0
        }
        lastLocation = null
        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Recording) }
        com.runapp.watchwear.tiles.ActiveRunTileService.requestUpdate(this)
    }

    private fun stopRecording() {
        gpsJob?.cancel(); gpsJob = null
        gpsRetryJob?.cancel(); gpsRetryJob = null
        hrJob?.cancel(); hrJob = null
        stepsJob?.cancel(); stepsJob = null
        tickerJob?.cancel(); tickerJob = null
        checkpointJob?.cancel(); checkpointJob = null

        val distanceAtFinish = RecordingRepository.metrics.value.distanceM
        val durationAtFinish = (activeElapsedMs() / 1000).toInt()
        tts?.announceFinish(distanceAtFinish, durationAtFinish, preferredUnit)

        if (pausedSinceMs > 0) {
            pausedAccumulatedMs += System.currentTimeMillis() - pausedSinceMs
            pausedSinceMs = 0
        }
        val finalElapsed = activeElapsedMs()
        val finalDistance = RecordingRepository.metrics.value.distanceM
        advanceHrCoverage(finalElapsed)
        val hr = heartRateClaim(
            bpmSum = bpmSum,
            bpmCount = bpmCount,
            hrAvailableMs = if (BuildConfig.ENABLE_HR) hrAvailableMs else null,
            activeElapsedMs = finalElapsed,
        )

        val file = trackWriter?.close()
        trackWriter = null

        RecordingRepository.update {
            it.copy(
                stage = RecordingRepository.Stage.Finished,
                elapsedMs = finalElapsed,
                distanceM = finalDistance,
                finishedHr = hr,
                trackFilePath = file?.absolutePath,
                laps = laps.toList(),
                activityType = activityType,
            )
        }

        // The checkpoint is deliberately NOT cleared here. Until the
        // `Finished` metrics above are banked into `LocalRunStore`, the
        // checkpoint is the run's only durable record — and this teardown
        // drops the process out of foreground-service state, which is
        // exactly when the OS is free to kill it. Clearing here raced the
        // consumer's queue write, so a kill in that window lost both. The
        // party that performs the write clears it instead
        // (`RunViewModel.handleFinishedRun`), so the safety net outlives
        // the run it is protecting. A checkpoint that survives a
        // completed write is not a phantom prompt: `recoveryActionFor`
        // grades an already-queued run as `Discard`.
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        com.runapp.watchwear.tiles.ActiveRunTileService.requestUpdate(this)
        stopSelf()
    }

    /// Credit the tick's active milliseconds to heart-rate coverage when the
    /// last usable sample is still fresh. Called from the ticker rather than
    /// from the HR collect because the gap this measures is a stream that has
    /// gone quiet — there is no emission to hang it on.
    private fun advanceHrCoverage(activeElapsedMs: Long) {
        if (!BuildConfig.ENABLE_HR) return
        val step = activeElapsedMs - lastHrTickElapsedMs
        lastHrTickElapsedMs = activeElapsedMs
        if (step <= 0L || lastHrSampleAtMs == 0L) return
        if (SystemClock.elapsedRealtime() - lastHrSampleAtMs <= HR_SAMPLE_FRESH_MS) {
            hrAvailableMs += step
        }
    }

    private fun isPaused(): Boolean =
        RecordingRepository.metrics.value.stage == RecordingRepository.Stage.Paused

    private fun activeElapsedMs(): Long = activeElapsedMs(
        nowMs = System.currentTimeMillis(),
        startedAtMs = startedAtMs,
        pausedAccumulatedMs = pausedAccumulatedMs,
        pausedSinceMs = pausedSinceMs,
    )

    // ----- GPS handler -----

    /// (Re)subscribe to the GPS stream. Cancels any existing subscription
    /// first so we don't double-stream. Called from `startRecording` and
    /// from the self-heal watchdog.
    private fun subscribeToGps() {
        gpsJob?.cancel()
        gpsJob = scope.launch {
            gps.stream()
                // A stream that throws — a location permission revoked
                // mid-run is the realistic one — used to escape this
                // `launch` and kill the process, taking the recording with
                // it. Report it as lost signal instead: the runner sees
                // "GPS lost", the retry loop above re-subscribes within
                // GPS_RETRY_INTERVAL_MS, and the elapsed clock keeps running.
                .catch { e ->
                    android.util.Log.w(TAG, "location stream failed", e)
                    RecordingRepository.update { it.copy(locationAvailable = false) }
                }
                .collect { event ->
                    when (event) {
                        is GpsEvent.Point -> if (!isPaused()) onGps(event.point)
                        is GpsEvent.Availability -> RecordingRepository.update {
                            it.copy(locationAvailable = event.available)
                        }
                    }
                }
        }
    }

    private fun onGps(p: GpsPoint) {
        lastPointAtMs = System.currentTimeMillis()
        trackWriter?.append(p)
        val asLoc = Location("").apply {
            latitude = p.lat; longitude = p.lng; time = p.epochMs
        }
        var newDistance = RecordingRepository.metrics.value.distanceM
        // The anchor advances ONLY on an accepted delta, or on a real gap.
        //
        // Advancing it after a REJECTED sub-2 m hop discards that ground for
        // good: at the 1 Hz fix rate a walker at 1.4 m/s produces ~1.4 m per
        // fix, every one of them under the floor, so a two-hour hike accrued
        // 0.00 km. Holding the anchor is exactly what lets two such fixes sum
        // to 2.8 m and count. The canonical Flutter recorder assigns
        // `_lastTrackedPosition` inside the accepted branch for this reason.
        //
        // The escape mirrors its `_gpsReanchorAfterSeconds`: once a real
        // interval has passed, rebase to the fresh fix WITHOUT crediting the
        // un-sampled gap, so a >100 m hop after dropped fixes cannot freeze the
        // anchor for the rest of the run instead.
        val prev = lastLocation
        val nowRealtimeMs = SystemClock.elapsedRealtime()
        if (prev == null) {
            lastLocation = asLoc
            lastAnchorRealtimeMs = nowRealtimeMs
        } else {
            val delta = haversineM(prev.latitude, prev.longitude, p.lat, p.lng)
            if (delta in 2.0..100.0) {
                newDistance += delta
                lastLocation = asLoc
                lastAnchorRealtimeMs = nowRealtimeMs
            } else if (delta > 100.0 && nowRealtimeMs - lastAnchorRealtimeMs >= GPS_REANCHOR_MS) {
                // Over-ceiling ONLY, and on a MONOTONIC clock.
                //
                // The escape exists for the >100 m case: fixes were dropped, the
                // runner really moved, and a fixed cap never scales — so without
                // it the stale anchor only ever recedes and distance freezes for
                // the rest of the run (#330). It must NOT fire for a sub-2 m
                // hop: that ground is DEFERRED, and discarding the deferral is
                // the 0.00 km bug this branch was added alongside. The firmware
                // re-anchors inside its over-ceiling branch only and holds the
                // anchor below the floor; this now matches.
                //
                // elapsedRealtime, not the fix's own stamp: a wall clock can
                // step backwards on an NTP sync (and a mock/test provider can
                // stall it entirely), and a negative or frozen delta means the
                // escape never fires — freezing distance exactly the way the
                // escape exists to prevent.
                lastLocation = asLoc
                lastAnchorRealtimeMs = nowRealtimeMs
            }
        }
        val elapsedS = activeElapsedMs() / 1000.0
        val pace = if (newDistance >= 50.0 && elapsedS > 0) elapsedS / newDistance * 1000.0 else null
        val posLL = RouteMath.LatLng(p.lat, p.lng)
        // One pass for both the off-route distance and the distance remaining —
        // each used to walk every segment of the (un-downsampled) route per GPS
        // fix and re-find the closest segment independently. routeProgress
        // shares that search; on a 5k-point ultra route at ~1 Hz that halves the
        // per-fix projection trig on the recording hot path.
        val progress = if (routeWaypoints.isNotEmpty())
            RouteMath.routeProgress(posLL, routeWaypoints) else null
        val offRoute = progress?.offRouteDistanceM
        val remaining = progress?.remainingM
        // Append to the rolling overlay buffer; halve density on
        // overflow so memory stays O(cap) regardless of run length.
        // The disk-backed full track via TrackWriter is the source of
        // truth for stats; this buffer is presentation-only.
        trackOverlay.add(posLL)
        TrackOverlayBuffer.halveIfOverflowing(trackOverlay, MAX_TRACK_OVERLAY_POINTS)
        RecordingRepository.update {
            it.copy(
                distanceM = newDistance,
                paceSecPerKm = pace,
                latestPoint = p,
                trackPointCount = trackWriter?.pointCount ?: 0,
                offRouteDistanceM = offRoute,
                routeRemainingM = remaining,
                trackOverlayPoints = trackOverlay.toList(),
            )
        }

        // TTS split: announce once per completed unit of the runner's
        // `preferred_unit`. Runs on the service's Default-dispatcher scope
        // already — the TTS engine is thread-safe and a Flush-queued speak()
        // replaces any in-flight utterance, so if two splits land in quick
        // succession (shouldn't happen at running pace, but) only the more
        // recent is spoken.
        val currentSplit = completedSplits(newDistance, preferredUnit)
        if (currentSplit > lastAnnouncedSplit) {
            lastAnnouncedSplit = currentSplit
            tts?.announceSplit(currentSplit, pace, preferredUnit)
        }

        // Pace-drift alert. Only fires when:
        //  - a target pace is set for this run
        //  - pace has stabilised (need at least 50 m of distance — same
        //    gate used for computing `pace` above)
        //  - the runner is currently moving (activity not paused is
        //    already implicit — onGps skips when paused)
        //  - the drift is >30 s/km in either direction
        //  - we haven't already fired an alert in the last 30 s
        val target = targetPaceSecPerKm
        if (target != null && target > 0 && pace != null) {
            // Gate in `shouldFirePaceAlert` so the drift threshold +
            // rate-limit windowing are unit-testable in isolation
            // (see `PaceAlertTest.kt`).
            val decision = shouldFirePaceAlert(
                targetPaceSecPerKm = target,
                currentPaceSecPerKm = pace,
                nowMs = System.currentTimeMillis(),
                lastAlertAtMs = lastPaceAlertAtMs,
            )
            lastPaceAlertAtMs = decision.newLastAlertAtMs
            if (decision.fire) firePaceAlert(tooSlow = decision.tooSlow)
        }
    }

    /// Parse the JSON array emitted by `RunViewModel.start()` (format:
    /// `[{"lat":.., "lng":..}, ...]`). Quietly returns empty on any
    /// parse failure — an empty list disables the `RouteMath` calls in
    /// `onGps` so the run proceeds as a no-route recording.
    ///
    /// Delegates to the file-level [parseRouteWaypointsJson] so the
    /// parse contract (well-formed, malformed, partial, type-coerced)
    /// is unit-testable in isolation (see `ParseRouteWaypointsTest`).
    private fun parseRouteWaypoints(
        json: String?,
    ): List<RouteMath.LatLng> = parseRouteWaypointsJson(json)

    private suspend fun writeCheckpoint() {
        val file = trackWriter ?: return
        if (file.pointCount == 0 && bpmCount == 0L) return
        val savedAtMs = System.currentTimeMillis()
        val currentPauseMs = if (pausedSinceMs > 0) savedAtMs - pausedSinceMs else 0
        checkpoints.save(
            Checkpoint(
                runId = runId,
                startedAtMs = startedAtMs,
                savedAtMs = savedAtMs,
                distanceM = RecordingRepository.metrics.value.distanceM,
                trackFilePath = file.path,
                trackPointCount = file.pointCount,
                bpmSum = bpmSum,
                bpmCount = bpmCount,
                hrAvailableMs = if (BuildConfig.ENABLE_HR) hrAvailableMs else null,
                activityType = activityType,
                laps = laps.map { CheckpointLap(it.number, it.atMs, it.distanceM) },
                steps = RecordingRepository.metrics.value.steps,
                privacyDefault = privacyDefault,
                pausedAccumulatedMs = pausedAccumulatedMs + currentPauseMs,
            )
        )
    }

    /// Fire the pace-drift alert: a Vibrator pulse pattern + TTS.
    ///
    /// Matches Android's `HapticFeedback.heavyImpact()` pattern from
    /// `apps/mobile_android/lib/screens/run_screen.dart` — two pulses
    /// for "speed up" (tooSlow=true), one for "slow down" (tooSlow=false).
    /// The direction is distinguishable by feel alone, so runners
    /// notice even with TTS muted or headphones paused.
    @Suppress("DEPRECATION")
    private fun firePaceAlert(tooSlow: Boolean) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        val effect = if (tooSlow) {
            // Two ~180 ms pulses with a ~180 ms gap, matching the
            // "speed up" cue on Android. `timings` is [off, on, off, on].
            VibrationEffect.createWaveform(
                longArrayOf(0, 180, 180, 180),
                intArrayOf(0, 255, 0, 255),
                -1,
            )
        } else {
            VibrationEffect.createOneShot(220, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        try {
            vibrator.vibrate(effect)
        } catch (e: Throwable) {
            // A watch with no vibrator is rare; a MISSING `VIBRATE`
            // declaration looks identical from here and is not rare at all —
            // it was the state of this manifest, so the haptic half of the
            // pace alert had never fired on any watch and the silence read as
            // hardware (decisions § 1302). Logged rather than swallowed: the
            // alert is L4, so the run is untouched either way, but a cue that
            // silently does not exist must leave a trace.
            android.util.Log.w(TAG, "pace-alert haptic refused", e)
        }
        tts?.announcePaceAlert(tooSlow)
    }

    private fun haversineM(aLat: Double, aLng: Double, bLat: Double, bLng: Double): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(bLat - aLat)
        val dLng = Math.toRadians(bLng - aLng)
        val a = sin(dLat / 2).pow(2.0) +
            cos(Math.toRadians(aLat)) * cos(Math.toRadians(bLat)) *
            sin(dLng / 2).pow(2.0)
        return r * 2 * Math.asin(sqrt(a))
    }

    // ----- Notifications -----

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification)
            return
        }
        val mask = foregroundServiceTypeMask(
            sdkInt = Build.VERSION.SDK_INT,
            healthPrerequisiteGranted = hasAnyPermission(
                android.Manifest.permission.BODY_SENSORS,
                android.Manifest.permission.ACTIVITY_RECOGNITION,
            ),
        )
        try {
            startForeground(NOTIFICATION_ID, notification, mask)
        } catch (e: Throwable) {
            // A refused type must not cost the runner the recording. The
            // location half is what the run cannot proceed without; retry
            // with it alone and let heart rate be the thing that degrades.
            android.util.Log.w(TAG, "foreground start refused type mask $mask", e)
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        }
    }

    private fun hasAnyPermission(vararg permissions: String): Boolean =
        permissions.any {
            checkSelfPermission(it) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }

    private fun refreshNotification(elapsedMs: Long, distanceM: Double, paused: Boolean = isPaused()) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(elapsedMs, distanceM, paused))
    }

    private fun buildNotification(elapsedMs: Long, distanceM: Double, paused: Boolean): Notification {
        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // Reuse the tested tile formatter: this one had no hours field, so a
        // 12 h ultra rendered "720:34" on the ongoing notification while the
        // tile beside it rendered "12:00:34" for the same run.
        val timeStr = formatElapsed(elapsedMs)
        // ...and the distance beside it honours preferredUnit, which the service
        // already carries and the tile already uses. Hardcoding km here meant a
        // mi-mode runner read 8.05 km on the ongoing-activity chip and 5.00 mi
        // on the tile beside it, for the same run.
        val distStr = formatDistanceLabel(distanceM)
        val text = getString(R.string.notif_time_distance, timeStr, distStr)
        val title = if (paused) getString(R.string.notif_paused) else getString(R.string.notif_recording_run)

        val baseBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(tapIntent)

        return runCatching {
            OngoingActivity.Builder(applicationContext, NOTIFICATION_ID, baseBuilder)
                .setStaticIcon(R.mipmap.ic_launcher)
                .setTouchIntent(tapIntent)
                .setStatus(
                    Status.Builder()
                        .addTemplate(
                            if (paused) getString(R.string.ongoing_template_paused)
                            else getString(R.string.ongoing_template_running)
                        )
                        .addPart(
                            "time",
                            Status.StopwatchPart(ongoingActivityBaseMs(startedAtMs, pausedAccumulatedMs)),
                        )
                        .addPart(
                            "distance",
                            Status.TextPart(
                                formatDistanceLabel(distanceM),
                            ),
                        )
                        .build()
                )
                .build()
                .apply { apply(applicationContext) }
            baseBuilder.build()
        }.getOrElse { baseBuilder.build() }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notif_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notif_channel_description)
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
    }

    // ----- Wake lock -----

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "watch_wear:RunRecording",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    /// Distance rendered in the runner's own unit, for the ongoing notification
    /// and the Ongoing Activity chip. Mirrors what the tile's formatStatRow
    /// does; the two sit side by side on the watch face.
    private fun formatDistanceLabel(distanceM: Double): String = when (preferredUnit) {
        DistanceUnit.KM -> getString(R.string.distance_km, formatDistance(distanceM, DistanceUnit.KM))
        DistanceUnit.MI -> getString(R.string.distance_mi, formatDistance(distanceM, DistanceUnit.MI))
    }

    companion object {
        /// Cap on the rolling track-overlay buffer. 256 points is enough
        /// for a recognisable polyline at the mini-map's 56 dp size on
        /// any watch hardware; with halve-on-overflow downsampling the
        /// buffer covers the whole run regardless of duration. ~4 KiB
        /// of memory per run.
        const val MAX_TRACK_OVERLAY_POINTS = 256

        /// Re-anchor the distance accumulator after a real gap, so a hop that
        /// failed the 100 m cap because fixes were dropped cannot freeze the
        /// anchor for the rest of the run. Mirrors the Flutter recorder's
        /// `_gpsReanchorAfterSeconds`.
        const val GPS_REANCHOR_MS = 10_000L

        const val ACTION_START = "com.runapp.watchwear.action.START_RECORDING"
        const val ACTION_STOP = "com.runapp.watchwear.action.STOP_RECORDING"
        const val ACTION_PAUSE = "com.runapp.watchwear.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "com.runapp.watchwear.action.RESUME_RECORDING"
        const val ACTION_LAP = "com.runapp.watchwear.action.MARK_LAP"
        const val EXTRA_RUN_ID = "run_id"
        const val EXTRA_ACTIVITY_TYPE = "activity_type"
        /// JSON array of `{"lat": .., "lng": ..}` objects — the picked
        /// route's waypoints. Optional; absent means "no route overlay".
        const val EXTRA_ROUTE_WAYPOINTS_JSON = "route_waypoints_json"
        /// Integer seconds-per-km target. `0` (default) means "no target";
        /// the service's pace-alert branch stays silent.
        const val EXTRA_TARGET_PACE_SEC_PER_KM = "target_pace_sec_per_km"
        /// `DistanceUnit` name (`"KM"` / `"MI"`) for the runner's distance
        /// preference. Absent / unrecognised → kilometres.
        const val EXTRA_PREFERRED_UNIT = "preferred_unit"
        /// Runner's universal `privacy_default` ("public" / "followers" /
        /// "private"). Snapshotted into each checkpoint so a crash-recovered
        /// run honours the same visibility as a normal stop. Absent when the
        /// prefs bag hadn't loaded at run start.
        const val EXTRA_PRIVACY_DEFAULT = "privacy_default"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "run_recording"
        private const val CHECKPOINT_INITIAL_DELAY_MS = 30_000L
        private const val CHECKPOINT_INTERVAL_MS = 15_000L
        // Ticker runs every 500ms for UI, but notifications only update
        // every Nth tick to avoid hammering NotificationManager over a
        // 10-hour run (72,000 → 7,200 refreshes).
        private const val NOTIFICATION_THROTTLE_TICKS = 10
        // GPS self-heal retry loop — mirrors the Android run_recorder.
        // [GPS_RETRY_INTERVAL_MS] is how often to poll; [GPS_STALL_MS]
        // is the Wear-specific "subscription alive but silent" threshold
        // — set well above the 1 s request cadence so a normal hiccup
        // doesn't retrigger a fresh subscription.
        private const val GPS_RETRY_INTERVAL_MS = 10_000L
        // GPS_STALL_MS lives in `GpsRetryDecision.kt` so the
        // resubscribe decision can be unit-tested. Re-exported here
        // by reference, not redeclared, to keep one source of truth.

        internal const val TAG = "RunRecordingService"

        /// The foreground-service type mask this service starts with.
        ///
        /// The manifest declares `location|health` plus both matching
        /// FOREGROUND_SERVICE_* permissions, and the runtime call passed
        /// LOCATION alone — so the health half of that declaration had
        /// never once been used. From API 34 the mask passed HERE, not the
        /// manifest, is what the platform reads when deciding whether a
        /// service may go on using a while-in-use permission while the app
        /// itself is not visible, and body sensors is one of those.
        ///
        /// HEALTH is conditional because the platform refuses it rather
        /// than ignoring it: a health service may only start once at least
        /// one of BODY_SENSORS / ACTIVITY_RECOGNITION has been granted, and
        /// a runner may decline both and still be entitled to a GPS run.
        internal fun foregroundServiceTypeMask(
            sdkInt: Int,
            healthPrerequisiteGranted: Boolean,
        ): Int {
            var mask = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                healthPrerequisiteGranted
            ) {
                mask = mask or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            }
            return mask
        }

        fun start(
            context: Context,
            runId: String,
            activityType: String,
            routeWaypointsJson: String? = null,
            targetPaceSecPerKm: Int? = null,
            preferredUnit: DistanceUnit = DistanceUnit.KM,
            privacyDefault: String? = null,
        ) {
            val intent = Intent(context, RunRecordingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RUN_ID, runId)
                putExtra(EXTRA_ACTIVITY_TYPE, activityType)
                putExtra(EXTRA_PREFERRED_UNIT, preferredUnit.name)
                if (!privacyDefault.isNullOrEmpty()) {
                    putExtra(EXTRA_PRIVACY_DEFAULT, privacyDefault)
                }
                if (!routeWaypointsJson.isNullOrEmpty()) {
                    putExtra(EXTRA_ROUTE_WAYPOINTS_JSON, routeWaypointsJson)
                }
                if (targetPaceSecPerKm != null && targetPaceSecPerKm > 0) {
                    putExtra(EXTRA_TARGET_PACE_SEC_PER_KM, targetPaceSecPerKm)
                }
            }
            context.startForegroundService(intent)
        }

        fun pause(context: Context) = send(context, ACTION_PAUSE)
        fun resume(context: Context) = send(context, ACTION_RESUME)
        fun lap(context: Context) = send(context, ACTION_LAP)
        fun stop(context: Context) = send(context, ACTION_STOP)

        private fun send(context: Context, action: String) {
            context.startService(
                Intent(context, RunRecordingService::class.java).apply { this.action = action }
            )
        }
    }
}
