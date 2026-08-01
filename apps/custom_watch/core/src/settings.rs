//! Phone→watch settings frame: the wire the phone uses to push user config
//! (max HR, pacer goal, gear baseline/target, HR-zone ceiling, QNH sea-level
//! reference, fuel-reminder cadences, run-view page curation, home-clock
//! timezone offset, the distance / time / pace-band alert cadences, the
//! race-phase plan, the guided-run selection, the resting HR, and the storm-alert
//! threshold) into the
//! recorder's + baro task's + alert engine's existing settings-sync hooks
//! (`Recorder::set_max_hr` / `set_resting_hr` / `set_pacer_goal` / `set_gear` /
//! `set_pages_enabled` / `set_hide_empty_pages` / `set_race_phases` /
//! `set_guided_run`, `AlertEngine::set_zone_ceiling` / `set_fuel_intervals` /
//! `set_distance_interval` / `set_time_interval` / `set_pace_band` /
//! `set_storm_alert` beside `state::STORM_THRESHOLD_HPA`,
//! `state::SEA_LEVEL_PA` for the baro altitude reference, and
//! `state::TZ_OFFSET_MIN` for the home clock).
//!
//! Binary, not JSON — the watch is `no_std` with no allocator and no JSON
//! parser, and the run-sync side already speaks fixed-layout little-endian
//! frames (`run_store`), so this matches that discipline: a 4-byte magic, a
//! version byte, two presence-bitfields (three from v7), then only the present
//! fields in bit order, then a CRC32 trailer. Every field is
//! optional so the phone can push a partial update (just a new max HR) without
//! disturbing the rest. Decoding only *parses* — the plausibility guards stay
//! in the setters it feeds, so a garbage value is rejected by the same rule
//! whether it arrives over BLE or the sim link.
//!
//! **The checksum is mandatory, and v1 / v2 no longer decode.** The trailer
//! arrived at v3, and for a while the two pre-CRC versions stayed decodable so
//! an un-upgraded phone's push kept configuring the watch. That trade is now
//! withdrawn, on the reasoning [`crate::course_store`] already records for its
//! own format: an accepted un-checksummed version is a bypass, because any
//! frame that fails the CRC can claim to be v2 instead and leave the check
//! decorative. Post-bonding write access is the security boundary — an
//! authorized writer gains nothing by choosing v1, since it could send a
//! well-formed v8 frame anyway — so what the mandate really buys is detecting
//! *accidental* corruption of a legacy push, which is otherwise applied as
//! truth: one flipped bit in a `max_hr` or a pacer goal was indistinguishable
//! from the value the phone sent. Nothing emits v1 or v2 (the phone encoder
//! here has always stamped the current version) and no watch has ever shipped,
//! so there is no compatibility debt to honour.

use crate::ice::{IceCard, ICE_WIRE_LEN};
use crate::page::mask_from_wire;
use crate::race_phases::RacePhasePreset;
use crate::run_store::crc32;

pub const SETTINGS_MAGIC: [u8; 4] = *b"SET1";

/// Version 8 (2026-07-31): the storm-alert threshold ([`crate::storm`], § 376)
/// takes `flags3` bit 1. The byte had six bits free after v7, so nothing about
/// the layout forced this bump — the **discipline** did: a set bit outside the
/// mask for a frame's own version is how `decode` tells a corrupt push from a
/// forward-compatible one, and that only works while a version names exactly
/// one field set. `decode` accepts v3 through v8, so a phone a few releases
/// behind keeps working; the encoder always emits v8.
pub const SETTINGS_VERSION: u8 = 8;

/// Version 7 (2026-07-30): the auto-lap trigger ([`crate::auto_lap`]) is the
/// field v6's saturation assert was waiting for — both presence bytes were
/// full, so it rides a THIRD presence byte (`flags3`) and the version bump that
/// comes with it, exactly as v2 did for `flags2` (§ 374).
const SETTINGS_VERSION_V7: u8 = 7;

/// Version 6 (2026-07-29): the ICE / medical-ID card ([`crate::ice`]) took
/// `flags2`'s LAST free bit — the card a responder reads off a collapsed
/// runner's wrist (§358).
const SETTINGS_VERSION_V6: u8 = 6;

/// Version 5 (2026-07-27): the resting-HR sync rides `flags2` bit 6 — the
/// second half of the TRIMP calibration pair ([`FLAG_MAX_HR`] has carried the
/// other half since v1), so the recorder's single-run training-stress model can
/// upgrade from the distance proxy to Banister TRIMP
/// ([`crate::training_load::compute_stress`]).
const SETTINGS_VERSION_V5: u8 = 5;

/// Version 4 (2026-07-26): the five settings the watch could already honour but
/// the phone had no way to reach took the next five `flags2` bits — the
/// distance / time alert cadences, the pace band, the race-phase plan, and the
/// guided-run selection — and the run-view page mask widened from 32 to 64 bits
/// so every page the enum declares is addressable rather than relying on
/// [`mask_from_wire`] to fail open past bit 31.
const SETTINGS_VERSION_V4: u8 = 4;

/// Version 3 (2026-07-25): the frame gained a CRC32 trailer, and is the OLDEST
/// version [`WatchSettings::decode`] accepts. Its only integrity check had been
/// that the byte count accounts for the fields the presence bitfield claims,
/// which catches any single-*bit* flip but not a single-*byte* corruption that
/// flips two bits across equal-width fields — the length is unchanged, so it
/// decodes as a fully valid but *different* update (one byte turns `flags`
/// `0xB8` into `0xE8` and the four bytes the phone sent as the QNH sea-level
/// pressure are applied as the run-view page mask).
const SETTINGS_VERSION_V3: u8 = 3;

/// Presence bits, in the order the fields are laid out after the header.
pub const FLAG_MAX_HR: u8 = 1 << 0;
pub const FLAG_PACER: u8 = 1 << 1;
pub const FLAG_GEAR: u8 = 1 << 2;
pub const FLAG_ZONE_CEILING: u8 = 1 << 3;
pub const FLAG_SEA_LEVEL: u8 = 1 << 4;
pub const FLAG_FUEL: u8 = 1 << 5;
pub const FLAG_PAGES: u8 = 1 << 6;
pub const FLAG_HIDE_EMPTY: u8 = 1 << 7;

/// Every presence bit the first flag byte defines. `pages` + `hide_empty`
/// (2026-07-21) consumed its last two bits, so this mask is saturated — which
/// is exactly why version 2 exists: the ninth field rode the version bump
/// into a second presence byte rather than an unknowable bit.
const KNOWN_FLAGS: u8 = FLAG_MAX_HR
    | FLAG_PACER
    | FLAG_GEAR
    | FLAG_ZONE_CEILING
    | FLAG_SEA_LEVEL
    | FLAG_FUEL
    | FLAG_PAGES
    | FLAG_HIDE_EMPTY;

/// Presence bits in the `flags2` byte, continuing the field order after
/// [`FLAG_HIDE_EMPTY`]. Bit 0 arrived with v2, bits 1-5 with v4, bit 6 with
/// v5, and bit 7 — the last — with v6. Both presence bytes are now saturated,
/// so the next field needs a third one and the version bump that comes with
/// it; [`KNOWN_FLAGS2`] is const-asserted saturated to make that unmissable.
pub const FLAG2_TZ_OFFSET: u8 = 1 << 0;
pub const FLAG2_DISTANCE_INTERVAL: u8 = 1 << 1;
pub const FLAG2_TIME_INTERVAL: u8 = 1 << 2;
pub const FLAG2_PACE_BAND: u8 = 1 << 3;
pub const FLAG2_RACE_PHASES: u8 = 1 << 4;
pub const FLAG2_GUIDED_RUN: u8 = 1 << 5;
pub const FLAG2_RESTING_HR: u8 = 1 << 6;
pub const FLAG2_ICE: u8 = 1 << 7;

/// Every presence bit `flags2` defines **at version 3** — a bit outside this
/// mask is one that version's own encoder could not have set.
const KNOWN_FLAGS2_V3: u8 = FLAG2_TZ_OFFSET;

/// Every presence bit `flags2` defines at version 4.
const KNOWN_FLAGS2_V4: u8 = FLAG2_TZ_OFFSET
    | FLAG2_DISTANCE_INTERVAL
    | FLAG2_TIME_INTERVAL
    | FLAG2_PACE_BAND
    | FLAG2_RACE_PHASES
    | FLAG2_GUIDED_RUN;

/// Every presence bit `flags2` defines at version 5.
const KNOWN_FLAGS2_V5: u8 = KNOWN_FLAGS2_V4 | FLAG2_RESTING_HR;

/// Every presence bit `flags2` defines from version 6 on. A set bit outside the
/// mask for the frame's *own* version can't be a forward-compatible field — a
/// new field rides a version bump, which `decode` rejects on the version byte —
/// so an unknown bit means a corrupt or misframed push, and `decode` rejects the
/// frame rather than silently dropping whatever the sender meant by it.
const KNOWN_FLAGS2: u8 = KNOWN_FLAGS2_V5 | FLAG2_ICE;

/// Presence bits in the `flags3` byte, which arrived with v7 because both
/// earlier bytes were saturated. Six bits are still free — but a free bit is
/// not a licence to skip the version bump: see [`SETTINGS_VERSION`].
pub const FLAG3_AUTO_LAP: u8 = 1 << 0;
pub const FLAG3_STORM_ALERT: u8 = 1 << 1;

/// Every presence bit `flags3` defines at version 7.
const KNOWN_FLAGS3_V7: u8 = FLAG3_AUTO_LAP;

/// Every presence bit `flags3` defines at the current version.
const KNOWN_FLAGS3: u8 = KNOWN_FLAGS3_V7 | FLAG3_STORM_ALERT;

/// Header through v6: magic (4) + version (1) + flags (1) + `flags2` (1). v7
/// appends `flags3`.
const HEADER_LEN: usize = 7;
const V7_HEADER_LEN: usize = HEADER_LEN + 1;

/// The CRC32 trailer, little-endian, over every byte before it. Mandatory —
/// every version [`WatchSettings::decode`] accepts carries one.
const CRC_LEN: usize = 4;

/// Width of the run-view page mask on the wire, in bytes. 64-bit since v4; a v3
/// frame carries 4 and is widened by [`mask_from_wire`] on decode.
const PAGES_LEN: usize = 8;
const PAGES_LEN_V3: usize = 4;

/// Width of the race-phase field: distance(4) + goal time(4) + preset(1).
const RACE_PHASES_LEN: usize = 9;

/// Capacity of the guided-run id field, in bytes — a NUL-padded ASCII library
/// id. The longest shipped id is 16 bytes (`tempo-builder-25`); the slack is for
/// ids a later library adds, since widening the field is a version bump.
pub const GUIDED_RUN_ID_LEN: usize = 24;

/// Largest a fully-populated frame can be — every field present: header,
/// max_hr(2), pacer(8), gear(8), zone_ceiling(1), sea_level_pa(4), fuel(8),
/// pages(8), hide_empty(1), tz_offset(2), distance_interval(4),
/// time_interval(4), pace_band(4), race_phases(9), guided_run(24),
/// resting_hr(2), ice(92), auto_lap(1), storm_alert(2), and the CRC trailer.
/// 196 bytes — the ICE card is far the widest field, and it is what leaves the
/// frame still inside one write at the 256-byte ATT MTU the `ble` task
/// configures, so a settings push still never needs chunking. A field group
/// wider than the ~60 bytes of headroom left would.
pub const MAX_SETTINGS_LEN: usize = V7_HEADER_LEN
    + 2
    + 8
    + 8
    + 1
    + 4
    + 8
    + PAGES_LEN
    + 1
    + 2
    + 4
    + 4
    + 4
    + RACE_PHASES_LEN
    + GUIDED_RUN_ID_LEN
    + 2
    + ICE_WIRE_LEN
    + 1
    + 2
    + CRC_LEN;

const _: () = assert!(MAX_SETTINGS_LEN <= 244);

/// Widest plausible UTC offset (minutes): no real zone sits outside ±14 h.
pub const TZ_OFFSET_LIMIT_MIN: i16 = 14 * 60;

/// A pacer goal to arm the virtual partner with.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PacerGoalCfg {
    pub distance_m: u32,
    pub time_s: u32,
}

