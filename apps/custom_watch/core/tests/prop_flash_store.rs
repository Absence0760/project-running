//! Property tests for the flash-resident records — the config page, the
//! persisted BLE bond, and the boot-time slot recovery scan. Every input is a
//! raw flash read: possibly erased (all-`0xFF`), possibly half-written by a
//! power loss, possibly written by an older firmware.

mod support;

use proptest::prelude::*;
use proptest::sample::Index;
use support::check;
use watch_core::flash_plan::{plan_checkpoint_write, plan_slot_write};
use watch_core::flash_store::{
    chunk_len, decode_config, encode_config, recover_slot, BondRecord, RecoveredRun, SlotDir,
    BOND_RECORD_LEN, CONFIG_RECORD_LEN, MAX_POINTS_PER_RUN, SLOT_COUNT, SLOT_LEN,
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
    check(
        256,
        (any::<u8>(), any::<u8>(), any::<Index>()),
        |(mode, flags, idx)| {
            let rec = encode_config(mode, flags);
            prop_assert_eq!(decode_config(&rec), Some((mode, flags)));
            let cut = idx.index(CONFIG_RECORD_LEN);
            prop_assert_eq!(decode_config(&rec[..cut]), None, "prefix of {} bytes", cut);
            Ok(())
        },
    );
}

