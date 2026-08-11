//! Cross-task shared state.
//!
//! The seams between producers and consumers. Each `Watch` hands out at most
//! `N` receivers and returns `None` past that, so `N` tracks the live
//! subscriber count — bump it when a new consumer subscribes.

use core::sync::atomic::{AtomicU32, AtomicU8, Ordering};

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::channel::Channel;
use embassy_sync::watch::Watch;
use watch_core::alerts::Alert;
use watch_core::ble_sync::{PushKind, PushOutcome};
use watch_core::button::RecordCommand;
use watch_core::course::Course;
use watch_core::elevation::{Reading as ElevationReading, RezeroStatus};
use watch_core::face::{IdleView, NavView};
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::gnss_signal::SignalSample;
use watch_core::hr_duty::HrSample;
use watch_core::hr_source::HrSource;
use watch_core::ice::IceCard;
use watch_core::page::Page;
use watch_core::pairing;
use watch_core::profiles::ActivityProfile;
use watch_core::record::{RouteElevView, Snapshot};
use watch_core::roadbook_store::PushedRoadbook;
use watch_core::screens::Screens;
use watch_core::settings::WatchSettings;
use watch_core::settings_menu::MenuView;
use watch_core::settings_queue::SETTINGS_QUEUE_DEPTH;
use watch_core::storm::StormView;
use watch_core::timers::Timer;
use watch_core::trackback::TrackbackView;
use watch_core::workout::{WorkoutStep, MAX_WORKOUT_STEPS};

/// Merged GPS fixes: `gps` publishes; `ui`, `phone`, `record`, `nav`, `baro`
/// (which feeds GPS altitude into the elevation complementary filter), and
/// `button` (which needs the receiver's UTC date + time-of-day as the wall-clock
/// stamp a persisted timer's reboot gap is measured against, §375) subscribe.
/// The button task only ever `try_get`s it, so a fix wakes it not at all.
pub static FIX: Watch<CriticalSectionRawMutex, Fix, 6> = Watch::new();

/// Latest heart-rate estimate, stamped with the uptime it was produced at:
/// the `hr_source` arbiter publishes — it is the ONLY publisher, so which
/// sensor won is a stated rule (`watch_core::hr_source::select_hr`) rather
/// than whichever task wrote last; the `ui` face and `record` (to stamp each
/// stored track point's bpm) subscribe. Both consumers age the sample through
/// `hr_duty::shown_bpm`, so a duty-cycled (or wedged) sensor's last reading
/// holds only within the mode's bounded staleness and then blanks / stops
/// banking everywhere at once.
pub static HR: Watch<CriticalSectionRawMutex, HrSample, 2> = Watch::new();

/// Which sensor [`HR`]'s latest reading was credited to, or `None` when nothing
/// is authoritative (the blank the arbiter synthesises has no producer). The
/// `hr_source` arbiter publishes it beside the sample; `record` subscribes and
/// mirrors it onto the run snapshot so the zones page can name the sensor.
/// Without it the arbitration ended at a defmt line and a strap that never
/// paired was indistinguishable, on the wrist, from one that won.
pub static HR_SOURCE: Watch<CriticalSectionRawMutex, Option<HrSource>, 1> = Watch::new();

/// The optical (MAX86177) sensor's own estimate: the `hr` task publishes, the
/// `hr_source` arbiter subscribes. A separate seam from [`HR`] so the wrist
/// sensor keeps publishing what it sees even while an external strap outranks
/// it — the arbiter, not the sensor, decides what the watch shows.
pub static HR_OPTICAL: Watch<CriticalSectionRawMutex, HrSample, 1> = Watch::new();

/// An external BLE heart-rate strap's estimate (§365): the `hr_strap` GATT
/// central task publishes one per decoded Heart Rate Measurement notification
/// — and one `bpm: None` on disconnect, so a dropped strap yields immediately
/// instead of waiting out its staleness budget; the `hr_source` arbiter
/// subscribes. Only ever written by the `ble` build (the strap task needs the
/// SoftDevice radio); on every other build it stays empty and the arbiter
/// forwards the optical sensor unchanged.
pub static HR_STRAP: Watch<CriticalSectionRawMutex, HrSample, 1> = Watch::new();

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

