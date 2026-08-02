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
//! of the store async on both builds, for different reasons: the `ble` path
//! awaits the SoftDevice's completion signal, while the default path awaits
//! nothing and instead subdivides its NVMC work so the executor gets the
//! CPU back between pages and between write bursts. The two end up handing
//! the other tasks the same shaped gaps — see
//! [`flash_erase`](RunStore::flash_erase) for the one gap neither build can
//! close. Reads stay synchronous on both builds — SoC flash is
//! memory-mapped and `nrf_softdevice::Flash` itself reads with a plain copy.
//! The `ble` backend is compile-only but correct by construction: it is the
//! arbitrated path the S140 requires, and only hardware bring-up (no dev kit
//! yet) remains to verify it.

use defmt::{debug, info, warn};
#[cfg(not(feature = "ble"))]
use embassy_futures::yield_now;
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
use watch_core::auto_lap::AutoLap;
use watch_core::flash_plan::{self, SlotReader};
use watch_core::flash_store::{self, SlotDir, SLOT_COUNT, SLOT_LEN};
use watch_core::gnss_mode::GnssMode;
use watch_core::ice;
use watch_core::profiles::ActivityProfile;
use watch_core::race_config;
use watch_core::run_store::ManifestEntry;
use watch_core::screens;
use watch_core::settings::WatchSettings;
use watch_core::timers;
use watch_core::waypoints;

use crate::state;

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

/// Bytes per NVMC write burst — 64 words, ≈ 2.6 ms of halted core. The arithmetic
/// behind the number is on [`RunStore::flash_write`].
#[cfg(not(feature = "ble"))]
const WRITE_CHUNK: usize = 256;

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
    /// Last value published to [`state::PENDING_RUNS`], so a mutation that leaves
    /// the count alone (the common case — every chunk served, every checkpoint
    /// that evicts nothing) wakes the ui task not at all.
    pending_published: u8,
    /// Last value published to [`state::UNSYNCED_RUNS`], change-gated for the
    /// same reason.
    unsynced_published: u8,
    /// Bumped by every operation that can change what
    /// [`manifest_at`](Self::manifest_at) returns, so the BLE task can skip
    /// re-encoding an unchanged manifest — and skip the SoftDevice value-set
    /// that goes with it — on every one of its 1 Hz ticks.
    manifest_gen: u32,
}

