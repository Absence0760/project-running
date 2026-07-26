//! Property tests for the NMEA parser and the UBX encoder. The parser's input
//! is a raw GNSS UART stream — partial lines, line noise, a receiver mid-boot
//! emitting garbage — so every byte here is untrusted. Run via
//! `bin/watch-test.sh`, or `cargo test --target <HOST_TRIPLE> -p ublox_nmea`.

use proptest::prelude::*;
use proptest::sample::Index;
use proptest::strategy::Strategy;
use proptest::test_runner::{Config, RngAlgorithm, TestCaseError, TestError, TestRng, TestRunner};
use ublox_nmea::{ubx, Parser, Sentence};

/// Run `test` over `cases` generated inputs from a fixed RNG rather than from
/// entropy, so a CI failure reproduces locally instead of vanishing on the next
/// attempt. Failure persistence is off for the same reason: the
/// `proptest-regressions/` file exists to replay a random seed, and it would
/// otherwise have the harness write into the source tree.
fn check<S: Strategy>(
    cases: u32,
    strategy: S,
    test: impl Fn(S::Value) -> Result<(), TestCaseError>,
) {
    let mut runner = TestRunner::new_with_rng(
        Config {
            cases,
            failure_persistence: None,
            ..Config::default()
        },
        TestRng::deterministic_rng(RngAlgorithm::ChaCha),
    );
    match runner.run(&strategy, test) {
        Ok(()) => {}
        Err(TestError::Fail(reason, input)) => {
            panic!("property failed: {reason}\nminimal failing input: {input:?}")
        }
        Err(e) => panic!("{e}"),
    }
}

/// NMEA caps a sentence at 82 chars; the parser's internal buffer is 100, so
/// this spans both the in-spec and the over-long cases.
const OVERSIZE: usize = 101;

fn feed_all(text: &[u8]) -> Vec<Sentence> {
    let mut p = Parser::new();
    text.iter().filter_map(|b| p.feed(*b)).collect()
}

fn checksum(payload: &[u8]) -> u8 {
    payload.iter().fold(0u8, |c, &b| c ^ b)
}

/// A sentence body with a correct checksum, ready to frame.
fn framed(payload: &[u8]) -> Vec<u8> {
    let mut out = b"$".to_vec();
    out.extend_from_slice(payload);
    out.extend_from_slice(format!("*{:02X}\r\n", checksum(payload)).as_bytes());
    out
}

/// Bytes that can appear inside a sentence payload: anything but the framing
/// characters, so the generated body is exactly as long as it looks.
fn a_payload(max: usize) -> impl Strategy<Value = Vec<u8>> {
    prop::collection::vec(
        any::<u8>().prop_filter("not a framing byte", |b| {
            *b != b'$' && *b != b'*' && *b != b'\r' && *b != b'\n'
        }),
        0..=max,
    )
}

/// A well-formed RMC over the legal field domain, plus the values to check the
/// parse against.
#[derive(Clone, Debug)]
struct RmcFixture {
    text: Vec<u8>,
    time_of_day: u32,
    lat_deg: f64,
    lon_deg: f64,
    speed_mps: f32,
    course_deg: f32,
}

fn an_rmc() -> impl Strategy<Value = RmcFixture> {
    (
        0u32..24,
        0u32..60,
        0u32..60,
        0u32..90,
        0f64..60.0,
        prop::bool::ANY,
        0u32..180,
        0f64..60.0,
        prop::bool::ANY,
        0f64..500.0,
        0f64..360.0,
    )
        .prop_map(
            |(h, m, s, lat_d, lat_m, north, lon_d, lon_m, east, knots, course)| {
                let ns = if north { 'N' } else { 'S' };
                let ew = if east { 'E' } else { 'W' };
                let body = format!(
                    "GPRMC,{h:02}{m:02}{s:02}.00,A,{lat_d:02}{lat_m:07.4},{ns},{lon_d:03}{lon_m:07.4},{ew},{knots:.2},{course:.1},080726,,,A"
                );
                // Re-read the formatted fields so the expectation is what the
                // wire actually carries, not the pre-rounding value.
                let lat_m_wire: f64 = format!("{lat_m:07.4}").parse().expect("lat minutes");
                let lon_m_wire: f64 = format!("{lon_m:07.4}").parse().expect("lon minutes");
                let knots_wire: f64 = format!("{knots:.2}").parse().expect("knots");
                let course_wire: f64 = format!("{course:.1}").parse().expect("course");
                let lat = lat_d as f64 + lat_m_wire / 60.0;
                let lon = lon_d as f64 + lon_m_wire / 60.0;
                RmcFixture {
                    text: framed(body.as_bytes()),
                    time_of_day: h * 3600 + m * 60 + s,
                    lat_deg: if north { lat } else { -lat },
                    lon_deg: if east { lon } else { -lon },
                    speed_mps: (knots_wire * 0.514_444) as f32,
                    course_deg: course_wire as f32,
                }
            },
        )
}

