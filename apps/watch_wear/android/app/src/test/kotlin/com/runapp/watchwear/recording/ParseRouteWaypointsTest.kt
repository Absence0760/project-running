package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Coverage of `parseRouteWaypointsJson` — parses the route polyline
/// the user picked on the pre-run screen and hands to the recording
/// service via an Intent extra.
///
/// The contract is "fail quiet": any parse error returns an empty
/// list, which disables off-route detection + route-overlay
/// rendering but lets the recording proceed normally. This matters
/// because the intent extra is cross-process input from another
/// part of the app — a malformed payload must NEVER crash the
/// foreground service mid-run.
///
/// Tests cover:
///   - happy paths: minimal, multi-point, with extra fields
///   - fail-quiet paths: null, empty, whitespace, malformed JSON,
///     wrong root type, missing keys, non-numeric values
///   - partial parses: array where SOME elements are bad — the
///     others should still come through
///   - numeric coercion: string-quoted numbers, scientific notation
class ParseRouteWaypointsTest {

    // ─────────────────── happy paths ───────────────────

    @Test fun `single-waypoint array parses cleanly`() {
        val out = parseRouteWaypointsJson("""[{"lat":51.5,"lng":-0.1}]""")
        assertEquals(1, out.size)
        assertEquals(51.5, out[0].lat, 0.0)
        assertEquals(-0.1, out[0].lng, 0.0)
    }

    @Test fun `multi-waypoint array preserves order`() {
        val out = parseRouteWaypointsJson(
            """[{"lat":51.5,"lng":-0.1},{"lat":52.0,"lng":-0.2},{"lat":52.5,"lng":-0.3}]"""
        )
        assertEquals(3, out.size)
        assertEquals(51.5, out[0].lat, 0.0)
        assertEquals(52.0, out[1].lat, 0.0)
        assertEquals(52.5, out[2].lat, 0.0)
    }

    @Test fun `extra fields per waypoint are ignored (forward compat)`() {
        // Future versions of the route picker may add fields (ele,
        // ts, etc.). The watch's parser must tolerate them rather
        // than refusing the whole payload.
        val out = parseRouteWaypointsJson(
            """[{"lat":51.5,"lng":-0.1,"ele":42.0,"ts":1700000000}]"""
        )
        assertEquals(1, out.size)
    }

    // ─────────────────── fail-quiet paths ───────────────────

    @Test fun `null returns empty list`() {
        assertTrue(parseRouteWaypointsJson(null).isEmpty())
    }

    @Test fun `empty string returns empty list`() {
        assertTrue(parseRouteWaypointsJson("").isEmpty())
    }

    @Test fun `whitespace-only string returns empty list`() {
        // Not technically valid JSON; should fail-quiet rather than
        // crash the service.
        assertTrue(parseRouteWaypointsJson("   ").isEmpty())
    }

    @Test fun `malformed JSON returns empty list (not crash)`() {
        // Critical: the intent extra is from another process and
        // must be treated as untrusted. A typo / truncation / bit
        // flip in the payload must NOT propagate as an exception.
        assertTrue(parseRouteWaypointsJson("[{lat:51.5}").isEmpty())
        assertTrue(parseRouteWaypointsJson("not even json").isEmpty())
        assertTrue(parseRouteWaypointsJson("{[").isEmpty())
    }

    @Test fun `non-array root returns empty list`() {
        // An object at the root (vs the expected array) is a wrong-
        // shape input. Empty list, not crash.
        assertTrue(parseRouteWaypointsJson("""{"lat":51.5,"lng":-0.1}""").isEmpty())
        assertTrue(parseRouteWaypointsJson("\"a string\"").isEmpty())
        assertTrue(parseRouteWaypointsJson("42").isEmpty())
    }

    @Test fun `empty array returns empty list (no waypoints)`() {
        assertTrue(parseRouteWaypointsJson("[]").isEmpty())
    }

    // ─────────────────── partial parses ───────────────────

