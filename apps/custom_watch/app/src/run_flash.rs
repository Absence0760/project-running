//! On-device flash run store — the `app/` half of README step 7.
//!
//! Persists a finished run's [`watch_core::run_store`] blob to a reserved region
//! at the top of the nRF52840's internal flash (slot layout in
//! [`watch_core::flash_store`]) over embassy-nrf's NVMC, and serves it back to
//! the BLE run-sync characteristics as a manifest + byte-range chunks.
//!
//! **Best-effort / L4.** Flash is the highest recording layer: a flash error
//! only `warn!`-logs and is dropped — it never panics and never disturbs the
//! L0/L1 recording math in `watch_core::record`. The store probes the NVMC
//! controller once at construction; if it is absent (the Renode sim models
//! flash as plain memory with *no* NVMC controller, so the controller's READY
//! register never asserts) the store marks itself unavailable and every
//! operation no-ops — which is exactly what stops the sim spinning forever in
//! NVMC's ready-poll. Recording is unaffected either way.
//!
//! **Tier-1 shape.** A run is staged in RAM by the caller (`run_store::RunWriter`
//! over a slot-sized `heapless::Vec`) and committed to flash in one erase+write
//! at stop, rather than streaming each point straight to flash. At the tier-1
//! 4 KiB-per-run budget ([`watch_core::flash_store::MAX_POINTS_PER_RUN`]) that is
//! simpler and keeps flash idle during recording; tier-2's megabyte QSPI tracks
//! will stream incrementally through [`FlashSink`] instead.
//!
//! **BLE / hardware caveat (UNVERIFIED).** embassy-nrf's `Nvmc` pokes the flash
//! controller directly. That is fine with no SoftDevice, but on the `ble` build
//! the S140 SoftDevice must arbitrate flash access — a real hardware bring-up
//! has to swap this backend for `nrf_softdevice::Flash` (which implements the
//! async NorFlash traits and coordinates page erase/write with the stack).
//! Direct NVMC access while the SoftDevice is enabled can fault or assert. This
//! compiles and is structured for that swap; it has never run on hardware.

use defmt::{info, warn};
use embassy_nrf::nvmc::{self, Nvmc};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
use embedded_storage::nor_flash::{NorFlash, ReadNorFlash};
use heapless::Vec;
use watch_core::flash_store::{self, RecoveredRun, SlotDir, SLOT_COUNT, SLOT_LEN};
use watch_core::run_store::{ByteSink, ManifestEntry};

/// Absolute flash offset of the run-store region: the top `REGION_LEN` bytes of
/// the chip's flash, carved out of both `memory.x` and `memory-ble.x`.
pub const REGION_OFFSET: u32 = (nvmc::FLASH_SIZE - flash_store::REGION_LEN) as u32;

const _: () = assert!(REGION_OFFSET.is_multiple_of(SLOT_LEN as u32));

/// nRF52840 NVMC `READY` register (base 0x4001E000, offset 0x400). Bit 0 set
/// means the controller is present and idle — the probe for a real NVMC vs the
/// Renode sim's bare flash memory.
const NVMC_READY_ADDR: usize = 0x4001_E400;

/// Shared run store: the `record` task commits into it, the `ble` task reads
/// from it. Held behind an async mutex so each op takes it only briefly.
pub type SharedStore = Mutex<CriticalSectionRawMutex, RunStore<'static>>;

/// A [`ByteSink`] appending to an already-erased flash slot. Lengths must be a
/// multiple of the NVMC 4-byte write size — every `run_store` record is.
pub struct FlashSink<'f, 'd> {
    flash: &'f mut Nvmc<'d>,
    offset: u32,
    end: u32,
}

impl<'f, 'd> FlashSink<'f, 'd> {
    pub fn new(flash: &'f mut Nvmc<'d>, start: u32, end: u32) -> Self {
        Self {
            flash,
            offset: start,
            end,
        }
    }
}

impl ByteSink for FlashSink<'_, '_> {
    type Error = nvmc::Error;

    fn write(&mut self, bytes: &[u8]) -> Result<(), nvmc::Error> {
        let len = bytes.len() as u32;
        if self.offset + len > self.end {
            return Err(nvmc::Error::OutOfBounds);
        }
        self.flash.write(self.offset, bytes)?;
        self.offset += len;
        Ok(())
    }
}

pub struct RunStore<'d> {
    flash: Nvmc<'d>,
    dir: SlotDir,
    available: bool,
}

impl<'d> RunStore<'d> {
    pub fn new(mut flash: Nvmc<'d>) -> Self {
        let available = nvmc_present();
        // Rebuild the slot directory from flash so runs recorded in a prior
        // power cycle are advertised again — their blobs survive, only the
        // in-RAM index is lost on reset. No NVMC (sim) → empty directory.
        let dir = if available {
            recover_dir(&mut flash)
        } else {
            SlotDir::new()
        };
        if available {
            info!(
                "run_flash: NVMC present, run store armed at {=u32:#x}, {=u8} run(s) recovered",
                REGION_OFFSET,
                dir.run_count()
            );
        } else {
            warn!(
                "run_flash: no NVMC controller (sim?) — run store disabled, recording unaffected"
            );
        }
        Self {
            flash,
            dir,
            available,
        }
    }

    /// The `run_seq` the record task should start numbering from so a new run
    /// can't reuse a recovered run's id. Read once at record-task startup.
    pub fn next_run_seq(&self) -> u32 {
        self.dir.next_run_seq()
    }

