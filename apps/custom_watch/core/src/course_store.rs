//! Phone→watch breadcrumb-course wire format + chunked reassembly.
//!
//! The phone pushes a route the runner wants to follow to the watch as a
//! fixed little-endian frame the firmware decodes into the [`Course`] the nav
//! task already consumes:
//!
//!   magic("CRS1", 4) | version(1) | point_count(2, u16 LE) | flags(1) |
//!   point[N] | elev_m[N]? | crc32(4, u32 LE)
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
//! count, length, unknown flag bit, or a failed checksum is rejected rather than
//! half-applied, so a corrupt push can never load a truncated or displaced
//! course mid-race.
//!
//! Host-tested (encode/decode round-trip, overflow rejection, chunk reassembly,
//! a golden byte vector per shape) against the Dart encoder
//! (`watch_course.dart`), which pins the SAME golden vectors, so the two wire
//! codecs can't drift.
//!
//! **The checksum is mandatory, and v1 / v2 no longer decode.** The settings
//! frame kept its pre-CRC versions decodable so an old phone's push still
//! configures the watch; that trade does not carry over here, for two reasons.
//! A rejected *settings* push leaves the previous config in place and every
//! field it carries is range-checked on the apply side, so corruption has a
//! second net; a course has no plausibility guard at all — any lat/lon on the
//! 1e-7 grid is a legal course, so a displaced polyline is indistinguishable
//! from a real one, and it is the polyline the off-course alert calibrates
//! against and the nav page draws. Silently following a subtly wrong breadcrumb
//! in the backcountry is materially worse than loading no course and saying so.
//! And an accepted un-checksummed version is a bypass: any frame that fails the
//! CRC can claim to be v2 instead, which would leave the check decorative. The
//! encoder here and the phone encoder are the same repo and version together;
//! an older phone build pushing v2 gets an honest "no course loaded" rather
//! than a plausible wrong one.

use heapless::Vec;

use crate::course::{Course, CoursePoint, MAX_COURSE_POINTS};
use crate::run_store::crc32;

/// Course frame magic — "CRS1".
pub const COURSE_MAGIC: [u8; 4] = *b"CRS1";

/// Version 3 (2026-07-26): the frame gained a CRC32 trailer. Its only integrity
/// check had been that the byte count accounts for the declared point count and
/// flags, which catches a truncation but not a flipped byte inside the point
/// array — that decodes as a perfectly valid course displaced by up to a
/// continent, and the off-course alert then calibrates against the wrong line.
/// Unlike [`crate::settings`], the pre-CRC versions are **not** still accepted
/// (module docs carry the reasoning); the encoder emits v3 only.
pub const COURSE_FORMAT_VERSION: u8 = 3;

/// Presence bit: the frame ends with one `i16 LE` metre elevation per point.
pub const COURSE_FLAG_ELEV: u8 = 1 << 0;

/// Every presence bit the flags byte defines. A set bit outside this mask can't
/// be a forward-compatible field — a new field rides a version bump, which
/// `decode` rejects on the version byte — so an unknown bit means a corrupt or
/// misframed push, and `decode` rejects the frame rather than silently dropping
/// whatever the sender meant by it (the `settings::KNOWN_FLAGS` rule).
const KNOWN_COURSE_FLAGS: u8 = COURSE_FLAG_ELEV;

/// Header: magic(4) + version(1) + point_count(2) + flags(1).
pub const COURSE_HEADER_LEN: usize = 8;
/// One point: lat_e7(4) + lon_e7(4).
pub const COURSE_POINT_LEN: usize = 8;
/// One elevation sample: metres as `i16 LE`. Metres, not decimetres — a
/// decimetre i16 tops out at 3276.7 m, below Mont Blanc.
pub const COURSE_ELEV_LEN: usize = 2;
/// The CRC32 trailer, little-endian, over every byte before it.
const COURSE_CRC_LEN: usize = 4;

/// Largest a full frame can be — a header plus [`MAX_COURSE_POINTS`] points,
/// their elevations, and the CRC trailer.
pub const MAX_COURSE_FRAME_LEN: usize = course_frame_len(MAX_COURSE_POINTS, true);

/// The BLE `course` write characteristic's value cap: one chunk is
/// `offset(2) | payload`, sized to fit inside one ATT write at the 256-byte MTU
/// (mirrors `run_store`'s `FRAME_CAP`).
pub const COURSE_CHUNK_CAP: usize = 244;

