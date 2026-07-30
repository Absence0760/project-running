//! Barometric altitude + cumulative vertical for the vert-first ultra metrics.
//!
//! Two pure pieces the `app/` baro task (BMP581, decisions.md § 90) and the
//! recording state machine consume: [`altitude_m`] turns a pressure reading
//! into an altitude, and [`VertAccumulator`] reduces a stream of altitudes
//! into total ascent + descent while a deadband keeps sensor noise out of the
//! totals. Both are `f32` to match [`crate::fix::Fix::alt_m`].
//!
//! A barometer cannot tell a slow real climb from slow barometric drift (a
//! weather front moving sea-level pressure) while a runner moves over flat
//! ground, so the deadband alone still banks tens of metres of phantom gain and
//! the absolute altitude drifts. [`VertAccumulator::push`] takes an optional
//! corroborating GPS altitude — noisy but never weather-biased — and runs a
//! complementary filter: baro stays the high-frequency signal for step-to-step
//! vert, while a slowly-slewed bias pulls the reference toward GPS so a
//! sustained baro-vs-GPS divergence (drift) is subtracted before it can bank as
//! gain/loss. Absent or implausible GPS falls back to the baro-only deadband.

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

/// Smallest altitude move worth waking every consumer of a [`Reading`] for.
///
/// The decimetre is the finest quantum anything downstream can *represent* —
/// the phone-link frame prints `{:.1}`, a stored track point's elevation field
/// is decimetres, and the face is coarser still at whole metres — so no
/// consumer can tell a smaller step from no step at all. It sits an order of
/// magnitude above the BMP581's own noise at the configured 16x oversampling
/// plus coefficient-7 IIR (single-digit centimetres of altitude), which is what
/// makes it enough to silence a resting wrist, and a thirtieth of
/// [`DEADBAND_M`], so it can never withhold a change the accumulator banks as
/// vert.
///
/// Deliberately *not* the face's whole-metre rendering quantum: the recorder
/// feeds this altitude to the live grade-adjusted-pace estimator, which reads a
/// grade off ~5 m segments, so a metre-coarse altitude would swing a segment's
/// grade by tens of percent and make the GAP row bounce on a climb.
pub const PUBLISH_STEP_M: f32 = 0.1;

/// Whether a freshly computed [`Reading`] is worth publishing on the elevation
/// watch, given the last one published.
///
/// The barometer is sampled at 1 Hz and `embassy_sync::Watch::send` wakes every
/// receiver whether or not the value moved, so an unconditional publish makes a
/// present BMP581 a free-running 1 Hz waker: the screen task waits on that
/// watch's `changed()` and re-renders the whole face once a second forever —
/// exactly the standing reason to wake the CPU that hardware VCOM and the
/// event-driven screen task removed from the display.
///
/// A quantised gate is what makes this work at all: a `Reading` is three `f32`s
/// off a noisy sensor, so consecutive samples on a motionless wrist are almost
/// never bit-identical and a plain `!=` would suppress nothing. Altitude must
/// move a whole [`PUBLISH_STEP_M`] from the last *published* value — anchored
/// there rather than to the previous sample, the same trick
/// [`VertAccumulator`]'s deadband uses, so a slow real climb of sub-threshold
/// steps still publishes once per step it gains and loses nothing. Either
/// cumulative total moving publishes at once; they only move when
/// [`VertAccumulator::push`] commits real vertical past [`DEADBAND_M`].
pub fn should_publish(last: Option<Reading>, next: Reading) -> bool {
    let Some(prev) = last else { return true };
    prev.gain_m != next.gain_m
        || prev.loss_m != next.loss_m
        || libm::fabsf(next.alt_m - prev.alt_m) >= PUBLISH_STEP_M
}

/// Per-sample fraction the GPS reference pull slews the settled baro-vs-GPS
/// bias by — the complementary filter's crossover. A first-order low-pass at
/// this rate attenuates white GPS noise to `sqrt(GPS_PULL / (2 - GPS_PULL)) ≈
/// 0.07` of its input, so a ±15 m per-sample GPS jitter lands as a sub-metre
/// wobble on the bias, far inside [`DEADBAND_M`] — GPS noise cannot bank vert.
/// Yet it is fast enough that a real weather drift (a brisk ~1–2 hPa/h ≈
/// 0.02 m/s of apparent altitude) is tracked with a steady-state lag of
/// `drift_rate / GPS_PULL` (~2 m here) that stays under the deadband, so the
/// drift is corrected rather than banked. Sized for the ~1 Hz GPS + baro
/// cadence; a single stray sample only moves the bias by 1 %.
const GPS_PULL: f32 = 0.01;