    @Test fun `array element missing lat is skipped, others kept`() {
        // Partial-shape tolerance: one bad element doesn't poison
        // the rest. The runner still gets a (slightly clipped) route
        // overlay rather than no overlay.
        val out = parseRouteWaypointsJson(
            """[{"lat":51.5,"lng":-0.1},{"lng":-0.2},{"lat":52.0,"lng":-0.3}]"""
        )
        assertEquals(2, out.size)
        assertEquals(51.5, out[0].lat, 0.0)
        assertEquals(52.0, out[1].lat, 0.0)
    }

    @Test fun `array element missing lng is skipped, others kept`() {
        val out = parseRouteWaypointsJson(
            """[{"lat":51.5,"lng":-0.1},{"lat":52.0},{"lat":52.5,"lng":-0.3}]"""
        )
        assertEquals(2, out.size)
        assertEquals(51.5, out[0].lat, 0.0)
        assertEquals(52.5, out[1].lat, 0.0)
    }

    @Test fun `non-object element in array is skipped`() {
        // Mixed-type array: stray numbers / strings / nested arrays
        // among the waypoints are skipped.
        val out = parseRouteWaypointsJson(
            """[{"lat":51.5,"lng":-0.1},42,"oops",[1,2],{"lat":52.0,"lng":-0.2}]"""
        )
        assertEquals(2, out.size)
    }

    @Test fun `non-numeric lat is skipped`() {
        // `toDoubleOrNull` returns null on non-numeric strings; the
        // parser short-circuits to skip.
        val out = parseRouteWaypointsJson(
            """[{"lat":"foo","lng":-0.1},{"lat":52.0,"lng":-0.2}]"""
        )
        assertEquals(1, out.size)
        assertEquals(52.0, out[0].lat, 0.0)
    }

    @Test fun `null lat is skipped`() {
        val out = parseRouteWaypointsJson(
            """[{"lat":null,"lng":-0.1},{"lat":52.0,"lng":-0.2}]"""
        )
        assertEquals(1, out.size)
    }

    @Test fun `all-bad elements returns empty list`() {
        val out = parseRouteWaypointsJson(
            """[{"foo":1},{"bar":2},42]"""
        )
        assertTrue(out.isEmpty())
    }

    // ─────────────────── numeric coercion ───────────────────

    @Test fun `string-quoted numbers parse (toDoubleOrNull is lenient)`() {
        // Some upstream encoders quote numbers; toDoubleOrNull
        // handles either. Pin that watch tolerates both forms so
        // the encoder upstream has flexibility.
        val out = parseRouteWaypointsJson(
            """[{"lat":"51.5","lng":"-0.1"}]"""
        )
        assertEquals(1, out.size)
        assertEquals(51.5, out[0].lat, 0.0)
        assertEquals(-0.1, out[0].lng, 0.0)
    }

    @Test fun `scientific notation parses`() {
        val out = parseRouteWaypointsJson("""[{"lat":5.15e1,"lng":-1e-1}]""")
        assertEquals(1, out.size)
        assertEquals(51.5, out[0].lat, 1e-9)
    }

    @Test fun `integer lat or lng parses as Double`() {
        // The schema is "lat / lng as Double" but a route exported
        // as `{"lat":51, "lng":-0}` should still parse.
        val out = parseRouteWaypointsJson("""[{"lat":51,"lng":0}]""")
        assertEquals(1, out.size)
        assertEquals(51.0, out[0].lat, 0.0)
        assertEquals(0.0, out[0].lng, 0.0)
    }

    @Test fun `extremely long array parses without issue (no stack overflow)`() {
        // Pre-run picker theoretically can hand a route with
        // thousands of waypoints. Pin that the parser doesn't
        // explode on a large but valid input.
        val n = 2000
        val arr = (0 until n).joinToString(",") {
            """{"lat":${51.0 + it / 10000.0},"lng":-0.1}"""
        }
        val out = parseRouteWaypointsJson("[$arr]")
        assertEquals(n, out.size)
    }
}
