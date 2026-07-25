//! On-device flash run store — the `app/` half of README step 7.
//!
//! Persists a finished run's [`watch_core::run_store`] blob to a reserved region
//! at the top of the nRF52840's internal flash (slot layout in
//! [`watch_core::flash_store`]) over the build's flash backend, and serves it
//! back to the BLE run-sync characteristics as a manifest + byte-range chunks.
//!
//! Every decision here — which slot a commit or checkpoint takes, the erase +
//! write range, where a chunk request reads from, and the boot recovery scan —
//! is [`watch_core::flash_plan`]'s, host-tested there. What is left in this file
//! is the flash I/O and the L4 logging around it.
//!
//! **Best-effort / L4.** Flash is the highest recording layer: a flash error
//! only `warn!`-logs and is dropped — it never panics and never disturbs the
//! L0/L1 recording math in `watch_core::record`. The default build probes the
//! NVMC controller once at construction; if it is absent (the Renode sim models
//! flash as plain memory with *no* NVMC controller, so the controller's READY
//! register never asserts) the store marks itself unavailable and every
//! operation no-ops — which is exactly what stops the sim spinning forever in
//! NVMC's ready-poll. The `ble` build cannot run under the sim at all (no
//! SoftDevice there), so it skips the probe. Recording is unaffected either way.
//!
//! **Tier-1 shape.** A run is staged in RAM by the caller (`run_store::RunWriter`
//! over a slot-sized `heapless::Vec`) and committed to flash in one erase+write
//! at stop, rather than streaming each point straight to flash. At the tier-1
//! 4 KiB-per-run budget ([`watch_core::flash_store::MAX_POINTS_PER_RUN`]) that is
//! simpler and keeps flash idle during recording; tier-2's megabyte QSPI tracks
//! will stream incrementally instead.
//!
//! **Flash backend split.** The default (no-SoftDevice) build pokes the NVMC
//! controller directly through embassy-nrf's blocking `Nvmc`. On the `ble`
//! build the S140 SoftDevice must arbitrate all flash access — direct NVMC
//! access while it is enabled can fault or assert — so the backend there is
//! `nrf_softdevice::Flash`, which routes every erase/write through
//! `sd_flash_*` and completes it via a SoC event. That makes the mutating half
//! of the store async: the `ble` path genuinely awaits the SoftDevice's
//! completion signal (never spin-blocks the executor), while the default path
//! keeps the NVMC backend's blocking behaviour unchanged behind the same async
//! signatures. Reads stay synchronous on both builds — SoC flash is
//! memory-mapped and `nrf_softdevice::Flash` itself reads with a plain copy.
//! The `ble` backend is compile-only but correct by construction: it is the
//! arbitrated path the S140 requires, and only hardware bring-up (no dev kit
//! yet) remains to verify it.

use defmt::{debug, info, warn};
use embassy_nrf::nvmc;
#[cfg(not(feature = "ble"))]
use embassy_nrf::nvmc::Nvmc;
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::mutex::Mutex;
#[cfg(not(feature = "ble"))]
use embedded_storage::nor_flash::NorFlash;
use embedded_storage::nor_flash::ReadNorFlash;
#[cfg(feature = "ble")]
use embedded_storage_async::nor_flash::NorFlash;
use heapless::Vec;
use watch_core::flash_plan::{self, SlotReader};
use watch_core::flash_store::{self, SlotDir, SLOT_COUNT, SLOT_LEN};
use watch_core::gnss_mode::GnssMode;
use watch_core::run_store::ManifestEntry;

/// Absolute flash offset of the run-store region: the top `REGION_LEN` bytes of
/// the chip's flash, carved out of both `memory.x` and `memory-ble.x`.
pub const REGION_OFFSET: u32 = (nvmc::FLASH_SIZE - flash_store::REGION_LEN) as u32;

const _: () = assert!(REGION_OFFSET.is_multiple_of(SLOT_LEN as u32));

/// Absolute flash offset of the persisted-config page: one erase page
/// immediately BELOW the run-store region. Sitting below the run slots (not
/// above) keeps [`REGION_OFFSET`] and every run-slot offset byte-identical, so a
/// config write can never disturb a stored run. Both `memory.x` and
/// `memory-ble.x` reserve this page alongside the run-store region.
pub const CONFIG_OFFSET: u32 = REGION_OFFSET - flash_store::CONFIG_LEN as u32;

const _: () = assert!(CONFIG_OFFSET.is_multiple_of(flash_store::CONFIG_LEN as u32));

