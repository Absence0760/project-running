package com.runapp.watchwear.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The two-press guard behind the crash-recovery prompt's Discard
/// (decisions § 1206). Compose state is not host-JVM testable in this module,
/// so the DECISION lives here as a pure function and the composable only holds
/// the timestamp — the same split `PaceAlert.shouldFirePaceAlert` uses.
class ConfirmGuardTest {

    @Test
    fun `an unarmed control arms rather than fires`() {
        assertEquals(ConfirmPress.Armed, confirmPress(armedAtMs = null, nowMs = 1_000))
    }

    @Test
    fun `a second press inside the window commits`() {
        assertEquals(ConfirmPress.Confirmed, confirmPress(armedAtMs = 1_000, nowMs = 1_001))
    }

    @Test
    fun `a press at the exact edge of the window still commits`() {
        assertEquals(
            ConfirmPress.Confirmed,
            confirmPress(armedAtMs = 1_000, nowMs = 1_000 + CONFIRM_WINDOW_MS),
        )
    }

    @Test
    fun `a press one millisecond past the window re-arms`() {
        assertEquals(
            ConfirmPress.Armed,
            confirmPress(armedAtMs = 1_000, nowMs = 1_000 + CONFIRM_WINDOW_MS + 1),
        )
    }

    @Test
    fun `a double press at the same instant commits`() {
        // Two taps can land on one millisecond reading; a zero-age arm is a
        // real second press, not a clock that moved.
        assertEquals(ConfirmPress.Confirmed, confirmPress(armedAtMs = 5_000, nowMs = 5_000))
    }

    @Test
    fun `an arm stamped in the future re-arms instead of committing`() {
        // A clock that jumped backwards must never make a destructive action
        // reachable in one press.
        assertEquals(ConfirmPress.Armed, confirmPress(armedAtMs = 9_000, nowMs = 1_000))
    }

    @Test
    fun `the window is long enough to press twice and short enough to lapse`() {
        assertTrue("a wrist double-press needs more than a second", CONFIRM_WINDOW_MS >= 2_000)
        assertTrue(
            "an arm left behind by a distraction must be gone before the runner looks again",
            CONFIRM_WINDOW_MS <= 15_000,
        )
    }
}
