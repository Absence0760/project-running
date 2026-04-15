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
/// Handles Start, Stop, Pause, and Resume intents. Paused intervals are
/// excluded from both the elapsed-time clock (so pace stays honest when
/// the user stops at a traffic light) and the distance accumulator (so
/// any GPS drift while standing still doesn't inflate the run).
class RunRecordingService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var gpsJob: Job? = null
    private var hrJob: Job? = null
    private var tickerJob: Job? = null
    private var checkpointJob: Job? = null

    private lateinit var gps: GpsRecorder
    private lateinit var hr: HeartRateMonitor
    private lateinit var checkpoints: CheckpointStore
    private var wakeLock: PowerManager.WakeLock? = null

    private var lastLocation: Location? = null
    private val track = mutableListOf<GpsPoint>()
    private val bpmSamples = mutableListOf<Int>()
    private var startedAtMs = 0L
    private var runId: String = ""

    // Paused-interval accounting. `pausedAccumulatedMs` is the sum of
    // previous pause intervals; `pausedSinceMs` is the start of the
    // current pause (0 when not paused). Active elapsed =
    // `(now - startedAtMs) - pausedAccumulatedMs - (now - pausedSinceMs)`.
    private var pausedAccumulatedMs = 0L
    private var pausedSinceMs = 0L

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
                intent.getStringExtra(EXTRA_RUN_ID) ?: UUID.randomUUID().toString()
            )
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        releaseWakeLock()
    }

    // ----- Lifecycle -----

    private fun startRecording(id: String) {
        if (RecordingRepository.metrics.value.isActive) return

        runId = id
        startedAtMs = System.currentTimeMillis()
        pausedAccumulatedMs = 0
        pausedSinceMs = 0
        track.clear()
        bpmSamples.clear()
        lastLocation = null

        startForegroundCompat(buildNotification(elapsedMs = 0L, distanceM = 0.0, paused = false))
        acquireWakeLock()

        RecordingRepository.update {
            RecordingRepository.Metrics(
                stage = RecordingRepository.Stage.Recording,
                runId = runId,
                startedAtMs = startedAtMs,
                elapsedMs = 0L,
            )
        }

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
        if (BuildConfig.ENABLE_HR) {
            hrJob = scope.launch {
                hr.stream().collect { bpm ->
                    if (isPaused()) return@collect
                    bpmSamples.add(bpm)
                    val avg = bpmSamples.sum().toDouble() / bpmSamples.size
                    RecordingRepository.update { it.copy(bpm = bpm, avgBpm = avg) }
                }
            }
        }
        tickerJob = scope.launch {
            while (true) {
                delay(500)
                val elapsed = activeElapsedMs()
                RecordingRepository.update { it.copy(elapsedMs = elapsed) }
                refreshNotification(elapsed, RecordingRepository.metrics.value.distanceM)
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
        // After a pause, the previous lastLocation is stale — discarding
        // it prevents a large haversine jump on the first fix after
        // resume, which would incorrectly inflate distance.
        lastLocation = null
        RecordingRepository.update { it.copy(stage = RecordingRepository.Stage.Recording) }
    }

    private fun stopRecording() {
        gpsJob?.cancel(); gpsJob = null
        hrJob?.cancel(); hrJob = null
        tickerJob?.cancel(); tickerJob = null
        checkpointJob?.cancel(); checkpointJob = null

        // Capture any in-progress pause into the accumulator so the
        // final duration honours the full pause history.
        if (pausedSinceMs > 0) {
            pausedAccumulatedMs += System.currentTimeMillis() - pausedSinceMs
            pausedSinceMs = 0
        }
        val finalElapsed = activeElapsedMs()
        val finalDistance = RecordingRepository.metrics.value.distanceM
        val avgBpm = if (bpmSamples.isEmpty()) null
            else bpmSamples.sum().toDouble() / bpmSamples.size

        RecordingRepository.update {
            it.copy(
                stage = RecordingRepository.Stage.Finished,
                elapsedMs = finalElapsed,
                distanceM = finalDistance,
                track = track.toList(),
                avgBpm = avgBpm,
            )
        }

        scope.launch { checkpoints.clear() }

        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun isPaused(): Boolean =
        RecordingRepository.metrics.value.stage == RecordingRepository.Stage.Paused

    private fun activeElapsedMs(): Long {
        val now = System.currentTimeMillis()
        val total = now - startedAtMs
        val currentPauseMs = if (pausedSinceMs > 0) now - pausedSinceMs else 0
        return (total - pausedAccumulatedMs - currentPauseMs).coerceAtLeast(0)
    }

    // ----- GPS handler -----

    private fun onGps(p: GpsPoint) {
        track.add(p)
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
                track = track.toList(),
            )
        }
    }

    private suspend fun writeCheckpoint() {
        if (track.isEmpty() && bpmSamples.isEmpty()) return
        checkpoints.save(
            Checkpoint(
                runId = runId,
                startedAtMs = startedAtMs,
                savedAtMs = System.currentTimeMillis(),
                distanceM = RecordingRepository.metrics.value.distanceM,
                track = track.map { CheckpointPoint.from(it) },
                bpmSamples = bpmSamples.toList(),
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

    // ----- Foreground notification -----

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

        // Wrap in an `OngoingActivity` so the system treats the run as
        // a first-class ongoing Wear activity — visible from the watch
        // face's ongoing-activity indicator and accessible from the
        // Tile picker. Falls back to a regular notification if the
        // Wear ongoing library isn't resolved at runtime.
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
        const val EXTRA_RUN_ID = "run_id"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "run_recording"
        private const val CHECKPOINT_INITIAL_DELAY_MS = 30_000L
        private const val CHECKPOINT_INTERVAL_MS = 15_000L

        fun start(context: Context, runId: String) {
            val intent = Intent(context, RunRecordingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RUN_ID, runId)
            }
            context.startForegroundService(intent)
        }

        fun pause(context: Context) = send(context, ACTION_PAUSE)
        fun resume(context: Context) = send(context, ACTION_RESUME)
        fun stop(context: Context) = send(context, ACTION_STOP)

        private fun send(context: Context, action: String) {
            context.startService(
                Intent(context, RunRecordingService::class.java).apply { this.action = action }
            )
        }
    }
}