/// nRF52840 NVMC `READY` register (base 0x4001E000, offset 0x400). Bit 0 set
/// means the controller is present and idle — the probe for a real NVMC vs the
/// Renode sim's bare flash memory.
#[cfg(not(feature = "ble"))]
const NVMC_READY_ADDR: usize = 0x4001_E400;

/// The per-build flash backend: embassy-nrf's blocking NVMC by default,
/// the SoftDevice-arbitrated `nrf_softdevice::Flash` on the `ble` build
/// (see the module doc's backend-split note).
#[cfg(not(feature = "ble"))]
pub type FlashBackend = Nvmc<'static>;
#[cfg(feature = "ble")]
pub type FlashBackend = nrf_softdevice::Flash;

#[cfg(not(feature = "ble"))]
type FlashError = nvmc::Error;
#[cfg(feature = "ble")]
type FlashError = nrf_softdevice::FlashError;

/// Shared run store: the `record` task commits into it, the `ble` task reads
/// from it. Held behind an async mutex so each op takes it only briefly.
pub type SharedStore = Mutex<CriticalSectionRawMutex, RunStore>;

pub struct RunStore {
    flash: FlashBackend,
    dir: SlotDir,
    available: bool,
}

impl RunStore {
    pub fn new(mut flash: FlashBackend) -> Self {
        #[cfg(not(feature = "ble"))]
        let available = nvmc_present();
        // The ble build cannot run under the Renode sim (no SoftDevice there),
        // so the sim-detection probe is moot: the SoftDevice flash API is
        // always present on real silicon.
        #[cfg(feature = "ble")]
        let available = true;
        // Rebuild the slot directory from flash so runs recorded in a prior
        // power cycle are advertised again — their blobs survive, only the
        // in-RAM index is lost on reset. No NVMC (sim) → empty directory.
        let dir = if available {
            flash_plan::recover_dir(&mut SlotFlash(&mut flash))
        } else {
            SlotDir::new()
        };
        if available {
            info!(
                "run_flash: run store armed at {=u32:#x}, {=u8} run(s) recovered",
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

    /// The one seam where the two backends diverge: NVMC erases in place
    /// (blocking, unchanged), the SoftDevice schedules the erase between radio
    /// events and signals completion — so the ble variant awaits that signal
    /// instead of polling.
    #[cfg(not(feature = "ble"))]
    async fn flash_erase(&mut self, from: u32, to: u32) -> Result<(), FlashError> {
        self.flash.erase(from, to)
    }

    #[cfg(feature = "ble")]
    async fn flash_erase(&mut self, from: u32, to: u32) -> Result<(), FlashError> {
        self.flash.erase(from, to).await
    }

    #[cfg(not(feature = "ble"))]
    async fn flash_write(&mut self, offset: u32, bytes: &[u8]) -> Result<(), FlashError> {
        self.flash.write(offset, bytes)
    }

    /// `sd_flash_write` requires a word-aligned source and the staging buffers
    /// are byte-aligned (`heapless::Vec<u8>` / `[u8; N]`), so bounce through an
    /// aligned chunk. Every store record length is a multiple of the 4-byte
    /// write size, so each chunk stays word-sized.
    #[cfg(feature = "ble")]
    async fn flash_write(&mut self, offset: u32, bytes: &[u8]) -> Result<(), FlashError> {
        #[repr(align(4))]
        struct AlignedChunk([u8; 256]);
        let mut chunk = AlignedChunk([0; 256]);
        let mut written = 0;
        while written < bytes.len() {
            let n = (bytes.len() - written).min(chunk.0.len());
            chunk.0[..n].copy_from_slice(&bytes[written..written + n]);
            self.flash
                .write(offset + written as u32, &chunk.0[..n])
                .await?;
            written += n;
        }
        Ok(())
    }

    /// The `run_seq` the record task should start numbering from so a new run
    /// can't reuse a recovered run's id. Read once at record-task startup.
    pub fn next_run_seq(&self) -> u32 {
        self.dir.next_run_seq()
    }

    /// Read the GNSS recording mode persisted by [`persist_gnss_mode`], or `None`
    /// when flash is unavailable (sim), unreadable, or the config page is
    /// erased/corrupt — so the boot path falls back to the default. Best-effort /
    /// L4: a read error only `warn!`s and reads as "no saved mode".
    pub fn read_gnss_mode(&mut self) -> Option<GnssMode> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; flash_store::CONFIG_RECORD_LEN];
        if let Err(e) = self.flash.read(CONFIG_OFFSET, &mut buf) {
            warn!("run_flash: config read failed {:?}", e);
            return None;
        }
        let byte = flash_store::decode_config(&buf)?;
        GnssMode::from_byte(byte)
    }

    /// Read the persisted BLE bond ([`persist_bond`](Self::persist_bond)), or
    /// `None` when flash is unavailable, unreadable, or the record is
    /// erased / corrupt — the watch then simply re-pairs (fail-closed, same
    /// rule as [`read_gnss_mode`](Self::read_gnss_mode)).
    pub fn read_bond(&mut self) -> Option<flash_store::BondRecord> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; flash_store::BOND_RECORD_LEN];
        let at = CONFIG_OFFSET + flash_store::BOND_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: bond read failed {:?}", e);
            return None;
        }
        flash_store::BondRecord::decode(&buf)
    }

    /// Persist the selected GNSS recording mode so it survives reboot / brown-out
    /// instead of silently reverting to the Performance default. Best-effort /
    /// L4: rewrites the config page (carrying any stored bond forward); any
    /// flash error only `warn!`s and returns, never blocking the caller. The
    /// button task calls this only when the mode actually changes, so the page is
    /// erased at most once per user mode switch — trivially within flash
    /// endurance and off the per-tick path.
    pub async fn persist_gnss_mode(&mut self, mode: GnssMode) {
        let bond = self.read_bond();
        if self.rewrite_config_page(Some(mode.to_byte()), bond).await {
            info!("run_flash: persisted GNSS mode {}", mode);
        }
    }

    /// Persist the BLE bond so a paired phone survives reboot / brown-out
    /// (issue #598). Best-effort / L4 like every flash path; erased at most
    /// once per (re-)pairing, so wear is negligible. Carries the stored GNSS
    /// mode forward — the two records share the config page. Only the `ble`
    /// task writes bonds, so this is feature-gated to keep the default
    /// build's clippy dead-code gate honest ([`read_bond`](Self::read_bond)
    /// stays unconditional — the GNSS-mode rewrite carries the record
    /// forward on every build).
    #[cfg(feature = "ble")]
    pub async fn persist_bond(&mut self, bond: flash_store::BondRecord) {
        let mode = self.read_gnss_mode().map(|m| m.to_byte());
        if self.rewrite_config_page(mode, Some(bond)).await {
            info!("run_flash: persisted BLE bond");
        }
    }

    /// Erase + rewrite the config page with whichever records are present.
    /// The page holds BOTH the CFG record (base) and the bond record
    /// ([`flash_store::BOND_RECORD_OFFSET`]); an erase clears both, so every
    /// caller reads the record it is NOT changing first and passes it through.
    /// Returns whether the rewrite fully succeeded.
    async fn rewrite_config_page(
        &mut self,
        gnss_mode_byte: Option<u8>,
        bond: Option<flash_store::BondRecord>,
    ) -> bool {
        if !self.available {
            return false;
        }
        let start = CONFIG_OFFSET;
        let end = start + flash_store::CONFIG_LEN as u32;
        if let Err(e) = self.flash_erase(start, end).await {
            warn!("run_flash: config erase failed {:?}", e);
            return false;
        }
        if let Some(mode) = gnss_mode_byte {
            let rec = flash_store::encode_config(mode);
            if let Err(e) = self.flash_write(start, &rec).await {
                warn!("run_flash: config write failed {:?}", e);
                return false;
            }
        }
        if let Some(b) = bond {
            let rec = b.encode();
            let at = start + flash_store::BOND_RECORD_OFFSET as u32;
            if let Err(e) = self.flash_write(at, &rec).await {
                warn!("run_flash: bond write failed {:?}", e);
                return false;
            }
        }
        true
    }

    /// Persist a finished run's staged blob. Best-effort: any failure warns,
    /// forgets the slot so the manifest can't advertise a half-written run, and
    /// returns — the caller ignores the outcome (L4).
    pub async fn commit(&mut self, run_seq: u32, start_uptime_s: u32, blob: &[u8]) {
        if !self.available {
            return;
        }
        // The plan takes the slot NOT holding this run's freshest checkpoint, so
        // a torn commit leaves that checkpoint recoverable at the next boot; the
        // superseded slot is released from the directory on the way.
        let Some(plan) = flash_plan::plan_slot_write(
            &mut self.dir,
            REGION_OFFSET,
            run_seq,
            start_uptime_s,
            blob.len(),
        ) else {
            warn!(
                "run_flash: blob {=usize} B exceeds slot {=usize} B, dropped",
                blob.len(),
                SLOT_LEN
            );
            return;
        };
        if let Err(e) = self.flash_erase(plan.erase_from, plan.erase_to).await {
            warn!("run_flash: erase slot {=usize} failed {:?}", plan.slot, e);
            self.dir.forget(plan.slot);
            return;
        }
        if let Err(e) = self.flash_write(plan.erase_from, blob).await {
            warn!("run_flash: write run {=u32} failed {:?}", run_seq, e);
            self.dir.forget(plan.slot);
            return;
        }
        info!(
            "run_flash: stored run {=u32} ({=usize} B) in slot {=usize}",
            run_seq,
            blob.len(),
            plan.slot
        );
    }

    /// Best-effort mid-run checkpoint: persist a *recoverable* snapshot of the
    /// run-so-far to flash so a battery swap or brown-out mid-run recovers a
    /// slightly-stale partial run instead of losing the entire in-progress track
    /// (which otherwise only reaches flash at stop).
    ///
    /// Each checkpoint ping-pongs into the slot NOT holding the previous one, so
    /// the erase+write window can never blank the only copy of the run-so-far —
    /// a brown-out mid-checkpoint costs the newest few minutes, not the run. The
    /// snapshot is recorded as unfinished, so it is never advertised or served
    /// while the run is still recording.
    ///
    /// L4 / best-effort: any flash error only warns and drops, so recording is
    /// never blocked (same contract as `commit`). The caller bounds the cadence
    /// to keep flash erase cycles within endurance — with two slots in rotation
    /// each takes half the erases it used to.
    pub async fn checkpoint(&mut self, run_seq: u32, start_uptime_s: u32, blob: &[u8]) {
        if !self.available {
            return;
        }
        let Some(plan) = flash_plan::plan_checkpoint_write(
            &mut self.dir,
            REGION_OFFSET,
            run_seq,
            start_uptime_s,
            blob.len(),
        ) else {
            warn!(
                "run_flash: checkpoint blob {=usize} B exceeds slot {=usize} B, dropped",
                blob.len(),
                SLOT_LEN
            );
            return;
        };
        if let Err(e) = self.flash_erase(plan.erase_from, plan.erase_to).await {
            warn!(
                "run_flash: checkpoint erase slot {=usize} failed {:?}",
                plan.slot, e
            );
            self.dir.forget(plan.slot);
            return;
        }
        if let Err(e) = self.flash_write(plan.erase_from, blob).await {
            warn!(
                "run_flash: checkpoint write run {=u32} failed {:?}",
                run_seq, e
            );
            self.dir.forget(plan.slot);
            return;
        }
        debug!(
            "run_flash: checkpointed run {=u32} ({=usize} B) in slot {=usize}",
            run_seq,
            blob.len(),
            plan.slot
        );
    }

    /// Manifest entries for every FINISHED run — a mid-run checkpoint of the run
    /// currently recording is never listed ([`SlotDir::manifest_at`]) — each
    /// run's `start_uptime_s` clamped to `watch_uptime_s` so a run recovered from
    /// a prior power cycle can't date in the future. Consumed by the BLE run-sync
    /// task; unused in the default (non-`ble`) build.
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
        if flash_plan::chunk_completes_run(&self.dir, run_seq, next_offset) {
            self.dir.mark_synced(run_seq);
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
        let cap = buf.len().min(u16::MAX as usize) as u16;
        let Some(plan) =
            flash_plan::plan_chunk_read(&self.dir, REGION_OFFSET, run_seq, rel_offset, cap)
        else {
            return 0;
        };
        if let Err(e) = self.flash.read(plan.at, &mut buf[..plan.len]) {
            warn!(
                "run_flash: read run {=u32} @ {=u32} failed {:?}",
                run_seq, rel_offset, e
            );
            return 0;
        }
        plan.len
    }
}

/// Feeds each slot's raw flash bytes to [`flash_plan::recover_dir`]'s boot scan.
/// Best-effort / L4: a read error on a slot only warns and recovers nothing from
/// it (that run stays unadvertised until overwritten), never blocking boot. The
/// scan's one-slot scratch buffer is transient — it runs before the record task
/// stages its own slot-sized blob, so the two never coexist on the stack.
struct SlotFlash<'a>(&'a mut FlashBackend);

impl SlotReader for SlotFlash<'_> {
    fn read_slot(&mut self, slot: usize, into: &mut [u8; SLOT_LEN]) -> bool {
        let abs = flash_store::slot_offset(REGION_OFFSET, slot);
        if let Err(e) = self.0.read(abs, into) {
            warn!("run_flash: recover read slot {=usize} failed {:?}", slot, e);
            return false;
        }
        true
    }
}

#[cfg(not(feature = "ble"))]
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
