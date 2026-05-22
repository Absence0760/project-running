package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Cross-platform contract test for the phone→watch routes payload.
///
/// The fixture at `fixtures/wear_routes_payload.json` (repo root) is
/// shared with the Flutter test
/// (`apps/mobile_android/test/wear_routes_fixture_test.dart`). Both
/// platforms read the same file and must agree on the wire format.
/// If you change a field here, update the Flutter test in the same
/// commit.
///
/// On Wear OS the parser (`parseRoutesJson`) is what we exercise —
/// the watch listens on the Wearable Data Layer at `/saved_routes`
/// and parses inbound `routes_json` payloads via this helper. The
/// fixture's `expected_payload_json` is what the phone's
/// `encodeRoutesForWatch` produces; running it through the parser
/// should yield the `expected_parsed_routes` shape.
class WearRoutesFixtureTest {

    private val fixture: JsonObject = run {
        // Gradle runs tests with cwd = `apps/watch_wear/android/app`,
        // so the fixture is 4 levels up at repo-root `fixtures/`.
        val f = File("../../../../fixtures/wear_routes_payload.json")
        Json.parseToJsonElement(f.readText()).jsonObject
    }

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `parser handles the canonical fixture wire format`() {
        // Serialise the `expected_payload_json` array exactly as
        // the phone would have written it; feed that JSON string
        // through `parseRoutesJson`; assert the parsed SavedRoutes
        // match `expected_parsed_routes`.
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val wireText = wireArr.toString()
        val parsed = parseRoutesJson(json, wireText)
        val expected = fixture["expected_parsed_routes"]!!.jsonArray

        assertEquals("route count mismatch", expected.size, parsed.size)
        for (i in expected.indices) {
            val want = expected[i].jsonObject
            val got = parsed[i]
            assertEquals("row $i id",
                want["id"]!!.jsonPrimitive.contentOrNull, got.id)
            assertEquals("row $i name",
                want["name"]!!.jsonPrimitive.contentOrNull, got.name)
            assertEquals("row $i distanceM",
                want["distanceM"]!!.jsonPrimitive.doubleOrNull!!, got.distanceM, 1e-9)
            assertEquals("row $i waypoint count",
                want["waypointCount"]!!.jsonPrimitive.contentOrNull!!.toInt(),
                got.waypoints.size)
            assertEquals("row $i first waypoint lat",
                want["firstLat"]!!.jsonPrimitive.doubleOrNull!!,
                got.waypoints.first().lat, 1e-9)
            assertEquals("row $i first waypoint lng",
                want["firstLng"]!!.jsonPrimitive.doubleOrNull!!,
                got.waypoints.first().lng, 1e-9)
            assertEquals("row $i last waypoint lat",
                want["lastLat"]!!.jsonPrimitive.doubleOrNull!!,
                got.waypoints.last().lat, 1e-9)
            assertEquals("row $i last waypoint lng",
                want["lastLng"]!!.jsonPrimitive.doubleOrNull!!,
                got.waypoints.last().lng, 1e-9)
        }
    }

    @Test
    fun `parser preserves Unicode + emoji in route name`() {
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val parsed = parseRoutesJson(json, wireArr.toString())
        val trail = parsed.first { it.id == "rt-trail-uuid-002" }
        assertEquals("Trail run with Unicode 🏃", trail.name)
    }

    @Test
    fun `parser handles distance encoded as int (10000) AND as double (5000_5)`() {
        // Dart's jsonEncode emits `10000` as int (no fractional part)
        // and `5000.5` as double. The parser's `doubleOrNull`
        // accepts both — pin that.
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val parsed = parseRoutesJson(json, wireArr.toString())
        val withDecimal = parsed.first { it.id == "9c4dca1e-cf7a-4f12-9f19-e29c70bdf101" }
        val withoutDecimal = parsed.first { it.id == "rt-trail-uuid-002" }
        assertEquals(5000.5, withDecimal.distanceM, 1e-9)
        assertEquals(10000.0, withoutDecimal.distanceM, 1e-9)
    }

