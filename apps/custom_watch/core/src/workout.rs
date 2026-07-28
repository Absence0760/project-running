//! Structured-workout execution — the on-watch port of the mobile
//! `run_recorder` `WorkoutRunner` (the shipped reference state machine,
//! `packages/run_recorder/lib/src/workout_runner.dart`), plus the `WKT1`
//! phone→watch push frame that delivers the step list.
//!
//! The phone pushes the **expanded** flat step sequence — its
//! `expandWorkoutSteps` already turns a plan's blocks into ordered steps, and
//! the watch has no plan to expand — the same pushed-pre-built model as the
//! roadbook. Each step carries an end condition (distance in metres OR a
//! duration in seconds; duration wins when both are present, mirroring
//! `WorkoutStep.isDurationBased`), an optional target pace + tolerance, and a
//! kind + rep labels the face renders as text (identifiers on the wire, never
//! strings — the `GuidedRunId` lesson inverted: these labels are pure
//! structure, so the numbers travel and the words stay in the firmware).
//!
//! What is deliberately NOT ported (decisions §354): `skipStep` / `rewindStep`
//! / `abandon` (phone-screen affordances; the §350 press grammar has no spare
//! key and a mis-tap that skips a rep is worse than no skip), the
//! `WorkoutStepResult` trail (the planned-vs-actual review is the phone's
//! surface — the flash run store is unchanged), and the cue *events*
//! (halfway / last-50 m / pace-drift): tier 1 has no TTS and no haptics, so
//! the Workout glance page's live rows ARE the cue surface. The advance
//! mathematics — anchors, the overshoot-carrying multi-step advance loop, the
//! pace-adherence bands — are ported faithfully, so watch and phone cannot
//! disagree on which step a runner is in.

use heapless::Vec;

use crate::run_store::crc32;

/// Most steps one pushed workout can carry. Ten work/recover pairs plus
/// warmup, steady blocks, and cooldown fit comfortably; a longer session must
/// be phone-trimmed. Wire + RAM budget: 32 × [`WORKOUT_STEP_LEN`] ≈ 384 B.
pub const MAX_WORKOUT_STEPS: usize = 32;

pub const WORKOUT_MAGIC: [u8; 4] = *b"WKT1";

/// Version 1 (2026-07-28). Carries a CRC32 trailer from birth — the `CRS1`
/// lesson (§335) applied in advance rather than retrofitted: like a course,
/// a step list has weak plausibility guards (most byte patterns are a legal
/// step), so the checksum is load-bearing from the first shipped frame.
pub const WORKOUT_FORMAT_VERSION: u8 = 1;

/// `magic(4) | version(1) | count(1)`.
pub const WORKOUT_HEADER_LEN: usize = 6;

/// `kind(1) | rep_index(1) | rep_total(1) | tolerance_s_per_km(1) |
/// target_distance_m(4, u32 LE) | target_duration_s(2, u16 LE) |
/// target_pace_s_per_km(2, u16 LE)`.
pub const WORKOUT_STEP_LEN: usize = 12;

const WORKOUT_CRC_LEN: usize = 4;

/// Whole-frame length for `count` steps.
pub const fn workout_frame_len(count: usize) -> usize {
    WORKOUT_HEADER_LEN + count * WORKOUT_STEP_LEN + WORKOUT_CRC_LEN
}

/// Largest legal frame — the assembler's buffer size.
pub const MAX_WORKOUT_FRAME_LEN: usize = workout_frame_len(MAX_WORKOUT_STEPS);

/// The step kinds, mirroring the mobile `WorkoutStepKind` enum — the wire
/// byte is the declaration index on BOTH sides, pinned by test.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WorkoutStepKind {
    Warmup,
    Rep,
    Recovery,
    Walk,
    Steady,
    Cooldown,
}

impl WorkoutStepKind {
    pub const fn from_byte(b: u8) -> Option<Self> {
        match b {
            0 => Some(Self::Warmup),
            1 => Some(Self::Rep),
            2 => Some(Self::Recovery),
            3 => Some(Self::Walk),
            4 => Some(Self::Steady),
            5 => Some(Self::Cooldown),
            _ => None,
        }
    }

