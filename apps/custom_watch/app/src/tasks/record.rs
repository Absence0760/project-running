//! Recording task — drives the host-tested `watch_core::record` state machine
//! from the button command stream and the live fix stream, publishes a snapshot
//! of the run totals, and streams the GPS track to the on-device flash run
//! store so a finished run can be synced to the phone (README step 7).
//!
//! Thin glue by design: distance, moving time, pace, the point-acceptance
//! filter, and the auto-pause all live in `watch_core::record` (host-tested);
//! the button-press → command mapping lives in `watch_core::button`; the flash
//! slot layout in `watch_core::flash_store`. This task selects over incoming
//! fixes (fed to the recorder) and commands (drive start/pause/resume/stop/lap),
//! plus — only while a run is Recording or Paused — a 1 Hz tick that advances
//! the wall clock between fixes. Idle and Finished have no clock to advance, so
//! the tick is dropped there and the task waits purely on events. It publishes
//! a snapshot only when it actually changed, so a resting recorder wakes no
//! downstream consumer (the ui face, the button task) on a heartbeat.
//!
//! Track capture: on start it opens a `run_store::RunWriter` over a slot-sized
//! RAM staging buffer; each fix the recorder accepts as a new anchor
//! (`Recorder::last_fix_stored`) becomes a `push_point`, stamped with the latest
//! heart rate + barometric altitude; on stop it finalises the blob with the
//! snapshot totals and commits it to flash. The store is best-effort (L4): a
//! flash error only logs and never disturbs the recording math, so recording
//! keeps working even where flash is unavailable (the Renode sim).
//!
//! Start path: on real hardware BTN1 starts the run (nothing auto-starts). The
//! `sim-autostart` Cargo feature (default OFF) restores a "start on first fix"
//! fallback for the Renode sim, which has no button injection — see
//! `apps/custom_watch/local_testing.md § Simulating without a board`.

use defmt::*;
use embassy_futures::select::{select, select3, Either, Either3};
use embassy_time::{Duration, Instant, Ticker};
use heapless::Vec;
use max86177::peak_detect::Reading as HrReading;
use watch_core::button::RecordCommand;
use watch_core::fix::Fix;
use watch_core::flash_store::{MAX_POINTS_PER_RUN, SLOT_LEN};
use watch_core::record::{RecordState, Recorder, Snapshot};
use watch_core::run_store::{verify_blob, RunWriter, TrackPoint};

use crate::run_flash::SharedStore;
use crate::state;

fn state_str(state: RecordState) -> &'static str {
    match state {
        RecordState::Idle => "idle",
        RecordState::Recording => "recording",
        RecordState::Paused => "paused",
        RecordState::Finished => "finished",
    }
}

/// A run being recorded: the RAM-staging writer plus the header fields needed to
/// commit the finished blob to flash.
struct OpenRun {
    writer: RunWriter<Vec<u8, SLOT_LEN>>,
    run_seq: u32,
    start_uptime_s: u32,
    cap_warned: bool,
}

/// Open a fresh staging writer for a new run, assigning the next run id. Returns
/// `None` only if the header write into the empty staging buffer fails, which it
/// cannot at `SLOT_LEN` capacity — guarded defensively.
fn open_run(next_seq: &mut u32, start_uptime_s: u32) -> Option<OpenRun> {
    let run_seq = *next_seq;
    *next_seq = next_seq.wrapping_add(1);
    match RunWriter::start(Vec::new(), run_seq, start_uptime_s) {
        Ok(writer) => Some(OpenRun {
            writer,
            run_seq,
            start_uptime_s,
            cap_warned: false,
        }),
        Err(_) => {
            warn!("record: run writer start failed");
            None
        }
    }
}

/// Append one accepted fix to the staged track, stamped with the latest HR +
/// altitude. Silent no-op once the tier-1 per-run point cap is reached
/// (recording totals keep accruing); warns once on the crossing.
fn push_point(open: &mut OpenRun, fix: &Fix, bpm: Option<u8>, baro_alt_m: Option<f32>) {
    if open.writer.point_count() >= MAX_POINTS_PER_RUN {
        if !open.cap_warned {
            warn!(
                "record: run {=u32} hit tier-1 flash point cap ({=u32}); track truncated, recording continues",
                open.run_seq, MAX_POINTS_PER_RUN
            );
            open.cap_warned = true;
        }
        return;
    }
    let point = TrackPoint {
        lat_e7: (fix.lat_deg * 1e7) as i32,
        lon_e7: (fix.lon_deg * 1e7) as i32,
        t_offset_s: fix.uptime_s.saturating_sub(open.start_uptime_s),
        ele_dm: baro_alt_m.or(fix.alt_m).and_then(ele_dm_from_m),
        bpm,
    };
    if open.writer.push_point(&point).is_err() && !open.cap_warned {
        warn!("record: staging buffer full for run {=u32}", open.run_seq);
        open.cap_warned = true;
    }
}

/// Finalise the staged blob with the snapshot totals and commit it to flash.
async fn commit_run(store: &'static SharedStore, open: OpenRun, snap: &Snapshot) {
    let distance_m = snap.distance_m.max(0.0) as u32;
    let blob = match open
        .writer
        .finalize(distance_m, snap.moving_s, snap.elapsed_s)
    {
        Ok(blob) => blob,
        Err(_) => {
            warn!("record: finalize failed for run {=u32}", open.run_seq);
            return;
        }
    };
    if !verify_blob(&blob) {
        warn!(
            "record: staged blob for run {=u32} failed self-verify, not storing",
            open.run_seq
        );
        return;
    }
    store
        .lock()
        .await
        .commit(open.run_seq, open.start_uptime_s, &blob);
}

