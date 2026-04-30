package com.runapp.watchwear

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

data class GpsPoint(val lat: Double, val lng: Double, val ele: Double?, val epochMs: Long)

/// Shape of each emission from [GpsRecorder.stream]. Either a new GPS
/// point arrived, or the underlying provider flipped availability (GPS
/// signal lost / regained / permission revoked).
sealed class GpsEvent {
    data class Point(val point: GpsPoint) : GpsEvent()
    data class Availability(val available: Boolean) : GpsEvent()
}

class GpsRecorder(context: Context) {
    private val client: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    /// One-shot read of the device's last cached location. Returns
    /// null if no fix is available or the call fails. Used by the
    /// countdown overlay to warm-fetch tiles before recording starts
    /// — letting tile downloads ride the 3-second countdown instead
    /// of stalling the running screen's first frame on HTTP latency.
    @SuppressLint("MissingPermission")
    suspend fun lastLocation(): GpsPoint? = suspendCancellableCoroutine { cont ->
        try {
            client.lastLocation
                .addOnSuccessListener { loc: Location? ->
                    cont.resume(loc?.let {
                        GpsPoint(
                            lat = it.latitude,
                            lng = it.longitude,
                            ele = if (it.hasAltitude()) it.altitude else null,
                            epochMs = it.time,
                        )
                    })
                }
                .addOnFailureListener { cont.resume(null) }
                .addOnCanceledListener { cont.resume(null) }
        } catch (_: Throwable) {
            cont.resume(null)
        }
    }

    /// Open a position stream at high accuracy with a 1-second update target.
    /// Emits [GpsEvent.Availability] when the provider's usable-signal state
    /// changes, so the caller can surface "GPS lost" to the user instead
    /// of showing stale distance silently.
    @SuppressLint("MissingPermission")
    fun stream(): Flow<GpsEvent> = callbackFlow {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
            .setMinUpdateIntervalMillis(500L)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (loc: Location in result.locations) {
                    if (!loc.hasAccuracy() || loc.accuracy > 30f) continue
                    trySend(
                        GpsEvent.Point(
                            GpsPoint(
                                lat = loc.latitude,
                                lng = loc.longitude,
                                ele = if (loc.hasAltitude()) loc.altitude else null,
                                epochMs = loc.time,
                            )
                        )
                    )
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                trySend(GpsEvent.Availability(availability.isLocationAvailable))
            }
        }

        // Pass the main Looper explicitly. `null` means "use the calling
        // thread's Looper", which throws when this Flow is collected on a
        // background dispatcher (e.g. the foreground service's scope).
        client.requestLocationUpdates(request, cb, Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(cb) }
    }
}
