package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/// Covers the M4 bound on `LocalRouteStore.save`: the Preferences
/// DataStore rewrites its whole backing file on every committed save, so
/// the persisted route list is capped at `MAX_ROUTES` (= the server-side
/// `limit=30` the watch fetch uses) before encoding. The dedup half (skip
/// the rewrite when the encoded list is unchanged) is bound to the
/// DataStore `Context` and isn't host-JVM-testable; the cap is the pure,
/// load-bearing decision.
class BoundRoutesTest {

    private fun route(i: Int) = SavedRoute(
        id = "route-$i",
        name = "Route $i",
        distanceM = 1000.0 * i,
        waypoints = listOf(SavedRoute.Waypoint(1.0 * i, 2.0 * i)),
    )

    @Test
    fun `MAX_ROUTES matches the server-side fetch limit`() {
        assertEquals(30, LocalRouteStore.MAX_ROUTES)
    }

    @Test
    fun `a list at the cap is returned untouched`() {
        val list = (1..LocalRouteStore.MAX_ROUTES).map { route(it) }
        val bounded = boundRoutes(list)
        assertEquals(LocalRouteStore.MAX_ROUTES, bounded.size)
        // Identity-preserved when no truncation is needed (no copy).
        assertSame(list, bounded)
    }

    @Test
    fun `an oversized list is truncated to the cap, keeping the head`() {
        val list = (1..100).map { route(it) }
        val bounded = boundRoutes(list)
        assertEquals(LocalRouteStore.MAX_ROUTES, bounded.size)
        // Order preserved — inbound lists are pre-sorted by recency, so
        // the head is the set the runner most wants.
        assertEquals("route-1", bounded.first().id)
        assertEquals("route-${LocalRouteStore.MAX_ROUTES}", bounded.last().id)
    }

    @Test
    fun `an empty list stays empty`() {
        assertEquals(emptyList<SavedRoute>(), boundRoutes(emptyList()))
    }

    @Test
    fun `a short list is returned as-is`() {
        val list = listOf(route(1), route(2), route(3))
        assertEquals(3, boundRoutes(list).size)
    }
}
