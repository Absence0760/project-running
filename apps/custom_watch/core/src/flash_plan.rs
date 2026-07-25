//! Flash slot write / read planning — the pure decision half of the `app/`
//! run-store driver (`app/src/run_flash.rs`).
//!
//! [`crate::flash_store`] owns the slot layout and the in-RAM [`SlotDir`]; this
//! module owns the arithmetic the driver wraps around it: which slot a commit or
//! a mid-run checkpoint lands in and the exact erase + write range that implies,
//! where a phone chunk request reads from, whether that read hands the phone the
//! last of the blob, and rebuilding the directory from flash at boot.
//!
//! Nothing here touches a flash handle — the driver feeds bytes in through
//! [`SlotReader`] — so the reboot-recovery scan and every offset are host-tested
//! rather than only reasoned about. A bug in any of it silently destroys a
//! recorded run, and the `app/` crate cannot be host-tested at all.

use crate::flash_store::{self, chunk_len, RecoveredRun, SlotDir, SLOT_COUNT, SLOT_LEN};

/// The flash operation one run blob implies: erase the whole slot, then write
/// the blob at its base. Erasing the *whole* slot is what stops a stale tail of
/// a longer previous run surviving underneath a shorter new one, where the
/// footer scan in [`flash_store::recover_slot`] could find the old footer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SlotWrite {
    pub slot: usize,
    /// Erase start, and the offset the blob's first byte goes to.
    pub erase_from: u32,
    /// Erase end, exclusive.
    pub erase_to: u32,
}

/// Reserve the slot a run's blob belongs in — reusing the slot a prior
/// checkpoint of the SAME `run_seq` already holds, else the next free slot, else
/// an eviction victim — and return the erase + write range for it.
///
/// `None` when the blob is larger than one slot: the run is dropped whole rather
/// than truncated into a slot, and the directory is left untouched so an
/// oversized blob can never evict a run that is genuinely on flash.
pub fn plan_slot_write(
    dir: &mut SlotDir,
    region_offset: u32,
    run_seq: u32,
    start_uptime_s: u32,
    blob_len: usize,
) -> Option<SlotWrite> {
    if blob_len > SLOT_LEN {
        return None;
    }
    let slot = dir.place_or_update(run_seq, blob_len as u32, start_uptime_s);
    let erase_from = flash_store::slot_offset(region_offset, slot);
    Some(SlotWrite {
        slot,
        erase_from,
        erase_to: erase_from + SLOT_LEN as u32,
    })
}

/// Where one phone chunk request reads from, in absolute flash offsets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChunkRead {
    pub at: u32,
    pub len: usize,
}

/// Plan the flash read for a `run_chunk` request: locate the run's slot, clamp
/// the length to what is left of the blob and to `cap` (the caller's reply
/// buffer), and resolve the blob-relative offset to an absolute one.
///
/// `None` — an empty reply — when the run isn't held, `rel_offset` is at or past
/// the blob end, or `cap` is zero. Fail-closed by construction: a request past
/// the end reads nothing rather than wrapping into the next slot or spilling the
/// erased tail of its own slot back to the phone.
pub fn plan_chunk_read(
    dir: &SlotDir,
    region_offset: u32,
    run_seq: u32,
    rel_offset: u32,
    cap: u16,
) -> Option<ChunkRead> {
    let (slot, size) = dir.find(run_seq)?;
    let len = chunk_len(size, rel_offset, cap, cap);
    if len == 0 {
        return None;
    }
    Some(ChunkRead {
        at: flash_store::slot_offset(region_offset, slot) + rel_offset,
        len: len as usize,
    })
}

/// Whether the phone's read cursor after a served chunk (`next_offset`) has
/// reached the end of run `run_seq`'s blob — the point the run counts as pulled
/// and becomes the preferred eviction victim. `false` for a run the directory
/// does not hold, so an unknown id can never mark anything synced.
pub fn chunk_completes_run(dir: &SlotDir, run_seq: u32, next_offset: u32) -> bool {
    dir.find(run_seq)
        .is_some_and(|(_, size)| next_offset >= size)
}

