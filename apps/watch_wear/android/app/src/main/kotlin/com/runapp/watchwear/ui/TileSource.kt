package com.runapp.watchwear.ui

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.runapp.watchwear.BuildConfig
import com.runapp.watchwear.recording.MercatorTiles
import com.runapp.watchwear.recording.RouteMath
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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
/// **Process-wide singleton.** Use `TileSource.get(context)` — never
/// `TileSource(...)` directly. Each `RouteMiniMap` composable
/// instance is a separate Compose subtree with its own `bitmaps`
/// SnapshotStateMap; if those instances each owned a separate
/// `TileSource` they'd each have a separate `memoryCache`, and a
/// freshly-mounted instance (e.g., the running screen mounting
/// after the countdown unmounts) would re-decode every tile from
/// disk, flashing midnight for a frame or two before the bitmaps
/// land. With the singleton, decoded `ImageBitmap`s survive across
/// composable instances.
///
/// Failures are silent — the tile layer falls back to the midnight
/// background, which is the same fallback as no-key mode. A flaky
/// network mid-run shouldn't draw scary error UI on the wrist.
class TileSource private constructor(context: Context) {

    /// Whether tile rendering is configured at all. Cheap caller check
    /// so the tile layer can be omitted entirely when there's no key.
    // Tile rendering lights up when EITHER `PUBLIC_TILE_URL_TEMPLATE`
    // is set (local Protomaps dev path — see
    // `docs/ops/protomaps_local_setup.md`) OR `PUBLIC_MAPTILER_KEY` is
    // set (production path). Logic extracted as the file-level
    // [tileSourceEnabled] helper so the OR / blank-check semantics
    // is unit-testable independent of BuildConfig.
    val enabled: Boolean = tileSourceEnabled(
        template = BuildConfig.PUBLIC_TILE_URL_TEMPLATE,
        maptilerKey = BuildConfig.PUBLIC_MAPTILER_KEY,
    )

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

    // Long-lived IO scope for fire-and-forget disk eviction triggered
    // from main-thread callers (e.g. sign-out). Process-singleton, so it
    // never needs cancelling.
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /// Synchronous in-memory peek. Returns the decoded bitmap if it's
    /// still in the LRU, or null if it'd require a disk hit. Used by
    /// `TileLayer` during composition to seed its bitmaps map so the
    /// first frame after a tile-list change already has cached
    /// tiles drawn — without this, every new composable instance
    /// would flash midnight while LaunchedEffect re-decodes from
    /// disk, even though OkHttp's HTTP cache hits.
    fun peekMemory(tile: MercatorTiles.Tile): ImageBitmap? {
        if (!enabled) return null
        return memoryCache.get("${tile.z}/${tile.x}/${tile.y}")
    }

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
                val url = buildTileUrl(
                    z = tile.z,
                    x = tile.x,
                    y = tile.y,
                    template = BuildConfig.PUBLIC_TILE_URL_TEMPLATE,
                    maptilerKey = BuildConfig.PUBLIC_MAPTILER_KEY,
                    styleSlug = styleSlug,
                )
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

    /// Evict everything — the in-memory decoded bitmaps and the OkHttp
    /// disk cache. Called on sign-out so the next user on this watch
    /// can't pull the previous user's prefetched route tiles (which
    /// reveal where they run) back off disk, and from `trimMemory` under
    /// the most severe OS pressure. Memory eviction is synchronous and
    /// cheap; the disk eviction (which deletes the journal + entries)
    /// runs on IO.
    suspend fun clear() {
        memoryCache.evictAll()
        withContext(Dispatchers.IO) {
            try {
                client.cache?.evictAll()
            } catch (e: Exception) {
                // Best-effort: a concurrent fetch can hold the cache lock.
                // Leaving stale tiles on disk is harmless (OkHttp caps at
                // 50 MB) — never crash the sign-out path over it.
            }
        }
    }

