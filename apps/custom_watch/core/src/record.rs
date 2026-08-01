//! Recording state machine — a host-testable port of the Dart `run_recorder`.
//!
//! [`Recorder`] reduces control commands (start / pause / resume / stop), a
//! stream of [`Fix`] samples, and a wall clock into the live run totals a watch
//! face reads: total distance, elapsed vs moving time, current speed, average /
//! current pace, and the lap counters (a 1 km auto-lap plus the manual
//! [`lap`](Recorder::lap) the Lap button drives — laps live in RAM for the
//! face's lap page only). The point-acceptance filter (min-distance,
//! implausible-jump, max-speed) and the moving-time speed gate reproduce the
//! constants the mobile recorder ships — see each `pub const` below.
//!
//! Pure logic, exactly like [`crate::fix`] and [`crate::face`]: no peripherals,
//! no Embassy, no allocator. Distances use the equirectangular projection the
//! Dart recorder already uses for its route-segment math (`_distanceToSegmentMetres`)
//! rather than a great-circle call, because this `no_std` crate takes no math
//! dependency and the two agree to well under a millimetre at the metres-apart
//! spacing of successive fixes.

use crate::auto_lap::{AutoLap, AUTO_LAP_DEFAULT};
use crate::backyard::{Backyard, BackyardView};
use crate::climb::{crest_ahead, ClimbDetector, ClimbView};
use crate::cutoff_eta::{next_cutoff_eta, CutoffEta, CutoffLeg};
use crate::distance_bands::{band_for_distance, DistanceBand};
use crate::fitness::RecoveryAdvice;
use crate::fix::Fix;
use crate::fuel_plan::{
    build_fuel_plan, FuelLegInput, FuelPlanOptions, DEFAULT_CARBS_PER_HOUR_G,
    DEFAULT_FLUID_PER_HOUR_ML, GEL_CARBS_G, SIP_FLUID_ML,
};
use crate::gear_wear::{gear_wear, GearWear};
use crate::grade_adjusted_pace::GapEstimator;
use crate::guided_runs::{cues_due, find_guided_run, is_guided_run_valid, GuidedRun};
use crate::hr_zones::{
    self, ZoneCutoffs, DEFAULT_MAX_HR_BPM, MAX_HR_PLAUSIBLE_MAX, MAX_HR_PLAUSIBLE_MIN, ZONE_COUNT,
};
use crate::pace_segments::{pace_bucket_for_speed, ActivityKind};
use crate::pacer::{Pacer, PacerStatus};
use crate::page::Page;
use crate::race_phases::{
    build_phase_plan, goal_pace_s_per_km, phase_at, phase_target_pace_s_per_km, PhasePlan,
    RacePhaseIntent, RacePhasePreset,
};
use crate::race_predictor::{predict_race_ladder, Effort, RacePrediction};
use crate::roadbook::CutoffStatus;
use crate::sleep_station::{sleep_budget, SleepBudget};
use crate::storm::StormView;
use crate::timers::TimerView;
use crate::training_load::{
    compute_calibration, compute_stress, HrPrefs, LoadTrendView, RunForLoad, StressMode,
};
use crate::training_paces::{paces_from_goal_pace, TrainingGender, TrainingPaces};
use crate::waypoints::{WaypointView, Waypoints};
use crate::workout::{StepResult, WorkoutAdherence, WorkoutRunner, WorkoutStep, WorkoutView};
use crate::workout_store;

/// Movement gate: a segment shorter than this is GPS jitter while effectively
/// stopped, not travel. `max(distanceFilterMetres = 3, minMovementMetres = 2)`
/// in `run_recorder`.
pub const TRACK_THRESHOLD_M: f64 = 3.0;

/// A single hop longer than this is a corrupt fix, never real travel — the
/// `delta < 100` ceiling in `run_recorder`. Calibrated for the ~1 s fix
/// cadence both recorders were built around; a throttled GNSS mode replaces
/// it with a segment-speed ceiling (see [`Recorder::set_fix_interval_s`]).
pub const MAX_JUMP_M: f64 = 100.0;

/// A segment implying a speed above this (or a non-positive time delta) is
/// implausible and dropped without moving the anchor. `_maxSpeedMps` in
/// `run_recorder`.
pub const MAX_SPEED_MPS: f64 = 10.0;

/// A rejected hop that spans at least this many seconds is a real GPS gap
/// (canyon, tunnel, dense cover — fixes stopped while the runner kept
/// moving), not a corrupt teleport: the anchor is rebased to the fresh fix
/// WITHOUT crediting the un-sampled gap distance. Without this the anchor
/// stays stale after any 1 Hz dropout that displaced the runner past
/// [`MAX_JUMP_M`], every later delta only grows, and distance is frozen for
/// the rest of the run. `_gpsReanchorAfterSeconds` in `run_recorder`
/// (its #330); long enough that a 1 Hz corrupt outlier (dt ≈ 1 s) still
/// fails closed.
pub const GPS_REANCHOR_AFTER_S: u32 = 10;

/// A segment slower than this counts its distance but not its time toward
/// moving time — the `minSpeedMps` of `run_stats.movingTimeOf`, which replaced
/// the removed live auto-pause as the way moving time is derived.
pub const MIN_MOVING_SPEED_MPS: f64 = 0.5;

/// Metres per degree of latitude for the equirectangular projection, matching
/// the constant in `run_recorder._distanceToSegmentMetres`.
pub const METRES_PER_DEGREE_LAT: f64 = 111_320.0;

/// Auto-lap boundary of the default trigger ([`AutoLap::Km1`]): the current lap
/// closes on the first accepted fix that carries it past this distance. A
/// manual lap resets the countdown, so the boundary is always measured from the
/// current lap's start, not from multiples of the run total.
pub const AUTO_LAP_DISTANCE_M: f64 = 1000.0;

const _: () = assert!(matches!(AutoLap::Km1.distance_m(), Some(m) if m == AUTO_LAP_DISTANCE_M));

/// How many cutoff legs the tier-1 recorder holds for the loaded course —
/// enough for an ultra's aid-station cutoffs. A pushed course with more must be
/// trimmed phone-side; [`Recorder::set_cutoff_legs`] caps rather than grows.
pub const MAX_CUTOFF_LEGS: usize = 16;

/// Minimum run distance before the live race-time predictor projects a ladder.
/// Below this a Riegel projection off a warm-up is noise, so the RacePredictor
/// page stays honestly blank — the same "not meaningful yet" gate `avg_pace`
/// applies to itself, one distance tier up. Not a change to the ported
/// algorithm (see [`crate::race_predictor`]): an input-validity guard for the
/// watch's live-partial-run effort source.
pub const MIN_PREDICT_DISTANCE_M: f64 = 1000.0;

/// Pace buckets tracked for the Splits page, matching `crate::pace_segments`'s
/// six-bucket ramp (slowest .. fastest).
pub const PACE_BUCKET_COUNT: usize = 6;

/// Elevation-profile capacity, in stored altitude samples. With the initial
/// spacing this covers ~1.6 km before the first thinning; each thinning halves
/// the count and doubles the spacing (the trackback breadcrumb's decimation, one
/// dimension instead of two), so the whole run stays represented at coarsening
/// resolution — seven doublings reach ~200 km — at a fixed 256 B of RAM. Sized
/// for a sparkline cell, not a full profile chart, so this is already more
/// resolution than the panel can show.
pub const ELEV_PROFILE_CAP: usize = 64;

/// Initial elevation-profile spacing: a new altitude sample is kept once the run
/// has advanced this far since the last kept sample. Doubles on each thinning.
pub const ELEV_PROFILE_SPACING_M: f64 = 25.0;

/// Pushed-course climb-profile capacity, in samples. The profile panel is 156 px
/// wide, so at 128 samples the drawn shape is limited by the panel rather than by
/// the series, and it costs 256 B against the course's own 4 KiB budget. Unlike
/// [`ELEV_PROFILE_CAP`] this never thins: the whole course is known up front, so
/// the series is sampled evenly across it once ([`crate::course_profile`]).
pub const COURSE_PROFILE_CAP: usize = 128;

/// How many pushed roadbook checkpoints the watch holds — an ultra's aid legs,
/// bounded like [`MAX_CUTOFF_LEGS`]. A longer roadbook is trimmed phone-side.
pub const MAX_PUSHED_LEGS: usize = 16;

/// Upcoming roadbook checkpoints the Roadbook page shows at once.
pub const ROADBOOK_WINDOW: usize = 4;

/// Plausible synced goal-race pace band (seconds per km): ~2:00/km (a road
/// world-record split) to ~20:00/km (a walk). A push outside this is corrupt and
/// ignored, the same guard shape as [`MAX_HR_PLAUSIBLE_MIN`] — a bad frame must
/// not fabricate a training-pace set.
pub const GOAL_PACE_PLAUSIBLE_MIN_S_PER_KM: f64 = 120.0;
pub const GOAL_PACE_PLAUSIBLE_MAX_S_PER_KM: f64 = 1200.0;

/// Plausible pushed race distance for a pacing-strategy phase plan: 1 km (the
/// shortest race a three-phase strategy shapes usefully) to 500 km (past the
/// longest single-stage ultras). A push outside this is corrupt and **ignored**,
/// not clamped — a bad frame must leave the phase rows honestly inactive rather
/// than plan a race the runner isn't in.
pub const RACE_PHASE_PLAUSIBLE_MIN_DISTANCE_M: f64 = 1_000.0;
pub const RACE_PHASE_PLAUSIBLE_MAX_DISTANCE_M: f64 = 500_000.0;

/// Plausible synced VO2 max / VDOT band: 20 (very unfit) to 90 (the same
/// physiological ceiling `fitness::vdot_from_run` rejects above). Guards a
/// corrupt fitness push from showing a fake number.
pub const FITNESS_VO2_PLAUSIBLE_MIN: f64 = 20.0;
pub const FITNESS_VO2_PLAUSIBLE_MAX: f64 = 90.0;

/// Plausible synced resting HR band: 25 bpm (below any recorded elite resting
/// rate) to 120 (above it a "resting" rate reads as a live one). Outside is
/// corrupt and ignored, the [`MAX_HR_PLAUSIBLE_MIN`] guard shape — a bad frame
/// must not skew every TRIMP stress the run banks.
pub const RESTING_HR_PLAUSIBLE_MIN: u16 = 25;
pub const RESTING_HR_PLAUSIBLE_MAX: u16 = 120;

/// Plausible magnitude bound for a pushed CTL / ATL / TSB value. A sustained
/// CTL near 200 is already elite-tour territory; 500 leaves generous headroom
/// while rejecting the wild values a corrupt push produces.
pub const LOAD_TREND_PLAUSIBLE_MAX: f32 = 500.0;

/// One pushed roadbook checkpoint — name-free + `Copy`. The phone builds the
/// roadbook from the route polyline + markers ([`crate::roadbook`], which needs
/// the polyline the watch doesn't hold) and pushes the numeric schedule, the
/// same model as cutoff legs. Loaded via [`Recorder::set_roadbook`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookCheckpoint {
    /// Cumulative distance along the course to this checkpoint, metres.
    pub cum_dist_m: f64,
    /// Distance of the leg arriving here, metres — the fuel scaler.
    pub leg_dist_m: f64,
    /// Projected elapsed arrival, seconds (from the phone-built roadbook).
    pub projected_elapsed_s: u32,
    /// Safe/tight/miss cutoff verdict, if this checkpoint carries a cutoff.
    pub cutoff: Option<CutoffStatus>,
    /// Whether this checkpoint offers water/food — a fuel refill point.
    pub is_refill: bool,
}

/// One upcoming checkpoint in the [`RoadbookView`] window.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct RoadbookLegView {
    pub cum_dist_m: f32,
    pub projected_elapsed_s: u32,
    pub cutoff: Option<CutoffStatus>,
}

/// The Roadbook page view: total checkpoints + the next few ahead of the
/// current position. `None` on the [`Snapshot`] when no roadbook is loaded.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookView {
    pub total: u8,
    pub upcoming: [RoadbookLegView; ROADBOOK_WINDOW],
    pub upcoming_len: u8,
}

/// The Fuel page view: what to carry to the next aid from the current position,
/// plus the whole-plan totals, from [`crate::fuel_plan`] over the loaded
/// roadbook.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelView {
    /// Carbs/fluid to carry out from the last aid to the next; `None` past the
    /// final aid.
    pub carry: Option<FuelCarryView>,
    pub total_carbs_g: f32,
    pub total_fluid_ml: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelCarryView {
    pub carbs_g: f32,
    pub fluid_ml: f32,
}

/// The TrainingPaces page view: the synced goal-race pace plus the five Daniels
/// intensity-zone paces derived from it ([`crate::training_paces`]). `None` on
/// the [`Snapshot`] until a goal pace is synced.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrainingPacesView {
    /// The synced goal-race pace these zones derive from, seconds per km.
    pub goal_pace_s_per_km: u32,
    /// The five zone paces (easy .. repetition, seconds per km).
    pub paces: TrainingPaces,
}

/// The Fitness page view: only what a single synced snapshot can honestly
/// present — the VO2 max / VDOT ceiling and the recovery-advice verdict, both
/// pushed from the phone. Deliberately no rolling CTL/ATL/TSB: that needs the
/// multi-day history the watch doesn't hold, so a single pushed number would be
/// a stale point masquerading as a live trend. `None` on the [`Snapshot`] until
/// synced.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FitnessView {
    /// Synced VO2 max estimate (== VDOT at these scales), or `None` when the
    /// phone couldn't derive one (no qualifying run).
    pub vo2_max: Option<f32>,
    /// Synced recovery-advice verdict, or `None` when the phone had no data.
    pub recovery: Option<RecoveryAdvice>,
}

/// The decimated elevation series the ElevationProfile page plots as a
/// mini-profile sparkline: baro-preferred altitude (metres, truncated to `i32`)
/// sampled along the run at ~[`ELEV_PROFILE_SPACING_M`] intervals and thinned by
/// halving so the whole run stays represented at fixed RAM. `len == 0` until the
/// first altitude sample lands, so a baro-less (or pre-fix) run leaves the page
/// an honest empty state. RAM display state like the laps + trackback breadcrumb
/// — the flash run-store wire format carries none of it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ElevProfileView {
    pub samples: [i32; ELEV_PROFILE_CAP],
    pub len: usize,
}

impl ElevProfileView {
    pub const fn empty() -> Self {
        Self {
            samples: [0; ELEV_PROFILE_CAP],
            len: 0,
        }
    }
}

// The synced summary each of the twelve run-view glance pages ported in the
// 2026-07-11 batch renders. Every one is a small `Copy` struct the phone pushes
// pre-computed (the phone holds the run history / plan / course the on-watch
// cores can't), stored `Option`-wrapped on the `Recorder` and passed through to
// `Snapshot`. `None` leaves the page an honest empty state until synced — the
// `set_fitness` / `set_training_goal_pace_s_per_km` precedent. Display state
// only: none of these touch the flash run-store wire format.

/// Year/Month-in-Running totals ([`crate::recap`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RecapView {
    pub runs: u16,
    pub distance_km: u16,
    pub longest_km: u16,
    pub best_streak_days: u16,
}

/// Current + best run-streak day counts ([`crate::streaks`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StreaksView {
    pub current_days: u16,
    pub best_days: u16,
}

/// Synced run-stats summary — moving time, elevation gain, split count
/// ([`crate::run_stats`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RunStatsView {
    pub moving_s: u32,
    pub gain_m: u16,
    pub splits: u16,
}

/// How long ago the current PR was set, in whole days ([`crate::pr_recency`]);
/// the face buckets it into today / weeks / months / years.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrRecencyView {
    pub days_ago: u16,
}

/// The re-plan proposal counts ([`crate::plan_replan`]): total changes split
/// into make-ups and ease-offs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PlanReplanView {
    pub changes: u8,
    pub make_ups: u8,
    pub ease_offs: u8,
}

/// The adaptive re-plan trend summary ([`crate::plan_adaptive_replan`]): the
/// multi-week adherence trend verdict (`trend` 0 on-track / 1 under — do more /
/// 2 over — ease off), its confidence (0 low / 1 medium / 2 high), the flagged
/// weeks over the trailing window, the proposed future-change count, and
/// whether a do-more suggestion was withheld for a fatigued runner.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PlanAdaptiveView {
    pub trend: u8,
    pub confidence: u8,
    pub flagged_weeks: u8,
    pub window_weeks: u8,
    pub changes: u8,
    pub fitness_gated: bool,
}

/// Where the run has got to in the armed guided run ([`crate::guided_runs`]):
/// how many of its cues the elapsed time has passed (`cue_index`, 0 before the
/// first), how many it has in total, the wait until the next one (`None` past
/// the last), and the run's target duration + what is left of it. Derived per
/// snapshot from elapsed time against the compiled-in library run, so it needs
/// no dispatcher state and re-derives correctly after a reboot mid-run.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GuidedRunView {
    pub cue_index: u8,
    pub cue_count: u8,
    pub next_cue_in_s: Option<u32>,
    pub duration_s: u32,
    pub remaining_s: u32,
}

/// The training-readiness score (0..=100) and its band ([`crate::readiness`]):
/// `band` is 0 low / 1 moderate / 2 high.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ReadinessView {
    pub score: u8,
    pub band: u8,
}

/// The primary goal's ring progress ([`crate::goals`]): percent 0..=100 and
/// whether it is complete.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GoalsView {
    pub percent: u8,
    pub complete: bool,
}

/// The next turn on the loaded course ([`crate::turn_cues`]): a direction code
/// (0 straight / 1 slight-left / 2 left / 3 sharp-left / 4 slight-right /
/// 5 right / 6 sharp-right / 7 u-turn), metres to it, and how many cues remain.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TurnCueView {
    pub direction: u8,
    pub distance_m: u16,
    pub remaining: u8,
}

/// A simplified-course summary ([`crate::route_simplify`]): point count after
/// simplification and total distance.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RouteSimplifyView {
    pub points: u16,
    pub distance_km: u16,
}

/// Auto-segment-effort match counts ([`crate::auto_segment_effort`]): how many
/// of the considered segments matched the run end-to-end.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AutoEffortView {
    pub matched: u8,
    pub considered: u8,
}

/// The loaded course's climb profile ([`crate::course_profile`]): total gain /
/// loss over the whole pushed series, the course's point count and length, and
/// the distance-even elevation series the RouteElev page draws as a shape.
/// `len == 0` means the course arrived without elevation — the page then shows
/// the geometry rows and no profile, never a flat line at zero.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RouteElevView {
    pub gain_m: u16,
    pub loss_m: u16,
    pub points: u16,
    pub total_m: u32,
    pub samples: [i16; COURSE_PROFILE_CAP],
    pub len: usize,
}

/// The race-day countdown + goal-feasibility verdict ([`crate::race_day`]):
/// signed days until the race (negative once past) and `feasible` 0 behind /
/// 1 on-track / 2 ahead.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RaceDayView {
    pub days_until: i16,
    pub feasible: u8,
}

/// The pacing-strategy phase the run is currently in ([`crate::race_phases`]),
/// re-derived from the live distance at [`snapshot`](Recorder::snapshot) time.
/// The intent travels as its identifier — the face resolves the label.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RacePhaseView {
    /// 1-based position of the phase in progress.
    pub index: u8,
    /// Phases in the plan.
    pub total: u8,
    pub intent: RacePhaseIntent,
    /// The phase's target pace, seconds per km; `None` when no goal time was
    /// pushed with the plan — a phase without a goal has no target pace.
    pub target_pace_s_per_km: Option<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecordState {
    Idle,
    Recording,
    Paused,
    Finished,
}

/// One completed lap — closed by the 1 km auto-lap boundary or a manual lap
/// press, kept in RAM for the face's lap page (laps are display state at
/// tier 1; the flash run-store wire format does not carry them).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lap {
    /// 1-based lap number within the run.
    pub index: u16,
    /// Ground covered within this lap alone.
    pub distance_m: f64,
    /// The lap split: wall-clock seconds from the lap's start to its close.
    pub elapsed_s: u32,
    /// Seconds of this lap that cleared the moving gate.
    pub moving_s: u32,
}

/// A `Copy` snapshot of the live totals, taken by [`Recorder::snapshot`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Snapshot {
    pub state: RecordState,
    /// Whether a `Paused` state came from an explicit [`Recorder::pause`]
    /// (cleared only by [`Recorder::resume`]) rather than the speed-derived
    /// auto-pause or the min-move filter's sampling artifact. Always `false`
    /// outside `Paused`, so the face can label a pause honestly: a manual
    /// pause demands a button press, everything else resumes itself on the
    /// next moving fix.
    pub manual_paused: bool,
    /// Whether a `Paused` state came from the fixes drying up rather than from
    /// the runner slowing down. Always `false` outside `Paused`. The face needs
    /// this told to it rather than inferred: the min-move artifact and a signal
    /// void are both non-manual pauses, and the only thing that separates them
    /// is whether a fix or the clock caused it — [`Snapshot::is_moving`] cannot
    /// answer that, because it deliberately still reads the last known speed so
    /// a runner climbing through a void keeps banking barometric vert.
    pub signal_lost: bool,
    pub distance_m: f64,
    /// Wall-clock seconds since start — includes paused stretches.
    pub elapsed_s: u32,
    /// Seconds the runner was actually moving — excludes both manual and
    /// auto (below-threshold) pauses.
    pub moving_s: u32,
    pub current_speed_mps: f32,
    /// Moving pace over the whole run, seconds per kilometre; `None` until
    /// there is enough distance to be meaningful.
    pub avg_pace_s_per_km: Option<u32>,
    /// Pace from the latest fix's speed, seconds per kilometre; `None` when
    /// stopped.
    pub current_pace_s_per_km: Option<u32>,
    /// Grade-adjusted current pace (the Minetti model over the streaming
    /// grade estimate — see [`crate::grade_adjusted_pace`]), seconds per
    /// kilometre; `None` below the walk threshold or when stopped. Equals raw
    /// pace while no altitude signal has arrived (grade 0), matching the
    /// Connect IQ field's no-altimeter behaviour.
    pub gap_s_per_km: Option<u32>,
    /// Whether [`Snapshot::gap_s_per_km`] is the estimator's hold-window
    /// value (a power-hike dip) rather than a live sample — the face marks a
    /// held value with `~` so it cannot pass as current.
    pub gap_held: bool,
    /// 1-based number of the lap in progress; 0 before a run starts.
    pub lap: u16,
    /// Ground covered within the current lap so far.
    pub lap_distance_m: f64,
    /// Wall-clock seconds since the current lap started.
    pub lap_elapsed_s: u32,
    /// The most recently completed lap, if any — the face's "last lap split".
    pub last_lap: Option<Lap>,
    /// What closes the next lap without a press. Carried so the Lap page can
    /// say so: a runner who cannot see that auto-lap is off reads a lap counter
    /// that never moves as a broken watch.
    pub auto_lap: AutoLap,
    /// The virtual-partner delta vs a configured goal (see [`crate::pacer`]);
    /// `None` while no goal is set or no run is under way — the pacer page
    /// shows an honest inactive state then, never a fake "on pace at zero".
    pub pacer: Option<PacerStatus>,
    /// The zone ladder in force for this run — carried so the face can place
    /// the live BPM in a zone without owning a second copy of the max-HR
    /// configuration.
    pub zone_cutoffs: ZoneCutoffs,
    /// The alert engine's armed zone ceiling (`Some(z)` = alert above zone
    /// `z`), mirrored via [`Recorder::set_alert_arms`]. Carried so the Zones
    /// page can render `CEIL Z4` / `CEIL --` — the arm is phone-pushed only,
    /// and a runner who cannot see that it never armed trusts an alert that
    /// will not fire.
    pub zone_ceiling: Option<u8>,
    /// The armed pace band `(fast, slow)` in s/km, mirrored the same way for
    /// the Pace page's `BAND` row.
    pub pace_band: Option<(u32, u32)>,
    /// Seconds of moving time spent in each zone (Z1..Z5). Accrues exactly
    /// where [`Snapshot::moving_s`] does — a paused / auto-paused stretch adds
    /// nothing — and only while an HR reading is live, so a sensorless run
    /// keeps all five at zero.
    pub zone_time_s: [u32; ZONE_COUNT],
    /// The live next-cutoff ETA when the loaded course carries cutoff legs and
    /// a run is under way; `None` otherwise, so the CutoffEta page reads an
    /// honest "no cutoffs loaded". Distance-along-route is fed from the nav
    /// projection via [`Recorder::set_route_position`]; a stale route position
    /// withholds the projected time rather than fabricate one off an old fix.
    pub cutoff: Option<CutoffEta>,
    /// How long the runner may sleep and still make the next cut-off
    /// ([`crate::sleep_station`], §373) — present exactly when
    /// [`Snapshot::cutoff`] is, since it is that same projection less a reserve.
    /// Its own [`crate::sleep_station::SleepStatus`] carries the honest empty
    /// states, so a stale fix
    /// yields `Unknown` rather than a nap length nothing will wake the runner
    /// from.
    pub sleep: Option<SleepBudget>,
    /// The live race-time ladder projected from the current run treated as a
    /// single effort — `None` until the run clears [`MIN_PREDICT_DISTANCE_M`]
    /// and a moving pace exists, so a warm-up shows no fabricated prediction.
    pub race_prediction: Option<RacePrediction>,
    /// Distance banked in each pace bucket (slowest..fastest), metres — the
    /// Splits page's pace-distribution, the pace analogue of [`Snapshot::zone_time_s`].
    /// All zero until a run accrues distance.
    pub pace_bucket_m: [f64; PACE_BUCKET_COUNT],
    /// This run's single-run training-load stress so far (distance/TRIMP model,
    /// see [`crate::training_load`]); `None` while idle or before any distance.
    pub training_stress: Option<f32>,
    /// Whether [`Snapshot::training_stress`] was scored by the TRIMP model
    /// (resting + max HR synced and a live HR average banked) rather than the
    /// distance proxy — the page's honest model label, mirroring the web
    /// chart's `has_trimp_signal` "HR-based" vs "volume-based" split. `false`
    /// whenever `training_stress` is `None`.
    pub training_stress_trimp: bool,
    /// The synced rolling CTL/ATL/TSB trio, or `None` until the phone pushes
    /// one — the TrainingLoad page's rolling half stays "NOT SYNCED" without it.
    pub load_trend: Option<LoadTrendView>,
    /// The race-distance band the run distance falls in, or `None` in a gap
    /// between bands (or while idle).
    pub band: Option<DistanceBand>,
    /// The active gear's wear verdict, or `None` when no gear is synced.
    pub gear: Option<GearWear>,
    /// The upcoming-checkpoint window of the loaded roadbook, or `None` when no
    /// roadbook is loaded.
    pub roadbook: Option<RoadbookView>,
    /// The fuelling headline over the loaded roadbook, or `None` without one.
    pub fuel: Option<FuelView>,
    /// The training-pace zones derived from the synced goal-race pace, or `None`
    /// until a goal pace is synced.
    pub training_paces: Option<TrainingPacesView>,
    /// The synced fitness snapshot (VO2 max + recovery advice), or `None` until
    /// the phone pushes one.
    pub fitness: Option<FitnessView>,
    /// The decimated elevation series for the ElevationProfile page's sparkline;
    /// `len == 0` until an altitude sample lands.
    pub elev_profile: ElevProfileView,
    /// The synced Year/Month-in-Running summary, or `None` until pushed.
    pub recap: Option<RecapView>,
    /// The synced run-streak counts, or `None` until pushed.
    pub streaks: Option<StreaksView>,
    /// The synced run-stats summary, or `None` until pushed.
    pub run_stats: Option<RunStatsView>,
    /// The synced PR-recency (days since the current PR), or `None` until pushed.
    pub pr_recency: Option<PrRecencyView>,
    /// The synced re-plan proposal counts, or `None` until pushed.
    pub plan_replan: Option<PlanReplanView>,
    /// The synced adaptive re-plan trend summary, or `None` until pushed.
    pub plan_adaptive: Option<PlanAdaptiveView>,
    /// Where the run has reached in the armed guided run, or `None` when none is
    /// armed.
    pub guided_run: Option<GuidedRunView>,
    /// Where the armed structured workout stands ([`crate::workout`]), or
    /// `None` when none is pushed — the Workout page then reads an honest
    /// inactive state. Armed while idle it previews step 0.
    pub workout: Option<WorkoutView>,
    /// The synced training-readiness score, or `None` until pushed.
    pub readiness: Option<ReadinessView>,
    /// The synced primary-goal progress, or `None` until pushed.
    pub goals: Option<GoalsView>,
    /// The next turn on the loaded course, or `None` until pushed.
    pub turn_cue: Option<TurnCueView>,
    /// The nav task's latched off-course verdict, fed per fix beside the
    /// route position: `Some(true)` while the [`crate::course::OffCourseAlert`]
    /// hysteresis is latched, `Some(false)` while a live projection says on
    /// course, `None` when nothing is projecting (no course, no fix yet).
    /// Tri-state so a course swap or a lost projection reads as *absence of
    /// knowledge*, never as a recovery.
    pub nav_off_course: Option<bool>,
    /// The simplified-course summary, or `None` until pushed.
    pub route_simplify: Option<RouteSimplifyView>,
    /// The auto-segment-effort match counts, or `None` until pushed.
    pub auto_effort: Option<AutoEffortView>,
    /// The loaded course's climb profile, or `None` when no course is loaded.
    pub route_elev: Option<RouteElevView>,
    /// Where the runner sits along the loaded course, in parts-per-thousand of
    /// its length — the profile page's position marker. `None` without a course,
    /// before a projection lands, or once the fed position goes stale, so the
    /// marker disappears rather than freezing at a position the runner left.
    pub route_position_permille: Option<u16>,
    /// The race-day countdown + feasibility, or `None` until pushed.
    pub race_day: Option<RaceDayView>,
    /// The pacing-strategy phase the run distance currently falls in, or `None`
    /// until a plan is pushed — the Pacer page then reads "PHASE --" rather than
    /// a phase the runner never asked for.
    pub race_phase: Option<RacePhaseView>,
    /// The barometric pressure tendency ([`crate::storm`], § 376), or `None`
    /// on a watch whose barometer never answered. Fed by the `baro` task, which
    /// owns the raw pressure and the GPS altitude the reduction needs, so the
    /// recorder only carries it — like the timer, the instrument outlives the
    /// run and a run start does not reset it.
    pub storm: Option<StormView>,
    /// The climb underfoot and the crest ahead ([`crate::climb`], §359). Both
    /// halves are independent: the live half needs no course, the crest half
    /// needs the pushed profile, and the page is empty only when neither has
    /// anything to say.
    pub climb: ClimbView,
    /// Backyard-ultra mode ([`crate::backyard`], § 372), or `None` while the
    /// mode is unarmed — which is also the Backyard page's presence bit, so an
    /// ordinary run never carries a bell page in its cycle.
    pub backyard: Option<BackyardView>,
    /// Distance + bearing from the current position back to the newest marked
    /// waypoint (§357), or `None` when nothing is marked or no position anchor
    /// exists — the Waypoint page then reads an honest empty state rather than
    /// an arrow to nowhere.
    pub waypoint: Option<WaypointView>,
    /// How many waypoints are stored, marked or not — the page's data-presence
    /// bit. Distinct from [`Snapshot::waypoint`] being `Some`: marks survive
    /// between runs, so the page must stay in the cycle while the store is
    /// non-empty even before this run has an anchor to measure from.
    pub waypoint_count: u8,
    /// Wrapping count of successful [`Recorder::mark_waypoint`] calls — the
    /// alert engine edge-detects it into the mark's on-screen confirmation.
    /// A counter and not [`Snapshot::waypoint_count`], because the eight-slot
    /// newest-wins store saturates: the ninth mark changes the count not at
    /// all and must still be answered.
    pub waypoint_mark_seq: u8,
    /// Wrapping count of refused marks (no position anchor) — the same edge
    /// detection, so a dead BTN5 hold says why instead of saying nothing.
    pub waypoint_refuse_seq: u8,
    /// The runner's countdown / stopwatch reading ([`crate::timers`], §375), or
    /// `None` while nothing is armed. Fed in from the task that owns the
    /// instrument rather than derived here — the timer outlives runs, so the
    /// recorder is no more its home than it is the course's ([`set_timer`]).
    ///
    /// [`set_timer`]: Recorder::set_timer
    pub timer: Option<TimerView>,
    /// The flash track's decimation factor: 1 = full resolution, `k` = one
    /// stored point per `k` accepted fixes after slot-full thinning
    /// ([`crate::run_store::RunWriter::push_point_bounded`]). Lets the face
    /// surface the reduced stored resolution on the wrist instead of it being
    /// a cable-only `warn!`; the WHOLE run is still represented.
    pub track_thinning: u8,
    /// The effective page cycle for this snapshot (bit = [`Page::bit`]):
    /// data-present pages ∩ the curated set, Dashboard always included. The
    /// button task walks it and the page indicator counts it.
    pub pages_mask: u64,
    /// The current hide-empty-pages filter state (the §284 toggle), published
    /// so the settings menu can show the value it is about to change — the
    /// read-before-commit rule — whichever side (menu or phone push) last set
    /// it.
    pub hide_empty_pages: bool,
}

