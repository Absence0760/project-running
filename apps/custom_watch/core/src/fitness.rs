//! Fitness metrics — VDOT / VO2 max, per-run TSS, the training-load rollup, and
//! the recovery-advice ladder.
//!
//! Parity port of the web canonical `apps/web/src/lib/training/fitness.ts`
//! (twin of `apps/mobile_android/lib/fitness.dart`). Same Daniels VDOT curve,
//! the same %VO2max race-pace demand, the same TSS = duration x intensity^2
//! model, and the same ATL(7d)/CTL(42d) EWMA rollup with a 28-day layoff reset.
//! This is a SEPARATE surface from [`crate::training_load`], which ports the
//! other web file (`training_load.ts`) — the 90-day fitness/fatigue/form series.
//! The two files share only the EWMA idea; nothing here imports or reuses
//! `training_load`, exactly as web keeps them as two files.
//!
//! The one representational change from the canonical helper: the web copy reads
//! `Run.started_at` as an ISO string and drives every window off `Date.now()` /
//! local-calendar-day bucketing (`localDateKey`). Neither ISO parsing nor a
//! timezone database belongs in a `no_std` firmware core, so — following
//! [`crate::training_load`]'s precedent — a run carries a plain **day index**
//! ([`RunForFitness::day`], calendar days from any fixed epoch, local tz) and
//! every window (`now_day` for the layoff/gap/90-day cutoffs, the trainingLoad
//! walk) is integer day arithmetic. Only relative day differences matter, so
//! this is the honest collapse of `localDateKey` + `Date.now()`, and every test
//! maps a `Date` offset to a day offset one-for-one.
//!
//! Human-readable advice is modelled as the [`RecoveryAdvice`] enum rather than
//! English string literals — the presentation layer owns the wording, matching
//! how `badges` / `onboarding` keep labels out of the pure helper.
//!
//! Pure logic, no peripherals, no allocator. f64 is kept (not f32) so the VDOT /
//! `libm::exp` / EWMA numbers match the web exactly.

/// Minimum qualifying-run distance (metres). Below this a run is too short for
/// honest VDOT math — a noisy 1 km sprint would inflate the max-over-window
/// ceiling. 1.5 km paired with the duration floor admits a comeback runner's
/// sustained short outing while still rejecting all-out efforts.
pub const MIN_QUALIFYING_DISTANCE_M: f64 = 1500.0;

/// Minimum qualifying-run duration (seconds). Guards the short-sprint inflation
/// case alongside the distance floor.
pub const MIN_QUALIFYING_DURATION_S: u32 = 300;

/// TSB at or above which a hard / quality session is advisable. Below it the
/// runner is still loaded enough that the next session should stay easy. Matches
/// the boundary where [`recovery_advice`] flips from loaded to sweet-spot.
pub const HARD_SESSION_TSB_THRESHOLD: f64 = -10.0;

/// Consecutive run-less days after which fitness is treated as lost and the
/// EWMAs reset to zero (mirrors the web `kLayoffResetDays`). Also the prior-gap
/// span that makes a resumed run "returning from a layoff".
const LAYOFF_RESET_DAYS: i32 = 28;

/// currentVdot look-back window (days): best qualifying effort within this.
const CURRENT_VDOT_WINDOW_DAYS: i32 = 90;

/// A resumed run within this many days of `now` counts as "currently active"
/// for the returning-from-layoff test.
const LAYOFF_ACTIVE_WINDOW_DAYS: i32 = 14;

/// Physiologically impossible VDOT ceiling — above this the input is corrupt (a
/// GPS distance spike / bad import) and is dropped rather than allowed to set
/// the max-over-window fitness ceiling.
const VDOT_CEILING: f64 = 90.0;

/// EWMA time constant (days) for acute load (ATL / fatigue).
const ATL_TAU_DAYS: f64 = 7.0;
/// EWMA time constant (days) for chronic load (CTL / fitness).
const CTL_TAU_DAYS: f64 = 42.0;

/// trainingLoad establishes a baseline over at least this many days of
/// pre-history so CTL isn't ramping from zero on the first logged day.
const BASELINE_DAYS: i32 = 42;

/// Bound on distinct run days / runs held on the stack — comfortably above any
/// realistic on-watch fitness history.
const MAX_RUNS: usize = 256;

/// Where a run's `source` came from — the recognised recording / import origins
/// qualify for fitness math; anything else ([`RunSource::Other`], e.g. a manual
/// entry) is excluded because its distance isn't measured.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RunSource {
    App,
    Watch,
    Strava,
    Garmin,
    HealthKit,
    HealthConnect,
    Other,
}