    pub const fn to_byte(self) -> u8 {
        match self {
            Self::Warmup => 0,
            Self::Rep => 1,
            Self::Recovery => 2,
            Self::Walk => 3,
            Self::Steady => 4,
            Self::Cooldown => 5,
        }
    }

    /// The face's row label for this kind.
    pub const fn label(self) -> &'static str {
        match self {
            Self::Warmup => "WARMUP",
            Self::Rep => "REP",
            Self::Recovery => "RECOVER",
            Self::Walk => "WALK",
            Self::Steady => "STEADY",
            Self::Cooldown => "COOL",
        }
    }
}

/// One expanded step. `target_duration_s > 0` puts the step on the time axis
/// (the mobile `isDurationBased` rule); otherwise `target_distance_m` is the
/// end condition. `rep_index`/`rep_total` are 1-based, 0 = unlabelled.
/// `target_pace_s_per_km == 0` means no pace target (warmups, recoveries).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WorkoutStep {
    pub kind: WorkoutStepKind,
    pub rep_index: u8,
    pub rep_total: u8,
    pub tolerance_s_per_km: u8,
    pub target_distance_m: u32,
    pub target_duration_s: u16,
    pub target_pace_s_per_km: u16,
}

impl WorkoutStep {
    pub const fn duration_based(&self) -> bool {
        self.target_duration_s > 0
    }

    /// A step must end: no end condition means the runner is parked on it
    /// forever, so such a step fails the whole list at the setter.
    pub const fn has_end_condition(&self) -> bool {
        self.target_duration_s > 0 || self.target_distance_m > 0
    }
}

/// The pace-adherence verdict, mirroring the mobile bands: inside the
/// tolerance, inside 2× it, or way off.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PaceAdherence {
    OnPace,
    Ahead,
    Behind,
    WayAhead,
    WayBehind,
}

/// What the Workout glance page renders — one step's live state.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WorkoutView {
    /// 0-based index of the active step (== `total` once done).
    pub step_index: u8,
    pub total: u8,
    pub kind: WorkoutStepKind,
    pub rep_index: u8,
    pub rep_total: u8,
    /// The active axis: remaining seconds for a duration step, remaining
    /// metres otherwise (the other reads 0).
    pub duration_based: bool,
    pub remaining_m: u32,
    pub remaining_s: u32,
    pub target_pace_s_per_km: u16,
    /// The step's own average pace so far, `None` under 5 m / 1 s of step.
    pub step_pace_s_per_km: Option<u16>,
    pub adherence: PaceAdherence,
    /// Step progress in parts-per-thousand along its own end condition.
    pub progress_permille: u16,
    /// The next step's kind, `None` on the last.
    pub next_kind: Option<WorkoutStepKind>,
    pub done: bool,
}

/// The runner: anchors the active step's start on the run's distance +
/// elapsed clocks and advances when the step's end condition is met, carrying
/// overshoot forward exactly like the mobile `_advance(carryOvershoot: true)`
/// loop — a single fix after a GPS gap can complete several short steps, and
/// re-anchoring to the current totals would silently stretch the next step by
/// the discarded overshoot.
pub struct WorkoutRunner {
    steps: Vec<WorkoutStep, MAX_WORKOUT_STEPS>,
    idx: usize,
    started: bool,
    step_start_distance_m: f64,
    step_start_elapsed_s: f64,
    last_distance_m: f64,
    last_elapsed_s: u32,
}

impl WorkoutRunner {
    pub fn new(steps: &[WorkoutStep]) -> Self {
        let mut v = Vec::new();
        for s in steps.iter().take(MAX_WORKOUT_STEPS) {
            let _ = v.push(*s);
        }
        Self {
            steps: v,
            idx: 0,
            started: false,
            step_start_distance_m: 0.0,
            step_start_elapsed_s: 0.0,
            last_distance_m: 0.0,
            last_elapsed_s: 0,
        }
    }

    pub fn is_complete(&self) -> bool {
        self.idx >= self.steps.len()
    }

