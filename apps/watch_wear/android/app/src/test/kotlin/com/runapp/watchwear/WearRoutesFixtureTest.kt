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
}
