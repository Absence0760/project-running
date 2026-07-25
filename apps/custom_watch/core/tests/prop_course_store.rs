//! Property tests for the phone→watch breadcrumb-course frame and its chunked
//! reassembler. Both are fed straight off the BLE `course` write
//! characteristic, so the frame bytes and the chunk offsets are equally
//! untrusted — a corrupt push must never load a truncated course mid-race.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::course::{CoursePoint, MAX_COURSE_POINTS};
use watch_core::course_store::{
    course_frame_len, decode, encode, CourseAssembler, CoursePush, COURSE_CHUNK_CAP,
    COURSE_HEADER_LEN, MAX_COURSE_FRAME_LEN,
};

/// Coordinates on the 1e-7-degree integer grid the wire format quantises to,
/// so encode → decode is exact by construction and any mismatch is a codec
/// bug rather than a rounding artefact.
fn a_polyline(max_points: usize) -> impl Strategy<Value = Vec<(i32, i32)>> {
    prop::collection::vec(
        (
            -900_000_000i32..=900_000_000,
            -1_800_000_000i32..=1_800_000_000,
        ),
        2..=max_points,
    )
}

fn to_points(e7: &[(i32, i32)]) -> Vec<CoursePoint> {
    e7.iter()
        .map(|(lat, lon)| CoursePoint {
            lat_deg: *lat as f64 / 1e7,
            lon_deg: *lon as f64 / 1e7,
        })
        .collect()
}

fn encoded(e7: &[(i32, i32)]) -> Vec<u8> {
    let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
    let len = encode(&to_points(e7), &mut buf).expect("a legal polyline encodes");
    buf[..len].to_vec()
}

#[test]
fn decode_never_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=(COURSE_HEADER_LEN + 40 * 8)),
        |bytes| {
            let _ = decode(&bytes);
            Ok(())
        },
    );
}

#[test]
fn a_decoded_course_always_satisfies_the_courses_own_bounds() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=(COURSE_HEADER_LEN + 40 * 8)),
        |bytes| {
            let Some(course) = decode(&bytes) else {
                return Ok(());
            };
            let n = course.points().len();
            prop_assert!(
                (2..=MAX_COURSE_POINTS).contains(&n),
                "decoded {n} points, outside 2..={MAX_COURSE_POINTS}"
            );
            prop_assert_eq!(bytes.len(), course_frame_len(n));
            prop_assert!(course.total_m().is_finite());
            for p in course.points() {
                prop_assert!(p.lat_deg.is_finite() && p.lon_deg.is_finite());
            }
            Ok(())
        },
    );
}

#[test]
fn a_polyline_round_trips_through_the_frame() {
    check(256, a_polyline(MAX_COURSE_POINTS), |e7| {
        let frame = encoded(&e7);
        prop_assert_eq!(frame.len(), course_frame_len(e7.len()));
        let course = decode(&frame).expect("a freshly encoded frame decodes");
        let want = to_points(&e7);
        prop_assert_eq!(course.points(), want.as_slice());
        Ok(())
    });
}

#[test]
fn an_over_cap_or_too_short_polyline_is_refused() {
    check(
        64,
        prop::collection::vec((0i32..1000, 0i32..1000), 0..=1),
        |short| {
            let mut buf = [0u8; MAX_COURSE_FRAME_LEN];
            prop_assert_eq!(encode(&to_points(&short), &mut buf), None);
            Ok(())
        },
    );
    check(
        16,
        prop::collection::vec(
            (0i32..1000, 0i32..1000),
            (MAX_COURSE_POINTS + 1)..=(MAX_COURSE_POINTS + 8),
        ),
        |over| {
            let mut buf = [0u8; MAX_COURSE_FRAME_LEN + 8 * 8];
            prop_assert_eq!(encode(&to_points(&over), &mut buf), None);
            Ok(())
        },
    );
}

#[test]
fn every_proper_prefix_of_a_frame_is_rejected() {
    check(256, (a_polyline(64), any::<Index>()), |(e7, idx)| {
        let frame = encoded(&e7);
        let cut = idx.index(frame.len());
        prop_assert_eq!(
            decode(&frame[..cut]).is_some(),
            false,
            "a {} of {} byte prefix decoded",
            cut,
            frame.len()
        );
        Ok(())
    });
}

