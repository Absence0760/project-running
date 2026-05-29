package com.runapp.watchwear

import com.runapp.watchwear.recording.RunCalories
import org.junit.Assert.assertEquals
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
}
