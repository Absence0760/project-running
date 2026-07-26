//! Property tests for the phone→watch settings frame. The frame is a presence
//! bitfield followed by only the fields the bits claim, which is exactly the
//! shape that silently mis-parses when a byte goes missing — so the properties
//! here are about the frame either decoding whole or not at all.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::run_store::crc32;
use watch_core::settings::{
    plausible_tz_offset_min, FuelCfg, GearCfg, PacerGoalCfg, WatchSettings, MAX_SETTINGS_LEN,
    SETTINGS_VERSION, TZ_OFFSET_LIMIT_MIN,
};

/// The two legacy versions `decode` still accepts: v1 (no `flags2`) and v2
/// (no CRC trailer). Neither is emitted any more — the encoder is v3-only.
const V1: u8 = 1;
const V2: u8 = 2;

/// Width of the v3 CRC32 trailer.
const CRC_WIDTH: usize = 4;

/// The legal domain of a settings frame — every field the encoder can carry
/// without a sentinel collapsing it. `target_m` is strictly positive (`0.0` is
/// the wire's "no target" sentinel), `zone_ceiling`'s inner value is non-zero
/// (`0` is its "clear the ceiling" sentinel), and floats are finite (a NaN is
/// not equal to itself, so it has no round-trip to assert).
fn a_settings() -> impl Strategy<Value = WatchSettings> {
    (
        prop::option::of(any::<u16>()),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of((-1e9f32..1e9f32, prop::option::of(1e-3f32..1e9f32))),
        prop::option::of(prop::option::of(1u8..=u8::MAX)),
        prop::option::of(-1e9f32..1e9f32),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of(any::<u32>()),
        prop::option::of(any::<bool>()),
        prop::option::of(any::<i16>()),
    )
        .prop_map(
            |(
                max_hr,
                pacer,
                gear,
                zone_ceiling,
                sea_level_pa,
                fuel,
                pages,
                hide_empty_pages,
                tz_offset_min,
            )| WatchSettings {
                max_hr,
                pacer: pacer.map(|(distance_m, time_s)| PacerGoalCfg { distance_m, time_s }),
                gear: gear.map(|(baseline_m, target_m)| GearCfg {
                    baseline_m,
                    target_m,
                }),
                zone_ceiling,
                sea_level_pa,
                fuel: fuel.map(|(drink_interval_s, eat_interval_s)| FuelCfg {
                    drink_interval_s,
                    eat_interval_s,
                }),
                pages,
                hide_empty_pages,
                tz_offset_min,
            },
        )
}

fn encoded(s: &WatchSettings) -> Vec<u8> {
    let mut buf = [0u8; MAX_SETTINGS_LEN];
    let len = s.encode(&mut buf).expect("a legal settings frame encodes");
    buf[..len].to_vec()
}

#[test]
fn decode_never_panics_on_arbitrary_bytes() {
    check(
        1024,
        prop::collection::vec(any::<u8>(), 0..=(MAX_SETTINGS_LEN + 8)),
        |bytes| {
            let _ = WatchSettings::decode(&bytes);
            Ok(())
        },
    );
}

#[test]
fn a_decoded_frames_timezone_is_never_an_implausible_offset() {
    check(
        1024,
        prop::collection::vec(any::<u8>(), 0..=(MAX_SETTINGS_LEN + 8)),
        |bytes| {
            let Some(s) = WatchSettings::decode(&bytes) else {
                return Ok(());
            };
            if let Some(m) = plausible_tz_offset_min(s.tz_offset_min) {
                prop_assert!(
                    (-TZ_OFFSET_LIMIT_MIN..=TZ_OFFSET_LIMIT_MIN).contains(&m),
                    "plausible offset {m} is outside the UTC range"
                );
            }
            Ok(())
        },
    );
}

#[test]
fn a_settings_frame_round_trips_within_its_declared_cap() {
    check(1024, a_settings(), |s| {
        let frame = encoded(&s);
        prop_assert!(
            frame.len() <= MAX_SETTINGS_LEN,
            "a {}-byte frame exceeds the {MAX_SETTINGS_LEN}-byte cap",
            frame.len()
        );
        prop_assert_eq!(WatchSettings::decode(&frame), Some(s));
        Ok(())
    });
}

