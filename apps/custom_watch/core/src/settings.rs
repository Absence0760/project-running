//! Phone→watch settings frame: the wire the phone uses to push user config
//! (max HR, pacer goal, gear baseline/target, HR-zone ceiling, QNH sea-level
//! reference, fuel-reminder cadences, run-view page curation, home-clock
//! timezone offset) into the recorder's + baro task's + alert engine's
//! existing settings-sync hooks (`Recorder::set_max_hr` / `set_pacer_goal` /
//! `set_gear` / `set_pages_enabled` / `set_hide_empty_pages`,
//! `AlertEngine::set_zone_ceiling` / `set_fuel_intervals`,
//! `state::SEA_LEVEL_PA` for the baro altitude reference, and
//! `state::TZ_OFFSET_MIN` for the home clock).
//!
//! Binary, not JSON — the watch is `no_std` with no allocator and no JSON
//! parser, and the run-sync side already speaks fixed-layout little-endian
//! frames (`run_store`), so this matches that discipline: a 4-byte magic, a
//! version byte, a presence-bitfield (two of them from v2), then only the
//! present fields in bit order, then (from v3) a CRC32 trailer. Every field is
//! optional so the phone can push a partial update (just a new max HR) without
//! disturbing the rest. Decoding only *parses* — the plausibility guards stay
//! in the setters it feeds, so a garbage value is rejected by the same rule
//! whether it arrives over BLE or the sim link.

use crate::run_store::crc32;

pub const SETTINGS_MAGIC: [u8; 4] = *b"SET1";

/// Version 3 (2026-07-25): the frame gained a CRC32 trailer. Its only integrity
/// check had been that the byte count accounts for the fields the presence
/// bitfield claims, which catches any single-*bit* flip but not a single-*byte*
/// corruption that flips two bits across equal-width fields — the length is
/// unchanged, so it decodes as a fully valid but *different* update (one byte
/// turns `flags` `0xB8` into `0xE8` and the four bytes the phone sent as the
/// QNH sea-level pressure are applied as the run-view page mask). `decode`
/// accepts v1 (no `flags2`, no offset) and v2 (no CRC) alongside v3, so an old
/// phone's push keeps working; the encoder always emits v3.
pub const SETTINGS_VERSION: u8 = 3;

/// Version 2 (2026-07-22): v1's flag byte was saturated, so the ninth field
/// (`tz_offset_min`) rode that version bump into a second presence byte
/// (`flags2`) after the first.
const SETTINGS_VERSION_V2: u8 = 2;

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

/// Presence bits in the v2 `flags2` byte, continuing the field order after
/// [`FLAG_HIDE_EMPTY`].
pub const FLAG2_TZ_OFFSET: u8 = 1 << 0;

/// Every presence bit `flags2` defines. A set bit outside this mask can't be
/// a forward-compatible field — a new field rides a version bump, which
/// `decode` rejects on the version byte — so an unknown bit means a corrupt
/// or misframed push, and `decode` rejects the frame rather than silently
/// dropping whatever the sender meant by it.
const KNOWN_FLAGS2: u8 = FLAG2_TZ_OFFSET;

/// v1 header: magic (4) + version (1) + flags (1). v2 appends `flags2`.
const V1_HEADER_LEN: usize = 6;
const HEADER_LEN: usize = V1_HEADER_LEN + 1;

/// The v3 CRC32 trailer, little-endian, over every byte before it.
const CRC_LEN: usize = 4;

