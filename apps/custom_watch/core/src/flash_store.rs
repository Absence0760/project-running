//! Tier-1 internal-flash run-store layout — the pure, host-tested half of the
//! `app/` flash driver (`app/src/run_flash.rs`).
//!
//! The nRF52840's 1 MB internal flash is tiny, so tier 1 reserves a small fixed
//! region of `SLOT_COUNT` equal-sized slots at the very top of flash, carved
//! out of both `app/memory.x` and `app/memory-ble.x`. Each finished run's blob
//! ([`crate::run_store`]) lives in one slot; a new run round-robins into the
//! next free slot, evicting the oldest when all are full. A full ultra needs
//! far more than this holds (see [`MAX_POINTS_PER_RUN`]) — that is the tier-2
//! external QSPI flash job, deliberately not solved here.
//!
//! Everything in this module is pure arithmetic plus a small in-RAM directory,
//! so it is `cargo test`-able on the host; the actual flash reads / erases /
//! writes live in the `app/` crate over embassy-nrf's NVMC.

use heapless::Vec;

use crate::run_store::{
    crc32, ManifestEntry, RunFooter, RunHeader, FOOTER_LEN, FORMAT_VERSION, HEADER_LEN, POINT_LEN,
};

/// One nRF52840 erase page (4 KiB) per run slot, so evicting a run is a single
/// page erase that never disturbs a neighbouring slot.
pub const SLOT_LEN: usize = 4096;

/// How many finished runs the tier-1 region holds at once.
pub const SLOT_COUNT: usize = 4;

/// Total reserved flash region. MUST equal the top-of-flash carve-out in BOTH
/// `app/memory.x` and `app/memory-ble.x`.
pub const REGION_LEN: usize = SLOT_LEN * SLOT_COUNT;

/// Track points that fit one slot: `HEADER + N*POINT + FOOTER <= SLOT_LEN`. At
/// roughly one accepted fix per second this is only a few minutes of a run —
/// the tier-1 internal-flash budget. A real ultra needs tier-2 external QSPI
/// flash; do not raise this to paper over that.
pub const MAX_POINTS_PER_RUN: u32 = ((SLOT_LEN - HEADER_LEN - FOOTER_LEN) / POINT_LEN) as u32;

/// Absolute flash offset of `slot` within a region beginning at `region_offset`.
pub const fn slot_offset(region_offset: u32, slot: usize) -> u32 {
    region_offset + (slot as u32) * (SLOT_LEN as u32)
}

/// Bytes to return for a phone chunk request: the smallest of what is left in
/// the blob from `offset`, the phone's `requested` length, and the notify
/// `mtu`. Zero once `offset` reaches (or passes) the blob end, so a request off
/// the end returns nothing rather than wrapping or over-reading.
pub fn chunk_len(size: u32, offset: u32, requested: u16, mtu: u16) -> u16 {
    if offset >= size {
        return 0;
    }
    let remaining = size - offset;
    remaining.min(requested as u32).min(mtu as u32) as u16
}

/// A finished run recovered from one slot's raw flash bytes at boot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RecoveredRun {
    pub run_seq: u32,
    pub size: u32,
    pub start_uptime_s: u32,
}

