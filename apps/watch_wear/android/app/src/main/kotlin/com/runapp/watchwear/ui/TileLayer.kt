package com.runapp.watchwear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import com.runapp.watchwear.recording.MercatorTiles

/// Raster tile layer for the in-run mini-map.
///
/// Given a `centre` + `viewportPx`, computes the visible tiles and
/// draws each one at its top-left screen pixel. Tiles arrive
/// asynchronously from `TileSource`; until a tile lands the slot is
/// transparent (the layer sits over the midnight background, which
/// shows through for missing tiles — graceful fallback). Once a tile
/// loads it stays in memory across recompositions, so panning by one
/// fix doesn't re-fetch.
@Composable
fun TileLayer(
    centre: MercatorTiles.Centre,
    viewportPx: Float,
    tileSource: TileSource,
    modifier: Modifier = Modifier,
) {
    if (!tileSource.enabled) return

    val tiles = remember(centre, viewportPx) {
        MercatorTiles.visibleTiles(centre, viewportPx)
    }

    // Map of "z/x/y" → ImageBitmap. Re-created whenever `tiles`
    // changes AND seeded synchronously from the TileSource singleton's
    // memory cache. This is what makes a freshly-mounted RouteMiniMap
    // skip the midnight-flash while LaunchedEffect would otherwise
    // re-fetch each tile: if a previous composable already decoded
    // the tile, it lives in `tileSource.peekMemory(...)` and lands
    // in `bitmaps` during composition, so the first frame draws it.
    val bitmaps: SnapshotStateMap<String, ImageBitmap> = remember(tiles, tileSource) {
        mutableStateMapOf<String, ImageBitmap>().apply {
            tiles.forEach { tile ->
                tileSource.peekMemory(tile)?.let {
                    put("${tile.z}/${tile.x}/${tile.y}", it)
                }
            }
        }
    }

    // Async fetch the tiles that weren't already in the memory cache.
    // Successful fetches mutate `bitmaps` (which is a SnapshotStateMap
    // so the Canvas recomposes) AND the singleton's memoryCache, so
    // future composable instances seed from it on first composition.
    LaunchedEffect(tiles) {
        tiles.forEach { tile ->
            val key = "${tile.z}/${tile.x}/${tile.y}"
            if (bitmaps.containsKey(key)) return@forEach
            val img = tileSource.load(tile)
            if (img != null) bitmaps[key] = img
        }
    }

    Canvas(modifier = modifier) {
        tiles.forEach { tile ->
            val key = "${tile.z}/${tile.x}/${tile.y}"
            val img = bitmaps[key] ?: return@forEach
            drawImage(
                image = img,
                topLeft = Offset(tile.screenX, tile.screenY),
            )
        }
    }
}
