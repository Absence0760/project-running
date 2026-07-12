//! Barometric altitude + cumulative vertical for the vert-first ultra metrics.
//!
//! Two pure pieces the `app/` baro task (BMP581, decisions.md § 90) and the
//! recording state machine consume: [`altitude_m`] turns a pressure reading
//! into an altitude, and [`VertAccumulator`] reduces a stream of altitudes
//! into total ascent + descent while a deadband keeps sensor noise out of the
//! totals. Both are `f32` to match [`crate::fix::Fix::alt_m`].

/// Sea-level standard temperature over the tropospheric lapse rate
/// (288.15 K / 0.0065 K/m) — the scale factor in the international
/// barometric formula.
const BARO_SCALE_M: f32 = 44330.0;

/// R*·L / (g0·M) for the ISA troposphere — the pressure-ratio exponent of the
/// international barometric formula.
const BARO_EXPONENT: f32 = 0.190295;

/// ICAO standard sea-level pressure, the default reference when no local QNH
/// calibration is available.
pub const STANDARD_SEA_LEVEL_PA: f32 = 101_325.0;

/// Altitude in metres from a pressure reading (Pascals) against a sea-level
/// reference pressure, via `alt = 44330 * (1 - (p/p0)^0.190295)`. At
/// `pressure_pa == sea_level_pa` the result is exactly 0 m.
pub fn altitude_m(pressure_pa: f32, sea_level_pa: f32) -> f32 {
    BARO_SCALE_M * (1.0 - libm::powf(pressure_pa / sea_level_pa, BARO_EXPONENT))
}

/// A barometric elevation snapshot the `app/` baro task publishes for the
/// face and phone link: the latest altitude plus the run's cumulative ascent
/// and descent. All `f32` to match [`crate::fix::Fix::alt_m`] and the
/// [`VertAccumulator`] totals it is assembled from.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reading {
    pub alt_m: f32,
    pub gain_m: f32,
    pub loss_m: f32,
}

/// Movement smaller than this from the last committed altitude is treated as
/// barometric noise rather than real vertical and left uncommitted. Sized to
/// swallow BMP581 short-term noise and the metre-scale oscillation a level
/// stretch produces, below the vertical of a real running step.
pub const DEADBAND_M: f32 = 3.0;

/// Cumulative total ascent + descent over a stream of altitude samples.
///
/// The reference altitude only advances when the run of movement since the
/// last commit crosses [`DEADBAND_M`]; on a crossing the whole delta is
/// committed and the reference jumps to that sample. Anchoring the deadband to
/// the last *committed* altitude (not the previous sample) is what lets a slow
/// real climb of many sub-threshold steps still fully accumulate while jitter
/// around a level commits nothing.
///
/// Accumulation is gated on the runner actually **moving** ([`push`](Self::push)'s
/// `moving` flag). A barometer can't tell a slow real climb from slow pressure
/// drift (a weather front / diurnal thermal low banks tens of metres of phantom
/// vert over an hour), but while the runner is *stationary* any altitude change
/// is by definition drift, not climb — so a stopped sample only re-bases the
/// reference and banks nothing. This kills the dominant phantom-vert source
/// (resting at aid, sleeping, waiting out weather on a col). Drift *while moving*
/// on flat ground is a residual that needs GPS-baro fusion — deliberately out of
/// scope here.
pub struct VertAccumulator {
    reference: Option<f32>,
    gain_m: f32,
    loss_m: f32,
}

impl Default for VertAccumulator {
    fn default() -> Self {
        Self::new()
    }
}

impl VertAccumulator {
    pub const fn new() -> Self {
        Self {
            reference: None,
            gain_m: 0.0,
            loss_m: 0.0,
        }
    }

    /// Feed the next altitude sample (metres) and whether the runner is moving.
    /// The first sample only seeds the reference; while moving, later samples
    /// accumulate once they clear the deadband. While **not** moving, the sample
    /// only re-bases the reference (banking nothing), so barometric drift during
    /// a stop is neither counted now nor dumped as a phantom delta on resume.
    pub fn push(&mut self, alt_m: f32, moving: bool) {
        let Some(reference) = self.reference else {
            self.reference = Some(alt_m);
            return;
        };
        if !moving {
            // Stationary: any change is drift, not climb. Track it as the new
            // baseline so a later real climb is measured from here, not from a
            // pre-drift reference that would bank the drift as gain/loss.
            self.reference = Some(alt_m);
            return;
        }
        let delta = alt_m - reference;
        if delta >= DEADBAND_M {
            self.gain_m += delta;
            self.reference = Some(alt_m);
        } else if delta <= -DEADBAND_M {
            self.loss_m += -delta;
            self.reference = Some(alt_m);
        }
    }

    pub fn gain_m(&self) -> f32 {
        self.gain_m
    }

    pub fn loss_m(&self) -> f32 {
        self.loss_m
    }

