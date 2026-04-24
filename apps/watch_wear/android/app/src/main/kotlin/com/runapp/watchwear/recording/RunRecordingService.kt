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
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.runapp.watchwear.BuildConfig
import com.runapp.watchwear.GpsEvent
import com.runapp.watchwear.GpsPoint
import com.runapp.watchwear.GpsRecorder
import com.runapp.watchwear.HeartRateMonitor
import com.runapp.watchwear.MainActivity
import com.runapp.watchwear.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
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
    private var tickerJob: Job? = null
    private var checkpointJob: Job? = null

    private lateinit var gps: GpsRecorder
    private lateinit var hr: HeartRateMonitor
    private lateinit var checkpoints: CheckpointStore
    private var wakeLock: PowerManager.WakeLock? = null
    private var trackWriter: TrackWriter? = null

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

    // Rolling HR aggregation instead of a list of every sample.
    // `bpmSum` / `bpmCount` let us compute avg in O(1) regardless of
    // how many samples have arrived.
    private var bpmSum = 0L
    private var bpmCount = 0L

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
        checkpoints = CheckpointStore(this)
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording(
                intent.getStringExtra(EXTRA_RUN_ID) ?: UUID.randomUUID().toString(),
                intent.getStringExtra(EXTRA_ACTIVITY_TYPE) ?: "run",
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
    }

    // ----- Lifecycle -----

    private fun startRecording(id: String, activity: String) {
        if (RecordingRepository.metrics.value.isActive) return

        runId = id
        activityType = activity
        startedAtMs = System.currentTimeMillis()
        pausedAccumulatedMs = 0
        pausedSinceMs = 0
        laps.clear()
        lastLocation = null
        lastPointAtMs = 0L
        bpmSum = 0
        bpmCount = 0
        tickIndex = 0

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
            )
        }

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

                val jobAlive = gpsJob?.isActive == true
                val now = System.currentTimeMillis()
                val silentMidRun = lastPointAtMs > 0 &&
                    (now - lastPointAtMs) > GPS_STALL_MS

                if (!jobAlive || silentMidRun) {
                    subscribeToGps()
                    // Reset the staleness window so we don't thrash if
                    // the fresh subscription also takes a few seconds
                    // to start emitting.
                    if (silentMidRun) lastPointAtMs = now
                }
            }
        }
        if (BuildConfig.ENABLE_HR) {
            hrJob = scope.launch {
                hr.stream().collect { bpm ->
                    if (isPaused()) return@collect
                    bpmSum += bpm
                    bpmCount++
                    val avg = bpmSum.toDouble() / bpmCount
                    RecordingRepository.update { it.copy(bpm = bpm, avgBpm = avg) }
                }
            }
        }
        tickerJob = scope.launch {
            while (true) {
                delay(500)
                val elapsed = activeElapsedMs()
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
    }

    private fun resumeRecording() {
        if (RecordingRepository.metrics.value.stage != RecordingRepository.Stage.Paused) return
        if (pausedSinceMs > 0) {
            pausedAccumulatedMs += System.currentTimeMillis() - pausedSinceMs
            pausedSinceMs = 0
        }
        lastLocation = null
        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Recording) }
    }

    private fun stopRecording() {
        gpsJob?.cancel(); gpsJob = null
        gpsRetryJob?.cancel(); gpsRetryJob = null
        hrJob?.cancel(); hrJob = null
        tickerJob?.cancel(); tickerJob = null
        checkpointJob?.cancel(); checkpointJob = null

        if (pausedSinceMs > 0) {
            pausedAccumulatedMs += System.currentTimeMillis() - pausedSinceMs
            pausedSinceMs = 0
        }
        val finalElapsed = activeElapsedMs()
        val finalDistance = RecordingRepository.metrics.value.distanceM
        val avgBpm = if (bpmCount == 0L) null else bpmSum.toDouble() / bpmCount

        val file = trackWriter?.close()
        trackWriter = null

        RecordingRepository.update {
            it.copy(
                stage = RecordingRepository.Stage.Finished,
                elapsedMs = finalElapsed,
                distanceM = finalDistance,
                avgBpm = avgBpm,
                trackFilePath = file?.absolutePath,
                trackPointCount = it.trackPointCount,
                laps = laps.toList(),
                activityType = activityType,
            )
        }

        scope.launch { checkpoints.clear() }

        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
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
            gps.stream().collect { event ->
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
        lastLocation?.let { prev ->
            val delta = haversineM(prev.latitude, prev.longitude, p.lat, p.lng)
            if (delta in 2.0..100.0) {
                newDistance += delta
            }
        }
        lastLocation = asLoc
        val elapsedS = activeElapsedMs() / 1000.0
        val pace = if (newDistance >= 50.0 && elapsedS > 0) elapsedS / newDistance * 1000.0 else null
        RecordingRepository.update {
            it.copy(
                distanceM = newDistance,
                paceSecPerKm = pace,
                latestPoint = p,
                trackPointCount = trackWriter?.pointCount ?: 0,
            )
        }
    }

    private suspend fun writeCheckpoint() {
        val file = trackWriter ?: return
        if (file.pointCount == 0 && bpmCount == 0L) return
        checkpoints.save(
            Checkpoint(
                runId = runId,
                startedAtMs = startedAtMs,
                savedAtMs = System.currentTimeMillis(),
                distanceM = RecordingRepository.metrics.value.distanceM,
                trackFilePath = file.path,
                trackPointCount = file.pointCount,
                bpmSum = bpmSum,
                bpmCount = bpmCount,
                activityType = activityType,
                laps = laps.map { CheckpointLap(it.number, it.atMs, it.distanceM) },
            )
        )
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
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
        val mins = elapsedMs / 60_000
        val secs = (elapsedMs / 1000) % 60
        val text = "%d:%02d  ·  %.2f km".format(mins, secs, distanceM / 1000.0)
        val title = if (paused) "Paused" else "Recording run"

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
                        .addTemplate(if (paused) "Paused · #distance#" else "#time# · #distance#")
                        .addPart("time", Status.StopwatchPart(startedAtMs - pausedAccumulatedMs))
                        .addPart(
                            "distance",
                            Status.TextPart("%.2f km".format(distanceM / 1000.0)),
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
            "Run recording",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Persistent notification while a run is being recorded."
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

    companion object {
        const val ACTION_START = "com.runapp.watchwear.action.START_RECORDING"
        const val ACTION_STOP = "com.runapp.watchwear.action.STOP_RECORDING"
        const val ACTION_PAUSE = "com.runapp.watchwear.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "com.runapp.watchwear.action.RESUME_RECORDING"
        const val ACTION_LAP = "com.runapp.watchwear.action.MARK_LAP"
        const val EXTRA_RUN_ID = "run_id"
        const val EXTRA_ACTIVITY_TYPE = "activity_type"

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
        private const val GPS_STALL_MS = 30_000L

        fun start(context: Context, runId: String, activityType: String) {
            val intent = Intent(context, RunRecordingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RUN_ID, runId)
                putExtra(EXTRA_ACTIVITY_TYPE, activityType)
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
