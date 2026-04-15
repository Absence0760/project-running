package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test

/// Active-elapsed-time math is the single most load-bearing calculation
/// in the recording service — every finish time + every pace number
/// depends on it. These tests exercise it against realistic scenarios
/// from short intervals to 10-hour ultra-runs.
class ElapsedMathTest {

    @Test
    fun `not paused, returns full elapsed`() {
        val start = 1_000_000L
        val now = start + 30_000
        assertEquals(30_000, activeElapsedMs(now, start, 0, 0))
    }

    @Test
    fun `currently paused, excludes in-progress pause`() {
        val start = 1_000_000L
        val now = start + 60_000
        val pauseStarted = start + 45_000 // paused for 15s, so active = 45s
        assertEquals(45_000, activeElapsedMs(now, start, 0, pauseStarted))
    }

    @Test
    fun `accumulated pause only`() {
        val start = 1_000_000L
        val now = start + 120_000
        assertEquals(110_000, activeElapsedMs(now, start, 10_000, 0))
    }

    @Test
    fun `accumulated pause plus in-progress pause`() {
        val start = 1_000_000L
        val now = start + 200_000
        val pauseStarted = start + 180_000
        // total 200s - accumulated 30s - current 20s = 150s
        assertEquals(150_000, activeElapsedMs(now, start, 30_000, pauseStarted))
    }

    @Test
    fun `zero at recording start`() {
        assertEquals(0, activeElapsedMs(1_000_000L, 1_000_000L, 0, 0))
    }

    @Test
    fun `never goes negative on clock weirdness`() {
        // nowMs < startedAtMs can happen if the user adjusts the clock.
        assertEquals(0, activeElapsedMs(999_000L, 1_000_000L, 0, 0))
    }

    @Test
    fun `10-hour ultra, 40min of pauses across many aid stations`() {
        val start = 0L
        val now = 10L * 3600 * 1000
        val pauses = 40L * 60 * 1000
        // 10h real - 40m aid = 9h20m = 33_600_000ms
        assertEquals(9L * 3600 * 1000 + 20 * 60 * 1000, activeElapsedMs(now, start, pauses, 0))
    }

    @Test
    fun `paused since start, zero active`() {
        val start = 1_000_000L
        val now = start + 30_000
        assertEquals(0, activeElapsedMs(now, start, 0, start))
    }
}
