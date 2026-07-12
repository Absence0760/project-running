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

use crate::cutoff_eta::{next_cutoff_eta, CutoffEta, CutoffLeg};
use crate::distance_bands::{band_for_distance, DistanceBand};
use crate::fitness::RecoveryAdvice;
use crate::fix::Fix;
use crate::fuel_plan::{
    build_fuel_plan, FuelLegInput, FuelPlanOptions, DEFAULT_CARBS_PER_HOUR_G,
    DEFAULT_FLUID_PER_HOUR_ML,
};
use crate::gear_wear::{gear_wear, GearWear};
use crate::grade_adjusted_pace::GapEstimator;
use crate::hr_zones::{
    self, ZoneCutoffs, DEFAULT_MAX_HR_BPM, MAX_HR_PLAUSIBLE_MAX, MAX_HR_PLAUSIBLE_MIN, ZONE_COUNT,
};
use crate::pace_segments::{pace_bucket_for_speed, ActivityKind};
use crate::pacer::{Pacer, PacerStatus};
use crate::race_predictor::{predict_race_ladder, Effort, RacePrediction};
use crate::roadbook::CutoffStatus;
use crate::training_load::{compute_stress, HrPrefs, RunForLoad};
use crate::training_paces::{paces_from_goal_pace, TrainingGender, TrainingPaces};

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

/// A segment slower than this counts its distance but not its time toward
/// moving time — the `minSpeedMps` of `run_stats.movingTimeOf`, which replaced
/// the removed live auto-pause as the way moving time is derived.
pub const MIN_MOVING_SPEED_MPS: f64 = 0.5;

/// Metres per degree of latitude for the equirectangular projection, matching
/// the constant in `run_recorder._distanceToSegmentMetres`.
pub const METRES_PER_DEGREE_LAT: f64 = 111_320.0;

/// Auto-lap boundary: the current lap closes on the first accepted fix that
/// carries it past this distance. The tier-1 default mirrors the classic
/// 1 km auto-lap; a manual lap resets the countdown, so the boundary is
/// always measured from the current lap's start, not from multiples of the
/// run total.
pub const AUTO_LAP_DISTANCE_M: f64 = 1000.0;

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

/// Plausible synced VO2 max / VDOT band: 20 (very unfit) to 90 (the same
/// physiological ceiling `fitness::vdot_from_run` rejects above). Guards a
/// corrupt fitness push from showing a fake number.
pub const FITNESS_VO2_PLAUSIBLE_MIN: f64 = 20.0;
pub const FITNESS_VO2_PLAUSIBLE_MAX: f64 = 90.0;

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

/// The loaded course's elevation profile summary ([`crate::route_elevation`]):
/// total gain / loss and the point count the profile was sampled to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RouteElevView {
    pub gain_m: u16,
    pub loss_m: u16,
    pub points: u16,
}

/// The race-day countdown + goal-feasibility verdict ([`crate::race_day`]):
/// signed days until the race (negative once past) and `feasible` 0 behind /
/// 1 on-track / 2 ahead.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RaceDayView {
    pub days_until: i16,
    pub feasible: u8,
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
    /// 1-based number of the lap in progress; 0 before a run starts.
    pub lap: u16,
    /// Ground covered within the current lap so far.
    pub lap_distance_m: f64,
    /// Wall-clock seconds since the current lap started.
    pub lap_elapsed_s: u32,
    /// The most recently completed lap, if any — the face's "last lap split".
    pub last_lap: Option<Lap>,
    /// The virtual-partner delta vs a configured goal (see [`crate::pacer`]);
    /// `None` while no goal is set or no run is under way — the pacer page
    /// shows an honest inactive state then, never a fake "on pace at zero".
    pub pacer: Option<PacerStatus>,
    /// The zone ladder in force for this run — carried so the face can place
    /// the live BPM in a zone without owning a second copy of the max-HR
    /// configuration.
    pub zone_cutoffs: ZoneCutoffs,
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
    /// The synced training-readiness score, or `None` until pushed.
    pub readiness: Option<ReadinessView>,
    /// The synced primary-goal progress, or `None` until pushed.
    pub goals: Option<GoalsView>,
    /// The next turn on the loaded course, or `None` until pushed.
    pub turn_cue: Option<TurnCueView>,
    /// The simplified-course summary, or `None` until pushed.
    pub route_simplify: Option<RouteSimplifyView>,
    /// The auto-segment-effort match counts, or `None` until pushed.
    pub auto_effort: Option<AutoEffortView>,
    /// The loaded course's elevation summary, or `None` until pushed.
    pub route_elev: Option<RouteElevView>,
    /// The race-day countdown + feasibility, or `None` until pushed.
    pub race_day: Option<RaceDayView>,
    /// The tier-1 flash slot's per-run point cap
    /// ([`crate::flash_store::MAX_POINTS_PER_RUN`]) has been reached: further GPS
    /// points are dropped from the stored track while the totals keep accruing.
    /// Lets the face surface the truncation on the wrist instead of it being a
    /// cable-only `warn!`.
    pub track_full: bool,
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

