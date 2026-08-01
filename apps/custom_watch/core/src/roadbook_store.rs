//! Phone→watch roadbook + cut-off schedule wire format + chunked reassembly.
//!
//! The compute behind the Roadbook, CutoffEta, Fuel and SleepStation pages has
//! been host-tested and correct for a while, and every one of them was inert on
//! hardware: [`crate::record::Recorder::set_roadbook`] had no non-test caller at
//! all, [`crate::record::Recorder::set_cutoff_legs`] only the canned
//! `SIM_CUTOFFS` behind the `sim-course` feature, and `CRS1` carries neither
//! series. This module is the missing wire.
//!
//!   magic("RBK1", 4) | version(1) | checkpoint_count(1, u8) |
//!   cutoff_count(1, u8) | flags(1) | checkpoint[N] | cutoff[M] |
//!   crc32(4, u32 LE)
//!
//! where each checkpoint is `cum_dist_m(4, u32 LE) | leg_dist_m(4, u32 LE) |
//! projected_elapsed_s(4, u32 LE) | cutoff(1, u8) | flags(1, u8)` — the cutoff
//! byte naming [`CutoffStatus`] (0 none / 1 safe / 2 tight / 3 miss) and the
//! flags byte carrying [`CHECKPOINT_FLAG_REFILL`] — and each cut-off leg is
//! `cum_dist_m(4, u32 LE) | limit_elapsed_s(4, u32 LE)`.
//!
//! Distances travel as whole metres, not the `f64` the structs hold: a metre is
//! four orders below the GPS noise the along-course projection carries, and a
//! `u32` covers 4,294 km of course — past any staged ultra. The checkpoints keep
//! no name, deliberately ([`crate::record::RoadbookCheckpoint`] is a `Copy`
//! struct because the phone holds the names and the panel has no room for
//! them).
//!
//! **Both series ride one frame, and neither is derivable from the other.** A
//! checkpoint's `cutoff` is the phone's *verdict* against its own goal-time
//! projection; a [`CutoffLeg`] is the *limit itself*, which is what
//! [`crate::cutoff_eta`] needs to project a live arrival off the runner's own
//! recent pace. Pushing them together also means one frame is the whole
//! schedule, so a re-push replaces it and cannot leave the Roadbook page
//! describing one race while the CutoffEta page projects another.
//!
//! Binary, chunked, CRC-sealed — the [`crate::course_store`] discipline
//! exactly, with the checksum **mandatory from v1** so there is no
//! pre-checksum version to fall back to. § 403 had to withdraw exactly that
//! hole from the settings frame: an accepted un-checksummed version is a
//! bypass, because any frame failing the CRC can simply claim to be the older
//! version, which leaves the check decorative. The stakes here match the
//! course's rather than the settings frame's — a settings push is
//! range-checked field by field on the apply side, whereas any monotonic
//! distance/time pair is a legal schedule, so a corrupt one is
//! indistinguishable from a real one and would be shown as the runner's
//! cut-off margin, their nap budget, and their pacer's terrain schedule.
//!
//! A frame declaring more than [`MAX_PUSHED_LEGS`] checkpoints or
//! [`MAX_CUTOFF_LEGS`] cut-offs is **refused, not truncated**: those setters cap
//! rather than grow, and silently dropping the last aid stations of a course
//! would hide the cut-offs nearest the finish — the ones that end races.
//! Trimming to fit is the phone's job, where there is a runner to tell.
//!
//! Zero of both counts is a legal frame and means *clear*: the pages fall back
//! to the honest inactive states they read before any push, rather than keeping
//! the finished race's legs.
//!
//! Host-tested with a golden byte vector the Dart encoder
//! (`watch_roadbook.dart`) pins too, so the two wire codecs can't drift.

use heapless::Vec;

use crate::cutoff_eta::CutoffLeg;
use crate::record::{RoadbookCheckpoint, MAX_CUTOFF_LEGS, MAX_PUSHED_LEGS};
use crate::roadbook::CutoffStatus;
use crate::run_store::crc32;

/// Roadbook frame magic — "RBK1".
pub const ROADBOOK_MAGIC: [u8; 4] = *b"RBK1";

/// Version 1. There is no pre-checksum version and there never was — see the
/// module docs for why one would make the CRC decorative.
pub const ROADBOOK_FORMAT_VERSION: u8 = 1;

/// Per-checkpoint flag: this checkpoint offers water/food, so the Fuel page
/// treats it as a refill point.
pub const CHECKPOINT_FLAG_REFILL: u8 = 1 << 0;

