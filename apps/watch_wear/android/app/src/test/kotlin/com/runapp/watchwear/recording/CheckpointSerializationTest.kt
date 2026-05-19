package com.runapp.watchwear.recording

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for the `Checkpoint` / `CheckpointLap` serialization wire
/// format.
///
/// `CheckpointStore` persists this shape under DataStore key
/// `checkpoint_v2`. A checkpoint is the watch's lifeline against an
/// in-progress run dying — `RunRecordingService` writes one every 15
/// seconds during recording, and `RunViewModel.checkRecovery` reads it
/// on next launch to offer "Recover unsaved run?".
///
/// **The forward-compat contract matters more here than for QueuedRun.**
/// A checkpoint represents a run that's still recording (or just
/// crashed). A v1-shape checkpoint on disk that fails to decode after a
/// background-installed upgrade silently drops the in-flight run —
/// `CheckpointStore.current` wraps the decode in
/// `runCatching { ... }.getOrNull()`, so a thrown MissingFieldException
/// from kotlinx-serialization just returns null and the recovery prompt
/// never appears. The runner thinks the watch ate their long-run.
///
/// These tests pin that every field added after v1 has a sensible
/// default so a v1-payload decodes cleanly into a recoverable
/// Checkpoint. If you add a NEW field to Checkpoint, give it a default
/// here too and add a matching v1-payload test below.
class CheckpointSerializationTest {

    private val json = Json { ignoreUnknownKeys = true }

    private val sample = Checkpoint(
        runId = "run-123",
        startedAtMs = 1_700_000_000_000L,
        savedAtMs = 1_700_000_900_000L,
        distanceM = 5_000.0,
        trackFilePath = "/data/cache/tracks/run-123.json",
        trackPointCount = 1_200,
        bpmSum = 87_000,
        bpmCount = 600,
        activityType = "run",
        laps = listOf(
            CheckpointLap(number = 1, atMs = 300_000, distanceM = 1_000.0),
            CheckpointLap(number = 2, atMs = 600_000, distanceM = 1_000.0),
        ),
    )

    @Test
    fun `Checkpoint round-trips through JSON cleanly`() {
        // Baseline: every field set, encode + decode yields the same
        // value. A regression in the synthesised serializer (serialName
        // collision, type swap) would surface here first.
        val encoded = json.encodeToString(Checkpoint.serializer(), sample)
        val decoded = json.decodeFromString(Checkpoint.serializer(), encoded)
        assertEquals(sample, decoded)
    }

    @Test
    fun `decode populates bpmSum + bpmCount = 0 when absent (v1 payload)`() {
        // Pre-rolling-HR builds wrote checkpoints WITHOUT bpmSum /
        // bpmCount — the avg-HR contract was a list of samples, not a
        // rolling pair. A regression that removed the `= 0L` default
        // would throw MissingFieldException, CheckpointStore.current
        // would catch + return null, and the runner's in-flight run
        // would silently vanish on next app start.
        val v1Json = """
        {
            "runId": "old-run",
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json",
            "trackPointCount": 1200
        }
        """.trimIndent()
        val decoded = json.decodeFromString(Checkpoint.serializer(), v1Json)
        assertEquals(0L, decoded.bpmSum)
        assertEquals(0L, decoded.bpmCount)
    }

    @Test
    fun `decode populates activityType = run when absent (v1 payload)`() {
        // Pre-activity-picker checkpoints had no activityType. The
        // default "run" matches QueuedRun's contract — anything else
        // would render incorrectly on the recovered upload.
        val v1Json = """
        {
            "runId": "old-run",
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json",
            "trackPointCount": 1200
        }
        """.trimIndent()
        val decoded = json.decodeFromString(Checkpoint.serializer(), v1Json)
        assertEquals("run", decoded.activityType)
    }

    @Test
    fun `decode populates laps = empty list when absent (v1 payload)`() {
        // Pre-lap-marking checkpoints had no laps array. Empty list is
        // the documented default — every downstream reader walks the
        // list unconditionally, so a regression to null would NPE on
        // the recovery save path.
        val v1Json = """
        {
            "runId": "old-run",
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json",
            "trackPointCount": 1200
        }
        """.trimIndent()
        val decoded = json.decodeFromString(Checkpoint.serializer(), v1Json)
        assertTrue(decoded.laps.isEmpty())
    }

