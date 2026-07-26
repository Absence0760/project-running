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
//! Also UNVERIFIED on hardware, but flash access IS SoftDevice-coordinated:
//! on this build `run_flash`'s backend is `nrf_softdevice::Flash`, so every
//! erase/write is arbitrated by the S140 (see the `run_flash` module doc's
//! backend-split note).
//!
//! Security (issue #598): the service is **fail-closed against unpaired
//! peers**. Every characteristic requires an encrypted link
//! (`security = "justworks"` — Security Mode 1 Level 2), advertising is
//! pairable ([`peripheral::advertise_pairable`]) with a bonding
//! [`SecurityHandler`], and the one bond persists to the flash config page
//! (`run_flash::persist_bond`) so a paired phone survives a power cycle. An
//! unbonded central can connect and see the service structure, but every
//! read / write / CCCD subscription on it is rejected by the SoftDevice until
//! pairing completes — run tracks (location history), settings pushes, and
//! course pushes never cross an unencrypted link. Just-works pairing carries
//! no MITM protection: the watch has no keyboard and its display code has no
//! passkey UI at tier 1, so an active in-range attacker during the one-time
//! pairing itself is accepted as out of scope (documented, not hidden).

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
    use embassy_futures::select::{select, Either};
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
    use watch_core::ble_sync::{self, CHUNK_QUEUE_DEPTH, MANIFEST_CAP};
    use watch_core::course_store::{self, CourseAssembler, CoursePush, COURSE_CHUNK_CAP};
    use watch_core::flash_store::BondRecord;
    use watch_core::link;
    use watch_core::run_store::ChunkRequest;
    use watch_core::settings::{WatchSettings, MAX_SETTINGS_LEN};

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
    /// config page. A NEW pairing replaces the old bond — losing a phone must
    /// not brick the watch — which is the standard single-bond wearable
    /// trade-off: possession of the watch (re-pair) beats possession of old
    /// radio captures.
    pub struct Bonder {
        peer: Cell<Option<Peer>>,
        sys_attrs: RefCell<heapless::Vec<u8, 64>>,
    }

    impl Default for Bonder {
        fn default() -> Self {
            Bonder {
                peer: Cell::new(None),
                sys_attrs: RefCell::new(heapless::Vec::new()),
            }
        }
    }

    /// Signals [`bond_persist`] that `on_bonded` staged fresh keys to persist.
    static BOND_SAVED: Signal<CriticalSectionRawMutex, ()> = Signal::new();

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
            if let Some(rec) = bonder.peer.get().map(Peer::to_record) {
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

        fn can_bond(&self, _conn: &Connection) -> bool {
            true
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
            // Fresh bond, fresh CCCD state.
            self.sys_attrs.borrow_mut().clear();
            self.peer.set(Some(Peer {
                master_id,
                key,
                peer_id,
            }));
            BOND_SAVED.signal(());
        }

        fn get_key(&self, _conn: &Connection, master_id: MasterId) -> Option<EncryptionInfo> {
            self.peer
                .get()
                .and_then(|peer| (master_id == peer.master_id).then_some(peer.key))
        }

        fn save_sys_attrs(&self, conn: &Connection) {
            if let Some(peer) = self.peer.get() {
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
                .peer
                .get()
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

    /// SoftDevice enable config. Mirrors nrf-softdevice's nRF52840 example:
    /// internal RC low-freq clock, one advertising set, peripheral-only roles,
    /// 256-byte ATT MTU. `gap_device_name` is what a scanner shows.
    pub fn config() -> nrf_softdevice::Config {
        nrf_softdevice::Config {
            clock: Some(raw::nrf_clock_lf_cfg_t {
                source: raw::NRF_CLOCK_LF_SRC_RC as u8,
                rc_ctiv: 16,
                rc_temp_ctiv: 2,
                accuracy: raw::NRF_CLOCK_LF_ACCURACY_500_PPM as u8,
            }),
            conn_gap: Some(raw::ble_gap_conn_cfg_t {
                conn_count: 1,
                event_length: 24,
            }),
            conn_gatt: Some(raw::ble_gatt_conn_cfg_t { att_mtu: 256 }),
            gatts_attr_tab_size: Some(raw::ble_gatts_cfg_attr_tab_size_t {
                attr_tab_size: raw::BLE_GATTS_ATTR_TAB_SIZE_DEFAULT,
            }),
            gap_role_count: Some(raw::ble_gap_cfg_role_count_t {
                adv_set_count: 1,
                periph_role_count: 1,
                central_role_count: 0,
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

    /// Build the manifest characteristic value from the store's current run list.
    async fn build_manifest(store: &SharedStore, uptime_s: u32) -> Vec<u8, MANIFEST_CAP> {
        // Clamp each run's start to the current uptime so a run recovered from a
        // prior power cycle can't advertise a start ahead of `uptime_s` and date
        // in the future on the phone (run_flash::manifest_at).
        let entries = store.lock().await.manifest_at(uptime_s);
        ble_sync::encode_manifest(&entries, uptime_s)
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

        // Re-arm the bonder with the bond persisted across the power cycle
        // (fail-closed: an erased/corrupt record just means re-pair).
        if let Some(rec) = store.lock().await.read_bond() {
            info!(
                "ble: restored persisted bond (ediv {=u16})",
                rec.master_ediv
            );
            bonder.peer.set(Some(Peer::from_record(&rec)));
        }

        loop {
            let adv = peripheral::ConnectableAdvertisement::ScannableUndirected {
                adv_data: &ADV_DATA,
                scan_data: &SCAN_DATA,
            };
            // Pairable: the connection carries the security handler, so a
            // central's pairing request negotiates just-works LESC bonding
            // instead of being rejected — and until it does, every
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
                            if state::SETTINGS.try_send(s).is_err() {
                                warn!("ble: settings queue full, push refused");
                            }
                        }
                        None => warn!("ble: bad settings frame ({=usize} B)", bytes.len()),
                    },
                    LinkServiceEvent::CourseWrite(bytes) => {
                        // Feed the reassembler; on completion decode + publish
                        // the course.
                        if let Some((offset, payload)) = ble_sync::parse_course_chunk(&bytes) {
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
                                    }
                                    None => {
                                        warn!("ble: course frame failed to decode");
                                        asm.reset();
                                    }
                                },
                                CoursePush::More => {}
                                CoursePush::Rejected => {
                                    warn!("ble: bad course chunk @ {=usize}", offset)
                                }
                            }
                        } else {
                            warn!("ble: short course chunk ({=usize} B)", bytes.len());
                        }
                    }
                },
            });

            let stream = async {
                let mut ticker = Ticker::every(Duration::from_secs(1));
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

                            // Refresh the manifest value so a read returns the
                            // current list; notify it too if the phone subscribed.
                            let manifest = build_manifest(store, now_s).await;
                            if let Err(e) = server.link.run_manifest_set(&manifest) {
                                debug!("ble: manifest set failed {:?}", e);
                            }
                            if manifest_notify.get() {
                                if let Err(e) = server.link.run_manifest_notify(&conn, &manifest) {
                                    debug!("ble: manifest notify failed {:?}", e);
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

            match select(gatt, stream).await {
                Either::First(e) => info!("ble: phone disconnected ({:?})", e),
                Either::Second(()) => {}
            }
        }
    }
}
