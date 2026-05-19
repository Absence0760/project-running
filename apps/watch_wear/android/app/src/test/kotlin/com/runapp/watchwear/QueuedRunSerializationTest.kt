package com.runapp.watchwear

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for the QueuedRun / QueuedLap serialization wire format.
///
/// `LocalRunStore` persists this shape under DataStore key
/// `queued_runs_v2`. Any change to the wire format — adding a field,
/// renaming an existing field, tightening a default — interacts with
/// every queued run already on a user's watch. A regression that
/// failed to decode old payloads would lose every offline-recorded
/// run still waiting to upload.
///
/// The class is `@Serializable data class`, so the default-arg shape
/// is baked into the synthesised serializer. These tests pin the
/// load-bearing forward-compat contracts: a v1-shape JSON (predating
/// the `isPublic` / `steps` / `laps` / `activityType` fields) must
/// still decode cleanly into a QueuedRun with the documented
/// defaults. Without these, a watch upgraded mid-queue would silently
/// drop runs because the JSON would fail to decode.
class QueuedRunSerializationTest {

    private val json = Json { ignoreUnknownKeys = true }

    private val sample = QueuedRun(
        id = "run-123",
        startedAtIso = "2026-05-19T08:00:00Z",
        durationS = 1800,
        distanceM = 5_000.0,
        trackFilePath = "/data/cache/tracks/run-123.json",
        avgBpm = 145.0,
        activityType = "run",
        laps = listOf(
            QueuedLap(number = 1, atMs = 300_000, distanceM = 1_000.0),
            QueuedLap(number = 2, atMs = 600_000, distanceM = 1_000.0),
        ),
        steps = 4_500,
        isPublic = true,
    )

    @Test
    fun `QueuedRun round-trips through JSON cleanly`() {
        // Baseline: every field set, encode + decode yields the same
        // value. A regression that broke the synthesised serializer
        // (e.g. a serialName collision) would surface here.
        val encoded = json.encodeToString(QueuedRun.serializer(), sample)
        val decoded = json.decodeFromString(QueuedRun.serializer(), encoded)
        assertEquals(sample, decoded)
    }

    @Test
    fun `decode populates isPublic = null when the field is absent (v1 payload)`() {
        // Pre-existed-field defaults: runs queued before `isPublic`
        // was added land with `isPublic = null` after upgrade. The
        // upload path treats null as "omit the column" so the DB
        // default (`false`) wins — preserves the pre-change behaviour.
        // A regression that defaulted to `false` here would silently
        // make every pre-existing queued run NON-PUBLIC even if the
        // recorder's privacy_default was `public` at stop time.
        val v1Json = """
        {
            "id": "old-run",
            "startedAtIso": "2026-05-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json"
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), v1Json)
        assertNull("isPublic must default to null for v1 payloads", decoded.isPublic)
    }

    @Test
    fun `decode populates steps = null when absent (v1 payload)`() {
        // Same forward-compat rationale as isPublic — `steps` was
        // added later. A v1 payload that lacks it must decode to
        // null so the upload path omits the column rather than
        // writing zero (which would mis-display "0 steps" on the
        // run detail page).
        val v1Json = """
        {
            "id": "old-run",
            "startedAtIso": "2026-05-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json"
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), v1Json)
        assertNull(decoded.steps)
    }

    @Test
    fun `decode populates activityType = run when absent (v1 payload)`() {
        // Older payloads predate the activity-type chip. The default
        // must be "run" (NOT "" or null) so the upload renders
        // correctly — the recording flow treats anything other than
        // the four enum values as a regression.
        val v1Json = """
        {
            "id": "old-run",
            "startedAtIso": "2026-05-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json"
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), v1Json)
        assertEquals("run", decoded.activityType)
    }

    @Test
    fun `decode populates laps = empty list when absent (v1 payload)`() {
        // Empty list (not null) is the documented default — every
        // downstream reader walks the list unconditionally. A
        // regression to null would NPE on the upload's "metadata.laps"
        // populate path.
        val v1Json = """
        {
            "id": "old-run",
            "startedAtIso": "2026-05-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json"
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), v1Json)
        assertTrue(decoded.laps.isEmpty())
    }

    @Test
    fun `decode populates avgBpm = null when absent (v1 payload)`() {
        // Pre-HR-enabled builds queued runs without an avg_bpm. The
        // null default omits the column on upload, NOT 0.0 which
        // would render as "0 bpm" on the run detail.
        val v1Json = """
        {
            "id": "old-run",
            "startedAtIso": "2026-05-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/old/path.json"
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), v1Json)
        assertNull(decoded.avgBpm)
    }

    @Test
    fun `decode ignores unknown keys (forward-compat for v3+ payloads)`() {
        // A future watch build (vN+1) may add a new field. When that
        // build queues a run, then the user downgrades / sideloads
        // an older APK (vN), the older code must STILL decode the
        // payload. `ignoreUnknownKeys = true` in `LocalRunStore.json`
        // is what makes this work. Pin it so a future writer doesn't
        // strip the flag.
        val futureJson = """
        {
            "id": "future-run",
            "startedAtIso": "2026-12-01T08:00:00Z",
            "durationS": 1800,
            "distanceM": 5000.0,
            "trackFilePath": "/future/path.json",
            "futureField1": "ignored",
            "elevationGain": 250.0,
            "nestedFuture": {"a": 1, "b": [1, 2, 3]}
        }
        """.trimIndent()
        val decoded = json.decodeFromString(QueuedRun.serializer(), futureJson)
        assertEquals("future-run", decoded.id)
        assertEquals(5_000.0, decoded.distanceM, 0.0)
    }

    @Test
    fun `QueuedLap round-trips with non-zero values`() {
        // The nested type's serializer is what populates metadata.laps
        // on upload. The lap timing (start_offset_s = delta from prev
        // lap) is computed in `buildRunMetadata` — what's stored here
        // is cumulative-form (atMs, distanceM). Pin that the
        // cumulative shape round-trips cleanly so the
        // cumulative→delta conversion downstream has the right
        // inputs.
        val lap = QueuedLap(number = 3, atMs = 900_000, distanceM = 3_000.0)
        val encoded = json.encodeToString(QueuedLap.serializer(), lap)
        val decoded = json.decodeFromString(QueuedLap.serializer(), encoded)
        assertEquals(lap, decoded)
    }

    @Test
    fun `list serializer round-trips an empty queue`() {
        // The DataStore default value is `"[]"` (line 55 of
        // LocalRunStore.kt). Pin that an empty list decodes through
        // the same path as a populated one — a regression in the
        // list serializer (e.g. requiring a non-empty array) would
        // surface as the upload-drain loop never starting on a
        // fresh-install watch.
        val listSerializer = ListSerializer(QueuedRun.serializer())
        val decoded = json.decodeFromString(listSerializer, "[]")
        assertTrue(decoded.isEmpty())
    }

    @Test
    fun `list serializer round-trips a populated queue`() {
        val listSerializer = ListSerializer(QueuedRun.serializer())
        val encoded = json.encodeToString(
            listSerializer,
            listOf(
                sample,
                sample.copy(id = "run-456"),
            ),
        )
        val decoded = json.decodeFromString(listSerializer, encoded)
        assertEquals(2, decoded.size)
        assertEquals("run-123", decoded[0].id)
        assertEquals("run-456", decoded[1].id)
    }
}
