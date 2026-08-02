//! Property tests for `RCF1`, the persisted race-configuration record.
//!
//! The record is read back from a flash page that may be erased, half-written,
//! stale or simply garbage, and what it configures is a runner's pacer goal, HR
//! ceiling, QNH reference and fuel cadence mid-race — so the contract is the one
//! every other codec on that page holds to: a record this firmware wrote comes
//! back exactly, and anything else reads as "no saved config" rather than as a
//! configuration nobody set. The record seals a whole `SET1` frame under its own
//! CRC32, so the sharp property is the corruption one: no single flipped byte
//! may ever yield a config DIFFERENT from the one encoded.
//!
//! The frame inside is [`watch_core::settings`]'s own and has its own suite
//! (`prop_settings`); what is pinned here is the wrapper, the persistable filter
//! that decides which fields may ride it at all, and the delta merge that keeps
//! a one-field push from erasing everything the runner set before it.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::ice::IceCard;
use watch_core::race_config::{
    decode, encode, merged, persistable, record_differs, RACE_CONFIG_RECORD_LEN, RCF1_MAGIC,
    RCF1_VERSION,
};
use watch_core::settings::{
    FuelCfg, GearCfg, GuidedRunId, PaceBandCfg, PacerGoalCfg, RacePhasesCfg, WatchSettings,
    GUIDED_RUN_ID_LEN,
};

/// A byte string guaranteed to differ from `record` in exactly one position, so
/// a corruption property can never accidentally test the identity.
fn corrupted(record: &[u8], at: usize, delta: u8) -> Vec<u8> {
    let mut b = record.to_vec();
    b[at] ^= delta;
    b
}

fn a_guided_run_id() -> impl Strategy<Value = GuidedRunId> {
    prop::collection::vec(prop::char::range('a', 'z'), 1..=GUIDED_RUN_ID_LEN).prop_map(|cs| {
        let s: String = cs.into_iter().collect();
        GuidedRunId::new(&s).expect("an id inside the field")
    })
}

/// The card is free-form text with no numeric edge for a property to explore and
/// has its own suite in `prop_push_codecs`; a fixed one is enough to prove this
/// record never carries it.
fn a_card() -> IceCard {
    IceCard::new(
        "ALEX MORGAN",
        "O NEG",
        "PENICILLIN, ASTHMA",
        "JAMIE MORGAN",
        "+1 555 0134",
    )
    .expect("printable fields within their caps pack")
}

/// The legal domain of a settings frame, generated over ALL eighteen fields —
/// including the four that must never survive the filter, so the drop is
/// asserted against frames that actually carried them.
///
/// Floats are finite: a NaN is not equal to itself, so it has no struct-equality
/// round-trip to assert. The NaN case is what
/// `race_config::tests::a_repeated_push_of_one_unchanged_frame_never_rewrites_the_page`
/// pins, over the bytes instead.
fn a_settings() -> impl Strategy<Value = WatchSettings> {
    let scalars = (
        prop::option::of(any::<u16>()),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of((-1e9f32..1e9f32, prop::option::of(1e-3f32..1e9f32))),
        prop::option::of(prop::option::of(1u8..=u8::MAX)),
        prop::option::of(-1e9f32..1e9f32),
        prop::option::of((any::<u32>(), any::<u32>())),
        prop::option::of(any::<i16>()),
        prop::option::of(any::<u16>()),
    );
    let cadences = (
        prop::option::of(prop::option::of(1u32..=u32::MAX)),
        prop::option::of(prop::option::of(1u32..=u32::MAX)),
        prop::option::of(prop::option::of((any::<u16>(), 1u16..=u16::MAX))),
        prop::option::of((
            prop::option::of(1u32..=u32::MAX),
            prop::option::of(1u32..=u32::MAX),
            any::<u8>(),
        )),
        prop::option::of(prop::option::of(a_guided_run_id())),
        prop::option::of(prop::option::of(1u16..=u16::MAX)),
    );
    // The four with a persistent home of their own, generated so the filter is
    // tested against frames that carry them rather than against frames that
    // never did.
    let elsewhere = (
        prop::option::of(any::<u64>()),
        prop::option::of(any::<bool>()),
        prop::option::of(prop::option::of(Just(a_card()))),
        prop::option::of(any::<u8>()),
    );
    (scalars, cadences, elsewhere).prop_map(
        |(
            (max_hr, pacer, gear, zone_ceiling, sea_level_pa, fuel, tz_offset_min, resting_hr),
            (distance_interval_m, time_interval_s, pace_band, race_phases, guided_run, storm_alert),
            (pages, hide_empty_pages, ice, auto_lap),
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
            ice,
            auto_lap,
            // Tenths of a hectopascal on the wire, so a generated threshold is
            // quantised to what the codec can carry and the round-trip is exact.
            storm_alert: storm_alert.map(|t| t.map(|tenths| f32::from(tenths) / 10.0)),
        },
    )
}

fn a_record() -> impl Strategy<Value = (WatchSettings, Vec<u8>)> {
    a_settings().prop_map(|s| (s, encode(&s).to_vec()))
}