#[test]
fn a_frame_never_fits_a_buffer_smaller_than_it_needs() {
    check(512, (a_settings(), any::<Index>()), |(s, idx)| {
        let len = encoded(&s).len();
        let short = idx.index(len);
        let mut buf = vec![0u8; short];
        prop_assert_eq!(s.encode(&mut buf), None, "encoded into {} bytes", short);
        Ok(())
    });
}

#[test]
fn every_proper_prefix_of_a_frame_is_rejected() {
    check(512, (a_settings(), any::<Index>()), |(s, idx)| {
        let frame = encoded(&s);
        let cut = idx.index(frame.len());
        prop_assert_eq!(
            WatchSettings::decode(&frame[..cut]),
            None,
            "a {} of {} byte prefix decoded",
            cut,
            frame.len()
        );
        Ok(())
    });
}

#[test]
fn a_frame_with_bytes_past_the_fields_the_flags_claim_is_rejected() {
    check(
        512,
        (a_settings(), prop::collection::vec(any::<u8>(), 1..=6)),
        |(s, tail)| {
            let mut frame = encoded(&s);
            frame.extend_from_slice(&tail);
            prop_assert_eq!(
                WatchSettings::decode(&frame),
                None,
                "{} trailing bytes decoded",
                tail.len()
            );
            Ok(())
        },
    );
}

#[test]
fn an_unknown_version_byte_is_rejected() {
    check(512, (a_settings(), any::<u8>()), |(s, version)| {
        prop_assume!(!matches!(version, V1 | V2 | SETTINGS_VERSION));
        let mut frame = encoded(&s);
        frame[4] = version;
        prop_assert_eq!(
            WatchSettings::decode(&frame),
            None,
            "version {} decoded",
            version
        );
        Ok(())
    });
}

#[test]
fn a_corrupt_magic_is_rejected() {
    check(
        512,
        (a_settings(), 0usize..4, 1u8..=u8::MAX),
        |(s, at, mask)| {
            let mut frame = encoded(&s);
            frame[at] ^= mask;
            prop_assert_eq!(
                WatchSettings::decode(&frame),
                None,
                "a flipped magic byte {} decoded",
                at
            );
            Ok(())
        },
    );
}

#[test]
fn an_unknown_presence_bit_in_flags2_is_rejected() {
    // A new field always rides a version bump, so a set bit `flags2` doesn't
    // define can only be corruption — decoding past it would apply a frame
    // shifted by however many bytes the sender meant to carry.
    check(512, (a_settings(), 1u8..=0x7F), |(s, extra)| {
        let mut frame = encoded(&s);
        frame[6] |= extra << 1;
        prop_assert_eq!(
            WatchSettings::decode(&frame),
            None,
            "flags2 {:#04x} decoded",
            frame[6]
        );
        Ok(())
    });
}

/// Field widths in presence-bit order: `max_hr`, `pacer`, `gear`,
/// `zone_ceiling`, `sea_level_pa`, `fuel`, `pages`, `hide_empty_pages`, then
/// `flags2`'s `tz_offset_min`.
const WIDTHS: [usize; 8] = [2, 8, 8, 1, 4, 8, 4, 1];
const TZ_WIDTH: usize = 2;

/// A frame assembled from raw header bytes rather than from [`WatchSettings`],
/// so the presence bytes and the payload length vary independently — the shape
/// a corrupt or hostile push actually has. A v3 frame is sealed with its real
/// checksum whatever its length, so the CRC never shadows the length check.
fn a_raw_frame() -> impl Strategy<Value = Vec<u8>> {
    (
        prop_oneof![Just(V1), Just(V2), Just(SETTINGS_VERSION), any::<u8>()],
        any::<u8>(),
        prop_oneof![Just(0u8), Just(1u8), any::<u8>()],
        prop::collection::vec(any::<u8>(), 0..=40),
        any::<bool>(),
    )
        .prop_map(|(version, flags, flags2, tail, exact)| {
            let two_presence_bytes = version == V2 || version == SETTINGS_VERSION;
            let mut frame = b"SET1".to_vec();
            frame.push(version);
            frame.push(flags);
            if two_presence_bytes {
                frame.push(flags2);
            }
            if exact {
                // Bias toward the length the flags claim, so decode succeeds
                // often enough for the success-side assertions to bite.
                let mut want: usize = (0..8)
                    .filter(|i| flags & (1 << i) != 0)
                    .map(|i| WIDTHS[i])
                    .sum();
                if two_presence_bytes && flags2 & 1 != 0 {
                    want += TZ_WIDTH;
                }
                let mut payload = tail.clone();
                payload.resize(want, 0);
                frame.extend_from_slice(&payload);
            } else {
                frame.extend_from_slice(&tail);
            }
            if version == SETTINGS_VERSION {
                let crc = crc32(&frame);
                frame.extend_from_slice(&crc.to_le_bytes());
            }
            frame
        })
}

