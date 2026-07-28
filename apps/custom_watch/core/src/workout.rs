//! Structured-workout execution — the step state machine that runs a planned
//! workout (warmup → reps → recoveries → cooldown) on the wrist.
//!
//! Parity port of the mobile runner state machine
//! (`packages/run_recorder/lib/src/workout_runner.dart`, spec
//! `docs/features/workout_execution.md`): the same per-step anchors, the same
//! auto-advance loop that carries overshoot across several steps in one
//! update, the same end-of-step warning window, the same pace-adherence
//! bands, and the same ≥80 % completed-for-adherence roll-up. Steps arrive
//! **pre-expanded**: `expandWorkoutSteps` needs the plan's structure + paces
//! bag, which live on the phone — the watch receives the flat step list over
//! the `WKT1` push ([`crate::workout_store`]), the same pushed-pre-built model
//! as the roadbook.
//!
//! What is deliberately NOT ported, and why:
//! - **Rewind + abandon** — both need a button the §350 grammar doesn't have
//!   spare mid-run. Skip rides the lap button (Garmin's own semantics: the lap
//!   press advances the step); a runner done with the workout just stops the
//!   run or stops glancing at the page.
//! - **The halfway progress cue** — a display-only banner has no chime to
//!   carry it, and the page's live progress already says "past half". The
//!   end-of-step warning IS ported (it is the time-critical one: get ready).
//! - **Pace-drift events** — the configured pace-band alert and this page's
//!   adherence flag own that surface on the watch.
//! - **The Dart event stream** — a `no_std` core carries no streams. Edges
//!   travel as monotonic counters in [`WorkoutView`] ([`transition_seq`,
//!   `ending_seq`](WorkoutView)); the alert engine fires a banner when one
//!   advances, which is the same once-per-edge contract.
//!
//! Time axis: the phone runner reads the recorder's stopwatch, which halts
//! during a manual pause but runs through an auto-pause. The recorder feeds
//! this runner the equivalent workout clock (elapsed minus manually-paused
//! seconds) so a standing rest inside a timed recovery still counts — resting
//! is what the step is for — while a manual pause freezes the step exactly
//! like the phone.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// Step-list capacity, sized for real plans with headroom: 6×400 expands to
/// 14 steps, a C25K session to 17, a 20×400 track session to 41.
pub const MAX_WORKOUT_STEPS: usize = 64;

/// Distance steps warn inside the last 50 m ([`WorkoutView::ending_seq`]),
/// gated to steps long enough that the warning doesn't collide with the
/// step's own start.
pub const ENDING_WINDOW_M: f64 = 50.0;
pub const ENDING_MIN_STEP_M: f64 = 100.0;

/// Duration steps warn inside the last 10 s, gated to steps over 20 s.
pub const ENDING_WINDOW_S: f64 = 10.0;
pub const ENDING_MIN_STEP_S: f64 = 20.0;

/// A completed step counts toward a clean adherence roll-up at ≥80 % of its
/// target on its own end axis — the mobile/web review section's cutoff.
const ADHERENCE_COMPLETED_FRACTION: f64 = 0.8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WorkoutStepKind {
    Warmup,
    Rep,
    Recovery,
    /// A walk-run rest interval (`recovery_pace == 'walk'` phone-side) — same
    /// mechanics as `Recovery`, labelled WALK.
    Walk,
    Steady,
    Cooldown,
}

impl WorkoutStepKind {
    /// Wire code, in the Dart enum's declaration order.
    pub fn code(self) -> u8 {
        match self {
            WorkoutStepKind::Warmup => 0,
            WorkoutStepKind::Rep => 1,
            WorkoutStepKind::Recovery => 2,
            WorkoutStepKind::Walk => 3,
            WorkoutStepKind::Steady => 4,
            WorkoutStepKind::Cooldown => 5,
        }
    }

    /// Decode a wire code; `None` for anything outside the known space, so a
    /// corrupt step can't render as some arbitrary kind.
    pub fn from_code(code: u8) -> Option<Self> {
        Some(match code {
            0 => WorkoutStepKind::Warmup,
            1 => WorkoutStepKind::Rep,
            2 => WorkoutStepKind::Recovery,
            3 => WorkoutStepKind::Walk,
            4 => WorkoutStepKind::Steady,
            5 => WorkoutStepKind::Cooldown,
            _ => return None,
        })
    }
}

