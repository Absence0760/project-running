//! Recording task — drives the host-tested `watch_core::record` state machine
//! from the button command stream and the live fix stream, publishes a snapshot
//! of the run totals, and streams the GPS track to the on-device flash run
//! store so a finished run can be synced to the phone (README step 7).
//!
//! Thin glue by design: distance, moving time, pace, the point-acceptance
//! filter, and the auto-pause all live in `watch_core::record` (host-tested);
//! the button-press → command mapping lives in `watch_core::button`; the flash
//! slot layout in `watch_core::flash_store`; the tick gate, flash-checkpoint
//! cadence, track-point shaping and pushed-QNH guard in
//! `watch_core::record_cadence`; and which sink each pushed settings field
//! feeds in `watch_core::settings_apply`. This task selects over incoming
//! fixes (fed to the recorder), commands (drive start/pause/resume/stop/lap),
//! and a pushed settings frame waiting to be drained, plus — only while a run
//! is Recording or Paused — a 1 Hz tick that advances the wall clock between
//! fixes. Idle and Finished have no clock to advance, so the tick is dropped
//! there and the task waits purely on events. It publishes a snapshot only when
//! it actually changed, so a resting recorder wakes no downstream consumer (the
//! ui face, the button task) on a heartbeat.
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
use embassy_futures::select::{select3, select4, Either3, Either4};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::watch::Sender;
use embassy_time::{Duration, Instant, Ticker};
use heapless::Vec;
use watch_core::alerts::{Alert, AlertEngine};
use watch_core::button::RecordCommand;
#[cfg(feature = "sim-course")]
use watch_core::cutoff_eta::CutoffLeg;
use watch_core::face::NavView;
use watch_core::fix::Fix;
use watch_core::flash_store::SLOT_LEN;
use watch_core::gnss_mode::GnssMode;
use watch_core::hr_duty::{self, HrSample};
use watch_core::ice::IceCard;
use watch_core::record::{RecordState, Recorder, Snapshot};
use watch_core::record_cadence::{run_active, track_point, CheckpointMark};
use watch_core::run_store::{
    verify_blob, LapRecord, PushOutcome, RunWriter, StepRecord, WorkoutRecord,
};
use watch_core::settings::{GuidedRunId, WatchSettings};
use watch_core::settings_apply::{plan_apply, SettingsEffect};
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
    /// Where the last mid-run flash checkpoint left off — both checkpoint
    /// triggers measure against it (`CheckpointMark::due`).
    last_ckpt: CheckpointMark,
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
            last_ckpt: CheckpointMark::default(),
        }),
        Err(_) => {
            warn!("record: run writer start failed");
            None
        }
    }
}

/// Append one accepted fix to the staged track, stamped with the latest HR +
/// altitude. The bounded push decimates instead of truncating when the tier-1
/// slot fills (issue #599): the whole run stays represented at coarser
/// resolution, and the new factor is returned so the recorder's snapshot can
/// surface it on the wrist.
fn push_point(
    open: &mut OpenRun,
    fix: &Fix,
    bpm: Option<u16>,
    baro_alt_m: Option<f32>,
) -> Option<u32> {
    let point = track_point(fix, open.start_uptime_s, bpm, baro_alt_m);
    match open.writer.push_point_bounded(&point) {
        PushOutcome::Thinned(k) => {
            warn!(
                "record: run {=u32} slot full — track thinned to 1/{=u32} resolution, whole run kept",
                open.run_seq, k
            );
            Some(k)
        }
        PushOutcome::Stored | PushOutcome::Dropped => None,
    }
}

