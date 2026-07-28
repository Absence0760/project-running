//! Cross-task shared state.
//!
//! The seams between producers and consumers. Each `Watch` hands out at most
//! `N` receivers and returns `None` past that, so `N` tracks the live
//! subscriber count — bump it when a new consumer subscribes.

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::channel::Channel;
use embassy_sync::watch::Watch;
use watch_core::alerts::Alert;
use watch_core::button::RecordCommand;
use watch_core::course::Course;
use watch_core::elevation::{Reading as ElevationReading, RezeroStatus};
use watch_core::face::{IdleView, NavView};
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::gnss_signal::SignalSample;
use watch_core::hr_duty::HrSample;
use watch_core::page::Page;
use watch_core::profiles::ActivityProfile;
use watch_core::record::{RouteElevView, Snapshot};
use watch_core::settings::WatchSettings;
use watch_core::settings_queue::SETTINGS_QUEUE_DEPTH;
use watch_core::trackback::TrackbackView;
use watch_core::workout::{WorkoutStep, MAX_WORKOUT_STEPS};

/// Merged GPS fixes: `gps` publishes; `ui`, `phone`, `record`, `nav`, and
/// `baro` (which feeds GPS altitude into the elevation complementary filter)
/// subscribe.
pub static FIX: Watch<CriticalSectionRawMutex, Fix, 5> = Watch::new();

/// Latest heart-rate estimate, stamped with the uptime it was produced at:
/// `hr` publishes; the `ui` face and `record` (to stamp each stored track
/// point's bpm) subscribe. Both consumers age the sample through
/// `hr_duty::shown_bpm`, so a duty-cycled (or wedged) sensor's last reading
/// holds only within the mode's bounded staleness and then blanks / stops
/// banking everywhere at once.
pub static HR: Watch<CriticalSectionRawMutex, HrSample, 2> = Watch::new();

/// Live recording totals: `record` publishes on change, the `ui` face, the
/// `button` task (for the state its toggle keys off), the `gps` task (which
/// de-rates fix publication while no run is active), and the `baro` task (which
/// gates vert accumulation on the runner moving) subscribe.
pub static RECORD: Watch<CriticalSectionRawMutex, Snapshot, 4> = Watch::new();

/// Recording control commands: the `button` task sends, `record` receives and
/// drives its state machine. A small buffer so a quick double-press (e.g.
/// pause then stop) is never dropped.
pub static RECORD_CMD: Channel<CriticalSectionRawMutex, RecordCommand, 4> = Channel::new();

/// Barometric elevation snapshot: `baro` publishes whenever
/// `elevation::should_publish` says the reading moved enough to be worth a
/// wake; the `ui` face, the `phone`/`ble` link, and `record` (to stamp each
/// stored track point's altitude) subscribe.
pub static ELEVATION: Watch<CriticalSectionRawMutex, ElevationReading, 3> = Watch::new();

/// The on-run alert currently on screen (`None` when the slot is clear):
/// `record` drives the `watch_core::alerts` engine and publishes on change;
/// the `ui` face draws the active alert as a 2x banner over the hero band.
/// One receiver (the `ui` task).
pub static ALERT: Watch<CriticalSectionRawMutex, Option<Alert>, 1> = Watch::new();

/// Current run-view page: the `button` task advances it on each BTN3 press, the
/// `ui` face reads it to pick the layout. One receiver (the `ui` task).
pub static PAGE: Watch<CriticalSectionRawMutex, Page, 1> = Watch::new();

/// Which idle face is showing: the `button` task toggles it on BTN4 while no
/// run is under way (home clock <-> diagnostics, decisions §291), the `ui`
/// face reads it to pick the idle layout. One receiver (the `ui` task).
pub static IDLE_VIEW: Watch<CriticalSectionRawMutex, IdleView, 1> = Watch::new();

/// The page-grid overview's cursor while the grid is open, `None` when closed.
/// The `button` task owns the grid state machine (`watch_core::page_grid`) and
/// its auto-select deadline; the `ui` task only renders whatever cursor this
/// carries. One receiver (the `ui` task).
pub static PAGE_GRID: Watch<CriticalSectionRawMutex, Option<Page>, 1> = Watch::new();

/// When the stop guard armed (uptime seconds), `None` once confirmed or
/// disarmed. The `button` task's dispatch publishes it; the `ui` task shows
/// the "press again" banner while the arm is inside its confirm window (the
/// window expiry itself is time-based, so a stale stamp simply stops
/// rendering). One receiver (the `ui` task).
pub static STOP_ARMED: Watch<CriticalSectionRawMutex, Option<u32>, 1> = Watch::new();

