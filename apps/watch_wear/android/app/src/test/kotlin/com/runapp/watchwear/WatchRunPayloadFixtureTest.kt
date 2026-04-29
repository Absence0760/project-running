package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Cross-platform contract test for the canonical watch-run payload.
///
/// The fixture at `fixtures/watch_run_payload.json` (repo root) is shared
/// with the Flutter test (`apps/mobile_*/test/watch_payload_fixture_test.dart`)
/// and the web test (`apps/web/src/lib/watch_payload_fixture.test.ts`).
/// All three platforms read the same file and must agree on the shape.
/// If you change a field here, update both other tests in the same commit.
///
/// On Wear OS the encoder is what we exercise (the watch posts directly
/// to Supabase; it doesn't decode an inbound payload). The test feeds
/// `buildRunMetadata` cumulative-form inputs that should produce the
/// canonical per-lap deltas in the fixture's `expectedMetadata`.
class WatchRunPayloadFixtureTest {

    private val fixture: JsonObject = run {
        // Gradle runs tests with cwd = the gradle module dir
        // (apps/watch_wear/android/app), so the fixture is 4 levels up.
        val f = File("../../../../fixtures/watch_run_payload.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    @Test
    fun `buildRunMetadata produces expectedMetadata for the canonical fixture`() {
        val expected = fixture["expectedMetadata"]!!.jsonObject
        val expectedLaps = expected["laps"]!!.jsonArray

        // Reconstruct cumulative-form QueuedLap inputs from the fixture's
        // canonical (per-lap-delta) shape. atMs and distanceM accumulate.
        var cumMs = 0L
        var cumDist = 0.0
        val laps = expectedLaps.map { el ->
            val obj = el.jsonObject
            cumMs += obj["duration_s"]!!.jsonPrimitive.int * 1000L
            cumDist += obj["distance_m"]!!.jsonPrimitive.double
            QueuedLap(
                number = obj["index"]!!.jsonPrimitive.int,
                atMs = cumMs,
                distanceM = cumDist,
            )
        }

        val metadata = buildRunMetadata(
            activityType = expected["activity_type"]!!.jsonPrimitive.content,
            avgBpm = expected["avg_bpm"]!!.jsonPrimitive.double,
            steps = null,
            laps = laps,
        )

        assertEquals(
            expected["activity_type"]!!.jsonPrimitive.content,
            metadata["activity_type"]!!.jsonPrimitive.content,
        )
        assertEquals(
            expected["avg_bpm"]!!.jsonPrimitive.double,
            metadata["avg_bpm"]!!.jsonPrimitive.double,
            0.0,
        )

        val producedLaps = metadata["laps"]!!.jsonArray
        assertEquals("lap count", expectedLaps.size, producedLaps.size)
        for (i in expectedLaps.indices) {
            val want = expectedLaps[i].jsonObject
            val got = producedLaps[i].jsonObject
            assertEquals("laps[$i].index", want["index"]!!.jsonPrimitive.int, got["index"]!!.jsonPrimitive.int)
            assertEquals(
                "laps[$i].start_offset_s",
                want["start_offset_s"]!!.jsonPrimitive.int,
                got["start_offset_s"]!!.jsonPrimitive.int,
            )
            assertEquals(
                "laps[$i].distance_m",
                want["distance_m"]!!.jsonPrimitive.double,
                got["distance_m"]!!.jsonPrimitive.double,
                0.0001,
            )
            assertEquals(
                "laps[$i].duration_s",
                want["duration_s"]!!.jsonPrimitive.int,
                got["duration_s"]!!.jsonPrimitive.int,
            )
        }
    }

    @Test
    fun `payload source matches expectedRow source`() {
        val payload = fixture["payload"]!!.jsonObject
        val expected = fixture["expectedRow"]!!.jsonObject
        assertEquals(
            expected["source"]!!.jsonPrimitive.content,
            payload["source"]!!.jsonPrimitive.content,
        )
    }

    @Test
    fun `track points carry per-point bpm`() {
        val payload = fixture["payload"]!!.jsonObject
        val track = payload["track"]!!.jsonArray
        assertEquals(fixture["expectedTrackCount"]!!.jsonPrimitive.int, track.size)
        val firstBpm = track[0].jsonObject["bpm"]!!.jsonPrimitive.int
        assertEquals(fixture["expectedFirstPointBpm"]!!.jsonPrimitive.int, firstBpm)
    }
}