pub struct Recorder {
    state: RecordState,
    /// Distinguishes an explicit `pause()` (resumed only by `resume()`) from a
    /// speed-derived auto-pause (resumed by the next moving fix).
    manual_paused: bool,
    start_s: u32,
    now_s: u32,
    moving_s: u32,
    distance_m: f64,
    current_speed_mps: f32,
    /// Last fix accepted for distance — the anchor the next segment measures
    /// from. Cleared on start / resume so a pause gap is never one huge hop.
    last: Option<Fix>,
    /// Whether the most recent [`on_fix`](Recorder::on_fix) call adopted the
    /// fix as a new anchor (the run's first fix or an accepted move). Read-only
    /// signal for the app's flash run-store; see [`last_fix_stored`](Recorder::last_fix_stored).
    last_fix_stored: bool,
    /// Count of anchor-adopting fixes this run — the points the app's flash
    /// run-store writes. Once it reaches [`crate::flash_store::MAX_POINTS_PER_RUN`]
    /// the tier-1 slot is full and further points are silently dropped, so the
    /// `Snapshot`'s `track_full` flag surfaces the truncation on the wrist rather
    /// than leaving it a cable-only `warn!`.
    stored_points: u32,
    /// 1-based number of the lap in progress; 0 while idle.
    lap_index: u16,
    /// Run totals at the current lap's start — the anchors lap-relative
    /// distance / elapsed / moving are measured from.
    lap_start_distance_m: f64,
    lap_start_elapsed_s: u32,
    lap_start_moving_s: u32,
    last_lap: Option<Lap>,
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
    /// Per-zone moving-time accumulators, reset on [`start`](Recorder::start).
    zone_time_s: [u32; ZONE_COUNT],
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
    readiness: Option<ReadinessView>,
    goals: Option<GoalsView>,
    turn_cue: Option<TurnCueView>,
    route_simplify: Option<RouteSimplifyView>,
    auto_effort: Option<AutoEffortView>,
    route_elev: Option<RouteElevView>,
    race_day: Option<RaceDayView>,
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
            distance_m: 0.0,
            current_speed_mps: 0.0,
            last: None,
            last_fix_stored: false,
            stored_points: 0,
            lap_index: 0,
            lap_start_distance_m: 0.0,
            lap_start_elapsed_s: 0,
            lap_start_moving_s: 0,
            last_lap: None,
            gap: GapEstimator::new(),
            baro_alt_m: None,
            hr_bpm: None,
            zone_cutoffs: hr_zones::zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            zone_time_s: [0; ZONE_COUNT],
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
            readiness: None,
            goals: None,
            turn_cue: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            race_day: None,
        }
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
    /// after a 30 s signal gap is still rejected as corrupt, exactly as today.
    pub fn set_fix_interval_s(&mut self, interval_s: u32) {
        self.fix_interval_s = interval_s.max(1);
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

    /// Latest heart-rate estimate for the zone accumulators. `None` clears it
    /// (the detector lost the pulse), so a stale BPM never keeps banking zone
    /// time after the sensor goes quiet.
    pub fn set_hr(&mut self, bpm: Option<u16>) {
        self.hr_bpm = bpm;
    }

    /// Rebuild the zone ladder from a configured max HR — the tier-1 hook a
    /// future settings sync drives; nothing on-device sets it yet. Values
    /// outside the app's plausibility window (80..=240, the same guard web's
    /// `defaultZoneCutoffs` applies to an explicit override) are ignored so
    /// garbage can't flatten the ladder. Zone time already banked is not
    /// re-bucketed — the ladder applies from now on.
    pub fn set_max_hr(&mut self, max_hr_bpm: u16) {
        if (MAX_HR_PLAUSIBLE_MIN..=MAX_HR_PLAUSIBLE_MAX).contains(&max_hr_bpm) {
            self.zone_cutoffs = hr_zones::zone_cutoffs_from_max_hr(max_hr_bpm);
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
    /// Fuel pages inactive.
    pub fn set_roadbook(&mut self, legs: &[RoadbookCheckpoint]) {
        self.roadbook_legs.clear();
        for leg in legs.iter().take(MAX_PUSHED_LEGS) {
            let _ = self.roadbook_legs.push(*leg);
        }
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

    pub fn set_route_simplify(&mut self, view: Option<RouteSimplifyView>) {
        self.route_simplify = view;
    }

    pub fn set_auto_effort(&mut self, view: Option<AutoEffortView>) {
        self.auto_effort = view;
    }

    pub fn set_route_elev(&mut self, view: Option<RouteElevView>) {
        self.route_elev = view;
    }

    /// The feasibility verdict is clamped to 0..=2 so a corrupt push can't render
    /// an unknown verdict label.
    pub fn set_race_day(&mut self, view: Option<RaceDayView>) {
        self.race_day = view.map(|v| RaceDayView {
            days_until: v.days_until,
            feasible: v.feasible.min(2),
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
        self.distance_m = 0.0;
        self.current_speed_mps = 0.0;
        self.last = None;
        self.stored_points = 0;
        self.lap_index = 1;
        self.lap_start_distance_m = 0.0;
        self.lap_start_elapsed_s = 0;
        self.lap_start_moving_s = 0;
        self.last_lap = None;
        self.zone_time_s = [0; ZONE_COUNT];
        self.pace_bucket_m = [0.0; PACE_BUCKET_COUNT];
        // Fresh grade anchors for the new run; the sticky baro altitude and HR
        // stay — each is still the current reading, not run state. The pacer
        // splits the same way: its finish latch is run state and clears, the
        // configured goal is settings and stays.
        self.gap.reset();
        self.pacer.reset();
        self.elev_profile.reset();
    }

    /// Manually pause. Valid while recording or auto-paused; inert once idle,
    /// finished, or already manually paused.
    pub fn pause(&mut self, now_s: u32) {
        let active = self.state == RecordState::Recording
            || (self.state == RecordState::Paused && !self.manual_paused);
        if !active {
            return;
        }
        self.now_s = now_s.max(self.now_s);
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
        self.now_s = now_s.max(self.now_s);
        self.state = RecordState::Recording;
        self.manual_paused = false;
        self.last = None;
    }

    /// Close the current lap by hand (the Lap button). Valid whenever a run is
    /// in progress — recording, auto-paused, or manually paused (a lap taken
    /// while paused closes at the frozen totals); inert once idle or finished.
    /// Also resets the auto-lap countdown: the next 1 km boundary is measured
    /// from here, not from multiples of the run total.
    pub fn lap(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.now_s = now_s.max(self.now_s);
        self.close_lap();
    }

    /// Finalise the run. Inert once idle or already finished; afterward fixes
    /// and ticks no longer move any total. The lap in progress stays open — it
    /// shows on the face as the (frozen) current lap, and laps are RAM display
    /// state only, so there is no record to finalise it into.
    pub fn stop(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.now_s = now_s.max(self.now_s);
        self.state = RecordState::Finished;
        self.current_speed_mps = 0.0;
    }

    /// Advance the wall clock without a new fix (the mobile recorder's 1 Hz
    /// tick). Elapsed grows through paused states; idle and finished are inert.
    pub fn tick(&mut self, now_s: u32) {
        if matches!(self.state, RecordState::Idle | RecordState::Finished) {
            return;
        }
        self.now_s = now_s.max(self.now_s);
    }

    /// Consume one GPS fix, using its `uptime_s` as the current time. Ignored
    /// unless recording or auto-paused — a manual pause gates fixes out
    /// entirely, mirroring `run_recorder`'s `if (_paused) return`.
    pub fn on_fix(&mut self, fix: &Fix) {
        self.last_fix_stored = false;
        match self.state {
            RecordState::Recording => {}
            RecordState::Paused if !self.manual_paused => {}
            _ => return,
        }
        self.now_s = fix.uptime_s.max(self.now_s);

        let last = match self.last {
            Some(l) => l,
            None => {
                self.last = Some(*fix);
                self.current_speed_mps = fix.speed_mps.max(0.0);
                self.last_fix_stored = true;
                self.stored_points = self.stored_points.saturating_add(1);
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
            // the HR in force for the segment — no reading, no accrual.
            if let Some(bpm) = self.hr_bpm {
                let zone = hr_zones::zone_for_bpm(bpm, &self.zone_cutoffs);
                self.zone_time_s[(zone - 1) as usize] += dt;
            }
            self.state = RecordState::Recording;
        } else {
            self.state = RecordState::Paused;
        }
        self.last = Some(*fix);
        self.last_fix_stored = true;
        self.stored_points = self.stored_points.saturating_add(1);
        self.feed_gap(fix);
        // Distance only moves here, so this is the one place the partner's
        // finish crossing can happen.
        self.pacer.on_distance(self.distance_m, self.elapsed_s());

        // Auto-lap: the fix that carries the current lap past the boundary
        // closes it. The overshoot stays in the closed lap and the next lap
        // starts at the closing fix's totals, so however long an accepted
        // segment is (a throttled GNSS mode allows multi-hundred-metre legs),
        // at most one lap closes per fix and no distance is lost.
        if self.distance_m - self.lap_start_distance_m >= AUTO_LAP_DISTANCE_M {
            self.close_lap();
        }
    }

    /// Advance the live-GAP grade estimate with an anchor-adopting fix: the
    /// run total so far plus the baro-preferred altitude (falling back to the
    /// fix's GPS altitude, mirroring the flash store's point stamping). No
    /// altitude at all leaves the grade untouched, exactly like the Connect IQ
    /// field's `updateGrade` early-out.
    fn feed_gap(&mut self, fix: &Fix) {
        if let Some(alt) = self.baro_alt_m.or(fix.alt_m.map(f64::from)) {
            self.gap.on_sample(self.distance_m, alt);
            self.elev_profile.push(self.distance_m, alt);
        }
    }

    /// Record the lap in progress as [`last_lap`](Snapshot::last_lap) and
    /// anchor the next one at the current totals. Shared by the auto-lap
    /// boundary and the manual [`lap`](Recorder::lap).
    fn close_lap(&mut self) {
        let elapsed = self.elapsed_s();
        self.last_lap = Some(Lap {
            index: self.lap_index,
            distance_m: self.distance_m - self.lap_start_distance_m,
            elapsed_s: elapsed.saturating_sub(self.lap_start_elapsed_s),
            moving_s: self.moving_s - self.lap_start_moving_s,
        });
        self.lap_index = self.lap_index.saturating_add(1);
        self.lap_start_distance_m = self.distance_m;
        self.lap_start_elapsed_s = elapsed;
        self.lap_start_moving_s = self.moving_s;
    }

    fn elapsed_s(&self) -> u32 {
        self.now_s.saturating_sub(self.start_s)
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            state: self.state,
            distance_m: self.distance_m,
            elapsed_s: self.elapsed_s(),
            moving_s: self.moving_s,
            current_speed_mps: self.current_speed_mps,
            avg_pace_s_per_km: self.avg_pace(),
            current_pace_s_per_km: self.current_pace(),
            gap_s_per_km: self.gap.gap_s_per_km(self.current_speed_mps as f64),
            lap: self.lap_index,
            lap_distance_m: self.distance_m - self.lap_start_distance_m,
            lap_elapsed_s: self.elapsed_s().saturating_sub(self.lap_start_elapsed_s),
            last_lap: self.last_lap,
            pacer: if self.state == RecordState::Idle {
                None
            } else {
                self.pacer.status(self.distance_m, self.elapsed_s())
            },
            zone_cutoffs: self.zone_cutoffs,
            zone_time_s: self.zone_time_s,
            cutoff: self.cutoff_snapshot(),
            race_prediction: self.race_prediction_snapshot(),
            pace_bucket_m: self.pace_bucket_m,
            training_stress: self.training_stress_snapshot(),
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
            readiness: self.readiness,
            goals: self.goals,
            turn_cue: self.turn_cue,
            route_simplify: self.route_simplify,
            auto_effort: self.auto_effort,
            route_elev: self.route_elev,
            race_day: self.race_day,
            track_full: self.stored_points >= crate::flash_store::MAX_POINTS_PER_RUN,
        }
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

    /// This run's single-run training-load stress, or `None` while idle / before
    /// any distance. Distance-model by default (the watch tracks no average HR);
    /// a future HR-threshold sync would upgrade it to TRIMP.
    fn training_stress_snapshot(&self) -> Option<f32> {
        if self.state == RecordState::Idle || self.distance_m < 1.0 {
            return None;
        }
        let run = RunForLoad {
            day: 0,
            duration_s: self.moving_s,
            distance_m: self.distance_m,
            avg_bpm: None,
        };
        Some(compute_stress(&run, &HrPrefs::default(), None) as f32)
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
        let plan = build_fuel_plan(
            &inputs,
            FuelPlanOptions {
                carbs_per_hour_g: DEFAULT_CARBS_PER_HOUR_G,
                fluid_per_hour_ml: DEFAULT_FLUID_PER_HOUR_ML,
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

    /// The live next-cutoff ETA, or `None` when idle or no cutoff legs are
    /// loaded. Projects from the fed route position + the whole-run moving pace;
    /// a missing or stale route position (lost signal) drops the projected time
    /// to `Unknown` — see [`crate::cutoff_eta`].
    fn cutoff_snapshot(&self) -> Option<CutoffEta> {
        if self.state == RecordState::Idle || self.cutoff_legs.is_empty() {
            return None;
        }
        // Stale once the fed position ages past a few fix intervals (scaled to
        // the GNSS mode's cadence, so Expedition's 60 s gaps are not "stale").
        let stale_budget_s = self.fix_interval_s.saturating_mul(3).max(10);
        let stale = self.route_along_m.is_none()
            || self.now_s.saturating_sub(self.route_along_at_s) > stale_budget_s;
        Some(next_cutoff_eta(
            self.route_along_m.unwrap_or(0.0),
            self.elapsed_s(),
            self.avg_pace().map(f64::from),
            stale,
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
    fn track_full_flips_when_the_flash_point_cap_is_reached() {
        use crate::flash_store::MAX_POINTS_PER_RUN;
        let mut r = Recorder::new();
        r.start(0);
        assert!(!r.snapshot().track_full, "empty run is not full");

        // The first fix seeds the anchor (1 stored point); each subsequent
        // accepted move (~5.5 m at 1 s → 5.5 m/s, over the 3 m threshold and
        // under the 10 m/s ceiling) adds one. Feed exactly the cap.
        let mut lat = 40.0;
        for i in 0..MAX_POINTS_PER_RUN {
            r.on_fix(&fix(lat, -105.0, 5.0, i));
            assert!(r.last_fix_stored(), "fix {i} should be an accepted anchor");
            if i + 1 < MAX_POINTS_PER_RUN {
                assert!(!r.snapshot().track_full, "not full yet at {}", i + 1);
            }
            lat += 0.00005;
        }
        assert!(
            r.snapshot().track_full,
            "the {MAX_POINTS_PER_RUN}-point tier-1 slot is now full"
        );

        // A fresh run clears it — the flag is per-run, not sticky across starts.
        let mut r2 = Recorder::new();
        r2.start(0);
        r2.on_fix(&fix(40.0, -105.0, 5.0, 0));
        assert!(!r2.snapshot().track_full);
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
        // Single-run stress is the distance model (the watch tracks no avg HR).
        let stress = snap.training_stress.expect("stress once distance accrues");
        assert!((stress - (snap.distance_m as f32 / 1000.0) * 10.0).abs() < 1.0);
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

        // Clearing works.
        r.set_recap(None);
        assert!(r.snapshot().recap.is_none());
    }
}
