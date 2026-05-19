package com.runapp.watchwear

import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Edge-cases for `buildRunMetadata`. The happy-path multi-lap fixture
/// is exercised by `WatchRunPayloadFixtureTest`; this file pins the
/// CONDITIONAL paths that decide whether each optional key appears
/// on the row at all.
///
/// Every conditional in `buildRunMetadata` is a contract: web's row
/// reader and the run-detail screen both branch on
/// `metadata['avg_bpm'] != null`, `metadata['steps'] != null`, etc.
/// A regression that wrote `0` instead of omitting (for steps), or
/// `null` instead of omitting (for avg_bpm), would surface as
/// "0 steps" / "0 bpm" on the run-detail page — which trains users
/// to distrust the values.
class WatchRunMetadataTest {

    private val isoStamp = "2026-05-19T12:34:56Z"

    @Test
    fun `null avgBpm omits the avg_bpm key entirely`() {
        // Pre-HR-enabled watches (and `BuildConfig.ENABLE_HR=false`)
        // produce avgBpm=null. The row must NOT carry an avg_bpm key
        // at all — the run-detail "N bpm avg" pill keys off presence,
        // not non-zero.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertFalse("avg_bpm must be absent when null", md.containsKey("avg_bpm"))
    }

    @Test
    fun `non-null avgBpm round-trips with one-decimal precision`() {
        // The watch averages across MeasureClient samples — a double
        // is the natural carrier. The web reader expects a numeric
        // (not a string) for the run-detail BPM display.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = 145.7,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertEquals(145.7, md["avg_bpm"]!!.jsonPrimitive.double, 0.0001)
    }

    @Test
    fun `null steps omits the steps key entirely`() {
        // Pre-pedometer-permission runs queue with steps=null. The
        // upload must omit the key — a 0-value would render as "0
        // steps" on the run-detail strip.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertFalse("steps must be absent when null", md.containsKey("steps"))
    }

    @Test
    fun `zero steps omits the steps key (the gt-zero guard)`() {
        // Sensor permission was granted but the sensor never delivered
        // a sample (rare — short run, no movement). The `> 0` guard
        // in buildRunMetadata MUST omit. A regression to `!= null` would
        // emit "0 steps" on the run detail — trains the user to
        // distrust the count. Pin the guard.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = 0,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertFalse("steps==0 must be omitted, not written", md.containsKey("steps"))
    }

    @Test
    fun `positive steps round-trips as an int`() {
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = 4_521,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertEquals(4_521, md["steps"]!!.jsonPrimitive.int)
    }

    @Test
    fun `empty laps omits the laps key entirely`() {
        // A run without any user-tapped laps queues with laps=emptyList.
        // The key must NOT appear — downstream readers (notably the
        // mobile delta-fetch) treat `metadata.laps == null` as
        // "no laps", and an empty array would still render an
        // empty laps section on the run detail.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertFalse("empty laps must be absent, not []", md.containsKey("laps"))
    }