impl RunSource {
    fn is_qualifying(self) -> bool {
        !matches!(self, RunSource::Other)
    }
}

/// A run reduced to what fitness math needs. `day` is the calendar-day index
/// (see the module docs); `indoor` collapses the web `metadata.indoor === true`
/// flag (treadmill/belt distance is not VDOT-worthy).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RunForFitness {
    pub day: i32,
    pub distance_m: f64,
    pub duration_s: u32,
    pub source: RunSource,
    pub indoor: bool,
}

/// Top-level snapshot suitable for the Fitness card. Mirrors the web
/// `FitnessSnapshot`.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct FitnessSnapshot {
    pub vdot: Option<f64>,
    pub vo2_max: Option<f64>,
    pub acute_load: Option<f64>,
    pub chronic_load: Option<f64>,
    pub training_stress_bal: Option<f64>,
    pub qualifying_run_count: usize,
}

/// The ATL / CTL / TSB trio evaluated at a day. Fields are `None` together when
/// there's no data.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrainingLoadResult {
    pub acute_load: Option<f64>,
    pub chronic_load: Option<f64>,
    pub training_stress_bal: Option<f64>,
}

impl TrainingLoadResult {
    const fn none() -> Self {
        Self {
            acute_load: None,
            chronic_load: None,
            training_stress_bal: None,
        }
    }
}

/// Recovery-advisor verdict, rule-based on TSB / CTL. The wording lives in the
/// presentation layer; the helper only decides the category.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RecoveryAdvice {
    /// TSB or CTL absent — log a few runs and try again.
    NotEnoughData,
    /// Form numbers reset after a break — rebuild gradually before hard work.
    ReturningFromLayoff,
    /// TSB < -30: heavily loaded, take it easy or rest today.
    HeavilyLoaded,
    /// CTL < 10: fitness still building, focus on consistency.
    StillBuilding,
    /// TSB < -10: loaded but within build territory, easy/steady.
    LoadedBuildTerritory,
    /// TSB < 10: sweet spot, a steady run or tempo works.
    SweetSpot,
    /// TSB < 25: tapering/freshening, a hard effort will land well soon.
    Tapering,
    /// Very fresh — race soon if tapering on purpose, else build again.
    VeryFresh,
}

/// Whether a run qualifies for fitness math: measured source, far/long enough,
/// not indoor.
pub fn is_qualifying_run(run: &RunForFitness) -> bool {
    run.distance_m >= MIN_QUALIFYING_DISTANCE_M
        && run.duration_s >= MIN_QUALIFYING_DURATION_S
        && !run.indoor
        && run.source.is_qualifying()
}

/// The qualifying runs, in input order — the direct port of web `qualifyingRuns`.
/// Internal consumers filter with [`is_qualifying_run`] instead of materialising
/// this, to keep the hot paths allocation- and copy-free.
pub fn qualifying_runs(runs: &[RunForFitness]) -> heapless::Vec<RunForFitness, MAX_RUNS> {
    let mut out = heapless::Vec::new();
    for r in runs {
        if is_qualifying_run(r) {
            let _ = out.push(*r);
        }
    }
    out
}

/// Count of qualifying runs — the snapshot's `qualifying_run_count` without the
/// copy.
pub fn qualifying_run_count(runs: &[RunForFitness]) -> usize {
    runs.iter().filter(|r| is_qualifying_run(r)).count()
}

/// Runner's Daniels VDOT from a single run's distance (m) + duration (s).
/// Inverts the "%VO2max at race pace" curve; rejects too-short efforts and a
/// physiologically impossible ceiling.
pub fn vdot_from_run(distance_m: f64, duration_s: f64) -> Option<f64> {
    if distance_m < 1000.0 || duration_s < 120.0 {
        return None;
    }
    let t_min = duration_s / 60.0;
    let v = distance_m / t_min;
    let vo2_demand = -4.6 + 0.182258 * v + 0.000104 * v * v;
    let pct_vo2_max =
        0.8 + 0.1894393 * libm::exp(-0.012778 * t_min) + 0.2989558 * libm::exp(-0.1932605 * t_min);
    if pct_vo2_max <= 0.0 {
        return None;
    }
    let vdot = vo2_demand / pct_vo2_max;
    if !vdot.is_finite() || vdot <= 0.0 {
        return None;
    }
    if vdot > VDOT_CEILING {
        return None;
    }
    Some(vdot)
}