/// One expanded workout step. Exactly one end axis is set: a distance step
/// carries `target_distance_m > 0` and `target_duration_s == 0`, a duration
/// step the reverse — the phone's expander never emits both, and the wire
/// decode rejects a step with neither. No label string: the kind + rep
/// numbering are identifiers the face renders, the [`crate::guided_runs`]
/// convention.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WorkoutStep {
    pub kind: WorkoutStepKind,
    /// 1-based rep / recovery numbering; 0 = not part of a repeat group.
    pub rep_index: u8,
    pub rep_total: u8,
    pub target_distance_m: u32,
    pub target_duration_s: u16,
    pub target_pace_s_per_km: u16,
    pub tolerance_s_per_km: u16,
}

impl WorkoutStep {
    pub fn is_duration_based(&self) -> bool {
        self.target_duration_s > 0
    }
}

/// Live pace vs the step's target ± tolerance: inside the band, inside twice
/// the band, or beyond it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PaceAdherence {
    OnPace,
    Ahead,
    Behind,
    WayAhead,
    WayBehind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum StepStatus {
    Completed,
    Skipped,
}

/// The roll-up verdict once every step is accounted for. No `Abandoned` —
/// abandon isn't ported (module docs).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WorkoutAdherence {
    Completed,
    Partial,
}

/// What one step actually banked, recorded when the runner advances off it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StepResult {
    pub step_index: u8,
    pub status: StepStatus,
    pub actual_distance_m: f64,
    pub actual_duration_s: f64,
    /// Whole-step average pace, gated like the live one (≥5 m and ≥1 s).
    pub actual_pace_s_per_km: Option<u16>,
}

/// The `Copy` view the recorder snapshot carries for the Workout page + the
/// alert engine. All-integer so the snapshot's equality check stays exact.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkoutView {
    /// 0-based position of the active step (clamped to the last once done).
    pub step_index: u8,
    pub step_total: u8,
    pub kind: WorkoutStepKind,
    pub rep_index: u8,
    pub rep_total: u8,
    pub duration_based: bool,
    pub target_distance_m: u32,
    pub target_duration_s: u16,
    pub target_pace_s_per_km: u16,
    pub step_distance_m: u32,
    pub step_elapsed_s: u32,
    /// Metres left on a distance step, 0 on a duration step.
    pub remaining_m: u32,
    /// Seconds left on a duration step, 0 on a distance step.
    pub remaining_s: u32,
    /// Progress along the step's own end condition, 0..=1000.
    pub progress_permille: u16,
    pub step_pace_s_per_km: Option<u16>,
    pub adherence: PaceAdherence,
    /// The kind + axis of the step after this one, for the NEXT row; `None`
    /// on the last step.
    pub next: Option<NextStep>,
    pub complete: bool,
    /// The roll-up verdict, present once [`complete`](WorkoutView::complete).
    pub rollup: Option<WorkoutAdherence>,
    /// Increments each time a step is entered (the first included) — the
    /// alert engine's step-transition edge. 0 until the run starts feeding.
    pub transition_seq: u16,
    /// Increments when a step enters its end-of-step warning window.
    pub ending_seq: u16,
}

/// The NEXT-row preview: what the following step asks for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NextStep {
    pub kind: WorkoutStepKind,
    pub rep_index: u8,
    pub rep_total: u8,
    pub target_distance_m: u32,
    pub target_duration_s: u16,
}

pub struct WorkoutRunner {
    steps: Vec<WorkoutStep, MAX_WORKOUT_STEPS>,
    idx: usize,
    step_start_distance_m: f64,
    step_start_clock_s: f64,
    /// Latest fed totals `(distance_m, clock_s)`; `None` until the first feed.
    last: Option<(f64, f64)>,
    started: bool,
    fired_ending: bool,
    results: Vec<StepResult, MAX_WORKOUT_STEPS>,
    transition_seq: u16,
    ending_seq: u16,
}

impl WorkoutRunner {
    /// Arm a runner over a pre-expanded step list. `None` when the list is
    /// empty or over [`MAX_WORKOUT_STEPS`] — fail-closed, the caller keeps
    /// whatever was armed before.
    pub fn new(steps: &[WorkoutStep]) -> Option<Self> {
        if steps.is_empty() || steps.len() > MAX_WORKOUT_STEPS {
            return None;
        }
        let mut v = Vec::new();
        for s in steps {
            v.push(*s).ok()?;
        }
        Some(Self {
            steps: v,
            idx: 0,
            step_start_distance_m: 0.0,
            step_start_clock_s: 0.0,
            last: None,
            started: false,
            fired_ending: false,
            results: Vec::new(),
            transition_seq: 0,
            ending_seq: 0,
        })
    }

