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
//!
//! **Slot budget.** Because a run's writes ping-pong across two slots so a torn
//! erase can never take the run-so-far with it, a run in progress reserves up to
//! two of the [`SLOT_COUNT`] slots and a starting run can therefore evict two
//! finished runs rather than one. That is the deliberate trade: bounding the loss
//! from a brownout to the newest few minutes is worth one slot of history, since
//! the evicted runs are (preferentially) ones the phone has already pulled while
//! the run in progress exists nowhere else. A completed run settles back to one
//! slot. The real fix for the cramped budget is tier-2's external QSPI, same as
//! for [`flash_store::MAX_POINTS_PER_RUN`].

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
    /// Whether taking this slot destroyed a finished run the phone had never
    /// pulled ([`SlotDir::next_write_evicts_unsynced`]). The driver turns it
    /// into the `! RUN LOST` banner — the loss used to reach only a `warn!`
    /// down a debug cable no runner carries.
    pub evicted_unsynced: bool,
}

/// Reserve the slot a FINISHED run's blob is committed into, and return the
/// erase + write range for it.
///
/// The target is the slot NOT holding the run's freshest mid-run checkpoint (see
/// [`plan_checkpoint_write`]), so a torn commit leaves that checkpoint's bytes
/// intact for the next boot's scan to recover.
///
/// **Reserving is not committing.** The superseded checkpoint keeps its directory
/// entry until the caller confirms the write landed with
/// [`SlotDir::commit_written`]; a write that failed calls
/// [`SlotDir::commit_failed`], which hands the run back to that checkpoint. Until
/// the new bytes are durable the checkpoint is the run's only copy, so the
/// directory must not stop claiming it.
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
    let evicted_unsynced = dir.next_write_evicts_unsynced(run_seq);
    Some(slot_write(
        region_offset,
        dir.reserve_commit(run_seq, blob_len as u32, start_uptime_s),
        evicted_unsynced,
    ))
}

/// Reserve the slot a mid-run checkpoint of `run_seq` is written into and return
/// the erase + write range for it.
///
/// Alternates away from the run's freshest copy: erasing a whole slot to rewrite
/// it in place — what this used to do — meant a brownout inside that window left
/// the slot BLANK and lost the entire run-so-far, the exact failure checkpointing
/// exists to prevent, recurring on every checkpoint. Ping-ponging makes a torn
/// checkpoint cost only the newest few minutes.
///
/// The reservation is not finished, so the snapshot never enters the manifest and
/// is never served while the run is still recording. Same over-a-slot rule as
/// [`plan_slot_write`].
pub fn plan_checkpoint_write(
    dir: &mut SlotDir,
    region_offset: u32,
    run_seq: u32,
    start_uptime_s: u32,
    blob_len: usize,
) -> Option<SlotWrite> {
    if blob_len > SLOT_LEN {
        return None;
    }
    let evicted_unsynced = dir.next_write_evicts_unsynced(run_seq);
    Some(slot_write(
        region_offset,
        dir.reserve_checkpoint(run_seq, blob_len as u32, start_uptime_s),
        evicted_unsynced,
    ))
}

