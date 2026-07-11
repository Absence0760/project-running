//! Phone→watch settings frame: the wire the phone uses to push user config
//! (max HR, pacer goal, gear baseline/target, HR-zone ceiling) into the
//! recorder's existing settings-sync hooks (`Recorder::set_max_hr` /
//! `set_pacer_goal` / `set_gear`, `AlertEngine::set_zone_ceiling`).
//!
//! Binary, not JSON — the watch is `no_std` with no allocator and no JSON
//! parser, and the run-sync side already speaks fixed-layout little-endian
//! frames (`run_store`), so this matches that discipline: a 4-byte magic, a
//! version byte, a presence-bitfield, then only the present fields in bit
//! order. Every field is optional so the phone can push a partial update (just
//! a new max HR) without disturbing the rest. Decoding only *parses* — the
//! plausibility guards stay in the setters it feeds, so a garbage value is
//! rejected by the same rule whether it arrives over BLE or the sim link.

pub const SETTINGS_MAGIC: [u8; 4] = *b"SET1";
pub const SETTINGS_VERSION: u8 = 1;

/// Presence bits, in the order the fields are laid out after the header.
pub const FLAG_MAX_HR: u8 = 1 << 0;
pub const FLAG_PACER: u8 = 1 << 1;
pub const FLAG_GEAR: u8 = 1 << 2;
pub const FLAG_ZONE_CEILING: u8 = 1 << 3;

/// Header: magic (4) + version (1) + flags (1).
const HEADER_LEN: usize = 6;

/// Largest a fully-populated frame can be — every field present:
/// header + max_hr(2) + pacer(8) + gear(8) + zone_ceiling(1).
pub const MAX_SETTINGS_LEN: usize = HEADER_LEN + 2 + 8 + 8 + 1;

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
}

impl WatchSettings {
    /// Decode a settings frame. Returns `None` on a bad magic, an unknown
    /// version, or a buffer too short for the fields the flags claim — never a
    /// partial struct off a truncated frame.
    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() < HEADER_LEN || b[0..4] != SETTINGS_MAGIC || b[4] != SETTINGS_VERSION {
            return None;
        }
        let flags = b[5];
        let mut off = HEADER_LEN;
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
        }
        Some(out)
    }

    /// Encode into `out`, returning the byte length written, or `None` if `out`
    /// is smaller than the frame needs. Only present fields are written, in flag
    /// order — the mirror the phone encoder pins to.
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

        let len = HEADER_LEN
            + self.max_hr.map_or(0, |_| 2)
            + self.pacer.map_or(0, |_| 8)
            + self.gear.map_or(0, |_| 8)
            + self.zone_ceiling.map_or(0, |_| 1);
        if out.len() < len {
            return None;
        }

        out[0..4].copy_from_slice(&SETTINGS_MAGIC);
        out[4] = SETTINGS_VERSION;
        out[5] = flags;
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
        Some(off)
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
        assert_eq!(n, HEADER_LEN, "no fields => header only");
        assert_eq!(buf[5], 0, "no flags set");
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
        bad_ver[4] = 2;
        assert_eq!(WatchSettings::decode(&bad_ver), None);
        assert_eq!(WatchSettings::decode(&[]), None);
        assert_eq!(WatchSettings::decode(b"SE"), None);
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
        };
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).unwrap();
        let expected: [u8; MAX_SETTINGS_LEN] = [
            0x53, 0x45, 0x54, 0x31, // "SET1"
            0x01, // version
            0x0f, // flags: max_hr | pacer | gear | zone_ceiling
            0xbe, 0x00, // max_hr = 190
            0xd3, 0xa4, 0x00, 0x00, // pacer distance_m = 42195
            0x40, 0x38, 0x00, 0x00, // pacer time_s = 14400
            0x00, 0x24, 0xf4, 0x48, // gear baseline_m = 500000.0 (f32 LE)
            0x00, 0x50, 0x43, 0x49, // gear target_m = 800000.0 (f32 LE)
            0x03, // zone_ceiling = 3
        ];
        assert_eq!(n, MAX_SETTINGS_LEN);
        assert_eq!(buf, expected);
    }
}
