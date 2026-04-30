package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackOverlayBufferTest {

    @Test
    fun `under cap is a noop`() {
        val buf = mutableListOf(1, 2, 3)
        TrackOverlayBuffer.halveIfOverflowing(buf, cap = 4)
        assertEquals(listOf(1, 2, 3), buf)
    }

    @Test
    fun `at cap exactly is a noop`() {
        val buf = mutableListOf(1, 2, 3, 4)
        TrackOverlayBuffer.halveIfOverflowing(buf, cap = 4)
        assertEquals(listOf(1, 2, 3, 4), buf)
    }

    @Test
    fun `one over cap halves to even indices`() {
        val buf = mutableListOf(1, 2, 3, 4, 5)
        TrackOverlayBuffer.halveIfOverflowing(buf, cap = 4)
        // Even indices of the original: 0, 2, 4 → values 1, 3, 5.
        assertEquals(listOf(1, 3, 5), buf)
    }

    @Test
    fun `geometric halving never evicts the first point`() {
        // First point is the run's start. We want it visible on the
        // mini-map throughout — geometric halving (every other) is
        // chosen specifically because it preserves index 0.
        val buf = (1..1000).toMutableList()
        var iterations = 0
        while (buf.size > 256) {
            TrackOverlayBuffer.halveIfOverflowing(buf, cap = 256)
            iterations++
            check(iterations < 20) { "halving loop didn't converge" }
        }
        assertEquals("first point preserved", 1, buf.first())
        assertTrue("size within cap", buf.size <= 256)
    }

    @Test
    fun `repeated halving converges in log(n) iterations`() {
        // 10000 points → 256 cap. Halving each time means
        // ceil(log2(10000/256)) = 6 iterations to get under cap.
        val buf = (1..10_000).toMutableList()
        var iterations = 0
        while (buf.size > 256) {
            TrackOverlayBuffer.halveIfOverflowing(buf, cap = 256)
            iterations++
        }
        assertTrue("should converge in ≤ 6 iterations, took $iterations", iterations <= 6)
        assertTrue("final size ≤ cap", buf.size <= 256)
    }

    @Test
    fun `successive append-plus-halve mimics service hot loop`() {
        // Mirror what RunRecordingService does: append one point per
        // GPS sample, then halveIfOverflowing(MAX). Run a synthetic
        // 600-point sequence and assert (a) buffer never exceeds cap,
        // (b) first point preserved, (c) last point is the most recent.
        val buf = mutableListOf<Int>()
        for (i in 1..600) {
            buf.add(i)
            TrackOverlayBuffer.halveIfOverflowing(buf, cap = 100)
            assertTrue("size never exceeds cap mid-loop", buf.size <= 100)
        }
        assertEquals("first point preserved", 1, buf.first())
        assertEquals("most recent point at end", 600, buf.last())
    }

    @Test
    fun `cap below 2 raises`() {
        val buf = mutableListOf(1, 2, 3)
        try {
            TrackOverlayBuffer.halveIfOverflowing(buf, cap = 1)
            org.junit.Assert.fail("cap=1 should have raised")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("cap"))
        }
    }
}