    /// Reset to step 0 with no anchors — a new run starts the workout over.
    pub fn reset(&mut self) {
        self.idx = 0;
        self.started = false;
        self.step_start_distance_m = 0.0;
        self.step_start_elapsed_s = 0.0;
        self.last_distance_m = 0.0;
        self.last_elapsed_s = 0;
    }

    fn step_distance_m(&self) -> f64 {
        (self.last_distance_m - self.step_start_distance_m).max(0.0)
    }

    fn step_elapsed_s(&self) -> f64 {
        (f64::from(self.last_elapsed_s) - self.step_start_elapsed_s).max(0.0)
    }

    /// Drive with the run's totals (the recorder's distance + elapsed clock —
    /// the same snapshot fields the mobile runner reads). First call anchors
    /// step 0; each call advances past every step whose end condition the
    /// totals now clear.
    pub fn on_progress(&mut self, distance_m: f64, elapsed_s: u32) {
        if self.steps.is_empty() {
            return;
        }
        self.last_distance_m = distance_m;
        self.last_elapsed_s = elapsed_s;
        if !self.started {
            self.started = true;
            self.step_start_distance_m = distance_m;
            self.step_start_elapsed_s = f64::from(elapsed_s);
        }
        while !self.is_complete() {
            let cur = self.steps[self.idx];
            let hit = if cur.duration_based() {
                self.step_elapsed_s() >= f64::from(cur.target_duration_s)
            } else {
                self.step_distance_m() >= f64::from(cur.target_distance_m)
            };
            if !hit {
                break;
            }
            self.advance_carrying_overshoot(cur);
        }
    }

    /// The mobile `_advance(carryOvershoot: true)`: consume exactly the
    /// step's target on its own axis, apportion the other axis by ratio, and
    /// move the anchors by the consumed amounts — never to the current
    /// totals, so the overshoot funds the next step.
    fn advance_carrying_overshoot(&mut self, step: WorkoutStep) {
        let covered_distance = self.step_distance_m();
        let covered_elapsed = self.step_elapsed_s();
        let (consumed_distance, consumed_elapsed) = if step.duration_based() {
            let consumed_elapsed = f64::from(step.target_duration_s);
            let ratio = if covered_elapsed > 0.0 {
                (consumed_elapsed / covered_elapsed).clamp(0.0, 1.0)
            } else {
                1.0
            };
            (covered_distance * ratio, consumed_elapsed)
        } else {
            let consumed_distance = f64::from(step.target_distance_m);
            let ratio = if covered_distance > 0.0 {
                (consumed_distance / covered_distance).clamp(0.0, 1.0)
            } else {
                1.0
            };
            (consumed_distance, covered_elapsed * ratio)
        };
        self.idx += 1;
        self.step_start_distance_m += consumed_distance;
        self.step_start_elapsed_s += consumed_elapsed;
    }

    fn step_pace_s_per_km(&self) -> Option<u16> {
        let d = self.step_distance_m();
        let el = self.step_elapsed_s();
        if d < 5.0 || el < 1.0 {
            return None;
        }
        let pace = el / (d / 1000.0);
        if !pace.is_finite() || pace < 0.0 {
            return None;
        }
        Some(libm::round(pace).min(f64::from(u16::MAX)) as u16)
    }

    fn adherence(&self, step: &WorkoutStep) -> PaceAdherence {
        if step.target_pace_s_per_km == 0 {
            return PaceAdherence::OnPace;
        }
        let Some(actual) = self.step_pace_s_per_km() else {
            return PaceAdherence::OnPace;
        };
        let diff = i32::from(actual) - i32::from(step.target_pace_s_per_km);
        let tol = i32::from(step.tolerance_s_per_km);
        if diff.abs() <= tol {
            PaceAdherence::OnPace
        } else if diff.abs() <= tol * 2 {
            if diff > 0 {
                PaceAdherence::Behind
            } else {
                PaceAdherence::Ahead
            }
        } else if diff > 0 {
            PaceAdherence::WayBehind
        } else {
            PaceAdherence::WayAhead
        }
    }