/// Every per-checkpoint flag bit defined. A set bit outside this mask can't be
/// a forward-compatible field — a new field rides a version bump — so it means
/// a corrupt or misframed push (the `settings::KNOWN_FLAGS` rule).
const KNOWN_CHECKPOINT_FLAGS: u8 = CHECKPOINT_FLAG_REFILL;

/// No frame-level presence bits yet; any set bit rejects, same rule.
const KNOWN_ROADBOOK_FLAGS: u8 = 0;

/// Header: magic(4) + version(1) + checkpoint_count(1) + cutoff_count(1) +
/// flags(1).
pub const ROADBOOK_HEADER_LEN: usize = 8;
/// One checkpoint: cum_dist(4) + leg_dist(4) + projected_elapsed(4) +
/// cutoff(1) + flags(1).
pub const ROADBOOK_CHECKPOINT_LEN: usize = 14;
/// One cut-off leg: cum_dist(4) + limit_elapsed(4).
pub const ROADBOOK_CUTOFF_LEN: usize = 8;
const ROADBOOK_CRC_LEN: usize = 4;

/// Largest a full frame can be — the header plus both series at their caps and
/// the CRC trailer. 364 B, which is why the push is chunked: one ATT write at
/// the `ble` task's 256-byte MTU carries at most `MTU - 3` = 253 bytes.
pub const MAX_ROADBOOK_FRAME_LEN: usize = roadbook_frame_len(MAX_PUSHED_LEGS, MAX_CUTOFF_LEGS);

/// The BLE `roadbook` write characteristic's chunk cap, mirroring
/// [`crate::course_store::COURSE_CHUNK_CAP`].
pub const ROADBOOK_CHUNK_CAP: usize = 244;

/// Frame length for a schedule of `checkpoints` checkpoints and `cutoffs`
/// cut-off legs.
pub const fn roadbook_frame_len(checkpoints: usize, cutoffs: usize) -> usize {
    ROADBOOK_HEADER_LEN
        + checkpoints * ROADBOOK_CHECKPOINT_LEN
        + cutoffs * ROADBOOK_CUTOFF_LEN
        + ROADBOOK_CRC_LEN
}

/// A decoded `RBK1` push: the roadbook checkpoints and the cut-off legs, ready
/// for [`crate::record::Recorder::set_roadbook`] and
/// [`crate::record::Recorder::set_cutoff_legs`]. Both empty is the clear.
#[derive(Clone, Debug, PartialEq)]
pub struct PushedRoadbook {
    pub checkpoints: Vec<RoadbookCheckpoint, MAX_PUSHED_LEGS>,
    pub cutoffs: Vec<CutoffLeg, MAX_CUTOFF_LEGS>,
}

impl Default for PushedRoadbook {
    fn default() -> Self {
        Self::new()
    }
}

impl PushedRoadbook {
    pub const fn new() -> Self {
        Self {
            checkpoints: Vec::new(),
            cutoffs: Vec::new(),
        }
    }

    /// Whether this push carries no schedule at all — the explicit clear.
    pub fn is_empty(&self) -> bool {
        self.checkpoints.is_empty() && self.cutoffs.is_empty()
    }
}

fn status_code(status: Option<CutoffStatus>) -> u8 {
    match status {
        None => 0,
        Some(CutoffStatus::Safe) => 1,
        Some(CutoffStatus::Tight) => 2,
        Some(CutoffStatus::Miss) => 3,
    }
}

/// `None` for a byte that names no status — the `WorkoutStepKind::from_code`
/// rule: an unknown code rejects the whole frame rather than being read as
/// "no cutoff", which would silently turn a missed cut-off into a blank cell.
fn status_from_code(code: u8) -> Option<Option<CutoffStatus>> {
    match code {
        0 => Some(None),
        1 => Some(Some(CutoffStatus::Safe)),
        2 => Some(Some(CutoffStatus::Tight)),
        3 => Some(Some(CutoffStatus::Miss)),
        _ => None,
    }
}

/// A metre distance as the wire's `u32`, or `None` when it cannot be
/// represented — non-finite, negative, or past `u32::MAX` metres. Fail-closed
/// at the sender: a clamp would push a plausible wrong distance.
fn metres(m: f64) -> Option<u32> {
    if !m.is_finite() || m < 0.0 {
        return None;
    }
    let rounded = libm::round(m);
    if rounded > u32::MAX as f64 {
        return None;
    }
    Some(rounded as u32)
}

