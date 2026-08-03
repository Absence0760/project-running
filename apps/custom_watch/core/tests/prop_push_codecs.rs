//! Property tests for the four phone→watch / flash push codecs that had none:
//! `WKT1` (workout steps), `WPT1` (marked waypoints), `ICE1` (the medical ID
//! record) and `SCR1` (runner-composed screens).
//!
//! All four are fed from bytes the firmware does not control — a BLE write, or
//! a flash page that may be erased, half-written or stale — so the shared
//! contract is the same one `prop_course_store` pins for the course frame:
//! a whole frame round-trips exactly, and anything else fails closed. Each
//! codec seals its body with a CRC32 trailer, so the corruption property is
//! the sharp one: no single flipped byte may ever produce a frame that decodes
//! to something OTHER than what was encoded. Half a waypoint list, a medical ID
//! with one wrong digit of a next-of-kin number, or a screen naming a metric
//! the runner did not choose are all worse than no record at all.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::alerts::{PACE_BAND_MAX_S_PER_KM, PACE_BAND_MIN_S_PER_KM};
use watch_core::ble_sync::{PushKind, PushOutcome, PUSH_STATUS_LEN};
use watch_core::face::Metric;
use watch_core::ice::{
    decode_record, IceCard, ICE1_MAGIC, ICE1_RECORD_LEN, ICE1_VERSION, ICE_BLOOD_LEN, ICE_FIELD_LEN,
};
use watch_core::pacer::GOAL_DISTANCE_MAX_M;
use watch_core::screens::{
    Layout, Screen, Screens, MAX_SCR1_LEN, MAX_SCREENS, SCR1_MAGIC, SCR1_VERSION,
};
use watch_core::waypoints::{Waypoints, MAX_WAYPOINTS, MAX_WPT1_LEN, WPT1_MAGIC, WPT1_VERSION};
use watch_core::workout::{WorkoutStep, WorkoutStepKind, MAX_WORKOUT_STEPS};
use watch_core::workout_store::{
    decode as workout_decode, encode as workout_encode, MAX_WORKOUT_FRAME_LEN,
    WORKOUT_FORMAT_VERSION, WORKOUT_MAGIC,
};

/// Every metric byte this firmware knows, so a generated screen only ever names
/// one the decoder will accept — the same enumeration `face.rs` uses.
fn all_metrics() -> Vec<Metric> {
    (1..=u8::MAX).filter_map(Metric::from_byte).collect()
}

/// A byte string that is guaranteed to differ from `frame` in exactly one
/// position, so a corruption property can never accidentally test the identity.
fn corrupted(frame: &[u8], at: usize, delta: u8) -> Vec<u8> {
    let mut b = frame.to_vec();
    b[at] ^= delta;
    b
}

fn a_printable_field(max: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(0x20u8..=0x7E, 0..=max)
        .prop_map(|b| String::from_utf8(b).expect("printable ASCII is UTF-8"))
}

fn a_step() -> impl Strategy<Value = WorkoutStep> {
    (
        prop::sample::select(vec![
            WorkoutStepKind::Warmup,
            WorkoutStepKind::Rep,
            WorkoutStepKind::Recovery,
            WorkoutStepKind::Walk,
            WorkoutStepKind::Steady,
            WorkoutStepKind::Cooldown,
        ]),
        0u8..=20,
        0u8..=20,
        // Exactly one end axis is set: `true` picks the distance axis.
        any::<bool>(),
        1u32..=GOAL_DISTANCE_MAX_M,
        1u16..=u16::MAX,
        PACE_BAND_MIN_S_PER_KM as u16..=PACE_BAND_MAX_S_PER_KM as u16,
        0u16..=255,
    )
        .prop_map(
            |(kind, rep_index, rep_total, by_distance, dist, dur, pace, tol)| WorkoutStep {
                kind,
                rep_index,
                rep_total,
                target_distance_m: if by_distance { dist } else { 0 },
                target_duration_s: if by_distance { 0 } else { dur },
                target_pace_s_per_km: pace,
                tolerance_s_per_km: tol,
            },
        )
}

fn a_workout_frame() -> impl Strategy<Value = (Vec<WorkoutStep>, Vec<u8>)> {
    prop::collection::vec(a_step(), 1..=MAX_WORKOUT_STEPS).prop_map(|steps| {
        let mut buf = [0u8; MAX_WORKOUT_FRAME_LEN];
        let len = workout_encode(&steps, &mut buf).expect("a plausible step list encodes");
        (steps, buf[..len].to_vec())
    })
}

