//! Grade-adjusted pace (GAP): the flat-ground pace that would cost the same
//! metabolic effort as running the current grade. Raw pace lies on hills — a
//! grind up a 10% wall reads slow and a screaming descent reads fast — so the
//! ultra runner this watch targets wants the effort-equivalent number.
//!
//! Energy-cost model: Minetti et al. 2002, "Energy cost of walking and running
//! at extreme uphill and downhill slopes" (J Appl Physiol 93:1039). C(i) is the
//! metabolic cost of running at gradient i (rise/run, fractional); the GAP
//! factor is C(i)/C(0) — how much harder this grade is than flat.
//!
//! Fourth parity surface of the same helper — keep the algorithm, constants,
//! and edge cases in lockstep with:
//! - `apps/web/src/lib/runs/grade_adjusted_pace.ts` (canonical),
//! - `apps/mobile_android/lib/grade_adjusted_pace.dart` (Dart twin),
//! - `apps/watch_garmin/source/GradeAdjustedPaceView.mc` (Connect IQ field —
//!   the source of the streaming [`GapEstimator`] shape and its constants).
//!
//! [`grade_adjusted_pace_s_per_km`] is the whole-track batch helper, mirrored
//! function-for-function from the web/Dart pair. [`GapEstimator`] is the
//! on-watch streaming variant the recorder feeds live — same grade-over-a-
//! segment smoothing the Garmin field uses, with the identical
//! [`grade_factor`] at its core.

use core::cell::Cell;

/// Flat-ground running cost C(0) from the polynomial below.
pub const MINETTI_FLAT_COST: f64 = 3.6;

/// Minetti's fit is only valid between roughly -45% and +45% grade; clamp to
/// that so a momentary altitude spike can't manufacture an absurd factor.
pub const MAX_GRADE: f64 = 0.45;

/// Minimum horizontal travel before a grade sample is trusted. GPS altitude is
/// jittery point-to-point, so grade is measured over a segment, mirroring the
/// watch field. 5 m matches `GradeAdjustedPaceView.mc`.
pub const MIN_SEGMENT_M: f64 = 5.0;

/// Below this speed the runner is walking / stopped and a live GAP is noise —
/// `MIN_SPEED_MPS` in `GradeAdjustedPaceView.mc`. Streaming-only gate; the
/// batch helper has no per-sample speed input.
pub const MIN_SPEED_MPS: f64 = 0.4;

/// Live-pace ceiling (99:00 per km): past this the value is a runaway from a
/// near-zero adjusted speed, not a pace. Mirrors the Garmin field's
/// `formatPace` guard; unreachable at the km unit given [`MIN_SPEED_MPS`] and
/// the bounded factor, kept so the streaming pipeline matches its source.
pub const MAX_PACE_S_PER_KM: f64 = 5940.0;

/// A power-hike up a steep headwall crawls below [`MIN_SPEED_MPS`] while the
/// effort-equivalent pace is *most* worth reading, so [`GapEstimator`] holds
/// the last valid GAP through such a dip rather than blanking to `--:--`. The
/// hold is bounded to this many consecutive sub-gate snapshot updates; the
/// recorder samples the estimator once per ~1 Hz active-clock tick, so this is
/// roughly a ten-second grace before a *sustained* slow crawl blanks. This is
/// watch-local streaming behaviour layered on top of the ported math — it does
/// NOT touch [`grade_factor`] or the parity-locked constants above, so it is
/// not part of the four-way lockstep.
pub const GAP_HOLD_WINDOW: u32 = 10;

/// Floor of the hold band. Between this and [`MIN_SPEED_MPS`] the runner is
/// still moving forward (a power-hike, ~0.3 m/s), so the held GAP is honest;
/// at or below it they have genuinely stopped and the estimator blanks at once
/// — the "real stop" exit the hold window must not paper over.
pub const GAP_HOLD_MIN_SPEED_MPS: f64 = 0.15;

/// Minetti 2002 5th-order fit: C(i) in J/kg/m, i fractional gradient.
pub fn minetti_cost_at_grade(i: f64) -> f64 {
    let i2 = i * i;
    let i3 = i2 * i;
    let i4 = i3 * i;
    let i5 = i4 * i;
    155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6
}

/// Cost multiplier relative to flat ground at a given fractional grade, with
/// the grade clamped to Minetti's valid range. 1.0 on the flat, > 1 uphill,
/// < 1 on gentle descents (running downhill is cheap until ~-20%).
pub fn grade_factor(grade: f64) -> f64 {
    minetti_cost_at_grade(grade.clamp(-MAX_GRADE, MAX_GRADE)) / MINETTI_FLAT_COST
}

