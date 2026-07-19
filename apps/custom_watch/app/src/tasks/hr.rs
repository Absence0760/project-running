//! HR task — drives the Maxim MAX86177 optical-HR AFE over I²C, runs the
//! host-tested peak-detect pipeline, and publishes a stamped BPM estimate.
//!
//! The `max86177` driver is blocking, so a bus that never answers would spin
//! the executor forever. Optical HR is an auxiliary layer (decisions §80 /
//! the layered-resilience contract): its absence must not stall GPS, display,
//! or the phone link. So the first transaction is an async, timeout-bounded
//! presence probe; if it times out — the Renode sim has no MAX86177 model, and
//! a bench build may not have the part wired — the task parks instead of
//! wedging the blocking driver.
//!
//! Sampling is duty-cycled to the selected GNSS recording mode's schedule
//! (`watch_core::hr_duty`): continuous in Performance, a short window per
//! minute-plus in Balanced / Expedition. Between windows the part is put into
//! shutdown — the LED drive current dominates HR power (README § Power
//! discipline) — and the FIFO stops being drained; on window open it is woken,
//! the FIFO flushed, and the detector reset so it re-converges on live samples
//! before anything is trusted. A sensor that won't wake degrades to "no HR"
//! for that window (L4) — consumers blank via the hold budget, recording is
//! untouched. The mode is frozen mid-run (BTN3 cycles pages then), so the
//! schedule never shifts under an open run.
//!
//! The licensed Maxim HR algorithm is pulled in via `bindgen` post-tier-1;
//! tier 1 uses the naive peak-detect in `max86177::peak_detect`.

use defmt::*;
use embassy_nrf::twim::Twim;
use embassy_time::{with_timeout, Duration, Instant, Timer};
use embedded_hal::i2c::Operation;
use max86177::peak_detect::{PeakDetector, Reading};
use max86177::{FifoWord, Max86177, I2C_ADDR, MEAS2_TAG};
use watch_core::gnss_mode::GnssMode;
use watch_core::hr_duty::{self, HrSample};

use crate::state;

/// Matches the ~100 Hz PPG output rate the driver configures.
const SAMPLE_RATE_HZ: u32 = 100;
const POLL: Duration = Duration::from_millis(20);
const PROBE_TIMEOUT: Duration = Duration::from_millis(200);

/// Back-off between wake retries when continuous sampling (no schedule to
/// defer to) hits a wake failure — keeps a dead bus off the 50 Hz poll pace.
const WAKE_RETRY: Duration = Duration::from_secs(1);

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
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut mode = GnssMode::default();
    let mut asleep = false;
    info!("hr: MAX86177 streaming");
    // Latest ambient (LED-off) count; each PPG (LED-on) sample is corrected
    // against it so bright-sun ambient bleed can't rail the pulse. Starts at 0
    // (no subtraction) until the first ambient word arrives — an honest raw read.
    let mut ambient: i32 = 0;
    loop {
        if let Some(m) = mode_rx.try_changed() {
            mode = m;
        }
        let now_s = Instant::now().as_secs() as u32;
        if let Some(w) = hr_duty::duty_window(mode) {
            if !w.is_on(now_s) {
                if !asleep {
                    // Treated as asleep even on failure — the next window's
                    // wake + flush is harmless on a part that never slept, and
                    // nothing is published while the window is closed either
                    // way; a failed shutdown only costs the power it was
                    // meant to save.
                    asleep = true;
                    match sensor.shutdown() {
                        Ok(()) => info!(
                            "hr: window closed; sensor shut down until {=u32}s",
                            w.next_start_s(now_s)
                        ),
                        Err(e) => warn!("hr: shutdown failed {:?}", e),
                    }
                }
                // Sleep to the next window start, but let an idle mode change
                // (BTN3) re-evaluate the schedule immediately.
                let wait_s = w.next_start_s(now_s).saturating_sub(now_s).max(1);
                if let Ok(m) =
                    with_timeout(Duration::from_secs(u64::from(wait_s)), mode_rx.changed()).await
                {
                    mode = m;
                }
                continue;
            }
        }
        if asleep {
            match sensor.wake() {
                Ok(()) => {
                    asleep = false;
                    // The pre-shutdown pulse train is 45+ s old; a fresh
                    // detector converges on live samples instead of stitching
                    // the stale history into a bogus inter-beat interval.
                    detector.reset();
                    ambient = 0;
                    info!("hr: window open; sensor sampling");
                }
                Err(e) => {
                    // L4: a sensor that won't wake means no HR, never a
                    // disturbed recording. Skip to the next scheduled window
                    // (or back off in continuous mode) and let consumers blank
                    // via the hold budget.
                    warn!("hr: wake failed {:?}; no HR this window", e);
                    match hr_duty::duty_window(mode) {
                        Some(w) => {
                            let wait_s = w.next_start_s(now_s).saturating_sub(now_s).max(1);
                            if let Ok(m) = with_timeout(
                                Duration::from_secs(u64::from(wait_s)),
                                mode_rx.changed(),
                            )
                            .await
                            {
                                mode = m;
                            }
                        }
                        None => Timer::after(WAKE_RETRY).await,
                    }
                    continue;
                }
            }
        }
        Timer::after(POLL).await;
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
            sender.send(HrSample {
                bpm: reading.valid.then_some(reading.bpm),
                at_s: Instant::now().as_secs() as u32,
            });
        }
    }
}
