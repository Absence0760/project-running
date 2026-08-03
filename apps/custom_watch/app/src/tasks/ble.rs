//! BLE task — GATT server that streams the phone-link status frames to a
//! paired phone over the radio (README step 6).
//!
//! Two builds live here:
//!
//! - **default / sim** (`ble` feature OFF): a stub. The phone link is carried
//!   by the `phone` task over UARTE1 → the Renode TCP bridge instead. Renode
//!   has no SoftDevice, so the real radio path can't run there at all.
//! - **hardware** (`--no-default-features --features ble`): enables the Nordic
//!   S140 SoftDevice, advertises a custom GATT service, and `notify`s one
//!   `watch_core::link` status frame per second on connection — the SAME bytes
//!   the UART transport emits, so the phone-side decoder is transport-agnostic
//!   (the design intent in docs/custom_watch/firmware.md § Sync protocol).
//!
//! UNVERIFIED: this path has never run. It compiles + links for the target,
//! but the SoftDevice can only be exercised on a real nRF52840 (see the
//! bench-verification notes in README step 6 — RAM origin, interrupt
//! priorities, and connection params all need confirming against hardware).
//!
//! Run sync (README step 7) rides the SAME service via two more
//! characteristics, backed by the on-device flash run store (`run_flash`):
//! - `run_manifest` (read + notify): a `run_store::ManifestHeader` + one
//!   `ManifestEntry` per finished run, refreshed each second.
//! - `run_chunk` (write + notify): the phone WRITES a `run_store::ChunkRequest`
//!   `{run_seq, offset, len}`; the watch notifies back exactly that byte slice
//!   of the run's blob (clamped to the notify MTU and the blob end).
//!
//! The course-push path (README course-push) rides the same service via one more
//! write characteristic:
//! - `course` (write): the phone WRITES a chunked `course_store` frame
//!   (`offset(2) | payload`); a per-connection `CourseAssembler` reassembles it,
//!   `course_store::decode` turns it into a `Course`, and it is published to the
//!   `nav` task via `state::COURSE`, which switches off `NO COURSE LOADED`.
//!
//! The roadbook push rides the same transport on one more write characteristic:
//! - `roadbook` (write): the phone WRITES a chunked `roadbook_store` frame; the
//!   watch reassembles + decodes it and publishes both series to the `record`
//!   task via `state::ROADBOOK`, which loads the recorder's roadbook
//!   checkpoints + cut-off legs. Until this landed the Roadbook / CutoffEta /
//!   Fuel / SleepStation pages could only ever show the canned `sim-course`
//!   schedule — the compute was built and host-tested, the wire was missing.
//!
//! All five of those pushes — settings, course, workout, screens, roadbook —
//! answer on one more characteristic:
//! - `push_status` (read): the `ble_sync::PushOutcome` verdict on the last
//!   push the watch resolved. An ATT write response is the SoftDevice's, not
//!   this task's — it is sent before the handler below runs — so without this
//!   row the phone's "sent" said only that the bytes arrived, and a refused
//!   settings / workout / screens / roadbook push left the OLD value armed
//!   with nothing but a `warn!` down a cable no runner carries (issue #664,
//!   decisions § 464). The wearer's half of the same seam is
//!   `state::PUSH_OUTCOME` → the alert engine's `! <KIND> FAIL` banner.
//!
//! Also UNVERIFIED on hardware, but flash access IS SoftDevice-coordinated:
//! on this build `run_flash`'s backend is `nrf_softdevice::Flash`, so every
//! erase/write is arbitrated by the S140 (see the `run_flash` module doc's
//! backend-split note).
//!
//! Security (issue #598): the service is **fail-closed against unpaired
//! peers**. Every characteristic requires an encrypted link
//! (`security = "justworks"` — Security Mode 1 Level 2), advertising is
//! pairable (`peripheral::advertise_pairable`) with a bonding
//! `SecurityHandler`, and the one bond persists to the flash config page
//! (`run_flash::persist_bond`) so a paired phone survives a power cycle. An
//! unbonded central can connect and see the service structure, but every
//! read / write / CCCD subscription on it is rejected by the SoftDevice until
//! pairing completes — run tracks (location history), settings pushes, and
//! course pushes never cross an unencrypted link.
//!
//! **Bond FORMATION is gated too, and that is the half the data plane cannot
//! cover.** Encryption-on-every-characteristic answers "may this peer read?"
//! with "only over an encrypted link", and a just-works pairing hands an
//! encrypted link to whoever asks — with no interaction at either end, because
//! `IoCapabilities::None` means there is nothing to confirm. So while bond
//! formation was ungated, any central within radio range of a *worn, already
//! set-up* watch could pair at any moment, read the whole run history
//! (coordinates of home, of every route, of every routine), push
//! settings / course / workout, and — `on_bonded` overwriting the peer
//! unconditionally — leave the owner's own phone unable to reconnect. A
//! bonded watch now refuses the pairing outright ([`Bonder`]'s `can_bond` +
//! `request_mitm_protection`) and drops the central that asked for it —
//! **unless the wearer has opened the §432 pairing window** (the settings
//! menu's guarded PAIR PHONE row, `watch_core::pairing`), the deliberate
//! re-pair path for a lost or dead phone that §378's FACTORY ERASE used to
//! be the only answer to. The window is 90 s, closes the moment a bond
//! forms, and lives in an atomic deadline (`state::PAIRING_WINDOW_UNTIL_S`)
//! because these callbacks run in the SoftDevice event context and can
//! neither await nor hold a `Watch` receiver; a reboot zeroes it, so the
//! gate fails closed.
//!
//! What remains out of scope is therefore the WEARER-OPENED windows, not the
//! whole life of the device: an active in-range attacker present during
//! first-time setup or during an open §432 window still wins a just-works
//! MITM, because the tier-1 face has no passkey UI to raise the bar with.
//! Accepted and documented, not hidden — the window turns a standing
//! exposure into 90 wearer-chosen seconds.