    /// React to an `onTrimMemory` callback. The in-memory decoded-bitmap
    /// cache is the RAM consumer worth dropping under pressure — the
    /// tiles re-decode from the OkHttp disk cache on the next draw, so
    /// the only cost is a one-frame midnight flash. At the most severe
    /// level (the app is next on the OS kill list) also hand the disk
    /// cache back. Fire-and-forget because `onTrimMemory` runs on the
    /// main thread. The level→disk decision is the pure
    /// [shouldEvictDiskOnTrim] helper so it's unit-testable.
    fun trimMemory(level: Int) {
        memoryCache.evictAll()
        if (shouldEvictDiskOnTrim(level)) {
            ioScope.launch {
                try {
                    client.cache?.evictAll()
                } catch (e: Exception) {
                    // See clear(): best-effort.
                }
            }
        }
    }

    companion object {
        @Volatile private var instance: TileSource? = null

        /// Process-wide singleton. Always pass any context — internally
        /// we anchor on `applicationContext` so the instance outlives
        /// any Activity / ViewModel that asks for it.
        fun get(context: Context): TileSource {
            val app = context.applicationContext
            return instance ?: synchronized(this) {
                instance ?: TileSource(app).also { instance = it }
            }
        }
    }
}

/// Decide whether an `onTrimMemory` at [level] should also evict the
/// OkHttp disk cache (not just the in-memory bitmaps). Only at
/// `TRIM_MEMORY_COMPLETE` (80) — the point where the OS says the app is
/// the next process it will kill — is it worth the disk churn of
/// dropping cached tiles. Lighter levels evict the memory cache only.
///
/// File-level `internal` so the threshold is exercised without an
/// Android `TileSource` instance; the `ComponentCallbacks2` constant is
/// a compile-time `static final int`, so the comparison is inlined and
/// the helper touches no Android class at runtime.
internal fun shouldEvictDiskOnTrim(level: Int): Boolean =
    level >= android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE

/// Decide whether [TileSource] should fetch tiles at all. Returns
/// true iff either the dev override [template] OR the production
/// [maptilerKey] is non-blank. Pure helper extracted so the OR /
/// blank-check semantics can be exercised without booting
/// `BuildConfig`.
///
/// Whitespace counts as absent on both sides — a stray space in
/// `.env.local` (very common copy/paste mistake) shouldn't silently
/// enable the network code path with a `?key=  ` request that
/// MapTiler 401s.
internal fun tileSourceEnabled(template: String, maptilerKey: String): Boolean {
    return template.isNotBlank() || maptilerKey.isNotBlank()
}

/// Build the raster-tile URL for a given (z, x, y). Honours the
/// `PUBLIC_TILE_URL_TEMPLATE` BuildConfig override (used by the
/// local Protomaps tileserver-gl dev setup — see
/// `docs/ops/protomaps_local_setup.md` + `decisions.md § 68`) and falls
/// back to the MapTiler URL keyed by [maptilerKey].
///
/// The template's `{z}`, `{x}`, `{y}` placeholders are substituted
/// literally. A template with no placeholders is returned as-is
/// (operator responsibility; tileserver-gl with a hardcoded
/// `?z=0&x=0&y=0` would silently produce identical tiles for every
/// grid cell, but malforming the override that way is the operator's
/// problem, not the library's).
///
/// File-level `internal` so the unit-test source set can call it
/// without instantiating `TileSource` (which needs a `Context`).
internal fun buildTileUrl(
    z: Int,
    x: Int,
    y: Int,
    template: String,
    maptilerKey: String,
    styleSlug: String = "streets-v2-dark",
): String {
    if (template.isNotBlank()) {
        return template
            .replace("{z}", z.toString())
            .replace("{x}", x.toString())
            .replace("{y}", y.toString())
    }
    return "https://api.maptiler.com/maps/$styleSlug/$z/$x/$y.png?key=$maptilerKey"
}