/// The idle settings menu while it is open (`None` = closed) — §351. The
/// `button` task owns the menu state machine (like the page grid); the `ui`
/// task only renders the published view over the idle face. Carries the §378
/// erase arm alongside the cursor because both are one modal state: split
/// across two channels the panel could show an armed legend over an un-armed
/// row. One receiver (the `ui` task).
pub static SETTINGS_MENU: Watch<CriticalSectionRawMutex, Option<MenuView>, 1> = Watch::new();

/// A confirmed factory erase (§378). The `button` task sends one once its
/// [`watch_core::erase::EraseGuard`] confirms and the flash wipe has run; the
/// `record` task receives and drops the RAM that mirrors what was just erased —
/// the recorder (waypoints, biometrics, curation), the breadcrumb, the ICE card
/// and the composed screens.
///
/// A dedicated channel rather than a `SET1` field, for §372's reason verbatim:
/// this is a watch-only action with no wire meaning, and folding it into a
/// pushed-settings frame would invent a "wipe this watch" command the phone
/// does not have and no one asked for. Capacity 1 — a second erase while one is
/// pending has nothing extra to ask for.
pub static FACTORY_ERASE: Channel<CriticalSectionRawMutex, (), 1> = Channel::new();

/// The runner's countdown timer / stopwatch (§375). The `button` task owns the
/// instrument (like the grid and the menu) and publishes it whole on every
/// change; the `record` task derives the view it feeds the recorder and the `ui`
/// task the one it draws. The *instrument* travels rather than a rendered view
/// because every reading is a function of the reader's clock — publishing a view
/// would need a per-second wake to keep it true, which is exactly what § 328
/// rules out. Two receivers (`record`, `ui`).
///
/// The instrument is persisted to the config page's `TMR1` record on every state
/// change, so a brown-out cannot silently take an armed nap timer. The button
/// task republishes here once it has resolved the stored record against a
/// wall-clock stamp — which is why a restored timer can appear on these surfaces
/// without any press having happened.
pub static TIMER: Watch<CriticalSectionRawMutex, Timer, 2> = Watch::new();

/// Whether the timer modal is open (§375) — the same ownership split as
/// [`SETTINGS_MENU`], and a bare flag rather than a cursor because the modal
/// shows one instrument and has nothing to point at. One receiver (the `ui`).
pub static TIMER_MENU: Watch<CriticalSectionRawMutex, bool, 1> = Watch::new();

/// The last-applied activity profile (§353), `None` until one is ever chosen.
/// `main` seeds it from the persisted CFG1 record at boot, the `button` task
/// re-publishes on a menu selection, and the `ui` task renders it on the
/// menu's PROFILE row. One receiver (the `ui` task).
pub static PROFILE: Watch<CriticalSectionRawMutex, Option<ActivityProfile>, 1> = Watch::new();

/// Whether backyard-ultra mode is armed (§372). `main` seeds it from the
/// persisted CFG1 flag at boot and the `button` task re-publishes on a menu
/// edit; the `record` task applies it to the recorder, which is where it
/// re-points the auto-lap onto the corral bell. One receiver (`record`) — the
/// `ui` task reads the arm off the recorder snapshot the menu row already
/// carries, rather than a second copy that could disagree with it.
pub static BACKYARD: Watch<CriticalSectionRawMutex, bool, 1> = Watch::new();

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

/// The verdict on the last phone→watch push any transport resolved — the ONE
/// funnel all five latest-value pushes run through ([`note_push`]).
///
/// Every one of them keeps its PREVIOUS value when a push is refused: a bad
/// chunk, a failed CRC, an undecodable frame, or a settings queue with no
/// room. The `record` task mirrors this into the recorder snapshot so the
/// alert engine can edge-detect a refusal into its `! <KIND> FAIL` banner.
/// Before the funnel existed only `course` had a surface at all and the other
/// four left nothing but a defmt warn down a cable no runner carries, so a
/// runner ran a race against the settings, workout, schedule or screens they
/// believed they had replaced. One receiver (`record`).
pub static PUSH_OUTCOME: Watch<CriticalSectionRawMutex, PushOutcome, 1> = Watch::new();

