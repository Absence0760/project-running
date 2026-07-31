//! External BLE heart-rate strap — the GATT **central** role (§365).
//!
//! Everywhere else in this firmware the watch is a peripheral: `ble.rs` serves
//! the Threkir service and the phone is the central. Here the roles invert.
//! The watch scans for a peripheral advertising the standard Heart Rate
//! Service (0x180D), connects to it, subscribes to Heart Rate Measurement
//! notifications (0x2A37), and publishes each decoded reading to
//! `state::HR_STRAP`, from where the `hr_source` arbiter decides whether it or
//! the on-wrist optical sensor is what the watch shows.
//!
//! Compiled only under the `ble` feature — it needs the S140 SoftDevice, whose
//! config `ble::config()` now declares one central role and two concurrent
//! connections (phone + strap).
//!
//! **Everything pure lives in `watch_core::hr_source`**, host-tested: the
//! advertising-data filter that decides a scan report belongs to a strap, the
//! Heart Rate Measurement codec (its flags byte selects a uint8 or uint16 rate
//! and declares two optional trailing fields, so the frame's length is a
//! function of its own first byte), the physiological + skin-contact rules
//! that make a reading trustworthy, and the precedence rule itself. What is
//! left here is radio glue.
//!
//! **UNVERIFIED — build-verified only, and it can never be more without
//! hardware.** Renode cannot run the proprietary SoftDevice (decisions § 210),
//! so nothing in this file has ever executed: not the scan, not the
//! connection, not one notification. Host tests over `hr_source` prove what the
//! bytes mean, not that a byte arrived. Two specific things need the bench
//! before any of this can be believed: whether a real strap's advertisement
//! passes the filter (some straps carry the service UUID only in their scan
//! response), and whether the S140's RAM requirement with a *second*
//! connection still fits `memory-ble.x`'s 31 KiB reservation — the SoftDevice
//! reports the true figure at boot, and until it does the reservation is a
//! guess carried over from a six-connection example.
//!
//! Fail-closed throughout: a malformed advertisement is not a strap, a
//! measurement whose flags and length disagree is dropped whole, a strap off
//! the chest publishes no rate, and a disconnect publishes an explicit blank
//! so the wrist sensor takes back over immediately rather than after the
//! staleness budget.

use core::slice;

use defmt::*;
use embassy_time::{Duration, Instant, Timer};
use heapless::Vec;
use nrf_softdevice::ble::{central, gatt_client, Address};
use nrf_softdevice::{raw, Softdevice};
use watch_core::hr_duty::HrSample;
use watch_core::hr_source::{self, HR_MEASUREMENT_CAP, SCAN_GAP_S, SCAN_WINDOW_S, STRAP_ATT_MTU};

use crate::state;

#[nrf_softdevice::gatt_client(uuid = "180d")]
struct HeartRateClient {
    #[characteristic(uuid = "2a37", notify)]
    heart_rate_measurement: Vec<u8, HR_MEASUREMENT_CAP>,
}

/// Scan / connect timeout in the SoftDevice's 10 ms units.
const SCAN_TIMEOUT_UNITS: u16 = (SCAN_WINDOW_S * 100) as u16;

/// The same long connection interval the phone link negotiates: a strap
/// notifies at ~1 Hz, so a 400–1000 ms interval costs nothing in freshness and
/// keeps idle radio power off the multi-day budget
/// (`docs/custom_watch/performance_path.md`). Units are 1.25 ms for the
/// intervals and 10 ms for the supervision timeout, which must exceed
/// `(1 + latency) * max_interval * 2` = 2 s.
const CONN_PARAMS: raw::ble_gap_conn_params_t = raw::ble_gap_conn_params_t {
    min_conn_interval: 320,
    max_conn_interval: 800,
    slave_latency: 0,
    conn_sup_timeout: 600,
};

/// Scan one bounded window for a peripheral offering the Heart Rate Service.
async fn find_strap(sd: &Softdevice) -> Option<Address> {
    let config = central::ScanConfig {
        timeout: SCAN_TIMEOUT_UNITS,
        ..Default::default()
    };
    let found = central::scan(sd, &config, |report| {
        // A report can carry no data at all; `from_raw_parts` on a null
        // pointer is UB, so the emptiness check comes before the slice.
        if report.data.len == 0 || report.data.p_data.is_null() {
            return None;
        }
        let ad = unsafe { slice::from_raw_parts(report.data.p_data, report.data.len as usize) };
        hr_source::advertises_heart_rate_service(ad).then(|| Address::from_raw(report.peer_addr))
    })
    .await;
    match found {
        Ok(addr) => Some(addr),
        Err(central::ScanError::Timeout) => None,
        Err(e) => {
            warn!("hr_strap: scan failed {:?}", e);
            None
        }
    }
}

/// One scan → connect → stream cycle. `true` once a strap link was actually
/// established, which is what tells [`run`] to re-scan straight away rather
/// than paying the between-window gap: a strap that briefly walked out of
/// range should come back in seconds, a watch with no strap at all should not
/// scan continuously.
async fn session(sd: &Softdevice) -> bool {
    let Some(addr) = find_strap(sd).await else {
        return false;
    };
    // A strap's BLE address is a stable identifier that follows one wearer
    // between sessions, so it sits behind the default-off gate too.
    #[cfg(feature = "log-personal-data")]
    info!("hr_strap: candidate {:?}", addr);
    #[cfg(not(feature = "log-personal-data"))]
    info!("hr_strap: candidate found");
    let addrs = [&addr];
    let config = central::ConnectConfig {
        att_mtu: Some(STRAP_ATT_MTU),
        scan_config: central::ScanConfig {
            whitelist: Some(&addrs),
            timeout: SCAN_TIMEOUT_UNITS,
            ..Default::default()
        },
        conn_params: CONN_PARAMS,
    };
    let conn = match central::connect(sd, &config).await {
        Ok(conn) => conn,
        Err(e) => {
            warn!("hr_strap: connect failed {:?}", e);
            return false;
        }
    };
    let client: HeartRateClient = match gatt_client::discover(&conn).await {
        Ok(client) => client,
        Err(e) => {
            warn!("hr_strap: discovery failed {:?}", e);
            return false;
        }
    };
    if let Err(e) = client.heart_rate_measurement_cccd_write(true).await {
        warn!("hr_strap: subscribe failed {:?}", e);
        return false;
    }
    info!("hr_strap: streaming");

    let sender = state::HR_STRAP.sender();
    gatt_client::run(&conn, &client, |event| match event {
        HeartRateClientEvent::HeartRateMeasurementNotification(bytes) => {
            match hr_source::parse_measurement(&bytes) {
                Some(measurement) => sender.send(HrSample {
                    bpm: measurement.trusted_bpm(),
                    at_s: Instant::now().as_secs() as u32,
                }),
                None => warn!("hr_strap: malformed measurement ({=usize} B)", bytes.len()),
            }
        }
    })
    .await;

    // Yield NOW rather than letting the last rate age out: the watch knows the
    // strap is gone, so it must stop outranking a wrist sensor that is still
    // reading.
    sender.send(HrSample {
        bpm: None,
        at_s: Instant::now().as_secs() as u32,
    });
    info!("hr_strap: disconnected");
    true
}

#[embassy_executor::task]
pub async fn run(sd: &'static Softdevice) -> ! {
    loop {
        if !session(sd).await {
            Timer::after(Duration::from_secs(u64::from(SCAN_GAP_S))).await;
        }
    }
}
