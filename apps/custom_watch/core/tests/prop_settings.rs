//! Property tests for the phone→watch settings frame. The frame is a presence
//! bitfield followed by only the fields the bits claim, which is exactly the
//! shape that silently mis-parses when a byte goes missing — so the properties
//! here are about the frame either decoding whole or not at all, and then about
//! the fan-out (`settings_apply`) routing every field the bits did claim.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::ice::ICE_WIRE_LEN;
use watch_core::record_cadence::plausible_sea_level_pa;
use watch_core::run_store::crc32;
use watch_core::settings::{
    plausible_fuel_interval_s, plausible_tz_offset_min, race_phase_preset_from_wire, FuelCfg,
    GearCfg, GuidedRunId, PaceBandCfg, PacerGoalCfg, RacePhasesCfg, WatchSettings,
    GUIDED_RUN_ID_LEN, MAX_SETTINGS_LEN, SETTINGS_VERSION, TZ_OFFSET_LIMIT_MIN,
};
use watch_core::settings_apply::{plan_apply, EffectKind};

/// Older versions in the raw-frame generator below. `decode` still accepts v3
/// (32-bit page mask) and v4 (no resting HR); v1 (no `flags2`) and v2 (no CRC
/// trailer) are **refused** — the checksum is mandatory, so an un-checksummed
/// version cannot be allowed to stand in for one that failed its CRC. None of
/// the four is emitted any more: the encoder is v8-only. V1 and V2 stay in the
/// generator on purpose, as raw frames that must never decode.
const V1: u8 = 1;
const V2: u8 = 2;
const V3: u8 = 3;
const V4: u8 = 4;

/// The versions `decode` accepts, and therefore the only ones the success-side
/// assertions can be reached through.
const DECODABLE: [u8; 3] = [V3, V4, SETTINGS_VERSION];

/// Width of the CRC32 trailer, carried by every decodable version.
const CRC_WIDTH: usize = 4;

/// The legal domain of a settings frame — every field the encoder can carry
/// without a sentinel collapsing it. `target_m` is strictly positive (`0.0` is
/// the wire's "no target" sentinel), `zone_ceiling`'s inner value is non-zero
/// (`0` is its "clear the ceiling" sentinel), and floats are finite (a NaN is
/// not equal to itself, so it has no round-trip to assert).
fn a_settings() -> impl Strategy<Value = WatchSettings> {
    let v3_fields = (
        prop::option::of(any::<u16>()),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of((-1e9f32..1e9f32, prop::option::of(1e-3f32..1e9f32))),
        prop::option::of(prop::option::of(1u8..=u8::MAX)),
        prop::option::of(-1e9f32..1e9f32),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of(any::<u64>()),
        prop::option::of(any::<bool>()),
        prop::option::of(any::<i16>()),
    );
    // proptest implements `Strategy` for tuples up to 12 wide, so v4's five
    // fields ride a nested tuple rather than widening the flat one past that.
    let v4_fields = (
        prop::option::of(prop::option::of(1u32..=u32::MAX)),
        prop::option::of(prop::option::of(1u32..=u32::MAX)),
        prop::option::of(prop::option::of((any::<u16>(), 1u16..=u16::MAX))),
        prop::option::of((
            prop::option::of(1u32..=u32::MAX),
            prop::option::of(1u32..=u32::MAX),
            any::<u8>(),
        )),
        prop::option::of(prop::option::of(a_guided_run_id())),
        prop::option::of(any::<u16>()),
    );
    (v3_fields, v4_fields).prop_map(
        |(
            (
                max_hr,
                pacer,
                gear,
                zone_ceiling,
                sea_level_pa,
                fuel,
                pages,
                hide_empty_pages,
                tz_offset_min,
            ),
            (distance_interval_m, time_interval_s, pace_band, race_phases, guided_run, resting_hr),
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
            distance_interval_m,
            time_interval_s,
            // Not generated: the card is free-form text with no numeric edge
            // cases for a property to explore, and its codec has its own
            // fail-closed unit tests. Fixed at absent so the generator keeps
            // exercising the numeric fields it was written for.
            ice: None,
            pace_band: pace_band.map(|b| {
                b.map(|(fast_s_per_km, slow_s_per_km)| PaceBandCfg {
                    fast_s_per_km,
                    slow_s_per_km,
                })
            }),
            race_phases: race_phases.map(|(distance_m, goal_time_s, preset)| RacePhasesCfg {
                distance_m,
                goal_time_s,
                preset,
            }),
            guided_run,
            resting_hr,
            // Not generated, for the same reason `ice` is not: a closed
            // eight-rung enum has no numeric edge for a property to explore,
            // and its wire byte has its own round-trip unit tests.
            auto_lap: None,
            // Not generated either: a tenths-of-a-hectopascal threshold is a
            // narrow integer domain the codec's own round-trip tests cover, and
            // fixing it absent keeps the generator on the fields it was
            // written for.
            storm_alert: None,
        },
    )
}