/// The active gear's accumulated-distance baseline + replacement target
/// (metres). `target_m == None` is an untracked shoe (wear known, no % — the
/// gear page reads the honest no-target state). On the wire a target of `0.0`
/// encodes `None`, so a real target is always positive.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GearCfg {
    pub baseline_m: f32,
    pub target_m: Option<f32>,
}

/// Fuel-reminder cadences (seconds of moving time) that override the alert
/// engine's fuel_plan-derived temperate defaults — the desert / hot-weather
/// case, where a runner needs far more fluid than the ~500 ml/hr baseline. Fed
/// straight into [`AlertEngine::set_fuel_intervals`], which keeps the "a zero
/// interval is ignored" plausibility guard, so a bad value can't disarm a
/// reminder.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct FuelCfg {
    pub drink_interval_s: u32,
    pub eat_interval_s: u32,
}

/// The pace window to alert outside of, seconds per kilometre. Named fields
/// rather than the `(u32, u32)` pair [`crate::alerts::AlertEngine::set_pace_band`]
/// takes, so the codec cannot transpose the edges on the way to a setter whose
/// only defence against a transposition is to reject the whole band.
///
/// Both edges travel as ONE field under ONE presence bit. Two bits would let a
/// partial push arm a new fast edge against whatever stale slow edge the watch
/// still held — precisely the inverted band the setter refuses — so the runner
/// would lose the whole update rather than half of it. One bit makes a
/// half-band unrepresentable: either both edges arrive or neither does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PaceBandCfg {
    pub fast_s_per_km: u16,
    pub slow_s_per_km: u16,
}

/// A race-phase plan to arm, mirroring
/// [`crate::record::Recorder::set_race_phases`]'s own argument shape: a `None`
/// distance is how that setter is told to CLEAR the plan, so the disarm needs no
/// second layer of `Option` here. On the wire a 0 distance encodes that clear
/// and a 0 goal time encodes "build the phases with no target pace".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RacePhasesCfg {
    pub distance_m: Option<u32>,
    pub goal_time_s: Option<u32>,
    /// The preset's wire discriminant, still raw: `decode` only parses, so a
    /// byte that names no preset is refused where the other value guards live
    /// (see [`race_phase_preset_from_wire`]) and costs only this field.
    pub preset: u8,
}

/// A guided-run library id, NUL-padded to [`GUIDED_RUN_ID_LEN`].
///
/// An ASCII id rather than an index into `guided_run_library()`, even though an
/// index is 23 bytes smaller. The library is a `&'static` slice compiled into
/// the firmware: a later build that inserts or reorders a run would silently
/// re-point every index the phone already holds, so a runner who picked "easy
/// 30" would get a fartlek after an OTA — undetectable, because both sides
/// still look valid. The id is the same identifier the web and Dart twins key
/// on, so it survives a reorder, and a run that no longer exists fails closed at
/// [`crate::record::Recorder::set_guided_run`] rather than resolving to a
/// neighbour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GuidedRunId {
    bytes: [u8; GUIDED_RUN_ID_LEN],
}

impl GuidedRunId {
    /// Build an id from a library string, or `None` if it cannot fit the field.
    /// Refusing an over-long id beats truncating one: a truncated id either
    /// resolves to nothing or, worse, to a different run whose id is a prefix.
    pub fn new(id: &str) -> Option<Self> {
        let src = id.as_bytes();
        if src.len() > GUIDED_RUN_ID_LEN {
            return None;
        }
        let mut bytes = [0u8; GUIDED_RUN_ID_LEN];
        bytes[..src.len()].copy_from_slice(src);
        Some(Self { bytes })
    }

    /// The id as a string, empty when the bytes are not valid UTF-8. Empty
    /// resolves to no library run, so a corrupt id leaves the current selection
    /// standing instead of arming an arbitrary one.
    pub fn as_str(&self) -> &str {
        let end = self
            .bytes
            .iter()
            .position(|&b| b == 0)
            .unwrap_or(GUIDED_RUN_ID_LEN);
        core::str::from_utf8(&self.bytes[..end]).unwrap_or("")
    }

    fn is_empty(&self) -> bool {
        self.bytes[0] == 0
    }
}

/// The preset a wire discriminant names, `None` for a byte that names none.
///
/// The byte is the enum's declaration index, which is identical on the watch, in
/// the Dart twin's `RacePhasePreset` and in the web union — and pinned to
/// [`RacePhasePreset::wire`]'s cross-platform string by a test, so a reorder
/// trips that test rather than silently re-pointing every plan the phone pushes.
pub const fn race_phase_preset_from_wire(b: u8) -> Option<RacePhasePreset> {
    match b {
        0 => Some(RacePhasePreset::TenTenTen),
        1 => Some(RacePhasePreset::NegativeSplit),
        2 => Some(RacePhasePreset::Even),
        _ => None,
    }
}

/// The wire discriminant for a preset — [`race_phase_preset_from_wire`]'s
/// inverse.
pub const fn race_phase_preset_to_wire(preset: RacePhasePreset) -> u8 {
    match preset {
        RacePhasePreset::TenTenTen => 0,
        RacePhasePreset::NegativeSplit => 1,
        RacePhasePreset::Even => 2,
    }
}

/// A partial settings update. Every field is `None` = "leave this as-is"; a
/// present field overrides. `zone_ceiling` is doubly-optional: the field being
/// present with `Some(None)` clears the ceiling (alerts off), `Some(Some(z))`
/// sets it — so the phone can both arm and disarm it.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WatchSettings {
    pub max_hr: Option<u16>,
    pub pacer: Option<PacerGoalCfg>,
    pub gear: Option<GearCfg>,
    /// Outer `Some` = the frame carried a zone-ceiling field; inner `Option` is
    /// the value (`None` = clear it). Absent frames leave the ceiling untouched.
    pub zone_ceiling: Option<Option<u8>>,
    /// QNH sea-level reference pressure (Pa) for the barometric-altitude
    /// calculation. Present = recalibrate the baro task's reference (the
    /// mountain/desert weather-front case); absent = leave the current
    /// reference. The plausibility guard lives on the apply side (the record
    /// task range-checks it before publishing), same discipline as the setters.
    pub sea_level_pa: Option<f32>,
    /// Fuel-reminder cadences override. Present = re-set the drink/eat moving-
    /// time intervals; absent = keep the current cadences.
    pub fuel: Option<FuelCfg>,
    /// The curated run-view page set: bit `i` enables the page with
    /// discriminant `i` (`Page::bit`). 64-bit since v4, so every page the enum
    /// declares is addressable; a pre-v4 frame's 32-bit mask is widened by
    /// [`mask_from_wire`], which leaves the pages past its reach enabled. The
    /// apply side force-includes the Dashboard so an all-zero mask can't empty
    /// the cycle.
    pub pages: Option<u64>,
    /// Whether the BTN3 cycle skips pages whose backing data is absent
    /// (`Recorder::set_hide_empty_pages`); the on-watch default is on.
    pub hide_empty_pages: Option<bool>,
    /// Local-time offset for the home clock, minutes east of UTC — the phone
    /// auto-sources it from its own zone on every push. Present = the home
    /// clock renders local time (its label flips UTC → LOCAL); absent = the
    /// clock stays honestly UTC-labelled. Plausibility guard:
    /// [`plausible_tz_offset_min`].
    pub tz_offset_min: Option<i16>,
    /// Metres of distance between distance alerts, doubly-optional like
    /// [`WatchSettings::zone_ceiling`]: `Some(None)` turns the alert off,
    /// `Some(Some(m))` arms it. On the wire a 0 encodes the off case, so an
    /// armed cadence is always positive. Range guard:
    /// [`crate::alerts::AlertEngine::set_distance_interval`].
    pub distance_interval_m: Option<Option<u32>>,
    /// Seconds of elapsed time between time alerts, same doubly-optional shape.
    pub time_interval_s: Option<Option<u32>>,
    /// The pace window to alert outside of, same doubly-optional shape (an
    /// all-zero band encodes off). See [`PaceBandCfg`] for why both edges share
    /// one presence bit.
    pub pace_band: Option<Option<PaceBandCfg>>,
    /// The race-phase plan. One `Option` only: the clear is a `None` distance
    /// inside [`RacePhasesCfg`], mirroring the setter.
    pub race_phases: Option<RacePhasesCfg>,
    /// The guided run to arm, doubly-optional: `Some(None)` deselects (an
    /// all-zero id on the wire), `Some(Some(id))` selects.
    pub guided_run: Option<Option<GuidedRunId>>,
    /// Resting HR (bpm) — the second half of the TRIMP calibration pair
    /// ([`WatchSettings::max_hr`] is the other). Present = upgrade the
    /// recorder's single-run stress model from the distance proxy to Banister
    /// TRIMP; absent = leave the current calibration. Plausibility guard:
    /// [`crate::record::Recorder::set_resting_hr`].
    pub resting_hr: Option<u16>,
    /// The ICE / medical-ID card a responder reads off the wrist
    /// ([`crate::ice`]), doubly-optional: `Some(None)` clears the card (an
    /// all-blank payload on the wire), `Some(Some(card))` sets it. A payload
    /// any field of which is not printable ASCII refuses the whole FRAME, not
    /// just this field — an unreadable medical ID is the one thing worse than
    /// none, so it must not ride in beside settings that did decode.
    pub ice: Option<Option<IceCard>>,
    /// The auto-lap trigger's wire discriminant, still raw: `decode` only
    /// parses, so a byte that names no rung is refused where the guard with no
    /// setter to live in runs ([`crate::auto_lap::AutoLap::from_byte`], called
    /// from `settings_apply`) and costs only this field. Absent leaves the
    /// trigger the watch already holds standing.
    pub auto_lap: Option<u8>,
    /// The storm-alert threshold ([`crate::storm`], § 376) — the fall in
    /// sea-level-reduced pressure over the trend window that raises the banner.
    /// Doubly-optional like [`WatchSettings::distance_interval_m`]:
    /// `Some(None)` disarms the banner, `Some(Some(hpa))` arms it at that
    /// threshold. On the wire it is tenths of a hectopascal and 0 encodes the
    /// disarm, so an armed threshold is always positive.
    ///
    /// One field, two sinks, because to a runner it is one control: the arm is
    /// the alert engine's ([`crate::alerts::AlertEngine::set_storm_alert`]) and
    /// the threshold the tracker's
    /// ([`crate::storm::StormTracker::set_fall_threshold_hpa`], where the
    /// plausibility guard and the release hysteresis live).
    pub storm_alert: Option<Option<f32>>,
}

/// The pushed timezone offset when it is a plausible UTC offset, `None` when
/// absent or out of range — ignored, never clamped, the same
/// reject-don't-repair discipline as the QNH guard
/// ([`crate::record_cadence::plausible_sea_level_pa`]): a clamped clock would
/// be confidently wrong, an unshifted one is honestly UTC-labelled.
pub fn plausible_tz_offset_min(tz_offset_min: Option<i16>) -> Option<i16> {
    tz_offset_min.filter(|m| (-TZ_OFFSET_LIMIT_MIN..=TZ_OFFSET_LIMIT_MIN).contains(m))
}

