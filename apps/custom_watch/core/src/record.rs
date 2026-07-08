//! Recording state machine — a host-testable port of the Dart `run_recorder`.
//!
//! [`Recorder`] reduces control commands (start / pause / resume / stop), a
//! stream of [`Fix`] samples, and a wall clock into the live run totals a watch
//! face reads: total distance, elapsed vs moving time, current speed, and
//! average / current pace. The point-acceptance filter (min-distance,
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

/// Movement gate: a segment shorter than this is GPS jitter while effectively
/// stopped, not travel. `max(distanceFilterMetres = 3, minMovementMetres = 2)`
/// in `run_recorder`.
pub const TRACK_THRESHOLD_M: f64 = 3.0;

/// A single hop longer than this is a corrupt fix, never real travel — the
/// `delta < 100` ceiling in `run_recorder`.
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecordState {
    Idle,
    Recording,
    Paused,
    Finished,
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
        }
    }

    pub fn state(&self) -> RecordState {
        self.state
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

    /// Finalise the run. Inert once idle or already finished; afterward fixes
    /// and ticks no longer move any total.
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
                return;
            }
        };

        let dt = fix.uptime_s.saturating_sub(last.uptime_s);
        let delta = segment_distance_m(&last, fix);

        // Corrupt fix: a shared/backwards timestamp, an implied speed past the
        // ceiling, or a jump too long to be real. Drop it and keep the anchor
        // so the next good fix measures from the last trusted position.
        if dt == 0 || delta >= MAX_JUMP_M || delta / dt as f64 > MAX_SPEED_MPS {
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
            self.state = RecordState::Recording;
        } else {
            self.state = RecordState::Paused;
        }
        self.last = Some(*fix);
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            state: self.state,
            distance_m: self.distance_m,
            elapsed_s: self.now_s.saturating_sub(self.start_s),
            moving_s: self.moving_s,
            current_speed_mps: self.current_speed_mps,
            avg_pace_s_per_km: self.avg_pace(),
            current_pace_s_per_km: self.current_pace(),
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