/// Recover the finished run persisted in one slot's raw flash bytes, or `None`
/// if the slot is erased, holds an unrecognised / newer-format blob, or holds
/// only a never-finalised (power-lost mid-run) blob — matching the manifest's
/// "unfinished blobs are never advertised" contract.
///
/// The blob does not store its own length, so the footer position is found by
/// scanning each point-aligned offset for the footer magic *and* a CRC32 that
/// verifies the header+points prefix. The CRC is what makes this safe: a byte
/// sequence inside the track data that happens to equal the footer magic fails
/// the CRC check, so the scan reads past it to the real footer. (A false early
/// stop would need a genuine CRC32 collision at a point boundary.)
pub fn recover_slot(bytes: &[u8]) -> Option<RecoveredRun> {
    let header = RunHeader::decode(bytes)?;
    if header.version != FORMAT_VERSION {
        return None;
    }
    for n in 0..=MAX_POINTS_PER_RUN {
        let footer_at = HEADER_LEN + n as usize * POINT_LEN;
        if footer_at + FOOTER_LEN > bytes.len() {
            break;
        }
        if let Some(footer) = RunFooter::decode(&bytes[footer_at..]) {
            if crc32(&bytes[..footer_at]) == footer.crc32 {
                return Some(RecoveredRun {
                    run_seq: header.run_seq,
                    size: (footer_at + FOOTER_LEN) as u32,
                    start_uptime_s: header.start_uptime_s,
                });
            }
        }
    }
    None
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SlotMeta {
    run_seq: u32,
    size: u32,
    start_uptime_s: u32,
}

/// In-RAM index of which slot holds which committed run.
///
/// Rebuilt each boot by [`from_recovered`](Self::from_recovered) scanning every
/// slot's flash bytes with [`recover_slot`], so a run recorded in a prior power
/// cycle is re-advertised rather than lost until overwritten. Run ids
/// (`run_seq`) are assigned by the caller (the `record` task), which is the
/// single writer and resumes numbering from [`next_run_seq`](Self::next_run_seq)
/// so a fresh run can't collide with a recovered one; new runs are recorded at
/// [`place`](Self::place).
pub struct SlotDir {
    slots: [Option<SlotMeta>; SLOT_COUNT],
}

impl Default for SlotDir {
    fn default() -> Self {
        Self::new()
    }
}

impl SlotDir {
    pub const fn new() -> Self {
        Self {
            slots: [None; SLOT_COUNT],
        }
    }

    /// Rebuild the directory from what each physical slot actually holds on
    /// flash at boot (each entry the result of [`recover_slot`] on that slot),
    /// so a run recorded in a prior power cycle is advertised again instead of
    /// being lost until its slot is overwritten. Each recovered run keeps ITS
    /// OWN slot index — not round-robined — so [`find`](Self::find) maps it back
    /// to the flash offset its bytes physically occupy.
    pub fn from_recovered(slots: [Option<RecoveredRun>; SLOT_COUNT]) -> Self {
        let mut dir = Self::new();
        for (i, r) in slots.into_iter().enumerate() {
            dir.slots[i] = r.map(|r| SlotMeta {
                run_seq: r.run_seq,
                size: r.size,
                start_uptime_s: r.start_uptime_s,
            });
        }
        dir
    }

    /// The `run_seq` a freshly-started run should take so it never collides with
    /// a recovered run: one past the highest seq currently on flash, else 0.
    /// The record task seeds its counter with this at boot; because eviction
    /// picks the lowest seq, resuming above the max keeps recovered (older) runs
    /// as the first evicted.
    pub fn next_run_seq(&self) -> u32 {
        self.slots
            .iter()
            .flatten()
            .map(|m| m.run_seq)
            .max()
            .map_or(0, |s| s.wrapping_add(1))
    }

    /// Choose the slot a freshly-committed run occupies — the first free slot,
    /// else the oldest (lowest `run_seq`) — record its metadata, and return the
    /// slot index so the caller knows where to write in flash.
    pub fn place(&mut self, run_seq: u32, size: u32, start_uptime_s: u32) -> usize {
        let slot = self.victim();
        self.slots[slot] = Some(SlotMeta {
            run_seq,
            size,
            start_uptime_s,
        });
        slot
    }

    fn victim(&self) -> usize {
        for (i, s) in self.slots.iter().enumerate() {
            if s.is_none() {
                return i;
            }
        }
        // All full: evict the lowest seq (the oldest committed run).
        let mut oldest = 0;
        for i in 1..SLOT_COUNT {
            if self.slots[i].map(|m| m.run_seq) < self.slots[oldest].map(|m| m.run_seq) {
                oldest = i;
            }
        }
        oldest
    }

    /// Drop a slot's record — used when the flash write for it failed, so the
    /// manifest never advertises a run that is not actually on flash.
    pub fn forget(&mut self, slot: usize) {
        if slot < SLOT_COUNT {
            self.slots[slot] = None;
        }
    }

    pub fn run_count(&self) -> u8 {
        self.slots.iter().filter(|s| s.is_some()).count() as u8
    }

    /// Manifest entries for every committed run, in slot order.
    pub fn manifest(&self) -> Vec<ManifestEntry, SLOT_COUNT> {
        let mut out = Vec::new();
        for s in self.slots.iter().flatten() {
            let _ = out.push(ManifestEntry {
                run_seq: s.run_seq,
                size: s.size,
                start_uptime_s: s.start_uptime_s,
            });
        }
        out
    }

    /// Locate a committed run by its id → `(slot index, blob size)`.
    pub fn find(&self, run_seq: u32) -> Option<(usize, u32)> {
        self.slots
            .iter()
            .enumerate()
            .find_map(|(i, s)| s.and_then(|m| (m.run_seq == run_seq).then_some((i, m.size))))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::run_store::{blob_len, RunWriter, TrackPoint, RUN_MAGIC};

    /// Build a full 4 KiB slot image: a finished run's blob followed by erased
    /// (0xFF) flash, exactly what a committed-then-power-cycled slot looks like.
    fn slot_image(run_seq: u32, start_uptime_s: u32, points: &[TrackPoint]) -> [u8; SLOT_LEN] {
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
        for p in points {
            w.push_point(p).expect("push");
        }
        let blob = w.finalize(1234, 600, 620).expect("finalize");
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..blob.len()].copy_from_slice(&blob);
        slot
    }

    fn a_point(t: u32) -> TrackPoint {
        TrackPoint {
            lat_e7: 400_150_200 + t as i32,
            lon_e7: -1_052_705_000,
            t_offset_s: t,
            ele_dm: Some(16_240),
            bpm: Some(120),
        }
    }

    #[test]
    fn max_points_blob_fits_one_slot() {
        assert_eq!(MAX_POINTS_PER_RUN, 253);
        assert!(blob_len(MAX_POINTS_PER_RUN) as usize <= SLOT_LEN);
        // One more point would overflow the slot.
        assert!(blob_len(MAX_POINTS_PER_RUN + 1) as usize > SLOT_LEN);
    }

    #[test]
    fn slot_offsets_are_page_spaced_within_the_region() {
        let base = 0x000F_C000;
        assert_eq!(slot_offset(base, 0), base);
        assert_eq!(slot_offset(base, 1), base + SLOT_LEN as u32);
        assert_eq!(slot_offset(base, 3), base + 3 * SLOT_LEN as u32);
        // The last slot still ends inside the region.
        assert_eq!(
            slot_offset(base, SLOT_COUNT - 1) + SLOT_LEN as u32,
            base + REGION_LEN as u32
        );
    }

    #[test]
    fn chunk_len_clamps_to_the_smallest_bound() {
        // Well inside the blob: the request is honoured.
        assert_eq!(chunk_len(1000, 0, 244, 244), 244);
        // Near the end: clamped to what remains.
        assert_eq!(chunk_len(1000, 900, 244, 244), 100);
        // The MTU is the smallest bound.
        assert_eq!(chunk_len(1000, 0, 244, 20), 20);
        // The request is the smallest bound.
        assert_eq!(chunk_len(1000, 0, 8, 244), 8);
    }

    #[test]
    fn chunk_len_is_zero_at_or_past_the_end() {
        assert_eq!(chunk_len(1000, 1000, 244, 244), 0);
        assert_eq!(chunk_len(1000, 1001, 244, 244), 0);
        assert_eq!(chunk_len(0, 0, 244, 244), 0);
    }

    #[test]
    fn place_fills_free_slots_in_order_then_evicts_oldest() {
        let mut dir = SlotDir::new();
        assert_eq!(dir.place(0, 100, 10), 0);
        assert_eq!(dir.place(1, 100, 11), 1);
        assert_eq!(dir.place(2, 100, 12), 2);
        assert_eq!(dir.place(3, 100, 13), 3);
        assert_eq!(dir.run_count(), 4);
        // Region full → the lowest-seq run (0, in slot 0) is evicted.
        assert_eq!(dir.place(4, 100, 14), 0);
        assert_eq!(dir.run_count(), 4);
        assert_eq!(dir.find(0), None, "evicted run is gone");
        assert_eq!(dir.find(4), Some((0, 100)));
        assert_eq!(dir.find(1), Some((1, 100)));
    }

    #[test]
    fn manifest_lists_every_committed_run() {
        let mut dir = SlotDir::new();
        dir.place(7, blob_len(3), 41);
        dir.place(8, blob_len(5), 700);
        let m = dir.manifest();
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].run_seq, 7);
        assert_eq!(m[0].size, blob_len(3));
        assert_eq!(m[0].start_uptime_s, 41);
        assert_eq!(m[1].run_seq, 8);
    }

    #[test]
    fn forget_removes_a_slot_from_the_directory() {
        let mut dir = SlotDir::new();
        let slot = dir.place(7, 100, 41);
        assert_eq!(dir.find(7), Some((slot, 100)));
        dir.forget(slot);
        assert_eq!(dir.find(7), None);
        assert_eq!(dir.run_count(), 0);
        // The freed slot is reused first.
        assert_eq!(dir.place(9, 200, 50), slot);
    }

    #[test]
    fn recover_slot_reads_back_a_finished_run() {
        let pts = [a_point(0), a_point(1), a_point(2)];
        let slot = slot_image(7, 41, &pts);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 7,
                size: blob_len(3),
                start_uptime_s: 41,
            }),
            "the footer is found past the erased 0xFF tail and the size is the blob, not the slot"
        );
    }

    #[test]
    fn recover_slot_reads_back_the_max_length_run() {
        let pts: heapless::Vec<TrackPoint, { MAX_POINTS_PER_RUN as usize }> =
            (0..MAX_POINTS_PER_RUN).map(a_point).collect();
        let slot = slot_image(3, 9, &pts);
        let r = recover_slot(&slot).expect("max-length run recovers");
        assert_eq!(r.run_seq, 3);
        assert_eq!(r.size, blob_len(MAX_POINTS_PER_RUN));
    }

    #[test]
    fn recover_slot_rejects_an_erased_slot() {
        assert_eq!(recover_slot(&[0xFFu8; SLOT_LEN]), None);
        assert_eq!(recover_slot(&[0x00u8; SLOT_LEN]), None);
    }

    #[test]
    fn recover_slot_rejects_a_never_finalised_blob() {
        // Header + points but no footer (power lost mid-run): the tail past the
        // points is erased 0xFF, so no footer magic + CRC ever matches.
        let mut staged: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        staged
            .extend_from_slice(
                &RunHeader {
                    version: FORMAT_VERSION,
                    flags: 0,
                    run_seq: 5,
                    start_uptime_s: 12,
                }
                .encode(),
            )
            .unwrap();
        for t in 0..4 {
            staged.extend_from_slice(&a_point(t).encode()).unwrap();
        }
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..staged.len()].copy_from_slice(&staged);
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_rejects_a_newer_format_version() {
        let mut slot = slot_image(7, 41, &[a_point(0)]);
        slot[4] = FORMAT_VERSION + 1; // header version byte
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_reads_past_footer_magic_inside_point_data() {
        // A track point whose first bytes equal the footer magic "END1" must not
        // fool the scan: the CRC at that offset won't match, so recovery reads
        // on to the real footer. lat_e7's LE bytes are the point's first four.
        let magic_lat = i32::from_le_bytes(*b"END1");
        let sneaky = TrackPoint {
            lat_e7: magic_lat,
            lon_e7: 5,
            t_offset_s: 0,
            ele_dm: None,
            bpm: None,
        };
        let pts = [sneaky, a_point(1), a_point(2)];
        let slot = slot_image(21, 8, &pts);
        // Sanity: the decoy footer magic really is sitting at the point-0 offset.
        assert_eq!(&slot[HEADER_LEN..HEADER_LEN + 4], b"END1");
        let r = recover_slot(&slot).expect("recovers despite the decoy magic");
        assert_eq!(r.run_seq, 21);
        assert_eq!(r.size, blob_len(3), "found the real footer, not the decoy");
    }

    #[test]
    fn from_recovered_places_runs_at_their_own_slots() {
        let mut recovered = [None; SLOT_COUNT];
        recovered[0] = Some(RecoveredRun {
            run_seq: 5,
            size: blob_len(3),
            start_uptime_s: 40,
        });
        recovered[2] = Some(RecoveredRun {
            run_seq: 9,
            size: blob_len(7),
            start_uptime_s: 900,
        });
        let dir = SlotDir::from_recovered(recovered);
        assert_eq!(dir.run_count(), 2);
        // Each run maps back to the physical slot its bytes occupy.
        assert_eq!(dir.find(5), Some((0, blob_len(3))));
        assert_eq!(dir.find(9), Some((2, blob_len(7))));
        let m = dir.manifest();
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].run_seq, 5);
        assert_eq!(m[1].run_seq, 9);
    }

    #[test]
    fn next_run_seq_resumes_past_the_highest_recovered() {
        assert_eq!(SlotDir::new().next_run_seq(), 0);
        let mut recovered = [None; SLOT_COUNT];
        recovered[0] = Some(RecoveredRun {
            run_seq: 5,
            size: 100,
            start_uptime_s: 40,
        });
        recovered[3] = Some(RecoveredRun {
            run_seq: 9,
            size: 100,
            start_uptime_s: 90,
        });
        let dir = SlotDir::from_recovered(recovered);
        assert_eq!(dir.next_run_seq(), 10);
    }

    #[test]
    fn a_new_run_after_recovery_evicts_the_oldest_recovered() {
        // All four slots recovered with seqs 0..=3; a fresh run resumes at 4 and,
        // the region being full, evicts the lowest seq (the oldest recovered).
        let recovered = [
            Some(RecoveredRun {
                run_seq: 0,
                size: 100,
                start_uptime_s: 1,
            }),
            Some(RecoveredRun {
                run_seq: 1,
                size: 100,
                start_uptime_s: 2,
            }),
            Some(RecoveredRun {
                run_seq: 2,
                size: 100,
                start_uptime_s: 3,
            }),
            Some(RecoveredRun {
                run_seq: 3,
                size: 100,
                start_uptime_s: 4,
            }),
        ];
        let mut dir = SlotDir::from_recovered(recovered);
        let seq = dir.next_run_seq();
        assert_eq!(seq, 4);
        assert_eq!(dir.place(seq, 200, 5), 0, "evicts slot 0 (seq 0)");
        assert_eq!(dir.find(0), None);
        assert_eq!(dir.find(4), Some((0, 200)));
    }

    #[test]
    fn recover_ignores_a_zeroed_magic() {
        // Guard that recovery keys on the magic, not just non-erased bytes.
        assert_ne!(RUN_MAGIC, [0u8; 4]);
    }
}
