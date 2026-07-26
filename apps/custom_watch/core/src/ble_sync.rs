//! BLE sync framing — the pure half of the GATT characteristics the `app/`
//! radio task serves (`app/src/tasks/ble.rs`).
//!
//! [`crate::run_store`] owns the run wire structs, [`crate::course_store`] the
//! course frame, and [`crate::flash_plan`] the flash side. What is left, and
//! lives here, is the framing in between: building the `run_manifest`
//! characteristic value the phone reads to discover finished runs, bounding a
//! `run_chunk` request to one notification, and splitting a `course` write into
//! its offset header and payload.
//!
//! This is the one protocol in the firmware that gets NO integration coverage at
//! all: the `ble` build needs the S140 SoftDevice, which the Renode sim does not
//! model, so it is otherwise compile-verified only. Every decision the transport
//! makes therefore lives here, host-tested, rather than inside the task body.

use heapless::Vec;

use crate::flash_store::SLOT_COUNT;
use crate::run_store::{ManifestEntry, ManifestHeader, MANIFEST_ENTRY_LEN, MANIFEST_HEADER_LEN};

/// The `run_manifest` characteristic value cap: a header plus one entry per
/// slot, so the whole list always fits a single read / notification and the
/// phone never has to page it.
pub const MANIFEST_CAP: usize = MANIFEST_HEADER_LEN + SLOT_COUNT * MANIFEST_ENTRY_LEN;

/// Build the `run_manifest` value: the header (how many runs, plus the watch's
/// current uptime — the anchor the phone dates each run against, the watch
/// having no RTC) followed by one entry per finished run in slot order.
///
/// Entries past [`SLOT_COUNT`] cannot fit the value and are dropped, so the
/// header's count always equals the entries actually present: a count that
/// outran the bytes would have the phone parse whatever followed the value as a
/// manifest entry.
pub fn encode_manifest(entries: &[ManifestEntry], watch_uptime_s: u32) -> Vec<u8, MANIFEST_CAP> {
    let entries = &entries[..entries.len().min(SLOT_COUNT)];
    let mut buf = Vec::new();
    let header = ManifestHeader {
        run_count: entries.len() as u8,
        watch_uptime_s,
    };
    let _ = buf.extend_from_slice(&header.encode());
    for e in entries {
        let _ = buf.extend_from_slice(&e.encode());
    }
    buf
}

/// How many bytes a chunk reply may carry: what the phone asked for, bounded by
/// one notification. The blob-end bound is
/// [`crate::flash_plan::plan_chunk_read`]'s job — this is only the transport
/// bound, so a hostile `len` up to `u16::MAX` can never size a read past the
/// reply buffer.
pub fn chunk_notify_len(requested: u16, notify_cap: u16) -> u16 {
    requested.min(notify_cap)
}

