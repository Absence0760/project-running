package com.runapp.watchwear

import android.Manifest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Grading of the pre-run permission dialog's result.
///
/// The callback this backs was `if (granted[ACCESS_FINE_LOCATION] == true)
/// { showCountdown = true }` with no else, so every denial returned the
/// runner to an unchanged pre-run screen: no countdown, no message, no
/// state change. On a watch with no keyboard a control that does nothing
/// is unrecoverable — there is nowhere to ask what happened.
class PermissionOutcomeTest {

    private val fine = Manifest.permission.ACCESS_FINE_LOCATION
    private val sensors = Manifest.permission.BODY_SENSORS
    private val activity = Manifest.permission.ACTIVITY_RECOGNITION
    private val notifications = Manifest.permission.POST_NOTIFICATIONS

    @Test
    fun `everything granted starts the run and reports nothing`() {
        val outcome = permissionOutcome(
            mapOf(fine to true, sensors to true, activity to true, notifications to true),
        )
        assertTrue(outcome.canStart)
        assertEquals(emptyList<PermissionCost>(), outcome.costs)
    }

    @Test
    fun `a location denial blocks the run and names itself`() {
        val outcome = permissionOutcome(
            mapOf(fine to false, sensors to true, activity to true),
        )
        assertFalse(outcome.canStart)
        assertEquals(listOf(PermissionCost.Location), outcome.costs)
    }

    @Test
    fun `an auxiliary denial degrades the run rather than blocking it`() {
        val outcome = permissionOutcome(
            mapOf(fine to true, sensors to false, activity to true),
        )
        assertTrue(
            "declining heart rate must not cost the runner the whole run",
            outcome.canStart,
        )
        assertEquals(listOf(PermissionCost.HeartRate), outcome.costs)
    }

    @Test
    fun `an absent key is not a denial`() {
        // POST_NOTIFICATIONS is only requested from API 33, so on a Wear OS
        // 3 watch it never appears in the map. Reading absence as denial
        // would tell every such runner they had turned off a notification
        // they were never asked about.
        val outcome = permissionOutcome(
            mapOf(fine to true, sensors to true, activity to true),
        )
        assertTrue(outcome.canStart)
        assertEquals(emptyList<PermissionCost>(), outcome.costs)

        val explicit = permissionOutcome(
            mapOf(fine to true, sensors to true, activity to true, notifications to false),
        )
        assertEquals(listOf(PermissionCost.OngoingNotification), explicit.costs)
    }

    @Test
    fun `costs are reported in one fixed order`() {
        // The card reads the same way every time, whatever order the
        // platform happened to key the result map in.
        val outcome = permissionOutcome(
            mapOf(
                notifications to false,
                activity to false,
                sensors to false,
                fine to false,
            ),
        )
        assertEquals(
            listOf(
                PermissionCost.Location,
                PermissionCost.HeartRate,
                PermissionCost.Steps,
                PermissionCost.OngoingNotification,
            ),
            outcome.costs,
        )
    }

    @Test
    fun `a run that cannot start always stops at the notice`() {
        val blocked = permissionOutcome(mapOf(fine to false))
        assertTrue(shouldInterruptForCosts(blocked, alreadyShown = false))
        assertTrue(
            "a second refusal is still a refusal — the reason does not " +
                "stop being owed because it was shown once",
            shouldInterruptForCosts(blocked, alreadyShown = true),
        )
        // The degenerate case: a result map that named nothing. Silently
        // doing nothing here is the original defect, so it stops too.
        val empty = permissionOutcome(emptyMap())
        assertFalse(empty.canStart)
        assertEquals(emptyList<PermissionCost>(), empty.costs)
        assertTrue(shouldInterruptForCosts(empty, alreadyShown = true))
    }

    @Test
    fun `a degraded but runnable set is reported once, not before every run`() {
        val degraded = permissionOutcome(mapOf(fine to true, activity to false))
        assertTrue(degraded.canStart)
        assertTrue(shouldInterruptForCosts(degraded, alreadyShown = false))
        assertFalse(
            "a runner who permanently declined step counting must not have " +
                "to dismiss the same card before every run",
            shouldInterruptForCosts(degraded, alreadyShown = true),
        )
    }

    @Test
    fun `a fully granted set never interrupts`() {
        val ok = permissionOutcome(mapOf(fine to true, sensors to true, activity to true))
        assertFalse(shouldInterruptForCosts(ok, alreadyShown = false))
        assertFalse(shouldInterruptForCosts(ok, alreadyShown = true))
    }
}
