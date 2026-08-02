//! Live climb detection and the crest ahead — the roadmap's "Climb detection /
//! ClimbPro-style ascent view" parity row.
//!
//! Two halves, because a runner asks two different questions on a hill and only
//! one of them can always be answered:
//!
//! - [`ClimbDetector`] segments the climb the runner is **in**, from the same
//!   distance + altitude stream the recorder already banks. It needs no course
//!   and works on an unmarked trail, but it can only report what has been
//!   climbed, never what is left — the watch cannot see the hill.
//! - [`crest_ahead`] answers "how much of this climb is left" from the pushed
//!   course profile. That is the headline Garmin ClimbPro number, and it is
//!   available exactly when a course is loaded — so it is a separate answer,
//!   not a field the live half fakes when it has no course.
//!
//! **The detector is hysteretic on both edges, and deliberately blunt.** A
//! climb opens only once [`CLIMB_START_GAIN_M`] has been banked above the last
//! low point, and closes only once [`CLIMB_END_DROP_M`] has been lost below the
//! climb's high point. Without both, barometric noise and the dips every real
//! climb carries would open and close a "climb" every few hundred metres, and a
//! page that re-zeroes on every roller is worse than no page: a runner pacing a
//! 400 m ascent would watch their banked gain reset three times on the way up.
//! The drop threshold is what makes the high point the CREST — the descent has
//! to be committed before the climb is called over.
//!
//! Grades come from the climb's own endpoints, not from the last two samples:
//! a single 1 m baro twitch across a 5 m step is a 20 % grade, and the number a
//! runner reads on a page has to be the hill, not the sensor.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`. There is
//! no web helper to port: the app has per-leg vert in `roadbook`, but live
//! segmentation is new firmware work (roadmap § Feature parity backlog).

/// Gain above the last low point that opens a climb. Below this a bump is a
/// roller, not an ascent worth its own page — and every real climb clears it
/// within the first minute.
pub const CLIMB_START_GAIN_M: f32 = 20.0;

/// Loss below the climb's high point that closes it. Deliberately smaller than
/// the opening gain: a false close costs the runner their banked gain, a late
/// close only holds a finished climb on screen a few hundred metres longer.
pub const CLIMB_END_DROP_M: f32 = 10.0;

/// Minimum average grade over the opening stretch for it to count as a climb.
/// 20 m gained over 4 km is a false flat, not an ascent.
pub const CLIMB_MIN_GRADE_PCT: f32 = 2.0;

/// Drop below a candidate crest, in the course profile's own metres, that
/// confirms it IS a crest rather than a step in the climb. Mirrors
/// [`CLIMB_END_DROP_M`]'s job on the live side.
pub const CREST_DROP_M: i32 = 10;

/// The climb the runner is currently in. `Default` is the all-zero climb —
/// only ever a rendering placeholder for "no active climb", never a state the
/// detector produces.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ActiveClimb {
    /// Metres gained from the climb's foot to the current position. Net of the
    /// dips inside the climb — this is height above the foot, not summed D+,
    /// because that is the number that predicts what is left.
    pub gain_m: f32,
    /// Ground covered since the climb's foot.
    pub distance_m: f32,
    /// Average grade over the whole climb so far, percent.
    pub avg_grade_pct: f32,
}

/// The next crest on the pushed course, from the runner's along-course
/// position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CrestAhead {
    /// Ground still to cover to the crest.
    pub distance_m: f32,
    /// Metres still to climb to reach it — the ClimbPro headline. Net height,
    /// so a dip on the way does not inflate it.
    pub gain_m: f32,
    /// Average grade from here to the crest, percent.
    pub avg_grade_pct: f32,
}

/// What the Climb page shows: the climb underfoot, the crest ahead, or
/// neither. Both halves are independent — a course can name a crest before the
/// detector has banked enough gain to open a climb, and the detector works
/// with no course at all.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ClimbView {
    pub active: Option<ActiveClimb>,
    pub ahead: Option<CrestAhead>,
}

impl ClimbView {
    /// Whether the page has anything real to show — its data-presence bit.
    pub fn is_empty(&self) -> bool {
        self.active.is_none() && self.ahead.is_none()
    }

