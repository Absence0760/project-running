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
    let mut vert = VertAccumulator::new();
    let mut moving = false;
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
        match sensor.read_pressure_pa() {
            Ok(Some(pa)) => {
                let alt = altitude_m(pa, STANDARD_SEA_LEVEL_PA);
                vert.push(alt, moving);
                let reading = vert.reading(alt);
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
