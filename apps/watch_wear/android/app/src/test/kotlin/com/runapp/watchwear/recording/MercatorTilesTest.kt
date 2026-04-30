package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class MercatorTilesTest {

    private fun ll(lat: Double, lng: Double) = RouteMath.LatLng(lat, lng)

    @Test
    fun `fitBounds returns null for empty point list`() {
        assertNull(MercatorTiles.fitBounds(emptyList(), 256f))
    }

    @Test
    fun `fitBounds zoom 14 for a single point`() {
        val c = MercatorTiles.fitBounds(listOf(ll(-37.81, 144.96)), 256f)!!
        assertEquals(14, c.zoom)
        assertEquals(-37.81, c.lat, 1e-9)
        assertEquals(144.96, c.lng, 1e-9)
    }

    @Test
    fun `fitBounds picks larger zoom for tighter bounds`() {
        val tight = MercatorTiles.fitBounds(
            listOf(ll(-37.810, 144.960), ll(-37.811, 144.961)),
            256f,
        )!!
        val loose = MercatorTiles.fitBounds(
            listOf(ll(-37.5, 144.5), ll(-38.0, 145.5)),
            256f,
        )!!
        assertTrue(
            "tighter bounds → higher zoom (zoomed in further); got tight=${tight.zoom} loose=${loose.zoom}",
            tight.zoom > loose.zoom,
        )
    }

    @Test
    fun `fitBounds clamps zoom to 1 for ridiculously wide bounds`() {
        // An almost-whole-world bounds — fits inside zoom 1 (which shows
        // the entire 4-tile world view). Important because log2 of an
        // already-fitting span yields a negative zoom we must clamp.
        val c = MercatorTiles.fitBounds(
            listOf(ll(-80.0, -170.0), ll(80.0, 170.0)),
            256f,
        )!!
        assertEquals(1, c.zoom)
    }

    @Test
    fun `fitBounds clamps zoom to 18 for sub-meter bounds`() {
        // A 1-meter-ish bounds; without the upper clamp the zoom would
        // shoot past 22 and tile servers would 404.
        val c = MercatorTiles.fitBounds(
            listOf(ll(-37.810000, 144.960000), ll(-37.810001, 144.960001)),
            256f,
        )!!
        assertTrue("zoom <= 18; got ${c.zoom}", c.zoom <= 18)
    }

    @Test
    fun `project lands the centre at viewport centre`() {
        val centre = MercatorTiles.Centre(-37.81, 144.96, 14)
        val (x, y) = MercatorTiles.project(ll(-37.81, 144.96), centre, 256f)
        // Centre should be exactly at (128, 128) on a 256-px viewport.
        assertEquals(128f, x, 0.5f)
        assertEquals(128f, y, 0.5f)
    }

    @Test
    fun `project northward decreases y as expected`() {
        // North of the centre should land above (smaller y).
        val centre = MercatorTiles.Centre(0.0, 0.0, 5)
        val (_, ySouth) = MercatorTiles.project(ll(-1.0, 0.0), centre, 256f)
        val (_, yNorth) = MercatorTiles.project(ll(1.0, 0.0), centre, 256f)
        assertTrue("northward ⇒ smaller y; south=$ySouth north=$yNorth", yNorth < ySouth)
    }

    @Test
    fun `project eastward increases x`() {
        val centre = MercatorTiles.Centre(0.0, 0.0, 5)
        val (xWest, _) = MercatorTiles.project(ll(0.0, -1.0), centre, 256f)
        val (xEast, _) = MercatorTiles.project(ll(0.0, 1.0), centre, 256f)
        assertTrue("eastward ⇒ larger x; west=$xWest east=$xEast", xEast > xWest)
    }

    @Test
    fun `project is symmetric across the centre`() {
        // A point N degrees east of centre and N degrees west of centre
        // should land equidistant from the viewport centre.
        val centre = MercatorTiles.Centre(0.0, 0.0, 8)
        val (xWest, _) = MercatorTiles.project(ll(0.0, -0.5), centre, 256f)
        val (xEast, _) = MercatorTiles.project(ll(0.0, 0.5), centre, 256f)
        val dWest = abs(128f - xWest)
        val dEast = abs(xEast - 128f)
        assertEquals("symmetry across centre", dWest, dEast, 0.5f)
    }

    @Test
    fun `visibleTiles emits all four corners around centre at minimum`() {
        // A 256-px viewport fits exactly one tile at integer alignment;
        // with the +1 overshoot we should always see at least 9 tiles
        // (3x3) so panning doesn't expose untiled background.
        val centre = MercatorTiles.Centre(0.0, 0.0, 5)
        val tiles = MercatorTiles.visibleTiles(centre, 256f)
        assertTrue("at least 9 tiles for safe pan; got ${tiles.size}", tiles.size >= 9)
        // All tiles share the chosen integer zoom.
        assertTrue("all tiles at zoom 5", tiles.all { it.z == 5 })
    }

    @Test
    fun `visibleTiles screen positions stitch to neighbours at exactly 256 px`() {
        val centre = MercatorTiles.Centre(0.0, 0.0, 5)
        val tiles = MercatorTiles.visibleTiles(centre, 256f)
        // Find any horizontally-adjacent pair and check the gap.
        val grouped = tiles.groupBy { it.y }
        val row = grouped.values.first { it.size >= 2 }.sortedBy { it.x }
        val gap = row[1].screenX - row[0].screenX
        assertEquals("adjacent tiles stitch at 256 px", 256f, gap, 0.5f)
    }

    @Test
    fun `visibleTiles does not emit negative or out-of-range tile indices`() {
        // Near the poles and antimeridian the tile index can wrap;
        // we deliberately clip rather than fetch wrap-around tiles.
        val nearPole = MercatorTiles.Centre(84.0, 179.0, 3)
        val tiles = MercatorTiles.visibleTiles(nearPole, 256f)
        assertTrue(
            "no negative tile indices; got ${tiles.filter { it.x < 0 || it.y < 0 }}",
            tiles.all { it.x >= 0 && it.y >= 0 },
        )
        val maxTile = (1 shl 3) - 1  // 2^z - 1
        assertTrue(
            "no over-range tile indices; got ${tiles.filter { it.x > maxTile || it.y > maxTile }}",
            tiles.all { it.x <= maxTile && it.y <= maxTile },
        )
    }

    @Test
    fun `tile projection and point projection agree at the same zoom`() {
        // Critical alignment invariant: a tile boundary in lat/lng must
        // project to the same screen pixel as the corresponding tile
        // corner emitted by visibleTiles. If these drift, the polyline
        // floats off the road.
        val centre = MercatorTiles.Centre(-37.81, 144.96, 14)
        val tiles = MercatorTiles.visibleTiles(centre, 256f)
        // Pick the tile that contains the centre — its corner lat/lng
        // can be back-computed and then projected; should match the
        // tile.screenX/screenY exactly.
        val tile = tiles.first { it.x == centre.lngToTileX() && it.y == centre.latToTileY() }
        val (cornerLat, cornerLng) = tileCornerLatLng(tile.z, tile.x, tile.y)
        val (sx, sy) = MercatorTiles.project(ll(cornerLat, cornerLng), centre, 256f)
        assertEquals("tile corner X aligns with project()", tile.screenX, sx, 1.0f)
        assertEquals("tile corner Y aligns with project()", tile.screenY, sy, 1.0f)
    }

    // --- helpers used only inside this file ---
    private fun MercatorTiles.Centre.lngToTileX(): Int {
        val n = 1 shl zoom
        return ((lng + 180.0) / 360.0 * n).toInt()
    }
    private fun MercatorTiles.Centre.latToTileY(): Int {
        val n = 1 shl zoom
        val rad = lat * Math.PI / 180.0
        val y = (1.0 - kotlin.math.ln(kotlin.math.tan(rad) + 1.0 / kotlin.math.cos(rad)) / Math.PI) / 2.0
        return (y * n).toInt()
    }
    private fun tileCornerLatLng(z: Int, x: Int, y: Int): Pair<Double, Double> {
        val n = (1 shl z).toDouble()
        val lng = x / n * 360.0 - 180.0
        val merc = y / n
        // Inverse of (1 - ln(tan φ + sec φ) / π) / 2 = merc
        val k = (1.0 - 2 * merc) * Math.PI
        val lat = kotlin.math.atan(kotlin.math.sinh(k)) * 180.0 / Math.PI
        return lat to lng
    }
}
