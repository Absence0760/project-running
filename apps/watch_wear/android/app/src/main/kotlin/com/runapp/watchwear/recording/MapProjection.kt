package com.runapp.watchwear.recording

/// Pure lat/lng → unit-square projection for the on-watch mini-map.
///
/// Equirectangular, square-aspect (longest span sets the scale on
/// both axes so the route doesn't get squashed by latitude
/// vs longitude span asymmetry). Padding is fractional — caller
/// passes `paddingFrac = 0.1` to leave 10% inset on each side.
///
/// At running scale (sub-10 km) equirectangular is visually
/// indistinguishable from Mercator on a 96 dp canvas; we deliberately
/// don't bring in the trig that the cross-route distance helpers in
/// `RouteMath.kt` use because the projection error is well below the
/// pixel-pitch of any Wear OS display we ship to.
object MapProjection {

    data class Bounds(
        val minLat: Double,
        val minLng: Double,
        val maxLat: Double,
        val maxLng: Double,
    ) {
        val centerLat: Double get() = (minLat + maxLat) / 2.0
        val centerLng: Double get() = (minLng + maxLng) / 2.0
    }

    /// Compute the bounding box across a route polyline plus an
    /// optional current position. Returns `null` when there's nothing
    /// to plot (caller should hide the canvas).
    fun computeBounds(
        route: List<RouteMath.LatLng>,
        current: RouteMath.LatLng?,
    ): Bounds? {
        var has = false
        var minLat = 0.0
        var maxLat = 0.0
        var minLng = 0.0
        var maxLng = 0.0
        for (p in route) {
            if (!has) {
                minLat = p.lat; maxLat = p.lat
                minLng = p.lng; maxLng = p.lng
                has = true
            } else {
                if (p.lat < minLat) minLat = p.lat
                if (p.lat > maxLat) maxLat = p.lat
                if (p.lng < minLng) minLng = p.lng
                if (p.lng > maxLng) maxLng = p.lng
            }
        }
        if (current != null) {
            if (!has) {
                minLat = current.lat; maxLat = current.lat
                minLng = current.lng; maxLng = current.lng
                has = true
            } else {
                if (current.lat < minLat) minLat = current.lat
                if (current.lat > maxLat) maxLat = current.lat
                if (current.lng < minLng) minLng = current.lng
                if (current.lng > maxLng) maxLng = current.lng
            }
        }
        return if (has) Bounds(minLat, minLng, maxLat, maxLng) else null
    }

    /// Project a single point into the unit square `[0, 1] × [0, 1]`,
    /// then apply `paddingFrac` inset on each side. The y axis is
    /// flipped so larger latitudes map to smaller y (screen y grows
    /// downward; lat grows northward).
    ///
    /// Both axes share the same span (the larger of latSpan / lngSpan)
    /// so the route preserves its shape. With unequal spans the
    /// shorter axis ends up with its content centred on the canvas.
    fun project(
        p: RouteMath.LatLng,
        bounds: Bounds,
        paddingFrac: Double = 0.1,
    ): Pair<Double, Double> {
        val latSpan = (bounds.maxLat - bounds.minLat).coerceAtLeast(1e-9)
        val lngSpan = (bounds.maxLng - bounds.minLng).coerceAtLeast(1e-9)
        val span = maxOf(latSpan, lngSpan)
        val cx = bounds.centerLng
        val cy = bounds.centerLat
        // Centre on midpoint, normalise by larger span, shift to [0, 1].
        val nx = (p.lng - cx) / span + 0.5
        val ny = (p.lat - cy) / span + 0.5
        val pad = paddingFrac.coerceIn(0.0, 0.49)
        val ax = pad + nx * (1.0 - 2 * pad)
        val ay = pad + (1.0 - ny) * (1.0 - 2 * pad)  // flip y
        return Pair(ax, ay)
    }
}