/// Current VDOT = max over qualifying runs in the last 90 days. The best single
/// effort is the fitness ceiling. `None` when no qualifying run exists.
pub fn current_vdot(runs: &[RunForFitness], now_day: i32) -> Option<f64> {
    let cutoff = now_day - CURRENT_VDOT_WINDOW_DAYS;
    let mut best: Option<f64> = None;
    for r in runs.iter().filter(|r| is_qualifying_run(r)) {
        if r.day < cutoff {
            continue;
        }
        if let Some(v) = vdot_from_run(r.distance_m, r.duration_s as f64) {
            best = Some(match best {
                Some(b) if b >= v => b,
                _ => v,
            });
        }
    }
    best
}

/// Cooper-style VO2 max — tracks VDOT 1:1 at these scales; exposed separately
/// only because users recognise the "VO2 max" label.
pub fn vo2_max_from_vdot(vdot: Option<f64>) -> Option<f64> {
    vdot
}

/// Training stress score for a single run: `duration_h x intensity^2 x 100`,
/// intensity = threshold_pace / run_pace.
pub fn run_tss(distance_m: f64, duration_s: f64, threshold_pace_sec_per_km: f64) -> f64 {
    if distance_m < 100.0 || duration_s < 30.0 || threshold_pace_sec_per_km <= 0.0 {
        return 0.0;
    }
    let run_pace_sec_per_km = duration_s / (distance_m / 1000.0);
    if run_pace_sec_per_km <= 0.0 {
        return 0.0;
    }
    let intensity = threshold_pace_sec_per_km / run_pace_sec_per_km;
    let duration_h = duration_s / 3600.0;
    duration_h * intensity * intensity * 100.0
}

/// Threshold pace (s/km) from VDOT — Daniels T-pace at 88% of VDOT, solving the
/// VO2-demand quadratic for velocity. `None` for null / non-positive input.
pub fn threshold_pace_sec_per_km_from_vdot(vdot: Option<f64>) -> Option<f64> {
    let vdot = match vdot {
        Some(v) if v > 0.0 => v,
        _ => return None,
    };
    let target = 0.88 * vdot + 4.6;
    let a = 0.000104;
    let b = 0.182258;
    let disc = b * b + 4.0 * a * target;
    if disc < 0.0 {
        return None;
    }
    let v_mpm = (-b + libm::sqrt(disc)) / (2.0 * a);
    if v_mpm <= 0.0 {
        return None;
    }
    let mps = v_mpm / 60.0;
    Some(1000.0 / mps)
}

/// Sum a qualifying run's TSS onto the day-keyed aggregate (the `no_std`
/// stand-in for the web `Map<yyyy-mm-dd, number>`).
fn add_day(by_day: &mut heapless::Vec<(i32, f64), MAX_RUNS>, day: i32, tss: f64) {
    for e in by_day.iter_mut() {
        if e.0 == day {
            e.1 += tss;
            return;
        }
    }
    let _ = by_day.push((day, tss));
}

/// Full training-load rollup: daily-bucketed TSS → 7-day ATL, 42-day CTL,
/// TSB = CTL - ATL, evaluated at `now_day`. All-`None` when there's no threshold
/// or no qualifying run.
pub fn training_load(
    runs: &[RunForFitness],
    threshold_pace_sec_per_km: Option<f64>,
    now_day: i32,
) -> TrainingLoadResult {
    let threshold = match threshold_pace_sec_per_km {
        Some(t) => t,
        None => return TrainingLoadResult::none(),
    };
    if runs.is_empty() {
        return TrainingLoadResult::none();
    }

    let mut by_day: heapless::Vec<(i32, f64), MAX_RUNS> = heapless::Vec::new();
    for r in runs.iter().filter(|r| is_qualifying_run(r)) {
        let tss = run_tss(r.distance_m, r.duration_s as f64, threshold);
        add_day(&mut by_day, r.day, tss);
    }
    if by_day.is_empty() {
        return TrainingLoadResult::none();
    }

    let end_day = now_day;
    let earliest = by_day.iter().map(|e| e.0).min().unwrap();
    // At least 42 days of pre-history (zeros) so CTL can establish a baseline.
    let start_day = earliest.min(end_day - BASELINE_DAYS);

    let atl_alpha = 1.0 - libm::exp(-1.0 / ATL_TAU_DAYS);
    let ctl_alpha = 1.0 - libm::exp(-1.0 / CTL_TAU_DAYS);
    let mut atl = 0.0;
    let mut ctl = 0.0;
    // After a sustained layoff, fitness is genuinely lost — zero the EWMAs so a
    // returning runner doesn't carry a phantom CTL that fakes a high TSB.
    let mut zero_streak = 0i32;
    let mut cursor = start_day;
    while cursor <= end_day {
        let tss = by_day
            .iter()
            .find(|e| e.0 == cursor)
            .map(|e| e.1)
            .unwrap_or(0.0);
        if tss > 0.0 {
            zero_streak = 0;
        } else {
            zero_streak += 1;
            if zero_streak >= LAYOFF_RESET_DAYS {
                atl = 0.0;
                ctl = 0.0;
            }
        }
        atl += atl_alpha * (tss - atl);
        ctl += ctl_alpha * (tss - ctl);
        cursor += 1;
    }
    TrainingLoadResult {
        acute_load: Some(atl),
        chronic_load: Some(ctl),
        training_stress_bal: Some(ctl - atl),
    }
}

