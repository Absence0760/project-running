package com.runapp.watchwear.recording

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/// Pure route-geometry helpers used during a run.
///
/// Ported from `packages/run_recorder/lib/src/run_recorder.dart` —
/// specifically `_offRouteDistance` and `_routeRemaining` plus the
/// equirectangular projection they share. Keep the two implementations
/// in sync; any algorithm change here lands in the Dart twin, too.
///
/// **Not wired yet.** This module exists so the off-route alert and the
/// "distance remaining" badge on the Wear RunningScreen can be built
/// without also designing route sync to the watch in the same PR. When
/// the sync path lands, the service calls these helpers per GPS sample
/// the same way Android does in `run_recorder.dart`.
///
/// All positions are `(latitude, longitude)` in decimal degrees.
/// All distances are in metres. Equirectangular projection is accurate
/// enough for running-route segments (a few km at most) — do not reuse
/// for long-haul geodesy.
object RouteMath {

    /// Minimum perpendicular distance from [pos] to any segment of
    /// [route]. Returns `null` when the route has fewer than two points
    /// (nothing to be off-route from).
    ///
    /// Mirrors `RunRecorder._offRouteDistance`.
    fun offRouteDistanceM(pos: LatLng, route: List<LatLng>): Double? {
        if (route.size < 2) return null
        var minDist = Double.POSITIVE_INFINITY
        for (i in 1 until route.size) {
            val d = distanceToSegmentM(
                pos.lat, pos.lng,
                route[i - 1].lat, route[i - 1].lng,
                route[i].lat, route[i].lng,
            )
            if (d < minDist) minDist = d
        }
        return minDist
    }

    /// Distance in metres from [pos] to the end of [route], projected
    /// onto the polyline. Finds the segment closest to [pos], projects
    /// onto it, then sums the remainder of that segment plus every
    /// subsequent segment's full length. Returns `null` when the route
    /// has fewer than two points.
    ///
    /// Mirrors `RunRecorder._routeRemaining`.
    fun routeRemainingM(pos: LatLng, route: List<LatLng>): Double? {
        if (route.size < 2) return null

        var closestSegmentIdx = 1
        var minDist = Double.POSITIVE_INFINITY
        var tAtClosest = 0.0
        for (i in 1 until route.size) {
            val proj = projectPointOnSegment(
                pos.lat, pos.lng,
                route[i - 1].lat, route[i - 1].lng,
                route[i].lat, route[i].lng,
            )
            if (proj.distance < minDist) {
                minDist = proj.distance
                closestSegmentIdx = i
                tAtClosest = proj.t
            }
        }

        val a = route[closestSegmentIdx - 1]
        val b = route[closestSegmentIdx]
        val segLen = haversineM(a.lat, a.lng, b.lat, b.lng)
        var remaining = segLen * (1.0 - tAtClosest)
        for (i in closestSegmentIdx + 1 until route.size) {
            remaining += haversineM(
                route[i - 1].lat, route[i - 1].lng,
                route[i].lat, route[i].lng,
            )
        }
        return remaining
    }

    /// Perpendicular distance in metres from point P to segment A-B,
    /// using an equirectangular projection centred on A. Accurate for
    /// the short segments that make up a running route; not suitable
    /// for arbitrary geodesy.
    internal fun distanceToSegmentM(
        pLat: Double, pLng: Double,
        aLat: Double, aLng: Double,
        bLat: Double, bLng: Double,
    ): Double = projectPointOnSegment(pLat, pLng, aLat, aLng, bLat, bLng).distance

    /// Project P onto segment A-B and return both the perpendicular
    /// distance and the parameter `t ∈ [0, 1]` along the segment.
    /// `t=0` means "at A", `t=1` means "at B".
    internal fun projectPointOnSegment(
        pLat: Double, pLng: Double,
        aLat: Double, aLng: Double,
        bLat: Double, bLng: Double,
    ): Projection {
        val metresPerDegreeLat = METRES_PER_DEGREE
        val metresPerDegreeLng = METRES_PER_DEGREE * cos(toRad(aLat))

        val px = (pLng - aLng) * metresPerDegreeLng
        val py = (pLat - aLat) * metresPerDegreeLat
        val bx = (bLng - aLng) * metresPerDegreeLng
        val by = (bLat - aLat) * metresPerDegreeLat

        val lenSq = bx * bx + by * by
        if (lenSq == 0.0) {
            return Projection(distance = sqrt(px * px + py * py), t = 0.0)
        }
        var t = (px * bx + py * by) / lenSq
        t = t.coerceIn(0.0, 1.0)
        val cx = bx * t
        val cy = by * t
        val dx = px - cx
        val dy = py - cy
        return Projection(distance = sqrt(dx * dx + dy * dy), t = t)
    }

    /// Great-circle distance in metres between two lat/lng points.
    internal fun haversineM(
        aLat: Double, aLng: Double,
        bLat: Double, bLng: Double,
    ): Double {
        val r = 6_371_000.0
        val dLat = toRad(bLat - aLat)
        val dLng = toRad(bLng - aLng)
        val a = sin(dLat / 2).pow(2.0) +
            cos(toRad(aLat)) * cos(toRad(bLat)) * sin(dLng / 2).pow(2.0)
        return r * 2 * asin(sqrt(a))
    }

    private fun toRad(deg: Double): Double = deg * PI / 180.0

    private const val METRES_PER_DEGREE = 111_320.0

    data class LatLng(val lat: Double, val lng: Double)

    data class Projection(val distance: Double, val t: Double)
}
