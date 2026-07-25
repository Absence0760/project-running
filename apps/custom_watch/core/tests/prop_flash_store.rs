//! Property tests for the flash-resident records — the config page, the
//! persisted BLE bond, and the boot-time slot recovery scan. Every input is a
//! raw flash read: possibly erased (all-`0xFF`), possibly half-written by a
//! power loss, possibly written by an older firmware.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::flash_store::{
    chunk_len, decode_config, encode_config, recover_slot, BondRecord, BOND_RECORD_LEN,
    CONFIG_RECORD_LEN, MAX_POINTS_PER_RUN, SLOT_LEN,
};
use watch_core::run_store::{
    blob_len, point_count, RunWriter, TrackPoint, FOOTER_LEN, HEADER_LEN, POINT_LEN,
};

fn a_bond() -> impl Strategy<Value = BondRecord> {
    (
        any::<u16>(),
        any::<[u8; 8]>(),
        any::<[u8; 16]>(),
        any::<u8>(),
        any::<u8>(),
        any::<[u8; 6]>(),
        any::<[u8; 16]>(),
    )
        .prop_map(
            |(master_ediv, master_rand, ltk, enc_flags, addr_flags, addr, irk)| BondRecord {
                master_ediv,
                master_rand,
                ltk,
                enc_flags,
                addr_flags,
                addr,
                irk,
            },
        )
}

/// A whole slot's worth of flash: a real blob written at the base, the rest
/// left erased, exactly as the run store leaves a page.
fn a_slot() -> impl Strategy<Value = (u32, u32, usize, Vec<u8>)> {
    (
        0usize..=64,
        any::<u32>(),
        any::<u32>(),
        any::<i32>(),
        any::<u32>(),
    )
        .prop_map(|(points, run_seq, start_uptime_s, lat_e7, distance_m)| {
            let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
            let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
            for t in 0..points as u32 {
                w.push_point(&TrackPoint {
                    lat_e7: lat_e7.wrapping_add(t as i32),
                    lon_e7: 0,
                    t_offset_s: t,
                    ele_dm: None,
                    bpm: None,
                })
                .expect("push");
            }
            let blob = w.finalize(distance_m, 0, 0).expect("finalize");
            let mut slot = vec![0xFFu8; SLOT_LEN];
            slot[..blob.len()].copy_from_slice(&blob);
            (run_seq, start_uptime_s, points, slot)
        })
}

#[test]
fn no_flash_decoder_panics_on_arbitrary_bytes() {
    check(
        256,
        prop::collection::vec(any::<u8>(), 0..=(HEADER_LEN + 24 * POINT_LEN + FOOTER_LEN)),
        |bytes| {
            let _ = decode_config(&bytes);
            let _ = BondRecord::decode(&bytes);
            let _ = recover_slot(&bytes);
            Ok(())
        },
    );
}

#[test]
fn an_erased_or_zeroed_page_reads_as_no_saved_state() {
    check(64, 0usize..=SLOT_LEN, |len| {
        let erased = vec![0xFFu8; len];
        prop_assert_eq!(decode_config(&erased), None);
        prop_assert_eq!(BondRecord::decode(&erased), None);
        prop_assert_eq!(recover_slot(&erased), None);
        let zeroed = vec![0u8; len];
        prop_assert_eq!(decode_config(&zeroed), None);
        prop_assert_eq!(BondRecord::decode(&zeroed), None);
        prop_assert_eq!(recover_slot(&zeroed), None);
        Ok(())
    });
}

