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
/// `Flow<HeartRateUpdate>` of live BPM samples and the sensor-state
/// changes between them. Samples are only carried when the sensor is
/// reporting `AVAILABLE` — ACQUIRING / unreliable wrist-off /
/// out-of-range samples are dropped so stale or obviously-bad values
/// don't pollute `avg_bpm`.
///
/// The flow used to be a bare `Flow<Int>`, which threw the state away:
/// every reason for having no bpm arrived as the same silence, and the
/// running screen could only render it as the same blank space. The
/// availability now rides every emission, so the recorder can say which
/// of the four it is (decisions § 1052).
///
/// Acquisition can fail three ways and all three end the same: the flow
/// closes and the run records without heart rate. `MeasureCallback`
/// gives `onRegistrationFailed` an empty default body, so leaving it
/// unimplemented — as this did — turns "Health Services refused" into
/// total silence: no samples, no error, an `avg_bpm` of null and
/// nothing anywhere that says why. The synchronous throw is worse than
/// silent: `registerMeasureCallback` raises `SecurityException` when
/// BODY_SENSORS was declined, which escaped the collector's `launch`
/// and took the whole process down mid-run, GPS trace included.
class HeartRateMonitor(context: Context) {
    private val client = HealthServices.getClient(context).measureClient

    fun stream(): Flow<HeartRateUpdate> = callbackFlow {
        var isAvailable = false
        val callback = object : MeasureCallback {
            override fun onRegistrationFailed(throwable: Throwable) {
                // Sent before the close: a channel that is closed
                // gracefully still delivers what was already sent, so
                // the collector learns why the flow ended instead of
                // seeing it simply stop.
                trySend(HeartRateUpdate(HeartRateAvailability.Unavailable))
                close()
            }

            override fun onAvailabilityChanged(
                dataType: DeltaDataType<*, *>,
                availability: Availability,
            ) {
                if (availability !is DataTypeAvailability) return
                isAvailable = availability == DataTypeAvailability.AVAILABLE
                trySend(HeartRateUpdate(availabilityOf(availability)))
            }

            override fun onDataReceived(data: DataPointContainer) {
                if (!isAvailable) return
                val points = data.getData(DataType.HEART_RATE_BPM)
                for (p in points) {
                    // SDK shape varies by Health Services version
                    // — `SampleDataPoint<*>.value` or `DataPoint.value`.
                    // Both stringify to a parseable Double on a real
                    // device; the cascade survives either shape.
                    val rawValue = (p as? SampleDataPoint<*>)?.value ?: p.value
                    val bpm = bpmFromSampleValue(rawValue) ?: continue
                    trySend(HeartRateUpdate(HeartRateAvailability.Available, bpm))
                }
            }
        }

        try {
            client.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
        } catch (_: Throwable) {
            trySend(HeartRateUpdate(HeartRateAvailability.Unavailable))
            close()
        }
        awaitClose {
            runCatching {
                client.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
            }
        }
    }

    companion object {
        /// Translate Health Services' sensor state into the one the
        /// recorder publishes.
        ///
        /// `UNAVAILABLE_DEVICE_OFF_BODY` is kept separate from
        /// `UNAVAILABLE` because it is the only one of the two a runner
        /// can act on — pushing the watch back up the wrist — and
        /// collapsing them would have cost the caption its only useful
        /// instruction. `UNKNOWN` reads as acquiring rather than as a
        /// failure: it is what the sensor reports before it has decided,
        /// and telling a runner there is no heart rate a second before
        /// the first sample lands is worse than telling them to wait.
        fun availabilityOf(availability: DataTypeAvailability): HeartRateAvailability =
            when (availability) {
                DataTypeAvailability.AVAILABLE -> HeartRateAvailability.Available
                DataTypeAvailability.ACQUIRING -> HeartRateAvailability.Acquiring
                DataTypeAvailability.UNKNOWN -> HeartRateAvailability.Acquiring
                DataTypeAvailability.UNAVAILABLE_DEVICE_OFF_BODY ->
                    HeartRateAvailability.OffWrist
                else -> HeartRateAvailability.Unavailable
            }

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

        /// Validate + truncate a raw `DataPointContainer` sample value
        /// into the typed `Int` BPM that flows through the watch's
        /// HR average. The SDK boxes the numeric in different
        /// shapes across versions; the caller does the cast cascade,
        /// then this helper does the stringify → Double → validity
        /// gate → Int conversion.
        ///
        /// Returns null when the value can't be parsed OR fails the
        /// 30..230 validity gate. Extracted so the parse + clamp
        /// path is unit-testable without booting Health Services
        /// (the SDK's `SampleDataPoint` isn't on the JVM-only test
        /// classpath).
        fun bpmFromSampleValue(rawValue: Any?): Int? {
            val parsed = rawValue?.toString()?.toDoubleOrNull() ?: return null
            if (!isValidBpm(parsed)) return null
            return parsed.toInt()
        }
    }
}
