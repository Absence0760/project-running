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
//! It also drives the `watch_core::alerts` engine (drink / eat reminders on
//! the fuel_plan moving-time cadence + the HR-zone ceiling alert) off the same
//! event cadence, publishing the active alert to `state::ALERT` on change —
//! after the recorder updates and never in its way (L4).
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
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::watch::Sender;
use embassy_time::{Duration, Instant, Ticker};
use heapless::Vec;
use max86177::peak_detect::Reading as HrReading;
use watch_core::alerts::{Alert, AlertEngine};
use watch_core::button::RecordCommand;
#[cfg(feature = "sim-course")]
use watch_core::cutoff_eta::CutoffLeg;
use watch_core::face::NavView;
use watch_core::fix::Fix;
use watch_core::flash_store::{MAX_POINTS_PER_RUN, SLOT_LEN};
use watch_core::record::{RecordState, Recorder, Snapshot};
use watch_core::run_store::{verify_blob, RunWriter, TrackPoint};
use watch_core::settings::WatchSettings;
use watch_core::trackback::Trackback;

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

/// Canned cut-off legs for the sim course (the `nav` task's ~180 m rectangle,
/// distances along its NW->SW->SE polyline). Two aid-station-style cut-offs the
/// bench_jog fixture sweeps past each lap, so the CutoffEta page shows a live
/// on / tight / behind verdict under the sim. Hardware carries none until a
/// course-push path lands, so its CutoffEta page reads "no cutoffs".
#[cfg(feature = "sim-course")]
static SIM_CUTOFFS: [CutoffLeg; 2] = [
    CutoffLeg {
        cum_dist_m: 90.0,
        limit_elapsed_s: 120,
    },
    CutoffLeg {
        cum_dist_m: 170.0,
        limit_elapsed_s: 240,
    },
];

/// Canned roadbook checkpoints for the sim course — start, an aid at 90 m, and
/// the 180 m finish, with demo arrival times matching the ~3 m/s bench_jog
/// fixture, so the Roadbook + Fuel pages show a live schedule + carry-to-aid
/// under the sim. Hardware carries none until a course-push path lands.
#[cfg(feature = "sim-course")]
static SIM_ROADBOOK: [watch_core::record::RoadbookCheckpoint; 3] = [
    watch_core::record::RoadbookCheckpoint {
        cum_dist_m: 0.0,
        leg_dist_m: 0.0,
        projected_elapsed_s: 0,
        cutoff: None,
        is_refill: true,
    },
    watch_core::record::RoadbookCheckpoint {
        cum_dist_m: 90.0,
        leg_dist_m: 90.0,
        projected_elapsed_s: 30,
        cutoff: Some(watch_core::roadbook::CutoffStatus::Safe),
        is_refill: true,
    },
    watch_core::record::RoadbookCheckpoint {
        cum_dist_m: 180.0,
        leg_dist_m: 90.0,
        projected_elapsed_s: 60,
        cutoff: Some(watch_core::roadbook::CutoffStatus::Tight),
        is_refill: false,
    },
];

