//! Barometer task — drives the Bosch BMP581 (per decisions.md § 90) over I²C,
//! turns pressure into altitude and cumulative vert via the host-tested
//! `watch_core::elevation`, and publishes a snapshot to `state::ELEVATION` for
//! the status face (ALT + VERT rows) and the phone link's `elev` field.
//!
//! Same resilience shape as the HR task: the blocking driver must not spin the
//! executor on a bus that never answers, so an async, timeout-bounded probe
//! gates it — an absent BMP581 (the Renode sim, an unwired bench) parks the
//! task rather than wedging it. Vert is an auxiliary layer over the L1 GPS
//! distance the recorder already owns.

use bmp581::{Bmp581, I2C_ADDR};
use defmt::*;
use embassy_nrf::twim::Twim;
use embassy_time::{with_timeout, Duration, Ticker};
use embedded_hal::i2c::Operation;
use watch_core::elevation::{altitude_m, VertAccumulator, STANDARD_SEA_LEVEL_PA};
use watch_core::record::{RecordState, MIN_MOVING_SPEED_MPS};

use crate::state;

const SAMPLE: Duration = Duration::from_secs(1);
const PROBE_TIMEOUT: Duration = Duration::from_millis(200);

#[embassy_executor::task]
pub async fn run(mut twim: Twim<'static>) {
    let mut probe = [0u8; 1];
    match with_timeout(
        PROBE_TIMEOUT,
        twim.transaction(I2C_ADDR, &mut [Operation::Read(&mut probe)]),
    )
    .await
    {
        Err(_) => {
            warn!("baro: no BMP581 on I2C (probe timed out); task parked");
            return;
        }
        Ok(Err(e)) => {
            warn!("baro: BMP581 probe failed {:?}; task parked", e);
            return;
        }
        Ok(Ok(())) => {}
    }

    let mut sensor = Bmp581::new(twim);
    if let Err(e) = sensor.init() {
        warn!("baro: BMP581 init failed {:?}; task parked", e);
        return;
    }
    let elevation_tx = state::ELEVATION.sender();
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut sea_level_rx = unwrap!(state::SEA_LEVEL_PA.receiver());
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut vert = VertAccumulator::new();
    let mut moving = false;
    // QNH reference for the altitude conversion. Defaults to the ISA standard
    // until a phone settings push recalibrates it (state::SEA_LEVEL_PA) — the
    // weather-front case where the fixed standard drifts the whole altitude.
    let mut sea_level_pa = STANDARD_SEA_LEVEL_PA;
    let mut ticker = Ticker::every(SAMPLE);
    info!("baro: BMP581 streaming");
    loop {
        ticker.next().await;
        // Pick up the latest recording state without blocking the sample tick;
        // vert only accumulates while a run is actively moving, so barometric
        // drift during a stop (aid station, sleep, weather on a col) banks
        // nothing (watch_core::elevation::VertAccumulator::push).
        if let Some(snap) = rec_rx.try_changed() {
            moving = snap.state == RecordState::Recording
                && snap.current_speed_mps >= MIN_MOVING_SPEED_MPS as f32;
        }
        // Pick up a recalibrated sea-level reference without blocking the tick.
        if let Some(pa) = sea_level_rx.try_changed() {
            sea_level_pa = pa;
        }
        match sensor.read_pressure_pa() {
            Ok(Some(pa)) => {
                let alt = altitude_m(pa, sea_level_pa);
                // Fresh GPS altitude corroborates the barometer against weather
                // drift (elevation's complementary filter): only a fresh fix
                // slews the bias, so signal loss freezes it rather than dragging
                // it toward a stale altitude. Read inside the pressure arm so a
                // read miss never consumes/drops a fix.
                let gps_alt = fix_rx.try_changed().and_then(|f| f.alt_m);
                let corrected = vert.push(alt, moving, gps_alt);
                let reading = vert.reading(corrected);
                debug!(
                    "baro: alt={}m gain={}m loss={}m",
                    reading.alt_m, reading.gain_m, reading.loss_m
                );
                elevation_tx.send(reading);
            }
            Ok(None) => {}
            Err(e) => warn!("baro: read error {:?}", e),
        }
    }
}