    /// Height fraction of the whole climb already banked — `gain` over
    /// `gain + still-to-climb`, the number the Climb page's thermometer
    /// fills by (§ 430). Both halves are net height, so a dip on the way
    /// distorts neither side. `None` without both: with no crest the total
    /// is unknowable and a fraction of a guess would render as progress, and
    /// with no active climb yet there is nothing banked to show — the crest
    /// block's rows already carry what is known.
    pub fn crest_progress(&self) -> Option<f32> {
        let (active, ahead) = (self.active?, self.ahead?);
        let banked = active.gain_m.max(0.0);
        let left = ahead.gain_m.max(0.0);
        let total = banked + left;
        if !total.is_finite() || total <= 0.0 {
            return None;
        }
        Some((banked / total).clamp(0.0, 1.0))
    }
}

/// Grade as a percent over a run, `0` when the run is too short to divide by.
fn grade_pct(rise_m: f32, run_m: f32) -> f32 {
    if run_m <= 0.0 || !rise_m.is_finite() {
        0.0
    } else {
        rise_m / run_m * 100.0
    }
}

/// Streaming climb segmenter, fed the recorder's distance + altitude on each
/// accepted fix.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ClimbDetector {
    /// The lowest point since the last climb closed — the foot a candidate
    /// climb is measured from.
    low_distance_m: f32,
    low_alt_m: f32,
    /// The highest point of the climb in progress; the crest once it closes.
    high_distance_m: f32,
    high_alt_m: f32,
    /// Set once the opening gain + grade gates are both cleared.
    climbing: bool,
    /// Whether any sample has landed — the first one seeds both extremes
    /// rather than being measured against a zero that means "no data".
    seeded: bool,
    last_distance_m: f32,
    last_alt_m: f32,
}

impl Default for ClimbDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl ClimbDetector {
    pub const fn new() -> Self {
        Self {
            low_distance_m: 0.0,
            low_alt_m: 0.0,
            high_distance_m: 0.0,
            high_alt_m: 0.0,
            climbing: false,
            seeded: false,
            last_distance_m: 0.0,
            last_alt_m: 0.0,
        }
    }

    /// Clear the state for a new run. The extremes are re-seeded by the next
    /// sample, so a new run never inherits the previous run's foot — which
    /// would open a climb the moment it started at a lower trailhead.
    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Feed one accepted fix: the run's cumulative distance and the
    /// baro-preferred altitude. A non-finite sample, or one that goes
    /// backwards in distance, is ignored — neither can be a real step, and
    /// both would corrupt the extremes the whole state machine measures from.
    pub fn on_sample(&mut self, distance_m: f64, alt_m: f64) {
        let d = distance_m as f32;
        let a = alt_m as f32;
        if !d.is_finite() || !a.is_finite() {
            return;
        }
        if !self.seeded {
            self.seeded = true;
            self.low_distance_m = d;
            self.low_alt_m = a;
            self.high_distance_m = d;
            self.high_alt_m = a;
            self.last_distance_m = d;
            self.last_alt_m = a;
            return;
        }
        if d < self.last_distance_m {
            return;
        }
        self.last_distance_m = d;
        self.last_alt_m = a;

        if a > self.high_alt_m {
            self.high_alt_m = a;
            self.high_distance_m = d;
        }
        if self.climbing {
            // The crest is the high point, and the descent has to be committed
            // before the climb is called over — a saddle mid-climb must not
            // reset the runner's banked gain.
            if self.high_alt_m - a >= CLIMB_END_DROP_M {
                self.climbing = false;
                self.low_alt_m = a;
                self.low_distance_m = d;
                self.high_alt_m = a;
                self.high_distance_m = d;
            }
            return;
        }
        // Not climbing: a new low re-bases the candidate foot, and enough gain
        // at enough grade above that foot opens a climb.
        if a < self.low_alt_m {
            self.low_alt_m = a;
            self.low_distance_m = d;
            self.high_alt_m = a;
            self.high_distance_m = d;
            return;
        }
        let gain = a - self.low_alt_m;
        let run = d - self.low_distance_m;
        if gain >= CLIMB_START_GAIN_M && grade_pct(gain, run) >= CLIMB_MIN_GRADE_PCT {
            self.climbing = true;
        }
    }

    /// The climb in progress, or `None` on the flat / on a descent.
    pub fn active(&self) -> Option<ActiveClimb> {
        if !self.climbing {
            return None;
        }
        let gain_m = self.last_alt_m - self.low_alt_m;
        let distance_m = self.last_distance_m - self.low_distance_m;
        Some(ActiveClimb {
            gain_m,
            distance_m,
            avg_grade_pct: grade_pct(gain_m, distance_m),
        })
    }
}