/// Encode a roadbook + cut-off schedule into `out` as an `RBK1` v1 frame,
/// returning the byte length written. `None` when either series is over its cap
/// ([`MAX_PUSHED_LEGS`] / [`MAX_CUTOFF_LEGS`] — refused, not trimmed), when a
/// distance can't be represented in whole metres, or when `out` is smaller than
/// the frame needs. The CRC32 trailer seals everything before it.
pub fn encode(
    checkpoints: &[RoadbookCheckpoint],
    cutoffs: &[CutoffLeg],
    out: &mut [u8],
) -> Option<usize> {
    if checkpoints.len() > MAX_PUSHED_LEGS || cutoffs.len() > MAX_CUTOFF_LEGS {
        return None;
    }
    let len = roadbook_frame_len(checkpoints.len(), cutoffs.len());
    if out.len() < len {
        return None;
    }
    out[0..4].copy_from_slice(&ROADBOOK_MAGIC);
    out[4] = ROADBOOK_FORMAT_VERSION;
    out[5] = checkpoints.len() as u8;
    out[6] = cutoffs.len() as u8;
    out[7] = 0;
    let mut off = ROADBOOK_HEADER_LEN;
    for cp in checkpoints {
        out[off..off + 4].copy_from_slice(&metres(cp.cum_dist_m)?.to_le_bytes());
        out[off + 4..off + 8].copy_from_slice(&metres(cp.leg_dist_m)?.to_le_bytes());
        out[off + 8..off + 12].copy_from_slice(&cp.projected_elapsed_s.to_le_bytes());
        out[off + 12] = status_code(cp.cutoff);
        out[off + 13] = if cp.is_refill {
            CHECKPOINT_FLAG_REFILL
        } else {
            0
        };
        off += ROADBOOK_CHECKPOINT_LEN;
    }
    for leg in cutoffs {
        out[off..off + 4].copy_from_slice(&metres(leg.cum_dist_m)?.to_le_bytes());
        out[off + 4..off + 8].copy_from_slice(&leg.limit_elapsed_s.to_le_bytes());
        off += ROADBOOK_CUTOFF_LEN;
    }
    let crc = crc32(&out[..off]).to_le_bytes();
    out[off..off + ROADBOOK_CRC_LEN].copy_from_slice(&crc);
    Some(len)
}

/// Whether the frame's trailing CRC32 matches the bytes it covers. Callers have
/// already established the frame is exactly as long as its header claims, so
/// splitting off the trailer can't underflow.
fn crc_matches(frame: &[u8]) -> bool {
    let body = frame.len() - ROADBOOK_CRC_LEN;
    let want = u32::from_le_bytes([
        frame[body],
        frame[body + 1],
        frame[body + 2],
        frame[body + 3],
    ]);
    crc32(&frame[..body]) == want
}

/// Validate the header bytes: `Some(frame_len)` for a header that names a frame
/// this build understands, `None` otherwise. Shared by [`decode`] and
/// [`RoadbookAssembler::push`] so the reassembler's early rejection and the
/// decoder's cannot disagree about what a legal header is.
fn header_frame_len(head: &[u8]) -> Option<usize> {
    if head.len() < ROADBOOK_HEADER_LEN
        || head[0..4] != ROADBOOK_MAGIC
        || head[4] != ROADBOOK_FORMAT_VERSION
    {
        return None;
    }
    let checkpoints = head[5] as usize;
    let cutoffs = head[6] as usize;
    if checkpoints > MAX_PUSHED_LEGS || cutoffs > MAX_CUTOFF_LEGS {
        return None;
    }
    if head[7] & !KNOWN_ROADBOOK_FLAGS != 0 {
        return None;
    }
    Some(roadbook_frame_len(checkpoints, cutoffs))
}

