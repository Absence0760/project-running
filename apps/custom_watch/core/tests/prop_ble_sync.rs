//! Property tests for the BLE sync framing. This is the one protocol in the
//! firmware with no integration coverage at all (the SoftDevice build cannot
//! run in the Renode sim), so the transport's decisions are only ever checked
//! here.

mod support;

use proptest::prelude::*;
use support::check;
use watch_core::ble_sync::{chunk_notify_len, encode_manifest, parse_push_chunk, MANIFEST_CAP};
use watch_core::flash_store::SLOT_COUNT;
use watch_core::run_store::{
    ManifestEntry, ManifestHeader, MANIFEST_ENTRY_LEN, MANIFEST_HEADER_LEN,
};

fn an_entry() -> impl Strategy<Value = ManifestEntry> {
    (any::<u32>(), any::<u32>(), any::<u32>()).prop_map(|(run_seq, size, start_uptime_s)| {
        ManifestEntry {
            run_seq,
            size,
            start_uptime_s,
        }
    })
}

#[test]
fn a_manifests_declared_count_never_outruns_the_bytes_it_wrote() {
    // The phone parses `run_count` fixed-width entries out of the value it
    // read. A count larger than the bytes present would have it parse whatever
    // followed the characteristic as a manifest entry.
    check(
        512,
        (
            prop::collection::vec(an_entry(), 0..=(SLOT_COUNT + 6)),
            any::<u32>(),
        ),
        |(entries, uptime)| {
            let buf = encode_manifest(&entries, uptime);
            prop_assert!(
                buf.len() <= MANIFEST_CAP,
                "a {}-byte manifest exceeds the {MANIFEST_CAP}-byte value cap",
                buf.len()
            );
            let header = ManifestHeader::decode(&buf).expect("a manifest starts with its header");
            prop_assert_eq!(header.watch_uptime_s, uptime);
            let count = header.run_count as usize;
            prop_assert!(count <= SLOT_COUNT, "{} entries claimed", count);
            prop_assert!(
                count <= entries.len(),
                "advertised {} runs from a list of {}",
                count,
                entries.len()
            );
            prop_assert_eq!(
                MANIFEST_HEADER_LEN + count * MANIFEST_ENTRY_LEN,
                buf.len(),
                "the declared count does not account for exactly the bytes written"
            );
            // Every advertised entry is one the caller actually offered — the
            // encoder may choose which to drop, never what to invent.
            for i in 0..count {
                let at = MANIFEST_HEADER_LEN + i * MANIFEST_ENTRY_LEN;
                let got = ManifestEntry::decode(&buf[at..]).expect("entry decodes");
                prop_assert!(entries.contains(&got), "entry {} was not offered", i);
            }
            Ok(())
        },
    );
}

#[test]
fn a_chunk_reply_is_always_bounded_by_one_notification() {
    check(2048, (any::<u16>(), any::<u16>()), |(requested, cap)| {
        let len = chunk_notify_len(requested, cap);
        prop_assert!(len <= requested, "{len} exceeds the requested {requested}");
        prop_assert!(len <= cap, "{len} exceeds the notify cap {cap}");
        Ok(())
    });
}

#[test]
fn a_course_write_either_parses_whole_or_is_dropped() {
    check(
        1024,
        prop::collection::vec(any::<u8>(), 0..=64),
        |bytes| match parse_push_chunk(&bytes) {
            None => {
                prop_assert!(bytes.len() < 2, "a {}-byte write was dropped", bytes.len());
                Ok(())
            }
            Some((offset, payload)) => {
                prop_assert!(bytes.len() >= 2);
                prop_assert_eq!(payload, &bytes[2..]);
                prop_assert_eq!(offset, u16::from_le_bytes([bytes[0], bytes[1]]) as usize);
                Ok(())
            }
        },
    );
}