/// The next crest ahead on a pushed course profile.
///
/// `samples` is the distance-even elevation series
/// ([`crate::course_profile::course_elev_view`]) and `along_m` the runner's
/// distance along the course. Walks forward from the current sample to the
/// first local maximum the profile then falls [`CREST_DROP_M`] below — the
/// same "commit to the descent" rule the live detector uses, so a step in a
/// staircase climb is not reported as the top.
///
/// `None` when there is no profile, no course length to place the runner on,
/// the runner is past the end, or nothing ahead climbs — on a descent the
/// honest answer is that there is no crest to reach, not a crest at zero
/// metres.
pub fn crest_ahead(samples: &[i16], total_m: f64, along_m: f64) -> Option<CrestAhead> {
    // `is_finite` before the comparison rather than a negated one: a NaN
    // total fails every ordering, so `!(total_m > 0.0)` would be doing the
    // finiteness check by accident. Spell both.
    if samples.len() < 2 || !total_m.is_finite() || total_m <= 0.0 || !along_m.is_finite() {
        return None;
    }
    let step_m = total_m / (samples.len() - 1) as f64;
    if step_m <= 0.0 {
        return None;
    }
    let here = along_m.clamp(0.0, total_m);
    // The sample the runner has reached, rounded DOWN: the crest search must
    // not skip past a summit sitting between this sample and the next.
    let i = ((here / step_m) as usize).min(samples.len() - 1);
    if i + 1 >= samples.len() {
        return None;
    }
    let mut peak_i = i;
    let mut peak_alt = samples[i] as i32;
    for (j, &s) in samples.iter().enumerate().skip(i + 1) {
        let alt = s as i32;
        if alt > peak_alt {
            peak_alt = alt;
            peak_i = j;
        } else if peak_alt - alt >= CREST_DROP_M {
            // The profile has committed to descending past the peak — that
            // peak is the crest.
            break;
        }
    }
    if peak_i == i {
        return None;
    }
    let gain_m = (peak_alt - samples[i] as i32) as f32;
    if gain_m <= 0.0 {
        return None;
    }
    // Measured from the runner, not from their sample: at 0.9 of the way
    // through a step, the crest is a step-tenth nearer than the grid says.
    let distance_m = ((peak_i as f64 * step_m) - here).max(0.0) as f32;
    Some(CrestAhead {
        gain_m,
        distance_m,
        avg_grade_pct: grade_pct(gain_m, distance_m),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Walk a detector over `(distance, altitude)` samples.
    fn walk(d: &mut ClimbDetector, samples: &[(f64, f64)]) {
        for &(dist, alt) in samples {
            d.on_sample(dist, alt);
        }
    }

    /// A steady climb: `n` steps of `step_m` ground gaining `rise_m` each.
    fn ascent(from_d: f64, from_a: f64, n: usize, step_m: f64, rise_m: f64) -> [(f64, f64); 64] {
        let mut out = [(0.0, 0.0); 64];
        for (k, slot) in out.iter_mut().enumerate().take(n) {
            let i = k as f64 + 1.0;
            *slot = (from_d + i * step_m, from_a + i * rise_m);
        }
        out
    }

    #[test]
    fn a_roller_never_opens_a_climb() {
        // 12 m over 300 m is a good grade but not enough gain — the whole
        // point of the opening threshold is that a page must not re-zero on
        // every bump of a rolling course.
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &ascent(0.0, 100.0, 6, 50.0, 2.0)[..6]);
        assert!(d.active().is_none());
    }

    #[test]
    fn a_false_flat_never_opens_a_climb() {
        // 30 m gained, but over 4 km — a grade of 0.75 %. Real gain, not a
        // climb, and calling it one would put a permanent CLIMB on the page
        // of anyone running a gently tilted valley road.
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &ascent(0.0, 100.0, 20, 200.0, 1.5)[..20]);
        assert!(d.active().is_none());
    }

    #[test]
    fn a_real_climb_opens_and_reports_gain_distance_and_grade() {
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        // 10 steps of 50 m gaining 5 m each: 50 m over 500 m, a 10 % grade.
        walk(&mut d, &ascent(0.0, 100.0, 10, 50.0, 5.0)[..10]);
        let c = d.active().expect("a 50 m ascent at 10 % is a climb");
        assert!((c.gain_m - 50.0).abs() < 0.01, "{}", c.gain_m);
        assert!((c.distance_m - 500.0).abs() < 0.01, "{}", c.distance_m);
        assert!((c.avg_grade_pct - 10.0).abs() < 0.01, "{}", c.avg_grade_pct);
    }

    #[test]
    fn a_saddle_inside_a_climb_does_not_reset_the_banked_gain() {
        // The failure this whole hysteresis exists to prevent: a runner pacing
        // a long ascent watches their banked gain survive the dips the climb
        // carries, instead of re-zeroing at every one.
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &ascent(0.0, 100.0, 10, 50.0, 5.0)[..10]);
        let before = d.active().unwrap().gain_m;
        // An 8 m saddle — inside CLIMB_END_DROP_M, so the climb stands.
        walk(&mut d, &[(520.0, 147.0), (540.0, 142.0)]);
        let after = d.active().expect("an 8 m dip must not close the climb");
        assert!(after.gain_m < before);
        assert!((after.gain_m - 42.0).abs() < 0.01, "{}", after.gain_m);
        // ...and the climb resumes from the same foot, not a new one.
        walk(&mut d, &[(600.0, 160.0)]);
        assert!((d.active().unwrap().gain_m - 60.0).abs() < 0.01);
    }

    #[test]
    fn a_committed_descent_closes_the_climb_at_its_crest() {
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &ascent(0.0, 100.0, 10, 50.0, 5.0)[..10]);
        assert!(d.active().is_some());
        // Past CLIMB_END_DROP_M below the 150 m crest.
        walk(&mut d, &[(600.0, 139.0)]);
        assert!(d.active().is_none(), "the climb is over at the crest");
        // The next climb measures from the new low, not from the old foot.
        walk(&mut d, &[(700.0, 130.0)]);
        walk(&mut d, &ascent(700.0, 130.0, 10, 50.0, 5.0)[..10]);
        let c = d.active().expect("a second ascent opens its own climb");
        assert!((c.gain_m - 50.0).abs() < 0.01, "{}", c.gain_m);
    }

    #[test]
    fn a_reset_forgets_the_previous_runs_foot() {
        // Without the re-seed, a run starting lower than the last one ended
        // would open a climb on its very first sample.
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &ascent(0.0, 100.0, 10, 50.0, 5.0)[..10]);
        assert!(d.active().is_some());
        d.reset();
        walk(&mut d, &[(0.0, 2_000.0)]);
        assert!(d.active().is_none());
    }

    #[test]
    fn garbage_samples_cannot_corrupt_the_extremes() {
        let mut d = ClimbDetector::new();
        walk(&mut d, &[(0.0, 100.0)]);
        walk(&mut d, &[(f64::NAN, 500.0), (100.0, f64::INFINITY)]);
        // A backwards distance is not a real step (the recorder's own anchor
        // never goes back), and taking it would make every grade negative.
        walk(&mut d, &[(-500.0, 90.0)]);
        assert!(d.active().is_none());
        walk(&mut d, &ascent(0.0, 100.0, 10, 50.0, 5.0)[..10]);
        let c = d.active().unwrap();
        assert!((c.distance_m - 500.0).abs() < 0.01, "{}", c.distance_m);
    }

    #[test]
    fn the_crest_ahead_is_the_next_summit_not_the_next_step() {
        // A staircase climb: up, a 4 m shelf, up again, then a real descent.
        // The crest is the far summit — a shelf inside a climb is not a top,
        // and reporting it as one would tell a runner they were nearly done
        // halfway up.
        let profile: [i16; 11] = [100, 110, 120, 116, 130, 140, 150, 140, 120, 100, 80];
        let c = crest_ahead(&profile, 1_000.0, 0.0).unwrap();
        assert!((c.gain_m - 50.0).abs() < 0.01, "{}", c.gain_m);
        assert!((c.distance_m - 600.0).abs() < 0.01, "{}", c.distance_m);
        assert!(
            (c.avg_grade_pct - 8.3333).abs() < 0.01,
            "{}",
            c.avg_grade_pct
        );
    }

    #[test]
    fn the_crest_ahead_shrinks_as_the_runner_climbs() {
        let profile: [i16; 11] = [100, 110, 120, 116, 130, 140, 150, 140, 120, 100, 80];
        let start = crest_ahead(&profile, 1_000.0, 0.0).unwrap();
        let later = crest_ahead(&profile, 1_000.0, 400.0).unwrap();
        assert!(later.gain_m < start.gain_m);
        assert!(later.distance_m < start.distance_m);
        assert!((later.gain_m - 20.0).abs() < 0.01, "{}", later.gain_m);
        assert!(
            (later.distance_m - 200.0).abs() < 0.01,
            "{}",
            later.distance_m
        );
    }

    #[test]
    fn a_position_between_samples_measures_from_the_runner() {
        // The crest sits at a grid sample; the runner does not. Rounding the
        // runner to the grid would over-report the distance left by up to a
        // whole step, which on a 100 km course is a kilometre.
        let profile: [i16; 11] = [100, 110, 120, 116, 130, 140, 150, 140, 120, 100, 80];
        let c = crest_ahead(&profile, 1_000.0, 450.0).unwrap();
        assert!((c.distance_m - 150.0).abs() < 0.01, "{}", c.distance_m);
        // The gain is measured from the runner's SAMPLE, which is the only
        // elevation the profile actually gives for where they are.
        assert!((c.gain_m - 20.0).abs() < 0.01, "{}", c.gain_m);
    }

    #[test]
    fn a_descent_has_no_crest_ahead_rather_than_a_crest_at_zero() {
        let profile: [i16; 11] = [100, 110, 120, 116, 130, 140, 150, 140, 120, 100, 80];
        assert_eq!(crest_ahead(&profile, 1_000.0, 700.0), None);
        // Standing exactly on the crest is the same answer.
        assert_eq!(crest_ahead(&profile, 1_000.0, 600.0), None);
    }

    #[test]
    fn a_missing_or_degenerate_profile_answers_nothing() {
        assert_eq!(crest_ahead(&[], 1_000.0, 0.0), None);
        assert_eq!(crest_ahead(&[100], 1_000.0, 0.0), None);
        assert_eq!(crest_ahead(&[100, 200], 0.0, 0.0), None);
        assert_eq!(crest_ahead(&[100, 200], f64::NAN, 0.0), None);
        assert_eq!(crest_ahead(&[100, 200], 1_000.0, f64::NAN), None);
        // Past the end of the course there is nothing ahead to climb.
        assert_eq!(crest_ahead(&[100, 200], 1_000.0, 1_000.0), None);
    }

    #[test]
    fn a_flat_profile_has_no_crest() {
        let flat = [120i16; 16];
        assert_eq!(crest_ahead(&flat, 5_000.0, 0.0), None);
    }

    #[test]
    fn an_empty_view_is_the_pages_presence_bit() {
        assert!(ClimbView::default().is_empty());
        assert!(!ClimbView {
            ahead: Some(CrestAhead {
                distance_m: 100.0,
                gain_m: 20.0,
                avg_grade_pct: 20.0,
            }),
            ..Default::default()
        }
        .is_empty());
    }
}