    /// The Workout page's live view, `None` only when no steps are loaded.
    pub fn view(&self) -> Option<WorkoutView> {
        let total = self.steps.len();
        if total == 0 {
            return None;
        }
        if self.is_complete() {
            let last = self.steps[total - 1];
            return Some(WorkoutView {
                step_index: total as u8,
                total: total as u8,
                kind: last.kind,
                rep_index: last.rep_index,
                rep_total: last.rep_total,
                duration_based: last.duration_based(),
                remaining_m: 0,
                remaining_s: 0,
                target_pace_s_per_km: 0,
                step_pace_s_per_km: None,
                adherence: PaceAdherence::OnPace,
                progress_permille: 1000,
                next_kind: None,
                done: true,
            });
        }
        let step = self.steps[self.idx];
        let (remaining_m, remaining_s, progress) = if step.duration_based() {
            let covered = self.step_elapsed_s();
            let target = f64::from(step.target_duration_s);
            let rem = (target - covered).max(0.0);
            (0, rem as u32, (covered / target).clamp(0.0, 1.0))
        } else {
            let covered = self.step_distance_m();
            let target = f64::from(step.target_distance_m);
            let rem = (target - covered).max(0.0);
            let progress = if target > 0.0 {
                (covered / target).clamp(0.0, 1.0)
            } else {
                1.0
            };
            (rem as u32, 0, progress)
        };
        Some(WorkoutView {
            step_index: self.idx as u8,
            total: total as u8,
            kind: step.kind,
            rep_index: step.rep_index,
            rep_total: step.rep_total,
            duration_based: step.duration_based(),
            remaining_m,
            remaining_s,
            target_pace_s_per_km: step.target_pace_s_per_km,
            step_pace_s_per_km: self.step_pace_s_per_km(),
            adherence: self.adherence(&step),
            progress_permille: libm::round(progress * 1000.0) as u16,
            next_kind: self.steps.get(self.idx + 1).map(|s| s.kind),
            done: false,
        })
    }
}

/// Encode a `WKT1` frame — the phone encoder's Rust mirror, pinned to the
/// same golden bytes as the Dart test.
pub fn encode(steps: &[WorkoutStep], out: &mut [u8]) -> Option<usize> {
    if steps.is_empty() || steps.len() > MAX_WORKOUT_STEPS {
        return None;
    }
    let len = workout_frame_len(steps.len());
    if out.len() < len {
        return None;
    }
    out[0..4].copy_from_slice(&WORKOUT_MAGIC);
    out[4] = WORKOUT_FORMAT_VERSION;
    out[5] = steps.len() as u8;
    let mut off = WORKOUT_HEADER_LEN;
    for s in steps {
        out[off] = s.kind.to_byte();
        out[off + 1] = s.rep_index;
        out[off + 2] = s.rep_total;
        out[off + 3] = s.tolerance_s_per_km;
        out[off + 4..off + 8].copy_from_slice(&s.target_distance_m.to_le_bytes());
        out[off + 8..off + 10].copy_from_slice(&s.target_duration_s.to_le_bytes());
        out[off + 10..off + 12].copy_from_slice(&s.target_pace_s_per_km.to_le_bytes());
        off += WORKOUT_STEP_LEN;
    }
    let crc = crc32(&out[..off]).to_le_bytes();
    out[off..off + WORKOUT_CRC_LEN].copy_from_slice(&crc);
    Some(off + WORKOUT_CRC_LEN)
}

