//! HR task — drives an optical-HR AFE over I²C, runs the host-tested
//! peak-detect pipeline, and publishes a stamped BPM estimate.
//!
//! The part is named exactly once, at construction: everything after that goes
//! through `watch_core::ppg::PpgAfe`, and the ADC scale, auto-gain window, LED
//! seed and slot tags are asked of the part rather than written here
//! (decisions.md § 623). A threshold quoted in photodiode counts means nothing
//! without the converter width behind it, so a task that hard-coded them would
//! judge an 18-bit stream by 19-bit bounds the moment the AFE changed.
//!
//! It publishes to `state::HR_OPTICAL`, not to the shared `state::HR` the face
//! and recorder read: an external BLE chest strap is a second source (§365),
//! and which one the watch shows is decided by the `hr_source` arbiter against
//! a stated rule rather than by whichever task happened to write last. This
//! task keeps reporting what the wrist sensor sees either way.
//!
//! The driver is blocking, so a bus that never answers would spin
//! the executor forever. Optical HR is an auxiliary layer (decisions §80 /
//! the layered-resilience contract): its absence must not stall GPS, display,
//! or the phone link. So the first transaction is an async, timeout-bounded
//! presence probe; if it times out — a bench build may not have the part wired
//! — the task parks instead of wedging the blocking driver.
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
//! The FIFO interleaves two measurement slots — LED-on PPG and LED-off ambient
//! — told apart by the logical tags the driver reports. The drain demuxes
//! strictly (`watch_core::hr_drain`): each PPG count is paired with the latest
//! ambient count for subtraction (bright-sun recovery), and a word with a tag
//! we didn't enable is dropped, never fed to the detector as PPG. A slow LED
//! auto-gain loop keeps the corrected DC in the detector's band while a raw-DC
//! guard protects ADC clipping headroom — ambient swings cancel out of the
//! corrected level, so the drive can't oscillate against sunlight flicker. Its
//! cadence is `hr_drain::AgcCadence` (~1 Hz, and a fresh period after every
//! duty-cycle wake) and its step size `ppg::agc_next_pa_ambient`. Register
//! effects are compile-only until the dev kit lands, like the rest of this
//! path.
//!
//! The licensed Maxim HR algorithm is pulled in via `bindgen` post-tier-1;
//! tier 1 uses the naive peak-detect in `watch_core::ppg`.