/// One track point of the batch helper's input — the fields the web
/// `TrackPoint` / Dart `Waypoint` carry that GAP reads. Timestamps are epoch
/// milliseconds (what `Date.parse` / `inMilliseconds` reduce to).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GapPoint {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub ele_m: Option<f64>,
    pub t_ms: Option<i64>,
}

/// Overall grade-adjusted pace for a run, in seconds per kilometre. Returns
/// `None` when GAP can't be computed or carries no information:
///  - fewer than two track points,
///  - no timestamps (can't derive segment durations),
///  - no elevation data at all (GAP would equal raw pace).
///
/// Walks the track accumulating horizontal distance until a segment is at
/// least [`MIN_SEGMENT_M`] long, then applies that segment's grade factor to
/// its horizontal distance to get equivalent-flat distance. GAP = total time
/// over total equivalent-flat distance.
pub fn grade_adjusted_pace_s_per_km(track: &[GapPoint]) -> Option<u32> {
    if track.len() < 2 {
        return None;
    }

    let mut anchor = 0;
    let mut seg_horiz = 0.0;
    let mut adj_dist_m = 0.0;
    let mut time_s = 0.0;
    let mut saw_ele = false;

    for i in 1..track.len() {
        seg_horiz += haversine_metres(
            track[i - 1].lat_deg,
            track[i - 1].lon_deg,
            track[i].lat_deg,
            track[i].lon_deg,
        );
        if seg_horiz < MIN_SEGMENT_M {
            continue;
        }

        let a = &track[anchor];
        let b = &track[i];
        if let (Some(at), Some(bt)) = (a.t_ms, b.t_ms) {
            let dt_ms = bt - at;
            if dt_ms > 0 {
                let mut factor = 1.0;
                if let (Some(ae), Some(be)) = (a.ele_m, b.ele_m) {
                    saw_ele = true;
                    factor = grade_factor((be - ae) / seg_horiz);
                }
                adj_dist_m += seg_horiz * factor;
                time_s += dt_ms as f64 / 1000.0;
            }
        }
        // Advance the anchor whether or not the segment was usable — a chunk
        // without timestamps shouldn't wedge the walk forever.
        anchor = i;
        seg_horiz = 0.0;
    }

    if !saw_ele || adj_dist_m <= 0.0 || time_s <= 0.0 {
        return None;
    }
    Some(libm::round(time_s / (adj_dist_m / 1000.0)) as u32)
}

/// Live grade-adjusted pace from an instantaneous speed and a smoothed grade —
/// the Garmin field's `gapPace` at the km unit, returning `None` where the
/// field renders `--:--` (too slow to trust, or a runaway value).
pub fn gap_pace_s_per_km(speed_mps: f64, grade: f64) -> Option<u32> {
    if speed_mps < MIN_SPEED_MPS {
        return None;
    }
    let gap_speed = speed_mps * grade_factor(grade);
    if gap_speed <= 0.0 {
        return None;
    }
    let pace = 1000.0 / gap_speed;
    if pace > MAX_PACE_S_PER_KM {
        return None;
    }
    Some(libm::round(pace) as u32)
}

/// Streaming grade estimate over (cumulative distance, altitude) samples — the
/// Garmin field's `updateGrade` rolled forward only when a real segment
/// ([`MIN_SEGMENT_M`]) has been covered, so point-to-point altitude jitter
/// never manufactures a grade. The recorder feeds it each accepted fix's run
/// total + the baro-preferred altitude; [`gap_s_per_km`](Self::gap_s_per_km)
/// applies [`gap_pace_s_per_km`] to the current speed. With no altitude ever
/// fed the grade stays 0 and GAP equals raw pace, exactly as the on-watch
/// field behaves without an altimeter signal.
pub struct GapEstimator {
    last_distance_m: Option<f64>,
    last_alt_m: Option<f64>,
    grade: f64,
    /// The most recent above-gate GAP, kept so a sub-gate power-hike dip can
    /// show it instead of `--:--`. `Cell` because the recorder samples GAP
    /// through the shared `&self` [`snapshot`](crate::record::Recorder::snapshot),
    /// so the hold bookkeeping has to advance without a `&mut` handle.
    last_gap: Cell<Option<u32>>,
    /// Consecutive sub-gate updates the held GAP has been shown for; blanks
    /// once it passes [`GAP_HOLD_WINDOW`].
    dip_count: Cell<u32>,
}

impl Default for GapEstimator {
    fn default() -> Self {
        Self::new()
    }
}

