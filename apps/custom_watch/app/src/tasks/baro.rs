//! Barometer task — drives the Bosch BMP581 (per decisions.md § 90) over I²C,
//! turns pressure into altitude and cumulative vert via the host-tested
//! `watch_core::elevation`, and publishes a snapshot to `state::ELEVATION` for
//! the status face (ALT + VERT rows) and the phone link's `elev` field.
//!
//! Same resilience shape as the HR task: the blocking driver must not spin the
//! executor on a bus that never answers, so an async, timeout-bounded probe
//! gates it — an absent BMP581 (the Renode sim, an unwired bench) parks the
//! task rather than wedging it (still answering manual re-zero requests with
//! an honest NO BARO). Vert is an auxiliary layer over the L1 GPS distance the
//! recorder already owns.
//!
//! Also the consumer of the manual QNH re-zero (idle-face BTN3 long-press,
//! `watch_core::button::btn3_action`): the task owns the vert accumulator, so
//! the bias snap happens here, but the decision itself — both freshness gates
//! and the two distinct refusals — is the host-tested
//! `watch_core::baro_rezero::rezero`. The outcome is published to
//! `state::QNH_REZERO` for the face's transient banner.
//!
//! It also owns the § 376 storm tracker, because this is the only task holding
//! both halves the sea-level reduction needs: the raw pressure, and the GPS
//! altitude to compensate it against. That altitude is fed **raw** rather than
//! taken from the complementary filter's corrected output — the filter's whole
//! job is to remove weather drift from the altitude, which is exactly the
//! signal the storm trend is looking for (see `watch_core::storm`'s module
//! doc). A sample with no fresh GPS altitude beside it contributes nothing, so
//! a signal void degrades the trend to an explicit refusal rather than to a
//! climb read as a front.
//!
//! Publication is **gated on a change worth waking for**
//! (`watch_core::elevation::should_publish`). `Watch::send` wakes every
//! receiver whatever the value, and the screen task waits on this watch, so
//! sending each 1 Hz sample made a present barometer re-render the face every
//! second forever — the free-running waker the README's power discipline rules
//! out. A manual re-zero snap is the one publication that bypasses the gate
//! (`baro_rezero::published_reading`), so the ALT row always moves with the
//! banner announcing it.

use bmp581::{Bmp581, I2C_ADDR};
use defmt::*;
use embassy_futures::select::{select, Either};
use embassy_nrf::twim::Twim;
use embassy_time::{with_timeout, Duration, Instant, Ticker};
use embedded_hal::i2c::Operation;
use watch_core::baro_rezero::{self, BaroSample};
use watch_core::elevation::{
    altitude_m, run_restarted, should_publish, Reading, RezeroStatus, VertAccumulator,
    STANDARD_SEA_LEVEL_PA,
};
use watch_core::fix::Fix;
use watch_core::storm::{StormTracker, StormView};

use crate::state;

const SAMPLE: Duration = Duration::from_secs(1);
const PROBE_TIMEOUT: Duration = Duration::from_millis(200);

/// The storm tracker's cadence. Hardware banks a five-minute bucket and trends
/// three hours of them, the synoptic tendency interval. The sim cannot spend
/// three hours of virtual time watching a front, so `sim-storm` compresses the
/// same arithmetic into a minute of buckets — the module's logic is
/// cadence-independent by construction, and only these two numbers move.
#[cfg(not(feature = "sim-storm"))]
const STORM_CADENCE_S: (u32, u32) = (
    watch_core::storm::STORM_BUCKET_S,
    watch_core::storm::STORM_WINDOW_S,
);
#[cfg(feature = "sim-storm")]
const STORM_CADENCE_S: (u32, u32) = (5, 60);