/// Decode an `RBK1` v1 frame. `None` on a bad magic, any version but the
/// current one, a count over either cap (checked *before* any indexed read), an
/// unknown frame or checkpoint flag bit, a length that disagrees with the
/// declared counts, a cut-off byte naming no status, or a CRC that doesn't
/// match — never a partially-applied schedule.
pub fn decode(frame: &[u8]) -> Option<PushedRoadbook> {
    if frame.len() != header_frame_len(frame)? {
        return None;
    }
    if !crc_matches(frame) {
        return None;
    }
    let checkpoint_count = frame[5] as usize;
    let cutoff_count = frame[6] as usize;
    let mut out = PushedRoadbook::new();
    let mut off = ROADBOOK_HEADER_LEN;
    for _ in 0..checkpoint_count {
        let flags = frame[off + 13];
        if flags & !KNOWN_CHECKPOINT_FLAGS != 0 {
            return None;
        }
        let cp = RoadbookCheckpoint {
            cum_dist_m: f64::from(u32::from_le_bytes([
                frame[off],
                frame[off + 1],
                frame[off + 2],
                frame[off + 3],
            ])),
            leg_dist_m: f64::from(u32::from_le_bytes([
                frame[off + 4],
                frame[off + 5],
                frame[off + 6],
                frame[off + 7],
            ])),
            projected_elapsed_s: u32::from_le_bytes([
                frame[off + 8],
                frame[off + 9],
                frame[off + 10],
                frame[off + 11],
            ]),
            cutoff: status_from_code(frame[off + 12])?,
            is_refill: flags & CHECKPOINT_FLAG_REFILL != 0,
        };
        out.checkpoints.push(cp).ok()?;
        off += ROADBOOK_CHECKPOINT_LEN;
    }
    for _ in 0..cutoff_count {
        let leg = CutoffLeg {
            cum_dist_m: f64::from(u32::from_le_bytes([
                frame[off],
                frame[off + 1],
                frame[off + 2],
                frame[off + 3],
            ])),
            limit_elapsed_s: u32::from_le_bytes([
                frame[off + 4],
                frame[off + 5],
                frame[off + 6],
                frame[off + 7],
            ]),
        };
        out.cutoffs.push(leg).ok()?;
        off += ROADBOOK_CUTOFF_LEN;
    }
    Some(out)
}

/// The outcome of feeding one chunk to a [`RoadbookAssembler`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoadbookPush {
    More,
    /// The frame is whole and passes its checksum — [`RoadbookAssembler::frame`]
    /// is ready to [`decode`].
    Complete,
    /// A malformed / out-of-order / overflowing chunk or a failed CRC; the
    /// buffer was reset.
    Rejected,
}

/// Reassembles a chunked roadbook push — `offset | payload` writes in order,
/// offset 0 restarting the buffer, every malformation failing closed with a
/// reset so the phone's next offset-0 write recovers. The
/// [`crate::course_store::CourseAssembler`] contract over the `RBK1` header.
pub struct RoadbookAssembler {
    buf: Vec<u8, MAX_ROADBOOK_FRAME_LEN>,
}

impl Default for RoadbookAssembler {
    fn default() -> Self {
        Self::new()
    }
}

impl RoadbookAssembler {
    pub const fn new() -> Self {
        Self { buf: Vec::new() }
    }

    pub fn reset(&mut self) {
        self.buf.clear();
    }

    pub fn frame(&self) -> &[u8] {
        &self.buf
    }