/// A non-empty id that fits the field — the domain the encoder can carry without
/// the all-zero "deselect" sentinel collapsing it.
fn a_guided_run_id() -> impl Strategy<Value = GuidedRunId> {
    prop::collection::vec(prop::char::range('a', 'z'), 1..=GUIDED_RUN_ID_LEN).prop_map(|cs| {
        let s: String = cs.into_iter().collect();
        GuidedRunId::new(&s).expect("an id inside the field")
    })
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
        prop_assume!(!DECODABLE.contains(&version) && !matches!(version, V1 | V2));
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
    // shifted by however many bytes the sender meant to carry. v5 defines bits
    // 0-6, so bit 7 is the unknown one (the v4-frame-claiming-bit-6 case is
    // pinned in the unit suite).
    check(512, a_settings(), |s| {
        let mut frame = encoded(&s);
        frame[6] |= 0x80;
        prop_assert_eq!(
            WatchSettings::decode(&frame),
            None,
            "flags2 {:#04x} decoded",
            frame[6]
        );
        Ok(())
    });
}

/// Field widths in `flags` bit order: `max_hr`, `pacer`, `gear`,
/// `zone_ceiling`, `sea_level_pa`, `fuel`, `pages`, `hide_empty_pages`. The page
/// mask is the one field whose width depends on the version (4 bytes before v4),
/// so [`widths`] takes it.
fn widths(version: u8) -> [usize; 8] {
    let pages = if matches!(version, V4 | SETTINGS_VERSION) {
        8
    } else {
        4
    };
    [2, 8, 8, 1, 4, 8, pages, 1]
}

/// Widths of the `flags2` fields, in bit order: `tz_offset_min`,
/// `distance_interval_m`, `time_interval_s`, `pace_band`, `race_phases`,
/// `guided_run`, `resting_hr` (v5), `ice` (v6). One entry per bit the byte
/// defines, so a saturated presence byte is covered end to end rather than
/// seven eighths of the way.
const WIDTHS2: [usize; 8] = [2, 4, 4, 4, 9, GUIDED_RUN_ID_LEN, 2, ICE_WIRE_LEN];

/// Widths of the `flags3` fields, in bit order: `auto_lap`, `storm_alert`. The
/// byte arrived with v7 and carries the two bits it defines; the other six are
/// unknown at every version and `decode` refuses a frame that sets one.
const WIDTHS3: [usize; 2] = [1, 2];

/// Versions whose header carries a third presence byte (`flags3`). Getting this
/// wrong in either the generator or the length oracle below is invisible in the
/// common case and shows up as a ~1-in-a-billion "the declared fields account
/// for 11 of 12 bytes" failure, which is how it survived unnoticed.
fn has_flags3(version: u8) -> bool {
    version == SETTINGS_VERSION
}

/// Bytes of header the frame's version declares: magic + version + `flags`,
/// plus `flags2` from v2 and `flags3` from v7.
fn header_len(version: u8) -> usize {
    match version {
        V1 => 6,
        v if has_flags3(v) => 8,
        _ => 7,
    }
}