/// Points on the 1e-7-degree grid the codec quantises to, so encode → decode is
/// exact and a mismatch is a codec bug rather than a rounding artefact.
fn a_waypoint_store() -> impl Strategy<Value = (Waypoints, Vec<u8>)> {
    prop::collection::vec(
        (
            -900_000_000i32..=900_000_000,
            -1_800_000_000i32..=1_800_000_000,
            any::<u32>(),
        ),
        0..=MAX_WAYPOINTS,
    )
    .prop_map(|marks| {
        let mut w = Waypoints::new();
        for (lat, lon, uptime) in marks {
            assert!(w.mark(lat as f64 / 1e7, lon as f64 / 1e7, uptime));
        }
        let mut buf = [0u8; MAX_WPT1_LEN];
        let len = w.encode(&mut buf).expect("a legal store encodes");
        (w, buf[..len].to_vec())
    })
}

fn an_ice_record() -> impl Strategy<Value = (IceCard, Vec<u8>)> {
    (
        a_printable_field(ICE_FIELD_LEN),
        a_printable_field(ICE_BLOOD_LEN),
        a_printable_field(ICE_FIELD_LEN),
        a_printable_field(ICE_FIELD_LEN),
        a_printable_field(ICE_FIELD_LEN),
    )
        .prop_map(|(holder, blood, conditions, contact, phone)| {
            let card = IceCard::new(&holder, &blood, &conditions, &contact, &phone)
                .expect("printable fields within their caps pack");
            let record = card.encode_record().to_vec();
            (card, record)
        })
}

fn a_screen_set() -> impl Strategy<Value = (Screens, Vec<u8>)> {
    let metrics = all_metrics();
    prop::collection::vec(
        (
            prop::sample::select(vec![Layout::Single, Layout::Duo, Layout::Trio]),
            prop::collection::vec(prop::sample::select(metrics), 3),
        ),
        0..=MAX_SCREENS,
    )
    .prop_map(|specs| {
        let screens: Vec<Screen> = specs
            .into_iter()
            .map(|(layout, picks)| {
                Screen::new(layout, &picks[..layout.slots()])
                    .expect("arity matches by construction")
            })
            .collect();
        let set = Screens::from_slice(&screens).expect("within MAX_SCREENS");
        let mut buf = [0u8; MAX_SCR1_LEN];
        let len = set.encode(&mut buf).expect("a legal set encodes");
        (set, buf[..len].to_vec())
    })
}

#[test]
fn a_workout_frame_round_trips_and_fails_closed() {
    check(256, a_workout_frame(), |(steps, frame)| {
        prop_assert_eq!(
            workout_decode(&frame).map(|v| v.to_vec()),
            Some(steps.clone())
        );
        for cut in 0..frame.len() {
            prop_assert!(workout_decode(&frame[..cut]).is_none(), "prefix {cut}");
        }
        let mut bad_magic = frame.clone();
        bad_magic[0] ^= 0xFF;
        prop_assert_ne!(&bad_magic[0..4], &WORKOUT_MAGIC);
        prop_assert!(workout_decode(&bad_magic).is_none());

        let mut bad_version = frame.clone();
        bad_version[4] = WORKOUT_FORMAT_VERSION.wrapping_add(1);
        prop_assert!(workout_decode(&bad_version).is_none());
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_workout() {
    check(
        512,
        (a_workout_frame(), any::<Index>(), 1u8..=255),
        |((steps, frame), at, delta)| {
            let at = at.index(frame.len());
            let decoded = workout_decode(&corrupted(&frame, at, delta)).map(|v| v.to_vec());
            prop_assert!(decoded.is_none() || decoded == Some(steps), "byte {at}");
            Ok(())
        },
    );
}

#[test]
fn workout_decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=MAX_WORKOUT_FRAME_LEN),
        |bytes| {
            let _ = workout_decode(&bytes);
            Ok(())
        },
    );
}

#[test]
fn a_waypoint_record_round_trips_and_fails_closed() {
    check(256, a_waypoint_store(), |(store, record)| {
        let decoded = Waypoints::decode(&record);
        prop_assert_eq!(decoded.as_ref(), Some(&store));
        for cut in 0..record.len() {
            prop_assert!(Waypoints::decode(&record[..cut]).is_none(), "prefix {cut}");
        }
        let mut bad_magic = record.clone();
        bad_magic[0] ^= 0xFF;
        prop_assert_ne!(&bad_magic[0..4], &WPT1_MAGIC);
        prop_assert!(Waypoints::decode(&bad_magic).is_none());

        let mut bad_version = record.clone();
        bad_version[4] = WPT1_VERSION.wrapping_add(1);
        prop_assert!(Waypoints::decode(&bad_version).is_none());
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_waypoint_store() {
    check(
        512,
        (a_waypoint_store(), any::<Index>(), 1u8..=255),
        |((store, record), at, delta)| {
            let at = at.index(record.len());
            let decoded = Waypoints::decode(&corrupted(&record, at, delta));
            prop_assert!(decoded.is_none() || decoded == Some(store), "byte {at}");
            Ok(())
        },
    );
}

#[test]
fn waypoint_decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=MAX_WPT1_LEN),
        |bytes| {
            let _ = Waypoints::decode(&bytes);
            Ok(())
        },
    );
}