#[test]
fn a_record_round_trips_the_persistable_half_and_fails_closed() {
    check(256, a_record(), |(settings, record)| {
        prop_assert_eq!(record.len(), RACE_CONFIG_RECORD_LEN);
        prop_assert_eq!(decode(&record), Some(persistable(&settings)));
        for cut in 0..record.len() {
            prop_assert!(decode(&record[..cut]).is_none(), "prefix {cut}");
        }
        let mut bad_magic = record.clone();
        bad_magic[0] ^= 0xFF;
        prop_assert_ne!(&bad_magic[0..4], &RCF1_MAGIC);
        prop_assert!(decode(&bad_magic).is_none());

        let mut bad_version = record.clone();
        bad_version[4] = RCF1_VERSION.wrapping_add(1);
        prop_assert!(decode(&bad_version).is_none());
        Ok(())
    });
}

#[test]
fn a_stored_record_never_carries_a_field_that_persists_elsewhere() {
    // The filter, asserted where it matters: whatever the phone pushed, what
    // comes back off the page can never re-apply the run-view page mask the
    // activity profile owns, the hide-empty choice or auto-lap rung `CFG1`
    // owns, or the medical ID `ICE1` owns.
    check(256, a_record(), |(_, record)| {
        let Some(out) = decode(&record) else {
            prop_assert!(false, "a record this codec wrote must decode");
            unreachable!()
        };
        prop_assert_eq!(out.pages, None);
        prop_assert_eq!(out.hide_empty_pages, None);
        prop_assert_eq!(out.ice, None);
        prop_assert_eq!(out.auto_lap, None);
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_config() {
    check(
        1024,
        (a_record(), any::<Index>(), 1u8..=255),
        |((settings, record), at, delta)| {
            let at = at.index(record.len());
            let decoded = decode(&corrupted(&record, at, delta));
            prop_assert!(
                decoded.is_none() || decoded == Some(persistable(&settings)),
                "byte {at}"
            );
            Ok(())
        },
    );
}

#[test]
fn a_torn_write_over_an_erased_page_never_decodes() {
    // The brown-out case the whole record exists to survive honestly: some
    // prefix of the bytes landed on a freshly-erased page and the rest is still
    // 0xFF. Every such page must read as "no saved config" — never as a
    // configuration the runner did not set.
    check(
        256,
        (a_record(), any::<Index>()),
        |((_, record), landed)| {
            let landed = landed.index(record.len());
            let mut torn = [0xFFu8; RACE_CONFIG_RECORD_LEN];
            torn[..landed].copy_from_slice(&record[..landed]);
            prop_assert!(decode(&torn).is_none(), "{landed} bytes landed");
            Ok(())
        },
    );
}

#[test]
fn decode_never_panics_on_arbitrary_bytes() {
    check(
        1024,
        prop::collection::vec(any::<u8>(), 0..=(RACE_CONFIG_RECORD_LEN + 8)),
        |bytes| {
            let _ = decode(&bytes);
            Ok(())
        },
    );
}

#[test]
fn a_push_overrides_only_the_fields_it_carries() {
    // A `SET1` frame is a delta, and the stored record has to be too: a phone
    // that pushes one new max HR must not erase the pacer goal it did not
    // mention.
    check(512, (a_settings(), a_settings()), |(stored, push)| {
        let base = persistable(&stored);
        let next = merged(&base, &push);
        let want = persistable(&push);
        prop_assert_eq!(next.max_hr, want.max_hr.or(base.max_hr));
        prop_assert_eq!(next.pacer, want.pacer.or(base.pacer));
        prop_assert_eq!(next.zone_ceiling, want.zone_ceiling.or(base.zone_ceiling));
        prop_assert_eq!(next.sea_level_pa, want.sea_level_pa.or(base.sea_level_pa));
        prop_assert_eq!(next.fuel, want.fuel.or(base.fuel));
        prop_assert_eq!(next.race_phases, want.race_phases.or(base.race_phases));
        prop_assert_eq!(next.storm_alert, want.storm_alert.or(base.storm_alert));
        // Merging is what the persist path stores, so it must never smuggle
        // in a field the filter drops either.
        prop_assert_eq!(next.pages, None);
        prop_assert_eq!(next.hide_empty_pages, None);
        prop_assert_eq!(next.ice, None);
        prop_assert_eq!(next.auto_lap, None);
        Ok(())
    });
}

#[test]
fn re_pushing_a_frame_the_page_already_holds_costs_no_erase() {
    // The wear gate. One erase per genuine change is within endurance by orders
    // of magnitude; one per repeated push of an unchanged frame is not, and a
    // phone that re-sends its whole settings screen on every reconnect is the
    // normal case, not the pathological one.
    check(512, (a_settings(), a_settings()), |(first, second)| {
        let stored = merged(&WatchSettings::default(), &first);
        let again = merged(&stored, &first);
        prop_assert!(!record_differs(&stored, &again), "an identical re-push");

        // And a push carrying nothing the record holds is likewise free.
        let only_elsewhere = WatchSettings {
            pages: second.pages,
            hide_empty_pages: second.hide_empty_pages,
            ice: second.ice,
            auto_lap: second.auto_lap,
            ..WatchSettings::default()
        };
        prop_assert!(!record_differs(&stored, &merged(&stored, &only_elsewhere)));
        Ok(())
    });
}
