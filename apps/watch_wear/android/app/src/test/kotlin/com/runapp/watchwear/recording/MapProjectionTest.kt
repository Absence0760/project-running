package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MapProjectionTest {

    private val ll = RouteMath::LatLng
    private val tol = 1e-9

    @Test
    fun `computeBounds returns null on empty inputs`() {
        assertNull(MapProjection.computeBounds(emptyList(), null))
    }

    @Test
    fun `computeBounds picks min and max across route only`() {
        val pts = listOf(ll(51.0, -0.5), ll(52.0, 0.5), ll(51.5, 0.0))
        val b = MapProjection.computeBounds(pts, null)!!
        assertEquals(51.0, b.minLat, tol)
        assertEquals(52.0, b.maxLat, tol)
        assertEquals(-0.5, b.minLng, tol)
        assertEquals(0.5, b.maxLng, tol)
    }

    @Test
    fun `computeBounds expands to include current position outside route`() {
        val pts = listOf(ll(51.0, 0.0), ll(51.1, 0.1))
        val cur = ll(50.5, -0.5)  // SW of every route point
        val b = MapProjection.computeBounds(pts, cur)!!
        assertEquals(50.5, b.minLat, tol)
        assertEquals(51.1, b.maxLat, tol)
        assertEquals(-0.5, b.minLng, tol)
        assertEquals(0.1, b.maxLng, tol)
    }

    @Test
    fun `computeBounds handles current-only input`() {
        val cur = ll(40.0, 10.0)
        val b = MapProjection.computeBounds(emptyList(), cur)!!
        assertEquals(40.0, b.minLat, tol)
        assertEquals(40.0, b.maxLat, tol)
        assertEquals(10.0, b.minLng, tol)
        assertEquals(10.0, b.maxLng, tol)
    }

    @Test
    fun `project centres a single-point bounds at canvas centre`() {
        val cur = ll(40.0, 10.0)
        val b = MapProjection.computeBounds(emptyList(), cur)!!
        val (x, y) = MapProjection.project(cur, b)
        // Both spans are zero → coerced to 1e-9 → projects exactly to centre.
        // Padding shouldn't shift the centre point.
        assertEquals(0.5, x, tol)
        assertEquals(0.5, y, tol)
    }

    @Test
    fun `project respects padding so corners never reach 0 or 1`() {
        val pts = listOf(ll(0.0, 0.0), ll(1.0, 1.0))
        val b = MapProjection.computeBounds(pts, null)!!
        val (x0, y0) = MapProjection.project(ll(0.0, 0.0), b, paddingFrac = 0.1)
        val (x1, y1) = MapProjection.project(ll(1.0, 1.0), b, paddingFrac = 0.1)
        // 10% padding → corners land at 0.10 and 0.90.
        assertEquals(0.10, x0, tol)
        assertEquals(0.90, y0, tol)  // y flipped: low lat → high y
        assertEquals(0.90, x1, tol)
        assertEquals(0.10, y1, tol)
    }

    @Test
    fun `project flips y so larger latitudes render higher on screen`() {
        val pts = listOf(ll(51.0, 0.0), ll(52.0, 0.0))
        val b = MapProjection.computeBounds(pts, null)!!
        val (_, ySouth) = MapProjection.project(ll(51.0, 0.0), b, paddingFrac = 0.0)
        val (_, yNorth) = MapProjection.project(ll(52.0, 0.0), b, paddingFrac = 0.0)
        assertTrue("northern point should have smaller y; got south=$ySouth north=$yNorth", yNorth < ySouth)
    }

    @Test
    fun `project preserves aspect when lng span exceeds lat span`() {
        // 0.1 deg lat × 1.0 deg lng (10x wider than tall). The route
        // should fill the x axis and centre on y.
        val pts = listOf(ll(50.0, 0.0), ll(50.1, 1.0))
        val b = MapProjection.computeBounds(pts, null)!!
        val (xMin, yMin) = MapProjection.project(ll(50.0, 0.0), b, paddingFrac = 0.0)
        val (xMax, yMax) = MapProjection.project(ll(50.1, 1.0), b, paddingFrac = 0.0)
        // x spans full canvas (with the larger span = 1.0 deg lng).
        assertEquals(0.0, xMin, tol)
        assertEquals(1.0, xMax, tol)
        // y centred — both points should be near 0.5, separated only
        // by the lat-span / lng-span ratio = 0.1.
        assertEquals(0.55, yMin, tol)  // south point at lower lat → larger y
        assertEquals(0.45, yMax, tol)
    }

    @Test
    fun `project of midpoint lands at canvas centre`() {
        val pts = listOf(ll(50.0, 0.0), ll(51.0, 1.0))
        val b = MapProjection.computeBounds(pts, null)!!
        val (x, y) = MapProjection.project(ll(50.5, 0.5), b, paddingFrac = 0.1)
        assertEquals(0.5, x, tol)
        assertEquals(0.5, y, tol)
    }

    @Test
    fun `paddingFrac is clamped to 0_49`() {
        val pts = listOf(ll(0.0, 0.0), ll(1.0, 1.0))
        val b = MapProjection.computeBounds(pts, null)!!
        // Padding > 0.49 would invert the canvas; clamp keeps it sane.
        val (x, _) = MapProjection.project(ll(0.0, 0.0), b, paddingFrac = 0.9)
        // With pad=0.49: ax = 0.49 + 0 * (1 - 0.98) = 0.49.
        assertEquals(0.49, x, tol)
    }
}