    @Test
    fun `parser handles waypoint count variations — 3 + 2 + 2 in the fixture`() {
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val parsed = parseRoutesJson(json, wireArr.toString())
        // Park loop = 3 waypoints, trail = 2, minimal = 2.
        assertEquals(3, parsed[0].waypoints.size)
        assertEquals(2, parsed[1].waypoints.size)
        assertEquals(2, parsed[2].waypoints.size)
    }

    @Test
    fun `every parsed route has at least 2 waypoints (the parser's minimum)`() {
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val parsed = parseRoutesJson(json, wireArr.toString())
        for (r in parsed) {
            assertTrue("route ${r.id} has ${r.waypoints.size} waypoints (need ≥ 2)",
                r.waypoints.size >= 2)
        }
    }

    @Test
    fun `fixture is consumable as both wire payload (Dart side) and parsed routes (Kotlin side)`() {
        // The contract: `expected_payload_json` is what gets put
        // onto the DataLayer; `expected_parsed_routes` is what the
        // Kotlin parser produces from that. The two MUST agree.
        // This top-level test serves as a single tripwire for any
        // drift — if a future edit changes one but not the other,
        // this assertion fires loudly.
        val wireArr = fixture["expected_payload_json"]!!.jsonArray
        val expectedParsed = fixture["expected_parsed_routes"]!!.jsonArray
        assertEquals(wireArr.size, expectedParsed.size)
        // Per-row id alignment — defends against re-ordering of
        // one array without the other.
        for (i in wireArr.indices) {
            val wireId = wireArr[i].jsonObject["id"]!!.jsonPrimitive.contentOrNull
            val parsedId = expectedParsed[i].jsonObject["id"]!!.jsonPrimitive.contentOrNull
            assertEquals("fixture order mismatch at row $i", wireId, parsedId)
        }
    }

    @Test
    fun `fixture file exists at the documented repo-root path`() {
        // Cross-platform tests rely on the fixture living at the
        // canonical path. A relocation would silently skip every
        // fixture-based check on the watch side — pin it.
        val f = File("../../../../fixtures/wear_routes_payload.json")
        assertTrue("fixture file missing at ${f.absolutePath}", f.exists())
        assertNotNull("fixture not valid JSON",
            Json.parseToJsonElement(f.readText()))
    }

    // ---- end-to-end pipeline via the fixture ----------------------------
    //
    // The Dart writer + Kotlin parser are tested independently above.
    // These tests compose them through the canonical fixture so a
    // change to one side that breaks the contract is caught even
    // when both sides still parse their own output.

    @Test
    fun `full pipeline — fixture wire payload → parser → applied state matches expected`() {
        // 1. Take the wire shape the phone-side encoder is contracted
        //    to produce.
        val wireText = fixture["expected_payload_json"]!!.jsonArray.toString()

        // 2. Parse it via the watch's actual parser.
        val parsed = parseRoutesJson(json, wireText)

        // 3. Apply the stale-push gate as the consumer would for a
        //    first push (lastAppliedMs = 0, incoming = arbitrary
        //    positive). This must always apply.
        val ok = shouldApplyRoutesPush(0L, 100L)
        assertTrue("first push must always apply", ok)

        // 4. Apply recents-based sort with a recents list that
        //    includes one of the fixture's ids. The matching id
        //    should float to the front.
        val recents = listOf("rt-trail-uuid-002")
        val sorted = sortRoutesByRecency(parsed, recents)

        // The "trail run" id must lead now.
        assertEquals("trail run must float to the front",
            "rt-trail-uuid-002", sorted.first().id)
        // Length is preserved (sort never adds or drops).
        assertEquals(parsed.size, sorted.size)
        // The fixture's expected_parsed_routes baseline still
        // matches in count.
        assertEquals(
            fixture["expected_parsed_routes"]!!.jsonArray.size,
            sorted.size,
        )
    }

    @Test
    fun `pipeline preserves Unicode end-to-end (writer→wire→parser→sort)`() {
        val wireText = fixture["expected_payload_json"]!!.jsonArray.toString()
        val parsed = parseRoutesJson(json, wireText)
        val sorted = sortRoutesByRecency(parsed, emptyList())
        val trail = sorted.first { it.id == "rt-trail-uuid-002" }
        assertEquals("Trail run with Unicode 🏃", trail.name)
    }

