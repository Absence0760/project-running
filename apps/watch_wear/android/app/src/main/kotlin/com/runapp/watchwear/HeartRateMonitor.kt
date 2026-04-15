package com.runapp.watchwear

import android.content.Context
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/// Wraps `HealthServices.getClient(context).measureClient` to produce a
/// `Flow<Int>` of live BPM samples. Same underlying API that was in the
/// Flutter build; just no method-channel bridge to cross.
class HeartRateMonitor(context: Context) {
    private val client = HealthServices.getClient(context).measureClient

    fun stream(): Flow<Int> = callbackFlow {
        val callback = object : MeasureCallback {
            override fun onAvailabilityChanged(
                dataType: DeltaDataType<*, *>,
                availability: Availability,
            ) {
                // no-op — availability changes aren't surfaced to the UI today
            }

            override fun onDataReceived(data: DataPointContainer) {
                val points = data.getData(DataType.HEART_RATE_BPM)
                for (p in points) {
                    trySend(p.value.toInt())
                }
            }
        }

        client.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
        awaitClose {
            client.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
        }
    }
}
