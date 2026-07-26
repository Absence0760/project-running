//! Phone→watch breadcrumb-course wire format + chunked reassembly.
//!
//! The phone pushes a route the runner wants to follow to the watch as a
//! fixed little-endian frame the firmware decodes into the [`Course`] the nav
//! task already consumes:
//!
//!   magic("CRS1", 4) | version(1) | point_count(2, u16 LE) | flags(1) |
//!   point[N] | elev_m[N]?
//!
//! where each point is `lat_e7(i32 LE) | lon_e7(i32 LE)` — the same 1e-7-degree
//! integer scaling `run_store` uses for track points, so a route simplified
//! phone-side to <= [`MAX_COURSE_POINTS`] survives the wire without float drift
//! — and each elevation is `i16 LE` metres, present only when
//! [`COURSE_FLAG_ELEV`] is set.
//!
//! Binary, not JSON — same discipline as [`crate::settings`] / [`crate::run_store`]:
//! the watch is `no_std` with no allocator, and the run-sync side already speaks
//! fixed-layout frames. A whole course exceeds one BLE notification, so the push
//! is chunked: the phone writes `offset(2, u16 LE) | payload` chunks in order and
//! the watch's [`CourseAssembler`] rebuilds the frame, then [`decode`] turns it
//! into a `Course`. Decoding only *parses* + fails closed — a bad magic, version,
//! count, length, or an over-cap course is rejected rather than half-applied, so
//! a corrupt push can never load a truncated course mid-race.
//!
//! Host-tested (encode/decode round-trip, overflow rejection, chunk reassembly,
//! a golden byte vector per version) against the Dart encoder
//! (`watch_course.dart`), which pins the SAME golden vectors, so the two wire
//! codecs can't drift.
//!
//! The frame carries no integrity trailer. A single-byte corruption inside the
//! point array decodes as a valid but *displaced* course — the same class of
//! hole `settings` closed with its v3 CRC32 — and closing it here is a sibling
//! concern, not part of the elevation field.

use heapless::Vec;

use crate::course::{Course, CoursePoint, MAX_COURSE_POINTS};

/// Course frame magic — "CRS1".
pub const COURSE_MAGIC: [u8; 4] = *b"CRS1";

/// Version 2 (2026-07-26): the frame gained a flags byte and, behind it, the
/// per-point elevation series the RouteElev page draws as a climb profile. v1
/// carried the polyline only, so it has no place to say "no elevation" —
/// `decode` still accepts it (an old phone's push keeps working, elevation-less)
/// while the encoder always emits v2, with the flag clear when the phone has no
/// elevation for the route.
pub const COURSE_FORMAT_VERSION: u8 = 2;
const COURSE_FORMAT_VERSION_V1: u8 = 1;

/// Presence bit: the frame ends with one `i16 LE` metre elevation per point.
pub const COURSE_FLAG_ELEV: u8 = 1 << 0;

/// Every presence bit the flags byte defines. A set bit outside this mask can't
/// be a forward-compatible field — a new field rides a version bump, which
/// `decode` rejects on the version byte — so an unknown bit means a corrupt or
/// misframed push, and `decode` rejects the frame rather than silently dropping
/// whatever the sender meant by it (the `settings::KNOWN_FLAGS` rule).
const KNOWN_COURSE_FLAGS: u8 = COURSE_FLAG_ELEV;

/// v1 header: magic(4) + version(1) + point_count(2). v2 appends `flags`.
const COURSE_HEADER_V1_LEN: usize = 7;
pub const COURSE_HEADER_LEN: usize = COURSE_HEADER_V1_LEN + 1;
/// One point: lat_e7(4) + lon_e7(4).
pub const COURSE_POINT_LEN: usize = 8;
/// One elevation sample: metres as `i16 LE`. Metres, not decimetres — a
/// decimetre i16 tops out at 3276.7 m, below Mont Blanc.
pub const COURSE_ELEV_LEN: usize = 2;

/// Largest a full frame can be — a v2 header plus [`MAX_COURSE_POINTS`] points
/// and their elevations.
pub const MAX_COURSE_FRAME_LEN: usize = course_frame_len(MAX_COURSE_POINTS, true);