/// Plausible GPS altitudes averaged into the initial bias seed before the
/// complementary filter engages. Vert stays pure baro-only over this window
/// (so it is never worse than baro-only and a real climb still banks), while
/// the running mean drives the seed's √N noise down — a low-noise seed means
/// the filter engages with no convergence transient to bank as phantom vert.
/// A conservative on-device starting point; the real receiver's noise sets the
/// final value.
const SEED_SAMPLES: u16 = 30;

/// GPS altitude outside this terrestrial window (or non-finite) is treated as
/// absent, so a spurious receiver altitude cannot wrench the bias.
pub const GPS_ALT_MIN_M: f32 = -500.0;
pub const GPS_ALT_MAX_M: f32 = 9000.0;

/// A GPS fix older than this cannot back a manual re-zero. Idle fix
/// publication is de-rated to just under the face's 5 s staleness budget (see
/// the gps task), so a healthy idle signal always passes; anything older is
/// the signal-lost case the re-zero must refuse rather than snap to a stale
/// altitude.
pub const REZERO_MAX_FIX_AGE_S: u32 = 5;

/// The GPS altitude a manual re-zero may re-base against, or `None` when
/// there is nothing honest to re-base to: no fix yet, a fix older than
/// [`REZERO_MAX_FIX_AGE_S`], a fix without an altitude (RMC-only), or an
/// implausible altitude.
pub fn rezero_reference(fix: Option<&crate::fix::Fix>, now_s: u32) -> Option<f32> {
    let fix = fix.filter(|f| now_s.saturating_sub(f.uptime_s) <= REZERO_MAX_FIX_AGE_S)?;
    plausible_gps(fix.alt_m)
}

/// The outcome of a manual QNH re-zero request, published for the face's
/// transient banner — honest about a refusal, never a silent no-op.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RezeroStatus {
    /// The altitude reference snapped to this GPS altitude (metres).
    Applied(f32),
    /// No fresh, plausible GPS altitude to re-base against; nothing changed.
    NoGps,
    /// No barometer streaming (absent sensor, or no sample yet); nothing to
    /// re-base.
    NoBaro,
}

/// How long the re-zero feedback banner stays on screen — the same dwell as
/// the on-run alert banners ([`crate::alerts::ALERT_TTL_S`]).
pub const REZERO_BANNER_TTL_S: u32 = 8;

/// The 2x banner text for a re-zero outcome, sized like [`crate::alerts::Banner`]
/// so it fits the face doubled.
pub type RezeroBanner = heapless::String<10>;

pub fn rezero_banner(status: RezeroStatus) -> RezeroBanner {
    use core::fmt::Write;
    let mut b = RezeroBanner::new();
    let _ = match status {
        // The plausibility window bounds the altitude at -500..=9000, so the
        // rounded figure always fits the 10-cell banner.
        RezeroStatus::Applied(alt_m) => write!(b, "SET {}M", libm::roundf(alt_m) as i32),
        RezeroStatus::NoGps => write!(b, "NO GPS FIX"),
        RezeroStatus::NoBaro => write!(b, "NO BARO"),
    };
    b
}

/// A receiver altitude worth deriving anything from, or `None`. Shared with
/// [`crate::record::Recorder`]'s altitude-fed surfaces so the two cannot
/// disagree about whether the same number is trustworthy.
pub fn plausible_gps(gps_alt_m: Option<f32>) -> Option<f32> {
    gps_alt_m.filter(|a| a.is_finite() && (GPS_ALT_MIN_M..=GPS_ALT_MAX_M).contains(a))
}

/// The complementary filter's estimate of the `baro - GPS` bias, and its
/// warm-up. Vert and the published altitude subtract [`Bias::offset`] from the
/// raw baro reading.
enum Bias {
    /// No plausible GPS has paired yet: pure baro-only, `offset` is 0.
    None,
    /// Averaging the first [`SEED_SAMPLES`] `baro - GPS` divergences into a
    /// low-noise seed. `offset` stays 0 (baro-only) during collection, so the
    /// filter's convergence is never banked as vert and a real climb over the
    /// window still accumulates exactly as baro-only would.
    Seeding { sum: f32, count: u16 },
    /// Engaged: the slow low-pass of `baro - GPS` the filter subtracts from
    /// baro for both vert and the auto-QNH-corrected altitude.
    Tracking(f32),
}

