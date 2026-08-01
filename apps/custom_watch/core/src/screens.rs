//! Runner-composed data screens: a small grid of slots, each naming one
//! [`Metric`] from the run view's catalogue.
//!
//! The 41 built-in glance pages each headline exactly one metric and fill the
//! rest of the panel with context chosen for that metric. That is the right
//! shape for a page about *one* thing — and the wrong shape for the question a
//! runner asks most often, which is two or three things at once. The Dashboard
//! is the only screen that answers it, and there is exactly one of it.
//!
//! A [`Screen`] is the second one, and the third: a layout plus the metrics to
//! put in it. Nothing here renders — [`crate::face`] owns that — and nothing
//! here decides *which* metrics are sensible together. This is the data model
//! and its wire format, both fail-closed.
//!
//! # The `SCR1` frame
//!
//! ```text
//! magic("SCR1", 4) | version(1) | count(1) | flags(1) | reserved(1)
//!   | screen[count] | crc32(4, u32 LE over everything before it)
//!
//! screen (4 bytes, fixed):
//!   layout(1)  |  metric[SCREEN_SLOTS] (3 x u8, 0 = empty)
//! ```
//!
//! One frame carries the whole set — it is a replacement, never a delta, so a
//! push that arrives is the complete answer to "what screens does this watch
//! have". At [`MAX_SCR1_LEN`] = 28 bytes it fits one ATT write inside the
//! 256-byte MTU with room to spare, so unlike [`crate::course_store`] and
//! [`crate::workout_store`] it is **not chunked**: paying for an offset-ordered
//! assembler and its reset-recovery contract would buy nothing at 28 bytes.
//!
//! The same bytes are the flash record, the way [`crate::waypoints`]'s are —
//! one codec, written to the config page on a push and read back at boot, so a
//! runner who built their screens before a race still has them after a power
//! cycle.
//!
//! # Fail-closed, whole-frame
//!
//! Bad magic, an unknown version, an unknown flag bit, a count past
//! [`MAX_SCREENS`], a length that disagrees with the count, a failed CRC, an
//! unknown layout byte, an unknown metric byte, a slot filled past its layout's
//! arity, or a screen with no metrics at all — every one of them rejects the
//! **whole frame**, exactly as [`crate::ice`] refuses a whole card rather than
//! blanking one field. The reason is the same: a screen whose third slot
//! silently emptied reads as a complete screen the runner authored, and there
//! is nothing on the wrist to say otherwise. Refusing the set leaves the 41
//! built-in pages working, which is the L4 answer.
//!
//! Bytes past the record are ignored, so the caller hands the whole
//! fixed-length flash read — erased `0xFF` tail and all — straight to
//! [`Screens::decode`].

use crate::face::Metric;
use crate::run_store::crc32;

/// How many screens a runner may compose.
///
/// Four, and the ceiling is navigation rather than storage — the config page
/// has kilobytes free. Every screen is a page in the § 350 cycle, and § 289's
/// press-cost model is a function of page count alone.
///
/// **Four was chosen against a 37-page ring and the ring is now 41** (§ 373,
/// § 375 and § 372 each added one on 2026-07-30; § 376's Storm page a day
/// later). At 37 + 4 the grid's symmetric worst was 7; at 40 + 4 = 44 it
/// became 8, which is the first count where it steps, and 41 + 4 = 45 sits
/// past that step without moving it again. The cap therefore no longer keeps
/// `navigation.md`'s published ceiling — that doc now publishes both numbers
/// rather than the smaller one. Left at 4 deliberately: dropping to 3 would
/// buy the ceiling back and cost the `SCR1` frame's capacity, its flash
/// record's size and its golden vectors, which is a decision to take on its
/// own and not a side effect of counting pages. The everyday filtered worst is
/// unmoved at 4.
pub const MAX_SCREENS: usize = 4;

/// Slots per screen — the widest layout's arity.
///
/// Three, because that is where the panel stops paying. Measured at a 45 cm
/// glance: the 32x48 numeral face subtends 38.8 arcmin and the 16x32 face 19.4.
/// [`Layout::Duo`] keeps *both* its values in the big face and needs no new
/// drawing primitive; [`Layout::Trio`] spends one on a hero and drops two to
/// the medium face. A fourth slot would put every value at 19.4 arcmin, and on
/// a device whose whole argument is the number a runner reads at hour 60 by
/// headlamp that is a trade to make with a prototype on a wrist, not in a
/// simulator — see the note on [`Layout`].
pub const SCREEN_SLOTS: usize = 3;

