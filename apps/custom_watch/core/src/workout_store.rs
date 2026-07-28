//! Phone→watch structured-workout wire format + chunked reassembly.
//!
//! The phone expands a planned workout (`expandWorkoutSteps` needs the plan's
//! structure + paces bag, which live phone-side) and pushes the flat step
//! list the [`crate::workout`] runner executes as a fixed little-endian
//! frame:
//!
//!   magic("WKT1", 4) | version(1) | step_count(1, u8) | flags(1) |
//!   step[N] | crc32(4, u32 LE)
//!
//! where each step is `kind(1) | rep_index(1) | rep_total(1) |
//! tolerance_s_per_km(1) | target_distance_m(4, u32 LE) |
//! target_duration_s(2, u16 LE) | target_pace_s_per_km(2, u16 LE)`.
//!
//! Binary, chunked, CRC-sealed — the [`crate::course_store`] discipline
//! exactly, checksum mandatory from v1: a flipped byte in a target distance
//! decodes as a perfectly plausible different workout (the runner would
//! advance a 400 m rep at 4000 m), and per-step validation can't tell 400
//! from 4000. Decoding only *parses* + fails closed: a bad magic, version,
//! count, unknown flag bit, length mismatch, failed checksum, unknown step
//! kind, a step with both end axes set (the expander never emits one), a
//! step with neither, or an implausible target rejects the WHOLE frame
//! rather than arming a partial workout.
//!
//! Host-tested with golden byte vectors the Dart encoder
//! (`watch_workout.dart`) pins too, so the two wire codecs can't drift.

use heapless::Vec;

use crate::alerts::{PACE_BAND_MAX_S_PER_KM, PACE_BAND_MIN_S_PER_KM};
use crate::pacer::GOAL_DISTANCE_MAX_M;
use crate::run_store::crc32;
use crate::workout::{WorkoutStep, WorkoutStepKind, MAX_WORKOUT_STEPS};

/// Workout frame magic — "WKT1".
pub const WORKOUT_MAGIC: [u8; 4] = *b"WKT1";

pub const WORKOUT_FORMAT_VERSION: u8 = 1;

/// No presence bits yet; any set bit is a corrupt or future frame and rejects
/// (a new field rides a version bump — the `settings::KNOWN_FLAGS` rule).
const KNOWN_WORKOUT_FLAGS: u8 = 0;

/// Header: magic(4) + version(1) + step_count(1) + flags(1).
pub const WORKOUT_HEADER_LEN: usize = 7;
/// One step: kind(1) + rep_index(1) + rep_total(1) + tolerance(1) +
/// distance(4) + duration(2) + pace(2).
pub const WORKOUT_STEP_LEN: usize = 12;
const WORKOUT_CRC_LEN: usize = 4;

/// Largest a full frame can be — the header plus [`MAX_WORKOUT_STEPS`] steps
/// and the CRC trailer.
pub const MAX_WORKOUT_FRAME_LEN: usize = workout_frame_len(MAX_WORKOUT_STEPS);

/// The BLE `workout` write characteristic's chunk payload cap, mirroring
/// [`crate::course_store::COURSE_CHUNK_CAP`].
pub const WORKOUT_CHUNK_CAP: usize = 244;

pub const fn workout_frame_len(step_count: usize) -> usize {
    WORKOUT_HEADER_LEN + step_count * WORKOUT_STEP_LEN + WORKOUT_CRC_LEN
}

/// Is this step one the runner can execute and the face can render honestly?
/// Exactly one end axis, a known kind (guaranteed by construction here — the
/// wire side re-checks the raw code), and plausible targets: a distance
/// inside `1..=`[`GOAL_DISTANCE_MAX_M`], and a pace inside the shared
/// [`PACE_BAND_MIN_S_PER_KM`]`..=`[`PACE_BAND_MAX_S_PER_KM`] window — the
/// same "beyond any human / past the live-pace ceiling" bounds the alert
/// band uses, because it is the same plausibility question.
fn step_plausible(s: &WorkoutStep) -> bool {
    let distance_based = s.target_distance_m > 0;
    let duration_based = s.target_duration_s > 0;
    if distance_based == duration_based {
        return false;
    }
    if distance_based && s.target_distance_m > GOAL_DISTANCE_MAX_M {
        return false;
    }
    (PACE_BAND_MIN_S_PER_KM..=PACE_BAND_MAX_S_PER_KM).contains(&u32::from(s.target_pace_s_per_km))
}