impl Snapshot {
    /// Is the runner physically moving right now?
    ///
    /// The barometric vert accumulator gates on this
    /// ([`crate::elevation::VertAccumulator::push`]'s `moving`): while stopped,
    /// an altitude change is weather drift rather than climb, so the reference
    /// re-bases and banks nothing.
    ///
    /// The answer comes from the receiver's own speed, **not** from
    /// `state == Recording`. [`RecordState::Paused`] means one of three
    /// different things here: a manual pause, an auto-pause (a segment under
    /// [`MIN_MOVING_SPEED_MPS`]), or merely a fix whose displacement failed the
    /// point-acceptance min-move filter ([`TRACK_THRESHOLD_M`]). That last one
    /// is a *sampling artifact of the GPS filter*, not a stop: a runner
    /// power-hiking a climb at ~1–2 m/s covers under 3 m per 1 Hz fix, so the
    /// state legitimately alternates Recording/Paused fix by fix. Gating vert on
    /// `Recording` re-based the deadband reference on every other sample, and a
    /// climb slower than [`TRACK_THRESHOLD_M`] per second — i.e. every real
    /// climb — banked exactly zero gain.
    ///
    /// A fourth `Paused` meaning joined these: the lost-signal auto-pause in
    /// [`Recorder::tick`]. Speed is deliberately *not* aged out there — a
    /// runner climbing through a canyon with no fixes must keep banking
    /// barometric vert — so this answers "moving" through a void, which is the
    /// honest answer to what it asks and the wrong one for a `REC`/`AUTO` tag.
    /// The face reads [`Snapshot::signal_lost`] for that instead.
    ///
    /// Speed is honest across all three fix-driven cases: `on_fix` stamps
    /// `current_speed_mps` from the fix before the min-move filter can flip the
    /// state, while [`Recorder::pause`], [`Recorder::stop`] and
    /// [`Recorder::start`] all zero it — so a real stop (aid station, sleep,
    /// waiting out weather on a col) still reads as not-moving and the
    /// phantom-vert protection is unchanged.
    pub fn is_moving(&self) -> bool {
        !matches!(self.state, RecordState::Idle | RecordState::Finished)
            && self.current_speed_mps as f64 >= MIN_MOVING_SPEED_MPS
    }
}

/// Fixed-RAM decimated elevation series feeding [`ElevProfileView`]. Mirrors the
/// trackback breadcrumb's halve-and-double-spacing decimation over one dimension
/// (altitude against distance-along-run), so the whole run's shape survives at a
/// bounded sample count instead of the tail falling off.
struct ElevProfile {
    samples: [i32; ELEV_PROFILE_CAP],
    len: usize,
    spacing_m: f64,
    last_kept_dist_m: f64,
}

impl ElevProfile {
    const fn new() -> Self {
        Self {
            samples: [0; ELEV_PROFILE_CAP],
            len: 0,
            spacing_m: ELEV_PROFILE_SPACING_M,
            last_kept_dist_m: 0.0,
        }
    }

    fn reset(&mut self) {
        *self = Self::new();
    }

    /// Keep the run's altitude at `dist_m`: the first sample anchors the start,
    /// later ones are kept once the run has advanced a full spacing interval;
    /// thin by halving when the buffer is full.
    fn push(&mut self, dist_m: f64, alt_m: f64) {
        let value = alt_m as i32;
        if self.len == 0 {
            self.samples[0] = value;
            self.len = 1;
            self.last_kept_dist_m = dist_m;
            return;
        }
        if dist_m - self.last_kept_dist_m >= self.spacing_m {
            if self.len == ELEV_PROFILE_CAP {
                self.thin();
            }
            self.samples[self.len] = value;
            self.len += 1;
            self.last_kept_dist_m = dist_m;
        }
    }

    fn thin(&mut self) {
        let mut kept = 0;
        let mut i = 0;
        while i < self.len {
            self.samples[kept] = self.samples[i];
            kept += 1;
            i += 2;
        }
        self.len = kept;
        self.spacing_m *= 2.0;
    }

    fn view(&self) -> ElevProfileView {
        ElevProfileView {
            samples: self.samples,
            len: self.len,
        }
    }
}

/// What the record task writes as the run blob's finalize-time workout
/// summary ([`Recorder::workout_summary`]): the planned step count, the
/// runner's live roll-up, and the arming-time `WKT1` frame CRC (`None` only
/// for a step list the canonical encoder refuses, in which case no summary —
/// and so no attributable trail — is written).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WorkoutSummary {
    pub step_total: u8,
    pub rollup: WorkoutAdherence,
    pub frame_crc: Option<u32>,
}

pub struct Recorder {
    state: RecordState,
    /// Distinguishes an explicit `pause()` (resumed only by `resume()`) from a
    /// speed-derived auto-pause (resumed by the next moving fix).
    manual_paused: bool,
    start_s: u32,
    now_s: u32,
    moving_s: u32,
    /// Seconds the clock advanced while manually paused. The workout runner's
    /// time axis is elapsed minus this — the phone recorder's stopwatch, which
    /// halts on a manual pause but runs through an auto-pause (a standing rest
    /// inside a timed recovery step is the step working as intended).
    manual_paused_s: u32,
    distance_m: f64,
    current_speed_mps: f32,
    /// Last fix accepted for distance — the anchor the next segment measures
    /// from. Cleared on start / resume so a pause gap is never one huge hop.
    last: Option<Fix>,
    /// Whether the most recent [`on_fix`](Recorder::on_fix) call adopted the
    /// fix as a new anchor (the run's first fix, an accepted move, or a
    /// post-gap re-anchor — see [`GPS_REANCHOR_AFTER_S`]). Read-only
    /// signal for the app's flash run-store; see [`last_fix_stored`](Recorder::last_fix_stored).
    last_fix_stored: bool,
    /// The flash writer's decimation factor, fed back by the app's record task
    /// after a slot-full thinning ([`run_store::RunWriter::push_point_bounded`]):
    /// 1 = full resolution, `k` = one stored point per `k` accepted fixes. The
    /// `Snapshot`'s `track_thinning` surfaces the reduced resolution on the
    /// wrist rather than leaving it a cable-only `warn!`.
    track_thinning: u8,
    /// 1-based number of the lap in progress; 0 while idle.
    lap_index: u16,
    /// Run totals at the current lap's start — the anchors lap-relative
    /// distance / elapsed / moving are measured from.
    lap_start_distance_m: f64,
    lap_start_elapsed_s: u32,
    lap_start_moving_s: u32,
    last_lap: Option<Lap>,
    /// What closes a lap without a press ([`set_auto_lap`](Recorder::set_auto_lap)).
    /// Survives `start`/`reset` like the other pushed configuration — a runner
    /// does not re-choose their lap trigger between the legs of a stage race.
    auto_lap: AutoLap,
    /// Closed laps awaiting flash persistence, drained by the app's record
    /// task via [`pop_closed_lap`](Recorder::pop_closed_lap). A queue rather
    /// than `last_lap` alone because one throttled-mode fix can close several
    /// laps at once and each must reach the stored blob. Sized for the worst
    /// realistic multi-close (a long dropout in Expedition mode).
    pending_laps: heapless::Deque<Lap, 16>,
    /// Streaming grade estimate for live GAP, fed each accepted fix with the
    /// baro-preferred altitude.
    gap: GapEstimator,
    /// Latest barometric altitude, published by the baro task via
    /// [`set_baro_altitude`](Recorder::set_baro_altitude). Preferred over the
    /// fix's GPS altitude for the grade — the same preference the flash
    /// run-store's point stamping already applies.
    baro_alt_m: Option<f64>,
    /// Latest heart-rate estimate, published by the hr task via
    /// [`set_hr`](Recorder::set_hr). `None` while the sensor is absent or the
    /// peak detector has lost the pulse — no zone time accrues then.
    hr_bpm: Option<u16>,
    /// Zone upper bounds derived from the configured max HR — see
    /// [`set_max_hr`](Recorder::set_max_hr).
    zone_cutoffs: ZoneCutoffs,
    /// The alert engine's armed zone ceiling + pace band, mirrored in by the
    /// record task via [`set_alert_arms`](Recorder::set_alert_arms) so the
    /// Zones and Pace pages can say whether their over-effort alert is armed.
    /// Only the engine's validated state is ever mirrored — the recorder never
    /// interprets the values, it just carries them to the face.
    zone_ceiling: Option<u8>,
    pace_band: Option<(u32, u32)>,
    /// Per-zone moving-time accumulators, reset on [`start`](Recorder::start).
    zone_time_s: [u32; ZONE_COUNT],
    /// Time-weighted BPM sum + its seconds, banked exactly where zone time
    /// banks (moving time with a live reading), reset on `start` — the run's
    /// average HR for the TRIMP stress model, without holding a sample series.
    hr_dt_bpm: u64,
    hr_dt_s: u32,
    /// The TRIMP calibration pair, from the settings sync via
    /// [`set_max_hr`](Recorder::set_max_hr) /
    /// [`set_resting_hr`](Recorder::set_resting_hr). Either absent keeps the
    /// single-run stress on the distance model.
    max_hr_bpm: Option<u16>,
    resting_hr_bpm: Option<u16>,
    /// The synced rolling CTL/ATL/TSB trio — see
    /// [`set_load_trend`](Recorder::set_load_trend); `None` keeps the
    /// TrainingLoad page's rolling half an honest "NOT SYNCED".
    load_trend: Option<LoadTrendView>,
    /// Virtual partner vs the configured goal — see
    /// [`set_pacer_goal`](Recorder::set_pacer_goal).
    pacer: Pacer,
    /// Expected seconds between incoming fixes — 1 at the default full rate;
    /// a throttled GNSS mode raises it. See
    /// [`set_fix_interval_s`](Recorder::set_fix_interval_s).
    fix_interval_s: u32,
    /// Distance along the loaded course, fed per accepted fix by the nav task
    /// (which owns the course + projection). `None` with no course loaded — the
    /// recorder stays course-agnostic; this is one more external input like the
    /// HR / baro / pacer-goal hooks, not a course dependency in the core math.
    route_along_m: Option<f64>,
    /// `now_s` when [`route_along_m`](Recorder::route_along_m) last updated — a
    /// position frozen by a lost signal ages into "stale" past a few fix
    /// intervals, at which point the cutoff ETA withholds a projected time.
    route_along_at_s: u32,
    /// Cutoff legs for the loaded course (distance-along-course + elapsed
    /// limit), set via [`set_cutoff_legs`](Recorder::set_cutoff_legs). Empty on
    /// the hardware build until a course-push path lands.
    cutoff_legs: heapless::Vec<CutoffLeg, MAX_CUTOFF_LEGS>,
    /// Per-pace-bucket distance accumulators (metres), reset on `start`.
    pace_bucket_m: [f64; PACE_BUCKET_COUNT],
    /// Baseline mileage + replacement target of the active gear, from a future
    /// settings sync via [`set_gear`](Recorder::set_gear); both `None` leaves
    /// the gear page inactive. The live run's distance is added to the baseline
    /// at snapshot time.
    gear_base_m: Option<f64>,
    gear_target_m: Option<f64>,
    /// The loaded roadbook checkpoints, pushed pre-built (see
    /// [`RoadbookCheckpoint`]); empty leaves the Roadbook + Fuel pages inactive.
    roadbook_legs: heapless::Vec<RoadbookCheckpoint, MAX_PUSHED_LEGS>,
    /// The synced goal-race pace (seconds per km) the TrainingPaces page derives
    /// its zone paces from — the same future settings-sync hook shape as the
    /// others; `None` by default leaves that page inactive. Plausibility-guarded
    /// in [`set_training_goal_pace_s_per_km`](Recorder::set_training_goal_pace_s_per_km).
    training_goal_pace_s_per_km: Option<f64>,
    /// The synced fitness snapshot the Fitness page shows, pushed pre-computed by
    /// the phone (which holds the multi-day history the on-watch cores can't).
    /// `None` by default leaves that page inactive.
    fitness: Option<FitnessView>,
    /// The decimated elevation series, fed the baro-preferred altitude on each
    /// accepted fix (the same seam that feeds the GAP grade + trackback), reset
    /// on [`start`](Recorder::start).
    elev_profile: ElevProfile,
    /// Phone-pushed summaries for the twelve 2026-07-11 glance pages; each
    /// `None` by default leaves its page an honest empty state until synced.
    recap: Option<RecapView>,
    streaks: Option<StreaksView>,
    run_stats: Option<RunStatsView>,
    pr_recency: Option<PrRecencyView>,
    plan_replan: Option<PlanReplanView>,
    plan_adaptive: Option<PlanAdaptiveView>,
    /// The armed guided run, a reference into the compiled-in library
    /// ([`set_guided_run`](Recorder::set_guided_run)); `None` leaves the
    /// GuidedRun page an honest inactive state.
    guided: Option<&'static GuidedRun<'static>>,
    /// The armed structured workout — the [`crate::workout`] runner over the
    /// pushed pre-expanded step list ([`set_workout`](Recorder::set_workout));
    /// `None` leaves the Workout page an honest inactive state.
    workout: Option<WorkoutRunner>,
    /// The armed step list's canonical `WKT1` CRC, computed once at arming —
    /// the flash blob's attribution handle
    /// ([`workout_summary`](Recorder::workout_summary)).
    workout_frame_crc: Option<u32>,
    /// How many settled step results the flash drain has consumed
    /// ([`pop_settled_workout_result`](Recorder::pop_settled_workout_result));
    /// reset whenever the runner's result trail resets (arming, start).
    workout_results_popped: usize,
    readiness: Option<ReadinessView>,
    goals: Option<GoalsView>,
    turn_cue: Option<TurnCueView>,
    nav_off_course: Option<bool>,
    route_simplify: Option<RouteSimplifyView>,
    auto_effort: Option<AutoEffortView>,
    route_elev: Option<RouteElevView>,
    race_day: Option<RaceDayView>,
    /// The pushed race pacing-strategy plan, built once in
    /// [`set_race_phases`](Recorder::set_race_phases); empty leaves the phase
    /// rows inactive. The phase in force is re-derived per snapshot from the
    /// live distance, so it advances with the run rather than at sync time.
    race_phases: PhasePlan,
    race_phase_goal_pace_s_per_km: Option<f64>,
    /// The armed countdown / stopwatch reading, fed per tick by the task that
    /// owns the instrument ([`set_timer`](Recorder::set_timer)).
    timer: Option<TimerView>,
    /// Whether the nav task holds a loaded course — the Nav page's data
    /// presence, fed via [`set_course_loaded`](Recorder::set_course_loaded)
    /// (the recorder stays course-agnostic; this is a presence bit, not the
    /// course).
    course_loaded: bool,
    /// The runner's curated page set, from settings sync
    /// ([`set_pages_enabled`](Recorder::set_pages_enabled)); bit =
    /// [`Page::bit`]. Default all-enabled.
    pages_enabled: u64,
    /// Whether the BTN3 cycle skips pages whose backing data is absent
    /// ([`set_hide_empty_pages`](Recorder::set_hide_empty_pages)). Default on:
    /// an unsynced watch cycles ~10 live pages instead of 33, and a page
    /// appears the moment its data does. Off restores the full fixed cycle
    /// (every empty state stays visitable).
    hide_empty_pages: bool,

    /// How many of the runner's composed screens exist
    /// ([`set_screen_count`](Recorder::set_screen_count)) — the count alone,
    /// never the screens.
    screen_count: usize,
    /// The synced timezone offset — the Daylight page's data presence, fed
    /// via [`set_tz_offset_min`](Recorder::set_tz_offset_min) (the face reads
    /// the live offset from the `state` watch; this is a presence bit, like
    /// [`course_loaded`](Recorder::set_course_loaded)).
    tz_offset_min: Option<i16>,
    /// The `baro` task's latest pressure tendency, held for the snapshot.
    /// Deliberately not cleared by a run boundary: the weather does not restart
    /// when the runner presses start.
    storm: Option<StormView>,
    /// Live ascent segmentation ([`crate::climb`]), fed the run distance +
    /// baro-preferred altitude on each accepted fix — the same seam the GAP
    /// grade and the elevation profile ride. Reset on
    /// [`start`](Recorder::start): a new run must not inherit the last one's
    /// foot, which at a lower trailhead would open a climb on the first fix.
    climb: ClimbDetector,
    /// Backyard-ultra mode (§ 372). Armed from the idle settings menu, so a run
    /// is wholly inside the mode or wholly outside it.
    backyard: Backyard,
    /// The receiver's UTC time-of-day and the uptime second it arrived on —
    /// the anchor the local wall clock extrapolates from, the same shaping the
    /// Daylight page's [`crate::daylight::daylight_at`] does. Deliberately NOT
    /// cleared by a pause the way `last` is: a paused runner's clock has not
    /// stopped, and the § 372 bell is anchored to it.
    last_clock: Option<(u32, u32)>,
    /// Positions the runner marked mid-run (§357), newest-last. Deliberately
    /// NOT cleared by [`start`](Recorder::start) or [`reset`](Recorder::reset):
    /// a water stash marked on yesterday's recce is the whole point of the
    /// feature, so the store outlives the run that filled it and only ages out
    /// by the newest-wins eviction in [`Waypoints::mark`]. The app restores it
    /// from flash at boot via [`set_waypoints`](Recorder::set_waypoints).
    waypoints: Waypoints,
    waypoint_mark_seq: u8,
    waypoint_refuse_seq: u8,
    /// The runner's pushed fuel cadences (`SET1`), seconds of moving time per
    /// sip / gel — the same values the alert engine runs on, mirrored here so
    /// the Fuel page's carry-out math describes THIS runner's plan rather
    /// than the temperate default. `None` = unpushed, defaults apply.
    fuel_drink_interval_s: Option<u32>,
    fuel_eat_interval_s: Option<u32>,
}

impl Default for Recorder {
    fn default() -> Self {
        Self::new()
    }
}

impl Recorder {
    pub const fn new() -> Self {
        Self {
            state: RecordState::Idle,
            manual_paused: false,
            start_s: 0,
            now_s: 0,
            moving_s: 0,
            manual_paused_s: 0,
            distance_m: 0.0,
            current_speed_mps: 0.0,
            last: None,
            last_fix_stored: false,
            track_thinning: 1,
            lap_index: 0,
            lap_start_distance_m: 0.0,
            lap_start_elapsed_s: 0,
            lap_start_moving_s: 0,
            last_lap: None,
            auto_lap: AUTO_LAP_DEFAULT,
            pending_laps: heapless::Deque::new(),
            gap: GapEstimator::new(),
            baro_alt_m: None,
            hr_bpm: None,
            zone_cutoffs: hr_zones::zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            zone_ceiling: None,
            pace_band: None,
            zone_time_s: [0; ZONE_COUNT],
            hr_dt_bpm: 0,
            hr_dt_s: 0,
            max_hr_bpm: None,
            resting_hr_bpm: None,
            load_trend: None,
            pacer: Pacer::new(),
            fix_interval_s: 1,
            route_along_m: None,
            route_along_at_s: 0,
            cutoff_legs: heapless::Vec::new(),
            pace_bucket_m: [0.0; PACE_BUCKET_COUNT],
            gear_base_m: None,
            gear_target_m: None,
            roadbook_legs: heapless::Vec::new(),
            training_goal_pace_s_per_km: None,
            fitness: None,
            elev_profile: ElevProfile::new(),
            recap: None,
            streaks: None,
            run_stats: None,
            pr_recency: None,
            plan_replan: None,
            plan_adaptive: None,
            guided: None,
            workout: None,
            workout_frame_crc: None,
            workout_results_popped: 0,
            readiness: None,
            goals: None,
            turn_cue: None,
            nav_off_course: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            race_day: None,
            race_phases: PhasePlan::new(),
            race_phase_goal_pace_s_per_km: None,
            timer: None,
            course_loaded: false,
            pages_enabled: u64::MAX,
            hide_empty_pages: true,
            screen_count: 0,
            tz_offset_min: None,
            storm: None,
            climb: ClimbDetector::new(),
            backyard: Backyard::new(),
            last_clock: None,
            waypoints: Waypoints::new(),
            waypoint_mark_seq: 0,
            waypoint_refuse_seq: 0,
            fuel_drink_interval_s: None,
            fuel_eat_interval_s: None,
        }
    }

    /// Presence bit for the Nav page: the nav task holds a loaded course.
    pub fn set_course_loaded(&mut self, loaded: bool) {
        self.course_loaded = loaded;
    }

    /// The flash writer's decimation factor, fed back by the app's record
    /// task after a slot-full thinning; clamps to the display's `u8` (a
    /// factor past 255 is indistinguishable on a glance row). Reset to full
    /// resolution on [`start`](Recorder::start) with the rest of the run
    /// state.
    pub fn set_track_thinning(&mut self, factor: u32) {
        self.track_thinning = factor.clamp(1, u8::MAX as u32) as u8;
    }

    /// The curated page set from settings sync (bit = [`Page::bit`]). Any
    /// mask is accepted — [`Page::next_in`] force-includes the Dashboard, so
    /// even an all-zero push can't empty the cycle.
    pub fn set_pages_enabled(&mut self, mask: u64) {
        self.pages_enabled = mask;
    }

    /// Whether the cycle skips data-less pages (see the field doc).
    pub fn set_hide_empty_pages(&mut self, hide: bool) {
        self.hide_empty_pages = hide;
    }

    /// How many composed screens (§ 364) the runner has, so the cycle carries
    /// exactly that many `Screen*` pages.
    ///
    /// The recorder holds only the count — the screens themselves are drawn
    /// from the pushed set the face is handed, and duplicating them here would
    /// put the same data in two places that could disagree about how many there
    /// are. Clamped, so a caller cannot open a page that has no screen behind
    /// it.
    pub fn set_screen_count(&mut self, n: usize) {
        self.screen_count = n.min(crate::screens::MAX_SCREENS);
    }

    /// Presence bit for the Daylight page: the settings sync has delivered a
    /// timezone offset. Without one the countdown would run against the wrong
    /// midnight, so the page stays out of the cycle rather than empty in it.
    /// Arm or disarm backyard-ultra mode (§ 372) — the idle settings menu's
    /// BACKYARD row, re-seeded from the persisted `CFG1` flag at boot.
    ///
    /// While armed the bell drives the auto-lap in place of the 1 km boundary:
    /// a backyard loop crosses six kilometre lines, so leaving the distance
    /// auto-lap on would bury the loop splits the phone reads as the runner's
    /// result. Re-arming an armed mode is inert, so the boot re-seed cannot
    /// wipe a race in progress.
    pub fn set_backyard_armed(&mut self, armed: bool) {
        self.backyard.set_armed(armed, self.distance_m);
    }

    pub fn set_tz_offset_min(&mut self, m: i16) {
        self.tz_offset_min = Some(m);
    }

    /// Mark the last accepted fix's position as a waypoint (§357) — BTN5's
    /// hold tier. Returns whether a mark was actually taken, so the caller can
    /// tell "saved" from "no position to save": marking uses the recorder's
    /// distance anchor rather than the raw fix stream because that is the
    /// position the run itself is measured from, so the mark and the track
    /// agree about where the runner was. No anchor (pre-first-fix, or a run
    /// that has only seen rejected fixes) marks nothing rather than a
    /// fabricated 0,0.
    ///
    /// A mark outside a run is refused for the same reason the button
    /// reducer never emits one there: an idle watch's anchor is the PREVIOUS
    /// run's last position, and silently saving that would be a lie about
    /// where the runner is standing.
    pub fn mark_waypoint(&mut self, uptime_s: u32) -> bool {
        if !matches!(self.state, RecordState::Recording | RecordState::Paused) {
            self.waypoint_refuse_seq = self.waypoint_refuse_seq.wrapping_add(1);
            return false;
        }
        let Some(last) = self.last else {
            self.waypoint_refuse_seq = self.waypoint_refuse_seq.wrapping_add(1);
            return false;
        };
        let marked = self.waypoints.mark(last.lat_deg, last.lon_deg, uptime_s);
        if marked {
            self.waypoint_mark_seq = self.waypoint_mark_seq.wrapping_add(1);
        } else {
            self.waypoint_refuse_seq = self.waypoint_refuse_seq.wrapping_add(1);
        }
        marked
    }

    /// Restore the marks persisted in flash (the app's boot path). Whole-store
    /// replacement rather than a merge: the flash record IS the store, so a
    /// decode failure leaves whatever is already in RAM instead of clearing it.
    pub fn set_waypoints(&mut self, w: Waypoints) {
        self.waypoints = w;
    }

    /// The marked positions, for the app's flash persistence.
    pub fn waypoints(&self) -> &Waypoints {
        &self.waypoints
    }

    /// Expected seconds between incoming fixes, from the selected GNSS mode
    /// (clamped to at least 1). At the default 1 s cadence the acceptance
    /// filter is byte-identical to the Dart `run_recorder`'s. At a throttled
    /// cadence the fixed [`MAX_JUMP_M`] ceiling would reject *every* legitimate
    /// segment (a runner at 4 m/s covers 240 m between 60 s fixes), so the
    /// jump gate switches to the segment-speed ceiling `MAX_SPEED_MPS * dt` —
    /// the same physical plausibility bound the speed gate already enforces,
    /// scaled by the actual time between fixes rather than an assumed 1 s.
    /// Deliberately keyed off the configured interval, not off `dt` alone, so
    /// the full-rate filter is never silently loosened: at 1 Hz a 150 m hop
    /// after a 30 s signal gap still credits no distance. (The hop does
    /// rebase the anchor when the gap is [`GPS_REANCHOR_AFTER_S`] or longer —
    /// `run_recorder`'s #330 — so recording resumes from the reacquire point
    /// instead of freezing against a stale anchor.)
    ///
    /// Forwarded to the GAP estimator, whose power-hike hold budget scales
    /// off the same cadence
    /// ([`gap_hold_ticks`](crate::grade_adjusted_pace::gap_hold_ticks)):
    /// `current_speed_mps` freezes between fixes, so a tick-count hold blind
    /// to the interval would expire mid-gap against a speed that could not
    /// yet have changed.
    pub fn set_fix_interval_s(&mut self, interval_s: u32) {
        self.fix_interval_s = interval_s.max(1);
        self.gap.set_fix_interval_s(interval_s);
    }

    pub fn state(&self) -> RecordState {
        self.state
    }

