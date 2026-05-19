package com.runapp.watchwear

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for the pure parts of `SavedRoute`.
///
/// `SavedRoute` is the narrow subset of the full `routes` row that the
/// watch carries — id + name + waypoints + distance. The two methods
/// it exposes (`toLatLngs` + `waypointsAsJson`) bridge the watch's
/// stored shape to the inputs the recording service expects.
///
/// `waypointsAsJson()` in particular is a wire-format contract:
/// `RunRecordingService.parseRouteWaypoints` parses the string this
/// emits, and the ACTION_START Intent extras pass it through as a
/// plain String to avoid Parcelable plumbing. A regression in the
/// emitted shape would silently break every recording started with a
/// route picker selection — the off-route banner + remaining-km badge
/// would simply not render.
class SavedRouteTest {

    private val sample = SavedRoute(
        id = "route-abc",
        name = "Centennial Park Loop",
        distanceM = 5234.6,
        waypoints = listOf(
            SavedRoute.Waypoint(lat = -33.8910, lng = 151.2330),
            SavedRoute.Waypoint(lat = -33.8915, lng = 151.2335),
            SavedRoute.Waypoint(lat = -33.8920, lng = 151.2340),
        ),
    )

    // ────────────────────────── toLatLngs ──────────────────────────

    @Test
    fun `toLatLngs maps every waypoint preserving order`() {
        // Reason: the off-route detection + remaining-km math relies
        // on this list's order — points are walked sequentially to
        // measure distance-along-route. A regression that reversed
        // the list (or sorted it) would break the route-progress
        // badge for every out-and-back route.
        val out = sample.toLatLngs()
        assertEquals(3, out.size)
        assertEquals(-33.8910, out[0].lat, 1e-9)
        assertEquals(151.2330, out[0].lng, 1e-9)
        assertEquals(-33.8915, out[1].lat, 1e-9)
        assertEquals(151.2335, out[1].lng, 1e-9)
        assertEquals(-33.8920, out[2].lat, 1e-9)
        assertEquals(151.2340, out[2].lng, 1e-9)
    }

    @Test
    fun `toLatLngs on an empty waypoint list returns empty`() {
        // Defensive: an empty list is a valid SavedRoute even though
        // it can't drive a recording. A regression that threw on
        // empty would crash the picker on any route row whose
        // waypoints had been wiped (e.g. a privacy-zone clip that
        // dropped every point).
        val empty = sample.copy(waypoints = emptyList())
        assertTrue(empty.toLatLngs().isEmpty())
    }

    @Test
    fun `toLatLngs preserves duplicate consecutive points`() {
        // RouteMath consumers handle duplicates themselves (zero-
        // length segments contribute zero remaining distance). Pin
        // that toLatLngs does NOT dedupe — that would be a hidden
        // mutation of the route shape vs what Supabase stored.
        val withDupes = sample.copy(
            waypoints = listOf(
                SavedRoute.Waypoint(lat = -33.89, lng = 151.23),
                SavedRoute.Waypoint(lat = -33.89, lng = 151.23),
                SavedRoute.Waypoint(lat = -33.90, lng = 151.24),
            ),
        )
        assertEquals(3, withDupes.toLatLngs().size)
    }

    // ─────────────────────── waypointsAsJson ───────────────────────

    @Test
    fun `waypointsAsJson emits a JSON array of lat,lng objects`() {
        // Reason: this is the wire format
        // RunRecordingService.parseRouteWaypoints decodes. Pin every
        // load-bearing detail of the emitted shape:
        //   - top-level is an array
        //   - each element has exactly `lat` + `lng`
        //   - values are numbers (not strings)
        //   - no `elevation` / `bpm` / etc. leak through
        val raw = sample.waypointsAsJson()
        val tree = Json.parseToJsonElement(raw)
        val arr = tree.jsonArray
        assertEquals(3, arr.size)
        val first = arr[0].jsonObject
        assertEquals(setOf("lat", "lng"), first.keys)
        assertEquals(-33.891, first["lat"]!!.jsonPrimitive.double, 1e-9)
        assertEquals(151.233, first["lng"]!!.jsonPrimitive.double, 1e-9)
    }

    @Test
    fun `waypointsAsJson empty list emits an empty JSON array literal`() {
        // The ACTION_START code path treats an empty string OR an
        // empty array as "no route selected". Pin that the encoder
        // emits the array form (not "null" / "" / "[\n]") — a
        // regression would surface as the route picker silently
        // failing for runners whose selected route had no waypoints
        // (rare but possible after a privacy clip).
        val empty = sample.copy(waypoints = emptyList())
        assertEquals("[]", empty.waypointsAsJson())
    }

    @Test
    fun `waypointsAsJson serialises Doubles, not Strings`() {
        // Defensive: numbers serialised as strings would round-trip
        // through `parseRouteWaypoints` but the typed reads inside
        // RouteMath would throw. A regression here is the kind of
        // silent contract drift that only surfaces in production
        // after the watch boots a real route.
        val raw = sample.waypointsAsJson()
        // The bare-number form has no quotes around the double.
        // A regression to String-typed lat would render `"-33.891"`
        // instead of `-33.891`.
        assertTrue(
            "lat value must be unquoted number; got: $raw",
            raw.contains("\"lat\":-33.891") ||
                raw.contains("\"lat\": -33.891"),
        )
        assertFalse(
            "lat value must not be quoted as string; got: $raw",
            raw.contains("\"lat\":\"-33.891\""),
        )
    }

    @Test
    fun `waypointsAsJson preserves order of insertion`() {
        // RouteMath walks the list in order; a JSON re-order would
        // silently invert the route direction for out-and-back
        // efforts.
        val raw = sample.waypointsAsJson()
        val arr = Json.parseToJsonElement(raw).jsonArray
        assertEquals(
            sample.waypoints[0].lat,
            arr[0].jsonObject["lat"]!!.jsonPrimitive.double,
            1e-9,
        )
        assertEquals(
            sample.waypoints[2].lat,
            arr[2].jsonObject["lat"]!!.jsonPrimitive.double,
            1e-9,
        )
    }

    // ─────────────────────── data class shape ───────────────────────

    @Test
    fun `data class equality uses all fields`() {
        // SavedRoute is `@Serializable data class`. The synthesised
        // equality matters because `LocalRouteStore` dedupes by
        // equality on cached routes — a regression to identity
        // equality (e.g. a custom equals that only compared `id`)
        // would let a route name / waypoint update silently fail to
        // overwrite the cached row.
        val a = SavedRoute("id", "Name", 1000.0, emptyList())
        val b = SavedRoute("id", "Name", 1000.0, emptyList())
        val c = SavedRoute("id", "Name", 1000.0, listOf(SavedRoute.Waypoint(1.0, 2.0)))
        assertEquals(a, b)
        assertFalse(a == c)
    }

    @Test
    fun `Waypoint equality uses lat AND lng`() {
        // Same equality contract for the inner data class — a
        // regression that compared only lat would let any
        // longitude-only update slip through silently.
        val p1 = SavedRoute.Waypoint(lat = 1.0, lng = 2.0)
        val p2 = SavedRoute.Waypoint(lat = 1.0, lng = 2.0)
        val p3 = SavedRoute.Waypoint(lat = 1.0, lng = 3.0)
        val p4 = SavedRoute.Waypoint(lat = 9.0, lng = 2.0)
        assertEquals(p1, p2)
        assertFalse(p1 == p3)
        assertFalse(p1 == p4)
    }
}