/// A frame assembled from raw header bytes rather than from [`WatchSettings`],
/// so the presence bytes and the payload length vary independently — the shape
/// a corrupt or hostile push actually has. A checksummed frame is sealed with its
/// real checksum whatever its length, so the CRC never shadows the length check.
fn a_raw_frame() -> impl Strategy<Value = Vec<u8>> {
    (
        prop_oneof![
            Just(V1),
            Just(V2),
            Just(V3),
            Just(V4),
            Just(SETTINGS_VERSION),
            any::<u8>()
        ],
        any::<u8>(),
        prop_oneof![Just(0u8), Just(1u8), Just(0x3Fu8), any::<u8>()],
        prop_oneof![Just(0u8), Just(1u8), Just(0x03u8), any::<u8>()],
        prop::collection::vec(any::<u8>(), 0..=90),
        any::<bool>(),
    )
        .prop_map(|(version, flags, flags2, flags3, tail, exact)| {
            let two_presence_bytes = matches!(version, V2 | V3 | V4 | SETTINGS_VERSION);
            let checksummed = matches!(version, V3 | V4 | SETTINGS_VERSION);
            let mut frame = b"SET1".to_vec();
            frame.push(version);
            frame.push(flags);
            if two_presence_bytes {
                frame.push(flags2);
            }
            if has_flags3(version) {
                frame.push(flags3);
            }
            if exact {
                // Bias toward the length the flags claim, so decode succeeds
                // often enough for the success-side assertions to bite.
                let w = widths(version);
                let mut want: usize = (0..8).filter(|i| flags & (1 << i) != 0).map(|i| w[i]).sum();
                if two_presence_bytes {
                    want += (0..WIDTHS2.len())
                        .filter(|i| flags2 & (1 << i) != 0)
                        .map(|i| WIDTHS2[i])
                        .sum::<usize>();
                }
                if has_flags3(version) {
                    want += (0..WIDTHS3.len())
                        .filter(|i| flags3 & (1 << i) != 0)
                        .map(|i| WIDTHS3[i])
                        .sum::<usize>();
                }
                let mut payload = tail.clone();
                payload.resize(want, 0);
                frame.extend_from_slice(&payload);
            } else {
                frame.extend_from_slice(&tail);
            }
            if checksummed {
                let crc = crc32(&frame);
                frame.extend_from_slice(&crc.to_le_bytes());
            }
            frame
        })
}

/// The offset walk is what makes a bitfield format dangerous: one field read at
/// the wrong width shifts every field after it. A decoded frame must therefore
/// populate exactly the flagged fields and consume exactly the bytes their
/// widths account for — nothing unread, nothing invented. A frame that does not
/// decode says nothing and passes.
///
/// Shared by the property below and the deterministic regression beside it, so
/// the oracle a rare generated case would have caught can be handed the exact
/// frame instead of waited for.
fn fields_match_the_presence_bytes(frame: &[u8]) -> Result<(), TestCaseError> {
    let Some(got) = WatchSettings::decode(frame) else {
        return Ok(());
    };
    let version = frame[4];
    // Tighter than "one of the versions that exist": v1 and v2 are in the
    // generator precisely so that reaching this line through one of them
    // would be a failure.
    prop_assert!(
        DECODABLE.contains(&version),
        "version {} decoded but is not decodable",
        version
    );
    let flags = frame[5];
    let flags2 = if version == V1 { 0 } else { frame[6] };
    let flags3 = if has_flags3(version) { frame[7] } else { 0 };

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
    let w = widths(version);
    let mut want = header_len(version);
    for (i, p) in present.iter().enumerate() {
        prop_assert_eq!(*p, flags & (1 << i) != 0, "field {} presence", i);
        if *p {
            want += w[i];
        }
    }
    let present2 = [
        got.tz_offset_min.is_some(),
        got.distance_interval_m.is_some(),
        got.time_interval_s.is_some(),
        got.pace_band.is_some(),
        got.race_phases.is_some(),
        got.guided_run.is_some(),
        got.resting_hr.is_some(),
        got.ice.is_some(),
    ];
    for (i, p) in present2.iter().enumerate() {
        prop_assert_eq!(*p, flags2 & (1 << i) != 0, "flags2 field {} presence", i);
        if *p {
            want += WIDTHS2[i];
        }
    }
    let present3 = [got.auto_lap.is_some(), got.storm_alert.is_some()];
    for (i, p) in present3.iter().enumerate() {
        prop_assert_eq!(*p, flags3 & (1 << i) != 0, "flags3 field {} presence", i);
        if *p {
            want += WIDTHS3[i];
        }
    }
    if matches!(version, V3 | V4 | SETTINGS_VERSION) {
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
}

#[test]
fn a_decoded_frame_carries_exactly_the_fields_its_presence_bytes_declare() {
    check(2048, a_raw_frame(), |frame| {
        fields_match_the_presence_bytes(&frame)
    });
}

#[test]
fn the_smallest_current_version_frame_is_measured_with_its_flags3_byte() {
    // The generated case the oracle used to get wrong, constructed rather than
    // waited for: an all-fields-absent v8 frame is header(8) + crc(4), and an
    // oracle that assumes the pre-v7 seven-byte header measures it as 11 of 12.
    // The generator reached this shape only when its tail byte happened to
    // stand in for the flags3 it never emitted, at odds around 1e-9 a case, so
    // the bug lived behind a property that ran thousands of times.
    let mut frame = b"SET1".to_vec();
    frame.push(SETTINGS_VERSION);
    frame.push(0); // flags
    frame.push(0); // flags2
    frame.push(0); // flags3
    frame.extend_from_slice(&crc32(&frame).to_le_bytes());
    assert_eq!(frame.len(), 12);
    assert_eq!(
        WatchSettings::decode(&frame),
        Some(WatchSettings::default()),
        "the frame the oracle is measured against must decode"
    );
    fields_match_the_presence_bytes(&frame).expect("the oracle accounts for every byte");
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
            prop_assert_eq!(
                got.distance_interval_m.is_some(),
                s.distance_interval_m.is_some()
            );
            prop_assert_eq!(got.time_interval_s.is_some(), s.time_interval_s.is_some());
            prop_assert_eq!(got.pace_band.is_some(), s.pace_band.is_some());
            prop_assert_eq!(got.race_phases.is_some(), s.race_phases.is_some());
            prop_assert_eq!(got.guided_run.is_some(), s.guided_run.is_some());
            Ok(())
        },
    );
}

