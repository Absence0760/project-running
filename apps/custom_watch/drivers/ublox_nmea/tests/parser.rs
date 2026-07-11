//! Host-side parser tests. Run via `bin/watch-test.sh` from the repo root,
//! or `cargo test --target <HOST_TRIPLE> -p ublox_nmea` from anywhere.

use ublox_nmea::{Parser, Sentence};

fn feed_all(parser: &mut Parser, text: &str) -> Vec<Sentence> {
    text.bytes().filter_map(|b| parser.feed(b)).collect()
}

fn parse_one(text: &str) -> Option<Sentence> {
    let mut p = Parser::new();
    feed_all(&mut p, text).into_iter().next()
}

// First fixture epoch of apps/custom_watch/sim/nmea/bench_jog.nmea.
const GGA: &str = "$GPGGA,073000.00,4000.9000,N,10516.2300,W,1,08,1.02,1624.0,M,-21.3,M,,*52\r\n";
const RMC: &str = "$GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A*4B\r\n";

#[test]
fn parses_gga() {
    let Some(Sentence::Gga(gga)) = parse_one(GGA) else {
        panic!("expected GGA");
    };
    assert_eq!(gga.time, Some(7 * 3600 + 30 * 60));
    assert_eq!(gga.quality, 1);
    assert_eq!(gga.sats, 8);
    assert!((gga.lat_deg.unwrap() - 40.015).abs() < 1e-9);
    assert!((gga.lon_deg.unwrap() - -105.2705).abs() < 1e-9);
    assert!((gga.alt_m.unwrap() - 1624.0).abs() < 1e-3);
}

#[test]
fn parses_rmc() {
    let Some(Sentence::Rmc(rmc)) = parse_one(RMC) else {
        panic!("expected RMC");
    };
    assert!(rmc.valid);
    assert_eq!(rmc.time, Some(7 * 3600 + 30 * 60));
    assert!((rmc.lat_deg.unwrap() - 40.015).abs() < 1e-9);
    assert!((rmc.lon_deg.unwrap() - -105.2705).abs() < 1e-9);
    assert!((rmc.speed_mps.unwrap() - 5.83 * 0.514_444).abs() < 1e-4);
    assert!((rmc.course_deg.unwrap() - 90.0).abs() < 1e-4);
}

#[test]
fn gn_talker_parses_like_gp() {
    // MAX-M10S multi-GNSS mode emits GN talkers; checksum recomputed for GN.
    let body = "GNRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A";
    let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
    let sentence = format!("${}*{:02X}\r\n", body, cksum);
    assert!(matches!(parse_one(&sentence), Some(Sentence::Rmc(_))));
}

#[test]
fn bad_checksum_dropped() {
    let corrupt = GGA.replace("*52", "*53");
    assert_eq!(parse_one(&corrupt), None);
}

#[test]
fn corrupted_payload_fails_checksum() {
    let corrupt = GGA.replace("4000.9000", "4000.9001");
    assert_eq!(parse_one(&corrupt), None);
}

#[test]
fn parses_gsv_sats_in_view() {
    let gsv = "$GPGSV,2,1,08,05,55,120,42,07,34,210,38,13,21,300,35,15,60,045,44*7D\r\n";
    assert_eq!(parse_one(gsv), Some(Sentence::Gsv { sats_in_view: 8 }));
}

#[test]
fn gsv_bad_checksum_dropped() {
    let gsv = "$GPGSV,2,1,08,05,55,120,42,07,34,210,38,13,21,300,35,15,60,045,44*7D\r\n";
    let corrupt = gsv.replace("*7D", "*7E");
    assert_eq!(parse_one(&corrupt), None);
}

#[test]
fn gsv_empty_sats_field_dropped() {
    // Malformed group header (empty sats-in-view field): drop, don't report 0.
    let body = "GPGSV,1,1,,05,55,120,42";
    let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
    let sentence = format!("${}*{:02X}\r\n", body, cksum);
    assert_eq!(parse_one(&sentence), None);
}

#[test]
fn gl_talker_gsv_parses_like_gp() {
    // GLONASS constellation emits GL talkers; checksum recomputed for GL.
    let body = "GLGSV,1,1,04,65,55,120,42,66,34,210,38,72,21,300,35,80,60,045,44";
    let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
    let sentence = format!("${}*{:02X}\r\n", body, cksum);
    assert_eq!(
        parse_one(&sentence),
        Some(Sentence::Gsv { sats_in_view: 4 })
    );
}

#[test]
fn gsv_multi_sentence_group_reports_same_total() {
    // A 2-message group: each sentence carries the same 08 total.
    let mut p = Parser::new();
    let group = "$GPGSV,2,1,08,05,55,120,42,07,34,210,38,13,21,300,35,15,60,045,44*7D\r\n\
        $GPGSV,2,2,08,18,12,090,30,20,48,270,41,24,08,180,28,30,29,330,37*7E\r\n";
    let got = feed_all(&mut p, group);
    assert_eq!(got.len(), 2);
    assert!(got.iter().all(|s| *s == Sentence::Gsv { sats_in_view: 8 }));
}

#[test]
fn void_rmc_reports_invalid_without_position() {
    // Cold start: status V, empty position/speed/course fields.
    let body = "GPRMC,073000.00,V,,,,,,,080726,,,N";
    let cksum = body.bytes().fold(0u8, |c, b| c ^ b);
    let sentence = format!("${}*{:02X}\r\n", body, cksum);
    let Some(Sentence::Rmc(rmc)) = parse_one(&sentence) else {
        panic!("expected RMC");
    };
    assert!(!rmc.valid);
    assert_eq!(rmc.lat_deg, None);
    assert_eq!(rmc.speed_mps, None);
}

#[test]
fn resyncs_mid_stream_and_across_noise() {
    // Joining mid-sentence: garbage before the first '$' is discarded.
    let mut p = Parser::new();
    let stream = format!("16.2300,W,1,08,*AA\r\nnoise{}\x00{}", GGA, RMC);
    let got = stream.bytes().filter_map(|b| p.feed(b)).collect::<Vec<_>>();
    assert_eq!(got.len(), 2);
    assert!(matches!(got[0], Sentence::Gga(_)));
    assert!(matches!(got[1], Sentence::Rmc(_)));
}

#[test]
fn oversized_sentence_dropped_then_recovers() {
    let mut p = Parser::new();
    let long = format!("$GPXXX,{}\r\n{}", "A".repeat(300), RMC);
    let got = feed_all(&mut p, &long);
    assert_eq!(got.len(), 1);
    assert!(matches!(got[0], Sentence::Rmc(_)));
}

#[test]
fn whole_fixture_file_parses() {
    let fixture = include_str!("../../../sim/nmea/bench_jog.nmea");
    let mut p = Parser::new();
    let mut rmc = 0;
    let mut gga = 0;
    let mut gsv = 0;
    let mut other = 0;
    for s in fixture.bytes().filter_map(|b| p.feed(b)) {
        match s {
            Sentence::Rmc(r) => {
                assert!(r.valid);
                rmc += 1;
            }
            Sentence::Gga(g) => {
                assert_eq!(g.quality, 1);
                assert_eq!(g.sats, 8);
                gga += 1;
            }
            Sentence::Gsv { sats_in_view } => {
                assert_eq!(sats_in_view, 8);
                gsv += 1;
            }
            Sentence::Other => other += 1,
        }
    }
    assert_eq!(rmc, 120);
    assert_eq!(gga, 120);
    assert_eq!(gsv, 2); // the two GSV lines
    assert_eq!(other, 0);
}