/// The wrapping sequence [`note_push`] stamps. An atomic rather than a `Cell`
/// in either transport task, because BOTH the `ble` task and the sim's
/// `phone` task resolve pushes and a per-task counter would let one rewind
/// the other's — the alert engine reads a bare inequality, so a rewind is a
/// spurious banner.
static PUSH_SEQ: AtomicU8 = AtomicU8::new(0);

/// Record one resolved phone→watch push and publish it. Returns the outcome so
/// a transport that also serves it on the wire (the `ble` task's `push_status`
/// characteristic) publishes exactly what the wrist was told.
///
/// Called on ACCEPTANCE too: the phone reads the sequence to learn whether its
/// "sent" was true, and a counter that only moved on failure is
/// indistinguishable, from the phone, from a watch that never answered. The
/// wrist stays silent for an accepted push — that judgement is the alert
/// engine's, not this seam's.
pub fn note_push(kind: PushKind, accepted: bool) -> PushOutcome {
    let seq = PUSH_SEQ.fetch_add(1, Ordering::Relaxed).wrapping_add(1);
    let outcome = PushOutcome {
        seq,
        kind,
        accepted,
    };
    PUSH_OUTCOME.sender().send(outcome);
    outcome
}

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

/// Pushed roadbook + cut-off schedule (the `RBK1` path): the `ble` task decodes
/// a chunked phone write into a `roadbook_store` frame and publishes it here;
/// the `record` task loads both series into the recorder, which is what backs
/// the Roadbook, CutoffEta, Fuel and SleepStation pages and the virtual
/// partner's terrain schedule. `None` means nothing pushed yet, and an empty
/// schedule is an explicit clear — either way those pages read their honest
/// unfed states rather than a stale race's legs.
///
/// Latest-value like `WORKOUT` and unlike the `SETTINGS` deltas: one frame
/// carries the whole schedule, so a re-push replaces it outright and a
/// coalesced intermediate is not a lost edit. One receiver (`record`).
pub static ROADBOOK: Watch<CriticalSectionRawMutex, Option<PushedRoadbook>, 1> = Watch::new();

/// The runner's composed data screens (the `SCR1` path, §364): the `ble` task
/// decodes one unchunked phone write and publishes it here; the `record` task
/// persists it to the config page and the `ui` task draws whichever one the
/// page cycle has landed on. `None` means none composed — the 37 built-in pages
/// are the whole cycle, which is the honest starting state.
///
/// Latest-value like `WORKOUT` and unlike the `SETTINGS` deltas: one frame
/// carries the complete set, so a re-push replaces it outright and a coalesced
/// intermediate value is not a lost edit. Two receivers (`record`, `ui`).
pub static SCREENS: Watch<CriticalSectionRawMutex, Option<Screens>, 2> = Watch::new();

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

/// The barometric pressure tendency (§376): the `baro` task owns the tracker —
/// it is the only task holding both the raw pressure and the GPS altitude the
/// sea-level reduction needs — and publishes on a change worth waking for; the
/// `record` task folds it into the snapshot, which is what puts the Storm page
/// in the cycle and feeds the alert engine's storm arm. `None` is a barometer
/// that never answered. One receiver (the `record` task).
pub static STORM: Watch<CriticalSectionRawMutex, Option<StormView>, 1> = Watch::new();

/// The storm-alert threshold in hPa over the trend window: the `record` task
/// publishes it when a pushed settings frame arms the banner; the `baro` task
/// hands it to the tracker, whose setter owns the plausibility guard. Same
/// dedicated-watch seam as `SEA_LEVEL_PA` and for the same reason — the value
/// belongs to a task the settings frame does not otherwise touch. No value
/// published means the tracker keeps its default threshold. One receiver (the
/// `baro` task).
pub static STORM_THRESHOLD_HPA: Watch<CriticalSectionRawMutex, f32, 1> = Watch::new();

