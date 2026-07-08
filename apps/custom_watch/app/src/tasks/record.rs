//! Recording task — drives the host-tested `watch_core::record` state machine
//! from the button command stream and the live fix stream, and publishes a
//! snapshot of the run totals.
//!
//! Thin glue by design: distance, moving time, pace, the point-acceptance
//! filter, and the auto-pause all live in `watch_core::record` (host-tested);
//! the button-press → command mapping lives in `watch_core::button`. This task
//! selects over three sources — a 1 Hz tick (advances the wall clock),
//! incoming fixes (fed to the recorder), and incoming commands (drive the
//! start/pause/resume/stop transitions) — and republishes the snapshot after
//! each.
//!
//! Start path: on real hardware BTN1 starts the run (nothing auto-starts).
//! The `sim-autostart` Cargo feature (default OFF) restores a "start on first
//! fix" fallback for the Renode sim, which has no button injection — see
//! `apps/custom_watch/local_testing.md § Simulating without a board`.

use defmt::*;
use embassy_futures::select::{select3, Either3};
use embassy_time::{Duration, Instant, Ticker};
use watch_core::button::RecordCommand;
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
    #[cfg(feature = "sim-autostart")]
    info!("record: sim-autostart on — starts on first fix");
    #[cfg(not(feature = "sim-autostart"))]
    info!("record: waiting for BTN1 to start");
    loop {
        match select3(ticker.next(), fix_rx.changed(), state::RECORD_CMD.receive()).await {
            Either3::First(()) => {
                recorder.tick(Instant::now().as_secs() as u32);
            }
            Either3::Second(fix) => {
                #[cfg(feature = "sim-autostart")]
                if recorder.state() == RecordState::Idle {
                    recorder.start(Instant::now().as_secs() as u32);
                    info!("record: sim-autostart on first fix");
                }
                recorder.on_fix(&fix);
            }
            Either3::Third(cmd) => {
                let now_s = Instant::now().as_secs() as u32;
                match cmd {
                    RecordCommand::Start => recorder.start(now_s),
                    RecordCommand::Pause => recorder.pause(now_s),
                    RecordCommand::Resume => recorder.resume(now_s),
                    RecordCommand::Stop => recorder.stop(now_s),
                }
                info!("record: command {} -> {}", cmd, state_str(recorder.state()));
            }
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