/// The BLE `course` write characteristic's value cap: one chunk is
/// `offset(2) | payload`, sized to fit inside one ATT write at the 256-byte MTU
/// (mirrors `run_store`'s `FRAME_CAP`).
pub const COURSE_CHUNK_CAP: usize = 244;

/// v2 frame length for a course of `point_count` points, with or without the
/// elevation series.
pub const fn course_frame_len(point_count: usize, with_elevation: bool) -> usize {
    COURSE_HEADER_LEN
        + point_count * COURSE_POINT_LEN
        + if with_elevation {
            point_count * COURSE_ELEV_LEN
        } else {
            0
        }
}

/// v1 frame length — the legacy layout [`decode`] still accepts.
pub const fn course_frame_len_v1(point_count: usize) -> usize {
    COURSE_HEADER_V1_LEN + point_count * COURSE_POINT_LEN
}

/// Encode a course polyline — and, when the phone has one, its per-point
/// elevation in metres — into `out` as a CRS1 v2 frame, returning the byte
/// length written. `None` when the course is too short (< 2) or over the tier-1
/// capacity (> [`MAX_COURSE_POINTS`]) — fail-closed, matching
/// [`Course::from_points`] — when `elev_m` is present but doesn't carry exactly
/// one sample per point, or when `out` is smaller than the frame needs. lat/lon
/// are quantised to 1e-7 degrees (round half away from zero, matching the Dart
/// encoder).
pub fn encode(points: &[CoursePoint], elev_m: Option<&[i16]>, out: &mut [u8]) -> Option<usize> {
    if points.len() < 2 || points.len() > MAX_COURSE_POINTS {
        return None;
    }
    if let Some(elev_m) = elev_m {
        if elev_m.len() != points.len() {
            return None;
        }
    }
    let len = course_frame_len(points.len(), elev_m.is_some());
    if out.len() < len {
        return None;
    }
    out[0..4].copy_from_slice(&COURSE_MAGIC);
    out[4] = COURSE_FORMAT_VERSION;
    out[5..7].copy_from_slice(&(points.len() as u16).to_le_bytes());
    out[7] = if elev_m.is_some() {
        COURSE_FLAG_ELEV
    } else {
        0
    };
    let mut off = COURSE_HEADER_LEN;
    for p in points {
        let lat_e7 = libm::round(p.lat_deg * 1e7) as i32;
        let lon_e7 = libm::round(p.lon_deg * 1e7) as i32;
        out[off..off + 4].copy_from_slice(&lat_e7.to_le_bytes());
        out[off + 4..off + 8].copy_from_slice(&lon_e7.to_le_bytes());
        off += COURSE_POINT_LEN;
    }
    for e in elev_m.unwrap_or(&[]) {
        out[off..off + COURSE_ELEV_LEN].copy_from_slice(&e.to_le_bytes());
        off += COURSE_ELEV_LEN;
    }
    Some(len)
}

/// Decode a CRS1 frame into a [`Course`]. Accepts v1 (polyline only) and v2
/// (flags byte, optional elevation). `None` on a bad magic, an unknown version,
/// an unknown flag bit, a point count outside `2..=MAX_COURSE_POINTS`
/// (fail-closed overflow rejection), a length that doesn't match the declared
/// count + flags (trailing / short bytes), or a non-finite point.
pub fn decode(frame: &[u8]) -> Option<Course> {
    if frame.len() < COURSE_HEADER_V1_LEN || frame[0..4] != COURSE_MAGIC {
        return None;
    }
    let version = frame[4];
    if version != COURSE_FORMAT_VERSION && version != COURSE_FORMAT_VERSION_V1 {
        return None;
    }
    let count = u16::from_le_bytes([frame[5], frame[6]]) as usize;
    if !(2..=MAX_COURSE_POINTS).contains(&count) {
        return None;
    }
    let (mut off, with_elev) = if version == COURSE_FORMAT_VERSION_V1 {
        if frame.len() != course_frame_len_v1(count) {
            return None;
        }
        (COURSE_HEADER_V1_LEN, false)
    } else {
        if frame.len() < COURSE_HEADER_LEN {
            return None;
        }
        let flags = frame[7];
        if flags & !KNOWN_COURSE_FLAGS != 0 {
            return None;
        }
        let with_elev = flags & COURSE_FLAG_ELEV != 0;
        if frame.len() != course_frame_len(count, with_elev) {
            return None;
        }
        (COURSE_HEADER_LEN, with_elev)
    };
    let mut points: Vec<CoursePoint, MAX_COURSE_POINTS> = Vec::new();
    for _ in 0..count {
        let lat_e7 =
            i32::from_le_bytes([frame[off], frame[off + 1], frame[off + 2], frame[off + 3]]);
        let lon_e7 = i32::from_le_bytes([
            frame[off + 4],
            frame[off + 5],
            frame[off + 6],
            frame[off + 7],
        ]);
        points
            .push(CoursePoint {
                lat_deg: lat_e7 as f64 / 1e7,
                lon_deg: lon_e7 as f64 / 1e7,
            })
            .ok()?;
        off += COURSE_POINT_LEN;
    }
    if !with_elev {
        return Course::from_points(&points);
    }
    let mut elev_m: Vec<i16, MAX_COURSE_POINTS> = Vec::new();
    for _ in 0..count {
        elev_m
            .push(i16::from_le_bytes([frame[off], frame[off + 1]]))
            .ok()?;
        off += COURSE_ELEV_LEN;
    }
    Course::from_points_with_elevation(&points, &elev_m)
}

