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

    private class ClockHolder(var value: Long = 0L)
}
