//! Even-pace target-time virtual partner — the tier-1 pacing-guidance slice.
//!
//! A goal (distance + time) defines a partner running the goal at a perfectly
//! even pace on the **elapsed** clock — a race clock doesn't stop at an aid
//! station, and Garmin's Virtual Partner runs on elapsed time for the same
//! reason, so ahead/behind here answers "will I cross the line by the goal
//! time", not "is my moving pace on target". [`Pacer::status`] reduces the
//! recorder's live distance + elapsed into the partner delta a runner glances
//! at: metres ahead/behind, the same delta as seconds at goal pace, a
//! projected finish at the current whole-run average, and an
//! ahead / on-pace / behind verdict inside the app's shared ±5 % dead-band
//! ([`ON_PACE_BAND`], the `challenge_progress` constant — the same
//! actual-vs-even-line ratio rule, so the watch can't grade "on pace"
//! differently than the app's challenge hint does).
//!
//! The goal is **unset by default** — the pacer is inactive until a
//! plausibility-guarded [`Pacer::set_goal`] arrives (the same future
//! settings-sync hook shape as `Recorder::set_max_hr`; nothing on-device sets
//! it at tier 1). Crossing the goal distance latches the finish: the delta
//! freezes at the banked result instead of drifting while the runner jogs out.
//!
//! With a loaded roadbook the partner is **grade-aware** (Garmin PacePro's
//! terrain allocation): [`Pacer::set_schedule`] takes the roadbook's
//! checkpoint curve — cumulative distance vs projected elapsed, which the
//! phone already allocated by grade-adjusted effort (`roadbook`'s
//! `gradeFactor` split) — and the partner runs that piecewise line instead of
//! the flat one, rescaled to the armed goal so the *shape* (terrain) applies
//! at the goal's overall pace even when the roadbook was built against a
//! different target. No schedule, or a garbage one, degrades to the even-pace
//! partner — the same honest-degrade rule `roadbook` itself uses without
//! elevation.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

/// Plausibility window for a goal distance. Below 100 m a "goal" is a tap
/// error, not a run; above 1000 km is beyond any single recorded effort the
/// tier-1 store could hold. Out-of-window values are ignored, never clamped.
pub const GOAL_DISTANCE_MIN_M: u32 = 100;
pub const GOAL_DISTANCE_MAX_M: u32 = 1_000_000;

/// Plausibility window for a goal time: one minute to ~11.5 days (a 1000 km
/// goal at world-tour ultra pace still fits). Same ignore-don't-clamp rule.
pub const GOAL_TIME_MIN_S: u32 = 60;
pub const GOAL_TIME_MAX_S: u32 = 1_000_000;

/// The on-pace dead-band, as a fraction of the partner's expected distance —
/// the firmware twin of web `challenge_progress.ts` `ON_PACE_BAND` (±5 %),
/// applied to the same actual-vs-even-line ratio so the two surfaces agree on
/// what "on pace" means.
pub const ON_PACE_BAND: f64 = 0.05;

/// Schedule capacity: one point per pushed roadbook checkpoint
/// (`record::MAX_PUSHED_LEGS` is 16) plus headroom for a start point the
/// caller may include (it is skipped, not stored).
pub const MAX_SCHEDULE_POINTS: usize = 17;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PaceVerdict {
    Ahead,
    OnPace,
    Behind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PacerGoal {
    pub distance_m: u32,
    pub time_s: u32,
}

/// The live partner delta, taken by [`Pacer::status`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PacerStatus {
    pub goal: PacerGoal,
    /// Metres ahead of the virtual partner; negative when behind.
    pub ahead_m: f64,
    /// The same delta as time at goal pace: seconds of lead (positive) or
    /// deficit (negative) on the partner.
    pub ahead_s: i32,
    /// Finish time extrapolated from the whole-run average so far (elapsed
    /// clock, like the partner); `None` until there is enough distance to be
    /// meaningful. Once finished, the actual crossing time.
    pub projected_finish_s: Option<u32>,
    /// Ahead / on-pace / behind, with [`ON_PACE_BAND`] treating small drift
    /// as on pace.
    pub verdict: PaceVerdict,
    /// Whether the goal distance has been crossed — the status is frozen at
    /// the crossing from then on.
    pub finished: bool,
    /// Whether the partner ran a terrain-allocated schedule rather than the
    /// flat line — the Pacer page tags the readout so a runner knows the
    /// climb-slow / descend-fast grading is in effect.
    pub terrain_aware: bool,
}

