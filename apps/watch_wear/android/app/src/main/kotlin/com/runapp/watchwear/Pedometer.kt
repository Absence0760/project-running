package com.runapp.watchwear

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/// Streams step counts for the current run.
///
/// Backed by `Sensor.TYPE_STEP_COUNTER`, which reports a cumulative step
/// count since device boot. We record the first reading as a baseline
/// and emit `currentReading - baseline` — so the flow always yields
/// "steps taken since this recording started". Baseline is per-
/// subscription, so a new `stream()` call for a new run is a fresh zero.
///
/// Requires `android.permission.ACTIVITY_RECOGNITION` (granted at
/// runtime by `RunWatchApp`'s `permissionLauncher`). Without the
/// permission or the sensor, the flow is silent (but doesn't throw) —
/// `RunRecordingService` handles that as "no steps this run" and the
/// save path omits `metadata.steps`.
class Pedometer(context: Context) {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    val isAvailable: Boolean get() = sensor != null

    fun stream(): Flow<Int> = callbackFlow {
        val s = sensor
        if (s == null) {
            // No step sensor — close the flow cleanly so the collector
            // returns null. The service's run-save path omits
            // `metadata.steps` in that case.
            close()
            return@callbackFlow
        }
        var baseline: Float? = null
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val total = event.values.firstOrNull() ?: return
                val b = baseline ?: run {
                    baseline = total
                    total
                }
                val stepsThisRun = (total - b).toInt().coerceAtLeast(0)
                trySend(stepsThisRun)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                // No-op — the cumulative counter is accurate enough for
                // our purposes and accuracy reports for this sensor type
                // are purely informational.
            }
        }
        sensorManager.registerListener(
            listener,
            s,
            // `SENSOR_DELAY_UI` ≈ 60 ms — plenty fine-grained for a
            // metadata.steps rollup. NORMAL (~200 ms) would also work;
            // UI is a touch more responsive for the live display.
            SensorManager.SENSOR_DELAY_UI,
        )
        awaitClose { sensorManager.unregisterListener(listener) }
    }
}