    @Test
    fun `single lap renders with start_offset_s = 0 + zero-based deltas`() {
        // First lap is special: start_offset_s = 0, duration_s and
        // distance_m are deltas from time-zero. A regression in the
        // running-total counters would produce start_offset_s !=
        // 0 for the first lap.
        val laps = listOf(
            QueuedLap(number = 1, atMs = 300_000, distanceM = 1_000.0),
        )
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = laps,
            lastModifiedAtIso = isoStamp,
        )
        val arr = md["laps"]!!.jsonArray
        assertEquals(1, arr.size)
        val lap = arr[0].jsonObject
        assertEquals(1, lap["index"]!!.jsonPrimitive.int)
        assertEquals(0, lap["start_offset_s"]!!.jsonPrimitive.int)
        assertEquals(1_000.0, lap["distance_m"]!!.jsonPrimitive.double, 0.0001)
        assertEquals(300, lap["duration_s"]!!.jsonPrimitive.int)
    }

    @Test
    fun `cumulative to delta conversion is correct across three laps`() {
        // Mirrors the canonical fixture intent but with explicit
        // cumulative inputs. A regression that compared cumulative
        // values directly (skipping the prevMs / prevDist running
        // totals) would write the wrong deltas for lap 2 onwards —
        // the most insidious bug because lap 1 looks right but the
        // splits page would show inflated values for the rest.
        val laps = listOf(
            QueuedLap(number = 1, atMs = 300_000, distanceM = 1_000.0),
            QueuedLap(number = 2, atMs = 600_000, distanceM = 2_050.0),
            QueuedLap(number = 3, atMs = 905_000, distanceM = 3_100.0),
        )
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = laps,
            lastModifiedAtIso = isoStamp,
        )
        val arr = md["laps"]!!.jsonArray
        assertEquals(3, arr.size)

        // Lap 1: from 0 → 300s, 0m → 1000m. Deltas: 300s, 1000m.
        val l1 = arr[0].jsonObject
        assertEquals(0, l1["start_offset_s"]!!.jsonPrimitive.int)
        assertEquals(1_000.0, l1["distance_m"]!!.jsonPrimitive.double, 0.0001)
        assertEquals(300, l1["duration_s"]!!.jsonPrimitive.int)

        // Lap 2: from 300s → 600s, 1000m → 2050m. Deltas: 300s, 1050m.
        val l2 = arr[1].jsonObject
        assertEquals(300, l2["start_offset_s"]!!.jsonPrimitive.int)
        assertEquals(1_050.0, l2["distance_m"]!!.jsonPrimitive.double, 0.0001)
        assertEquals(300, l2["duration_s"]!!.jsonPrimitive.int)

        // Lap 3: from 600s → 905s, 2050m → 3100m. Deltas: 305s, 1050m.
        val l3 = arr[2].jsonObject
        assertEquals(600, l3["start_offset_s"]!!.jsonPrimitive.int)
        assertEquals(1_050.0, l3["distance_m"]!!.jsonPrimitive.double, 0.0001)
        assertEquals(305, l3["duration_s"]!!.jsonPrimitive.int)
    }

    @Test
    fun `negative-delta inputs are coerced to zero (defensive)`() {
        // Shouldn't happen — the recording service stamps monotonic
        // atMs values and a stricter coerceAtLeast(0.0) in the
        // distance accumulator. But if a clock-jump or a recovery
        // path produced atMs[i+1] < atMs[i], the math would emit a
        // negative duration_s which the upload row would reject.
        // Pin the defensive coerce.
        val laps = listOf(
            QueuedLap(number = 1, atMs = 600_000, distanceM = 1_000.0),
            QueuedLap(number = 2, atMs = 300_000, distanceM = 800.0), // earlier than lap 1
        )
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = laps,
            lastModifiedAtIso = isoStamp,
        )
        val arr = md["laps"]!!.jsonArray
        val l2 = arr[1].jsonObject
        // duration_s and distance_m for lap 2 are both coerced to >=0.
        assertTrue(
            "duration_s must coerce to >= 0 on out-of-order input",
            l2["duration_s"]!!.jsonPrimitive.int >= 0,
        )
        assertTrue(
            "distance_m must coerce to >= 0 on out-of-order input",
            l2["distance_m"]!!.jsonPrimitive.double >= 0.0,
        )
    }

    @Test
    fun `activityType is always written even for non-run`() {
        // The activity-type picker on PreRunScreen can pick walk /
        // hike / cycle. The metadata field is the only signal the
        // server has to drive the icon + the dashboard filter chip.
        // A regression that wrote "run" unconditionally would silently
        // mis-bucket every walk/hike/cycle from the watch.
        for (kind in listOf("run", "walk", "hike", "cycle")) {
            val md = buildRunMetadata(
                activityType = kind,
                avgBpm = null,
                steps = null,
                laps = emptyList(),
                lastModifiedAtIso = isoStamp,
            )
            assertEquals(
                "activity_type must round-trip exactly",
                kind,
                md["activity_type"]!!.jsonPrimitive.content,
            )
        }
    }

    @Test
    fun `last_modified_at is always written`() {
        // Mobile's delta-fetch path filters on
        // `metadata->>'last_modified_at' > since`. Without this stamp
        // the row is invisible to every refresh after the first full
        // pull (per the inline KDoc comment in buildRunMetadata).
        // Even the "minimal" no-bpm no-steps no-laps payload MUST
        // carry it.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertEquals(
            isoStamp,
            md["last_modified_at"]!!.jsonPrimitive.content,
        )
    }

    @Test
    fun `minimum-shape payload has exactly activity_type + last_modified_at`() {
        // Pin the floor: null avgBpm + null steps + empty laps yields
        // a metadata object with exactly two keys. A regression that
        // added a default field (or wrote an explicit null for the
        // omitted ones) would push extra keys into the runs.metadata
        // jsonb and trip the metadata_registry guard test on mobile.
        val md = buildRunMetadata(
            activityType = "run",
            avgBpm = null,
            steps = null,
            laps = emptyList(),
            lastModifiedAtIso = isoStamp,
        )
        assertEquals(setOf("activity_type", "last_modified_at"), md.keys)
        // Spot the keys that must NOT be present.
        assertNull(md["avg_bpm"])
        assertNull(md["steps"])
        assertNull(md["laps"])
    }
}