impl Bias {
    fn offset(&self) -> f32 {
        match self {
            Bias::Tracking(bias) => *bias,
            _ => 0.0,
        }
    }
}

/// Cumulative total ascent + descent over a stream of altitude samples.
///
/// The reference altitude only advances when the run of movement since the
/// last commit crosses [`DEADBAND_M`]; on a crossing the whole delta is
/// committed and the reference jumps to that sample. Anchoring the deadband to
/// the last *committed* altitude (not the previous sample) is what lets a slow
/// real climb of many sub-threshold steps still fully accumulate while jitter
/// around a level commits nothing.
///
/// `bias` is a GPS-baro complementary filter: baro stays the high-frequency
/// signal for step-to-step vert, while a slowly-slewed [`Bias`] pulls the
/// reference toward the unbiased (but noisy) GPS altitude. A sustained
/// baro-vs-GPS divergence is weather drift, not climb, so subtracting the bias
/// keeps that drift out of the totals; a real climb (baro and GPS rising
/// together) leaves the bias untouched and banks in full. The same bias
/// auto-corrects the absolute altitude reference off GPS — a weather front no
/// longer permanently offsets altitude even with no phone to push a QNH
/// calibration. With no GPS the filter never engages and behaviour is exactly
/// baro-only.
pub struct VertAccumulator {
    reference: Option<f32>,
    gain_m: f32,
    loss_m: f32,
    bias: Bias,
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
            bias: Bias::None,
        }
    }

    /// Feed the next barometric altitude sample (metres) with an optional
    /// corroborating GPS altitude, and return the bias-corrected altitude that
    /// backs the published absolute-altitude reading.
    ///
    /// Vert is taken from `baro - bias`, where `bias` is the complementary
    /// filter's slow, GPS-referenced estimate of the barometer's weather bias:
    /// a sustained drift is subtracted before it can bank as gain/loss (drift
    /// correction is not climb), while a real climb (baro and GPS rising
    /// together) leaves the bias untouched and accumulates in full. Per-sample
    /// GPS noise is averaged out — first into the running-mean seed, then by
    /// the slow [`GPS_PULL`] slew — so it never injects vert. Passing `None`
    /// (or an implausible GPS altitude) freezes the bias, so vert degrades to
    /// the baro-only deadband behaviour exactly.
    ///
    /// `moving` gates accumulation on the runner actually moving: while stopped,
    /// any altitude change is drift, not climb, so the reference only re-bases
    /// and banks nothing. This is the GPS-independent safety — it holds even
    /// with no GPS altitude to drive the complementary bias (aid station, sleep,
    /// waiting out weather on a col) — complementing the GPS bias that handles
    /// drift *while moving* on flat ground.
    pub fn push(&mut self, baro_alt_m: f32, moving: bool, gps_alt_m: Option<f32>) -> f32 {
        if let Some(seed) = self.advance_bias(baro_alt_m, gps_alt_m) {
            // Engaging the seed shifts the altitude frame from raw baro to
            // GPS-corrected (auto-QNH) in one step. Re-frame the deadband anchor
            // by the same offset so that one-time step is never banked as vert,
            // while a real climb pending since the last commit is preserved.
            if let Some(reference) = self.reference {
                self.reference = Some(reference - seed);
            }
        }
        let corrected = baro_alt_m - self.bias.offset();
        match self.reference {
            None => self.reference = Some(corrected),
            Some(reference) => {
                if !moving {
                    // Stationary: re-base to the corrected altitude, bank nothing
                    // — drift while stopped is not climb, and never dumps as a
                    // phantom delta once the runner resumes.
                    self.reference = Some(corrected);
                } else {
                    let delta = corrected - reference;
                    if delta >= DEADBAND_M {
                        self.gain_m += delta;
                        self.reference = Some(corrected);
                    } else if delta <= -DEADBAND_M {
                        self.loss_m += -delta;
                        self.reference = Some(corrected);
                    }
                }
            }
        }
        corrected
    }

    /// Advance the bias with the latest plausible GPS altitude. Returns the seed
    /// offset on the single sample where the running mean finishes and the
    /// filter engages (so the caller re-frames the deadband anchor by it);
    /// `None` on every other sample, including the slow ongoing slew.
    fn advance_bias(&mut self, baro_alt_m: f32, gps_alt_m: Option<f32>) -> Option<f32> {
        let gps = plausible_gps(gps_alt_m)?;
        let divergence = baro_alt_m - gps;
        match &mut self.bias {
            Bias::None => {
                self.bias = Bias::Seeding {
                    sum: divergence,
                    count: 1,
                };
                None
            }
            Bias::Seeding { sum, count } => {
                *sum += divergence;
                *count += 1;
                if *count >= SEED_SAMPLES {
                    let seed = *sum / f32::from(*count);
                    self.bias = Bias::Tracking(seed);
                    return Some(seed);
                }
                None
            }
            Bias::Tracking(bias) => {
                *bias += GPS_PULL * (divergence - *bias);
                None
            }
        }
    }

    /// Manual QNH re-zero: snap the complementary-filter bias so the corrected
    /// altitude reads exactly `gps_alt_m` right now, instead of waiting out the
    /// slow [`GPS_PULL`] convergence. Returns the snapped altitude, or `None`
    /// (a no-op, nothing changed) when the GPS altitude is implausible.
    ///
    /// Snapping the bias — rather than recomputing the QNH pressure reference —
    /// keeps the correction in the frame the filter already tracks: a new
    /// sea-level reference would shift the raw baro altitude and the filter
    /// would slowly slew the bias to cancel it again, nullifying the
    /// calibration. The deadband anchor is re-framed by the same shift (the
    /// seed-engage pattern in [`Self::push`]) so the one-time reference step is
    /// never banked as vert, while a real climb pending since the last commit
    /// is preserved. A snapped bias is `Tracking`, so the ongoing filter
    /// continues from it with no convergence transient — and any in-progress
    /// seed is superseded by the runner's explicit calibration.
    pub fn rezero(&mut self, baro_alt_m: f32, gps_alt_m: Option<f32>) -> Option<f32> {
        let gps = plausible_gps(gps_alt_m)?;
        let snapped = baro_alt_m - gps;
        let shift = snapped - self.bias.offset();
        if let Some(reference) = self.reference {
            self.reference = Some(reference - shift);
        }
        self.bias = Bias::Tracking(snapped);
        Some(gps)
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
            acc.push(alt, true, None);
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn climb_then_descent_accumulates_both() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true, None);
        for step in 1..=10 {
            acc.push((step * 10) as f32, true, None);
        }
        for step in (0..=9).rev() {
            acc.push((step * 10) as f32, true, None);
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
            acc.push(step as f32, true, None);
        }
        assert!((acc.gain_m() - 100.0).abs() <= DEADBAND_M);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn reading_bundles_altitude_with_current_totals() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true, None);
        acc.push(50.0, true, None);
        acc.push(30.0, true, None);
        let r = acc.reading(30.0);
        assert_eq!(r.alt_m, 30.0);
        assert!((r.gain_m - 50.0).abs() < 1e-3);
        assert!((r.loss_m - 20.0).abs() < 1e-3);
    }

    #[test]
    fn reset_clears_totals_and_reference() {
        let mut acc = VertAccumulator::new();
        acc.push(0.0, true, None);
        acc.push(50.0, true, None);
        acc.reset();
        assert_eq!(acc.gain_m(), 0.0);
        acc.push(1000.0, true, None);
        acc.push(1050.0, true, None);
        assert!((acc.gain_m() - 50.0).abs() < 1e-3);
    }

    #[test]
    fn push_returns_the_bias_corrected_altitude() {
        // No GPS ever paired: the returned altitude is the raw baro reading.
        let mut baro_only = VertAccumulator::new();
        assert!((baro_only.push(1620.0, true, None) - 1620.0).abs() < 1e-3);

        // Baro reads 14 m high vs a flat GPS: once the seed window closes the
        // filter engages and the returned altitude tracks GPS — the auto-QNH
        // correction that needs no phone.
        let mut acc = VertAccumulator::new();
        let mut corrected = 0.0;
        for _ in 0..SEED_SAMPLES + 1 {
            corrected = acc.push(1624.0, true, Some(1610.0));
        }
        assert!((corrected - 1610.0).abs() < 1e-3, "auto-QNH: {corrected}");
    }

    // (4) Absent GPS reproduces the baro-only deadband totals exactly.
    #[test]
    fn absent_gps_falls_back_to_baro_only_deadband_exactly() {
        let mut acc = VertAccumulator::new();
        for alt in [100.0, 101.0, 102.0, 103.0, 104.0, 105.0] {
            acc.push(alt, true, None);
        }
        // reference 100 → 103 crosses the 3 m band once, banking 3 m; the 104/105
        // remainder stays sub-threshold. Pure baro-only behaviour.
        assert!((acc.gain_m() - 3.0).abs() < 1e-3);
        assert_eq!(acc.loss_m(), 0.0);
    }

    /// A slow flat-ground barometric drift of `total` metres over `samples`
    /// ticks; `gps` supplies the corroborating altitude per tick.
    fn drift_gain(total: f32, samples: usize, gps: impl Fn(usize) -> Option<f32>) -> f32 {
        let base = 100.0;
        let mut acc = VertAccumulator::new();
        for n in 0..samples {
            let baro = base + total * (n as f32) / (samples as f32);
            acc.push(baro, true, gps(n));
        }
        acc.gain_m()
    }

    // (1) Drift while moving on flat ground WITH corroborating flat GPS banks
    // ~no phantom vert, where the baro-only case banks the whole drift.
    #[test]
    fn drift_with_flat_gps_banks_no_phantom_vert() {
        let baro_only = drift_gain(30.0, 1500, |_| None);
        assert!(
            baro_only > 20.0,
            "baro-only must bank the drift: {baro_only}"
        );

        let corroborated = drift_gain(30.0, 1500, |_| Some(100.0));
        assert_eq!(
            corroborated, 0.0,
            "flat GPS must cancel the drift, not bank it: {corroborated}"
        );
    }

    // (2) A real climb with corroborating rising GPS still fully accumulates —
    // the filter must not suppress genuine gain.
    #[test]
    fn real_climb_with_rising_gps_still_fully_accumulates() {
        let mut acc = VertAccumulator::new();
        // GPS carries a constant +5 m offset and rises in lockstep with baro,
        // so baro - GPS stays constant: the bias never moves, gain is preserved.
        for step in 0..=100 {
            let baro = step as f32;
            acc.push(baro, true, Some(baro + 5.0));
        }
        assert!(
            (acc.gain_m() - 100.0).abs() <= DEADBAND_M,
            "rising GPS must not suppress a real climb: {}",
            acc.gain_m()
        );
        assert_eq!(acc.loss_m(), 0.0);
    }

    // (3) GPS per-sample noise around a flat mean injects no spurious vert.
    #[test]
    fn gps_noise_around_flat_mean_injects_no_vert() {
        let mut acc = VertAccumulator::new();
        for n in 0..600u32 {
            // Deterministic bounded ±15 m jitter with ~zero mean.
            let noise = ((n * 7 % 31) as f32) - 15.0;
            acc.push(200.0, true, Some(200.0 + noise));
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    // Seeding the bias off a large initial QNH offset must re-anchor the
    // deadband, not bank the offset as a descent.
    #[test]
    fn gps_seed_reanchors_without_banking() {
        let mut acc = VertAccumulator::new();
        // Baro reads 1624 m (standard-QNH altitude) but true GPS is 1610 m.
        for _ in 0..50 {
            acc.push(1624.0, true, Some(1610.0));
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    // An implausible or non-finite GPS altitude is ignored, so it can neither
    // wrench the bias nor suppress a real climb read off the baro.
    #[test]
    fn implausible_gps_is_ignored() {
        let mut acc = VertAccumulator::new();
        for step in 0..=100 {
            let bad = if step % 2 == 0 {
                Some(f32::NAN)
            } else {
                Some(1.0e9)
            };
            acc.push(step as f32, true, bad);
        }
        assert!((acc.gain_m() - 100.0).abs() <= DEADBAND_M);
        assert_eq!(acc.loss_m(), 0.0);
    }

    // GPS dropping out mid-run freezes the bias and degrades to baro-only (never
    // worse than today); when GPS returns the slow pull resumes without a jump.
    #[test]
    fn gps_signal_loss_freezes_bias_then_recovers() {
        let mut acc = VertAccumulator::new();
        // Establish a flat, corroborated baseline.
        for _ in 0..200 {
            acc.push(300.0, true, Some(300.0));
        }
        assert_eq!(acc.gain_m(), 0.0);
        // Signal lost: a real climb read off the baro still accumulates.
        for step in 1..=20 {
            acc.push(300.0 + step as f32, true, None);
        }
        assert!((acc.gain_m() - 20.0).abs() <= DEADBAND_M);
        // Signal back, now flat again: no phantom vert on recovery.
        let after_recovery_start = acc.gain_m();
        for _ in 0..200 {
            acc.push(320.0, true, Some(320.0));
        }
        assert_eq!(acc.gain_m(), after_recovery_start);
        assert_eq!(acc.loss_m(), 0.0);
    }

    // --- Manual QNH re-zero: the phone-free, instant bias snap ---

    #[test]
    fn rezero_snaps_the_published_altitude_instantly() {
        // Baro-only frame reads 1624 m but GPS says 1610 m: one re-zero snaps
        // the corrected altitude to GPS with no seed window or slow pull.
        let mut acc = VertAccumulator::new();
        acc.push(1624.0, true, None);
        assert_eq!(acc.rezero(1624.0, Some(1610.0)), Some(1610.0));
        assert!((acc.push(1624.0, true, None) - 1610.0).abs() < 1e-3);
    }

    #[test]
    fn rezero_banks_no_vert_and_preserves_a_pending_climb() {
        let mut acc = VertAccumulator::new();
        acc.push(100.0, true, None);
        // 2 m of real climb pending, below the 3 m deadband.
        acc.push(102.0, true, None);
        acc.rezero(102.0, Some(88.0));
        assert_eq!(acc.gain_m(), 0.0, "the snap itself must bank nothing");
        assert_eq!(acc.loss_m(), 0.0);
        // Another 2 m of climb joins the pending 2 m and commits the full 4 m
        // in the snapped frame — the anchor was re-framed, not reset.
        acc.push(104.0, true, None);
        assert!((acc.gain_m() - 4.0).abs() < 1e-3);
    }

    #[test]
    fn rezero_with_implausible_gps_is_a_refused_no_op() {
        let mut acc = VertAccumulator::new();
        acc.push(500.0, true, None);
        for bad in [None, Some(f32::NAN), Some(1.0e9), Some(-2000.0)] {
            assert_eq!(acc.rezero(500.0, bad), None);
        }
        // Nothing changed: the altitude frame is still raw baro.
        assert!((acc.push(500.0, true, None) - 500.0).abs() < 1e-3);
    }

    #[test]
    fn rezero_engages_tracking_so_later_drift_is_still_corrected() {
        // After a snap the filter must keep tracking from the snapped bias: a
        // flat-GPS baro drift is corrected, not banked, with no seed transient.
        let mut acc = VertAccumulator::new();
        acc.push(100.0, true, None);
        acc.rezero(100.0, Some(100.0));
        for n in 0..1500 {
            let baro = 100.0 + 30.0 * (n as f32) / 1500.0;
            acc.push(baro, true, Some(100.0));
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    #[test]
    fn rezero_supersedes_an_in_progress_seed() {
        let mut acc = VertAccumulator::new();
        // Part-way through the seed window (baro reads 20 m high)...
        for _ in 0..10 {
            acc.push(1020.0, true, Some(1000.0));
        }
        // ...the runner snaps to a known-good fix. The seed must not later
        // engage over the explicit calibration.
        acc.rezero(1020.0, Some(1000.0));
        for _ in 0..100 {
            let corrected = acc.push(1020.0, true, Some(1000.0));
            assert!((corrected - 1000.0).abs() < 1e-3);
        }
        assert_eq!(acc.gain_m(), 0.0);
        assert_eq!(acc.loss_m(), 0.0);
    }

    fn fix_at(alt_m: Option<f32>, uptime_s: u32) -> crate::fix::Fix {
        crate::fix::Fix {
            lat_deg: 40.0,
            lon_deg: -105.0,
            speed_mps: 0.0,
            course_deg: None,
            sats: 8,
            alt_m,
            time_of_day: None,
            date: None,
            uptime_s,
        }
    }

    #[test]
    fn rezero_reference_needs_a_fresh_plausible_gps_altitude() {
        let fresh = fix_at(Some(1610.0), 100);
        assert_eq!(rezero_reference(Some(&fresh), 100), Some(1610.0));
        assert_eq!(
            rezero_reference(Some(&fresh), 100 + REZERO_MAX_FIX_AGE_S),
            Some(1610.0)
        );
        // Stale, altitude-less, implausible, or absent fixes all refuse.
        assert_eq!(
            rezero_reference(Some(&fresh), 101 + REZERO_MAX_FIX_AGE_S),
            None
        );
        assert_eq!(rezero_reference(Some(&fix_at(None, 100)), 100), None);
        assert_eq!(
            rezero_reference(Some(&fix_at(Some(f32::NAN), 100)), 100),
            None
        );
        assert_eq!(rezero_reference(None, 100), None);
    }

    #[test]
    fn rezero_banner_states_the_outcome() {
        assert_eq!(
            rezero_banner(RezeroStatus::Applied(1610.4)).as_str(),
            "SET 1610M"
        );
        assert_eq!(
            rezero_banner(RezeroStatus::Applied(-500.0)).as_str(),
            "SET -500M"
        );
        assert_eq!(
            rezero_banner(RezeroStatus::Applied(9000.0)).as_str(),
            "SET 9000M"
        );
        assert_eq!(rezero_banner(RezeroStatus::NoGps).as_str(), "NO GPS FIX");
        assert_eq!(rezero_banner(RezeroStatus::NoBaro).as_str(), "NO BARO");
    }

    // --- Moving-gate: the GPS-independent safety (GPS absent throughout) ---

    #[test]
    fn stationary_drift_banks_nothing() {
        // A weather front drifts apparent altitude up ~100 m while the runner
        // rests, with NO GPS to drive the bias. moving=false must bank nothing
        // and re-basing must not dump a phantom delta on resume.
        let mut acc = VertAccumulator::new();
        acc.push(2500.0, true, None);
        for step in 1..=100 {
            acc.push(2500.0 + step as f32, false, None);
        }
        assert_eq!(acc.gain_m(), 0.0, "drift while stopped is not climb");
        assert_eq!(acc.loss_m(), 0.0);
        // A real move from the drifted base accrues normally.
        acc.push(2600.0 + DEADBAND_M, true, None);
        assert!((acc.gain_m() - DEADBAND_M).abs() < 1e-3);
    }

    #[test]
    fn a_real_climb_while_moving_is_unaffected_by_the_gate() {
        let mut acc = VertAccumulator::new();
        acc.push(1000.0, true, None);
        for step in 1..=50 {
            acc.push(1000.0 + step as f32, true, None);
        }
        assert!((acc.gain_m() - 50.0).abs() <= DEADBAND_M);
    }

    #[test]
    fn drift_down_while_stopped_then_descent_while_moving() {
        let mut acc = VertAccumulator::new();
        acc.push(3000.0, true, None);
        for step in 1..=40 {
            acc.push(3000.0 - step as f32, false, None);
        }
        assert_eq!(acc.loss_m(), 0.0);
        acc.push(2960.0 - 10.0, true, None);
        assert!((acc.loss_m() - 10.0).abs() < 1e-3);
        assert_eq!(acc.gain_m(), 0.0);
    }

    #[test]
    fn stopped_with_live_gps_still_banks_nothing() {
        // The composed case: moving-gate AND a live (Tracking) GPS bias. Warm the
        // filter to Tracking on flat terrain while moving, then STOP while a
        // weather front drifts baro up but GPS holds flat. The moving-gate must
        // bank nothing regardless of the present GPS bias underneath.
        let mut acc = VertAccumulator::new();
        for _ in 0..(SEED_SAMPLES + 10) {
            acc.push(1000.0, true, Some(1000.0));
        }
        let (g0, l0) = (acc.gain_m(), acc.loss_m());
        assert_eq!(g0, 0.0);
        assert_eq!(l0, 0.0);
        for step in 1..=50 {
            acc.push(1000.0 + step as f32, false, Some(1000.0));
        }
        assert_eq!(
            acc.gain_m(),
            g0,
            "no gain banked while stopped, even with live GPS"
        );
        assert_eq!(acc.loss_m(), l0);
    }

    // --- Publication gate: what the 1 Hz barometer is allowed to wake ---

    /// Drive `should_publish` the way the baro task does — anchored on the last
    /// reading actually published — and count what got through.
    fn publishes(readings: impl IntoIterator<Item = Reading>) -> usize {
        let mut published: Option<Reading> = None;
        let mut n = 0;
        for r in readings {
            if should_publish(published, r) {
                published = Some(r);
                n += 1;
            }
        }
        n
    }

    #[test]
    fn the_publish_step_is_the_finest_quantum_a_consumer_can_represent() {
        // A decimetre: the phone-link frame's `{:.1}` and the stored track
        // point's decimetre elevation field. Coarsening it past this would
        // start withholding altitude the wire format can actually carry — and
        // that the live GAP estimator reads its grade from.
        assert_eq!(PUBLISH_STEP_M, 0.1);
        // It must also stay well under the noise floor the accumulator banks
        // vert at, or a committed climb could go unpublished.
        assert!(PUBLISH_STEP_M < DEADBAND_M);
    }

    #[test]
    fn the_first_reading_always_publishes() {
        let r = Reading {
            alt_m: 1_610.0,
            gain_m: 0.0,
            loss_m: 0.0,
        };
        assert!(should_publish(None, r));
    }

    #[test]
    fn sensor_noise_never_wakes_a_consumer_twice() {
        // The defect this gate closes: a motionless wrist with a present BMP581
        // used to publish (and so re-render the whole face) once a second
        // forever, because two f32 samples off a real sensor are never equal.
        // The jitter here is the configured 16x-OSR + IIR-7 noise floor, low
        // centimetres.
        let jitter = (0..600u32).map(|n| Reading {
            alt_m: 1_000.0 + (((n * 7 % 11) as f32) - 5.0) * 0.005,
            gain_m: 0.0,
            loss_m: 0.0,
        });
        assert_eq!(publishes(jitter), 1);
    }

    #[test]
    fn a_real_climb_publishes_every_sample() {
        // Metre-a-second steps dwarf the step, so the gate is transparent —
        // altitude, and the grade the GAP estimator reads off it, arrive at
        // full sample rate exactly as before.
        let mut acc = VertAccumulator::new();
        let climb = (0..=100).map(|step| {
            let corrected = acc.push(step as f32, true, None);
            acc.reading(corrected)
        });
        assert_eq!(publishes(climb), 101);
    }

    #[test]
    fn a_slow_climb_is_throttled_but_never_starved() {
        // 4 cm a second — a gentle grade at a hiking pace, under the step. The
        // gate must still publish on the step, and the published altitude must
        // never trail the sample by a whole one.
        let mut acc = VertAccumulator::new();
        let mut published: Option<Reading> = None;
        let mut n = 0;
        for step in 0..=100 {
            let corrected = acc.push(step as f32 * 0.04, true, None);
            let r = acc.reading(corrected);
            if should_publish(published, r) {
                published = Some(r);
                n += 1;
            }
            assert!(
                libm::fabsf(published.unwrap().alt_m - r.alt_m) < PUBLISH_STEP_M,
                "the published altitude fell a whole step behind the sample"
            );
        }
        assert!((30..=40).contains(&n), "one publish per step climbed: {n}");
    }

    #[test]
    fn banked_vert_publishes_even_when_the_altitude_barely_moved() {
        // The totals are their own clause: they drive the VERT row, and they
        // only move when the accumulator commits real vertical.
        let prev = Reading {
            alt_m: 100.0,
            gain_m: 0.0,
            loss_m: 0.0,
        };
        for next in [
            Reading {
                gain_m: 3.0,
                ..prev
            },
            Reading {
                loss_m: 3.0,
                ..prev
            },
        ] {
            assert!(should_publish(Some(prev), next));
        }
    }

    #[test]
    fn a_manual_rezero_snap_moves_far_enough_to_publish() {
        let mut acc = VertAccumulator::new();
        let raw = acc.push(1_624.0, true, None);
        let before = acc.reading(raw);
        let snapped = acc.rezero(1_624.0, Some(1_610.0)).unwrap();
        assert!(should_publish(Some(before), acc.reading(snapped)));
    }

    #[test]
    fn a_non_finite_altitude_does_not_free_run_the_waker() {
        // A NaN comparison is false either way; the gate must fall on the side
        // that cannot resurrect the per-second waker.
        let nan = Reading {
            alt_m: f32::NAN,
            gain_m: 0.0,
            loss_m: 0.0,
        };
        assert!(!should_publish(Some(nan), nan));
    }
}
