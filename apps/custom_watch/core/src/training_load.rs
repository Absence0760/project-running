//! Training-load curves — per-run stress + the 90-day fitness/fatigue/form
//! (CTL/ATL/TSB) EWMA series.
//!
//! Parity port of the web canonical `apps/web/src/lib/training/training_load.ts`
//! (twin of `apps/mobile_android/lib/training_load.dart`) — same TRIMP-when-HR /
//! distance-proxy stress ladder, same per-window calibration, the same
//! separable lift-load channel, and the same EWMA trio (ATL time constant 7 d,
//! CTL 42 d) with a 126-day warm-up walk and a 28-day layoff reset.
//!
//! The one representational change from the canonical helpers: the web/Dart
//! copies key runs by parsing `started_at` into a local calendar-day string
//! (`localDateKey`) and walk the display window by `Date` arithmetic. Neither
//! ISO parsing nor a timezone database belongs in a `no_std` firmware core, so
//! here a run/lift carries a plain **day index** ([`RunForLoad::day`]) and the
//! series is anchored on an `end_day` — an integer count of calendar days from
//! any fixed epoch. Only relative day differences matter to the algorithm, so
//! this is the honest collapse of `localDateKey` + the day cursor, and every
//! test scenario maps a `Date` offset to a day offset one-for-one.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`. f64 is
//! kept (not f32) so the EWMA + `libm::exp` outputs match the web numbers.

/// Consecutive run-less days after which fitness is treated as lost and the
/// CTL/ATL EWMAs reset to zero. Four weeks past any taper or rest week and into
/// genuine detraining — without it a long layoff leaves a phantom CTL that
/// inflates TSB into "well-rested, train hard", dangerous advice for a returner.
pub const LAYOFF_RESET_DAYS: u32 = 28;

/// Tonnage → stress. Calibrated against a ~8,000 kg hard session at RPE 8 so it
/// scores ≈50 — squarely in the easy-run TSS band.
pub const LIFT_STRESS_PER_KG_TONNAGE: f64 = 50.0 / 8000.0;

/// Per-session hard cap so a fat-fingered weight can't spike the shared curve.
pub const LIFT_STRESS_CAP: f64 = 150.0;

/// Max distinct calendar days the daily-stress aggregate can hold. Comfortably
/// above a year, so any realistic run/lift history fits without dropping days.
const MAX_DAYS: usize = 366;

/// Max points a single training-load series can emit — one per displayed day.
/// Above the 90-day default with headroom; the warm-up days emit nothing.
const MAX_SERIES_DAYS: usize = 96;

/// EWMA time constant (days) for acute load (ATL / fatigue).
const ATL_TAU_DAYS: f64 = 7.0;
/// EWMA time constant (days) for chronic load (CTL / fitness).
const CTL_TAU_DAYS: f64 = 42.0;
/// Warm-up days walked before the displayed window so the EWMAs reach steady
/// state by day 1 of the chart. 3× the CTL time constant (~12.5% residual).
const WARMUP_DAYS: i32 = 42 * 3;

/// Which stress model a window uses. Decided once per window so the chart can't
/// switch mid-series and manufacture a discontinuity (persona-hunt Pro #2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum StressMode {
    /// Banister TRIMP for HR-eligible runs; a window-calibrated distance rate
    /// as the fallback for HR-less runs so both land on one scale.
    Trimp,
    /// Legacy 10 points/km for every run — used when the window has no
    /// HR-eligible run to calibrate against.
    Distance,
}

/// A run reduced to what training-load needs. `avg_bpm` is already numeric
/// (the watch reads a typed HR stream), so the web's string coercion collapses
/// to an `Option<f64>` treated as absent when non-finite.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RunForLoad {
    /// Calendar-day index of the run (days from any fixed epoch, local tz).
    pub day: i32,
    pub duration_s: u32,
    pub distance_m: f64,
    pub avg_bpm: Option<f64>,
}

/// The HR calibration inputs. Both absent (or `max <= resting`) forces
/// [`StressMode::Distance`].
#[derive(Clone, Copy, Debug, PartialEq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HrPrefs {
    pub resting_hr_bpm: Option<f64>,
    pub max_hr_bpm: Option<f64>,
}

