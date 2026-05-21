package com.runapp.watchwear

/// Pure step-baseline math for `Pedometer.stream`.
///
/// `Sensor.TYPE_STEP_COUNTER` emits the CUMULATIVE step count since
/// device boot — never resets, monotonically non-decreasing across
/// hours and days. The watch's recorder only wants the steps for
/// THIS run, so we record the first reading as a baseline and emit
/// `currentReading - baseline` on every subsequent sample.
///
/// Result of [stepsSinceBaseline].
data class StepBaselineResult(
    /// The baseline to remember — either freshly set (first sample)
    /// or unchanged (subsequent samples).
    val baseline: Float,
    /// Steps to emit to the consumer this tick.
    val stepsThisRun: Int,
)

/// Compute the steps-since-baseline emission for a single sensor
/// reading. Called from `Pedometer.stream`'s `onSensorChanged` —
/// callers thread the [baseline] through across calls (null on the
/// first reading; the returned [StepBaselineResult.baseline] on
/// subsequent ones).
///
/// Defensive behaviour:
///   - first-reading baseline = the reading itself, so the
///     emission is 0 (run starts from "no steps yet").
///   - negative delta (baseline somehow ABOVE current — shouldn't
///     happen with TYPE_STEP_COUNTER's monotonic guarantee, but
///     defence-in-depth) is coerced to 0 rather than emitting a
///     negative count, which would render as "−42 steps" on the
///     post-run summary.
///   - Float → Int conversion truncates: 3.7 → 3. Pedometer
///     emissions are always integer counts on real hardware, but
///     the sensor type carries a Float so we guard the cast.
internal fun stepsSinceBaseline(
    currentReading: Float,
    baseline: Float?,
): StepBaselineResult {
    val b = baseline ?: currentReading
    val delta = (currentReading - b).toInt().coerceAtLeast(0)
    return StepBaselineResult(baseline = b, stepsThisRun = delta)
}
