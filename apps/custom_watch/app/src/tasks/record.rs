//! Recording task — drives the host-tested `watch_core::record` state machine
//! from the live fix stream and publishes a snapshot of the run totals.
//!
//! Thin glue by design: distance, moving time, pace, the point-acceptance
//! filter, and the auto-pause all live in `watch_core::record` (host-tested).
//! This task moves fixes into the `Recorder` on a 1 Hz cadence and republishes
//! its snapshot.
//!
//! Tier-1 stand-in: the run auto-starts on the first fix. A button-driven
//! start/stop belongs to the (not-yet-built) button handler; wiring that in is
//! the remaining half of README step 7.

use defmt::*;
use embassy_time::{Duration, Instant, Ticker};
use watch_core::record::{RecordState, Recorder};

use crate::state;

fn state_str(state: RecordState) -> &'static str {
    match state {
        RecordState::Idle => "idle",
        RecordState::Recording => "recording",
        RecordState::Paused => "paused",
        RecordState::Finished => "finished",
    }
}

#[embassy_executor::task]
pub async fn run() {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let sender = state::RECORD.sender();
    let mut recorder = Recorder::new();
    let mut ticker = Ticker::every(Duration::from_secs(1));
    info!("record: waiting for first fix to auto-start");
    loop {
        ticker.next().await;
        let now_s = Instant::now().as_secs() as u32;
        match fix_rx.try_changed() {
            Some(fix) => {
                if recorder.state() == RecordState::Idle {
                    recorder.start(now_s);
                    info!("record: auto-started on first fix");
                }
                recorder.on_fix(&fix);
            }
            None => recorder.tick(now_s),
        }
        let snap = recorder.snapshot();
        debug!(
            "record: {} dist={}m moving={}s",
            state_str(snap.state),
            snap.distance_m,
            snap.moving_s
        );
        sender.send(snap);
    }
}
