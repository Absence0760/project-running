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

use crate::run_store::{ManifestEntry, FOOTER_LEN, HEADER_LEN, POINT_LEN};

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SlotMeta {
    run_seq: u32,
    size: u32,
    start_uptime_s: u32,
}

/// In-RAM index of which slot holds which committed run.
///
/// Rebuilt each boot — tier 1 does not scan flash headers on power-up (a
/// documented limitation), so the directory advertises only runs recorded this
/// power cycle even though their blobs survive in flash. Run ids (`run_seq`)
/// are assigned by the caller (the `record` task), which is the single writer;
/// this directory just records what it is told at [`place`](Self::place).
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
    use crate::run_store::blob_len;

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
}