/// Cells a slot's label may use.
///
/// A slot's value is drawn in a numeral face that costs 2 or 4 cells per glyph,
/// and the label rides the remainder of its row. Five cells is what a Trio's
/// medium row can spare beside a six-glyph value; [`Metric::slot_label`] is
/// pinned inside it by test.
pub const SLOT_LABEL_CELLS: usize = 5;

pub const SCR1_MAGIC: [u8; 4] = *b"SCR1";
pub const SCR1_VERSION: u8 = 1;

/// No flags defined yet. A set bit rejects the frame: a new field rides a
/// version bump, which the version byte already refuses, so a bit outside this
/// mask can only be corruption — [`crate::workout_store`]'s rule.
const KNOWN_SCR1_FLAGS: u8 = 0;

/// Header: magic(4) + version(1) + count(1) + flags(1) + reserved(1).
pub const SCR1_HEADER_LEN: usize = 8;

/// One screen: layout(1) + metric[SCREEN_SLOTS].
pub const SCR1_ENTRY_LEN: usize = 1 + SCREEN_SLOTS;

const SCR1_CRC_LEN: usize = 4;

/// Largest a `SCR1` record can be — the caller's encode and flash-read buffer.
pub const MAX_SCR1_LEN: usize = SCR1_HEADER_LEN + MAX_SCREENS * SCR1_ENTRY_LEN + SCR1_CRC_LEN;

/// The flash config page writes in 4-byte words, so the record has to land on
/// one. It does by construction (8 + 4*4 + 4 = 28); this is here so a capacity
/// change that breaks it is a compile error rather than a failed write.
const _: () = assert!(MAX_SCR1_LEN.is_multiple_of(4));

/// And it has to stay inside one ATT write, or the "not chunked" decision above
/// silently becomes a truncated push.
const _: () = assert!(MAX_SCR1_LEN <= 244);

/// How a screen arranges its slots.
///
/// The byte is the wire discriminant and is stable for the same reason
/// [`Metric::to_byte`] is. **3 is deliberately unassigned**: it is the seat a
/// four-slot `Quad` would take, held open so adding it later is a version bump
/// against a known byte rather than a scramble. Until then `decode` rejects it,
/// because accepting a layout this firmware cannot draw would put a blank
/// screen in the cycle.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Layout {
    /// One metric, the full 32x48 hero — what every built-in glance page does.
    Single,
    /// Two metrics stacked, **both** in the 32x48 hero face. The only
    /// multi-field layout that costs nothing in legibility.
    Duo,
    /// A 32x48 hero over two 16x32 rows: one thing you are watching and two you
    /// are keeping an eye on.
    Trio,
}

impl Layout {
    pub const fn to_byte(self) -> u8 {
        match self {
            Layout::Single => 0,
            Layout::Duo => 1,
            Layout::Trio => 2,
        }
    }

    pub const fn from_byte(b: u8) -> Option<Layout> {
        Some(match b {
            0 => Layout::Single,
            1 => Layout::Duo,
            2 => Layout::Trio,
            _ => return None,
        })
    }

    /// How many slots this layout draws.
    pub const fn slots(self) -> usize {
        match self {
            Layout::Single => 1,
            Layout::Duo => 2,
            Layout::Trio => 3,
        }
    }

    /// The stable cross-platform name for the wire byte — the same guard
    /// [`Metric::wire_name`] carries.
    pub const fn wire_name(self) -> &'static str {
        match self {
            Layout::Single => "single",
            Layout::Duo => "duo",
            Layout::Trio => "trio",
        }
    }
}

/// One runner-composed screen.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Screen {
    pub layout: Layout,
    /// Slots in draw order, top to bottom. Entries past `layout.slots()` are
    /// `None` and the codec refuses a frame that fills one.
    pub slots: [Option<Metric>; SCREEN_SLOTS],
}

impl Screen {
    /// A screen from a layout and the metrics to fill it, or `None` when the
    /// two disagree — too few metrics for the layout, or one past its arity.
    ///
    /// The arity check is what stops a `Single` carrying three metrics of which
    /// two never draw: the runner would have chosen them, and the watch would
    /// silently ignore two thirds of that choice.
    pub fn new(layout: Layout, metrics: &[Metric]) -> Option<Screen> {
        if metrics.len() != layout.slots() {
            return None;
        }
        let mut slots = [None; SCREEN_SLOTS];
        for (slot, m) in slots.iter_mut().zip(metrics) {
            *slot = Some(*m);
        }
        Some(Screen { layout, slots })
    }

