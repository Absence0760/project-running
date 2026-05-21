package com.runapp.watchwear.recording

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/// Parse the JSON array emitted by `RunViewModel.start()` via the
/// `EXTRA_ROUTE_WAYPOINTS` intent extra. Format: a JSON array of
/// `{"lat":<num>, "lng":<num>}` objects.
///
/// Quietly returns empty on ANY parse failure — null / blank string,
/// non-array root, malformed JSON, mid-array shape break. An empty
/// list disables the `RouteMath` calls in `onGps` so the run
/// proceeds as a no-route recording without crashing.
///
/// Lifted from `RunRecordingService.parseRouteWaypoints` so the
/// fail-quiet contract is unit-testable without booting a foreground
/// service. The intent extra arrives from another process
/// (`RunViewModel.start()`); treat it as untrusted input.
internal fun parseRouteWaypointsJson(json: String?): List<RouteMath.LatLng> {
    if (json.isNullOrEmpty()) return emptyList()
    return try {
        val parser = Json { ignoreUnknownKeys = true }
        val arr = parser.parseToJsonElement(json) as? JsonArray
            ?: return emptyList()
        arr.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val lat = (obj["lat"] as? JsonPrimitive)?.content?.toDoubleOrNull()
                ?: return@mapNotNull null
            val lng = (obj["lng"] as? JsonPrimitive)?.content?.toDoubleOrNull()
                ?: return@mapNotNull null
            RouteMath.LatLng(lat, lng)
        }
    } catch (_: Throwable) {
        emptyList()
    }
}
