package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Test

/// Step-baseline math for `Pedometer.stream`. `TYPE_STEP_COUNTER`
/// emits the CUMULATIVE count since device boot; we record the first
/// reading as a baseline and emit `current - baseline` so the
/// recorder sees steps for THIS run only.
class PedometerMathTest {

    // ─────────── first reading establishes baseline ───────────

    @Test fun `first reading sets baseline and emits 0`() {
        // The watch boots with, say, 12 345 cumulative steps since
        // last reboot. When the recording starts, the FIRST sample
        // must yield 0 (the runner hasn't taken any steps yet
        // during the run).
        val out = stepsSinceBaseline(currentReading = 12_345f, baseline = null)
        assertEquals(12_345f, out.baseline, 0.0f)
        assertEquals(0, out.stepsThisRun)
    }

    @Test fun `first reading at zero (cold device boot) is also OK`() {
        // Hypothetical: device was rebooted right before the run.
        // First sample is 0. The baseline becomes 0 and emission
        // is 0.
        val out = stepsSinceBaseline(currentReading = 0f, baseline = null)
        assertEquals(0f, out.baseline, 0.0f)
        assertEquals(0, out.stepsThisRun)
    }

    // ─────────── subsequent readings delta correctly ───────────

    @Test fun `subsequent reading emits delta from baseline`() {
        // Run-time scenario: baseline is set to 1000 (where the
        // user was when they hit Start). 200 steps later, sensor
        // reports 1200. Emission should be 200.
        val out = stepsSinceBaseline(currentReading = 1200f, baseline = 1000f)
        assertEquals(1000f, out.baseline, 0.0f,
        )
        assertEquals(200, out.stepsThisRun)
    }

    @Test fun `baseline is NOT updated on subsequent readings`() {
        // Critical regression guard: if a sloppy refactor reset the
        // baseline on every sample, the emission would always be 0
        // and the runner would see zero steps no matter how far
        // they ran.
        val out = stepsSinceBaseline(currentReading = 5_000f, baseline = 1000f)
        assertEquals(
            "Baseline must STAY at 1000 — re-setting it would zero out every emission.",
            1000f, out.baseline, 0.0f,
        )
    }

    @Test fun `large-magnitude delta (long run) works`() {
        // 30 000 steps is a marathon. Confirm Float→Int truncation
        // doesn't lose precision at that scale.
        val out = stepsSinceBaseline(currentReading = 31_234f, baseline = 1_234f)
        assertEquals(30_000, out.stepsThisRun)
    }

    // ─────────── defensive: negative deltas coerced ───────────

    @Test fun `negative delta coerces to 0 (defence in depth)`() {
        // TYPE_STEP_COUNTER's contract is monotonic non-decreasing,
        // but a corrupt sensor sample / kernel quirk could
        // theoretically emit a lower value than the baseline. The
        // post-run table must NEVER show "−42 steps".
        val out = stepsSinceBaseline(currentReading = 500f, baseline = 1000f)
        assertEquals(
            "Negative delta would render as a UI bug — pin the coerce-to-zero.",
            0, out.stepsThisRun,
        )
    }

    @Test fun `baseline at 0 and current at 0 yields 0`() {
        val out = stepsSinceBaseline(currentReading = 0f, baseline = 0f)
        assertEquals(0, out.stepsThisRun)
    }

    // ─────────── Float to Int truncation ───────────

    @Test fun `fractional reading truncates (3_7 to 3)`() {
        // Sensor.TYPE_STEP_COUNTER carries a Float although real
        // hardware always emits whole-number values. Defensive:
        // pin Float→Int truncation rather than round-half-up.
        val out = stepsSinceBaseline(currentReading = 1003.7f, baseline = 1000f)
        assertEquals(3, out.stepsThisRun)
    }

    // ─────────── threaded sequence (realistic mid-run) ───────────

    @Test fun `realistic recording sequence threads baseline forward`() {
        // Walks through a recording: cold start → baseline set →
        // five subsequent readings as the runner accumulates steps.
        // Pins that the production loop's `baseline = result.baseline`
        // pattern produces the right cumulative-for-this-run series.
        var baseline: Float? = null
        val emissions = mutableListOf<Int>()
        for (reading in listOf(1000f, 1100f, 1250f, 1300f, 1500f, 2000f)) {
            val result = stepsSinceBaseline(reading, baseline)
            baseline = result.baseline
            emissions += result.stepsThisRun
        }
        // First emission is 0 (baseline-set). Subsequent are the
        // running deltas: 100, 250, 300, 500, 1000.
        assertEquals(listOf(0, 100, 250, 300, 500, 1000), emissions)
        // Baseline never moves after the first sample.
        assertEquals(1000f, baseline)
    }
}
