package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DrainBackoffTest {

    @Test
    fun `fresh instance is not in backoff and has zero current window`() {
        val now = ClockHolder()
        val b = DrainBackoff(nowMs = now::value)
        assertEquals(0, b.consecutiveFailures)
        assertFalse(b.isInBackoff())
        assertEquals(0L, b.currentBackoffMs())
    }

    @Test
    fun `first failure arms a 60 s window`() {
        val now = ClockHolder(value = 10_000L)
        val b = DrainBackoff(nowMs = now::value)
        b.onFailure()
        assertEquals(1, b.consecutiveFailures)
        assertEquals(60_000L, b.currentBackoffMs())
        assertTrue(b.isInBackoff())
    }

    @Test
    fun `consecutive failures double the window`() {
        val now = ClockHolder(value = 0L)
        val b = DrainBackoff(nowMs = now::value)
        b.onFailure() // 60s
        assertEquals(60_000L, b.currentBackoffMs())
        b.onFailure() // 120s
        assertEquals(120_000L, b.currentBackoffMs())
        b.onFailure() // 240s
        assertEquals(240_000L, b.currentBackoffMs())
        b.onFailure() // 480s
        assertEquals(480_000L, b.currentBackoffMs())
        b.onFailure() // 960s
        assertEquals(960_000L, b.currentBackoffMs())
    }

    @Test
    fun `window clamps at the 30 min ceiling no matter how many failures pile up`() {
        val now = ClockHolder(value = 0L)
        val b = DrainBackoff(nowMs = now::value)
        repeat(40) { b.onFailure() }
        assertEquals(30 * 60_000L, b.currentBackoffMs())
    }

    @Test
    fun `clock advancing past the window clears isInBackoff`() {
        val now = ClockHolder(value = 0L)
        val b = DrainBackoff(nowMs = now::value)
        b.onFailure()
        assertTrue(b.isInBackoff())
        now.value = 60_001L
        assertFalse(b.isInBackoff())
    }

    @Test
    fun `onSuccess resets the counter and the timestamp`() {
        val now = ClockHolder(value = 0L)
        val b = DrainBackoff(nowMs = now::value)
        b.onFailure()
        b.onFailure()
        assertEquals(2, b.consecutiveFailures)

        b.onSuccess()
        assertEquals(0, b.consecutiveFailures)
        assertEquals(0L, b.lastFailureAtMs)
        assertFalse(b.isInBackoff())
    }

    @Test
    fun `lastFailureAtMs reflects the most recent failure`() {
        val now = ClockHolder(value = 1_000L)
        val b = DrainBackoff(nowMs = now::value)
        b.onFailure()
        assertEquals(1_000L, b.lastFailureAtMs)
        now.value = 90_000L
        b.onFailure()
        assertEquals(90_000L, b.lastFailureAtMs)
    }

    // ---- queueReadRetryDelayMs ----
    //
    // The queue STREAM's retry curve, which is not this class's. `Flow.catch`
    // on `store.queue` completed the flow, so one failed read froze the
    // pre-run count for the life of the process (decisions § 1104). The
    // replacement is a retry, and a retry that never slows down against a
    // permanently corrupt file is a busy loop.

    @Test
    fun `the first retry is immediate enough to ride out a transient blip`() {
        // A local file open, not a network round trip: waiting the drain's
        // 60 s to re-read a file that recovered in the same second would
        // leave the chip wrong for a minute for no reason.
        assertEquals(1_000L, queueReadRetryDelayMs(0))
    }

    @Test
    fun `consecutive failures double the wait`() {
        assertEquals(2_000L, queueReadRetryDelayMs(1))
        assertEquals(4_000L, queueReadRetryDelayMs(2))
        assertEquals(8_000L, queueReadRetryDelayMs(3))
    }

    @Test
    fun `the wait is capped so a corrupt file costs one open a minute`() {
        assertEquals(32_000L, queueReadRetryDelayMs(5))
        assertEquals(60_000L, queueReadRetryDelayMs(6))
        assertEquals(60_000L, queueReadRetryDelayMs(60))
    }

    @Test
    fun `an attempt count that would overflow the shift still clamps`() {
        // `1_000L shl 64` is `1_000L shl 0` on the JVM — the shift wraps, so
        // an unclamped exponent returns the BASE delay after 64 failures and
        // the backoff silently resets to a busy retry.
        assertEquals(60_000L, queueReadRetryDelayMs(64))
        assertEquals(60_000L, queueReadRetryDelayMs(Long.MAX_VALUE))
    }

    private class ClockHolder(var value: Long = 0L)
}