/// The outcome of feeding one chunk to a [`CourseAssembler`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CoursePush {
    /// More chunks are needed before the frame is complete.
    More,
    /// The frame is complete — [`CourseAssembler::frame`] is ready to [`decode`].
    Complete,
    /// A malformed / out-of-order / overflowing chunk; the buffer was reset.
    Rejected,
}

/// Reassembles a chunked course push. The phone writes `offset | payload` chunks
/// in order; each [`push`](CourseAssembler::push) appends the payload, and once
/// the declared frame length has arrived the caller [`decode`]s [`frame`](
/// CourseAssembler::frame). An offset of 0 restarts the buffer, so a phone can
/// always recover from a dropped push. Fail-closed: an out-of-order offset, an
/// overflowing chunk, or a bad/over-cap header resets the buffer and yields
/// [`CoursePush::Rejected`] rather than assembling a corrupt frame.
pub struct CourseAssembler {
    buf: Vec<u8, MAX_COURSE_FRAME_LEN>,
}

impl Default for CourseAssembler {
    fn default() -> Self {
        Self::new()
    }
}

impl CourseAssembler {
    pub const fn new() -> Self {
        Self { buf: Vec::new() }
    }

    pub fn reset(&mut self) {
        self.buf.clear();
    }

    /// The bytes assembled so far — a whole frame once [`push`](Self::push)
    /// returned `Ok(true)`.
    pub fn frame(&self) -> &[u8] {
        &self.buf
    }

