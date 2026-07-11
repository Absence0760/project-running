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

use crate::fix::Fix;
use crate::grade_adjusted_pace::GapEstimator;
use crate::hr_zones::{
    self, ZoneCutoffs, DEFAULT_MAX_HR_BPM, MAX_HR_PLAUSIBLE_MAX, MAX_HR_PLAUSIBLE_MIN, ZONE_COUNT,
};
use crate::pacer::{Pacer, PacerStatus};

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
        self.lap_index = 1;
        self.lap_start_distance_m = 0.0;
        self.lap_start_elapsed_s = 0;
        self.lap_start_moving_s = 0;
        self.last_lap = None;
        self.zone_time_s = [0; ZONE_COUNT];
        // Fresh grade anchors for the new run; the sticky baro altitude and HR
        // stay — each is still the current reading, not run state. The pacer
        // splits the same way: its finish latch is run state and clears, the
        // configured goal is settings and stays.
        self.gap.reset();
        self.pacer.reset();
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
        }
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
}
