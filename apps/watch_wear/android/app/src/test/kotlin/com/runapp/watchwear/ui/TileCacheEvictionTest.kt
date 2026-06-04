package com.runapp.watchwear.ui

import android.content.ComponentCallbacks2
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Covers the tile-cache eviction paths added for M2: the OkHttp disk
/// cache + in-memory bitmap LRU previously had no way to be flushed on
/// sign-out or under OS memory pressure.
///
/// The pure level→disk decision is unit-testable directly; the actual
/// `clear()` / `trimMemory()` eviction needs a real OkHttp `Cache` +
/// `Context`, and the call-site wiring lives in `@Composable`-adjacent
/// host classes — both follow the module's "source-grep arch guard"
/// convention rather than Robolectric.
class TileCacheEvictionTest {

    // ─────────────── shouldEvictDiskOnTrim thresholds ───────────────

    @Test
    fun `disk evicted only at TRIM_MEMORY_COMPLETE and above`() {
        assertTrue(shouldEvictDiskOnTrim(ComponentCallbacks2.TRIM_MEMORY_COMPLETE))
    }

    @Test
    fun `lighter trim levels keep the disk cache`() {
        // Memory cache still drops at these levels (trimMemory always
        // evicts memory) — only the disk eviction is gated.
        assertFalse(shouldEvictDiskOnTrim(ComponentCallbacks2.TRIM_MEMORY_MODERATE))
        assertFalse(shouldEvictDiskOnTrim(ComponentCallbacks2.TRIM_MEMORY_BACKGROUND))
        assertFalse(shouldEvictDiskOnTrim(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN))
        assertFalse(shouldEvictDiskOnTrim(ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL))
        assertFalse(shouldEvictDiskOnTrim(0))
    }

    // ─────────────── eviction wiring guards ───────────────

    private fun read(path: String): String = File(path).readText()

    @Test
    fun `TileSource exposes clear and trimMemory that evict both caches`() {
        val src = read("src/main/kotlin/com/runapp/watchwear/ui/TileSource.kt")
        assertTrue("clear() must exist", src.contains("suspend fun clear()"))
        assertTrue("trimMemory() must exist", src.contains("fun trimMemory(level: Int)"))
        // clear() drops the in-memory LRU and the OkHttp disk cache.
        assertTrue("clear must evict the memory LRU", src.contains("memoryCache.evictAll()"))
        assertTrue("must evict the OkHttp disk cache", src.contains("client.cache?.evictAll()"))
    }

    @Test
    fun `onTrimMemory is wired in MainActivity to TileSource trimMemory`() {
        val src = read("src/main/kotlin/com/runapp/watchwear/MainActivity.kt")
        assertTrue(
            "MainActivity must override onTrimMemory",
            src.contains("override fun onTrimMemory(level: Int)"),
        )
        assertTrue(
            "onTrimMemory must delegate to TileSource.trimMemory",
            Regex("""TileSource\.get\([^)]*\)\.trimMemory\(level\)""").containsMatchIn(src),
        )
    }

    @Test
    fun `sign-out teardown clears the tile cache`() {
        val src = read("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt")
        // tearDownSession runs on both signOut and the phone-side cleared
        // signal; it must flush tiles so prefetched route tiles don't
        // carry over to the next user on this watch.
        assertTrue(
            "tearDownSession must clear the TileSource",
            Regex("""TileSource\.get\(.*\)\.clear\(\)""").containsMatchIn(src),
        )
    }
}
