package com.runapp.watchwear

import android.content.Context
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.DeltaDataType
import androidx.health.services.client.data.SampleDataPoint
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/// Wraps `HealthServices.getClient(context).measureClient` to produce a
/// `Flow<Int>` of live BPM samples. Samples are only emitted when the
/// sensor is reporting `AVAILABLE` — ACQUIRING / unreliable wrist-off
/// / out-of-range samples are dropped so stale or obviously-bad values
/// don't pollute `avg_bpm`.
class HeartRateMonitor(context: Context) {
    private val client = HealthServices.getClient(context).measureClient

    fun stream(): Flow<Int> = callbackFlow {
        var isAvailable = false
        val callback = object : MeasureCallback {
            override fun onAvailabilityChanged(
                dataType: DeltaDataType<*, *>,
                availability: Availability,
            ) {
                if (availability is DataTypeAvailability) {
                    isAvailable = availability == DataTypeAvailability.AVAILABLE
                }
            }

            override fun onDataReceived(data: DataPointContainer) {
                if (!isAvailable) return
                val points = data.getData(DataType.HEART_RATE_BPM)
                for (p in points) {
                    val bpm = (p as? SampleDataPoint<*>)?.value?.toString()?.toDoubleOrNull()
                        ?: p.value.toString().toDoubleOrNull()
                        ?: continue
                    if (!isValidBpm(bpm)) continue
                    trySend(bpm.toInt())
                }
            }
        }

        client.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
        awaitClose {
            client.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
        }
    }

    companion object {
        /// Resting human HR floor. A real watch sensor can briefly emit
        /// values below this during wrist-off / startup-acquire — those
        /// are sensor noise, not a real reading. Inclusive bound: 30 is
        /// accepted as plausible-but-very-low; 29.9 is rejected.
        const val MIN_VALID_BPM = 30

        /// Anaerobic ceiling for an extreme-effort human. The sensor
        /// can briefly spike past this during wrist motion (the LED
        /// stops registering blood flow and the algorithm hallucinates
        /// a higher rate). Inclusive bound: 230 is accepted; 230.1 is
        /// rejected.
        const val MAX_VALID_BPM = 230

        /// Validity gate for a raw Health Services BPM sample. Used by
        /// `onDataReceived` to drop sensor noise before the value
        /// reaches `RunViewModel`'s rolling HR average. Pinned by
        /// `HeartRateMonitorTest` so a regression to a tighter range
        /// (e.g. 60..180 — typical-runner range) wouldn't silently
        /// drop legitimate floor / ceiling readings.
        fun isValidBpm(bpm: Double): Boolean =
            bpm >= MIN_VALID_BPM && bpm <= MAX_VALID_BPM
    }
}
