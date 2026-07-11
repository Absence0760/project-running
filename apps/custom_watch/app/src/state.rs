//! Cross-task shared state.
//!
//! The seams between producers and consumers. Each `Watch` hands out at most
//! `N` receivers and returns `None` past that, so `N` tracks the live
//! subscriber count — bump it when a new consumer subscribes.

use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::channel::Channel;
use embassy_sync::watch::Watch;
use max86177::peak_detect::Reading as HrReading;
use watch_core::alerts::Alert;
use watch_core::button::RecordCommand;
use watch_core::elevation::Reading as ElevationReading;
use watch_core::face::NavView;
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::page::Page;
use watch_core::record::Snapshot;
use watch_core::trackback::TrackbackView;

/// Merged GPS fixes: `gps` publishes; `ui`, `phone`, `record`, and `nav`
/// subscribe.
pub static FIX: Watch<CriticalSectionRawMutex, Fix, 4> = Watch::new();

/// Latest heart-rate estimate: `hr` publishes; the `ui` face and `record`
/// (to stamp each stored track point's bpm) subscribe.
pub static HR: Watch<CriticalSectionRawMutex, HrReading, 2> = Watch::new();

/// Live recording totals: `record` publishes on change, the `ui` face, the
/// `button` task (for the state its toggle keys off), and the `gps` task (which
/// de-rates fix publication while no run is active) subscribe.
pub static RECORD: Watch<CriticalSectionRawMutex, Snapshot, 3> = Watch::new();

/// Recording control commands: the `button` task sends, `record` receives and
/// drives its state machine. A small buffer so a quick double-press (e.g.
/// pause then stop) is never dropped.
pub static RECORD_CMD: Channel<CriticalSectionRawMutex, RecordCommand, 4> = Channel::new();

/// Barometric elevation snapshot: `baro` publishes each sample; the `ui` face,
/// the `phone`/`ble` link, and `record` (to stamp each stored track point's
/// altitude) subscribe.
pub static ELEVATION: Watch<CriticalSectionRawMutex, ElevationReading, 3> = Watch::new();

/// The on-run alert currently on screen (`None` when the slot is clear):
/// `record` drives the `watch_core::alerts` engine and publishes on change;
/// the `ui` face draws the active alert as a 2x banner over the hero band.
/// One receiver (the `ui` task).
pub static ALERT: Watch<CriticalSectionRawMutex, Option<Alert>, 1> = Watch::new();

/// Current run-view page: the `button` task advances it on each BTN3 press, the
/// `ui` face reads it to pick the layout. One receiver (the `ui` task).
pub static PAGE: Watch<CriticalSectionRawMutex, Page, 1> = Watch::new();

/// Course-projection status for the Nav page: the `nav` task publishes per fix
/// (or once at boot when no course is loaded); the `ui` task renders it and
/// `record` reads the distance-along-course it feeds the recorder for the
/// cut-off ETA. Two receivers (`ui`, `record`).
pub static NAV: Watch<CriticalSectionRawMutex, NavView, 2> = Watch::new();

/// Back-to-start navigation view (breadcrumb + distance/bearing to start):
/// `record` publishes one per accepted fix — the same seam the flash track
/// store consumes, so the crumb mirrors the stored track exactly — and the
/// `ui` task renders it on the BackToStart page. One receiver (the `ui`).
pub static TRACKBACK: Watch<CriticalSectionRawMutex, TrackbackView, 1> = Watch::new();

/// Selected GNSS recording mode: the `button` task cycles it on an idle-face
/// BTN3 press; the `gps` task reads the fix-forwarding cadence, `record` the
/// interval its acceptance filter scales to, and the `ui` face the mode rows +
/// staleness budget. No value published means the default (Performance).
pub static GNSS_MODE: Watch<CriticalSectionRawMutex, GnssMode, 3> = Watch::new();

/// Uptime (seconds) of the last button press — any button. The `button` task
/// stamps it on every confirmed press; the `ui` task reads it to gate the
/// face's ~1 Hz animations to a short window after an interaction, so an idle
/// wrist stops paying the per-second animation redraw. One receiver (the `ui`).
pub static INTERACTION: Watch<CriticalSectionRawMutex, u32, 1> = Watch::new();