/// Encode a pre-expanded step list into `out` as a WKT1 frame, returning the
/// byte length written. `None` when the list is empty, over
/// [`MAX_WORKOUT_STEPS`], carries a step that fails [`step_plausible`] or a
/// tolerance past the wire's u8, or when `out` is too small — fail-closed,
/// matching the decoder, so an unencodable workout is caught at the sender.
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
    out[6] = 0;
    let mut off = WORKOUT_HEADER_LEN;
    for s in steps {
        if !step_plausible(s) || s.tolerance_s_per_km > u16::from(u8::MAX) {
            return None;
        }
        out[off] = s.kind.code();
        out[off + 1] = s.rep_index;
        out[off + 2] = s.rep_total;
        out[off + 3] = s.tolerance_s_per_km as u8;
        out[off + 4..off + 8].copy_from_slice(&s.target_distance_m.to_le_bytes());
        out[off + 8..off + 10].copy_from_slice(&s.target_duration_s.to_le_bytes());
        out[off + 10..off + 12].copy_from_slice(&s.target_pace_s_per_km.to_le_bytes());
        off += WORKOUT_STEP_LEN;
    }
    let crc = crc32(&out[..off]).to_le_bytes();
    out[off..off + WORKOUT_CRC_LEN].copy_from_slice(&crc);
    Some(len)
}

fn crc_matches(frame: &[u8]) -> bool {
    let body = frame.len() - WORKOUT_CRC_LEN;
    let want = u32::from_le_bytes([
        frame[body],
        frame[body + 1],
        frame[body + 2],
        frame[body + 3],
    ]);
    crc32(&frame[..body]) == want
}

/// Decode a WKT1 frame into the step list. `None` on any malformation the
/// module docs enumerate — never a partial workout.
pub fn decode(frame: &[u8]) -> Option<Vec<WorkoutStep, MAX_WORKOUT_STEPS>> {
    if frame.len() < WORKOUT_HEADER_LEN
        || frame[0..4] != WORKOUT_MAGIC
        || frame[4] != WORKOUT_FORMAT_VERSION
    {
        return None;
    }
    let count = frame[5] as usize;
    if !(1..=MAX_WORKOUT_STEPS).contains(&count) {
        return None;
    }
    if frame[6] & !KNOWN_WORKOUT_FLAGS != 0 {
        return None;
    }
    if frame.len() != workout_frame_len(count) {
        return None;
    }
    if !crc_matches(frame) {
        return None;
    }
    let mut steps: Vec<WorkoutStep, MAX_WORKOUT_STEPS> = Vec::new();
    let mut off = WORKOUT_HEADER_LEN;
    for _ in 0..count {
        let step = WorkoutStep {
            kind: WorkoutStepKind::from_code(frame[off])?,
            rep_index: frame[off + 1],
            rep_total: frame[off + 2],
            tolerance_s_per_km: u16::from(frame[off + 3]),
            target_distance_m: u32::from_le_bytes([
                frame[off + 4],
                frame[off + 5],
                frame[off + 6],
                frame[off + 7],
            ]),
            target_duration_s: u16::from_le_bytes([frame[off + 8], frame[off + 9]]),
            target_pace_s_per_km: u16::from_le_bytes([frame[off + 10], frame[off + 11]]),
        };
        if !step_plausible(&step) {
            return None;
        }
        steps.push(step).ok()?;
        off += WORKOUT_STEP_LEN;
    }
    Some(steps)
}

/// The outcome of feeding one chunk to a [`WorkoutAssembler`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkoutPush {
    More,
    /// The frame is whole and passes its checksum — [`WorkoutAssembler::frame`]
    /// is ready to [`decode`].
    Complete,
    /// A malformed / out-of-order / overflowing chunk or a failed CRC; the
    /// buffer was reset.
    Rejected,
}

