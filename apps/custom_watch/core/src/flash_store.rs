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

/// One nRF52840 erase page reserved for the tiny persisted-config record, sat
/// immediately BELOW the run-store region (its absolute offset is one page under
/// [`crate::run_flash::REGION_OFFSET`] — see `app/src/run_flash::CONFIG_OFFSET`).
/// A dedicated page keeps a config rewrite — a single page erase — from ever
/// touching a run slot, and leaves every run-store slot offset undisturbed.
/// MUST match the config carve-out in BOTH `app/memory.x` and `app/memory-ble.x`.
pub const CONFIG_LEN: usize = SLOT_LEN;

/// Length of the fixed config record written at the base of the config page. A
/// multiple of the NVMC 4-byte write word, so it commits in one write.
pub const CONFIG_RECORD_LEN: usize = 12;

/// Version of the config-record wire format. Bumped only if the field layout
/// after the magic changes; an unrecognised version reads as "no saved config".
pub const CONFIG_VERSION: u8 = 1;

/// Magic prefixing a valid config record — distinguishes a written record from
/// an erased (all-`0xFF`) or zeroed page.
const CONFIG_MAGIC: [u8; 4] = *b"CFG1";

/// Encode the persisted-config record — `magic | version | gnss_mode | 0 0 |
/// crc32` — for the flash config page. The CRC covers every byte before it, so a
/// torn, erased, or garbage page fails [`decode_config`] and the caller falls
/// back to defaults (same fail-closed rule as [`recover_slot`]).
pub fn encode_config(gnss_mode: u8) -> [u8; CONFIG_RECORD_LEN] {
    let mut buf = [0u8; CONFIG_RECORD_LEN];
    buf[0..4].copy_from_slice(&CONFIG_MAGIC);
    buf[4] = CONFIG_VERSION;
    buf[5] = gnss_mode;
    // buf[6..8] reserved, left zero (still CRC-covered).
    let crc = crc32(&buf[0..8]);
    buf[8..12].copy_from_slice(&crc.to_le_bytes());
    buf
}