/// The idle settings menu's cursor while it is open (`None` = closed) —
/// §351. The `button` task owns the menu state machine (like the page grid);
/// the `ui` task only renders the published cursor over the idle face. One
/// receiver (the `ui` task).
pub static SETTINGS_MENU: Watch<CriticalSectionRawMutex, Option<u8>, 1> = Watch::new();

/// The last-applied activity profile (§353), `None` until one is ever chosen.
/// `main` seeds it from the persisted CFG1 record at boot, the `button` task
/// re-publishes on a menu selection, and the `ui` task renders it on the
/// menu's PROFILE row. One receiver (the `ui` task).
pub static PROFILE: Watch<CriticalSectionRawMutex, Option<ActivityProfile>, 1> = Watch::new();

/// Course-projection status for the Nav page: the `nav` task publishes per fix
/// (or once at boot when no course is loaded); the `ui` task renders it and
/// `record` reads the distance-along-course it feeds the recorder for the
/// cut-off ETA. Two receivers (`ui`, `record`).
pub static NAV: Watch<CriticalSectionRawMutex, NavView, 2> = Watch::new();

/// Pushed breadcrumb course (README course-push path): the `ble` task decodes a
/// chunked phone write into a `course_store` frame, builds a `Course`, and
/// publishes it here; the `nav` task swaps its active course to the pushed one
/// (from `NoCourse`, or over the boot/sim course), and the `ui` task draws the
/// pushed course's polyline on the Nav map. `None` means nothing pushed yet. Two
/// receivers (`nav`, `ui`). The 4 KiB value is the course's point buffer — held
/// once here so a re-push replaces it cleanly, no static-cell reuse.
pub static COURSE: Watch<CriticalSectionRawMutex, Option<Course>, 2> = Watch::new();

/// Pushed structured workout (the `WKT1` path): the `ble` task decodes a
/// chunked phone write into a `workout_store` frame's step list and publishes
/// it here; the `record` task arms the recorder's workout runner with it.
/// `None` means nothing pushed yet — the Workout page reads its honest
/// inactive state. Latest-value (a re-push replaces the armed workout), unlike
/// the `SETTINGS` deltas. One receiver (`record`).
pub static WORKOUT: Watch<
    CriticalSectionRawMutex,
    Option<heapless::Vec<WorkoutStep, MAX_WORKOUT_STEPS>>,
    1,
> = Watch::new();

/// The active course's climb profile for the RouteElev page: the `nav` task —
/// which already owns the active (boot or pushed) course — shapes one with
/// `course_profile::course_elev_view` whenever that course changes and publishes
/// it here; the `record` task folds it into the recorder so the face + the
/// profile overlay read it off the snapshot. `None` means no course is loaded.
/// Sent instead of the `Course` itself so no second ~4.5 KiB polyline copy has
/// to live in the record task. One receiver (`record`).
pub static ROUTE_PROFILE: Watch<CriticalSectionRawMutex, Option<RouteElevView>, 1> = Watch::new();

/// Back-to-start navigation view (breadcrumb + distance/bearing to start):
/// `record` publishes one per accepted fix — the same seam the flash track
/// store consumes, so the crumb mirrors the stored track exactly — and the
/// `ui` task renders it on the BackToStart page. One receiver (the `ui`).
pub static TRACKBACK: Watch<CriticalSectionRawMutex, TrackbackView, 1> = Watch::new();

/// Selected GNSS recording mode: the `button` task cycles it on an idle-face
/// BTN3 press; the `gps` task reads the fix-forwarding cadence, `record` the
/// interval its acceptance filter scales to, the `ui` face the mode rows +
/// staleness budget, and the `hr` task its sampling duty cycle
/// (`hr_duty::duty_window`). No value published means the default
/// (Performance).
pub static GNSS_MODE: Watch<CriticalSectionRawMutex, GnssMode, 4> = Watch::new();

/// Uptime (seconds) of the last button press — any button. The `button` task
/// stamps it on every confirmed press; the `ui` task reads it to gate the
/// face's ~1 Hz animations to a short window after an interaction, so an idle
/// wrist stops paying the per-second animation redraw. One receiver (the `ui`).
pub static INTERACTION: Watch<CriticalSectionRawMutex, u32, 1> = Watch::new();