/// Reassembles a chunked workout push — `offset | payload` writes in order,
/// offset 0 restarting the buffer, every malformation failing closed with a
/// reset so the phone's next offset-0 write recovers. The
/// [`crate::course_store::CourseAssembler`] contract over the WKT1 header.
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
        // Validate the header as soon as it's whole so a bad stream fails
        // fast instead of accreting bytes toward a frame that can't decode.
        if self.buf[0..4] != WORKOUT_MAGIC || self.buf[4] != WORKOUT_FORMAT_VERSION {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        let count = self.buf[5] as usize;
        if !(1..=MAX_WORKOUT_STEPS).contains(&count) {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        if self.buf[6] & !KNOWN_WORKOUT_FLAGS != 0 {
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
        // The checksum is the last gate, so `Complete` means the frame will
        // decode past it — the record task never arms a whole-but-corrupt
        // workout (per-step plausibility still runs in `decode`).
        if !crc_matches(&self.buf) {
            self.buf.clear();
            return WorkoutPush::Rejected;
        }
        WorkoutPush::Complete
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The demo workout the golden vectors pin: warmup 800 m @ 6:00, then
    /// 2× (400 m rep @ 4:00 / 90 s walk-run recovery @ 7:00), cooldown
    /// 600 m @ 6:00 — six steps covering both end axes and a rep group.
    fn demo_steps() -> [WorkoutStep; 6] {
        [
            WorkoutStep {
                kind: WorkoutStepKind::Warmup,
                rep_index: 0,
                rep_total: 0,
                target_distance_m: 800,
                target_duration_s: 0,
                target_pace_s_per_km: 360,
                tolerance_s_per_km: 10,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 1,
                rep_total: 2,
                target_distance_m: 400,
                target_duration_s: 0,
                target_pace_s_per_km: 240,
                tolerance_s_per_km: 10,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Walk,
                rep_index: 1,
                rep_total: 1,
                target_distance_m: 0,
                target_duration_s: 90,
                target_pace_s_per_km: 420,
                tolerance_s_per_km: 15,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Rep,
                rep_index: 2,
                rep_total: 2,
                target_distance_m: 400,
                target_duration_s: 0,
                target_pace_s_per_km: 240,
                tolerance_s_per_km: 10,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Steady,
                rep_index: 0,
                rep_total: 0,
                target_distance_m: 1000,
                target_duration_s: 0,
                target_pace_s_per_km: 300,
                tolerance_s_per_km: 12,
            },
            WorkoutStep {
                kind: WorkoutStepKind::Cooldown,
                rep_index: 0,
                rep_total: 0,
                target_distance_m: 600,
                target_duration_s: 0,
                target_pace_s_per_km: 360,
                tolerance_s_per_km: 10,
            },
        ]
    }

    fn encode_vec(steps: &[WorkoutStep]) -> std::vec::Vec<u8> {
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let n = encode(steps, &mut buf).expect("encodes");
        buf[..n].to_vec()
    }

    fn hex_of(frame: &[u8]) -> std::string::String {
        frame.iter().map(|b| std::format!("{:02x}", b)).collect()
    }

    /// Re-seal a body with the CRC the decoder checks, so a test can exercise
    /// a rejection *past* the checksum.
    fn sealed(body: &[u8]) -> std::vec::Vec<u8> {
        let mut frame = body.to_vec();
        frame.extend_from_slice(&crc32(body).to_le_bytes());
        frame
    }

    #[test]
    fn round_trips_the_demo_workout() {
        let steps = demo_steps();
        let frame = encode_vec(&steps);
        assert_eq!(frame.len(), workout_frame_len(6));
        let decoded = decode(&frame).expect("decodes");
        assert_eq!(decoded.as_slice(), &steps[..]);
    }

    /// Golden vector: the exact bytes the demo workout produces. The Dart
    /// encoder (`watch_workout.dart`) pins this same hex, so a format drift
    /// on either side fails a test rather than silently corrupting a push.
    #[test]
    fn golden_frame_is_stable() {
        let frame = encode_vec(&demo_steps());
        assert_eq!(
            hex_of(&frame).as_str(),
            "574b54310106000000000a20030000000068010101020a900100000000f0\
             000301010f000000005a00a4010102020a900100000000f0000400000ce8\
             03000000002c010500000a5802000000006801a9d7dbb8",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_workout.dart"
        );
        let body = frame.len() - WORKOUT_CRC_LEN;
        assert_eq!(
            u32::from_le_bytes([
                frame[body],
                frame[body + 1],
                frame[body + 2],
                frame[body + 3]
            ]),
            crc32(&frame[..body])
        );
    }

    #[test]
    fn encode_rejects_empty_over_cap_and_implausible_steps() {
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        assert!(encode(&[], &mut buf).is_none());
        let over = [demo_steps()[0]; MAX_WORKOUT_STEPS + 1];
        assert!(encode(&over, &mut buf).is_none());

        let mut both_axes = demo_steps();
        both_axes[0].target_duration_s = 60;
        assert!(encode(&both_axes, &mut buf).is_none());
        let mut no_axis = demo_steps();
        no_axis[0].target_distance_m = 0;
        assert!(encode(&no_axis, &mut buf).is_none());
        let mut silly_pace = demo_steps();
        silly_pace[0].target_pace_s_per_km = 60;
        assert!(encode(&silly_pace, &mut buf).is_none());
        let mut wide_tolerance = demo_steps();
        wide_tolerance[0].tolerance_s_per_km = 300;
        assert!(encode(&wide_tolerance, &mut buf).is_none());
    }

    #[test]
    fn encode_rejects_a_buffer_too_small() {
        let mut tiny = [0u8; WORKOUT_HEADER_LEN + WORKOUT_STEP_LEN];
        assert!(encode(&demo_steps(), &mut tiny).is_none());
        let mut exact = [0u8; workout_frame_len(6)];
        assert!(encode(&demo_steps(), &mut exact).is_some());
    }

    #[test]
    fn decode_rejects_bad_magic_version_flags_and_counts() {
        let frame = encode_vec(&demo_steps());
        assert!(decode(&[]).is_none());
        assert!(decode(&frame[..WORKOUT_HEADER_LEN - 1]).is_none());
        let mut bad_magic = frame.clone();
        bad_magic[0] = b'X';
        assert!(decode(&bad_magic).is_none());
        let mut bad_ver = frame.clone();
        bad_ver[4] = WORKOUT_FORMAT_VERSION + 1;
        assert!(decode(&bad_ver).is_none());

        let body = &frame[..frame.len() - WORKOUT_CRC_LEN];
        let mut odd_flag = body.to_vec();
        odd_flag[6] = 1 << 0;
        assert!(decode(&sealed(&odd_flag)).is_none());
        let mut zero_count = body.to_vec();
        zero_count[5] = 0;
        assert!(decode(&sealed(&zero_count)).is_none());
        let mut over_count = body.to_vec();
        over_count[5] = (MAX_WORKOUT_STEPS as u8) + 1;
        assert!(decode(&sealed(&over_count)).is_none());
    }

    #[test]
    fn decode_rejects_a_length_that_disagrees_with_the_count() {
        let frame = encode_vec(&demo_steps());
        assert!(decode(&frame[..frame.len() - 1]).is_none());
        let mut long = frame.clone();
        long.push(0x00);
        assert!(decode(&long).is_none());
        // Re-sealed at the wrong length, so the length check stands on its
        // own underneath the checksum.
        let body = &frame[..frame.len() - WORKOUT_CRC_LEN];
        assert!(decode(&sealed(&body[..body.len() - 1])).is_none());
        let mut over = body.to_vec();
        over.push(0x00);
        assert!(decode(&sealed(&over)).is_none());
    }

    #[test]
    fn decode_rejects_an_unknown_kind_and_an_implausible_step() {
        let frame = encode_vec(&demo_steps());
        let body = &frame[..frame.len() - WORKOUT_CRC_LEN];

        let mut odd_kind = body.to_vec();
        odd_kind[WORKOUT_HEADER_LEN] = 6;
        assert!(decode(&sealed(&odd_kind)).is_none());

        // Both axes zero: clear the warmup's 800 m.
        let mut no_axis = body.to_vec();
        no_axis[WORKOUT_HEADER_LEN + 4..WORKOUT_HEADER_LEN + 8].fill(0);
        assert!(decode(&sealed(&no_axis)).is_none());

        // Both axes set: give the warmup a duration too.
        let mut both_axes = body.to_vec();
        both_axes[WORKOUT_HEADER_LEN + 8..WORKOUT_HEADER_LEN + 10]
            .copy_from_slice(&60u16.to_le_bytes());
        assert!(decode(&sealed(&both_axes)).is_none());

        // A pace beyond the live-pace ceiling.
        let mut silly_pace = body.to_vec();
        silly_pace[WORKOUT_HEADER_LEN + 10..WORKOUT_HEADER_LEN + 12]
            .copy_from_slice(&6000u16.to_le_bytes());
        assert!(decode(&sealed(&silly_pace)).is_none());
    }

    /// The reproducer the mandatory CRC exists for: one flipped bit in a
    /// target distance is a perfectly well-formed frame describing a
    /// different workout — 400 m reps become 4496 m reps, still plausible,
    /// still decodable. The CRC turns it into a rejection.
    #[test]
    fn a_single_byte_corruption_cannot_change_a_target() {
        let frame = encode_vec(&demo_steps());
        let rep_distance_at = WORKOUT_HEADER_LEN + WORKOUT_STEP_LEN + 4;
        let body = &frame[..frame.len() - WORKOUT_CRC_LEN];
        let mut displaced = body.to_vec();
        displaced[rep_distance_at + 1] ^= 0x10;
        let steps = decode(&sealed(&displaced)).expect("well-formed under its own crc");
        assert_ne!(steps[1].target_distance_m, 400, "the flip changed the rep");

        let mut corrupt = frame.clone();
        corrupt[rep_distance_at + 1] ^= 0x10;
        assert!(decode(&corrupt).is_none());
    }

    #[test]
    fn a_frame_whose_crc_does_not_match_is_rejected() {
        let frame = encode_vec(&demo_steps());
        for at in 0..WORKOUT_CRC_LEN {
            let mut bad = frame.clone();
            bad[frame.len() - WORKOUT_CRC_LEN + at] ^= 0x01;
            assert!(decode(&bad).is_none(), "a flipped crc byte {at} decoded");
        }
    }

    fn chunks(frame: &[u8], payload_len: usize) -> std::vec::Vec<(usize, std::vec::Vec<u8>)> {
        let mut out = std::vec::Vec::new();
        let mut off = 0;
        while off < frame.len() {
            let end = (off + payload_len).min(frame.len());
            out.push((off, frame[off..end].to_vec()));
            off = end;
        }
        out
    }

    #[test]
    fn assembler_reassembles_and_decodes_a_chunked_frame() {
        let frame = encode_vec(&demo_steps());
        let mut asm = WorkoutAssembler::new();
        let parts = chunks(&frame, 8);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let want = if i == parts.len() - 1 {
                WorkoutPush::Complete
            } else {
                WorkoutPush::More
            };
            assert_eq!(asm.push(*off, payload), want, "at chunk {i}");
        }
        assert_eq!(asm.frame(), frame.as_slice());
        let steps = decode(asm.frame()).expect("decodes the reassembled frame");
        assert_eq!(steps.len(), 6);
    }

    #[test]
    fn assembler_rejects_out_of_order_then_recovers_from_offset_zero() {
        let frame = encode_vec(&demo_steps());
        let mut asm = WorkoutAssembler::new();
        assert_eq!(asm.push(8, &frame[8..16]), WorkoutPush::Rejected);
        assert!(asm.frame().is_empty());
        let mut last = WorkoutPush::More;
        for (off, payload) in chunks(&frame, 12) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, WorkoutPush::Complete);
        assert_eq!(asm.frame(), frame.as_slice());
    }

    #[test]
    fn assembler_rejects_a_whole_frame_whose_crc_fails() {
        let mut frame = encode_vec(&demo_steps());
        frame[WORKOUT_HEADER_LEN] ^= 0x01;
        let mut asm = WorkoutAssembler::new();
        let parts = chunks(&frame, 8);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let outcome = asm.push(*off, payload);
            if i < parts.len() - 1 {
                assert_eq!(outcome, WorkoutPush::More, "at chunk {i}");
            } else {
                assert_eq!(outcome, WorkoutPush::Rejected, "corrupt frame completed");
            }
        }
        assert!(asm.frame().is_empty());
        // The buffer is clean, so an honest re-push lands.
        let honest = encode_vec(&demo_steps());
        let mut last = WorkoutPush::More;
        for (off, payload) in chunks(&honest, 8) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, WorkoutPush::Complete);
    }

    #[test]
    fn assembler_rejects_a_bad_header_stream() {
        let mut asm = WorkoutAssembler::new();
        let bad = [b'X', b'X', b'X', b'X', WORKOUT_FORMAT_VERSION, 0x06, 0x00];
        assert_eq!(asm.push(0, &bad), WorkoutPush::Rejected);
        assert!(asm.frame().is_empty());
        let mut zero_count = [0u8; WORKOUT_HEADER_LEN];
        zero_count[0..4].copy_from_slice(&WORKOUT_MAGIC);
        zero_count[4] = WORKOUT_FORMAT_VERSION;
        zero_count[5] = 0;
        assert_eq!(asm.push(0, &zero_count), WorkoutPush::Rejected);
        let mut odd_flag = [0u8; WORKOUT_HEADER_LEN];
        odd_flag[0..4].copy_from_slice(&WORKOUT_MAGIC);
        odd_flag[4] = WORKOUT_FORMAT_VERSION;
        odd_flag[5] = 6;
        odd_flag[6] = 1 << 7;
        assert_eq!(asm.push(0, &odd_flag), WorkoutPush::Rejected);
    }
}
