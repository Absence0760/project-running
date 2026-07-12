//! Phone→watch breadcrumb-course wire format + chunked reassembly.
//!
//! The phone pushes a route the runner wants to follow to the watch as a
//! fixed little-endian frame the firmware decodes into the [`Course`] the nav
//! task already consumes:
//!
//!   magic("CRS1", 4) | version(1) | point_count(2, u16 LE) | point[N]
//!
//! where each point is `lat_e7(i32 LE) | lon_e7(i32 LE)` — the same 1e-7-degree
//! integer scaling `run_store` uses for track points, so a route simplified
//! phone-side to <= [`MAX_COURSE_POINTS`] survives the wire without float drift.
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
//! a golden byte vector) against the Dart encoder (`watch_course.dart`), which
//! pins the SAME golden vector, so the two wire codecs can't drift.

use heapless::Vec;

use crate::course::{Course, CoursePoint, MAX_COURSE_POINTS};

/// Course frame magic — "CRS1".
pub const COURSE_MAGIC: [u8; 4] = *b"CRS1";
pub const COURSE_FORMAT_VERSION: u8 = 1;

/// Header: magic(4) + version(1) + point_count(2).
pub const COURSE_HEADER_LEN: usize = 7;
/// One point: lat_e7(4) + lon_e7(4).
pub const COURSE_POINT_LEN: usize = 8;

/// Largest a full frame can be — a header plus [`MAX_COURSE_POINTS`] points.
pub const MAX_COURSE_FRAME_LEN: usize = COURSE_HEADER_LEN + MAX_COURSE_POINTS * COURSE_POINT_LEN;

/// The BLE `course` write characteristic's value cap: one chunk is
/// `offset(2) | payload`, sized to fit inside one ATT write at the 256-byte MTU
/// (mirrors `run_store`'s `FRAME_CAP`).
pub const COURSE_CHUNK_CAP: usize = 244;

/// Frame length for a course of `point_count` points.
pub const fn course_frame_len(point_count: usize) -> usize {
    COURSE_HEADER_LEN + point_count * COURSE_POINT_LEN
}

/// Encode a course polyline into `out` as a CRS1 frame, returning the byte length
/// written. `None` when the course is too short (< 2) or over the tier-1 capacity
/// (> [`MAX_COURSE_POINTS`]) — fail-closed, matching [`Course::from_points`] — or
/// when `out` is smaller than the frame needs. lat/lon are quantised to 1e-7
/// degrees (round half away from zero, matching the Dart encoder).
pub fn encode(points: &[CoursePoint], out: &mut [u8]) -> Option<usize> {
    if points.len() < 2 || points.len() > MAX_COURSE_POINTS {
        return None;
    }
    let len = course_frame_len(points.len());
    if out.len() < len {
        return None;
    }
    out[0..4].copy_from_slice(&COURSE_MAGIC);
    out[4] = COURSE_FORMAT_VERSION;
    out[5..7].copy_from_slice(&(points.len() as u16).to_le_bytes());
    let mut off = COURSE_HEADER_LEN;
    for p in points {
        let lat_e7 = libm::round(p.lat_deg * 1e7) as i32;
        let lon_e7 = libm::round(p.lon_deg * 1e7) as i32;
        out[off..off + 4].copy_from_slice(&lat_e7.to_le_bytes());
        out[off + 4..off + 8].copy_from_slice(&lon_e7.to_le_bytes());
        off += COURSE_POINT_LEN;
    }
    Some(len)
}

/// Decode a CRS1 frame into a [`Course`]. `None` on a bad magic, an unknown
/// version, a point count outside `2..=MAX_COURSE_POINTS` (fail-closed overflow
/// rejection), a length that doesn't match the declared count (trailing / short
/// bytes), or a non-finite point.
pub fn decode(frame: &[u8]) -> Option<Course> {
    if frame.len() < COURSE_HEADER_LEN
        || frame[0..4] != COURSE_MAGIC
        || frame[4] != COURSE_FORMAT_VERSION
    {
        return None;
    }
    let count = u16::from_le_bytes([frame[5], frame[6]]) as usize;
    if !(2..=MAX_COURSE_POINTS).contains(&count) {
        return None;
    }
    if frame.len() != course_frame_len(count) {
        return None;
    }
    let mut points: Vec<CoursePoint, MAX_COURSE_POINTS> = Vec::new();
    let mut off = COURSE_HEADER_LEN;
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
    Course::from_points(&points)
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
        if self.buf.len() < COURSE_HEADER_LEN {
            return CoursePush::More;
        }
        // The header is in: validate it early so a bad stream fails fast instead
        // of accreting bytes toward a frame that can never decode.
        if self.buf[0..4] != COURSE_MAGIC || self.buf[4] != COURSE_FORMAT_VERSION {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        let count = u16::from_le_bytes([self.buf[5], self.buf[6]]) as usize;
        if !(2..=MAX_COURSE_POINTS).contains(&count) {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        let want = course_frame_len(count);
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

    fn encode_vec(points: &[CoursePoint]) -> std::vec::Vec<u8> {
        let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
        let n = encode(points, &mut buf).expect("encodes");
        buf[..n].to_vec()
    }

    #[test]
    fn round_trips_a_small_course() {
        let pts = sim_points();
        let frame = encode_vec(&pts);
        assert_eq!(frame.len(), course_frame_len(3));
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

    /// Golden vector: the exact bytes the sim course produces. The Dart encoder
    /// (`watch_course.dart`) pins this same hex, so a format drift on either side
    /// fails a test rather than silently corrupting a pushed course.
    #[test]
    fn golden_frame_is_stable() {
        let frame = encode_vec(&sim_points());
        let hex = frame
            .iter()
            .fold(heapless::String::<128>::new(), |mut s, b| {
                let _ = core::fmt::write(&mut s, format_args!("{:02x}", b));
                s
            });
        assert_eq!(
            hex.as_str(),
            "4352533101030083edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_course.dart"
        );
    }

    #[test]
    fn encode_rejects_too_few_and_too_many_points() {
        assert!(encode(&[], &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        assert!(encode(&[pt(1.0, 2.0)], &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        let over: std::vec::Vec<CoursePoint> = (0..=MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        assert!(encode(&over, &mut [0u8; MAX_COURSE_FRAME_LEN]).is_none());
        let at_cap: std::vec::Vec<CoursePoint> = (0..MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
        assert_eq!(encode(&at_cap, &mut buf), Some(MAX_COURSE_FRAME_LEN));
    }

    #[test]
    fn encode_rejects_a_buffer_too_small() {
        let mut tiny = [0u8; COURSE_HEADER_LEN + COURSE_POINT_LEN]; // room for one point, needs two
        assert!(encode(&sim_points(), &mut tiny).is_none());
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
        bad_ver[4] = 2;
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
    }
}