    /// Latest barometric altitude for the live-GAP grade. Sticky — the baro
    /// task publishes on change, so the most recent reading stays preferred
    /// over GPS altitude until the next one arrives.
    pub fn set_baro_altitude(&mut self, alt_m: f32) {
        self.baro_alt_m = Some(alt_m as f64);
    }

    /// Latest barometric pressure tendency from the `baro` task ([`crate::storm`]).
    /// `None` is a watch whose barometer never answered, which keeps the Storm
    /// page out of the cycle entirely; every other state — including both
    /// refusals — is a [`StormView`] the page renders honestly.
    pub fn set_storm(&mut self, view: Option<StormView>) {
        self.storm = view;
    }

    /// Latest heart-rate estimate for the zone accumulators. `None` clears it
    /// (the detector lost the pulse), so a stale BPM never keeps banking zone
    /// time after the sensor goes quiet.
    pub fn set_hr(&mut self, bpm: Option<u16>) {
        self.hr_bpm = bpm;
    }

    /// Rebuild the zone ladder from a configured max HR — the settings-sync
    /// hook the `SET1` frame drives. Values outside the app's plausibility
    /// window (80..=240, the same guard web's `defaultZoneCutoffs` applies to
    /// an explicit override) are ignored so garbage can't flatten the ladder.
    /// Zone time already banked is not re-bucketed — the ladder applies from
    /// now on. Also the upper half of the TRIMP calibration pair (see
    /// [`set_resting_hr`](Recorder::set_resting_hr)).
    pub fn set_max_hr(&mut self, max_hr_bpm: u16) {
        if (MAX_HR_PLAUSIBLE_MIN..=MAX_HR_PLAUSIBLE_MAX).contains(&max_hr_bpm) {
            self.zone_cutoffs = hr_zones::zone_cutoffs_from_max_hr(max_hr_bpm);
            self.max_hr_bpm = Some(max_hr_bpm);
        }
    }

    /// Mirror the alert engine's armed zone ceiling + pace band into the
    /// snapshot, so the Zones and Pace pages can say whether their over-effort
    /// alert is armed at all — a phone-less runner otherwise carries a
    /// disarmed race-critical alert with nothing on any surface saying so.
    /// Callers pass the engine's own getters, never raw wire values: the
    /// engine validates on set, and this mirror must not become a second
    /// place the values are interpreted.
    pub fn set_alert_arms(&mut self, zone_ceiling: Option<u8>, pace_band: Option<(u32, u32)>) {
        self.zone_ceiling = zone_ceiling;
        self.pace_band = pace_band;
    }

    /// Resting HR — the lower half of the TRIMP calibration pair. With both
    /// halves synced (and a live HR average) the single-run training stress
    /// upgrades from the distance proxy to Banister TRIMP, the same ladder the
    /// web/Dart `training_load` helpers run. Values outside
    /// [`RESTING_HR_PLAUSIBLE_MIN`]..=[`RESTING_HR_PLAUSIBLE_MAX`] are ignored.
    pub fn set_resting_hr(&mut self, resting_hr_bpm: u16) {
        if (RESTING_HR_PLAUSIBLE_MIN..=RESTING_HR_PLAUSIBLE_MAX).contains(&resting_hr_bpm) {
            self.resting_hr_bpm = Some(resting_hr_bpm);
        }
    }

    /// Load the synced rolling CTL/ATL/TSB trio the TrainingLoad page's rolling
    /// half shows — pushed pre-computed by the phone (the watch holds no
    /// multi-day history), the [`set_fitness`](Recorder::set_fitness) hook
    /// shape. `None` clears back to the honest "NOT SYNCED". The trio is
    /// accepted or rejected WHOLE: a non-finite or implausible member drops the
    /// push (keeping the current view) rather than blending a corrupt value
    /// into two good ones — the pace-band atomicity rule.
    pub fn set_load_trend(&mut self, view: Option<LoadTrendView>) {
        match view {
            None => self.load_trend = None,
            Some(v) => {
                let plausible = |x: f32| x.is_finite() && x.abs() <= LOAD_TREND_PLAUSIBLE_MAX;
                if plausible(v.ctl)
                    && plausible(v.atl)
                    && plausible(v.tsb)
                    && v.ctl >= 0.0
                    && v.atl >= 0.0
                {
                    self.load_trend = Some(v);
                }
            }
        }
    }

    /// Arm the virtual partner with a goal distance + time — the same future
    /// settings-sync hook shape as [`set_max_hr`](Recorder::set_max_hr);
    /// nothing on-device sets it at tier 1, so the default (unset) keeps the
    /// pacer inactive. Plausibility guarding lives in [`Pacer::set_goal`].
    pub fn set_pacer_goal(&mut self, distance_m: u32, time_s: u32) {
        self.pacer.set_goal(distance_m, time_s);
    }

    /// Latest distance along the loaded course, from the nav task's projection.
    /// `None` clears it (no course, or a fix that didn't project). Stamped with
    /// the current clock so a lost-signal freeze ages into "stale" and the
    /// cutoff ETA stops projecting off it — the recorder never fabricates an
    /// arrival from a position it can no longer trust.
    pub fn set_route_position(&mut self, along_m: Option<f64>) {
        self.route_along_m = along_m;
        if along_m.is_some() {
            self.route_along_at_s = self.now_s;
        }
    }

    /// Load the cutoff legs for the current course (distance-along-course +
    /// elapsed-seconds limit). Replaces any existing set and caps at
    /// [`MAX_CUTOFF_LEGS`] rather than growing — a longer course is trimmed
    /// phone-side before the push. Empty legs leave the CutoffEta page inactive.
    pub fn set_cutoff_legs(&mut self, legs: &[CutoffLeg]) {
        self.cutoff_legs.clear();
        for leg in legs.iter().take(MAX_CUTOFF_LEGS) {
            let _ = self.cutoff_legs.push(*leg);
        }
    }

    /// Load the active gear's rolled-up baseline distance + replacement target
    /// (metres) — the same future settings-sync hook shape as the others; both
    /// unset by default keeps the gear page inactive. The live run's distance is
    /// added to the baseline in [`snapshot`](Recorder::snapshot), so a run in
    /// progress wears the shoe down in real time.
    pub fn set_gear(&mut self, baseline_m: Option<f64>, target_m: Option<f64>) {
        self.gear_base_m = baseline_m;
        self.gear_target_m = target_m;
    }

    /// Load the roadbook checkpoints for the current course (pushed pre-built,
    /// see [`RoadbookCheckpoint`]). Replaces any existing set and caps at
    /// [`MAX_PUSHED_LEGS`] rather than growing. Empty legs leave the Roadbook +
    /// Fuel pages inactive. The checkpoint curve doubles as the virtual
    /// partner's terrain schedule ([`crate::pacer::Pacer::set_schedule`]) —
    /// the phone allocated `projected_elapsed_s` by grade-adjusted effort, so
    /// the pacer grades a climb honestly; an empty or shapeless roadbook
    /// degrades the partner back to even pace.
    pub fn set_roadbook(&mut self, legs: &[RoadbookCheckpoint]) {
        self.roadbook_legs.clear();
        let mut schedule: heapless::Vec<(f64, u32), MAX_PUSHED_LEGS> = heapless::Vec::new();
        for leg in legs.iter().take(MAX_PUSHED_LEGS) {
            let _ = self.roadbook_legs.push(*leg);
            let _ = schedule.push((leg.cum_dist_m, leg.projected_elapsed_s));
        }
        self.pacer.set_schedule(&schedule);
    }

    /// Load the synced goal-race pace (seconds per km) the TrainingPaces page
    /// derives its zone paces from — the same future settings-sync hook shape as
    /// the others; `None` (or a value outside the
    /// [`GOAL_PACE_PLAUSIBLE_MIN_S_PER_KM`]..=[`GOAL_PACE_PLAUSIBLE_MAX_S_PER_KM`]
    /// window) leaves the page inactive. The zone paces are re-derived at
    /// [`snapshot`](Recorder::snapshot) time via [`paces_from_goal_pace`].
    pub fn set_training_goal_pace_s_per_km(&mut self, goal_s_per_km: Option<f64>) {
        self.training_goal_pace_s_per_km = goal_s_per_km.filter(|p| {
            (GOAL_PACE_PLAUSIBLE_MIN_S_PER_KM..=GOAL_PACE_PLAUSIBLE_MAX_S_PER_KM).contains(p)
        });
    }

    /// Load the synced fitness snapshot the Fitness page shows — the VO2 max /
    /// VDOT ceiling + the recovery-advice verdict, both pushed pre-computed by
    /// the phone. Same unset-by-default hook shape as the others. The VO2 value
    /// is plausibility-guarded (a corrupt push can't fake a fitness number);
    /// both `None` leaves the page inactive. Deliberately no CTL/ATL/TSB input —
    /// the rolling series needs history the watch doesn't hold.
    pub fn set_fitness(&mut self, vo2_max: Option<f64>, recovery: Option<RecoveryAdvice>) {
        let vo2 = vo2_max
            .filter(|v| (FITNESS_VO2_PLAUSIBLE_MIN..=FITNESS_VO2_PLAUSIBLE_MAX).contains(v))
            .map(|v| v as f32);
        self.fitness = if vo2.is_none() && recovery.is_none() {
            None
        } else {
            Some(FitnessView {
                vo2_max: vo2,
                recovery,
            })
        };
    }

    /// Load the synced summaries for the twelve 2026-07-11 glance pages. Each is
    /// a phone-pushed `Copy` view (the phone runs the ported core over the
    /// history / plan / course the watch doesn't hold) stored verbatim; `None`
    /// leaves the page an honest empty state. Display state only — none touch the
    /// flash run-store wire format. Kept as plain setters (no plausibility guard):
    /// the phone owns the computation, and the fields are already bounded counts.
    pub fn set_recap(&mut self, view: Option<RecapView>) {
        self.recap = view;
    }

    pub fn set_streaks(&mut self, view: Option<StreaksView>) {
        self.streaks = view;
    }

    pub fn set_run_stats(&mut self, view: Option<RunStatsView>) {
        self.run_stats = view;
    }

    pub fn set_pr_recency(&mut self, view: Option<PrRecencyView>) {
        self.pr_recency = view;
    }

    pub fn set_plan_replan(&mut self, view: Option<PlanReplanView>) {
        self.plan_replan = view;
    }

    /// The trend + confidence are clamped to their 0..=2 code spaces and the
    /// week counts to the trend window, so a corrupt push can't render an
    /// unknown verdict or an impossible "9/3 weeks".
    pub fn set_plan_adaptive(&mut self, view: Option<PlanAdaptiveView>) {
        self.plan_adaptive = view.map(|v| {
            let window = v
                .window_weeks
                .min(crate::plan_adaptive_replan::ADAPTIVE_TREND_WINDOW as u8);
            PlanAdaptiveView {
                trend: v.trend.min(2),
                confidence: v.confidence.min(2),
                flagged_weeks: v.flagged_weeks.min(window),
                window_weeks: window,
                changes: v.changes,
                fitness_gated: v.fitness_gated,
            }
        });
    }

    /// Arm the Workout page + runner with a pushed pre-expanded step list
    /// (the `WKT1` push — [`crate::workout_store`] already validated every
    /// step). Empty disarms; a list the runner rejects (over-cap) is IGNORED
    /// so garbage can't disarm a workout mid-session. Armed mid-run, the
    /// runner anchors at the current totals on its next feed; armed idle, it
    /// waits for [`start`](Recorder::start). The step list is configuration
    /// like the pacer goal — it survives stop and re-arms on the next start.
    ///
    /// A push identical to the armed list (same canonical frame CRC — the
    /// §356 attribution identity) is a NO-OP: a BLE retry or a phone
    /// reconnect re-delivering the frame must not wipe mid-run step progress
    /// and splice a second trail into the stored blob — exactly the
    /// duplicate-index shape the phone then has to discard. Re-arming stays
    /// what it is for a *different* workout: a deliberate change.
    pub fn set_workout(&mut self, steps: &[WorkoutStep]) {
        if steps.is_empty() {
            self.workout = None;
            self.workout_frame_crc = None;
            self.workout_results_popped = 0;
            return;
        }
        let crc = workout_store::frame_crc(steps);
        if self.workout.is_some() && crc.is_some() && crc == self.workout_frame_crc {
            return;
        }
        if let Some(w) = WorkoutRunner::new(steps) {
            self.workout = Some(w);
            self.workout_frame_crc = crc;
            self.workout_results_popped = 0;
        }
    }

    /// The next settled step result the flash drain has not yet consumed —
    /// the [`pop_closed_lap`](Recorder::pop_closed_lap) contract for workout
    /// outcomes: the record task drains after each event and streams what it
    /// gets into the staged blob, so a mid-run checkpoint carries every step
    /// settled before it. The cursor resets wherever the runner's trail does
    /// (arming, [`start`](Recorder::start)).
    pub fn pop_settled_workout_result(&mut self) -> Option<StepResult> {
        let w = self.workout.as_ref()?;
        let r = w.results().get(self.workout_results_popped).copied()?;
        self.workout_results_popped += 1;
        Some(r)
    }

    /// The armed workout's in-progress step recorded as skipped-so-far, for
    /// the finalize-time flush — a run stopped mid-step still accounts for
    /// the step it was in, the phone runner's own convention.
    pub fn workout_in_progress_result(&self) -> Option<StepResult> {
        self.workout.as_ref()?.in_progress_result()
    }

    /// The armed workout's finalize-time summary: planned step count, the
    /// live ≥80 % roll-up, and the arming-time `WKT1` frame CRC. `None` when
    /// no workout is armed — a run without one writes no workout records.
    pub fn workout_summary(&self) -> Option<WorkoutSummary> {
        let w = self.workout.as_ref()?;
        Some(WorkoutSummary {
            step_total: w.step_count().min(u8::MAX as usize) as u8,
            rollup: w.rollup(),
            frame_crc: self.workout_frame_crc,
        })
    }

    /// Arm the GuidedRun page with a scripted coach run by library id (the
    /// runner's selection, made on the phone). `None` disarms it.
    ///
    /// The guard is library membership plus the ported validator: an id that is
    /// not in the library, or a library entry whose cues are unsorted or run
    /// past its duration, is IGNORED — the current selection stands rather than
    /// a garbled push arming a different run or disarming one mid-run.
    pub fn set_guided_run(&mut self, id: Option<&str>) {
        match id {
            None => self.guided = None,
            Some(id) => {
                if let Some(g) = find_guided_run(id).filter(|g| is_guided_run_valid(g)) {
                    self.guided = Some(g);
                }
            }
        }
    }

    /// The readiness score is clamped to 0..=100 and the band to 0..=2 so a
    /// corrupt push can't render an out-of-range ring or an unknown band label.
    pub fn set_readiness(&mut self, view: Option<ReadinessView>) {
        self.readiness = view.map(|v| ReadinessView {
            score: v.score.min(100),
            band: v.band.min(2),
        });
    }

    /// The goal percent is clamped to 0..=100 so a corrupt push can't overfill
    /// the ring.
    pub fn set_goals(&mut self, view: Option<GoalsView>) {
        self.goals = view.map(|v| GoalsView {
            percent: v.percent.min(100),
            complete: v.complete,
        });
    }

    /// The turn direction is clamped to the 0..=7 code space so an unknown code
    /// can't index past the face's direction glyphs.
    pub fn set_turn_cue(&mut self, view: Option<TurnCueView>) {
        self.turn_cue = view.map(|v| TurnCueView {
            direction: v.direction.min(7),
            ..v
        });
    }

    /// The nav task's latched off-course verdict, fed per fix beside
    /// [`set_route_position`](Recorder::set_route_position) — see
    /// [`Snapshot::nav_off_course`] for the tri-state contract.
    pub fn set_nav_off_course(&mut self, off_course: Option<bool>) {
        self.nav_off_course = off_course;
    }

    /// Mirror the `SET1` fuel cadences into the Fuel page's carry-out math —
    /// the same guard shape as [`crate::alerts::AlertEngine::set_fuel_intervals`]:
    /// a zero interval is nonsense and leaves that arm on its current value.
    pub fn set_fuel_intervals(&mut self, drink_moving_s: u32, eat_moving_s: u32) {
        if drink_moving_s > 0 {
            self.fuel_drink_interval_s = Some(drink_moving_s);
        }
        if eat_moving_s > 0 {
            self.fuel_eat_interval_s = Some(eat_moving_s);
        }
    }

    pub fn set_route_simplify(&mut self, view: Option<RouteSimplifyView>) {
        self.route_simplify = view;
    }

    pub fn set_auto_effort(&mut self, view: Option<AutoEffortView>) {
        self.auto_effort = view;
    }

    /// Load the loaded course's climb profile — the nav task shapes it with
    /// [`crate::course_profile::course_elev_view`] whenever the active course
    /// changes, and `None` once no course is loaded. The recorder stays
    /// course-agnostic: it only folds the profile's length in with the fed
    /// along-course distance to place the page's position marker.
    pub fn set_route_elev(&mut self, view: Option<RouteElevView>) {
        self.route_elev = view;
    }

    /// The feasibility verdict is clamped to 0..=2 so a corrupt push can't render
    /// an unknown verdict label.
    /// Feed the countdown / stopwatch reading (§375). The same external-input
    /// shape as [`set_hr`](Recorder::set_hr) and
    /// [`set_route_position`](Recorder::set_route_position), and for the §215
    /// reason: the instrument is armed on the idle face and survives every run
    /// boundary, so the recorder has no business owning it — it only carries
    /// the reading so the page and the alert engine read one snapshot.
    pub fn set_timer(&mut self, view: Option<TimerView>) {
        self.timer = view;
    }

    pub fn set_race_day(&mut self, view: Option<RaceDayView>) {
        self.race_day = view.map(|v| RaceDayView {
            days_until: v.days_until,
            feasible: v.feasible.min(2),
        });
    }

    /// Load the runner's race pacing strategy: the race distance, the goal time
    /// (optional — without one the phases are still bounded by distance but carry
    /// no target pace), and the preset the phone chose. The plan is built here via
    /// [`build_phase_plan`]; the phase in force is re-derived per snapshot.
    ///
    /// Both inputs are plausibility-guarded and an implausible one is **ignored**
    /// (never clamped), the [`set_fitness`](Recorder::set_fitness) shape: a
    /// distance outside
    /// [`RACE_PHASE_PLAUSIBLE_MIN_DISTANCE_M`]..=[`RACE_PHASE_PLAUSIBLE_MAX_DISTANCE_M`]
    /// leaves the whole plan unset, and a goal time whose implied pace falls
    /// outside the shared
    /// [`GOAL_PACE_PLAUSIBLE_MIN_S_PER_KM`]..=[`GOAL_PACE_PLAUSIBLE_MAX_S_PER_KM`]
    /// band drops only the target pace — the phase boundaries are still honest.
    pub fn set_race_phases(
        &mut self,
        distance_m: Option<f64>,
        goal_time_s: Option<f64>,
        preset: RacePhasePreset,
    ) {
        self.race_phases.clear();
        self.race_phase_goal_pace_s_per_km = None;
        let Some(distance_m) = distance_m.filter(|d| {
            (RACE_PHASE_PLAUSIBLE_MIN_DISTANCE_M..=RACE_PHASE_PLAUSIBLE_MAX_DISTANCE_M).contains(d)
        }) else {
            return;
        };
        self.race_phases = build_phase_plan(distance_m, preset);
        self.race_phase_goal_pace_s_per_km = goal_time_s
            .and_then(|t| goal_pace_s_per_km(distance_m, t))
            .filter(|p| {
                (GOAL_PACE_PLAUSIBLE_MIN_S_PER_KM..=GOAL_PACE_PLAUSIBLE_MAX_S_PER_KM).contains(p)
            });
    }

    /// Whether the most recent [`on_fix`](Recorder::on_fix) stored a new track
    /// point — the run's first anchor, or an accepted move that accrued
    /// distance. `false` after any call that rejected the fix (corrupt / too
    /// fast), treated it as jitter, or was gated out by state (idle, finished,
    /// or manually paused). The app's flash run-store keys its `push_point` off
    /// this, so the stored track mirrors the recorder's accepted fixes exactly
    /// rather than duplicating the acceptance filter.
    pub fn last_fix_stored(&self) -> bool {
        self.last_fix_stored
    }

    /// Drain one closed lap awaiting flash persistence (oldest first). The
    /// app's record task pops after every event and writes each as a v2 lap
    /// record, so laps land in the stored blob in close order exactly once.
    pub fn pop_closed_lap(&mut self) -> Option<Lap> {
        self.pending_laps.pop_front()
    }

    /// Begin a run. Only valid from `Idle`; a second call is inert so a
    /// re-issued start can't reset a run in progress.
    pub fn start(&mut self, now_s: u32) {
        if self.state != RecordState::Idle {
            return;
        }
        self.state = RecordState::Recording;
        self.manual_paused = false;
        self.start_s = now_s;
        self.now_s = now_s;
        self.moving_s = 0;
        self.manual_paused_s = 0;
        self.distance_m = 0.0;
        self.current_speed_mps = 0.0;
        self.last = None;
        self.track_thinning = 1;
        self.backyard.on_run_start();
        self.lap_index = 1;
        self.lap_start_distance_m = 0.0;
        self.lap_start_elapsed_s = 0;
        self.lap_start_moving_s = 0;
        self.last_lap = None;
        self.pending_laps.clear();
        self.zone_time_s = [0; ZONE_COUNT];
        self.hr_dt_bpm = 0;
        self.hr_dt_s = 0;
        self.pace_bucket_m = [0.0; PACE_BUCKET_COUNT];
        // Fresh grade anchors for the new run; the sticky baro altitude and HR
        // stay — each is still the current reading, not run state. The pacer
        // splits the same way: its finish latch is run state and clears, the
        // configured goal is settings and stays.
        self.gap.reset();
        self.pacer.reset();
        self.elev_profile.reset();
        self.climb.reset();
        // The armed workout re-runs from step 0, and the immediate feed
        // announces the first step at the gun (transition_seq 1).
        if let Some(w) = self.workout.as_mut() {
            w.reset();
            w.on_totals(0.0, 0);
            self.workout_results_popped = 0;
        }
    }

    /// Manually pause. Valid while recording or auto-paused; inert once idle,
    /// finished, or already manually paused.
    pub fn pause(&mut self, now_s: u32) {
        let active = self.state == RecordState::Recording
            || (self.state == RecordState::Paused && !self.manual_paused);
        if !active {
            return;
        }
        self.advance_now(now_s);
        self.state = RecordState::Paused;
        self.manual_paused = true;
        self.current_speed_mps = 0.0;
    }

    /// Resume a manual pause. Inert unless currently manually paused (an
    /// auto-pause resumes on its own from the next moving fix).
    pub fn resume(&mut self, now_s: u32) {
        if self.state != RecordState::Paused || !self.manual_paused {
            return;
        }
        self.advance_now(now_s);
        self.state = RecordState::Recording;
        self.manual_paused = false;
        self.last = None;
    }

    /// Choose what closes a lap without a press ([`crate::auto_lap`]). Takes
    /// effect from the lap in progress: the new trigger measures from the
    /// current lap's start, not from the run total, so switching mid-run cannot
    /// retroactively close laps that never happened. No plausibility guard —
    /// the catalogue is closed, and the byte that names a rung is validated
    /// where it is decoded.
    pub fn set_auto_lap(&mut self, trigger: AutoLap) {
        self.auto_lap = trigger;
    }

    /// Close the current lap by hand (the Lap button). Valid whenever a run is
    /// in progress — recording, auto-paused, or manually paused (a lap taken
    /// while paused closes at the frozen totals); inert once idle or finished.
    /// Also resets the auto-lap countdown on whichever axis is armed: the next
    /// boundary is measured from here, not from multiples of the run total.
    pub fn lap(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.advance_now(now_s);
        self.close_lap();
        // In backyard mode that same press is the corral return (§ 372) — the
        // one gesture, marking the loop the runner just finished; it is not a
        // second meaning for BTN5, only a second reader of the lap it closes.
        self.backyard.on_corral_return(now_s, self.distance_m);
        // During a workout the lap press doubles as "advance the step" —
        // Garmin's own lap-button semantics — because the §350 grammar has no
        // spare button for a dedicated skip.
        if let Some(w) = self.workout.as_mut() {
            w.skip_step();
        }
    }

    /// Finalise the run. Inert once idle or already finished; afterward fixes
    /// and ticks no longer move any total. The lap in progress stays open — it
    /// shows on the face as the (frozen) current lap, and laps are RAM display
    /// state only, so there is no record to finalise it into.
    pub fn stop(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.advance_now(now_s);
        self.state = RecordState::Finished;
        self.current_speed_mps = 0.0;
    }

    /// Dismiss a finished run: back to `Idle`, so the idle face (the home
    /// screen) shows and a fresh `start` can follow — without this, `Finished`
    /// was a dead end and the watch stayed on the run view until reboot. Only
    /// valid once `Finished`; the stored run was committed at `stop`, so this
    /// changes view state only, never data (`start` clears the totals as
    /// always).
    pub fn reset(&mut self, now_s: u32) {
        if self.state != RecordState::Finished {
            return;
        }
        self.advance_now(now_s);
        self.state = RecordState::Idle;
    }

    /// Advance the wall clock without a new fix (the mobile recorder's 1 Hz
    /// tick). Elapsed grows through paused states; idle and finished are inert.
    ///
    /// A run whose fixes have dried up auto-pauses here. Every other state
    /// transition is driven by a fix arriving, so without this the recorder
    /// held `Recording` across a signal void for as long as the void lasted —
    /// distance and moving time correctly frozen, but the run view still
    /// telling the runner it was tracking them. The tick is the only thing
    /// that runs when nothing is arriving, so it is the only place the absence
    /// of fixes can be noticed.
    ///
    /// Gated on having had a fix at all: `last` is also cleared by
    /// [`resume`](Recorder::resume), and pausing a just-resumed run before its
    /// first fix would fight the runner's own button. A run that has never had
    /// a fix is the acquisition case, which the face reports separately.
    ///
    /// Deliberately moves the state and nothing else. It does **not** zero
    /// `current_speed_mps`, so [`is_moving`](Recorder::is_moving) — and with it
    /// the barometric vert accumulator — is untouched: banking a climb through
    /// a signal void is a core ultra case, and ageing the speed out was
    /// weighed and refused for exactly that reason. A void is a statement
    /// about the GPS, not about whether the runner is still climbing.
    pub fn tick(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.advance_now(now_s);
        if self.state == RecordState::Recording && self.fix_stale() {
            self.state = RecordState::Paused;
        }
        self.feed_workout();
        self.fold_backyard();
    }

    /// Consume one GPS fix, using its `uptime_s` as the current time. Ignored
    /// unless recording or auto-paused — a manual pause gates fixes out
    /// entirely, mirroring `run_recorder`'s `if (_paused) return`.
    pub fn on_fix(&mut self, fix: &Fix) {
        self.last_fix_stored = false;
        if let Some(tod) = fix.time_of_day {
            self.last_clock = Some((tod, fix.uptime_s));
        }
        match self.state {
            RecordState::Recording => {}
            RecordState::Paused if !self.manual_paused => {}
            _ => return,
        }
        self.advance_now(fix.uptime_s);

        let last = match self.last {
            Some(l) => l,
            None => {
                self.last = Some(*fix);
                self.current_speed_mps = fix.speed_mps.max(0.0);
                self.last_fix_stored = true;
                self.feed_gap(fix);
                return;
            }
        };

        let dt = fix.uptime_s.saturating_sub(last.uptime_s);
        let delta = segment_distance_m(&last, fix);

        // Corrupt fix: a shared/backwards timestamp, an implied speed past the
        // ceiling, or a jump too long to be real. Drop it and keep the anchor
        // so the next good fix measures from the last trusted position. The
        // jump ceiling is interval-aware — see `set_fix_interval_s`.
        let max_jump_m = if self.fix_interval_s > 1 {
            MAX_SPEED_MPS * dt as f64
        } else {
            MAX_JUMP_M
        };
        if dt == 0 || delta >= max_jump_m || delta / dt as f64 > MAX_SPEED_MPS {
            // Real GPS gap, not a teleport: the hop failed the one-hop cap but
            // a genuine interval elapsed (`run_recorder`'s #330 re-anchor,
            // `_gpsReanchorAfterSeconds`). Rebase the anchor to the fresh fix
            // WITHOUT crediting the un-sampled gap distance or its time —
            // exactly how the first fix of a run anchors. The rebased point is
            // stored so the flash track carries the reacquire position, and
            // the gap banks no moving time. Without this, a 1 Hz dropout that
            // displaced the runner past MAX_JUMP_M froze distance for the rest
            // of the run: the fixed cap never scales, so the stale anchor only
            // ever receded. 1 Hz only, mirroring the Dart recorder it ports —
            // a throttled mode needs no re-anchor because its `MAX_SPEED_MPS *
            // dt` ceiling grows faster than any real displacement, so a held
            // anchor self-heals on a later fix. A dt == 0 duplicate can never
            // reach here (dt >= the gate), so timestamp dupes stay
            // failed-closed.
            if self.fix_interval_s <= 1 && dt >= GPS_REANCHOR_AFTER_S {
                self.current_speed_mps = fix.speed_mps.max(0.0);
                self.last = Some(*fix);
                self.last_fix_stored = true;
                self.feed_gap(fix);
            }
            return;
        }
        self.current_speed_mps = fix.speed_mps.max(0.0);

        if delta <= TRACK_THRESHOLD_M {
            self.state = RecordState::Paused;
            return;
        }

        // Distance always accrues on an accepted segment; the segment's time
        // only counts as moving when its speed clears the moving gate — the
        // movingTimeOf rule, which auto-pauses a slow (stopped-but-drifting)
        // stretch out of moving time while still crediting the ground covered.
        self.distance_m += delta;
        // Pace-distribution: bank the segment's distance in the bucket for its
        // own speed — the Splits page's pace analogue of the HR-zone time.
        let bucket = pace_bucket_for_speed(delta / dt as f64, ActivityKind::Run);
        self.pace_bucket_m[bucket] += delta;
        if delta / dt as f64 >= MIN_MOVING_SPEED_MPS {
            self.moving_s += dt;
            // Zone time banks exactly where moving time does, into the zone of
            // the HR in force for the segment — no reading, no accrual. The
            // TRIMP average banks on the same rule, so both HR aggregates agree
            // on which seconds carried a pulse.
            if let Some(bpm) = self.hr_bpm {
                let zone = hr_zones::zone_for_bpm(bpm, &self.zone_cutoffs);
                self.zone_time_s[(zone - 1) as usize] += dt;
                self.hr_dt_bpm += u64::from(bpm) * u64::from(dt);
                self.hr_dt_s += dt;
            }
            self.state = RecordState::Recording;
        } else {
            self.state = RecordState::Paused;
        }
        self.last = Some(*fix);
        self.last_fix_stored = true;
        self.feed_gap(fix);
        // Distance only moves here, so this is the one place the partner's
        // finish crossing can happen.
        self.pacer.on_distance(self.distance_m, self.elapsed_s());
        self.feed_workout();

        self.check_auto_lap();
    }