    /// Feed one chunk written at `offset`. Returns [`CoursePush::Complete`] when
    /// the frame is now whole, [`CoursePush::More`] when more chunks are needed,
    /// or [`CoursePush::Rejected`] on a malformed / out-of-order / overflowing
    /// chunk (buffer reset). An `offset` of 0 restarts a fresh push.
    pub fn push(&mut self, offset: usize, payload: &[u8]) -> CoursePush {
        if offset == 0 {
            self.buf.clear();
        }
        if offset != self.buf.len() {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        if self.buf.extend_from_slice(payload).is_err() {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        if self.buf.len() < COURSE_HEADER_V1_LEN {
            return CoursePush::More;
        }
        // The header is in: validate it early so a bad stream fails fast instead
        // of accreting bytes toward a frame that can never decode.
        let version = self.buf[4];
        if self.buf[0..4] != COURSE_MAGIC
            || (version != COURSE_FORMAT_VERSION && version != COURSE_FORMAT_VERSION_V1)
        {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        let count = u16::from_le_bytes([self.buf[5], self.buf[6]]) as usize;
        if !(2..=MAX_COURSE_POINTS).contains(&count) {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        let want = if version == COURSE_FORMAT_VERSION_V1 {
            course_frame_len_v1(count)
        } else {
            if self.buf.len() < COURSE_HEADER_LEN {
                return CoursePush::More;
            }
            let flags = self.buf[7];
            if flags & !KNOWN_COURSE_FLAGS != 0 {
                self.buf.clear();
                return CoursePush::Rejected;
            }
            course_frame_len(count, flags & COURSE_FLAG_ELEV != 0)
        };
        if self.buf.len() < want {
            CoursePush::More
        } else if self.buf.len() == want {
            CoursePush::Complete
        } else {
            self.buf.clear();
            CoursePush::Rejected
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pt(lat_deg: f64, lon_deg: f64) -> CoursePoint {
        CoursePoint { lat_deg, lon_deg }
    }

    /// The canned sim course's three points, each an exact 1e-7 multiple so the
    /// e7 quantisation is lossless and the golden vector is stable.
    fn sim_points() -> [CoursePoint; 3] {
        [
            pt(40.0158083, -105.2705),
            pt(40.015, -105.2705),
            pt(40.015, -105.269445),
        ]
    }

    /// Bench-plausible altitudes for the sim course (Boulder, ~1650 m): a small
    /// rise then a fall, so gain and loss are both non-zero.
    const SIM_ELEV_M: [i16; 3] = [1650, 1655, 1640];

    fn encode_vec(points: &[CoursePoint]) -> std::vec::Vec<u8> {
        encode_vec_with(points, None)
    }

    fn encode_vec_with(points: &[CoursePoint], elev_m: Option<&[i16]>) -> std::vec::Vec<u8> {
        let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
        let n = encode(points, elev_m, &mut buf).expect("encodes");
        buf[..n].to_vec()
    }

    fn hex_of(frame: &[u8]) -> heapless::String<192> {
        frame
            .iter()
            .fold(heapless::String::<192>::new(), |mut s, b| {
                let _ = core::fmt::write(&mut s, format_args!("{:02x}", b));
                s
            })
    }

    /// A v1 frame (no flags byte, no elevation) as an old phone would send it.
    fn v1_frame(points: &[CoursePoint]) -> std::vec::Vec<u8> {
        let mut out = std::vec::Vec::new();
        out.extend_from_slice(&COURSE_MAGIC);
        out.push(COURSE_FORMAT_VERSION_V1);
        out.extend_from_slice(&(points.len() as u16).to_le_bytes());
        for p in points {
            out.extend_from_slice(&(libm::round(p.lat_deg * 1e7) as i32).to_le_bytes());
            out.extend_from_slice(&(libm::round(p.lon_deg * 1e7) as i32).to_le_bytes());
        }
        out
    }

    #[test]
    fn round_trips_a_small_course() {
        let pts = sim_points();
        let frame = encode_vec(&pts);
        assert_eq!(frame.len(), course_frame_len(3, false));
        let course = decode(&frame).expect("decodes");
        assert_eq!(course.points().len(), 3);
        for (a, b) in course.points().iter().zip(pts.iter()) {
            assert!(
                (a.lat_deg - b.lat_deg).abs() < 1e-7,
                "lat {} {}",
                a.lat_deg,
                b.lat_deg
            );
            assert!(
                (a.lon_deg - b.lon_deg).abs() < 1e-7,
                "lon {} {}",
                a.lon_deg,
                b.lon_deg
            );
        }
    }

    #[test]
    fn round_trips_a_course_with_elevation() {
        let frame = encode_vec_with(&sim_points(), Some(&SIM_ELEV_M));
        assert_eq!(frame.len(), course_frame_len(3, true));
        assert_eq!(frame[7], COURSE_FLAG_ELEV);
        let course = decode(&frame).expect("decodes");
        assert_eq!(course.elevations(), Some(&SIM_ELEV_M[..]));
    }

    #[test]
    fn an_elevation_less_v2_frame_decodes_to_a_course_without_a_profile() {
        let course = decode(&encode_vec(&sim_points())).expect("decodes");
        assert!(course.elevations().is_none());
    }

    /// Golden vector: the exact bytes the sim course produces. The Dart encoder
    /// (`watch_course.dart`) pins this same hex, so a format drift on either side
    /// fails a test rather than silently corrupting a pushed course.
    #[test]
    fn golden_frame_is_stable() {
        assert_eq!(
            hex_of(&encode_vec(&sim_points())).as_str(),
            "435253310203000083edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_course.dart"
        );
    }

    /// The elevation-bearing golden vector, pinned on both sides like the
    /// elevation-less one above.
    #[test]
    fn golden_elevation_frame_is_stable() {
        assert_eq!(
            hex_of(&encode_vec_with(&sim_points(), Some(&SIM_ELEV_M))).as_str(),
            "435253310203000183edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1720677066806",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_course.dart"
        );
    }

    #[test]
    fn encode_rejects_too_few_and_too_many_points() {
        assert!(encode(&[], None, &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        assert!(encode(&[pt(1.0, 2.0)], None, &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        let over: std::vec::Vec<CoursePoint> = (0..=MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        assert!(encode(&over, None, &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        let at_cap: std::vec::Vec<CoursePoint> = (0..MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        let elev: std::vec::Vec<i16> = (0..MAX_COURSE_POINTS).map(|i| i as i16).collect();
        let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
        assert_eq!(
            encode(&at_cap, None, &mut buf),
            Some(course_frame_len(MAX_COURSE_POINTS, false))
        );
        assert_eq!(
            encode(&at_cap, Some(&elev), &mut buf),
            Some(MAX_COURSE_FRAME_LEN)
        );
    }

    #[test]
    fn encode_rejects_an_elevation_series_of_the_wrong_length() {
        let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
        assert!(encode(&sim_points(), Some(&[1650, 1655]), &mut buf).is_none());
        assert!(encode(&sim_points(), Some(&[]), &mut buf).is_none());
        assert!(encode(&sim_points(), Some(&[1, 2, 3, 4]), &mut buf).is_none());
    }

    #[test]
    fn encode_rejects_a_buffer_too_small() {
        let mut tiny = [0u8; COURSE_HEADER_LEN + COURSE_POINT_LEN]; // room for one point, needs two
        assert!(encode(&sim_points(), None, &mut tiny).is_none());
        // Exactly big enough without elevation, one sample short with it.
        let mut no_room_for_elev = [0u8; course_frame_len(3, false)];
        assert!(encode(&sim_points(), None, &mut no_room_for_elev).is_some());
        assert!(encode(&sim_points(), Some(&SIM_ELEV_M), &mut no_room_for_elev).is_none());
    }

    #[test]
    fn decode_still_accepts_a_v1_frame() {
        let frame = v1_frame(&sim_points());
        let course = decode(&frame).expect("v1 decodes");
        assert_eq!(course.points().len(), 3);
        assert!(course.elevations().is_none());
    }

    #[test]
    fn decode_rejects_an_unknown_version_and_an_unknown_flag_bit() {
        let mut future = encode_vec(&sim_points());
        future[4] = COURSE_FORMAT_VERSION + 1;
        assert!(decode(&future).is_none());
        let mut odd_flag = encode_vec(&sim_points());
        odd_flag[7] = 1 << 1;
        assert!(decode(&odd_flag).is_none());
        // A frame whose flags claim elevation but whose length doesn't carry it.
        let mut lying_flag = encode_vec(&sim_points());
        lying_flag[7] = COURSE_FLAG_ELEV;
        assert!(decode(&lying_flag).is_none());
    }

    #[test]
    fn decode_rejects_a_truncated_elevation_series() {
        let frame = encode_vec_with(&sim_points(), Some(&SIM_ELEV_M));
        assert!(decode(&frame[..frame.len() - 2]).is_none());
        let mut long = frame.clone();
        long.push(0x00);
        long.push(0x00);
        assert!(decode(&long).is_none());
    }

    #[test]
    fn decode_rejects_bad_magic_version_and_short_frames() {
        let frame = encode_vec(&sim_points());
        assert!(decode(&[]).is_none());
        assert!(decode(&frame[..COURSE_HEADER_LEN - 1]).is_none());
        let mut bad_magic = frame.clone();
        bad_magic[0] = b'X';
        assert!(decode(&bad_magic).is_none());
        let mut bad_ver = frame.clone();
        bad_ver[4] = COURSE_FORMAT_VERSION + 1;
        assert!(decode(&bad_ver).is_none());
    }

    #[test]
    fn decode_rejects_a_length_that_disagrees_with_the_count() {
        let frame = encode_vec(&sim_points());
        // One byte short: flags claim 3 points, bytes lack the last.
        assert!(decode(&frame[..frame.len() - 1]).is_none());
        // Trailing byte past the declared points.
        let mut long = frame.clone();
        long.push(0x00);
        assert!(decode(&long).is_none());
    }

    #[test]
    fn decode_rejects_an_over_cap_or_too_small_count() {
        let mut frame = encode_vec(&sim_points());
        // Claim 257 points (over MAX_COURSE_POINTS) — rejected before any read.
        frame[5..7].copy_from_slice(&((MAX_COURSE_POINTS as u16) + 1).to_le_bytes());
        assert!(decode(&frame).is_none());
        // Claim 1 point — a course must have >= 2.
        let mut one = encode_vec(&sim_points());
        one[5..7].copy_from_slice(&1u16.to_le_bytes());
        assert!(decode(&one).is_none());
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
        let frame = encode_vec(&sim_points());
        let mut asm = CourseAssembler::new();
        let parts = chunks(&frame, 8);
        let mut last = CoursePush::More;
        for (off, payload) in &parts {
            last = asm.push(*off, payload);
        }
        assert_eq!(last, CoursePush::Complete, "complete after the last chunk");
        assert_eq!(asm.frame(), frame.as_slice());
        let course = decode(asm.frame()).expect("decodes the reassembled frame");
        assert_eq!(course.points().len(), 3);
    }

    #[test]
    fn assembler_needs_more_until_the_last_chunk() {
        let frame = encode_vec(&sim_points());
        let mut asm = CourseAssembler::new();
        let parts = chunks(&frame, 8);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let want = if i == parts.len() - 1 {
                CoursePush::Complete
            } else {
                CoursePush::More
            };
            assert_eq!(asm.push(*off, payload), want, "at chunk {}", i);
        }
    }

    #[test]
    fn assembler_rejects_out_of_order_then_recovers_from_offset_zero() {
        let frame = encode_vec(&sim_points());
        let mut asm = CourseAssembler::new();
        // A chunk that skips ahead of the buffer is rejected and the buffer reset.
        assert_eq!(asm.push(8, &frame[8..16]), CoursePush::Rejected);
        assert!(asm.frame().is_empty());
        // Restart from offset 0 and finish cleanly.
        let mut last = CoursePush::More;
        for (off, payload) in chunks(&frame, 12) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, CoursePush::Complete);
        assert_eq!(asm.frame(), frame.as_slice());
    }

    #[test]
    fn assembler_reassembles_an_elevation_bearing_frame() {
        let frame = encode_vec_with(&sim_points(), Some(&SIM_ELEV_M));
        let mut asm = CourseAssembler::new();
        let parts = chunks(&frame, 8);
        let mut last = CoursePush::More;
        for (off, payload) in &parts {
            last = asm.push(*off, payload);
        }
        assert_eq!(last, CoursePush::Complete);
        let course = decode(asm.frame()).expect("decodes the reassembled frame");
        assert_eq!(course.elevations(), Some(&SIM_ELEV_M[..]));
    }

    #[test]
    fn assembler_rejects_a_bad_header_stream() {
        let mut asm = CourseAssembler::new();
        // A full header with the wrong magic fails as soon as it's in.
        let bad = [b'X', b'X', b'X', b'X', COURSE_FORMAT_VERSION, 0x03, 0x00];
        assert_eq!(asm.push(0, &bad), CoursePush::Rejected);
        assert!(asm.frame().is_empty());
        // A header declaring an over-cap count fails too.
        let mut over = [0u8; COURSE_HEADER_LEN];
        over[0..4].copy_from_slice(&COURSE_MAGIC);
        over[4] = COURSE_FORMAT_VERSION;
        over[5..7].copy_from_slice(&((MAX_COURSE_POINTS as u16) + 1).to_le_bytes());
        assert_eq!(asm.push(0, &over), CoursePush::Rejected);
        // An unknown flag bit fails as soon as the flags byte lands.
        let mut odd_flag = [0u8; COURSE_HEADER_LEN];
        odd_flag[0..4].copy_from_slice(&COURSE_MAGIC);
        odd_flag[4] = COURSE_FORMAT_VERSION;
        odd_flag[5..7].copy_from_slice(&3u16.to_le_bytes());
        odd_flag[7] = 1 << 7;
        assert_eq!(asm.push(0, &odd_flag), CoursePush::Rejected);
    }
}