/// One point of the partner's schedule: cumulative course distance reached at
/// an elapsed time. Stored unscaled, exactly as pushed.
#[derive(Clone, Copy, Debug, PartialEq)]
struct SchedulePoint {
    dist_m: f64,
    elapsed_s: f64,
}

pub struct Pacer {
    goal: Option<PacerGoal>,
    /// Elapsed seconds at the fix that crossed the goal distance. Latched by
    /// [`on_distance`](Pacer::on_distance) — distance only moves on accepted
    /// fixes, so the crossing is quantised to one fix interval; good enough
    /// for a glance readout, and it can only *under*-report the lead.
    finish_elapsed_s: Option<u32>,
    /// The terrain schedule ([`set_schedule`](Pacer::set_schedule)); empty
    /// means the even-pace partner.
    schedule: heapless::Vec<SchedulePoint, MAX_SCHEDULE_POINTS>,
}

impl Default for Pacer {
    fn default() -> Self {
        Self::new()
    }
}

impl Pacer {
    pub const fn new() -> Self {
        Self {
            goal: None,
            finish_elapsed_s: None,
            schedule: heapless::Vec::new(),
        }
    }

    /// Load the terrain schedule: the roadbook's `(cumulative distance,
    /// projected elapsed)` checkpoints, in course order. Fail-closed like
    /// every push decoder: a leading start point at `(0, 0)` is skipped, and
    /// anything else non-finite, non-strictly-increasing on either axis, or
    /// longer than [`MAX_SCHEDULE_POINTS`] drops the WHOLE schedule
    /// (truncating mid-course and then rescaling would misread an aid station
    /// as the finish and distort every split). Fewer than two surviving points
    /// carry no shape. Every degenerate case lands on the even-pace partner —
    /// never a stale schedule from a previous course, and never fabricated
    /// terrain.
    pub fn set_schedule(&mut self, points: &[(f64, u32)]) {
        self.schedule.clear();
        let pts = match points.first() {
            Some(&(d, t)) if d == 0.0 && t == 0 => &points[1..],
            _ => points,
        };
        if pts.len() > MAX_SCHEDULE_POINTS {
            return;
        }
        let mut staged: heapless::Vec<SchedulePoint, MAX_SCHEDULE_POINTS> = heapless::Vec::new();
        let (mut prev_d, mut prev_t) = (0.0, 0.0);
        for &(dist_m, elapsed_s) in pts {
            let t = elapsed_s as f64;
            if !dist_m.is_finite() || dist_m <= prev_d || t <= prev_t {
                return;
            }
            let _ = staged.push(SchedulePoint {
                dist_m,
                elapsed_s: t,
            });
            (prev_d, prev_t) = (dist_m, t);
        }
        if staged.len() >= 2 {
            self.schedule = staged;
        }
    }

    /// Drop the terrain schedule — back to the even-pace partner.
    pub fn clear_schedule(&mut self) {
        self.schedule.clear();
    }

    /// Configure the goal — the future settings-sync hook, mirroring
    /// `Recorder::set_max_hr`: values outside the plausibility windows are
    /// ignored so garbage can't arm a nonsense partner. A (re)set goal clears
    /// any latched finish, since the result banked against the old goal means
    /// nothing against the new one.
    pub fn set_goal(&mut self, distance_m: u32, time_s: u32) {
        if (GOAL_DISTANCE_MIN_M..=GOAL_DISTANCE_MAX_M).contains(&distance_m)
            && (GOAL_TIME_MIN_S..=GOAL_TIME_MAX_S).contains(&time_s)
        {
            self.goal = Some(PacerGoal { distance_m, time_s });
            self.finish_elapsed_s = None;
        }
    }

