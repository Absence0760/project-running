package com.runapp.watchwear.recording

import com.runapp.watchwear.QueuedRun
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/// Covers the cache→files track migration and the orphan sweep that
/// replaces the platform's own reclamation of the old cache directory.
///
/// The bug being pinned: an unsynced run's GPS track was the only copy of
/// the trace and lived in `context.cacheDir`, which the platform purges
/// under storage pressure. Moving the directory is only half the fix — an
/// upgrade over an install with runs already queued has to carry those
/// files across, and the new home has to be swept, because `filesDir` never
/// reclaims anything on its own.
class TrackStorageTest {

    private lateinit var root: File
    private lateinit var legacy: File
    private lateinit var durable: File

    @Before fun setUp() {
        root = File.createTempFile("track_storage", "").let {
            it.delete()
            it.mkdirs()
            it
        }
        legacy = File(root, "cache/tracks").also { it.mkdirs() }
        durable = File(root, "files/tracks")
    }

    @After fun tearDown() {
        root.deleteRecursively()
    }

    private fun queued(id: String, path: String) = QueuedRun(
        id = id,
        startedAtIso = "2026-01-01T00:00:00Z",
        durationS = 3600,
        distanceM = 10_000.0,
        trackFilePath = path,
    )

    private fun legacyTrack(id: String, body: String = "[]"): File =
        File(legacy, "$id.json").also { it.writeText(body) }

    // ───────────────────────── migration ─────────────────────────

    @Test fun `a queued run's cached track moves to the durable dir and the entry follows`() {
        val source = legacyTrack("run-a", "[{\"lat\":1.0}]")
        val migrated = migrateQueuedTracks(listOf(queued("run-a", source.absolutePath)), legacy, durable)

        val destination = File(durable, "run-a.json")
        assertEquals(destination.absolutePath, migrated.single().trackFilePath)
        assertTrue("the payload must exist at the new path", destination.exists())
        assertEquals("[{\"lat\":1.0}]", destination.readText())
        assertFalse("the cached copy must not be left behind", source.exists())
    }

    @Test fun `every queued run migrates, not just the first`() {
        val runs = listOf("a", "b", "c").map { queued(it, legacyTrack(it).absolutePath) }
        val migrated = migrateQueuedTracks(runs, legacy, durable)

        assertEquals(
            listOf("a", "b", "c").map { File(durable, "$it.json").absolutePath },
            migrated.map { it.trackFilePath },
        )
    }

    @Test fun `a run whose cached payload was already purged keeps its old path`() {
        // Rewriting the entry to a durable path that has no file behind it
        // would recast "the platform purged this" as "this run never had a
        // track", and the two need different handling at drain time.
        val ghost = File(legacy, "gone.json").absolutePath
        val migrated = migrateQueuedTracks(listOf(queued("gone", ghost)), legacy, durable)

        assertEquals(ghost, migrated.single().trackFilePath)
        assertFalse(File(durable, "gone.json").exists())
    }

    @Test fun `a run already on the durable path is left alone`() {
        durable.mkdirs()
        val already = File(durable, "run-a.json").also { it.writeText("[]") }
        val migrated = migrateQueuedTracks(listOf(queued("run-a", already.absolutePath)), legacy, durable)

        assertEquals(already.absolutePath, migrated.single().trackFilePath)
        assertTrue(already.exists())
    }

    @Test fun `migration is idempotent across relaunches`() {
        val source = legacyTrack("run-a")
        val once = migrateQueuedTracks(listOf(queued("run-a", source.absolutePath)), legacy, durable)
        val twice = migrateQueuedTracks(once, legacy, durable)

        assertEquals(once.map { it.trackFilePath }, twice.map { it.trackFilePath })
        assertTrue(File(durable, "run-a.json").exists())
    }

    @Test fun `a file outside the legacy dir is never touched`() {
        val elsewhere = File(root, "elsewhere.json").also { it.writeText("[]") }
        val migrated = migrateQueuedTracks(listOf(queued("x", elsewhere.absolutePath)), legacy, durable)

        assertEquals(elsewhere.absolutePath, migrated.single().trackFilePath)
        assertTrue(elsewhere.exists())
    }

    // ─────────────────────────── sweep ───────────────────────────

    private fun durableTrack(name: String, ageMs: Long): File {
        durable.mkdirs()
        return File(durable, name).also {
            it.writeText("[]")
            it.setLastModified(NOW - ageMs)
        }
    }

    @Test fun `an aged unreferenced track is deleted`() {
        val orphan = durableTrack("orphan.json", 2 * TrackStorage.ORPHAN_MIN_AGE_MS)
        val deleted = sweepOrphanTracks(durable, emptySet(), NOW)

        assertEquals(listOf(orphan.absolutePath), deleted.map { it.absolutePath })
        assertFalse(orphan.exists())
    }

    @Test fun `a queued run's track survives the sweep`() {
        val kept = durableTrack("queued.json", 2 * TrackStorage.ORPHAN_MIN_AGE_MS)
        sweepOrphanTracks(durable, setOf(kept.absolutePath), NOW)
        assertTrue(kept.exists())
    }

    @Test fun `a pending crash recovery's track survives the sweep`() {
        // Not in the queue until the runner accepts the prompt, and easily
        // older than the age gate after an overnight crash — exactly the
        // file a naive sweep would eat.
        val checkpoint = durableTrack("recovering.json", 9 * TrackStorage.ORPHAN_MIN_AGE_MS)
        sweepOrphanTracks(durable, setOf(checkpoint.absolutePath), NOW)
        assertTrue(checkpoint.exists())
    }

    @Test fun `a track younger than the age gate survives even unreferenced`() {
        val fresh = durableTrack("fresh.json", TrackStorage.ORPHAN_MIN_AGE_MS / 2)
        assertEquals(emptyList<File>(), sweepOrphanTracks(durable, emptySet(), NOW))
        assertTrue(fresh.exists())
    }

    @Test fun `a missing directory sweeps to nothing rather than throwing`() {
        assertEquals(emptyList<File>(), sweepOrphanTracks(File(root, "never"), emptySet(), NOW))
    }

    private companion object {
        const val NOW = 1_800_000_000_000L
    }
}