/// Altitude in metres → wire-format decimetres, dropping values outside the
/// `i16` decimetre range (about ±3276 m — a frozen `TrackPoint` limit; tier-2
/// widens it) so an out-of-range reading stores `None`, never a wrong value.
fn ele_dm_from_m(alt_m: f32) -> Option<i16> {
    let dm = alt_m * 10.0;
    if dm.is_finite() && dm > i16::MIN as f32 && dm <= i16::MAX as f32 {
        Some(dm as i16)
    } else {
        None
    }
}

/// Latest HR reading → a track point's `bpm`, dropping invalid or out-of-`u8`
/// estimates.
fn bpm_of(r: &HrReading) -> Option<u8> {
    (r.valid && (1..=255).contains(&r.bpm)).then_some(r.bpm as u8)
}

#[embassy_executor::task]
pub async fn run(store: &'static SharedStore) {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut hr_rx = unwrap!(state::HR.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let sender = state::RECORD.sender();
    let mut recorder = Recorder::new();
    let mut ticker = Ticker::every(Duration::from_secs(1));
    let mut next_seq: u32 = 0;
    let mut open: Option<OpenRun> = None;
    let mut latest_bpm: Option<u8> = None;
    let mut latest_baro_alt_m: Option<f32> = None;
    // Seed with the initial idle snapshot so it is never published — consumers
    // treat "no RECORD value yet" as idle, which is exactly right.
    let mut last_published = recorder.snapshot();
    #[cfg(feature = "sim-autostart")]
    info!("record: sim-autostart on — starts on first fix");
    #[cfg(not(feature = "sim-autostart"))]
    info!("record: waiting for BTN1 to start");
    loop {
        // A tick only means something while a run is advancing a clock. Idle and
        // Finished don't, so drop the ticker there and wait purely on events.
        let event = if is_active(recorder.state()) {
            match select3(ticker.next(), fix_rx.changed(), state::RECORD_CMD.receive()).await {
                Either3::First(()) => Event::Tick,
                Either3::Second(fix) => Event::Fix(fix),
                Either3::Third(cmd) => Event::Cmd(cmd),
            }
        } else {
            match select(fix_rx.changed(), state::RECORD_CMD.receive()).await {
                Either::First(fix) => Event::Fix(fix),
                Either::Second(cmd) => Event::Cmd(cmd),
            }
        };

        match event {
            Event::Tick => recorder.tick(Instant::now().as_secs() as u32),
            Event::Fix(fix) => {
                if let Some(r) = hr_rx.try_changed() {
                    latest_bpm = bpm_of(&r);
                }
                if let Some(r) = elev_rx.try_changed() {
                    latest_baro_alt_m = Some(r.alt_m);
                }
                #[cfg(feature = "sim-autostart")]
                if recorder.state() == RecordState::Idle {
                    let now_s = Instant::now().as_secs() as u32;
                    recorder.start(now_s);
                    ticker.reset(); // fresh clock — no catch-up burst of ticks
                    open = open_run(&mut next_seq, now_s);
                    info!("record: sim-autostart on first fix");
                }
                recorder.on_fix(&fix);
                if recorder.last_fix_stored() {
                    if let Some(o) = open.as_mut() {
                        push_point(o, &fix, latest_bpm, latest_baro_alt_m);
                    }
                }
            }
            Event::Cmd(cmd) => {
                let now_s = Instant::now().as_secs() as u32;
                let prev = recorder.state();
                match cmd {
                    RecordCommand::Start => recorder.start(now_s),
                    RecordCommand::Pause => recorder.pause(now_s),
                    RecordCommand::Resume => recorder.resume(now_s),
                    RecordCommand::Stop => recorder.stop(now_s),
                    RecordCommand::Lap => recorder.lap(now_s),
                }
                let now = recorder.state();
                if prev == RecordState::Idle && now == RecordState::Recording {
                    ticker.reset(); // entering the active clock — avoid a burst
                    if open.is_none() {
                        open = open_run(&mut next_seq, now_s);
                    }
                }
                if now == RecordState::Finished {
                    if let Some(o) = open.take() {
                        commit_run(store, o, &recorder.snapshot()).await;
                    }
                }
                info!("record: command {} -> {}", cmd, state_str(now));
            }
        }

        // Publish only on change: a resting recorder must not wake the ui face
        // or the button task on a heartbeat.
        let snap = recorder.snapshot();
        if snap != last_published {
            debug!(
                "record: {} dist={}m moving={}s",
                state_str(snap.state),
                snap.distance_m,
                snap.moving_s
            );
            last_published = snap;
            sender.send(snap);
        }
    }
}

/// A run advances its wall clock only while Recording or Paused; Idle and
/// Finished are inert, so the 1 Hz tick is dropped in those states.
fn is_active(state: RecordState) -> bool {
    matches!(state, RecordState::Recording | RecordState::Paused)
}

enum Event {
    Tick,
    Fix(Fix),
    Cmd(RecordCommand),
}