    /// Drop any latched finish for a fresh run; the configured goal stays —
    /// it is settings, not run state (same split as the sticky max HR).
    pub fn reset(&mut self) {
        self.finish_elapsed_s = None;
    }

    /// Observe the run totals after a distance change. The call that carries
    /// the total past the goal distance latches the finish; later calls are
    /// inert.
    pub fn on_distance(&mut self, distance_m: f64, elapsed_s: u32) {
        let Some(goal) = self.goal else { return };
        if self.finish_elapsed_s.is_none() && distance_m >= goal.distance_m as f64 {
            self.finish_elapsed_s = Some(elapsed_s);
        }
    }

    /// The partner delta at the given run totals, or `None` while no goal is
    /// configured (the pacer is inactive, not "on pace at zero").
    pub fn status(&self, distance_m: f64, elapsed_s: u32) -> Option<PacerStatus> {
        let goal = self.goal?;
        let pace_mps = goal.distance_m as f64 / goal.time_s as f64;
        let terrain_aware = !self.schedule.is_empty();
        Some(match self.finish_elapsed_s {
            Some(finish_s) => {
                let ahead_s = goal.time_s as i64 - finish_s as i64;
                let (partner_m, _) = self.partner_at(goal, finish_s as f64);
                PacerStatus {
                    goal,
                    ahead_m: pace_mps * ahead_s as f64,
                    ahead_s: clamp_i32(ahead_s),
                    projected_finish_s: Some(finish_s),
                    verdict: verdict(goal.distance_m as f64, partner_m),
                    finished: true,
                    terrain_aware,
                }
            }
            None => {
                let (partner_m, local_mps) = self.partner_at(goal, elapsed_s as f64);
                let ahead_m = distance_m - partner_m;
                let projected_finish_s = if distance_m >= 1.0 && elapsed_s > 0 {
                    let s = elapsed_s as f64 * goal.distance_m as f64 / distance_m;
                    Some(s.min(u32::MAX as f64) as u32)
                } else {
                    None
                };
                PacerStatus {
                    goal,
                    ahead_m,
                    ahead_s: clamp_i32((ahead_m / local_mps) as i64),
                    projected_finish_s,
                    verdict: verdict(distance_m, partner_m),
                    finished: false,
                    terrain_aware,
                }
            }
        })
    }

    /// Where the partner is at `elapsed` seconds, and its speed there — the
    /// reference line. Even pace without a schedule; with one, the schedule's
    /// piecewise line with both axes rescaled onto the armed goal (the
    /// roadbook's *shape* — terrain — at the goal's overall pace, so a
    /// roadbook built against a different target still grades correctly).
    /// Past the last point the final leg's pace extends, mirroring the even
    /// partner running on past the line. The metres-to-seconds conversion
    /// uses the LOCAL pace so a lead on a climb reads as the time it is
    /// actually worth there.
    fn partner_at(&self, goal: PacerGoal, elapsed: f64) -> (f64, f64) {
        let pace_mps = goal.distance_m as f64 / goal.time_s as f64;
        let Some(last) = self.schedule.last() else {
            return (pace_mps * elapsed, pace_mps);
        };
        let scale_d = goal.distance_m as f64 / last.dist_m;
        let scale_t = goal.time_s as f64 / last.elapsed_s;
        let (mut prev_d, mut prev_t) = (0.0, 0.0);
        for p in &self.schedule {
            let (d, t) = (p.dist_m * scale_d, p.elapsed_s * scale_t);
            if elapsed <= t {
                let slope = (d - prev_d) / (t - prev_t);
                return (prev_d + slope * (elapsed - prev_t), slope);
            }
            (prev_d, prev_t) = (d, t);
        }
        // Past the finish: the validated schedule has >= 2 points, so the
        // final leg's slope is well-defined.
        let n = self.schedule.len();
        let (d1, t1) = (
            self.schedule[n - 1].dist_m * scale_d,
            self.schedule[n - 1].elapsed_s * scale_t,
        );
        let (d0, t0) = (
            self.schedule[n - 2].dist_m * scale_d,
            self.schedule[n - 2].elapsed_s * scale_t,
        );
        let slope = (d1 - d0) / (t1 - t0);
        (d1 + slope * (elapsed - t1), slope)
    }
}

