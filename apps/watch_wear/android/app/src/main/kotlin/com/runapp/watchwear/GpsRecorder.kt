package com.runapp.watchwear

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

data class GpsPoint(val lat: Double, val lng: Double, val ele: Double?, val epochMs: Long)

class GpsRecorder(context: Context) {
    private val client: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    /// Open a position stream at high accuracy with a 1-second update target.
    /// Callers are responsible for holding `ACCESS_FINE_LOCATION` — the
    /// Compose UI asks the runtime permission before the first `start`.
    @SuppressLint("MissingPermission")
    fun stream(): Flow<GpsPoint> = callbackFlow {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
            .setMinUpdateIntervalMillis(500L)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (loc: Location in result.locations) {
                    if (!loc.hasAccuracy() || loc.accuracy > 30f) continue
                    trySend(
                        GpsPoint(
                            lat = loc.latitude,
                            lng = loc.longitude,
                            ele = if (loc.hasAltitude()) loc.altitude else null,
                            epochMs = loc.time,
                        )
                    )
                }
            }
        }

        // Pass the main Looper explicitly. `null` means "use the calling
        // thread's Looper", which throws when this Flow is collected on a
        // background dispatcher (e.g. the foreground service's scope).
        client.requestLocationUpdates(request, cb, Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(cb) }
    }
}