/// Frame length for a course of `point_count` points, with or without the
/// elevation series.
pub const fn course_frame_len(point_count: usize, with_elevation: bool) -> usize {
    COURSE_HEADER_LEN
        + point_count * COURSE_POINT_LEN
        + if with_elevation {
            point_count * COURSE_ELEV_LEN
        } else {
            0
        }
        + COURSE_CRC_LEN
}

/// Encode a course polyline — and, when the phone has one, its per-point
/// elevation in metres — into `out` as a CRS1 v3 frame, returning the byte
/// length written. `None` when the course is too short (< 2) or over the tier-1
/// capacity (> [`MAX_COURSE_POINTS`]) — fail-closed, matching
/// [`Course::from_points`] — when `elev_m` is present but doesn't carry exactly
/// one sample per point, or when `out` is smaller than the frame needs. lat/lon
/// are quantised to 1e-7 degrees (round half away from zero, matching the Dart
/// encoder), then the CRC32 trailer seals everything before it.
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
    let crc = crc32(&out[..off]).to_le_bytes();
    out[off..off + COURSE_CRC_LEN].copy_from_slice(&crc);
    Some(len)
}

/// Whether the frame's trailing CRC32 matches the bytes it covers. Callers have
/// already established that the frame is exactly as long as its header claims,
/// so splitting off the trailer can't underflow.
fn crc_matches(frame: &[u8]) -> bool {
    let body = frame.len() - COURSE_CRC_LEN;
    let want = u32::from_le_bytes([
        frame[body],
        frame[body + 1],
        frame[body + 2],
        frame[body + 3],
    ]);
    crc32(&frame[..body]) == want
}

