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

    /// Feed the next altitude sample (metres). The first sample only seeds the
    /// reference; later samples accumulate once they clear the deadband.
    pub fn push(&mut self, alt_m: f32) {
        let Some(reference) = self.reference else {
            self.reference = Some(alt_m);
            return;
        };
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
            acc.push(alt);
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn climb_then_descent_accumulates_both() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0);
        for step in 1..=10 {
            acc.push((step * 10) as f32);
        }
        for step in (0..=9).rev() {
            acc.push((step * 10) as f32);
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
            acc.push(step as f32);
        }
        assert!((acc.gain_m() - 100.0).abs() <= DEADBAND_M);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn reading_bundles_altitude_with_current_totals() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0);
        acc.push(50.0);
        acc.push(30.0);
        let r = acc.reading(30.0);
        assert_eq!(r.alt_m, 30.0);
        assert!((r.gain_m - 50.0).abs() < 1e-3);
        assert!((r.loss_m - 20.0).abs() < 1e-3);
    }

    #[test]
    fn reset_clears_totals_and_reference() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0);
        acc.push(50.0);
        acc.reset();
        assert_eq!(acc.gain_m(), 0.0);
        acc.push(1000.0);
        acc.push(1050.0);
        assert!((acc.gain_m() - 50.0).abs() < 1e-3);
    }
}