    /// Close whatever laps the armed trigger has come due for. Both axes bank
    /// only on ground the recorder accepted as movement — distance structurally,
    /// moving time because that is the axis the budget is measured on — so a
    /// stationary runner can never close a lap here, however long they stand
    /// still (§ 374). This is the only place either axis advances, which is why
    /// it is also the only place the check has to run.
    ///
    /// **A backyard bell outranks the chosen trigger entirely** (§ 372 over
    /// § 374), on both axes and at every rung. The loop is the unit the format
    /// is scored in, so it has to be exactly one lap record; a 1 km rung spends
    /// six per 6.706 km loop and a 5 min rung twelve per hour, and on a 64-record
    /// budget either evicts the loop splits that ARE the result inside the first
    /// ten loops. The runner's choice is dormant, not cleared — it is a `CFG1`
    /// setting and disarming the bell restores it — which also makes `Off` and a
    /// time rung behave the same way here as a distance one, rather than each
    /// needing its own answer.
    ///
    /// A single accepted fix in a throttled GNSS mode can span several
    /// boundaries after a dropout, so each axis must close MORE than one lap —
    /// a bare `if` closed only ONE and merged the rest into one giant lap,
    /// silently corrupting the lap counter/index and every split from that point
    /// on. Every boundary but the last lands on the exact line (proportional
    /// slice of the open lap); the last close keeps the established
    /// single-boundary behaviour — the overshoot stays in the closed lap and the
    /// next lap opens at the closing fix's totals.
    fn check_auto_lap(&mut self) {
        if self.backyard.armed() {
            return;
        }
        if let Some(boundary) = self.auto_lap.distance_m() {
            while self.distance_m - self.lap_start_distance_m >= 2.0 * boundary {
                self.close_lap_at(self.lap_start_distance_m + boundary);
            }
            if self.distance_m - self.lap_start_distance_m >= boundary {
                self.close_lap();
            }
        }
        if let Some(budget) = self.auto_lap.moving_s() {
            while self.moving_s - self.lap_start_moving_s >= 2 * budget {
                self.close_lap_at_moving(self.lap_start_moving_s + budget);
            }
            if self.moving_s - self.lap_start_moving_s >= budget {
                self.close_lap();
            }
        }
    }

    /// The runner's local time of day, extrapolated from the receiver's last
    /// clock and shifted by the pushed timezone offset — `None` until both
    /// exist, which is what makes the Backyard page refuse a countdown rather
    /// than count down to the wrong hour.
    fn local_tod_s(&self) -> Option<u32> {
        let tz = self.tz_offset_min?;
        let (tod, at) = self.last_clock?;
        let aged = u64::from(tod) + u64::from(self.now_s.saturating_sub(at));
        Some(((aged as i64 + i64::from(tz) * 60).rem_euclid(86_400)) as u32)
    }

    /// Fold the wall clock into backyard mode and take the bell's lap when it
    /// asks for one. Called from the 1 Hz tick, which runs through both pause
    /// kinds for as long as a run is live — so no bell window can pass
    /// unobserved, which is the assumption the window detector rests on.
    fn fold_backyard(&mut self) {
        if !self.backyard.armed() {
            return;
        }
        let Some(tod) = self.local_tod_s() else {
            return;
        };
        if self.backyard.on_clock(tod) {
            self.close_lap();
            self.backyard.on_bell_lap(self.distance_m);
        }
    }

    /// Advance the altitude-fed surfaces with an anchor-adopting fix: the run
    /// total so far plus the baro-preferred altitude (falling back to the
    /// fix's GPS altitude, mirroring the flash store's point stamping). No
    /// altitude at all leaves them untouched, exactly like the Connect IQ
    /// field's `updateGrade` early-out — the live GAP grade, the elevation
    /// sparkline, and the §359 climb segmenter all read the same sample, so a
    /// hill cannot register on one page and not another.
    ///
    /// The GPS fallback narrows through [`crate::elevation::plausible_gps`],
    /// the same terrestrial window the vert filter already refuses to pull its
    /// bias toward. Without it the three surfaces here were the only consumers
    /// that trusted a receiver altitude no one else did — the flash track's
    /// point stamping bounds it too ([`crate::record_cadence::track_point`]) —
    /// and one out-of-band sample is not transient: the elevation profile thins
    /// by keeping even indices, so the sample it lands in survives every later
    /// thinning for the rest of the run.
    fn feed_gap(&mut self, fix: &Fix) {
        if let Some(alt) = self
            .baro_alt_m
            .or(crate::elevation::plausible_gps(fix.alt_m).map(f64::from))
        {
            self.gap.on_sample(self.distance_m, alt);
            self.elev_profile.push(self.distance_m, alt);
            self.climb.on_sample(self.distance_m, alt);
        }
    }

    /// Record the lap in progress as [`last_lap`](Snapshot::last_lap) and
    /// anchor the next one at the current totals. Shared by the auto-lap
    /// boundary and the manual [`lap`](Recorder::lap).
    fn close_lap(&mut self) {
        self.close_lap_at(self.distance_m);
    }

    /// Close the current lap at `close_distance_m` (`lap_start_distance_m <
    /// close_distance_m <= self.distance_m`), attributing a distance-
    /// proportional slice of the open lap's elapsed/moving time to it and
    /// re-anchoring the next lap there. Closing at the full `self.distance_m`
    /// (the manual-lap and single-boundary case) takes the whole open lap with
    /// no remainder — identical to the old body. Closing at an intermediate
    /// kilometre boundary is what lets a single throttled-mode fix that spans
    /// several boundaries after a GNSS dropout close one lap per boundary
    /// instead of merging them all into one giant lap (which silently corrupts
    /// the lap counter/index and every split thereafter).
    fn close_lap_at(&mut self, close_distance_m: f64) {
        let elapsed = self.elapsed_s();
        let lap_distance = close_distance_m - self.lap_start_distance_m;
        let open_distance = self.distance_m - self.lap_start_distance_m;
        let frac = if open_distance > 0.0 {
            (lap_distance / open_distance).clamp(0.0, 1.0)
        } else {
            1.0
        };
        let open_elapsed = elapsed.saturating_sub(self.lap_start_elapsed_s);
        let open_moving = self.moving_s - self.lap_start_moving_s;
        let lap_elapsed = libm::round(open_elapsed as f64 * frac) as u32;
        let lap_moving = libm::round(open_moving as f64 * frac) as u32;
        let closed = Lap {
            index: self.lap_index,
            distance_m: lap_distance,
            elapsed_s: lap_elapsed,
            moving_s: lap_moving,
        };
        self.last_lap = Some(closed);
        // Queue for flash persistence (v2 lap records). A full queue drops
        // the NEW close from storage only — display state above is already
        // set — and can only happen if the app stops draining between events.
        let _ = self.pending_laps.push_back(closed);
        self.lap_index = self.lap_index.saturating_add(1);
        self.lap_start_distance_m = close_distance_m;
        self.lap_start_elapsed_s = self.lap_start_elapsed_s.saturating_add(lap_elapsed);
        self.lap_start_moving_s = self.lap_start_moving_s.saturating_add(lap_moving);
    }

    /// [`close_lap_at`](Self::close_lap_at) with the axes swapped: close at
    /// `close_moving_s` seconds of moving time (`lap_start_moving_s <
    /// close_moving_s <= self.moving_s`), attributing a proportional slice of
    /// the open lap's distance and elapsed time and re-anchoring there.
    ///
    /// A near-twin of the distance close rather than a shared helper over a
    /// fraction, because each axis has to anchor EXACTLY on its own quantity:
    /// re-deriving the closing moving-second from a float fraction of the open
    /// lap would let the anchor drift a second per lap, and a 60-lap race would
    /// bank a minute of moving time that no lap contains.
    fn close_lap_at_moving(&mut self, close_moving_s: u32) {
        let lap_moving = close_moving_s.saturating_sub(self.lap_start_moving_s);
        let open_moving = self.moving_s - self.lap_start_moving_s;
        let frac = if open_moving > 0 {
            (f64::from(lap_moving) / f64::from(open_moving)).clamp(0.0, 1.0)
        } else {
            1.0
        };
        let open_elapsed = self.elapsed_s().saturating_sub(self.lap_start_elapsed_s);
        let open_distance = self.distance_m - self.lap_start_distance_m;
        let lap_elapsed = libm::round(open_elapsed as f64 * frac) as u32;
        let lap_distance = open_distance * frac;
        let closed = Lap {
            index: self.lap_index,
            distance_m: lap_distance,
            elapsed_s: lap_elapsed,
            moving_s: lap_moving,
        };
        self.last_lap = Some(closed);
        let _ = self.pending_laps.push_back(closed);
        self.lap_index = self.lap_index.saturating_add(1);
        self.lap_start_distance_m += lap_distance;
        self.lap_start_elapsed_s = self.lap_start_elapsed_s.saturating_add(lap_elapsed);
        self.lap_start_moving_s = close_moving_s;
    }

    fn elapsed_s(&self) -> u32 {
        self.now_s.saturating_sub(self.start_s)
    }

    /// Advance the wall clock, banking the delta as manually-paused time when
    /// it passes during a manual pause — the accounting behind
    /// [`workout_clock_s`](Recorder::workout_clock_s). Every mutator that used
    /// to write `now_s` directly routes through here so no advancement can
    /// slip past the bank.
    fn advance_now(&mut self, now_s: u32) {
        let now_s = now_s.max(self.now_s);
        if self.state == RecordState::Paused && self.manual_paused {
            self.manual_paused_s += now_s - self.now_s;
        }
        self.now_s = now_s;
    }

    /// The workout runner's time axis: elapsed minus manually-paused seconds —
    /// the phone recorder's stopwatch (halts on manual pause, runs through an
    /// auto-pause; see the `manual_paused_s` field).
    fn workout_clock_s(&self) -> u32 {
        self.elapsed_s().saturating_sub(self.manual_paused_s)
    }

    /// Feed the armed workout the live totals. Called wherever a run total
    /// moves (the tick's clock, an accepted fix's distance); inert with no
    /// workout armed.
    fn feed_workout(&mut self) {
        let (distance_m, clock_s) = (self.distance_m, self.workout_clock_s());
        if let Some(w) = self.workout.as_mut() {
            w.on_totals(distance_m, clock_s);
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let mut snap = Snapshot {
            state: self.state,
            // Gated on Paused because `stop()` doesn't clear the flag — a
            // Finished snapshot must not carry a stale manual-pause marker.
            manual_paused: self.state == RecordState::Paused && self.manual_paused,
            signal_lost: self.state == RecordState::Paused
                && !self.manual_paused
                && self.fix_stale(),
            distance_m: self.distance_m,
            elapsed_s: self.elapsed_s(),
            moving_s: self.moving_s,
            current_speed_mps: self.current_speed_mps,
            avg_pace_s_per_km: self.avg_pace(),
            current_pace_s_per_km: self.current_pace(),
            gap_s_per_km: self.gap.gap_s_per_km(self.current_speed_mps as f64),
            // After the sampling line above — struct literals evaluate in
            // source order, and the hold flag describes that call's answer.
            gap_held: self.gap.held(),
            lap: self.lap_index,
            lap_distance_m: self.distance_m - self.lap_start_distance_m,
            lap_elapsed_s: self.elapsed_s().saturating_sub(self.lap_start_elapsed_s),
            last_lap: self.last_lap,
            auto_lap: self.auto_lap,
            pacer: if self.state == RecordState::Idle {
                None
            } else {
                self.pacer.status(self.distance_m, self.elapsed_s())
            },
            zone_cutoffs: self.zone_cutoffs,
            zone_ceiling: self.zone_ceiling,
            pace_band: self.pace_band,
            zone_time_s: self.zone_time_s,
            cutoff: self.cutoff_snapshot(),
            sleep: self.sleep_snapshot(),
            race_prediction: self.race_prediction_snapshot(),
            pace_bucket_m: self.pace_bucket_m,
            training_stress: self.training_stress_snapshot().map(|(s, _)| s),
            training_stress_trimp: self
                .training_stress_snapshot()
                .is_some_and(|(_, trimp)| trimp),
            load_trend: self.load_trend,
            band: if self.state == RecordState::Idle {
                None
            } else {
                band_for_distance(self.distance_m)
            },
            gear: self.gear_snapshot(),
            roadbook: self.roadbook_snapshot(),
            fuel: self.fuel_snapshot(),
            training_paces: self.training_paces_snapshot(),
            fitness: self.fitness,
            elev_profile: self.elev_profile.view(),
            recap: self.recap,
            streaks: self.streaks,
            run_stats: self.run_stats,
            pr_recency: self.pr_recency,
            plan_replan: self.plan_replan,
            plan_adaptive: self.plan_adaptive,
            guided_run: self.guided_run_snapshot(),
            workout: self.workout.as_ref().map(|w| w.view()),
            readiness: self.readiness,
            goals: self.goals,
            turn_cue: self.turn_cue,
            nav_off_course: self.nav_off_course,
            route_simplify: self.route_simplify,
            auto_effort: self.auto_effort,
            route_elev: self.route_elev,
            route_position_permille: self.route_position_permille(),
            race_day: self.race_day,
            race_phase: self.race_phase_snapshot(),
            storm: self.storm,
            climb: self.climb_snapshot(),
            backyard: self.backyard.armed().then(|| {
                self.backyard
                    .view(self.distance_m, self.current_pace(), self.now_s)
            }),
            waypoint: self
                .last
                .and_then(|f| self.waypoints.view(f.lat_deg, f.lon_deg)),
            waypoint_count: self.waypoints.len() as u8,
            waypoint_mark_seq: self.waypoint_mark_seq,
            waypoint_refuse_seq: self.waypoint_refuse_seq,
            timer: self.timer,
            track_thinning: self.track_thinning,
            pages_mask: 0,
            hide_empty_pages: self.hide_empty_pages,
        };
        snap.pages_mask = self.pages_mask(&snap);
        snap
    }

    /// The effective BTN3 cycle for this snapshot: the pages whose data is
    /// present (unless [`hide_empty_pages`](Recorder::set_hide_empty_pages)
    /// is off), intersected with the runner's curated set, Dashboard always
    /// included. [`Page::next_in`] / [`Page::prev_in`] walk exactly this
    /// mask, and the page-position indicator counts it — so the dot row says
    /// how many pages the cycle actually has right now.
    fn pages_mask(&self, s: &Snapshot) -> u64 {
        let available = if self.hide_empty_pages {
            self.available_pages(s)
        } else {
            u64::MAX
        };
        (available & self.pages_enabled) | Page::Dashboard.bit()
    }

    /// Which pages have something real to show for this snapshot. The core
    /// run pages (Dashboard / Distance / Pace / Lap / Splits) and the
    /// Back-to-start safety page are always available; every other page is
    /// available exactly when the data behind its honest empty state exists —
    /// the same conditions the `face` renderers key their inactive states on.
    fn available_pages(&self, s: &Snapshot) -> u64 {
        let mut m = Page::Dashboard.bit()
            | Page::Distance.bit()
            | Page::Pace.bit()
            | Page::Lap.bit()
            | Page::Splits.bit()
            | Page::BackToStart.bit();
        let mut set = |page: Page, on: bool| {
            if on {
                m |= page.bit();
            }
        };
        // Zone time banks only while an HR reading is live, so any banked
        // second means the sensor is (or was) on this run.
        set(Page::Zones, s.zone_time_s.iter().any(|&t| t > 0));
        set(Page::Pacer, s.pacer.is_some());
        set(Page::RacePredictor, s.race_prediction.is_some());
        set(Page::TrainingLoad, s.training_stress.is_some());
        set(Page::DistanceBand, s.band.is_some());
        set(Page::CutoffEta, s.cutoff.is_some());
        set(Page::SleepStation, s.sleep.is_some());
        set(Page::Roadbook, s.roadbook.is_some());
        set(Page::Fuel, s.fuel.is_some());
        set(Page::Nav, self.course_loaded);
        set(Page::GearWear, s.gear.is_some());
        set(Page::TrainingPaces, s.training_paces.is_some());
        set(Page::Fitness, s.fitness.is_some());
        set(Page::ElevationProfile, s.elev_profile.len > 0);
        set(Page::Recap, s.recap.is_some());
        set(Page::Streaks, s.streaks.is_some());
        set(Page::RunStats, s.run_stats.is_some());
        set(Page::PrRecency, s.pr_recency.is_some());
        set(Page::PlanReplan, s.plan_replan.is_some());
        set(Page::PlanAdaptive, s.plan_adaptive.is_some());
        set(Page::GuidedRun, s.guided_run.is_some());
        set(Page::Workout, s.workout.is_some());
        set(Page::Readiness, s.readiness.is_some());
        set(Page::Goals, s.goals.is_some());
        set(Page::TurnCue, s.turn_cue.is_some());
        set(Page::RouteSimplify, s.route_simplify.is_some());
        set(Page::AutoEffort, s.auto_effort.is_some());
        set(Page::RouteElev, s.route_elev.is_some());
        set(Page::RaceDay, s.race_day.is_some());
        set(Page::Daylight, self.tz_offset_min.is_some());
        // Keyed on the STORE, not on a live view: a marked stash is worth
        // navigating back to even while the GPS is still reacquiring, so the
        // page must not vanish from the cycle the moment the fix does.
        set(Page::Waypoint, s.waypoint_count > 0);
        set(Page::Climb, !s.climb.is_empty());
        // Keyed on the watch being able to state a reduced pressure at all —
        // which covers `Building`, where the absolute figure is already real
        // and only its tendency is withheld. A barometer that never answered
        // and a reference-less one both drop the page rather than seating a
        // permanent refusal in a cycle whose whole point is that it is short.
        set(
            Page::Storm,
            s.storm.is_some_and(|v| v.sea_level_hpa.is_some()),
        );
        // Keyed on the instrument being ARMED, not merely configured: a preset
        // dialled and abandoned in the modal is not a page, and a reset gives
        // the seat back.
        set(Page::Timer, s.timer.is_some());
        // Armed, not fed: an armed watch that cannot yet read a clock must
        // still carry the page, because `NOT SYNCED` on it is the only place a
        // runner learns the countdown needs a timezone push.
        set(Page::Backyard, s.backyard.is_some());
        // A composed screen is available when the runner has actually composed
        // it. Keyed on the COUNT rather than on any metric being fed, because a
        // screen the runner built is a page they asked for — its slots saying
        // `SYNC` is an answer, not an absence, and hiding it would silently
        // overrule the composition.
        for i in 0..self.screen_count {
            if let Some(p) = Page::of_screen_index(i) {
                m |= p.bit();
            }
        }
        m
    }

    /// The Climb page's view: the ascent the detector has open, plus the crest
    /// the pushed course profile puts ahead of the runner's along-course
    /// position. The crest half is derived per snapshot rather than banked, so
    /// it shrinks with every fix instead of at sync time — and it needs no new
    /// input: the distance-even profile the RouteElev page already carries is
    /// exactly the series to search.
    ///
    /// It takes the same staleness gate as the profile marker and the cutoff
    /// ETA: a position frozen by a lost signal would keep reporting the crest
    /// from where the runner *was*, so the metres-remaining would stop falling
    /// while they climbed — the one number on the page a runner would act on,
    /// stuck. The live half is unaffected, since it is fed by the fixes
    /// themselves and simply stops advancing when they do.
    fn climb_snapshot(&self) -> ClimbView {
        ClimbView {
            active: self.climb.active(),
            ahead: self.route_elev.as_ref().and_then(|e| {
                if self.route_position_stale() {
                    return None;
                }
                crest_ahead(
                    &e.samples[..e.len],
                    f64::from(e.total_m),
                    self.route_along_m?,
                )
            }),
        }
    }

    /// Where the run has reached in the armed guided run, or `None` when none is
    /// armed. Derived, not stored: the cue the elapsed time has passed comes from
    /// the ported `(prev, now]` dispatcher run from before the start
    /// ([`cues_due`]), so the page needs no per-tick state and survives a reboot
    /// mid-run. Elapsed reads 0 while idle, so an armed run shows its full
    /// duration rather than the previous run's tail.
    fn guided_run_snapshot(&self) -> Option<GuidedRunView> {
        let g = self.guided?;
        let elapsed_s = if self.state == RecordState::Idle {
            0
        } else {
            self.elapsed_s()
        };
        let elapsed = f64::from(elapsed_s);
        let cue_index = cues_due(g, -1.0, elapsed).len();
        Some(GuidedRunView {
            cue_index: cue_index as u8,
            cue_count: g.cues.len() as u8,
            // The cues are sorted ascending, so the first one not yet passed is
            // the one at the passed count.
            next_cue_in_s: g
                .cues
                .get(cue_index)
                .map(|c| (c.at_sec - elapsed).max(0.0) as u32),
            duration_s: g.duration_sec as u32,
            remaining_s: (g.duration_sec - elapsed).max(0.0) as u32,
        })
    }

    /// The training-pace zones derived from the synced goal-race pace, or `None`
    /// until one is synced. Gender-neutral (base Daniels curve) — the watch has
    /// no gender-sync hook, and the base curve is the honest default (no
    /// unvalidated calibration). Not gated on run state: the paces are a plan
    /// reference, meaningful the moment a goal is synced.
    fn training_paces_snapshot(&self) -> Option<TrainingPacesView> {
        let goal = self.training_goal_pace_s_per_km?;
        Some(TrainingPacesView {
            goal_pace_s_per_km: goal as u32,
            paces: paces_from_goal_pace(goal, TrainingGender::None),
        })
    }

    /// The pacing-strategy phase the live distance falls in, or `None` until a
    /// plan is pushed. Not gated on run state: at distance 0 the runner is in the
    /// plan's opening phase, which is the honest answer both before and at the
    /// gun.
    fn race_phase_snapshot(&self) -> Option<RacePhaseView> {
        let index = phase_at(&self.race_phases, self.distance_m);
        if index < 0 {
            return None;
        }
        let phase = &self.race_phases[index as usize];
        Some(RacePhaseView {
            index: index as u8 + 1,
            total: self.race_phases.len() as u8,
            intent: phase.intent,
            target_pace_s_per_km: phase_target_pace_s_per_km(
                phase,
                self.race_phase_goal_pace_s_per_km,
            )
            .map(|p| p as u32),
        })
    }

    /// This run's single-run training-load stress plus whether the TRIMP model
    /// scored it, or `None` while idle / before any distance. Distance-model
    /// until the settings sync delivers the resting + max HR pair AND the run
    /// has banked a live HR average — then Banister TRIMP, the same
    /// [`compute_stress`] ladder the web/Dart helpers run.
    fn training_stress_snapshot(&self) -> Option<(f32, bool)> {
        if self.state == RecordState::Idle || self.distance_m < 1.0 {
            return None;
        }
        let avg_bpm = (self.hr_dt_s > 0).then(|| self.hr_dt_bpm as f64 / f64::from(self.hr_dt_s));
        let prefs = HrPrefs {
            resting_hr_bpm: self.resting_hr_bpm.map(f64::from),
            max_hr_bpm: self.max_hr_bpm.map(f64::from),
        };
        let run = RunForLoad {
            day: 0,
            duration_s: self.moving_s,
            distance_m: self.distance_m,
            avg_bpm,
        };
        let trimp =
            compute_calibration(core::slice::from_ref(&run), &prefs).mode == StressMode::Trimp;
        Some((compute_stress(&run, &prefs, None) as f32, trimp))
    }

    /// The active gear's wear verdict with this run's distance folded into the
    /// baseline, or `None` when no gear baseline is synced.
    fn gear_snapshot(&self) -> Option<GearWear> {
        let base = self.gear_base_m?;
        Some(gear_wear(Some(base + self.distance_m), self.gear_target_m))
    }

    /// The upcoming-checkpoint window from the current route position. `None`
    /// with no roadbook loaded or while idle.
    fn roadbook_snapshot(&self) -> Option<RoadbookView> {
        if self.state == RecordState::Idle || self.roadbook_legs.is_empty() {
            return None;
        }
        let pos = self.route_along_m.unwrap_or(0.0);
        let mut upcoming = [RoadbookLegView::default(); ROADBOOK_WINDOW];
        let mut len = 0;
        for leg in self.roadbook_legs.iter() {
            if leg.cum_dist_m < pos {
                continue;
            }
            if len >= ROADBOOK_WINDOW {
                break;
            }
            upcoming[len] = RoadbookLegView {
                cum_dist_m: leg.cum_dist_m as f32,
                projected_elapsed_s: leg.projected_elapsed_s,
                cutoff: leg.cutoff,
            };
            len += 1;
        }
        Some(RoadbookView {
            total: self.roadbook_legs.len() as u8,
            upcoming,
            upcoming_len: len as u8,
        })
    }

    /// The fuelling headline over the loaded roadbook — the carry out of the
    /// last aid at/behind the current position plus the whole-plan totals,
    /// scaled by [`crate::fuel_plan`]. `None` without a roadbook or while idle.
    fn fuel_snapshot(&self) -> Option<FuelView> {
        if self.state == RecordState::Idle || self.roadbook_legs.is_empty() {
            return None;
        }
        // Reconstruct the aid services from the pushed refill flag; static
        // slices satisfy `FuelLegInput`'s borrow without owning storage.
        const REFILL: &[&str] = &["water"];
        const DRY: &[&str] = &[];
        let mut inputs: heapless::Vec<FuelLegInput, MAX_PUSHED_LEGS> = heapless::Vec::new();
        for leg in self.roadbook_legs.iter() {
            let _ = inputs.push(FuelLegInput {
                projected_elapsed_s: leg.projected_elapsed_s as f64,
                leg_dist_m: leg.leg_dist_m,
                services: if leg.is_refill { REFILL } else { DRY },
            });
        }
        // The pushed cadences invert through the same units the alert engine's
        // forward reduction used (one gel, one sip), so the page and the
        // reminders describe one plan. A desert runner who tightened their
        // drink cadence over SET1 sees the carry-out grow to match; unpushed,
        // the temperate defaults stand.
        let carbs_per_hour_g = self
            .fuel_eat_interval_s
            .map(|s| GEL_CARBS_G * 3600.0 / f64::from(s))
            .unwrap_or(DEFAULT_CARBS_PER_HOUR_G);
        let fluid_per_hour_ml = self
            .fuel_drink_interval_s
            .map(|s| SIP_FLUID_ML * 3600.0 / f64::from(s))
            .unwrap_or(DEFAULT_FLUID_PER_HOUR_ML);
        let plan = build_fuel_plan(
            &inputs,
            FuelPlanOptions {
                carbs_per_hour_g,
                fluid_per_hour_ml,
                heat_factor: None,
                gel_carbs_g: None,
                weight_kg: None,
            },
        );
        let carry_view = |c: crate::fuel_plan::FuelCarry| FuelCarryView {
            carbs_g: c.carbs_g as f32,
            fluid_ml: c.fluid_ml as f32,
        };
        // The carry set at the last aid at/behind us is what we're carrying now;
        // before the first aid, the start's carry.
        let pos = self.route_along_m.unwrap_or(0.0);
        let mut carry = None;
        for (i, leg) in self.roadbook_legs.iter().enumerate() {
            if leg.cum_dist_m > pos {
                break;
            }
            if let Some(c) = plan.legs.get(i).and_then(|l| l.carry_to_next_aid) {
                carry = Some(carry_view(c));
            }
        }
        if carry.is_none() {
            carry = plan
                .legs
                .first()
                .and_then(|l| l.carry_to_next_aid)
                .map(carry_view);
        }
        Some(FuelView {
            carry,
            total_carbs_g: plan.total_carbs_g as f32,
            total_fluid_ml: plan.total_fluid_ml as f32,
        })
    }

    /// Is the fed along-course position too old to speak for where the runner
    /// is now? Stale once it ages past [`fix_stale_budget_s`](Recorder::fix_stale_budget_s),
    /// and a position that never arrived counts as stale.
    fn route_position_stale(&self) -> bool {
        self.route_along_m.is_none()
            || self.now_s.saturating_sub(self.route_along_at_s) > self.fix_stale_budget_s()
    }

    /// How long a fix may go unrefreshed before it stops speaking for now.
    /// Scaled to the GNSS mode's cadence so Expedition's 60 s gaps are not
    /// "stale", floored so a 1 Hz mode tolerates a few dropped sentences.
    /// Shared by the along-course staleness gate and the lost-signal
    /// auto-pause: the two must agree, or the run view would claim to be
    /// tracking a runner whose course position it has already disowned.
    fn fix_stale_budget_s(&self) -> u32 {
        self.fix_interval_s.saturating_mul(3).max(10)
    }

    /// Have the fixes dried up? The one predicate behind both the lost-signal
    /// auto-pause in [`tick`](Recorder::tick) and the [`Snapshot::signal_lost`]
    /// the face labels it from, so the state and its explanation cannot
    /// disagree. A run that has never had a fix is not a dropout.
    fn fix_stale(&self) -> bool {
        self.last
            .is_some_and(|l| self.now_s.saturating_sub(l.uptime_s) > self.fix_stale_budget_s())
    }

    /// The profile marker's along-course position, withheld while the fed
    /// position is missing or stale — the same rule the cut-off ETA follows, so
    /// a lost-signal runner's marker disappears instead of lying about where
    /// they are.
    fn route_position_permille(&self) -> Option<u16> {
        if self.route_position_stale() {
            return None;
        }
        crate::course_profile::position_permille(
            self.route_along_m?,
            self.route_elev.as_ref()?.total_m,
        )
    }

    /// The live next-cutoff ETA, or `None` when idle or no cutoff legs are
    /// loaded. Projects from the fed route position + the whole-run moving pace;
    /// a missing or stale route position (lost signal) drops the projected time
    /// to `Unknown` — see [`crate::cutoff_eta`].
    fn cutoff_snapshot(&self) -> Option<CutoffEta> {
        if self.state == RecordState::Idle || self.cutoff_legs.is_empty() {
            return None;
        }
        let stale = self.route_position_stale();
        Some(next_cutoff_eta(
            self.route_along_m.unwrap_or(0.0),
            self.elapsed_s(),
            self.avg_pace().map(f64::from),
            stale,
            &self.cutoff_legs,
        ))
    }

    /// The sleep-station nap budget, on the same gate as the cut-off ETA — the
    /// two answer one question from one projection, so a course whose cut-offs
    /// feed one must feed the other.
    ///
    /// Both paces are handed over rather than picked here: `avg_pace` is the
    /// run's MOVING pace, which the cut-off page projects from, and the race
    /// pace below divides by the elapsed clock so every aid-station stop the
    /// runner has already taken is priced in. [`sleep_budget`] takes the slower.
    fn sleep_snapshot(&self) -> Option<SleepBudget> {
        if self.state == RecordState::Idle || self.cutoff_legs.is_empty() {
            return None;
        }
        Some(sleep_budget(
            self.route_along_m.unwrap_or(0.0),
            self.elapsed_s(),
            self.avg_pace().map(f64::from),
            self.race_pace(),
            self.route_position_stale(),
            &self.cutoff_legs,
        ))
    }

    /// The live race-time ladder, projecting the current run as a single effort
    /// (age 0). `None` until the run clears [`MIN_PREDICT_DISTANCE_M`]; below
    /// that a Riegel projection is noise. `predict_race_ladder` returns `None`
    /// itself when the effort doesn't qualify (no moving time yet).
    fn race_prediction_snapshot(&self) -> Option<RacePrediction> {
        if self.state == RecordState::Idle || self.distance_m < MIN_PREDICT_DISTANCE_M {
            return None;
        }
        predict_race_ladder(&[Effort {
            distance_m: self.distance_m,
            duration_s: self.moving_s,
            age_days: 0.0,
        }])
    }

    fn avg_pace(&self) -> Option<u32> {
        if self.moving_s == 0 || self.distance_m < 1.0 {
            return None;
        }
        Some((self.moving_s as f64 * 1000.0 / self.distance_m) as u32)
    }

    /// Whole-run pace against the RACE clock rather than the moving one — every
    /// stop so far divided back into it, so it is never faster than
    /// [`Recorder::avg_pace`] and is the honest input to a projection a runner
    /// will make more stops during.
    fn race_pace(&self) -> Option<f64> {
        let elapsed = self.elapsed_s();
        if elapsed == 0 || self.distance_m < 1.0 {
            return None;
        }
        Some(f64::from(elapsed) * 1000.0 / self.distance_m)
    }

    fn current_pace(&self) -> Option<u32> {
        if self.current_speed_mps <= 0.1 {
            return None;
        }
        Some((1000.0 / self.current_speed_mps as f64) as u32)
    }
}

/// Equirectangular ground distance between two fixes, in metres. Longitude is
/// scaled by the cosine of the first fix's latitude, matching the Dart
/// recorder's segment-distance projection.
fn segment_distance_m(a: &Fix, b: &Fix) -> f64 {
    let m_per_deg_lon = METRES_PER_DEGREE_LAT * cos(to_rad(a.lat_deg));
    let dy = (b.lat_deg - a.lat_deg) * METRES_PER_DEGREE_LAT;
    let dx = (b.lon_deg - a.lon_deg) * m_per_deg_lon;
    sqrt(dx * dx + dy * dy)
}

fn to_rad(deg: f64) -> f64 {
    deg * core::f64::consts::PI / 180.0
}

/// Newton–Raphson square root — `core` has no `f64::sqrt` without a math dep.
fn sqrt(x: f64) -> f64 {
    if x <= 0.0 || x.is_nan() {
        return 0.0;
    }
    let mut g = x;
    let mut i = 0;
    while i < 32 {
        let next = 0.5 * (g + x / g);
        if fabs(next - g) <= 1e-12 * next {
            return next;
        }
        g = next;
        i += 1;
    }
    g
}

/// Cosine via the even Taylor series to x^12. The argument is a latitude in
/// radians (|x| <= pi/2), where this holds to ~1e-4 at the poles and far
/// tighter at running latitudes — sub-millimetre once scaled by a per-fix
/// longitude delta.
fn cos(x: f64) -> f64 {
    let x2 = x * x;
    let mut term = 1.0;
    let mut sum = 1.0;
    let mut n = 1;
    while n <= 6 {
        term *= -x2 / (((2 * n - 1) * (2 * n)) as f64);
        sum += term;
        n += 1;
    }
    sum
}

fn fabs(x: f64) -> f64 {
    if x < 0.0 {
        -x
    } else {
        x
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fix(lat: f64, lon: f64, speed: f32, t: u32) -> Fix {
        Fix {
            lat_deg: lat,
            lon_deg: lon,
            speed_mps: speed,
            course_deg: None,
            sats: 8,
            alt_m: None,
            time_of_day: None,
            date: None,
            uptime_s: t,
        }
    }

    fn fix_alt(lat: f64, lon: f64, speed: f32, t: u32, alt_m: f32) -> Fix {
        Fix {
            alt_m: Some(alt_m),
            ..fix(lat, lon, speed, t)
        }
    }

    // Ground truth computed with std's trig, using the same projection the
    // module ships — validates the hand-rolled sqrt/cos, not just the formula.
    fn expected_m(a: (f64, f64), b: (f64, f64)) -> f64 {
        let m_lon = 111_320.0 * a.0.to_radians().cos();
        let dy = (b.0 - a.0) * 111_320.0;
        let dx = (b.1 - a.1) * m_lon;
        (dx * dx + dy * dy).sqrt()
    }

    #[test]
    fn transitions_are_legal_and_illegal_ones_inert() {
        let mut r = Recorder::new();
        assert_eq!(r.state(), RecordState::Idle);

        // Nothing is legal from Idle except start.
        r.pause(1);
        r.resume(1);
        r.stop(1);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        assert_eq!(r.state(), RecordState::Idle);
        assert_eq!(r.snapshot().distance_m, 0.0);

        r.start(0);
        assert_eq!(r.state(), RecordState::Recording);
        r.tick(10);
        // A second start is inert — the clock keeps its original anchor.
        r.start(3);
        assert_eq!(r.snapshot().elapsed_s, 10);

        // Resume while recording is inert; pause then double-pause is idempotent.
        r.resume(10);
        assert_eq!(r.state(), RecordState::Recording);
        r.pause(11);
        assert_eq!(r.state(), RecordState::Paused);
        r.pause(12);
        assert_eq!(r.state(), RecordState::Paused);
        r.resume(13);
        assert_eq!(r.state(), RecordState::Recording);

        r.stop(20);
        assert_eq!(r.state(), RecordState::Finished);
        // Everything is inert after finish.
        r.resume(21);
        r.pause(21);
        r.start(21);
        assert_eq!(r.state(), RecordState::Finished);
    }

    #[test]
    fn distance_accumulates_to_ground_truth() {
        let mut r = Recorder::new();
        r.start(0);
        let pts = [
            (40.0, -105.0),
            (40.00004, -105.00002),
            (40.00008, -105.00004),
            (40.00012, -105.00006),
            (40.00016, -105.00008),
            (40.00020, -105.00010),
        ];
        let mut expected = 0.0;
        for w in pts.windows(2) {
            expected += expected_m(w[0], w[1]);
        }
        for (i, p) in pts.iter().enumerate() {
            r.on_fix(&fix(p.0, p.1, 5.0, i as u32));
        }
        let s = r.snapshot();
        assert!(
            fabs(s.distance_m - expected) < 1e-3,
            "distance {} vs expected {}",
            s.distance_m,
            expected
        );
        // Every 1 s segment cleared the moving gate.
        assert_eq!(s.moving_s, (pts.len() - 1) as u32);
        assert_eq!(s.elapsed_s, (pts.len() - 1) as u32);
        assert!(s.avg_pace_s_per_km.is_some());
    }

    #[test]
    fn implausible_fixes_are_rejected() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 0));

