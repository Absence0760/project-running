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
//! Deliberately even-pace only: grade-aware splitting (Garmin PacePro's
//! terrain allocation, the roadbook's `gradeFactor` effort split) is a later
//! slice on the same seam.
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
}

pub struct Pacer {
    goal: Option<PacerGoal>,
    /// Elapsed seconds at the fix that crossed the goal distance. Latched by
    /// [`on_distance`](Pacer::on_distance) — distance only moves on accepted
    /// fixes, so the crossing is quantised to one fix interval; good enough
    /// for a glance readout, and it can only *under*-report the lead.
    finish_elapsed_s: Option<u32>,
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
        }
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
        Some(match self.finish_elapsed_s {
            Some(finish_s) => {
                let ahead_s = goal.time_s as i64 - finish_s as i64;
                PacerStatus {
                    goal,
                    ahead_m: pace_mps * ahead_s as f64,
                    ahead_s: clamp_i32(ahead_s),
                    projected_finish_s: Some(finish_s),
                    verdict: verdict(goal.distance_m as f64, pace_mps * finish_s as f64),
                    finished: true,
                }
            }
            None => {
                let partner_m = pace_mps * elapsed_s as f64;
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
                    ahead_s: clamp_i32((ahead_m / pace_mps) as i64),
                    projected_finish_s,
                    verdict: verdict(distance_m, partner_m),
                    finished: false,
                }
            }
        })
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
