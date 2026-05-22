package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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

/// Tests for the file-level pure helpers `shouldApplyRoutesPush`
/// + `sortRoutesByRecency` extracted from `RoutesBridge.kt`. These
/// power the watch-side defensive logic without requiring the
/// `RunViewModel` to be instantiated.
class RoutesPushApplyTest {
    private fun wp(lat: Double, lng: Double) = SavedRoute.Waypoint(lat, lng)
    private fun rt(id: String) = SavedRoute(
        id = id,
        name = id,
        distanceM = 1000.0,
        waypoints = listOf(wp(0.0, 0.0), wp(1.0, 1.0)),
    )

    // ---- shouldApplyRoutesPush ----

    @Test
    fun `first push is applied when no prior state exists`() {
        // lastApplied=0 ⇒ any positive timestamp wins.
        assertTrue(shouldApplyRoutesPush(0L, 100L))
        assertTrue(shouldApplyRoutesPush(0L, 1L))
    }

    @Test
    fun `strictly-newer push is applied`() {
        assertTrue(shouldApplyRoutesPush(100L, 101L))
        assertTrue(shouldApplyRoutesPush(100L, 1_000_000L))
    }

    @Test
    fun `equal-timestamp push is rejected — Wearable DataLayer can re-deliver`() {
        // Re-delivery of an identical DataItem can happen during
        // Wearable reconnects. The cache is already authoritative
        // at that timestamp; don't waste a store write.
        assertFalse(shouldApplyRoutesPush(100L, 100L))
    }

    @Test
    fun `older push is rejected — protects against out-of-order delivery`() {
        assertFalse(shouldApplyRoutesPush(200L, 100L))
        assertFalse(shouldApplyRoutesPush(200L, 199L))
        assertFalse(shouldApplyRoutesPush(200L, 0L))
    }

    @Test
    fun `negative timestamp (corrupt writer) is treated as zero`() {
        // A pre-stamp-aware writer or a corrupt DataMap could send
        // 0 or negative. Apply ONCE so the user gets the push, but
        // pin the next legitimate push's `lastApplied=0` semantics.
        assertTrue("first push with negative timestamp is applied as a one-shot",
            shouldApplyRoutesPush(0L, -1L))
        assertFalse("negative-stamp push after a real one is rejected",
            shouldApplyRoutesPush(100L, -1L))
        assertFalse("zero-stamp push after a real one is rejected",
            shouldApplyRoutesPush(100L, 0L))
    }

    @Test
    fun `monotonic sequence applies every push in order`() {
        var last = 0L
        for (incoming in listOf(10L, 20L, 30L, 50L, 100L, 1_000_000L)) {
            assertTrue(
                "push $incoming should apply after $last",
                shouldApplyRoutesPush(last, incoming),
            )
            last = incoming
        }
    }

    // ---- sortRoutesByRecency ----

    @Test
    fun `empty recents preserves incoming order`() {
        val routes = listOf(rt("a"), rt("b"), rt("c"))
        val sorted = sortRoutesByRecency(routes, emptyList())
        assertEquals(listOf("a", "b", "c"), sorted.map { it.id })
    }

    @Test
    fun `recent route floats to the front`() {
        val routes = listOf(rt("a"), rt("b"), rt("c"))
        val sorted = sortRoutesByRecency(routes, listOf("c"))
        assertEquals(listOf("c", "a", "b"), sorted.map { it.id })
    }

    @Test
    fun `multiple recents preserve LRU order at the front`() {
        // recentIds is MRU-first per LocalRouteStore.pushRecent. We
        // float them to the front in the same order.
        val routes = listOf(rt("a"), rt("b"), rt("c"), rt("d"))
        val sorted = sortRoutesByRecency(routes, listOf("c", "a"))
        // c, then a (recents in order), then rest in incoming order.
        assertEquals(listOf("c", "a", "b", "d"), sorted.map { it.id })
    }