#[test]
fn a_decoded_frame_carries_exactly_the_fields_its_presence_bytes_declare() {
    // The offset walk is what makes a bitfield format dangerous: one field
    // read at the wrong width shifts every field after it. A decoded frame
    // must therefore populate exactly the flagged fields and consume exactly
    // the bytes their widths account for — nothing unread, nothing invented.
    check(2048, a_raw_frame(), |frame| {
        let Some(got) = WatchSettings::decode(&frame) else {
            return Ok(());
        };
        let version = frame[4];
        prop_assert!(matches!(version, V1 | V2 | SETTINGS_VERSION));
        let flags = frame[5];
        let (flags2, header_len) = if version == V1 { (0, 6) } else { (frame[6], 7) };

        let present = [
            got.max_hr.is_some(),
            got.pacer.is_some(),
            got.gear.is_some(),
            got.zone_ceiling.is_some(),
            got.sea_level_pa.is_some(),
            got.fuel.is_some(),
            got.pages.is_some(),
            got.hide_empty_pages.is_some(),
        ];
        let mut want = header_len;
        for (i, p) in present.iter().enumerate() {
            prop_assert_eq!(*p, flags & (1 << i) != 0, "field {} presence", i);
            if *p {
                want += WIDTHS[i];
            }
        }
        prop_assert_eq!(got.tz_offset_min.is_some(), flags2 & 1 != 0);
        if got.tz_offset_min.is_some() {
            want += TZ_WIDTH;
        }
        if version == SETTINGS_VERSION {
            want += CRC_WIDTH;
        }
        prop_assert_eq!(
            frame.len(),
            want,
            "the declared fields account for {} of {} bytes",
            want,
            frame.len()
        );
        Ok(())
    });
}

#[test]
fn a_single_bit_flip_of_a_presence_byte_is_always_caught() {
    // Flipping one presence bit changes the length the flags claim, so the
    // exact-length check rejects the frame on its own — before the v3 CRC the
    // property below relies on ever gets a say.
    check(1024, (a_settings(), 5usize..=6, 0u32..8), |(s, at, bit)| {
        let mut frame = encoded(&s);
        frame[at] ^= 1 << bit;
        prop_assert_eq!(
            WatchSettings::decode(&frame),
            None,
            "bit {} of byte {} survived",
            bit,
            at
        );
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_frame_claiming_different_fields() {
    // The exact-length check catches any single-*bit* flip, but not a
    // single-*byte* one that flips two bits across equal-width fields: `flags`
    // 0x10 ^ 0x50 -> 0x40 leaves the length untouched and applies the four
    // bytes the phone sent as the QNH sea-level pressure as the run-view
    // `pages` mask instead. Every equal-width pair is confusable this way
    // (sea_level <-> pages, pacer <-> gear <-> fuel, zone_ceiling <->
    // hide_empty), which is why v3 carries the same crc32 the rest of the
    // firmware's wire formats do.
    check(
        1024,
        (a_settings(), any::<Index>(), 1u8..=u8::MAX),
        |(s, idx, mask)| {
            let mut frame = encoded(&s);
            let at = idx.index(frame.len());
            frame[at] ^= mask;
            let Some(got) = WatchSettings::decode(&frame) else {
                return Ok(());
            };
            prop_assert_eq!(got.max_hr.is_some(), s.max_hr.is_some());
            prop_assert_eq!(got.pacer.is_some(), s.pacer.is_some());
            prop_assert_eq!(got.gear.is_some(), s.gear.is_some());
            prop_assert_eq!(got.zone_ceiling.is_some(), s.zone_ceiling.is_some());
            prop_assert_eq!(got.sea_level_pa.is_some(), s.sea_level_pa.is_some());
            prop_assert_eq!(got.fuel.is_some(), s.fuel.is_some());
            prop_assert_eq!(got.pages.is_some(), s.pages.is_some());
            prop_assert_eq!(got.hide_empty_pages.is_some(), s.hide_empty_pages.is_some());
            prop_assert_eq!(got.tz_offset_min.is_some(), s.tz_offset_min.is_some());
            Ok(())
        },
    );
}