    /// Persist a finished run's staged blob. Best-effort: any failure warns,
    /// forgets the slot so the manifest can't advertise a half-written run, and
    /// returns — the caller ignores the outcome (L4).
    pub fn commit(&mut self, run_seq: u32, start_uptime_s: u32, blob: &[u8]) {
        if !self.available {
            return;
        }
        if blob.len() > SLOT_LEN {
            warn!(
                "run_flash: blob {=usize} B exceeds slot {=usize} B, dropped",
                blob.len(),
                SLOT_LEN
            );
            return;
        }
        let slot = self.dir.place(run_seq, blob.len() as u32, start_uptime_s);
        let start = flash_store::slot_offset(REGION_OFFSET, slot);
        let end = start + SLOT_LEN as u32;
        if let Err(e) = self.flash.erase(start, end) {
            warn!("run_flash: erase slot {=usize} failed {:?}", slot, e);
            self.dir.forget(slot);
            return;
        }
        let mut sink = FlashSink::new(&mut self.flash, start, end);
        if let Err(e) = sink.write(blob) {
            warn!("run_flash: write run {=u32} failed {:?}", run_seq, e);
            self.dir.forget(slot);
            return;
        }
        info!(
            "run_flash: stored run {=u32} ({=usize} B) in slot {=usize}",
            run_seq,
            blob.len(),
            slot
        );
    }

    /// Manifest entries for every committed run this power cycle, each run's
    /// `start_uptime_s` clamped to `watch_uptime_s` so a run recovered from a
    /// prior power cycle can't date in the future (see
    /// [`SlotDir::manifest_at`]). Consumed by the BLE run-sync task; unused in
    /// the default (non-`ble`) build.
    #[cfg_attr(not(feature = "ble"), allow(dead_code))]
    pub fn manifest_at(&self, watch_uptime_s: u32) -> Vec<ManifestEntry, SLOT_COUNT> {
        self.dir.manifest_at(watch_uptime_s)
    }

    /// Once the phone has pulled through a run's blob end (`next_offset` is its
    /// read cursor after the chunk just served), mark the run synced so eviction
    /// sacrifices it before a still-unsynced run. RAM-only, best-effort (L4):
    /// the synced bit is not persisted across a reboot. Consumed by the BLE
    /// run-sync task; unused in the default build.
    #[cfg_attr(not(feature = "ble"), allow(dead_code))]
    pub fn mark_synced_if_complete(&mut self, run_seq: u32, next_offset: u32) {
        if let Some((_, size)) = self.dir.find(run_seq) {
            if next_offset >= size {
                self.dir.mark_synced(run_seq);
            }
        }
    }

    /// Copy up to `buf.len()` bytes of run `run_seq`'s blob starting at
    /// `rel_offset` into `buf`; returns how many were read (0 if the run is
    /// unknown, flash is unavailable, or `rel_offset` is past the blob end).
    /// Consumed by the BLE run-sync task; unused in the default build.
    #[cfg_attr(not(feature = "ble"), allow(dead_code))]
    pub fn read_chunk(&mut self, run_seq: u32, rel_offset: u32, buf: &mut [u8]) -> usize {
        if !self.available {
            return 0;
        }
        let Some((slot, size)) = self.dir.find(run_seq) else {
            return 0;
        };
        let remaining = size.saturating_sub(rel_offset);
        if remaining == 0 {
            return 0;
        }
        let n = (buf.len() as u32).min(remaining) as usize;
        let abs = flash_store::slot_offset(REGION_OFFSET, slot) + rel_offset;
        if let Err(e) = self.flash.read(abs, &mut buf[..n]) {
            warn!(
                "run_flash: read run {=u32} @ {=u32} failed {:?}",
                run_seq, rel_offset, e
            );
            return 0;
        }
        n
    }
}

/// Read each slot's raw bytes from flash once at boot and rebuild the directory
/// from whatever finished runs are found there. Best-effort / L4: a read error
/// on a slot just leaves it empty (that run stays unadvertised until overwritten)
/// and never blocks boot. The one-slot scratch buffer is transient — this runs
/// before the record task stages its own slot-sized blob, so the two never
/// coexist on the stack.
fn recover_dir(flash: &mut Nvmc<'_>) -> SlotDir {
    let mut recovered: [Option<RecoveredRun>; SLOT_COUNT] = [None; SLOT_COUNT];
    let mut buf = [0u8; SLOT_LEN];
    for (slot, entry) in recovered.iter_mut().enumerate() {
        let abs = flash_store::slot_offset(REGION_OFFSET, slot);
        if let Err(e) = flash.read(abs, &mut buf) {
            warn!("run_flash: recover read slot {=usize} failed {:?}", slot, e);
            continue;
        }
        *entry = flash_store::recover_slot(&buf);
    }
    SlotDir::from_recovered(recovered)
}

fn nvmc_present() -> bool {
    // A single read of the NVMC READY register. On real silicon the controller
    // is ready at boot and bit 0 reads 1. Renode models the nRF52840's flash as
    // plain memory with no NVMC controller, so this address is unmapped: Renode
    // logs one "read from unmapped memory" warning and returns 0. Returning 0
    // here is what keeps us from ever calling the ready-polling erase/write,
    // which would otherwise spin forever against the absent controller.
    let ready = unsafe { core::ptr::read_volatile(NVMC_READY_ADDR as *const u32) };
    ready & 1 == 1
}