    /// Re-arm for a fresh run: back to step 0, results cleared, edges reset.
    /// The step list stays — a pushed workout is configuration, like the
    /// pacer goal.
    pub fn reset(&mut self) {
        self.idx = 0;
        self.step_start_distance_m = 0.0;
        self.step_start_clock_s = 0.0;
        self.last = None;
        self.started = false;
        self.fired_ending = false;
        self.results.clear();
        self.transition_seq = 0;
        self.ending_seq = 0;
    }

    pub fn is_complete(&self) -> bool {
        self.idx >= self.steps.len()
    }

    fn step_distance_m(&self) -> f64 {
        match self.last {
            Some((d, _)) => (d - self.step_start_distance_m).max(0.0),
            None => 0.0,
        }
    }

    fn step_elapsed_s(&self) -> f64 {
        match self.last {
            Some((_, c)) => (c - self.step_start_clock_s).max(0.0),
            None => 0.0,
        }
    }

    /// Whole-step average pace so far, mirroring the phone's gates: at least
    /// 5 m and a whole second, else no pace.
    fn step_pace_s_per_km(&self) -> Option<u16> {
        let d = self.step_distance_m();
        let el = trunc_s(self.step_elapsed_s());
        if d < 5.0 || el < 1.0 {
            return None;
        }
        Some(round_pace(el, d))
    }

    fn pace_adherence(&self) -> PaceAdherence {
        let Some(step) = self.steps.get(self.idx) else {
            return PaceAdherence::OnPace;
        };
        let Some(actual) = self.step_pace_s_per_km() else {
            return PaceAdherence::OnPace;
        };
        let diff = i32::from(actual) - i32::from(step.target_pace_s_per_km);
        let tol = i32::from(step.tolerance_s_per_km);
        if diff.abs() <= tol {
            return PaceAdherence::OnPace;
        }
        if diff.abs() <= tol * 2 {
            return if diff > 0 {
                PaceAdherence::Behind
            } else {
                PaceAdherence::Ahead
            };
        }
        if diff > 0 {
            PaceAdherence::WayBehind
        } else {
            PaceAdherence::WayAhead
        }
    }

    /// Feed the live totals — the recorder's distance and its workout clock
    /// (module docs). Anchors the first step on the first call, fires the
    /// end-of-step warning once per step, and auto-advances through every
    /// step the update's overshoot covers.
    pub fn on_totals(&mut self, distance_m: f64, clock_s: u32) {
        let clock_s = f64::from(clock_s);
        self.last = Some((distance_m, clock_s));

        if !self.started {
            self.started = true;
            self.step_start_distance_m = distance_m;
            self.step_start_clock_s = clock_s;
            if !self.is_complete() {
                self.transition_seq = self.transition_seq.wrapping_add(1);
            }
        }
        if self.is_complete() {
            return;
        }

        let step = self.steps[self.idx];
        let ending_hit = if step.is_duration_based() {
            let target = f64::from(step.target_duration_s);
            target - trunc_s(self.step_elapsed_s()) <= ENDING_WINDOW_S && target > ENDING_MIN_STEP_S
        } else {
            let target = f64::from(step.target_distance_m);
            target - self.step_distance_m() <= ENDING_WINDOW_M && target > ENDING_MIN_STEP_M
        };
        if !self.fired_ending && ending_hit {
            self.fired_ending = true;
            self.ending_seq = self.ending_seq.wrapping_add(1);
        }

        // Auto-advance, carrying the overshoot forward: one update can cover
        // more than one step's target (duration steps shorter than the tick
        // interval, or a distance jump past a short rep + its recovery after
        // a GPS gap). Bounded — each iteration increments `idx`.
        while !self.is_complete() {
            let cur = self.steps[self.idx];
            let hit = if cur.is_duration_based() {
                self.step_elapsed_s() >= f64::from(cur.target_duration_s)
            } else {
                self.step_distance_m() >= f64::from(cur.target_distance_m)
            };
            if !hit {
                break;
            }
            self.advance(StepStatus::Completed, true);
        }
    }

    /// Skip the current step — what's covered so far is recorded as skipped
    /// and the next step starts fresh from the current totals. The lap-button
    /// hook (Garmin's lap-press-advances-the-step semantics). No-op before
    /// the first feed or once complete.
    pub fn skip_step(&mut self) {
        if self.is_complete() || self.last.is_none() {
            return;
        }
        self.advance(StepStatus::Skipped, false);
    }

