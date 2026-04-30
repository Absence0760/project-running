package com.runapp.watchwear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import com.runapp.watchwear.recording.MapProjection
import com.runapp.watchwear.recording.RouteMath

/// Wear-side mini-map: route polyline + runner-position dot, no
/// underlying tile layer. v1 of "live position on planned route"
/// (roadmap.md Phase 2). The off-route banner is the alarm; this is
/// the at-a-glance "where am I along the course?" view.
///
/// Tile background is deliberately deferred. At 56 dp on a 46 mm
/// screen the tile pitch is sub-legible; runners see the polyline
/// and a moving dot, not a map. Adding raster tiles would mean
/// HTTP fetches per pan, a disk cache, and battery cost — none of
/// which buys legible information at this size. When we add a
/// renderer for the larger-screen case (route preview on the watch
/// face), it can re-use this projection helper.
@Composable
fun RouteMiniMap(
    route: List<RouteMath.LatLng>,
    current: RouteMath.LatLng?,
    modifier: Modifier = Modifier,
    routeColor: Color = Color(0xFFE5C158),  // DuskPalette.amber-ish
    currentColor: Color = Color.White,
    backgroundColor: Color = Color(0xFF120D22),  // DuskPalette.midnight
) {
    // Caching the bounds across recompositions matters: route is
    // constant for the duration of a run, and `current` only changes
    // on each GPS sample (sub-1 Hz). Without `remember(route, current)`
    // we'd recompute the bounding box on every UI tick.
    val bounds = remember(route, current) {
        MapProjection.computeBounds(route, current)
    } ?: return

    Canvas(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(backgroundColor),
    ) {
        val w = size.width
        val h = size.height
        // Square inner area: route projection assumes equal aspect.
        // If the host modifier isn't square we centre within the
        // shorter side so the projection doesn't distort.
        val side = minOf(w, h)
        val originX = (w - side) / 2f
        val originY = (h - side) / 2f

        if (route.size >= 2) {
            val path = Path()
            for ((i, p) in route.withIndex()) {
                val (nx, ny) = MapProjection.project(p, bounds)
                val px = originX + nx.toFloat() * side
                val py = originY + ny.toFloat() * side
                if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
            drawPath(
                path = path,
                color = routeColor,
                style = Stroke(width = 2.dp.toPx()),
            )
        }

        if (current != null) {
            val (nx, ny) = MapProjection.project(current, bounds)
            val cx = originX + nx.toFloat() * side
            val cy = originY + ny.toFloat() * side
            // Halo first so the dot stays visible on top of the
            // polyline if the runner happens to be exactly on it.
            drawCircle(
                color = currentColor.copy(alpha = 0.3f),
                radius = 5.dp.toPx(),
                center = Offset(cx, cy),
            )
            drawCircle(
                color = currentColor,
                radius = 3.dp.toPx(),
                center = Offset(cx, cy),
            )
        }
    }
}
