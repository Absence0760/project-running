package com.runapp.watchwear

import com.runapp.watchwear.recording.RouteMath
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.put

/// A route as stored on the watch — id + name + waypoints + distance.
///
/// This is a narrow subset of the full `routes` row on Supabase; the
/// watch only needs enough to render a picker, stamp the recorded run
/// with `route_id`, and feed the polyline to `RouteMath`. Elevation,
/// surface, slug, etc. stay on the phone / web until a watch surface
/// needs them.
@Serializable
data class SavedRoute(
    val id: String,
    val name: String,
    val distanceM: Double,
    val waypoints: List<Waypoint>,
) {
    /// Lightweight conversion to the `RouteMath` input type. Avoids
    /// leaking the `SavedRoute` shape into pure-math territory — the
    /// helpers only need lat/lng.
    fun toLatLngs(): List<RouteMath.LatLng> =
        waypoints.map { RouteMath.LatLng(it.lat, it.lng) }

    /// Serialise the waypoints as a JSON array of `{lat, lng}` objects,
    /// the exact shape `RunRecordingService.parseRouteWaypoints`
    /// expects. Passing as a string keeps `ACTION_START`'s Intent
    /// payload simple — no Parcelable plumbing for a one-shot read.
    fun waypointsAsJson(): String = buildJsonArray {
        for (wp in waypoints) {
            addJsonObject {
                put("lat", wp.lat)
                put("lng", wp.lng)
            }
        }
    }.toString()

    @Serializable
    data class Waypoint(val lat: Double, val lng: Double)
}