#[test]
fn the_config_record_round_trips_and_rejects_every_truncation() {
    check(256, (any::<u8>(), any::<Index>()), |(mode, idx)| {
        let rec = encode_config(mode);
        prop_assert_eq!(decode_config(&rec), Some(mode));
        let cut = idx.index(CONFIG_RECORD_LEN);
        prop_assert_eq!(decode_config(&rec[..cut]), None, "prefix of {} bytes", cut);
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_of_the_config_record_is_always_caught() {
    check(
        512,
        (any::<u8>(), any::<Index>(), 1u8..=u8::MAX),
        |(mode, idx, mask)| {
            let mut rec = encode_config(mode);
            let at = idx.index(CONFIG_RECORD_LEN);
            rec[at] ^= mask;
            prop_assert_eq!(decode_config(&rec), None, "flip at byte {}", at);
            Ok(())
        },
    );
}

#[test]
fn the_bond_record_round_trips_and_rejects_every_truncation() {
    check(256, (a_bond(), any::<Index>()), |(bond, idx)| {
        let rec = bond.encode();
        prop_assert_eq!(BondRecord::decode(&rec), Some(bond));
        let cut = idx.index(BOND_RECORD_LEN);
        prop_assert_eq!(BondRecord::decode(&rec[..cut]), None, "prefix of {} bytes", cut);
        Ok(())
    });
}

#[test]
fn a_single_byte_corruption_of_the_bond_record_is_always_caught() {
    check(
        512,
        (a_bond(), any::<Index>(), 1u8..=u8::MAX),
        |(bond, idx, mask)| {
            let mut rec = bond.encode();
            let at = idx.index(BOND_RECORD_LEN);
            rec[at] ^= mask;
            prop_assert_eq!(BondRecord::decode(&rec), None, "flip at byte {}", at);
            Ok(())
        },
    );
}

#[test]
fn recovery_never_reports_more_than_the_slot_can_hold() {
    check(
        128,
        prop::collection::vec(any::<u8>(), 0..=SLOT_LEN),
        |bytes| {
            let Some(run) = recover_slot(&bytes) else {
                return Ok(());
            };
            prop_assert!(
                run.size as usize <= bytes.len(),
                "recovered size {} outruns the {} bytes read",
                run.size,
                bytes.len()
            );
            let n = point_count(run.size).expect("a recovered size is a whole blob length");
            prop_assert!(
                n <= MAX_POINTS_PER_RUN,
                "{n} records exceeds the {MAX_POINTS_PER_RUN}-record slot cap"
            );
            Ok(())
        },
    );
}

#[test]
fn a_committed_run_recovers_exactly_from_its_slot() {
    check(128, a_slot(), |(run_seq, start_uptime_s, points, slot)| {
        let run = recover_slot(&slot).expect("a finished blob recovers");
        prop_assert_eq!(run.run_seq, run_seq);
        prop_assert_eq!(run.start_uptime_s, start_uptime_s);
        prop_assert_eq!(run.size, blob_len(points as u32));
        Ok(())
    });
}

#[test]
fn a_truncated_slot_never_recovers_a_shorter_run() {
    // A power loss mid-write leaves a prefix on flash. The scan must find no
    // run at all rather than a plausible-looking shorter one, because a short
    // read would advertise a size the phone then pulls as a whole track.
    check(
        128,
        (a_slot(), any::<Index>()),
        |((_, _, points, slot), idx)| {
            let full = blob_len(points as u32) as usize;
            let cut = idx.index(full);
            let truncated = &slot[..cut];
            if let Some(run) = recover_slot(truncated) {
                prop_assert!(
                    run.size as usize <= cut,
                    "recovered {} bytes from a {cut}-byte prefix",
                    run.size
                );
                prop_assert!(
                    run.size < blob_len(points as u32),
                    "a prefix must never recover the whole run"
                );
            }
            Ok(())
        },
    );
}

#[test]
fn a_chunk_reply_never_over_reads_a_blob() {
    check(
        1024,
        (any::<u32>(), any::<u32>(), any::<u16>(), any::<u16>()),
        |(size, offset, requested, mtu)| {
            let len = chunk_len(size, offset, requested, mtu);
            prop_assert!(len <= requested, "{len} exceeds the requested {requested}");
            prop_assert!(len <= mtu, "{len} exceeds the notify mtu {mtu}");
            prop_assert!(
                offset.saturating_add(len as u32) <= size.max(offset),
                "offset {offset} + len {len} reads past size {size}"
            );
            if offset < size {
                prop_assert!(offset + len as u32 <= size);
            } else {
                prop_assert_eq!(len, 0, "a request at or past the end serves nothing");
            }
            Ok(())
        },
    );
}
