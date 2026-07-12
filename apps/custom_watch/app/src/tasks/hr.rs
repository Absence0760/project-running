//! HR task — drives the Maxim MAX86177 optical-HR AFE over I²C, runs the
//! host-tested peak-detect pipeline, and publishes a BPM estimate.
//!
//! The `max86177` driver is blocking, so a bus that never answers would spin
//! the executor forever. Optical HR is an auxiliary layer (decisions §80 /
//! the layered-resilience contract): its absence must not stall GPS, display,
//! or the phone link. So the first transaction is an async, timeout-bounded
//! presence probe; if it times out — the Renode sim has no MAX86177 model, and
//! a bench build may not have the part wired — the task parks instead of
//! wedging the blocking driver.
//!
//! The licensed Maxim HR algorithm is pulled in via `bindgen` post-tier-1;
//! tier 1 uses the naive peak-detect in `max86177::peak_detect`.

use defmt::*;
use embassy_nrf::twim::Twim;
use embassy_time::{with_timeout, Duration, Ticker};
use embedded_hal::i2c::Operation;
use max86177::peak_detect::{PeakDetector, Reading};
use max86177::{FifoWord, Max86177, I2C_ADDR, MEAS2_TAG};

use crate::state;

/// Matches the ~100 Hz PPG output rate the driver configures.
const SAMPLE_RATE_HZ: u32 = 100;
const POLL: Duration = Duration::from_millis(20);
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
            warn!("hr: no MAX86177 on I2C (probe timed out); task parked");
            return;
        }
        Ok(Err(e)) => {
            warn!("hr: MAX86177 probe failed {:?}; task parked", e);
            return;
        }
        Ok(Ok(())) => {}
    }

    let mut sensor = Max86177::new(twim);
    if let Err(e) = sensor.init() {
        warn!("hr: MAX86177 init failed {:?}; task parked", e);
        return;
    }
    let mut detector = PeakDetector::new(SAMPLE_RATE_HZ);
    let sender = state::HR.sender();
    let mut ticker = Ticker::every(POLL);
    info!("hr: MAX86177 streaming");
    // Latest ambient (LED-off) count; each PPG (LED-on) sample is corrected
    // against it so bright-sun ambient bleed can't rail the pulse. Starts at 0
    // (no subtraction) until the first ambient word arrives — an honest raw read.
    let mut ambient: i32 = 0;
    loop {
        ticker.next().await;
        let mut latest: Option<Reading> = None;
        loop {
            match sensor.read_tagged_sample() {
                Ok(Some(FifoWord { tag, value })) if tag == MEAS2_TAG => ambient = value as i32,
                Ok(Some(FifoWord { value, .. })) => {
                    latest = Some(detector.push_ambient(value as i32, ambient))
                }
                Ok(None) => break,
                Err(e) => {
                    warn!("hr: read error {:?}", e);
                    break;
                }
            }
        }
        if let Some(reading) = latest {
            sender.send(reading);
        }
    }
}
