package com.runapp.watchwear.ui

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.runapp.watchwear.BuildConfig
import com.runapp.watchwear.recording.MercatorTiles
import com.runapp.watchwear.recording.RouteMath
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Cache
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/// Async raster-tile fetcher backed by an HTTP disk cache.
///
/// Resolves `(z, x, y)` to an `ImageBitmap` by:
/// 1. Returning the in-memory bitmap if still cached (fast — same
///    bitmap survives recompositions and inter-tile pans).
/// 2. Asking OkHttp for the URL; OkHttp's disk cache (50 MB) honours
///    MapTiler's `Cache-Control: max-age=86400` and serves locally.
/// 3. Decoding the response body into a Bitmap and caching in memory.
///
/// Failures are silent — the tile layer falls back to the midnight
/// background, which is the same fallback as no-key mode. A flaky
/// network mid-run shouldn't draw scary error UI on the wrist.
class TileSource(context: Context) {

    /// Whether tile rendering is configured at all. Cheap caller check
    /// so the tile layer can be omitted entirely when there's no key.
    val enabled: Boolean = BuildConfig.PUBLIC_MAPTILER_KEY.isNotBlank()

    /// MapTiler dark-style raster endpoint. Hard-coded to
    /// `streets-v2-dark` because the watch UI is always dark — the
    /// runtime style switching the web app does (`map-style.svelte.ts`)
    /// would require a settings surface we don't have. Add one later
    /// if a runner asks for satellite or topo on-watch.
    private val styleSlug = "streets-v2-dark"

    // Disk cache for HTTP responses. 50 MB is plenty: a covered route
    // at zoom 14 fits in ~30 tiles × ~25 KB ≈ 750 KB, so 50 MB holds
    // well over a year of distinct routes.
    private val cacheDir = File(context.cacheDir, "tiles")
    private val client: OkHttpClient = OkHttpClient.Builder()
        .cache(Cache(cacheDir, 50L * 1024 * 1024))
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    // Decoded bitmaps in memory. Compose draws every visible tile per
    // recomposition; without this we'd re-decode 9–16 PNGs per tick.
    // 64 entries comfortably covers the visible viewport plus the
    // overshoot tiles, with headroom for the next-zoom tier when the
    // runner pans.
    private val memoryCache = LruCache<String, ImageBitmap>(64)

    /// Fetch (or cache-hit) a tile. Returns null on any failure path
    /// — caller should treat null as "keep midnight background".
    /// Suspending so the caller can launch a background coroutine and
    /// not block the Compose thread.
    suspend fun load(tile: MercatorTiles.Tile): ImageBitmap? {
        if (!enabled) return null
        val key = "${tile.z}/${tile.x}/${tile.y}"
        memoryCache.get(key)?.let { return it }
        return withContext(Dispatchers.IO) {
            try {
                val url = "https://api.maptiler.com/maps/$styleSlug/" +
                    "${tile.z}/${tile.x}/${tile.y}.png" +
                    "?key=${BuildConfig.PUBLIC_MAPTILER_KEY}"
                val req = Request.Builder().url(url).build()
                client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val bytes = resp.body.bytes()
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?: return@withContext null
                    val img = bmp.asImageBitmap()
                    memoryCache.put(key, img)
                    img
                }
            } catch (e: Exception) {
                // Silent failure: tile rendering is L3 in the layered-
                // resilience model — its absence must not break the
                // run-recording path. Caller draws the polyline + dot
                // on midnight regardless.
                null
            }
        }
    }

    /// Eagerly download every street-zoom tile that the route passes
    /// through, plus a one-tile buffer on each side. Designed for the
    /// route-selection moment: while the runner has connectivity
    /// (paired phone, wifi), we pull the *follow-current* tiles
    /// they'll see at run time — not the wide fit-bounds tiles, which
    /// the running screen never actually displays.
    ///
    /// Tile count is roughly `route_km / 0.3` at zoom 17 (≈300 m per
    /// tile at mid-latitudes), plus the 8-tile ring around each
    /// covered tile. A 5 km route ⇒ ~50 tiles ⇒ ~1.5 MB. A marathon
    /// route ⇒ ~400 tiles ⇒ ~12 MB. Both fit comfortably in the 50 MB
    /// disk cache.
    ///
    /// Fans out concurrently — OkHttp's dispatcher caps in-flight
    /// requests at 64. Failures are silent (per `load`); a partially-
    /// fetched cache is still better than nothing.
    suspend fun prefetch(points: List<RouteMath.LatLng>, zoom: Int = 17) {
        if (!enabled || points.isEmpty()) return
        val needed = mutableSetOf<Pair<Int, Int>>()
        val n = 1 shl zoom
        for (p in points) {
            val rad = p.lat * Math.PI / 180.0
            val tx = ((p.lng + 180.0) / 360.0 * n).toInt().coerceIn(0, n - 1)
            val ty = ((1.0 - kotlin.math.ln(kotlin.math.tan(rad) + 1.0 / kotlin.math.cos(rad)) / Math.PI) / 2.0 * n)
                .toInt().coerceIn(0, n - 1)
            // 3x3 ring around the tile that contains the waypoint.
            for (dx in -1..1) for (dy in -1..1) {
                val nx = tx + dx
                val ny = ty + dy
                if (nx in 0 until n && ny in 0 until n) {
                    needed.add(nx to ny)
                }
            }
        }
        coroutineScope {
            needed.forEach { (x, y) ->
                launch { load(MercatorTiles.Tile(zoom, x, y, 0f, 0f)) }
            }
        }
    }
}