/// Local-time offset (minutes east of UTC) for the home clock: the `record`
/// task publishes the plausibility-guarded value when a pushed settings frame
/// carries `tz_offset_min` (the phone auto-sources it from its own zone —
/// same dedicated-watch seam as `SEA_LEVEL_PA`, so the `ui` task never
/// re-derives partial-frame apply semantics); the `ui` task shifts the home
/// clock hero and flips its row-7 label UTC → LOCAL. No value published means
/// the clock stays honestly UTC-labelled. One receiver (the `ui` task).
pub static TZ_OFFSET_MIN: Watch<CriticalSectionRawMutex, i16, 1> = Watch::new();

/// The ICE / medical-ID card a responder reads off the wrist (§358): the
/// `record` task publishes it from the flash record at boot and again on every
/// pushed settings frame that carries one; the `ui` task renders it as the
/// third idle face. `None` = no card, which that face says honestly rather
/// than showing empty rows. One receiver (the `ui` task).
pub static ICE: Watch<CriticalSectionRawMutex, Option<IceCard>, 1> = Watch::new();

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

/// How many finished runs on flash the phone has not pulled at all — the runs
/// a §378 factory erase would destroy with no copy existing anywhere else. The
/// `run_flash` store publishes it from the same seam as [`PENDING_RUNS`] (it is
/// the superset count: pending additionally requires an interrupted recording);
/// the `ui` task folds it into the armed erase prompt so the confirm names the
/// stake, and stays silent at zero. One receiver (the `ui` task).
pub static UNSYNCED_RUNS: Watch<CriticalSectionRawMutex, u8, 1> = Watch::new();

/// Outcome of the latest manual QNH re-zero, stamped with the uptime second it
/// was decided: the `baro` task publishes it (honest refusals included — no
/// fresh GPS, no barometer); the `ui` task shows it as a transient idle-face
/// banner. One receiver (the `ui` task).
pub static QNH_REZERO: Watch<CriticalSectionRawMutex, (RezeroStatus, u32), 1> = Watch::new();

/// Uptime second the wearer-armed §432 BLE pairing window closes at
/// (`pairing::WINDOW_CLOSED` = closed). An atomic rather than a `Watch`
/// because its consumer is the `ble` task's `SecurityHandler`, whose
/// callbacks run in the SoftDevice event context and can neither await nor
/// hold a receiver. The `button` task opens it from the menu's PAIR PHONE
/// row and closes it on a left press; the bonder closes it the moment a bond
/// forms; the deadline closes it by comparison. A reboot zeroes it —
/// fail-closed.
static PAIRING_WINDOW_UNTIL_S: AtomicU32 = AtomicU32::new(pairing::WINDOW_CLOSED);

pub fn open_pairing_window(now_s: u32) {
    PAIRING_WINDOW_UNTIL_S.store(pairing::window_deadline(now_s), Ordering::Relaxed);
}

pub fn close_pairing_window() {
    PAIRING_WINDOW_UNTIL_S.store(pairing::WINDOW_CLOSED, Ordering::Relaxed);
}

pub fn pairing_window_remaining_s(now_s: u32) -> Option<u32> {
    pairing::window_remaining_s(PAIRING_WINDOW_UNTIL_S.load(Ordering::Relaxed), now_s)
}

pub fn pairing_window_open(now_s: u32) -> bool {
    pairing_window_remaining_s(now_s).is_some()
}

/// Factory-erase generation. Bumped by the button task when the wearer
/// completes FACTORY ERASE (§ 378); the BLE security handler records the
/// generation each bond was formed under and treats an older one as absent
/// (`pairing::bond_is_live`).
///
/// An atomic for the same reason the pairing deadline is one: the SoftDevice's
/// security callbacks run in event context and can neither await nor hold a
/// `Watch` receiver, so the erase has to be legible to them without being
/// delivered to them. A `Channel` cannot serve this — it has one receiver, and
/// `record` already consumes it.
static BOND_ERASE_GEN: AtomicU32 = AtomicU32::new(0);