/// Reads one run slot's raw bytes for [`recover_dir`]. `false` reports a flash
/// read error: that slot recovers nothing rather than the scan trusting a
/// partially-filled buffer.
pub trait SlotReader {
    fn read_slot(&mut self, slot: usize, into: &mut [u8; SLOT_LEN]) -> bool;
}

/// Rebuild the slot directory from what flash actually holds, as the driver does
/// once at boot: every slot is scanned with [`flash_store::recover_slot`], so a
/// run recorded in a prior power cycle is advertised again instead of staying
/// lost until its slot is overwritten. Each recovered run keeps its own slot
/// index, so [`SlotDir::find`] maps it back to the bytes it physically occupies.
pub fn recover_dir<R: SlotReader>(reader: &mut R) -> SlotDir {
    let mut recovered: [Option<RecoveredRun>; SLOT_COUNT] = [None; SLOT_COUNT];
    let mut buf = [0u8; SLOT_LEN];
    for (slot, entry) in recovered.iter_mut().enumerate() {
        if reader.read_slot(slot, &mut buf) {
            *entry = flash_store::recover_slot(&buf);
        }
    }
    SlotDir::from_recovered(recovered)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::flash_store::{MAX_POINTS_PER_RUN, REGION_LEN};
    use crate::run_store::{
        blob_len, verify_blob, RunWriter, TrackPoint, FOOTER_LEN, HEADER_LEN, POINT_LEN,
    };

    /// Slot-aligned base, deliberately not zero so a lost `region_offset` in any
    /// offset computation shows up as a wrong absolute address.
    const BASE: u32 = 0x000F_B000;

    /// A whole run-store region as bytes, plus the erase / write / read
    /// primitives the `app/` driver performs against real flash.
    struct FakeFlash {
        region: [u8; REGION_LEN],
        /// Slots whose reads fail, to exercise the recovery path's L4 tolerance.
        fail_read: [bool; SLOT_COUNT],
    }

    impl FakeFlash {
        fn erased() -> Self {
            Self {
                region: [0xFF; REGION_LEN],
                fail_read: [false; SLOT_COUNT],
            }
        }

        fn at(&self, abs: u32) -> usize {
            (abs - BASE) as usize
        }

        fn erase(&mut self, from: u32, to: u32) {
            let (from, to) = (self.at(from), self.at(to));
            self.region[from..to].fill(0xFF);
        }

        fn write(&mut self, at: u32, bytes: &[u8]) {
            let at = self.at(at);
            self.region[at..at + bytes.len()].copy_from_slice(bytes);
        }

        fn read(&self, at: u32, into: &mut [u8]) {
            let at = self.at(at);
            into.copy_from_slice(&self.region[at..at + into.len()]);
        }

        /// Apply a planned write exactly as `run_flash::commit` does.
        fn apply(&mut self, plan: SlotWrite, blob: &[u8]) {
            self.erase(plan.erase_from, plan.erase_to);
            self.write(plan.erase_from, blob);
        }

        /// Serve chunk requests until the blob is exhausted, exactly as the BLE
        /// task does, and return the reassembled bytes plus the final cursor.
        fn pull_all(
            &self,
            dir: &SlotDir,
            run_seq: u32,
            cap: u16,
        ) -> (heapless::Vec<u8, 4096>, u32) {
            let mut out: heapless::Vec<u8, 4096> = heapless::Vec::new();
            let mut cursor = 0u32;
            while let Some(plan) = plan_chunk_read(dir, BASE, run_seq, cursor, cap) {
                let mut buf = [0u8; 4096];
                self.read(plan.at, &mut buf[..plan.len]);
                out.extend_from_slice(&buf[..plan.len]).expect("fits");
                cursor += plan.len as u32;
            }
            (out, cursor)
        }
    }

    impl SlotReader for FakeFlash {
        fn read_slot(&mut self, slot: usize, into: &mut [u8; SLOT_LEN]) -> bool {
            if self.fail_read[slot] {
                return false;
            }
            self.read(flash_store::slot_offset(BASE, slot), into);
            true
        }
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

    fn a_blob(run_seq: u32, start_uptime_s: u32, points: u32) -> heapless::Vec<u8, SLOT_LEN> {
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
        for t in 0..points {
            w.push_point(&a_point(t)).expect("push");
        }
        w.finalize(1234, 600, 620).expect("finalize")
    }

    #[test]
    fn plan_slot_write_fills_every_slot_in_order_then_wraps() {
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            let plan = plan_slot_write(&mut dir, BASE, seq, 100, 100).expect("fits");
            assert_eq!(plan.slot, seq as usize);
            assert_eq!(plan.erase_from, BASE + seq * SLOT_LEN as u32);
        }
        // Region full: the fifth run wraps onto the oldest slot.
        let plan = plan_slot_write(&mut dir, BASE, 4, 100, 100).expect("fits");
        assert_eq!(plan.slot, 0);
        assert_eq!(plan.erase_from, BASE);
        assert_eq!(dir.find(0), None, "the wrapped-over run is gone");
        assert_eq!(dir.find(4), Some((0, 100)));
    }

    #[test]
    fn plan_slot_write_erases_exactly_one_slot_never_a_neighbour() {
        let mut dir = SlotDir::new();
        for slot in 0..SLOT_COUNT {
            let plan = plan_slot_write(&mut dir, BASE, slot as u32, 0, 100).expect("fits");
            assert_eq!(plan.erase_to - plan.erase_from, SLOT_LEN as u32);
            assert_eq!(plan.erase_from, flash_store::slot_offset(BASE, slot));
            // The erase never reaches into the next slot, and never below the
            // region base (where the config page lives).
            assert_eq!(plan.erase_to, flash_store::slot_offset(BASE, slot + 1));
            assert!(plan.erase_from >= BASE);
            assert!(plan.erase_to <= BASE + REGION_LEN as u32);
        }
    }

    #[test]
    fn plan_slot_write_accepts_exactly_a_slot_and_rejects_one_byte_over() {
        let mut dir = SlotDir::new();
        assert!(plan_slot_write(&mut dir, BASE, 1, 0, SLOT_LEN).is_some());
        assert_eq!(
            plan_slot_write(&mut dir, BASE, 2, 0, SLOT_LEN + 1),
            None,
            "one byte over a slot is dropped whole"
        );
    }

    #[test]
    fn an_oversized_blob_never_disturbs_the_directory() {
        // The critical half of the size gate: a run too big to store must not
        // evict — or resize — a run that IS on flash on its way to being dropped.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            plan_slot_write(&mut dir, BASE, seq, 0, 200).expect("fits");
        }
        assert_eq!(plan_slot_write(&mut dir, BASE, 99, 0, SLOT_LEN + 1), None);
        assert_eq!(dir.run_count(), SLOT_COUNT as u8);
        for seq in 0..SLOT_COUNT as u32 {
            assert_eq!(dir.find(seq), Some((seq as usize, 200)), "run {seq} intact");
        }
        assert_eq!(dir.find(99), None, "the rejected run was never recorded");
    }

    #[test]
    fn plan_slot_write_at_the_point_cap_and_one_over() {
        // 253 points is the most that leaves room for the footer in one slot.
        let capped = blob_len(MAX_POINTS_PER_RUN) as usize;
        let mut dir = SlotDir::new();
        assert!(plan_slot_write(&mut dir, BASE, 1, 0, capped).is_some());
        assert_eq!(capped, HEADER_LEN + 253 * POINT_LEN + FOOTER_LEN);
        assert!(capped <= SLOT_LEN);

        // One point more cannot be a slot-resident blob at all.
        let over = blob_len(MAX_POINTS_PER_RUN + 1) as usize;
        assert!(over > SLOT_LEN);
        assert_eq!(plan_slot_write(&mut dir, BASE, 2, 0, over), None);
    }

    #[test]
    fn plan_slot_write_reuses_a_checkpointed_runs_slot() {
        // Every mid-run checkpoint and the final commit must target the SAME
        // page, or a checkpoint left in another slot would be advertised
        // alongside the finished run as a second, stale copy.
        let mut dir = SlotDir::new();
        let first = plan_slot_write(&mut dir, BASE, 7, 41, 100).expect("fits");
        let grown = plan_slot_write(&mut dir, BASE, 7, 41, 500).expect("fits");
        let committed = plan_slot_write(&mut dir, BASE, 7, 41, 900).expect("fits");
        assert_eq!(first.slot, grown.slot);
        assert_eq!(first.slot, committed.slot);
        assert_eq!(first.erase_from, committed.erase_from);
        assert_eq!(dir.run_count(), 1, "one slot consumed, not three");
        assert_eq!(
            dir.find(7),
            Some((first.slot, 900)),
            "size updated in place"
        );
    }

    #[test]
    fn plan_chunk_read_walks_a_blob_with_no_gap_or_overlap() {
        let blob = a_blob(7, 41, 60);
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let plan = plan_slot_write(&mut dir, BASE, 7, 41, blob.len()).expect("fits");
        flash.apply(plan, &blob);

        let (pulled, cursor) = flash.pull_all(&dir, 7, 244);
        assert_eq!(cursor, blob.len() as u32);
        assert_eq!(&pulled[..], &blob[..], "byte-exact reassembly");
        assert!(verify_blob(&pulled));
    }

    #[test]
    fn plan_chunk_read_reassembles_identically_at_every_chunk_size() {
        // An off-by-one in the offset or length arithmetic shows up as a gap or a
        // duplicated byte at some particular stride, so sweep the strides —
        // including ones that divide the blob exactly and ones that don't.
        let blob = a_blob(3, 9, 41);
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let plan = plan_slot_write(&mut dir, BASE, 3, 9, blob.len()).expect("fits");
        flash.apply(plan, &blob);

        for cap in [1u16, 2, 3, 7, 16, 17, 100, 244, 700, 4096] {
            let (pulled, cursor) = flash.pull_all(&dir, 3, cap);
            assert_eq!(cursor, blob.len() as u32, "cap {cap}");
            assert_eq!(&pulled[..], &blob[..], "cap {cap}");
        }
    }

    #[test]
    fn plan_chunk_read_clamps_the_final_partial_chunk_to_the_blob_end() {
        let blob = a_blob(5, 0, 3);
        let size = blob.len() as u32;
        let mut dir = SlotDir::new();
        plan_slot_write(&mut dir, BASE, 5, 0, blob.len()).expect("fits");

        // One byte short of the end: exactly one byte is served, not `cap`.
        let plan = plan_chunk_read(&dir, BASE, 5, size - 1, 244).expect("one byte left");
        assert_eq!(plan.len, 1);
        assert_eq!(plan.at, BASE + size - 1);
        // A request that starts inside and would run past the end is clamped.
        let plan = plan_chunk_read(&dir, BASE, 5, size - 10, 244).expect("ten bytes left");
        assert_eq!(plan.len, 10);
        assert_eq!(plan.at + plan.len as u32, BASE + size);
    }

    #[test]
    fn plan_chunk_read_fails_closed_off_the_end_and_on_an_unknown_run() {
        let mut dir = SlotDir::new();
        plan_slot_write(&mut dir, BASE, 5, 0, 100).expect("fits");
        assert_eq!(plan_chunk_read(&dir, BASE, 5, 100, 244), None, "at the end");
        assert_eq!(
            plan_chunk_read(&dir, BASE, 5, 101, 244),
            None,
            "past the end"
        );
        assert_eq!(
            plan_chunk_read(&dir, BASE, 5, u32::MAX, 244),
            None,
            "a hostile offset never wraps into a valid read"
        );
        assert_eq!(plan_chunk_read(&dir, BASE, 6, 0, 244), None, "unknown run");
        assert_eq!(plan_chunk_read(&dir, BASE, 5, 0, 0), None, "no reply room");
        assert_eq!(
            plan_chunk_read(&SlotDir::new(), BASE, 0, 0, 244),
            None,
            "an empty directory serves nothing"
        );
    }

    #[test]
    fn plan_chunk_read_never_plans_past_its_own_slot() {
        // The clamp is what keeps a read inside the run's own page: a blob in the
        // last slot must never plan a read beyond the region, and one in slot 0
        // must never spill into slot 1.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            plan_slot_write(&mut dir, BASE, seq, 0, SLOT_LEN).expect("fits");
        }
        for seq in 0..SLOT_COUNT as u32 {
            let slot_end = flash_store::slot_offset(BASE, seq as usize + 1);
            for offset in [0u32, 1, SLOT_LEN as u32 - 1] {
                let plan = plan_chunk_read(&dir, BASE, seq, offset, u16::MAX).expect("in range");
                assert!(
                    plan.at + plan.len as u32 <= slot_end,
                    "run {seq} @ {offset} stayed in its slot"
                );
            }
        }
    }

    #[test]
    fn plan_chunk_read_serves_out_of_order_requests_independently() {
        // The phone may retry or reorder; each request is answered from its own
        // offset with no carried cursor state.
        let blob = a_blob(11, 3, 20);
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let plan = plan_slot_write(&mut dir, BASE, 11, 3, blob.len()).expect("fits");
        flash.apply(plan, &blob);

        for offset in [200u32, 0, 100, 0, 300, 16] {
            let plan = plan_chunk_read(&dir, BASE, 11, offset, 32).expect("in range");
            let mut buf = [0u8; 32];
            flash.read(plan.at, &mut buf[..plan.len]);
            let want = &blob[offset as usize..offset as usize + plan.len];
            assert_eq!(&buf[..plan.len], want, "offset {offset}");
        }
    }

    #[test]
    fn a_disconnect_mid_transfer_resumes_exactly_where_it_stopped() {
        let blob = a_blob(2, 0, 50);
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let plan = plan_slot_write(&mut dir, BASE, 2, 0, blob.len()).expect("fits");
        flash.apply(plan, &blob);

        // Pull two chunks, then "disconnect": the phone keeps only its cursor.
        let mut cursor = 0u32;
        let mut first_half: heapless::Vec<u8, 4096> = heapless::Vec::new();
        for _ in 0..2 {
            let plan = plan_chunk_read(&dir, BASE, 2, cursor, 100).expect("in range");
            let mut buf = [0u8; 100];
            flash.read(plan.at, &mut buf[..plan.len]);
            first_half.extend_from_slice(&buf[..plan.len]).unwrap();
            cursor += plan.len as u32;
        }
        assert!(!chunk_completes_run(&dir, 2, cursor), "not yet complete");

        // Reconnect and resume from the stored cursor.
        let mut whole = first_half;
        while let Some(plan) = plan_chunk_read(&dir, BASE, 2, cursor, 100) {
            let mut buf = [0u8; 100];
            flash.read(plan.at, &mut buf[..plan.len]);
            whole.extend_from_slice(&buf[..plan.len]).unwrap();
            cursor += plan.len as u32;
        }
        assert_eq!(&whole[..], &blob[..], "no gap and no duplicated byte");
        assert!(verify_blob(&whole));
        assert!(chunk_completes_run(&dir, 2, cursor));
    }

    #[test]
    fn chunk_completes_run_only_at_or_past_the_blob_end() {
        let mut dir = SlotDir::new();
        plan_slot_write(&mut dir, BASE, 5, 0, 100).expect("fits");
        assert!(!chunk_completes_run(&dir, 5, 0));
        assert!(!chunk_completes_run(&dir, 5, 99));
        assert!(
            chunk_completes_run(&dir, 5, 100),
            "exactly the end completes"
        );
        assert!(chunk_completes_run(&dir, 5, 101));
        assert!(
            !chunk_completes_run(&dir, 6, u32::MAX),
            "an unknown run is never marked synced"
        );
    }

    #[test]
    fn chunk_completes_a_zero_length_run_on_the_first_look() {
        // A run whose blob is somehow recorded as zero-length has nothing to
        // pull, so it is complete at cursor 0 — and serves no chunk.
        let mut dir = SlotDir::new();
        plan_slot_write(&mut dir, BASE, 9, 0, 0).expect("zero-length is placeable");
        assert_eq!(plan_chunk_read(&dir, BASE, 9, 0, 244), None);
        assert!(chunk_completes_run(&dir, 9, 0));
    }

    #[test]
    fn recover_dir_reads_back_every_slot_at_its_own_offset() {
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            let blob = a_blob(seq, seq * 10, seq + 1);
            let plan = plan_slot_write(&mut dir, BASE, seq, seq * 10, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }

        let recovered = recover_dir(&mut flash);
        assert_eq!(recovered.run_count(), SLOT_COUNT as u8);
        for seq in 0..SLOT_COUNT as u32 {
            assert_eq!(
                recovered.find(seq),
                Some((seq as usize, blob_len(seq + 1))),
                "run {seq} maps to the slot its bytes occupy"
            );
        }
        assert_eq!(recovered.next_run_seq(), SLOT_COUNT as u32);
    }

    #[test]
    fn recover_dir_from_an_erased_region_finds_nothing() {
        let mut flash = FakeFlash::erased();
        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 0);
        assert_eq!(dir.next_run_seq(), 0, "numbering starts from zero");
        assert!(dir.manifest().is_empty());
    }

    #[test]
    fn recover_dir_recovers_a_gap_in_the_middle_of_the_region() {
        // Only slot 2 holds a run: recovery must place it at 2, not compact it
        // to 0, or every later chunk read would address the wrong page.
        let mut flash = FakeFlash::erased();
        let blob = a_blob(30, 900, 6);
        let mut dir = SlotDir::new();
        for seq in 0..3u32 {
            plan_slot_write(&mut dir, BASE, seq, 0, 100).expect("fits");
        }
        let plan = SlotWrite {
            slot: 2,
            erase_from: flash_store::slot_offset(BASE, 2),
            erase_to: flash_store::slot_offset(BASE, 3),
        };
        flash.apply(plan, &blob);

        let recovered = recover_dir(&mut flash);
        assert_eq!(recovered.run_count(), 1);
        assert_eq!(recovered.find(30), Some((2, blob_len(6))));
        assert_eq!(recovered.next_run_seq(), 31);

        // And the recovered run reads back byte-exactly from slot 2.
        let (pulled, _) = flash.pull_all(&recovered, 30, 244);
        assert_eq!(&pulled[..], &blob[..]);
    }

    #[test]
    fn recover_dir_tolerates_a_failed_slot_read() {
        // L4: an unreadable slot recovers nothing and never blocks boot — the
        // other slots still come back.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for seq in 0..2u32 {
            let blob = a_blob(seq, 0, 4);
            let plan = plan_slot_write(&mut dir, BASE, seq, 0, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }
        flash.fail_read[0] = true;

        let recovered = recover_dir(&mut flash);
        assert_eq!(recovered.run_count(), 1);
        assert_eq!(recovered.find(0), None, "the unreadable slot is empty");
        assert_eq!(recovered.find(1), Some((1, blob_len(4))));
    }

    #[test]
    fn recover_dir_rejects_a_torn_write() {
        // Power lost partway through the blob write: the header and some points
        // landed, the footer never did, so the slot recovers nothing rather than
        // a run whose totals were never written.
        let mut flash = FakeFlash::erased();
        let blob = a_blob(4, 0, 30);
        let torn = blob.len() - FOOTER_LEN - 3 * POINT_LEN;
        flash.erase(BASE, BASE + SLOT_LEN as u32);
        flash.write(BASE, &blob[..torn]);

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 0, "a footerless blob is not a run");
        assert_eq!(dir.next_run_seq(), 0);
    }

    #[test]
    fn recover_dir_rejects_a_corrupt_slot() {
        // One flipped bit inside the track data: the footer is present but its
        // CRC no longer covers these bytes, so the run is refused outright
        // rather than handed to the phone as a silently-wrong track.
        let mut flash = FakeFlash::erased();
        let mut blob = a_blob(6, 0, 12);
        blob[HEADER_LEN + 5] ^= 0x01;
        flash.write(BASE, &blob);

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 0);
    }

    #[test]
    fn recover_dir_reads_back_a_zero_point_run() {
        let mut flash = FakeFlash::erased();
        let blob = a_blob(8, 15, 0);
        assert_eq!(blob.len() as u32, blob_len(0));
        flash.write(BASE, &blob);

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.find(8), Some((0, blob_len(0))));
        // Nothing to pull past the header + footer, and it verifies.
        let (pulled, cursor) = flash.pull_all(&dir, 8, 244);
        assert_eq!(cursor, blob_len(0));
        assert!(verify_blob(&pulled));
    }

    #[test]
    fn recover_dir_reads_back_a_full_slot_run() {
        let mut flash = FakeFlash::erased();
        let blob = a_blob(12, 7, MAX_POINTS_PER_RUN);
        assert_eq!(blob.len() as u32, blob_len(MAX_POINTS_PER_RUN));
        flash.write(BASE, &blob);

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.find(12), Some((0, blob_len(MAX_POINTS_PER_RUN))));
        let (pulled, _) = flash.pull_all(&dir, 12, 244);
        assert_eq!(&pulled[..], &blob[..]);
        assert!(verify_blob(&pulled));
    }

    #[test]
    fn a_shorter_run_over_a_longer_one_never_recovers_the_old_footer() {
        // The stale-tail hazard the whole-slot erase exists to prevent: slot 0
        // held a 200-point run, then a 3-point run is committed over it. Without
        // the erase, the old footer would still be sitting further into the page
        // and the footer scan could stop there, handing the phone a blob made of
        // two different runs.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let long = a_blob(1, 0, 200);
        let plan = plan_slot_write(&mut dir, BASE, 1, 0, long.len()).expect("fits");
        flash.apply(plan, &long);

        let short = a_blob(2, 50, 3);
        let plan = plan_slot_write(&mut dir, BASE, 2, 50, short.len()).expect("fits");
        assert_eq!(plan.slot, 1, "a different run takes a free slot first");

        // Force the reuse case: the same slot, as a wrap-around eviction does.
        let reuse = SlotWrite {
            slot: 0,
            erase_from: BASE,
            erase_to: BASE + SLOT_LEN as u32,
        };
        flash.apply(reuse, &short);
        let mut slot0 = [0u8; SLOT_LEN];
        flash.read(BASE, &mut slot0);
        assert_eq!(
            flash_store::recover_slot(&slot0),
            Some(RecoveredRun {
                run_seq: 2,
                size: blob_len(3),
                start_uptime_s: 50,
            }),
            "only the new, shorter run is found"
        );
    }

    #[test]
    fn a_run_survives_a_reboot_and_pulls_byte_exactly() {
        // The whole vertical, end to end: commit → power cycle → rebuild the
        // directory from flash → serve every chunk → the phone's reassembly
        // verifies. This is the path a lost run would silently break.
        let mut flash = FakeFlash::erased();
        let blob = a_blob(21, 640, 120);
        {
            let mut dir = SlotDir::new();
            let plan = plan_slot_write(&mut dir, BASE, 21, 640, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }

        let mut dir = recover_dir(&mut flash);
        let entries = dir.manifest_at(50);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].run_seq, 21);
        assert_eq!(entries[0].size, blob.len() as u32);
        assert_eq!(
            entries[0].start_uptime_s, 50,
            "a prior-boot start is clamped out of the future"
        );

        let (pulled, cursor) = flash.pull_all(&dir, 21, 244);
        assert_eq!(&pulled[..], &blob[..]);
        assert!(verify_blob(&pulled));
        assert!(chunk_completes_run(&dir, 21, cursor));
        dir.mark_synced(21);

        // Once synced it becomes the eviction victim, so the next run reuses it.
        let plan = plan_slot_write(&mut dir, BASE, 22, 10, 100).expect("fits");
        assert_eq!(plan.slot, 1, "a free slot still comes first");
    }

    #[test]
    fn wrapping_through_the_region_keeps_every_surviving_run_readable() {
        // Ten runs through four slots: after all the eviction churn, every run
        // the directory still claims must read back and verify, and no evicted
        // run may linger in the manifest.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for seq in 0..10u32 {
            let blob = a_blob(seq, seq * 100, seq % 7 + 1);
            let plan = plan_slot_write(&mut dir, BASE, seq, seq * 100, blob.len()).expect("fits");
            flash.apply(plan, &blob);
            // The phone pulls each run as it lands, so eviction has a synced
            // victim to sacrifice.
            let (pulled, cursor) = flash.pull_all(&dir, seq, 244);
            assert_eq!(&pulled[..], &blob[..], "run {seq} pulled intact");
            assert!(chunk_completes_run(&dir, seq, cursor));
            dir.mark_synced(seq);
        }
        assert_eq!(dir.run_count(), SLOT_COUNT as u8);
        assert_eq!(dir.next_run_seq(), 10);

        // Everything still advertised reads back and verifies.
        for entry in dir.manifest().iter() {
            let (pulled, cursor) = flash.pull_all(&dir, entry.run_seq, 244);
            assert_eq!(cursor, entry.size, "run {} size matches", entry.run_seq);
            assert!(verify_blob(&pulled), "run {} verifies", entry.run_seq);
        }
        // The runs that were evicted are gone from the directory, not stale.
        for seq in 0..6u32 {
            assert_eq!(dir.find(seq), None, "run {seq} was evicted");
        }
    }

    #[test]
    fn a_reboot_mid_wrap_recovers_whatever_physically_survived() {
        // Five runs into four slots, then power loss. Recovery must find exactly
        // the four blobs on flash — including the one that overwrote run 0 — and
        // resume numbering above the highest, so a new run can't reuse an id.
        let mut flash = FakeFlash::erased();
        {
            let mut dir = SlotDir::new();
            for seq in 0..5u32 {
                let blob = a_blob(seq, seq * 10, 3);
                let plan =
                    plan_slot_write(&mut dir, BASE, seq, seq * 10, blob.len()).expect("fits");
                flash.apply(plan, &blob);
            }
        }
        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), SLOT_COUNT as u8);
        assert_eq!(dir.find(0), None, "run 0's page was overwritten by run 4");
        assert_eq!(dir.find(4), Some((0, blob_len(3))));
        assert_eq!(dir.next_run_seq(), 5);
        for seq in 1..5u32 {
            let (pulled, _) = flash.pull_all(&dir, seq, 244);
            assert!(verify_blob(&pulled), "run {seq} verifies after the reboot");
        }
    }
}