/// One logged set of a lift session.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct LiftSetForLoad {
    pub reps: Option<f64>,
    pub weight_kg: Option<f64>,
    pub rpe: Option<f64>,
}

/// A lift session: a day plus its sets (borrowed, no allocation).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LiftForLoad<'a> {
    /// Calendar-day index of the session (see [`RunForLoad::day`]).
    pub day: i32,
    pub sets: &'a [LiftSetForLoad],
}

/// Stress-model calibration for a window.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct StressCalibration {
    pub mode: StressMode,
    /// Stress points per km used as the fallback for HR-less runs in
    /// [`StressMode::Trimp`]. `None` in [`StressMode::Distance`].
    pub trimp_per_km_fallback: Option<f64>,
}

/// One day of the training-load series.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrainingLoadPoint {
    /// The day index this point covers.
    pub day: i32,
    /// Total daily stress (run + lift), unrounded — the value the EWMA stepped.
    pub stress: f64,
    /// Provenance split; `run_stress` is always recoverable so a lift-load bug
    /// can't corrupt run-only readiness. `lift_stress` is 0 when no lifts pass.
    pub run_stress: f64,
    pub lift_stress: f64,
    pub atl: f64,
    pub ctl: f64,
    pub tsb: f64,
}

/// Daily-stress aggregate keyed by day index — the `no_std` stand-in for the
/// web `Map<yyyy-mm-dd, number>`.
pub struct DailyStress {
    entries: heapless::Vec<(i32, f64), MAX_DAYS>,
}

impl DailyStress {
    fn new() -> Self {
        Self {
            entries: heapless::Vec::new(),
        }
    }

    fn add(&mut self, day: i32, stress: f64) {
        for e in self.entries.iter_mut() {
            if e.0 == day {
                e.1 += stress;
                return;
            }
        }
        let _ = self.entries.push((day, stress));
    }

    /// Total stress logged on `day`, or `None` when that day carries none.
    pub fn get(&self, day: i32) -> Option<f64> {
        self.entries.iter().find(|e| e.0 == day).map(|e| e.1)
    }

