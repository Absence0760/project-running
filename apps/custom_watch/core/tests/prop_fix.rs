//! Property tests for the GNSS fix accumulator. Its input is whatever the
//! MAX-M10S's UART produced, reduced by the NMEA parser — so a sentence stream
//! can be partial, out of order, or a receiver that just lost its fix. The
//! invariant that matters on the wrist is that a position never outlives the
//! fix it came from: a stale lat/lon leaking into the next merge would put the
//! runner somewhere they were minutes ago.

mod support;

use proptest::prelude::*;
use support::check;
use ublox_nmea::{GgaData, GstData, RmcData, Sentence, ZdaData};
use watch_core::fix::FixAccumulator;

fn a_coord() -> impl Strategy<Value = Option<f64>> {
    prop::option::of(prop_oneof![
        -90.0f64..90.0,
        Just(f64::NAN),
        Just(f64::INFINITY),
    ])
}

fn an_rmc() -> impl Strategy<Value = RmcData> {
    (
        prop::option::of(0u32..86_400),
        any::<bool>(),
        a_coord(),
        a_coord(),
        prop::option::of(-1e6f32..1e6),
        prop::option::of(-1e6f32..1e6),
        prop::option::of((0u8..=40, 0u8..=15, 2000u16..2100)),
    )
        .prop_map(
            |(time, valid, lat_deg, lon_deg, speed_mps, course_deg, date_dmy)| RmcData {
                time,
                valid,
                lat_deg,
                lon_deg,
                speed_mps,
                course_deg,
                date_dmy,
            },
        )
}

fn a_gga() -> impl Strategy<Value = GgaData> {
    (
        prop::option::of(0u32..86_400),
        a_coord(),
        a_coord(),
        any::<u8>(),
        any::<u8>(),
        prop::option::of(-1e6f32..1e6),
    )
        .prop_map(|(time, lat_deg, lon_deg, quality, sats, alt_m)| GgaData {
            time,
            lat_deg,
            lon_deg,
            quality,
            sats,
            alt_m,
        })
}

fn a_sentence() -> impl Strategy<Value = Sentence> {
    prop_oneof![
        4 => an_rmc().prop_map(Sentence::Rmc),
        3 => a_gga().prop_map(Sentence::Gga),
        1 => any::<u8>().prop_map(|sats_in_view| Sentence::Gsv { sats_in_view }),
        1 => Just(Sentence::Zda(ZdaData::default())),
        1 => Just(Sentence::Gst(GstData::default())),
        1 => Just(Sentence::Other),
    ]
}

#[test]
fn a_fix_never_outlives_the_sentence_it_came_from() {
    check(
        512,
        prop::collection::vec((a_sentence(), any::<u32>()), 0..=24),
        |stream| {
            let mut acc = FixAccumulator::new();
            // The reference state a fix is only ever allowed to be built from.
            let mut armed_rmc: Option<RmcData> = None;
            let mut armed_gga: Option<GgaData> = None;

            for (sentence, uptime_s) in &stream {
                match sentence {
                    Sentence::Rmc(rmc) if rmc.valid => armed_rmc = Some(*rmc),
                    Sentence::Rmc(_) => {
                        armed_rmc = None;
                        armed_gga = None;
                    }
                    Sentence::Gga(gga) if gga.quality > 0 => armed_gga = Some(*gga),
                    _ => {}
                }

                let Some(fix) = acc.apply(sentence, *uptime_s) else {
                    continue;
                };

                prop_assert_eq!(
                    fix.uptime_s,
                    *uptime_s,
                    "a fix must be stamped with the uptime it was assembled at"
                );
                let rmc = armed_rmc.expect("a fix requires a currently-valid RMC");
                // Compared by bit pattern, not by value: a generated NaN
                // coordinate is not equal to itself, and "the fix carried the
                // armed RMC's exact bytes through" is the claim.
                prop_assert_eq!(
                    Some(f64::to_bits(fix.lat_deg)),
                    rmc.lat_deg.map(f64::to_bits),
                    "the fix position is not the armed RMC's"
                );
                prop_assert_eq!(
                    Some(f64::to_bits(fix.lon_deg)),
                    rmc.lon_deg.map(f64::to_bits)
                );
                prop_assert_eq!(fix.time_of_day, rmc.time);
                prop_assert_eq!(fix.course_deg, rmc.course_deg);

                match armed_gga {
                    None => {
                        // Nothing has enriched the accumulator since the last
                        // void RMC, so the GGA-sourced fields must read as
                        // absent rather than carry a previous fix's numbers.
                        prop_assert_eq!(fix.sats, 0, "satellite count leaked from a cleared GGA");
                        prop_assert_eq!(fix.alt_m, None, "altitude leaked from a cleared GGA");
                    }
                    Some(gga) => {
                        prop_assert_eq!(fix.sats, gga.sats);
                        prop_assert_eq!(fix.alt_m, gga.alt_m);
                    }
                }
            }
            Ok(())
        },
    );
}

#[test]
fn a_void_rmc_always_clears_the_accumulated_position() {
    // The receiver dropping to a void RMC is the "lost the fix" signal. No
    // amount of GGA enrichment afterwards may resurrect the last position.
    check(
        512,
        (
            an_rmc().prop_map(|mut r| {
                r.valid = true;
                r
            }),
            a_gga().prop_map(|mut g| {
                g.quality = g.quality.max(1);
                g
            }),
            prop::collection::vec(a_gga(), 0..=6),
            any::<u32>(),
        ),
        |(valid_rmc, good_gga, later_ggas, uptime_s)| {
            let mut acc = FixAccumulator::new();
            acc.apply(&Sentence::Gga(good_gga), uptime_s);
            acc.apply(&Sentence::Rmc(valid_rmc), uptime_s);

            let mut void = valid_rmc;
            void.valid = false;
            prop_assert_eq!(acc.apply(&Sentence::Rmc(void), uptime_s), None);

            for gga in &later_ggas {
                prop_assert_eq!(
                    acc.apply(&Sentence::Gga(*gga), uptime_s),
                    None,
                    "a GGA resurrected a position after the fix was lost"
                );
            }
            Ok(())
        },
    );
}
