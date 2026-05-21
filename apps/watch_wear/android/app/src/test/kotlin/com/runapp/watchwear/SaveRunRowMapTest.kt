package com.runapp.watchwear

import com.runapp.watchwear.generated.RunRow
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Column-set + value-shape pin for `buildSaveRunRowMap` — the helper
/// that produces the `runs.insert` body that
/// `SupabaseClient.saveRun` POSTs to PostgREST.
///
/// Tests cover:
///   - the canonical column set + types
///   - source = "watch" (the schema CHECK constraint accepts this; the
///     mobile / web `RunSource` enum lists it too)
///   - external_id = runId for retry idempotency (matches the unique
///     index on `runs.external_id` so a 409 → drop-and-continue path
///     in the drain loop works correctly)
///   - is_public omitted-vs-set semantics — omitting lets the DB
///     default (`false`) apply, which matches the contract the rest
///     of the codebase relies on for "watch run without an explicit
///     privacy override"
///
/// Any future column rename in a migration regenerates `RunRow.COL_*`
/// constants, so this test inherently follows along — there's no
/// hard-coded column-name string to drift.
class SaveRunRowMapTest {

    private val sampleMetadata: JsonObject = buildJsonObject {
        put("activity_type", "run")
        put("avg_bpm", 142)
    }

    @Test fun `row contains the canonical column set`() {
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "user-1",
            startedAtIso = "2026-01-01T00:00:00.000Z",
            durationS = 3600,
            distanceM = 10_000.0,
            trackPath = "user-1/abc.json.gz",
            metadata = sampleMetadata,
            isPublic = null,
        )
        // Pin every load-bearing column. If a future migration drops
        // one (or the regenerated DbRows.kt does), this test breaks
        // immediately and the wire format failure is loud.
        assertTrue(row.containsKey(RunRow.COL_ID))
        assertTrue(row.containsKey(RunRow.COL_USER_ID))
        assertTrue(row.containsKey(RunRow.COL_STARTED_AT))
        assertTrue(row.containsKey(RunRow.COL_DURATION_S))
        assertTrue(row.containsKey(RunRow.COL_DISTANCE_M))
        assertTrue(row.containsKey(RunRow.COL_SOURCE))
        assertTrue(row.containsKey(RunRow.COL_TRACK_URL))
        assertTrue(row.containsKey(RunRow.COL_METADATA))
        assertTrue(row.containsKey(RunRow.COL_EXTERNAL_ID))
    }

    @Test fun `source is always watch (RunSource enum value) regardless of caller`() {
        // The schema's `runs.source` CHECK constraint requires one of
        // the registered RunSource enum values; "watch" is the
        // Wear OS / watchOS label. Pin it so a sloppy refactor
        // doesn't write "app" by mistake and silently re-label every
        // watch-saved run.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "user-1",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "user-1/abc.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertEquals("watch", row[RunRow.COL_SOURCE])
    }

    @Test fun `external_id equals runId — the retry-idempotency contract`() {
        // The drain loop classifies HTTP 409 as DropAndContinue
        // because a 409 means the row is already in the DB.
        // PostgREST raises 409 when an insert conflicts on a unique
        // index — for watch runs that index is `(external_id)`,
        // populated with the runId. If a future refactor sets
        // external_id to something else (or drops it), every retry
        // would create a duplicate row and the drain loop's 409 path
        // would never fire.
        val row = buildSaveRunRowMap(
            runId = "my-run-id-42",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/my-run-id-42.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertEquals("my-run-id-42", row[RunRow.COL_ID])
        assertEquals("my-run-id-42", row[RunRow.COL_EXTERNAL_ID])
    }

    @Test fun `is_public OMITTED when caller passes null`() {
        // Null privacy default → omit the column entirely so the DB
        // default (false / private) applies. Sending `null`
        // explicitly would write `NULL`, which would then NOT match
        // either privacy bucket on read.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertFalse(
            "is_public must be ABSENT when the caller passes null — DB default applies.",
            row.containsKey(RunRow.COL_IS_PUBLIC),
        )
    }

    @Test fun `is_public PRESENT when caller passes true (privacy_default = public)`() {
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = true,
        )
        assertEquals(true, row[RunRow.COL_IS_PUBLIC])
    }

    @Test fun `is_public PRESENT when caller passes false (privacy_default = followers or private)`() {
        // Both `followers` and `private` map to `is_public = false`
        // per the QueuedRun.privacyDefault → Boolean mapping. Pin
        // that this branch also writes the column explicitly so
        // server-side reads can branch on a stable value.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = false,
        )
        assertEquals(false, row[RunRow.COL_IS_PUBLIC])
    }

    @Test fun `metadata round-trips intact (the JsonObject is not serialised away)`() {
        // The metadata bag carries activity_type + avg_bpm + steps
        // + laps from the watch's WatchRunMetadata.buildRunMetadata
        // call. The save path must hand the object through unchanged
        // — encodeJsonMap downstream will serialise it. If a refactor
        // accidentally stringifies it here, the row's metadata column
        // would receive a string blob instead of jsonb.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = sampleMetadata,
            isPublic = null,
        )
        assertEquals(sampleMetadata, row[RunRow.COL_METADATA])
    }

    @Test fun `null metadata is permitted and written through as null`() {
        // A pre-WatchRunMetadata.buildRunMetadata caller (or a future
        // path that genuinely has no metadata) hands null. The DB
        // permits NULL on `runs.metadata`, so passing it through is
        // correct.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertNull(row[RunRow.COL_METADATA])
    }

    @Test fun `track_path is verbatim — no transformation of the bucket key`() {
        // Storage path convention: `{user_id}/{run_id}.json.gz`. The
        // saveRun upload path constructs this string from the same
        // `uid` and `runId`. Any divergence (path prefix, encoding,
        // trailing slash) would orphan the track from the row.
        // Pin that whatever the caller hands in is what lands in
        // the row.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 60,
            distanceM = 1000.0,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertEquals("u/abc.json.gz", row[RunRow.COL_TRACK_URL])
    }

    @Test fun `numeric types preserved — durationS Int, distanceM Double`() {
        // JsonElement serialisation differs for Int vs Double, and
        // PostgREST's column-type-inference depends on the JSON
        // value's shape. duration_s is an `integer` column;
        // distance_m is `double precision`. A future refactor that
        // accidentally coerced both to one type would either write
        // `60.0` to an integer column (PostgREST silently truncates)
        // or `1000` to a double column (PostgREST widens, no-op).
        // Both would be subtle bugs.
        val row = buildSaveRunRowMap(
            runId = "abc",
            uid = "u",
            startedAtIso = "2026-01-01T00:00:00Z",
            durationS = 3600,
            distanceM = 10_000.5,
            trackPath = "u/abc.json.gz",
            metadata = null,
            isPublic = null,
        )
        assertTrue(
            "duration_s must be Int — column type is integer.",
            row[RunRow.COL_DURATION_S] is Int,
        )
        assertTrue(
            "distance_m must be Double — column type is double precision.",
            row[RunRow.COL_DISTANCE_M] is Double,
        )
        assertEquals(3600, row[RunRow.COL_DURATION_S])
        assertEquals(10_000.5, row[RunRow.COL_DISTANCE_M] as Double, 0.0)
    }
}
