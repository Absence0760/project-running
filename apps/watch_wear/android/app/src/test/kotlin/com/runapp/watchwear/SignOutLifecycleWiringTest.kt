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
        val body = tearDownBody(src)
        assertTrue("must clear the session store", body.contains("sessionStore.clear()"))
        assertTrue("must clear the route store", body.contains("routeStore.clear()"))
        assertTrue("must clear the run queue", body.contains("store.clear()"))
        assertTrue(
            "must clear the tile cache",
            Regex("""TileSource\.get\(.*\)\.clear\(\)""").containsMatchIn(body),
        )
    }

    /// The checkpoint is the same run payload as a queued run, reached by a
    /// different door, and it used to survive the wipe the queue gets. Its
    /// track file survives too — `sweepOrphanTracks` deliberately keeps the
    /// file a checkpoint names — so `gradeRecovery` still graded `Offer` after
    /// a sign-out and the next user to sign in could upload the previous
    /// user's GPS trace into their own account.
    @Test
    fun `tearDownSession disarms the crash checkpoint and its track file`() {
        val src = read("RunViewModel.kt")
        val body = tearDownBody(src)
        assertTrue("must clear the crash checkpoint", body.contains("checkpoints.clear()"))
        // Reading it BEFORE the clear is the only way the path is still known.
        assertTrue(
            "must read the checkpoint before clearing it, or its track file cannot be found",
            body.indexOf("checkpoints.current()") in 0 until body.indexOf("checkpoints.clear()"),
        )
        assertTrue(
            "must delete the checkpoint's own track file",
            Regex("""File\(\w+\.trackFilePath\)\.delete\(\)""").containsMatchIn(body),
        )
        assertTrue(
            "must drop a recovery prompt already on screen",
            Regex("""pendingRecovery\s*=\s*null""").containsMatchIn(body),
        )
    }

    /// `sweepOrphanTracks` keeping the checkpoint's file is what makes the
    /// leak above reachable rather than self-healing, so it is pinned here
    /// too: were it ever to start deleting that file, this guard's reasoning
    /// would need re-deriving rather than silently becoming redundant.
    @Test
    fun `the orphan sweep spares the file the checkpoint names`() {
        val src = read("RunViewModel.kt")
        assertTrue(
            "expected sweepOrphanTracks to exempt the live checkpoint's track file",
            Regex("""checkpoints\.current\(\)""").containsMatchIn(src),
        )
    }

    private fun tearDownBody(src: String): String {
        val block = Regex("""private suspend fun tearDownSession\(\)\s*\{([\s\S]*?)\n    \}""")
            .find(src)?.groupValues?.get(1)
        assertTrue("expected a tearDownSession body", block != null)
        return block!!
    }
}