/// Decode a `WKT1` frame into its step list. `None` on a bad magic, an
/// unknown version, an out-of-range count, a length that does not match the
/// count, an unknown kind byte, a step with no end condition, or a failed
/// CRC — never a partial list. Like the course (and unlike `SET1`), there is
/// no version-compat ladder to keep: v1 is the first shipped frame and it is
/// checksummed from birth.
pub fn decode(frame: &[u8]) -> Option<Vec<WorkoutStep, MAX_WORKOUT_STEPS>> {
    if frame.len() < WORKOUT_HEADER_LEN + WORKOUT_CRC_LEN {
        return None;
    }
    if frame[0..4] != WORKOUT_MAGIC || frame[4] != WORKOUT_FORMAT_VERSION {
        return None;
    }
    let count = frame[5] as usize;
    if !(1..=MAX_WORKOUT_STEPS).contains(&count) {
        return None;
    }
    if frame.len() != workout_frame_len(count) {
        return None;
    }
    let body_len = frame.len() - WORKOUT_CRC_LEN;
    let stored = u32::from_le_bytes([
        frame[body_len],
        frame[body_len + 1],
        frame[body_len + 2],
        frame[body_len + 3],
    ]);
    if crc32(&frame[..body_len]) != stored {
        return None;
    }
    let mut steps = Vec::new();
    let mut off = WORKOUT_HEADER_LEN;
    for _ in 0..count {
        let step = WorkoutStep {
            kind: WorkoutStepKind::from_byte(frame[off])?,
            rep_index: frame[off + 1],
            rep_total: frame[off + 2],
            tolerance_s_per_km: frame[off + 3],
            target_distance_m: u32::from_le_bytes([
                frame[off + 4],
                frame[off + 5],
                frame[off + 6],
                frame[off + 7],
            ]),
            target_duration_s: u16::from_le_bytes([frame[off + 8], frame[off + 9]]),
            target_pace_s_per_km: u16::from_le_bytes([frame[off + 10], frame[off + 11]]),
        };
        if !step.has_end_condition() {
            return None;
        }
        let _ = steps.push(step);
        off += WORKOUT_STEP_LEN;
    }
    Some(steps)
}

/// The outcome of feeding one chunk to a [`WorkoutAssembler`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkoutPush {
    More,
    Complete,
    Rejected,
}

/// Reassembles a chunked `WKT1` push — the [`crate::course_store`] assembler
/// discipline verbatim: offset 0 restarts, out-of-order or overflowing chunks
/// reject and reset, the header is validated as soon as it is in, and the CRC
/// is the last gate so `Complete` implies [`decode`] succeeds.
pub struct WorkoutAssembler {
    buf: Vec<u8, MAX_WORKOUT_FRAME_LEN>,
}

impl Default for WorkoutAssembler {
    fn default() -> Self {
        Self::new()
    }
}

impl WorkoutAssembler {
    pub const fn new() -> Self {
        Self { buf: Vec::new() }
    }

    pub fn reset(&mut self) {
        self.buf.clear();
    }

    pub fn frame(&self) -> &[u8] {
        &self.buf
    }