    /// The metrics this screen draws, in order.
    pub fn metrics(&self) -> impl Iterator<Item = Metric> + '_ {
        self.slots[..self.layout.slots()].iter().filter_map(|s| *s)
    }
}

/// The whole set of runner-composed screens — what one `SCR1` frame carries.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Screens {
    screens: heapless::Vec<Screen, MAX_SCREENS>,
}

impl Screens {
    pub fn new() -> Self {
        Self::default()
    }

    /// Build a set, refusing one screen past [`MAX_SCREENS`] rather than
    /// dropping it — a runner who composed five screens and got four would have
    /// no way to tell which one the watch discarded.
    pub fn from_slice(screens: &[Screen]) -> Option<Self> {
        if screens.len() > MAX_SCREENS {
            return None;
        }
        let mut v: heapless::Vec<Screen, MAX_SCREENS> = heapless::Vec::new();
        for s in screens {
            v.push(*s).ok()?;
        }
        Some(Screens { screens: v })
    }

    pub fn len(&self) -> usize {
        self.screens.len()
    }

    pub fn is_empty(&self) -> bool {
        self.screens.is_empty()
    }

    pub fn get(&self, i: usize) -> Option<&Screen> {
        self.screens.get(i)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Screen> {
        self.screens.iter()
    }

    /// Encode into `out`, returning the byte count written, or `None` when the
    /// buffer is too small.
    pub fn encode(&self, out: &mut [u8]) -> Option<usize> {
        let len = SCR1_HEADER_LEN + self.screens.len() * SCR1_ENTRY_LEN + SCR1_CRC_LEN;
        if out.len() < len {
            return None;
        }
        out[0..4].copy_from_slice(&SCR1_MAGIC);
        out[4] = SCR1_VERSION;
        out[5] = self.screens.len() as u8;
        out[6] = 0;
        out[7] = 0;
        let mut off = SCR1_HEADER_LEN;
        for s in &self.screens {
            out[off] = s.layout.to_byte();
            for i in 0..SCREEN_SLOTS {
                out[off + 1 + i] = s.slots[i].map_or(0, Metric::to_byte);
            }
            off += SCR1_ENTRY_LEN;
        }
        let crc = crc32(&out[..off]);
        out[off..off + SCR1_CRC_LEN].copy_from_slice(&crc.to_le_bytes());
        Some(len)
    }

    /// Decode a `SCR1` record, or `None` for anything that is not exactly one.
    ///
    /// See the module docs for the full rejection list — every one of them
    /// refuses the whole set rather than a field, and an empty set (`count` 0)
    /// is a legitimate answer meaning "this runner has composed none".
    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < SCR1_HEADER_LEN || b[0..4] != SCR1_MAGIC || b[4] != SCR1_VERSION {
            return None;
        }
        if b[6] & !KNOWN_SCR1_FLAGS != 0 {
            return None;
        }
        let count = b[5] as usize;
        if count > MAX_SCREENS {
            return None;
        }
        let len = SCR1_HEADER_LEN + count * SCR1_ENTRY_LEN + SCR1_CRC_LEN;
        if b.len() < len {
            return None;
        }
        let body = len - SCR1_CRC_LEN;
        let stored = u32::from_le_bytes([b[body], b[body + 1], b[body + 2], b[body + 3]]);
        if crc32(&b[..body]) != stored {
            return None;
        }
        let mut screens: heapless::Vec<Screen, MAX_SCREENS> = heapless::Vec::new();
        let mut off = SCR1_HEADER_LEN;
        for _ in 0..count {
            let layout = Layout::from_byte(b[off])?;
            let mut slots = [None; SCREEN_SLOTS];
            for (i, slot) in slots.iter_mut().enumerate() {
                let byte = b[off + 1 + i];
                if i < layout.slots() {
                    // A drawn slot must name a metric this firmware knows.
                    *slot = Some(Metric::from_byte(byte)?);
                } else if byte != 0 {
                    // A byte past the layout's arity is the shape a shorter
                    // overwrite of a previous screen leaves behind — refuse it
                    // rather than draw a screen the runner did not compose.
                    return None;
                }
            }
            screens.push(Screen { layout, slots }).ok()?;
            off += SCR1_ENTRY_LEN;
        }
        Some(Screens { screens })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Screens {
        Screens::from_slice(&[
            Screen::new(Layout::Duo, &[Metric::Distance, Metric::AvgPace]).unwrap(),
            Screen::new(
                Layout::Trio,
                &[Metric::Elapsed, Metric::HeartRate, Metric::Altitude],
            )
            .unwrap(),
            Screen::new(Layout::Single, &[Metric::ClimbGain]).unwrap(),
        ])
        .unwrap()
    }

    #[test]
    fn a_set_round_trips() {
        let s = sample();
        let mut buf = [0u8; MAX_SCR1_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(n, SCR1_HEADER_LEN + 3 * SCR1_ENTRY_LEN + SCR1_CRC_LEN);
        assert_eq!(Screens::decode(&buf[..n]).unwrap(), s);
    }

    /// The caller hands the whole fixed-length flash read, erased tail included.
    #[test]
    fn a_trailing_erased_region_is_ignored() {
        let s = sample();
        let mut buf = [0xFFu8; MAX_SCR1_LEN];
        s.encode(&mut buf).unwrap();
        assert_eq!(Screens::decode(&buf).unwrap(), s);
    }

    #[test]
    fn an_empty_set_is_a_legitimate_answer() {
        let s = Screens::new();
        let mut buf = [0u8; MAX_SCR1_LEN];
        let n = s.encode(&mut buf).unwrap();
        let back = Screens::decode(&buf[..n]).unwrap();
        assert!(back.is_empty());
    }

    #[test]
    fn every_corruption_rejects_the_whole_set() {
        let s = sample();
        let mut good = [0u8; MAX_SCR1_LEN];
        let n = s.encode(&mut good).unwrap();

        let cases: [(&str, &dyn Fn(&mut [u8])); 7] = [
            ("bad magic", &|b: &mut [u8]| b[0] = b'X'),
            ("unknown version", &|b: &mut [u8]| b[4] = 2),
            ("count past the cap", &|b: &mut [u8]| b[5] = 9),
            ("unknown flag bit", &|b: &mut [u8]| b[6] = 1),
            ("unknown layout", &|b: &mut [u8]| b[SCR1_HEADER_LEN] = 3),
            ("unknown metric", &|b: &mut [u8]| {
                b[SCR1_HEADER_LEN + 1] = 200
            }),
            ("flipped crc bit", &|b: &mut [u8]| {
                let last = b.len() - 1;
                b[last] ^= 1
            }),
        ];
        for (what, corrupt) in cases {
            let mut bad = good;
            corrupt(&mut bad[..n]);
            assert!(
                Screens::decode(&bad[..n]).is_none(),
                "{what} was accepted — every rejection has to refuse the whole set"
            );
        }
    }

    /// The shape a shorter overwrite of a previous screen leaves behind.
    #[test]
    fn a_metric_past_the_layouts_arity_rejects_the_frame() {
        let s = Screens::from_slice(&[Screen::new(Layout::Single, &[Metric::Distance]).unwrap()])
            .unwrap();
        let mut buf = [0u8; MAX_SCR1_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert!(Screens::decode(&buf[..n]).is_some());
        // Slot 1 is past a Single's arity; a live byte there is not the
        // runner's screen.
        buf[SCR1_HEADER_LEN + 2] = Metric::HeartRate.to_byte();
        assert!(Screens::decode(&buf[..n]).is_none());
    }

    #[test]
    fn a_screen_refuses_a_metric_count_its_layout_cannot_draw() {
        assert!(Screen::new(Layout::Single, &[Metric::Distance, Metric::AvgPace]).is_none());
        assert!(Screen::new(Layout::Trio, &[Metric::Distance]).is_none());
        assert!(Screen::new(Layout::Duo, &[]).is_none());
    }

    #[test]
    fn a_set_refuses_one_screen_past_the_cap() {
        let one = Screen::new(Layout::Single, &[Metric::Distance]).unwrap();
        assert!(Screens::from_slice(&[one; MAX_SCREENS]).is_some());
        assert!(Screens::from_slice(&[one; MAX_SCREENS + 1]).is_none());
    }

    #[test]
    fn a_short_buffer_encodes_nothing() {
        let s = sample();
        let mut buf = [0u8; 8];
        assert!(s.encode(&mut buf).is_none());
    }

    /// The frozen wire vector. A change here is a wire break — update this AND
    /// the Dart mirror in `apps/mobile_android/lib/watch_screens.dart`.
    #[test]
    fn the_golden_frame_is_stable() {
        let s =
            Screens::from_slice(&[
                Screen::new(Layout::Duo, &[Metric::Distance, Metric::AvgPace]).unwrap(),
            ])
            .unwrap();
        let mut buf = [0u8; MAX_SCR1_LEN];
        let n = s.encode(&mut buf).unwrap();
        let mut hex: heapless::String<64> = heapless::String::new();
        for b in &buf[..n] {
            use core::fmt::Write;
            let _ = write!(hex, "{b:02x}");
        }
        // magic "SCR1" | v1 | count 1 | flags 0 | reserved 0
        //   | Duo(1) Distance(2) AvgPace(3) empty(0) | crc32 LE
        // The trailer is independently checked against `zlib.crc32`, so this
        // pins a standard CRC-32 and not merely whatever `crc32` computes.
        assert_eq!(hex.as_str(), "5343523101010000010203007b58f901");
    }

    /// Every metric byte is stable, unique, and round-trips — the guard that
    /// makes a reorder of the enum a red test instead of a silent re-point of
    /// every screen the phone has pushed.
    #[test]
    fn metric_bytes_are_unique_stable_and_round_trip() {
        let mut seen = [false; 256];
        let mut n = 0;
        for b in 1..=255u8 {
            if let Some(m) = Metric::from_byte(b) {
                assert_eq!(m.to_byte(), b, "{} does not round-trip", m.wire_name());
                assert!(!seen[b as usize], "byte {b} is claimed twice");
                seen[b as usize] = true;
                n += 1;
            }
        }
        assert_eq!(n, 39, "the catalogue and its byte map have drifted");
        assert!(Metric::from_byte(0).is_none(), "0 is the empty slot");
        assert!(Metric::from_byte(40).is_none(), "40 is past the catalogue");
        // A handful pinned by name, so a reorder cannot quietly renumber them.
        assert_eq!(Metric::from_byte(1).unwrap().wire_name(), "elapsed");
        assert_eq!(Metric::from_byte(2).unwrap().wire_name(), "distance");
        assert_eq!(Metric::from_byte(5).unwrap().wire_name(), "heart_rate");
        assert_eq!(Metric::from_byte(34).unwrap().wire_name(), "race_day_days");
        assert_eq!(Metric::from_byte(39).unwrap().wire_name(), "gap");
        assert_eq!(Metric::from_byte(35).unwrap().wire_name(), "sleep_budget");
    }

    #[test]
    fn layout_bytes_round_trip_and_reserve_the_quad_seat() {
        for (b, name) in [(0u8, "single"), (1, "duo"), (2, "trio")] {
            let l = Layout::from_byte(b).unwrap();
            assert_eq!(l.to_byte(), b);
            assert_eq!(l.wire_name(), name);
        }
        assert!(
            Layout::from_byte(3).is_none(),
            "3 is the reserved Quad seat and must not decode until it draws"
        );
        assert_eq!(Layout::Single.slots(), 1);
        assert_eq!(Layout::Duo.slots(), 2);
        assert_eq!(Layout::Trio.slots(), 3);
    }

    #[test]
    fn every_slot_label_fits_the_cells_a_slot_can_spare() {
        // Derived from the catalogue, not a hard-coded ceiling: a `1..=37`
        // bound silently exempted `storm_delta` (38) and `gap` (39) from this
        // guard, which is how § 389's held-GAP mark reached the composed slots
        // unchecked.
        for b in 1..=u8::MAX {
            let Some(m) = Metric::from_byte(b) else {
                continue;
            };
            let label = m.slot_label();
            assert!(
                !label.is_empty() && label.len() <= SLOT_LABEL_CELLS,
                "{} labels a slot with {label:?}, {} cells against {SLOT_LABEL_CELLS}",
                m.wire_name(),
                label.len()
            );
            assert!(
                label
                    .bytes()
                    .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b' '),
                "{} labels a slot with {label:?} — slot labels are upper-case ASCII, \
                 the vocabulary every other label row on the face uses",
                m.wire_name()
            );
        }
    }
}
