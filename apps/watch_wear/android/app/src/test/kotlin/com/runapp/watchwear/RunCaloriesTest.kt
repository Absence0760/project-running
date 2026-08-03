package com.runapp.watchwear

import com.runapp.watchwear.recording.RunCalories
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/// Pins the watch-side calorie estimate (persona samsung #34) against
/// the shared 1 kcal/kg/km ladder so the wrist figure matches the
/// phone/web run-detail recompute.
class RunCaloriesTest {

    @Test
    fun `run uses 1 kcal per kg per km`() {
        // 70 kg × 1.0 × 10 km = 700.
        assertEquals(700, RunCalories.estimate(10_000.0, 70.0, "run"))
    }

    @Test
    fun `walk and cycle use lower coefficients`() {
        assertEquals(350, RunCalories.estimate(10_000.0, 70.0, "walk")) // 0.5
        assertEquals(280, RunCalories.estimate(10_000.0, 70.0, "cycle")) // 0.4
    }

    @Test
    fun `null weight falls back to the 70 kg default`() {
        assertEquals(
            RunCalories.estimate(5_000.0, 70.0, "run"),
            RunCalories.estimate(5_000.0, null, "run"),
        )
    }

    @Test
    fun `unknown activity type falls back to the run coefficient`() {
        assertEquals(
            RunCalories.estimate(5_000.0, 80.0, "run"),
            RunCalories.estimate(5_000.0, 80.0, "rollerblade"),
        )
    }

    @Test
    fun `zero distance is zero kcal`() {
        assertEquals(0, RunCalories.estimate(0.0, 70.0, "run"))
    }

    @Test
    fun `a synced body weight is used, not the fallback`() {
        // The wrist reads `user_settings.prefs.body_weight_kg`, so a runner
        // who set 55 kg must not be billed the 70 kg median. Pins the
        // absolute figure (55 × 1.0 × 10 = 550) AND that it differs from the
        // fallback — an implementation that ignored `weightKg` entirely
        // would still pass the absolute assert if 70 were substituted, so
        // the inequality is the load-bearing half.
        assertEquals(550, RunCalories.estimate(10_000.0, 55.0, "run"))
        assertEquals(950, RunCalories.estimate(10_000.0, 95.0, "run"))
        assertNotEquals(
            RunCalories.estimate(10_000.0, null, "run"),
            RunCalories.estimate(10_000.0, 55.0, "run"),
        )
    }

    @Test
    fun `an unset body weight reproduces the documented 70 kg fallback`() {
        // Pins the literal, not merely equality with estimate(.., 70.0, ..) —
        // that form would still pass if DEFAULT_BODY_WEIGHT_KG drifted.
        assertEquals(70.0, RunCalories.DEFAULT_BODY_WEIGHT_KG, 0.0)
        assertEquals(700, RunCalories.estimate(10_000.0, null, "run"))
        // Non-physical weights take the same path as unset.
        assertEquals(700, RunCalories.estimate(10_000.0, 0.0, "run"))
        assertEquals(700, RunCalories.estimate(10_000.0, -5.0, "run"))
    }

    @Test
    fun `hike coefficient sits between walk and run`() {
        assertEquals(490, RunCalories.estimate(10_000.0, 70.0, "hike")) // 0.7
        assertNotEquals(
            RunCalories.estimate(10_000.0, 70.0, "walk"),
            RunCalories.estimate(10_000.0, 70.0, "hike"),
        )
    }

    @Test
    fun `negative distance clamps to zero rather than a negative burn`() {
        assertEquals(0, RunCalories.estimate(-5_000.0, 70.0, "run"))
    }
}