impl GapEstimator {
    pub const fn new() -> Self {
        Self {
            last_distance_m: None,
            last_alt_m: None,
            grade: 0.0,
            last_gap: Cell::new(None),
            dip_count: Cell::new(0),
        }
    }

    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// The current smoothed, clamped grade (rise/run, fractional).
    pub fn grade(&self) -> f64 {
        self.grade
    }

    /// Feed one (cumulative run distance, altitude) sample. The first sample
    /// seeds the anchors; later ones roll the grade only once the run since
    /// the anchor reaches [`MIN_SEGMENT_M`].
    pub fn on_sample(&mut self, distance_m: f64, alt_m: f64) {
        let (Some(last_d), Some(last_a)) = (self.last_distance_m, self.last_alt_m) else {
            self.last_distance_m = Some(distance_m);
            self.last_alt_m = Some(alt_m);
            return;
        };
        let run = distance_m - last_d;
        if run >= MIN_SEGMENT_M {
            self.grade = ((alt_m - last_a) / run).clamp(-MAX_GRADE, MAX_GRADE);
            self.last_distance_m = Some(distance_m);
            self.last_alt_m = Some(alt_m);
        }
    }

    /// Live GAP for the current speed against the smoothed grade, seconds per
    /// kilometre.
    ///
    /// Above [`MIN_SPEED_MPS`] this is the pure [`gap_pace_s_per_km`], recorded
    /// as the value to hold. A dip into the power-hike band (between
    /// [`GAP_HOLD_MIN_SPEED_MPS`] and the gate) keeps showing that held value
    /// for up to [`GAP_HOLD_WINDOW`] consecutive updates before blanking, so a
    /// steep-headwall crawl reads its recent effort-pace instead of `--:--`. A
    /// genuine stop (at or below [`GAP_HOLD_MIN_SPEED_MPS`]) blanks at once and
    /// forgets the held value, so a resumed hike can't resurrect a pre-stop
    /// pace.
    pub fn gap_s_per_km(&self, speed_mps: f64) -> Option<u32> {
        if speed_mps <= GAP_HOLD_MIN_SPEED_MPS {
            self.last_gap.set(None);
            self.dip_count.set(0);
            return None;
        }
        if speed_mps >= MIN_SPEED_MPS {
            let gap = gap_pace_s_per_km(speed_mps, self.grade);
            self.last_gap.set(gap);
            self.dip_count.set(0);
            return gap;
        }
        let held_for = self.dip_count.get().saturating_add(1);
        self.dip_count.set(held_for);
        if held_for <= GAP_HOLD_WINDOW {
            self.last_gap.get()
        } else {
            self.last_gap.set(None);
            None
        }
    }
}