    /// Advance off the current step. Auto-completion (`carry_overshoot`)
    /// records exactly the step's target on its end axis with the off axis
    /// allocated proportionally (constant-pace assumption), and anchors the
    /// next step at that consumed boundary so the overshoot flows into it. A
    /// skip records what was covered and anchors fresh at the current totals.
    fn advance(&mut self, status: StepStatus, carry_overshoot: bool) {
        let step = self.steps[self.idx];
        let covered_distance = self.step_distance_m();
        let covered_elapsed = self.step_elapsed_s();

        let (consumed_distance, consumed_elapsed) = if carry_overshoot {
            if step.is_duration_based() {
                let consumed = f64::from(step.target_duration_s);
                let ratio = if covered_elapsed > 0.0 {
                    (consumed / covered_elapsed).clamp(0.0, 1.0)
                } else {
                    1.0
                };
                (covered_distance * ratio, consumed)
            } else {
                let consumed = f64::from(step.target_distance_m);
                let ratio = if covered_distance > 0.0 {
                    (consumed / covered_distance).clamp(0.0, 1.0)
                } else {
                    1.0
                };
                (consumed, covered_elapsed * ratio)
            }
        } else {
            (covered_distance, covered_elapsed)
        };

        let _ = self.results.push(result_for(
            self.idx as u8,
            consumed_distance,
            consumed_elapsed,
            status,
        ));

        self.idx += 1;
        if carry_overshoot {
            self.step_start_distance_m += consumed_distance;
            self.step_start_clock_s += consumed_elapsed;
        } else if let Some((d, c)) = self.last {
            self.step_start_distance_m = d;
            self.step_start_clock_s = c;
        }
        self.fired_ending = false;
        if !self.is_complete() {
            self.transition_seq = self.transition_seq.wrapping_add(1);
        }
    }

    /// Every step's outcome, the in-progress one included as skipped-so-far —
    /// the same convention the phone uses for its crash-checkpoint trail.
    pub fn snapshot_results(&self) -> Vec<StepResult, MAX_WORKOUT_STEPS> {
        let mut out = self.results.clone();
        if !self.is_complete() && self.last.is_some() {
            let _ = out.push(result_for(
                self.idx as u8,
                self.step_distance_m(),
                self.step_elapsed_s(),
                StepStatus::Skipped,
            ));
        }
        out
    }

    /// The roll-up: `Completed` when every step ran to ≥80 % of its target on
    /// its own end axis and nothing was skipped, else `Partial`.
    pub fn rollup(&self) -> WorkoutAdherence {
        let results = self.snapshot_results();
        if results.is_empty() {
            return WorkoutAdherence::Partial;
        }
        let mut any_short = results.len() < self.steps.len();
        for r in &results {
            if r.status == StepStatus::Skipped {
                any_short = true;
                continue;
            }
            let step = self.steps[r.step_index as usize];
            if step.is_duration_based() {
                if trunc_s(r.actual_duration_s)
                    < f64::from(step.target_duration_s) * ADHERENCE_COMPLETED_FRACTION
                {
                    any_short = true;
                }
            } else if r.actual_distance_m
                < f64::from(step.target_distance_m) * ADHERENCE_COMPLETED_FRACTION
            {
                any_short = true;
            }
        }
        if any_short {
            WorkoutAdherence::Partial
        } else {
            WorkoutAdherence::Completed
        }
    }

    /// The page's / alert engine's view of where the workout stands. Complete
    /// runs keep the last step's identity under the DONE state.
    pub fn view(&self) -> WorkoutView {
        let shown_idx = self.idx.min(self.steps.len() - 1);
        let step = self.steps[shown_idx];
        let complete = self.is_complete();
        let step_distance = self.step_distance_m();
        let step_elapsed = self.step_elapsed_s();
        let (remaining_m, remaining_s, progress) = if complete {
            (0, 0, 1000)
        } else if step.is_duration_based() {
            let target = f64::from(step.target_duration_s);
            let left = (target - trunc_s(step_elapsed)).max(0.0);
            (0, left as u32, permille(trunc_s(step_elapsed), target))
        } else {
            let target = f64::from(step.target_distance_m);
            let left = (target - step_distance).max(0.0);
            (left as u32, 0, permille(step_distance, target))
        };
        WorkoutView {
            step_index: shown_idx as u8,
            step_total: self.steps.len() as u8,
            kind: step.kind,
            rep_index: step.rep_index,
            rep_total: step.rep_total,
            duration_based: step.is_duration_based(),
            target_distance_m: step.target_distance_m,
            target_duration_s: step.target_duration_s,
            target_pace_s_per_km: step.target_pace_s_per_km,
            step_distance_m: if complete { 0 } else { step_distance as u32 },
            step_elapsed_s: if complete { 0 } else { step_elapsed as u32 },
            remaining_m,
            remaining_s,
            progress_permille: progress,
            step_pace_s_per_km: if complete {
                None
            } else {
                self.step_pace_s_per_km()
            },
            adherence: if complete {
                PaceAdherence::OnPace
            } else {
                self.pace_adherence()
            },
            next: if complete {
                None
            } else {
                self.steps.get(self.idx + 1).map(|n| NextStep {
                    kind: n.kind,
                    rep_index: n.rep_index,
                    rep_total: n.rep_total,
                    target_distance_m: n.target_distance_m,
                    target_duration_s: n.target_duration_s,
                })
            },
            complete,
            rollup: if complete { Some(self.rollup()) } else { None },
            transition_seq: self.transition_seq,
            ending_seq: self.ending_seq,
        }
    }
}