/// The `challenge_progress` verdict rule on the actual-vs-expected ratio:
/// ahead at or past `1 + ON_PACE_BAND`, behind under `1 - ON_PACE_BAND`,
/// on pace between — and on pace while the partner hasn't left the line yet
/// (expected 0), where the ratio is undefined.
fn verdict(actual_m: f64, expected_m: f64) -> PaceVerdict {
    if expected_m <= 0.0 {
        return PaceVerdict::OnPace;
    }
    let ratio = actual_m / expected_m;
    if ratio >= 1.0 + ON_PACE_BAND {
        PaceVerdict::Ahead
    } else if ratio < 1.0 - ON_PACE_BAND {
        PaceVerdict::Behind
    } else {
        PaceVerdict::OnPace
    }
}

fn clamp_i32(v: i64) -> i32 {
    if v > i32::MAX as i64 {
        i32::MAX
    } else if v < i32::MIN as i64 {
        i32::MIN
    } else {
        v as i32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn goal_10k_50min() -> Pacer {
        let mut p = Pacer::new();
        p.set_goal(10_000, 3_000); // 5:00/km partner, ~3.333 m/s
        p
    }

    #[test]
    fn unset_goal_yields_no_status() {
        let p = Pacer::new();
        assert!(p.status(5_000.0, 1_500).is_none());
    }

    #[test]
    fn set_goal_rejects_implausible_values() {
        let mut p = Pacer::new();
        p.set_goal(GOAL_DISTANCE_MIN_M - 1, 600);
        p.set_goal(GOAL_DISTANCE_MAX_M + 1, 600);
        p.set_goal(10_000, GOAL_TIME_MIN_S - 1);
        p.set_goal(10_000, GOAL_TIME_MAX_S + 1);
        p.set_goal(0, 0);
        assert!(p.status(0.0, 0).is_none(), "garbage must not arm the pacer");

        p.set_goal(GOAL_DISTANCE_MIN_M, GOAL_TIME_MIN_S);
        let st = p.status(0.0, 0).unwrap();
        assert_eq!(
            st.goal,
            PacerGoal {
                distance_m: GOAL_DISTANCE_MIN_M,
                time_s: GOAL_TIME_MIN_S
            }
        );

        // A later garbage call keeps the armed goal, mirroring set_max_hr.
        p.set_goal(0, 0);
        assert_eq!(
            p.status(0.0, 0).unwrap().goal.distance_m,
            GOAL_DISTANCE_MIN_M
        );
    }

    #[test]
    fn start_line_reads_on_pace_not_behind() {
        let p = goal_10k_50min();
        let st = p.status(0.0, 0).unwrap();
        assert_eq!(st.verdict, PaceVerdict::OnPace);
        assert_eq!(st.ahead_m, 0.0);
        assert_eq!(st.ahead_s, 0);
        assert_eq!(st.projected_finish_s, None, "no distance, no projection");
        assert!(!st.finished);
    }

    #[test]
    fn ahead_metres_and_seconds_agree_via_goal_pace() {
        let p = goal_10k_50min();
        // 600 s in: partner at 2000 m, runner at 2100 m -> +100 m = +30 s.
        let st = p.status(2_100.0, 600).unwrap();
        assert!((st.ahead_m - 100.0).abs() < 1e-9);
        assert_eq!(st.ahead_s, 30);
        // Behind mirrors the sign: 1900 m -> -100 m = -30 s.
        let st = p.status(1_900.0, 600).unwrap();
        assert!((st.ahead_m + 100.0).abs() < 1e-9);
        assert_eq!(st.ahead_s, -30);
    }

    #[test]
    fn verdict_band_matches_challenge_progress() {
        let p = goal_10k_50min();
        // Partner at 2000 m: the band edges sit at exactly 2100 / 1900 m.
        assert_eq!(p.status(2_100.0, 600).unwrap().verdict, PaceVerdict::Ahead);
        assert_eq!(
            p.status(2_099.0, 600).unwrap().verdict,
            PaceVerdict::OnPace,
            "just inside the +5% edge"
        );
        assert_eq!(
            p.status(1_900.0, 600).unwrap().verdict,
            PaceVerdict::OnPace,
            "the -5% edge itself is still on pace (ratio < 1 - band is behind)"
        );
        assert_eq!(p.status(1_899.0, 600).unwrap().verdict, PaceVerdict::Behind);
    }

    #[test]
    fn projected_finish_extrapolates_the_whole_run_average() {
        let p = goal_10k_50min();
        // 2500 m in 600 s -> 10 km at that average lands at 2400 s.
        let st = p.status(2_500.0, 600).unwrap();
        assert_eq!(st.projected_finish_s, Some(2_400));
        // Slower than goal projects past the target.
        let st = p.status(1_800.0, 600).unwrap();
        assert!(st.projected_finish_s.unwrap() > 3_000);
    }

    #[test]
    fn finish_latches_on_the_crossing_and_freezes() {
        let mut p = goal_10k_50min();
        p.on_distance(9_990.0, 2_800);
        assert!(!p.status(9_990.0, 2_800).unwrap().finished);

        p.on_distance(10_004.0, 2_820);
        let st = p.status(10_004.0, 2_820).unwrap();
        assert!(st.finished);
        assert_eq!(st.ahead_s, 180, "banked 3:00 under the 50:00 goal");
        assert_eq!(st.projected_finish_s, Some(2_820));
        assert_eq!(st.verdict, PaceVerdict::Ahead);

        // Jogging out past the line moves nothing.
        p.on_distance(11_000.0, 3_500);
        assert_eq!(p.status(11_000.0, 3_500).unwrap(), st);
    }

    #[test]
    fn finishing_near_the_goal_time_reads_on_pace() {
        let mut p = goal_10k_50min();
        // 2% under goal: inside the band, honest "on pace", still +60 s.
        p.on_distance(10_001.0, 2_940);
        let st = p.status(10_001.0, 2_940).unwrap();
        assert!(st.finished);
        assert_eq!(st.ahead_s, 60);
        assert_eq!(st.verdict, PaceVerdict::OnPace);
    }

    #[test]
    fn behind_then_catch_up_flips_the_verdict_back() {
        let p = goal_10k_50min();
        // Stalled at the start: 0 m while the partner runs 300 s out.
        let st = p.status(0.0, 300).unwrap();
        assert_eq!(st.verdict, PaceVerdict::Behind);
        assert_eq!(st.ahead_s, -300, "a full stop reads as the elapsed deficit");
        // Catching back up: 3400 m at 1000 s vs the partner's 3333 m.
        let st = p.status(3_400.0, 1_000).unwrap();
        assert_eq!(st.verdict, PaceVerdict::OnPace);
        assert!(st.ahead_s > 0 && st.ahead_s < 30);
        // Overtaking past the band.
        assert_eq!(
            p.status(3_600.0, 1_000).unwrap().verdict,
            PaceVerdict::Ahead
        );
    }

    #[test]
    fn reset_clears_the_latch_but_keeps_the_goal() {
        let mut p = goal_10k_50min();
        p.on_distance(10_000.0, 2_820);
        assert!(p.status(10_000.0, 2_820).unwrap().finished);
        p.reset();
        let st = p.status(0.0, 0).unwrap();
        assert!(!st.finished, "the latch is run state and resets");
        assert_eq!(st.goal.distance_m, 10_000, "the goal is settings and stays");
    }

    #[test]
    fn setting_a_new_goal_drops_a_stale_finish() {
        let mut p = goal_10k_50min();
        p.on_distance(10_000.0, 2_820);
        p.set_goal(21_097, 6_300);
        let st = p.status(10_000.0, 2_900).unwrap();
        assert!(!st.finished, "a result banked against the old goal is void");
        assert_eq!(st.goal.distance_m, 21_097);
    }

    #[test]
    fn multi_day_ultra_does_not_overflow() {
        let mut p = Pacer::new();
        // 1000 km in ~11.5 days — the top of both plausibility windows, 1 m/s.
        p.set_goal(GOAL_DISTANCE_MAX_M, GOAL_TIME_MAX_S);
        // Deep into the effort but not yet finished: the f64/i64 arithmetic must
        // stay finite and produce a sane projection, never wrap or NaN.
        let st = p.status(500_000.0, 500_000).unwrap();
        assert!(st.ahead_m.is_finite());
        assert_eq!(st.projected_finish_s, Some(1_000_000));
        assert!(!st.finished);
        // A finish latched at a huge elapsed (~136 years) clamps rather than
        // wrapping the seconds delta or the projected finish.
        p.on_distance(GOAL_DISTANCE_MAX_M as f64, u32::MAX);
        let st = p.status(GOAL_DISTANCE_MAX_M as f64, u32::MAX).unwrap();
        assert!(st.finished);
        assert_eq!(st.projected_finish_s, Some(u32::MAX));
        assert_eq!(
            st.ahead_s,
            i32::MIN,
            "a finish this late clamps, never wraps"
        );
        assert!(st.ahead_m.is_finite());
        assert_eq!(st.verdict, PaceVerdict::Behind);
    }

    /// A 10 km / 50:00 goal whose first half is a climb the roadbook allocated
    /// 2000 s (of 3000) to: the terrain partner runs 2.5 m/s up, 5 m/s down.
    fn goal_10k_climb_first() -> Pacer {
        let mut p = goal_10k_50min();
        p.set_schedule(&[(0.0, 0), (5_000.0, 2_000), (10_000.0, 3_000)]);
        p
    }

    #[test]
    fn without_a_schedule_the_partner_is_even_and_untagged() {
        let p = goal_10k_50min();
        let st = p.status(2_100.0, 600).unwrap();
        assert!(!st.terrain_aware);
        assert!((st.ahead_m - 100.0).abs() < 1e-9);
        assert_eq!(st.ahead_s, 30);
    }

    #[test]
    fn terrain_partner_is_slow_on_the_climb() {
        let p = goal_10k_climb_first();
        // 1000 s up the climb: terrain partner at 2500 m, even would be 3333 m.
        // A runner at 2500 m is executing perfectly — on pace, not behind.
        let st = p.status(2_500.0, 1_000).unwrap();
        assert!(st.terrain_aware);
        assert!((st.ahead_m - 0.0).abs() < 1e-9);
        assert_eq!(st.verdict, PaceVerdict::OnPace);
        // The even partner would have graded the same runner behind.
        let even = goal_10k_50min().status(2_500.0, 1_000).unwrap();
        assert_eq!(even.verdict, PaceVerdict::Behind);
    }

    #[test]
    fn terrain_partner_is_fast_on_the_descent() {
        let p = goal_10k_climb_first();
        // 2500 s in: 2000 s of climb + 500 s at 5 m/s -> partner at 7500 m.
        let st = p.status(7_500.0, 2_500).unwrap();
        assert!((st.ahead_m - 0.0).abs() < 1e-9);
        assert_eq!(st.verdict, PaceVerdict::OnPace);
        // Even pace (8333 m) on the descent would flatter a 7900 m runner:
        // terrain grades them ahead of schedule, even grades them behind.
        assert_eq!(
            p.status(7_900.0, 2_500).unwrap().verdict,
            PaceVerdict::Ahead
        );
        let even = goal_10k_50min().status(7_900.0, 2_500).unwrap();
        assert_eq!(even.verdict, PaceVerdict::Behind);
    }

    #[test]
    fn ahead_seconds_use_the_local_pace() {
        let p = goal_10k_climb_first();
        // On the climb (2.5 m/s) a +100 m lead is worth 40 s, not the flat 30.
        let st = p.status(1_600.0, 600).unwrap();
        assert!((st.ahead_m - 100.0).abs() < 1e-9);
        assert_eq!(st.ahead_s, 40);
    }

    #[test]
    fn schedule_rescales_onto_the_armed_goal() {
        let mut p = goal_10k_50min();
        // A roadbook built against a 5 km / 25:00 target with the same
        // climb-first shape: both axes scale x2 onto the 10 km / 50:00 goal.
        p.set_schedule(&[(2_500.0, 1_000), (5_000.0, 1_500)]);
        let st = p.status(2_500.0, 1_000).unwrap();
        assert!(st.terrain_aware);
        assert!((st.ahead_m - 0.0).abs() < 1e-9, "scaled climb leg holds");
    }

    #[test]
    fn partner_extends_past_the_finish_at_the_final_leg_pace() {
        let p = goal_10k_climb_first();
        // 100 s past the goal time: partner ran on at the descent's 5 m/s.
        let (partner_m, mps) = p.partner_at(
            PacerGoal {
                distance_m: 10_000,
                time_s: 3_000,
            },
            3_100.0,
        );
        assert!((partner_m - 10_500.0).abs() < 1e-9);
        assert!((mps - 5.0).abs() < 1e-9);
    }

    #[test]
    fn garbage_schedules_degrade_to_the_even_partner() {
        for garbage in [
            // Non-monotonic distance, non-monotonic time, non-finite.
            &[(5_000.0, 1_000), (4_000.0, 2_000)][..],
            &[(5_000.0, 2_000), (10_000.0, 1_000)][..],
            &[(f64::NAN, 1_000), (10_000.0, 3_000)][..],
        ] {
            let mut p = goal_10k_climb_first();
            p.set_schedule(garbage);
            let st = p.status(2_500.0, 1_000).unwrap();
            assert!(
                !st.terrain_aware,
                "a garbage push must drop terrain entirely, not keep a stale course: {garbage:?}"
            );
            assert_eq!(st.verdict, PaceVerdict::Behind, "even-pace grading again");
        }
    }

    #[test]
    fn a_single_point_schedule_carries_no_shape_and_degrades_to_even() {
        let mut p = goal_10k_climb_first();
        // A 1-checkpoint roadbook replaces the old one but has no terrain.
        p.set_schedule(&[(10_000.0, 3_000)]);
        let st = p.status(2_100.0, 600).unwrap();
        assert!(!st.terrain_aware);
        assert_eq!(st.ahead_s, 30, "flat conversion again");
    }

    #[test]
    fn clear_schedule_returns_to_the_even_partner() {
        let mut p = goal_10k_climb_first();
        p.clear_schedule();
        assert!(!p.status(2_500.0, 1_000).unwrap().terrain_aware);
        assert_eq!(
            p.status(2_500.0, 1_000).unwrap().verdict,
            PaceVerdict::Behind
        );
    }

    #[test]
    fn finish_latch_grades_against_the_terrain_line() {
        let mut p = goal_10k_climb_first();
        p.on_distance(10_002.0, 2_850);
        let st = p.status(10_002.0, 2_850).unwrap();
        assert!(st.finished);
        assert!(st.terrain_aware);
        assert_eq!(st.ahead_s, 150, "banked 2:30 under the goal");
        // 2850 s on the terrain line = 5000 + 850*5 = 9250 m expected; the
        // 10 km crossing is ~8% past it — Ahead, same as the flat grade here.
        assert_eq!(st.verdict, PaceVerdict::Ahead);
    }

    #[test]
    fn on_distance_without_a_goal_is_inert() {
        let mut p = Pacer::new();
        p.on_distance(10_000.0, 2_820);
        p.set_goal(10_000, 3_000);
        assert!(
            !p.status(9_000.0, 2_900).unwrap().finished,
            "a crossing observed before the goal existed must not latch"
        );
    }
}