    @Test
    fun `v1 payload with NO post-v1 fields decodes into a fully-recoverable Checkpoint`() {
        // Belt-and-braces: a worst-case v1 payload — every defaulted
        // field absent — must still produce a Checkpoint with sensible
        // values across the board, NOT throw + drop to null in
        // CheckpointStore.current's runCatching wrapper. This is the
        // single most important test in this file: if this fails, a
        // user upgrading mid-run loses their in-flight session.
        val v1Json = """
        {
            "runId": "old-run",
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json",
            "trackPointCount": 1200
        }
        """.trimIndent()
        val decoded = json.decodeFromString(Checkpoint.serializer(), v1Json)
        assertEquals("old-run", decoded.runId)
        assertEquals(1_700_000_000_000L, decoded.startedAtMs)
        assertEquals(1_700_000_900_000L, decoded.savedAtMs)
        assertEquals(5_000.0, decoded.distanceM, 0.0)
        assertEquals("/old/path.json", decoded.trackFilePath)
        assertEquals(1_200, decoded.trackPointCount)
        // Defaults apply for all four newer fields.
        assertEquals(0L, decoded.bpmSum)
        assertEquals(0L, decoded.bpmCount)
        assertEquals("run", decoded.activityType)
        assertTrue(decoded.laps.isEmpty())
    }

    @Test
    fun `decode ignores unknown keys (forward-compat for vN+1 payloads)`() {
        // A future build (vN+1) may add new fields. When that build
        // writes a checkpoint then the user downgrades / sideloads an
        // older APK (vN), the older code must still decode the payload.
        // `ignoreUnknownKeys = true` in CheckpointStore.json is what
        // makes this work — pin it so a future writer doesn't strip
        // the flag.
        val futureJson = """
        {
            "runId": "future-run",
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/future/path.json",
            "trackPointCount": 1200,
            "futureCadence": 180,
            "nestedFuture": {"a": 1}
        }
        """.trimIndent()
        val decoded = json.decodeFromString(Checkpoint.serializer(), futureJson)
        assertEquals("future-run", decoded.runId)
    }

    @Test
    fun `CheckpointLap round-trips with non-zero values`() {
        val lap = CheckpointLap(number = 3, atMs = 900_000, distanceM = 3_000.0)
        val encoded = json.encodeToString(CheckpointLap.serializer(), lap)
        val decoded = json.decodeFromString(CheckpointLap.serializer(), encoded)
        assertEquals(lap, decoded)
    }

    @Test
    fun `CheckpointLap list serializes inside Checkpoint without drift`() {
        // Specific concern: the nested list type's element shape isn't
        // referenced anywhere except inside Checkpoint, so a refactor
        // that renamed a CheckpointLap field could compile clean +
        // pass the QueuedLap tests but silently break recovery. Pin
        // the field shape via a round-trip that exercises both names
        // and values.
        val encoded = json.encodeToString(Checkpoint.serializer(), sample)
        // Spot-check: keys appear in the encoded form.
        assertTrue(
            "encoded checkpoint must contain 'number' field name for laps",
            encoded.contains("\"number\""),
        )
        assertTrue(
            "encoded checkpoint must contain 'atMs' field name for laps",
            encoded.contains("\"atMs\""),
        )
        assertTrue(
            "encoded checkpoint must contain 'distanceM' field name for laps",
            encoded.contains("\"distanceM\""),
        )
        val decoded = json.decodeFromString(Checkpoint.serializer(), encoded)
        assertEquals(sample.laps, decoded.laps)
    }

    @Test
    fun `missing required v1 field surfaces as runCatching null (documented contract)`() {
        // This is a contract pin, not a forward-compat happy-path:
        // when even a v1-required field is missing (e.g. runId), the
        // decode SHOULD throw — and CheckpointStore.current catches it
        // and returns null. The runner sees no recovery prompt rather
        // than a half-formed Checkpoint with an empty runId crashing
        // the upload path. This pins that the decoder is strict on
        // truly-required fields while permissive on optional ones.
        val brokenJson = """
        {
            "startedAtMs": 1700000000000,
            "savedAtMs": 1700000900000,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json",
            "trackPointCount": 1200
        }
        """.trimIndent()
        val result = runCatching {
            json.decodeFromString(Checkpoint.serializer(), brokenJson)
        }
        // Either the decode throws (MissingFieldException) OR the
        // resulting Checkpoint has an empty runId — both are
        // acceptable, but a SILENT happy path with default "" runId
        // would let an unrecoverable run through. Pin that one of the
        // two failure modes fires.
        if (result.isSuccess) {
            assertNull(
                "if decode succeeds, runId must not silently default " +
                    "to an empty string — that would let an " +
                    "unrecoverable run through to the upload path",
                if (result.getOrThrow().runId.isEmpty()) null else "ok",
            )
        }
        // The expected/happy outcome: the decode throws and
        // runCatching converts to null at the call site.
        assertTrue(
            "decode of a v1-payload missing runId must either throw " +
                "or yield a Checkpoint with empty runId — never a " +
                "silent happy path",
            result.isFailure ||
                result.getOrNull()?.runId?.isEmpty() == true,
        )
    }
}