#[cfg(not(feature = "ble"))]
#[embassy_executor::task]
pub async fn run() {
    defmt::warn!("ble::run is a stub — build --features ble for the real radio (README step 6)");
}

#[cfg(feature = "ble")]
pub use imp::{bond_persist, config, run, softdevice_task, Bonder, Server};

#[cfg(feature = "ble")]
mod imp {
    // The gatt_server macro names every characteristic event `<Name>...Write`,
    // so the generated LinkServiceEvent trips enum_variant_names once there is
    // more than one characteristic. The names are the macro's, not ours.
    #![allow(clippy::enum_variant_names)]

    use core::cell::{Cell, RefCell};

    use defmt::*;
    use embassy_futures::select::{select, select3, Either, Either3};
    use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
    use embassy_sync::channel::Channel;
    use embassy_sync::signal::Signal;
    use embassy_time::{Duration, Instant, Ticker, Timer};
    use heapless::Vec;
    use nrf_softdevice::ble::advertisement_builder::{
        Flag, LegacyAdvertisementBuilder, LegacyAdvertisementPayload, ServiceList,
    };
    use nrf_softdevice::ble::gatt_server::{get_sys_attrs, set_sys_attrs};
    use nrf_softdevice::ble::security::{IoCapabilities, SecurityHandler};
    use nrf_softdevice::ble::{
        gatt_server, peripheral, Address, Connection, EncryptionInfo, IdentityKey,
        IdentityResolutionKey, MasterId, SecurityMode,
    };
    use nrf_softdevice::{raw, Softdevice};
    use watch_core::ble_sync::{
        self, PushKind, PushOutcome, CHUNK_QUEUE_DEPTH, MANIFEST_CAP, PUSH_STATUS_LEN,
    };
    use watch_core::course_store::{self, CourseAssembler, CoursePush, COURSE_CHUNK_CAP};
    use watch_core::flash_store::BondRecord;
    use watch_core::link;
    use watch_core::pairing;
    use watch_core::roadbook_store::{self, RoadbookAssembler, RoadbookPush, ROADBOOK_CHUNK_CAP};
    use watch_core::run_store::ChunkRequest;
    use watch_core::screens::{Screens, MAX_SCR1_LEN};
    use watch_core::settings::{WatchSettings, MAX_SETTINGS_LEN};
    use watch_core::workout_store::{self, WorkoutAssembler, WorkoutPush, WORKOUT_CHUNK_CAP};

    use crate::run_flash::SharedStore;
    use crate::state;

    /// Custom 128-bit service + characteristic UUIDs for the Threkir watch
    /// link. The characteristic carries the newline-terminated JSON status
    /// frame; the service UUID doubles as the 128-bit UUID advertised in the
    /// scan response so the phone app can filter for it. The `u128` here must
    /// stay byte-for-byte the same value as the service string below.
    const LINK_SERVICE_UUID: u128 = 0xd1f6a7e0_5b2c_4e9a_9c3d_1a2b3c4d5e6f;

    /// One notify carries a whole `link::Frame`. A single ATT notification
    /// tops out at `ATT_MTU - 3` bytes; with the 256-byte MTU below that's
    /// 253, so 244 leaves margin and comfortably fits every real frame (the
    /// worst-case frame is ~160 bytes; see `link.rs`). Also the run-chunk
    /// notify payload cap — a chunk reply never exceeds one notification.
    const FRAME_CAP: usize = 244;