/// Persist a just-closed lap into the staged blob (v2 lap record, stream
/// order). Best-effort like the rest of the flash path: a full sink or the
/// per-run stored-lap budget only warns — the RAM display state is what the
/// runner reads mid-run.
fn push_lap(open: &mut OpenRun, lap: &watch_core::record::Lap) {
    let record = LapRecord {
        index: lap.index,
        lap_distance_dm: (lap.distance_m * 10.0).clamp(0.0, u32::MAX as f64) as u32,
        split_s: lap.elapsed_s,
        moving_s: lap.moving_s,
    };
    match open.writer.push_lap(&record) {
        Ok(true) => {}
        Ok(false) => warn!(
            "record: run {=u32} lap {=u16} dropped from storage (stored-lap budget)",
            open.run_seq, lap.index
        ),
        Err(_) => warn!(
            "record: run {=u32} lap {=u16} dropped from storage (slot full)",
            open.run_seq, lap.index
        ),
    }
}

/// Persist one settled workout step into the staged blob (v4 step record,
/// stream order). Best-effort like the lap path: the RAM roll-up is what the
/// runner reads mid-run; a full sink or the stored-step budget only warns.
fn push_step_result(open: &mut OpenRun, r: &watch_core::workout::StepResult) {
    let record = StepRecord {
        step_index: r.step_index,
        skipped: r.status == watch_core::workout::StepStatus::Skipped,
        distance_dm: (r.actual_distance_m * 10.0).clamp(0.0, u32::MAX as f64) as u32,
        duration_s: r.actual_duration_s.clamp(0.0, u32::MAX as f64) as u32,
        pace_s_per_km: r.actual_pace_s_per_km,
    };
    match open.writer.push_step(&record) {
        Ok(true) => {}
        Ok(false) => warn!(
            "record: run {=u32} workout step {=u8} dropped from storage (stored-step budget)",
            open.run_seq, r.step_index
        ),
        Err(_) => warn!(
            "record: run {=u32} workout step {=u8} dropped from storage (slot full)",
            open.run_seq, r.step_index
        ),
    }
}

/// Flush the armed workout's remaining trail into the staged blob before the
/// final commit (decisions §356): any settled results the event loop hasn't
/// drained yet, the in-progress step recorded as skipped-so-far, then the
/// summary that attributes the whole trail to the pushed WKT1 frame. Without
/// the summary the phone deliberately discards the step records, so a step
/// list the canonical encoder refuses (which set_workout can't arm from a
/// real push) is logged rather than half-written.
fn flush_workout(open: &mut OpenRun, recorder: &mut Recorder) {
    while let Some(r) = recorder.pop_settled_workout_result() {
        push_step_result(open, &r);
    }
    if let Some(r) = recorder.workout_in_progress_result() {
        push_step_result(open, &r);
    }
    let Some(summary) = recorder.workout_summary() else {
        return;
    };
    let Some(frame_crc) = summary.frame_crc else {
        warn!(
            "record: run {=u32} workout trail has no frame CRC — summary not stored",
            open.run_seq
        );
        return;
    };
    let record = WorkoutRecord {
        step_total: summary.step_total,
        partial: summary.rollup == watch_core::workout::WorkoutAdherence::Partial,
        frame_crc,
    };
    match open.writer.push_workout(&record) {
        Ok(true) => info!(
            "record: run {=u32} workout results stored ({=u8} planned steps)",
            open.run_seq, summary.step_total
        ),
        Ok(false) => warn!(
            "record: run {=u32} workout summary already stored",
            open.run_seq
        ),
        Err(_) => warn!(
            "record: run {=u32} workout summary dropped (slot full)",
            open.run_seq
        ),
    }
}