#[test]
fn a_single_byte_corruption_of_the_config_record_is_always_caught() {
    check(
        512,
        (any::<u8>(), any::<u8>(), any::<Index>(), 1u8..=u8::MAX),
        |(mode, flags, idx, mask)| {
            let mut rec = encode_config(mode, flags);
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
        prop_assert_eq!(
            BondRecord::decode(&rec[..cut]),
            None,
            "prefix of {} bytes",
            cut
        );
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

/// One run-store driver operation: a mid-run checkpoint or a finished-run
/// commit, whose flash write either lands or fails after the erase has already
/// blanked the target page.
#[derive(Clone, Copy, Debug)]
struct SlotOp {
    commit: bool,
    run_seq: u32,
    blob_len: usize,
    write_ok: bool,
}

fn a_slot_op() -> impl Strategy<Value = SlotOp> {
    (any::<bool>(), 0u32..4, 1usize..=SLOT_LEN, any::<bool>()).prop_map(
        |(commit, run_seq, blob_len, write_ok)| SlotOp {
            commit,
            run_seq,
            blob_len,
            write_ok,
        },
    )
}

#[test]
fn the_directory_never_advertises_a_run_that_is_not_durable_on_flash() {
    // The seal-then-drop invariant, over arbitrary interleavings of checkpoints,
    // commits, and torn writes: every run the directory advertises must be
    // physically present, at the slot and size it claims. Holding a superseded
    // entry until the replacement write lands is what keeps the directory from
    // under-reporting; this is the other side of it — the late release must never
    // let the directory OVER-report, nor advertise one run twice.
    check(256, prop::collection::vec(a_slot_op(), 0..24), |ops| {
        let mut dir = SlotDir::new();
        // What each page physically holds, as (run_seq, blob length).
        let mut durable: [Option<(u32, u32)>; SLOT_COUNT] = [None; SLOT_COUNT];
        for op in ops {
            let planned = if op.commit {
                plan_slot_write(&mut dir, 0, op.run_seq, 0, op.blob_len)
            } else {
                plan_checkpoint_write(&mut dir, 0, op.run_seq, 0, op.blob_len)
            };
            let Some(plan) = planned else { continue };
            // The erase always happens first, so whatever the page held is gone
            // whether or not the write behind it lands.
            durable[plan.slot] = op.write_ok.then_some((op.run_seq, op.blob_len as u32));
            match (op.commit, op.write_ok) {
                (true, true) => dir.commit_written(plan.slot),
                (true, false) => dir.commit_failed(plan.slot),
                (false, true) => {}
                (false, false) => dir.forget(plan.slot),
            }

            // A pending partial run is always one of the advertised ones: the
            // wrist marker can never claim a run the phone cannot then pull.
            prop_assert!(
                dir.pending_partial_count() <= dir.run_count(),
                "{} pending exceeds the {} advertised",
                dir.pending_partial_count(),
                dir.run_count()
            );

            let mut seen: heapless::Vec<u32, SLOT_COUNT> = heapless::Vec::new();
            for entry in dir.manifest().iter() {
                prop_assert!(
                    !seen.contains(&entry.run_seq),
                    "run {} advertised twice",
                    entry.run_seq
                );
                seen.push(entry.run_seq)
                    .expect("at most one entry per slot");
                let (slot, size) = dir.find(entry.run_seq).expect("an advertised run resolves");
                prop_assert_eq!(
                    durable[slot],
                    Some((entry.run_seq, size)),
                    "run {} claims slot {}, which holds {:?}",
                    entry.run_seq,
                    slot,
                    durable[slot]
                );
            }
        }
        Ok(())
    });
}

/// An arbitrary post-reset flash region as the boot scan sees it: each slot
/// either erased or holding a recovered blob, finished or not, with ids drawn
/// from a small pool so ping-pong pairs of one run occur often.
fn a_recovered_region() -> impl Strategy<Value = [Option<RecoveredRun>; SLOT_COUNT]> {
    prop::collection::vec(
        prop::option::of((any::<bool>(), 0u32..4, 1u32..=4096, any::<u32>())),
        SLOT_COUNT,
    )
    .prop_map(|v| {
        let mut slots: [Option<RecoveredRun>; SLOT_COUNT] = [None; SLOT_COUNT];
        for (slot, entry) in slots.iter_mut().zip(v) {
            *slot = entry.map(|(finished, run_seq, size, elapsed_s)| RecoveredRun {
                run_seq,
                size,
                start_uptime_s: 0,
                finished,
                elapsed_s,
            });
        }
        slots
    })
}

#[test]
fn the_boot_scan_counts_every_interrupted_run_it_advertises_and_no_others() {
    // The wrist marker's honesty, over every shape a post-reset region can take:
    // it never over-claims (a pending run is always advertised), a region of
    // cleanly committed runs raises it not at all, and a region where NOTHING got
    // its commit raises it for every run recovered.
    check(256, a_recovered_region(), |slots| {
        let dir = SlotDir::from_recovered(slots);
        let mut ids: heapless::Vec<u32, SLOT_COUNT> = heapless::Vec::new();
        for r in slots.iter().flatten() {
            if !ids.contains(&r.run_seq) {
                ids.push(r.run_seq).expect("at most one id per slot");
            }
        }
        prop_assert_eq!(
            dir.run_count() as usize,
            ids.len(),
            "every distinct recovered run is advertised exactly once"
        );
        prop_assert!(dir.pending_partial_count() <= dir.run_count());
        if slots.iter().flatten().all(|r| r.finished) {
            prop_assert_eq!(
                dir.pending_partial_count(),
                0,
                "a region of committed runs has nothing pending"
            );
        }
        if slots.iter().flatten().all(|r| !r.finished) {
            prop_assert_eq!(
                dir.pending_partial_count(),
                dir.run_count(),
                "a region of checkpoints is pending in full"
            );
        }
        Ok(())
    });
}

#[test]
fn a_live_run_never_becomes_a_pending_partial_however_it_is_written() {
    // The other direction of the same boundary: with every flash write landing,
    // no interleaving of checkpoints and commits can make the recorder's own
    // in-progress bytes look like an interrupted run. Only a reset (the scan
    // above) or a failed commit may.
    check(256, prop::collection::vec(a_slot_op(), 0..24), |ops| {
        let mut dir = SlotDir::new();
        for op in ops {
            let planned = if op.commit {
                plan_slot_write(&mut dir, 0, op.run_seq, 0, op.blob_len)
            } else {
                plan_checkpoint_write(&mut dir, 0, op.run_seq, 0, op.blob_len)
            };
            let Some(plan) = planned else { continue };
            if op.commit {
                dir.commit_written(plan.slot);
            }
            prop_assert_eq!(dir.pending_partial_count(), 0);
        }
        Ok(())
    });
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