    /// Bundle the current cumulative totals with `alt_m` into a [`Reading`]
    /// for publication to the face and phone link.
    pub fn reading(&self, alt_m: f32) -> Reading {
        Reading {
            alt_m,
            gain_m: self.gain_m,
            loss_m: self.loss_m,
        }
    }

    pub fn reset(&mut self) {
        *self = Self::new();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sea_level_pressure_is_zero_altitude() {
        assert!(altitude_m(STANDARD_SEA_LEVEL_PA, STANDARD_SEA_LEVEL_PA).abs() < 1e-3);
    }

    #[test]
    fn lower_pressure_is_positive_altitude() {
        // 90000 Pa against standard sea level is ~988.6 m of standard atmosphere.
        assert!((altitude_m(90_000.0, STANDARD_SEA_LEVEL_PA) - 988.6).abs() < 1.0);
        // 84556 Pa is the ISA pressure at ~1500 m.
        assert!((altitude_m(84_556.0, STANDARD_SEA_LEVEL_PA) - 1500.0).abs() < 1.0);
    }

    #[test]
    fn deadband_rejects_jitter_around_a_level() {
        let mut acc = VertAccumulator::new();
        for alt in [100.0, 101.5, 98.5, 102.0, 99.0, 100.5, 98.0, 100.0] {
            acc.push(alt, true);
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn climb_then_descent_accumulates_both() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true);
        for step in 1..=10 {
            acc.push((step * 10) as f32, true);
        }
        for step in (0..=9).rev() {
            acc.push((step * 10) as f32, true);
        }
        assert!((acc.gain_m() - 100.0).abs() < 1e-3);
        assert!((acc.loss_m() - 100.0).abs() < 1e-3);
    }

    #[test]
    fn slow_sub_threshold_climb_still_fully_accumulates() {
        // The classic deadband-reference bug: 1 m steps never individually
        // exceed a 3 m deadband, yet the total climb must not be lost.
        let mut acc = VertAccumulator::new();
        for step in 0..=100 {
            acc.push(step as f32, true);
        }
        assert!((acc.gain_m() - 100.0).abs() <= DEADBAND_M);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn stationary_drift_banks_nothing() {
        // A weather front drops pressure while the runner rests: apparent
        // altitude ramps ~100 m monotonically, but nothing moves. With
        // moving=false, none of it is banked as gain, and re-basing means the
        // drift doesn't dump as a phantom delta once the runner resumes.
        let mut acc = VertAccumulator::new();
        acc.push(2500.0, true);
        for step in 1..=100 {
            acc.push(2500.0 + step as f32, false); // stopped, pressure drifting up
        }
        assert_eq!(acc.gain_m(), 0.0, "drift while stopped is not climb");
        assert_eq!(acc.loss_m(), 0.0);
        // Resuming at the drifted altitude banks nothing retroactively: a small
        // real move from here accrues normally, measured from the drifted base.
        acc.push(2600.0 + DEADBAND_M, true);
        assert!((acc.gain_m() - DEADBAND_M).abs() < 1e-3);
    }

    #[test]
    fn a_real_climb_while_moving_is_unaffected_by_the_gate() {
        // Same altitude profile as a climb, but flagged moving: it must still
        // fully accumulate — the gate only suppresses the stationary case.
        let mut acc = VertAccumulator::new();
        acc.push(1000.0, true);
        for step in 1..=50 {
            acc.push(1000.0 + step as f32, true);
        }
        assert!((acc.gain_m() - 50.0).abs() <= DEADBAND_M);
    }

    #[test]
    fn drift_down_while_stopped_then_descent_while_moving() {
        // Pressure rises while resting (apparent altitude falls) — no loss
        // banked — then a genuine moving descent from the re-based reference is.
        let mut acc = VertAccumulator::new();
        acc.push(3000.0, true);
        for step in 1..=40 {
            acc.push(3000.0 - step as f32, false); // stopped, apparent altitude falling
        }
        assert_eq!(acc.loss_m(), 0.0);
        acc.push(2960.0 - 10.0, true);
        assert!((acc.loss_m() - 10.0).abs() < 1e-3);
        assert_eq!(acc.gain_m(), 0.0);
    }

    #[test]
    fn reading_bundles_altitude_with_current_totals() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true);
        acc.push(50.0, true);
        acc.push(30.0, true);
        let r = acc.reading(30.0);
        assert_eq!(r.alt_m, 30.0);
        assert!((r.gain_m - 50.0).abs() < 1e-3);
        assert!((r.loss_m - 20.0).abs() < 1e-3);
    }

    #[test]
    fn reset_clears_totals_and_reference() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true);
        acc.push(50.0, true);
        acc.reset();
        assert_eq!(acc.gain_m(), 0.0);
        acc.push(1000.0, true);
        acc.push(1050.0, true);
        assert!((acc.gain_m() - 50.0).abs() < 1e-3);
    }
}