/// Read only by the `ble` build's security handler — the non-BLE build has no
/// keys to retire, but still bumps the counter so the two builds share one
/// erase path rather than a `cfg` at the call site.
#[cfg(feature = "ble")]
pub fn bond_erase_gen() -> u32 {
    BOND_ERASE_GEN.load(Ordering::Relaxed)
}

/// Invalidate the live bond. Wrapping is harmless and unreachable in practice:
/// the predicate compares for equality, and a wearer would have to complete
/// 2^32 guarded erases to alias one.
pub fn bump_bond_erase_gen() {
    BOND_ERASE_GEN.fetch_add(1, Ordering::Relaxed);
}

/// Report every `Watch`'s borrow state, for the panic handler.
///
/// Exists because of issue #713, whose panic — `RefCell already mutably
/// borrowed`, raised inside `embassy_sync::watch`'s generic code — names a
/// source line and nothing else. All 37 `Watch`es here monomorphise through
/// that same line, so the message cannot say WHICH one, and the two candidate
/// explanations need different evidence to tell apart: a genuine double borrow
/// leaves the flag holding a legitimate borrow count, while the corruption seen
/// in #754 would leave it holding something that was never a count.
///
/// Three words per `Watch`, not the whole struct. The first attempt dumped
/// every byte and **destroyed its own evidence**: 37 full structs overran the
/// defmt-rtt ring before Renode drained it, and only the last 5 lines survived
/// — including, fatally, the loss of the `panicked` line that
/// `sim/ci_smoke.py` scans for, which would have turned a panic back into the
/// misattributed failure § 582 exists to prevent.
///
/// Which three: `RefCell`'s borrow flag is `Cell<isize>` (align 4) beside a
/// `WatchState` carrying a `u64` (align 8), so the compiler is free to place
/// the value first and the flag after it. The first word covers the
/// flag-at-front layout, the last two cover flag-at-back with or without
/// trailing padding.
///
/// Read through raw pointers, never a `&Watch`: the whole point is to observe a
/// state the type system says cannot exist.
macro_rules! watch_dump {
    ($($w:ident),* $(,)?) => {
        pub fn dump_watches() {
            $(
                {
                    let p = core::ptr::addr_of!($w) as *const u32;
                    let words = core::mem::size_of_val(unsafe { &*core::ptr::addr_of!($w) }) / 4;
                    let first = unsafe { core::ptr::read_volatile(p) };
                    let back1 = unsafe { core::ptr::read_volatile(p.add(words - 1)) };
                    let back2 = unsafe { core::ptr::read_volatile(p.add(words - 2)) };
                    defmt::error!(
                        "panic: w {=str} @{=u32:#010x} n={=usize} {=u32:#010x} .. {=u32:#010x} {=u32:#010x}",
                        stringify!($w),
                        p as u32,
                        words,
                        first,
                        back2,
                        back1
                    );
                }
            )*
        }
    };
}

watch_dump!(
    FIX,
    HR,
    HR_SOURCE,
    HR_OPTICAL,
    HR_STRAP,
    RECORD,
    ELEVATION,
    ALERT,
    PAGE,
    IDLE_VIEW,
    PAGE_GRID,
    STOP_ARMED,
    SETTINGS_MENU,
    TIMER,
    TIMER_MENU,
    PROFILE,
    BACKYARD,
    NAV,
    COURSE,
    PUSH_OUTCOME,
    WORKOUT,
    ROADBOOK,
    SCREENS,
    ROUTE_PROFILE,
    TRACKBACK,
    GNSS_MODE,
    INTERACTION,
    SIGNAL,
    BATTERY,
    SEA_LEVEL_PA,
    STORM,
    STORM_THRESHOLD_HPA,
    TZ_OFFSET_MIN,
    ICE,
    PENDING_RUNS,
    UNSYNCED_RUNS,
    QNH_REZERO,
);
