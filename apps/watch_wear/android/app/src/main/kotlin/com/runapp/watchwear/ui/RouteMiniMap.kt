package com.runapp.watchwear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import com.runapp.watchwear.recording.MercatorTiles
import com.runapp.watchwear.recording.RouteMath

/// Street-level zoom for the follow-current mode. At zoom 17 a 256-px
/// tile spans roughly 300 m on the ground at mid-latitudes, so a
/// ~200 dp watch face shows a few blocks around the runner — close
/// enough to read which side of the road they're on.
private const val FOLLOW_ZOOM = 17

/// Wear-side mini-map: optional raster tiles + route polyline +
/// track-so-far + runner-position dot. v2 of "live position on planned
/// route" — v1 was polyline-only (`MapProjection` equirectangular).
///
/// When `PUBLIC_MAPTILER_KEY` is set in the build, the map fetches
/// `streets-v2-dark` raster tiles from MapTiler and draws them under
/// the polyline using the same Web Mercator projection. Without the
/// key the map falls back to polyline-on-midnight, which is the
/// behaviour from v1. The off-route banner stays the alarm; this is
/// the at-a-glance "where am I in the run?" view.
///
/// All projection + tile math lives in `recording/MercatorTiles.kt`
/// so it's unit-testable without mounting Compose.
@Composable
fun RouteMiniMap(
    route: List<RouteMath.LatLng>,
    current: RouteMath.LatLng?,
    modifier: Modifier = Modifier,
    track: List<RouteMath.LatLng> = emptyList(),
    routeColor: Color = Color(0xFFE5C158),  // DuskPalette.amber-ish
    currentColor: Color = Color.White,
    trackColor: Color = Color(0xFF818CF8),  // indigo, faded behind route
    startColor: Color = Color(0xFF34D399),  // emerald — "go"
    endColor: Color = Color(0xFFF87171),    // coral — "finish"
    backgroundColor: Color = Color(0xFF120D22),  // DuskPalette.midnight
    // Default RoundedCornerShape(8.dp) gives the small inline mini-map
    // its card-like look. When the map is used as a full-screen
    // background on a round Wear OS device, pass `RectangleShape` so
    // the device's hardware mask handles the rounding — the inner
    // 8 dp clip would otherwise leave faint straight edges visible
    // in the corners that the screen background can't fill.
    clipShape: Shape = RoundedCornerShape(8.dp),
) {
    // Bounds + zoom depend on the actual viewport size — we need the
    // pixel dimensions before we can pick a Mercator zoom level that
    // fits. BoxWithConstraints exposes the size at composition time.
    BoxWithConstraints(
        modifier = modifier
            .clip(clipShape)
            .background(backgroundColor),
    ) {
        val density = LocalDensity.current
        val sideDp = if (maxWidth < maxHeight) maxWidth else maxHeight
        val sidePx = with(density) { sideDp.toPx() }
        // Square inner area: projection assumes equal aspect. If the
        // host modifier isn't square, centre within the shorter side
        // so the projection doesn't distort.
        val originX = with(density) { ((maxWidth - sideDp) / 2).toPx() }
        val originY = with(density) { ((maxHeight - sideDp) / 2).toPx() }

        // Two projection modes:
        //   * Follow-current at street zoom (17). When `current` is
        //     non-null (RunningScreen has a GPS fix) we centre on the
        //     runner so they see streets close-up — fit-bounds on a
        //     full 5 km route would render their position as a
        //     single pixel against a tiny polyline. Garmin / Apple
        //     Watch defaults to this.
        //   * Fit-bounds. When there's no current fix (PreRun route
        //     preview, indoor mode) we frame the whole polyline so
        //     the runner can see the route shape before they start.
        val centre = remember(route, current, track, sidePx) {
            if (current != null) {
                MercatorTiles.Centre(current.lat, current.lng, FOLLOW_ZOOM)
            } else {
                val all = route + track
                MercatorTiles.fitBounds(all, sidePx)
            }
        }

        if (centre != null) {
            // Tile layer first so the polyline renders on top. Lazy:
            // skips entirely (and is cheap) if PUBLIC_MAPTILER_KEY is
            // unset — TileSource.enabled gates the network path.
            val ctx = LocalContext.current
            val tileSource = remember(ctx) { TileSource.get(ctx) }
            if (tileSource.enabled) {
                TileLayer(
                    centre = centre,
                    viewportPx = sidePx,
                    tileSource = tileSource,
                    modifier = Modifier.fillMaxSize(),
                )
            }

            Canvas(modifier = Modifier.fillMaxSize()) {
                fun project(p: RouteMath.LatLng): Offset {
                    val (sx, sy) = MercatorTiles.project(p, centre, sidePx)
                    return Offset(originX + sx, originY + sy)
                }

                // Track-so-far behind everything else, faded — context,
                // not primary signal. The route line + position dot
                // are the primary readouts; the track is "where you
                // came from" and shouldn't compete visually.
                if (track.size >= 2) {
                    val path = Path()
                    for ((i, p) in track.withIndex()) {
                        val o = project(p)
                        if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
                    }
                    drawPath(
                        path = path,
                        color = trackColor.copy(alpha = 0.55f),
                        style = Stroke(width = 1.5.dp.toPx()),
                    )
                }

                if (route.size >= 2) {
                    val path = Path()
                    for ((i, p) in route.withIndex()) {
                        val o = project(p)
                        if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
                    }
                    drawPath(
                        path = path,
                        color = routeColor,
                        style = Stroke(width = 2.dp.toPx()),
                    )

                    // Start + end markers. Most planned routes are loops
                    // (first ≈ last waypoint), so detect that case and
                    // draw a single emerald "start/finish" dot rather
                    // than stacking two indistinguishable circles. The
                    // ~12 m threshold matches the GPS sample-spacing
                    // floor used elsewhere in the recorder, so a route
                    // imported from a real GPX with sub-metre wobble
                    // between start/end still reads as a loop.
                    fun drawRouteMarker(at: Offset, color: Color) {
                        drawCircle(
                            color = color.copy(alpha = 0.35f),
                            radius = 5.dp.toPx(),
                            center = at,
                        )
                        drawCircle(color = color, radius = 3.dp.toPx(), center = at)
                    }
                    val start = route.first()
                    val end = route.last()
                    val isLoop = RouteMath.haversineM(
                        start.lat, start.lng, end.lat, end.lng,
                    ) < 12.0
                    drawRouteMarker(project(start), startColor)
                    if (!isLoop) drawRouteMarker(project(end), endColor)
                }

                if (current != null) {
                    val o = project(current)
                    // Halo first so the dot stays visible on top of
                    // the polyline if the runner happens to be
                    // exactly on it.
                    drawCircle(
                        color = currentColor.copy(alpha = 0.3f),
                        radius = 5.dp.toPx(),
                        center = o,
                    )
                    drawCircle(
                        color = currentColor,
                        radius = 3.dp.toPx(),
                        center = o,
                    )
                }
            }
        }
    }
}
