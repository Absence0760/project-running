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
//! Out of scope for step 6 and still open (README step 7): handing a *finished
//! run* to the phone as a chunked file (`run_manifest` / `run_chunk` per
//! firmware.md). That needs an on-device run-storage layer (LittleFS) that
//! tier 1 doesn't have yet; the live status-frame notify below is the
//! foundation it will build on.

#[cfg(not(feature = "ble"))]
#[embassy_executor::task]
pub async fn run() {
    defmt::warn!("ble::run is a stub — build --features ble for the real radio (README step 6)");
}

#[cfg(feature = "ble")]
pub use imp::{config, run, softdevice_task, Server};

#[cfg(feature = "ble")]
mod imp {
    use core::cell::Cell;

    use defmt::*;
    use embassy_futures::select::{select, Either};
    use embassy_time::{Duration, Instant, Ticker, Timer};
    use heapless::Vec;
    use nrf_softdevice::ble::advertisement_builder::{
        Flag, LegacyAdvertisementBuilder, LegacyAdvertisementPayload, ServiceList,
    };
    use nrf_softdevice::ble::{gatt_server, peripheral};
    use nrf_softdevice::{raw, Softdevice};
    use watch_core::link;

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
    /// worst-case frame is ~160 bytes; see `link.rs`).
    const FRAME_CAP: usize = 244;

    #[nrf_softdevice::gatt_service(uuid = "d1f6a7e0-5b2c-4e9a-9c3d-1a2b3c4d5e6f")]
    pub struct LinkService {
        #[characteristic(uuid = "d1f6a7e1-5b2c-4e9a-9c3d-1a2b3c4d5e6f", read, notify)]
        frame: Vec<u8, FRAME_CAP>,
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

    /// Advertise → serve → re-advertise on disconnect, forever. While
    /// connected, push one status frame per second (only once the phone has
    /// subscribed to notifications, tracked via the CCCD write event).
    #[embassy_executor::task]
    pub async fn run(sd: &'static Softdevice, server: &'static Server) -> ! {
        // Receivers are acquired ONCE: a `Watch` hands out a fixed number and
        // re-subscribing on every reconnect would exhaust it. `latest`/`elev`
        // persist across reconnects so a fresh connection sees last-known data.
        let mut fix_rx = unwrap!(state::FIX.receiver());
        let mut elev_rx = unwrap!(state::ELEVATION.receiver());
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

            // Shared between the GATT event handler (sets it on CCCD write) and
            // the notify loop (reads it). Single-threaded executor, so a Cell
            // is enough — no atomics needed.
            let notifications = Cell::new(false);

            let gatt = gatt_server::run(&conn, server, |e| match e {
                ServerEvent::Link(LinkServiceEvent::FrameCccdWrite { notifications: on }) => {
                    info!("ble: notifications {}", on);
                    notifications.set(on);
                }
            });

            let stream = async {
                let mut ticker = Ticker::every(Duration::from_secs(1));
                loop {
                    ticker.next().await;
                    if let Some(fix) = fix_rx.try_changed() {
                        latest = Some(fix);
                    }
                    if let Some(reading) = elev_rx.try_changed() {
                        elev = Some(reading);
                    }
                    if !notifications.get() {
                        continue;
                    }
                    let frame = link::status_frame(
                        latest.as_ref(),
                        elev.as_ref(),
                        Instant::now().as_secs() as u32,
                    );
                    let bytes = frame.as_bytes();
                    let mut buf: Vec<u8, FRAME_CAP> = Vec::new();
                    // Frames fit FRAME_CAP; the clamp is belt-and-braces so a
                    // future wider frame truncates rather than refuses to build.
                    let n = bytes.len().min(FRAME_CAP);
                    let _ = buf.extend_from_slice(&bytes[..n]);
                    if let Err(e) = server.link.frame_notify(&conn, &buf) {
                        debug!("ble: notify failed {:?}", e);
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