    pub fn push(&mut self, offset: usize, payload: &[u8]) -> RoadbookPush {
        if offset == 0 {
            self.buf.clear();
        }
        if offset != self.buf.len() {
            self.buf.clear();
            return RoadbookPush::Rejected;
        }
        if self.buf.extend_from_slice(payload).is_err() {
            self.buf.clear();
            return RoadbookPush::Rejected;
        }
        if self.buf.len() < ROADBOOK_HEADER_LEN {
            return RoadbookPush::More;
        }
        // Validate the header as soon as it's whole so a bad stream fails fast
        // instead of accreting bytes toward a frame that can never decode.
        let Some(want) = header_frame_len(&self.buf) else {
            self.buf.clear();
            return RoadbookPush::Rejected;
        };
        if self.buf.len() < want {
            return RoadbookPush::More;
        }
        if self.buf.len() > want {
            self.buf.clear();
            return RoadbookPush::Rejected;
        }
        // The checksum is the last gate, so `Complete` means the frame will
        // decode past it — the record task never loads a whole-but-corrupt
        // schedule (the per-checkpoint status + flag checks still run in
        // `decode`).
        if !crc_matches(&self.buf) {
            self.buf.clear();
            return RoadbookPush::Rejected;
        }
        RoadbookPush::Complete
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The canned sim schedule the `record` task carries behind `sim-course`:
    /// start, an aid at 90 m, the 180 m finish. Every value is a whole metre /
    /// second so the wire quantisation is lossless and the golden is stable.
    fn sim_checkpoints() -> [RoadbookCheckpoint; 3] {
        [
            RoadbookCheckpoint {
                cum_dist_m: 0.0,
                leg_dist_m: 0.0,
                projected_elapsed_s: 0,
                cutoff: None,
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 90.0,
                leg_dist_m: 90.0,
                projected_elapsed_s: 30,
                cutoff: Some(CutoffStatus::Safe),
                is_refill: true,
            },
            RoadbookCheckpoint {
                cum_dist_m: 180.0,
                leg_dist_m: 90.0,
                projected_elapsed_s: 60,
                cutoff: Some(CutoffStatus::Tight),
                is_refill: false,
            },
        ]
    }

    fn sim_cutoffs() -> [CutoffLeg; 2] {
        [
            CutoffLeg {
                cum_dist_m: 90.0,
                limit_elapsed_s: 120,
            },
            CutoffLeg {
                cum_dist_m: 170.0,
                limit_elapsed_s: 240,
            },
        ]
    }

    fn encode_vec(checkpoints: &[RoadbookCheckpoint], cutoffs: &[CutoffLeg]) -> std::vec::Vec<u8> {
        let mut buf = [0u8; MAX_ROADBOOK_FRAME_LEN];
        let n = encode(checkpoints, cutoffs, &mut buf).expect("encodes");
        buf[..n].to_vec()
    }

    fn hex_of(frame: &[u8]) -> std::string::String {
        use core::fmt::Write as _;
        frame.iter().fold(std::string::String::new(), |mut s, b| {
            let _ = write!(&mut s, "{:02x}", b);
            s
        })
    }

    /// Build a frame around `body` by appending the CRC the decoder will check,
    /// so a test can exercise a rejection *past* the checksum rather than
    /// tripping on it.
    fn sealed(body: &[u8]) -> std::vec::Vec<u8> {
        let mut frame = body.to_vec();
        frame.extend_from_slice(&crc32(body).to_le_bytes());
        frame
    }

    fn body_of(frame: &[u8]) -> &[u8] {
        &frame[..frame.len() - ROADBOOK_CRC_LEN]
    }

    /// The decoded schedule lives in a `state::ROADBOOK` watch for the life of
    /// the device, so its footprint is a standing RAM cost, not a transient.
    /// Pinned the way § 405 pinned `size_of::<Course>()`: the next field added
    /// to either struct should be a deliberate decision rather than a surprise.
    #[test]
    fn the_pushed_schedules_ram_cost_is_pinned() {
        assert_eq!(core::mem::size_of::<PushedRoadbook>(), 656);
        // 16 checkpoints at 24 B + 16 cut-off legs at 16 B, plus each `Vec`'s
        // length word — under 1 KiB of the 256 KiB budget, against the ~4.5 KiB
        // the course polyline it describes already costs.
        assert_eq!(core::mem::size_of::<RoadbookCheckpoint>(), 24);
        assert_eq!(core::mem::size_of::<CutoffLeg>(), 16);
    }

    #[test]
    fn round_trips_the_sim_schedule() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        assert_eq!(frame.len(), roadbook_frame_len(3, 2));
        let got = decode(&frame).expect("decodes");
        assert_eq!(got.checkpoints.as_slice(), &sim_checkpoints()[..]);
        assert_eq!(got.cutoffs.as_slice(), &sim_cutoffs()[..]);
    }

    #[test]
    fn round_trips_at_both_caps() {
        let cps: std::vec::Vec<RoadbookCheckpoint> = (0..MAX_PUSHED_LEGS)
            .map(|i| RoadbookCheckpoint {
                cum_dist_m: (i as f64 + 1.0) * 5_000.0,
                leg_dist_m: 5_000.0,
                projected_elapsed_s: (i as u32 + 1) * 1_800,
                cutoff: Some(CutoffStatus::Miss),
                is_refill: i % 2 == 0,
            })
            .collect();
        let legs: std::vec::Vec<CutoffLeg> = (0..MAX_CUTOFF_LEGS)
            .map(|i| CutoffLeg {
                cum_dist_m: (i as f64 + 1.0) * 5_000.0,
                limit_elapsed_s: (i as u32 + 1) * 2_000,
            })
            .collect();
        let frame = encode_vec(&cps, &legs);
        assert_eq!(frame.len(), MAX_ROADBOOK_FRAME_LEN);
        let got = decode(&frame).expect("decodes");
        assert_eq!(got.checkpoints.as_slice(), cps.as_slice());
        assert_eq!(got.cutoffs.as_slice(), legs.as_slice());
    }

    /// A frame the whole point of which is that it clears: the pages fall back
    /// to their unpushed states rather than keeping a finished race's legs.
    #[test]
    fn an_empty_schedule_round_trips_as_the_clear() {
        let frame = encode_vec(&[], &[]);
        assert_eq!(frame.len(), roadbook_frame_len(0, 0));
        let got = decode(&frame).expect("decodes");
        assert!(got.is_empty());
        assert_eq!(got, PushedRoadbook::new());
    }

    /// Either series alone is legal: a course with cut-offs the phone couldn't
    /// build a goal-time roadbook for still arms the CutoffEta page, and vice
    /// versa.
    #[test]
    fn either_series_alone_round_trips() {
        let only_cps = encode_vec(&sim_checkpoints(), &[]);
        let got = decode(&only_cps).expect("decodes");
        assert_eq!(got.checkpoints.len(), 3);
        assert!(got.cutoffs.is_empty());

        let only_legs = encode_vec(&[], &sim_cutoffs());
        let got = decode(&only_legs).expect("decodes");
        assert!(got.checkpoints.is_empty());
        assert_eq!(got.cutoffs.len(), 2);
    }

