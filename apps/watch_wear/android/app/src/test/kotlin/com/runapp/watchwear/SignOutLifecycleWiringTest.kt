package com.runapp.watchwear

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the sign-out lifecycle (L3 + L4): every
/// per-user cache on the watch must be wiped on sign-out so nothing
/// carries over to the next user. LocalRunStore previously had no
/// clear() at all and was left untouched by `tearDownSession`, so a run
/// queued by user A could upload under user B's credentials on the next
/// drain.
///
/// The stores are DataStore-/Context-bound (not host-JVM-testable
/// without Robolectric), so the contract is pinned with a source grep
/// per the module's convention.
class SignOutLifecycleWiringTest {

    private fun read(rel: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

    @Test
    fun `LocalRunStore exposes a clear that wipes the queue and its track files`() {
        val src = read("LocalRunStore.kt")
        assertTrue("LocalRunStore must expose clear()", src.contains("suspend fun clear()"))
        // It must delete the on-disk track files, not just the queue key,
        // so the previous user's GPS traces don't linger in the cache dir.
        assertTrue(
            "clear() must delete the referenced track files",
            Regex("""File\(run\.trackFilePath\)\.delete\(\)""").containsMatchIn(src),
        )
        assertTrue(
            "clear() must drop the queue key",
            src.contains("prefs.remove(KEY_QUEUE)"),
        )
    }

    @Test
    fun `tearDownSession wipes every per-user cache including the run queue`() {
        val src = read("RunViewModel.kt")
        val block = Regex("""private suspend fun tearDownSession\(\)\s*\{([\s\S]*?)\n    \}""")
            .find(src)?.groupValues?.get(1)
        assertTrue("expected a tearDownSession body", block != null)
        val body = block!!
        assertTrue("must clear the session store", body.contains("sessionStore.clear()"))
        assertTrue("must clear the route store", body.contains("routeStore.clear()"))
        assertTrue("must clear the run queue", body.contains("store.clear()"))
        assertTrue(
            "must clear the tile cache",
            Regex("""TileSource\.get\(.*\)\.clear\(\)""").containsMatchIn(body),
        )
    }
}