/// Largest a fully-populated frame can be — every field present: v2 header +
/// max_hr(2) + pacer(8) + gear(8) + zone_ceiling(1) + sea_level_pa(4) + fuel(8)
/// + pages(4) + hide_empty(1) + tz_offset(2) + the v3 CRC trailer.
pub const MAX_SETTINGS_LEN: usize = HEADER_LEN + 2 + 8 + 8 + 1 + 4 + 8 + 4 + 1 + 2 + CRC_LEN;

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
    /// discriminant `i` (`Page::bit`). The apply side force-includes the
    /// Dashboard so an all-zero mask can't empty the cycle.
    pub pages: Option<u32>,
    /// Whether the BTN3 cycle skips pages whose backing data is absent
    /// (`Recorder::set_hide_empty_pages`); the on-watch default is on.
    pub hide_empty_pages: Option<bool>,
    /// Local-time offset for the home clock, minutes east of UTC — the phone
    /// auto-sources it from its own zone on every push. Present = the home
    /// clock renders local time (its label flips UTC → LOCAL); absent = the
    /// clock stays honestly UTC-labelled. Plausibility guard:
    /// [`plausible_tz_offset_min`].
    pub tz_offset_min: Option<i16>,
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
    /// never a partial or off-frame struct. Accepts version 1 (no `flags2`, so
    /// no tz offset) and version 2 (no CRC) alongside the current version 3, so
    /// an old phone's push keeps working.
    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < V1_HEADER_LEN || b[0..4] != SETTINGS_MAGIC {
            return None;
        }
        let flags = b[5];
        // Version 1's flag byte is saturated (every bit is a known field), so
        // the unknown-bit rejection only has `flags2` left to police. This
        // assert turns the first over-saturating flag into a compile error
        // instead of a silently-accepted frame.
        const _: () = assert!(KNOWN_FLAGS == u8::MAX);
        let (b, flags2, mut off) = match b[4] {
            1 => (b, 0u8, V1_HEADER_LEN),
            SETTINGS_VERSION_V2 => (b, *b.get(6)?, HEADER_LEN),
            SETTINGS_VERSION => {
                let end = b.len().checked_sub(CRC_LEN)?;
                if end < HEADER_LEN {
                    return None;
                }
                let want = u32::from_le_bytes([b[end], b[end + 1], b[end + 2], b[end + 3]]);
                if crc32(&b[..end]) != want {
                    return None;
                }
                (&b[..end], b[6], HEADER_LEN)
            }
            _ => return None,
        };
        if flags2 & !KNOWN_FLAGS2 != 0 {
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
            let end = off + 4;
            let raw = b.get(off..end)?;
            out.pages = Some(u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]));
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
        // Bytes left over past the fields the flags claim mean a corrupt or
        // misframed push (data present for a bit that wasn't set); reject it
        // rather than silently apply a frame the phone didn't mean to send.
        if off != b.len() {
            return None;
        }
        Some(out)
    }

    /// Encode a version-3 frame into `out`, returning the byte length written,
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

        let len = HEADER_LEN
            + CRC_LEN
            + self.max_hr.map_or(0, |_| 2)
            + self.pacer.map_or(0, |_| 8)
            + self.gear.map_or(0, |_| 8)
            + self.zone_ceiling.map_or(0, |_| 1)
            + self.sea_level_pa.map_or(0, |_| 4)
            + self.fuel.map_or(0, |_| 8)
            + self.pages.map_or(0, |_| 4)
            + self.hide_empty_pages.map_or(0, |_| 1)
            + self.tz_offset_min.map_or(0, |_| 2);
        if out.len() < len {
            return None;
        }

        out[0..4].copy_from_slice(&SETTINGS_MAGIC);
        out[4] = SETTINGS_VERSION;
        out[5] = flags;
        out[6] = flags2;
        let mut off = HEADER_LEN;

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
            out[off..off + 4].copy_from_slice(&p.to_le_bytes());
            off += 4;
        }
        if let Some(h) = self.hide_empty_pages {
            out[off] = h as u8;
            off += 1;
        }
        if let Some(m) = self.tz_offset_min {
            out[off..off + 2].copy_from_slice(&m.to_le_bytes());
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
        assert_eq!(n, HEADER_LEN + CRC_LEN, "no fields => header + crc");
        assert_eq!(buf[4], SETTINGS_VERSION);
        assert_eq!(buf[5], 0, "no flags set");
        assert_eq!(buf[6], 0, "no flags2 set");
        assert_eq!(roundtrip(&s), s);
    }

    #[test]
    fn every_field_roundtrips() {
        let s = WatchSettings {
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
                pages: Some(u32::MAX),
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
        ];
        for s in cases {
            assert_eq!(roundtrip(&s), s, "roundtrip failed for {s:?}");
        }
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
        bad_ver[4] = 4;
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
        let mut header = [0u8; HEADER_LEN];
        header[0..4].copy_from_slice(&SETTINGS_MAGIC);
        header[4] = SETTINGS_VERSION;
        header[5] = 0;
        header[6] = 0x02; // bit 1: no v2 field defines it
        let frame = sealed(&header);
        assert_eq!(WatchSettings::decode(&frame), None);
        // A v3 header cut short of its flags2 byte is a short buffer, not a
        // zero flags2.
        assert_eq!(WatchSettings::decode(&frame[..V1_HEADER_LEN]), None);
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
    /// (`^ 0x50`), and the QNH sea-level pressure the phone sent is applied as
    /// the run-view page mask instead while the QNH silently vanishes — same
    /// length, same plausibility, different settings. Every equal-width pair is
    /// confusable this way (`pacer` <-> `gear` <-> `fuel`, `zone_ceiling` <->
    /// `hide_empty_pages`); the CRC turns all of them into a rejection.
    #[test]
    fn a_single_byte_flags_corruption_cannot_re_frame_qnh_as_the_page_mask() {
        let s = WatchSettings {
            sea_level_pa: Some(101_325.0),
            ..Default::default()
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        assert_eq!(buf[5], FLAG_SEA_LEVEL);

        // Re-sealed, the corruption is still a perfectly well-formed frame —
        // the length check has nothing to catch, which is the whole defect.
        let mut body = buf[..n - CRC_LEN].to_vec();
        body[5] ^= 0x50;
        let re_framed = WatchSettings::decode(&sealed(&body)).expect("length-valid under its crc");
        assert_eq!(re_framed.sea_level_pa, None);
        assert_eq!(re_framed.pages, Some(101_325.0f32.to_bits()));

        // Over the wire the sender's CRC travels with the frame, so the same
        // flip is rejected outright rather than applied as different config.
        let mut corrupt = buf;
        corrupt[5] ^= 0x50;
        assert_eq!(WatchSettings::decode(&corrupt[..n]), None);
    }

    #[test]
    fn flag_byte_is_saturated_so_the_next_field_is_a_version_bump() {
        // pages + hide_empty consumed bits 6 + 7: every bit of the first flag
        // byte is a known field, so the unknown-bit rejection only polices
        // flags2. The promised version bump happened — tz_offset (v2) rode it
        // into flags2 — and the next saturation repeats the drill: whoever
        // fills flags2's bit 7 bumps to v3.
        assert_eq!(KNOWN_FLAGS, u8::MAX);
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
                pages: Some(0x1234_5678),
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
        for tz in [None, Some(-345i16)] {
            for mask in 0u8..=u8::MAX {
                let s = WatchSettings {
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
                    pages: (mask & FLAG_PAGES != 0).then_some(0x0f0f_0f0f),
                    hide_empty_pages: (mask & FLAG_HIDE_EMPTY != 0).then_some(false),
                    tz_offset_min: tz,
                };
                let back = roundtrip(&s);
                assert_eq!(back, s, "roundtrip drift at mask {mask:#08b} tz {tz:?}");
                assert_eq!(back.max_hr.is_some(), mask & FLAG_MAX_HR != 0);
                assert_eq!(back.pacer.is_some(), mask & FLAG_PACER != 0);
                assert_eq!(back.gear.is_some(), mask & FLAG_GEAR != 0);
                assert_eq!(back.zone_ceiling.is_some(), mask & FLAG_ZONE_CEILING != 0);
                assert_eq!(back.sea_level_pa.is_some(), mask & FLAG_SEA_LEVEL != 0);
                assert_eq!(back.fuel.is_some(), mask & FLAG_FUEL != 0);
                assert_eq!(back.pages.is_some(), mask & FLAG_PAGES != 0);
                assert_eq!(back.hide_empty_pages.is_some(), mask & FLAG_HIDE_EMPTY != 0);
                assert_eq!(back.tz_offset_min, tz);
            }
        }
    }

    #[test]
    fn encode_into_too_small_buffer_returns_none() {
        let s = WatchSettings {
            max_hr: Some(190),
            ..Default::default()
        };
        let mut tiny = [0u8; HEADER_LEN + 1]; // needs +2 for max_hr
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
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        let expected: [u8; MAX_SETTINGS_LEN] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x03, // version
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
            0xf4, 0x68, 0x74, 0xf1, // crc32 over every byte above (u32 LE)
        ];
        assert_eq!(n, MAX_SETTINGS_LEN);
        assert_eq!(buf, expected);
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
            &[0x53, 0x45, 0x54, 0x31, 0x03, 0x00, 0x01, 0xc6, 0xfd, 0xb6, 0x52, 0xd9, 0xcc]
        );
    }

    /// The frozen v2 golden vector (every field, version byte 0x02, no CRC)
    /// must keep decoding into exactly what it decoded into before the v3
    /// bump: a phone that hasn't shipped the checksummed encoder yet still
    /// configures the watch.
    #[test]
    fn v2_golden_vector_still_decodes() {
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
        assert_eq!(
            WatchSettings::decode(&v2),
            Some(WatchSettings {
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
            })
        );
        // A v2 frame carrying a v3-shaped trailer is trailing bytes, not a crc.
        let mut with_trailer = v2.to_vec();
        with_trailer.extend_from_slice(&crc32(&v2).to_le_bytes());
        assert_eq!(WatchSettings::decode(&with_trailer), None);
    }

    /// The frozen v1 golden vector (every v1 field, version byte 0x01, no
    /// flags2) must keep decoding: an old phone's push still applies, it just
    /// carries no timezone offset — the clock stays UTC.
    #[test]
    fn v1_golden_vector_still_decodes_with_no_tz_offset() {
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
        let s = WatchSettings::decode(&v1).expect("v1 frame decodes");
        assert_eq!(
            s,
            WatchSettings {
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
                tz_offset_min: None,
            }
        );
        // Chopped to its header, the flags still claim every field: reject.
        assert_eq!(WatchSettings::decode(&v1[..6]), None);
    }

    #[test]
    fn v1_framing_discipline_survives_the_version_bump() {
        let header_only: [u8; 6] = [0x53, 0x45, 0x54, 0x31, 0x01, 0x00];
        assert_eq!(
            WatchSettings::decode(&header_only),
            Some(WatchSettings::default())
        );
        let max_hr: [u8; 8] = [0x53, 0x45, 0x54, 0x31, 0x01, 0x01, 0xbe, 0x00];
        assert_eq!(
            WatchSettings::decode(&max_hr).and_then(|s| s.max_hr),
            Some(190)
        );
        // Truncated field and trailing byte both still reject on v1.
        assert_eq!(WatchSettings::decode(&max_hr[..7]), None);
        let trailing: [u8; 7] = [0x53, 0x45, 0x54, 0x31, 0x01, 0x00, 0x00];
        assert_eq!(WatchSettings::decode(&trailing), None);
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