#[test]
fn an_ice_record_round_trips_and_fails_closed() {
    check(256, an_ice_record(), |(card, record)| {
        prop_assert_eq!(decode_record(&record), Some(card));
        for cut in 0..record.len() {
            prop_assert!(decode_record(&record[..cut]).is_none(), "prefix {cut}");
        }
        let mut bad_magic = record.clone();
        bad_magic[0] ^= 0xFF;
        prop_assert_ne!(&bad_magic[0..4], &ICE1_MAGIC);
        prop_assert!(decode_record(&bad_magic).is_none());

        let mut bad_version = record.clone();
        bad_version[4] = ICE1_VERSION.wrapping_add(1);
        prop_assert!(decode_record(&bad_version).is_none());
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_ice_card() {
    check(
        512,
        (an_ice_record(), any::<Index>(), 1u8..=255),
        |((card, record), at, delta)| {
            let at = at.index(record.len());
            let decoded = decode_record(&corrupted(&record, at, delta));
            prop_assert!(decoded.is_none() || decoded == Some(card), "byte {at}");
            Ok(())
        },
    );
}

#[test]
fn ice_decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=ICE1_RECORD_LEN),
        |bytes| {
            let _ = decode_record(&bytes);
            Ok(())
        },
    );
}

#[test]
fn a_screen_set_round_trips_and_fails_closed() {
    check(256, a_screen_set(), |(set, record)| {
        let decoded = Screens::decode(&record);
        prop_assert_eq!(decoded.as_ref(), Some(&set));
        for cut in 0..record.len() {
            prop_assert!(Screens::decode(&record[..cut]).is_none(), "prefix {cut}");
        }
        let mut bad_magic = record.clone();
        bad_magic[0] ^= 0xFF;
        prop_assert_ne!(&bad_magic[0..4], &SCR1_MAGIC);
        prop_assert!(Screens::decode(&bad_magic).is_none());

        let mut bad_version = record.clone();
        bad_version[4] = SCR1_VERSION.wrapping_add(1);
        prop_assert!(Screens::decode(&bad_version).is_none());
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_screen_set() {
    check(
        512,
        (a_screen_set(), any::<Index>(), 1u8..=255),
        |((set, record), at, delta)| {
            let at = at.index(record.len());
            let decoded = Screens::decode(&corrupted(&record, at, delta));
            prop_assert!(decoded.is_none() || decoded == Some(set), "byte {at}");
            Ok(())
        },
    );
}

#[test]
fn screens_decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=MAX_SCR1_LEN),
        |bytes| {
            let _ = Screens::decode(&bytes);
            Ok(())
        },
    );
}

/// The `PSH1` push verdict — the one record in this family the WATCH writes and
/// the PHONE decodes, so its fail-closed direction is the mirror of the others:
/// what must never happen is arbitrary bytes reading as a verdict, because the
/// phone reports "sent" off exactly this.
fn a_push_outcome() -> impl Strategy<Value = PushOutcome> {
    (
        any::<u8>(),
        prop::sample::select(vec![
            PushKind::Settings,
            PushKind::Course,
            PushKind::Workout,
            PushKind::Screens,
            PushKind::Roadbook,
        ]),
        any::<bool>(),
    )
        .prop_map(|(seq, kind, accepted)| PushOutcome {
            seq,
            kind,
            accepted,
        })
}

#[test]
fn a_push_outcome_round_trips_and_fails_closed() {
    check(
        256,
        (a_push_outcome(), any::<Index>(), 1u8..=255),
        |(outcome, at, delta)| {
            let bytes = outcome.encode();
            prop_assert_eq!(PushOutcome::decode(&bytes), Some(outcome));
            // Unlike its CRC-sealed siblings this record has no checksum — it
            // rides one encrypted ATT read, not a chunked write — so the property
            // is the weaker but sufficient one: a corrupted byte may fail to
            // decode, but if it decodes it decodes to what the bytes now say, and
            // a corrupted MAGIC never decodes at all.
            let corrupt = corrupted(&bytes, at.index(bytes.len()), delta);
            if at.index(bytes.len()) < 4 {
                prop_assert_eq!(PushOutcome::decode(&corrupt), None, "a foreign magic");
            }
            Ok(())
        },
    );
}

#[test]
fn push_outcome_decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=PUSH_STATUS_LEN + 4),
        |bytes| {
            let _ = PushOutcome::decode(&bytes);
            Ok(())
        },
    );
}
