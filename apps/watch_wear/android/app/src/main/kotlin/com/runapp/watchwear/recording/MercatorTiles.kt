package com.runapp.watchwear.recording

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.tan

/// Web Mercator projection + tile coords for the in-run mini-map.
///
/// Replaces the older equirectangular `MapProjection` once raster tiles
/// were added: tiles must use Mercator (the standard for slippy maps),
/// and the polyline must use the *same* projection or it drifts off
/// the road. So this single helper emits both — viewport pixel coords
/// for `RouteMath.LatLng` points AND the (z, x, y, screenX, screenY)
/// tuples that cover the visible viewport.
///
/// Conventions:
/// - 256-pixel tiles (the MapTiler default).
/// - Integer zoom levels (1..18). Continuous zoom would let polylines
///   fit tighter, but raster tiles only exist at integer zooms and
///   re-scaling them on the fly is ugly. The polyline accepts a touch
///   of slack at the bounds in exchange for tile alignment.
/// - North is up. Web Mercator's y axis grows southward; we mirror it
///   so screen pixel (0, 0) is top-left.
object MercatorTiles {

    /// Choose a centre + zoom that fits all `points` inside a square
    /// viewport of side `viewportPx`, with `paddingFrac` of the side
    /// reserved as a margin on each axis (default 10%). Returns null
    /// for an empty point list.
    ///
    /// Single-point fallback is zoom 14 — neighbourhood scale,
    /// roughly 1 km across at the equator. Visually meaningful even
    /// when GPS hasn't yet produced a track.
    data class Centre(val lat: Double, val lng: Double, val zoom: Int)

    fun fitBounds(
        points: List<RouteMath.LatLng>,
        viewportPx: Float,
        paddingFrac: Double = 0.10,
    ): Centre? {
        if (points.isEmpty()) return null
        val minLat = points.minOf { it.lat }
        val maxLat = points.maxOf { it.lat }
        val minLng = points.minOf { it.lng }
        val maxLng = points.maxOf { it.lng }
        val centreLat = (minLat + maxLat) / 2.0
        val centreLng = (minLng + maxLng) / 2.0

        // Single-point bounds — zoom 14 is a sensible default
        // (neighbourhood scale). Latitude / longitude equality is
        // exact here because the bounds come from min/max of the
        // same point.
        if (minLat == maxLat && minLng == maxLng) {
            return Centre(centreLat, centreLng, 14)
        }

        val targetPx = (viewportPx * (1.0 - 2 * paddingFrac)).coerceAtLeast(1.0)
        val dLng = (maxLng - minLng).coerceAtLeast(1e-9)
        // Mercator y is dimensionless in [0, 1] over the world; multiply
        // by 256 * 2^z to get world pixels. Solve for the zoom where
        // the lng/lat span fits the target pixel width.
        val zoomLng = log2(targetPx * 360.0 / (256.0 * dLng))
        val mercY1 = mercatorYNorm(minLat)
        val mercY2 = mercatorYNorm(maxLat)
        val dY = abs(mercY2 - mercY1).coerceAtLeast(1e-9)
        val zoomLat = log2(targetPx / (256.0 * dY))
        val zoom = floor(minOf(zoomLng, zoomLat)).toInt().coerceIn(1, 18)
        return Centre(centreLat, centreLng, zoom)
    }

    /// Project a lat/lng to viewport pixel coords given a centre + zoom.
    /// `viewportPx` is the square viewport's side; the centre lands at
    /// (viewportPx/2, viewportPx/2). Pixel coords may fall outside
    /// [0, viewportPx]; callers can clip or skip such points.
    fun project(
        latLng: RouteMath.LatLng,
        centre: Centre,
        viewportPx: Float,
    ): Pair<Float, Float> {
        val n = 2.0.pow(centre.zoom.toDouble())
        val worldSide = 256.0 * n
        val centreXWorld = (centre.lng + 180.0) / 360.0 * worldSide
        val centreYWorld = mercatorYNorm(centre.lat) * worldSide
        val pxWorld = (latLng.lng + 180.0) / 360.0 * worldSide
        val pyWorld = mercatorYNorm(latLng.lat) * worldSide
        val half = viewportPx / 2.0
        val sx = (half + (pxWorld - centreXWorld)).toFloat()
        val sy = (half + (pyWorld - centreYWorld)).toFloat()
        return sx to sy
    }

    /// One tile to draw: integer (z, x, y) plus the screen pixel of
    /// its top-left corner. Tiles are 256x256.
    data class Tile(val z: Int, val x: Int, val y: Int, val screenX: Float, val screenY: Float)

    /// Emit all tiles whose 256x256 footprints intersect a
    /// `viewportPx`-square viewport centred on `centre`. The list
    /// always includes a small overshoot (one tile beyond each edge)
    /// so panning / re-centering between fixes doesn't expose
    /// untiled background.
    fun visibleTiles(centre: Centre, viewportPx: Float): List<Tile> {
        val z = centre.zoom
        val n = 2.0.pow(z.toDouble())
        val worldSide = 256.0 * n
        val centreXWorld = (centre.lng + 180.0) / 360.0 * worldSide
        val centreYWorld = mercatorYNorm(centre.lat) * worldSide
        val half = viewportPx / 2.0
        // Number of tiles needed each side of centre to cover viewport,
        // plus 1 overshoot for safety (handles rounding + gives a tile
        // of breathing room when the centre nudges).
        val tilesEachSide = ((viewportPx / 2f) / 256f).toInt() + 2
        val centreTileX = (centreXWorld / 256.0).toInt()
        val centreTileY = (centreYWorld / 256.0).toInt()
        val nInt = n.toInt()
        val out = mutableListOf<Tile>()
        for (xOff in -tilesEachSide..tilesEachSide) {
            for (yOff in -tilesEachSide..tilesEachSide) {
                val tx = centreTileX + xOff
                val ty = centreTileY + yOff
                // Tile y wraps catastrophically near the poles in the
                // Mercator scheme; clip rather than fetching nonsense.
                // Tile x wraps cleanly on the antimeridian, but no
                // route in this app spans it — clip both for symmetry.
                if (tx < 0 || ty < 0 || tx >= nInt || ty >= nInt) continue
                val tileWorldX = tx * 256.0
                val tileWorldY = ty * 256.0
                val sx = (half + (tileWorldX - centreXWorld)).toFloat()
                val sy = (half + (tileWorldY - centreYWorld)).toFloat()
                out.add(Tile(z, tx, ty, sx, sy))
            }
        }
        return out
    }

    /// Mercator y projection, normalised to [0, 1] over the visible
    /// world (~85.05° ↔ -85.05°). Internal helper.
    private fun mercatorYNorm(lat: Double): Double {
        val rad = lat * PI / 180.0
        // Standard Mercator: y = ln(tan(π/4 + φ/2)) = asinh(tan φ).
        // Expressed as ln(tan φ + 1/cos φ) to avoid the half-angle.
        val y = ln(tan(rad) + 1.0 / cos(rad))
        return (1.0 - y / PI) / 2.0
    }
}