#[test]
fn the_parser_never_panics_on_an_arbitrary_byte_stream() {
    check(512, prop::collection::vec(any::<u8>(), 0..=400), |bytes| {
        let _ = feed_all(&bytes);
        Ok(())
    });
}

#[test]
fn a_correct_checksum_never_panics_and_a_wrong_one_never_parses() {
    check(1024, (a_payload(80), 1u8..=u8::MAX), |(payload, delta)| {
        let _ = feed_all(&framed(&payload));

        let wrong = checksum(&payload) ^ delta;
        let mut text = b"$".to_vec();
        text.extend_from_slice(&payload);
        text.extend_from_slice(format!("*{wrong:02X}\r\n").as_bytes());
        prop_assert!(
            feed_all(&text).is_empty(),
            "a sentence with a wrong checksum parsed"
        );
        Ok(())
    });
}

#[test]
fn a_sentence_with_no_checksum_delimiter_never_parses() {
    check(512, a_payload(80), |payload| {
        let mut text = b"$".to_vec();
        text.extend_from_slice(&payload);
        text.extend_from_slice(b"\r\n");
        prop_assert!(
            feed_all(&text).is_empty(),
            "a sentence with no '*' checksum parsed"
        );
        Ok(())
    });
}

#[test]
fn an_rmc_round_trips_through_the_wire() {
    check(512, an_rmc(), |f| {
        let sentences = feed_all(&f.text);
        prop_assert_eq!(
            sentences.len(),
            1,
            "text: {:?}",
            String::from_utf8_lossy(&f.text)
        );
        let Sentence::Rmc(rmc) = sentences[0] else {
            return Err(TestCaseError::fail("expected an RMC"));
        };
        prop_assert!(rmc.valid);
        prop_assert_eq!(rmc.time, Some(f.time_of_day));
        prop_assert!(
            (rmc.lat_deg.expect("lat") - f.lat_deg).abs() < 1e-9,
            "lat {:?} vs {}",
            rmc.lat_deg,
            f.lat_deg
        );
        prop_assert!(
            (rmc.lon_deg.expect("lon") - f.lon_deg).abs() < 1e-9,
            "lon {:?} vs {}",
            rmc.lon_deg,
            f.lon_deg
        );
        prop_assert!((rmc.speed_mps.expect("speed") - f.speed_mps).abs() < 1e-3);
        prop_assert!((rmc.course_deg.expect("course") - f.course_deg).abs() < 1e-3);
        Ok(())
    });
}

#[test]
fn every_proper_prefix_of_a_sentence_is_dropped() {
    // A UART read that ends mid-sentence must yield nothing, not a sentence
    // with the tail fields silently defaulted.
    check(512, (an_rmc(), any::<Index>()), |(f, idx)| {
        // Strip the '$' and the CRLF, then cut inside the body.
        let body = &f.text[1..f.text.len() - 2];
        let cut = idx.index(body.len());
        let mut text = b"$".to_vec();
        text.extend_from_slice(&body[..cut]);
        text.extend_from_slice(b"\r\n");
        prop_assert!(
            feed_all(&text).is_empty(),
            "a {}-of-{} byte prefix parsed",
            cut,
            body.len()
        );
        Ok(())
    });
}