#[embassy_executor::task]
pub async fn run(store: &'static SharedStore) {
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut hr_rx = unwrap!(state::HR.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut nav_rx = unwrap!(state::NAV.receiver());
    let mut settings_rx = unwrap!(state::SETTINGS.receiver());
    let sender = state::RECORD.sender();
    let alert_sender = state::ALERT.sender();
    let trackback_sender = state::TRACKBACK.sender();
    let sea_level_tx = state::SEA_LEVEL_PA.sender();
    let mut recorder = Recorder::new();
    // On-run alerts ride this task because it already owns the recorder's
    // event cadence; the engine is pure and fed after the recorder updates,
    // so an alert can never disturb the recording math (L4).
    let mut alerts = AlertEngine::new();
    let mut last_alert: Option<Alert> = None;
    let mut ticker = Ticker::every(Duration::from_secs(1));
    // Resume past any run recovered from flash so a new run can't reuse a
    // recovered run's id (which would confuse the phone's manifest + chunk pull).
    let mut next_seq: u32 = store.lock().await.next_run_seq();
    let mut open: Option<OpenRun> = None;
    let mut latest_bpm: Option<u8> = None;
    let mut latest_baro_alt_m: Option<f32> = None;
    let mut trackback = Trackback::new();
    let mut crumb_len: usize = 0;
    // Seed with the initial idle snapshot so it is never published — consumers
    // treat "no RECORD value yet" as idle, which is exactly right.
    let mut last_published = recorder.snapshot();
    #[cfg(feature = "sim-autostart")]
    info!("record: sim-autostart on — starts on first fix");
    // The sim can't wait 15 minutes of moving time for a real reminder, so
    // the autostart build shortens the fuel cadences (drink 30 s, eat 45 s of
    // moving time). Hardware keeps the fuel_plan-derived defaults.
    #[cfg(feature = "sim-autostart")]
    {
        alerts.set_fuel_intervals(30, 45);
        info!("record: sim fuel cadence 30s drink / 45s eat (moving time)");
    }
    // Sim-only demo settings, applied through the SAME path a phone push takes
    // (`apply_settings`) so the sim exercises the settings-sync apply, not a
    // separate hardcoded seam: a 1 km / 5:00 pacer goal (a partner slightly
    // faster than the ~5:33/km bench_jog fixture, so the Pacer page reads a live
    // BEHIND) and a 700 km / 800 km shoe (a live DUE the run's mileage pushes on).
    // Hardware stays unset until a real push over the settings characteristic.
    #[cfg(feature = "sim-autostart")]
    {
        use watch_core::settings::{GearCfg, PacerGoalCfg};
        let demo = WatchSettings {
            pacer: Some(PacerGoalCfg {
                distance_m: 1_000,
                time_s: 300,
            }),
            gear: Some(GearCfg {
                baseline_m: 700_000.0,
                target_m: Some(800_000.0),
            }),
            ..WatchSettings::default()
        };
        apply_settings(&demo, &mut recorder, &mut alerts, &sea_level_tx);
        info!("record: sim demo settings applied (pacer 1km/5:00, gear 700/800 km)");
    }
    #[cfg(not(feature = "sim-autostart"))]
    info!("record: waiting for BTN1 to start");
    // The canned sim course carries cut-off legs so the CutoffEta page shows a
    // live verdict; hardware has none until a course-push path lands.
    #[cfg(feature = "sim-course")]
    {
        recorder.set_cutoff_legs(&SIM_CUTOFFS);
        info!("record: sim cutoff legs loaded (90 m/2:00, 170 m/4:00)");
        recorder.set_roadbook(&SIM_ROADBOOK);
        info!("record: sim roadbook loaded (start / aid 90 m / finish 180 m)");
    }
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

        // Keep the recorder's acceptance filter scaled to the selected GNSS
        // mode's fix cadence (see `Recorder::set_fix_interval_s`). The mode
        // only changes while idle (BTN3 cycles pages once a run is under way),
        // so it is always applied here before the Start command that opens the
        // run reaches the recorder.
        if let Some(mode) = mode_rx.try_changed() {
            recorder.set_fix_interval_s(mode.fix_interval_s());
        }

        // Feed the nav task's course projection to the recorder for the cut-off
        // ETA. The nav task owns the course + projection (published per fix);
        // the recorder stays course-agnostic and just folds the along-course
        // distance in, withholding an ETA once the position goes stale.
        if let Some(nav) = nav_rx.try_changed() {
            recorder.set_route_position(match nav {
                NavView::Status(s) => Some(s.along_m),
                NavView::NoCourse | NavView::NoFix => None,
            });
        }

        // A pushed settings frame (from the ble task; the sim seeds one above)
        // applies each present field to the recorder + alert engine. Config, not
        // run data — L4, applied before the event mutates run totals.
        if let Some(Some(s)) = settings_rx.try_changed() {
            apply_settings(&s, &mut recorder, &mut alerts, &sea_level_tx);
        }

        match event {
            Event::Tick => recorder.tick(Instant::now().as_secs() as u32),
            Event::Fix(fix) => {
                if let Some(r) = hr_rx.try_changed() {
                    latest_bpm = bpm_of(&r);
                    // The recorder's zone-time accumulators bank against the
                    // same HR the track points are stamped with; a dropped
                    // pulse (None) stops the accrual.
                    recorder.set_hr(latest_bpm.map(u16::from));
                }
                if let Some(r) = elev_rx.try_changed() {
                    latest_baro_alt_m = Some(r.alt_m);
                    // The recorder's live-GAP grade prefers the barometric
                    // altitude, same as the track-point stamping below.
                    recorder.set_baro_altitude(r.alt_m);
                }
                #[cfg(feature = "sim-autostart")]
                if recorder.state() == RecordState::Idle {
                    let now_s = Instant::now().as_secs() as u32;
                    recorder.start(now_s);
                    ticker.reset(); // fresh clock — no catch-up burst of ticks
                    open = open_run(&mut next_seq, now_s);
                    trackback.reset();
                    crumb_len = 0;
                    info!("record: sim-autostart on first fix");
                }
                recorder.on_fix(&fix);
                if recorder.last_fix_stored() {
                    if let Some(o) = open.as_mut() {
                        push_point(o, &fix, latest_bpm, latest_baro_alt_m);
                    }
                    trackback.on_point(fix.lat_deg, fix.lon_deg, fix.uptime_s);
                    let view = trackback.view();
                    if view.len < crumb_len {
                        info!(
                            "trackback: breadcrumb thinned to {=usize} points (spacing doubled)",
                            view.len
                        );
                    }
                    crumb_len = view.len;
                    debug!(
                        "trackback: crumbs={=usize} to_start={=f32}m brg={=?} hdg={=?}",
                        view.len,
                        view.distance_to_start_m,
                        view.bearing_to_start_deg,
                        view.heading_deg
                    );
                    trackback_sender.send(view);
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
                    // A new run must never render the previous run's crumb: the
                    // published empty view holds the page's placeholders until
                    // the first accepted fix anchors the new start.
                    trackback.reset();
                    crumb_len = 0;
                    trackback_sender.send(trackback.view());
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
        let alert = alerts.on_update(
            &snap,
            latest_bpm.map(u16::from),
            Instant::now().as_secs() as u32,
        );
        if alert != last_alert {
            match alert {
                Some(a) => info!("record: alert {}", a),
                None => info!("record: alert cleared"),
            }
            last_alert = alert;
            alert_sender.send(alert);
        }
        if snap != last_published {
            debug!(
                "record: {} dist={}m moving={}s pacer={}s",
                state_str(snap.state),
                snap.distance_m,
                snap.moving_s,
                snap.pacer.map(|p| p.ahead_s)
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

/// Plausible QNH sea-level pressure window (Pa). A pushed `sea_level_pa` outside
/// this is ignored — never published — the same "reject, don't clamp"
/// discipline the recorder/alert setters keep for a garbage value. ~870–1080
/// hPa spans every real weather system (record sea-level pressure extremes sit
/// well inside it), so anything outside is a corrupt or misframed push.
const MIN_SEA_LEVEL_PA: f32 = 87_000.0;
const MAX_SEA_LEVEL_PA: f32 = 108_000.0;

/// Apply a pushed settings frame: each present field feeds the recorder's (or
/// alert engine's) existing settings-sync setter, which keeps its own
/// plausibility guard, so a bad value is rejected the same way regardless of
/// transport. The QNH sea-level reference has no setter (it is a `state` watch
/// the baro task consumes), so its plausibility guard lives here — range-check,
/// then publish. Absent fields are left untouched — a partial push is a partial
/// update, never a reset of the rest.
fn apply_settings(
    s: &WatchSettings,
    recorder: &mut Recorder,
    alerts: &mut AlertEngine,
    sea_level_tx: &Sender<'static, CriticalSectionRawMutex, f32, 1>,
) {
    if let Some(hr) = s.max_hr {
        recorder.set_max_hr(hr);
    }
    if let Some(p) = s.pacer {
        recorder.set_pacer_goal(p.distance_m, p.time_s);
    }
    if let Some(g) = s.gear {
        recorder.set_gear(Some(g.baseline_m as f64), g.target_m.map(f64::from));
    }
    if let Some(z) = s.zone_ceiling {
        alerts.set_zone_ceiling(z);
    }
    if let Some(pa) = s.sea_level_pa {
        if (MIN_SEA_LEVEL_PA..=MAX_SEA_LEVEL_PA).contains(&pa) {
            sea_level_tx.send(pa);
        }
    }
    if let Some(f) = s.fuel {
        alerts.set_fuel_intervals(f.drink_interval_s, f.eat_interval_s);
    }
}

enum Event {
    Tick,
    Fix(Fix),
    Cmd(RecordCommand),
}