    pub fn push(&mut self, offset: usize, payload: &[u8]) -> WorkoutPush {
        if offset == 0 {
            self.buf.clear();
        }
        if offset != self.buf.len() {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        if self.buf.extend_from_slice(payload).is_err() {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        if self.buf.len() < WORKOUT_HEADER_LEN {
            return WorkoutPush::More;
        }
        if self.buf[0..4] != WORKOUT_MAGIC || self.buf[4] != WORKOUT_FORMAT_VERSION {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        let count = self.buf[5] as usize;
        if !(1..=MAX_WORKOUT_STEPS).contains(&count) {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        let want = workout_frame_len(count);
        if self.buf.len() < want {
            return WorkoutPush::More;
        }
        if self.buf.len() > want {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        let body_len = want - WORKOUT_CRC_LEN;
        let stored = u32::from_le_bytes([
            self.buf[body_len],
            self.buf[body_len + 1],
            self.buf[body_len + 2],
            self.buf[body_len + 3],
        ]);
        if crc32(&self.buf[..body_len]) != stored {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        WorkoutPush::Complete
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dist_step(kind: WorkoutStepKind, m: u32, pace: u16) -> WorkoutStep {
        WorkoutStep {
            kind,
            rep_index: 0,
            rep_total: 0,
            tolerance_s_per_km: 10,
            target_distance_m: m,
            target_duration_s: 0,
            target_pace_s_per_km: pace,
        }
    }

    fn time_step(kind: WorkoutStepKind, s: u16, pace: u16) -> WorkoutStep {
        WorkoutStep {
            kind,
            rep_index: 0,
            rep_total: 0,
            tolerance_s_per_km: 10,
            target_distance_m: 0,
            target_duration_s: s,
            target_pace_s_per_km: pace,
        }
    }

    /// The canned intervals session the sim arms: warmup, 3 × (400 m rep +
    /// 200 m jog), cooldown.
    fn intervals() -> [WorkoutStep; 8] {
        let mut steps = [dist_step(WorkoutStepKind::Warmup, 800, 0); 8];
        for i in 0..3 {
            steps[1 + i * 2] = WorkoutStep {
                rep_index: i as u8 + 1,
                rep_total: 3,
                ..dist_step(WorkoutStepKind::Rep, 400, 270)
            };
            steps[2 + i * 2] = WorkoutStep {
                rep_index: i as u8 + 1,
                rep_total: 3,
                ..dist_step(WorkoutStepKind::Recovery, 200, 0)
            };
        }
        steps[7] = dist_step(WorkoutStepKind::Cooldown, 600, 0);
        steps
    }

    #[test]
    fn first_progress_anchors_step_zero_at_the_current_totals() {
        // The workout can be armed mid-run; step 0 starts where the runner is,
        // not at the run's zero (the mobile `_emittedFirstStart` anchor).
        let mut r = WorkoutRunner::new(&intervals());
        r.on_progress(500.0, 120);
        let v = r.view().unwrap();
        assert_eq!(v.step_index, 0);
        assert_eq!(v.remaining_m, 800);
        r.on_progress(900.0, 240);
        assert_eq!(r.view().unwrap().remaining_m, 400);
    }

    #[test]
    fn distance_steps_advance_on_distance_and_time_steps_on_elapsed() {
        let steps = [
            dist_step(WorkoutStepKind::Warmup, 100, 0),
            time_step(WorkoutStepKind::Rep, 60, 270),
        ];
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(99.0, 30);
        assert_eq!(r.view().unwrap().step_index, 0);
        r.on_progress(100.0, 31);
        let v = r.view().unwrap();
        assert_eq!(v.step_index, 1);
        assert!(v.duration_based);
        // The time step's clock starts at the advance, not at the run start.
        assert_eq!(v.remaining_s, 60);
        r.on_progress(150.0, 90);
        assert_eq!(r.view().unwrap().remaining_s, 1);
        r.on_progress(160.0, 91);
        assert!(r.view().unwrap().done);
    }

    #[test]
    fn one_jump_can_complete_several_steps_carrying_the_overshoot() {
        // The mobile advance loop's reason to exist: a GPS gap's single fix
        // covers a short rep AND its recovery; the next step must start at the
        // sum of the cleared targets, not at the fix.
        let steps = [
            dist_step(WorkoutStepKind::Rep, 100, 0),
            dist_step(WorkoutStepKind::Recovery, 100, 0),
            dist_step(WorkoutStepKind::Rep, 400, 0),
        ];
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(250.0, 60);
        let v = r.view().unwrap();
        assert_eq!(v.step_index, 2);
        // 250 m covered, 200 m consumed by the first two steps: the third
        // step keeps the 50 m overshoot.
        assert_eq!(v.remaining_m, 350);
    }

    #[test]
    fn the_view_reports_step_pace_and_the_mobile_adherence_bands() {
        let steps = [dist_step(WorkoutStepKind::Rep, 1000, 300)];
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        // 500 m in 150 s = 300 s/km — on pace.
        r.on_progress(500.0, 150);
        let v = r.view().unwrap();
        assert_eq!(v.step_pace_s_per_km, Some(300));
        assert_eq!(v.adherence, PaceAdherence::OnPace);
        // 15 s/km slow: outside tol 10, inside 20 — Behind.
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(400.0, 126);
        assert_eq!(r.view().unwrap().adherence, PaceAdherence::Behind);
        // 340 s/km: way behind.
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(500.0, 170);
        assert_eq!(r.view().unwrap().adherence, PaceAdherence::WayBehind);
        // No pace target: always on pace, whatever the speed.
        let steps = [dist_step(WorkoutStepKind::Warmup, 1000, 0)];
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(100.0, 600);
        assert_eq!(r.view().unwrap().adherence, PaceAdherence::OnPace);
    }

    #[test]
    fn completion_latches_and_reset_starts_over() {
        let steps = [dist_step(WorkoutStepKind::Rep, 100, 0)];
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(150.0, 30);
        assert!(r.view().unwrap().done);
        r.on_progress(200.0, 60);
        assert!(r.view().unwrap().done);
        r.reset();
        r.on_progress(200.0, 60);
        let v = r.view().unwrap();
        assert!(!v.done);
        assert_eq!(v.remaining_m, 100);
    }

    #[test]
    fn the_view_carries_labels_progress_and_the_next_step() {
        let steps = intervals();
        let mut r = WorkoutRunner::new(&steps);
        r.on_progress(0.0, 0);
        r.on_progress(400.0, 120);
        let v = r.view().unwrap();
        assert_eq!(v.kind, WorkoutStepKind::Warmup);
        assert_eq!(v.total, 8);
        assert_eq!(v.progress_permille, 500);
        assert_eq!(v.next_kind, Some(WorkoutStepKind::Rep));
        r.on_progress(800.0, 240);
        let v = r.view().unwrap();
        assert_eq!(v.kind, WorkoutStepKind::Rep);
        assert_eq!(v.rep_index, 1);
        assert_eq!(v.rep_total, 3);
        assert_eq!(v.next_kind, Some(WorkoutStepKind::Recovery));
    }

    #[test]
    fn kind_bytes_are_pinned_to_the_mobile_enum_order() {
        // The wire byte is the Dart `WorkoutStepKind` declaration index —
        // warmup, rep, recovery, walk, steady, cooldown. A reorder on either
        // side re-points every pushed step.
        assert_eq!(WorkoutStepKind::Warmup.to_byte(), 0);
        assert_eq!(WorkoutStepKind::Rep.to_byte(), 1);
        assert_eq!(WorkoutStepKind::Recovery.to_byte(), 2);
        assert_eq!(WorkoutStepKind::Walk.to_byte(), 3);
        assert_eq!(WorkoutStepKind::Steady.to_byte(), 4);
        assert_eq!(WorkoutStepKind::Cooldown.to_byte(), 5);
        for b in 0..=5u8 {
            assert_eq!(WorkoutStepKind::from_byte(b).unwrap().to_byte(), b);
        }
        assert_eq!(WorkoutStepKind::from_byte(6), None);
    }

    #[test]
    fn frames_round_trip_and_reject_every_corruption_class() {
        let steps = intervals();
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let n = encode(&steps, &mut buf).unwrap();
        assert_eq!(n, workout_frame_len(8));
        let back = decode(&buf[..n]).unwrap();
        assert_eq!(back.as_slice(), &steps[..]);

        // Truncation, extension, bad magic, unknown version, count mismatch.
        assert_eq!(decode(&buf[..n - 1]), None);
        let mut long = [0u8; MAX_WORKOUT_FRAME_LEN + 1];
        long[..n].copy_from_slice(&buf[..n]);
        assert_eq!(decode(&long[..n + 1]), None);
        let mut bad = buf;
        bad[0] = b'X';
        assert_eq!(decode(&bad[..n]), None);
        let mut bad = buf;
        bad[4] = WORKOUT_FORMAT_VERSION + 1;
        assert_eq!(decode(&bad[..n]), None);
        let mut bad = buf;
        bad[5] = 7;
        assert_eq!(decode(&bad[..n]), None);

        // A single flipped payload byte fails the CRC.
        let mut bad = buf;
        bad[WORKOUT_HEADER_LEN + 4] ^= 0x01;
        assert_eq!(decode(&bad[..n]), None);
    }

    #[test]
    fn a_step_with_no_end_condition_rejects_the_frame() {
        // Zero distance AND zero duration never advances — the runner would
        // park on it forever, so the frame fails whole (re-sealed under its
        // own valid CRC to prove the check stands on its own).
        let steps = [dist_step(WorkoutStepKind::Rep, 100, 0)];
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let n = encode(&steps, &mut buf).unwrap();
        buf[WORKOUT_HEADER_LEN + 4..WORKOUT_HEADER_LEN + 8].copy_from_slice(&0u32.to_le_bytes());
        let body = n - WORKOUT_CRC_LEN;
        let crc = crc32(&buf[..body]).to_le_bytes();
        buf[body..n].copy_from_slice(&crc);
        assert_eq!(decode(&buf[..n]), None);

        // An unknown kind byte, likewise re-sealed.
        let n = encode(&steps, &mut buf).unwrap();
        buf[WORKOUT_HEADER_LEN] = 6;
        let crc = crc32(&buf[..body]).to_le_bytes();
        buf[body..n].copy_from_slice(&crc);
        assert_eq!(decode(&buf[..n]), None);
    }

    #[test]
    fn encode_rejects_empty_and_over_cap_lists() {
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        assert_eq!(encode(&[], &mut buf), None);
        let too_many = [dist_step(WorkoutStepKind::Rep, 100, 0); MAX_WORKOUT_STEPS + 1];
        assert_eq!(encode(&too_many, &mut buf), None);
        let mut tiny = [0u8; 4];
        assert_eq!(encode(&intervals(), &mut tiny), None);
    }

    #[test]
    fn the_assembler_accepts_chunks_and_rejects_disorder() {
        let steps = intervals();
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let n = encode(&steps, &mut buf).unwrap();
        let frame = &buf[..n];

        let mut asm = WorkoutAssembler::new();
        let mid = n / 2;
        assert_eq!(asm.push(0, &frame[..mid]), WorkoutPush::More);
        assert_eq!(asm.push(mid, &frame[mid..]), WorkoutPush::Complete);
        assert!(decode(asm.frame()).is_some());

        // Out-of-order offset rejects and resets; offset 0 self-heals.
        let mut asm = WorkoutAssembler::new();
        assert_eq!(asm.push(0, &frame[..mid]), WorkoutPush::More);
        assert_eq!(asm.push(mid + 1, &frame[mid..]), WorkoutPush::Rejected);
        assert_eq!(asm.push(0, frame), WorkoutPush::Complete);

        // A corrupt final chunk fails the CRC gate.
        let mut asm = WorkoutAssembler::new();
        let mut bad = frame.to_vec_or_panic();
        let last = bad.len() - WORKOUT_CRC_LEN - 1;
        bad[last] ^= 0x40;
        assert_eq!(asm.push(0, &bad), WorkoutPush::Rejected);
    }

    trait ToVecOrPanic {
        fn to_vec_or_panic(&self) -> Vec<u8, MAX_WORKOUT_FRAME_LEN>;
    }

    impl ToVecOrPanic for [u8] {
        fn to_vec_or_panic(&self) -> Vec<u8, MAX_WORKOUT_FRAME_LEN> {
            let mut v = Vec::new();
            v.extend_from_slice(self).unwrap();
            v
        }
    }

    #[test]
    fn a_golden_frame_is_pinned_for_the_dart_encoder() {
        // One warmup + one paced rep — small enough to eyeball, pinned
        // byte-for-byte on both sides (the Dart `watch_workout` test).
        let steps = [
            dist_step(WorkoutStepKind::Warmup, 800, 0),
            WorkoutStep {
                rep_index: 1,
                rep_total: 3,
                ..dist_step(WorkoutStepKind::Rep, 400, 270)
            },
        ];
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let n = encode(&steps, &mut buf).unwrap();
        let body = n - WORKOUT_CRC_LEN;
        let expected_body: [u8; 30] = [
            0x57, 0x4b, 0x54, 0x31, // "WKT1"
            0x01, // version
            0x02, // count
            0x00, 0x00, 0x00, 0x0a, // warmup, no reps, tol 10
            0x20, 0x03, 0x00, 0x00, // 800 m
            0x00, 0x00, // no duration
            0x00, 0x00, // no pace target
            0x01, 0x01, 0x03, 0x0a, // rep 1/3, tol 10
            0x90, 0x01, 0x00, 0x00, // 400 m
            0x00, 0x00, // no duration
            0x0e, 0x01, // 270 s/km
        ];
        assert_eq!(&buf[..body], &expected_body);
        // The trailer is the derived crc32 of everything before it — asserted
        // as a derivation here; the Dart twin pins the same frame's literal
        // bytes, trailer included.
        assert_eq!(
            u32::from_le_bytes([buf[body], buf[body + 1], buf[body + 2], buf[body + 3]]),
            crc32(&buf[..body])
        );
    }
}