/// Top-level snapshot: VDOT, VO2 max, training load + qualifying-run count.
pub fn compute_snapshot(runs: &[RunForFitness], now_day: i32) -> FitnessSnapshot {
    let vdot = current_vdot(runs, now_day);
    let threshold = threshold_pace_sec_per_km_from_vdot(vdot);
    let load = training_load(runs, threshold, now_day);
    FitnessSnapshot {
        vdot,
        vo2_max: vo2_max_from_vdot(vdot),
        acute_load: load.acute_load,
        chronic_load: load.chronic_load,
        training_stress_bal: load.training_stress_bal,
        qualifying_run_count: qualifying_run_count(runs),
    }
}

/// Rule-based recovery verdict on TSB / CTL. A returning runner's high TSB is
/// detraining, not freshness, so that override comes before the freshness rungs;
/// a heavy acute overload warrants rest even at low chronic load, so the
/// overload guard comes before the still-building rung.
pub fn recovery_advice(
    tsb: Option<f64>,
    ctl: Option<f64>,
    returning_from_layoff: bool,
) -> RecoveryAdvice {
    let (tsb, ctl) = match (tsb, ctl) {
        (Some(t), Some(c)) => (t, c),
        _ => return RecoveryAdvice::NotEnoughData,
    };
    if returning_from_layoff {
        return RecoveryAdvice::ReturningFromLayoff;
    }
    if tsb < -30.0 {
        return RecoveryAdvice::HeavilyLoaded;
    }
    if ctl < 10.0 {
        return RecoveryAdvice::StillBuilding;
    }
    if tsb < HARD_SESSION_TSB_THRESHOLD {
        return RecoveryAdvice::LoadedBuildTerritory;
    }
    if tsb < 10.0 {
        return RecoveryAdvice::SweetSpot;
    }
    if tsb < 25.0 {
        return RecoveryAdvice::Tapering;
    }
    RecoveryAdvice::VeryFresh
}

/// Easy / rest days until Form (TSB) recovers to the hard-session threshold,
/// projecting the EWMAs forward with zero added stress (a floor, not a promise).
/// `Some(0)` when already recovered, `Some(n)` when it lands within `max_days`,
/// `None` when it would take longer.
pub fn days_until_next_hard_session(
    atl: Option<f64>,
    ctl: Option<f64>,
    max_days: u32,
) -> Option<u32> {
    let (atl, ctl) = match (atl, ctl) {
        (Some(a), Some(c)) => (a, c),
        _ => return None,
    };
    let atl_decay = libm::exp(-1.0 / ATL_TAU_DAYS);
    let ctl_decay = libm::exp(-1.0 / CTL_TAU_DAYS);
    let mut a = atl;
    let mut c = ctl;
    for d in 0..=max_days {
        if c - a >= HARD_SESSION_TSB_THRESHOLD {
            return Some(d);
        }
        a *= atl_decay;
        c *= ctl_decay;
    }
    None
}

/// Whether the runner is returning from a layoff: their most recent qualifying
/// run is recent (within 14 days of `now_day`) but the gap before it was
/// >= [`LAYOFF_RESET_DAYS`]. A single run can't prove a prior gap.
pub fn is_returning_from_layoff(runs: &[RunForFitness], now_day: i32) -> bool {
    let mut days: heapless::Vec<i32, MAX_RUNS> = heapless::Vec::new();
    for r in runs.iter().filter(|r| is_qualifying_run(r)) {
        if r.day <= now_day {
            let _ = days.push(r.day);
        }
    }
    if days.is_empty() {
        return false;
    }
    days.sort_unstable();
    let latest = days[days.len() - 1];
    if now_day - latest > LAYOFF_ACTIVE_WINDOW_DAYS {
        return false;
    }
    if days.len() == 1 {
        return false;
    }
    let prev = days[days.len() - 2];
    latest - prev >= LAYOFF_RESET_DAYS
}