        // ~130 m in 1 s: over the speed ceiling and the jump ceiling.
        r.on_fix(&fix(40.001, -105.001, 3.0, 1));
        assert_eq!(r.snapshot().distance_m, 0.0);

        // Shared timestamp (dt == 0): undefined speed, rejected.
        r.on_fix(&fix(40.00005, -105.0, 3.0, 0));
        assert_eq!(r.snapshot().distance_m, 0.0);

        // A good fix still measures from the original anchor.
        r.on_fix(&fix(40.00005, -105.0, 4.0, 2));
        let d = r.snapshot().distance_m;
        assert!((d - expected_m((40.0, -105.0), (40.00005, -105.0))).abs() < 1e-3);
    }

    #[test]
    fn throttled_interval_accepts_legitimate_minute_apart_segments() {
        // Expedition mode: one fix per 60 s. A runner at ~4 m/s covers ~240 m
        // per segment — far past the 1 Hz MAX_JUMP_M ceiling, entirely real.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        let pts = [
            (40.0, -105.0),
            (40.00216, -105.0), // ~240 m north
            (40.00432, -105.0),
            (40.00648, -105.0),
        ];
        let mut expected = 0.0;
        for w in pts.windows(2) {
            expected += expected_m(w[0], w[1]);
        }
        for (i, p) in pts.iter().enumerate() {
            r.on_fix(&fix(p.0, p.1, 4.0, i as u32 * 60));
        }
        let s = r.snapshot();
        assert!(
            fabs(s.distance_m - expected) < 1e-3,
            "distance {} vs expected {}",
            s.distance_m,
            expected
        );
        assert_eq!(s.moving_s, 180, "each 60 s segment clears the moving gate");
        assert_eq!(s.state, RecordState::Recording);
    }

    #[test]
    fn throttled_interval_still_rejects_implausible_speed() {
        // The physical plausibility bound survives the throttle: ~700 m in
        // 60 s implies ~11.7 m/s, past MAX_SPEED_MPS — corrupt, dropped, and
        // the anchor kept for the next fix to measure from.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        r.on_fix(&fix(40.0063, -105.0, 4.0, 60));
        assert_eq!(r.snapshot().distance_m, 0.0);
        // A missed forwarding (dt = 2 intervals) scales the allowance with the
        // actual gap: ~480 m over 120 s is 4 m/s, accepted.
        r.on_fix(&fix(40.00432, -105.0, 4.0, 120));
        let d = r.snapshot().distance_m;
        assert!((d - expected_m((40.0, -105.0), (40.00432, -105.0))).abs() < 1e-3);
    }

    #[test]
    fn full_rate_filter_is_not_loosened_by_the_interval_hook() {
        // At the default 1 s cadence the fixed 100 m ceiling still applies
        // even when a signal gap makes the implied speed plausible: a 150 m
        // hop after 30 s dark is corrupt at 1 Hz, exactly as before the hook.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        r.on_fix(&fix(40.00135, -105.0, 4.0, 30));
        assert_eq!(r.snapshot().distance_m, 0.0);
        // An explicit interval of 1 (Performance) is the same filter, and a
        // zero interval clamps to 1 rather than dividing the gate away.
        r.set_fix_interval_s(1);
        r.on_fix(&fix(40.0027, -105.0, 4.0, 60));
        assert_eq!(r.snapshot().distance_m, 0.0);
        r.set_fix_interval_s(0);
        r.on_fix(&fix(40.00405, -105.0, 4.0, 90));
        assert_eq!(r.snapshot().distance_m, 0.0);
    }

    #[test]
    fn throttled_auto_lap_still_closes_once_per_boundary() {
        // ~240 m segments at 60 s: the fifth segment carries the lap past
        // 1 km; the overshoot stays in the closed lap and the next lap opens
        // at the closing fix.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        for i in 0..=5u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00216, -105.0, 4.0, i * 60));
            if i < 5 {
                assert_eq!(r.snapshot().lap, 1, "no lap before the boundary (i={})", i);
            }
        }
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        let last = s.last_lap.unwrap();
        assert_eq!(last.index, 1);
        assert!(last.distance_m >= AUTO_LAP_DISTANCE_M);
        assert_eq!(s.lap_distance_m, 0.0);
    }

    #[test]
    fn throttled_auto_lap_closes_one_lap_per_boundary_in_a_single_fix() {
        // Expedition mode (60 s fixes) after a ~5 min GNSS dropout: a single
        // accepted fix carries the lap ~2.5 km at once, spanning TWO kilometre
        // boundaries. Regression guard for the merge bug — a bare `if` closed
        // only one lap, leaving a 2.5 km "lap" and a permanently-off counter.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        // ~2.5 km north in one 300 s gap (5 missed 60 s fixes): ~8.3 m/s, under
        // the 10 m/s ceiling × 300 s, so the interval jump gate accepts it.
        r.on_fix(&fix(40.0 + 0.0225, -105.0, 4.0, 300));
        let s = r.snapshot();
        // Two boundaries crossed → two laps closed → now on lap 3, instead of
        // the pre-fix behaviour of a single merged ~2.5 km lap (lap == 2).
        assert_eq!(s.lap, 3, "a 2.5 km single-fix jump must close two laps");
        // The first (intermediate) close landed on the exact kilometre line;
        // the last close absorbed the overshoot, keeping the established model
        // (overshoot in the closed lap, open lap reset to 0).
        let last = s.last_lap.unwrap();
        assert_eq!(last.index, 2);
        assert!(last.distance_m >= AUTO_LAP_DISTANCE_M);
        assert_eq!(s.lap_distance_m, 0.0);
        assert!((s.distance_m - 2500.0).abs() < 60.0);
    }

    /// Metres north of 40.0, in degrees — the fixtures below are all straight
    /// northbound legs, so a distance is easier to read than a latitude.
    fn north(metres: f64) -> f64 {
        40.0 + metres / METRES_PER_DEGREE_LAT
    }

    #[test]
    fn a_fresh_recorder_reports_the_kilometre_default() {
        let r = Recorder::new();
        assert_eq!(r.snapshot().auto_lap, AutoLap::Km1);
    }

    #[test]
    fn auto_lap_off_closes_nothing_but_the_lap_press_still_does() {
        // The rung an ultra runner picks to spend the 64-record store on their
        // own splits: no boundary fires, the button still works.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Off);
        r.set_fix_interval_s(60);
        r.start(0);
        for i in 0..=30u32 {
            r.on_fix(&fix(north(f64::from(i) * 100.0), -105.0, 4.0, i * 25));
        }
        let s = r.snapshot();
        assert!(s.distance_m > 2900.0);
        assert_eq!(s.lap, 1, "an off trigger must close no lap");
        assert!(s.last_lap.is_none());
        r.lap(800);
        assert_eq!(r.snapshot().lap, 2);
    }

    #[test]
    fn the_mile_trigger_closes_on_the_mile_not_the_kilometre() {
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Mi1);
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(north(0.0), -105.0, 4.0, 0));
        r.on_fix(&fix(north(1200.0), -105.0, 4.0, 300));
        assert_eq!(r.snapshot().lap, 1, "past a km is not past a mile");
        r.on_fix(&fix(north(1700.0), -105.0, 4.0, 425));
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        assert!(s.last_lap.unwrap().distance_m >= 1609.344);
    }

    #[test]
    fn a_time_trigger_closes_on_moving_time() {
        // 1 m/s northbound: 300 s of moving time arrives long before any
        // distance rung would have fired, so the close can only be the clock.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Min5);
        r.set_fix_interval_s(60);
        r.start(0);
        for i in 0..=5u32 {
            r.on_fix(&fix(north(f64::from(i) * 60.0), -105.0, 1.0, i * 60));
        }
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        let last = s.last_lap.unwrap();
        assert_eq!(last.moving_s, 300);
        assert!(last.distance_m < 400.0, "well short of any distance rung");
    }

    #[test]
    fn a_throttled_time_lap_closes_one_lap_per_boundary_in_a_single_fix() {
        // The time axis needs the multi-close the distance axis needed: one
        // accepted fix after a long dropout can bank several budgets at once,
        // and a bare `if` would merge them into one giant lap.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Min5);
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(north(0.0), -105.0, 1.0, 0));
        // 700 m over 700 s = 1 m/s: clears the moving gate, inside the
        // interval-scaled jump ceiling, and banks 700 s against a 300 s budget.
        r.on_fix(&fix(north(700.0), -105.0, 1.0, 700));
        let s = r.snapshot();
        assert_eq!(s.lap, 3, "700 s against a 300 s budget must close two laps");
        // The intermediate close landed exactly on the boundary; the last one
        // absorbed the overshoot, mirroring the distance axis.
        assert_eq!(s.last_lap.unwrap().moving_s, 400);
        assert_eq!(r.pop_closed_lap().unwrap().moving_s, 300);
        assert_eq!(r.pop_closed_lap().unwrap().moving_s, 400);
        assert!(r.pop_closed_lap().is_none());
    }

    #[test]
    fn a_stationary_runner_closes_no_lap_on_either_axis() {
        // The failure this design exists to make impossible: an auto-lap that
        // banked on the ELAPSED clock would turn a long aid-station stop into a
        // stream of empty laps, and on the 64-record flash budget those empty
        // laps displace real ones. Distance cannot accrue below the acceptance
        // filter and moving time cannot accrue below the moving gate, so an
        // hour of standing still closes nothing on either rung.
        for trigger in [AutoLap::Km1, AutoLap::Min5] {
            let mut r = Recorder::new();
            r.set_auto_lap(trigger);
            r.start(0);
            r.on_fix(&fix(north(0.0), -105.0, 4.0, 0));
            for t in 1..=3600u32 {
                // Sub-metre jitter around one spot, plus the 1 Hz clock tick.
                r.on_fix(&fix(
                    north(if t % 2 == 0 { 0.0 } else { 0.5 }),
                    -105.0,
                    0.0,
                    t,
                ));
                r.tick(t);
            }
            let s = r.snapshot();
            assert_eq!(s.elapsed_s, 3600, "the wall clock still ran ({trigger:?})");
            assert_eq!(
                s.moving_s, 0,
                "nothing cleared the moving gate ({trigger:?})"
            );
            assert_eq!(s.lap, 1, "{trigger:?} closed a lap while standing still");
            assert!(s.last_lap.is_none());
            assert!(r.pop_closed_lap().is_none());
        }
    }

    #[test]
    fn a_manual_pause_banks_nothing_toward_a_time_lap() {
        // A manual pause gates fixes out entirely, so the only clock that runs
        // is elapsed — which the time trigger deliberately does not read.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Min5);
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(north(0.0), -105.0, 1.0, 0));
        r.on_fix(&fix(north(120.0), -105.0, 1.0, 120));
        r.pause(120);
        for t in 121..=1200u32 {
            r.tick(t);
        }
        let s = r.snapshot();
        assert_eq!(s.elapsed_s, 1200);
        assert_eq!(s.moving_s, 120);
        assert_eq!(s.lap, 1, "a paused stretch must not close a lap");
        r.resume(1200);
        // Resuming drops the anchor, so the first fix back only re-anchors;
        // 180 more moving seconds then completes the budget, from the moving
        // clock the pause froze rather than the 20 minutes the wall clock ran.
        r.on_fix(&fix(north(120.0), -105.0, 1.0, 1200));
        r.on_fix(&fix(north(300.0), -105.0, 1.0, 1380));
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        assert_eq!(s.last_lap.unwrap().moving_s, 300);
    }

    #[test]
    fn a_manual_lap_restarts_the_time_countdown_too() {
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Min5);
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(north(0.0), -105.0, 1.0, 0));
        r.on_fix(&fix(north(240.0), -105.0, 1.0, 240));
        r.lap(240);
        assert_eq!(r.snapshot().lap, 2);
        // 240 s already banked, but the countdown restarted: 240 more is not
        // enough, 300 is.
        r.on_fix(&fix(north(480.0), -105.0, 1.0, 480));
        assert_eq!(r.snapshot().lap, 2);
        r.on_fix(&fix(north(540.0), -105.0, 1.0, 540));
        assert_eq!(r.snapshot().lap, 3);
    }

    #[test]
    fn changing_the_trigger_mid_run_measures_from_the_open_lap() {
        // Switching must not retroactively close laps that never happened, nor
        // hold a boundary the runner has already passed.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(north(0.0), -105.0, 4.0, 0));
        r.on_fix(&fix(north(800.0), -105.0, 4.0, 200));
        assert_eq!(r.snapshot().lap, 1);
        r.set_auto_lap(AutoLap::Mi1);
        assert_eq!(r.snapshot().auto_lap, AutoLap::Mi1);
        r.on_fix(&fix(north(1100.0), -105.0, 4.0, 275));
        assert_eq!(r.snapshot().lap, 1, "the kilometre boundary is gone");
        r.on_fix(&fix(north(1700.0), -105.0, 4.0, 425));
        assert_eq!(r.snapshot().lap, 2, "the mile boundary applies from lap 1");
    }

    #[test]
    fn below_threshold_stretch_auto_pauses_and_is_excluded_from_moving() {
        let mut r = Recorder::new();
        r.start(0);
        // Three fast 1 s segments northbound.
        for (i, lat) in [40.0, 40.00005, 40.0001, 40.00015].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        assert_eq!(r.state(), RecordState::Recording);
        assert_eq!(r.snapshot().moving_s, 3);
        let dist_before = r.snapshot().distance_m;

        // Jitter within ~1 m of the last anchor for three seconds — auto-pause.
        for (t, lon) in [(4, -105.0), (5, -105.000005), (6, -105.0)].iter() {
            r.on_fix(&fix(40.00015, *lon, 0.0, *t));
        }
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Paused);
        assert_eq!(s.moving_s, 3, "paused seconds excluded from moving time");
        assert_eq!(
            s.elapsed_s, 6,
            "wall clock still advanced through the pause"
        );
        assert_eq!(s.distance_m, dist_before, "jitter added no distance");

        // Moving again auto-resumes and moving time accrues once more.
        r.on_fix(&fix(40.0002, -105.0, 4.0, 8));
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Recording);
        assert!(s.moving_s > 3);
        assert!(s.distance_m > dist_before);
    }

    #[test]
    fn snapshot_marks_only_a_manual_pause_as_manual() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        r.on_fix(&fix(40.00005, -105.0, 5.0, 1));
        assert!(!r.snapshot().manual_paused);

        // A stationary stretch auto-pauses: Paused, but not manual.
        r.on_fix(&fix(40.00005, -105.0, 0.0, 2));
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Paused);
        assert!(!s.manual_paused);

        // An explicit pause is the one the runner must resume by hand.
        r.pause(3);
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Paused);
        assert!(s.manual_paused);

        // Stopping out of a manual pause must not leak the stale flag into
        // the Finished snapshot.
        r.stop(4);
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Finished);
        assert!(!s.manual_paused);
    }

    #[test]
    fn reset_dismisses_a_finished_run_and_only_a_finished_run() {
        let mut r = Recorder::new();
        // Inert from idle and mid-run: a stray press can't wipe the view of a
        // live recording.
        r.reset(0);
        assert_eq!(r.state(), RecordState::Idle);
        r.start(1);
        r.reset(2);
        assert_eq!(r.state(), RecordState::Recording);
        r.pause(3);
        r.reset(4);
        assert_eq!(r.state(), RecordState::Paused);
        // From finished: back to idle, and a fresh start records from zero.
        r.stop(5);
        r.reset(6);
        assert_eq!(r.state(), RecordState::Idle);
        r.start(7);
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Recording);
        assert_eq!(s.distance_m, 0.0);
        assert_eq!(s.elapsed_s, 0);
    }

    #[test]
    fn dropout_reacquire_rebases_anchor_without_crediting_gap() {
        // run_recorder's #330: a hop that fails the one-hop cap after a real
        // signal gap re-anchors instead of freezing distance forever.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 0));
        r.on_fix(&fix(40.00005, -105.0, 3.0, 1));
        let dist_before = r.snapshot().distance_m;
        assert!(dist_before > 5.0, "sanity: pre-gap segment accrued");
        assert_eq!(r.snapshot().moving_s, 1);

        // 41 s dropout during which the runner moved ~150 m: past MAX_JUMP_M,
        // so the hop credits nothing — but the anchor rebases (and the point
        // is stored so the flash track carries the reacquire position).
        r.on_fix(&fix(40.00140, -105.0, 3.0, 42));
        let s = r.snapshot();
        assert_eq!(s.distance_m, dist_before, "gap distance never credited");
        assert_eq!(s.moving_s, 1, "gap banks no moving time");
        assert!(r.last_fix_stored(), "reacquire point stored to the track");

        // The very next fix measures from the reacquire point — ~5.6 m, not
        // ~155 m from the pre-gap anchor. Before the re-anchor this fix (and
        // every one after it) was rejected and distance stayed frozen.
        r.on_fix(&fix(40.00145, -105.0, 3.0, 43));
        let s = r.snapshot();
        let resumed = s.distance_m - dist_before;
        assert!(
            (5.0..7.0).contains(&resumed),
            "recording resumed from the reacquire point (got {resumed} m)"
        );
        assert_eq!(s.state, RecordState::Recording);
    }

    #[test]
    fn short_gap_teleport_still_rejected_and_keeps_anchor() {
        // Under GPS_REANCHOR_AFTER_S the one-hop cap keeps its old semantics:
        // reject AND hold the anchor, so a corrupt teleport can't re-base.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 0));

        // 150 m in 9 s (16.7 m/s): both implausible and past the cap, and
        // too soon to be a trusted gap — dropped, anchor untouched.
        r.on_fix(&fix(40.00135, -105.0, 3.0, 9));
        assert_eq!(r.snapshot().distance_m, 0.0);
        assert!(!r.last_fix_stored(), "teleport not stored");

        // A fix near the ORIGINAL anchor is accepted and measures from it —
        // proof the teleport did not move the anchor.
        r.on_fix(&fix(40.00004, -105.0, 3.0, 10));
        let d = r.snapshot().distance_m;
        assert!(
            (3.0..6.0).contains(&d),
            "next fix measured from the held anchor (got {d} m)"
        );
    }

    #[test]
    fn slow_segment_counts_distance_not_moving_time() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 0.3, 0));
        // ~4.45 m over 10 s => 0.44 m/s: past the movement gate, under the
        // moving-speed gate. Distance counts; the 10 s does not.
        r.on_fix(&fix(40.00004, -105.0, 0.3, 10));
        let s = r.snapshot();
        assert!(s.distance_m > TRACK_THRESHOLD_M);
        assert_eq!(s.moving_s, 0);
        assert_eq!(s.state, RecordState::Paused);
    }

    #[test]
    fn manual_pause_ignores_fixes() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        r.pause(1);
        // A fix during a manual pause is dropped, distance frozen.
        r.on_fix(&fix(40.0005, -105.0, 4.0, 2));
        assert_eq!(r.snapshot().distance_m, 0.0);
        assert_eq!(r.state(), RecordState::Paused);
        // On resume the anchor is cleared so the pause gap isn't one big hop.
        r.resume(3);
        r.on_fix(&fix(40.0005, -105.0, 4.0, 4));
        assert_eq!(r.snapshot().distance_m, 0.0);
    }

    #[test]
    fn last_fix_stored_marks_only_anchor_adopting_fixes() {
        let mut r = Recorder::new();
        // Idle: a fix is gated out, nothing stored.
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        assert!(!r.last_fix_stored());

        r.start(0);
        // First fix in a run is the anchor — stored.
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        assert!(r.last_fix_stored());

        // A jitter fix within the movement threshold stores nothing.
        r.on_fix(&fix(40.000005, -105.0, 0.0, 1));
        assert!(!r.last_fix_stored());

        // An accepted move is stored.
        r.on_fix(&fix(40.00008, -105.0, 4.0, 2));
        assert!(r.last_fix_stored());

        // An implausible (over-speed) fix is rejected, not stored.
        r.on_fix(&fix(40.01, -105.0, 4.0, 3));
        assert!(!r.last_fix_stored());

        // A fix during a manual pause is gated out.
        r.pause(4);
        r.on_fix(&fix(40.0005, -105.0, 4.0, 5));
        assert!(!r.last_fix_stored());
    }

    #[test]
    fn track_thinning_is_fed_back_clamped_and_reset_on_start() {
        let mut r = Recorder::new();
        r.start(0);
        assert_eq!(r.snapshot().track_thinning, 1, "full resolution by default");

        // The app's record task feeds the writer's factor back after a thin.
        r.set_track_thinning(4);
        assert_eq!(r.snapshot().track_thinning, 4);
        // Clamped into the display's u8; zero can't fake full resolution off.
        r.set_track_thinning(0);
        assert_eq!(r.snapshot().track_thinning, 1);
        r.set_track_thinning(1_024);
        assert_eq!(r.snapshot().track_thinning, u8::MAX);

        // A fresh run resets it — per-run state, not sticky across starts.
        let mut r2 = Recorder::new();
        r2.set_track_thinning(8);
        r2.start(0);
        assert_eq!(r2.snapshot().track_thinning, 1);
    }

    #[test]
    fn auto_lap_closes_at_each_kilometre_boundary() {
        let mut r = Recorder::new();
        r.start(0);
        let seg_m = expected_m((40.0, -105.0), (40.00008, -105.0)); // ~8.9 m
        let fixes_per_lap = (AUTO_LAP_DISTANCE_M / seg_m) as u32 + 1; // first crossing
        for i in 0..=fixes_per_lap * 2 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
            if i < fixes_per_lap {
                assert_eq!(r.snapshot().lap, 1, "no lap before the boundary (i={})", i);
            }
            if i == fixes_per_lap {
                let s = r.snapshot();
                assert_eq!(s.lap, 2, "boundary fix opens lap 2");
                let last = s.last_lap.unwrap();
                assert_eq!(last.index, 1);
                assert_eq!(last.elapsed_s, fixes_per_lap);
                assert_eq!(last.moving_s, fixes_per_lap);
                assert!(
                    last.distance_m >= AUTO_LAP_DISTANCE_M
                        && last.distance_m < AUTO_LAP_DISTANCE_M + 2.0 * seg_m,
                    "lap 1 distance {} not just past the boundary",
                    last.distance_m
                );
            }
        }
        // The second boundary closed lap 2 with the same one-lap split, and the
        // in-progress lap restarted at the closing fix.
        let s = r.snapshot();
        assert_eq!(s.lap, 3);
        let last = s.last_lap.unwrap();
        assert_eq!(last.index, 2);
        assert_eq!(last.elapsed_s, fixes_per_lap);
        assert!(last.distance_m >= AUTO_LAP_DISTANCE_M);
        assert_eq!(s.lap_elapsed_s, 0);
        assert_eq!(s.lap_distance_m, 0.0);
    }

    #[test]
    fn manual_lap_closes_now_and_resets_the_auto_boundary() {
        let mut r = Recorder::new();
        r.start(0);
        // ~445 m in 50 segments.
        for i in 0..=50 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        let before = r.snapshot();
        assert_eq!(before.lap, 1);
        assert!(before.last_lap.is_none());

        r.lap(50);
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        let last = s.last_lap.unwrap();
        assert_eq!(last.index, 1);
        assert_eq!(last.elapsed_s, 50);
        assert!((last.distance_m - before.distance_m).abs() < 1e-9);
        assert_eq!(s.lap_distance_m, 0.0);
        assert_eq!(s.lap_elapsed_s, 0);

        // The auto boundary measures from the manual lap: the run total passing
        // 1 km must not close lap 2 — only 1 km within lap 2 would.
        for i in 51..=120 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        let s = r.snapshot();
        assert!(s.distance_m > AUTO_LAP_DISTANCE_M);
        assert!(s.lap_distance_m < AUTO_LAP_DISTANCE_M);
        assert_eq!(s.lap, 2, "auto-lap must not fire off the run total");
    }

    #[test]
    fn lap_splits_measure_the_lap_not_the_run() {
        let mut r = Recorder::new();
        r.start(0);
        for i in 0..=10 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        r.lap(10); // lap 1: 10 s elapsed, 10 s moving

        // Lap 2 spans a 10 s manual pause, then five moving segments.
        r.pause(12);
        r.resume(20);
        for (k, t) in (21..=26).enumerate() {
            r.on_fix(&fix(40.001 + k as f64 * 0.00008, -105.0, 5.0, t));
        }
        r.lap(26);
        let last = r.snapshot().last_lap.unwrap();
        assert_eq!(last.index, 2);
        assert_eq!(
            last.elapsed_s, 16,
            "lap split runs 10 -> 26, pause included"
        );
        assert_eq!(last.moving_s, 5, "only the five moving segments count");
        assert!(last.distance_m < 100.0, "previous laps' distance excluded");
    }

    #[test]
    fn manual_lap_is_inert_when_idle_or_finished() {
        let mut r = Recorder::new();
        r.lap(5);
        let s = r.snapshot();
        assert_eq!(s.lap, 0);
        assert!(s.last_lap.is_none());

        r.start(0);
        for (i, lat) in [40.0, 40.00005, 40.0001].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        r.stop(10);
        // Stop leaves the lap in progress open (laps are display state only),
        // and a lap press after finish changes nothing.
        let frozen = r.snapshot();
        assert_eq!(frozen.lap, 1);
        r.lap(20);
        assert_eq!(r.snapshot(), frozen);
    }

    #[test]
    fn back_to_back_manual_laps_record_a_zero_length_lap() {
        let mut r = Recorder::new();
        r.start(0);
        r.tick(5);
        r.lap(5);
        r.lap(5);
        let s = r.snapshot();
        assert_eq!(s.lap, 3);
        let last = s.last_lap.unwrap();
        assert_eq!(last.index, 2);
        assert_eq!(last.elapsed_s, 0);
        assert_eq!(last.distance_m, 0.0);
    }

    #[test]
    fn gap_reads_the_grade_from_gps_altitude_without_a_baro() {
        let mut r = Recorder::new();
        r.start(0);
        // Northbound ~8.9 m steps at 1 Hz, climbing 10% of the ground covered.
        for i in 0..=10u32 {
            let lat = 40.0 + i as f64 * 0.00008;
            let alt = 1000.0 + i as f32 * 0.89;
            r.on_fix(&fix_alt(lat, -105.0, 5.0, i, alt));
        }
        let s = r.snapshot();
        // Raw current pace comes from the fix's reported speed (5 m/s)...
        assert_eq!(s.current_pace_s_per_km, Some(200));
        // ...and the climb makes the effort-equivalent flat pace faster.
        assert!(s.gap_s_per_km.unwrap() < 200);
    }

    #[test]
    fn gap_prefers_the_baro_altitude_over_the_gps_fix() {
        let mut r = Recorder::new();
        r.start(0);
        for i in 0..=10u32 {
            let lat = 40.0 + i as f64 * 0.00008;
            // The GPS altitude claims a 10% climb, but the barometer reads a
            // 10% descent — the baro wins, same preference as the flash store.
            r.set_baro_altitude(1000.0 - i as f32 * 0.89);
            r.on_fix(&fix_alt(lat, -105.0, 5.0, i, 1000.0 + i as f32 * 0.89));
        }
        assert!(r.snapshot().gap_s_per_km.unwrap() > 200);
    }

    #[test]
    fn gap_equals_raw_pace_with_no_altitude_signal() {
        let mut r = Recorder::new();
        r.start(0);
        for i in 0..=5u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        // No baro, no GPS altitude: grade stays 0 and GAP reads as raw pace —
        // the live field's no-altimeter behaviour.
        assert_eq!(r.snapshot().gap_s_per_km, Some(200));
    }

    #[test]
    fn gap_hold_rides_out_a_throttled_mode_inter_fix_gap_and_marks_it_held() {
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        // 300 m legs at 60 s spacing: a 5 m/s runner in Expedition mode.
        for i in 0..=3u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.0027, -105.0, 5.0, i * 60));
        }
        let live = r.snapshot();
        assert_eq!(live.gap_s_per_km, Some(200));
        assert!(!live.gap_held);

        // The headwall: the next fix reports a sub-gate crawl, and the fix
        // after it is a minute away — every 1 Hz snapshot in between samples
        // the frozen 0.3 m/s, so a cadence-blind ten-tick hold would blank
        // GAP for the last fifty seconds of the gap.
        r.on_fix(&fix(40.0108, -105.0, 0.3, 240));
        for _ in 0..60 {
            let s = r.snapshot();
            assert_eq!(s.gap_s_per_km, Some(200));
            assert!(s.gap_held);
        }
        // The next fix confirms the crawl as sustained; the original
        // ten-tick grace spends down and GAP blanks honestly.
        r.on_fix(&fix(40.01096, -105.0, 0.3, 300));
        for _ in 0..9 {
            let s = r.snapshot();
            assert_eq!(s.gap_s_per_km, Some(200));
            assert!(s.gap_held);
        }
        let s = r.snapshot();
        assert_eq!(s.gap_s_per_km, None);
        assert!(!s.gap_held);
    }

    #[test]
    fn gap_gates_out_walking_and_stopped() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 0.3, 0));
        let s = r.snapshot();
        // 0.3 m/s: the raw current pace still renders, but GAP is below the
        // walk threshold where pace-from-speed is noise.
        assert!(s.current_pace_s_per_km.is_some());
        assert_eq!(s.gap_s_per_km, None);
        r.stop(1);
        assert_eq!(r.snapshot().gap_s_per_km, None);
    }

    #[test]
    fn zone_time_banks_with_moving_time_into_the_hr_zone() {
        let mut r = Recorder::new();
        r.start(0);
        // 152 bpm on the default 190 ladder is the Z3 cutoff itself.
        r.set_hr(Some(152));
        for i in 0..=5u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        let s = r.snapshot();
        assert_eq!(s.moving_s, 5);
        assert_eq!(s.zone_time_s, [0, 0, 5, 0, 0]);
        assert_eq!(s.zone_cutoffs, [114, 133, 152, 171, 190]);

        // The HR moves one beat past the cutoff: further seconds bank in Z4.
        r.set_hr(Some(153));
        for i in 6..=8u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        assert_eq!(r.snapshot().zone_time_s, [0, 0, 5, 3, 0]);
    }

    #[test]
    fn no_hr_reading_accrues_no_zone_time() {
        let mut r = Recorder::new();
        r.start(0);
        for i in 0..=4u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        let s = r.snapshot();
        assert_eq!(s.moving_s, 4, "moving time still accrues sensorless");
        assert_eq!(s.zone_time_s, [0; 5]);

        // A reading that later drops out (detector lost the pulse) stops the
        // accrual again — a stale BPM never keeps banking.
        r.set_hr(Some(120));
        r.on_fix(&fix(40.0004, -105.0, 5.0, 5));
        assert_eq!(r.snapshot().zone_time_s, [0, 1, 0, 0, 0]);
        r.set_hr(None);
        r.on_fix(&fix(40.00048, -105.0, 5.0, 6));
        let s = r.snapshot();
        assert_eq!(s.zone_time_s, [0, 1, 0, 0, 0]);
        assert_eq!(s.moving_s, 6);
    }

    #[test]
    fn paused_time_accrues_no_zone_time() {
        let mut r = Recorder::new();
        r.start(0);
        r.set_hr(Some(152));
        for i in 0..=3u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        assert_eq!(r.snapshot().zone_time_s, [0, 0, 3, 0, 0]);

        // Manual pause: fixes are gated out entirely — nothing banks.
        r.pause(4);
        r.on_fix(&fix(40.001, -105.0, 5.0, 6));
        r.tick(10);
        assert_eq!(r.snapshot().zone_time_s, [0, 0, 3, 0, 0]);
        r.resume(10);

        // Auto-pause: jitter within the movement gate adds no moving time and
        // no zone time, even with a live HR.
        r.on_fix(&fix(40.00024, -105.0, 0.0, 11));
        r.on_fix(&fix(40.000245, -105.0, 0.0, 13));
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Paused);
        assert_eq!(s.zone_time_s, [0, 0, 3, 0, 0]);

        // A slow (sub-moving-gate) segment counts distance but neither moving
        // nor zone time.
        r.on_fix(&fix(40.00028, -105.0, 0.3, 23));
        let s = r.snapshot();
        assert_eq!(s.moving_s, 3);
        assert_eq!(s.zone_time_s, [0, 0, 3, 0, 0]);
    }

    #[test]
    fn start_resets_the_zone_accumulators_but_keeps_the_sticky_hr() {
        let mut r = Recorder::new();
        r.start(0);
        r.set_hr(Some(160));
        for i in 0..=3u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 5.0, i));
        }
        r.stop(4);
        assert_eq!(r.snapshot().zone_time_s, [0, 0, 0, 3, 0]);

        let mut r2 = Recorder::new();
        r2.set_hr(Some(160));
        r2.start(0);
        assert_eq!(r2.snapshot().zone_time_s, [0; 5]);
        // The sticky HR survives start — the first moving segment banks.
        r2.on_fix(&fix(40.0, -105.0, 5.0, 0));
        r2.on_fix(&fix(40.00008, -105.0, 5.0, 1));
        assert_eq!(r2.snapshot().zone_time_s, [0, 0, 0, 1, 0]);
    }

    #[test]
    fn set_max_hr_rebuilds_the_ladder_and_rejects_garbage() {
        let mut r = Recorder::new();
        assert_eq!(r.snapshot().zone_cutoffs, [114, 133, 152, 171, 190]);
        r.set_max_hr(200);
        assert_eq!(r.snapshot().zone_cutoffs, [120, 140, 160, 180, 200]);
        // Outside the 80..=240 plausibility window: ignored, ladder kept.
        r.set_max_hr(40);
        r.set_max_hr(300);
        assert_eq!(r.snapshot().zone_cutoffs, [120, 140, 160, 180, 200]);

        // The new ladder rebuckets from now on: 135 bpm is Z3 on the 190
        // ladder but only Z2 at max 200.
        r.start(0);
        r.set_hr(Some(135));
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        r.on_fix(&fix(40.00008, -105.0, 5.0, 1));
        assert_eq!(r.snapshot().zone_time_s, [0, 1, 0, 0, 0]);
    }

    #[test]
    fn pacer_is_inactive_without_a_goal_and_while_idle() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        assert!(
            r.snapshot().pacer.is_none(),
            "no goal: the pacer stays inactive, never a fake on-pace zero"
        );

        let mut r = Recorder::new();
        r.set_pacer_goal(10_000, 3_000);
        assert!(
            r.snapshot().pacer.is_none(),
            "a goal alone arms nothing while idle"
        );
        r.start(0);
        assert!(r.snapshot().pacer.is_some());
    }

    #[test]
    fn pacer_runs_on_the_elapsed_clock_through_a_manual_pause() {
        let mut r = Recorder::new();
        // 1 km goal in 200 s: a 5 m/s partner.
        r.set_pacer_goal(1_000, 200);
        r.start(0);
        // ~8.9 m/s northbound for 10 s: ~89 m vs the partner's 50 m — ahead.
        for i in 0..=10u32 {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 8.9, i));
        }
        let st = r.snapshot().pacer.unwrap();
        assert!(st.ahead_m > 30.0 && st.ahead_s > 0);
        assert_eq!(st.verdict, crate::pacer::PaceVerdict::Ahead);
        assert!(!st.finished);

        // A manual pause freezes distance but not the partner: the race clock
        // keeps running, so by t=100 the partner is ~500 m out and the runner
        // has fallen behind — the Garmin virtual-partner elapsed semantics.
        r.pause(11);
        r.tick(100);
        let st = r.snapshot().pacer.unwrap();
        assert!(st.ahead_m < -300.0 && st.ahead_s < -60);
        assert_eq!(st.verdict, crate::pacer::PaceVerdict::Behind);
    }

    #[test]
    fn pacer_freezes_at_the_goal_crossing() {
        let mut r = Recorder::new();
        r.set_pacer_goal(100, 60);
        r.start(0);
        let seg_m = expected_m((40.0, -105.0), (40.00008, -105.0)); // ~8.9 m
        let crossing = (100.0 / seg_m) as u32 + 1; // first fix past 100 m
        for i in 0..=crossing {
            r.on_fix(&fix(40.0 + i as f64 * 0.00008, -105.0, 8.9, i));
        }
        let st = r.snapshot().pacer.unwrap();
        assert!(st.finished);
        assert_eq!(st.ahead_s, 60 - crossing as i32, "the banked result");
        assert_eq!(st.projected_finish_s, Some(crossing));

        // Jogging out and ticking on moves nothing — the result is banked.
        r.on_fix(&fix(40.0 + 20.0 * 0.00008, -105.0, 8.9, crossing + 8));
        r.tick(500);
        assert_eq!(r.snapshot().pacer.unwrap(), st);
    }

    #[test]
    fn set_pacer_goal_rejects_garbage_like_set_max_hr() {
        let mut r = Recorder::new();
        r.set_pacer_goal(0, 0);
        r.set_pacer_goal(50, 300); // under the 100 m distance floor
        r.set_pacer_goal(10_000, 30); // under the 60 s time floor
        r.start(0);
        assert!(
            r.snapshot().pacer.is_none(),
            "garbage must not arm the pacer"
        );
    }

    #[test]
    fn stop_finalises_and_further_fixes_do_not_mutate_totals() {
        let mut r = Recorder::new();
        r.start(0);
        for (i, lat) in [40.0, 40.00005, 40.0001].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        r.stop(10);
        let frozen = r.snapshot();
        assert_eq!(frozen.state, RecordState::Finished);

        r.on_fix(&fix(40.001, -105.0, 5.0, 20));
        r.tick(50);
        assert_eq!(r.snapshot(), frozen);
    }

    #[test]
    fn idle_has_no_cutoff_or_prediction() {
        let r = Recorder::new();
        assert_eq!(r.snapshot().cutoff, None);
        assert_eq!(r.snapshot().race_prediction, None);
    }

    #[test]
    fn race_prediction_gated_on_min_distance() {
        // ~240 m segments at 60 s (4 m/s, clears the moving gate). Below 1 km
        // the predictor stays blank; the segment that crosses 1 km turns it on.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        let mut lat = 40.0;
        r.on_fix(&fix(lat, -105.0, 4.0, 0));
        for i in 1..=3 {
            lat += 0.00216; // ~240 m north
            r.on_fix(&fix(lat, -105.0, 4.0, i * 60));
        }
        // ~720 m — under the gate.
        assert!(r.snapshot().distance_m < MIN_PREDICT_DISTANCE_M);
        assert_eq!(r.snapshot().race_prediction, None);
        for i in 4..=6 {
            lat += 0.00216;
            r.on_fix(&fix(lat, -105.0, 4.0, i * 60));
        }
        // ~1440 m — the ladder is live.
        let snap = r.snapshot();
        assert!(snap.distance_m >= MIN_PREDICT_DISTANCE_M);
        let pred = snap.race_prediction.expect("ladder past the min distance");
        assert_eq!(pred.rungs.len(), 4);
        assert_eq!(pred.qualifying_count, 1);
        // The anchor is the live run: its distance/time, projected age 0.
        assert!((pred.anchor.distance_m - snap.distance_m).abs() < 1e-9);
        assert_eq!(pred.anchor.age_days, 0.0);
    }

    #[test]
    fn cutoff_eta_needs_legs_and_projects_from_route_position() {
        use crate::cutoff_eta::CutoffEtaStatus;

        // A run under way with a moving pace but no cutoff legs: no ETA surface.
        // 60 s fix interval so the ~240 m segment clears the jump filter.
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        r.on_fix(&fix(40.00216, -105.0, 4.0, 60)); // ~240 m, moving pace exists
        assert!(r.snapshot().avg_pace_s_per_km.is_some());
        assert_eq!(r.snapshot().cutoff, None);

        // Load a cutoff 500 m along the course and feed a 200 m route position:
        // 300 m to go, a fresh fix + known pace, so an honest verdict (not
        // Unknown) with the distance reported.
        r.set_cutoff_legs(&[CutoffLeg {
            cum_dist_m: 500.0,
            limit_elapsed_s: 600,
        }]);
        r.set_route_position(Some(200.0));
        let eta = r
            .snapshot()
            .cutoff
            .expect("cutoff surface with legs loaded");
        assert!(eta.has_cutoff);
        assert!((eta.distance_to_m - 300.0).abs() < 1e-6);
        assert_ne!(eta.status, CutoffEtaStatus::Unknown);
        assert!(eta.projected_arrival_elapsed_s.is_some());

        // Let the clock run on with no fresh route position: the frozen position
        // ages past the stale budget, so the ETA is withheld (Unknown) while the
        // checkpoint distance is still reported.
        r.tick(300);
        let stale = r.snapshot().cutoff.expect("still has the leg");
        assert_eq!(stale.status, CutoffEtaStatus::Unknown);
        assert_eq!(stale.projected_arrival_elapsed_s, None);
        assert!(stale.has_cutoff);
    }

    #[test]
    fn the_sleep_budget_rides_the_cutoff_gate_and_the_slower_pace() {
        use crate::sleep_station::SleepStatus;

        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));
        r.on_fix(&fix(40.00216, -105.0, 4.0, 60));
        assert_eq!(r.snapshot().sleep, None, "no legs, no budget");
        assert_eq!(r.snapshot().pages_mask & Page::SleepStation.bit(), 0);

        // A cut-off two hours out, 300 m to go: masses of margin, so a budget.
        r.set_cutoff_legs(&[CutoffLeg {
            cum_dist_m: 500.0,
            limit_elapsed_s: 7_200,
        }]);
        r.set_route_position(Some(200.0));
        let s = r.snapshot();
        let sleep = s.sleep.expect("budget with legs loaded");
        assert_eq!(sleep.status, SleepStatus::Budget);
        assert_ne!(s.pages_mask & Page::SleepStation.bit(), 0);

        // The projection is never faster than the race clock allows: the run
        // banked 240 m in 60 s of MOVING time but the elapsed clock is what the
        // cut-off is measured on, so the slower of the two is what it used.
        let race_pace = f64::from(s.elapsed_s) * 1000.0 / s.distance_m;
        assert_eq!(sleep.pace_s_per_km, Some(race_pace));
        assert!(race_pace >= f64::from(s.avg_pace_s_per_km.unwrap()));

        // The position ages out: the budget goes Unknown with the cut-off ETA
        // rather than counting down off a place the runner has left.
        r.tick(300);
        let stale = r.snapshot().sleep.expect("still has the leg");
        assert_eq!(stale.status, SleepStatus::Unknown);
        assert_eq!(stale.budget_min(), None);
    }

    #[test]
    fn idle_has_no_sleep_budget() {
        let r = Recorder::new();
        assert_eq!(r.snapshot().sleep, None);
    }

    #[test]
    fn the_course_profile_marker_needs_both_a_profile_and_a_fresh_position() {
        let profile = |total_m: u32| RouteElevView {
            gain_m: 100,
            loss_m: 50,
            points: 8,
            total_m,
            samples: [1500; COURSE_PROFILE_CAP],
            len: COURSE_PROFILE_CAP,
        };

        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 4.0, 0));

        // A fed position with no course profile has nothing to be a fraction of.
        r.set_route_position(Some(500.0));
        assert_eq!(r.snapshot().route_position_permille, None);

        // Profile plus a fresh position: half way along a 1 km course.
        r.set_route_elev(Some(profile(1000)));
        assert_eq!(r.snapshot().route_position_permille, Some(500));

        // A profile with no fed position leaves the marker off.
        r.set_route_position(None);
        assert_eq!(r.snapshot().route_position_permille, None);

        // A position that ages past the stale budget withholds the marker rather
        // than freezing it where the runner last had signal.
        r.set_route_position(Some(500.0));
        assert_eq!(r.snapshot().route_position_permille, Some(500));
        r.tick(600);
        assert_eq!(r.snapshot().route_position_permille, None);

        // A zero-length course can't place a marker either.
        r.set_route_position(Some(500.0));
        r.set_route_elev(Some(profile(0)));
        assert_eq!(r.snapshot().route_position_permille, None);
    }

    #[test]
    fn distance_band_pace_buckets_and_training_stress_wire_through() {
        let mut r = Recorder::new();
        // Idle: every derived surface is inactive.
        assert_eq!(r.snapshot().band, None);
        assert_eq!(r.snapshot().training_stress, None);
        assert_eq!(r.snapshot().pace_bucket_m, [0.0; PACE_BUCKET_COUNT]);

        // A throttled interval lets the test cover ~5 km in a few long legs
        // rather than 500 one-second fixes.
        r.set_fix_interval_s(60);
        r.start(0);
        let d = 500.0 / METRES_PER_DEGREE_LAT;
        for i in 1..=11 {
            r.on_fix(&fix(40.0 + i as f64 * d, -105.0, 8.0, i * 60));
        }
        let snap = r.snapshot();
        assert!(
            (4900.0..5100.0).contains(&snap.distance_m),
            "distance {}",
            snap.distance_m
        );
        // Band mirrors the pure classifier over the live distance.
        assert_eq!(snap.band, band_for_distance(snap.distance_m));
        assert_eq!(
            snap.band.map(|b| b.key),
            Some(crate::distance_bands::DistanceBandKey::FiveK)
        );
        // Every accepted segment's distance banks in exactly one bucket, so the
        // buckets sum back to the run distance.
        let bucket_sum: f64 = snap.pace_bucket_m.iter().sum();
        assert!((bucket_sum - snap.distance_m).abs() < 1.0);
        // Single-run stress is the distance model until the HR pair syncs.
        let stress = snap.training_stress.expect("stress once distance accrues");
        assert!((stress - (snap.distance_m as f32 / 1000.0) * 10.0).abs() < 1.0);
        assert!(!snap.training_stress_trimp);
    }

    #[test]
    fn synced_hr_pair_plus_live_average_upgrades_stress_to_trimp() {
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.set_max_hr(190);
        r.set_resting_hr(50);
        r.start(0);
        r.set_hr(Some(150));
        let d = 500.0 / METRES_PER_DEGREE_LAT;
        for i in 1..=11 {
            r.on_fix(&fix(40.0 + i as f64 * d, -105.0, 8.0, i * 60));
        }
        let snap = r.snapshot();
        let stress = snap.training_stress.expect("stress once distance accrues");
        assert!(snap.training_stress_trimp, "HR pair + average => TRIMP");
        // The banked average is a constant 150, so the score IS the Banister
        // TRIMP of the moving time at that HR — visibly different from the
        // 10-points/km distance model.
        let distance_model = (snap.distance_m as f32 / 1000.0) * 10.0;
        assert!((stress - distance_model).abs() > 1.0);
        assert!(stress > 0.0);

        // Half the pair (or no HR average) stays honestly on the distance model.
        let mut half = Recorder::new();
        half.set_fix_interval_s(60);
        half.set_max_hr(190);
        half.start(0);
        half.set_hr(Some(150));
        half.on_fix(&fix(40.0, -105.0, 8.0, 0));
        half.on_fix(&fix(40.0 + 3.0 * d, -105.0, 8.0, 180));
        let s = half.snapshot();
        assert!(!s.training_stress_trimp);

        let mut no_avg = Recorder::new();
        no_avg.set_fix_interval_s(60);
        no_avg.set_max_hr(190);
        no_avg.set_resting_hr(50);
        no_avg.start(0);
        no_avg.on_fix(&fix(40.0, -105.0, 8.0, 0));
        no_avg.on_fix(&fix(40.0 + 3.0 * d, -105.0, 8.0, 180));
        let s = no_avg.snapshot();
        assert!(!s.training_stress_trimp, "sensorless run keeps the proxy");
    }

    #[test]
    fn set_resting_hr_rejects_garbage_like_set_max_hr() {
        let mut r = Recorder::new();
        r.set_fix_interval_s(60);
        r.set_max_hr(190);
        r.set_resting_hr(10);
        r.set_resting_hr(500);
        r.start(0);
        r.set_hr(Some(150));
        let d = 500.0 / METRES_PER_DEGREE_LAT;
        for i in 1..=4 {
            r.on_fix(&fix(40.0 + i as f64 * d, -105.0, 8.0, i * 60));
        }
        assert!(
            !r.snapshot().training_stress_trimp,
            "an implausible resting HR must not arm the TRIMP pair"
        );
        r.set_resting_hr(50);
        assert!(r.snapshot().training_stress_trimp);
    }

    #[test]
    fn hr_average_resets_with_the_run_not_with_the_sticky_reading() {
        let mut r = Recorder::new();
        r.set_max_hr(190);
        r.set_resting_hr(50);
        r.start(0);
        r.set_hr(Some(180));
        for i in 0..=3u32 {
            r.on_fix(&fix(40.0 + f64::from(i) * 0.00008, -105.0, 5.0, i));
        }
        r.stop(4);
        r.reset(5);
        // The next run's average starts fresh — a hard prior interval must not
        // bleed its HR into an easy jog's TRIMP.
        r.start(10);
        assert_eq!(r.snapshot().training_stress, None);
        r.on_fix(&fix(41.0, -105.0, 5.0, 10));
        r.on_fix(&fix(41.00008, -105.0, 5.0, 11));
        let snap = r.snapshot();
        assert!(
            snap.training_stress_trimp,
            "sticky HR still feeds the new run"
        );
    }

    #[test]
    fn load_trend_syncs_whole_and_rejects_corrupt_pushes() {
        let mut r = Recorder::new();
        assert_eq!(r.snapshot().load_trend, None);

        let trend = LoadTrendView {
            ctl: 82.0,
            atl: 95.0,
            tsb: -13.0,
        };
        r.set_load_trend(Some(trend));
        assert_eq!(r.snapshot().load_trend, Some(trend));

        // A corrupt member drops the WHOLE push — the current view stands.
        for bad in [
            LoadTrendView {
                ctl: f32::NAN,
                ..trend
            },
            LoadTrendView {
                atl: f32::INFINITY,
                ..trend
            },
            LoadTrendView {
                tsb: LOAD_TREND_PLAUSIBLE_MAX + 1.0,
                ..trend
            },
            LoadTrendView { ctl: -1.0, ..trend },
        ] {
            r.set_load_trend(Some(bad));
            assert_eq!(
                r.snapshot().load_trend,
                Some(trend),
                "{bad:?} must not land"
            );
        }

        // None clears back to the honest unsynced state.
        r.set_load_trend(None);
        assert_eq!(r.snapshot().load_trend, None);
    }

    #[test]
    fn gear_wear_folds_the_live_run_into_the_baseline() {
        let mut r = Recorder::new();
        r.start(0);
        // No gear synced → inactive.
        assert!(r.snapshot().gear.is_none());
        // A shoe at 700 km of an 800 km target sits in the 85% "due" band.
        r.set_gear(Some(700_000.0), Some(800_000.0));
        let g = r.snapshot().gear.expect("gear active once synced");
        assert_eq!(g.status, crate::gear_wear::GearWearStatus::Due);
        assert!(g.fraction.unwrap() >= 0.85);
    }

    #[test]
    fn roadbook_and_fuel_wire_through() {
        let mut r = Recorder::new();
        assert!(r.snapshot().roadbook.is_none());
        assert!(r.snapshot().fuel.is_none());
        r.set_roadbook(&[
            RoadbookCheckpoint {
                cum_dist_m: 0.0,
                leg_dist_m: 0.0,
                projected_elapsed_s: 0,
                cutoff: None,
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 5000.0,
                leg_dist_m: 5000.0,
                projected_elapsed_s: 1800,
                cutoff: Some(CutoffStatus::Safe),
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 10000.0,
                leg_dist_m: 5000.0,
                projected_elapsed_s: 3600,
                cutoff: Some(CutoffStatus::Tight),
                is_refill: false,
            },
        ]);
        r.start(0);
        // No position yet → the window starts at the first checkpoint.
        let rb = r.snapshot().roadbook.expect("roadbook active");
        assert_eq!(rb.total, 3);
        assert_eq!(rb.upcoming_len, 3);
        assert_eq!(rb.upcoming[1].cutoff, Some(CutoffStatus::Safe));
        // Past the first aid: only the finish is still ahead.
        r.set_route_position(Some(6000.0));
        let rb2 = r.snapshot().roadbook.unwrap();
        assert_eq!(rb2.upcoming_len, 1);
        assert!((rb2.upcoming[0].cum_dist_m - 10000.0).abs() < 1.0);
        // Fuel scales onto the schedule: non-zero totals + a carry out of the
        // aid we are between.
        let f = r.snapshot().fuel.expect("fuel active with a roadbook");
        assert!(f.total_carbs_g > 0.0 && f.total_fluid_ml > 0.0);
        assert!(f.carry.is_some());

        // A pushed cadence re-rates the plan through the same units the alert
        // engine reduced through: halving the drink interval (900 → 450 s)
        // doubles the fluid budget, and the untouched eat arm keeps its rate.
        r.set_fuel_intervals(450, 0);
        let f2 = r.snapshot().fuel.unwrap();
        assert!(
            (f2.total_fluid_ml - 2.0 * f.total_fluid_ml).abs() < 1.0,
            "{} vs {}",
            f2.total_fluid_ml,
            f.total_fluid_ml
        );
        assert!((f2.total_carbs_g - f.total_carbs_g).abs() < f32::EPSILON);
    }

    #[test]
    fn roadbook_arms_the_terrain_pacer_and_an_empty_one_disarms_it() {
        let mut r = Recorder::new();
        r.set_pacer_goal(10_000, 3_600);
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        assert!(
            !r.snapshot().pacer.expect("goal armed").terrain_aware,
            "no roadbook yet: even-pace partner"
        );
        // A climb-first roadbook (start + aid + finish, phone-allocated).
        r.set_roadbook(&[
            RoadbookCheckpoint {
                cum_dist_m: 0.0,
                leg_dist_m: 0.0,
                projected_elapsed_s: 0,
                cutoff: None,
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 5_000.0,
                leg_dist_m: 5_000.0,
                projected_elapsed_s: 2_400,
                cutoff: None,
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 10_000.0,
                leg_dist_m: 5_000.0,
                projected_elapsed_s: 3_600,
                cutoff: None,
                is_refill: false,
            },
        ]);
        assert!(
            r.snapshot().pacer.unwrap().terrain_aware,
            "the pushed checkpoint curve doubles as the partner schedule"
        );
        // Clearing the roadbook drops the terrain partner with it.
        r.set_roadbook(&[]);
        assert!(!r.snapshot().pacer.unwrap().terrain_aware);
    }

    #[test]
    fn the_climb_detector_rides_the_same_altitude_seam_as_the_grade() {
        // A hill must not register on the GAP page and not on the Climb page:
        // both read the sample `feed_gap` takes, so one feed proves both.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix_alt(0.0, 0.0, 3.0, 1, 100.0));
        assert!(r.snapshot().climb.active.is_none());
        // ~55 m of gain over ~550 m — a 10 % climb, past the opening gate.
        for i in 1..=11 {
            let lat = 0.0001 * i as f64 * 0.5;
            r.on_fix(&fix_alt(
                lat,
                0.0,
                3.0,
                1 + i as u32 * 10,
                100.0 + 5.0 * i as f32,
            ));
        }
        let c = r.snapshot().climb.active.expect("a 10 % ascent is a climb");
        assert!(c.gain_m > 50.0, "{}", c.gain_m);
        assert_ne!(r.snapshot().pages_mask & Page::Climb.bit(), 0);
    }

    #[test]
    fn a_new_run_never_inherits_the_last_runs_foot() {
        // Without the reset, a run starting lower than the last one ended
        // opens a climb on its first fix — a phantom ascent the runner never
        // made, on the page that exists to tell them what they did.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix_alt(0.0, 0.0, 3.0, 1, 2_000.0));
        for i in 1..=11 {
            let lat = 0.0001 * i as f64 * 0.5;
            r.on_fix(&fix_alt(
                lat,
                0.0,
                3.0,
                1 + i as u32 * 10,
                2_000.0 + 5.0 * i as f32,
            ));
        }
        assert!(r.snapshot().climb.active.is_some());
        r.stop(200);
        r.reset(201);
        r.start(202);
        r.on_fix(&fix_alt(0.0, 0.0, 3.0, 203, 100.0));
        assert!(r.snapshot().climb.active.is_none());
    }

    #[test]
    fn the_crest_ahead_needs_both_a_profile_and_a_position() {
        // Derived per snapshot from the profile the RouteElev page already
        // carries, so it shrinks with every fix rather than at sync time —
        // but it is honestly absent until both halves are there.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        // Up to a crest at sample 6 (600 m), then a committed descent.
        let mut samples = [0i16; COURSE_PROFILE_CAP];
        for (i, s) in samples.iter_mut().enumerate().take(11) {
            *s = if i <= 6 {
                100 + 10 * i as i16
            } else {
                160 - 20 * (i as i16 - 6)
            };
        }
        let view = RouteElevView {
            gain_m: 60,
            loss_m: 80,
            points: 11,
            total_m: 1_000,
            samples,
            len: 11,
        };
        r.set_route_elev(Some(view));
        assert!(
            r.snapshot().climb.ahead.is_none(),
            "no along-course position yet"
        );
        r.set_route_position(Some(0.0));
        let a = r
            .snapshot()
            .climb
            .ahead
            .expect("a crest 600 m up the course");
        assert!((a.gain_m - 60.0).abs() < 0.01, "{}", a.gain_m);
        assert!((a.distance_m - 600.0).abs() < 0.01, "{}", a.distance_m);
        // ...and it shrinks as the runner climbs.
        r.set_route_position(Some(400.0));
        let b = r.snapshot().climb.ahead.unwrap();
        assert!(b.gain_m < a.gain_m && b.distance_m < a.distance_m);

        // A position frozen by a lost signal ages past the stale budget, and
        // the crest goes away rather than reporting the one from where the
        // runner was — metres-remaining stuck while they climb is the failure.
        r.tick(600);
        assert!(r.snapshot().climb.ahead.is_none());
        // A fresh position brings it straight back.
        r.set_route_position(Some(400.0));
        assert!(r.snapshot().climb.ahead.is_some());
    }

    #[test]
    fn a_mark_saves_the_anchor_the_run_is_measured_from() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(10.0, 20.0, 3.0, 1));
        assert!(r.mark_waypoint(5));
        let w = r.waypoints().latest().copied().unwrap();
        assert_eq!((w.lat_deg, w.lon_deg), (10.0, 20.0));
        assert_eq!(w.marked_uptime_s, 5);
        // The view measures from the CURRENT anchor back to the mark, so a
        // mark taken where the runner stands reads zero and then grows.
        assert_eq!(r.snapshot().waypoint.unwrap().distance_m, 0.0);
        // Due north — 0.001 deg of latitude is ~111 m.
        r.on_fix(&fix(10.001, 20.0, 3.0, 40));
        let v = r.snapshot().waypoint.unwrap();
        assert!((v.distance_m - 111.0).abs() < 2.0, "{}", v.distance_m);
        assert!(
            v.bearing_deg > 179.0 && v.bearing_deg < 181.0,
            "{}",
            v.bearing_deg
        );
        assert_eq!(v.count, 1);
    }

    #[test]
    fn a_mark_without_an_anchor_or_outside_a_run_saves_nothing() {
        // Never a fabricated 0,0: idle has no position of its own, and a run
        // that has not yet accepted a fix has no anchor to save.
        let mut r = Recorder::new();
        assert!(!r.mark_waypoint(1));
        r.start(0);
        assert!(!r.mark_waypoint(2));
        assert!(r.waypoints().is_empty());
        // Every outcome counts on its own wire: two refusals so far, no mark
        // — the alert engine's edge detection answers the press either way.
        assert_eq!(r.snapshot().waypoint_refuse_seq, 2);
        assert_eq!(r.snapshot().waypoint_mark_seq, 0);
        r.on_fix(&fix(10.0, 20.0, 3.0, 1));
        assert!(r.mark_waypoint(3));
        assert_eq!(r.snapshot().waypoint_mark_seq, 1);
        assert_eq!(r.snapshot().waypoint_refuse_seq, 2);
        // A finished run's anchor is history — the run is already committed,
        // so a stray hold must not append to the store.
        r.stop(10);
        assert!(!r.mark_waypoint(11));
        assert_eq!(r.waypoints().len(), 1);
    }

    #[test]
    fn marks_outlive_the_run_that_made_them() {
        // The whole point of the feature: a stash marked on one run is still
        // there on the next, so neither start nor reset may clear the store.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(10.0, 20.0, 3.0, 1));
        assert!(r.mark_waypoint(2));
        r.stop(10);
        r.reset(11);
        assert_eq!(r.waypoints().len(), 1);
        r.start(20);
        assert_eq!(r.waypoints().len(), 1);
        // ...and with no anchor yet in the new run, the page has a count but
        // no honest distance to show.
        let s = r.snapshot();
        assert_eq!(s.waypoint_count, 1);
        assert!(s.waypoint.is_none());
    }

    #[test]
    fn the_timer_page_joins_the_cycle_only_while_something_is_armed() {
        let mut r = Recorder::new();
        r.start(0);
        assert_eq!(r.snapshot().pages_mask & Page::Timer.bit(), 0);
        let mut t = crate::timers::Timer::new();
        t.start_stop(0);
        r.set_timer(t.snapshot_view(5));
        assert_ne!(r.snapshot().pages_mask & Page::Timer.bit(), 0);
        // Cleared, and the seat goes back — an unarmed instrument is not a page.
        t.start_stop(5);
        assert!(t.reset());
        r.set_timer(t.snapshot_view(6));
        assert_eq!(r.snapshot().pages_mask & Page::Timer.bit(), 0);
    }

    #[test]
    fn the_waypoint_page_joins_the_cycle_on_the_first_mark_and_stays() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(10.0, 20.0, 3.0, 1));
        assert_eq!(r.snapshot().pages_mask & Page::Waypoint.bit(), 0);
        assert!(r.mark_waypoint(2));
        assert_ne!(r.snapshot().pages_mask & Page::Waypoint.bit(), 0);
        // Keyed on the store, not on a live view: losing the fix must not
        // pull the page out from under a runner walking back to the stash.
        r.stop(10);
        r.reset(11);
        r.start(12);
        assert_ne!(
            r.snapshot().pages_mask & Page::Waypoint.bit(),
            0,
            "a stored mark keeps the page reachable before the new run's first fix"
        );
    }

    #[test]
    fn pages_mask_hides_empty_pages_by_default() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        let mask = r.snapshot().pages_mask;
        // The core run pages + Back-to-start are always in.
        for p in [
            Page::Dashboard,
            Page::Distance,
            Page::Pace,
            Page::Lap,
            Page::Splits,
            Page::BackToStart,
        ] {
            assert_ne!(mask & p.bit(), 0, "{p:?} must always be in the cycle");
        }
        // Nothing synced, no course, no HR: the sync-fed glances are out.
        for p in [
            Page::Zones,
            Page::Roadbook,
            Page::Fuel,
            Page::Nav,
            Page::GearWear,
            Page::Fitness,
            Page::Recap,
            Page::RaceDay,
            Page::Daylight,
        ] {
            assert_eq!(mask & p.bit(), 0, "{p:?} has no data and must be hidden");
        }
    }

    #[test]
    fn pages_appear_the_moment_their_data_does() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        assert_eq!(r.snapshot().pages_mask & Page::Pacer.bit(), 0);
        r.set_pacer_goal(10_000, 3_000);
        assert_ne!(r.snapshot().pages_mask & Page::Pacer.bit(), 0);
        assert_eq!(r.snapshot().pages_mask & Page::Nav.bit(), 0);
        r.set_course_loaded(true);
        assert_ne!(r.snapshot().pages_mask & Page::Nav.bit(), 0);
        r.set_course_loaded(false);
        assert_eq!(r.snapshot().pages_mask & Page::Nav.bit(), 0);
        assert_eq!(r.snapshot().pages_mask & Page::Daylight.bit(), 0);
        r.set_tz_offset_min(-360);
        assert_ne!(r.snapshot().pages_mask & Page::Daylight.bit(), 0);
    }

    #[test]
    fn hide_empty_off_restores_the_full_fixed_cycle() {
        let mut r = Recorder::new();
        r.set_hide_empty_pages(false);
        r.start(0);
        assert_eq!(
            r.snapshot().pages_mask,
            u64::MAX,
            "every page visitable, empty states and all"
        );
    }

    /// The cycle carries exactly the composed screens the runner has, and an
    /// unpushed watch walks the 41 built-ins with no blank seats among them.
    #[test]
    fn the_cycle_carries_exactly_the_composed_screens() {
        let mut r = Recorder::new();
        r.start(0);
        let none = r.snapshot().pages_mask;
        for i in 0..crate::screens::MAX_SCREENS {
            let p = Page::of_screen_index(i).unwrap();
            assert_eq!(none & p.bit(), 0, "{p:?} is in the cycle before any push");
        }

        r.set_screen_count(2);
        let two = r.snapshot().pages_mask;
        assert_ne!(two & Page::Screen1.bit(), 0);
        assert_ne!(two & Page::Screen2.bit(), 0);
        assert_eq!(two & Page::Screen3.bit(), 0, "a screen that does not exist");
        assert_eq!(two & Page::Screen4.bit(), 0);

        // BTN3 from home reaches the runner's own screen in one press — the
        // whole reason these pages seat where they do.
        assert_eq!(Page::Dashboard.next_in(two), Page::Screen1);
        assert_eq!(Page::Screen2.next_in(two), Page::Distance);
    }

    /// A count past the cap cannot open a page with no screen behind it.
    #[test]
    fn a_screen_count_past_the_cap_is_clamped() {
        let mut r = Recorder::new();
        r.set_screen_count(99);
        r.start(0);
        let mask = r.snapshot().pages_mask;
        for i in 0..crate::screens::MAX_SCREENS {
            assert_ne!(mask & Page::of_screen_index(i).unwrap().bit(), 0);
        }
        assert!(Page::of_screen_index(crate::screens::MAX_SCREENS).is_none());
    }

    #[test]
    fn curated_pages_intersect_and_dashboard_is_forced() {
        let mut r = Recorder::new();
        r.set_hide_empty_pages(false);
        r.set_pages_enabled(Page::Pace.bit() | Page::Splits.bit());
        r.start(0);
        let mask = r.snapshot().pages_mask;
        assert_eq!(
            mask,
            Page::Dashboard.bit() | Page::Pace.bit() | Page::Splits.bit()
        );
        // Even an all-zero push keeps the Dashboard reachable.
        r.set_pages_enabled(0);
        assert_eq!(r.snapshot().pages_mask, Page::Dashboard.bit());
        // With hide-empty back on, curation still can't resurrect a dataless
        // page: enabled ∩ available.
        r.set_hide_empty_pages(true);
        r.set_pages_enabled(Page::Fuel.bit() | Page::Distance.bit());
        let mask = r.snapshot().pages_mask;
        assert_eq!(mask & Page::Fuel.bit(), 0, "no roadbook, no Fuel page");
        assert_ne!(mask & Page::Distance.bit(), 0);
    }

    #[test]
    fn training_goal_pace_wires_through_and_guards_implausible() {
        let mut r = Recorder::new();
        r.start(0);
        // No goal synced → the page is honestly inactive.
        assert!(r.snapshot().training_paces.is_none());

        // A 4:00/km (240 s/km) goal derives the five zone paces, slow → fast.
        r.set_training_goal_pace_s_per_km(Some(240.0));
        let tp = r
            .snapshot()
            .training_paces
            .expect("paces once a goal is synced");
        assert_eq!(tp.goal_pace_s_per_km, 240);
        assert!(tp.paces.easy > tp.paces.marathon);
        assert!(tp.paces.marathon > tp.paces.tempo);
        assert!(tp.paces.tempo > tp.paces.interval);
        assert!(tp.paces.interval > tp.paces.repetition);
        // Matches the ported core directly (base curve, gender-neutral).
        assert_eq!(tp.paces, paces_from_goal_pace(240.0, TrainingGender::None));

        // An implausible pace (30 s/km, faster than any human) is ignored — the
        // previously-synced goal is cleared, never replaced with garbage.
        r.set_training_goal_pace_s_per_km(Some(30.0));
        assert!(r.snapshot().training_paces.is_none());
        // A too-slow value (past the 20:00/km ceiling) is likewise dropped.
        r.set_training_goal_pace_s_per_km(Some(2000.0));
        assert!(r.snapshot().training_paces.is_none());
        // Explicit clear.
        r.set_training_goal_pace_s_per_km(Some(300.0));
        assert!(r.snapshot().training_paces.is_some());
        r.set_training_goal_pace_s_per_km(None);
        assert!(r.snapshot().training_paces.is_none());
    }

    #[test]
    fn fitness_wires_through_and_guards_implausible() {
        let mut r = Recorder::new();
        r.start(0);
        // Nothing synced → honestly inactive.
        assert!(r.snapshot().fitness.is_none());

        // A plausible VO2 + recovery verdict wires straight through.
        r.set_fitness(Some(52.0), Some(RecoveryAdvice::SweetSpot));
        let f = r.snapshot().fitness.expect("fitness once synced");
        assert_eq!(f.vo2_max, Some(52.0));
        assert_eq!(f.recovery, Some(RecoveryAdvice::SweetSpot));

        // An implausible VO2 (past the 90 ceiling) is dropped, but a valid
        // recovery verdict alone still activates the page with a `--` VO2.
        r.set_fitness(Some(140.0), Some(RecoveryAdvice::HeavilyLoaded));
        let f = r
            .snapshot()
            .fitness
            .expect("recovery alone keeps the page active");
        assert_eq!(f.vo2_max, None);
        assert_eq!(f.recovery, Some(RecoveryAdvice::HeavilyLoaded));

        // Both empty → back to inactive.
        r.set_fitness(None, None);
        assert!(r.snapshot().fitness.is_none());
        // A sub-floor VO2 with no recovery is also inactive.
        r.set_fitness(Some(5.0), None);
        assert!(r.snapshot().fitness.is_none());
    }

    #[test]
    fn elevation_profile_empty_without_any_altitude() {
        let mut r = Recorder::new();
        r.start(0);
        // No baro pushed and the fixes carry no GPS altitude: nothing to sample.
        for i in 0..5u32 {
            r.on_fix(&fix(40.0, -105.0 + i as f64 * 0.0012, 4.0, i));
        }
        assert_eq!(r.snapshot().elev_profile.len, 0);
    }

    #[test]
    fn elevation_profile_banks_baro_preferred_altitude_along_the_run() {
        let mut r = Recorder::new();
        r.start(0);
        // ~5.5 m north per 1 s fix (clears the 1 Hz jump/speed gate) over 40
        // fixes (~220 m, several 25 m spacing intervals), with the baro climbing.
        for i in 0..40u32 {
            r.set_baro_altitude(1200.0 + i as f32 * 2.0);
            r.on_fix(&fix(40.0 + i as f64 * 0.00005, -105.0, 5.0, i));
        }
        let v = r.snapshot().elev_profile;
        assert!(
            v.len >= 5,
            "banks a sample per spacing interval, got {}",
            v.len
        );
        assert_eq!(v.samples[0], 1200, "first sample is the start altitude");
        assert!(
            v.samples[v.len - 1] > v.samples[0],
            "series climbs with the baro reading"
        );
    }

    #[test]
    fn elevation_profile_thins_by_halving_when_full() {
        let mut r = Recorder::new();
        r.start(0);
        // ~5.5 m north per 1 s fix (clears the 1 Hz jump/speed gate) over 800
        // fixes (~4.4 km) forces several thinnings, with the baro climbing.
        for i in 0..800u32 {
            r.set_baro_altitude(1000.0 + i as f32);
            r.on_fix(&fix(40.0 + i as f64 * 0.00005, -105.0, 5.0, i));
        }
        let v = r.snapshot().elev_profile;
        assert!(v.len <= ELEV_PROFILE_CAP);
        assert!(
            v.len > ELEV_PROFILE_CAP / 2,
            "stays densely populated after thinning: {}",
            v.len
        );
        assert_eq!(v.samples[0], 1000, "the start altitude survives thinning");
        assert!(
            v.samples[v.len - 1] > 1300,
            "the tail still reaches the climb's top, not a truncated head"
        );
    }

    #[test]
    fn synced_summary_setters_round_trip_and_clamp() {
        let mut r = Recorder::new();
        // Unset by default — every synced page reads its honest empty state.
        let s = r.snapshot();
        assert!(s.recap.is_none() && s.readiness.is_none() && s.race_day.is_none());
        assert!(s.plan_adaptive.is_none());

        r.set_recap(Some(RecapView {
            runs: 120,
            distance_km: 1500,
            longest_km: 42,
            best_streak_days: 30,
        }));
        assert_eq!(r.snapshot().recap.unwrap().runs, 120);

        // A corrupt push can't render an out-of-range ring or an unknown band /
        // verdict / turn glyph — the setters clamp to the code space.
        r.set_readiness(Some(ReadinessView {
            score: 200,
            band: 9,
        }));
        let rd = r.snapshot().readiness.unwrap();
        assert_eq!((rd.score, rd.band), (100, 2));

        r.set_goals(Some(GoalsView {
            percent: 250,
            complete: true,
        }));
        assert_eq!(r.snapshot().goals.unwrap().percent, 100);

        r.set_turn_cue(Some(TurnCueView {
            direction: 42,
            distance_m: 100,
            remaining: 3,
        }));
        assert_eq!(r.snapshot().turn_cue.unwrap().direction, 7);

        r.set_race_day(Some(RaceDayView {
            days_until: -5,
            feasible: 9,
        }));
        assert_eq!(r.snapshot().race_day.unwrap().feasible, 2);

        r.set_plan_adaptive(Some(PlanAdaptiveView {
            trend: 9,
            confidence: 9,
            flagged_weeks: 9,
            window_weeks: 9,
            changes: 4,
            fitness_gated: true,
        }));
        let pa = r.snapshot().plan_adaptive.unwrap();
        assert_eq!((pa.trend, pa.confidence), (2, 2));
        assert_eq!((pa.flagged_weeks, pa.window_weeks), (3, 3));
        assert_eq!(pa.changes, 4);
        assert!(pa.fitness_gated);

        r.set_plan_adaptive(Some(PlanAdaptiveView {
            trend: 1,
            confidence: 1,
            flagged_weeks: 2,
            window_weeks: 3,
            changes: 1,
            fitness_gated: false,
        }));
        let pa = r.snapshot().plan_adaptive.unwrap();
        assert_eq!((pa.flagged_weeks, pa.window_weeks), (2, 3));

        // Clearing works.
        r.set_recap(None);
        assert!(r.snapshot().recap.is_none());
    }

    #[test]
    fn race_phase_advances_from_hold_back_to_the_closing_phase_with_the_run() {
        let mut r = Recorder::new();
        assert!(r.snapshot().race_phase.is_none(), "no plan pushed");

        // A 10 km race off a 50:00 goal: 300 s/km even, held back 2 % to 306.
        r.set_race_phases(
            Some(10_000.0),
            Some(3_000.0),
            RacePhasePreset::NegativeSplit,
        );
        let p = r.snapshot().race_phase.expect("active once pushed");
        assert_eq!((p.index, p.total), (1, 2));
        assert_eq!(p.intent, RacePhaseIntent::HoldBack);
        assert_eq!(p.target_pace_s_per_km, Some(306));

        // Past halfway the closing phase's derived factor takes over.
        r.set_fix_interval_s(60);
        r.start(0);
        let d = 500.0 / METRES_PER_DEGREE_LAT;
        for i in 1..=11 {
            r.on_fix(&fix(40.0 + i as f64 * d, -105.0, 8.0, i * 60));
        }
        let p = r.snapshot().race_phase.expect("still active mid-run");
        assert_eq!((p.index, p.total), (2, 2));
        assert_eq!(p.intent, RacePhaseIntent::Race);
        assert_eq!(p.target_pace_s_per_km, Some(294));
    }

    #[test]
    fn implausible_race_phase_pushes_are_ignored_not_clamped() {
        let mut r = Recorder::new();
        // A distance outside the plausible band leaves the whole plan unset —
        // no silently-clamped race the runner never entered.
        r.set_race_phases(Some(500.0), Some(3_000.0), RacePhasePreset::TenTenTen);
        assert!(r.snapshot().race_phase.is_none());
        r.set_race_phases(Some(600_000.0), Some(3_000.0), RacePhasePreset::TenTenTen);
        assert!(r.snapshot().race_phase.is_none());
        r.set_race_phases(Some(f64::NAN), Some(3_000.0), RacePhasePreset::Even);
        assert!(r.snapshot().race_phase.is_none());

        // An implausible goal time drops only the target pace: a 10 km in 60 s
        // is a 6 s/km pace, so the phase boundaries stand and carry no target.
        r.set_race_phases(Some(10_000.0), Some(60.0), RacePhasePreset::Even);
        let p = r
            .snapshot()
            .race_phase
            .expect("boundaries are still honest");
        assert_eq!(p.intent, RacePhaseIntent::Even);
        assert_eq!(p.target_pace_s_per_km, None);

        // No goal time at all reads identically.
        r.set_race_phases(Some(10_000.0), None, RacePhasePreset::Even);
        assert_eq!(r.snapshot().race_phase.unwrap().target_pace_s_per_km, None);

        // Clearing works.
        r.set_race_phases(None, Some(3_000.0), RacePhasePreset::Even);
        assert!(r.snapshot().race_phase.is_none());
    }

    /// The sim's demo arming (`app/src/tasks/record.rs`, `sim-autostart`) picks
    /// the shortest plan the setter will take and the preset with the earliest
    /// first boundary, so a canned run of a few hundred metres actually crosses a
    /// phase instead of holding phase 1 for the whole fixture. Both halves of
    /// that claim are checked here, because nothing in `app/` is host-testable.
    #[test]
    fn the_shortest_plausible_ten_ten_ten_plan_changes_phase_inside_400_m() {
        let mut r = Recorder::new();
        r.set_race_phases(
            Some(RACE_PHASE_PLAUSIBLE_MIN_DISTANCE_M),
            Some(300.0),
            RacePhasePreset::TenTenTen,
        );
        let p = r.snapshot().race_phase.expect("1 km is plausible");
        assert_eq!((p.index, p.total), (1, 3));
        assert_eq!(p.intent, RacePhaseIntent::HoldBack);
        assert_eq!(p.target_pace_s_per_km, Some(306));

        r.set_fix_interval_s(60);
        r.start(0);
        // The first fix anchors, then two 200 m hops: 400 m clears the
        // generalised ten-mile boundary at 381.4 m, which no other preset
        // reaches before its own halfway.
        let d = 200.0 / METRES_PER_DEGREE_LAT;
        for i in 1..=3 {
            r.on_fix(&fix(40.0 + i as f64 * d, -105.0, 8.0, i * 60));
        }
        let p = r.snapshot().race_phase.expect("still active mid-run");
        assert_eq!((p.index, p.intent), (2, RacePhaseIntent::Settle));
        assert_eq!(p.target_pace_s_per_km, Some(300));
    }

    // --- The guided-run page ----------------------------------------------

    /// The other half of the sim demo: the armed run has to put a cue inside the
    /// canned fixture's few minutes, or the page renders a schedule that never
    /// advances. `first-timer-15` is the library's densest opener.
    #[test]
    fn the_sim_demo_guided_run_advances_a_cue_within_the_first_four_minutes() {
        let mut r = Recorder::new();
        r.set_guided_run(Some("first-timer-15"));
        r.start(0);
        let v = r.snapshot().guided_run.expect("library id arms");
        assert_eq!(v.duration_s, 900);
        assert_eq!((v.cue_index, v.next_cue_in_s), (1, Some(180)));

        r.tick(180);
        let v = r.snapshot().guided_run.unwrap();
        assert_eq!(v.cue_index, 2, "the 3:00 cue has fired");
        assert_eq!(v.next_cue_in_s, Some(60), "then one a minute");
        assert_eq!(v.remaining_s, 720);
    }

    #[test]
    fn an_unarmed_guided_run_page_is_honestly_inactive() {
        let mut r = Recorder::new();
        r.start(0);
        let s = r.snapshot();
        assert!(s.guided_run.is_none(), "nothing armed, nothing to show");
        assert_eq!(
            s.pages_mask & Page::GuidedRun.bit(),
            0,
            "an unarmed page stays out of the cycle"
        );
    }

    #[test]
    fn an_unknown_guided_run_id_is_ignored_not_applied() {
        // The guard: a garbled id must neither arm a different run nor disarm
        // the one the runner selected. Only an explicit `None` disarms.
        let mut r = Recorder::new();
        let armed = crate::guided_runs::guided_run_library()[0].id;
        r.set_guided_run(Some(armed));
        r.start(0);
        let before = r.snapshot().guided_run.unwrap();
        r.set_guided_run(Some("not-a-guided-run"));
        assert_eq!(r.snapshot().guided_run, Some(before), "push ignored");
        r.set_guided_run(None);
        assert!(r.snapshot().guided_run.is_none(), "None disarms");
        r.set_guided_run(Some(""));
        assert!(r.snapshot().guided_run.is_none(), "empty id arms nothing");
    }

    #[test]
    fn the_guided_run_page_walks_its_cues_with_elapsed_time() {
        let g = crate::guided_runs::find_guided_run("easy-30").expect("library run");
        let mut r = Recorder::new();
        r.set_guided_run(Some(g.id));
        r.start(0);
        let v = r.snapshot().guided_run.unwrap();
        assert_eq!(v.cue_count as usize, g.cues.len());
        assert_eq!(v.duration_s, 1_800);
        assert_eq!(v.remaining_s, 1_800);
        assert_eq!(v.cue_index, 1, "the kickoff cue fires at the start");
        assert_eq!(v.next_cue_in_s, Some(300));

        // One second before the 5:00 cue, then the tick that crosses it.
        r.tick(299);
        let v = r.snapshot().guided_run.unwrap();
        assert_eq!((v.cue_index, v.next_cue_in_s), (1, Some(1)));
        r.tick(300);
        let v = r.snapshot().guided_run.unwrap();
        assert_eq!(v.cue_index, 2, "the mark is inclusive, like cues_due");
        assert_eq!(v.next_cue_in_s, Some(300));
        assert_eq!(v.remaining_s, 1_500);

        // Past the last cue: no next one, and the countdown floors at zero
        // rather than wrapping.
        r.tick(1_900);
        let v = r.snapshot().guided_run.unwrap();
        assert_eq!(v.cue_index as usize, g.cues.len());
        assert_eq!(v.next_cue_in_s, None);
        assert_eq!(v.remaining_s, 0);
    }

    #[test]
    fn every_library_guided_run_fits_the_dispatch_buffer() {
        // `guided_run_snapshot` counts passed cues off `cues_due`, whose buffer
        // is capped: a library run with more cues than the cap would silently
        // stop advancing the page's cue index near the end.
        for g in crate::guided_runs::guided_run_library() {
            assert!(
                g.cues.len() <= crate::guided_runs::MAX_GUIDED_CUES,
                "{} has more cues than the dispatch buffer holds",
                g.id
            );
            let mut r = Recorder::new();
            r.set_guided_run(Some(g.id));
            r.start(0);
            r.tick(g.duration_sec as u32);
            let v = r.snapshot().guided_run.unwrap();
            assert_eq!(
                v.cue_index, v.cue_count,
                "{} must have passed every cue at its duration",
                g.id
            );
        }
    }

    // --- Snapshot::is_moving — the barometric vert gate --------------------

    #[test]
    fn is_moving_true_through_the_min_move_filters_paused_state() {
        // A runner power-hiking a climb at ~1.7 m/s covers under the 3 m
        // min-move threshold in one 1 Hz fix, so the point-acceptance filter
        // flips the state to Paused even though the receiver reports real
        // speed. That is a GPS sampling artifact, not a stop — the vert gate
        // must stay open or a whole climb banks zero gain.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 1.7, 0));
        // ~1.7 m north: under TRACK_THRESHOLD_M, so the filter pauses.
        r.on_fix(&fix(40.0000153, -105.0, 1.7, 1));
        let s = r.snapshot();
        assert_eq!(s.state, RecordState::Paused, "min-move filter paused");
        assert!(
            s.current_speed_mps as f64 >= MIN_MOVING_SPEED_MPS,
            "the receiver still reports real speed"
        );
        assert!(s.is_moving(), "a sub-threshold hop is not a stop");
    }

    #[test]
    fn is_moving_false_when_genuinely_stopped_or_inert() {
        // Idle before any run.
        let mut r = Recorder::new();
        assert!(!r.snapshot().is_moving());

        // Standing still with a good fix: the receiver reports ~0 speed, so the
        // phantom-vert protection still closes the gate.
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        assert!(r.snapshot().is_moving());
        r.on_fix(&fix(40.0, -105.0, 0.0, 1));
        assert!(!r.snapshot().is_moving(), "stationary banks nothing");

        // A manual pause zeroes speed even though the last fix was fast.
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        r.on_fix(&fix(40.0005, -105.0, 5.0, 1));
        assert!(r.snapshot().is_moving());
        r.pause(2);
        assert!(!r.snapshot().is_moving(), "manual pause banks nothing");

        // So does a stop.
        r.resume(3);
        r.on_fix(&fix(40.001, -105.0, 5.0, 4));
        assert!(r.snapshot().is_moving());
        r.stop(5);
        assert!(!r.snapshot().is_moving(), "finished banks nothing");
    }

    #[test]
    fn sustained_climb_banks_vert_through_min_move_pauses() {
        // End-to-end regression for the bug the Renode BMP581 model surfaced:
        // gating the vert accumulator on `state == Recording` discarded every
        // metre of a real climb, because the min-move filter alternated the
        // state fix by fix and each Paused sample re-based the deadband
        // reference before the pending gain could cross it.
        use crate::elevation::VertAccumulator;

        let mut r = Recorder::new();
        r.start(0);
        let mut vert = VertAccumulator::new();
        let mut alt = 1600.0f32;
        // 120 s of climbing at ~1.7 m/s over the ground and 0.4 m/s vertical —
        // a 24 % grade power-hike, the mountain_loop fixture's terrain.
        for t in 0..120u32 {
            let lat = 40.0 + f64::from(t) * 0.0000153;
            r.on_fix(&fix(lat, -105.0, 1.7, t));
            alt += 0.4;
            vert.push(alt, r.snapshot().is_moving(), None);
        }
        assert!(
            r.snapshot().state == RecordState::Paused
                || r.snapshot().state == RecordState::Recording,
            "run stayed active"
        );
        // ~48 m of real climb; the deadband holds back at most one 3 m step.
        assert!(
            vert.gain_m() > 44.0,
            "a sustained climb banks its gain (got {})",
            vert.gain_m()
        );
        assert_eq!(vert.loss_m(), 0.0, "a pure climb banks no loss");
    }

    #[test]
    fn stationary_drift_banks_no_vert() {
        // The phantom-vert protection the moving gate exists for: a weather
        // front moves the barometer while the runner sits at an aid station.
        use crate::elevation::VertAccumulator;

        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 5.0, 0));
        let mut vert = VertAccumulator::new();
        let mut alt = 1600.0f32;
        for t in 1..120u32 {
            // Stationary: same position, receiver reports no speed.
            r.on_fix(&fix(40.0, -105.0, 0.0, t));
            alt += 0.4; // 48 m of pure barometric drift
            vert.push(alt, r.snapshot().is_moving(), None);
        }
        assert_eq!(vert.gain_m(), 0.0, "drift while stopped banks nothing");
        assert_eq!(vert.loss_m(), 0.0);
    }

    // ─────────── structured workout ───────────

    fn workout_steps() -> [crate::workout::WorkoutStep; 2] {
        use crate::workout::{WorkoutStep, WorkoutStepKind};
        [
            WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 1,
                rep_total: 2,
                target_distance_m: 100,
                target_duration_s: 0,
                target_pace_s_per_km: 300,
                tolerance_s_per_km: 10,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 2,
                rep_total: 2,
                target_distance_m: 100,
                target_duration_s: 0,
                target_pace_s_per_km: 300,
                tolerance_s_per_km: 10,
            },
        ]
    }

    fn duration_step(duration_s: u16) -> [crate::workout::WorkoutStep; 1] {
        use crate::workout::{WorkoutStep, WorkoutStepKind};
        [WorkoutStep {
            kind: WorkoutStepKind::Steady,
            rep_index: 0,
            rep_total: 0,
            target_distance_m: 0,
            target_duration_s: duration_s,
            target_pace_s_per_km: 300,
            tolerance_s_per_km: 10,
        }]
    }

    #[test]
    fn set_workout_arms_the_page_and_start_announces_the_first_step() {
        let mut r = Recorder::new();
        assert!(r.snapshot().workout.is_none());
        assert_eq!(r.snapshot().pages_mask & Page::Workout.bit(), 0);

        r.set_workout(&workout_steps());
        // Armed while idle: the page previews step 0, nothing announced yet.
        let snap = r.snapshot();
        let w = snap.workout.expect("armed");
        assert_eq!(w.step_index, 0);
        assert_eq!(w.transition_seq, 0);
        assert_ne!(snap.pages_mask & Page::Workout.bit(), 0);

        r.start(0);
        let w = r.snapshot().workout.expect("armed");
        assert_eq!(w.transition_seq, 1, "the gun announces step one");

        r.set_workout(&[]);
        assert!(r.snapshot().workout.is_none(), "empty push disarms");
    }

    #[test]
    fn workout_advances_on_accepted_fix_distance() {
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        // Four ~33 m hops: 100.2 m banked, past the first 100 m rep.
        for (i, t) in [1u32, 11, 21, 31].iter().enumerate() {
            r.on_fix(&fix(40.0 + i as f64 * 0.0003, -105.0, 3.0, *t));
        }
        let w = r.snapshot().workout.expect("armed");
        assert_eq!(w.step_index, 1, "the covered distance advanced the rep");
        assert!(!w.complete);
    }

    #[test]
    fn manual_lap_skips_the_active_workout_step() {
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        r.on_fix(&fix(40.0002, -105.0, 3.0, 8));
        assert_eq!(r.snapshot().workout.unwrap().step_index, 0);
        r.lap(9);
        let snap = r.snapshot();
        assert_eq!(
            snap.workout.unwrap().step_index,
            1,
            "the lap press advances the step (Garmin lap semantics)"
        );
        assert_eq!(snap.lap, 2, "and still closes a lap");
    }

    #[test]
    fn settled_workout_results_drain_in_order_and_once() {
        use crate::workout::StepStatus;
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        assert!(r.pop_settled_workout_result().is_none(), "nothing settled");
        for (i, t) in [1u32, 11, 21, 31].iter().enumerate() {
            r.on_fix(&fix(40.0 + i as f64 * 0.0003, -105.0, 3.0, *t));
        }
        let first = r.pop_settled_workout_result().expect("step 0 settled");
        assert_eq!(first.step_index, 0);
        assert_eq!(first.status, StepStatus::Completed);
        assert!(
            r.pop_settled_workout_result().is_none(),
            "a drained result is consumed exactly once"
        );
        // The in-progress step reads as skipped-so-far for a mid-step stop.
        let in_progress = r.workout_in_progress_result().expect("mid step 1");
        assert_eq!(in_progress.step_index, 1);
        assert_eq!(in_progress.status, StepStatus::Skipped);
        r.lap(35);
        let second = r.pop_settled_workout_result().expect("skip settles");
        assert_eq!(second.step_index, 1);
        assert_eq!(second.status, StepStatus::Skipped);
        assert!(
            r.workout_in_progress_result().is_none(),
            "complete — nothing in progress"
        );
    }

    #[test]
    fn the_workout_drain_resets_with_the_result_trail() {
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        r.lap(2);
        assert!(r.pop_settled_workout_result().is_some());
        // A fresh start re-runs the workout from step 0 with a cleared trail;
        // the drain cursor must follow or it would skip the new run's results.
        r.stop(3);
        r.reset(4);
        r.start(5);
        assert!(r.pop_settled_workout_result().is_none());
        r.on_fix(&fix(40.0, -105.0, 3.0, 6));
        r.lap(7);
        let again = r.pop_settled_workout_result().expect("new trail drains");
        assert_eq!(again.step_index, 0);
        // Re-arming with a DIFFERENT workout replaces the trail: the cursor
        // resets with it (an identical push is a no-op — its own test).
        r.lap(8);
        r.set_workout(&duration_step(30));
        assert!(r.pop_settled_workout_result().is_none());
    }

    #[test]
    fn an_identical_workout_repush_is_a_no_op() {
        // A BLE retry or phone reconnect re-delivering the armed WKT1 frame
        // must not wipe mid-run progress and splice a second trail into the
        // blob — the duplicate-index shape the phone fail-closed drops. The
        // canonical frame CRC (the §356 attribution identity) is the
        // equality; a different workout still re-arms deliberately.
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        r.lap(2);
        assert!(r.pop_settled_workout_result().is_some());
        assert_eq!(r.snapshot().workout.unwrap().step_index, 1);

        r.set_workout(&workout_steps());
        let w = r.snapshot().workout.expect("still armed");
        assert_eq!(w.step_index, 1, "progress survives the re-push");
        assert_eq!(w.transition_seq, 2, "no re-announcement of step one");
        assert!(
            r.pop_settled_workout_result().is_none(),
            "the drain cursor did not rewind — no spliced second trail"
        );

        r.set_workout(&duration_step(30));
        let w = r.snapshot().workout.expect("armed");
        assert_eq!(w.step_index, 0, "a different workout re-arms fresh");
        assert!(w.duration_based);
    }

    #[test]
    fn workout_summary_carries_the_rollup_and_the_arming_crc() {
        use crate::workout::WorkoutAdherence;
        let mut r = Recorder::new();
        assert!(r.workout_summary().is_none(), "no workout, no summary");
        let steps = workout_steps();
        r.set_workout(&steps);
        let summary = r.workout_summary().expect("armed");
        assert_eq!(summary.step_total, 2);
        assert_eq!(summary.rollup, WorkoutAdherence::Partial, "nothing run yet");
        assert_eq!(
            summary.frame_crc,
            crate::workout_store::frame_crc(&steps),
            "the attribution handle is the canonical WKT1 frame CRC"
        );
        assert!(summary.frame_crc.is_some());
        r.start(0);
        for (i, t) in [1u32, 11, 21, 31, 41, 51, 61, 71].iter().enumerate() {
            r.on_fix(&fix(40.0 + i as f64 * 0.0003, -105.0, 3.0, *t));
        }
        assert!(r.snapshot().workout.unwrap().complete);
        assert_eq!(
            r.workout_summary().unwrap().rollup,
            WorkoutAdherence::Completed
        );
        r.set_workout(&[]);
        assert!(r.workout_summary().is_none(), "disarm clears the summary");
    }

    #[test]
    fn a_manual_pause_freezes_the_workout_clock() {
        let mut r = Recorder::new();
        r.set_workout(&duration_step(30));
        r.start(0);
        for t in 1..=10u32 {
            r.tick(t);
        }
        assert_eq!(r.snapshot().workout.unwrap().step_elapsed_s, 10);
        r.pause(10);
        for t in 11..=100u32 {
            r.tick(t);
        }
        let snap = r.snapshot();
        assert_eq!(snap.elapsed_s, 100, "wall clock runs through the pause");
        assert_eq!(
            snap.workout.unwrap().step_elapsed_s,
            10,
            "the workout clock does not"
        );
        r.resume(100);
        for t in 101..=115u32 {
            r.tick(t);
        }
        assert_eq!(r.snapshot().workout.unwrap().step_elapsed_s, 25);
        for t in 116..=121u32 {
            r.tick(t);
        }
        let w = r.snapshot().workout.unwrap();
        assert!(w.complete, "30 workout-clock seconds complete the step");
    }

    #[test]
    fn an_auto_pause_keeps_the_workout_clock_running() {
        // A standing rest inside a timed step is the step working as
        // intended: the sub-threshold fix flips the state to (auto) Paused,
        // and the clock — unlike a manual pause — keeps banking.
        let mut r = Recorder::new();
        r.set_workout(&duration_step(30));
        r.start(0);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        r.on_fix(&fix(40.0, -105.0, 0.0, 2));
        assert_eq!(r.state(), RecordState::Paused);
        assert!(!r.snapshot().manual_paused);
        for t in 3..=35u32 {
            r.tick(t);
        }
        assert!(
            r.snapshot().workout.unwrap().complete,
            "the timed step ran through the auto-pause"
        );
    }

    #[test]
    fn a_restart_rearms_the_pushed_workout_from_step_zero() {
        let mut r = Recorder::new();
        r.set_workout(&workout_steps());
        r.start(0);
        for (i, t) in [1u32, 11, 21, 31].iter().enumerate() {
            r.on_fix(&fix(40.0 + i as f64 * 0.0003, -105.0, 3.0, *t));
        }
        assert_eq!(r.snapshot().workout.unwrap().step_index, 1);
        r.stop(40);
        r.reset(41);
        // The pushed steps are configuration and survive; the next run
        // starts the workout over.
        r.start(50);
        let w = r.snapshot().workout.expect("still armed");
        assert_eq!(w.step_index, 0);
        assert_eq!(w.transition_seq, 1);
        assert!(!w.complete);
    }

    #[test]
    fn a_signal_void_auto_pauses_and_the_next_fix_resumes() {
        // The dropout guard's claim (2): a stretch with no fixes has to read
        // paused. State is otherwise only ever written by a fix arriving, so a
        // void held whatever the last fix left behind — Recording, while
        // distance and moving time sat frozen.
        let mut r = Recorder::new();
        r.start(0);
        for (i, lat) in [40.0, 40.00005, 40.0001].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        assert_eq!(r.state(), RecordState::Recording);

        // The last fix landed at t=2, and the 1 Hz budget is 10 s.
        r.tick(12);
        assert_eq!(
            r.state(),
            RecordState::Recording,
            "paused a fix that is still inside its budget"
        );
        r.tick(13);
        assert_eq!(r.state(), RecordState::Paused);
        assert!(
            !r.snapshot().manual_paused,
            "a lost signal is not a manual pause"
        );

        // ...and the recorder comes back on its own from the next moving fix,
        // exactly as an auto-pause from a slow stretch does.
        r.on_fix(&fix(40.0003, -105.0, 5.0, 14));
        assert_eq!(r.state(), RecordState::Recording);
    }

    #[test]
    fn a_throttled_mode_scales_the_void_budget_instead_of_pausing_between_fixes() {
        // Expedition's 60 s cadence is not a dropout. Sharing one budget with
        // route_position_stale is what keeps these two agreeing.
        let mut r = Recorder::new();
        r.start(0);
        r.set_fix_interval_s(60);
        r.on_fix(&fix(40.0, -105.0, 3.0, 1));
        r.on_fix(&fix(40.0005, -105.0, 3.0, 61));
        assert_eq!(r.state(), RecordState::Recording);
        r.tick(61 + 180);
        assert_eq!(
            r.state(),
            RecordState::Recording,
            "a throttled mode's own cadence read as a signal void"
        );
        r.tick(62 + 180);
        assert_eq!(r.state(), RecordState::Paused);
    }

    #[test]
    fn a_void_never_overrides_the_runners_own_pause_button() {
        // The auto-pause only ever leaves Recording, so it cannot launder a
        // manual pause into an automatic one — resume() must still be the only
        // way back, and the face must keep labelling it manual.
        let mut r = Recorder::new();
        r.start(0);
        for (i, lat) in [40.0, 40.00005, 40.0001].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        r.pause(3);
        r.tick(100);
        assert_eq!(r.state(), RecordState::Paused);
        assert!(
            r.snapshot().manual_paused,
            "the void relabelled the runner's pause as automatic"
        );
        r.resume(101);
        assert_eq!(r.state(), RecordState::Recording);
    }

    #[test]
    fn a_void_pause_still_banks_barometric_vert_for_a_runner_climbing_it() {
        // is_moving() reads current_speed_mps, NOT the state, so the void pause
        // must not zero the speed: ageing it out was weighed and refused
        // because it costs a climber their genuine vert in a canyon. Pinning
        // it here so the auto-pause can't quietly become that refused change.
        let mut r = Recorder::new();
        r.start(0);
        for (i, lat) in [40.0, 40.00005, 40.0001].iter().enumerate() {
            r.on_fix(&fix(*lat, -105.0, 5.0, i as u32));
        }
        r.tick(13);
        assert_eq!(r.state(), RecordState::Paused);
        assert!(
            r.snapshot().is_moving(),
            "the void pause aged out the speed and stopped the vert accumulator"
        );
        // ...which is exactly why the face cannot read the tag off is_moving,
        // and why the snapshot has to carry the reason explicitly.
        assert!(r.snapshot().signal_lost);

        // A real stop still reads as stopped — the manual pause zeroes it.
        r.pause(14);
        assert!(!r.snapshot().is_moving());
        assert!(
            !r.snapshot().signal_lost,
            "a manual pause is never labelled a lost signal"
        );
    }

    #[test]
    fn a_run_with_no_fix_yet_is_not_paused_by_the_void_gate() {
        // Acquisition, and the window just after resume() clears the anchor,
        // are not dropouts — pausing there would fight the runner's button.
        let mut r = Recorder::new();
        r.start(0);
        r.tick(100);
        assert_eq!(r.state(), RecordState::Recording);
    }

    #[test]
    fn an_implausible_gps_altitude_never_reaches_the_elevation_surfaces() {
        // The vert filter already refuses a receiver altitude outside the
        // terrestrial window, but the GAP grade / elevation sparkline / climb
        // segmenter took the raw value. One such sample is permanent: the
        // profile thins by keeping even indices, so sample 0 survives every
        // later thinning and the sparkline's range is wrong for the whole run.
        for bad in [
            f32::INFINITY,
            f32::NEG_INFINITY,
            f32::NAN,
            1e9,
            crate::elevation::GPS_ALT_MAX_M + 1.0,
            crate::elevation::GPS_ALT_MIN_M - 1.0,
        ] {
            let mut r = Recorder::new();
            r.start(0);
            r.on_fix(&fix_alt(40.0, -105.0, 3.0, 1, bad));
            assert_eq!(
                r.snapshot().elev_profile.len,
                0,
                "{bad} was banked as an altitude"
            );
        }
    }

    #[test]
    fn a_plausible_gps_altitude_still_feeds_the_elevation_surfaces() {
        // The guard may only ever drop a value the vert filter already
        // distrusts; the window's own boundaries are inside it.
        for good in [
            crate::elevation::GPS_ALT_MIN_M,
            0.0,
            1624.0,
            crate::elevation::GPS_ALT_MAX_M,
        ] {
            let mut r = Recorder::new();
            r.start(0);
            r.on_fix(&fix_alt(40.0, -105.0, 3.0, 1, good));
            let p = r.snapshot().elev_profile;
            assert_eq!(p.len, 1, "{good} was dropped");
            assert_eq!(p.samples[0], good as i32);
        }
    }

    /// A fix carrying the receiver's UTC clock — what the backyard bell needs
    /// on top of a pushed timezone.
    fn fix_at(lat: f64, lon: f64, speed: f32, t: u32, tod_utc_s: u32) -> Fix {
        Fix {
            time_of_day: Some(tod_utc_s),
            ..fix(lat, lon, speed, t)
        }
    }

    #[test]
    fn the_backyard_page_is_absent_until_the_mode_is_armed() {
        let mut r = Recorder::new();
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        assert!(r.snapshot().backyard.is_none());
        assert_eq!(r.snapshot().pages_mask & Page::Backyard.bit(), 0);
        r.set_backyard_armed(true);
        assert!(r.snapshot().backyard.is_some());
        assert_ne!(r.snapshot().pages_mask & Page::Backyard.bit(), 0);
    }

    #[test]
    fn an_armed_backyard_withholds_the_countdown_until_it_has_both_clocks() {
        // The page is present the moment the mode is armed — `NOT SYNCED` on
        // it is where a runner learns the countdown needs a timezone — but the
        // number is withheld until a timezone AND a receiver clock exist.
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.start(0);
        r.on_fix(&fix(0.0, 0.0, 3.0, 1));
        r.tick(2);
        assert_eq!(r.snapshot().backyard.unwrap().to_bell_s, None);
        // A timezone alone is not enough: nothing has told the watch the hour.
        r.set_tz_offset_min(0);
        r.tick(3);
        assert_eq!(r.snapshot().backyard.unwrap().to_bell_s, None);
        r.on_fix(&fix_at(0.0, 0.001, 3.0, 4, 9 * 3600 + 50 * 60));
        r.tick(5);
        assert_eq!(
            r.snapshot().backyard.unwrap().to_bell_s,
            Some(10 * 60 - 1),
            "the fix clock aged by the uptime since it landed"
        );
    }

    #[test]
    fn the_pushed_timezone_moves_the_bell_not_just_the_display() {
        // 09:50 UTC is 15:20 local in a +05:30 zone — twenty past the hour, not
        // ten to it. A countdown that assumed UTC hours would tell this runner
        // they had ten minutes when they had forty.
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.set_tz_offset_min(330);
        r.start(0);
        r.on_fix(&fix_at(0.0, 0.0, 3.0, 1, 9 * 3600 + 50 * 60));
        r.tick(1);
        assert_eq!(r.snapshot().backyard.unwrap().to_bell_s, Some(40 * 60));
    }

    #[test]
    fn the_bell_takes_the_lap_the_runner_did_not() {
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.set_tz_offset_min(0);
        r.start(0);
        r.on_fix(&fix_at(0.0, 0.0, 3.0, 1, 9 * 3600 + 59 * 60 + 58));
        r.tick(1);
        assert_eq!(r.snapshot().lap, 1);
        assert_eq!(r.snapshot().backyard.unwrap().loops, 0);
        // Two seconds later the hour turns.
        r.tick(3);
        let s = r.snapshot();
        assert_eq!(
            s.lap, 2,
            "the bell closed the loop through the lap machinery"
        );
        assert_eq!(s.backyard.unwrap().loops, 1);
        assert!(s.last_lap.is_some(), "and it banked a split like any lap");
    }

    #[test]
    fn a_corral_press_closes_the_loop_and_stands_the_bell_down() {
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.set_tz_offset_min(0);
        r.start(0);
        r.on_fix(&fix_at(0.0, 0.0, 3.0, 1, 9 * 3600 + 59 * 60 + 50));
        r.tick(1);
        r.lap(2);
        let s = r.snapshot();
        assert_eq!(s.lap, 2);
        assert_eq!(s.backyard.unwrap().loops, 1);
        assert!(s.backyard.unwrap().in_corral, "the press marks the return");
        // The bell must not close a second loop for the same hour.
        r.tick(12);
        let s = r.snapshot();
        assert_eq!(s.lap, 2, "one loop, one lap");
        assert_eq!(s.backyard.unwrap().loops, 1);
        assert!(
            !s.backyard.unwrap().in_corral,
            "and the next loop has been sent off"
        );
    }

    #[test]
    fn the_bell_owns_the_auto_lap_while_armed() {
        // A backyard loop crosses six kilometre lines. Leaving the distance
        // auto-lap on would bury the loop splits the phone reads as the result.
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.start(0);
        for i in 1..=250u32 {
            r.on_fix(&fix(f64::from(i) * 0.00008, 0.0, 9.0, i));
        }
        let s = r.snapshot();
        assert!(s.distance_m > 2_000.0, "{}", s.distance_m);
        assert_eq!(s.lap, 1, "no kilometre lap closed inside the loop");
        // Disarmed, the same walk closes the usual kilometre laps.
        let mut r2 = Recorder::new();
        r2.start(0);
        for i in 1..=250u32 {
            r2.on_fix(&fix(f64::from(i) * 0.00008, 0.0, 9.0, i));
        }
        assert!(r2.snapshot().lap > 1);
    }

    #[test]
    fn the_bell_outranks_a_time_rung_too_and_the_choice_comes_back_disarmed() {
        // § 372 was written against the hard-coded kilometre § 374 replaced, so
        // the arm has to answer for the rungs § 374 added as well. A 5-minute
        // rung is the worse of the two on this store: twelve empty closes per
        // hour-long loop against a 64-record budget, evicting the loop splits
        // that ARE the result. The choice is dormant, not cleared.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Min5);
        r.set_backyard_armed(true);
        r.set_fix_interval_s(60);
        r.start(0);
        for i in 0..=6u32 {
            r.on_fix(&fix(north(f64::from(i) * 60.0), -105.0, 1.0, i * 60));
        }
        let s = r.snapshot();
        assert!(s.moving_s >= 300, "{}", s.moving_s);
        assert_eq!(s.lap, 1, "an armed bell must suppress the time rung too");

        r.set_backyard_armed(false);
        r.on_fix(&fix(north(7.0 * 60.0), -105.0, 1.0, 7 * 60));
        assert_eq!(
            r.snapshot().lap,
            2,
            "disarming restores the runner's own trigger"
        );
    }

    #[test]
    fn an_armed_bell_over_an_off_trigger_leaves_only_the_press_and_the_bell() {
        // `Off` and the bell agree on the automatic axis, so the arm changes
        // nothing there — what it must not do is take the button as well.
        let mut r = Recorder::new();
        r.set_auto_lap(AutoLap::Off);
        r.set_backyard_armed(true);
        r.start(0);
        for i in 1..=250u32 {
            r.on_fix(&fix(f64::from(i) * 0.00008, 0.0, 9.0, i));
        }
        assert_eq!(r.snapshot().lap, 1);
        r.lap(300);
        assert_eq!(r.snapshot().lap, 2, "the corral return still closes a loop");
    }

    #[test]
    fn a_new_run_starts_the_race_over_but_keeps_the_mode() {
        let mut r = Recorder::new();
        r.set_backyard_armed(true);
        r.set_tz_offset_min(0);
        r.start(0);
        r.on_fix(&fix_at(0.0, 0.0, 3.0, 1, 9 * 3600 + 59 * 60 + 50));
        r.tick(1);
        r.lap(2);
        assert_eq!(r.snapshot().backyard.unwrap().loops, 1);
        r.stop(3);
        r.reset(4);
        r.start(5);
        let s = r.snapshot();
        assert!(s.backyard.is_some(), "the mode outlives the run");
        assert_eq!(s.backyard.unwrap().loops, 0);
    }
}