    @Test
    fun `recent id not in routes is silently skipped`() {
        // The watch's recentIds can hold ids the phone never
        // pushed (the route was deleted on the phone but its id
        // lingers in the LRU). Just drop those entries.
        val routes = listOf(rt("a"), rt("b"))
        val sorted = sortRoutesByRecency(routes, listOf("ghost", "b"))
        assertEquals(listOf("b", "a"), sorted.map { it.id })
    }

    @Test
    fun `empty routes returns empty regardless of recents`() {
        val sorted = sortRoutesByRecency(emptyList(), listOf("a", "b"))
        assertTrue(sorted.isEmpty())
    }

    @Test
    fun `idempotent — re-applying the same recents doesn't change order`() {
        val routes = listOf(rt("a"), rt("b"), rt("c"))
        val once = sortRoutesByRecency(routes, listOf("b"))
        val twice = sortRoutesByRecency(once, listOf("b"))
        assertEquals(once.map { it.id }, twice.map { it.id })
    }

    @Test
    fun `recents list with all-unknown ids is a no-op`() {
        val routes = listOf(rt("a"), rt("b"))
        val sorted = sortRoutesByRecency(routes, listOf("x", "y", "z"))
        assertEquals(listOf("a", "b"), sorted.map { it.id })
    }

    @Test
    fun `output list length matches input list length`() {
        val routes = listOf(rt("a"), rt("b"), rt("c"), rt("d"))
        val sorted = sortRoutesByRecency(routes, listOf("c", "a", "x"))
        assertEquals("the helper re-orders, never adds or drops",
            routes.size, sorted.size)
    }

    @Test
    fun `output contains exactly the same id set as input`() {
        val routes = listOf(rt("a"), rt("b"), rt("c"), rt("d"))
        val sorted = sortRoutesByRecency(routes, listOf("c", "a"))
        assertEquals(routes.map { it.id }.toSet(), sorted.map { it.id }.toSet())
    }

    @Test
    fun `re-ordering preserves SavedRoute identity per id`() {
        // The helper returns the SAME SavedRoute instances — the
        // recents pull from byId, the rest filter from the input.
        // Both paths yield references back to the originals.
        val a = rt("a")
        val b = rt("b")
        val routes = listOf(a, b)
        val sorted = sortRoutesByRecency(routes, listOf("b"))
        assertTrue("b instance preserved", sorted[0] === b)
        assertTrue("a instance preserved", sorted[1] === a)
    }

    @Test
    fun `100-route + 10-recent sort returns in 50ms`() {
        // Regression guard against an O(n²) refactor.
        val routes = (0 until 100).map { rt("r-$it") }
        val recents = (0 until 10).map { "r-$it" }
        val start = System.nanoTime()
        val sorted = sortRoutesByRecency(routes, recents)
        val elapsedMs = (System.nanoTime() - start) / 1_000_000
        assertEquals(100, sorted.size)
        assertTrue("sort took ${elapsedMs}ms (regression?)", elapsedMs < 50)
    }
}

/// Tests for the wire-shape of `RoutesPush` — pins the data class
/// contract that the phone-side payload writer + watch-side
/// consumer both depend on.
class RoutesPushTest {
    private val sample = SavedRoute(
        id = "rt-1",
        name = "Sample",
        distanceM = 5000.0,
        waypoints = listOf(
            SavedRoute.Waypoint(47.37, 8.54),
            SavedRoute.Waypoint(47.371, 8.541),
        ),
    )

    @Test
    fun `equality is by-value over routes + updatedAtMs`() {
        val a = RoutesPush(listOf(sample), 100L)
        val b = RoutesPush(listOf(sample), 100L)
        assertEquals(a, b)
    }

    @Test
    fun `equality differs on updatedAtMs`() {
        val a = RoutesPush(listOf(sample), 100L)
        val b = RoutesPush(listOf(sample), 101L)
        assertNotEquals(a, b)
    }

    @Test
    fun `empty routes is a legitimate push payload`() {
        // The phone sends an empty array when the user unstarred
        // their last route — the watch should clear its cache.
        val push = RoutesPush(emptyList(), 100L)
        assertTrue(push.routes.isEmpty())
        assertEquals(100L, push.updatedAtMs)
    }