    // Every characteristic requires an encrypted (paired) link — issue #598.
    // `justworks` = Security Mode 1 Level 2: the SoftDevice rejects any read,
    // write, or CCCD subscription from an unencrypted connection, so the data
    // plane is fail-closed while the service remains discoverable for pairing.
    #[nrf_softdevice::gatt_service(uuid = "d1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f")]
    pub struct LinkService {
        #[characteristic(
            uuid = "d1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            read,
            notify,
            security = "justworks"
        )]
        frame: Vec<u8, FRAME_CAP>,
        /// Finished-run manifest (README step 7). Read for the list; notified
        /// each second so a connected phone sees a run appear live.
        #[characteristic(
            uuid = "d1f6a7e2-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            read,
            notify,
            security = "justworks"
        )]
        run_manifest: Vec<u8, MANIFEST_CAP>,
        /// Run-chunk pull (README step 7). The phone WRITES a `ChunkRequest`;
        /// the watch notifies back that byte slice of the run blob.
        #[characteristic(
            uuid = "d1f6a7e3-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            notify,
            security = "justworks"
        )]
        run_chunk: Vec<u8, FRAME_CAP>,
        /// Settings push. The phone WRITES a `settings::WatchSettings` frame; the
        /// watch decodes it and queues it on `state::SETTINGS`, which the record
        /// task drains into the recorder + alert engine. Write-only — no readback.
        #[characteristic(
            uuid = "d1f6a7e4-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            security = "justworks"
        )]
        settings: Vec<u8, MAX_SETTINGS_LEN>,
        /// Course push (README course-push path). The phone WRITES chunked
        /// `course_store` frame bytes (`offset(2, u16 LE) | payload`); the watch
        /// reassembles them, decodes the `Course`, and publishes it to the nav
        /// task via `state::COURSE`. Write-only — a fire-and-forget push like
        /// `settings`; a whole course exceeds one notification, so it is chunked.
        #[characteristic(
            uuid = "d1f6a7e5-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            security = "justworks"
        )]
        course: Vec<u8, COURSE_CHUNK_CAP>,
        /// Structured-workout push (the `WKT1` path). The phone WRITES chunked
        /// `workout_store` frame bytes (the same `offset | payload` transport
        /// as `course`); the watch reassembles, decodes the step list, and
        /// publishes it to the record task via `state::WORKOUT`.
        #[characteristic(
            uuid = "d1f6a7e6-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            security = "justworks"
        )]
        workout: Vec<u8, WORKOUT_CHUNK_CAP>,
        /// Composed-data-screen push (the `SCR1` path, §364). The phone WRITES
        /// one whole `screens::Screens` frame; the watch decodes it and
        /// publishes it to `state::SCREENS`, where the record task persists it
        /// and the ui task draws it.
        ///
        /// Unchunked, unlike `course` and `workout`: the whole set is
        /// [`MAX_SCR1_LEN`] bytes, so it fits one ATT write with room to spare
        /// and an offset-ordered assembler would buy nothing but a
        /// reset-recovery contract to get wrong.
        #[characteristic(
            uuid = "d1f6a7e7-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            security = "justworks"
        )]
        screens: Vec<u8, MAX_SCR1_LEN>,
        /// Roadbook + cut-off schedule push (the `RBK1` path). The phone WRITES
        /// chunked `roadbook_store` frame bytes (the same `offset | payload`
        /// transport as `course` and `workout`); the watch reassembles, decodes
        /// both series, and publishes them to the record task via
        /// `state::ROADBOOK`, which is what makes the Roadbook / CutoffEta /
        /// Fuel / SleepStation pages read live data on hardware instead of only
        /// under `sim-course`.
        ///
        /// Chunked, unlike `screens`: a full schedule is 364 B, and one ATT
        /// write at the 256-byte MTU carries `MTU - 3` = 253.
        ///
        /// **Take the next free suffix; never renumber a row above.** § 410 was
        /// a whole broken run-sync path caused by inserting a characteristic
        /// ahead of existing ones without the phone client following.
        #[characteristic(
            uuid = "d1f6a7e8-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            write,
            security = "justworks"
        )]
        roadbook: Vec<u8, ROADBOOK_CHUNK_CAP>,
        /// The verdict on the last push the watch resolved, for the phone
        /// (`ble_sync::PushOutcome`, the `PSH1` record). Read-only, and the
        /// only row here that answers rather than accepts.
        ///
        /// It exists because an ATT write-with-response says nothing about
        /// whether the watch KEPT the value: the SoftDevice writes the
        /// attribute and answers the central before this task's handler ever
        /// runs, so the phone's "sent" is a transport fact, never an
        /// application one. That is how five characteristics could refuse a
        /// push while the phone reported success.
        ///
        /// Read, not notify: a read is one request/response the phone drives
        /// inside the connection it already opened to push, so there is no
        /// subscribe-before-write ordering to get wrong on a path that can
        /// never be simulated (§ 210). The phone samples the sequence before
        /// its writes and polls it after; an unmoved sequence is
        /// *unconfirmed*, never *accepted*.
        #[characteristic(
            uuid = "d1f6a7e9-5b2c-4e9a-9c3d-1a2b3c4d5e6f",
            read,
            security = "justworks"
        )]
        push_status: Vec<u8, PUSH_STATUS_LEN>,
    }

    /// The `push_status` characteristic value for `outcome`. The encode is
    /// [`PushOutcome`]'s (host-tested there); this only lifts it into the
    /// heapless `Vec` the generated setter takes.
    fn push_status_value(outcome: &PushOutcome) -> Vec<u8, PUSH_STATUS_LEN> {
        let mut v: Vec<u8, PUSH_STATUS_LEN> = Vec::new();
        let _ = v.extend_from_slice(&outcome.encode());
        v
    }

    #[nrf_softdevice::gatt_server]
    pub struct Server {
        link: LinkService,
    }

    /// One remembered peer: the SoftDevice key set a bond produces.
    #[derive(Clone, Copy)]
    struct Peer {
        master_id: MasterId,
        key: EncryptionInfo,
        peer_id: IdentityKey,
    }

    impl Peer {
        /// The flash-persistable form (`watch_core::flash_store::BondRecord` —
        /// plain bytes, no SoftDevice types, so the codec stays host-tested).
        fn to_record(self) -> BondRecord {
            BondRecord {
                master_ediv: self.master_id.ediv,
                master_rand: self.master_id.rand,
                ltk: self.key.ltk,
                enc_flags: self.key.flags,
                addr_flags: self.peer_id.addr.flags,
                addr: self.peer_id.addr.bytes,
                irk: self.peer_id.irk.as_raw().irk,
            }
        }

        fn from_record(rec: &BondRecord) -> Self {
            Peer {
                master_id: MasterId {
                    ediv: rec.master_ediv,
                    rand: rec.master_rand,
                },
                key: EncryptionInfo {
                    ltk: rec.ltk,
                    flags: rec.enc_flags,
                },
                peer_id: IdentityKey {
                    irk: IdentityResolutionKey::from_raw(raw::ble_gap_irk_t { irk: rec.irk }),
                    addr: Address {
                        flags: rec.addr_flags,
                        bytes: rec.addr,
                    },
                },
            }
        }
    }

    /// Just-works LESC bonding handler (issue #598). Holds the ONE remembered
    /// phone (a watch pairs with its owner's phone, not a fleet) plus that
    /// peer's GATT system attributes (CCCD state). `on_bonded` runs in the
    /// SoftDevice event context and cannot await, so it stages the keys and
    /// signals [`BOND_SAVED`]; the `run` loop persists them to the flash
    /// config page.
    ///
    /// **The bond is formed once.** A second pairing is refused rather than
    /// allowed to replace the first: `on_bonded` overwrites `self.peer` and
    /// `bond_persist` overwrites `BND1`, so "a new pairing replaces the old
    /// bond" is not a fleet-of-one nicety, it is a takeover — proximity alone
    /// would be enough to become the watch's phone and to lock the owner's out.
    /// Losing a phone still must not brick the watch, and the path for that is
    /// the §432 pairing window (the settings menu's guarded PAIR PHONE row —
    /// 90 s of wearer-sanctioned replacement, costing possession of the watch
    /// instead of mere radio range), with FACTORY ERASE (§378) remaining the
    /// scorched-earth fallback that also clears `BND1`.
    pub struct Bonder {
        /// The one remembered phone, behind the erase-generation check that
        /// retires it. A [`pairing::BondCell`] rather than a bare `Cell`
        /// because the check is not optional and a call site that skipped it
        /// served a wiped owner's keys twice before the type existed — the
        /// FACTORY ERASE bumps the generation and the firmware never reboots,
        /// so nothing else would retire them.
        peer: pairing::BondCell<Peer>,
        sys_attrs: RefCell<heapless::Vec<u8, 64>>,
    }

    impl Default for Bonder {
        fn default() -> Self {
            Bonder {
                peer: pairing::BondCell::new(),
                sys_attrs: RefCell::new(heapless::Vec::new()),
            }
        }
    }

    impl Bonder {
        /// The stored peer, or `None` once a factory erase has retired it.
        fn live_peer(&self) -> Option<Peer> {
            self.peer.live(state::bond_erase_gen())
        }

        /// Whether a live bond is held.
        fn is_bonded(&self) -> bool {
            self.peer.is_live(state::bond_erase_gen())
        }

        /// Adopt `peer` as of the current erase generation.
        fn set_peer(&self, peer: Option<Peer>) {
            self.peer.set(peer, state::bond_erase_gen());
        }
    }

    /// Signals [`bond_persist`] that `on_bonded` staged fresh keys to persist.
    static BOND_SAVED: Signal<CriticalSectionRawMutex, ()> = Signal::new();

    /// Signals [`run`] that a central asked to pair while the watch already has
    /// a bond, so the connection can be dropped from task context — the
    /// `SecurityHandler` callbacks run inside the SoftDevice's event handler
    /// and are the wrong place to tear a link down, exactly as `on_bonded` is
    /// the wrong place to erase a flash page (hence [`BOND_SAVED`]).
    static PAIRING_REFUSED: Signal<CriticalSectionRawMutex, ()> = Signal::new();

    /// Persist freshly-staged bond keys to the flash config page. A DEDICATED
    /// task, not a branch of the connection's serve loop: many centrals
    /// disconnect immediately after pairing completes, and a disconnect
    /// resolves the `select(gatt, stream)` in [`run`] and DROPS the stream
    /// future — which would cancel an in-flight `persist_bond` mid-erase and
    /// (fail-closed but silently) lose both the bond and the stored GNSS mode
    /// on exactly the connection where bonding just happened. This task is
    /// never cancelled, so the erase+write transaction always runs to
    /// completion. L4 best-effort — a failed write only means re-pairing
    /// after reboot, never a broken link now.
    #[embassy_executor::task]
    pub async fn bond_persist(store: &'static SharedStore, bonder: &'static Bonder) -> ! {
        loop {
            BOND_SAVED.wait().await;
            if let Some(rec) = bonder.live_peer().map(Peer::to_record) {
                store.lock().await.persist_bond(rec).await;
            }
        }
    }

    impl SecurityHandler for Bonder {
        fn io_capabilities(&self) -> IoCapabilities {
            // No keyboard, and the tier-1 face has no passkey page: just-works
            // (no MITM protection during the one-time pairing — see the module
            // doc's threat note).
            IoCapabilities::None
        }

        /// Bond only while [`pairing::may_bond`] says so: always before the
        /// first bond, and afterwards only inside a wearer-opened §432
        /// window. Signals the refusal so [`run`] can drop the central that
        /// asked — see the type doc for why an unsanctioned second bond is a
        /// takeover rather than a re-pair.
        fn can_bond(&self, _conn: &Connection) -> bool {
            let now_s = Instant::now().as_secs() as u32;
            let ok = pairing::may_bond(self.is_bonded(), state::pairing_window_open(now_s));
            if !ok {
                PAIRING_REFUSED.signal(());
            }
            ok
        }

        /// Refuse the *pairing*, not merely the bond, whenever the bond would
        /// be refused.
        ///
        /// `can_bond` returning false only clears the bonding bit: the pairing
        /// still completes, the link still reaches Mode 1 Level 2, and Level 2
        /// is exactly what every characteristic's `justworks` gate accepts — so
        /// the stranger would read the whole run history over a session key and
        /// merely fail to persist. Requiring MITM protection while
        /// [`Self::io_capabilities`] is `None` names a combination just-works
        /// cannot satisfy, so the SoftDevice fails the pairing procedure on
        /// authentication requirements instead of completing it.
        ///
        /// The exact negation of [`pairing::may_bond`], evaluated at the same
        /// gate: an unpaired watch (and a §432 window) must still pair with no
        /// interaction, since there is no passkey face to interact with.
        fn request_mitm_protection(&self, _conn: &Connection) -> bool {
            let now_s = Instant::now().as_secs() as u32;
            !pairing::may_bond(self.is_bonded(), state::pairing_window_open(now_s))
        }

        fn on_security_update(&self, _conn: &Connection, security_mode: SecurityMode) {
            info!("ble: security update {:?}", security_mode);
        }

        fn on_bonded(
            &self,
            _conn: &Connection,
            master_id: MasterId,
            key: EncryptionInfo,
            peer_id: IdentityKey,
        ) {
            info!("ble: bonded (ediv {=u16})", master_id.ediv);
            // A §432 window is spent the moment it admits one bond — left
            // open, the 90 s tail would invite a SECOND replacement behind
            // the phone that just paired.
            state::close_pairing_window();
            // Fresh bond, fresh CCCD state.
            self.sys_attrs.borrow_mut().clear();
            self.set_peer(Some(Peer {
                master_id,
                key,
                peer_id,
            }));
            BOND_SAVED.signal(());
        }

        fn get_key(&self, _conn: &Connection, master_id: MasterId) -> Option<EncryptionInfo> {
            self.live_peer()
                .and_then(|peer| (master_id == peer.master_id).then_some(peer.key))
        }

        fn save_sys_attrs(&self, conn: &Connection) {
            if let Some(peer) = self.live_peer() {
                if peer.peer_id.is_match(conn.peer_address()) {
                    let mut sys_attrs = self.sys_attrs.borrow_mut();
                    let capacity = sys_attrs.capacity();
                    unwrap!(sys_attrs.resize(capacity, 0));
                    match get_sys_attrs(conn, &mut sys_attrs) {
                        Ok(len) => sys_attrs.truncate(len),
                        Err(e) => {
                            warn!("ble: get_sys_attrs failed {:?}", e);
                            sys_attrs.clear();
                        }
                    }
                }
            }
        }

        fn load_sys_attrs(&self, conn: &Connection) {
            let attrs = self.sys_attrs.borrow();
            let attrs = if self
                .live_peer()
                .map(|peer| peer.peer_id.is_match(conn.peer_address()))
                .unwrap_or(false)
            {
                (!attrs.is_empty()).then_some(attrs.as_slice())
            } else {
                None
            };
            if let Err(e) = set_sys_attrs(conn, attrs) {
                warn!("ble: set_sys_attrs failed {:?}", e);
            }
        }
    }

    /// The SoftDevice's own background task — must be spawned exactly once and
    /// run forever, or the stack stops servicing radio events.
    #[embassy_executor::task]
    pub async fn softdevice_task(sd: &'static Softdevice) -> ! {
        sd.run().await
    }

    /// SoftDevice enable config: internal RC low-freq clock, one advertising
    /// set, 256-byte ATT MTU. `gap_device_name` is what a scanner shows.
    ///
    /// **Two roles at once.** The watch is a peripheral to the phone (this
    /// task) and a central to an external HR strap (`hr_strap`, §365), so
    /// `conn_count` is 2 and one central role is declared. That raises the
    /// SoftDevice's RAM requirement above the peripheral-only figure; the
    /// linker script's 31 KiB reservation is a carried-over over-estimate from
    /// a six-connection example and is expected to still cover it, but only
    /// the device can say — `Softdevice::enable` prints the true RAM start at
    /// boot, and confirming it is a bench item (`memory-ble.x`,
    /// `docs/custom_watch/quality_standards.md` step 6).
    ///
    /// `central_sec_count` stays 0: the Heart Rate Service is served
    /// unencrypted by every strap on the market, and the watch initiates no
    /// security as a central. A strap that demands encryption is out of scope
    /// at tier 1 and will simply fail to subscribe.
    pub fn config() -> nrf_softdevice::Config {
        nrf_softdevice::Config {
            clock: Some(raw::nrf_clock_lf_cfg_t {
                source: raw::NRF_CLOCK_LF_SRC_RC as u8,
                rc_ctiv: 16,
                rc_temp_ctiv: 2,
                accuracy: raw::NRF_CLOCK_LF_ACCURACY_500_PPM as u8,
            }),
            conn_gap: Some(raw::ble_gap_conn_cfg_t {
                conn_count: 2,
                event_length: 24,
            }),
            conn_gatt: Some(raw::ble_gatt_conn_cfg_t { att_mtu: 256 }),
            gatts_attr_tab_size: Some(raw::ble_gatts_cfg_attr_tab_size_t {
                attr_tab_size: raw::BLE_GATTS_ATTR_TAB_SIZE_DEFAULT,
            }),
            gap_role_count: Some(raw::ble_gap_cfg_role_count_t {
                adv_set_count: 1,
                periph_role_count: 1,
                central_role_count: 1,
                central_sec_count: 0,
                _bitfield_1: raw::ble_gap_cfg_role_count_t::new_bitfield_1(0),
            }),
            gap_device_name: Some(raw::ble_gap_cfg_device_name_t {
                p_value: b"Threkir" as *const u8 as _,
                current_len: 7,
                max_len: 7,
                write_perm: unsafe { core::mem::zeroed() },
                _bitfield_1: raw::ble_gap_cfg_device_name_t::new_bitfield_1(
                    raw::BLE_GATTS_VLOC_STACK as u8,
                ),
            }),
            ..Default::default()
        }
    }

    static ADV_DATA: LegacyAdvertisementPayload = LegacyAdvertisementBuilder::new()
        .flags(&[Flag::GeneralDiscovery, Flag::LE_Only])
        .full_name("Threkir")
        .build();

    static SCAN_DATA: LegacyAdvertisementPayload = LegacyAdvertisementBuilder::new()
        .services_128(ServiceList::Complete, &[LINK_SERVICE_UUID.to_le_bytes()])
        .build();

    /// Republish the `run_manifest` characteristic value if the store's manifest
    /// generation has moved since `built_gen` — returning the value now
    /// published, or `None` when the one already published still stands.
    ///
    /// The manifest changes when a run finishes, is evicted, or is fully pulled;
    /// rebuilding it on every 1 Hz tick instead meant a `manifest_at` + encode +
    /// SoftDevice value-set per second for the whole time a phone was connected,
    /// whether or not it ever read the characteristic. The decision itself is
    /// [`ble_sync::manifest_needs_rebuild`], host-tested there like every other
    /// choice this transport makes — including that a `None` `built_gen` (a
    /// fresh link) always publishes once before its first read.
    ///
    /// The one thing this trades away is the header's uptime anchor: it is the
    /// value at the last rebuild, not at the last tick, so within a connection
    /// where nothing changed it can lag. A lagging anchor makes a run read as
    /// YOUNGER than it is (`now - (uptime - start)`), which is the direction the
    /// phone already handles — `SlotDir::manifest_at` documents the same
    /// under-aging for a run recovered across a power cycle, and
    /// `payloadFromBlob` falls back to the blob footer's elapsed time when the
    /// offset is shorter than the run itself.
    async fn refresh_manifest(
        server: &Server,
        store: &SharedStore,
        built_gen: &mut Option<u32>,
        uptime_s: u32,
    ) -> Option<Vec<u8, MANIFEST_CAP>> {
        // Clamp each run's start to the current uptime so a run recovered from a
        // prior power cycle can't advertise a start ahead of `uptime_s` and date
        // in the future on the phone (run_flash::manifest_at).
        let (gen, entries) = {
            let guard = store.lock().await;
            let gen = guard.manifest_gen();
            if !ble_sync::manifest_needs_rebuild(*built_gen, gen) {
                return None;
            }
            (gen, guard.manifest_at(uptime_s))
        };
        let manifest = ble_sync::encode_manifest(&entries, uptime_s);
        if let Err(e) = server.link.run_manifest_set(&manifest) {
            // Leave `built_gen` alone so the next tick retries: a failed set
            // means the published value is still the OLD list.
            debug!("ble: manifest set failed {:?}", e);
            return None;
        }
        *built_gen = Some(gen);
        Some(manifest)
    }

    /// Advertise → serve → re-advertise on disconnect, forever. While
    /// connected, push one status frame per second (only once the phone has
    /// subscribed, tracked via the CCCD write event); keep the run manifest
    /// characteristic fresh; and answer each `run_chunk` write with the
    /// requested slice of the run blob (README step 7). Bond persistence
    /// lives in [`bond_persist`], deliberately outside this task's
    /// connection-scoped select (issue #598).
    #[embassy_executor::task]
    pub async fn run(
        sd: &'static Softdevice,
        server: &'static Server,
        store: &'static SharedStore,
        bonder: &'static Bonder,
    ) -> ! {
        // Receivers are acquired ONCE: a `Watch` hands out a fixed number and
        // re-subscribing on every reconnect would exhaust it. `latest`/`elev`
        // persist across reconnects so a fresh connection sees last-known data.
        let mut fix_rx = unwrap!(state::FIX.receiver());
        let mut elev_rx = unwrap!(state::ELEVATION.receiver());
        let course_sender = state::COURSE.sender();
        let mut latest = None;
        let mut elev = None;

        // Publish the pre-push verdict so a phone that reads `push_status`
        // before ever pushing gets a well-formed `PSH1` at sequence 0 rather
        // than an empty value — which its decoder would (correctly) refuse,
        // and which would then read as "this firmware has no verdict to give".
        if let Err(e) = server
            .link
            .push_status_set(&push_status_value(&PushOutcome::DEFAULT))
        {
            debug!("ble: push status init failed {:?}", e);
        }

        // Re-arm the bonder with the bond persisted across the power cycle
        // (fail-closed: an erased/corrupt record just means re-pair).
        if let Some(rec) = store.lock().await.read_bond() {
            info!(
                "ble: restored persisted bond (ediv {=u16})",
                rec.master_ediv
            );
            bonder.set_peer(Some(Peer::from_record(&rec)));
        }

        loop {
            let adv = peripheral::ConnectableAdvertisement::ScannableUndirected {
                adv_data: &ADV_DATA,
                scan_data: &SCAN_DATA,
            };
            // Pairable on EVERY pass, bonded or not, and that is deliberate:
            // `advertise_pairable` and `advertise_connectable` emit the same
            // bytes through the same `advertise_inner` — "pairable" is not an
            // on-air property here, it is only whether the resulting
            // `Connection` carries the security handler. And the handler is
            // what answers the SoftDevice's SEC_INFO_REQUEST with the stored
            // LTK when the bonded phone reconnects, so dropping it once bonded
            // would close the data plane against the one peer it exists for
            // (the SoftDevice would get a null key and never encrypt).
            // Refusing a SECOND pairing is the bonder's job instead
            // (`can_bond` + `request_mitm_protection`), and until either
            // pairing or a reconnect encrypts the link, every
            // characteristic's justworks gate keeps the data plane closed.
            let conn = match peripheral::advertise_pairable(
                sd,
                adv,
                &peripheral::Config::default(),
                bonder,
            )
            .await
            {
                Ok(conn) => conn,
                Err(e) => {
                    warn!("ble: advertise failed {:?}", e);
                    Timer::after(Duration::from_secs(1)).await;
                    continue;
                }
            };
            info!("ble: phone connected");
            // A refusal staged against the PREVIOUS central must not kill this
            // connection: the signal is a static, so it outlives the link that
            // set it.
            PAIRING_REFUSED.reset();

            // Request a long connection interval. The default is 7.5 ms (built
            // for HID); a watch that streams one status frame per second and
            // otherwise syncs every few minutes wants ~1 s, which cuts idle
            // radio power by ~100x (performance_path.md "BLE connection-interval
            // tuning"). Best-effort — the central may renegotiate. Units:
            // interval 1.25 ms, supervision timeout 10 ms; timeout must exceed
            // (1 + latency) * max_interval * 2 (2 s here), 6 s clears it.
            if let Err(e) = conn.set_conn_params(raw::ble_gap_conn_params_t {
                min_conn_interval: 320, // 400 ms
                max_conn_interval: 800, // 1000 ms
                slave_latency: 0,
                conn_sup_timeout: 600, // 6000 ms
            }) {
                warn!("ble: set_conn_params failed {:?}", e);
            }

            // Shared between the GATT event handler (sets them on CCCD write /
            // enqueues a chunk request) and the serve loop (reads them). The
            // executor is single-threaded, so a Cell + a Channel suffice.
            let notifications = Cell::new(false);
            let manifest_notify = Cell::new(false);
            let chunk_req: Channel<CriticalSectionRawMutex, ChunkRequest, CHUNK_QUEUE_DEPTH> =
                Channel::new();
            // Reassembles a chunked course push over this connection. Interior
            // mutability (RefCell) keeps the GATT handler a plain `Fn`, like the
            // Cell/Signal above; the single-threaded executor makes it sound.
            let course_asm: RefCell<CourseAssembler> = RefCell::new(CourseAssembler::new());
            let workout_asm: RefCell<WorkoutAssembler> = RefCell::new(WorkoutAssembler::new());
            let roadbook_asm: RefCell<RoadbookAssembler> = RefCell::new(RoadbookAssembler::new());
            // EVERY way a push resolves funnels through here — all five
            // characteristics, accepted and refused alike. Each of the five is
            // latest-value, so a refusal leaves the OLD course / workout /
            // schedule / screens / settings armed while the runner's phone
            // just said "sent": the `warn!` beside each site reaches a debug
            // cable, this reaches the wrist (via `state::PUSH_OUTCOME` and the
            // alert engine) and the phone (via the `push_status`
            // characteristic this publishes).
            //
            // A plain `Fn`, like the Cell and Channel above, because that is
            // what `gatt_server::run`'s handler is; the SoftDevice value-set
            // is fallible and best-effort — a failed set only costs the phone
            // its verdict, never the wearer's banner.
            let note_push = |kind: PushKind, accepted: bool| {
                let outcome = state::note_push(kind, accepted);
                if let Err(e) = server.link.push_status_set(&push_status_value(&outcome)) {
                    debug!("ble: push status set failed {:?}", e);
                }
            };

            let gatt = gatt_server::run(&conn, server, |e| match e {
                ServerEvent::Link(e) => match e {
                    LinkServiceEvent::FrameCccdWrite { notifications: on } => {
                        info!("ble: link notifications {}", on);
                        notifications.set(on);
                    }
                    LinkServiceEvent::RunManifestCccdWrite { notifications: on } => {
                        info!("ble: manifest notifications {}", on);
                        manifest_notify.set(on);
                    }
                    LinkServiceEvent::RunChunkWrite(bytes) => match ChunkRequest::decode(&bytes) {
                        Some(req) => {
                            if chunk_req.try_send(req).is_err() {
                                warn!(
                                    "ble: chunk queue full, dropped run {=u32} @ {=u32}",
                                    req.run_seq, req.offset
                                );
                            }
                        }
                        None => warn!("ble: bad chunk request ({=usize} B)", bytes.len()),
                    },
                    LinkServiceEvent::RunChunkCccdWrite { notifications: on } => {
                        debug!("ble: chunk notifications {}", on);
                    }
                    LinkServiceEvent::SettingsWrite(bytes) => match WatchSettings::decode(&bytes) {
                        Some(s) => {
                            info!("ble: settings push ({=usize} B)", bytes.len());
                            // A full queue is a REFUSAL, not a delay: the
                            // channel drops the newest, so the runner's
                            // corrected zones / cadences never arrive at all.
                            match state::SETTINGS.try_send(s) {
                                Ok(()) => note_push(PushKind::Settings, true),
                                Err(_) => {
                                    warn!("ble: settings queue full, push refused");
                                    note_push(PushKind::Settings, false);
                                }
                            }
                        }
                        None => {
                            warn!("ble: bad settings frame ({=usize} B)", bytes.len());
                            note_push(PushKind::Settings, false);
                        }
                    },
                    // Whole-frame fail-closed: a refused set leaves whatever
                    // the watch already had, which is the 37 built-in pages at
                    // worst. A partially-applied one would put a screen in the
                    // cycle the runner never composed.
                    LinkServiceEvent::ScreensWrite(bytes) => match Screens::decode(&bytes) {
                        Some(set) => {
                            info!("ble: screens push ({=usize} screens)", set.len());
                            state::SCREENS.sender().send(Some(set));
                            note_push(PushKind::Screens, true);
                        }
                        None => {
                            warn!("ble: bad screens frame ({=usize} B)", bytes.len());
                            note_push(PushKind::Screens, false);
                        }
                    },
                    LinkServiceEvent::CourseWrite(bytes) => {
                        // Feed the reassembler; on completion decode + publish
                        // the course.
                        if let Some((offset, payload)) = ble_sync::parse_push_chunk(&bytes) {
                            let mut asm = course_asm.borrow_mut();
                            match asm.push(offset, payload) {
                                CoursePush::Complete => match course_store::decode(asm.frame()) {
                                    Some(course) => {
                                        info!(
                                            "ble: course push complete ({} points, {} m)",
                                            course.points().len(),
                                            course.total_m() as u32
                                        );
                                        course_sender.send(Some(course));
                                        asm.reset();
                                        note_push(PushKind::Course, true);
                                    }
                                    None => {
                                        warn!("ble: course frame failed to decode");
                                        asm.reset();
                                        note_push(PushKind::Course, false);
                                    }
                                },
                                CoursePush::More => {}
                                CoursePush::Rejected => {
                                    warn!("ble: bad course chunk @ {=usize}", offset);
                                    note_push(PushKind::Course, false);
                                }
                            }
                        } else {
                            warn!("ble: short course chunk ({=usize} B)", bytes.len());
                            note_push(PushKind::Course, false);
                        }
                    }
                    LinkServiceEvent::WorkoutWrite(bytes) => {
                        if let Some((offset, payload)) = ble_sync::parse_push_chunk(&bytes) {
                            let mut asm = workout_asm.borrow_mut();
                            match asm.push(offset, payload) {
                                WorkoutPush::Complete => match workout_store::decode(asm.frame()) {
                                    Some(steps) => {
                                        info!("ble: workout push complete ({} steps)", steps.len());
                                        state::WORKOUT.sender().send(Some(steps));
                                        asm.reset();
                                        note_push(PushKind::Workout, true);
                                    }
                                    None => {
                                        warn!("ble: workout frame failed to decode");
                                        asm.reset();
                                        note_push(PushKind::Workout, false);
                                    }
                                },
                                WorkoutPush::More => {}
                                WorkoutPush::Rejected => {
                                    warn!("ble: bad workout chunk @ {=usize}", offset);
                                    note_push(PushKind::Workout, false);
                                }
                            }
                        } else {
                            warn!("ble: short workout chunk ({=usize} B)", bytes.len());
                            note_push(PushKind::Workout, false);
                        }
                    }
                    LinkServiceEvent::RoadbookWrite(bytes) => {
                        if let Some((offset, payload)) = ble_sync::parse_push_chunk(&bytes) {
                            let mut asm = roadbook_asm.borrow_mut();
                            match asm.push(offset, payload) {
                                RoadbookPush::Complete => {
                                    match roadbook_store::decode(asm.frame()) {
                                        Some(rb) => {
                                            info!(
                                                "ble: roadbook push complete ({} checkpoints, {} cutoffs)",
                                                rb.checkpoints.len(),
                                                rb.cutoffs.len()
                                            );
                                            state::ROADBOOK.sender().send(Some(rb));
                                            asm.reset();
                                            note_push(PushKind::Roadbook, true);
                                        }
                                        None => {
                                            warn!("ble: roadbook frame failed to decode");
                                            asm.reset();
                                            note_push(PushKind::Roadbook, false);
                                        }
                                    }
                                }
                                RoadbookPush::More => {}
                                RoadbookPush::Rejected => {
                                    warn!("ble: bad roadbook chunk @ {=usize}", offset);
                                    note_push(PushKind::Roadbook, false);
                                }
                            }
                        } else {
                            warn!("ble: short roadbook chunk ({=usize} B)", bytes.len());
                            note_push(PushKind::Roadbook, false);
                        }
                    }
                },
            });

            let stream = async {
                let mut ticker = Ticker::every(Duration::from_secs(1));
                // Per-connection, so the first tick after a reconnect always
                // republishes: a run can finish while nothing is connected.
                let mut built_gen: Option<u32> = None;
                refresh_manifest(
                    server,
                    store,
                    &mut built_gen,
                    Instant::now().as_secs() as u32,
                )
                .await;
                loop {
                    match select(ticker.next(), chunk_req.receive()).await {
                        Either::First(()) => {
                            let now_s = Instant::now().as_secs() as u32;
                            if let Some(fix) = fix_rx.try_changed() {
                                latest = Some(fix);
                            }
                            if let Some(reading) = elev_rx.try_changed() {
                                elev = Some(reading);
                            }

                            // Republish the manifest only when the run list moved,
                            // and notify the change if the phone subscribed.
                            if let Some(manifest) =
                                refresh_manifest(server, store, &mut built_gen, now_s).await
                            {
                                if manifest_notify.get() {
                                    if let Err(e) =
                                        server.link.run_manifest_notify(&conn, &manifest)
                                    {
                                        debug!("ble: manifest notify failed {:?}", e);
                                    }
                                }
                            }

                            if notifications.get() {
                                let frame =
                                    link::status_frame(latest.as_ref(), elev.as_ref(), now_s);
                                let bytes = frame.as_bytes();
                                let mut buf: Vec<u8, FRAME_CAP> = Vec::new();
                                // Frames fit FRAME_CAP; the clamp is belt-and-braces
                                // so a future wider frame truncates rather than
                                // refuses to build.
                                let n = bytes.len().min(FRAME_CAP);
                                let _ = buf.extend_from_slice(&bytes[..n]);
                                if let Err(e) = server.link.frame_notify(&conn, &buf) {
                                    debug!("ble: notify failed {:?}", e);
                                }
                            }
                        }
                        Either::Second(req) => {
                            // Clamp to the notify MTU; read_chunk further clamps
                            // to the blob end. An empty reply means unknown run
                            // or past-the-end, so the phone isn't left waiting.
                            let want =
                                ble_sync::chunk_notify_len(req.len, FRAME_CAP as u16) as usize;
                            let mut scratch = [0u8; FRAME_CAP];
                            let n = {
                                let mut guard = store.lock().await;
                                let n =
                                    guard.read_chunk(req.run_seq, req.offset, &mut scratch[..want]);
                                // Reaching the blob end means the phone has pulled
                                // this whole run: mark it synced so eviction keeps
                                // a still-unsynced run over it.
                                if n > 0 {
                                    guard.mark_synced_if_complete(
                                        req.run_seq,
                                        req.offset + n as u32,
                                    );
                                }
                                n
                            };
                            let mut out: Vec<u8, FRAME_CAP> = Vec::new();
                            let _ = out.extend_from_slice(&scratch[..n]);
                            if let Err(e) = server.link.run_chunk_notify(&conn, &out) {
                                debug!("ble: chunk notify failed {:?}", e);
                            }
                        }
                    }
                }
            };

            match select3(gatt, stream, PAIRING_REFUSED.wait()).await {
                Either3::First(e) => info!("ble: phone disconnected ({:?})", e),
                Either3::Second(()) => {}
                Either3::Third(()) => {
                    warn!("ble: pairing refused — already bonded, dropping central");
                    let _ = conn.disconnect();
                }
            }
        }
    }
}