/// Whether a freshly computed tendency is worth publishing, given the last one
/// sent. The reason the gate exists is the reason
/// [`should_publish`] exists one field over: the barometer samples at 1 Hz and
/// `Watch::send` wakes every receiver whatever the value, so an unconditional
/// publish would make a present BMP581 a per-second waker again.
///
/// Gated on the fields a CONSUMER can tell apart — the trend word, the tenth of
/// a hectopascal the page renders, and whether the pressure is known at all —
/// rather than on the struct, whose `span_s` advances on every banked bucket
/// and whose `delta_hpa` is a float that is almost never bit-identical twice.
fn storm_worth_publishing(last: Option<Option<StormView>>, next: Option<StormView>) -> bool {
    let Some(prev) = last else { return true };
    let key = |v: Option<StormView>| {
        v.map(|v| {
            (
                v.trend,
                // Truncation, not rounding, because the point is only that
                // two readings a consumer renders identically do not both wake
                // it — and truncation needs no float helper here.
                v.delta_hpa.map(|d| (d * 10.0) as i32),
                v.sea_level_hpa.map(|p| p as i32),
            )
        })
    };
    key(prev) != key(next)
}

/// Parked stand-in when no BMP581 answered: keep draining manual re-zero
/// requests with an honest NO BARO instead of leaving a press silently
/// unanswered (the request channel would otherwise have no consumer).
async fn park_without_sensor() {
    let status_tx = state::QNH_REZERO.sender();
    // A watch with no barometer has no tendency, and says so rather than
    // leaving the Storm page's presence bit at whatever it booted with.
    state::STORM.sender().send(None);
    loop {
        state::QNH_REZERO_REQ.receive().await;
        status_tx.send((RezeroStatus::NoBaro, Instant::now().as_secs() as u32));
    }
}

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
            return park_without_sensor().await;
        }
        Ok(Err(e)) => {
            warn!("baro: BMP581 probe failed {:?}; task parked", e);
            return park_without_sensor().await;
        }
        Ok(Ok(())) => {}
    }

    let mut sensor = Bmp581::new(twim);
    if let Err(e) = sensor.init() {
        warn!("baro: BMP581 init failed {:?}; task parked", e);
        return park_without_sensor().await;
    }
    let elevation_tx = state::ELEVATION.sender();
    let rezero_status_tx = state::QNH_REZERO.sender();
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut sea_level_rx = unwrap!(state::SEA_LEVEL_PA.receiver());
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut vert = VertAccumulator::new();
    let mut moving = false;
    let mut last_elapsed_s: Option<u32> = None;
    // The latest merged fix and raw baro altitude (with the uptime it was
    // sampled), kept for the manual re-zero: the snap needs the current baro
    // altitude plus a GPS altitude it can judge freshness on
    // (rezero_reference), neither of which a request-time sensor read could
    // supply alone.
    let mut last_fix: Option<Fix> = None;
    let mut last_alt: Option<BaroSample> = None;
    let mut published: Option<Reading> = None;
    let storm_tx = state::STORM.sender();
    let mut storm_threshold_rx = unwrap!(state::STORM_THRESHOLD_HPA.receiver());
    let mut storm = StormTracker::with_cadence(STORM_CADENCE_S.0, STORM_CADENCE_S.1);
    let mut storm_published: Option<Option<StormView>> = None;
    // QNH reference for the altitude conversion. Defaults to the ISA standard
    // until a phone settings push recalibrates it (state::SEA_LEVEL_PA) — the
    // weather-front case where the fixed standard drifts the whole altitude.
    let mut sea_level_pa = STANDARD_SEA_LEVEL_PA;
    let mut ticker = Ticker::every(SAMPLE);
    info!("baro: BMP581 streaming");
    loop {
        // A manual re-zero request (idle-face BTN3 long-press) is answered
        // between samples: snap the complementary-filter bias to the freshest
        // GPS altitude, or refuse honestly — never a silent no-op. Config/L4:
        // the snap moves only the altitude reference, the vert totals and the
        // recorder's L1 distance are untouched.
        if let Either::Second(()) = select(ticker.next(), state::QNH_REZERO_REQ.receive()).await {
            if let Some(f) = fix_rx.try_changed() {
                last_fix = Some(f);
            }
            let now_s = Instant::now().as_secs() as u32;
            let status = baro_rezero::rezero(&mut vert, last_alt, last_fix.as_ref(), now_s);
            if let Some(reading) = baro_rezero::published_reading(&vert, status) {
                elevation_tx.send(reading);
                published = Some(reading);
            }
            info!("baro: qnh re-zero -> {}", status);
            rezero_status_tx.send((status, now_s));
            continue;
        }
        // Pick up the latest recording state without blocking the sample tick;
        // vert only accumulates while a run is actively moving, so barometric
        // drift during a stop (aid station, sleep, weather on a col) banks
        // nothing (watch_core::elevation::VertAccumulator::push). The
        // is-moving decision is the host-tested `Snapshot::is_moving` — the
        // recorder's Paused state alone can't answer it, since the GPS
        // point-acceptance min-move filter also parks a genuinely climbing
        // runner there.
        if let Some(snap) = rec_rx.try_changed() {
            // ...and open a new run at zero vert. The totals published here are
            // the RUN's, but this task's accumulator lives for the whole power
            // cycle, so a second run would otherwise open holding the first
            // one's climb — beneath a run-scoped elevation sparkline that
            // correctly starts empty. Keyed on the recorder's clock going back
            // (`run_restarted`), not on a state edge: this watch keeps only the
            // latest snapshot, so an edge can pass entirely between two ticks.
            if run_restarted(last_elapsed_s, snap.elapsed_s) {
                vert.start_run();
                info!("baro: vert reset for a new run");
            }
            last_elapsed_s = Some(snap.elapsed_s);
            moving = snap.is_moving();
        }
        // Pick up a recalibrated sea-level reference without blocking the tick.
        if let Some(pa) = sea_level_rx.try_changed() {
            sea_level_pa = pa;
        }
        // ...and a pushed storm threshold, whose plausibility guard is the
        // tracker's own — an implausible one leaves the current threshold
        // standing rather than clamping to an edge.
        if let Some(hpa) = storm_threshold_rx.try_changed() {
            storm.set_fall_threshold_hpa(hpa);
            info!("baro: storm threshold {} hPa", storm.fall_threshold_hpa());
        }
        match sensor.read_pressure_pa() {
            Ok(Some(pa)) => {
                let alt = altitude_m(pa, sea_level_pa);
                last_alt = Some(BaroSample {
                    alt_m: alt,
                    at_s: Instant::now().as_secs() as u32,
                });
                // Fresh GPS altitude corroborates the barometer against weather
                // drift (elevation's complementary filter): only a fresh fix
                // slews the bias, so signal loss freezes it rather than dragging
                // it toward a stale altitude. Read inside the pressure arm so a
                // read miss never consumes/drops a fix.
                let fresh_fix = fix_rx.try_changed();
                if let Some(f) = fresh_fix {
                    last_fix = Some(f);
                }
                let gps_alt = fresh_fix.and_then(|f| f.alt_m);
                let corrected = vert.push(alt, moving, gps_alt);
                let reading = vert.reading(corrected);
                debug!(
                    "baro: alt={}m gain={}m loss={}m",
                    reading.alt_m, reading.gain_m, reading.loss_m
                );
                if should_publish(published, reading) {
                    elevation_tx.send(reading);
                    published = Some(reading);
                }
                // The storm tracker takes the RAW pressure and the RAW GPS
                // altitude — never `corrected`, which has had the weather
                // filtered out of it by design (watch_core::storm).
                let now_s = Instant::now().as_secs() as u32;
                storm.on_sample(pa, gps_alt, now_s);
                let view = storm.view(now_s);
                storm.on_view(&view);
                let next = Some(view);
                if storm_worth_publishing(storm_published, next) {
                    // The task's own line, so a sim scenario can assert the
                    // tendency rather than a panel reading of it.
                    match (view.trend, view.delta_hpa, view.sea_level_hpa) {
                        (t, Some(d), Some(p)) => info!(
                            "baro: storm {} delta={}hPa qnh={}hPa span={}s",
                            t, d, p, view.span_s
                        ),
                        (t, _, p) => info!("baro: storm {} qnh={:?}hPa", t, p),
                    }
                    storm_tx.send(next);
                    storm_published = Some(next);
                }
            }
            Ok(None) => {}
            Err(e) => warn!("baro: read error {:?}", e),
        }
    }
}