/// Decode a CRS1 v3 frame into a [`Course`]. `None` on a bad magic, any version
/// but the current one, an unknown flag bit, a point count outside
/// `2..=MAX_COURSE_POINTS` (fail-closed overflow rejection), a length that
/// doesn't match the declared count + flags (trailing / short bytes), or a CRC
/// that doesn't match the bytes it covers.
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
    let flags = frame[7];
    if flags & !KNOWN_COURSE_FLAGS != 0 {
        return None;
    }
    let with_elev = flags & COURSE_FLAG_ELEV != 0;
    if frame.len() != course_frame_len(count, with_elev) {
        return None;
    }
    if !crc_matches(frame) {
        return None;
    }
    let mut off = COURSE_HEADER_LEN;
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
    /// the frame is now whole *and* passes its checksum, [`CoursePush::More`]
    /// when more chunks are needed, or [`CoursePush::Rejected`] on a malformed /
    /// out-of-order / overflowing chunk or a failed CRC (buffer reset). An
    /// `offset` of 0 restarts a fresh push, so a rejected stream self-heals on
    /// the phone's next attempt.
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
        let flags = self.buf[7];
        if flags & !KNOWN_COURSE_FLAGS != 0 {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        let want = course_frame_len(count, flags & COURSE_FLAG_ELEV != 0);
        if self.buf.len() < want {
            return CoursePush::More;
        }
        if self.buf.len() > want {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        // The checksum is the last gate, so `Complete` means the frame will
        // decode — the nav task never sees a whole-but-corrupt course.
        if !crc_matches(&self.buf) {
            self.buf.clear();
            return CoursePush::Rejected;
        }
        CoursePush::Complete
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

    /// Build a v3 frame around `body` (header + points + elevation) by appending
    /// the CRC the decoder will check, so a test can exercise a rejection *past*
    /// the checksum rather than tripping on it.
    fn sealed(body: &[u8]) -> std::vec::Vec<u8> {
        let mut frame = body.to_vec();
        frame.extend_from_slice(&crc32(body).to_le_bytes());
        frame
    }

    /// A pre-CRC frame as an older phone build would send it: `version` 1 with a
    /// 7-byte header (no flags byte), or `version` 2 with the flags byte, neither
    /// carrying a trailer.
    fn legacy_frame(version: u8, points: &[CoursePoint]) -> std::vec::Vec<u8> {
        let mut out = std::vec::Vec::new();
        out.extend_from_slice(&COURSE_MAGIC);
        out.push(version);
        out.extend_from_slice(&(points.len() as u16).to_le_bytes());
        if version == 2 {
            out.push(0);
        }
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
    fn an_elevation_less_frame_decodes_to_a_course_without_a_profile() {
        let course = decode(&encode_vec(&sim_points())).expect("decodes");
        assert!(course.elevations().is_none());
    }

    /// Golden vector: the exact bytes the sim course produces. The Dart encoder
    /// (`watch_course.dart`) pins this same hex, so a format drift on either side
    /// fails a test rather than silently corrupting a pushed course.
    #[test]
    fn golden_frame_is_stable() {
        let frame = encode_vec(&sim_points());
        assert_eq!(
            hex_of(&frame).as_str(),
            "435253310303000083edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c114996437",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_course.dart"
        );
        // The trailer is the derived checksum of everything before it, not just
        // the literal pinned above.
        let body = frame.len() - COURSE_CRC_LEN;
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

    /// The elevation-bearing golden vector, pinned on both sides like the
    /// elevation-less one above.
    #[test]
    fn golden_elevation_frame_is_stable() {
        assert_eq!(
            hex_of(&encode_vec_with(&sim_points(), Some(&SIM_ELEV_M))).as_str(),
            "435253310303000183edd91718ff40c1f0cdd91718ff40c1f0cdd9174e2841c1\
             720677066806b8269c11",
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

    /// The pre-CRC layouts are refused outright. Accepting them would leave the
    /// checksum decorative — a frame that fails it could simply claim to be v2 —
    /// and a displaced course is worse than no course (see the module docs).
    #[test]
    fn decode_rejects_the_pre_crc_versions() {
        for version in [1u8, 2] {
            let frame = legacy_frame(version, &sim_points());
            assert!(decode(&frame).is_none(), "v{version} frame decoded");
            // Nor does bolting a valid trailer onto the legacy body rescue it —
            // the version byte is what's checked.
            assert!(
                decode(&sealed(&frame)).is_none(),
                "sealed v{version} decoded"
            );
        }
    }

    #[test]
    fn decode_rejects_an_unknown_version_and_an_unknown_flag_bit() {
        let mut future = encode_vec(&sim_points());
        future[4] = COURSE_FORMAT_VERSION + 1;
        assert!(decode(&future).is_none());
        // Re-sealed, so the rejection is the flag check rather than the CRC.
        let body = encode_vec(&sim_points());
        let body = &body[..body.len() - COURSE_CRC_LEN];
        let mut odd_flag = body.to_vec();
        odd_flag[7] = 1 << 1;
        assert!(decode(&sealed(&odd_flag)).is_none());
        // A frame whose flags claim elevation but whose length doesn't carry it.
        let mut lying_flag = body.to_vec();
        lying_flag[7] = COURSE_FLAG_ELEV;
        assert!(decode(&sealed(&lying_flag)).is_none());
    }

    #[test]
    fn decode_rejects_a_truncated_elevation_series() {
        let frame = encode_vec_with(&sim_points(), Some(&SIM_ELEV_M));
        assert!(decode(&frame[..frame.len() - 2]).is_none());
        let mut long = frame.clone();
        long.push(0x00);
        long.push(0x00);
        assert!(decode(&long).is_none());
        // Re-sealed at each wrong length, so the length check is doing its own
        // job underneath the checksum.
        let body = &frame[..frame.len() - COURSE_CRC_LEN];
        assert!(decode(&sealed(&body[..body.len() - 2])).is_none());
        let mut over = body.to_vec();
        over.extend_from_slice(&[0x00, 0x00]);
        assert!(decode(&sealed(&over)).is_none());
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
        // A header with no room for the trailer at all is short, not v2.
        assert!(decode(&frame[..COURSE_HEADER_LEN + COURSE_POINT_LEN]).is_none());
    }

    #[test]
    fn decode_rejects_a_length_that_disagrees_with_the_count() {
        let frame = encode_vec(&sim_points());
        // One byte short: the count claims 3 points, bytes lack the last.
        assert!(decode(&frame[..frame.len() - 1]).is_none());
        // Trailing byte past the declared points.
        let mut long = frame.clone();
        long.push(0x00);
        assert!(decode(&long).is_none());
    }

    /// Appending to a frame invalidates its checksum, so the CRC alone rejects
    /// the naive case. Re-sealing the longer frame proves the exact-length check
    /// still stands on its own.
    #[test]
    fn trailing_bytes_are_rejected_even_when_the_crc_covers_them() {
        let frame = encode_vec(&sim_points());
        let mut body = frame[..frame.len() - COURSE_CRC_LEN].to_vec();
        body.push(0x00);
        assert!(decode(&sealed(&body)).is_none());
    }

    /// The reproducer the v3 bump exists for: one byte of the point array, and
    /// the course the watch follows is displaced — the polyline is still legal
    /// (every lat/lon on the 1e-7 grid is), the length still agrees, and there is
    /// no plausibility guard downstream, so the off-course alert would calibrate
    /// against the wrong line. The CRC turns it into a rejection.
    #[test]
    fn a_single_byte_corruption_of_a_point_cannot_displace_the_course() {
        let frame = encode_vec(&sim_points());
        let body = &frame[..frame.len() - COURSE_CRC_LEN];

        // Re-sealed, the corruption is a perfectly well-formed frame — the
        // length check has nothing to catch, which is the whole defect.
        let mut displaced = body.to_vec();
        displaced[COURSE_HEADER_LEN + 3] ^= 0x04;
        let course = decode(&sealed(&displaced)).expect("length-valid under its crc");
        let honest = decode(&frame).expect("decodes");
        let off_deg = (course.points()[0].lat_deg - honest.points()[0].lat_deg).abs();
        assert!(
            off_deg > 0.5,
            "corruption moved the point only {off_deg} deg"
        );

        // Over the wire the sender's CRC travels with the frame, so the same
        // flip is rejected outright rather than followed as a different course.
        let mut corrupt = frame.clone();
        corrupt[COURSE_HEADER_LEN + 3] ^= 0x04;
        assert!(decode(&corrupt).is_none());
    }

    #[test]
    fn a_frame_whose_crc_does_not_match_is_rejected() {
        for frame in [
            encode_vec(&sim_points()),
            encode_vec_with(&sim_points(), Some(&SIM_ELEV_M)),
        ] {
            assert!(decode(&frame).is_some());
            for at in 0..COURSE_CRC_LEN {
                let mut bad = frame.clone();
                bad[frame.len() - COURSE_CRC_LEN + at] ^= 0x01;
                assert!(decode(&bad).is_none(), "a flipped crc byte {at} decoded");
            }
        }
    }

    #[test]
    fn decode_rejects_an_over_cap_or_too_small_count() {
        let frame = encode_vec(&sim_points());
        let body = &frame[..frame.len() - COURSE_CRC_LEN];
        // Claim 257 points (over MAX_COURSE_POINTS) — rejected before any read,
        // re-sealed so the count check fires rather than the CRC.
        let mut over = body.to_vec();
        over[5..7].copy_from_slice(&((MAX_COURSE_POINTS as u16) + 1).to_le_bytes());
        assert!(decode(&sealed(&over)).is_none());
        // Claim 1 point — a course must have >= 2.
        let mut one = body.to_vec();
        one[5..7].copy_from_slice(&1u16.to_le_bytes());
        assert!(decode(&sealed(&one)).is_none());
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

    /// A whole-but-corrupt frame must never reach `Complete`: the nav task
    /// decodes whatever the assembler calls complete, so the checksum is the
    /// assembler's last gate too, and a rejection clears the buffer so the
    /// phone's next offset-0 write recovers.
    #[test]
    fn assembler_rejects_a_whole_frame_whose_crc_fails() {
        let mut frame = encode_vec(&sim_points());
        frame[COURSE_HEADER_LEN] ^= 0x01;
        let mut asm = CourseAssembler::new();
        let parts = chunks(&frame, 8);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let outcome = asm.push(*off, payload);
            if i < parts.len() - 1 {
                assert_eq!(outcome, CoursePush::More, "at chunk {i}");
            } else {
                assert_eq!(outcome, CoursePush::Rejected, "corrupt frame completed");
            }
        }
        assert!(asm.frame().is_empty());
        // The buffer is clean, so an honest re-push lands.
        let honest = encode_vec(&sim_points());
        let mut last = CoursePush::More;
        for (off, payload) in chunks(&honest, 8) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, CoursePush::Complete);
    }

    #[test]
    fn assembler_rejects_a_bad_header_stream() {
        let mut asm = CourseAssembler::new();
        // A full header with the wrong magic fails as soon as it's in.
        let bad = [
            b'X',
            b'X',
            b'X',
            b'X',
            COURSE_FORMAT_VERSION,
            0x03,
            0x00,
            0x00,
        ];
        assert_eq!(asm.push(0, &bad), CoursePush::Rejected);
        assert!(asm.frame().is_empty());
        // A pre-CRC version fails on the version byte, same as `decode`.
        for version in [1u8, 2] {
            let mut legacy = [0u8; COURSE_HEADER_LEN];
            legacy[0..4].copy_from_slice(&COURSE_MAGIC);
            legacy[4] = version;
            legacy[5..7].copy_from_slice(&3u16.to_le_bytes());
            assert_eq!(asm.push(0, &legacy), CoursePush::Rejected, "v{version}");
        }
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