use defmt::*;
use embassy_nrf::twim::Twim;
use embassy_time::{with_timeout, Duration, Instant, Timer};
use embedded_hal::i2c::Operation;
use max30101::{Max30101, I2C_ADDR};
use watch_core::gnss_mode::GnssMode;
use watch_core::hr_drain::{next_window_wait_s, AgcCadence, FifoDemux, FifoSlot};
use watch_core::hr_duty::{self, HrSample};
use watch_core::ppg::{agc_next_pa_ambient, Contact, FifoWord, PeakDetector, PpgAfe, Reading};

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
            warn!("hr: no AFE on I2C (probe timed out); task parked");
            return;
        }
        Ok(Err(e)) => {
            warn!("hr: AFE probe failed {:?}; task parked", e);
            return;
        }
        Ok(Ok(())) => {}
    }

    let mut sensor = Max30101::new(twim);
    if let Err(e) = PpgAfe::init(&mut sensor) {
        warn!("hr: AFE init failed {:?}; task parked", e);
        return;
    }
    // Scale, AGC window, LED seed and slot tags all come from the part rather
    // than from constants here, so swapping the AFE is a `Max30101::new` line
    // and nothing else in this task (decisions.md § 623).
    let mut detector = PeakDetector::new(SAMPLE_RATE_HZ, sensor.scale());
    let sender = state::HR_OPTICAL.sender();
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut mode = GnssMode::default();
    let mut asleep = false;
    info!("hr: AFE streaming");
    // Slot demux + the ambient (LED-off) latch each PPG (LED-on) sample is
    // corrected against, so bright-sun ambient bleed can't rail the pulse
    // (`watch_core::hr_drain`).
    let mut demux = FifoDemux::new(sensor.tags());
    // LED auto-gain state. `led_pa` mirrors the LEDx_PA register (init programs
    // LED_PA_DEFAULT; the register survives shutdown, so it carries across duty
    // windows without a re-write). `agc` owns when a step is allowed
    // (`watch_core::hr_drain`) and `agc_next_pa_ambient` by how much — judging
    // the corrected DC for brightness and the raw DC for clipping headroom, so
    // ambient swings can't walk the drive. One unknown-tag warning per task
    // lifetime: a persistent stray tag means config drift, and per-word logging
    // at 100 Hz would drown defmt.
    let agc_cfg = sensor.agc_config();
    let mut led_pa: u8 = sensor.led_pa_default();
    let mut agc = AgcCadence::per_second(SAMPLE_RATE_HZ);
    let mut warned_unknown_tag = false;
    // Change-only observability: one line when the published estimate flips
    // (valid BPM appears / moves / blanks) and one when the contact
    // classification changes (Worn / OffWrist / Saturated), so a defmt stream
    // — sim or bench — shows the HR story without a 50 Hz log flood.
    let mut logged_bpm: Option<Option<u16>> = None;
    let mut logged_contact: Option<Contact> = None;
    // Last sample actually put on the HR watch, so a byte-identical resend can
    // be suppressed (`hr_duty::should_publish`).
    let mut last_published: Option<HrSample> = None;
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
                    match PpgAfe::shutdown(&mut sensor) {
                        Ok(()) => info!(
                            "hr: window closed; sensor shut down until {=u32}s",
                            w.next_start_s(now_s)
                        ),
                        Err(e) => warn!("hr: shutdown failed {:?}", e),
                    }
                }
                // Sleep to the next window start, but let an idle mode change
                // (BTN3) re-evaluate the schedule immediately.
                let wait_s = next_window_wait_s(w, now_s);
                if let Ok(m) =
                    with_timeout(Duration::from_secs(u64::from(wait_s)), mode_rx.changed()).await
                {
                    mode = m;
                }
                continue;
            }
        }
        if asleep {
            match PpgAfe::wake(&mut sensor) {
                Ok(()) => {
                    asleep = false;
                    // The pre-shutdown pulse train is 45+ s old; a fresh
                    // detector converges on live samples instead of stitching
                    // the stale history into a bogus inter-beat interval.
                    detector.reset();
                    demux.reset();
                    agc.reset();
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
                            let wait_s = next_window_wait_s(w, now_s);
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
            match PpgAfe::read_tagged_sample(&mut sensor) {
                Ok(Some(FifoWord { tag, value })) => match demux.apply(tag, value as i32) {
                    FifoSlot::Ppg => {
                        latest = Some(detector.push_ambient(value as i32, demux.ambient()));
                        agc.sample();
                    }
                    FifoSlot::Ambient => {}
                    FifoSlot::Unknown => {
                        if !warned_unknown_tag {
                            warned_unknown_tag = true;
                            warn!("hr: unknown FIFO tag {=u8}; dropping", tag);
                        }
                    }
                },
                Ok(None) => break,
                Err(e) => {
                    warn!("hr: read error {:?}", e);
                    break;
                }
            }
        }
        if let Some(dc) = agc.due(detector.raw_dc(), detector.corrected_dc()) {
            let next = agc_next_pa_ambient(dc.raw, dc.corrected, led_pa, &agc_cfg);
            if next != led_pa {
                // L4 best-effort like every other write here: a failed drive
                // update keeps the old current — the detector's contact honesty
                // covers a rail until the next attempt.
                match PpgAfe::set_led_current(&mut sensor, next) {
                    Ok(()) => {
                        debug!("hr: AGC LED drive {=u8} -> {=u8}", led_pa, next);
                        led_pa = next;
                    }
                    Err(e) => warn!("hr: AGC LED write failed {:?}", e),
                }
            }
        }
        if let Some(reading) = latest {
            let contact = detector.contact();
            if logged_contact != Some(contact) {
                info!("hr: contact {:?}", contact);
                logged_contact = Some(contact);
            }
            let bpm = reading.valid.then_some(reading.bpm);
            if logged_bpm != Some(bpm) {
                // Change-gated, so the stream of these IS a heart-rate series.
                // The value is behind the default-off `log-personal-data` gate;
                // trusted-vs-not is the part the optical chain is debugged
                // against and carries no biometric.
                #[cfg(feature = "log-personal-data")]
                match bpm {
                    Some(b) => info!("hr: bpm {=u16}", b),
                    None => info!("hr: no trusted pulse"),
                }
                #[cfg(not(feature = "log-personal-data"))]
                match bpm {
                    Some(_) => info!("hr: trusted pulse"),
                    None => info!("hr: no trusted pulse"),
                }
                logged_bpm = Some(bpm);
            }
            // Publish only what carries new information. The drain runs at
            // 50 Hz and the arbiter → screen chain hangs off this watch, so
            // resending a byte-identical sample would wake the UI 50 times a
            // second
            // — the free-running waker the README's power discipline rules
            // out. `at_s` is whole seconds, so a steady pulse still publishes
            // once per second and `shown_bpm`'s hold budget ages unchanged,
            // while a real change propagates on the sample that produced it.
            let sample = HrSample {
                bpm,
                at_s: Instant::now().as_secs() as u32,
            };
            if hr_duty::should_publish(last_published, sample) {
                sender.send(sample);
                last_published = Some(sample);
            }
        }
    }
}
