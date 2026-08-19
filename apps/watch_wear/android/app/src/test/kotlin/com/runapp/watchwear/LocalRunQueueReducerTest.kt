package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The pure half of `LocalRunStore`'s three queue mutations — the halves
/// that must run against the `Preferences` snapshot inside DataStore's
/// `edit` transaction rather than against a `queue.first()` read taken
/// outside it.
///
/// A stale-snapshot write is what let an uploaded run come back: the drain
/// removed it, a concurrent `save` wrote a list built before that removal,
/// and the entry reappeared pointing at a track file the drain had already
/// deleted. Every later drain then failed on the missing payload and the
/// entry never cleared.
class LocalRunQueueReducerTest {

    private fun run(id: String, distanceM: Double = 10_000.0) = QueuedRun(
        id = id,
        startedAtIso = "2026-01-01T00:00:00Z",
        durationS = 3600,
        distanceM = distanceM,
        trackFilePath = "/data/tracks/$id.json",
    )

    @Test fun `save appends to an absent queue`() {
        val ids = decodeQueue(queueAfterSave(null, run("a"))).map { it.id }
        assertEquals(listOf("a"), ids)
    }

    @Test fun `save appends to an existing queue`() {
        val raw = queueAfterSave(queueAfterSave(null, run("a")), run("b"))
        assertEquals(listOf("a", "b"), decodeQueue(raw).map { it.id })
    }

    @Test fun `save replaces an entry with the same id rather than duplicating it`() {
        val raw = queueAfterSave(queueAfterSave(null, run("a", 1.0)), run("a", 42.0))
        val queue = decodeQueue(raw)
        assertEquals(1, queue.size)
        assertEquals(42.0, queue.single().distanceM, 0.0)
    }

    @Test fun `remove drops only the named id`() {
        var raw = queueAfterSave(null, run("a"))
        raw = queueAfterSave(raw, run("b"))
        raw = queueAfterSave(raw, run("c"))
        assertEquals(listOf("a", "c"), decodeQueue(queueAfterRemove(raw, "b")).map { it.id })
    }

    @Test fun `remove of an absent id leaves the queue untouched`() {
        val raw = queueAfterSave(null, run("a"))
        assertEquals(listOf("a"), decodeQueue(queueAfterRemove(raw, "nope")).map { it.id })
    }

    @Test fun `a save applied to the drain's post-removal state cannot resurrect the removed run`() {
        // The whole point of reducing against the transaction's own snapshot:
        // the removal is already in `raw` when the save reduces over it, so
        // the uploaded run stays gone.
        var raw = queueAfterSave(null, run("uploaded"))
        raw = queueAfterRemove(raw, "uploaded")
        raw = queueAfterSave(raw, run("just-finished"))

        assertEquals(listOf("just-finished"), decodeQueue(raw).map { it.id })
    }

    @Test fun `a corrupt payload reduces to a queue holding just the new run`() {
        // Fail-open on decode would be a silent data loss either way; what
        // must not happen is the mutation throwing and the just-finished run
        // never being persisted at all.
        val raw = queueAfterSave("{not json", run("a"))
        assertEquals(listOf("a"), decodeQueue(raw).map { it.id })
    }

    @Test fun `round-tripping preserves every field the upload needs`() {
        val original = run("a").copy(
            avgBpm = 142.0,
            activityType = "walk",
            laps = listOf(QueuedLap(1, 1_000L, 1000.0)),
            steps = 5000,
            isPublic = true,
        )
        val restored = decodeQueue(queueAfterSave(null, original)).single()
        assertEquals(original, restored)
        assertTrue(restored.trackFilePath.isNotEmpty())
    }
}