    @Test
    fun `pipeline applies a sequence of two pushes with stale-push gate`() {
        // Simulate the realistic flow:
        //  push A (older) → apply → state = A's set, ts=100
        //  push B (newer) → apply → state = B's set, ts=200
        // Then the fixture's wire JSON is "B". Apply it as push B,
        // then re-apply the same wire JSON as a "stale re-delivery"
        // (older timestamp) and confirm the state stays at B.
        val wireText = fixture["expected_payload_json"]!!.jsonArray.toString()

        // Push A — older.
        val pushAt100 = shouldApplyRoutesPush(0L, 100L)
        assertTrue(pushAt100)
        var lastApplied = 100L

        // Push B (the fixture) — newer.
        val pushAt200 = shouldApplyRoutesPush(lastApplied, 200L)
        assertTrue(pushAt200)
        val parsedB = parseRoutesJson(json, wireText)
        assertEquals(fixture["expected_parsed_routes"]!!.jsonArray.size, parsedB.size)
        lastApplied = 200L

        // Stale re-delivery of A: must NOT apply, state preserved.
        val staleA = shouldApplyRoutesPush(lastApplied, 100L)
        assertTrue("stale push must be rejected", !staleA)
    }

    @Test
    fun `pipeline accepts an empty wire payload as legitimate (unstar-all)`() {
        // The fixture is the populated case; this test inverts it:
        // an empty array IS valid — the user unstarred everything.
        // The pipeline must clear without throwing.
        val emptyWire = "[]"
        val parsed = parseRoutesJson(json, emptyWire)
        assertTrue("empty wire produces empty list", parsed.isEmpty())
        val sorted = sortRoutesByRecency(parsed, listOf("rt-trail-uuid-002"))
        assertTrue("sort of empty stays empty", sorted.isEmpty())
        // Stale-push gate still works on empty content.
        assertTrue("first empty push applies", shouldApplyRoutesPush(0L, 100L))
        assertTrue(
            "subsequent empty push at newer timestamp also applies",
            shouldApplyRoutesPush(100L, 200L),
        )
    }

    @Test
    fun `pipeline tolerates re-delivery of byte-identical wire at newer timestamp`() {
        // The phone-side diff cache catches identical re-sends at
        // the source, but the watch must still tolerate them in
        // case the cache is bypassed (different bridge instances,
        // legacy phone-side build). The gate accepts the newer
        // timestamp; the parser produces the same SavedRoute set.
        val wireText = fixture["expected_payload_json"]!!.jsonArray.toString()
        val first = parseRoutesJson(json, wireText)
        val second = parseRoutesJson(json, wireText)
        assertEquals(first.size, second.size)
        for (i in first.indices) {
            assertEquals(first[i].id, second[i].id)
            assertEquals(first[i].name, second[i].name)
            assertEquals(first[i].distanceM, second[i].distanceM, 1e-9)
            assertEquals(first[i].waypoints.size, second[i].waypoints.size)
        }
    }

    @Test
    fun `pipeline route shape is exactly id+name+distanceM+waypoints — no leaks`() {
        // Pin that the watch's domain model is the narrow set —
        // any wire field the phone might add (user_id, club_id,
        // is_starred, secret) cannot land on the watch's
        // SavedRoute. Defends against an inadvertent phone-side
        // encoder bloat leaking sensitive fields onto the watch.
        val wireText = fixture["expected_payload_json"]!!.jsonArray.toString()
        val parsed = parseRoutesJson(json, wireText)
        val fields = SavedRoute::class.java.declaredFields
            .map { it.name }
            .toSet()
        // Only the four wire fields (plus the synthetic $stable
        // Compose marker on data classes) should be present.
        for (forbidden in listOf("userId", "user_id", "clubId", "isStarred",
            "is_public", "tags", "secret")) {
            assertFalse(
                "SavedRoute must NOT carry $forbidden — would leak from a future phone-side change",
                fields.contains(forbidden),
            )
        }
        // Sanity: every parsed route's id is non-empty (the parser
        // would have dropped any row with a null/missing id).
        for (r in parsed) {
            assertTrue("parser produces non-empty id", r.id.isNotEmpty())
        }
    }
}
