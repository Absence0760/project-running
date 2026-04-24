package com.runapp.watchwear.recording

import com.runapp.watchwear.recording.RouteMath.LatLng
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Route-geometry math is the kernel of the off-route alert + the
/// "X to go" badge. These tests mirror the behavioural expectations of
/// the Dart twin in `packages/run_recorder` — any change that breaks
/// symmetry here must land on Android too.
class RouteMathTest {

    // Tolerances: equirectangular projection is accurate to ~1 m over
    // running-route segments, but unit-test tolerances can be tighter
    // because we build fixtures with exact Cartesian geometry in mind.
    private val metreTolerance = 1.0
    private val tTolerance = 1e-3

    // A tiny ~100m E-W segment in central Berlin. Lat/lng chosen so the
    // 111,320 m/° lat approximation and cos(lat)·111,320 m/° lng give
    // clean numbers.
    private val berlinA = LatLng(52.5200, 13.4050)
    private val berlinB = LatLng(52.5200, 13.4065) // ~101 m east of A

    @Test
    fun `offRouteDistance returns null for empty route`() {
        assertNull(RouteMath.offRouteDistanceM(berlinA, emptyList()))
    }

    @Test
    fun `offRouteDistance returns null for single-point route`() {
        assertNull(RouteMath.offRouteDistanceM(berlinA, listOf(berlinA)))
    }

    @Test
    fun `offRouteDistance zero when point lies exactly on segment`() {
        val mid = LatLng(52.5200, (13.4050 + 13.4065) / 2)
        val d = RouteMath.offRouteDistanceM(mid, listOf(berlinA, berlinB))
        assertNotNull(d)
        assertEquals(0.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance perpendicular distance matches expected`() {
        // ~50m north of the segment midpoint.
        val off = LatLng(52.5200 + 50.0 / 111_320.0, (13.4050 + 13.4065) / 2)
        val d = RouteMath.offRouteDistanceM(off, listOf(berlinA, berlinB))
        assertNotNull(d)
        assertEquals(50.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance clamps at endpoints when projection is past segment end`() {
        // ~30m east of point B (past the end of the segment). The closest
        // point on the finite segment is B itself.
        val past = LatLng(52.5200, 13.4065 + 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val d = RouteMath.offRouteDistanceM(past, listOf(berlinA, berlinB))
        assertNotNull(d)
        assertEquals(30.0, d!!, metreTolerance)
    }

    @Test
    fun `offRouteDistance picks minimum across multiple segments`() {
        // Three-segment route: A→B, B→C, C→D.
        val c = LatLng(52.5210, 13.4065) // ~111 m north of B
        val d = LatLng(52.5210, 13.4080) // ~101 m east of C
        val route = listOf(berlinA, berlinB, c, d)

        // Sit 10 m off segment B→C; should be the winning (minimum)
        // distance over all four candidates.
        val near = LatLng(52.5205, 13.4065 + 10.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5205))))
        val off = RouteMath.offRouteDistanceM(near, route)
        assertNotNull(off)
        assertEquals(10.0, off!!, metreTolerance)
    }

    @Test
    fun `routeRemaining returns null for empty route`() {
        assertNull(RouteMath.routeRemainingM(berlinA, emptyList()))
    }

    @Test
    fun `routeRemaining returns null for single-point route`() {
        assertNull(RouteMath.routeRemainingM(berlinA, listOf(berlinA)))
    }

    @Test
    fun `routeRemaining at start of segment equals full segment length`() {
        val r = RouteMath.routeRemainingM(berlinA, listOf(berlinA, berlinB))
        assertNotNull(r)
        val expected = RouteMath.haversineM(
            berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng,
        )
        assertEquals(expected, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining at end of segment is zero`() {
        val r = RouteMath.routeRemainingM(berlinB, listOf(berlinA, berlinB))
        assertNotNull(r)
        assertEquals(0.0, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining at midpoint is half the segment length`() {
        val mid = LatLng(52.5200, (13.4050 + 13.4065) / 2)
        val r = RouteMath.routeRemainingM(mid, listOf(berlinA, berlinB))
        assertNotNull(r)
        val segLen = RouteMath.haversineM(
            berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng,
        )
        assertEquals(segLen / 2, r!!, metreTolerance)
    }

    @Test
    fun `routeRemaining sums across multiple segments past closest projection`() {
        val c = LatLng(52.5210, 13.4065)
        val d = LatLng(52.5210, 13.4080)
        val route = listOf(berlinA, berlinB, c, d)

        // Start from A — expect full route length.
        val total = RouteMath.routeRemainingM(berlinA, route)
        val expected = RouteMath.haversineM(berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng) +
            RouteMath.haversineM(berlinB.lat, berlinB.lng, c.lat, c.lng) +
            RouteMath.haversineM(c.lat, c.lng, d.lat, d.lng)
        assertNotNull(total)
        assertEquals(expected, total!!, metreTolerance * 3)
    }

    @Test
    fun `routeRemaining correctly drops to last-segment length when past midpoint`() {
        val c = LatLng(52.5210, 13.4065)
        val d = LatLng(52.5210, 13.4080)
        val route = listOf(berlinA, berlinB, c, d)

        // Stand exactly on C — the remainder should be exactly C→D.
        val r = RouteMath.routeRemainingM(c, route)
        val expected = RouteMath.haversineM(c.lat, c.lng, d.lat, d.lng)
        assertNotNull(r)
        assertEquals(expected, r!!, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment clamps t at zero when point is before segment start`() {
        // ~30m west of A (before the start).
        val before = LatLng(52.5200, 13.4050 - 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val proj = RouteMath.projectPointOnSegment(
            before.lat, before.lng,
            berlinA.lat, berlinA.lng,
            berlinB.lat, berlinB.lng,
        )
        assertEquals(0.0, proj.t, tTolerance)
        assertEquals(30.0, proj.distance, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment clamps t at one when point is after segment end`() {
        val past = LatLng(52.5200, 13.4065 + 30.0 / (111_320.0 * kotlin.math.cos(Math.toRadians(52.5200))))
        val proj = RouteMath.projectPointOnSegment(
            past.lat, past.lng,
            berlinA.lat, berlinA.lng,
            berlinB.lat, berlinB.lng,
        )
        assertEquals(1.0, proj.t, tTolerance)
        assertEquals(30.0, proj.distance, metreTolerance)
    }

    @Test
    fun `projectPointOnSegment returns raw distance when segment is zero-length`() {
        val proj = RouteMath.projectPointOnSegment(
            52.5201, 13.4051,
            berlinA.lat, berlinA.lng,
            berlinA.lat, berlinA.lng, // zero-length segment
        )
        assertEquals(0.0, proj.t, tTolerance)
        assertTrue(proj.distance > 0.0)
    }

    @Test
    fun `haversineM matches equirectangular within tolerance for short segments`() {
        val h = RouteMath.haversineM(berlinA.lat, berlinA.lng, berlinB.lat, berlinB.lng)
        // ~1.5e-3 degrees at lat 52.52 × ~67,800 m/°lng ≈ 101 m.
        assertEquals(101.7, h, metreTolerance)
    }
}