fn result_for(step_index: u8, distance_m: f64, elapsed_s: f64, status: StepStatus) -> StepResult {
    let secs = trunc_s(elapsed_s);
    let pace = if distance_m >= 5.0 && secs >= 1.0 {
        Some(round_pace(secs, distance_m))
    } else {
        None
    };
    StepResult {
        step_index,
        status,
        actual_distance_m: distance_m,
        actual_duration_s: elapsed_s,
        actual_pace_s_per_km: pace,
    }
}

/// Whole seconds, the phone's `Duration.inSeconds` truncation — adherence and
/// pace gates compare on the same boundary the Dart runner does.
fn trunc_s(s: f64) -> f64 {
    libm::floor(s.max(0.0))
}

fn round_pace(elapsed_s: f64, distance_m: f64) -> u16 {
    libm::round(elapsed_s / (distance_m / 1000.0)).clamp(0.0, f64::from(u16::MAX)) as u16
}

fn permille(done: f64, target: f64) -> u16 {
    if target <= 0.0 {
        return 1000;
    }
    (done / target * 1000.0).clamp(0.0, 1000.0) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of the runner half of
    /// `packages/run_recorder/test/workout_runner_test.dart` — same
    /// scenarios, same expected values, so the ports can't drift. The
    /// expansion suite is not mirrored (expansion runs phone-side; the watch
    /// receives pre-expanded steps), and the rewind / abandon / halfway /
    /// event-stream cases cover behaviour deliberately not ported (module
    /// docs).
    fn dist_step(distance_m: u32) -> WorkoutStep {
        WorkoutStep {
            kind: WorkoutStepKind::Rep,
            rep_index: 0,
            rep_total: 0,
            target_distance_m: distance_m,
            target_duration_s: 0,
            target_pace_s_per_km: 240,
            tolerance_s_per_km: 10,
        }
    }

    fn dur_step(duration_s: u16) -> WorkoutStep {
        WorkoutStep {
            kind: WorkoutStepKind::Rep,
            rep_index: 0,
            rep_total: 0,
            target_distance_m: 0,
            target_duration_s: duration_s,
            target_pace_s_per_km: 240,
            tolerance_s_per_km: 10,
        }
    }

    // ─────────── auto-advance ───────────

    #[test]
    fn advances_exactly_when_step_distance_reaches_target() {
        let mut r = WorkoutRunner::new(&[dist_step(400), dist_step(200)]).unwrap();
        r.on_totals(0.0, 0);
        assert_eq!(r.view().transition_seq, 1, "first step announces itself");
        r.on_totals(200.0, 60);
        assert_eq!(r.view().step_index, 0);
        r.on_totals(400.0, 120);
        assert_eq!(r.view().step_index, 1);
        assert_eq!(r.view().transition_seq, 2);
        r.on_totals(600.0, 180);
        assert!(r.is_complete());
    }

    #[test]
    fn a_single_update_that_overshoots_clears_multiple_distance_steps() {
        // A GPS gap lands one update 250 m past the start, covering two
        // 100 m steps plus into a third: both crossed boundaries advance,
        // each completed step records its TARGET (not the overshoot), and
        // the third carries the leftover 50 m.
        let mut r =
            WorkoutRunner::new(&[dist_step(100), dist_step(100), dist_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(250.0, 50);
        assert_eq!(r.view().step_index, 2);
        assert_eq!(r.view().transition_seq, 3, "three entries: 0, 1, 2");
        let results = r.snapshot_results();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].status, StepStatus::Completed);
        assert_eq!(results[1].status, StepStatus::Completed);
        assert!((results[0].actual_distance_m - 100.0).abs() < 1e-9);
        assert!((results[1].actual_distance_m - 100.0).abs() < 1e-9);
        assert_eq!(results[2].status, StepStatus::Skipped, "in-progress row");
        assert!((results[2].actual_distance_m - 50.0).abs() < 1e-9);
        assert_eq!(r.view().step_distance_m, 50);
    }

    #[test]
    fn a_single_update_clears_multiple_short_duration_steps() {
        // Three 10 s steps but the tick lands 25 s in: the first two both
        // complete at their 10 s target and the third carries the 5 s left.
        let mut r = WorkoutRunner::new(&[dur_step(10), dur_step(10), dur_step(10)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 25);
        assert_eq!(r.view().step_index, 2);
        let results = r.snapshot_results();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].status, StepStatus::Completed);
        assert_eq!(results[1].status, StepStatus::Completed);
        assert!((results[0].actual_duration_s - 10.0).abs() < 1e-9);
        assert!((results[1].actual_duration_s - 10.0).abs() < 1e-9);
        assert_eq!(r.view().step_elapsed_s, 5);
    }

    #[test]
    fn a_single_update_can_complete_the_entire_workout() {
        let mut r = WorkoutRunner::new(&[dist_step(100), dist_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(500.0, 120);
        assert!(r.is_complete());
        let v = r.view();
        assert!(v.complete);
        assert_eq!(v.rollup, Some(WorkoutAdherence::Completed));
        // Completion is not a step entry: two steps, two transitions.
        assert_eq!(v.transition_seq, 2);
    }

    #[test]
    fn the_first_feed_announces_the_first_step_exactly_once() {
        let mut r = WorkoutRunner::new(&[dist_step(400)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(10.0, 5);
        assert_eq!(r.view().transition_seq, 1);
    }

    #[test]
    fn ending_warning_fires_once_inside_the_last_fifty_metres() {
        let mut r = WorkoutRunner::new(&[dist_step(1000), dist_step(1000)]).unwrap();
        r.on_totals(0.0, 0);
        assert_eq!(r.view().ending_seq, 0);
        r.on_totals(600.0, 180);
        assert_eq!(r.view().ending_seq, 0, "halfway is not the window");
        r.on_totals(960.0, 280);
        assert_eq!(r.view().ending_seq, 1);
        r.on_totals(990.0, 295);
        assert_eq!(r.view().ending_seq, 1, "once per step");
        // The next step re-arms the warning (checked from the feed after the
        // one that advanced, the Dart runner's own ordering).
        r.on_totals(1960.0, 590);
        r.on_totals(1965.0, 592);
        assert_eq!(r.view().ending_seq, 2);
    }

    #[test]
    fn ending_warning_is_suppressed_for_short_steps() {
        // A 100 m step never warns (the gate is > 100 m), and a 20 s
        // duration step never warns (> 20 s) — the warning would collide
        // with the step's own start.
        let mut r = WorkoutRunner::new(&[dist_step(100), dur_step(20)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(99.0, 30);
        assert_eq!(r.view().ending_seq, 0);
        r.on_totals(100.0, 31);
        assert_eq!(r.view().step_index, 1);
        r.on_totals(100.0, 45);
        assert_eq!(r.view().ending_seq, 0);
    }

    #[test]
    fn duration_step_ending_warning_fires_in_the_last_ten_seconds() {
        let mut r = WorkoutRunner::new(&[dur_step(60), dur_step(60)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        assert_eq!(r.view().ending_seq, 0);
        r.on_totals(180.0, 51);
        assert_eq!(r.view().ending_seq, 1);
    }

    // ─────────── controls ───────────

    #[test]
    fn skip_marks_the_step_skipped_and_advances() {
        let mut r = WorkoutRunner::new(&[dist_step(400), dist_step(200)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        r.skip_step();
        assert_eq!(r.view().step_index, 1);
        let results = r.snapshot_results();
        assert_eq!(results[0].status, StepStatus::Skipped);
        assert!((results[0].actual_distance_m - 100.0).abs() < 1e-9);
        // The next step anchors fresh at the skip totals.
        assert_eq!(r.view().step_distance_m, 0);
    }

    #[test]
    fn skip_is_inert_before_the_first_feed_and_after_completion() {
        let mut r = WorkoutRunner::new(&[dist_step(100)]).unwrap();
        r.skip_step();
        assert_eq!(r.view().step_index, 0);
        assert!(r.snapshot_results().is_empty());
        r.on_totals(0.0, 0);
        r.on_totals(150.0, 40);
        assert!(r.is_complete());
        r.skip_step();
        assert!(r.is_complete());
        assert_eq!(r.snapshot_results().len(), 1);
    }

    // ─────────── duration-based steps ───────────

    #[test]
    fn auto_advances_on_elapsed_reaching_target_duration() {
        let mut r = WorkoutRunner::new(&[dur_step(30), dist_step(200)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(50.0, 15);
        assert_eq!(r.view().step_index, 0);
        assert_eq!(r.view().remaining_s, 15);
        r.on_totals(100.0, 30);
        assert_eq!(r.view().step_index, 1);
    }

    #[test]
    fn progress_reads_the_time_axis_for_duration_steps() {
        let mut r = WorkoutRunner::new(&[dur_step(60)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(50.0, 15);
        let v = r.view();
        assert!(v.duration_based);
        assert_eq!(v.progress_permille, 250);
        assert_eq!(v.remaining_s, 45);
        assert_eq!(v.remaining_m, 0);
    }

    #[test]
    fn progress_reads_the_distance_axis_for_distance_steps() {
        let mut r = WorkoutRunner::new(&[dist_step(400)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        let v = r.view();
        assert!(!v.duration_based);
        assert_eq!(v.progress_permille, 250);
        assert_eq!(v.remaining_m, 300);
        assert_eq!(v.remaining_s, 0);
    }

    #[test]
    fn rollup_applies_the_eighty_percent_threshold_on_the_time_axis() {
        // A skipped duration step that banked 80 % of its target still reads
        // Partial (skip is skip); a completed one at ≥80 % counts clean.
        let mut r = WorkoutRunner::new(&[dur_step(100), dur_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 100);
        r.on_totals(200.0, 200);
        assert!(r.is_complete());
        assert_eq!(r.rollup(), WorkoutAdherence::Completed);

        let mut r = WorkoutRunner::new(&[dur_step(100), dist_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(50.0, 79);
        r.skip_step();
        r.on_totals(200.0, 200);
        assert!(r.is_complete());
        assert_eq!(r.rollup(), WorkoutAdherence::Partial);
    }

    // ─────────── pace adherence ───────────

    #[test]
    fn flags_way_behind_when_thirty_five_seconds_off_target() {
        // Target 240 s/km ± 10; 400 m in 110 s = 275 s/km, 35 s slow — past
        // twice the tolerance.
        let mut r = WorkoutRunner::new(&[dist_step(1000)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(400.0, 110);
        assert_eq!(r.view().step_pace_s_per_km, Some(275));
        assert_eq!(r.view().adherence, PaceAdherence::WayBehind);
    }

    #[test]
    fn adherence_bands_split_at_one_and_two_tolerances() {
        let mut r = WorkoutRunner::new(&[dist_step(10_000)]).unwrap();
        r.on_totals(0.0, 0);
        // 1000 m in 245 s: 5 s slow, inside ±10 — on pace.
        r.on_totals(1000.0, 245);
        assert_eq!(r.view().adherence, PaceAdherence::OnPace);
        // 2000 m in 510 s: 255 s/km, 15 s slow — behind, not way-behind.
        r.on_totals(2000.0, 510);
        assert_eq!(r.view().adherence, PaceAdherence::Behind);
        // 3000 m in 660 s: 220 s/km, 20 s fast — ahead (exactly 2× tol).
        r.on_totals(3000.0, 660);
        assert_eq!(r.view().adherence, PaceAdherence::Ahead);
    }

    #[test]
    fn no_pace_below_the_minimum_sample_reads_on_pace() {
        let mut r = WorkoutRunner::new(&[dist_step(400)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(3.0, 30);
        assert_eq!(r.view().step_pace_s_per_km, None);
        assert_eq!(r.view().adherence, PaceAdherence::OnPace);
    }

    // ─────────── results ───────────

    #[test]
    fn snapshot_results_cover_every_advanced_step_and_the_in_progress_one() {
        let mut r =
            WorkoutRunner::new(&[dist_step(100), dist_step(100), dist_step(400)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        r.on_totals(200.0, 60);
        r.on_totals(250.0, 75);
        let results = r.snapshot_results();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].step_index, 0);
        assert_eq!(results[0].status, StepStatus::Completed);
        assert_eq!(results[1].status, StepStatus::Completed);
        assert_eq!(results[2].status, StepStatus::Skipped);
        assert!((results[2].actual_distance_m - 50.0).abs() < 1e-9);
        // A completed step's pace comes from its consumed share: 100 m of
        // each 30 s segment at 3.33 m/s → 300 s/km.
        assert_eq!(results[0].actual_pace_s_per_km, Some(300));
    }

    #[test]
    fn in_progress_rollup_reads_partial() {
        let mut r = WorkoutRunner::new(&[dist_step(100), dist_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(120.0, 40);
        assert!(!r.is_complete());
        assert_eq!(r.rollup(), WorkoutAdherence::Partial);
    }

    #[test]
    fn fully_completed_rollup_reads_completed() {
        let mut r = WorkoutRunner::new(&[dist_step(100), dur_step(30)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        r.on_totals(180.0, 60);
        assert!(r.is_complete());
        assert_eq!(r.rollup(), WorkoutAdherence::Completed);
    }

    // ─────────── watch-specific ───────────

    #[test]
    fn new_rejects_an_empty_or_over_cap_step_list() {
        assert!(WorkoutRunner::new(&[]).is_none());
        let over = [dist_step(100); MAX_WORKOUT_STEPS + 1];
        assert!(WorkoutRunner::new(&over).is_none());
        let at_cap = [dist_step(100); MAX_WORKOUT_STEPS];
        assert!(WorkoutRunner::new(&at_cap).is_some());
    }

    #[test]
    fn view_before_the_first_feed_previews_step_zero() {
        let steps = [
            WorkoutStep {
                kind: WorkoutStepKind::Warmup,
                rep_index: 0,
                rep_total: 0,
                target_distance_m: 800,
                target_duration_s: 0,
                target_pace_s_per_km: 360,
                tolerance_s_per_km: 10,
            },
            dist_step(400),
        ];
        let r = WorkoutRunner::new(&steps).unwrap();
        let v = r.view();
        assert_eq!(v.step_index, 0);
        assert_eq!(v.step_total, 2);
        assert_eq!(v.kind, WorkoutStepKind::Warmup);
        assert_eq!(v.progress_permille, 0);
        assert_eq!(v.transition_seq, 0, "nothing announced until fed");
        assert_eq!(v.next.unwrap().kind, WorkoutStepKind::Rep);
    }

    #[test]
    fn reset_rearms_the_same_steps_for_a_fresh_run() {
        let mut r = WorkoutRunner::new(&[dist_step(100), dist_step(100)]).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(300.0, 90);
        assert!(r.is_complete());
        r.reset();
        assert!(!r.is_complete());
        assert_eq!(r.view().step_index, 0);
        assert_eq!(r.view().transition_seq, 0);
        assert!(r.snapshot_results().is_empty());
        // A fresh run's totals restart from zero and anchor cleanly.
        r.on_totals(0.0, 0);
        r.on_totals(100.0, 30);
        assert_eq!(r.view().step_index, 1);
    }

    #[test]
    fn mid_run_arming_anchors_at_the_current_totals() {
        // A workout pushed 2 km into a run must not instantly complete off
        // the pre-push distance: the first feed anchors where the run is.
        let mut r = WorkoutRunner::new(&[dist_step(400)]).unwrap();
        r.on_totals(2000.0, 600);
        assert_eq!(r.view().step_index, 0);
        assert_eq!(r.view().step_distance_m, 0);
        r.on_totals(2400.0, 720);
        assert!(r.is_complete());
    }

    #[test]
    fn view_complete_state_keeps_the_last_step_identity() {
        let steps = [
            dist_step(100),
            WorkoutStep {
                kind: WorkoutStepKind::Cooldown,
                rep_index: 0,
                rep_total: 0,
                target_distance_m: 200,
                target_duration_s: 0,
                target_pace_s_per_km: 400,
                tolerance_s_per_km: 10,
            },
        ];
        let mut r = WorkoutRunner::new(&steps).unwrap();
        r.on_totals(0.0, 0);
        r.on_totals(400.0, 150);
        let v = r.view();
        assert!(v.complete);
        assert_eq!(v.kind, WorkoutStepKind::Cooldown);
        assert_eq!(v.step_index, 1);
        assert_eq!(v.next, None);
        assert_eq!(v.progress_permille, 1000);
    }

    #[test]
    fn kind_codes_round_trip_and_reject_unknowns() {
        for kind in [
            WorkoutStepKind::Warmup,
            WorkoutStepKind::Rep,
            WorkoutStepKind::Recovery,
            WorkoutStepKind::Walk,
            WorkoutStepKind::Steady,
            WorkoutStepKind::Cooldown,
        ] {
            assert_eq!(WorkoutStepKind::from_code(kind.code()), Some(kind));
        }
        assert_eq!(WorkoutStepKind::from_code(6), None);
        assert_eq!(WorkoutStepKind::from_code(255), None);
    }
}