    /// Golden vector: the exact bytes the sim schedule produces. The Dart
    /// encoder (`watch_roadbook.dart`) pins this same hex, so a format drift on
    /// either side fails a test rather than silently pushing a wrong schedule.
    #[test]
    fn golden_frame_is_stable() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        assert_eq!(
            hex_of(&frame).as_str(),
            "52424b3101030200\
             0000000000000000000000000001\
             5a0000005a0000001e0000000101\
             b40000005a0000003c0000000200\
             5a00000078000000\
             aa000000f0000000\
             79e5afab",
            "wire format changed — update BOTH this vector and the Dart mirror \
             in apps/mobile_android/lib/watch_roadbook.dart"
        );
        // The trailer is the derived checksum of everything before it, not just
        // the literal pinned above.
        let body = body_of(&frame);
        assert_eq!(
            u32::from_le_bytes([
                frame[body.len()],
                frame[body.len() + 1],
                frame[body.len() + 2],
                frame[body.len() + 3],
            ]),
            crc32(body)
        );
    }

    #[test]
    fn encode_refuses_an_over_cap_series_rather_than_truncating() {
        let mut buf = [0u8; MAX_ROADBOOK_FRAME_LEN + ROADBOOK_CHECKPOINT_LEN];
        let over_cps: std::vec::Vec<RoadbookCheckpoint> = (0..=MAX_PUSHED_LEGS)
            .map(|i| RoadbookCheckpoint {
                cum_dist_m: i as f64 * 100.0,
                leg_dist_m: 100.0,
                projected_elapsed_s: i as u32 * 60,
                cutoff: None,
                is_refill: false,
            })
            .collect();
        assert!(encode(&over_cps, &[], &mut buf).is_none());
        let over_legs: std::vec::Vec<CutoffLeg> = (0..=MAX_CUTOFF_LEGS)
            .map(|i| CutoffLeg {
                cum_dist_m: i as f64 * 100.0,
                limit_elapsed_s: i as u32 * 60,
            })
            .collect();
        assert!(encode(&[], &over_legs, &mut buf).is_none());
    }

    #[test]
    fn encode_refuses_a_distance_the_wire_cannot_carry() {
        let mut buf = [0u8; MAX_ROADBOOK_FRAME_LEN];
        for bad in [f64::NAN, f64::INFINITY, -1.0, 5e9] {
            let cp = RoadbookCheckpoint {
                cum_dist_m: bad,
                leg_dist_m: 0.0,
                projected_elapsed_s: 0,
                cutoff: None,
                is_refill: false,
            };
            assert!(encode(&[cp], &[], &mut buf).is_none(), "cum {bad} encoded");
            let cp = RoadbookCheckpoint {
                cum_dist_m: 0.0,
                leg_dist_m: bad,
                projected_elapsed_s: 0,
                cutoff: None,
                is_refill: false,
            };
            assert!(encode(&[cp], &[], &mut buf).is_none(), "leg {bad} encoded");
            let leg = CutoffLeg {
                cum_dist_m: bad,
                limit_elapsed_s: 0,
            };
            assert!(
                encode(&[], &[leg], &mut buf).is_none(),
                "limit {bad} encoded"
            );
        }
    }

    #[test]
    fn encode_refuses_a_buffer_too_small() {
        let mut exact = [0u8; roadbook_frame_len(3, 2)];
        assert!(encode(&sim_checkpoints(), &sim_cutoffs(), &mut exact).is_some());
        let mut one_short = [0u8; roadbook_frame_len(3, 2) - 1];
        assert!(encode(&sim_checkpoints(), &sim_cutoffs(), &mut one_short).is_none());
    }

    #[test]
    fn decode_rejects_bad_magic_and_short_frames() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        assert!(decode(&[]).is_none());
        assert!(decode(&frame[..ROADBOOK_HEADER_LEN - 1]).is_none());
        let mut bad_magic = frame.clone();
        bad_magic[0] = b'X';
        assert!(decode(&bad_magic).is_none());
    }

    /// A future version is refused outright — re-sealed, so the rejection is
    /// the version gate rather than the checksum.
    #[test]
    fn decode_rejects_a_future_version() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut future = body_of(&frame).to_vec();
        future[4] = ROADBOOK_FORMAT_VERSION + 1;
        assert!(decode(&sealed(&future)).is_none());
        // And a version below the current one, which has never existed.
        let mut past = body_of(&frame).to_vec();
        past[4] = 0;
        assert!(decode(&sealed(&past)).is_none());
    }

    #[test]
    fn decode_rejects_an_over_cap_count_before_reading_a_cell() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut over_cps = body_of(&frame).to_vec();
        over_cps[5] = MAX_PUSHED_LEGS as u8 + 1;
        assert!(decode(&sealed(&over_cps)).is_none());
        let mut over_legs = body_of(&frame).to_vec();
        over_legs[6] = MAX_CUTOFF_LEGS as u8 + 1;
        assert!(decode(&sealed(&over_legs)).is_none());
        // A count of 255 must be refused on the count, not read as 255 cells.
        let mut absurd = body_of(&frame).to_vec();
        absurd[5] = 0xff;
        assert!(decode(&sealed(&absurd)).is_none());
    }

    #[test]
    fn decode_rejects_an_unknown_frame_or_checkpoint_flag_bit() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut odd_frame_flag = body_of(&frame).to_vec();
        odd_frame_flag[7] = 1 << 3;
        assert!(decode(&sealed(&odd_frame_flag)).is_none());
        let mut odd_cp_flag = body_of(&frame).to_vec();
        odd_cp_flag[ROADBOOK_HEADER_LEN + 13] |= 1 << 7;
        assert!(decode(&sealed(&odd_cp_flag)).is_none());
    }

    #[test]
    fn decode_rejects_a_cutoff_byte_naming_no_status() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        for code in [4u8, 0x80, 0xff] {
            let mut bad = body_of(&frame).to_vec();
            bad[ROADBOOK_HEADER_LEN + 12] = code;
            assert!(
                decode(&sealed(&bad)).is_none(),
                "status code {code} decoded"
            );
        }
    }

    #[test]
    fn decode_rejects_a_length_that_disagrees_with_the_counts() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        assert!(decode(&frame[..frame.len() - 1]).is_none());
        let mut long = frame.clone();
        long.push(0x00);
        assert!(decode(&long).is_none());
        // Re-sealed at each wrong length, so the exact-length check stands on
        // its own underneath the checksum.
        let body = body_of(&frame);
        assert!(decode(&sealed(&body[..body.len() - 1])).is_none());
        let mut over = body.to_vec();
        over.push(0x00);
        assert!(decode(&sealed(&over)).is_none());
    }

    /// The reproducer the mandatory CRC exists for: flip one byte of a
    /// projected arrival and the frame is still perfectly well-formed — the
    /// length agrees, every status names a verdict, and there is no
    /// plausibility guard downstream — so the runner would be shown a cut-off
    /// margin and a nap budget computed off a schedule nobody sent.
    #[test]
    fn a_single_byte_corruption_cannot_displace_the_schedule() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let at = ROADBOOK_HEADER_LEN + ROADBOOK_CHECKPOINT_LEN + 9;

        let mut displaced = body_of(&frame).to_vec();
        displaced[at] ^= 0x10;
        let got = decode(&sealed(&displaced)).expect("length-valid under its own crc");
        let honest = decode(&frame).expect("decodes");
        let moved = got.checkpoints[1].projected_elapsed_s;
        assert_ne!(moved, honest.checkpoints[1].projected_elapsed_s);
        assert!(moved > 3_600, "the flip moved the arrival by {moved} s");

        // Over the wire the sender's CRC travels with the frame, so the same
        // flip is refused rather than loaded as a different schedule.
        let mut corrupt = frame.clone();
        corrupt[at] ^= 0x10;
        assert!(decode(&corrupt).is_none());
    }

    #[test]
    fn a_frame_whose_crc_does_not_match_is_rejected() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        assert!(decode(&frame).is_some());
        for at in 0..ROADBOOK_CRC_LEN {
            let mut bad = frame.clone();
            bad[frame.len() - ROADBOOK_CRC_LEN + at] ^= 0x01;
            assert!(decode(&bad).is_none(), "a flipped crc byte {at} decoded");
        }
        // And a flip anywhere in the body, which is what the trailer is for.
        for at in 0..frame.len() - ROADBOOK_CRC_LEN {
            let mut bad = frame.clone();
            bad[at] ^= 0x01;
            // A flipped magic/version/count byte is caught earlier; the point
            // is only that nothing decodes.
            assert!(decode(&bad).is_none(), "a flipped body byte {at} decoded");
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
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut asm = RoadbookAssembler::new();
        let parts = chunks(&frame, 8);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let want = if i == parts.len() - 1 {
                RoadbookPush::Complete
            } else {
                RoadbookPush::More
            };
            assert_eq!(asm.push(*off, payload), want, "at chunk {i}");
        }
        assert_eq!(asm.frame(), frame.as_slice());
        let got = decode(asm.frame()).expect("decodes the reassembled frame");
        assert_eq!(got.checkpoints.len(), 3);
        assert_eq!(got.cutoffs.len(), 2);
    }

    /// The worst-case frame needs more than one ATT write at the 256-byte MTU,
    /// which is the whole reason this push is chunked rather than whole.
    #[test]
    fn the_worst_case_frame_needs_more_than_one_write() {
        assert_eq!(MAX_ROADBOOK_FRAME_LEN, 364);
        // One ATT_WRITE_REQ carries MTU - 3 bytes of value.
        assert!(MAX_ROADBOOK_FRAME_LEN > 256 - 3);
        let parts = chunks(&[0u8; MAX_ROADBOOK_FRAME_LEN], ROADBOOK_CHUNK_CAP - 2);
        assert_eq!(parts.len(), 2);
        for (_, payload) in &parts {
            assert!(payload.len() + 2 <= ROADBOOK_CHUNK_CAP);
        }
    }

    #[test]
    fn assembler_rejects_out_of_order_then_recovers_from_offset_zero() {
        let frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut asm = RoadbookAssembler::new();
        assert_eq!(asm.push(8, &frame[8..16]), RoadbookPush::Rejected);
        assert!(asm.frame().is_empty());
        let mut last = RoadbookPush::More;
        for (off, payload) in chunks(&frame, 12) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, RoadbookPush::Complete);
        assert_eq!(asm.frame(), frame.as_slice());
    }

    /// A whole-but-corrupt frame must never reach `Complete`: the record task
    /// decodes whatever the assembler calls complete, so the checksum is the
    /// assembler's last gate too, and a rejection clears the buffer so the
    /// phone's next offset-0 write recovers.
    #[test]
    fn assembler_rejects_a_whole_frame_whose_crc_fails() {
        let mut frame = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        frame[ROADBOOK_HEADER_LEN] ^= 0x01;
        let mut asm = RoadbookAssembler::new();
        let parts = chunks(&frame, 16);
        for (i, (off, payload)) in parts.iter().enumerate() {
            let outcome = asm.push(*off, payload);
            if i < parts.len() - 1 {
                assert_eq!(outcome, RoadbookPush::More, "at chunk {i}");
            } else {
                assert_eq!(outcome, RoadbookPush::Rejected, "corrupt frame completed");
            }
        }
        assert!(asm.frame().is_empty());
        let honest = encode_vec(&sim_checkpoints(), &sim_cutoffs());
        let mut last = RoadbookPush::More;
        for (off, payload) in chunks(&honest, 16) {
            last = asm.push(off, &payload);
        }
        assert_eq!(last, RoadbookPush::Complete);
    }

    #[test]
    fn assembler_rejects_a_bad_header_stream() {
        let mut asm = RoadbookAssembler::new();
        let mut head = [0u8; ROADBOOK_HEADER_LEN];
        head[0..4].copy_from_slice(&ROADBOOK_MAGIC);
        head[4] = ROADBOOK_FORMAT_VERSION;

        let mut bad_magic = head;
        bad_magic[0] = b'X';
        assert_eq!(asm.push(0, &bad_magic), RoadbookPush::Rejected);
        assert!(asm.frame().is_empty());

        let mut future = head;
        future[4] = ROADBOOK_FORMAT_VERSION + 1;
        assert_eq!(asm.push(0, &future), RoadbookPush::Rejected);

        let mut over = head;
        over[5] = MAX_PUSHED_LEGS as u8 + 1;
        assert_eq!(asm.push(0, &over), RoadbookPush::Rejected);

        let mut over_legs = head;
        over_legs[6] = MAX_CUTOFF_LEGS as u8 + 1;
        assert_eq!(asm.push(0, &over_legs), RoadbookPush::Rejected);

        let mut odd_flag = head;
        odd_flag[7] = 1 << 7;
        assert_eq!(asm.push(0, &odd_flag), RoadbookPush::Rejected);
    }

    /// A chunk past the buffer's capacity is refused rather than silently
    /// dropped — the buffer is exactly the worst-case frame, so this is the
    /// over-long-push path.
    #[test]
    fn assembler_rejects_an_overflowing_chunk() {
        let mut asm = RoadbookAssembler::new();
        let too_big = [0u8; MAX_ROADBOOK_FRAME_LEN + 1];
        assert_eq!(asm.push(0, &too_big), RoadbookPush::Rejected);
        assert!(asm.frame().is_empty());
    }
}
