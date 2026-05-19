package com.runapp.watchwear.recording

import com.runapp.watchwear.GpsPoint
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files

/// Unit tests for `TrackWriter` — the append-only streamer that backs
/// the recording loop's track file. The output IS a wire-format
/// contract: readers (Dart api_client + anything decoding the Storage
/// track blob) parse the exact JSON the writer produces.
///
/// A regression here would surface as runs uploading with corrupt
/// tracks — the row would land in Supabase but the GPS trace on
/// `/runs/[id]` would render empty or fail to parse. Hard to catch
/// in production until users notice their tracks are missing.
class TrackWriterTest {

    private lateinit var tempDir: File
    private lateinit var trackFile: File

    @Before
    fun setUp() {
        tempDir = Files.createTempDirectory("track-writer-test").toFile()
        trackFile = File(tempDir, "tracks/run-abc.json")
    }

    @After
    fun tearDown() {
        tempDir.deleteRecursively()
    }

    @Test
    fun `open then close with no points yields an empty JSON array`() {
        // The empty case must STILL be a valid JSON array — readers
        // downstream parse JSON unconditionally and a malformed
        // `null` / `""` / `[` file would crash the run-detail render
        // even for runs that legitimately had no GPS fix (indoor /
        // treadmill recordings).
        val w = TrackWriter(trackFile)
        w.open()
        val out = w.close()
        assertEquals("[]", out.readText())
    }

    @Test
    fun `single appended point produces a one-element array`() {
        val w = TrackWriter(trackFile)
        w.open()
        w.append(GpsPoint(lat = 51.5, lng = -0.1, ele = 25.3, epochMs = 1_716_000_000_000))
        val out = w.close()
        val arr = Json.parseToJsonElement(out.readText()).jsonArray
        assertEquals(1, arr.size)
        val p = arr[0].jsonObject
        assertEquals(51.5, p["lat"]!!.jsonPrimitive.content.toDouble(), 1e-9)
        assertEquals(-0.1, p["lng"]!!.jsonPrimitive.content.toDouble(), 1e-9)
        assertEquals(25.3, p["ele"]!!.jsonPrimitive.content.toDouble(), 1e-9)
        assertNotNull(p["ts"])
    }

    @Test
    fun `multiple points are comma-separated, no trailing comma`() {
        // A trailing comma before `]` would produce invalid JSON
        // (most readers reject `,]`). Pin the separator behaviour
        // because the writer uses a `count > 0` guard, which is
        // the kind of off-by-one that's easy to get wrong in a
        // refactor.
        val w = TrackWriter(trackFile)
        w.open()
        for (i in 0 until 5) {
            w.append(GpsPoint(lat = 51.0 + i * 0.01, lng = -0.1, ele = null, epochMs = 1_716_000_000_000L + i * 1000L))
        }
        val out = w.close().readText()
        // Valid JSON (no trailing comma).
        val arr = Json.parseToJsonElement(out).jsonArray
        assertEquals(5, arr.size)
        // Sanity-check the raw text — no `,]` substring.
        assertFalse("output must not contain trailing comma: $out", out.contains(",]"))
    }

    @Test
    fun `null elevation serialises as JSON null literal, not quoted string`() {
        // Defensive: if the writer accidentally emitted `"ele":"null"`
        // (a quoted string), every reader's typed parse would either
        // throw or interpret it as the string "null" instead of a
        // missing elevation. The recording stack writes `ele = null`
        // for samples that lack altitude (urban-canyon GPS / indoor
        // mode), so this path is hit every run.
        val w = TrackWriter(trackFile)
        w.open()
        w.append(GpsPoint(lat = 51.5, lng = -0.1, ele = null, epochMs = 1_716_000_000_000))
        val out = w.close().readText()
        // Direct substring check — the JSON parser would silently
        // accept either form, so assert on the raw output.
        assertTrue(
            "expected ele:null literal; got: $out",
            out.contains("\"ele\":null"),
        )
        assertFalse(
            "ele must not be quoted as string; got: $out",
            out.contains("\"ele\":\"null\""),
        )
        // And the parsed value must be the JsonNull singleton, not a
        // JsonPrimitive holding the string "null".
        val arr = Json.parseToJsonElement(out).jsonArray
        val ele = arr[0].jsonObject["ele"]
        assertEquals(JsonNull, ele)
    }

