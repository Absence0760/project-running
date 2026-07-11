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
//! Also UNVERIFIED, and additionally: with the SoftDevice enabled, flash
//! access must be SoftDevice-coordinated — see the `run_flash` hardware caveat
//! (the NVMC backend must become `nrf_softdevice::Flash` before hardware use).

#[cfg(not(feature = "ble"))]
#[embassy_executor::task]
pub async fn run() {
    defmt::warn!("ble::run is a stub — build --features ble for the real radio (README step 6)");
}

#[cfg(feature = "ble")]
pub use imp::{config, run, softdevice_task, Server};

#[cfg(feature = "ble")]
mod imp {
    // The gatt_server macro names every characteristic event `<Name>...Write`,
    // so the generated LinkServiceEvent trips enum_variant_names once there is
    // more than one characteristic. The names are the macro's, not ours.
    #![allow(clippy::enum_variant_names)]

    use core::cell::Cell;

    use defmt::*;
    use embassy_futures::select::{select, Either};
    use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
    use embassy_sync::signal::Signal;
    use embassy_time::{Duration, Instant, Ticker, Timer};
    use heapless::Vec;
    use nrf_softdevice::ble::advertisement_builder::{
        Flag, LegacyAdvertisementBuilder, LegacyAdvertisementPayload, ServiceList,
    };
    use nrf_softdevice::ble::{gatt_server, peripheral};
    use nrf_softdevice::{raw, Softdevice};
    use watch_core::run_store::{
        ChunkRequest, ManifestHeader, MANIFEST_ENTRY_LEN, MANIFEST_HEADER_LEN,
    };
    use watch_core::settings::{WatchSettings, MAX_SETTINGS_LEN};
    use watch_core::{flash_store, link};

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

    /// Manifest characteristic value: a `ManifestHeader` + one `ManifestEntry`
    /// per slot. `flash_store::SLOT_COUNT` runs fit in one read/notify.
    const MANIFEST_CAP: usize = MANIFEST_HEADER_LEN + flash_store::SLOT_COUNT * MANIFEST_ENTRY_LEN;

    #[nrf_softdevice::gatt_service(uuid = "d1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f")]
    pub struct LinkService {
        #[characteristic(uuid = "d1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f", read, notify)]
        frame: Vec<u8, FRAME_CAP>,
        /// Finished-run manifest (README step 7). Read for the list; notified
        /// each second so a connected phone sees a run appear live.
        #[characteristic(uuid = "d1f6a7e2-5b2c-4e9a-9c3d-1a2b3c4d5e6f", read, notify)]
        run_manifest: Vec<u8, MANIFEST_CAP>,
        /// Run-chunk pull (README step 7). The phone WRITES a `ChunkRequest`;
        /// the watch notifies back that byte slice of the run blob.
        #[characteristic(uuid = "d1f6a7e3-5b2c-4e9a-9c3d-1a2b3c4d5e6f", write, notify)]
        run_chunk: Vec<u8, FRAME_CAP>,
        /// Settings push. The phone WRITES a `settings::WatchSettings` frame; the
        /// watch decodes it and publishes to `state::SETTINGS`, which the record
        /// task applies to the recorder + alert engine. Write-only — no readback.
        #[characteristic(uuid = "d1f6a7e4-5b2c-4e9a-9c3d-1a2b3c4d5e6f", write)]
        settings: Vec<u8, MAX_SETTINGS_LEN>,
    }

    #[nrf_softdevice::gatt_server]
    pub struct Server {
        link: LinkService,
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

    /// Build the manifest characteristic value: header (run count + the watch
    /// uptime anchor) followed by one entry per finished run.
    async fn build_manifest(store: &SharedStore, uptime_s: u32) -> Vec<u8, MANIFEST_CAP> {
        let entries = store.lock().await.manifest();
        let mut buf: Vec<u8, MANIFEST_CAP> = Vec::new();
        let header = ManifestHeader {
            run_count: entries.len() as u8,
            watch_uptime_s: uptime_s,
        };
        let _ = buf.extend_from_slice(&header.encode());
        for e in entries.iter() {
            let _ = buf.extend_from_slice(&e.encode());
        }
        buf
    }

    /// Advertise → serve → re-advertise on disconnect, forever. While
    /// connected, push one status frame per second (only once the phone has
    /// subscribed, tracked via the CCCD write event); keep the run manifest
    /// characteristic fresh; and answer each `run_chunk` write with the
    /// requested slice of the run blob (README step 7).
    #[embassy_executor::task]
    pub async fn run(
        sd: &'static Softdevice,
        server: &'static Server,
        store: &'static SharedStore,
    ) -> ! {
        // Receivers are acquired ONCE: a `Watch` hands out a fixed number and
        // re-subscribing on every reconnect would exhaust it. `latest`/`elev`
        // persist across reconnects so a fresh connection sees last-known data.
        let mut fix_rx = unwrap!(state::FIX.receiver());
        let mut elev_rx = unwrap!(state::ELEVATION.receiver());
        let settings_sender = state::SETTINGS.sender();
        let mut latest = None;
        let mut elev = None;

        loop {
            let adv = peripheral::ConnectableAdvertisement::ScannableUndirected {
                adv_data: &ADV_DATA,
                scan_data: &SCAN_DATA,
            };
            let conn =
                match peripheral::advertise_connectable(sd, adv, &peripheral::Config::default())
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
            // signals a chunk request) and the serve loop (reads them). The
            // executor is single-threaded, so a Cell + a Signal suffice.
            let notifications = Cell::new(false);
            let manifest_notify = Cell::new(false);
            let chunk_req: Signal<CriticalSectionRawMutex, ChunkRequest> = Signal::new();

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
                        Some(req) => chunk_req.signal(req),
                        None => warn!("ble: bad chunk request ({=usize} B)", bytes.len()),
                    },
                    LinkServiceEvent::RunChunkCccdWrite { notifications: on } => {
                        debug!("ble: chunk notifications {}", on);
                    }
                    LinkServiceEvent::SettingsWrite(bytes) => match WatchSettings::decode(&bytes) {
                        Some(s) => {
                            info!("ble: settings push ({=usize} B)", bytes.len());
                            settings_sender.send(Some(s));
                        }
                        None => warn!("ble: bad settings frame ({=usize} B)", bytes.len()),
                    },
                },
            });

            let stream = async {
                let mut ticker = Ticker::every(Duration::from_secs(1));
                loop {
                    match select(ticker.next(), chunk_req.wait()).await {
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
                            let want = (req.len as usize).min(FRAME_CAP);
                            let mut scratch = [0u8; FRAME_CAP];
                            let n = store.lock().await.read_chunk(
                                req.run_seq,
                                req.offset,
                                &mut scratch[..want],
                            );
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
