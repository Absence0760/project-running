package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Coverage of `shouldFirePaceAlert` — the rate-limited pace-drift
/// trigger that powers haptic + TTS "speed up" / "slow down" cues.
///
/// User-visible safety feature: a runner relying on the haptic to
/// hold a target pace must trust that the alert fires when the drift
/// is real AND doesn't strobe when the pace is wobbly. Both the
/// 30 s/km drift threshold and the 30 s rate-limit are tuned by feel
/// — pinning them in source guards against an accidental constant-
/// change.
class PaceAlertTest {

    // ───────────── below threshold (no fire) ─────────────

    @Test fun `pace within drift threshold (0 diff) does NOT fire`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 300.0,
            nowMs = 0L,
            lastAlertAtMs = 0L,
        )
        assertFalse(d.fire)
        assertEquals(0L, d.newLastAlertAtMs)
    }

    @Test fun `pace exactly 30 sec drift does NOT fire (strict greater than)`() {
        // Boundary: 30 s drift is at the threshold. The check is
        // `> 30` (strict), so exactly-30 doesn't fire. Pin the strict
        // inequality so a sloppy `>=` change doesn't trigger on
        // every borderline reading.
        val tooSlow = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 330.0,
            nowMs = 0L,
            lastAlertAtMs = 0L,
        )
        assertFalse("Drift exactly equal to threshold (30) must not fire.", tooSlow.fire)

        val tooFast = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 270.0,
            nowMs = 0L,
            lastAlertAtMs = 0L,
        )
        assertFalse(tooFast.fire)
    }

    @Test fun `pace 29 sec slower does NOT fire`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 329.0,
            nowMs = 0L,
            lastAlertAtMs = 0L,
        )
        assertFalse(d.fire)
    }

    // ───────────── above threshold (fires) ─────────────

    @Test fun `pace 31 sec SLOWER fires with tooSlow=true`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 331.0,
            nowMs = 60_000L,
            lastAlertAtMs = 0L,
        )
        assertTrue(d.fire)
        assertTrue("Positive drift = runner is slower than target", d.tooSlow)
        assertEquals(60_000L, d.newLastAlertAtMs)
    }

    @Test fun `pace 31 sec FASTER fires with tooSlow=false`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 269.0,
            nowMs = 60_000L,
            lastAlertAtMs = 0L,
        )
        assertTrue(d.fire)
        assertFalse("Negative drift = runner is faster than target", d.tooSlow)
    }

    @Test fun `large drift (100 sec slow) fires with tooSlow=true`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 60_000L,
            lastAlertAtMs = 0L,
        )
        assertTrue(d.fire)
        assertTrue(d.tooSlow)
    }

    // ───────────── rate-limit ─────────────

    @Test fun `rate-limit blocks fire when elapsed lt 30 sec since last alert`() {
        // Drift exceeds threshold but the rate-limit window hasn't
        // cleared yet. No fire — the haptic stays quiet.
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 5_000L,
            lastAlertAtMs = 0L,
        )
        assertFalse("Rate-limit window must block consecutive alerts.", d.fire)
        // Critical: the rate-limit timestamp DOESN'T move forward
        // when we don't fire. If it did, the window would never
        // clear because every onGps call would push it forward.
        assertEquals(
            "lastAlertAtMs must NOT advance when fire is blocked — would otherwise reset the rate-limit on every GPS sample.",
            0L,
            d.newLastAlertAtMs,
        )
    }

    @Test fun `rate-limit at exactly 30 sec since last alert still blocks (strict greater than)`() {
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 30_000L,
            lastAlertAtMs = 0L,
        )
        assertFalse("Rate-limit exactly equal to 30 s does not fire — strict `>`.", d.fire)
    }

    @Test fun `rate-limit at 30001 ms since last alert allows fire`() {
        // One millisecond past the window — fires.
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 30_001L,
            lastAlertAtMs = 0L,
        )
        assertTrue(d.fire)
        assertEquals(30_001L, d.newLastAlertAtMs)
    }

    @Test fun `rate-limit honours arbitrary lastAlertAtMs offset (not absolute time)`() {
        // The math is `nowMs - lastAlertAtMs > 30_000`, not anchored
        // at 0. Pin that an alert two minutes into a run, followed
        // by another at 2:31, fires correctly.
        val d = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 151_000L,
            lastAlertAtMs = 120_000L,
        )
        assertTrue(d.fire)
        assertEquals(151_000L, d.newLastAlertAtMs)
    }

    @Test fun `pace-noise doesn't reset rate-limit (no-fire preserves timestamp)`() {
        // Realistic case: an alert fired at t=120s. At t=125s the pace
        // is back within threshold; the no-fire decision MUST preserve
        // lastAlertAtMs=120000. Then at t=148s the pace drifts again
        // — still inside the rate-limit window from 120, no fire.
        // At t=151s, more than 30s past the original alert, fires.
        val step1 = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 305.0,  // within threshold
            nowMs = 125_000L,
            lastAlertAtMs = 120_000L,
        )
        assertFalse(step1.fire)
        assertEquals(120_000L, step1.newLastAlertAtMs)

        val step2 = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,  // drift exceeded, but within rate-limit
            nowMs = 148_000L,
            lastAlertAtMs = step1.newLastAlertAtMs,
        )
        assertFalse(step2.fire)
        assertEquals(120_000L, step2.newLastAlertAtMs)

        val step3 = shouldFirePaceAlert(
            targetPaceSecPerKm = 300,
            currentPaceSecPerKm = 400.0,
            nowMs = 151_000L,
            lastAlertAtMs = step2.newLastAlertAtMs,
        )
        assertTrue(step3.fire)
        assertEquals(151_000L, step3.newLastAlertAtMs)
    }

    // ───────────── threshold constants ─────────────

    @Test fun `PACE_DRIFT_THRESHOLD pinned at 30 sec per km`() {
        assertEquals(30, PACE_DRIFT_THRESHOLD_S_PER_KM)
    }

    @Test fun `PACE_ALERT_RATE_LIMIT pinned at 30 sec`() {
        assertEquals(30_000L, PACE_ALERT_RATE_LIMIT_MS)
    }

    // ───────────── direction consistency ─────────────

    @Test fun `every fire decision has consistent tooSlow flag with the diff sign`() {
        // Sweep across drift values that fire — confirm tooSlow is
        // ALWAYS the sign of (current - target).
        for (current in listOf(331.0, 350.0, 400.0, 600.0)) {
            val d = shouldFirePaceAlert(
                targetPaceSecPerKm = 300,
                currentPaceSecPerKm = current,
                nowMs = 60_000L,
                lastAlertAtMs = 0L,
            )
            assertTrue("current=$current must fire", d.fire)
            assertTrue("current=$current is slower than target, tooSlow must be true", d.tooSlow)
        }
        for (current in listOf(269.0, 250.0, 200.0, 100.0)) {
            val d = shouldFirePaceAlert(
                targetPaceSecPerKm = 300,
                currentPaceSecPerKm = current,
                nowMs = 60_000L,
                lastAlertAtMs = 0L,
            )
            assertTrue("current=$current must fire", d.fire)
            assertFalse("current=$current is faster than target, tooSlow must be false", d.tooSlow)
        }
    }
}