    @Test
    fun `timestamp renders as ISO 8601 UTC`() {
        // The reader (Dart `Waypoint.timestamp = DateTime.tryParse`)
        // requires ISO 8601 with the trailing Z. epochMs converts to
        // `Instant` which formats with `.toString()` → ISO. Pin so a
        // refactor to e.g. `java.util.Date` (which formats as a
        // locale-dependent string) wouldn't silently break parsing
        // for every saved run.
        val w = TrackWriter(trackFile)
        w.open()
        // 2024-05-19T08:00:00Z = epoch 1716105600000
        w.append(GpsPoint(lat = 0.0, lng = 0.0, ele = null, epochMs = 1_716_105_600_000))
        val out = w.close().readText()
        val ts = Json.parseToJsonElement(out).jsonArray[0].jsonObject["ts"]!!.jsonPrimitive.content
        assertEquals("2024-05-19T08:00:00Z", ts)
    }

    @Test
    fun `pointCount tracks each append`() {
        // `RunRecordingService` reads `pointCount` for the live
        // notification ("12 km · 5800 points"). An off-by-one in
        // count increment would surface as the notification lagging
        // by one point all run.
        val w = TrackWriter(trackFile)
        w.open()
        assertEquals(0, w.pointCount)
        w.append(GpsPoint(lat = 0.0, lng = 0.0, ele = null, epochMs = 0))
        assertEquals(1, w.pointCount)
        w.append(GpsPoint(lat = 0.0, lng = 0.0, ele = null, epochMs = 1000))
        assertEquals(2, w.pointCount)
        w.close()
    }

    @Test
    fun `re-opening an existing file resets pointCount and starts fresh`() {
        // The recording service might re-`open()` on a recovery flow.
        // The file delete + count = 0 reset is critical — a stale
        // file's bytes + a non-reset count would produce a
        // double-bracketed `[[…]]` array.
        val w = TrackWriter(trackFile)
        w.open()
        w.append(GpsPoint(lat = 0.0, lng = 0.0, ele = null, epochMs = 0))
        assertEquals(1, w.pointCount)
        w.close()

        // Second open — same file path, fresh start.
        w.open()
        assertEquals(0, w.pointCount)
        w.append(GpsPoint(lat = 9.0, lng = 9.0, ele = null, epochMs = 9999))
        val out = w.close().readText()
        // The re-opened file holds ONLY the second point. The first
        // (lat=0) must NOT appear.
        assertFalse(
            "re-opened file must not retain first-pass bytes: $out",
            out.contains("\"lat\":0.0,\"lng\":0.0"),
        )
        assertTrue(out.contains("\"lat\":9.0"))
    }

    @Test
    fun `close is idempotent`() {
        // The shutdown path may call close() more than once (the
        // try-finally in RunRecordingService.stopRecording). Pin
        // that the second call doesn't corrupt the file. The first
        // close writes `]`; a non-idempotent second close that
        // wrote another `]` would produce `]]` and break readers.
        val w = TrackWriter(trackFile)
        w.open()
        w.append(GpsPoint(lat = 1.0, lng = 1.0, ele = null, epochMs = 0))
        val first = w.close().readText()
        val second = w.close().readText() // <-- the test
        assertEquals(first, second)
        // And still valid JSON.
        val arr = Json.parseToJsonElement(second).jsonArray
        assertEquals(1, arr.size)
    }

    @Test
    fun `path exposes the absolute file path`() {
        // RunRecordingService reads `path` to stamp the checkpoint's
        // `trackFilePath` so a crash-recovery can find the file.
        // Absolute (not relative) is load-bearing — relative paths
        // would be resolved against whatever cwd the service had at
        // restart time, which is undefined for an Android process.
        val w = TrackWriter(trackFile)
        assertEquals(trackFile.absolutePath, w.path)
        assertTrue(w.path.startsWith("/"))
    }
}
