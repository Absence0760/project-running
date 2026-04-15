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
import com.runapp.watchwear.BuildConfig
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
/// Exists as a foreground service so Android won't kill the process the
/// moment the watch face goes ambient or the user navigates away. Posts
/// a sticky `RunningNotification` so the OS treats it as user-visible
/// work. Holds a partial `WAKE_LOCK` so the CPU keeps ticking the
/// elapsed-time clock while the screen is off.
///
/// All state goes through [RecordingRepository] — the ViewModel never
/// talks to the service directly except via start/stop intents.
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

    override fun onCreate() {
        super.onCreate()
        gps = GpsRecorder(this)
        hr = HeartRateMonitor(this)
        checkpoints = CheckpointStore(this)
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording(intent.getStringExtra(EXTRA_RUN_ID) ?: UUID.randomUUID().toString())
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
        if (RecordingRepository.metrics.value.stage == RecordingRepository.Stage.Recording) return

        runId = id
        startedAtMs = System.currentTimeMillis()
        track.clear()
        bpmSamples.clear()
        lastLocation = null

        startForegroundCompat(buildNotification(elapsedMs = 0L, distanceM = 0.0))
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
            gps.stream().collect { p -> onGps(p) }
        }
        if (BuildConfig.ENABLE_HR) {
            hrJob = scope.launch {
                hr.stream().collect { bpm ->
                    bpmSamples.add(bpm)
                    val avg = bpmSamples.sum().toDouble() / bpmSamples.size
                    RecordingRepository.update { it.copy(bpm = bpm, avgBpm = avg) }
                }
            }
        }
        tickerJob = scope.launch {
            while (true) {
                delay(500)
                val elapsed = System.currentTimeMillis() - startedAtMs
                RecordingRepository.update { it.copy(elapsedMs = elapsed) }
                refreshNotification(elapsed, RecordingRepository.metrics.value.distanceM)
            }
        }
        checkpointJob = scope.launch {
            // First snapshot at 30s, then every 15s.
            delay(CHECKPOINT_INITIAL_DELAY_MS)
            while (true) {
                writeCheckpoint()
                delay(CHECKPOINT_INTERVAL_MS)
            }
        }
    }

    private fun stopRecording() {
        gpsJob?.cancel(); gpsJob = null
        hrJob?.cancel(); hrJob = null
        tickerJob?.cancel(); tickerJob = null
        checkpointJob?.cancel(); checkpointJob = null

        val finalElapsed = System.currentTimeMillis() - startedAtMs
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

        scope.launch {
            // Recording is finished — checkpoint is no longer needed; the
            // run lives in LocalRunStore + the queued upload path now.
            checkpoints.clear()
        }

        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ----- GPS handler (mirrors RunViewModel.onGps + computePace) -----

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
        val elapsedS = (System.currentTimeMillis() - startedAtMs) / 1000.0
        val pace = if (newDistance >= 50.0 && elapsedS > 0) elapsedS / newDistance * 1000.0 else null
        RecordingRepository.update {
            it.copy(
                distanceM = newDistance,
                paceSecPerKm = pace,
                track = track.toList(),
                locationAvailable = true,
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

    private fun refreshNotification(elapsedMs: Long, distanceM: Double) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(elapsedMs, distanceM))
    }

    private fun buildNotification(elapsedMs: Long, distanceM: Double): Notification {
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

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording run")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(tapIntent)
            .build()
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
            // No timeout — recording owns its own lifecycle and releases
            // explicitly on stop. A timeout would silently drop the lock
            // mid-run and stop GPS updates.
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

        fun stop(context: Context) {
            val intent = Intent(context, RunRecordingService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
