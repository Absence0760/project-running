//! Frame boundaries on the phone link's settings pipe — the byte accumulator
//! that used to sit inlined in `app/src/tasks/phone.rs`'s `settings_rx`.
//!
//! [`crate::settings`] owns the wire layout. What is left, and lives here, is
//! only where one pushed frame ends and the next begins. The pipe carries no
//! length prefix and no delimiter, so the boundary is an idle gap: the TCP
//! bridge delivers a pushed frame's bytes back-to-back, and anything slower is
//! a new push.
//!
//! Two rules a driver must not get wrong:
//!
//! - **The buffer holds exactly one maximal frame.** A fully-populated frame
//!   is [`MAX_SETTINGS_LEN`] bytes to the byte, and the phone's encoder emits
//!   one whenever it pushes every field — so an accumulator one byte short
//!   would refuse the largest legitimate push, and refuse it silently: the only
//!   evidence is a log line on a device with no console attached.
//! - **Oversize latches, and the whole push dies with it.** Once more bytes
//!   arrive than a frame can be, what is buffered is a prefix of something
//!   else; decoding it could apply settings the phone never sent. The latch has
//!   to clear at the boundary too, or one over-long push would keep poisoning
//!   the ones after it.
//!
//! This is the sim's only settings path — the `ble` build serves the same
//! frames from a GATT characteristic and compiles that driver out entirely — so
//! it is what proved a settings push end-to-end before any hardware existed.

use crate::settings::{WatchSettings, MAX_SETTINGS_LEN};

/// Idle gap that marks a frame boundary, in milliseconds. Milliseconds rather
/// than an `embassy_time::Duration` so this crate keeps its "pure logic over
/// plain data, no Embassy" contract; the driver builds the timer from it.
pub const FRAME_GAP_MS: u64 = 100;

/// What a closed frame boundary turned out to hold.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SettingsPush {
    /// The gap closed on an empty buffer — nothing was pushed. Distinct from
    /// [`SettingsPush::Rejected`] even though an empty slice is not a settings
    /// frame either: reported as a rejection, every idle stretch of the link
    /// would log a warning about a push that never happened.
    Empty,
    /// More bytes arrived before the gap than any settings frame can carry.
    Oversize,
    /// The buffered bytes are not a settings frame — bad magic, unknown
    /// version, failed CRC, a field the flags claim but the bytes lack, or
    /// bytes past the fields the flags claim.
    Rejected { len: usize },
    /// A decoded update, ready for the settings-sync hooks.
    Applied { settings: WatchSettings, len: usize },
}

/// Accumulates pushed bytes between idle gaps.
pub struct SettingsFramer {
    buf: [u8; MAX_SETTINGS_LEN],
    len: usize,
    oversize: bool,
}

impl SettingsFramer {
    pub const fn new() -> Self {
        Self {
            buf: [0u8; MAX_SETTINGS_LEN],
            len: 0,
            oversize: false,
        }
    }

    /// Whether nothing has been pushed since the last boundary. A driver waits
    /// for the next byte with no gap timer running in that state, so an idle
    /// link costs no wakeups.
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Take one read's worth of bytes — a whole read, not one byte, because the
    /// boundary is the gap and never a read edge: where a driver's reads happen
    /// to split a frame must not change how that frame decodes.
    ///
    /// Once the buffer is full a further byte latches oversize and the rest of
    /// the push is dropped, rather than overwriting bytes already held.
    pub fn push(&mut self, bytes: &[u8]) {
        for &b in bytes {
            if self.len == self.buf.len() {
                self.oversize = true;
                return;
            }
            self.buf[self.len] = b;
            self.len += 1;
        }
    }

    /// Close the boundary: decode whatever accumulated, then start the next
    /// frame clean.
    pub fn on_gap(&mut self) -> SettingsPush {
        let out = if self.oversize {
            SettingsPush::Oversize
        } else if self.len == 0 {
            SettingsPush::Empty
        } else {
            match WatchSettings::decode(&self.buf[..self.len]) {
                Some(settings) => SettingsPush::Applied {
                    settings,
                    len: self.len,
                },
                None => SettingsPush::Rejected { len: self.len },
            }
        };
        self.reset();
        out
    }

