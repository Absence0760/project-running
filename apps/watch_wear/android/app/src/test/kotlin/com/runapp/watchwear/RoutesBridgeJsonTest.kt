package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.Json

/// Pure-JVM coverage for the JSON contract between the phone's
/// `WearRoutesBridge` (Dart) push and the watch's `RoutesBridge`
/// listener. The Wearable DataLayer plumbing itself can't be tested
/// without instrumentation, so the parser is pulled out as a
/// file-level helper and exercised here.
class RoutesBridgeJsonTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `empty array yields empty list`() {
        val out = parseRoutesJson(json, "[]")
        assertTrue(out.isEmpty())
    }

    @Test
    fun `malformed JSON yields empty list rather than crashing`() {
        assertTrue(parseRoutesJson(json, "{not json").isEmpty())
        assertTrue(parseRoutesJson(json, "").isEmpty())
        assertTrue(parseRoutesJson(json, "null").isEmpty())
    }

    @Test
    fun `parses a single route with two waypoints`() {
        val raw = """
            [{
                "id": "r-1",
                "name": "Park loop",
                "distance_m": 5000.0,
                "waypoints": [
                    {"lat": 47.37, "lng": 8.54},
                    {"lat": 47.371, "lng": 8.541}
                ]
            }]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        val r = out.single()
        assertEquals("r-1", r.id)
        assertEquals("Park loop", r.name)
        assertEquals(5000.0, r.distanceM, 1e-9)
        assertEquals(2, r.waypoints.size)
        assertEquals(47.37, r.waypoints.first().lat, 1e-9)
        assertEquals(8.541, r.waypoints.last().lng, 1e-9)
    }

    @Test
    fun `drops routes with fewer than 2 waypoints`() {
        val raw = """
            [
                {"id": "good", "name": "OK", "distance_m": 100,
                 "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]},
                {"id": "single", "name": "Single", "distance_m": 100,
                 "waypoints": [{"lat":1.0,"lng":2.0}]},
                {"id": "empty", "name": "Empty", "distance_m": 100,
                 "waypoints": []}
            ]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        assertEquals("good", out.single().id)
    }

    @Test
    fun `drops routes missing id or waypoints array`() {
        val raw = """
            [
                {"name": "No id", "distance_m": 100,
                 "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]},
                {"id": "no-wps", "name": "No waypoints", "distance_m": 100},
                {"id": "keeper", "name": "Keep", "distance_m": 100,
                 "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]}
            ]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        assertEquals("keeper", out.single().id)
    }

    @Test
    fun `falls back to default name when missing`() {
        val raw = """
            [{"id":"r","distance_m":100,
              "waypoints":[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals("Unnamed route", out.single().name)
    }

    @Test
    fun `falls back to zero distance when missing`() {
        val raw = """
            [{"id":"r","name":"N",
              "waypoints":[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(0.0, out.single().distanceM, 1e-9)
    }

    @Test
    fun `drops individual waypoints missing lat or lng`() {
        val raw = """
            [{"id":"r","name":"N","distance_m":100,
              "waypoints":[
                {"lat":1.0,"lng":2.0},
                {"lat":3.0},
                {"lng":4.0},
                {"lat":5.0,"lng":6.0}
              ]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        // The two malformed waypoints are dropped, leaving 2 valid ones.
        assertEquals(2, out.single().waypoints.size)
        assertEquals(1.0, out.single().waypoints.first().lat, 1e-9)
        assertEquals(6.0, out.single().waypoints.last().lng, 1e-9)
    }

    @Test
    fun `tolerates extra top-level fields the writer might add later`() {
        // Forward-compat: a phone running a newer build than the
        // watch must not break the watch's parser by adding fields
        // (e.g. is_starred, club_id) the watch doesn't understand.
        val raw = """
            [{
                "id": "r-1",
                "name": "Future route",
                "distance_m": 5000,
                "is_starred": true,
                "club_id": "club-uuid",
                "novel_future_field": {"nested": "value"},
                "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]
            }]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        assertEquals("r-1", out.single().id)
        assertEquals("Future route", out.single().name)
    }

    @Test
    fun `Unicode in route name + ID round-trips intact`() {
        // A user with a non-ASCII route name (CJK, emoji, accented)
        // must not lose characters through the DataLayer push +
        // local JSON parse on the watch.
        val raw = """
            [{
                "id": "r-早朝",
                "name": "早朝ラン 🏃‍♂️ Müller",
                "distance_m": 5000,
                "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]
            }]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        assertEquals("r-早朝", out.single().id)
        assertEquals("早朝ラン 🏃‍♂️ Müller", out.single().name)
    }

    @Test
    fun `parses 500-route payload in under 500ms`() {
        // Regression guard: phone-side push of a power user's
        // starred set must not lock the watch's main thread on
        // parse. 500 routes × 4 waypoints ≈ 80 KB JSON — well under
        // Wearable Data Layer's per-item cap (~100 KB) but a
        // realistic worst-case for a few-thousand-route phone.
        val sb = StringBuilder("[")
        for (i in 0 until 500) {
            if (i > 0) sb.append(",")
            sb.append(
                """{"id":"r-$i","name":"Route $i","distance_m":${5000.0 + i},
                "waypoints":[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0},
                {"lat":5.0,"lng":6.0},{"lat":7.0,"lng":8.0}]}""".trimIndent(),
            )
        }
        sb.append("]")
        val start = System.nanoTime()
        val out = parseRoutesJson(json, sb.toString())
        val elapsedMs = (System.nanoTime() - start) / 1_000_000
        assertEquals(500, out.size)
        assertTrue(
            "500-route parse took ${elapsedMs}ms (regression?)",
            elapsedMs < 500,
        )
    }

    @Test
    fun `preserves duplicate ids in input — caller deduplicates`() {
        // The DataLayer payload is the canonical contract — if the
        // phone somehow pushes duplicate ids, the parser passes
        // them through and the consumer (LocalRouteStore.save +
        // RunViewModel.sortByRecency) decides on dedup policy.
        val raw = """
            [
                {"id":"dup","name":"First","distance_m":100,
                 "waypoints":[{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}]},
                {"id":"dup","name":"Second","distance_m":200,
                 "waypoints":[{"lat":5.0,"lng":6.0},{"lat":7.0,"lng":8.0}]}
            ]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(2, out.size)
        assertEquals("First", out.first().name)
        assertEquals("Second", out.last().name)
    }

    @Test
    fun `string-coerced numeric values are accepted as a forgiving wire contract`() {
        // kotlinx.serialization's `doubleOrNull` parses string-typed
        // primitives that hold a valid number — `"1.0"` is treated
        // identically to `1.0`. This is fine because the typical
        // mis-encode is "JS-style stringify wrapping numbers in
        // quotes", not "garbage in a string-typed field". Pin the
        // contract so a future refactor doesn't tighten this
        // accidentally and break a real-world phone push.
        val raw = """
            [{"id":"r-1","name":"Stringy","distance_m":100,
              "waypoints":[
                {"lat":"1.0","lng":"2.0"},
                {"lat":3.0,"lng":"4.0"}
              ]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        val wps = out.single().waypoints
        assertEquals(2, wps.size)
        assertEquals(1.0, wps[0].lat, 1e-9)
        assertEquals(2.0, wps[0].lng, 1e-9)
        assertEquals(3.0, wps[1].lat, 1e-9)
        assertEquals(4.0, wps[1].lng, 1e-9)
    }

    @Test
    fun `truly garbage values in lat or lng drop the waypoint`() {
        // A waypoint where the lat/lng can't be coerced to a
        // double at all — drop it. The route falls below the
        // 2-waypoint minimum and the whole route is rejected.
        val raw = """
            [{"id":"r-1","name":"Junk","distance_m":100,
              "waypoints":[
                {"lat":"not-a-number","lng":"also-bad"},
                {"lat":3.0,"lng":"definitely-not-a-double"}
              ]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertTrue(
            "garbage waypoints should fall under the 2-wp minimum",
            out.isEmpty(),
        )
    }

    @Test
    fun `negative + extreme coordinates pass through`() {
        // Antimeridian / south-pole / out-of-range coordinates are
        // the consumer's problem (RouteMath / map rendering). The
        // parser doesn't pre-validate semantics.
        val raw = """
            [{"id":"r-1","name":"Edge","distance_m":100,
              "waypoints":[
                {"lat":-90.0,"lng":-180.0},
                {"lat":90.0,"lng":180.0},
                {"lat":1e10,"lng":-1e10}
              ]}]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(1, out.size)
        val wps = out.single().waypoints
        assertEquals(3, wps.size)
        assertEquals(-90.0, wps[0].lat, 1e-9)
        assertEquals(1e10, wps[2].lat, 1e-9)
    }

    @Test
    fun `top-level non-array yields empty list, not a crash`() {
        // The DataLayer wire format is always a JSON array. A
        // single object (corrupt push) should be handled like any
        // other malformed payload.
        assertTrue(parseRoutesJson(json, "{}").isEmpty())
        assertTrue(parseRoutesJson(json, "42").isEmpty())
        assertTrue(parseRoutesJson(json, "\"a string\"").isEmpty())
    }

    @Test
    fun `parses multiple routes preserving order`() {
        val raw = """
            [
                {"id":"a","name":"A","distance_m":1,
                 "waypoints":[{"lat":0.0,"lng":0.0},{"lat":1.0,"lng":1.0}]},
                {"id":"b","name":"B","distance_m":2,
                 "waypoints":[{"lat":2.0,"lng":2.0},{"lat":3.0,"lng":3.0}]},
                {"id":"c","name":"C","distance_m":3,
                 "waypoints":[{"lat":4.0,"lng":4.0},{"lat":5.0,"lng":5.0}]}
            ]
        """.trimIndent()
        val out = parseRoutesJson(json, raw)
        assertEquals(listOf("a", "b", "c"), out.map { it.id })
    }
}