fn slot_write(region_offset: u32, slot: usize, evicted_unsynced: bool) -> SlotWrite {
    let erase_from = flash_store::slot_offset(region_offset, slot);
    SlotWrite {
        slot,
        erase_from,
        erase_to: erase_from + SLOT_LEN as u32,
        evicted_unsynced,
    }
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

/// The flash range a factory erase (§378) covers: the config page and every run
/// slot, as one contiguous span.
///
/// **It really is one span.** The config page sits immediately BELOW the run
/// region (`app/src/run_flash::CONFIG_OFFSET` = `REGION_OFFSET - CONFIG_LEN`),
/// so there is no gap between them and nothing else of the watch's inside them
/// — which is why the erase can be a single range rather than a list of records
/// a future record could be left off. Everything personal the device stores is
/// in here: the run blobs (coordinates + bpm), the waypoints, the ICE card, the
/// BLE bond's long-term and identity-resolution keys, and the config.
///
/// **This erases bytes, not directory entries.** [`SlotDir::forget`] drops a
/// slot's entry and leaves its bytes for the next reservation to overwrite,
/// which is right for a failed write and wrong for a wipe: the adversary a
/// factory erase exists for is whoever holds the device next, and nothing in
/// this workspace enables APPROTECT, so a debug probe reads every byte the
/// firmware's own reader would have skipped.
pub const fn plan_factory_erase(region_offset: u32) -> (u32, u32) {
    (
        region_offset - flash_store::CONFIG_LEN as u32,
        region_offset + flash_store::REGION_LEN as u32,
    )
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

    /// A mid-run checkpoint blob — the run-so-far plus totals-so-far, with the
    /// finished flag clear. `elapsed_s` is what orders successive checkpoints of
    /// one run at boot, so it is the caller's to advance.
    fn a_checkpoint(
        run_seq: u32,
        start_uptime_s: u32,
        points: u32,
        elapsed_s: u32,
    ) -> heapless::Vec<u8, SLOT_LEN> {
        let sink: heapless::Vec<u8, SLOT_LEN> = heapless::Vec::new();
        let mut w = RunWriter::start(sink, run_seq, start_uptime_s).expect("start");
        for t in 0..points {
            w.push_point(&a_point(t)).expect("push");
        }
        w.checkpoint_blob(500, elapsed_s, elapsed_s)
            .expect("checkpoint")
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
    fn a_checkpoint_never_erases_the_run_so_far_and_the_commit_supersedes_it() {
        // Each write for one run must target a DIFFERENT page than the run's
        // freshest copy: erasing the same page in place — what this used to do —
        // meant a brownout inside the erase+write window left the slot blank and
        // lost the whole run-so-far, on every checkpoint. And when the run
        // commits, the leftover checkpoint must stop occupying a slot, or a stale
        // second copy of the same run would linger.
        let mut dir = SlotDir::new();
        let first = plan_checkpoint_write(&mut dir, BASE, 7, 41, 100).expect("fits");
        let second = plan_checkpoint_write(&mut dir, BASE, 7, 41, 500).expect("fits");
        assert_ne!(
            first.erase_from, second.erase_from,
            "the second checkpoint must not erase the first"
        );
        let third = plan_checkpoint_write(&mut dir, BASE, 7, 41, 700).expect("fits");
        assert_eq!(
            third.erase_from, first.erase_from,
            "checkpoints alternate across two slots, they don't keep allocating"
        );
        assert_eq!(dir.find(7), None, "no checkpoint is ever served");
        assert!(dir.manifest().is_empty(), "nor advertised");

        let committed = plan_slot_write(&mut dir, BASE, 7, 41, 900).expect("fits");
        assert_ne!(
            committed.erase_from, third.erase_from,
            "the commit must not erase the freshest checkpoint either"
        );
        dir.commit_written(committed.slot);
        assert_eq!(dir.run_count(), 1, "the checkpoint slot is released");
        assert_eq!(dir.find(7), Some((committed.slot, 900)));
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
            evicted_unsynced: false,
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
            evicted_unsynced: false,
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
                finished: true,
                elapsed_s: 620,
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
    fn a_commit_that_takes_an_unsynced_run_says_so() {
        // Four finished runs, none pulled: the fifth run's commit must evict
        // one that exists nowhere else — the plan reports the loss so the
        // driver can raise `! RUN LOST` instead of only warning down a cable.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            let plan = plan_slot_write(&mut dir, BASE, seq, seq, 100).expect("fits");
            assert!(
                !plan.evicted_unsynced,
                "run {seq} took a free slot, nothing was lost"
            );
        }
        let plan = plan_slot_write(&mut dir, BASE, 4, 10, 100).expect("fits");
        assert!(
            plan.evicted_unsynced,
            "the oldest unsynced run was destroyed"
        );
    }

    #[test]
    fn a_commit_over_a_synced_victim_reports_no_loss() {
        // The phone holds a copy of a synced run, so its eviction costs
        // nothing irreplaceable — the flag must stay quiet or it cries wolf.
        let mut dir = SlotDir::new();
        for seq in 0..SLOT_COUNT as u32 {
            plan_slot_write(&mut dir, BASE, seq, seq, 100).expect("fits");
            dir.mark_synced(seq);
        }
        let plan = plan_slot_write(&mut dir, BASE, 4, 10, 100).expect("fits");
        assert!(!plan.evicted_unsynced);
    }

    #[test]
    fn a_runs_own_ping_pong_slots_never_read_as_a_loss() {
        // Once a run holds both checkpoint slots, later checkpoints and the
        // final commit land on its own staler copy — superseding yourself is
        // not an eviction.
        let mut dir = SlotDir::new();
        plan_checkpoint_write(&mut dir, BASE, 7, 41, 100).expect("fits");
        plan_checkpoint_write(&mut dir, BASE, 7, 41, 120).expect("fits");
        let third = plan_checkpoint_write(&mut dir, BASE, 7, 41, 140).expect("fits");
        assert!(!third.evicted_unsynced);
        let commit = plan_slot_write(&mut dir, BASE, 7, 41, 160).expect("fits");
        assert!(!commit.evicted_unsynced);
    }

    #[test]
    fn three_unsynced_runs_are_one_start_from_a_loss() {
        // The idle face's pressure threshold, pinned where it comes from: at
        // three unsynced runs the next start's FIRST checkpoint takes the free
        // slot, and its SECOND has no free and no synced slot left — an
        // unsynced run goes. This is why the home face speaks at three, not
        // only at four.
        let mut dir = SlotDir::new();
        for seq in 0..3u32 {
            plan_slot_write(&mut dir, BASE, seq, seq, 100).expect("fits");
        }
        assert_eq!(dir.unsynced_count(), 3);
        let first = plan_checkpoint_write(&mut dir, BASE, 3, 10, 100).expect("fits");
        assert!(!first.evicted_unsynced, "the free slot absorbs the first");
        let second = plan_checkpoint_write(&mut dir, BASE, 3, 10, 120).expect("fits");
        assert!(second.evicted_unsynced, "the second must take a run");
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

    #[test]
    fn a_brownout_mid_checkpoint_still_leaves_the_run_so_far_on_flash() {
        // The failure checkpointing exists to prevent, which checkpointing itself
        // used to cause: the erase+write window. Two checkpoints land, the third
        // is interrupted after its erase and before its footer — and the run must
        // still come back, one checkpoint stale.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();

        let early = a_checkpoint(7, 41, 5, 100);
        let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, early.len()).expect("fits");
        flash.apply(plan, &early);

        let later = a_checkpoint(7, 41, 20, 200);
        let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, later.len()).expect("fits");
        flash.apply(plan, &later);

        // Third checkpoint: erase happens, then the power goes. Nothing more is
        // written and the in-RAM directory dies with it.
        let torn = a_checkpoint(7, 41, 40, 300);
        let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, torn.len()).expect("fits");
        flash.erase(plan.erase_from, plan.erase_to);
        assert_eq!(
            plan.erase_from,
            flash_store::slot_offset(BASE, 0),
            "the third checkpoint erases the slot holding the FIRST, not the second"
        );

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 1, "the run survived the torn checkpoint");
        let (pulled, cursor) = flash.pull_all(&dir, 7, 244);
        assert_eq!(
            &pulled[..],
            &later[..],
            "the second checkpoint came back whole"
        );
        assert!(verify_blob(&pulled));
        assert!(chunk_completes_run(&dir, 7, cursor));
    }

    #[test]
    fn a_checkpointed_run_is_reachable_and_flagged_pending_after_the_reboot() {
        // The whole point of checkpointing, end to end over the flash model: the
        // brown-out took the run before its commit, and at the next boot the run
        // is advertised, pullable byte-for-byte, AND counted as pending so the
        // idle face can say so. Before this the blob was recovered into RAM and
        // then reachable by nobody — write-only checkpointing.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let ckpt = a_checkpoint(7, 41, 20, 200);
        let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, ckpt.len()).expect("fits");
        flash.apply(plan, &ckpt);
        assert_eq!(
            dir.pending_partial_count(),
            0,
            "nothing is pending while the run is still live"
        );

        let mut dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 1);
        assert_eq!(dir.pending_partial_count(), 1);
        let (pulled, cursor) = flash.pull_all(&dir, 7, 244);
        assert_eq!(&pulled[..], &ckpt[..]);
        assert!(verify_blob(&pulled));
        assert!(chunk_completes_run(&dir, 7, cursor));

        // The phone pulling it through retires the marker; a run started
        // afterwards never re-arms it off its own checkpoints.
        dir.mark_synced(7);
        assert_eq!(dir.pending_partial_count(), 0);
        let seq = dir.next_run_seq();
        let blob = a_checkpoint(seq, 900, 5, 100);
        let plan = plan_checkpoint_write(&mut dir, BASE, seq, 900, blob.len()).expect("fits");
        flash.apply(plan, &blob);
        assert_eq!(dir.pending_partial_count(), 0);
        assert_eq!(dir.find(seq), None, "and stays unservable while it records");
    }

    #[test]
    fn a_reboot_with_both_ping_pong_slots_intact_keeps_the_newer_one() {
        // Both checkpoints landed cleanly before the reset. Exactly one run may be
        // advertised, and it must be the fresher snapshot.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for (points, elapsed) in [(5u32, 100u32), (20, 200)] {
            let blob = a_checkpoint(7, 41, points, elapsed);
            let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.manifest().len(), 1, "one run, not two copies of it");
        assert_eq!(
            dir.find(7),
            Some((1, blob_len(20))),
            "the newer checkpoint, at the slot its bytes occupy"
        );
        let (pulled, _) = flash.pull_all(&dir, 7, 244);
        assert_eq!(&pulled[..], &a_checkpoint(7, 41, 20, 200)[..]);
        assert!(verify_blob(&pulled));
        assert_eq!(dir.next_run_seq(), 8, "the id is not reused");
    }

    #[test]
    fn a_torn_commit_falls_back_to_the_surviving_checkpoint_at_the_next_boot() {
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for (points, elapsed) in [(5u32, 100u32), (20, 200)] {
            let blob = a_checkpoint(7, 41, points, elapsed);
            let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }
        // The commit erases its target and dies mid-write.
        let final_blob = a_blob(7, 41, 40);
        let plan = plan_slot_write(&mut dir, BASE, 7, 41, final_blob.len()).expect("fits");
        flash.erase(plan.erase_from, plan.erase_to);
        flash.write(plan.erase_from, &final_blob[..64]);
        dir.commit_failed(plan.slot);

        // The LIVE directory already falls back — the superseded checkpoint's
        // entry outlived the write, so the run is servable without a reboot.
        let (live, _) = flash.pull_all(&dir, 7, 244);
        assert_eq!(&live[..], &a_checkpoint(7, 41, 20, 200)[..]);

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.run_count(), 1);
        let (pulled, _) = flash.pull_all(&dir, 7, 244);
        assert_eq!(
            &pulled[..],
            &a_checkpoint(7, 41, 20, 200)[..],
            "the newest checkpoint the commit deliberately did not erase"
        );
        assert!(verify_blob(&pulled));
    }

    #[test]
    fn a_failed_commit_serves_the_surviving_checkpoint_without_waiting_for_a_reboot() {
        // Seal-then-drop, end to end over the flash model: the commit's erase
        // blanks its own page and then the write never happens, so the run's only
        // bytes are the checkpoint's. Because the superseded entry outlived the
        // write, the live directory already resolves the run to those bytes —
        // byte-identically to what the next boot's scan would rebuild.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let ckpt = a_checkpoint(7, 41, 20, 200);
        let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, ckpt.len()).expect("fits");
        flash.apply(plan, &ckpt);

        let final_blob = a_blob(7, 41, 40);
        let plan = plan_slot_write(&mut dir, BASE, 7, 41, final_blob.len()).expect("fits");
        flash.erase(plan.erase_from, plan.erase_to);
        dir.commit_failed(plan.slot);

        let (pulled, cursor) = flash.pull_all(&dir, 7, 244);
        assert_eq!(
            &pulled[..],
            &ckpt[..],
            "the checkpoint is served in its place"
        );
        assert!(verify_blob(&pulled));
        assert!(chunk_completes_run(&dir, 7, cursor));
        assert_eq!(recover_dir(&mut flash).find(7), dir.find(7));
    }

    #[test]
    fn a_committed_run_supersedes_its_leftover_checkpoint_at_the_next_boot() {
        // A successful commit leaves the staler checkpoint's BYTES on flash (its
        // page was never the write target). At the next boot both slots claim run
        // 7, and the finished blob has to win even though it is SHORTER — a
        // post-thinning commit holds half the points of a pre-thinning checkpoint,
        // so size cannot be the tiebreaker.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        for (points, elapsed) in [(5u32, 100u32), (20, 200)] {
            let blob = a_checkpoint(7, 41, points, elapsed);
            let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, blob.len()).expect("fits");
            flash.apply(plan, &blob);
        }
        let final_blob = a_blob(7, 41, 10);
        let plan = plan_slot_write(&mut dir, BASE, 7, 41, final_blob.len()).expect("fits");
        flash.apply(plan, &final_blob);
        dir.commit_written(plan.slot);
        assert!(
            final_blob.len() < blob_len(20) as usize,
            "shorter than a checkpoint"
        );

        let dir = recover_dir(&mut flash);
        assert_eq!(dir.manifest().len(), 1, "one entry, not the pair");
        let (pulled, _) = flash.pull_all(&dir, 7, 244);
        assert_eq!(&pulled[..], &final_blob[..], "the committed blob won");
        assert!(verify_blob(&pulled));
    }

    #[test]
    fn a_phone_connected_through_a_run_is_offered_nothing_until_the_commit() {
        // The straddling-transfer defect: while the run records, its checkpoints
        // sat in the manifest, so a phone could pull a partial blob and ingest it
        // as a complete run — and the later commit re-advertised the same run_seq
        // with larger, disagreeing bytes. Between two checkpoints the whole prefix
        // can also change (thinning), so a transfer spanning one reassembled bytes
        // from two different blobs. Nothing about the live run may be visible.
        let mut flash = FakeFlash::erased();
        let mut dir = SlotDir::new();
        let earlier = a_blob(3, 0, 6);
        let plan = plan_slot_write(&mut dir, BASE, 3, 0, earlier.len()).expect("fits");
        flash.apply(plan, &earlier);

        for (points, elapsed) in [(5u32, 100u32), (20, 200), (40, 300)] {
            let blob = a_checkpoint(7, 41, points, elapsed);
            let plan = plan_checkpoint_write(&mut dir, BASE, 7, 41, blob.len()).expect("fits");
            flash.apply(plan, &blob);
            let entries = dir.manifest_at(1_000);
            assert_eq!(
                entries
                    .iter()
                    .map(|e| e.run_seq)
                    .collect::<heapless::Vec<_, SLOT_COUNT>>()[..],
                [3][..],
                "only the previously-committed run is advertised"
            );
            assert_eq!(
                plan_chunk_read(&dir, BASE, 7, 0, 244),
                None,
                "and the live run is not served even when asked for by id"
            );
            assert!(
                !chunk_completes_run(&dir, 7, u32::MAX),
                "nor can it be marked synced"
            );
        }

        let final_blob = a_blob(7, 41, 40);
        let plan = plan_slot_write(&mut dir, BASE, 7, 41, final_blob.len()).expect("fits");
        flash.apply(plan, &final_blob);
        dir.commit_written(plan.slot);
        assert_eq!(dir.manifest_at(1_000).len(), 2, "now the run appears, once");
        let (pulled, cursor) = flash.pull_all(&dir, 7, 244);
        assert_eq!(&pulled[..], &final_blob[..]);
        assert!(verify_blob(&pulled));
        assert!(chunk_completes_run(&dir, 7, cursor));
    }

    #[test]
    fn a_factory_erase_covers_every_byte_the_store_ever_writes() {
        // The claim a wipe stands on: not "the records we remembered to list"
        // but "every address this crate can put personal data at". Each record
        // offset below is checked against the range rather than against a copy
        // of the arithmetic, so a record added at a new offset — or a page
        // layout that grew — fails here rather than surviving an erase.
        let (from, to) = plan_factory_erase(BASE);
        let config = BASE - flash_store::CONFIG_LEN as u32;
        assert_eq!(from, config, "the erase starts at the config page");
        assert_eq!(
            to,
            BASE + REGION_LEN as u32,
            "and ends at the top of the run region"
        );
        assert_eq!(
            to - from,
            (flash_store::CONFIG_LEN + REGION_LEN) as u32,
            "one contiguous span — the config page abuts the run region, so a \
             wipe needs no second range and can leave no gap between them"
        );
        for (name, at, len) in [
            ("config", 0, flash_store::CONFIG_RECORD_LEN),
            (
                "bond",
                flash_store::BOND_RECORD_OFFSET,
                flash_store::BOND_RECORD_LEN,
            ),
            (
                "waypoints",
                flash_store::WAYPOINT_RECORD_OFFSET,
                crate::waypoints::MAX_WPT1_LEN,
            ),
            (
                "ice",
                flash_store::ICE_RECORD_OFFSET,
                crate::ice::ICE1_RECORD_LEN,
            ),
            (
                "screens",
                flash_store::SCREENS_RECORD_OFFSET,
                crate::screens::MAX_SCR1_LEN,
            ),
            (
                "timer",
                flash_store::TIMER_RECORD_OFFSET,
                crate::timers::TIMER_RECORD_LEN,
            ),
        ] {
            let start = config + at as u32;
            assert!(
                start >= from && start + len as u32 <= to,
                "the {name} record is outside the factory-erase range"
            );
        }
        for slot in 0..SLOT_COUNT {
            let start = flash_store::slot_offset(BASE, slot);
            assert!(
                start >= from && start + SLOT_LEN as u32 <= to,
                "run slot {slot} is outside the factory-erase range"
            );
        }
        // Both ends land on an erase-page boundary, or the NVMC would refuse
        // the range and the wipe would silently do nothing.
        assert_eq!(from % SLOT_LEN as u32, 0);
        assert_eq!(to % SLOT_LEN as u32, 0);
    }
}