/// Great-circle distance between two lat/lng points, in metres — the same
/// haversine (R = 6371 km) the web/Dart batch helpers use, so the four ports
/// agree segment for segment. The canonical copy for `watch_core`: the privacy,
/// roadbook, route-description, route-geometry, and turn-cue modules all call
/// this rather than keep their own.
pub fn haversine_metres(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    const R: f64 = 6_371_000.0;
    let d_lat = (lat2 - lat1) * core::f64::consts::PI / 180.0;
    let d_lng = (lng2 - lng1) * core::f64::consts::PI / 180.0;
    let sin_lat = libm::sin(d_lat / 2.0);
    let sin_lng = libm::sin(d_lng / 2.0);
    let a = sin_lat * sin_lat
        + libm::cos(lat1 * core::f64::consts::PI / 180.0)
            * libm::cos(lat2 * core::f64::consts::PI / 180.0)
            * sin_lng
            * sin_lng;
    R * 2.0 * libm::atan2(libm::sqrt(a), libm::sqrt(1.0 - a))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/runs/grade_adjusted_pace.test.ts` /
    /// `apps/mobile_android/test/grade_adjusted_pace_test.dart` — same
    /// scenarios, same expected values, so the four ports can't drift.
    ///
    /// Build a straight east-west track at a constant horizontal speed and a
    /// constant grade. `grade_pct` is rise/run as a percentage.
    fn graded_track(
        points: usize,
        step_m: f64,
        step_s: f64,
        grade_pct: f64,
        with_ele: bool,
        with_ts: bool,
    ) -> Vec<GapPoint> {
        let lat = 40.0_f64;
        let t0: i64 = 1_767_225_600_000; // 2026-01-01T00:00:00Z, as the twins use
        let deg_per_m = 1.0 / (111_320.0 * libm::cos(lat * core::f64::consts::PI / 180.0));
        let mut out = Vec::with_capacity(points);
        let mut ele = 100.0;
        for i in 0..points {
            out.push(GapPoint {
                lat_deg: lat,
                lon_deg: -100.0 + i as f64 * step_m * deg_per_m,
                ele_m: with_ele.then_some(ele),
                t_ms: with_ts.then_some(t0 + libm::round(i as f64 * step_s * 1000.0) as i64),
            });
            ele += (grade_pct / 100.0) * step_m;
        }
        out
    }

    #[test]
    fn minetti_cost_at_flat_is_the_cached_flat_constant() {
        assert_eq!(minetti_cost_at_grade(0.0), MINETTI_FLAT_COST);
        assert_eq!(grade_factor(0.0), 1.0);
    }

    #[test]
    fn uphill_costs_more_than_flat_gentle_downhill_costs_less() {
        assert!(
            grade_factor(0.1) > 1.0,
            "a 10% climb should cost more than flat"
        );
        assert!(
            grade_factor(-0.1) < 1.0,
            "a gentle 10% descent should cost less than flat"
        );
    }

    #[test]
    fn grade_is_clamped_to_minetti_valid_range() {
        assert_eq!(grade_factor(0.9), grade_factor(MAX_GRADE));
        assert_eq!(grade_factor(-0.9), grade_factor(-MAX_GRADE));
    }

    #[test]
    fn flat_run_gap_equals_raw_pace() {
        // 5 m/s flat = 200 s/km raw. With zero grade every factor is 1.
        let track = graded_track(60, 5.0, 1.0, 0.0, true, true);
        assert_eq!(grade_adjusted_pace_s_per_km(&track), Some(200));
    }

    #[test]
    fn uphill_run_gap_is_faster_than_raw_pace() {
        // Climbing at 10% — same raw speed costs more effort, so the
        // effort-equivalent flat pace is FASTER (smaller s/km) than raw.
        let track = graded_track(60, 5.0, 1.0, 10.0, true, true);
        let gap = grade_adjusted_pace_s_per_km(&track).unwrap();
        assert!(gap < 200, "expected GAP {} to be faster than raw 200", gap);
    }

    #[test]
    fn descent_run_gap_is_slower_than_raw_pace() {
        let track = graded_track(60, 5.0, 1.0, -10.0, true, true);
        let gap = grade_adjusted_pace_s_per_km(&track).unwrap();
        assert!(gap > 200, "expected GAP {} to be slower than raw 200", gap);
    }

    #[test]
    fn no_elevation_data_gap_is_none() {
        let track = graded_track(60, 5.0, 1.0, 10.0, false, true);
        assert_eq!(grade_adjusted_pace_s_per_km(&track), None);
    }

    #[test]
    fn no_timestamps_gap_is_none() {
        let track = graded_track(60, 5.0, 1.0, 10.0, true, false);
        assert_eq!(grade_adjusted_pace_s_per_km(&track), None);
    }

    #[test]
    fn too_few_points_gap_is_none() {
        assert_eq!(grade_adjusted_pace_s_per_km(&[]), None);
        assert_eq!(
            grade_adjusted_pace_s_per_km(&[GapPoint {
                lat_deg: 40.0,
                lon_deg: -100.0,
                ele_m: Some(100.0),
                t_ms: Some(1_767_225_600_000),
            }]),
            None
        );
    }

    #[test]
    fn mixed_track_with_some_missing_elevation_still_computes() {
        let mut track = graded_track(60, 5.0, 1.0, 10.0, true, true);
        // Drop elevation on a handful of mid-run points — segments around them
        // fall back to factor 1, but the run as a whole still has grade signal.
        for p in &mut track[20..25] {
            p.ele_m = None;
        }
        let gap = grade_adjusted_pace_s_per_km(&track).unwrap();
        assert!(
            gap < 200,
            "still adjusted for the climb on the graded segments"
        );
    }

    // --- streaming estimator (the Garmin-field shape the recorder feeds) ---

    #[test]
    fn estimator_needs_a_real_segment_before_trusting_a_grade() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0); // seeds
        e.on_sample(3.0, 103.0); // 3 m run < MIN_SEGMENT_M: jitter, no grade
        assert_eq!(e.grade(), 0.0);
        e.on_sample(10.0, 101.0); // 10 m run from the seed, +1 m rise
        assert!((e.grade() - 0.1).abs() < 1e-9);
    }

    #[test]
    fn estimator_clamps_the_grade_like_the_pure_factor() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(10.0, 200.0); // a 1000% "grade" from an altitude spike
        assert_eq!(e.grade(), MAX_GRADE);
        assert_eq!(e.gap_s_per_km(5.0), gap_pace_s_per_km(5.0, MAX_GRADE));
    }

    #[test]
    fn estimator_flat_gap_equals_raw_pace() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(50.0, 100.0);
        assert_eq!(e.gap_s_per_km(5.0), Some(200));
    }

    #[test]
    fn estimator_uphill_faster_downhill_slower_than_raw() {
        let mut up = GapEstimator::new();
        up.on_sample(0.0, 100.0);
        up.on_sample(50.0, 105.0); // +10%
        assert!(up.gap_s_per_km(5.0).unwrap() < 200);

        let mut down = GapEstimator::new();
        down.on_sample(0.0, 100.0);
        down.on_sample(50.0, 95.0); // -10%
        assert!(down.gap_s_per_km(5.0).unwrap() > 200);
    }

    #[test]
    fn estimator_below_walk_threshold_is_none() {
        let e = GapEstimator::new();
        assert_eq!(e.gap_s_per_km(0.39), None);
        assert_eq!(e.gap_s_per_km(0.0), None);
        assert!(e.gap_s_per_km(MIN_SPEED_MPS).is_some());
    }

    #[test]
    fn estimator_holds_last_gap_through_a_power_hike_dip_then_blanks() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(50.0, 105.0); // +10% headwall
        let hiking_gap = e.gap_s_per_km(5.0).unwrap(); // primes the held value

        // The crawl up the wall drops below the walk gate but is still moving.
        // Every update inside the window shows the last effort-pace, not --:--.
        for _ in 0..GAP_HOLD_WINDOW {
            assert_eq!(e.gap_s_per_km(0.3), Some(hiking_gap));
        }
        // Once the dip outlasts the window the crawl is no longer a transient;
        // GAP blanks.
        assert_eq!(e.gap_s_per_km(0.3), None);
    }

    #[test]
    fn estimator_recovering_from_a_dip_refills_the_hold_window() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(50.0, 105.0);
        let gap = e.gap_s_per_km(5.0).unwrap();

        assert_eq!(e.gap_s_per_km(0.3), Some(gap)); // one dip update
        assert_eq!(e.gap_s_per_km(5.0), Some(gap)); // back above the gate resets it

        // The full window is available again after the recovery.
        for _ in 0..GAP_HOLD_WINDOW {
            assert_eq!(e.gap_s_per_km(0.3), Some(gap));
        }
        assert_eq!(e.gap_s_per_km(0.3), None);
    }

    #[test]
    fn estimator_real_stop_blanks_immediately_and_forgets_the_held_gap() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(50.0, 105.0);
        assert!(e.gap_s_per_km(5.0).is_some()); // primes a valid GAP

        // A genuine stop (at/below the hold floor) blanks at once — not after
        // the window — and clears the held value...
        assert_eq!(e.gap_s_per_km(0.05), None);
        // ...so a sub-gate hike resumed after the stop shows nothing until the
        // speed climbs back over the gate and GAP is recomputed.
        assert_eq!(e.gap_s_per_km(0.3), None);
        assert!(e.gap_s_per_km(5.0).is_some());
    }

    #[test]
    fn estimator_dip_before_any_valid_gap_stays_blank() {
        // No above-gate reading has ever primed a value, so a sub-gate dip has
        // nothing to hold and must stay None across the whole window.
        let e = GapEstimator::new();
        for _ in 0..GAP_HOLD_WINDOW {
            assert_eq!(e.gap_s_per_km(0.3), None);
        }
        assert_eq!(e.gap_s_per_km(0.3), None);
    }

    #[test]
    fn estimator_without_altitude_reports_raw_pace() {
        // No altitude ever fed: grade stays 0, GAP == raw pace — the live
        // field's no-altimeter behaviour (the batch helper returns None
        // instead, because a whole-run GAP with no signal adds nothing).
        let e = GapEstimator::new();
        assert_eq!(e.gap_s_per_km(4.0), Some(250));
    }

    #[test]
    fn estimator_reset_clears_grade_and_anchors() {
        let mut e = GapEstimator::new();
        e.on_sample(0.0, 100.0);
        e.on_sample(50.0, 105.0);
        assert!(e.grade() > 0.0);
        e.reset();
        assert_eq!(e.grade(), 0.0);
        e.on_sample(0.0, 200.0); // re-seeds rather than seeing a 100 m cliff
        e.on_sample(50.0, 200.0);
        assert_eq!(e.grade(), 0.0);
    }
}
