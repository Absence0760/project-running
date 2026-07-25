//! Property tests for the run wire format — the bytes the phone reassembles
//! from BLE and the watch reads back off flash, so every input here is
//! untrusted. The hand-written cases in `run_store.rs` pin known-adversarial
//! shapes; these assert the invariants that must hold for inputs nobody
//! thought of: never panic, fail closed, round-trip the legal domain, reject
//! every truncation, and never let a corrupted or over-claiming blob yield
//! more records than the cap.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::run_store::{
    blob_len, crc32, point_count, record_tag, verify_blob, ChunkRequest, LapRecord, ManifestEntry,
    ManifestHeader, RunFooter, RunHeader, RunWriter, TrackPoint, ELE_NONE, FOOTER_LEN, HEADER_LEN,
    MANIFEST_ENTRY_LEN, MANIFEST_HEADER_LEN, RECORD_LEN, RECORD_TAG_LAP, RECORD_TAG_POINT,
};

/// Big enough for every blob these suites build, and the real slot size.
const SLOT: usize = 4096;

/// A track point in the legal domain: `ele_dm` never carries the [`ELE_NONE`]
/// sentinel and `bpm` never carries the 0 = absent sentinel, since both encode
/// as "absent" by design.
fn a_point() -> impl Strategy<Value = TrackPoint> {
    (
        any::<i32>(),
        any::<i32>(),
        any::<u32>(),
        prop::option::of((ELE_NONE + 1)..=i16::MAX),
        prop::option::of(1u8..=u8::MAX),
    )
        .prop_map(|(lat_e7, lon_e7, t_offset_s, ele_dm, bpm)| TrackPoint {
            lat_e7,
            lon_e7,
            t_offset_s,
            ele_dm,
            bpm,
        })
}

fn a_lap() -> impl Strategy<Value = LapRecord> {
    (any::<u16>(), any::<u32>(), any::<u32>(), any::<u32>()).prop_map(
        |(index, lap_distance_dm, split_s, moving_s)| LapRecord {
            index,
            lap_distance_dm,
            split_s,
            moving_s,
        },
    )
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Record {
    Point(TrackPoint),
    Lap(LapRecord),
}

fn a_record() -> impl Strategy<Value = Record> {
    prop_oneof![
        3 => a_point().prop_map(Record::Point),
        1 => a_lap().prop_map(Record::Lap),
    ]
}

/// A blob built the way the recorder builds one: header, records in order,
/// CRC-stamped footer. Kept well under [`MAX_STORED_LAPS`] laps so the
/// lap-drop rule never fires — that rule is another suite's business.
fn a_blob(max_records: usize) -> impl Strategy<Value = (Vec<Record>, Vec<u8>)> {
    (
        prop::collection::vec(a_record(), 0..=max_records),
        any::<u32>(),
        any::<u32>(),
        any::<u32>(),
        any::<u32>(),
        any::<u32>(),
    )
        .prop_map(
            |(records, run_seq, start_uptime_s, distance_m, moving_s, elapsed_s)| {
                let sink: heapless::Vec<u8, SLOT> = heapless::Vec::new();
                let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
                for r in &records {
                    match r {
                        Record::Point(p) => w.push_point(p).expect("push point"),
                        Record::Lap(l) => {
                            assert!(w.push_lap(l).expect("push lap"), "under the lap cap");
                        }
                    }
                }
                let blob = w.finalize(distance_m, moving_s, elapsed_s).expect("finalize");
                (records, blob.to_vec())
            },
        )
}

/// Walk a blob's record region back into the record sequence, dispatching on
/// each cell's tag the way a reader must.
fn decode_records(blob: &[u8], count: usize) -> Option<Vec<Record>> {
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let at = HEADER_LEN + i * RECORD_LEN;
        let cell = blob.get(at..at + RECORD_LEN)?;
        match record_tag(cell)? {
            RECORD_TAG_POINT => out.push(Record::Point(TrackPoint::decode(cell)?)),
            RECORD_TAG_LAP => out.push(Record::Lap(LapRecord::decode(cell)?)),
            _ => return None,
        }
    }
    Some(out)
}

#[test]
fn no_decoder_panics_on_arbitrary_bytes() {
    check(
        512,
        prop::collection::vec(any::<u8>(), 0..=(HEADER_LEN + 8 * RECORD_LEN + FOOTER_LEN)),
        |bytes| {
            let _ = RunHeader::decode(&bytes);
            let _ = RunFooter::decode(&bytes);
            let _ = TrackPoint::decode(&bytes);
            let _ = LapRecord::decode(&bytes);
            let _ = record_tag(&bytes);
            let _ = ManifestHeader::decode(&bytes);
            let _ = ManifestEntry::decode(&bytes);
            let _ = ChunkRequest::decode(&bytes);
            let _ = verify_blob(&bytes);
            let _ = crc32(&bytes);
            Ok(())
        },
    );
}

#[test]
fn point_count_never_panics_and_stays_consistent_with_blob_len() {
    check(512, any::<u32>(), |len| {
        if let Some(n) = point_count(len) {
            prop_assert_eq!(blob_len(n), len);
        }
        Ok(())
    });
}