/// The idle signal meter's input pair — GSV satellites-in-view plus the GSA
/// fix mode: the `gps` task publishes it best-effort whenever
/// `gnss_signal::should_publish` says the bar count would move, so a repeated
/// GSV group (one sentence each) cannot wake the face several times a second.
/// The pair travels together because the bars are a function of both. No value
/// published means "nothing acquired" (zero bars). One receiver (the `ui`
/// face's meter).
pub static SIGNAL: Watch<CriticalSectionRawMutex, SignalSample, 1> = Watch::new();

/// Pushed user settings (max HR / pacer goal / gear / HR-zone ceiling / QNH /
/// fuel cadences / page curation / timezone offset): the `ble` task decodes a
/// phone characteristic write (the sim decodes the same frames off the
/// phone-link pipe via `phone::settings_rx`, and seeds a demo frame) and sends;
/// the `record` task drains every queued frame and applies each present field
/// to the recorder + alert engine through their settings-sync setters.
///
/// A queue rather than a latest-value slot because each frame is a *delta* —
/// an absent field means "leave it alone", so two frames arriving between two
/// record-task wakes must both be applied, and coalescing them would drop the
/// earlier push's fields entirely. Depth + reasoning in
/// `watch_core::settings_queue`.
pub static SETTINGS: Channel<CriticalSectionRawMutex, WatchSettings, SETTINGS_QUEUE_DEPTH> =
    Channel::new();

/// Latest battery percent estimate. `None` means no plausible reading — an
/// absent battery, a bench/USB regulator rail, or a mid-stream reading that
/// left the LiPo band — and consumers show their honest absent state (no
/// icon, no BAT row). The `battery` task publishes on change only (a steady
/// percent wakes nobody); the `ui` task draws the idle-face gauge and the
/// diagnostics BAT row from it. One receiver (the `ui` task).
pub static BATTERY: Watch<CriticalSectionRawMutex, Option<u8>, 1> = Watch::new();

/// QNH sea-level reference pressure (Pa) for the barometric-altitude
/// calculation: the `record` task publishes a plausibility-guarded value when a
/// pushed settings frame carries `sea_level_pa` (the mountain/desert weather-
/// front recalibration); the `baro` task consumes it and swaps its altitude
/// reference off the fixed `STANDARD_SEA_LEVEL_PA`. No value published means the
/// baro task keeps its default reference. One receiver (the `baro` task).
pub static SEA_LEVEL_PA: Watch<CriticalSectionRawMutex, f32, 1> = Watch::new();

/// Local-time offset (minutes east of UTC) for the home clock: the `record`
/// task publishes the plausibility-guarded value when a pushed settings frame
/// carries `tz_offset_min` (the phone auto-sources it from its own zone —
/// same dedicated-watch seam as `SEA_LEVEL_PA`, so the `ui` task never
/// re-derives partial-frame apply semantics); the `ui` task shifts the home
/// clock hero and flips its row-7 label UTC → LOCAL. No value published means
/// the clock stays honestly UTC-labelled. One receiver (the `ui` task).
pub static TZ_OFFSET_MIN: Watch<CriticalSectionRawMutex, i16, 1> = Watch::new();

/// Manual QNH re-zero request: the `button` task sends one on an idle-face
/// BTN3 long-press; the `baro` task (which owns the vert accumulator the snap
/// applies to) receives and performs it. Capacity 1 — a press while one is
/// pending has nothing extra to ask for.
pub static QNH_REZERO_REQ: Channel<CriticalSectionRawMutex, (), 1> = Channel::new();

/// How many runs on flash are a mid-run checkpoint the phone has not pulled —
/// the runs whose recording ended with the power rather than with a stop. The
/// `run_flash` store publishes it (from its boot scan, and again whenever an
/// eviction, a failed commit, or a completed phone pull moves the count); the
/// `ui` task shows it as a standing marker on the home face, so a runner whose
/// watch rebooted mid-ultra can see the run survived and needs syncing. No value
/// published means none. One receiver (the `ui` task).
pub static PENDING_RUNS: Watch<CriticalSectionRawMutex, u8, 1> = Watch::new();

/// Outcome of the latest manual QNH re-zero, stamped with the uptime second it
/// was decided: the `baro` task publishes it (honest refusals included — no
/// fresh GPS, no barometer); the `ui` task shows it as a transient idle-face
/// banner. One receiver (the `ui` task).
pub static QNH_REZERO: Watch<CriticalSectionRawMutex, (RezeroStatus, u32), 1> = Watch::new();