/// How many fields the frame carries, counted off the wire's own presence
/// bitfields rather than off a list kept here — an oracle that grows with the
/// format, since a new field cannot reach the watch without a presence bit.
fn present_field_count(s: &WatchSettings) -> usize {
    let frame = encoded(s);
    (frame[5].count_ones() + frame[6].count_ones()) as usize
}

/// Where a kind sits in the [`EffectKind`] chain.
fn chain_index(kind: EffectKind) -> usize {
    let mut at = EffectKind::FIRST;
    let mut i = 0;
    while at != kind {
        at = at.next().expect("every kind is on the chain");
        i += 1;
    }
    i
}

#[test]
fn every_present_field_routes_to_exactly_one_effect() {
    // The unit suite pins the fully-populated frame; this pins all 2^14 presence
    // combinations over the whole value domain, including the guards that
    // reject rather than clamp. A field the fan-out forgets is invisible at
    // runtime — the frame decodes and the watch just ignores it — so the count
    // is taken from the presence bits the encoder itself set. The fuel guard
    // runs per arm and costs the field only when neither arm survives it.
    check(1024, a_settings(), |s| {
        let rejected = usize::from(s.sea_level_pa.is_some_and(|pa| !plausible_sea_level_pa(pa)))
            + usize::from(
                s.tz_offset_min.is_some() && plausible_tz_offset_min(s.tz_offset_min).is_none(),
            )
            + usize::from(
                s.race_phases
                    .is_some_and(|c| race_phase_preset_from_wire(c.preset).is_none()),
            )
            + usize::from(s.fuel.is_some_and(|f| {
                !plausible_fuel_interval_s(f.drink_interval_s)
                    && !plausible_fuel_interval_s(f.eat_interval_s)
            }));
        prop_assert_eq!(
            plan_apply(&s).len(),
            present_field_count(&s) - rejected,
            "{:?}",
            s
        );
        Ok(())
    });
}

#[test]
fn a_plan_feeds_each_sink_at_most_once_and_in_field_order() {
    // Two effects for one sink would mean the later silently overwrote the
    // earlier; out-of-order ones would mean the plan no longer reads like the
    // bytes that produced it.
    check(1024, a_settings(), |s| {
        let mut last: Option<usize> = None;
        for effect in plan_apply(&s) {
            let at = chain_index(effect.kind());
            prop_assert!(
                last.is_none_or(|prev| prev < at),
                "{:?} follows chain index {:?}",
                effect,
                last
            );
            last = Some(at);
        }
        Ok(())
    });
}