#[test]
fn the_parser_resyncs_on_the_next_frame_after_arbitrary_noise() {
    check(
        512,
        (
            prop::collection::vec(
                any::<u8>().prop_filter("no frame start", |b| *b != b'$'),
                0..=200,
            ),
            an_rmc(),
        ),
        |(noise, f)| {
            let mut text = noise;
            text.extend_from_slice(&f.text);
            let sentences = feed_all(&text);
            prop_assert!(
                sentences
                    .iter()
                    .any(|s| matches!(s, Sentence::Rmc(r) if r.valid)),
                "the valid RMC after {} noise bytes was lost",
                text.len() - f.text.len()
            );
            Ok(())
        },
    );
}

#[test]
fn an_oversized_sentence_is_dropped_without_disturbing_the_next_one() {
    check(
        256,
        (
            a_payload(400).prop_filter("over the buffer", |p| p.len() >= OVERSIZE),
            an_rmc(),
        ),
        |(payload, f)| {
            let mut text = framed(&payload);
            text.extend_from_slice(&f.text);
            let sentences = feed_all(&text);
            prop_assert_eq!(
                sentences.len(),
                1,
                "an oversized sentence of {} bytes was not dropped cleanly",
                payload.len()
            );
            prop_assert!(matches!(sentences[0], Sentence::Rmc(r) if r.valid));
            Ok(())
        },
    );
}

#[test]
fn a_ubx_frame_round_trips_through_its_own_framing() {
    check(
        512,
        (
            any::<u8>(),
            any::<u8>(),
            prop::collection::vec(any::<u8>(), 0..=64),
        ),
        |(class, id, payload)| {
            let mut out = vec![0u8; ubx::FRAME_OVERHEAD + payload.len()];
            let len = ubx::write_frame(class, id, &payload, &mut out).expect("fits exactly");
            prop_assert_eq!(len, ubx::FRAME_OVERHEAD + payload.len());
            prop_assert_eq!(&out[0..2], &[ubx::SYNC1, ubx::SYNC2]);
            prop_assert_eq!(out[2], class);
            prop_assert_eq!(out[3], id);
            prop_assert_eq!(u16::from_le_bytes([out[4], out[5]]) as usize, payload.len());
            prop_assert_eq!(&out[6..6 + payload.len()], payload.as_slice());
            let (ck_a, ck_b) = ubx::checksum(&out[2..len - 2]);
            prop_assert_eq!((out[len - 2], out[len - 1]), (ck_a, ck_b));
            Ok(())
        },
    );
}

#[test]
fn a_ubx_frame_never_writes_past_a_short_buffer() {
    check(
        512,
        (
            any::<u8>(),
            any::<u8>(),
            prop::collection::vec(any::<u8>(), 0..=32),
            any::<Index>(),
        ),
        |(class, id, payload, idx)| {
            let need = ubx::FRAME_OVERHEAD + payload.len();
            let short = idx.index(need);
            let mut out = vec![0xAAu8; short];
            prop_assert_eq!(
                ubx::write_frame(class, id, &payload, &mut out),
                None,
                "a {}-byte frame fit {} bytes",
                need,
                short
            );
            prop_assert!(
                out.iter().all(|b| *b == 0xAA),
                "a refused write still touched the buffer"
            );
            Ok(())
        },
    );
}

#[test]
fn a_pmreq_backup_never_encodes_the_sleep_forever_duration() {
    // The spec reads a duration of 0 as "no time limit", which would strand a
    // receiver whose wake byte was lost — the whole point of the backstop.
    check(1024, any::<u32>(), |duration_ms| {
        let frame = ubx::pmreq_backup(duration_ms);
        prop_assert_eq!(frame.len(), ubx::PMREQ_FRAME_LEN);
        prop_assert_eq!(&frame[0..2], &[ubx::SYNC1, ubx::SYNC2]);
        prop_assert_eq!(frame[2], ubx::CLASS_RXM);
        prop_assert_eq!(frame[3], ubx::ID_PMREQ);
        let encoded = u32::from_le_bytes([frame[10], frame[11], frame[12], frame[13]]);
        prop_assert!(encoded > 0, "encoded a duration of 0");
        prop_assert_eq!(encoded, duration_ms.max(1));
        let (ck_a, ck_b) = ubx::checksum(&frame[2..ubx::PMREQ_FRAME_LEN - 2]);
        prop_assert_eq!(
            (
                frame[ubx::PMREQ_FRAME_LEN - 2],
                frame[ubx::PMREQ_FRAME_LEN - 1]
            ),
            (ck_a, ck_b)
        );
        Ok(())
    });
}