/// Every record the shared config page holds. One erase covers the whole
/// page, so a rewrite of any one of them must carry the others through.
#[derive(Clone, Default)]
struct ConfigPage {
    config: Option<(u8, u8, u8)>,
    bond: Option<flash_store::BondRecord>,
    waypoints: Option<waypoints::Waypoints>,
    ice: Option<ice::IceCard>,
    screens: Option<screens::Screens>,
    timer: Option<timers::TimerRecord>,
    race_config: Option<WatchSettings>,
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
                "run_flash: run store armed at {=u32:#x}, {=u8} run(s) recovered ({=u8} interrupted)",
                REGION_OFFSET,
                dir.run_count(),
                dir.pending_partial_count()
            );
        } else {
            warn!(
                "run_flash: no NVMC controller (sim?) — run store disabled, recording unaffected"
            );
        }
        let mut store = Self {
            flash,
            dir,
            available,
            pending_published: 0,
            unsynced_published: 0,
            manifest_gen: 0,
        };
        store.publish_pending();
        store
    }

    /// Publish the count of interrupted-and-unpulled runs for the ui task's
    /// home-face marker, and the count of unpulled runs overall for the §378
    /// erase prompt's stake line, each on change only.
    ///
    /// The store owns both facts and every path that can move either lives in
    /// this file — the boot scan, an eviction taken by a commit or a checkpoint,
    /// a failed commit, and a completed phone pull — so publishing here is what
    /// keeps the wrist from drifting out of step with flash. Best-effort / L4 like
    /// the rest of the store: a `Watch` send cannot fail, and nothing about
    /// recording depends on either marker.
    fn publish_pending(&mut self) {
        let pending = self.dir.pending_partial_count();
        if pending != self.pending_published {
            self.pending_published = pending;
            state::PENDING_RUNS.sender().send(pending);
        }
        let unsynced = self.dir.unsynced_count();
        if unsynced != self.unsynced_published {
            self.unsynced_published = unsynced;
            state::UNSYNCED_RUNS.sender().send(unsynced);
        }
    }

    /// A counter that moves whenever the manifest may have changed. The BLE
    /// task holds the last value it built from and rebuilds only when this
    /// differs, so a connected phone no longer costs a `manifest_at` + encode +
    /// SoftDevice value-set every second for a list that changes when a run
    /// finishes, is evicted, or is fully pulled. Consumed by the BLE run-sync
    /// task; unused in the default build.
    #[cfg_attr(not(feature = "ble"), allow(dead_code))]
    pub fn manifest_gen(&self) -> u32 {
        self.manifest_gen
    }

    /// Deliberately over-approximates: called on ENTRY to the mutating paths
    /// rather than only where the directory actually moves, so a future edit
    /// that adds an eviction or an early return cannot leave a stale manifest
    /// published. A spurious bump costs one re-encode.
    fn bump_manifest_gen(&mut self) {
        self.manifest_gen = self.manifest_gen.wrapping_add(1);
    }

    /// Erase one NVMC page per command, handing the executor the CPU between
    /// pages so the GPS and button tasks are not held off for the whole range.
    ///
    /// **A single page erase cannot be subdivided, polled or yielded through.**
    /// The nRF52840 halts the core for the entire `tERASEPAGE` = 85 ms the
    /// moment it fetches an instruction from flash while the NVMC is busy
    /// (nRF52840 PS § 4.4 NVMC: "The CPU is halted if the CPU executes code
    /// from the flash while the NVMC is writing to the flash", stated for
    /// `ERASEPAGE` too) — which is also why embassy-nrf's own `READY` spin-loop
    /// needs no RAM-resident thunk: the halt is a bus stall, not a fault.
    /// Driving `ERASEPAGE` / `READY` by hand and awaiting a timer between polls
    /// would buy nothing, because every other task on this executor is in flash
    /// as well, so there is nothing the core could run in the window; only a
    /// whole-firmware-in-RAM build would change that, which 256 KiB does not
    /// allow. A commit or a checkpoint erases exactly one slot
    /// (`SLOT_LEN` == `PAGE_SIZE` == 4 KiB) and so keeps its single 85 ms stall,
    /// irreducibly; the win here is [`factory_erase`](Self::factory_erase)'s
    /// five pages, which no longer monopolise the CPU for 425 ms at once.
    ///
    /// The bounds + alignment guard is embassy-nrf's own, hoisted: `Nvmc::erase`
    /// rejects a bad range before touching flash, and erasing page-by-page must
    /// not turn that into a partial erase followed by the same error.
    #[cfg(not(feature = "ble"))]
    async fn flash_erase(&mut self, from: u32, to: u32) -> Result<(), FlashError> {
        if to < from || to as usize > nvmc::FLASH_SIZE {
            return Err(nvmc::Error::OutOfBounds);
        }
        let page = nvmc::PAGE_SIZE as u32;
        if !from.is_multiple_of(page) || !to.is_multiple_of(page) {
            return Err(nvmc::Error::Unaligned);
        }
        let mut at = from;
        while at < to {
            self.flash.erase(at, at + page)?;
            at += page;
            if at < to {
                yield_now().await;
            }
        }
        Ok(())
    }

    #[cfg(feature = "ble")]
    async fn flash_erase(&mut self, from: u32, to: u32) -> Result<(), FlashError> {
        self.flash.erase(from, to).await
    }

    /// Write in [`WRITE_CHUNK`] bursts, yielding between them.
    ///
    /// Unlike an erase, a write *can* be broken up: each 32-bit word costs
    /// `tWRITE` = 41 µs of halted core (nRF52840 PS § 4.4) and the halt ends
    /// with the word, so between words the flash is fetchable and the executor
    /// runs normally. A full 4 KiB slot is 1024 words ≈ 42 ms as one burst; at
    /// 64 words per chunk nothing else waits on the store for more than
    /// ≈ 2.6 ms, and the 15 scheduler passes plus 32 extra `CONFIG.WEN`
    /// transitions it costs are register writes and empty poll loops against an
    /// idle controller — well under 1 % of the 42 ms. A finer chunk would
    /// buy latency that the irreducible 85 ms erase in front of every slot
    /// write dominates anyway. Small records (every config page write) are one
    /// chunk and yield nowhere.
    ///
    /// Same hoisted guard as [`flash_erase`](Self::flash_erase), for the same
    /// reason, and the same 256 B the `ble` path bounces through — so both
    /// builds hand the other tasks identically shaped gaps.
    #[cfg(not(feature = "ble"))]
    async fn flash_write(&mut self, offset: u32, bytes: &[u8]) -> Result<(), FlashError> {
        if offset as usize + bytes.len() > nvmc::FLASH_SIZE {
            return Err(nvmc::Error::OutOfBounds);
        }
        if !offset.is_multiple_of(4) || !bytes.len().is_multiple_of(4) {
            return Err(nvmc::Error::Unaligned);
        }
        let mut written = 0;
        while written < bytes.len() {
            let n = (bytes.len() - written).min(WRITE_CHUNK);
            self.flash
                .write(offset + written as u32, &bytes[written..written + n])?;
            written += n;
            if written < bytes.len() {
                yield_now().await;
            }
        }
        Ok(())
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

    /// Read the raw persisted config record — `(gnss_mode_byte, flags,
    /// profile_byte)` — or `None` when flash is unavailable (sim), unreadable,
    /// or the config page is erased/corrupt. Best-effort / L4: a read error
    /// only `warn!`s and reads as "no saved config".
    fn read_config_bytes(&mut self) -> Option<(u8, u8, u8)> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; flash_store::CONFIG_RECORD_LEN];
        if let Err(e) = self.flash.read(CONFIG_OFFSET, &mut buf) {
            warn!("run_flash: config read failed {:?}", e);
            return None;
        }
        flash_store::decode_config(&buf)
    }

    /// Read the GNSS recording mode persisted by [`persist_gnss_mode`], or `None`
    /// so the boot path falls back to the default (same fail-closed rule as
    /// [`read_config_bytes`](Self::read_config_bytes)).
    pub fn read_gnss_mode(&mut self) -> Option<GnssMode> {
        let (byte, _, _) = self.read_config_bytes()?;
        GnssMode::from_byte(byte)
    }

    /// Read the hide-empty-pages choice persisted by
    /// [`persist_hide_empty`](Self::persist_hide_empty), or `None` when no
    /// explicit choice was ever stored (every pre-§351 record) — the recorder
    /// then keeps its default.
    pub fn read_hide_empty(&mut self) -> Option<bool> {
        let (_, flags, _) = self.read_config_bytes()?;
        flash_store::hide_empty_from_flags(flags)
    }

    /// Whether the persisted record has backyard-ultra mode armed (§372). A
    /// missing or corrupt record reads as disarmed, which is also the default
    /// — the fail-closed direction for a mode that re-points the auto-lap.
    pub fn read_backyard(&mut self) -> bool {
        self.read_config_bytes()
            .is_some_and(|(_, flags, _)| flash_store::backyard_from_flags(flags))
    }

    /// Read the activity profile persisted by
    /// [`persist_profile`](Self::persist_profile), or `None` when no profile
    /// was ever selected (every pre-§353 record) or the stored discriminant
    /// names none — a corrupt byte reads as "no profile", never a wrong one.
    pub fn read_profile(&mut self) -> Option<ActivityProfile> {
        let (_, flags, profile) = self.read_config_bytes()?;
        ActivityProfile::from_byte(flash_store::profile_from_flags(flags, profile)?)
    }

    /// Read the auto-lap trigger persisted by
    /// [`persist_auto_lap`](Self::persist_auto_lap), or `None` when none was
    /// ever pushed (every pre-§374 record) or the stored discriminant names no
    /// rung — the recorder then keeps its 1 km default, never a wrong rung.
    pub fn read_auto_lap(&mut self) -> Option<AutoLap> {
        let (_, flags, _) = self.read_config_bytes()?;
        AutoLap::from_byte(flash_store::auto_lap_from_flags(flags)?)
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
    /// L4: rewrites the config page (carrying any stored flags + bond forward);
    /// any flash error only `warn!`s and returns, never blocking the caller. The
    /// button task calls this only when the mode actually changes, so the page is
    /// erased at most once per user mode switch — trivially within flash
    /// endurance and off the per-tick path.
    pub async fn persist_gnss_mode(&mut self, mode: GnssMode) {
        let mut page = self.read_config_page();
        let (flags, profile) = page.config.map(|(_, f, p)| (f, p)).unwrap_or((0, 0));
        page.config = Some((mode.to_byte(), flags, profile));
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted GNSS mode {}", mode);
        }
    }

    /// Persist an explicit hide-empty-pages choice (§351 — the settings menu's
    /// toggle, or a phone push) so it survives reboot. Same best-effort / L4
    /// rules and the same carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode); the record task calls
    /// this only when the value actually changes. A watch with no stored GNSS
    /// mode pins the current default alongside — the record must carry a valid
    /// mode byte, and the default is what an unset mode already means.
    pub async fn persist_hide_empty(&mut self, hide: bool) {
        let mut page = self.read_config_page();
        let (mode_byte, flags, profile) =
            page.config.unwrap_or((GnssMode::default().to_byte(), 0, 0));
        page.config = Some((
            mode_byte,
            flash_store::set_hide_empty_flags(flags, hide),
            profile,
        ));
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted hide-empty-pages {}", hide);
        }
    }

    /// Persist the backyard-ultra arm (§372) so a runner who armed it at a
    /// start line still has it after a brown-out at hour 30. Same best-effort
    /// / L4 rules and carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode).
    pub async fn persist_backyard(&mut self, armed: bool) {
        let mut page = self.read_config_page();
        let (mode_byte, flags, profile) =
            page.config.unwrap_or((GnssMode::default().to_byte(), 0, 0));
        page.config = Some((
            mode_byte,
            flash_store::set_backyard_flags(flags, armed),
            profile,
        ));
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted backyard mode {}", armed);
        }
    }

    /// Persist the selected activity profile (§353) so the menu's row — and
    /// the boot-time re-apply of the profile's page preset — survive a
    /// reboot. Same best-effort / L4 rules and carry-everything-forward page
    /// rewrite as [`persist_gnss_mode`](Self::persist_gnss_mode); the button
    /// task calls this only when the selection actually changes.
    pub async fn persist_profile(&mut self, profile: ActivityProfile) {
        let mut page = self.read_config_page();
        let (mode_byte, flags, _) = page.config.unwrap_or((GnssMode::default().to_byte(), 0, 0));
        page.config = Some((
            mode_byte,
            flags | flash_store::CONFIG_FLAG_PROFILE_SET,
            profile.to_byte(),
        ));
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted activity profile {}", profile);
        }
    }

    /// Persist the pushed auto-lap trigger (§374) so a mid-race battery pull
    /// cannot silently re-split the rest of the run at the 1 km default. Same
    /// best-effort / L4 rules and carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode); the record task calls
    /// this only when the pushed value actually changes.
    pub async fn persist_auto_lap(&mut self, trigger: AutoLap) {
        let mut page = self.read_config_page();
        let (mode_byte, flags, profile) =
            page.config.unwrap_or((GnssMode::default().to_byte(), 0, 0));
        page.config = Some((
            mode_byte,
            flash_store::set_auto_lap_flags(flags, trigger.to_byte()),
            profile,
        ));
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted auto-lap {}", trigger);
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
        let mut page = self.read_config_page();
        page.bond = Some(bond);
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted BLE bond");
        }
    }

    /// Read the waypoints persisted by
    /// [`persist_waypoints`](Self::persist_waypoints), or `None` when flash is
    /// unavailable, unreadable, or the record is erased / corrupt — the watch
    /// then starts with an empty store (fail-closed, same rule as
    /// [`read_bond`](Self::read_bond)).
    pub fn read_waypoints(&mut self) -> Option<waypoints::Waypoints> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; waypoints::MAX_WPT1_LEN];
        let at = CONFIG_OFFSET + flash_store::WAYPOINT_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: waypoint read failed {:?}", e);
            return None;
        }
        waypoints::Waypoints::decode(&buf)
    }

    /// Persist the marked waypoints (§357) so a reboot keeps them — a stash
    /// the runner marked to find again is worth nothing if a battery pull
    /// forgets it. Same best-effort / L4 rules and carry-everything-forward
    /// page rewrite as [`persist_gnss_mode`](Self::persist_gnss_mode); marks
    /// are a handful per run, so page wear is negligible.
    pub async fn persist_waypoints(&mut self, wpts: &waypoints::Waypoints) {
        let mut page = self.read_config_page();
        page.waypoints = Some(wpts.clone());
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted waypoints ({=usize})", wpts.len());
        }
    }

    /// Read the ICE / medical-ID card persisted by
    /// [`persist_ice`](Self::persist_ice), or `None` when flash is
    /// unavailable, unreadable, or the record is erased / corrupt / carries a
    /// byte the face cannot render — a responder is shown nothing rather than
    /// a garbled medical line (fail-closed, and the same gate the wire uses).
    pub fn read_ice(&mut self) -> Option<ice::IceCard> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; ice::ICE1_RECORD_LEN];
        let at = CONFIG_OFFSET + flash_store::ICE_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: ice read failed {:?}", e);
            return None;
        }
        ice::decode_record(&buf)
    }

    /// Persist the ICE / medical-ID card (§358). A medic reads the wrist of a
    /// watch that may have power-cycled, so the card must not live only in
    /// the RAM a `SET1` push fills. `None` clears it — the record is simply
    /// not rewritten after the erase, so a cleared card leaves no stale one
    /// behind. Same best-effort / L4 rules and carry-everything-forward page
    /// rewrite as [`persist_gnss_mode`](Self::persist_gnss_mode); a card
    /// changes about as often as a phone number does.
    pub async fn persist_ice(&mut self, card: Option<ice::IceCard>) {
        let mut page = self.read_config_page();
        page.ice = card;
        if self.rewrite_config_page(&page).await {
            match card {
                Some(_) => info!("run_flash: persisted ICE card"),
                None => info!("run_flash: cleared ICE card"),
            }
        }
    }

    /// Read the composed data screens persisted by
    /// [`persist_screens`](Self::persist_screens), or `None` when flash is
    /// unavailable, unreadable, or the record is erased / corrupt — the watch
    /// then starts with the 37 built-in pages and nothing else, which is the
    /// L4 answer (fail-closed, and the same whole-frame rule the wire uses).
    pub fn read_screens(&mut self) -> Option<screens::Screens> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; screens::MAX_SCR1_LEN];
        let at = CONFIG_OFFSET + flash_store::SCREENS_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: screens read failed {:?}", e);
            return None;
        }
        screens::Screens::decode(&buf)
    }

    /// Persist the runner's composed data screens (§364) so a reboot keeps
    /// them. A set built the night before a race is worth nothing if the
    /// battery pull at the start line forgets it. `None` clears them — the
    /// record is simply not rewritten after the erase, so a cleared set leaves
    /// no stale one behind, exactly as [`persist_ice`](Self::persist_ice) does.
    /// Same best-effort / L4 rules and carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode); a screen set changes when
    /// a runner redesigns it, which is rarely.
    pub async fn persist_screens(&mut self, set: Option<&screens::Screens>) {
        let mut page = self.read_config_page();
        page.screens = set.cloned();
        if self.rewrite_config_page(&page).await {
            match set {
                Some(s) => info!("run_flash: persisted {=usize} screens", s.len()),
                None => info!("run_flash: cleared composed screens"),
            }
        }
    }

    /// Read the timer persisted by [`persist_timer`](Self::persist_timer), or
    /// `None` when flash is unavailable, unreadable, or the record is erased /
    /// corrupt — the watch then starts with a cleared instrument, which is the
    /// fail-closed answer (same rule as [`read_ice`](Self::read_ice)).
    ///
    /// Returns the raw record rather than a `Timer`, deliberately: rebuilding one
    /// needs a wall-clock stamp to measure the reboot gap against, and at boot
    /// there is usually no fix yet. Resolving it here would have to pass
    /// `wall_now = None` and so mark every restored timer's gap unknown, even the
    /// ones a fix arriving seconds later could have measured exactly. The button
    /// task holds the record and calls `Timer::from_record` once it has a stamp.
    pub fn read_timer(&mut self) -> Option<timers::TimerRecord> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; timers::TIMER_RECORD_LEN];
        let at = CONFIG_OFFSET + flash_store::TIMER_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: timer read failed {:?}", e);
            return None;
        }
        timers::TimerRecord::decode(&buf)
    }

    /// Persist the runner's countdown / stopwatch (§375) so a brown-out on a
    /// cold battery cannot silently take a nap timer with it. `None` clears it —
    /// the record is simply not rewritten after the erase, so a reset instrument
    /// cannot be resurrected by the next boot, exactly as
    /// [`persist_ice`](Self::persist_ice) does.
    ///
    /// Same best-effort / L4 rules and carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode). The caller must gate this
    /// on a **state change** — armed, stopped, resumed, cleared — and never on
    /// the record's contents: an armed timer's `elapsed_s` moves every second, so
    /// a contents-gated write would erase this page once per tick, which is over
    /// half a page's endurance in one 90-minute countdown. The reading needs no
    /// rewriting because the record stores the anchor, and an anchor does not
    /// drift.
    pub async fn persist_timer(&mut self, rec: Option<timers::TimerRecord>) {
        let mut page = self.read_config_page();
        page.timer = rec;
        if self.rewrite_config_page(&page).await {
            match rec {
                Some(_) => info!("run_flash: persisted timer"),
                None => info!("run_flash: cleared timer"),
            }
        }
    }

    /// Read the phone-pushed race configuration persisted by
    /// [`persist_race_config`](Self::persist_race_config), or `None` when flash
    /// is unavailable, unreadable, or the record is erased / corrupt — the watch
    /// then boots with its own defaults, which is the fail-closed answer (same
    /// rule as [`read_ice`](Self::read_ice)).
    ///
    /// Returns the settings frame rather than the applied values, deliberately:
    /// the caller feeds it to `settings_apply::plan_apply`, so a restored value
    /// meets exactly the guard a pushed one would — there is no second, staler
    /// copy of any field's plausibility rule.
    pub fn read_race_config(&mut self) -> Option<WatchSettings> {
        if !self.available {
            return None;
        }
        let mut buf = [0u8; race_config::RACE_CONFIG_RECORD_LEN];
        let at = CONFIG_OFFSET + flash_store::RACE_CONFIG_RECORD_OFFSET as u32;
        if let Err(e) = self.flash.read(at, &mut buf) {
            warn!("run_flash: race config read failed {:?}", e);
            return None;
        }
        race_config::decode(&buf)
    }

    /// Persist the accumulated phone-pushed race configuration so a brown-out
    /// mid-race cannot silently hand the rest of it a watch with no pacer goal,
    /// no HR ceiling, an altitude referenced to standard pressure and the
    /// temperate default fuel cadence. Same best-effort / L4 rules and
    /// carry-everything-forward page rewrite as
    /// [`persist_gnss_mode`](Self::persist_gnss_mode).
    ///
    /// The caller must gate this on `race_config::record_differs`, and hand over
    /// the whole accumulated config rather than one frame's delta: the page is
    /// erased whole per write, so a per-FIELD call would erase it once per field
    /// of a settings screen the runner filled in, and an ungated call would
    /// erase it once per push whether or not anything changed.
    pub async fn persist_race_config(&mut self, cfg: &WatchSettings) {
        let mut page = self.read_config_page();
        page.race_config = Some(*cfg);
        if self.rewrite_config_page(&page).await {
            info!("run_flash: persisted race config");
        }
    }

    /// Wipe every byte of flash this store owns — the config page and all four
    /// run slots — and forget the directory that indexed them (§378). Returns
    /// whether the erase actually reached flash.
    ///
    /// **This erases bytes, not entries.** [`SlotDir::forget`] would satisfy
    /// every reader in this firmware while leaving each blob's coordinates and
    /// heart rates sitting at the address they were written to; the adversary a
    /// factory erase exists for is whoever holds the device next, and nothing in
    /// this workspace enables APPROTECT, so a debug probe reads exactly what the
    /// directory was hiding. The range is [`flash_plan::plan_factory_erase`]'s,
    /// which is host-tested to cover every record offset and every slot — the
    /// one guard against a wipe that quietly skips a record added later.
    ///
    /// What this does NOT claim: an erase is a return to `0xFF` at every address
    /// the firmware wrote, with no wear-levelling or copy-back layer underneath
    /// to leave a shadow copy elsewhere (this store addresses pages directly).
    /// It is not a claim against charge-remnant recovery on a decapped die, and
    /// it does nothing about a probe attached *before* the erase — that is
    /// encryption at rest, which tier 1 does not have. And because the `BND1`
    /// record on that page holds the BLE long-term key that every reconnection
    /// derives its session key from, with no forward secrecy on the data
    /// channel, a probe attached before the erase reads more than the stored
    /// runs: it reads the LTK, and with it retroactively decrypts any earlier
    /// encrypted traffic an attacker had passively captured — so a lost, stolen
    /// or resold device exposes what was ever transmitted to it, not only what
    /// is currently on it.
    ///
    /// Best-effort / L4 like every other flash path: a failure warns and the
    /// caller carries on clearing RAM, because a wipe that half-worked must
    /// still take everything it can reach.
    pub async fn factory_erase(&mut self) -> bool {
        self.dir = SlotDir::new();
        self.publish_pending();
        self.bump_manifest_gen();
        if !self.available {
            warn!("run_flash: factory erase — flash unavailable, RAM only");
            return false;
        }
        let (from, to) = flash_plan::plan_factory_erase(REGION_OFFSET);
        if let Err(e) = self.flash_erase(from, to).await {
            warn!("run_flash: factory erase failed {:?}", e);
            return false;
        }
        info!(
            "run_flash: factory erase — {=u32} B cleared from {=u32:#x}",
            to - from,
            from
        );
        true
    }

    /// Every record the shared config page currently holds, so a writer can
    /// change one and hand the rest back untouched.
    fn read_config_page(&mut self) -> ConfigPage {
        ConfigPage {
            config: self.read_config_bytes(),
            bond: self.read_bond(),
            waypoints: self.read_waypoints(),
            ice: self.read_ice(),
            screens: self.read_screens(),
            timer: self.read_timer(),
            race_config: self.read_race_config(),
        }
    }

    /// Erase + rewrite the config page with whichever records are present.
    /// One erase clears the WHOLE page — every record on it — so a writer
    /// reads the page ([`read_config_page`](Self::read_config_page)), changes
    /// the one field it owns, and hands the rest straight back. Returns
    /// whether the rewrite fully succeeded.
    ///
    /// Takes the records as a struct rather than as N same-shaped `Option`
    /// arguments: four positional `Option`s is exactly the shape a caller can
    /// transpose in silence, and the page would still write — just with the
    /// bond's bytes where the waypoints go.
    async fn rewrite_config_page(&mut self, page: &ConfigPage) -> bool {
        if !self.available {
            return false;
        }
        let start = CONFIG_OFFSET;
        let end = start + flash_store::CONFIG_LEN as u32;
        if let Err(e) = self.flash_erase(start, end).await {
            warn!("run_flash: config erase failed {:?}", e);
            return false;
        }
        if let Some((mode, flags, profile)) = page.config {
            let rec = flash_store::encode_config(mode, flags, profile);
            if let Err(e) = self.flash_write(start, &rec).await {
                warn!("run_flash: config write failed {:?}", e);
                return false;
            }
        }
        if let Some(b) = page.bond {
            let rec = b.encode();
            let at = start + flash_store::BOND_RECORD_OFFSET as u32;
            if let Err(e) = self.flash_write(at, &rec).await {
                warn!("run_flash: bond write failed {:?}", e);
                return false;
            }
        }
        if let Some(w) = page.waypoints.as_ref() {
            let mut buf = [0u8; waypoints::MAX_WPT1_LEN];
            if let Some(len) = w.encode(&mut buf) {
                let at = start + flash_store::WAYPOINT_RECORD_OFFSET as u32;
                if let Err(e) = self.flash_write(at, &buf[..len]).await {
                    warn!("run_flash: waypoint write failed {:?}", e);
                    return false;
                }
            }
        }
        if let Some(c) = page.ice.as_ref() {
            let rec = c.encode_record();
            let at = start + flash_store::ICE_RECORD_OFFSET as u32;
            if let Err(e) = self.flash_write(at, &rec).await {
                warn!("run_flash: ice write failed {:?}", e);
                return false;
            }
        }
        if let Some(s) = page.screens.as_ref() {
            let mut buf = [0u8; screens::MAX_SCR1_LEN];
            if let Some(len) = s.encode(&mut buf) {
                let at = start + flash_store::SCREENS_RECORD_OFFSET as u32;
                if let Err(e) = self.flash_write(at, &buf[..len]).await {
                    warn!("run_flash: screens write failed {:?}", e);
                    return false;
                }
            }
        }
        if let Some(t) = page.timer {
            let rec = t.encode();
            let at = start + flash_store::TIMER_RECORD_OFFSET as u32;
            if let Err(e) = self.flash_write(at, &rec).await {
                warn!("run_flash: timer write failed {:?}", e);
                return false;
            }
        }
        if let Some(c) = page.race_config.as_ref() {
            let rec = race_config::encode(c);
            let at = start + flash_store::RACE_CONFIG_RECORD_OFFSET as u32;
            if let Err(e) = self.flash_write(at, &rec).await {
                warn!("run_flash: race config write failed {:?}", e);
                return false;
            }
        }
        true
    }

    /// Persist a finished run's staged blob. Best-effort: any failure warns,
    /// drops the slot so the manifest can't advertise a half-written run, and
    /// returns — the caller ignores the write outcome (L4).
    ///
    /// Returns whether the slot this commit took destroyed a finished run the
    /// phone had never pulled ([`flash_plan::SlotWrite::evicted_unsynced`]) —
    /// the record task turns that into `Recorder::note_run_lost` and the
    /// `! RUN LOST` banner. Reported on every post-reservation path, success
    /// or not: the reservation is what takes the victim's directory entry, so
    /// by the time an erase or write fails the loss has already happened.
    pub async fn commit(&mut self, run_seq: u32, start_uptime_s: u32, blob: &[u8]) -> bool {
        if !self.available {
            return false;
        }
        self.bump_manifest_gen();
        // The plan takes the slot NOT holding this run's freshest checkpoint, so
        // a torn commit leaves that checkpoint recoverable — and the directory
        // keeps claiming that checkpoint until these bytes are actually down.
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
            return false;
        };
        if plan.evicted_unsynced {
            warn!(
                "run_flash: commit of run {=u32} evicted an unsynced run from slot {=usize}",
                run_seq, plan.slot
            );
        }
        if let Err(e) = self.flash_erase(plan.erase_from, plan.erase_to).await {
            warn!("run_flash: erase slot {=usize} failed {:?}", plan.slot, e);
            self.dir.commit_failed(plan.slot);
            self.publish_pending();
            return plan.evicted_unsynced;
        }
        if let Err(e) = self.flash_write(plan.erase_from, blob).await {
            warn!("run_flash: write run {=u32} failed {:?}", run_seq, e);
            self.dir.commit_failed(plan.slot);
            self.publish_pending();
            return plan.evicted_unsynced;
        }
        self.dir.commit_written(plan.slot);
        self.publish_pending();
        info!(
            "run_flash: stored run {=u32} ({=usize} B) in slot {=usize}",
            run_seq,
            blob.len(),
            plan.slot
        );
        plan.evicted_unsynced
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
    ///
    /// Returns whether the slot this checkpoint took destroyed an unsynced
    /// run, on `commit`'s exact contract. The checkpoint path is where a new
    /// run in a full store usually takes its victims — the first two
    /// checkpoints claim the ping-pong pair — so this is the report that
    /// reaches the runner while the run whose start caused the loss is still
    /// on the wrist.
    pub async fn checkpoint(&mut self, run_seq: u32, start_uptime_s: u32, blob: &[u8]) -> bool {
        if !self.available {
            return false;
        }
        // A checkpoint is never itself advertised, but reserving its slot can
        // evict a finished run that was.
        self.bump_manifest_gen();
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
            return false;
        };
        if plan.evicted_unsynced {
            warn!(
                "run_flash: checkpoint of run {=u32} evicted an unsynced run from slot {=usize}",
                run_seq, plan.slot
            );
        }
        if let Err(e) = self.flash_erase(plan.erase_from, plan.erase_to).await {
            warn!(
                "run_flash: checkpoint erase slot {=usize} failed {:?}",
                plan.slot, e
            );
            self.dir.forget(plan.slot);
            self.publish_pending();
            return plan.evicted_unsynced;
        }
        if let Err(e) = self.flash_write(plan.erase_from, blob).await {
            warn!(
                "run_flash: checkpoint write run {=u32} failed {:?}",
                run_seq, e
            );
            self.dir.forget(plan.slot);
            self.publish_pending();
            return plan.evicted_unsynced;
        }
        self.publish_pending();
        debug!(
            "run_flash: checkpointed run {=u32} ({=usize} B) in slot {=usize}",
            run_seq,
            blob.len(),
            plan.slot
        );
        plan.evicted_unsynced
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
            self.publish_pending();
            self.bump_manifest_gen();
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