#[test]
fn a_frame_with_trailing_bytes_is_rejected() {
    check(
        256,
        (a_polyline(64), prop::collection::vec(any::<u8>(), 1..=8)),
        |(e7, tail)| {
            let mut frame = encoded(&e7);
            frame.extend_from_slice(&tail);
            prop_assert!(decode(&frame).is_none(), "trailing bytes must not decode");
            Ok(())
        },
    );
}

#[test]
fn a_single_byte_corruption_never_changes_the_point_count() {
    check(
        512,
        (a_polyline(64), any::<Index>(), 1u8..=u8::MAX),
        |(e7, idx, mask)| {
            let mut frame = encoded(&e7);
            let at = idx.index(frame.len());
            frame[at] ^= mask;
            match decode(&frame) {
                None => Ok(()),
                Some(course) => {
                    prop_assert_eq!(
                        course.points().len(),
                        e7.len(),
                        "a surviving corruption changed the point count"
                    );
                    Ok(())
                }
            }
        },
    );
}

#[test]
fn a_chunked_push_reassembles_the_frame_it_was_split_from() {
    check(
        128,
        (a_polyline(MAX_COURSE_POINTS), 1usize..=COURSE_CHUNK_CAP),
        |(e7, chunk)| {
            let frame = encoded(&e7);
            let mut asm = CourseAssembler::new();
            let mut offset = 0usize;
            let mut outcome = CoursePush::More;
            while offset < frame.len() {
                let end = (offset + chunk).min(frame.len());
                outcome = asm.push(offset, &frame[offset..end]);
                prop_assert_ne!(outcome, CoursePush::Rejected, "chunk at {}", offset);
                offset = end;
            }
            prop_assert_eq!(outcome, CoursePush::Complete);
            prop_assert_eq!(asm.frame(), frame.as_slice());
            let course = decode(asm.frame()).expect("a reassembled frame decodes");
            let want = to_points(&e7);
            prop_assert_eq!(course.points(), want.as_slice());
            Ok(())
        },
    );
}

#[test]
fn an_arbitrary_chunk_stream_never_completes_an_undecodable_frame() {
    check(
        256,
        prop::collection::vec(
            (
                prop_oneof![
                    Just(0usize),
                    0usize..=MAX_COURSE_FRAME_LEN,
                    any::<u16>().prop_map(|v| v as usize)
                ],
                prop::collection::vec(any::<u8>(), 0..=COURSE_CHUNK_CAP),
            ),
            0..=12,
        ),
        |chunks| {
            let mut asm = CourseAssembler::new();
            for (offset, payload) in &chunks {
                let outcome = asm.push(*offset, payload);
                prop_assert!(
                    asm.frame().len() <= MAX_COURSE_FRAME_LEN,
                    "the assembler buffered {} bytes",
                    asm.frame().len()
                );
                if outcome == CoursePush::Complete {
                    // Fail-closed: "complete" must mean decodable, never a
                    // frame the nav task then half-applies.
                    prop_assert!(
                        decode(asm.frame()).is_some(),
                        "a Complete frame failed to decode"
                    );
                }
                if outcome == CoursePush::Rejected {
                    prop_assert!(asm.frame().is_empty(), "a rejection must reset the buffer");
                }
            }
            Ok(())
        },
    );
}

#[test]
fn a_chunk_stream_that_skips_a_byte_is_rejected_rather_than_stitched() {
    check(
        128,
        (a_polyline(32), 2usize..=32, 1usize..=4),
        |(e7, chunk, skip)| {
            let frame = encoded(&e7);
            let mut asm = CourseAssembler::new();
            let first = chunk.min(frame.len());
            prop_assert_ne!(asm.push(0, &frame[..first]), CoursePush::Rejected);
            let resume = (first + skip).min(frame.len());
            if resume > first {
                prop_assert_eq!(
                    asm.push(resume, &frame[resume..]),
                    CoursePush::Rejected,
                    "an offset gap of {} was stitched over",
                    skip
                );
                prop_assert!(asm.frame().is_empty());
            }
            Ok(())
        },
    );
}