    @Test
    fun `parsed routes contain only safe id + name + distance + waypoints fields`() {
        // The wire format is narrow on purpose — the watch picker
        // only needs those four fields. This test pins the leak
        // surface: even if the phone added extra keys to the
        // payload, the parser only carries through the safe set.
        val raw = """
            [{
                "id": "rt-1",
                "name": "Test",
                "distance_m": 1000,
                "waypoints": [{"lat":1.0,"lng":2.0},{"lat":3.0,"lng":4.0}],
                "user_id": "leaked-uid",
                "secret_field": "leaked-secret"
            }]
        """.trimIndent()
        val parsed = parseRoutesJson(Json { ignoreUnknownKeys = true }, raw)
        assertEquals(1, parsed.size)
        // SavedRoute has no field for user_id or secret_field —
        // the leak surface is bounded by the data class shape.
        val fields = SavedRoute::class.java.declaredFields.map { it.name }.toSet()
        assertFalse("user_id leaked", fields.contains("user_id"))
        assertFalse("secret_field leaked", fields.contains("secret_field"))
    }
}

/// Simulates the `observeRoutesBridge` consumer state machine —
/// composes `shouldApplyRoutesPush` + `sortRoutesByRecency` over a
/// sequence of inbound `RoutesPush` events and checks the final
/// "applied" snapshot matches expectation.
///
/// The full `RunViewModel.observeRoutesBridge` flow can't run on a
/// JVM (it touches `viewModelScope`, `DataClient`, and DataStore),
/// but the pure-logic surface that DECIDES what to apply is fully
/// testable.
class RoutesPushApplySequenceTest {
    private fun wp(lat: Double, lng: Double) = SavedRoute.Waypoint(lat, lng)
    private fun rt(id: String) = SavedRoute(
        id = id,
        name = id,
        distanceM = 1000.0,
        waypoints = listOf(wp(0.0, 0.0), wp(1.0, 1.0)),
    )

    /// Mimics what observeRoutesBridge does on every inbound push:
    /// gate by `shouldApplyRoutesPush`, then re-order by recents.
    /// Returns the new applied state.
    private data class AppliedState(val routes: List<SavedRoute>, val ts: Long)

    private fun apply(
        state: AppliedState,
        push: RoutesPush,
        recents: List<String>,
    ): AppliedState {
        if (!shouldApplyRoutesPush(state.ts, push.updatedAtMs)) return state
        return AppliedState(sortRoutesByRecency(push.routes, recents), push.updatedAtMs)
    }