/// Split one `course` write into its `offset(2, u16 LE) | payload` framing.
///
/// `None` when the write is too short to carry the offset header. Fail-closed:
/// feeding a header-less write to the reassembler as offset 0 would silently
/// overwrite the start of a course frame mid-push.
pub fn parse_course_chunk(bytes: &[u8]) -> Option<(usize, &[u8])> {
    if bytes.len() < 2 {
        return None;
    }
    Some((
        u16::from_le_bytes([bytes[0], bytes[1]]) as usize,
        &bytes[2..],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::flash_plan::{chunk_completes_run, plan_chunk_read, plan_slot_write, SlotWrite};
    use crate::flash_store::{slot_offset, SlotDir, SLOT_LEN};
    use crate::run_store::{
        blob_len, verify_blob, ChunkRequest, RunWriter, TrackPoint, CHUNK_REQUEST_LEN,
    };

    /// One notification's payload at the 256-byte ATT MTU the `ble` task
    /// configures — the same cap the task passes in.
    const NOTIFY_CAP: u16 = 244;

    const BASE: u32 = 0x000F_B000;

    fn an_entry(run_seq: u32) -> ManifestEntry {
        ManifestEntry {
            run_seq,
            size: blob_len(run_seq + 1),
            start_uptime_s: run_seq * 100,
        }
    }

    /// Decode a manifest value the way the phone does: header, then `run_count`
    /// fixed-width entries.
    fn decode_manifest(bytes: &[u8]) -> Option<(ManifestHeader, Vec<ManifestEntry, SLOT_COUNT>)> {
        let header = ManifestHeader::decode(bytes)?;
        let mut entries = Vec::new();
        for i in 0..header.run_count as usize {
            let at = MANIFEST_HEADER_LEN + i * MANIFEST_ENTRY_LEN;
            if at + MANIFEST_ENTRY_LEN > bytes.len() {
                return None;
            }
            entries.push(ManifestEntry::decode(&bytes[at..])?).ok()?;
        }
        Some((header, entries))
    }

    #[test]
    fn an_empty_manifest_is_a_bare_header() {
        let buf = encode_manifest(&[], 3600);
        assert_eq!(buf.len(), MANIFEST_HEADER_LEN);
        let (header, entries) = decode_manifest(&buf).expect("decodes");
        assert_eq!(header.run_count, 0);
        assert_eq!(header.watch_uptime_s, 3600);
        assert!(entries.is_empty());
    }

    #[test]
    fn a_full_manifest_fills_the_characteristic_exactly() {
        let all: [ManifestEntry; SLOT_COUNT] = core::array::from_fn(|i| an_entry(i as u32));
        let buf = encode_manifest(&all, 7200);
        assert_eq!(buf.len(), MANIFEST_CAP, "a full list is the value cap");

        let (header, entries) = decode_manifest(&buf).expect("decodes");
        assert_eq!(header.run_count, SLOT_COUNT as u8);
        assert_eq!(header.watch_uptime_s, 7200);
        assert_eq!(entries.len(), SLOT_COUNT);
        for (i, e) in entries.iter().enumerate() {
            assert_eq!(*e, an_entry(i as u32), "entry {i} round-trips in order");
        }
    }

    #[test]
    fn every_manifest_length_round_trips() {
        for n in 0..=SLOT_COUNT {
            let all: Vec<ManifestEntry, SLOT_COUNT> =
                (0..n as u32).map(an_entry).collect::<Vec<_, SLOT_COUNT>>();
            let buf = encode_manifest(&all, 42);
            assert_eq!(
                buf.len(),
                MANIFEST_HEADER_LEN + n * MANIFEST_ENTRY_LEN,
                "{n} entries"
            );
            let (header, entries) = decode_manifest(&buf).expect("decodes");
            assert_eq!(header.run_count as usize, n);
            assert_eq!(entries.len(), n);
        }
    }

    #[test]
    fn the_manifest_count_never_outruns_the_entries_present() {
        // The value cannot hold more than SLOT_COUNT entries, so the header must
        // not claim more either — a phone trusting an over-large count would
        // parse whatever bytes followed the value as a manifest entry.
        let too_many: [ManifestEntry; SLOT_COUNT + 3] =
            core::array::from_fn(|i| an_entry(i as u32));
        let buf = encode_manifest(&too_many, 9);
        assert_eq!(buf.len(), MANIFEST_CAP);
        let (header, entries) = decode_manifest(&buf).expect("decodes");
        assert_eq!(header.run_count, SLOT_COUNT as u8);
        assert_eq!(entries.len(), SLOT_COUNT);
        assert_eq!(
            MANIFEST_HEADER_LEN + header.run_count as usize * MANIFEST_ENTRY_LEN,
            buf.len(),
            "the declared count accounts for exactly the bytes written"
        );
    }

    #[test]
    fn chunk_notify_len_bounds_a_hostile_request() {
        assert_eq!(chunk_notify_len(0, NOTIFY_CAP), 0);
        assert_eq!(chunk_notify_len(1, NOTIFY_CAP), 1);
        assert_eq!(chunk_notify_len(NOTIFY_CAP - 1, NOTIFY_CAP), NOTIFY_CAP - 1);
        assert_eq!(chunk_notify_len(NOTIFY_CAP, NOTIFY_CAP), NOTIFY_CAP);
        assert_eq!(chunk_notify_len(NOTIFY_CAP + 1, NOTIFY_CAP), NOTIFY_CAP);
        assert_eq!(
            chunk_notify_len(u16::MAX, NOTIFY_CAP),
            NOTIFY_CAP,
            "a request 268x the notify payload is clamped, not honoured"
        );
    }

    #[test]
    fn parse_course_chunk_rejects_a_header_less_write() {
        assert_eq!(parse_course_chunk(&[]), None);
        assert_eq!(parse_course_chunk(&[0x00]), None, "half an offset header");
    }

    #[test]
    fn parse_course_chunk_reads_a_little_endian_offset() {
        assert_eq!(
            parse_course_chunk(&[0, 0, 1, 2, 3]),
            Some((0, &[1u8, 2, 3][..]))
        );
        assert_eq!(
            parse_course_chunk(&[0x34, 0x12, 9]),
            Some((0x1234, &[9u8][..]))
        );
        assert_eq!(
            parse_course_chunk(&[0xFF, 0xFF]),
            Some((0xFFFF, &[][..])),
            "the largest offset with an empty payload still parses"
        );
    }

    #[test]
    fn a_malformed_chunk_request_never_reaches_the_flash_plan() {
        // The hostile-frame path end to end: whatever the phone writes to
        // `run_chunk` must either decode to a request or be dropped. A decode
        // failure must not fall through to a read.
        let mut dir = SlotDir::new();
        let plan = plan_slot_write(&mut dir, BASE, 7, 0, 500).expect("fits");
        dir.commit_written(plan.slot);

        for len in 0..CHUNK_REQUEST_LEN {
            let short = [0xABu8; CHUNK_REQUEST_LEN];
            assert_eq!(
                ChunkRequest::decode(&short[..len]),
                None,
                "a {len}-byte write is not a request"
            );
        }

        // A well-formed request for a run that isn't held, and a well-formed
        // request off the end of one that is, both serve nothing.
        let unknown = ChunkRequest {
            run_seq: 0xDEAD_BEEF,
            offset: 0,
            len: u16::MAX,
        };
        let req = ChunkRequest::decode(&unknown.encode()).expect("decodes");
        let cap = chunk_notify_len(req.len, NOTIFY_CAP);
        assert_eq!(
            plan_chunk_read(&dir, BASE, req.run_seq, req.offset, cap),
            None
        );
        assert!(!chunk_completes_run(&dir, req.run_seq, u32::MAX));

        let past_end = ChunkRequest {
            run_seq: 7,
            offset: u32::MAX,
            len: u16::MAX,
        };
        let req = ChunkRequest::decode(&past_end.encode()).expect("decodes");
        let cap = chunk_notify_len(req.len, NOTIFY_CAP);
        assert_eq!(plan_chunk_read(&dir, BASE, 7, req.offset, cap), None);
    }

    #[test]
    fn the_phone_syncs_a_run_off_the_manifest_alone() {
        // The whole run-sync protocol as the phone drives it: read the manifest,
        // then for each advertised run issue `run_chunk` requests until the
        // reported size is in hand, and verify the reassembled blob.
        let mut region = [0xFFu8; SLOT_LEN * SLOT_COUNT];
        let mut dir = SlotDir::new();
        let mut blobs: Vec<(u32, heapless::Vec<u8, SLOT_LEN>), SLOT_COUNT> = Vec::new();
        for seq in 0..SLOT_COUNT as u32 {
            let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
            let mut w = RunWriter::start(sink, seq, seq * 60).expect("start");
            for t in 0..(seq * 17 + 1) {
                w.push_point(&TrackPoint {
                    lat_e7: t as i32,
                    lon_e7: 5,
                    t_offset_s: t,
                    ele_dm: None,
                    bpm: None,
                })
                .expect("push");
            }
            let blob = w.finalize(100, 90, 95).expect("finalize");
            let plan: SlotWrite =
                plan_slot_write(&mut dir, BASE, seq, seq * 60, blob.len()).expect("fits");
            let at = (plan.erase_from - BASE) as usize;
            region[at..at + blob.len()].copy_from_slice(&blob);
            dir.commit_written(plan.slot);
            blobs.push((seq, blob)).expect("fits");
        }

        let manifest = encode_manifest(&dir.manifest_at(10_000), 10_000);
        let (header, entries) = decode_manifest(&manifest).expect("decodes");
        assert_eq!(header.run_count as usize, SLOT_COUNT);

        for entry in entries.iter() {
            let mut pulled: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
            let mut cursor = 0u32;
            // The phone asks for more than one notification can carry every time.
            let want = chunk_notify_len(1024, NOTIFY_CAP);
            while let Some(plan) = plan_chunk_read(&dir, BASE, entry.run_seq, cursor, want) {
                assert!(plan.len <= NOTIFY_CAP as usize, "a reply fits one notify");
                let at = (plan.at - BASE) as usize;
                pulled
                    .extend_from_slice(&region[at..at + plan.len])
                    .expect("fits");
                cursor += plan.len as u32;
            }
            assert_eq!(cursor, entry.size, "pulled exactly the advertised size");
            assert!(chunk_completes_run(&dir, entry.run_seq, cursor));
            assert!(verify_blob(&pulled), "run {} verifies", entry.run_seq);
            let expected = blobs
                .iter()
                .find(|(seq, _)| *seq == entry.run_seq)
                .expect("known run");
            assert_eq!(&pulled[..], &expected.1[..]);
        }
    }

    #[test]
    fn a_manifest_entrys_offsets_address_its_own_slot() {
        // Cross-check the two halves agree: the size the manifest advertises for
        // a run and the offsets the chunk planner hands out for it must belong to
        // the same slot, or the phone would reassemble a neighbour's bytes.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            let plan = plan_slot_write(&mut dir, BASE, seq, 0, 1000 + seq as usize).expect("fits");
            dir.commit_written(plan.slot);
        }
        let manifest = encode_manifest(&dir.manifest(), 500);
        let (_, entries) = decode_manifest(&manifest).expect("decodes");
        for entry in entries.iter() {
            let (slot, size) = dir.find(entry.run_seq).expect("held");
            assert_eq!(entry.size, size);
            let first =
                plan_chunk_read(&dir, BASE, entry.run_seq, 0, NOTIFY_CAP).expect("in range");
            assert_eq!(first.at, slot_offset(BASE, slot));
            let last =
                plan_chunk_read(&dir, BASE, entry.run_seq, size - 1, NOTIFY_CAP).expect("in range");
            assert_eq!(last.len, 1);
            assert!(last.at < slot_offset(BASE, slot + 1));
        }
    }
}