    /// Drop a partial frame. A driver calls this when the pipe itself errors
    /// mid-frame: the bytes either side of a failed read cannot be known to
    /// belong to the same push, so joining them would decode a frame nobody
    /// sent.
    pub fn reset(&mut self) {
        self.len = 0;
        self.oversize = false;
    }
}

impl Default for SettingsFramer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::{
        FuelCfg, GearCfg, GuidedRunId, PaceBandCfg, PacerGoalCfg, RacePhasesCfg,
    };

    /// Every field present, so `encode` emits a frame of exactly
    /// [`MAX_SETTINGS_LEN`] bytes — the maximal push the phone can make.
    fn maximal() -> WatchSettings {
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
            tz_offset_min: Some(345),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(PaceBandCfg {
                fast_s_per_km: 300,
                slow_s_per_km: 420,
            })),
            race_phases: Some(RacePhasesCfg {
                distance_m: Some(42_195),
                goal_time_s: Some(12_600),
                preset: 0,
            }),
            guided_run: Some(GuidedRunId::new("tempo-builder-25")),
        }
    }

    fn encoded(s: &WatchSettings) -> Vec<u8> {
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        let n = s.encode(&mut buf).expect("encodes");
        buf[..n].to_vec()
    }

    /// Push `bytes` a byte at a time, the way the UARTE driver reads them, then
    /// close the boundary.
    fn push_then_gap(framer: &mut SettingsFramer, bytes: &[u8]) -> SettingsPush {
        for b in bytes {
            framer.push(&[*b]);
        }
        framer.on_gap()
    }

    #[test]
    fn a_maximal_frame_is_accepted_to_its_last_byte() {
        // The live off-by-one risk: the buffer is sized MAX_SETTINGS_LEN and a
        // fully-populated frame is exactly that long, so a capacity one short
        // would refuse every all-fields push with only a log line to show for
        // it. MAX_SETTINGS_LEN has grown three times now (45 -> 49 for the v3
        // CRC trailer -> 98 for v4's five settings and the 64-bit page mask),
        // and each growth re-runs this risk.
        let s = maximal();
        let frame = encoded(&s);
        assert_eq!(
            frame.len(),
            MAX_SETTINGS_LEN,
            "the all-fields frame is the buffer capacity"
        );

        let mut framer = SettingsFramer::new();
        assert_eq!(
            push_then_gap(&mut framer, &frame),
            SettingsPush::Applied {
                settings: s,
                len: MAX_SETTINGS_LEN
            }
        );
    }

    #[test]
    fn one_byte_past_a_maximal_frame_refuses_the_whole_push() {
        // The buffer is full at MAX_SETTINGS_LEN, so the extra byte cannot be
        // held. It must not be dropped quietly either: the first
        // MAX_SETTINGS_LEN bytes still decode perfectly on their own, and
        // applying them would honour a frame whose sender clearly meant
        // something else.
        let mut frame = encoded(&maximal());
        frame.push(0x00);
        assert_eq!(frame.len(), MAX_SETTINGS_LEN + 1);

        let mut framer = SettingsFramer::new();
        assert_eq!(push_then_gap(&mut framer, &frame), SettingsPush::Oversize);
    }

    #[test]
    fn an_arbitrarily_long_push_is_refused_the_same_way() {
        let mut framer = SettingsFramer::new();
        let flood = [0xABu8; MAX_SETTINGS_LEN * 4];
        assert_eq!(push_then_gap(&mut framer, &flood), SettingsPush::Oversize);
    }

    #[test]
    fn the_oversize_latch_does_not_corrupt_the_next_frame() {
        // A latch that survived the boundary would turn one over-long push into
        // every later push being discarded — the settings pipe dead until
        // reboot, with no state visible to say why.
        let mut framer = SettingsFramer::new();
        let mut too_long = encoded(&maximal());
        too_long.push(0x00);
        assert_eq!(
            push_then_gap(&mut framer, &too_long),
            SettingsPush::Oversize
        );

        let s = maximal();
        let frame = encoded(&s);
        assert_eq!(
            push_then_gap(&mut framer, &frame),
            SettingsPush::Applied {
                settings: s,
                len: MAX_SETTINGS_LEN
            },
            "the push after an oversize one must decode on its own merits"
        );
        assert!(framer.is_empty());
    }

    #[test]
    fn an_idle_gap_with_nothing_buffered_yields_nothing() {
        // Not a rejection: an empty slice fails `decode` like any other
        // non-frame, so reporting it as one would warn on every quiet stretch
        // of the link about a push that never happened.
        let mut framer = SettingsFramer::new();
        for _ in 0..5 {
            assert_eq!(framer.on_gap(), SettingsPush::Empty);
        }
        assert!(framer.is_empty());
    }

    #[test]
    fn a_frame_split_across_arbitrary_read_chunks_reassembles_identically() {
        // Where the reads land is the transport's business, not the frame's.
        let s = maximal();
        let frame = encoded(&s);
        let expected = SettingsPush::Applied {
            settings: s,
            len: frame.len(),
        };

        for chunk in 1..=frame.len() {
            let mut framer = SettingsFramer::new();
            for part in frame.chunks(chunk) {
                framer.push(part);
            }
            assert_eq!(framer.on_gap(), expected, "chunked by {chunk}");
        }

        // And an uneven split, including a zero-length read.
        let mut framer = SettingsFramer::new();
        framer.push(&frame[..1]);
        framer.push(&[]);
        framer.push(&frame[1..7]);
        framer.push(&frame[7..8]);
        framer.push(&frame[8..]);
        assert_eq!(framer.on_gap(), expected);
    }

    #[test]
    fn every_frame_length_the_encoder_emits_survives_the_accumulator() {
        // Presence bits change the frame length, so the accumulator has to hold
        // every length between a bare header and the maximum — not just the
        // two ends. Walking `flags` alongside the five `flags2` fields covers
        // the whole span rather than only the first byte's half of it.
        for mask in 0u8..=u8::MAX {
            let s = WatchSettings {
                max_hr: (mask & 0x01 != 0).then_some(175),
                pacer: (mask & 0x02 != 0).then_some(PacerGoalCfg {
                    distance_m: 10_000,
                    time_s: 3_000,
                }),
                gear: (mask & 0x04 != 0).then_some(GearCfg {
                    baseline_m: 250_000.0,
                    target_m: None,
                }),
                zone_ceiling: (mask & 0x08 != 0).then_some(Some(2)),
                sea_level_pa: (mask & 0x10 != 0).then_some(99_000.0),
                fuel: (mask & 0x20 != 0).then_some(FuelCfg {
                    drink_interval_s: 450,
                    eat_interval_s: 1_000,
                }),
                pages: (mask & 0x40 != 0).then_some(0x0f0f_0f0f_f0f0_f0f0),
                hide_empty_pages: (mask & 0x80 != 0).then_some(false),
                tz_offset_min: Some(-570),
                distance_interval_m: (mask & 0x01 != 0).then_some(Some(1_000)),
                time_interval_s: (mask & 0x02 != 0).then_some(None),
                pace_band: (mask & 0x04 != 0).then_some(Some(PaceBandCfg {
                    fast_s_per_km: 300,
                    slow_s_per_km: 420,
                })),
                race_phases: (mask & 0x08 != 0).then_some(RacePhasesCfg {
                    distance_m: Some(42_195),
                    goal_time_s: None,
                    preset: 2,
                }),
                guided_run: (mask & 0x10 != 0).then(|| GuidedRunId::new("easy-30")),
            };
            let frame = encoded(&s);
            let mut framer = SettingsFramer::new();
            assert_eq!(
                push_then_gap(&mut framer, &frame),
                SettingsPush::Applied {
                    settings: s,
                    len: frame.len()
                },
                "mask {mask:#04x}"
            );
        }
    }

    #[test]
    fn a_read_error_drops_the_partial_frame_and_nothing_else() {
        let s = maximal();
        let frame = encoded(&s);

        let mut framer = SettingsFramer::new();
        framer.push(&frame[..20]);
        framer.reset();
        assert!(framer.is_empty());
        assert_eq!(
            push_then_gap(&mut framer, &frame),
            SettingsPush::Applied {
                settings: s,
                len: frame.len()
            },
            "the half-frame before the error must not prefix the next push"
        );
    }

    #[test]
    fn a_reset_clears_the_oversize_latch_too() {
        let mut framer = SettingsFramer::new();
        framer.push(&[0xFFu8; MAX_SETTINGS_LEN + 1]);
        framer.reset();
        assert_eq!(framer.on_gap(), SettingsPush::Empty);
    }

    #[test]
    fn a_buffer_that_is_not_a_settings_frame_is_rejected_with_its_length() {
        let mut framer = SettingsFramer::new();
        assert_eq!(
            push_then_gap(&mut framer, b"hello"),
            SettingsPush::Rejected { len: 5 }
        );

        // A real frame whose checksum was corrupted in flight: the codec's
        // fail-closed rules are what reject it, the framer only reports.
        let mut corrupt = encoded(&maximal());
        corrupt[5] ^= 0x50;
        let len = corrupt.len();
        assert_eq!(
            push_then_gap(&mut framer, &corrupt),
            SettingsPush::Rejected { len }
        );
    }

    #[test]
    fn two_frames_pushed_without_a_gap_between_them_apply_neither() {
        // The gap is the only boundary there is, so back-to-back frames are one
        // buffer. Both outcomes are fail-closed, and which one it is depends
        // only on whether the pair fits: the codec's trailing-bytes rule
        // catches the short pair, the capacity catches the long one.
        let short = encoded(&WatchSettings {
            tz_offset_min: Some(345),
            ..Default::default()
        });
        let mut pair = short.clone();
        pair.extend_from_slice(&short);
        assert!(pair.len() <= MAX_SETTINGS_LEN);
        let mut framer = SettingsFramer::new();
        assert_eq!(
            push_then_gap(&mut framer, &pair),
            SettingsPush::Rejected { len: pair.len() }
        );

        let big = encoded(&maximal());
        let mut pair = big.clone();
        pair.extend_from_slice(&big);
        assert_eq!(push_then_gap(&mut framer, &pair), SettingsPush::Oversize);
    }

    #[test]
    fn a_short_legacy_frame_still_applies() {
        // The v1 golden vector, which an un-upgraded phone still pushes: it is
        // well under the buffer, and nothing about the accumulator may care.
        let v1: [u8; 8] = [0x53, 0x45, 0x54, 0x31, 0x01, 0x01, 0xbe, 0x00];
        let mut framer = SettingsFramer::new();
        assert_eq!(
            push_then_gap(&mut framer, &v1),
            SettingsPush::Applied {
                settings: WatchSettings {
                    max_hr: Some(190),
                    ..Default::default()
                },
                len: 8
            }
        );
    }

    #[test]
    fn is_empty_tracks_the_frame_boundary() {
        // The driver only arms the gap timer once a frame has started, so this
        // flag decides whether an idle link wakes the CPU at all.
        let mut framer = SettingsFramer::new();
        assert!(framer.is_empty());
        framer.push(&[0x53]);
        assert!(!framer.is_empty());
        framer.on_gap();
        assert!(framer.is_empty());
        framer.push(&[0xFFu8; MAX_SETTINGS_LEN + 1]);
        assert!(
            !framer.is_empty(),
            "an oversize push is still an open frame"
        );
    }
}