/// Persist a recoverable snapshot of the run-so-far to its flash slot WITHOUT
/// consuming the staging writer (best-effort / L4). Mirrors [`commit_run`] but
/// builds the blob via `checkpoint_blob`, so recording keeps streaming into the
/// same writer afterwards.
async fn checkpoint_run(store: &'static SharedStore, open: &OpenRun, snap: &Snapshot) {
    let distance_m = snap.distance_m.max(0.0) as u32;
    let Some(blob) = open
        .writer
        .checkpoint_blob(distance_m, snap.moving_s, snap.elapsed_s)
    else {
        warn!(
            "record: checkpoint blob build failed for run {=u32}",
            open.run_seq
        );
        return;
    };
    if !verify_blob(&blob) {
        warn!(
            "record: checkpoint blob for run {=u32} failed self-verify, not storing",
            open.run_seq
        );
        return;
    }
    store
        .lock()
        .await
        .checkpoint(open.run_seq, open.start_uptime_s, &blob)
        .await;
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
        .commit(open.run_seq, open.start_uptime_s, &blob)
        .await;
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
    let mut route_profile_rx = unwrap!(state::ROUTE_PROFILE.receiver());
    let mut workout_rx = unwrap!(state::WORKOUT.receiver());
    let sender = state::RECORD.sender();
    let alert_sender = state::ALERT.sender();
    let trackback_sender = state::TRACKBACK.sender();
    let sea_level_tx = state::SEA_LEVEL_PA.sender();
    let tz_offset_tx = state::TZ_OFFSET_MIN.sender();
    let ice_tx = state::ICE.sender();
    let screens_tx = state::SCREENS.sender();
    let mut screens_rx = state::SCREENS.receiver().unwrap();
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
    // Restore the persisted hide-empty-pages choice (§351) so the settings
    // menu's toggle survives a reboot the way the GNSS mode does; None means
    // no explicit choice was ever stored and the recorder keeps its default.
    let mut persisted_hide: Option<bool> = store.lock().await.read_hide_empty();
    // The ICE card the flash record already holds — published straight away so
    // the idle face has it before any phone connects, and kept as the
    // comparison so a repeated push never re-erases the config page.
    let mut persisted_ice = store.lock().await.read_ice();
    if persisted_ice.is_some() {
        info!("record: restored ICE card");
    }
    ice_tx.send(persisted_ice);
    // The composed data screens the flash record already holds (§364) —
    // published straight away so the page cycle carries them before any phone
    // connects, and kept as the comparison so a repeated push never re-erases
    // the config page. A runner who built their screens the night before a race
    // has them at the start line, battery pull or not.
    let mut persisted_screens = store.lock().await.read_screens();
    if let Some(s) = persisted_screens.as_ref() {
        info!("record: restored {=usize} composed screen(s)", s.len());
    }
    // The recorder holds only the count — it decides which `Screen*` pages the
    // BTN3 cycle carries; the screens themselves reach the face through the
    // published set, so there is one copy of them and it cannot disagree with
    // itself about how many there are.
    recorder.set_screen_count(persisted_screens.as_ref().map_or(0, |s| s.len()));
    // Sim-only composed screens, published on the SAME channel a phone push
    // feeds so the whole publish → gate → render path runs, not a shortcut into
    // the face. One screen per layout, headed by metrics the bench_jog fixture
    // actually moves, so the panel shows numbers changing rather than three
    // `SYNC` tokens: distance and pace are fed from the first fix, elapsed and
    // lap from the clock, and altitude from the sim's baro.
    #[cfg(feature = "sim-screens")]
    if persisted_screens.is_none() {
        use watch_core::face::Metric;
        use watch_core::screens::{Layout, Screen, Screens};
        let demo = Screens::from_slice(&[
            unwrap!(Screen::new(
                Layout::Duo,
                &[Metric::Distance, Metric::AvgPace]
            )),
            unwrap!(Screen::new(
                Layout::Trio,
                &[Metric::Elapsed, Metric::HeartRate, Metric::Altitude]
            )),
            unwrap!(Screen::new(Layout::Single, &[Metric::LapElapsed])),
        ]);
        if let Some(set) = demo {
            info!("record: sim composed screens ({=usize})", set.len());
            persisted_screens = Some(set.clone());
            recorder.set_screen_count(set.len());
        }
    }
    screens_tx.send(persisted_screens.clone());
    let mut open: Option<OpenRun> = None;
    let mut hr: Option<HrSample> = None;
    let mut mode = GnssMode::default();
    let mut latest_baro_alt_m: Option<f32> = None;
    let mut trackback = Trackback::new();
    let mut crumb_len: usize = 0;
    if let Some(hide) = persisted_hide {
        recorder.set_hide_empty_pages(hide);
        info!("record: restored hide-empty-pages {}", hide);
    }
    // Re-apply the persisted activity profile's page preset (§353) — the
    // selection itself is display state (main seeds `state::PROFILE`), but the
    // curated mask lives only in the recorder, so a reboot re-derives it from
    // the stored profile the way the mode is re-read from CFG1.
    if let Some(p) = store.lock().await.read_profile() {
        recorder.set_pages_enabled(watch_core::profiles::preset(p).pages);
        info!("record: restored profile {} page preset", p);
    }
    // Restore the marked waypoints (§357). A stash the runner marked is worth
    // nothing if a battery pull forgets it, so the store is read back before
    // the first press can land; an absent or corrupt record leaves the empty
    // store the recorder booted with.
    if let Some(w) = store.lock().await.read_waypoints() {
        info!("record: restored {=usize} waypoint(s)", w.len());
        recorder.set_waypoints(w);
    }
    // Seed with the initial idle snapshot so it is never published — consumers
    // treat "no RECORD value yet" as idle, which is exactly right.
    let mut last_published = recorder.snapshot();
    #[cfg(feature = "sim-autostart")]
    info!("record: sim-autostart on — starts on first fix");
    // The sim can't wait 15 minutes of moving time for a real reminder, so the
    // sim build shortens the fuel cadences (drink 30 s, eat 45 s of moving time).
    // Hardware keeps the fuel_plan-derived defaults.
    //
    // Its own feature rather than riding `sim-autostart`, because these cadences
    // are what the `alerts` scenario exists to observe and pure noise to
    // everything else: past ~100 s they overlap into a continuous banner, and a
    // banner covers the two hero rows of whatever page is on screen. That made
    // six of `bin/watch-shots.sh`'s twenty-one run screens unusable as layout
    // references — including CLMB, whose whole hero is the climb figure — with
    // no way to ask for a quiet watch short of dropping the demo settings that
    // arm most of the pages. `--no-alerts` is that way.
    #[cfg(feature = "sim-alerts")]
    {
        alerts.set_fuel_intervals(30, 45);
        info!("record: sim fuel cadence 30s drink / 45s eat (moving time)");
        // The distance / time / pace arms are off on hardware until a settings
        // sync arms them, so the sim arms them itself through the same public
        // setters: the shortest plausible cadences, and a band straddling the
        // ~5:33/km bench_jog fixture so the pace alert reads a live TOO SLOW.
        alerts.set_distance_interval(Some(watch_core::alerts::DISTANCE_INTERVAL_MIN_M));
        alerts.set_time_interval(Some(watch_core::alerts::TIME_INTERVAL_MIN_S));
        alerts.set_pace_band(Some((300, 320)));
        info!("record: sim alerts 100m / 60s / pace band 5:00-5:20 per km");
    }
    // Sim-only demo settings, applied through the SAME path a phone push takes
    // (`apply_settings`) so the sim exercises the settings-sync apply, not a
    // separate hardcoded seam: a 1 km / 5:00 pacer goal (a partner slightly
    // faster than the ~5:33/km bench_jog fixture, so the Pacer page reads a live
    // BEHIND) and a 700 km / 800 km shoe (a live DUE the run's mileage pushes on).
    //
    // The race-phase plan and the guided run are here for the same reason and
    // with values picked so their pages are not merely non-empty but *move*
    // under bench_jog. 1 km is `RACE_PHASE_PLAUSIBLE_MIN_DISTANCE_M`, the
    // shortest plan the setter accepts, and `TenTenTen` has the earliest first
    // boundary any preset offers (381.4 m, the generalised 10-mile fraction) —
    // so the Pacer page's phase row walks HOLD 5:06 -> SETTLE 5:00 -> RACE 4:50
    // as the run accrues rather than sitting in phase 1. The goal time matches
    // the pacer goal so both rows on that page describe one race.
    // `first-timer-15` is the library run with the densest early cues (0 s,
    // 180 s, then every 60 s), so the GuidedRun page's cue index advances inside
    // the first few minutes; the other two wait 240 s / 300 s for their second.
    // Hardware stays unset until a real push over the settings characteristic.
    #[cfg(feature = "sim-autostart")]
    {
        use watch_core::race_phases::RacePhasePreset;
        use watch_core::settings::{
            race_phase_preset_to_wire, GearCfg, GuidedRunId, PacerGoalCfg, RacePhasesCfg,
        };
        let demo = WatchSettings {
            pacer: Some(PacerGoalCfg {
                distance_m: 1_000,
                time_s: 300,
            }),
            gear: Some(GearCfg {
                baseline_m: 700_000.0,
                target_m: Some(800_000.0),
            }),
            race_phases: Some(RacePhasesCfg {
                distance_m: Some(1_000),
                goal_time_s: Some(300),
                preset: race_phase_preset_to_wire(RacePhasePreset::TenTenTen),
            }),
            guided_run: Some(GuidedRunId::new("first-timer-15")),
            // Mountain time (UTC-6), the bench_jog fixture's longitude — so the
            // Daylight page renders a live pre-dawn sunrise countdown (the
            // golden-tested 3:03 / AT 04:34 / DAYLIGHT 14:53) instead of its
            // NOT SYNCED state.
            tz_offset_min: Some(-360),
            ..WatchSettings::default()
        };
        apply_settings(
            &demo,
            &mut recorder,
            &mut alerts,
            &sea_level_tx,
            &tz_offset_tx,
            &ice_tx,
        );
        info!(
            "record: sim demo settings applied (pacer 1km/5:00, gear 700/800 km, phases 1km/5:00 ten-ten-ten, guided first-timer-15, tz UTC-6)"
        );
        // A demo structured workout, armed over the SAME channel a phone's
        // WKT1 push lands on, with steps short enough that the ~3 m/s
        // bench_jog fixture walks the whole thing in ~2 minutes: warmup,
        // 2 x (50 m rep / 30 s timed recovery), cooldown — so the Workout
        // page advances, the step banners fire, and DONE is reachable.
        // Hardware stays unset until a real push over the characteristic.
        {
            use watch_core::workout::{WorkoutStep, WorkoutStepKind};
            let dist = |kind, rep_index, rep_total, target_distance_m, pace| WorkoutStep {
                kind,
                rep_index,
                rep_total,
                target_distance_m,
                target_duration_s: 0,
                target_pace_s_per_km: pace,
                tolerance_s_per_km: 10,
            };
            let mut steps: heapless::Vec<WorkoutStep, { watch_core::workout::MAX_WORKOUT_STEPS }> =
                heapless::Vec::new();
            let _ = steps.push(dist(WorkoutStepKind::Warmup, 0, 0, 60, 360));
            let _ = steps.push(dist(WorkoutStepKind::Rep, 1, 2, 50, 300));
            let _ = steps.push(WorkoutStep {
                kind: WorkoutStepKind::Recovery,
                rep_index: 1,
                rep_total: 1,
                target_distance_m: 0,
                target_duration_s: 30,
                target_pace_s_per_km: 420,
                tolerance_s_per_km: 15,
            });
            let _ = steps.push(dist(WorkoutStepKind::Rep, 2, 2, 50, 300));
            let _ = steps.push(dist(WorkoutStepKind::Cooldown, 0, 0, 60, 360));
            state::WORKOUT.sender().send(Some(steps));
            info!("record: sim demo workout queued (5 steps)");
        }
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
        // The settings arm is `ready_to_receive`, not `receive`: it wakes on a
        // pushed frame without taking it, so the drain below stays the sole
        // consumer and keeps every queued frame in one FIFO order. It is last so
        // it can never pre-empt a fix or a command, and it wakes only when a
        // publisher actually sends — nothing polls.
        let event = if run_active(recorder.state()) {
            match select4(
                ticker.next(),
                fix_rx.changed(),
                state::RECORD_CMD.receive(),
                state::SETTINGS.ready_to_receive(),
            )
            .await
            {
                Either4::First(()) => Event::Tick,
                Either4::Second(fix) => Event::Fix(fix),
                Either4::Third(cmd) => Event::Cmd(cmd),
                Either4::Fourth(()) => Event::Settings,
            }
        } else {
            match select3(
                fix_rx.changed(),
                state::RECORD_CMD.receive(),
                state::SETTINGS.ready_to_receive(),
            )
            .await
            {
                Either3::First(fix) => Event::Fix(fix),
                Either3::Second(cmd) => Event::Cmd(cmd),
                Either3::Third(()) => Event::Settings,
            }
        };

        // Keep the recorder's acceptance filter scaled to the selected GNSS
        // mode's fix cadence (see `Recorder::set_fix_interval_s`). The mode
        // only changes while idle (BTN3 cycles pages once a run is under way),
        // so it is always applied here before the Start command that opens the
        // run reaches the recorder.
        if let Some(m) = mode_rx.try_changed() {
            mode = m;
            recorder.set_fix_interval_s(m.fix_interval_s());
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
            // Presence bit for the page filter: NoFix still means a course is
            // loaded — only NoCourse hides the Nav page from the cycle.
            recorder.set_course_loaded(!matches!(nav, NavView::NoCourse));
            // The nav task owns the course, so it also carries the next turn
            // ahead; feed it to the recorder's TurnCue page (course-agnostic
            // recorder, same seam as the along-course distance above).
            recorder.set_turn_cue(match nav {
                NavView::Status(s) => s.next_turn,
                NavView::NoCourse | NavView::NoFix => None,
            });
        }

        // The active course's climb profile for the RouteElev page — shaped by
        // the nav task on each course change, so this only forwards it.
        if let Some(profile) = route_profile_rx.try_changed() {
            recorder.set_route_elev(profile);
        }

        // A pushed structured workout (the ble task's WKT1 decode) arms the
        // recorder's runner; a re-push replaces it, anchoring at the current
        // totals if a run is under way.
        if let Some(pushed) = workout_rx.try_changed() {
            match pushed {
                Some(steps) => {
                    recorder.set_workout(&steps);
                    info!("record: workout armed ({=usize} steps)", steps.len());
                }
                None => {
                    recorder.set_workout(&[]);
                    info!("record: workout cleared");
                }
            }
        }

        // Pushed settings frames (from the ble task; the sim seeds one above)
        // apply each present field to the recorder + alert engine. Config, not
        // run data — L4, applied before the event mutates run totals, so a frame
        // that arrived alongside a Start lands before that command reaches the
        // recorder. Every queued frame is drained in arrival order: each is a
        // delta, so applying only the newest would silently drop whatever an
        // earlier push carried.
        while let Ok(s) = state::SETTINGS.try_receive() {
            apply_settings(
                &s,
                &mut recorder,
                &mut alerts,
                &sea_level_tx,
                &tz_offset_tx,
                &ice_tx,
            );
            // An explicit hide-empty choice is persisted whichever side made
            // it — the settings menu's toggle and a phone push land here on
            // the same channel — so the last writer is what a reboot restores
            // (§351). Skipped when unchanged: the config page is never
            // re-erased for a repeated push.
            if let Some(hide) = s.hide_empty_pages {
                if persisted_hide != Some(hide) {
                    store.lock().await.persist_hide_empty(hide).await;
                    persisted_hide = Some(hide);
                }
            }
            // Same rule for the ICE card, and for the same reason it exists at
            // all: a medic reads the wrist of a watch that may have
            // power-cycled since the push. Skipped when unchanged.
            if let Some(card) = s.ice {
                if persisted_ice != card {
                    store.lock().await.persist_ice(card).await;
                    persisted_ice = card;
                }
            }
        }

        // Composed data screens arrive as a whole set, so this is a
        // latest-value read rather than a drained queue: one frame is the
        // complete answer, and a coalesced intermediate is not a lost edit the
        // way a dropped settings delta would be. Persisted only when it differs
        // from what flash already holds — which also means the publication this
        // task made from flash at boot costs no write when it comes back round.
        if let Some(set) = screens_rx.try_changed() {
            recorder.set_screen_count(set.as_ref().map_or(0, |s| s.len()));
            if persisted_screens != set {
                store.lock().await.persist_screens(set.as_ref()).await;
                persisted_screens = set;
            }
        }

        match event {
            Event::Tick => recorder.tick(Instant::now().as_secs() as u32),
            Event::Fix(fix) => {
                if let Some(s) = hr_rx.try_changed() {
                    hr = Some(s);
                }
                // The recorder's zone-time accumulators bank against the same
                // HR the track points are stamped with, and only within the
                // mode's duty-cycle hold budget (`hr_duty::shown_bpm`): a
                // duty-cycled gap banks the held zone through one off-window,
                // past that it banks nothing — the same rule the face shows
                // by. A dropped pulse (bpm None) stops the accrual instantly.
                let held = hr_duty::shown_bpm(hr, fix.uptime_s, mode);
                recorder.set_hr(held);
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
                        if let Some(k) = push_point(o, &fix, held, latest_baro_alt_m) {
                            recorder.set_track_thinning(k);
                        }
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
                    RecordCommand::Reset => recorder.reset(now_s),
                    RecordCommand::MarkWaypoint => {
                        // Persist immediately rather than at stop: the reason
                        // to mark a stash is that you may not finish the run
                        // that found it. Best-effort / L4 like every other
                        // config write — a flash error warns and the RAM mark
                        // still shows on the page. A refused mark (no anchor)
                        // writes nothing, so a dead press costs no page erase.
                        if recorder.mark_waypoint(now_s) {
                            let w = recorder.waypoints().clone();
                            store.lock().await.persist_waypoints(&w).await;
                        } else {
                            warn!("record: waypoint mark ignored — no position anchor");
                        }
                    }
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
                    if let Some(o) = open.as_mut() {
                        flush_workout(o, &mut recorder);
                    }
                    if let Some(o) = open.take() {
                        commit_run(store, o, &recorder.snapshot()).await;
                    }
                }
                info!("record: command {} -> {}", cmd, state_str(now));
            }
            // The drain above already consumed and applied the frame this wake
            // was for; the loop tail republishes whatever it changed.
            Event::Settings => {}
        }

        // Persist any laps this event closed (manual, auto, or a throttled
        // fix that crossed several kilometre boundaries at once) — one v2 lap
        // record each, in close order — and any workout steps it settled
        // (auto-advance or a lap-press skip) — one v4 step record each, so a
        // mid-run checkpoint carries the trail settled before it.
        if let Some(o) = open.as_mut() {
            while let Some(lap) = recorder.pop_closed_lap() {
                push_lap(o, &lap);
            }
            while let Some(r) = recorder.pop_settled_workout_result() {
                push_step_result(o, &r);
            }
        }

        // Publish only on change: a resting recorder must not wake the ui face
        // or the button task on a heartbeat.
        let snap = recorder.snapshot();

        // Best-effort mid-run flash checkpoint (L4): once a run has staged at
        // least one point, periodically persist a recoverable snapshot of the
        // run-so-far to its slot so a reset mid-run recovers a slightly-stale
        // partial run instead of the whole in-progress track (which only reaches
        // flash at stop otherwise). Cadence is wear-bounded — see
        // record_cadence::CHECKPOINT_INTERVAL_S. Runs after the recorder updates
        // and never in its way; the final commit_run at stop supersedes the last
        // checkpoint.
        if recorder.state() == RecordState::Recording {
            if let Some(o) = open.as_mut() {
                let points = o.writer.point_count();
                if o.last_ckpt.due(points, snap.elapsed_s) {
                    checkpoint_run(store, o, &snap).await;
                    o.last_ckpt = CheckpointMark {
                        points,
                        elapsed_s: snap.elapsed_s,
                    };
                }
            }
        }
        // The zone-ceiling alert judges the same staleness-bounded HR the
        // recorder banks with — a reading past its hold budget must not keep
        // an "over ceiling" alert alive.
        let alert_now_s = Instant::now().as_secs() as u32;
        let alert = alerts.on_update(
            &snap,
            hr_duty::shown_bpm(hr, alert_now_s, mode),
            alert_now_s,
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

/// Execute a pushed settings frame: `watch_core::settings_apply` decides which
/// sink each present field feeds and hands back one typed effect per field
/// (host-tested, exhaustive by construction), so this is only the seam that
/// owns the sinks themselves — the two `state` watches the baro + ui tasks
/// consume, and the recorder / alert-engine setters, each of which keeps its own
/// plausibility guard so a bad value is rejected the same way regardless of
/// transport.
fn apply_settings(
    s: &WatchSettings,
    recorder: &mut Recorder,
    alerts: &mut AlertEngine,
    sea_level_tx: &Sender<'static, CriticalSectionRawMutex, f32, 1>,
    tz_offset_tx: &Sender<'static, CriticalSectionRawMutex, i16, 1>,
    ice_tx: &Sender<'static, CriticalSectionRawMutex, Option<IceCard>, 1>,
) {
    for effect in plan_apply(s) {
        match effect {
            SettingsEffect::MaxHr(bpm) => recorder.set_max_hr(bpm),
            SettingsEffect::PacerGoal { distance_m, time_s } => {
                recorder.set_pacer_goal(distance_m, time_s)
            }
            SettingsEffect::Gear {
                baseline_m,
                target_m,
            } => recorder.set_gear(Some(baseline_m), target_m),
            SettingsEffect::ZoneCeiling(zone) => alerts.set_zone_ceiling(zone),
            SettingsEffect::SeaLevelPa(pa) => sea_level_tx.send(pa),
            SettingsEffect::FuelIntervals {
                drink_interval_s,
                eat_interval_s,
            } => alerts.set_fuel_intervals(drink_interval_s, eat_interval_s),
            SettingsEffect::PagesEnabled(mask) => recorder.set_pages_enabled(mask),
            SettingsEffect::HideEmptyPages(hide) => recorder.set_hide_empty_pages(hide),
            SettingsEffect::TzOffsetMin(m) => {
                recorder.set_tz_offset_min(m);
                tz_offset_tx.send(m);
            }
            SettingsEffect::DistanceInterval(m) => alerts.set_distance_interval(m),
            SettingsEffect::TimeInterval(s) => alerts.set_time_interval(s),
            SettingsEffect::PaceBand(band) => alerts.set_pace_band(band),
            SettingsEffect::RacePhases {
                distance_m,
                goal_time_s,
                preset,
            } => recorder.set_race_phases(distance_m, goal_time_s, preset),
            SettingsEffect::GuidedRun(id) => {
                recorder.set_guided_run(id.as_ref().map(GuidedRunId::as_str))
            }
            SettingsEffect::RestingHr(bpm) => recorder.set_resting_hr(bpm),
            // The one effect with two sinks: the watch the ui task renders
            // from, here, and the flash record the drain loop writes — a
            // medical ID that vanishes on a power cycle is not a medical ID.
            SettingsEffect::Ice(card) => ice_tx.send(card),
        }
    }
}

enum Event {
    Tick,
    Fix(Fix),
    Cmd(RecordCommand),
    Settings,
}