#[cfg(test)]
mod crest_progress_tests {
    use super::*;

    fn view(banked: f32, left: f32) -> ClimbView {
        ClimbView {
            active: Some(ActiveClimb {
                gain_m: banked,
                distance_m: 1_000.0,
                avg_grade_pct: 10.0,
            }),
            ahead: Some(CrestAhead {
                distance_m: 500.0,
                gain_m: left,
                avg_grade_pct: 12.0,
            }),
        }
    }

    #[test]
    fn banked_over_total_height() {
        assert_eq!(view(220.0, 110.0).crest_progress(), Some(220.0 / 330.0));
        assert_eq!(view(0.0, 100.0).crest_progress(), Some(0.0));
    }

    #[test]
    fn refuses_without_both_halves_or_a_total() {
        let mut only_ahead = view(1.0, 1.0);
        only_ahead.active = None;
        assert_eq!(only_ahead.crest_progress(), None);
        let mut only_active = view(1.0, 1.0);
        only_active.ahead = None;
        assert_eq!(only_active.crest_progress(), None);
        assert_eq!(
            view(0.0, 0.0).crest_progress(),
            None,
            "zero total is a guess"
        );
        assert_eq!(
            view(-5.0, 0.0).crest_progress(),
            None,
            "negatives clamp to no total"
        );
    }

    #[test]
    fn a_crest_passed_mid_update_clamps_to_full() {
        assert_eq!(
            view(f32::INFINITY, 1.0).crest_progress(),
            None,
            "non-finite refuses"
        );
        assert_eq!(view(330.0, 0.0).crest_progress(), Some(1.0));
    }
}