impl WatchSettings {
    /// Decode a settings frame. Returns `None` on a bad magic, an unknown
    /// version, a failed CRC, an unknown presence bit, a buffer too short for
    /// the fields the flags claim, or trailing bytes past the declared fields —
    /// never a partial or off-frame struct. Accepts v3 through v8, so a phone a
    /// few releases behind keeps working; a version NEWER than this reader
    /// understands is refused with the same fail-closed rule as a corrupt one,
    /// because its layout is unknowable. The pre-CRC v1 / v2 are refused too —
    /// module docs carry that reasoning.
    pub fn decode(b: &[u8]) -> Option<Self> {
        // Bytes one and two are full; byte three is where a new field goes
        // until it saturates too, and then the drill repeats. These turn the
        // first over-saturating flag into a compile error rather than a
        // silently-accepted frame.
        const _: () = assert!(KNOWN_FLAGS2 == u8::MAX);
        if b.len() < HEADER_LEN || b[0..4] != SETTINGS_MAGIC {
            return None;
        }
        let flags = b[5];
        // The first flag byte is saturated (every bit is a known field), so the
        // unknown-bit rejection only has `flags2` and `flags3` left to police.
        // This assert turns the first over-saturating flag into a compile error
        // instead of a silently-accepted frame.
        const _: () = assert!(KNOWN_FLAGS == u8::MAX);
        // Everything a version changes about the layout: whether `flags3` is
        // there at all, how wide the page mask is, and which `flags2` / `flags3`
        // bits that version's own encoder could have set.
        let (header_len, pages_len, known2, known3) = match b[4] {
            SETTINGS_VERSION_V3 => (HEADER_LEN, PAGES_LEN_V3, KNOWN_FLAGS2_V3, 0),
            SETTINGS_VERSION_V4 => (HEADER_LEN, PAGES_LEN, KNOWN_FLAGS2_V4, 0),
            SETTINGS_VERSION_V5 => (HEADER_LEN, PAGES_LEN, KNOWN_FLAGS2_V5, 0),
            SETTINGS_VERSION_V6 => (HEADER_LEN, PAGES_LEN, KNOWN_FLAGS2, 0),
            SETTINGS_VERSION_V7 => (V7_HEADER_LEN, PAGES_LEN, KNOWN_FLAGS2, KNOWN_FLAGS3_V7),
            SETTINGS_VERSION => (V7_HEADER_LEN, PAGES_LEN, KNOWN_FLAGS2, KNOWN_FLAGS3),
            _ => return None,
        };
        let mut off = header_len;
        // Every accepted version carries the trailer, so the checksum is not a
        // per-version branch any more: a frame that fails it never reaches a
        // field, and a sender cannot dodge it by claiming an older version.
        let b = {
            let end = b.len().checked_sub(CRC_LEN)?;
            if end < off {
                return None;
            }
            let want = u32::from_le_bytes([b[end], b[end + 1], b[end + 2], b[end + 3]]);
            if crc32(&b[..end]) != want {
                return None;
            }
            &b[..end]
        };
        let flags2 = *b.get(6)?;
        if flags2 & !known2 != 0 {
            return None;
        }
        let flags3 = if header_len >= V7_HEADER_LEN {
            *b.get(7)?
        } else {
            0
        };
        if flags3 & !known3 != 0 {
            return None;
        }
        let mut out = WatchSettings::default();

        if flags & FLAG_MAX_HR != 0 {
            let end = off + 2;
            let raw = b.get(off..end)?;
            out.max_hr = Some(u16::from_le_bytes([raw[0], raw[1]]));
            off = end;
        }
        if flags & FLAG_PACER != 0 {
            let end = off + 8;
            let raw = b.get(off..end)?;
            out.pacer = Some(PacerGoalCfg {
                distance_m: u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]),
                time_s: u32::from_le_bytes([raw[4], raw[5], raw[6], raw[7]]),
            });
            off = end;
        }
        if flags & FLAG_GEAR != 0 {
            let end = off + 8;
            let raw = b.get(off..end)?;
            let baseline_m = f32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]);
            let target = f32::from_le_bytes([raw[4], raw[5], raw[6], raw[7]]);
            out.gear = Some(GearCfg {
                baseline_m,
                target_m: (target > 0.0).then_some(target),
            });
            off = end;
        }
        if flags & FLAG_ZONE_CEILING != 0 {
            let z = *b.get(off)?;
            // 0 encodes "clear" (Some(None)); 1..=4 a real ceiling.
            out.zone_ceiling = Some((z != 0).then_some(z));
            off += 1;
        }
        if flags & FLAG_SEA_LEVEL != 0 {
            let end = off + 4;
            let raw = b.get(off..end)?;
            out.sea_level_pa = Some(f32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]));
            off = end;
        }
        if flags & FLAG_FUEL != 0 {
            let end = off + 8;
            let raw = b.get(off..end)?;
            out.fuel = Some(FuelCfg {
                drink_interval_s: u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]),
                eat_interval_s: u32::from_le_bytes([raw[4], raw[5], raw[6], raw[7]]),
            });
            off = end;
        }
        if flags & FLAG_PAGES != 0 {
            let end = off + pages_len;
            let raw = b.get(off..end)?;
            out.pages = Some(if pages_len == PAGES_LEN {
                u64::from_le_bytes([
                    raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                ])
            } else {
                // A pre-v4 phone cannot name a page past discriminant 31, so
                // those stay enabled rather than being curated out by a sender
                // that had no way to ask for them. Same rule as before the
                // widening, moved from the fan-out to here now that a current
                // frame carries the whole mask and needs no compensation.
                mask_from_wire(u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]))
            });
            off = end;
        }
        if flags & FLAG_HIDE_EMPTY != 0 {
            out.hide_empty_pages = Some(*b.get(off)? != 0);
            off += 1;
        }
        if flags2 & FLAG2_TZ_OFFSET != 0 {
            let end = off + 2;
            let raw = b.get(off..end)?;
            out.tz_offset_min = Some(i16::from_le_bytes([raw[0], raw[1]]));
            off = end;
        }
        if flags2 & FLAG2_DISTANCE_INTERVAL != 0 {
            let end = off + 4;
            let raw = b.get(off..end)?;
            // 0 encodes "off" (Some(None)); anything else arms the cadence.
            let m = u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]);
            out.distance_interval_m = Some((m != 0).then_some(m));
            off = end;
        }
        if flags2 & FLAG2_TIME_INTERVAL != 0 {
            let end = off + 4;
            let raw = b.get(off..end)?;
            let s = u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]);
            out.time_interval_s = Some((s != 0).then_some(s));
            off = end;
        }
        if flags2 & FLAG2_PACE_BAND != 0 {
            let end = off + 4;
            let raw = b.get(off..end)?;
            let fast_s_per_km = u16::from_le_bytes([raw[0], raw[1]]);
            let slow_s_per_km = u16::from_le_bytes([raw[2], raw[3]]);
            // An all-zero band encodes "off"; a half-zero or inverted one is a
            // real band the setter will refuse — `decode` only parses.
            out.pace_band = Some((fast_s_per_km != 0 || slow_s_per_km != 0).then_some(
                PaceBandCfg {
                    fast_s_per_km,
                    slow_s_per_km,
                },
            ));
            off = end;
        }
        if flags2 & FLAG2_RACE_PHASES != 0 {
            let end = off + RACE_PHASES_LEN;
            let raw = b.get(off..end)?;
            let distance_m = u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]);
            let goal_time_s = u32::from_le_bytes([raw[4], raw[5], raw[6], raw[7]]);
            out.race_phases = Some(RacePhasesCfg {
                // 0 distance clears the plan, 0 goal time builds it with no
                // target pace — both are what the setter's `None`s mean.
                distance_m: (distance_m != 0).then_some(distance_m),
                goal_time_s: (goal_time_s != 0).then_some(goal_time_s),
                preset: raw[8],
            });
            off = end;
        }
        if flags2 & FLAG2_GUIDED_RUN != 0 {
            let end = off + GUIDED_RUN_ID_LEN;
            let raw = b.get(off..end)?;
            let mut bytes = [0u8; GUIDED_RUN_ID_LEN];
            bytes.copy_from_slice(raw);
            let id = GuidedRunId { bytes };
            // An all-zero id deselects; anything else names a library run the
            // setter resolves (and fails closed on if it is unknown).
            out.guided_run = Some((!id.is_empty()).then_some(id));
            off = end;
        }
        if flags2 & FLAG2_RESTING_HR != 0 {
            let end = off + 2;
            let raw = b.get(off..end)?;
            out.resting_hr = Some(u16::from_le_bytes([raw[0], raw[1]]));
            off = end;
        }
        if flags2 & FLAG2_ICE != 0 {
            let end = off + ICE_WIRE_LEN;
            let raw = b.get(off..end)?;
            // The one field whose own content can reject the frame: every
            // other value is merely parsed here and guarded at its setter, but
            // `IceCard` HAS no plausibility guard downstream — the card is
            // free-form text, so this parse is the only place a garbled
            // medical line can be caught, and a card that reaches the face is
            // one a responder will act on.
            let card = IceCard::from_bytes(raw)?;
            // An all-blank card clears the ID; anything else sets it.
            out.ice = Some((!card.is_blank()).then_some(card));
            off = end;
        }
        if flags3 & FLAG3_AUTO_LAP != 0 {
            out.auto_lap = Some(*b.get(off)?);
            off += 1;
        }
        if flags3 & FLAG3_STORM_ALERT != 0 {
            let end = off + 2;
            let raw = b.get(off..end)?;
            let tenths = u16::from_le_bytes([raw[0], raw[1]]);
            out.storm_alert = Some((tenths != 0).then(|| f32::from(tenths) / 10.0));
            off = end;
        }
        // Bytes left over past the fields the flags claim mean a corrupt or
        // misframed push (data present for a bit that wasn't set); reject it
        // rather than silently apply a frame the phone didn't mean to send.
        if off != b.len() {
            return None;
        }
        Some(out)
    }

    /// Encode a version-8 frame into `out`, returning the byte length written,
    /// or `None` if `out` is smaller than the frame needs. Only present fields
    /// are written, in flag order, then the CRC32 trailer over everything
    /// before it — the mirror the phone encoder pins to.
    pub fn encode(&self, out: &mut [u8]) -> Option<usize> {
        let mut flags = 0u8;
        if self.max_hr.is_some() {
            flags |= FLAG_MAX_HR;
        }
        if self.pacer.is_some() {
            flags |= FLAG_PACER;
        }
        if self.gear.is_some() {
            flags |= FLAG_GEAR;
        }
        if self.zone_ceiling.is_some() {
            flags |= FLAG_ZONE_CEILING;
        }
        if self.sea_level_pa.is_some() {
            flags |= FLAG_SEA_LEVEL;
        }
        if self.fuel.is_some() {
            flags |= FLAG_FUEL;
        }
        if self.pages.is_some() {
            flags |= FLAG_PAGES;
        }
        if self.hide_empty_pages.is_some() {
            flags |= FLAG_HIDE_EMPTY;
        }
        let mut flags2 = 0u8;
        if self.tz_offset_min.is_some() {
            flags2 |= FLAG2_TZ_OFFSET;
        }
        if self.distance_interval_m.is_some() {
            flags2 |= FLAG2_DISTANCE_INTERVAL;
        }
        if self.time_interval_s.is_some() {
            flags2 |= FLAG2_TIME_INTERVAL;
        }
        if self.pace_band.is_some() {
            flags2 |= FLAG2_PACE_BAND;
        }
        if self.race_phases.is_some() {
            flags2 |= FLAG2_RACE_PHASES;
        }
        if self.guided_run.is_some() {
            flags2 |= FLAG2_GUIDED_RUN;
        }
        if self.resting_hr.is_some() {
            flags2 |= FLAG2_RESTING_HR;
        }
        if self.ice.is_some() {
            flags2 |= FLAG2_ICE;
        }
        let mut flags3 = 0u8;
        if self.auto_lap.is_some() {
            flags3 |= FLAG3_AUTO_LAP;
        }
        if self.storm_alert.is_some() {
            flags3 |= FLAG3_STORM_ALERT;
        }

        let len = V7_HEADER_LEN
            + CRC_LEN
            + self.max_hr.map_or(0, |_| 2)
            + self.pacer.map_or(0, |_| 8)
            + self.gear.map_or(0, |_| 8)
            + self.zone_ceiling.map_or(0, |_| 1)
            + self.sea_level_pa.map_or(0, |_| 4)
            + self.fuel.map_or(0, |_| 8)
            + self.pages.map_or(0, |_| PAGES_LEN)
            + self.hide_empty_pages.map_or(0, |_| 1)
            + self.tz_offset_min.map_or(0, |_| 2)
            + self.distance_interval_m.map_or(0, |_| 4)
            + self.time_interval_s.map_or(0, |_| 4)
            + self.pace_band.map_or(0, |_| 4)
            + self.race_phases.map_or(0, |_| RACE_PHASES_LEN)
            + self.guided_run.map_or(0, |_| GUIDED_RUN_ID_LEN)
            + self.resting_hr.map_or(0, |_| 2)
            + self.ice.map_or(0, |_| ICE_WIRE_LEN)
            + self.auto_lap.map_or(0, |_| 1)
            + self.storm_alert.map_or(0, |_| 2);
        if out.len() < len {
            return None;
        }

        out[0..4].copy_from_slice(&SETTINGS_MAGIC);
        out[4] = SETTINGS_VERSION;
        out[5] = flags;
        out[6] = flags2;
        out[7] = flags3;
        let mut off = V7_HEADER_LEN;

        if let Some(hr) = self.max_hr {
            out[off..off + 2].copy_from_slice(&hr.to_le_bytes());
            off += 2;
        }
        if let Some(p) = self.pacer {
            out[off..off + 4].copy_from_slice(&p.distance_m.to_le_bytes());
            out[off + 4..off + 8].copy_from_slice(&p.time_s.to_le_bytes());
            off += 8;
        }
        if let Some(g) = self.gear {
            out[off..off + 4].copy_from_slice(&g.baseline_m.to_le_bytes());
            // None target is a 0.0 sentinel; decode maps it back to None.
            let target = g.target_m.unwrap_or(0.0);
            out[off + 4..off + 8].copy_from_slice(&target.to_le_bytes());
            off += 8;
        }
        if let Some(z) = self.zone_ceiling {
            out[off] = z.unwrap_or(0);
            off += 1;
        }
        if let Some(pa) = self.sea_level_pa {
            out[off..off + 4].copy_from_slice(&pa.to_le_bytes());
            off += 4;
        }
        if let Some(f) = self.fuel {
            out[off..off + 4].copy_from_slice(&f.drink_interval_s.to_le_bytes());
            out[off + 4..off + 8].copy_from_slice(&f.eat_interval_s.to_le_bytes());
            off += 8;
        }
        if let Some(p) = self.pages {
            out[off..off + PAGES_LEN].copy_from_slice(&p.to_le_bytes());
            off += PAGES_LEN;
        }
        if let Some(h) = self.hide_empty_pages {
            out[off] = h as u8;
            off += 1;
        }
        if let Some(m) = self.tz_offset_min {
            out[off..off + 2].copy_from_slice(&m.to_le_bytes());
            off += 2;
        }
        if let Some(m) = self.distance_interval_m {
            // None is a 0 sentinel; decode maps it back to None.
            out[off..off + 4].copy_from_slice(&m.unwrap_or(0).to_le_bytes());
            off += 4;
        }
        if let Some(s) = self.time_interval_s {
            out[off..off + 4].copy_from_slice(&s.unwrap_or(0).to_le_bytes());
            off += 4;
        }
        if let Some(band) = self.pace_band {
            let b = band.unwrap_or(PaceBandCfg {
                fast_s_per_km: 0,
                slow_s_per_km: 0,
            });
            out[off..off + 2].copy_from_slice(&b.fast_s_per_km.to_le_bytes());
            out[off + 2..off + 4].copy_from_slice(&b.slow_s_per_km.to_le_bytes());
            off += 4;
        }
        if let Some(cfg) = self.race_phases {
            out[off..off + 4].copy_from_slice(&cfg.distance_m.unwrap_or(0).to_le_bytes());
            out[off + 4..off + 8].copy_from_slice(&cfg.goal_time_s.unwrap_or(0).to_le_bytes());
            out[off + 8] = cfg.preset;
            off += RACE_PHASES_LEN;
        }
        if let Some(id) = self.guided_run {
            let bytes = id.map_or([0u8; GUIDED_RUN_ID_LEN], |i| i.bytes);
            out[off..off + GUIDED_RUN_ID_LEN].copy_from_slice(&bytes);
            off += GUIDED_RUN_ID_LEN;
        }
        if let Some(hr) = self.resting_hr {
            out[off..off + 2].copy_from_slice(&hr.to_le_bytes());
            off += 2;
        }
        if let Some(card) = self.ice {
            // The clear is an all-blank payload, so `decode` reads it back as
            // `Some(None)` without a second sentinel to keep in step.
            let bytes = card.map_or([0u8; ICE_WIRE_LEN], |c| c.to_bytes());
            out[off..off + ICE_WIRE_LEN].copy_from_slice(&bytes);
            off += ICE_WIRE_LEN;
        }
        if let Some(trigger) = self.auto_lap {
            out[off] = trigger;
            off += 1;
        }
        if let Some(threshold) = self.storm_alert {
            let tenths = threshold.map_or(0u16, |hpa| libm::roundf(hpa * 10.0).max(1.0) as u16);
            out[off..off + 2].copy_from_slice(&tenths.to_le_bytes());
            off += 2;
        }
        let crc = crc32(&out[..off]).to_le_bytes();
        out[off..off + CRC_LEN].copy_from_slice(&crc);
        Some(off + CRC_LEN)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auto_lap::AutoLap;

    const BAND: PaceBandCfg = PaceBandCfg {
        fast_s_per_km: 300,
        slow_s_per_km: 420,
    };

    /// The golden card: every field populated, the two widest at their cap so
    /// a padding slip shows up in the pinned bytes.
    fn ice_card() -> Option<IceCard> {
        IceCard::new(
            "ALEX MORGAN",
            "O NEG",
            "PENICILLIN, ASTHMA",
            "JAMIE MORGAN",
            "+1 555 0134",
        )
    }

    const MARATHON_PLAN: RacePhasesCfg = RacePhasesCfg {
        distance_m: Some(42_195),
        goal_time_s: Some(12_600),
        preset: 0,
    };

    fn roundtrip(s: &WatchSettings) -> WatchSettings {
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).expect("encodes into MAX buffer");
        WatchSettings::decode(&buf[..n]).expect("decodes what it encoded")
    }

    #[test]
    fn empty_frame_roundtrips_to_all_none() {
        let s = WatchSettings::default();
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(n, V7_HEADER_LEN + CRC_LEN, "no fields => header + crc");
        assert_eq!(buf[4], SETTINGS_VERSION);
        assert_eq!(buf[5], 0, "no flags set");
        assert_eq!(buf[6], 0, "no flags2 set");
        assert_eq!(buf[7], 0, "no flags3 set");
        assert_eq!(roundtrip(&s), s);
    }

    #[test]
    fn every_field_roundtrips() {
        let s = WatchSettings {
            auto_lap: Some(AutoLap::Mi1.to_byte()),
            storm_alert: Some(Some(6.0)),
            max_hr: Some(190),
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 4 * 3600,
            }),
            gear: Some(GearCfg {
                baseline_m: 500_000.0,
                target_m: Some(800_000.0),
            }),
            zone_ceiling: Some(Some(3)),
            sea_level_pa: Some(101_325.0),
            fuel: Some(FuelCfg {
                drink_interval_s: 600,
                eat_interval_s: 1_200,
            }),
            pages: Some(0x0000_00ff),
            hide_empty_pages: Some(false),
            tz_offset_min: Some(345),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(BAND)),
            race_phases: Some(MARATHON_PLAN),
            guided_run: Some(GuidedRunId::new("easy-30")),
            resting_hr: Some(48),
            ice: Some(ice_card()),
        };
        assert_eq!(roundtrip(&s), s);
    }

    #[test]
    fn each_field_alone_roundtrips() {
        let cases = [
            WatchSettings {
                max_hr: Some(175),
                ..Default::default()
            },
            WatchSettings {
                pacer: Some(PacerGoalCfg {
                    distance_m: 10_000,
                    time_s: 3_000,
                }),
                ..Default::default()
            },
            WatchSettings {
                gear: Some(GearCfg {
                    baseline_m: 123_456.0,
                    target_m: None,
                }),
                ..Default::default()
            },
            WatchSettings {
                zone_ceiling: Some(Some(4)),
                ..Default::default()
            },
            WatchSettings {
                zone_ceiling: Some(None), // clear
                ..Default::default()
            },
            WatchSettings {
                sea_level_pa: Some(98_500.0),
                ..Default::default()
            },
            WatchSettings {
                fuel: Some(FuelCfg {
                    drink_interval_s: 450,
                    eat_interval_s: 1_000,
                }),
                ..Default::default()
            },
            WatchSettings {
                pages: Some(0),
                ..Default::default()
            },
            WatchSettings {
                pages: Some(u64::MAX),
                ..Default::default()
            },
            WatchSettings {
                hide_empty_pages: Some(true),
                ..Default::default()
            },
            WatchSettings {
                hide_empty_pages: Some(false),
                ..Default::default()
            },
            WatchSettings {
                tz_offset_min: Some(345), // Kathmandu, +5:45
                ..Default::default()
            },
            WatchSettings {
                tz_offset_min: Some(-570), // Marquesas, -9:30
                ..Default::default()
            },
            WatchSettings {
                tz_offset_min: Some(TZ_OFFSET_LIMIT_MIN),
                ..Default::default()
            },
            WatchSettings {
                tz_offset_min: Some(-TZ_OFFSET_LIMIT_MIN),
                ..Default::default()
            },
            WatchSettings {
                distance_interval_m: Some(Some(1_000)),
                ..Default::default()
            },
            WatchSettings {
                distance_interval_m: Some(None), // off
                ..Default::default()
            },
            WatchSettings {
                time_interval_s: Some(Some(1_800)),
                ..Default::default()
            },
            WatchSettings {
                time_interval_s: Some(None), // off
                ..Default::default()
            },
            WatchSettings {
                pace_band: Some(Some(BAND)),
                ..Default::default()
            },
            WatchSettings {
                pace_band: Some(None), // off
                ..Default::default()
            },
            WatchSettings {
                race_phases: Some(MARATHON_PLAN),
                ..Default::default()
            },
            WatchSettings {
                race_phases: Some(RacePhasesCfg {
                    distance_m: None, // clear the plan
                    goal_time_s: None,
                    preset: 2,
                }),
                ..Default::default()
            },
            WatchSettings {
                race_phases: Some(RacePhasesCfg {
                    distance_m: Some(50_000),
                    goal_time_s: None, // phases with no target pace
                    preset: 1,
                }),
                ..Default::default()
            },
            WatchSettings {
                guided_run: Some(GuidedRunId::new("tempo-builder-25")),
                ..Default::default()
            },
            WatchSettings {
                guided_run: Some(None), // deselect
                ..Default::default()
            },
            WatchSettings {
                pages: Some(u64::MAX),
                ..Default::default()
            },
        ];
        for s in cases {
            assert_eq!(roundtrip(&s), s, "roundtrip failed for {s:?}");
        }
    }

    #[test]
    fn a_v4_disarm_is_distinct_from_an_absent_field_and_from_an_armed_one() {
        // The `Some(None)` shape `zone_ceiling` established: the phone must be
        // able to turn a setting off, not only on. Collapsing disarm into absent
        // would leave an alert firing that the runner switched off.
        for (off, armed) in [
            (
                WatchSettings {
                    distance_interval_m: Some(None),
                    ..Default::default()
                },
                WatchSettings {
                    distance_interval_m: Some(Some(1_000)),
                    ..Default::default()
                },
            ),
            (
                WatchSettings {
                    time_interval_s: Some(None),
                    ..Default::default()
                },
                WatchSettings {
                    time_interval_s: Some(Some(1_800)),
                    ..Default::default()
                },
            ),
            (
                WatchSettings {
                    pace_band: Some(None),
                    ..Default::default()
                },
                WatchSettings {
                    pace_band: Some(Some(BAND)),
                    ..Default::default()
                },
            ),
            (
                WatchSettings {
                    guided_run: Some(None),
                    ..Default::default()
                },
                WatchSettings {
                    guided_run: Some(GuidedRunId::new("easy-30")),
                    ..Default::default()
                },
            ),
        ] {
            assert_eq!(roundtrip(&off), off);
            assert_eq!(roundtrip(&armed), armed);
            assert_ne!(roundtrip(&off), roundtrip(&armed));
            assert_ne!(roundtrip(&off), WatchSettings::default());
        }
    }

    #[test]
    fn a_pace_band_travels_whole_under_one_presence_bit() {
        // Two bits would let a partial push arm a new fast edge against a stale
        // slow edge — an inverted band the setter then refuses, so the runner
        // loses the whole update instead of half of it. One bit makes that
        // unrepresentable: either both edges arrive or neither does.
        let s = WatchSettings {
            pace_band: Some(Some(BAND)),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(buf[6], FLAG2_PACE_BAND, "one bit, not two");
        assert_eq!(
            n,
            V7_HEADER_LEN + 4 + CRC_LEN,
            "both edges ride the one field"
        );
        let back = roundtrip(&s).pace_band.unwrap().unwrap();
        assert_eq!(back.fast_s_per_km, 300);
        assert_eq!(back.slow_s_per_km, 420);
    }

    #[test]
    fn an_implausible_pace_band_decodes_because_the_guard_is_the_setters() {
        // `decode` only parses (decisions §217): an inverted band is rejected by
        // `AlertEngine::set_pace_band`, so a bad value is refused the same way
        // over BLE and over the sim link.
        let inverted = PaceBandCfg {
            fast_s_per_km: 420,
            slow_s_per_km: 300,
        };
        let s = WatchSettings {
            pace_band: Some(Some(inverted)),
            ..Default::default()
        };
        assert_eq!(roundtrip(&s).pace_band, Some(Some(inverted)));
    }

    #[test]
    fn a_race_phase_preset_byte_is_pinned_to_the_cross_platform_wire_name() {
        // The byte is the enum's declaration index, which is identical in the
        // Dart twin and the web union. Pinning it to `wire()` means a reorder of
        // the Rust enum trips this test instead of silently re-pointing every
        // plan the phone pushes — the same drift hazard that kept the guided-run
        // field an id rather than a library index.
        for (b, name) in [(0u8, "ten_ten_ten"), (1, "negative_split"), (2, "even")] {
            let preset = race_phase_preset_from_wire(b).expect("byte names a preset");
            assert_eq!(preset.wire(), name);
            assert_eq!(race_phase_preset_to_wire(preset), b);
        }
        for b in 3..=u8::MAX {
            assert_eq!(
                race_phase_preset_from_wire(b),
                None,
                "byte {b} named a preset"
            );
        }
    }

    #[test]
    fn a_guided_run_id_survives_the_wire_and_refuses_to_be_truncated() {
        // Truncation is the danger a fixed field invites: a clipped id either
        // resolves to nothing or, worse, to a different run whose id is a prefix
        // of the one the runner picked. `new` refuses instead.
        for id in ["easy-30", "tempo-builder-25", "first-timer-15"] {
            let s = WatchSettings {
                guided_run: Some(GuidedRunId::new(id)),
                ..Default::default()
            };
            assert_eq!(roundtrip(&s), s);
            assert_eq!(roundtrip(&s).guided_run.unwrap().unwrap().as_str(), id);
        }
        assert_eq!(
            GuidedRunId::new(&"x".repeat(GUIDED_RUN_ID_LEN)).is_some(),
            true
        );
        assert_eq!(GuidedRunId::new(&"x".repeat(GUIDED_RUN_ID_LEN + 1)), None);
        // An id whose bytes are not UTF-8 reads as empty, which resolves to no
        // library run — the current selection stands rather than an arbitrary one.
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = WatchSettings {
            guided_run: Some(GuidedRunId::new("easy-30")),
            ..Default::default()
        }
        .encode(&mut buf)
        .unwrap();
        let mut body = buf[..n - CRC_LEN].to_vec();
        body[V7_HEADER_LEN] = 0xff;
        let back = WatchSettings::decode(&sealed(&body)).expect("length-valid under its crc");
        assert_eq!(back.guided_run.unwrap().unwrap().as_str(), "");
    }

    #[test]
    fn untracked_gear_target_survives_the_zero_sentinel() {
        let s = WatchSettings {
            gear: Some(GearCfg {
                baseline_m: 250_000.0,
                target_m: None,
            }),
            ..Default::default()
        };
        let back = roundtrip(&s);
        assert_eq!(back.gear.unwrap().target_m, None);
    }

    #[test]
    fn sea_level_reference_survives_the_wire() {
        let s = WatchSettings {
            sea_level_pa: Some(102_300.0),
            ..Default::default()
        };
        assert_eq!(roundtrip(&s).sea_level_pa, Some(102_300.0));
    }

    #[test]
    fn fuel_intervals_survive_the_wire() {
        let s = WatchSettings {
            fuel: Some(FuelCfg {
                drink_interval_s: 420,
                eat_interval_s: 1_050,
            }),
            ..Default::default()
        };
        let back = roundtrip(&s).fuel.unwrap();
        assert_eq!(back.drink_interval_s, 420);
        assert_eq!(back.eat_interval_s, 1_050);
    }

    #[test]
    fn zone_ceiling_clear_and_set_are_distinct() {
        let clear = WatchSettings {
            zone_ceiling: Some(None),
            ..Default::default()
        };
        let set = WatchSettings {
            zone_ceiling: Some(Some(2)),
            ..Default::default()
        };
        assert_eq!(roundtrip(&clear).zone_ceiling, Some(None));
        assert_eq!(roundtrip(&set).zone_ceiling, Some(Some(2)));
    }

    #[test]
    fn bad_magic_or_version_is_rejected() {
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        WatchSettings::default().encode(&mut buf).unwrap();
        let mut bad_magic = buf;
        bad_magic[0] = b'X';
        assert_eq!(WatchSettings::decode(&bad_magic), None);
        let mut bad_ver = buf;
        bad_ver[4] = SETTINGS_VERSION + 1;
        assert_eq!(WatchSettings::decode(&bad_ver), None);
        assert_eq!(WatchSettings::decode(&[]), None);
        assert_eq!(WatchSettings::decode(b"SE"), None);
    }

    /// Build a v3 frame around `body` (header + fields) by appending the CRC
    /// the decoder will check, so a test can exercise a rejection *past* the
    /// checksum rather than tripping on it.
    fn sealed(body: &[u8]) -> Vec<u8> {
        let mut frame = body.to_vec();
        frame.extend_from_slice(&crc32(body).to_le_bytes());
        frame
    }

    #[test]
    fn unknown_flags2_bit_is_rejected() {
        // Stamped v4, whose header is `HEADER_LEN` and whose `flags2` mask stops
        // at bit 5 — so bit 7 is genuinely unknown to it and the rejection is
        // the unknown bit rather than a length mismatch. The zero-flags2 control
        // below is what keeps that honest: it must DECODE, so a frame this
        // shape cannot be getting refused for its size.
        let mut header = [0u8; HEADER_LEN];
        header[0..4].copy_from_slice(&SETTINGS_MAGIC);
        header[4] = SETTINGS_VERSION_V4;
        header[5] = 0;
        header[6] = 0x80;
        assert_eq!(WatchSettings::decode(&sealed(&header)), None);
        header[6] = 0;
        assert_eq!(
            WatchSettings::decode(&sealed(&header)),
            Some(WatchSettings::default()),
            "the control must decode, or the rejection above proves nothing"
        );
        // A header cut short of its flags2 byte is a short buffer, not a zero
        // flags2.
        let frame = sealed(&header);
        assert_eq!(WatchSettings::decode(&frame[..HEADER_LEN - 1]), None);
    }

    #[test]
    fn a_v4_frame_claiming_the_v5_resting_hr_bit_is_rejected() {
        // A version-4 encoder could never have set bit 6 — the field rode the
        // v5 bump — so a v4 frame claiming it is corrupt, not forward-compatible.
        let mut body = [0u8; HEADER_LEN + 2];
        body[0..4].copy_from_slice(&SETTINGS_MAGIC);
        body[4] = SETTINGS_VERSION_V4;
        body[5] = 0;
        body[6] = FLAG2_RESTING_HR;
        body[7] = 48;
        assert_eq!(WatchSettings::decode(&sealed(&body)), None);
    }

    #[test]
    fn truncated_field_is_rejected_not_partially_read() {
        let s = WatchSettings {
            max_hr: Some(180),
            pacer: Some(PacerGoalCfg {
                distance_m: 5_000,
                time_s: 1_500,
            }),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        // Chop the last byte of the pacer field: flags claim it, bytes lack it.
        assert_eq!(WatchSettings::decode(&buf[..n - 1]), None);
    }

    #[test]
    fn trailing_bytes_past_declared_fields_are_rejected() {
        let s = WatchSettings {
            max_hr: Some(150),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert!(n < MAX_SETTINGS_LEN);
        // One extra byte belongs to no set flag: data present for an unset bit.
        assert_eq!(WatchSettings::decode(&buf[..n + 1]), None);
    }

    #[test]
    fn trailing_bytes_are_rejected_even_when_the_crc_covers_them() {
        // Appending to a frame invalidates its checksum, so the CRC alone
        // rejects the naive case. Re-sealing the longer frame proves the
        // exact-length check is still doing its own job underneath.
        let s = WatchSettings {
            max_hr: Some(150),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        let mut body = buf[..n - CRC_LEN].to_vec();
        body.push(0x00);
        assert_eq!(WatchSettings::decode(&sealed(&body)), None);
    }

    #[test]
    fn a_frame_whose_crc_does_not_match_is_rejected() {
        let s = WatchSettings {
            max_hr: Some(190),
            sea_level_pa: Some(101_325.0),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert!(WatchSettings::decode(&buf[..n]).is_some());
        for at in 0..CRC_LEN {
            let mut bad = buf;
            bad[n - CRC_LEN + at] ^= 0x01;
            assert_eq!(
                WatchSettings::decode(&bad[..n]),
                None,
                "a flipped crc byte {at} decoded"
            );
        }
        // A v3 frame with no room for the trailer at all is short, not v2.
        assert_eq!(WatchSettings::decode(&buf[..HEADER_LEN + 2]), None);
    }

    /// The reproducer the v3 bump exists for: one byte of the flags, two bits
    /// (`^ 0x06`), and the pacer goal the phone sent is applied as the gear
    /// baseline + replacement target instead while the goal silently vanishes —
    /// same length, same plausibility, different settings. Every equal-width pair
    /// is confusable this way (`pacer` <-> `gear` <-> `fuel` <-> `pages`,
    /// `zone_ceiling` <-> `hide_empty_pages`, `sea_level_pa` <->
    /// `distance_interval_m` <-> `time_interval_s` <-> `pace_band`); the CRC
    /// turns all of them into a rejection. v4 widening `pages` to 8 bytes retired
    /// the original QNH <-> page-mask pair and moved it into `pacer`'s group —
    /// an argument for the checksum, not against it: which pairs are confusable
    /// is an accident of the current field widths, so the integrity check cannot
    /// depend on knowing them.
    #[test]
    fn a_single_byte_flags_corruption_cannot_re_frame_a_pacer_goal_as_gear() {
        let s = WatchSettings {
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 14_400,
            }),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(buf[5], FLAG_PACER);

        // Re-sealed, the corruption is still a perfectly well-formed frame —
        // the length check has nothing to catch, which is the whole defect.
        let mut body = buf[..n - CRC_LEN].to_vec();
        body[5] ^= 0x06;
        let re_framed = WatchSettings::decode(&sealed(&body)).expect("length-valid under its crc");
        assert_eq!(re_framed.pacer, None);
        assert_eq!(
            re_framed.gear,
            Some(GearCfg {
                baseline_m: f32::from_bits(42_195),
                target_m: Some(f32::from_bits(14_400)),
            })
        );

        // Over the wire the sender's CRC travels with the frame, so the same
        // flip is rejected outright rather than applied as different config.
        let mut corrupt = buf;
        corrupt[5] ^= 0x06;
        assert_eq!(WatchSettings::decode(&corrupt[..n]), None);
    }

    #[test]
    fn flag_byte_is_saturated_so_the_next_field_is_a_version_bump() {
        // pages + hide_empty consumed bits 6 + 7: every bit of the first flag
        // byte is a known field, so the unknown-bit rejection only polices
        // flags2. The promised version bump happened — tz_offset (v2) rode it
        // into flags2 — and the drill has now run to its end: the ICE card
        // (v6) took flags2's bit 7, so BOTH bytes are saturated and the next
        // field needs a third presence byte plus its own version. Two const
        // asserts in `decode` make that a compile error rather than a silently
        // accepted frame; these pin the same fact where a reader will meet it.
        assert_eq!(KNOWN_FLAGS, u8::MAX);
        assert_eq!(
            KNOWN_FLAGS2,
            u8::MAX,
            "both presence bytes are full — the next field needs a third"
        );
        // A full flag byte with too few bytes for what it claims still rejects,
        // even when the checksum over those too-few bytes is correct.
        let mut body = [0u8; HEADER_LEN + 2];
        body[0..4].copy_from_slice(&SETTINGS_MAGIC);
        body[4] = SETTINGS_VERSION;
        body[5] = u8::MAX;
        assert_eq!(WatchSettings::decode(&sealed(&body)), None);
    }

    #[test]
    fn each_set_field_truncated_by_one_byte_is_rejected() {
        let cases = [
            WatchSettings {
                max_hr: Some(180),
                ..Default::default()
            },
            WatchSettings {
                pacer: Some(PacerGoalCfg {
                    distance_m: 5_000,
                    time_s: 1_500,
                }),
                ..Default::default()
            },
            WatchSettings {
                gear: Some(GearCfg {
                    baseline_m: 100.0,
                    target_m: Some(200.0),
                }),
                ..Default::default()
            },
            WatchSettings {
                zone_ceiling: Some(Some(3)),
                ..Default::default()
            },
            WatchSettings {
                sea_level_pa: Some(100_000.0),
                ..Default::default()
            },
            WatchSettings {
                fuel: Some(FuelCfg {
                    drink_interval_s: 400,
                    eat_interval_s: 900,
                }),
                ..Default::default()
            },
            WatchSettings {
                pages: Some(0x1234_5678_9abc_def0),
                ..Default::default()
            },
            WatchSettings {
                hide_empty_pages: Some(true),
                ..Default::default()
            },
            WatchSettings {
                tz_offset_min: Some(-570),
                ..Default::default()
            },
            WatchSettings {
                distance_interval_m: Some(Some(1_000)),
                ..Default::default()
            },
            WatchSettings {
                time_interval_s: Some(Some(1_800)),
                ..Default::default()
            },
            WatchSettings {
                pace_band: Some(Some(BAND)),
                ..Default::default()
            },
            WatchSettings {
                race_phases: Some(MARATHON_PLAN),
                ..Default::default()
            },
            WatchSettings {
                guided_run: Some(GuidedRunId::new("easy-30")),
                ..Default::default()
            },
            WatchSettings {
                resting_hr: Some(48),
                ..Default::default()
            },
        ];
        for s in cases {
            let mut buf = [0u8; MAX_SETTINGS_LEN];
            let n = s.encode(&mut buf).unwrap();
            assert!(n > HEADER_LEN);
            assert_eq!(
                WatchSettings::decode(&buf[..n - 1]),
                None,
                "truncated {s:?}"
            );
        }
    }

    #[test]
    fn all_presence_combinations_roundtrip() {
        for flags2 in 0u8..=KNOWN_FLAGS2 {
            let tz = (flags2 & FLAG2_TZ_OFFSET != 0).then_some(-345i16);
            for flags3 in 0u8..=KNOWN_FLAGS3 {
                for mask in 0u8..=u8::MAX {
                    let s = WatchSettings {
                        auto_lap: (flags3 & FLAG3_AUTO_LAP != 0)
                            .then_some(AutoLap::Min10.to_byte()),
                        storm_alert: (flags3 & FLAG3_STORM_ALERT != 0).then_some(Some(4.0)),
                        max_hr: (mask & FLAG_MAX_HR != 0).then_some(190),
                        pacer: (mask & FLAG_PACER != 0).then_some(PacerGoalCfg {
                            distance_m: 21_097,
                            time_s: 7_200,
                        }),
                        gear: (mask & FLAG_GEAR != 0).then_some(GearCfg {
                            baseline_m: 300_000.0,
                            target_m: Some(600_000.0),
                        }),
                        zone_ceiling: (mask & FLAG_ZONE_CEILING != 0).then_some(Some(2)),
                        sea_level_pa: (mask & FLAG_SEA_LEVEL != 0).then_some(99_000.0),
                        fuel: (mask & FLAG_FUEL != 0).then_some(FuelCfg {
                            drink_interval_s: 500,
                            eat_interval_s: 1_100,
                        }),
                        pages: (mask & FLAG_PAGES != 0).then_some(0x0f0f_0f0f_f0f0_f0f0),
                        hide_empty_pages: (mask & FLAG_HIDE_EMPTY != 0).then_some(false),
                        tz_offset_min: tz,
                        distance_interval_m: (flags2 & FLAG2_DISTANCE_INTERVAL != 0)
                            .then_some(Some(1_000)),
                        time_interval_s: (flags2 & FLAG2_TIME_INTERVAL != 0).then_some(None),
                        pace_band: (flags2 & FLAG2_PACE_BAND != 0).then_some(Some(BAND)),
                        race_phases: (flags2 & FLAG2_RACE_PHASES != 0).then_some(MARATHON_PLAN),
                        guided_run: (flags2 & FLAG2_GUIDED_RUN != 0)
                            .then(|| GuidedRunId::new("easy-30")),
                        resting_hr: (flags2 & FLAG2_RESTING_HR != 0).then_some(48),
                        ice: (flags2 & FLAG2_ICE != 0).then_some(ice_card()),
                    };
                    let back = roundtrip(&s);
                    assert_eq!(
                    back, s,
                    "roundtrip drift at mask {mask:#08b} flags2 {flags2:#08b} flags3 {flags3:#08b}"
                );
                    assert_eq!(back.max_hr.is_some(), mask & FLAG_MAX_HR != 0);
                    assert_eq!(back.pacer.is_some(), mask & FLAG_PACER != 0);
                    assert_eq!(back.gear.is_some(), mask & FLAG_GEAR != 0);
                    assert_eq!(back.zone_ceiling.is_some(), mask & FLAG_ZONE_CEILING != 0);
                    assert_eq!(back.sea_level_pa.is_some(), mask & FLAG_SEA_LEVEL != 0);
                    assert_eq!(back.fuel.is_some(), mask & FLAG_FUEL != 0);
                    assert_eq!(back.pages.is_some(), mask & FLAG_PAGES != 0);
                    assert_eq!(back.hide_empty_pages.is_some(), mask & FLAG_HIDE_EMPTY != 0);
                    assert_eq!(back.tz_offset_min, tz);
                    assert_eq!(
                        back.distance_interval_m.is_some(),
                        flags2 & FLAG2_DISTANCE_INTERVAL != 0
                    );
                    assert_eq!(
                        back.time_interval_s.is_some(),
                        flags2 & FLAG2_TIME_INTERVAL != 0
                    );
                    assert_eq!(back.pace_band.is_some(), flags2 & FLAG2_PACE_BAND != 0);
                    assert_eq!(back.race_phases.is_some(), flags2 & FLAG2_RACE_PHASES != 0);
                    assert_eq!(back.guided_run.is_some(), flags2 & FLAG2_GUIDED_RUN != 0);
                    assert_eq!(back.resting_hr.is_some(), flags2 & FLAG2_RESTING_HR != 0);
                    assert_eq!(back.auto_lap.is_some(), flags3 & FLAG3_AUTO_LAP != 0);
                    assert_eq!(back.storm_alert.is_some(), flags3 & FLAG3_STORM_ALERT != 0);
                }
            }
        }
    }

    #[test]
    fn encode_into_too_small_buffer_returns_none() {
        let s = WatchSettings {
            max_hr: Some(190),
            ..Default::default()
        };
        let mut tiny = [0u8; V7_HEADER_LEN + 1]; // needs +2 for max_hr, +4 for the crc
        assert_eq!(s.encode(&mut tiny), None);
    }

    /// Golden vector — the phone encoder must produce these exact bytes for this
    /// struct. Pinned on both sides (mirrored in the Dart `watch_settings` test)
    /// so the two wire codecs can't drift, the way the run-sync blob is pinned.
    #[test]
    fn golden_vector() {
        let s = WatchSettings {
            max_hr: Some(190),
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 14_400,
            }),
            gear: Some(GearCfg {
                baseline_m: 500_000.0,
                target_m: Some(800_000.0),
            }),
            zone_ceiling: Some(Some(3)),
            sea_level_pa: Some(101_325.0),
            fuel: Some(FuelCfg {
                drink_interval_s: 900,
                eat_interval_s: 1_500,
            }),
            pages: Some(0x0000_c0ff),
            hide_empty_pages: Some(true),
            tz_offset_min: Some(345),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(BAND)),
            race_phases: Some(MARATHON_PLAN),
            guided_run: Some(GuidedRunId::new("easy-30")),
            resting_hr: Some(48),
            ice: Some(ice_card()),
            auto_lap: Some(2),
            storm_alert: Some(Some(4.0)),
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        let expected: [u8; MAX_SETTINGS_LEN] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x08, // version
            0xff, // flags: every version-1 field
            0xff, // flags2: tz|distance|time|pace|race|guided|resting|ice — saturated
            0x03, // flags3: auto_lap|storm_alert
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // pages = 0xc0ff (u64 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xe8, 0x03, 0x00, 0x00, // distance_interval_m = 1000
            0x08, 0x07, 0x00, 0x00, // time_interval_s = 1800
            0x2c, 0x01, // pace_band fast = 300 s/km
            0xa4, 0x01, // pace_band slow = 420 s/km
            0xd3, 0xa4, 0x00, 0x00, // race_phases distance_m = 42195
            0x38, 0x31, 0x00, 0x00, // race_phases goal_time_s = 12600
            0x00, // race_phases preset = ten_ten_ten
            0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, // guided_run id "easy-30"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NUL padding to 24
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30,
            0x00, // resting_hr = 48
            // ice: holder "ALEX MORGAN", NUL-padded to 21
            0x41, 0x4c, 0x45, 0x58, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: blood "O NEG", NUL-padded to 8
            0x4f, 0x20, 0x4e, 0x45, 0x47, 0x00, 0x00, 0x00, //
            // ice: conditions "PENICILLIN, ASTHMA", NUL-padded to 21
            0x50, 0x45, 0x4e, 0x49, 0x43, 0x49, 0x4c, 0x4c, 0x49, 0x4e, 0x2c, 0x20, 0x41, 0x53,
            0x54, 0x48, 0x4d, 0x41, 0x00, 0x00, 0x00, //
            // ice: contact "JAMIE MORGAN", NUL-padded to 21
            0x4a, 0x41, 0x4d, 0x49, 0x45, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: phone "+1 555 0134", NUL-padded to 21
            0x2b, 0x31, 0x20, 0x35, 0x35, 0x35, 0x20, 0x30, 0x31, 0x33, 0x34, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            0x02, // auto_lap = 1 mi
            0x28, 0x00, // storm_alert = 4.0 hPa, in tenths
            0x1c, 0x26, 0xd5, 0xdf, // crc32 over every byte above (u32 LE)
        ];
        assert_eq!(n, MAX_SETTINGS_LEN);
        assert_eq!(buf, expected);
    }

    #[test]
    fn a_storm_threshold_travels_as_tenths_and_zero_is_the_disarm() {
        for hpa in [1.0f32, 2.5, 4.0, 6.0, 20.0] {
            let s = WatchSettings {
                storm_alert: Some(Some(hpa)),
                ..Default::default()
            };
            assert_eq!(roundtrip(&s).storm_alert, Some(Some(hpa)), "{hpa} hPa");
        }
        // Disarming is a real update, not an absence — the same distinction the
        // zone ceiling has carried since v1.
        assert_eq!(
            roundtrip(&WatchSettings {
                storm_alert: Some(None),
                ..Default::default()
            })
            .storm_alert,
            Some(None)
        );
        assert_eq!(roundtrip(&WatchSettings::default()).storm_alert, None);
        // An armed threshold must never round to the disarm sentinel however
        // small it is: the tracker's own window would reject 0.02 hPa, but a
        // wire that silently turned "arm" into "off" would be a different bug
        // in a different place, with nothing to reject.
        let tiny = WatchSettings {
            storm_alert: Some(Some(0.02)),
            ..Default::default()
        };
        assert_eq!(roundtrip(&tiny).storm_alert, Some(Some(0.1)));
    }

    /// The frozen v7 golden vector (every v7 field, version byte 0x07) must
    /// keep decoding into exactly what it decoded into before the v8 bump: a
    /// phone that hasn't shipped the storm-alert encoder yet still configures
    /// the watch, and the banner it never mentioned stays as the watch has it
    /// rather than being armed or disarmed by omission.
    #[test]
    fn v7_golden_vector_still_decodes() {
        let v7: [u8; 194] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x07, // version
            0xff, // flags: every version-1 field
            0xff, // flags2: tz|distance|time|pace|race|guided|resting|ice — saturated
            0x01, // flags3: auto_lap
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // pages = 0xc0ff (u64 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xe8, 0x03, 0x00, 0x00, // distance_interval_m = 1000
            0x08, 0x07, 0x00, 0x00, // time_interval_s = 1800
            0x2c, 0x01, // pace_band fast = 300 s/km
            0xa4, 0x01, // pace_band slow = 420 s/km
            0xd3, 0xa4, 0x00, 0x00, // race_phases distance_m = 42195
            0x38, 0x31, 0x00, 0x00, // race_phases goal_time_s = 12600
            0x00, // race_phases preset = ten_ten_ten
            0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, // guided_run id "easy-30"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NUL padding to 24
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30,
            0x00, // resting_hr = 48
            // ice: holder "ALEX MORGAN", NUL-padded to 21
            0x41, 0x4c, 0x45, 0x58, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: blood "O NEG", NUL-padded to 8
            0x4f, 0x20, 0x4e, 0x45, 0x47, 0x00, 0x00, 0x00, //
            // ice: conditions "PENICILLIN, ASTHMA", NUL-padded to 21
            0x50, 0x45, 0x4e, 0x49, 0x43, 0x49, 0x4c, 0x4c, 0x49, 0x4e, 0x2c, 0x20, 0x41, 0x53,
            0x54, 0x48, 0x4d, 0x41, 0x00, 0x00, 0x00, //
            // ice: contact "JAMIE MORGAN", NUL-padded to 21
            0x4a, 0x41, 0x4d, 0x49, 0x45, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: phone "+1 555 0134", NUL-padded to 21
            0x2b, 0x31, 0x20, 0x35, 0x35, 0x35, 0x20, 0x30, 0x31, 0x33, 0x34, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            0x02, // auto_lap = 1 mi
            0xff, 0x55, 0x93, 0xbc, // crc32 over every byte above (u32 LE)
        ];
        let s = WatchSettings::decode(&v7).expect("a v7 frame decodes");
        assert_eq!(s.storm_alert, None, "a v7 phone names no storm threshold");
        assert_eq!(s.auto_lap, Some(2));
        assert_eq!(s.max_hr, Some(190));
        assert_eq!(s.ice, Some(ice_card()));
    }

    /// The reason the v8 bump exists at all, given `flags3` had six free bits:
    /// an unknown presence bit is how [`WatchSettings::decode`] tells a corrupt
    /// push from a legitimate one, and that only holds while a version names
    /// exactly one field set. A v7-stamped frame carrying the v8 bit is
    /// therefore refused whole — not read as a v7 frame with a trailing
    /// surprise.
    #[test]
    fn a_v7_stamped_frame_cannot_carry_the_v8_field() {
        let s = WatchSettings {
            storm_alert: Some(Some(4.0)),
            ..WatchSettings::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(WatchSettings::decode(&buf[..n]), Some(s));
        // Re-stamp the version and re-seal the CRC, so the ONLY thing wrong
        // with the frame is that its version does not know its own field.
        buf[4] = 7;
        let crc = crc32(&buf[..n - CRC_LEN]).to_le_bytes();
        buf[n - CRC_LEN..n].copy_from_slice(&crc);
        assert_eq!(WatchSettings::decode(&buf[..n]), None);
    }

    /// The frozen v6 golden vector (every v6 field, version byte 0x06) must
    /// keep decoding into exactly what it decoded into before the v7 bump: a
    /// phone that hasn't shipped the auto-lap encoder yet still configures the
    /// watch, and the trigger it never sent leaves the watch's own standing
    /// rather than resetting it to a default mid-race.
    #[test]
    fn v6_golden_vector_still_decodes() {
        let v6: [u8; 192] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x06, // version
            0xff, // flags: every version-1 field
            0xff, // flags2: tz|distance|time|pace|race|guided|resting|ice — saturated
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // pages = 0xc0ff (u64 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xe8, 0x03, 0x00, 0x00, // distance_interval_m = 1000
            0x08, 0x07, 0x00, 0x00, // time_interval_s = 1800
            0x2c, 0x01, // pace_band fast = 300 s/km
            0xa4, 0x01, // pace_band slow = 420 s/km
            0xd3, 0xa4, 0x00, 0x00, // race_phases distance_m = 42195
            0x38, 0x31, 0x00, 0x00, // race_phases goal_time_s = 12600
            0x00, // race_phases preset = ten_ten_ten
            0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, // guided_run id "easy-30"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NUL padding to 24
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30,
            0x00, // resting_hr = 48
            // ice: holder "ALEX MORGAN", NUL-padded to 21
            0x41, 0x4c, 0x45, 0x58, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: blood "O NEG", NUL-padded to 8
            0x4f, 0x20, 0x4e, 0x45, 0x47, 0x00, 0x00, 0x00, //
            // ice: conditions "PENICILLIN, ASTHMA", NUL-padded to 21
            0x50, 0x45, 0x4e, 0x49, 0x43, 0x49, 0x4c, 0x4c, 0x49, 0x4e, 0x2c, 0x20, 0x41, 0x53,
            0x54, 0x48, 0x4d, 0x41, 0x00, 0x00, 0x00, //
            // ice: contact "JAMIE MORGAN", NUL-padded to 21
            0x4a, 0x41, 0x4d, 0x49, 0x45, 0x20, 0x4d, 0x4f, 0x52, 0x47, 0x41, 0x4e, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            // ice: phone "+1 555 0134", NUL-padded to 21
            0x2b, 0x31, 0x20, 0x35, 0x35, 0x35, 0x20, 0x30, 0x31, 0x33, 0x34, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
            0x2d, 0xc5, 0x38, 0x5a, // crc32 over every byte above (u32 LE)
        ];
        let s = WatchSettings::decode(&v6).expect("v6 frame decodes");
        assert_eq!(s.auto_lap, None, "a v6 phone names no trigger");
        assert_eq!(s.max_hr, Some(190));
        assert_eq!(s.resting_hr, Some(48));
        assert_eq!(s.ice, Some(ice_card()));
        assert_eq!(s.tz_offset_min, Some(345));
    }

    #[test]
    fn a_flags3_bit_no_version_defines_refuses_the_frame() {
        // Same fail-closed rule as flags2: an unknown presence bit cannot be a
        // forward-compatible field (a new field rides a version bump), so it
        // means a corrupt or misframed push and the whole frame goes.
        let s = WatchSettings {
            auto_lap: Some(AutoLap::Km1.to_byte()),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(WatchSettings::decode(&buf[..n]), Some(s));
        let mut body = buf[..n - CRC_LEN].to_vec();
        body[7] |= 0x80;
        assert_eq!(WatchSettings::decode(&sealed(&body)), None);
    }

    #[test]
    fn an_auto_lap_byte_naming_no_rung_still_decodes_because_the_guard_is_downstream() {
        // `decode` only parses (decisions §217). The byte is refused where the
        // guard with no setter to live in runs — `settings_apply` — so a
        // garbage rung costs this field, never the frame beside it.
        let s = WatchSettings {
            auto_lap: Some(200),
            max_hr: Some(185),
            ..Default::default()
        };
        let back = roundtrip(&s);
        assert_eq!(back.auto_lap, Some(200));
        assert_eq!(back.max_hr, Some(185));
        assert_eq!(AutoLap::from_byte(200), None);
    }

    /// The frozen v5 golden vector (every v5 field, version byte 0x05) must
    /// keep decoding into exactly what it decoded into before the v6 bump: a
    /// phone that hasn't shipped the ICE encoder yet still configures the
    /// watch, and the card it never sent reads as absent, not as blank.
    #[test]
    fn v5_golden_vector_still_decodes() {
        let v5: [u8; 100] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x05, // version 5
            0xff, // flags: every version-1 field
            0x7f, // flags2: tz | distance | time | pace | race | guided | resting
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // pages = 0xc0ff (u64 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xe8, 0x03, 0x00, 0x00, // distance_interval_m = 1000
            0x08, 0x07, 0x00, 0x00, // time_interval_s = 1800
            0x2c, 0x01, // pace_band fast = 300 s/km
            0xa4, 0x01, // pace_band slow = 420 s/km
            0xd3, 0xa4, 0x00, 0x00, // race_phases distance_m = 42195
            0x38, 0x31, 0x00, 0x00, // race_phases goal_time_s = 12600
            0x00, // race_phases preset = ten_ten_ten
            0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, // guided_run id "easy-30"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NUL padding to 24
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30,
            0x00, // resting_hr = 48
            0x97, 0x6f, 0x44, 0xf0, // crc32 over every byte above (u32 LE)
        ];
        let decoded = WatchSettings::decode(&v5).expect("a v5 frame still decodes");
        assert_eq!(decoded.resting_hr, Some(48));
        assert_eq!(decoded.guided_run, Some(GuidedRunId::new("easy-30")));
        assert_eq!(
            decoded.ice, None,
            "an unsent card is absent, which leaves the watch's own card standing"
        );
    }

    /// The frozen v4 golden vector (every v4 field, version byte 0x04) must
    /// keep decoding into exactly what it decoded into before the v5 bump: a
    /// phone that hasn't shipped the resting-HR encoder yet still configures
    /// the watch.
    #[test]
    fn v4_golden_vector_still_decodes() {
        let v4: [u8; 98] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x04, // version 4
            0xff, // flags: every version-1 field
            0x3f, // flags2: tz | distance | time | pace | race | guided
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // pages = 0xc0ff (u64 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xe8, 0x03, 0x00, 0x00, // distance_interval_m = 1000
            0x08, 0x07, 0x00, 0x00, // time_interval_s = 1800
            0x2c, 0x01, // pace_band fast = 300 s/km
            0xa4, 0x01, // pace_band slow = 420 s/km
            0xd3, 0xa4, 0x00, 0x00, // race_phases distance_m = 42195
            0x38, 0x31, 0x00, 0x00, // race_phases goal_time_s = 12600
            0x00, // race_phases preset = ten_ten_ten
            0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, // guided_run id "easy-30"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NUL padding to 24
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0xcd, 0x9c,
            0x55, // crc32 over every byte above (u32 LE)
        ];
        assert_eq!(
            WatchSettings::decode(&v4),
            Some(WatchSettings {
                // A pre-v7 phone cannot name a trigger, and a pre-v8 one
                // cannot arm the storm banner, so the watch keeps what it
                // already holds rather than being reset to a default.
                auto_lap: None,
                storm_alert: None,
                max_hr: Some(190),
                pacer: Some(PacerGoalCfg {
                    distance_m: 42_195,
                    time_s: 14_400,
                }),
                gear: Some(GearCfg {
                    baseline_m: 500_000.0,
                    target_m: Some(800_000.0),
                }),
                zone_ceiling: Some(Some(3)),
                sea_level_pa: Some(101_325.0),
                fuel: Some(FuelCfg {
                    drink_interval_s: 900,
                    eat_interval_s: 1_500,
                }),
                pages: Some(0x0000_c0ff),
                hide_empty_pages: Some(true),
                tz_offset_min: Some(345),
                distance_interval_m: Some(Some(1_000)),
                time_interval_s: Some(Some(1_800)),
                pace_band: Some(Some(BAND)),
                race_phases: Some(MARATHON_PLAN),
                guided_run: Some(GuidedRunId::new("easy-30")),
                resting_hr: None,
                ice: None,
            })
        );
    }

    /// The v4-arms-only frame, pinned byte-for-byte on both sides: the only
    /// vector that exercises the five new fields without the rest of the frame.
    #[test]
    fn golden_vector_v4_arms_only() {
        let armed = WatchSettings {
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(BAND)),
            race_phases: Some(MARATHON_PLAN),
            guided_run: Some(GuidedRunId::new("easy-30")),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = armed.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[
                0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x3e, 0x00, 0xe8, 0x03, 0x00, 0x00, 0x08, 0x07,
                0x00, 0x00, 0x2c, 0x01, 0xa4, 0x01, 0xd3, 0xa4, 0x00, 0x00, 0x38, 0x31, 0x00, 0x00,
                0x00, 0x65, 0x61, 0x73, 0x79, 0x2d, 0x33, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x96, 0xd4, 0x71,
                0x78
            ]
        );
    }

    /// The resting-HR-only frame, pinned byte-for-byte on both sides — the only
    /// vector that exercises the v5 field alone.
    #[test]
    fn golden_vector_resting_hr_only() {
        let s = WatchSettings {
            resting_hr: Some(48),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x40, 0x00, 0x30, 0x00, 0x0c, 0xac, 0xd5, 0x52]
        );
    }

    /// The ICE-only frame, pinned byte-for-byte on both sides — the only
    /// vector that exercises the v6 field alone, and the one that pins the
    /// field-by-field NUL padding a shorter name must produce.
    #[test]
    fn golden_vector_ice_only() {
        let s = WatchSettings {
            ice: Some(IceCard::new("ALEX", "O NEG", "ASTHMA", "JAMIE", "555 0134")),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[
                0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x80, 0x00, 0x41, 0x4c, 0x45, 0x58, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x4f, 0x20, 0x4e, 0x45, 0x47, 0x00, 0x00, 0x00, 0x41, 0x53, 0x54, 0x48, 0x4d,
                0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x4a, 0x41, 0x4d, 0x49, 0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x35, 0x35, 0x35, 0x20, 0x30,
                0x31, 0x33, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x83, 0x1e, 0x0d, 0x7c
            ]
        );
    }

    /// The tz-only frame, pinned byte-for-byte on both sides too — it is the
    /// only field that exercises the flags2 half of the header alone, and a
    /// negative offset pins the two's-complement encoding.
    #[test]
    fn golden_vector_tz_only() {
        let s = WatchSettings {
            tz_offset_min: Some(-570),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x01, 0x00, 0xc6, 0xfd, 0xce, 0x5b, 0x97, 0xf0]
        );
    }

    /// The auto-lap-only frame. Every earlier version's field has a single-field
    /// vector; v7 and v8 shipped without one, so the two flags3 fields were
    /// pinned only inside the all-fields golden where a layout error can hide
    /// behind its neighbours' offsets. The rung is spelled as `AutoLap::Min10`
    /// rather than a bare `6` so a reorder of that enum fails here.
    #[test]
    fn golden_vector_auto_lap_only() {
        let s = WatchSettings {
            auto_lap: Some(AutoLap::Min10.to_byte()),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x00, 0x01, 0x06, 0x8d, 0x63, 0x1f, 0x14]
        );
    }

    /// The storm-only frame, the flags3 companion above. An armed threshold is
    /// tenths of a hectopascal little-endian, so 4.0 hPa is 40 — the sentinel
    /// nothing armed may collide with is 0, which `storm_alert: Some(None)`
    /// writes and `a_storm_threshold_travels_as_tenths_and_zero_is_the_disarm`
    /// covers.
    #[test]
    fn golden_vector_storm_only() {
        let s = WatchSettings {
            storm_alert: Some(Some(4.0)),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(
            &buf[..n],
            &[0x53, 0x45, 0x54, 0x31, 0x08, 0x00, 0x00, 0x02, 0x28, 0x00, 0x06, 0xb8, 0x5e, 0x48]
        );
    }

    /// The frozen v2 golden vector (every field, version byte 0x02, no CRC) is
    /// now **refused**. It decoded for as long as the CRC was optional; keeping
    /// it decodable made the checksum decorative, because any frame that fails
    /// the CRC could re-stamp itself v2 and be applied unchecked. The vector is
    /// kept rather than deleted so the rejection is pinned against the exact
    /// bytes that used to be accepted — nothing about this frame is malformed
    /// except its version.
    #[test]
    fn a_v2_golden_vector_is_refused_for_carrying_no_checksum() {
        let v2: [u8; 45] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x02, // version 2
            0xff, // flags: every version-1 field
            0x01, // flags2: tz_offset
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, // pages = 0x0000c0ff (u32 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
        ];
        assert_eq!(WatchSettings::decode(&v2), None);
        // Nor can a v2 frame buy its way back in by appending a correct
        // trailer: the version byte, not the presence of four checksum-shaped
        // bytes, is what selects the layout, so this is a v2 frame with
        // trailing bytes and it stays refused.
        let mut with_trailer = v2.to_vec();
        with_trailer.extend_from_slice(&crc32(&v2).to_le_bytes());
        assert_eq!(WatchSettings::decode(&with_trailer), None);
    }

    /// The frozen v1 golden vector (every v1 field, version byte 0x01, no
    /// `flags2`) is refused for the same reason as v2 above — it predates the
    /// checksum entirely. Kept as a vector so the rejection is pinned against
    /// the bytes an un-upgraded phone would actually have sent.
    #[test]
    fn a_v1_golden_vector_is_refused_for_carrying_no_checksum() {
        let v1: [u8; 42] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x01, // version 1
            0xff, // flags: every version-1 field
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, // pages = 0x0000c0ff (u32 LE)
            0x01, // hide_empty_pages = true
        ];
        assert_eq!(WatchSettings::decode(&v1), None);
        // As sent, that frame is refused twice over — no trailer AND a withdrawn
        // version. Sealing it isolates the version gate: the CRC now checks out,
        // so the version byte is the only thing left wrong, and the rejection
        // has to be the gate's.
        assert_eq!(WatchSettings::decode(&sealed(&v1)), None);
        // Chopped to its header it is refused too, but for the older reason —
        // so the version gate is not the only thing standing here.
        assert_eq!(WatchSettings::decode(&v1[..6]), None);
    }

    /// The version gate runs on the version byte alone, ahead of and
    /// independent of the field walk: a withdrawn version whose framing is
    /// otherwise impeccable is still refused.
    ///
    /// **Every frame here is sealed with a valid CRC**, which is the whole point
    /// — an un-sealed v1 frame is refused by the mandatory checksum whether or
    /// not the version gate exists, so testing the raw bytes would pass even
    /// with v1 decoding restored and prove nothing. Sealing leaves the version
    /// as the only defect. That also closes the bypass the withdrawal exists to
    /// close: a frame that fails its CRC must not be able to re-stamp itself v1
    /// or v2 and be waved through.
    #[test]
    fn no_pre_crc_framing_however_tidy_survives_the_version_gate() {
        for body in [
            [0x53, 0x45, 0x54, 0x31, 0x01, 0x00].as_slice(), // v1 header only
            &[0x53, 0x45, 0x54, 0x31, 0x01, 0x01, 0xbe, 0x00], // v1, one clean field
            &[0x53, 0x45, 0x54, 0x31, 0x02, 0x00, 0x00],     // v2 header only
            &[0x53, 0x45, 0x54, 0x31, 0x02, 0x01, 0x00, 0xbe, 0x00], // v2, one clean field
        ] {
            assert_eq!(
                WatchSettings::decode(&sealed(body)),
                None,
                "sealed legacy frame {body:?}"
            );
        }
        // The control, so the sealing itself cannot be what rejects: the same
        // one-field shape stamped v4 — a version that IS accepted, whose header
        // is the same width — decodes.
        let mut v4 = [0u8; HEADER_LEN + 2];
        v4[0..4].copy_from_slice(&SETTINGS_MAGIC);
        v4[4] = SETTINGS_VERSION_V4;
        v4[5] = FLAG_MAX_HR;
        v4[HEADER_LEN..].copy_from_slice(&190u16.to_le_bytes());
        assert_eq!(
            WatchSettings::decode(&sealed(&v4)).and_then(|s| s.max_hr),
            Some(190),
            "the control must decode, or the rejections above prove nothing"
        );
    }

    /// The regression that matters most: the version the phone actually emits
    /// still decodes end-to-end, fully populated, through the same `decode`
    /// that now refuses v1 / v2. Breaking the live settings path would be far
    /// worse than the integrity gap the refusal closes.
    #[test]
    fn the_current_v8_path_still_decodes_end_to_end() {
        let s = WatchSettings {
            max_hr: Some(190),
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 14_400,
            }),
            gear: Some(GearCfg {
                baseline_m: 500_000.0,
                target_m: Some(800_000.0),
            }),
            zone_ceiling: Some(Some(3)),
            sea_level_pa: Some(101_325.0),
            fuel: Some(FuelCfg {
                drink_interval_s: 900,
                eat_interval_s: 1_500,
            }),
            pages: Some(0x0000_c0ff),
            hide_empty_pages: Some(true),
            tz_offset_min: Some(345),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(BAND)),
            race_phases: Some(MARATHON_PLAN),
            guided_run: Some(GuidedRunId::new("easy-30")),
            resting_hr: Some(48),
            ice: Some(ice_card()),
            auto_lap: Some(AutoLap::Mi1.to_byte()),
            storm_alert: Some(Some(4.0)),
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(buf[4], SETTINGS_VERSION, "the encoder still stamps v8");
        assert_eq!(n, MAX_SETTINGS_LEN, "a full push is the maximal frame");
        assert_eq!(WatchSettings::decode(&buf[..n]), Some(s));
    }

    /// The frozen v3 golden vector (every field, version byte 0x03, 32-bit page
    /// mask, CRC) must keep decoding: a phone on the previous format still
    /// configures the watch, it just reaches none of the v4 settings.
    #[test]
    fn v3_golden_vector_still_decodes() {
        let v3: [u8; 49] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x03, // version 3
            0xff, // flags: every version-1 field
            0x01, // flags2: tz_offset
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
            0x80, 0xe6, 0xc5, 0x47, // sea_level_pa = 101325.0 (f32 LE)
            0x84, 0x03, 0x00, 0x00, // fuel drink_interval_s = 900
            0xdc, 0x05, 0x00, 0x00, // fuel eat_interval_s = 1500
            0xff, 0xc0, 0x00, 0x00, // pages = 0x0000c0ff (u32 LE)
            0x01, // hide_empty_pages = true
            0x59, 0x01, // tz_offset_min = +345 (+5:45, i16 LE)
            0xf4, 0x68, 0x74, 0xf1, // crc32 over every byte above
        ];
        let s = WatchSettings::decode(&v3).expect("v3 frame decodes");
        assert_eq!(s.max_hr, Some(190));
        assert_eq!(s.tz_offset_min, Some(345));
        assert_eq!(s.distance_interval_m, None, "a v3 phone arms no alerts");
        assert_eq!(s.time_interval_s, None);
        assert_eq!(s.pace_band, None);
        assert_eq!(s.race_phases, None);
        assert_eq!(s.guided_run, None);
        // A v3 frame that sets one of v4's flags2 bits is corruption, not a
        // forward-compatible field: its own encoder could not have set it.
        let mut ahead = v3;
        ahead[6] |= FLAG2_PACE_BAND;
        let body = &ahead[..ahead.len() - CRC_LEN];
        assert_eq!(WatchSettings::decode(&sealed(body)), None);
    }

    #[test]
    fn a_legacy_page_mask_leaves_pages_past_its_reach_enabled() {
        // A pre-v4 phone cannot name a page past discriminant 31. Curating one it
        // had no way to ask for would silently drop it from the cycle, so the
        // widening fails OPEN — `page::mask_from_wire`, the same rule the fan-out
        // used to apply, now applied here where the version says it is owed.
        // Seated on v3, the oldest version still accepted and the last one
        // carrying the 32-bit mask; it read v1 until the pre-CRC versions were
        // withdrawn, and the narrow-mask property is the version-independent
        // point.
        let mut body = [0u8; HEADER_LEN + PAGES_LEN_V3];
        body[0..4].copy_from_slice(&SETTINGS_MAGIC);
        body[4] = SETTINGS_VERSION_V3;
        body[5] = FLAG_PAGES;
        body[HEADER_LEN..].copy_from_slice(&0x0000_0003u32.to_le_bytes());
        let pages = WatchSettings::decode(&sealed(&body))
            .unwrap()
            .pages
            .unwrap();
        assert_eq!(pages, mask_from_wire(0x0000_0003));
        assert_eq!(pages & 0xffff_ffff, 0x0000_0003, "the low half is verbatim");
        assert_eq!(
            pages >> 32,
            u64::from(u32::MAX),
            "the unreachable half stays on"
        );
        // A v4 frame is taken at its word in both halves: there is nothing it
        // cannot address, so there is nothing to compensate for.
        let s = WatchSettings {
            pages: Some(0x0000_0000_0000_0003),
            ..Default::default()
        };
        assert_eq!(roundtrip(&s).pages, Some(3));
    }

    #[test]
    fn out_of_range_tz_offset_is_ignored_not_clamped() {
        for ok in [0i16, 345, -570, TZ_OFFSET_LIMIT_MIN, -TZ_OFFSET_LIMIT_MIN] {
            assert_eq!(plausible_tz_offset_min(Some(ok)), Some(ok));
        }
        for bad in [
            TZ_OFFSET_LIMIT_MIN + 1,
            -(TZ_OFFSET_LIMIT_MIN + 1),
            i16::MAX,
            i16::MIN,
        ] {
            assert_eq!(
                plausible_tz_offset_min(Some(bad)),
                None,
                "must ignore {bad}"
            );
        }
        assert_eq!(plausible_tz_offset_min(None), None);
    }
}
