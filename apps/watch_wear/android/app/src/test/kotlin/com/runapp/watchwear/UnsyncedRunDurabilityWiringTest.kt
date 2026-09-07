package com.runapp.watchwear

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guards for the three properties that keep a recorded run
/// alive between "stop" and "uploaded". The stores and the ViewModel are
/// DataStore-/Context-bound, so per this module's convention (see
/// `SignOutLifecycleWiringTest`) the contract is pinned by reading the
/// source; the logic underneath each one is covered by
/// `TrackStorageTest`, `LocalRunQueueReducerTest` and `SingleFlightTest`.
///
/// The three properties:
///   1. an unsynced payload lives where only this app can delete it;
///   2. the queue is mutated inside DataStore's transaction, so a removal
///      cannot be undone by a concurrent save built on a stale snapshot;
///   3. only one drain, and only one token refresh, runs at a time.
class UnsyncedRunDurabilityWiringTest {

    private fun read(rel: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

    private fun body(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("expected `$signature` in source", start >= 0)
        val open = source.indexOf('{', start)
        var depth = 0
        var i = open
        while (i < source.length) {
            if (source[i] == '{') depth++
            if (source[i] == '}') {
                depth--
                if (depth == 0) return source.substring(open, i + 1)
            }
            i++
        }
        throw AssertionError("unbalanced braces after `$signature`")
    }

    // ─────────── 1. the payload is not in a purgeable directory ───────────

    @Test
    fun `a run's track file is written to the durable files dir`() {
        val src = read("recording/TrackStorage.kt")
        assertTrue(
            "TrackStorage.durableDir must resolve under filesDir — cacheDir is " +
                "reclaimed by the platform under storage pressure, and until the " +
                "run uploads that file is the only copy of the trace.",
            Regex("""fun durableDir\(context: Context\): File = File\(context\.filesDir""")
                .containsMatchIn(src),
        )
        assertFalse(
            "TrackWriter must not resolve a run's track under cacheDir",
            read("recording/TrackWriter.kt").contains("context.cacheDir"),
        )
    }

    @Test
    fun `an existing install's queued tracks are migrated out of the cache dir`() {
        val store = read("LocalRunStore.kt")
        assertTrue(
            "LocalRunStore must expose a migration that rewrites queued paths",
            store.contains("suspend fun migrateTrackFiles("),
        )
        assertTrue(
            "the migration must move the files and rewrite the queue in one edit",
            body(store, "suspend fun migrateTrackFiles(")
                .let { it.contains("dataStore.edit") && it.contains("migrateQueuedTracks(") },
        )
        val vm = read("RunViewModel.kt")
        assertTrue(
            "the ViewModel must run the migration against the legacy cache dir",
            body(vm, "private suspend fun reconcileTrackStorage()")
                .contains("TrackStorage.legacyCacheDir(app)"),
        )
        val drain = body(vm, "private suspend fun drainQueueLocked(")
        val reconcileAt = drain.indexOf("reconcileTrackStorage()")
        val snapshotAt = drain.indexOf("store.queue.first()")
        assertTrue("expected the reconcile call in drainQueue", reconcileAt >= 0)
        assertTrue(
            "a drain must reconcile storage before it reads the queue, or it " +
                "would upload against paths still pointing at the purgeable dir",
            reconcileAt < snapshotAt,
        )
    }

    @Test
    fun `a queued run whose payload is gone still uploads instead of sticking forever`() {
        val push = body(read("RunViewModel.kt"), "private suspend fun pushRun(")
        assertTrue(
            "pushRun must tolerate a missing track file rather than throwing ENOENT",
            push.contains("takeIf { it.exists() }"),
        )
        assertFalse(
            "pushRun must not delete the track file — the delete belongs after " +
                "the queue entry is removed, or a crash between the two leaves an " +
                "entry whose re-post would null out an already-uploaded track_url",
            push.contains("delete()"),
        )
    }

    // ─────────── 2. the queue mutates inside the transaction ───────────

    @Test
    fun `save and remove mutate inside one DataStore edit`() {
        val src = read("LocalRunStore.kt")
        for (signature in listOf("suspend fun save(run: QueuedRun)", "suspend fun remove(id: String)")) {
            val block = body(src, signature)
            assertTrue("`$signature` must mutate inside dataStore.edit", block.contains("dataStore.edit"))
            assertFalse(
                "`$signature` must not read the queue outside the transaction — a " +
                    "read-modify-write on a stale snapshot resurrects an uploaded run " +
                    "after its track file has been deleted",
                block.contains("queue.first()"),
            )
        }
        assertFalse(
            "clear() must read the queue it is dropping from inside the same edit",
            body(src, "suspend fun clear()").contains("queue.first()"),
        )
    }

    // ─────────── 3. one drain, one refresh ───────────

    @Test
    fun `drainQueue is serialised`() {
        val vm = read("RunViewModel.kt")
        assertTrue(
            "cold start fires two drains (cached-session restore + phone-bridge " +
                "restore) and neither is held off by backoff at zero failures, so " +
                "drainQueue must hold a mutex across the whole pass",
            Regex("""drainMutex\.withLock \{ drainQueueLocked\(force\) \}""")
                .containsMatchIn(vm),
        )
    }

    @Test
    fun `a dropped queue entry goes before the file it points at`() {
        // The ordering had one caller and lived inline in the drain hook until
        // the rejected-queue discard became a second one (decisions § 1347).
        // Two copies of an invariant is one copy that can drift, so it moved to
        // `dropQueuedRun` — and this guard follows it there rather than reading
        // whichever caller happens to be first in the file.
        val vm = read("RunViewModel.kt")
        val drop = body(vm, "private suspend fun dropQueuedRun(")
        val removeAt = drop.indexOf("store.remove(id)")
        val deleteAt = drop.indexOf("File(run.trackFilePath).delete()")
        assertTrue("expected the queue removal in dropQueuedRun", removeAt >= 0)
        assertTrue("expected the track delete in dropQueuedRun", deleteAt >= 0)
        assertTrue("the queue entry must go first", removeAt < deleteAt)
        // …and the drain must still go through it, or the ordering is guarded
        // in a function the upload path no longer calls.
        val drain = body(vm, "private suspend fun drainQueueLocked(")
        assertTrue(
            "the drain's onSuccessfulDrain hook must delegate to dropQueuedRun — " +
                "an inline copy is the drift this move exists to prevent",
            Regex("""onSuccessfulDrain = OnSuccessfulDrain \{ id -> dropQueuedRun\(id""")
                .containsMatchIn(drain),
        )
        assertFalse(
            "the drain hook must not delete a track file itself",
            drain.contains("File(run.trackFilePath).delete()"),
        )
    }

    @Test
    fun `refreshAccessToken is single-flighted`() {
        val src = read("SupabaseClient.kt")
        assertTrue(
            "two concurrent refreshes race a rotating refresh token — the second " +
                "spends one the first already consumed and the watch signs out",
            Regex("""suspend fun refreshAccessToken\(\): RefreshedSession = refreshFlight\.run \{""")
                .containsMatchIn(src),
        )
    }
}
