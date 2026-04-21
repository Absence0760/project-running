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
                    // Sanity clamp — a real watch sensor can briefly spike
                    // to absurd values during wrist motion. Resting human
                    // HR floor ~30, anaerobic ceiling ~230. Outside that
                    // the reading is sensor noise.
                    if (bpm < 30 || bpm > 230) continue
                    trySend(bpm.toInt())
                }
            }
        }

        client.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
        awaitClose {
            client.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
        }
    }
}
