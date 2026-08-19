//! Battery task — samples the supply rail through whichever internal SAADC
//! channel can see the cell on this supply path, maps the conversion onto a 1S
//! LiPo percent via the host-tested `watch_core::battery_sense` (over the
//! `watch_core::battery` curve), and publishes to `state::BATTERY` for the idle
//! faces' gauge + the diagnostics BAT row.
//!
//! The channel is chosen in `main` from the supply mode `supply::report` reads
//! at boot, and the `SupplySense` handed here is the same decision: it is what
//! scales the conversion, so the task cannot be given a channel and a scale
//! that disagree.
//!
//! Same resilience posture as the hr/baro tasks — L4, best-effort, a battery
//! bug must never disturb recording — but the park mechanics differ, because
//! embassy-nrf's `sample()` is not cancel-safe on an absent peripheral: both
//! its completion and its cancel-drop path fire TASKS_STOP and busy-wait for
//! EVENTS_STOPPED, so the hr/baro `with_timeout` idiom would spin the
//! executor forever the moment the timeout drops the probe future (Renode's
//! nRF52840 has no SAADC model, so no SAADC event ever fires — sim-hit). The
//! probe instead races the first conversion against a timer WITHOUT
//! cancelling: if the timer wins, the task parks with the probe future alive
//! and never polled again — nothing is dropped, nothing spins. On silicon
//! the SAADC is an internal peripheral whose conversions always complete in
//! microseconds, so the probe resolves immediately and the steady loop needs
//! no timeout at all.
//!
//! The boot reading is then gated on `battery_sense::percent_from_raw`: the DK
//! powered from USB regulates VDD to ~3.0 V, a regulator rail, not a cell, and
//! mapping it would render a confident lie (0%) on the face — so a non-LiPo
//! rail parks too. Parked means nothing is ever published and every consumer
//! shows its honest absent state.
//!
//! One sample per minute: state of charge moves over hours, so a faster
//! cadence would be an unjustifiable standing wake (README § Power
//! discipline). Publication is change-only for the same reason.

use core::future::pending;
use core::pin::pin;

use defmt::*;
use embassy_futures::select::{select, Either};
use embassy_nrf::saadc::Saadc;
use embassy_time::{Duration, Ticker, Timer};
use watch_core::battery_sense::{mv_from_raw, percent_from_raw, SupplySense};

use crate::state;

const SAMPLE: Duration = Duration::from_secs(60);
const PROBE_TIMEOUT: Duration = Duration::from_millis(200);

#[embassy_executor::task]
pub async fn run(mut saadc: Saadc<'static, 1>, sense: SupplySense) {
    let mut buf = [0i16; 1];
    {
        let probe = pin!(saadc.sample(&mut buf));
        if let Either::Second(()) = select(probe, Timer::after(PROBE_TIMEOUT)).await {
            info!("battery: SAADC silent (no model / no hardware); task parked");
            pending::<()>().await;
        }
    }
    let mv = mv_from_raw(sense, buf[0]);
    let Some(pct) = percent_from_raw(sense, buf[0]) else {
        info!(
            "battery: supply unreadable as a 1S LiPo on {} (raw {=i16} -> {=u16}mV: bench/USB rail, or saturated above full scale); task parked",
            sense, buf[0], mv
        );
        return;
    };
    let sender = state::BATTERY.sender();
    let mut shown = Some(pct);
    sender.send(shown);
    info!(
        "battery: streaming on {} ({=u16}mV -> {=u8}%)",
        sense, mv, pct
    );
    let mut ticker = Ticker::every(SAMPLE);
    loop {
        ticker.next().await;
        saadc.sample(&mut buf).await;
        let mv = mv_from_raw(sense, buf[0]);
        // A reading that left the readable domain mid-stream blanks the gauge
        // instead of rendering a percent off a rail; the next tick retries.
        let next = percent_from_raw(sense, buf[0]);
        if next.is_none() {
            warn!(
                "battery: unreadable (raw {=i16} -> {=u16}mV); blanking",
                buf[0], mv
            );
        }
        if next != shown {
            match next {
                Some(pct) => info!("battery: {=u8}%", pct),
                None => info!("battery: reading lost; gauge blanked"),
            }
            sender.send(next);
            shown = next;
        }
    }
}