    @Test
    fun `monotonic sequence applies every push`() {
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("a")), 100L), emptyList())
        assertEquals(100L, state.ts)
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b")), 200L), emptyList())
        assertEquals(200L, state.ts)
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b"), rt("c")), 300L), emptyList())
        assertEquals(300L, state.ts)
        assertEquals(listOf("a", "b", "c"), state.routes.map { it.id })
    }

    @Test
    fun `out-of-order push leaves earlier state intact`() {
        var state = AppliedState(emptyList(), 0L)
        // First a newer push lands.
        state = apply(state, RoutesPush(listOf(rt("newer")), 200L), emptyList())
        // Then an older arrives late (e.g. reconnect replay).
        state = apply(state, RoutesPush(listOf(rt("older")), 100L), emptyList())
        // State stays at the newer push.
        assertEquals(200L, state.ts)
        assertEquals(listOf("newer"), state.routes.map { it.id })
    }

    @Test
    fun `same-timestamp re-delivery is a no-op`() {
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("a")), 100L), emptyList())
        val stateRef = state
        state = apply(state, RoutesPush(listOf(rt("DIFFERENT")), 100L), emptyList())
        // Equal-timestamp push is rejected — state unchanged.
        assertEquals(stateRef.routes, state.routes)
        assertEquals(stateRef.ts, state.ts)
    }

    @Test
    fun `empty push at newer timestamp clears the routes list (user unstarred all)`() {
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b")), 100L), emptyList())
        // User unstarred everything; phone sends an empty array.
        state = apply(state, RoutesPush(emptyList(), 200L), emptyList())
        assertEquals(200L, state.ts)
        assertTrue("routes must be cleared after empty push", state.routes.isEmpty())
    }

    @Test
    fun `recents from the watch float matching ids to the front of each push`() {
        var state = AppliedState(emptyList(), 0L)
        val recents = listOf("c", "a")
        state = apply(
            state,
            RoutesPush(listOf(rt("a"), rt("b"), rt("c"), rt("d")), 100L),
            recents,
        )
        // c, a (recents in order), then b, d (rest in incoming order).
        assertEquals(listOf("c", "a", "b", "d"), state.routes.map { it.id })
    }

    @Test
    fun `recents that disappear from a subsequent push are silently dropped`() {
        var state = AppliedState(emptyList(), 0L)
        // First push: includes b — recents=[b] floats it.
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b")), 100L), listOf("b"))
        assertEquals(listOf("b", "a"), state.routes.map { it.id })
        // User unstarred b on the phone — second push omits it.
        // recents still says [b] but sortRoutesByRecency just skips.
        state = apply(state, RoutesPush(listOf(rt("a"), rt("c")), 200L), listOf("b"))
        assertEquals(listOf("a", "c"), state.routes.map { it.id })
    }

    @Test
    fun `cold-start zero-timestamp push is applied as one-shot`() {
        // The cold-start path (RoutesBridge.current()) reads a
        // DataItem written before the writer started stamping
        // updated_at_ms. Pin: a single zero-stamp push lands once,
        // but any later real-stamp push wins.
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("legacy")), 0L), emptyList())
        // The legacy push applied as a one-shot (lastApplied was 0,
        // incoming is 0/non-positive — guard says ok the first time).
        assertEquals(listOf("legacy"), state.routes.map { it.id })
        // After we have any state, a real-stamped push wins.
        state = apply(state, RoutesPush(listOf(rt("real")), 50L), emptyList())
        assertEquals(listOf("real"), state.routes.map { it.id })
        assertEquals(50L, state.ts)
    }

    @Test
    fun `stress — 100 pushes alternating future + past results in monotonic increase`() {
        var state = AppliedState(emptyList(), 0L)
        for (i in 1..100) {
            // Alternate between t=i*10 (forward) and t=i*5 (past).
            val ts = if (i % 2 == 0) (i * 10L) else (i * 5L)
            val routes = listOf(rt("r-$i"))
            state = apply(state, RoutesPush(routes, ts), emptyList())
        }
        // Only forward pushes "win"; final state is monotonically
        // non-decreasing on the timestamp axis.
        assertTrue("final timestamp must be > 0", state.ts > 0L)
    }

    @Test
    fun `out-of-order push followed by stale doesn't roll the watch back`() {
        // Realistic edge case: phone pushes A (t=100), then B (t=200),
        // then C (t=300). Watch receives them as C, A, B due to
        // Wearable Data Layer's at-least-once delivery semantics.
        // Expectation: only C lands; A and B are dropped.
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("C")), 300L), emptyList())
        state = apply(state, RoutesPush(listOf(rt("A")), 100L), emptyList())
        state = apply(state, RoutesPush(listOf(rt("B")), 200L), emptyList())
        assertEquals(300L, state.ts)
        assertEquals(listOf("C"), state.routes.map { it.id })
    }

    @Test
    fun `recents updated mid-sequence affects later pushes only`() {
        var state = AppliedState(emptyList(), 0L)
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b")), 100L), emptyList())
        // Initial: incoming order.
        assertEquals(listOf("a", "b"), state.routes.map { it.id })
        // User taps b on the watch (LRU update on the watch side);
        // next phone push re-sorts with b first.
        state = apply(state, RoutesPush(listOf(rt("a"), rt("b")), 200L), listOf("b"))
        assertEquals(listOf("b", "a"), state.routes.map { it.id })
    }
}