/// Decode the persisted-config record, returning the stored `gnss_mode` byte, or
/// `None` when the bytes are too short, carry the wrong magic or version, or fail
/// the CRC — an erased or corrupt page reads as "no saved config". The mode byte
/// itself is validated by the caller ([`crate::gnss_mode::GnssMode::from_byte`]),
/// so a CRC-valid but unknown byte still falls back to the default.
pub fn decode_config(bytes: &[u8]) -> Option<u8> {
    if bytes.len() < CONFIG_RECORD_LEN {
        return None;
    }
    if bytes[0..4] != CONFIG_MAGIC {
        return None;
    }
    if bytes[4] != CONFIG_VERSION {
        return None;
    }
    let stored = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);
    if crc32(&bytes[0..8]) != stored {
        return None;
    }
    Some(bytes[5])
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
    /// The phone has pulled this run's whole blob. Eviction sacrifices a synced
    /// run before a still-unsynced one, so a finished-but-unsynced run is not
    /// silently overwritten. RAM-only — not persisted across a reboot (that is a
    /// wire-format v2 job), so a run recovered from a prior power cycle starts
    /// unsynced and is protected until the phone re-pulls it.
    synced: bool,
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
                synced: false,
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
            synced: false,
        });
        slot
    }

    /// Mark a committed run as fully pulled by the phone, so [`place`](Self::place)
    /// evicts it before a still-unsynced run. No-op if the id isn't held.
    pub fn mark_synced(&mut self, run_seq: u32) {
        for s in self.slots.iter_mut().flatten() {
            if s.run_seq == run_seq {
                s.synced = true;
            }
        }
    }

    /// Reserve or reuse the slot holding `run_seq`. If a prior mid-run
    /// checkpoint already placed this run, reuse ITS slot (updating the recorded
    /// size) so a checkpoint and the final commit target the same page and the
    /// commit supersedes the checkpoint; otherwise choose a fresh slot exactly
    /// like [`place`](Self::place).
    pub fn place_or_update(&mut self, run_seq: u32, size: u32, start_uptime_s: u32) -> usize {
        if let Some((slot, _)) = self.find(run_seq) {
            self.slots[slot] = Some(SlotMeta {
                run_seq,
                size,
                start_uptime_s,
                synced: false,
            });
            slot
        } else {
            self.place(run_seq, size, start_uptime_s)
        }
    }

    fn victim(&self) -> usize {
        for (i, s) in self.slots.iter().enumerate() {
            if s.is_none() {
                return i;
            }
        }
        // All full. Evict the oldest SYNCED run (lowest seq the phone has already
        // pulled) so a finished-but-unsynced run is never silently overwritten
        // while any synced run still occupies a slot.
        let mut synced_victim: Option<(usize, u32)> = None;
        for (i, m) in self
            .slots
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.map(|m| (i, m)))
        {
            if m.synced && synced_victim.is_none_or(|(_, seq)| m.run_seq < seq) {
                synced_victim = Some((i, m.run_seq));
            }
        }
        if let Some((i, _)) = synced_victim {
            return i;
        }
        // Nothing synced: fall back to the oldest run overall — the region can't
        // hold more than SLOT_COUNT, so an unsynced run must go. Best-effort.
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
        self.manifest_at(u32::MAX)
    }

    /// Manifest entries with each run's `start_uptime_s` clamped to the current
    /// `watch_uptime_s`.
    ///
    /// The watch has no RTC, so the phone dates a run as
    /// `now - (watch_uptime_s - start_uptime_s)`. A run recovered from a PRIOR
    /// power cycle carries a `start_uptime_s` from that boot's epoch, which can
    /// exceed the current (post-reboot) uptime and date the run in the FUTURE.
    /// Clamping `start_uptime_s <= watch_uptime_s` makes the offset non-negative,
    /// so a recovered run reads as "around this power-on" (under-aged) rather than
    /// in the future. Precise wall-clock dating of a prior-boot run needs the
    /// phone to fall back to the footer's elapsed time — a phone-side follow-up.
    pub fn manifest_at(&self, watch_uptime_s: u32) -> Vec<ManifestEntry, SLOT_COUNT> {
        let mut out = Vec::new();
        for s in self.slots.iter().flatten() {
            let _ = out.push(ManifestEntry {
                run_seq: s.run_seq,
                size: s.size,
                start_uptime_s: s.start_uptime_s.min(watch_uptime_s),
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
    use crate::run_store::{blob_len, verify_blob, RunWriter, TrackPoint, RUN_MAGIC};

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
    fn place_or_update_reuses_the_slot_for_an_existing_run() {
        // The first checkpoint places the run; later checkpoints + the final
        // commit must land in the SAME slot so the commit supersedes rather than
        // leaving a stale checkpoint in another slot.
        let mut dir = SlotDir::new();
        let s0 = dir.place_or_update(7, 100, 41);
        let s1 = dir.place_or_update(7, 260, 41); // grew as more points staged
        assert_eq!(s0, s1, "same run reuses its slot");
        assert_eq!(dir.find(7), Some((s0, 260)), "size updated in place");
        assert_eq!(dir.run_count(), 1, "no second slot consumed");

        // A different run still takes a fresh slot.
        let s2 = dir.place_or_update(8, 100, 50);
        assert_ne!(s2, s0);
        assert_eq!(dir.run_count(), 2);
    }

    #[test]
    fn place_or_update_matches_place_for_a_brand_new_run() {
        let mut a = SlotDir::new();
        let mut b = SlotDir::new();
        assert_eq!(a.place_or_update(3, 100, 10), b.place(3, 100, 10));
        assert_eq!(a.find(3), b.find(3));
    }

    #[test]
    fn recover_slot_reads_back_a_checkpoint_blob_as_a_partial_run() {
        // A mid-run checkpoint (partial track + totals-so-far) written into a
        // slot and power-cycled recovers exactly like a finished run — the whole
        // point of checkpointing: a reset mid-run recovers a slightly-stale
        // partial run instead of nothing.
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, 9, 77).expect("start");
        for t in 0..5 {
            w.push_point(&a_point(t)).expect("push");
        }
        let ckpt = w.checkpoint_blob(321, 200, 210).expect("checkpoint");
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..ckpt.len()].copy_from_slice(&ckpt);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 9,
                size: blob_len(5),
                start_uptime_s: 77,
            }),
            "the partial run recovers with the totals-so-far"
        );
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

    /// A CRC-internally-consistent blob at an arbitrary header `version`, so a
    /// test can present exactly what a future firmware would write: a valid
    /// footer whose CRC covers a header carrying a version we don't understand.
    fn slot_image_version(
        version: u8,
        run_seq: u32,
        start_uptime_s: u32,
        points: &[TrackPoint],
    ) -> [u8; SLOT_LEN] {
        let mut prefix: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        prefix
            .extend_from_slice(
                &RunHeader {
                    version,
                    flags: 0,
                    run_seq,
                    start_uptime_s,
                }
                .encode(),
            )
            .unwrap();
        for p in points {
            prefix.extend_from_slice(&p.encode()).unwrap();
        }
        let footer = RunFooter {
            distance_m: 1234,
            moving_s: 600,
            elapsed_s: 620,
            crc32: crc32(&prefix),
        }
        .encode();
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..prefix.len()].copy_from_slice(&prefix);
        slot[prefix.len()..prefix.len() + FOOTER_LEN].copy_from_slice(&footer);
        slot
    }

    #[test]
    fn recover_slot_reads_past_a_mid_track_decoy_magic() {
        // The decoy magic sits mid-run, not at point 0: the scan must still walk
        // past it (CRC mismatch there) and land on the true footer at the end.
        let sneaky = TrackPoint {
            lat_e7: i32::from_le_bytes(*b"END1"),
            lon_e7: 5,
            t_offset_s: 2,
            ele_dm: None,
            bpm: None,
        };
        let pts = [a_point(0), a_point(1), sneaky, a_point(3), a_point(4)];
        let slot = slot_image(30, 8, &pts);
        assert_eq!(
            &slot[HEADER_LEN + 2 * POINT_LEN..HEADER_LEN + 2 * POINT_LEN + 4],
            b"END1",
            "the decoy magic is planted at the point-2 boundary"
        );
        let r = recover_slot(&slot).expect("recovers past the mid-track decoy");
        assert_eq!(r.run_seq, 30);
        assert_eq!(r.size, blob_len(5), "found the real footer, not the decoy");
    }

    #[test]
    fn recover_slot_reads_past_a_decoy_magic_in_the_last_point() {
        // Nastiest placement: the decoy is the LAST point, so its would-be CRC
        // field overlaps the true footer's own magic bytes. The CRC still fails
        // there and the true footer one point later wins.
        let sneaky = TrackPoint {
            lat_e7: i32::from_le_bytes(*b"END1"),
            lon_e7: 9,
            t_offset_s: 2,
            ele_dm: None,
            bpm: None,
        };
        let pts = [a_point(0), a_point(1), sneaky];
        let slot = slot_image(31, 8, &pts);
        assert_eq!(
            &slot[HEADER_LEN + 2 * POINT_LEN..HEADER_LEN + 2 * POINT_LEN + 4],
            b"END1"
        );
        let r = recover_slot(&slot).expect("recovers past the last-point decoy");
        assert_eq!(r.run_seq, 31);
        assert_eq!(r.size, blob_len(3));
    }

    #[test]
    fn recover_slot_rejects_a_crc_valid_newer_version_blob() {
        // A future firmware writes a v2 blob with an internally-correct CRC. The
        // version gate must reject it BEFORE the footer scan — the CRC being
        // valid is exactly why this can't lean on CRC failure to filter it.
        let pts = [a_point(0), a_point(1)];
        let newer = slot_image_version(FORMAT_VERSION + 1, 7, 41, &pts);
        assert!(
            verify_blob(&newer[..blob_len(2) as usize]),
            "the v2 CRC is valid"
        );
        assert_eq!(recover_slot(&newer), None, "rejected by the version gate");

        // Same builder at the understood version DOES recover, so the version is
        // the only thing that changed and the gate is what rejected the newer one.
        let ours = slot_image_version(FORMAT_VERSION, 7, 41, &pts);
        assert_eq!(
            recover_slot(&ours),
            Some(RecoveredRun {
                run_seq: 7,
                size: blob_len(2),
                start_uptime_s: 41,
            })
        );
    }

    #[test]
    fn recover_slot_rejects_a_half_written_header() {
        // Only the magic landed before power loss; the rest of the page is still
        // erased, so the version byte reads 0xFF and fails the gate.
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..4].copy_from_slice(&RUN_MAGIC);
        assert_eq!(recover_slot(&slot), None);

        // A fully-written header with nothing after it (zero points, no footer)
        // is a never-finalised slot and recovers nothing.
        let mut slot = [0xFFu8; SLOT_LEN];
        slot[..HEADER_LEN].copy_from_slice(
            &RunHeader {
                version: FORMAT_VERSION,
                flags: 0,
                run_seq: 2,
                start_uptime_s: 9,
            }
            .encode(),
        );
        assert_eq!(recover_slot(&slot), None);
    }

    #[test]
    fn recover_slot_never_reads_out_of_bounds_on_a_short_slice() {
        // Slices too short to hold a header, or a header but no room for a
        // footer, must return None without panicking or over-reading.
        assert_eq!(recover_slot(&[]), None);
        assert_eq!(recover_slot(&[0xFFu8; 8]), None);
        assert_eq!(recover_slot(&[0xFFu8; HEADER_LEN]), None);

        let header = RunHeader {
            version: FORMAT_VERSION,
            flags: 0,
            run_seq: 1,
            start_uptime_s: 3,
        }
        .encode();
        // Header exactly, no bytes for a footer: the loop breaks on the first n.
        assert_eq!(recover_slot(&header), None);

        // Header + a footer magic but the footer itself is truncated (10 of 20
        // bytes). The `footer_at + FOOTER_LEN > len` guard must skip the decode
        // rather than slice past the end.
        let mut truncated: heapless::Vec<u8, 64> = heapless::Vec::new();
        truncated.extend_from_slice(&header).unwrap();
        truncated.extend_from_slice(b"END1123456").unwrap();
        assert_eq!(recover_slot(&truncated), None);
    }

    #[test]
    fn recover_slot_reads_back_a_zero_point_run() {
        // Header + footer, no points: the footer sits at n == 0.
        let slot = slot_image(4, 15, &[]);
        assert_eq!(
            recover_slot(&slot),
            Some(RecoveredRun {
                run_seq: 4,
                size: blob_len(0),
                start_uptime_s: 15,
            })
        );
    }

    #[test]
    fn next_run_seq_with_a_full_directory_resumes_above_the_max() {
        // Four recovered runs whose seqs are out of slot order: the next id is
        // one past the maximum, never one past slot 3's or the count.
        let recovered = [
            Some(RecoveredRun {
                run_seq: 12,
                size: 100,
                start_uptime_s: 1,
            }),
            Some(RecoveredRun {
                run_seq: 7,
                size: 100,
                start_uptime_s: 2,
            }),
            Some(RecoveredRun {
                run_seq: 30,
                size: 100,
                start_uptime_s: 3,
            }),
            Some(RecoveredRun {
                run_seq: 3,
                size: 100,
                start_uptime_s: 4,
            }),
        ];
        let dir = SlotDir::from_recovered(recovered);
        assert_eq!(dir.run_count(), 4);
        assert_eq!(dir.next_run_seq(), 31);
    }

    #[test]
    fn config_round_trips_every_mode_byte() {
        for mode in [0u8, 1, 2] {
            let rec = encode_config(mode);
            assert_eq!(rec.len(), CONFIG_RECORD_LEN);
            assert_eq!(decode_config(&rec), Some(mode));
        }
    }

    #[test]
    fn config_record_is_write_word_aligned_and_page_sized() {
        // NVMC writes a 4-byte word; the record must be a whole number of them,
        // and it must fit inside the one reserved erase page.
        assert_eq!(CONFIG_RECORD_LEN % 4, 0);
        assert!(CONFIG_RECORD_LEN <= CONFIG_LEN);
        assert_eq!(CONFIG_LEN, SLOT_LEN, "config page is one erase page");
    }

    #[test]
    fn decode_config_rejects_an_erased_or_zeroed_page() {
        assert_eq!(decode_config(&[0xFFu8; CONFIG_LEN]), None);
        assert_eq!(decode_config(&[0x00u8; CONFIG_LEN]), None);
    }

    #[test]
    fn decode_config_rejects_a_corrupt_crc() {
        // Flip the stored mode byte without recomputing the CRC — exactly a
        // single-bit flash bit-rot — and the record must read as absent.
        let mut rec = encode_config(2);
        rec[5] ^= 0xFF;
        assert_eq!(decode_config(&rec), None);
        // Corrupting a CRC-covered reserved byte is caught too.
        let mut rec = encode_config(1);
        rec[6] ^= 0x01;
        assert_eq!(decode_config(&rec), None);
    }

    #[test]
    fn decode_config_rejects_wrong_magic_and_version() {
        let mut rec = encode_config(1);
        rec[0] = b'X';
        assert_eq!(decode_config(&rec), None);
        let mut rec = encode_config(1);
        rec[4] = CONFIG_VERSION + 1;
        assert_eq!(decode_config(&rec), None);
    }

    #[test]
    fn decode_config_never_reads_out_of_bounds_on_a_short_slice() {
        assert_eq!(decode_config(&[]), None);
        assert_eq!(decode_config(&[0xFFu8; 4]), None);
        let rec = encode_config(0);
        assert_eq!(decode_config(&rec[..CONFIG_RECORD_LEN - 1]), None);
    }

    #[test]
    fn eviction_picks_the_lowest_seq_regardless_of_slot_index() {
        // The oldest run (lowest seq) is NOT in slot 0, so this proves eviction
        // keys on seq, not on a slot-0 bias.
        let recovered = [
            Some(RecoveredRun {
                run_seq: 3,
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
                run_seq: 0,
                size: 100,
                start_uptime_s: 4,
            }),
        ];
        let mut dir = SlotDir::from_recovered(recovered);
        let seq = dir.next_run_seq();
        assert_eq!(seq, 4);
        assert_eq!(dir.place(seq, 200, 5), 3, "evicts slot 3 (seq 0)");
        assert_eq!(dir.find(0), None);
        assert_eq!(dir.find(4), Some((3, 200)));
    }

    #[test]
    fn eviction_sacrifices_a_synced_run_before_an_unsynced_one() {
        // Four runs, seqs 0..=3. The oldest (seq 0) is UNSYNCED; a newer run
        // (seq 2) has been fully pulled by the phone. A fifth run must evict the
        // synced seq 2, NOT the older-but-unsynced seq 0.
        let mut dir = SlotDir::new();
        dir.place(0, 100, 10);
        dir.place(1, 100, 11);
        dir.place(2, 100, 12);
        dir.place(3, 100, 13);
        dir.mark_synced(2);
        assert_eq!(
            dir.place(4, 100, 14),
            2,
            "evicts the synced run, not the oldest"
        );
        assert_eq!(dir.find(2), None, "the synced run was the victim");
        assert_eq!(
            dir.find(0),
            Some((0, 100)),
            "the unsynced oldest run survives"
        );
        assert_eq!(dir.find(4), Some((2, 100)));
    }

    #[test]
    fn eviction_prefers_the_oldest_synced_run() {
        // Two synced runs (seqs 1 and 3): eviction picks the lower-seq synced one.
        let mut dir = SlotDir::new();
        for seq in 0..4 {
            dir.place(seq, 100, seq);
        }
        dir.mark_synced(3);
        dir.mark_synced(1);
        assert_eq!(
            dir.place(4, 100, 14),
            1,
            "lowest-seq synced run is the victim"
        );
        assert_eq!(dir.find(1), None);
        assert_eq!(
            dir.find(3),
            Some((3, 100)),
            "the newer synced run survives this round"
        );
    }

    #[test]
    fn eviction_falls_back_to_oldest_when_nothing_is_synced() {
        // With no synced run to sacrifice, the region is physically full, so the
        // oldest (lowest-seq) run must go — the unchanged best-effort fallback.
        let mut dir = SlotDir::new();
        for seq in 0..4 {
            dir.place(seq, 100, seq);
        }
        assert_eq!(dir.place(4, 100, 14), 0, "no synced run → evict the oldest");
        assert_eq!(dir.find(0), None);
    }

    #[test]
    fn recovered_runs_start_unsynced_and_are_protected() {
        // A run recovered from a prior power cycle carries no synced bit, so it
        // is protected: a fresh run can't evict it while it stays unsynced —
        // unless every slot is an unsynced recovered run (the fallback).
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
            None,
        ];
        let mut dir = SlotDir::from_recovered(recovered);
        // Slot 3 is free, so a new run fills it — nothing evicted.
        assert_eq!(dir.place(3, 100, 4), 3);
        // Now full and all unsynced: the next run falls back to the oldest.
        assert_eq!(dir.place(4, 100, 5), 0);
        assert_eq!(dir.find(0), None);
    }

    #[test]
    fn mark_synced_ignores_an_unknown_run() {
        let mut dir = SlotDir::new();
        dir.place(7, 100, 10);
        dir.mark_synced(999); // not held — no panic, no effect
        dir.place(8, 100, 11);
        dir.mark_synced(8); // 8 is the only synced run
        dir.place(9, 100, 12);
        dir.place(10, 100, 13);
        let slot_of_8 = dir.find(8).expect("8 is held").0;
        // Full: the synced run (8) is the victim, and the unknown mark_synced(999)
        // left seq 7 unsynced and therefore protected.
        assert_eq!(dir.place(11, 100, 14), slot_of_8);
        assert_eq!(dir.find(8), None);
        assert_eq!(
            dir.find(7),
            Some((0, 100)),
            "the unsynced oldest run survives"
        );
    }

    #[test]
    fn manifest_at_clamps_a_prior_boot_start_out_of_the_future() {
        // A run recovered from a prior boot carries start=3600; the post-reboot
        // uptime is only 100. Unclamped, the phone would date it in the future.
        let recovered = [
            Some(RecoveredRun {
                run_seq: 5,
                size: 200,
                start_uptime_s: 3600,
            }),
            None,
            None,
            None,
        ];
        let dir = SlotDir::from_recovered(recovered);
        // manifest_at clamps start to the current uptime → never > watch_uptime_s.
        let clamped = dir.manifest_at(100);
        assert_eq!(
            clamped[0].start_uptime_s, 100,
            "clamped to the current uptime"
        );
        // The unclamped manifest still carries the raw (prior-boot) start.
        assert_eq!(dir.manifest()[0].start_uptime_s, 3600);
    }

    #[test]
    fn manifest_at_leaves_a_same_session_start_untouched() {
        // A run recorded THIS session has start <= uptime, so the clamp is a no-op
        // and it dates correctly; only the future-dating recovered case is changed.
        let mut dir = SlotDir::new();
        dir.place(1, 100, 40);
        dir.place(2, 100, 900);
        let m = dir.manifest_at(1000);
        assert_eq!(m[0].start_uptime_s, 40);
        assert_eq!(m[1].start_uptime_s, 900);
    }
}
