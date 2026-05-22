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