#[test]
fn a_track_point_round_trips_through_its_record() {
    check(512, a_point(), |p| {
        let bytes = p.encode();
        prop_assert_eq!(record_tag(&bytes), Some(RECORD_TAG_POINT));
        prop_assert_eq!(TrackPoint::decode(&bytes), Some(p));
        prop_assert_eq!(LapRecord::decode(&bytes), None);
        Ok(())
    });
}

#[test]
fn a_lap_record_round_trips_through_its_record() {
    check(512, a_lap(), |l| {
        let bytes = l.encode();
        prop_assert_eq!(record_tag(&bytes), Some(RECORD_TAG_LAP));
        prop_assert_eq!(LapRecord::decode(&bytes), Some(l));
        prop_assert_eq!(TrackPoint::decode(&bytes), None);
        Ok(())
    });
}

#[test]
fn header_footer_manifest_and_chunk_request_round_trip() {
    check(
        512,
        (
            any::<u8>(),
            any::<u8>(),
            any::<u32>(),
            any::<u32>(),
            any::<u32>(),
            any::<u32>(),
            any::<u32>(),
            any::<u32>(),
            any::<u8>(),
            any::<u16>(),
        ),
        |(version, flags, run_seq, start_uptime_s, a, b, c, d, run_count, len)| {
            let header = RunHeader {
                version,
                flags,
                run_seq,
                start_uptime_s,
            };
            prop_assert_eq!(RunHeader::decode(&header.encode()), Some(header));

            let footer = RunFooter {
                distance_m: a,
                moving_s: b,
                elapsed_s: c,
                crc32: d,
            };
            prop_assert_eq!(RunFooter::decode(&footer.encode()), Some(footer));

            let mh = ManifestHeader {
                run_count,
                watch_uptime_s: a,
            };
            prop_assert_eq!(ManifestHeader::decode(&mh.encode()), Some(mh));

            let entry = ManifestEntry {
                run_seq,
                size: b,
                start_uptime_s: c,
            };
            prop_assert_eq!(ManifestEntry::decode(&entry.encode()), Some(entry));

            let req = ChunkRequest {
                run_seq,
                offset: a,
                len,
            };
            prop_assert_eq!(ChunkRequest::decode(&req.encode()), Some(req));
            Ok(())
        },
    );
}

#[test]
fn a_written_blob_verifies_and_replays_its_records_in_order() {
    check(256, a_blob(48), |(records, blob)| {
        prop_assert_eq!(blob.len() as u32, blob_len(records.len() as u32));
        prop_assert_eq!(point_count(blob.len() as u32), Some(records.len() as u32));
        prop_assert!(verify_blob(&blob));
        let replayed = decode_records(&blob, records.len());
        prop_assert_eq!(replayed.as_ref(), Some(&records));
        Ok(())
    });
}

#[test]
fn every_proper_prefix_of_a_blob_is_rejected() {
    check(
        256,
        (a_blob(32), any::<Index>()),
        |((_, blob), idx)| {
            let cut = idx.index(blob.len());
            prop_assert!(
                !verify_blob(&blob[..cut]),
                "a {cut}-byte prefix of a {}-byte blob must not verify",
                blob.len()
            );
            Ok(())
        },
    );
}

#[test]
fn a_single_byte_corruption_never_yields_a_different_run() {
    check(
        256,
        (a_blob(24), any::<Index>(), 1u8..=u8::MAX),
        |((records, blob), idx, mask)| {
            let at = idx.index(blob.len());
            let footer_at = HEADER_LEN + records.len() * RECORD_LEN;
            let mut bad = blob.clone();
            bad[at] ^= mask;

            if at < footer_at {
                prop_assert!(
                    !verify_blob(&bad),
                    "a flip at {at} is inside the CRC-covered header+records"
                );
            }
            if verify_blob(&bad) {
                prop_assert_eq!(
                    point_count(bad.len() as u32),
                    Some(records.len() as u32),
                    "a surviving corruption never changes the record count"
                );
                prop_assert_eq!(RunHeader::decode(&bad), RunHeader::decode(&blob));
                let replayed = decode_records(&bad, records.len());
                prop_assert_eq!(
                    replayed.as_ref(),
                    Some(&records),
                    "a surviving corruption never changes a record"
                );
            }
            Ok(())
        },
    );
}

#[test]
fn a_manifest_entrys_size_is_always_a_decodable_blob_length() {
    check(
        512,
        prop::collection::vec(any::<u8>(), MANIFEST_HEADER_LEN..=(MANIFEST_HEADER_LEN + 4 * MANIFEST_ENTRY_LEN)),
        |bytes| {
            let Some(header) = ManifestHeader::decode(&bytes) else {
                return Ok(());
            };
            // A phone that trusts run_count must never be walked off the end of
            // the value it read.
            for i in 0..header.run_count as usize {
                let at = MANIFEST_HEADER_LEN + i * MANIFEST_ENTRY_LEN;
                if at + MANIFEST_ENTRY_LEN > bytes.len() {
                    break;
                }
                prop_assert!(ManifestEntry::decode(&bytes[at..]).is_some());
            }
            Ok(())
        },
    );
}
