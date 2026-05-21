package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// "Should I resubscribe the GPS source?" — pure decision lifted
/// from `RunRecordingService.gpsRetryJob`. Two trigger paths, both
/// load-bearing on Wear OS where `FusedLocationProviderClient` can
/// silently stop emitting while keeping the callback registered.
class GpsRetryDecisionTest {

    // ─────────── dead-subscription trigger (primary path) ───────────

    @Test fun `dead subscription resubscribes (jobAlive=false)`() {
        val d = shouldResubscribeGps(
            jobAlive = false,
            lastPointAtMs = 1_000_000L,
            nowMs = 1_010_000L,
        )
        assertTrue(d.shouldResubscribe)
        assertFalse("Dead subscription is not a stall — primary trigger.",
            d.triggeredByStall)
    }

    @Test fun `dead subscription resubscribes even with no prior fix`() {
        // jobAlive=false beats every other condition. Even at cold
        // start (lastPointAtMs=0), if the job died we need to bring
        // GPS back up.
        val d = shouldResubscribeGps(
            jobAlive = false,
            lastPointAtMs = 0L,
            nowMs = 1_000L,
        )
        assertTrue(d.shouldResubscribe)
        assertFalse(d.triggeredByStall)
    }

    // ─────────── stall trigger (secondary, Wear-specific) ───────────

    @Test fun `alive subscription silent gt 30 sec mid-run triggers resubscribe`() {
        // jobAlive=true but no GPS sample for 30+ seconds. Force a
        // fresh subscription — the Wear-specific failure mode where
        // `FusedLocationProviderClient` keeps the callback registered
        // but stops emitting.
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 100_000L,
            nowMs = 131_000L,  // 31 s elapsed
        )
        assertTrue(d.shouldResubscribe)
        assertTrue("Stall-triggered resubscribe must signal `triggeredByStall=true` so the caller resets the staleness window.",
            d.triggeredByStall)
    }

    @Test fun `alive subscription silent EXACTLY 30 sec does NOT resubscribe`() {
        // Boundary: the check is `> 30_000` (strict). Exactly-30 is
        // still within the tolerance. Pin so a sloppy `>=` change
        // doesn't trigger on every borderline poll cycle.
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 100_000L,
            nowMs = 130_000L,
        )
        assertFalse(d.shouldResubscribe)
        assertFalse(d.triggeredByStall)
    }

    @Test fun `alive subscription silent 30001 ms resubscribes (one ms past)`() {
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 100_000L,
            nowMs = 130_001L,
        )
        assertTrue(d.shouldResubscribe)
        assertTrue(d.triggeredByStall)
    }

    @Test fun `alive subscription with recent fix does NOT resubscribe`() {
        // Healthy state: GPS sample 1 second ago, subscription
        // alive. Do nothing.
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 100_000L,
            nowMs = 101_000L,
        )
        assertFalse(d.shouldResubscribe)
        assertFalse(d.triggeredByStall)
    }

    // ─────────── initial cold-acquire is NOT a stall ───────────

    @Test fun `alive subscription with lastPointAtMs=0 does NOT count as stall`() {
        // Critical: at recording start, we haven't received a fix
        // yet. The subscription is alive but `lastPointAtMs == 0`.
        // This is INDOOR / COLD-ACQUIRE — a legitimate state that
        // must NOT trigger a resubscribe. The runner sees "No GPS
        // — time only" banner; the elapsed clock keeps ticking.
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 0L,
            nowMs = 120_000L,  // 2 min into a cold-acquire
        )
        assertFalse(
            "Initial no-fix is NOT a stall — pinned per RunRecordingService.kt comment.",
            d.shouldResubscribe,
        )
        assertFalse(d.triggeredByStall)
    }

    @Test fun `alive subscription with lastPointAtMs=0 even after long indoor period`() {
        // Indoor warm-up could take many minutes. The retry loop
        // polls every 10 s; without the lastPointAtMs=0 guard, the
        // loop would thrash resubscriptions forever during the
        // warm-up.
        val d = shouldResubscribeGps(
            jobAlive = true,
            lastPointAtMs = 0L,
            nowMs = 600_000L,  // 10 min indoor
        )
        assertFalse(d.shouldResubscribe)
    }

    // ─────────── precedence: dead subscription wins over stall ───────────

    @Test fun `dead subscription takes precedence over stall (triggeredByStall=false)`() {
        // Both conditions hold: subscription dead AND last fix was
        // long ago. Decision is "resubscribe" but classify as
        // dead-sub (not stall) so the caller doesn't reset
        // `lastPointAtMs = nowMs` (resetting would erase the fact
        // that we'd had a fix mid-run, useful diagnostics).
        val d = shouldResubscribeGps(
            jobAlive = false,
            lastPointAtMs = 100_000L,
            nowMs = 200_000L,
        )
        assertTrue(d.shouldResubscribe)
        assertFalse(
            "Dead-subscription path must not be tagged as stall — the caller branches on this.",
            d.triggeredByStall,
        )
    }

    // ─────────── constant pinned ───────────

    @Test fun `GPS_STALL_MS pinned at 30 sec`() {
        // The 30 s threshold is tuned for the Wear-specific failure
        // mode. Pin in source so a sloppy refactor doesn't drop it
        // to 5 s (haptic thrash) or raise it to 5 min (runner loses
        // distance for an entire kilometre).
        assertEquals(30_000L, GPS_STALL_MS)
    }
}