/// Whether the runner is mid-gap returning: at least one run in history but the
/// most recent is older than `gap_days`. Counts every run (any logged activity
/// proves prior history), not just qualifying ones.
pub fn is_returning_from_gap(runs: &[RunForFitness], gap_days: i32, now_day: i32) -> bool {
    let mut latest: Option<i32> = None;
    for r in runs {
        if r.day <= now_day {
            latest = Some(match latest {
                Some(l) if l >= r.day => l,
                _ => r.day,
            });
        }
    }
    match latest {
        None => false,
        Some(l) => now_day - l >= gap_days,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/fitness.test.ts` — same scenarios,
    /// same expected values, with the web tests' `Date` offsets mapped to
    /// day-index offsets from a fixed `REF` "now" so the ports can't drift.
    const REF: i32 = 20_000;

    fn run(day: i32, distance_m: f64, duration_s: u32) -> RunForFitness {
        RunForFitness {
            day,
            distance_m,
            duration_s,
            source: RunSource::App,
            indoor: false,
        }
    }

    // ─────────────── qualifying_runs ───────────────

    #[test]
    fn qualifying_runs_drops_sub_1_5km() {
        let long_enough = run(REF - 29, 5000.0, 1500);
        let too_short = run(REF - 28, 1000.0, 360);
        assert_eq!(
            qualifying_runs(&[long_enough, too_short]).as_slice(),
            &[long_enough][..]
        );
    }

    #[test]
    fn qualifying_runs_admits_sustained_comeback_run() {
        let comeback = run(REF - 29, 1800.0, 600);
        assert_eq!(qualifying_runs(&[comeback]).as_slice(), &[comeback][..]);
    }

    #[test]
    fn qualifying_runs_drops_sub_5min() {
        let long_enough = run(REF - 29, 5000.0, 1500);
        let too_short = run(REF - 28, 5000.0, 200);
        assert_eq!(
            qualifying_runs(&[long_enough, too_short]).as_slice(),
            &[long_enough][..]
        );
    }

    #[test]
    fn qualifying_runs_drops_indoor_treadmill() {
        let outdoor = run(REF - 29, 5000.0, 1500);
        let treadmill = RunForFitness {
            source: RunSource::Garmin,
            indoor: true,
            ..run(REF - 28, 5000.0, 1500)
        };
        assert_eq!(
            qualifying_runs(&[outdoor, treadmill]).as_slice(),
            &[outdoor][..]
        );
    }

    #[test]
    fn qualifying_runs_accepts_recognised_sources_drops_others() {
        let sources = [
            RunSource::App,
            RunSource::Watch,
            RunSource::Strava,
            RunSource::Garmin,
            RunSource::HealthKit,
            RunSource::HealthConnect,
        ];
        let mut runs: heapless::Vec<RunForFitness, 8> = heapless::Vec::new();
        for s in sources {
            runs.push(RunForFitness {
                source: s,
                ..run(REF - 29, 5000.0, 1500)
            })
            .unwrap();
        }
        runs.push(RunForFitness {
            source: RunSource::Other,
            ..run(REF - 29, 5000.0, 1500)
        })
        .unwrap();
        assert_eq!(qualifying_runs(&runs).len(), sources.len());
    }

    // ─────────────── vdot_from_run ───────────────

    #[test]
    fn vdot_from_run_sub_1km_returns_none() {
        assert_eq!(vdot_from_run(500.0, 200.0), None);
    }

    #[test]
    fn vdot_from_run_sub_2min_returns_none() {
        assert_eq!(vdot_from_run(1500.0, 100.0), None);
    }

    #[test]
    fn vdot_from_run_20min_5k_around_50() {
        let v = vdot_from_run(5000.0, 20.0 * 60.0).unwrap();
        assert!(v > 48.0 && v < 52.0, "expected ~50, got {v}");
    }

    #[test]
    fn vdot_from_run_3h_marathon_around_53_to_55() {
        let v = vdot_from_run(42195.0, 3.0 * 3600.0).unwrap();
        assert!(v > 52.0 && v < 56.0, "expected ~54, got {v}");
    }

    #[test]
    fn vdot_from_run_distance_glitch_rejected() {
        assert_eq!(vdot_from_run(5000.0, 10.0 * 60.0), None);
        let elite = vdot_from_run(5000.0, 14.0 * 60.0).unwrap();
        assert!(elite < VDOT_CEILING, "elite 5k should qualify, got {elite}");
    }

    #[test]
    fn current_vdot_glitch_does_not_poison_ceiling() {
        let runs = [
            run(REF - 9, 5000.0, 1200), // legit ~20:00 5k
            run(REF - 9, 5000.0, 600),  // glitch 5 km in 10 min
        ];
        let v = current_vdot(&runs, REF).unwrap();
        assert!(v < VDOT_CEILING, "ceiling should be the real run, got {v}");
    }

    #[test]
    fn vdot_from_run_faster_pace_higher_vdot() {
        let fast = vdot_from_run(5000.0, 18.0 * 60.0).unwrap();
        let slow = vdot_from_run(5000.0, 25.0 * 60.0).unwrap();
        assert!(fast > slow, "fast {fast} should beat slow {slow}");
    }

    // ─────────────── current_vdot ───────────────

    #[test]
    fn current_vdot_picks_best_recent_run() {
        let fast = run(REF - 15, 5000.0, 18 * 60);
        let slow = run(REF - 8, 5000.0, 25 * 60);
        let v = current_vdot(&[fast, slow], REF).unwrap();
        assert!(v > 52.0);
    }

    #[test]
    fn current_vdot_ignores_runs_older_than_90_days() {
        let recent_slow = run(REF - 15, 5000.0, 25 * 60);
        let old_fast = run(REF - 150, 5000.0, 18 * 60);
        let v = current_vdot(&[recent_slow, old_fast], REF).unwrap();
        assert!(v < 50.0, "old fast run should be excluded, got {v}");
    }

    #[test]
    fn current_vdot_empty_is_none() {
        assert_eq!(current_vdot(&[], REF), None);
    }

    // ─────────────── vo2_max_from_vdot ───────────────

    #[test]
    fn vo2_max_from_vdot_passes_through() {
        assert_eq!(vo2_max_from_vdot(Some(50.0)), Some(50.0));
        assert_eq!(vo2_max_from_vdot(None), None);
    }

    // ─────────────── threshold_pace_sec_per_km_from_vdot ───────────────

    #[test]
    fn threshold_pace_null_in_null_out() {
        assert_eq!(threshold_pace_sec_per_km_from_vdot(None), None);
    }

    #[test]
    fn threshold_pace_vdot_50_in_230_to_270_band() {
        let t = threshold_pace_sec_per_km_from_vdot(Some(50.0)).unwrap();
        assert!(t > 230.0 && t < 270.0, "got {t}");
    }

    #[test]
    fn threshold_pace_higher_vdot_faster() {
        let elite = threshold_pace_sec_per_km_from_vdot(Some(70.0)).unwrap();
        let beginner = threshold_pace_sec_per_km_from_vdot(Some(30.0)).unwrap();
        assert!(elite < beginner);
    }

    // ─────────────── run_tss ───────────────

    #[test]
    fn run_tss_guards_return_zero() {
        assert_eq!(run_tss(50.0, 60.0, 300.0), 0.0);
        assert_eq!(run_tss(1000.0, 10.0, 300.0), 0.0);
        assert_eq!(run_tss(5000.0, 1500.0, 0.0), 0.0);
    }

    #[test]
    fn run_tss_threshold_pace_yields_100_per_hour() {
        let tss = run_tss(12000.0, 3600.0, 300.0);
        assert!((tss - 100.0).abs() < 1.0, "got {tss}");
    }

    #[test]
    fn run_tss_faster_than_threshold_rises_super_linearly() {
        let slow = run_tss(10000.0, 3600.0, 300.0);
        let fast = run_tss(12000.0, 3600.0, 300.0);
        let faster = run_tss(15000.0, 3600.0, 300.0);
        assert!(fast > slow);
        assert!(faster > fast);
        assert!(faster - fast > fast - slow);
    }

    // ─────────────── training_load ───────────────

    #[test]
    fn training_load_null_threshold_or_no_runs_all_null() {
        let empty = training_load(&[], Some(300.0), REF);
        assert_eq!(empty.acute_load, None);
        let no_thresh = training_load(&[run(REF - 15, 5000.0, 1500)], None, REF);
        assert_eq!(no_thresh.acute_load, None);
    }

    #[test]
    fn training_load_emits_non_null_curves() {
        let mut runs: heapless::Vec<RunForFitness, 8> = heapless::Vec::new();
        for week in 0..6 {
            runs.push(run(REF - (40 - week * 7), 10000.0, 3600))
                .unwrap();
        }
        let load = training_load(&runs, Some(300.0), REF);
        assert!(load.acute_load.unwrap() > 0.0);
        assert!(load.chronic_load.unwrap() > 0.0);
        assert!(load.training_stress_bal.is_some());
    }

    // Pins the reconciled EWMA convention: a single 10 km / 60-min run
    // (TSS = 69.44...) at threshold 300 s/km, logged 9 days before `now`, walked
    // across the 43-day baseline window. Computed, not guessed — mirrors the
    // web `trainingLoad — single run produces the reconciled ...` test.
    #[test]
    fn training_load_single_run_reconciled_atl_ctl_tsb() {
        let load = training_load(&[run(REF - 9, 10000.0, 3600)], Some(300.0), REF);
        let atl = load.acute_load.unwrap();
        let ctl = load.chronic_load.unwrap();
        let tsb = load.training_stress_bal.unwrap();
        assert!((atl - 2.555695151929763).abs() < 1e-9, "atl {atl}");
        assert!((ctl - 1.3187582819498793).abs() < 1e-9, "ctl {ctl}");
        assert!((tsb - -1.2369368699798837).abs() < 1e-9, "tsb {tsb}");
    }

    #[test]
    fn training_load_tsb_rises_during_14_day_taper() {
        let build_end = REF - 14;
        let mut runs: heapless::Vec<RunForFitness, 8> = heapless::Vec::new();
        for week in 0..4 {
            runs.push(run(build_end - (28 - week * 7), 15000.0, 4500))
                .unwrap();
        }
        let at_build_end = training_load(&runs, Some(300.0), build_end);
        let at_taper_end = training_load(&runs, Some(300.0), REF);
        assert!(
            at_taper_end.training_stress_bal.unwrap() > at_build_end.training_stress_bal.unwrap()
        );
    }

    // ─────────────── compute_snapshot ───────────────

    #[test]
    fn compute_snapshot_rolls_together() {
        let mut runs: heapless::Vec<RunForFitness, 8> = heapless::Vec::new();
        for week in 0..6 {
            runs.push(run(REF - (40 - week * 7), 10000.0, 50 * 60))
                .unwrap();
        }
        let snap = compute_snapshot(&runs, REF);
        assert!(snap.vdot.is_some());
        assert_eq!(snap.vo2_max, snap.vdot);
        assert_eq!(snap.qualifying_run_count, 6);
        assert!(snap.acute_load.is_some());
    }

    #[test]
    fn compute_snapshot_empty_all_null_zero_count() {
        let snap = compute_snapshot(&[], REF);
        assert_eq!(snap.vdot, None);
        assert_eq!(snap.vo2_max, None);
        assert_eq!(snap.acute_load, None);
        assert_eq!(snap.chronic_load, None);
        assert_eq!(snap.training_stress_bal, None);
        assert_eq!(snap.qualifying_run_count, 0);
    }

    // ─────────────── recovery_advice ───────────────

    #[test]
    fn recovery_advice_null_inputs_no_data() {
        assert_eq!(
            recovery_advice(None, None, false),
            RecoveryAdvice::NotEnoughData
        );
        assert_eq!(
            recovery_advice(None, Some(50.0), false),
            RecoveryAdvice::NotEnoughData
        );
        assert_eq!(
            recovery_advice(Some(0.0), None, false),
            RecoveryAdvice::NotEnoughData
        );
    }

    #[test]
    fn recovery_advice_sub_10_ctl_still_building() {
        assert_eq!(
            recovery_advice(Some(0.0), Some(5.0), false),
            RecoveryAdvice::StillBuilding
        );
    }

    #[test]
    fn recovery_advice_heavy_overload_warns_at_low_ctl() {
        let advice = recovery_advice(Some(-40.0), Some(8.0), false);
        assert_eq!(advice, RecoveryAdvice::HeavilyLoaded);
        assert_ne!(advice, RecoveryAdvice::StillBuilding);
    }

    #[test]
    fn recovery_advice_ladder_rises_through_bands() {
        let heavy = recovery_advice(Some(-40.0), Some(50.0), false);
        let loaded = recovery_advice(Some(-15.0), Some(50.0), false);
        let sweet = recovery_advice(Some(0.0), Some(50.0), false);
        let taper = recovery_advice(Some(15.0), Some(50.0), false);
        let fresh = recovery_advice(Some(40.0), Some(50.0), false);
        assert_eq!(heavy, RecoveryAdvice::HeavilyLoaded);
        assert_eq!(loaded, RecoveryAdvice::LoadedBuildTerritory);
        assert_eq!(sweet, RecoveryAdvice::SweetSpot);
        assert_eq!(taper, RecoveryAdvice::Tapering);
        assert_eq!(fresh, RecoveryAdvice::VeryFresh);
        let all = [heavy, loaded, sweet, taper, fresh];
        for i in 0..all.len() {
            for j in (i + 1)..all.len() {
                assert_ne!(all[i], all[j], "each band should be unique");
            }
        }
    }

    #[test]
    fn recovery_advice_returning_overrides_freshness() {
        let normal = recovery_advice(Some(40.0), Some(50.0), false);
        let returning = recovery_advice(Some(40.0), Some(50.0), true);
        assert_ne!(normal, returning);
        assert_eq!(returning, RecoveryAdvice::ReturningFromLayoff);
        assert_ne!(returning, RecoveryAdvice::VeryFresh);
    }

    // ─────────────── days_until_next_hard_session ───────────────

    #[test]
    fn days_until_next_hard_session_null_inputs_none() {
        assert_eq!(days_until_next_hard_session(None, Some(50.0), 21), None);
        assert_eq!(days_until_next_hard_session(Some(50.0), None, 21), None);
    }

    #[test]
    fn days_until_next_hard_session_already_recovered_zero() {
        assert_eq!(
            days_until_next_hard_session(Some(50.0), Some(60.0), 21),
            Some(0)
        );
        assert_eq!(
            days_until_next_hard_session(Some(60.0), Some(50.0), 21),
            Some(0)
        );
    }

    #[test]
    fn days_until_next_hard_session_heavy_fatigue_needs_days() {
        let d = days_until_next_hard_session(Some(90.0), Some(60.0), 21).unwrap();
        assert!(d >= 1, "should be at least a day out");
        let atl_decay = libm::exp(-1.0 / 7.0);
        let ctl_decay = libm::exp(-1.0 / 42.0);
        let mut a = 90.0f64;
        let mut c = 60.0f64;
        for i in 0..d {
            assert!(
                c - a < HARD_SESSION_TSB_THRESHOLD,
                "day {i} should still be loaded"
            );
            a *= atl_decay;
            c *= ctl_decay;
        }
        assert!(
            c - a >= HARD_SESSION_TSB_THRESHOLD,
            "crosses on the returned day"
        );
    }

    #[test]
    fn days_until_next_hard_session_none_when_exceeds_max_days() {
        assert_eq!(
            days_until_next_hard_session(Some(90.0), Some(60.0), 1),
            None
        );
    }

    // ─────────────── is_returning_from_layoff ───────────────

    #[test]
    fn is_returning_from_layoff_true_after_gap() {
        let runs = [run(REF - 150, 10000.0, 3000), run(REF - 1, 5000.0, 1800)];
        assert!(is_returning_from_layoff(&runs, REF));
    }

    #[test]
    fn is_returning_from_layoff_false_for_steady_runner() {
        let runs = [
            run(REF - 10, 8000.0, 2400),
            run(REF - 3, 8000.0, 2400),
            run(REF - 1, 8000.0, 2400),
        ];
        assert!(!is_returning_from_layoff(&runs, REF));
    }

    #[test]
    fn is_returning_from_layoff_false_for_single_run() {
        let runs = [run(REF - 1, 5000.0, 1800)];
        assert!(!is_returning_from_layoff(&runs, REF));
    }

    #[test]
    fn is_returning_from_layoff_false_when_not_active() {
        let runs = [run(REF - 90, 10000.0, 3000), run(REF - 40, 10000.0, 3000)];
        assert!(!is_returning_from_layoff(&runs, REF));
    }

    // ─────────────── is_returning_from_gap ───────────────

    #[test]
    fn is_returning_from_gap_false_for_no_runs() {
        assert!(!is_returning_from_gap(&[], 60, REF));
    }

    #[test]
    fn is_returning_from_gap_true_when_most_recent_older_than_gap() {
        let runs = [run(REF - 241, 10000.0, 3000), run(REF - 151, 8000.0, 2400)];
        assert!(is_returning_from_gap(&runs, 60, REF));
    }

    #[test]
    fn is_returning_from_gap_false_for_active_runner() {
        let runs = [run(REF - 88, 10000.0, 3000), run(REF - 10, 8000.0, 2400)];
        assert!(!is_returning_from_gap(&runs, 60, REF));
    }

    #[test]
    fn is_returning_from_gap_counts_non_qualifying_runs() {
        let treadmill = RunForFitness {
            indoor: true,
            ..run(REF - 211, 1500.0, 600)
        };
        assert!(is_returning_from_gap(&[treadmill], 60, REF));
    }

    #[test]
    fn is_returning_from_gap_boundary() {
        let exactly_60 = run(REF - 60, 5000.0, 1800);
        assert!(is_returning_from_gap(&[exactly_60], 60, REF));
        let fifty_nine = run(REF - 59, 5000.0, 1800);
        assert!(!is_returning_from_gap(&[fifty_nine], 60, REF));
    }
}