    pub fn contains(&self, day: i32) -> bool {
        self.get(day).is_some()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

fn finite(v: Option<f64>) -> Option<f64> {
    match v {
        Some(x) if x.is_finite() => Some(x),
        _ => None,
    }
}

fn banister_trimp(duration_s: u32, avg_bpm: f64, rest: f64, max: f64) -> f64 {
    let duration_min = duration_s as f64 / 60.0;
    let hrr = ((avg_bpm - rest) / (max - rest)).clamp(0.0, 1.0);
    let k = 1.92;
    duration_min * hrr * 0.64 * libm::exp(k * hrr)
}

fn median(xs: &mut [f64]) -> f64 {
    xs.sort_unstable_by(|a, b| a.partial_cmp(b).unwrap());
    let mid = xs.len() / 2;
    if xs.len().is_multiple_of(2) {
        (xs[mid - 1] + xs[mid]) / 2.0
    } else {
        xs[mid]
    }
}

fn round2(n: f64) -> f64 {
    libm::round(n * 100.0) / 100.0
}

/// Decide the calibration for a window. If the HR prefs are configured (with
/// `max > resting`) AND at least one run carries `avg_bpm`, the mode is
/// [`StressMode::Trimp`] with the fallback rate set to the median TRIMP-per-km
/// of the eligible runs (anchored to the runner's own intensity). Otherwise
/// [`StressMode::Distance`].
pub fn compute_calibration(runs: &[RunForLoad], prefs: &HrPrefs) -> StressCalibration {
    let (rest, max) = match (finite(prefs.resting_hr_bpm), finite(prefs.max_hr_bpm)) {
        (Some(r), Some(m)) if m > r => (r, m),
        _ => {
            return StressCalibration {
                mode: StressMode::Distance,
                trimp_per_km_fallback: None,
            }
        }
    };

    let mut trimps_per_km: heapless::Vec<f64, MAX_DAYS> = heapless::Vec::new();
    for r in runs {
        let Some(avg) = finite(r.avg_bpm) else {
            continue;
        };
        let km = r.distance_m / 1000.0;
        if km <= 0.0 || r.duration_s == 0 {
            continue;
        }
        let trimp = banister_trimp(r.duration_s, avg, rest, max);
        if trimp > 0.0 {
            let _ = trimps_per_km.push(trimp / km);
        }
    }

    if trimps_per_km.is_empty() {
        return StressCalibration {
            mode: StressMode::Distance,
            trimp_per_km_fallback: None,
        };
    }
    StressCalibration {
        mode: StressMode::Trimp,
        trimp_per_km_fallback: Some(median(&mut trimps_per_km)),
    }
}

/// Per-run training stress score. Pass a `calibration` to honour the
/// window-level mode (via [`aggregate_daily_stress`], which derives one for the
/// whole window). Without one the mode is derived from this single run — the
/// legacy per-run dispatch.
pub fn compute_stress(
    run: &RunForLoad,
    prefs: &HrPrefs,
    calibration: Option<&StressCalibration>,
) -> f64 {
    if run.distance_m <= 0.0 && run.duration_s == 0 {
        return 0.0;
    }

    let owned;
    let cal = match calibration {
        Some(c) => c,
        None => {
            owned = compute_calibration(core::slice::from_ref(run), prefs);
            &owned
        }
    };

    let avg_bpm = finite(run.avg_bpm);
    let rest = finite(prefs.resting_hr_bpm);
    let max = finite(prefs.max_hr_bpm);

    match cal.mode {
        StressMode::Trimp => {
            let km = run.distance_m / 1000.0;
            let rate = cal.trimp_per_km_fallback.unwrap_or(7.0);
            if let (Some(a), Some(r), Some(m)) = (avg_bpm, rest, max) {
                if m > r {
                    let trimp = banister_trimp(run.duration_s, a, r, m);
                    // avg_bpm <= resting (misconfig, strap dropout, recovery
                    // shuffle) → hrr=0 → trimp=0; the stress<=0 skip would drop
                    // a real logged run. Fall back to the same distance proxy an
                    // HR-less run uses so a real effort always counts.
                    if trimp > 0.0 {
                        return trimp;
                    }
                    return km * rate;
                }
            }
            km * rate
        }
        StressMode::Distance => (run.distance_m / 1000.0) * 10.0,
    }
}

/// Sum run stresses by day. Derives a single calibration for the whole window
/// so every run is scored on the same scale.
pub fn aggregate_daily_stress(runs: &[RunForLoad], prefs: &HrPrefs) -> DailyStress {
    let calibration = compute_calibration(runs, prefs);
    let mut out = DailyStress::new();
    for r in runs {
        let stress = compute_stress(r, prefs, Some(&calibration));
        if stress <= 0.0 {
            continue;
        }
        out.add(r.day, stress);
    }
    out
}

/// RPE → intensity multiplier, anchored at RPE 8 = 1.0; absent (or non-finite)
/// RPE = 1.0; bounded so a stray value can't dominate tonnage.
pub fn rpe_factor(rpe: Option<f64>) -> f64 {
    match finite(rpe) {
        None => 1.0,
        Some(r) => (0.5 + r / 16.0).clamp(0.5, 1.25),
    }
}

/// Per-session lift stress: `k · Σ(reps · weight_kg · rpeFactor)`, capped. Sets
/// missing reps or weight contribute nothing.
pub fn compute_lift_stress(lift: &LiftForLoad) -> f64 {
    let mut weighted = 0.0;
    for s in lift.sets {
        let (Some(reps), Some(weight)) = (finite(s.reps), finite(s.weight_kg)) else {
            continue;
        };
        if reps <= 0.0 || weight <= 0.0 {
            continue;
        }
        weighted += reps * weight * rpe_factor(s.rpe);
    }
    (weighted * LIFT_STRESS_PER_KG_TONNAGE).min(LIFT_STRESS_CAP)
}

/// Sum lift stress by day, mirroring [`aggregate_daily_stress`]. Kept separate
/// so run-only and lift-only daily series never mingle until a caller combines
/// them.
pub fn aggregate_daily_lift_stress(lifts: &[LiftForLoad]) -> DailyStress {
    let mut out = DailyStress::new();
    for l in lifts {
        let stress = compute_lift_stress(l);
        if stress <= 0.0 {
            continue;
        }
        out.add(l.day, stress);
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn step(
    stress: f64,
    atl: &mut f64,
    ctl: &mut f64,
    zero_streak: &mut u32,
    atl_alpha: f64,
    ctl_alpha: f64,
) {
    if stress > 0.0 {
        *zero_streak = 0;
    } else {
        *zero_streak += 1;
        if *zero_streak >= LAYOFF_RESET_DAYS {
            *atl = 0.0;
            *ctl = 0.0;
        }
    }
    *atl += atl_alpha * (stress - *atl);
    *ctl += ctl_alpha * (stress - *ctl);
}

/// EWMA trio over a `window_days`-long daily window ending on `end_day` (a day
/// index; see the module docs). Days with no stress still tick the decay. A
/// 126-day warm-up window is walked first so the EWMAs reach steady state by
/// day 1 of the displayed window (an established runner shouldn't see fitness
/// ramp from zero); pass no lifts and the run-only curve is unchanged.
pub fn compute_training_load_series(
    runs: &[RunForLoad],
    prefs: &HrPrefs,
    window_days: u32,
    end_day: i32,
    lifts: &[LiftForLoad],
) -> heapless::Vec<TrainingLoadPoint, MAX_SERIES_DAYS> {
    let daily = aggregate_daily_stress(runs, prefs);
    let daily_lift = aggregate_daily_lift_stress(lifts);
    let atl_alpha = 1.0 - libm::exp(-1.0 / ATL_TAU_DAYS);
    let ctl_alpha = 1.0 - libm::exp(-1.0 / CTL_TAU_DAYS);
    let wd = window_days as i32;

    let mut atl = 0.0;
    let mut ctl = 0.0;
    let mut zero_streak: u32 = 0;

    // Warm-up: seed the EWMAs without emitting points. The streak carries
    // across the warm-up → display boundary so a gap straddling it still resets.
    for i in 0..WARMUP_DAYS {
        let day = end_day - (wd - 1) - WARMUP_DAYS + i;
        let s = daily.get(day).unwrap_or(0.0) + daily_lift.get(day).unwrap_or(0.0);
        step(
            s,
            &mut atl,
            &mut ctl,
            &mut zero_streak,
            atl_alpha,
            ctl_alpha,
        );
    }

    let mut points = heapless::Vec::new();
    for i in 0..wd {
        let day = end_day - (wd - 1) + i;
        let run_stress = daily.get(day).unwrap_or(0.0);
        let lift_stress = daily_lift.get(day).unwrap_or(0.0);
        let stress = run_stress + lift_stress;
        step(
            stress,
            &mut atl,
            &mut ctl,
            &mut zero_streak,
            atl_alpha,
            ctl_alpha,
        );
        let _ = points.push(TrainingLoadPoint {
            day,
            stress,
            run_stress: round2(run_stress),
            lift_stress: round2(lift_stress),
            atl: round2(atl),
            ctl: round2(ctl),
            tsb: round2(ctl - atl),
        });
    }
    points
}

/// Whether any run carries a TRIMP-eligible HR signal — drives the honest
/// "HR-based" vs "volume-based" chart label.
pub fn has_trimp_signal(runs: &[RunForLoad], prefs: &HrPrefs) -> bool {
    if prefs.resting_hr_bpm.is_none() || prefs.max_hr_bpm.is_none() {
        return false;
    }
    runs.iter().any(|r| finite(r.avg_bpm).is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/training_load.test.ts` /
    /// `apps/mobile_android/test/training_load_test.dart` — same scenarios,
    /// same expected values, with `Date` offsets mapped to day-index offsets so
    /// the ports can't drift.
    const REF: i32 = 20_000;

    fn easy_5k() -> RunForLoad {
        RunForLoad {
            day: REF,
            duration_s: 1800,
            distance_m: 5000.0,
            avg_bpm: None,
        }
    }

    fn no_prefs() -> HrPrefs {
        HrPrefs::default()
    }

    fn hr_prefs(rest: f64, max: f64) -> HrPrefs {
        HrPrefs {
            resting_hr_bpm: Some(rest),
            max_hr_bpm: Some(max),
        }
    }

    fn hard_lift_sets() -> [LiftSetForLoad; 16] {
        [LiftSetForLoad {
            reps: Some(8.0),
            weight_kg: Some(62.5),
            rpe: Some(8.0),
        }; 16]
    }

    #[test]
    fn compute_stress_distance_fallback_easy_5k() {
        assert_eq!(compute_stress(&easy_5k(), &no_prefs(), None), 50.0);
    }

    #[test]
    fn compute_stress_trimp_lights_up_with_hr() {
        let run = RunForLoad {
            day: REF,
            duration_s: 3600,
            distance_m: 10000.0,
            avg_bpm: Some(150.0),
        };
        let trimp = compute_stress(&run, &hr_prefs(50.0, 190.0), None);
        let distance = compute_stress(&run, &no_prefs(), None);
        assert_ne!(trimp, distance);
        assert!(trimp > 0.0);
    }

    #[test]
    fn compute_stress_zero_distance_zero_duration_is_zero() {
        let run = RunForLoad {
            day: REF,
            duration_s: 0,
            distance_m: 0.0,
            avg_bpm: None,
        };
        assert_eq!(compute_stress(&run, &no_prefs(), None), 0.0);
    }

    #[test]
    fn compute_stress_positive_duration_no_distance_is_zero_not_nan() {
        let run = RunForLoad {
            day: REF,
            duration_s: 1800,
            distance_m: 0.0,
            avg_bpm: None,
        };
        let stress = compute_stress(&run, &no_prefs(), None);
        assert!(!stress.is_nan());
        assert_eq!(stress, 0.0);
    }

    #[test]
    fn aggregate_distance_less_run_never_poisons_with_nan() {
        let good = RunForLoad {
            day: REF,
            duration_s: 1800,
            distance_m: 5000.0,
            avg_bpm: None,
        };
        let no_distance = RunForLoad {
            day: REF,
            duration_s: 1800,
            distance_m: 0.0,
            avg_bpm: None,
        };
        let m = aggregate_daily_stress(&[good, no_distance], &no_prefs());
        assert!(!m.get(REF).unwrap().is_nan());
        assert_eq!(m.get(REF), Some(50.0));
    }

    #[test]
    fn series_distance_less_run_does_not_blank_curve() {
        let runs = [
            RunForLoad {
                day: REF - 5,
                duration_s: 3600,
                distance_m: 10000.0,
                avg_bpm: None,
            },
            RunForLoad {
                day: REF - 4,
                duration_s: 1800,
                distance_m: 0.0,
                avg_bpm: None,
            },
        ];
        let series = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        assert!(series
            .iter()
            .all(|p| !p.ctl.is_nan() && !p.atl.is_nan() && !p.tsb.is_nan()));
        assert!(series.iter().any(|p| p.ctl > 0.0));
    }

    #[test]
    fn aggregate_sums_same_day_runs() {
        let a = RunForLoad {
            day: REF,
            duration_s: 1500,
            distance_m: 5000.0,
            avg_bpm: None,
        };
        let b = RunForLoad {
            day: REF,
            duration_s: 900,
            distance_m: 3000.0,
            avg_bpm: None,
        };
        let m = aggregate_daily_stress(&[a, b], &no_prefs());
        assert_eq!(m.get(REF), Some(80.0));
    }

    #[test]
    fn series_emits_exactly_window_days() {
        let series = compute_training_load_series(&[], &no_prefs(), 30, REF, &[]);
        assert_eq!(series.len(), 30);
    }

    #[test]
    fn series_long_layoff_resets_ctl_tsb() {
        let mut runs: heapless::Vec<RunForLoad, 32> = heapless::Vec::new();
        for i in 50..=70 {
            runs.push(RunForLoad {
                day: REF - i,
                duration_s: 3000,
                distance_m: 10000.0,
                avg_bpm: None,
            })
            .unwrap();
        }
        let series = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        let last = series.last().unwrap();
        assert!(last.ctl < 1.0, "CTL should reset to ~0 after a >28d layoff");
        assert!(last.tsb.abs() < 1.0, "TSB should be ~0 after a layoff");
    }

    #[test]
    fn series_tsb_rises_during_taper() {
        let mut runs: heapless::Vec<RunForLoad, 32> = heapless::Vec::new();
        for i in 14..=28 {
            runs.push(RunForLoad {
                day: REF - i,
                duration_s: 1500,
                distance_m: 5000.0,
                avg_bpm: None,
            })
            .unwrap();
        }
        let series = compute_training_load_series(&runs, &no_prefs(), 60, REF, &[]);
        let last = series.last().unwrap();
        assert!(
            last.tsb > 0.0,
            "TSB should be positive after a 14-day taper"
        );
    }

    #[test]
    fn series_is_zero_with_no_runs() {
        let series = compute_training_load_series(&[], &no_prefs(), 30, REF, &[]);
        assert!(series
            .iter()
            .all(|p| p.atl == 0.0 && p.ctl == 0.0 && p.tsb == 0.0));
    }

    #[test]
    fn has_trimp_signal_false_when_no_avg_bpm() {
        assert!(!has_trimp_signal(&[easy_5k()], &hr_prefs(50.0, 190.0)));
    }

    #[test]
    fn has_trimp_signal_true_when_run_has_avg_bpm_and_prefs() {
        let with_hr = RunForLoad {
            avg_bpm: Some(150.0),
            ..easy_5k()
        };
        assert!(has_trimp_signal(&[with_hr], &hr_prefs(50.0, 190.0)));
    }

    #[test]
    fn has_trimp_signal_false_when_prefs_missing() {
        let with_hr = RunForLoad {
            avg_bpm: Some(150.0),
            ..easy_5k()
        };
        assert!(!has_trimp_signal(&[with_hr], &no_prefs()));
    }

    #[test]
    fn calibration_distance_when_no_hr_prefs() {
        let cal = compute_calibration(&[easy_5k()], &no_prefs());
        assert_eq!(cal.mode, StressMode::Distance);
        assert_eq!(cal.trimp_per_km_fallback, None);
    }

    #[test]
    fn calibration_distance_when_prefs_set_but_no_hr_run() {
        let cal = compute_calibration(&[easy_5k()], &hr_prefs(50.0, 190.0));
        assert_eq!(cal.mode, StressMode::Distance);
    }

    #[test]
    fn calibration_trimp_when_a_run_has_hr() {
        let with_hr = RunForLoad {
            avg_bpm: Some(140.0),
            ..easy_5k()
        };
        let cal = compute_calibration(&[with_hr], &hr_prefs(50.0, 190.0));
        assert_eq!(cal.mode, StressMode::Trimp);
        assert!(cal.trimp_per_km_fallback.unwrap() > 0.0);
    }

    #[test]
    fn aggregate_strap_less_day_uses_calibrated_fallback() {
        let with_hr = RunForLoad {
            day: REF,
            duration_s: 3600,
            distance_m: 12000.0,
            avg_bpm: Some(140.0),
        };
        let no_hr = RunForLoad {
            day: REF + 1,
            duration_s: 3600,
            distance_m: 12000.0,
            avg_bpm: None,
        };
        let daily = aggregate_daily_stress(&[with_hr, no_hr], &hr_prefs(50.0, 190.0));
        let day1 = daily.get(REF).unwrap();
        let day2 = daily.get(REF + 1).unwrap();
        assert!(day1 > 0.0 && day2 > 0.0);
        let ratio = day2 / day1;
        assert!(ratio > 0.5 && ratio < 1.5, "got ratio {ratio}");
    }

    #[test]
    fn aggregate_pure_distance_window_keeps_legacy_10_per_km() {
        let daily = aggregate_daily_stress(&[easy_5k()], &no_prefs());
        assert_eq!(daily.get(REF), Some(50.0));
    }

    #[test]
    fn aggregate_low_hr_run_in_trimp_mode_still_contributes() {
        let prefs = hr_prefs(55.0, 190.0);
        let normal_hr = RunForLoad {
            day: REF,
            duration_s: 3600,
            distance_m: 12000.0,
            avg_bpm: Some(150.0),
        };
        let low_hr = RunForLoad {
            day: REF + 1,
            duration_s: 3000,
            distance_m: 10000.0,
            avg_bpm: Some(50.0),
        };
        let daily = aggregate_daily_stress(&[normal_hr, low_hr], &prefs);
        let low_hr_stress = daily.get(REF + 1).unwrap();
        assert!(low_hr_stress > 0.0);
        let cal = compute_calibration(&[normal_hr, low_hr], &prefs);
        assert_eq!(low_hr_stress, 10.0 * cal.trimp_per_km_fallback.unwrap());
    }

    #[test]
    fn series_single_low_hr_run_still_builds_fitness() {
        let prefs = hr_prefs(55.0, 190.0);
        let runs = [RunForLoad {
            day: REF - 1,
            duration_s: 3000,
            distance_m: 10000.0,
            avg_bpm: Some(50.0),
        }];
        let series = compute_training_load_series(&runs, &prefs, 90, REF, &[]);
        assert!(series.iter().any(|p| p.ctl > 0.0));
        let last_day = &series[series.len() - 2];
        assert!(last_day.stress > 0.0);
    }

    #[test]
    fn series_ctl_at_steady_state_day_1_for_established_pro() {
        let mut runs: heapless::Vec<RunForLoad, 320> = heapless::Vec::new();
        for i in 1..=300 {
            runs.push(RunForLoad {
                day: REF - i,
                duration_s: 3600,
                distance_m: 12000.0,
                avg_bpm: None,
            })
            .unwrap();
        }
        let series = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        let day1 = &series[0];
        assert!(
            day1.ctl > 100.0,
            "day 1 CTL should be ≈120 at steady state, got {}",
            day1.ctl
        );
        assert!(
            day1.tsb.abs() < 10.0,
            "day 1 TSB should be within 10 of 0, got {}",
            day1.tsb
        );
    }

    #[test]
    fn series_new_user_no_pre_window_history_ramps_from_zero() {
        let runs = [RunForLoad {
            day: REF - 10,
            duration_s: 1500,
            distance_m: 5000.0,
            avg_bpm: None,
        }];
        let series = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        assert!(series[0].ctl < 1.0, "new user day-1 CTL should be ~0");
    }

    #[test]
    fn rpe_factor_anchored_absent_bounded() {
        assert_eq!(rpe_factor(Some(8.0)), 1.0);
        assert_eq!(rpe_factor(None), 1.0);
        assert!(rpe_factor(Some(6.0)) < 1.0 && rpe_factor(Some(10.0)) > 1.0);
        assert_eq!(rpe_factor(Some(0.0)), 0.5);
        assert_eq!(rpe_factor(Some(20.0)), 1.25);
    }

    #[test]
    fn calibration_hard_lift_scores_in_easy_run_band() {
        let sets = hard_lift_sets();
        let stress = compute_lift_stress(&LiftForLoad {
            day: REF,
            sets: &sets,
        });
        assert!(stress >= 40.0 && stress <= 60.0, "got {stress}");
    }

    #[test]
    fn lift_stress_sets_without_reps_or_weight_contribute_nothing() {
        let sets = [
            LiftSetForLoad {
                reps: Some(20.0),
                weight_kg: None,
                rpe: None,
            },
            LiftSetForLoad {
                reps: None,
                weight_kg: Some(60.0),
                rpe: None,
            },
            LiftSetForLoad {
                reps: Some(0.0),
                weight_kg: Some(60.0),
                rpe: None,
            },
        ];
        assert_eq!(
            compute_lift_stress(&LiftForLoad {
                day: REF,
                sets: &sets
            }),
            0.0
        );
    }

    #[test]
    fn lift_stress_fat_fingered_weight_is_capped() {
        let sets = [LiftSetForLoad {
            reps: Some(5.0),
            weight_kg: Some(50000.0),
            rpe: Some(8.0),
        }];
        assert_eq!(
            compute_lift_stress(&LiftForLoad {
                day: REF,
                sets: &sets
            }),
            LIFT_STRESS_CAP
        );
    }

    #[test]
    fn aggregate_lift_sums_by_day_skips_empty_sessions() {
        let hard = hard_lift_sets();
        let empty = [LiftSetForLoad {
            reps: Some(10.0),
            weight_kg: None,
            rpe: None,
        }];
        let lifts = [
            LiftForLoad {
                day: REF,
                sets: &hard,
            },
            LiftForLoad {
                day: REF,
                sets: &hard,
            },
            LiftForLoad {
                day: REF + 1,
                sets: &empty,
            },
        ];
        let daily = aggregate_daily_lift_stress(&lifts);
        assert!(daily.get(REF).unwrap() > 80.0);
        assert!(!daily.contains(REF + 1));
    }

    #[test]
    fn lift_stress_is_separable_run_only_recoverable() {
        let runs = [RunForLoad {
            day: REF - 1,
            duration_s: 2400,
            distance_m: 8000.0,
            avg_bpm: None,
        }];
        let hard = hard_lift_sets();
        let lifts = [LiftForLoad {
            day: REF - 1,
            sets: &hard,
        }];

        let run_only = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        let with_lifts = compute_training_load_series(&runs, &no_prefs(), 90, REF, &lifts);

        for (a, b) in with_lifts.iter().zip(run_only.iter()) {
            assert_eq!(
                a.run_stress, b.stress,
                "runStress must equal the run-only total"
            );
        }
        let last = &with_lifts[with_lifts.len() - 2];
        assert!(last.lift_stress > 0.0, "lift day should carry lift stress");
        assert!(
            last.stress > last.run_stress,
            "total exceeds run-only on a lift day"
        );
        assert!(
            with_lifts.last().unwrap().atl > run_only.last().unwrap().atl,
            "lifting should raise fatigue on the shared curve"
        );
    }

    #[test]
    fn run_only_readiness_uncorrupted_by_lift_magnitude() {
        let runs = [RunForLoad {
            day: REF - 1,
            duration_s: 2400,
            distance_m: 8000.0,
            avg_bpm: None,
        }];
        let normal = hard_lift_sets();
        let normal_lifts = [LiftForLoad {
            day: REF - 1,
            sets: &normal,
        }];
        let absurd = [LiftSetForLoad {
            reps: Some(10.0),
            weight_kg: Some(200.0),
            rpe: Some(10.0),
        }; 20];
        let absurd_lifts = [LiftForLoad {
            day: REF - 1,
            sets: &absurd,
        }];

        let run_only = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        let with_normal = compute_training_load_series(&runs, &no_prefs(), 90, REF, &normal_lifts);
        let with_absurd = compute_training_load_series(&runs, &no_prefs(), 90, REF, &absurd_lifts);

        for (a, b) in with_normal.iter().zip(run_only.iter()) {
            assert_eq!(a.run_stress, b.stress);
        }
        for (a, b) in with_absurd.iter().zip(run_only.iter()) {
            assert_eq!(a.run_stress, b.stress);
        }

        // Recovery is byte-identical no matter how large the lift load was.
        let recovered = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        for (a, b) in recovered.iter().zip(run_only.iter()) {
            assert_eq!(a.ctl, b.ctl);
            assert_eq!(a.atl, b.atl);
            assert_eq!(a.tsb, b.tsb);
        }

        let last_run = run_only.last().unwrap();
        let last_normal = with_normal.last().unwrap();
        let last_absurd = with_absurd.last().unwrap();
        assert!(
            last_normal.atl > last_run.atl,
            "lifts raise combined fatigue"
        );
        assert!(
            last_absurd.atl > last_normal.atl,
            "a heavier lift raises it further"
        );
        assert!(last_normal.tsb < last_run.tsb, "lifts lower combined form");
        assert!(
            last_absurd.tsb < last_normal.tsb,
            "a heavier lift lowers it further"
        );
    }

    #[test]
    fn series_no_lifts_leaves_lift_stress_zero_and_stress_unchanged() {
        let runs = [RunForLoad {
            day: REF - 2,
            duration_s: 1500,
            distance_m: 5000.0,
            avg_bpm: None,
        }];
        let series = compute_training_load_series(&runs, &no_prefs(), 90, REF, &[]);
        assert!(series.iter().all(|p| p.lift_stress == 0.0));
        assert!(series.iter().all(|p| p.stress == p.run_stress));
    }
}
