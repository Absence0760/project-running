//! Watch-face layout: state in, text rows out.
//!
//! The face is a fixed grid of [`ROWS`] lines x [`COLS`] characters — the
//! 168x144 Sharp MIP divided by the 8x16 font cell. Producing plain rows
//! (rather than drawing) keeps layout pure and host-testable; the `app/`
//! ui task pushes each row through the `sharp_mip` text renderer and the
//! display driver only redraws lines whose content changed.
//!
//! Two layouts, chosen by whether a run is under way:
//!
//! - **Run dashboard** (recording / paused / finished) — the metrics a runner
//!   actually reads on the move: elapsed run time, distance, average + current
//!   pace, heart rate, altitude, and cumulative vert — the ultra headline
//!   pair — with a one-line GPS glance at the bottom. Raw position is
//!   deliberately absent: nobody reads lat/lon mid-ultra, and the fix still
//!   feeds the track, the flash store, and the phone link. Rows keep a fixed
//!   position with a `--` placeholder when a metric is not yet available, so a
//!   glance always finds a value in the same spot rather than a jumping grid.
//! - **Status face** (idle) — the bench / acquisition view: uptime clock, GPS
//!   status, last-known position, speed, altitude, HR, and vert. This is what
//!   shows before a run starts and while the first fix is being acquired.

use core::fmt::Write;

use crate::course::NavStatus;
use crate::cutoff_eta::CutoffEtaStatus;
use crate::elevation;
use crate::fitness::RecoveryAdvice;
use crate::fix::Fix;
use crate::gear_wear::GearWearStatus;
use crate::gnss_mode::GnssMode;
use crate::hr_zones::{self, ZoneCutoffs, ZONE_COUNT};
use crate::pacer::PaceVerdict;
use crate::page::Page;
use crate::race_predictor::{LadderRung, PredictionConfidence};
use crate::record::{RecordState, Snapshot};
use crate::roadbook::CutoffStatus;
use crate::trackback::{self, TrackbackView};

pub const COLS: usize = 21;
pub const ROWS: usize = 9;

/// A fix older than this (in seconds of uptime) renders as signal lost.
pub const STALE_AFTER_S: u32 = 5;

/// The staleness budget in force: while a run is active, fixes arrive at the
/// selected GNSS mode's cadence, so "stale" must mean *older than that
/// cadence* — a 40 s-old fix in Expedition mode is the chosen rhythm, not a
/// lost signal, and flagging it (or cycling the search arcs) would cry wolf
/// for the whole run. Idle publication is de-rated to just under
/// [`STALE_AFTER_S`] regardless of mode (see the gps task), so the idle face
/// keeps the tight budget and a genuinely lost signal still flags within
/// seconds. The mode's own interval keeps the usual slack on top.
pub fn stale_after_s(mode: GnssMode, run_active: bool) -> u32 {
    if run_active {
        mode.fix_interval_s() - 1 + STALE_AFTER_S
    } else {
        STALE_AFTER_S
    }
}

pub type Row = heapless::String<COLS>;

/// A display-agnostic icon slot the dashboard places in a row's left gutter.
/// `core` stays free of the `sharp_mip` crate (it must not know the panel), so
/// the app maps each variant onto the driver's own `Icon` when it blits — an
/// exhaustive match there catches any drift at compile time, the same way the
/// `COLS == TEXT_COLS` asserts pin the two grids together.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FaceIcon {
    Stopwatch,
    Footsteps,
    Heart,
    /// The small-heart frame of the ~1 Hz HR pulse; alternates with [`Heart`].
    HeartSmall,
    Mountain,
    Vert,
    Satellite,
    /// GPS-searching frames — arcs grow `SatSearch0` -> `SatSearch1` ->
    /// [`Satellite`] once per second while no fresh fix is locked.
    SatSearch0,
    SatSearch1,
}

/// What the Nav page has to work with — the app's nav task derives it per fix
/// from whether a course is loaded and whether the position projected onto it,
/// and publishes it as cross-task state. Layout content stays a pure function
/// of this, so every Nav state is host-tested.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum NavView {
    /// No course on the device (no `sim-course` build, no BLE push yet).
    NoCourse,
    /// A course is loaded but no position has projected onto it yet.
    NoFix,
    /// Live projection of the latest fix onto the course.
    Status(NavStatus),
}

/// The text row the app overlays at 2x over the Nav page's map panel while
/// the off-course alert is latched — the unmissable treatment. Steady, not
/// blinking: a lost ultra runner must never catch the blank frame.
pub fn nav_alert_row(nav: NavView) -> Option<Row> {
    match nav {
        NavView::Status(s) if s.alerting => {
            let mut row = Row::new();
            let _ = write!(row, "OFF COURSE");
            Some(row)
        }
        _ => None,
    }
}

/// Text row the 2x [`nav_alert_row`] overlay is anchored on (it spans this row
/// and the next) — mid-panel, so it sits over the breadcrumb.
pub const NAV_ALERT_ROW: usize = 3;

/// First text row of the Nav page's map panel; the panel spans
/// [`NAV_PANEL_ROWS`] rows from here. The app converts rows to pixels with the
/// panel's own cell height — `core` stays display-agnostic.
pub const NAV_PANEL_TOP_ROW: usize = 1;
pub const NAV_PANEL_ROWS: usize = 6;

// The panel must leave the info + GPS rows below it, and the 2x alert overlay
// (two rows tall) must land wholly inside the panel.
const _: () = assert!(NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS <= ROWS - 2);
const _: () = assert!(NAV_ALERT_ROW >= NAV_PANEL_TOP_ROW);
const _: () = assert!(NAV_ALERT_ROW + 2 <= NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS);

/// Whether the run view is showing — i.e. [`page_rows`] draws a run layout
/// rather than the idle status face. The app keys page-specific drawing (the
/// Nav page's map panel) off the same predicate the layout selection uses.
pub fn run_view(rec: Option<&Snapshot>) -> bool {
    rec.and_then(|snap| rec_tag(snap.state)).is_some()
}

fn rec_tag(state: RecordState) -> Option<&'static str> {
    match state {
        RecordState::Idle => None,
        RecordState::Recording => Some("REC"),
        RecordState::Paused => Some("PAU"),
        RecordState::Finished => Some("FIN"),
    }
}

/// Render the face. Rows are truncated at [`COLS`], never wrapped.
///
/// A run in progress (recording / paused / finished) draws the run dashboard;
/// otherwise the idle status face. `hr_bpm` is `None` until the peak detector
/// reports a stable pulse; `rec` is the live recording snapshot (its state
/// selects the layout); `elev` is the latest barometric reading (`None` until
/// the baro streams — the dashboard's ALT then falls back to the GPS fix and
/// VERT shows a placeholder); `mode` is the selected GNSS mode (it labels the
/// GPS rows, sets the idle face's MODE row, and stretches the staleness
/// budget to the mode's fix cadence while recording).
pub fn face_rows(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
) -> [Row; ROWS] {
    match rec.and_then(|snap| rec_tag(snap.state).map(|tag| (snap, tag))) {
        Some((snap, tag)) => dashboard(fix, hr_bpm, snap, tag, elev, uptime_s, true, mode),
        None => status_face(fix, hr_bpm, elev, uptime_s, mode),
    }
}

/// The icon that sits in each row's left gutter, paired 1:1 with [`face_rows`].
/// Only the run dashboard carries icons — the idle status face is all text, so
/// every slot is `None` there. The dashboard's icon rows leave their gutter (the
/// first five cells) blank so the blitted 16x16 glyph never collides with text.
///
/// Two gutter icons animate off `uptime_s` (so the choice stays a pure,
/// host-tested function of the inputs, not a hidden timer): the HR heart pulses
/// while a pulse is detected, and the GPS satellite cycles its search arcs while
/// no fresh fix is locked.
pub fn face_icons(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    uptime_s: u32,
    mode: GnssMode,
) -> [Option<FaceIcon>; ROWS] {
    dashboard_icons(fix, hr_bpm, rec, uptime_s, true, mode)
}

fn dashboard_icons(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Option<FaceIcon>; ROWS] {
    let mut icons = [None; ROWS];
    if rec.and_then(|snap| rec_tag(snap.state)).is_some() {
        // Rows 0-1 are the 2x time hero (no gutter icon). Row 2 down carry them.
        icons[2] = Some(FaceIcon::Footsteps);
        icons[5] = Some(heart_icon(hr_bpm, uptime_s, animate));
        icons[6] = Some(FaceIcon::Mountain);
        icons[7] = Some(FaceIcon::Vert);
        icons[8] = Some(gps_icon(fix, uptime_s, animate, stale_after_s(mode, true)));
    }
    icons
}

/// The elapsed run time for the dashboard's 2x hero band (rows 0-1), or `None`
/// when no run is under way (the idle status face has no hero). The app draws
/// this with the `sharp_mip` framebuffer's `draw_text_2x`; keeping the string
/// here keeps the hero's content host-tested alongside the rest of the face.
pub fn hero_line(rec: Option<&Snapshot>) -> Option<Row> {
    let snap = rec.filter(|snap| rec_tag(snap.state).is_some())?;
    let (h, m, s) = hms(snap.elapsed_s);
    let mut row = Row::new();
    let _ = write!(row, "{}:{:02}:{:02}", h.min(999), m, s);
    Some(row)
}

/// Page-aware entry point: the 1x rows for `page`. A run in progress draws the
/// selected page (the full dashboard or a single-metric glance); idle always
/// draws the status face regardless of page. `animate` gates the ~1 Hz REC
/// blink — off, the tag holds steady-on so it costs no per-second redraw. Pair
/// with [`page_icons`] + [`page_hero`]. The bare [`face_rows`] is the
/// always-animated `Dashboard`-page equivalent.
// One positional slot per live input signal, in the state.rs order — a pure
// render function of the whole watch state; grouping them into a struct would
// only move the same list one level down.
#[allow(clippy::too_many_arguments)]
pub fn page_rows(
    page: Page,
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    elev: Option<&elevation::Reading>,
    nav: NavView,
    tb: Option<&TrackbackView>,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    match rec.and_then(|snap| rec_tag(snap.state).map(|tag| (snap, tag))) {
        None => status_face(fix, hr_bpm, elev, uptime_s, mode),
        Some((snap, tag)) => match page {
            Page::Dashboard => dashboard(fix, hr_bpm, snap, tag, elev, uptime_s, animate, mode),
            Page::Distance => glance(
                GlanceMetric::Distance,
                fix,
                hr_bpm,
                snap,
                tag,
                uptime_s,
                animate,
                mode,
            ),
            Page::Pace => glance(
                GlanceMetric::Pace,
                fix,
                hr_bpm,
                snap,
                tag,
                uptime_s,
                animate,
                mode,
            ),
            Page::Lap => lap_glance(fix, hr_bpm, snap, tag, uptime_s, animate, mode),
            Page::Splits => splits_glance(fix, tag, uptime_s, animate, mode),
            Page::Zones => zones_glance(fix, hr_bpm, snap, tag, uptime_s, animate, mode),
            Page::Pacer => pacer_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RacePredictor => race_predictor_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::TrainingLoad => training_load_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::DistanceBand => distance_band_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::CutoffEta => cutoff_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Roadbook => roadbook_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Fuel => fuel_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Nav => nav_page(nav, fix, tag, uptime_s, animate, mode),
            Page::BackToStart => back_to_start_glance(fix, tb, tag, uptime_s, animate, mode),
            Page::GearWear => gear_wear_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::TrainingPaces => training_paces_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Fitness => fitness_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::ElevationProfile => {
                elevation_profile_glance(fix, snap, elev, tag, uptime_s, animate, mode)
            }
            Page::Recap => recap_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Streaks => streaks_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RunStats => run_stats_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::PrRecency => pr_recency_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::PlanReplan => plan_replan_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Readiness => readiness_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Goals => goals_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::TurnCue => turn_cue_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RouteSimplify => route_simplify_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::AutoEffort => auto_effort_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RouteElev => route_elev_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RaceDay => race_day_glance(fix, snap, tag, uptime_s, animate, mode),
        },
    }
}

/// Gutter icons for `page`. Only the dashboard carries them; the glance pages
/// are text + a single 2x hero, so every slot is `None`. `animate` gates the
/// heart pulse + GPS-search cycle (see [`dashboard_icons`]).
pub fn page_icons(
    page: Page,
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Option<FaceIcon>; ROWS] {
    match page {
        Page::Dashboard => dashboard_icons(fix, hr_bpm, rec, uptime_s, animate, mode),
        Page::Distance
        | Page::Pace
        | Page::Lap
        | Page::Splits
        | Page::Zones
        | Page::Pacer
        | Page::RacePredictor
        | Page::TrainingLoad
        | Page::DistanceBand
        | Page::CutoffEta
        | Page::Roadbook
        | Page::Fuel
        | Page::Nav
        | Page::BackToStart
        | Page::GearWear
        | Page::TrainingPaces
        | Page::Fitness
        | Page::ElevationProfile
        | Page::Recap
        | Page::Streaks
        | Page::RunStats
        | Page::PrRecency
        | Page::PlanReplan
        | Page::Readiness
        | Page::Goals
        | Page::TurnCue
        | Page::RouteSimplify
        | Page::AutoEffort
        | Page::RouteElev
        | Page::RaceDay => [None; ROWS],
    }
}

/// The 2x hero string for `page`: elapsed time on the dashboard, the page's
/// headline metric on a glance page (the live BPM on the zones page, `--`
/// without a pulse), or `None` when no run is under way. The Nav page never
/// has a hero — its map panel owns the rows the hero would cover.
pub fn page_hero(
    page: Page,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    tb: Option<&TrackbackView>,
) -> Option<Row> {
    let snap = rec.filter(|snap| rec_tag(snap.state).is_some())?;
    Some(match page {
        Page::Nav => return None,
        Page::Dashboard => {
            let (h, m, s) = hms(snap.elapsed_s);
            let mut row = Row::new();
            let _ = write!(row, "{}:{:02}:{:02}", h.min(999), m, s);
            row
        }
        Page::Distance => glance_hero(GlanceMetric::Distance, snap),
        Page::Pace => glance_hero(GlanceMetric::Pace, snap),
        Page::Lap => split_row(snap.lap_elapsed_s),
        Page::Zones => {
            let mut row = Row::new();
            match hr_bpm {
                Some(bpm) => {
                    let _ = write!(row, "{}", bpm.min(999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Pacer => match snap.pacer {
            Some(status) => signed_split(status.ahead_s),
            None => {
                let mut row = Row::new();
                let _ = write!(row, "--");
                row
            }
        },
        // The 10K projection is the headline rung (the anchor reference
        // distance, the most universally-read yardstick); the page's rows carry
        // the whole ladder.
        Page::RacePredictor => match &snap.race_prediction {
            Some(pred) => {
                let (h, m, s) = hms(pred.rungs[1].predicted_s as u32);
                let mut row = Row::new();
                if h > 0 {
                    let _ = write!(row, "{}:{:02}:{:02}", h.min(99), m, s);
                } else {
                    let _ = write!(row, "{}:{:02}", m, s);
                }
                row
            }
            None => {
                let mut row = Row::new();
                let _ = write!(row, "--");
                row
            }
        },
        // The margin to the next cut-off: `+` slack, `-` over. `--` when there
        // is no cut-off ahead or the projection is withheld (stale / no pace).
        Page::CutoffEta => match snap.cutoff.and_then(|c| c.margin_s) {
            Some(margin_s) => signed_split(margin_s),
            None => {
                let mut row = Row::new();
                let _ = write!(row, "--");
                row
            }
        },
        // The Splits + DistanceBand heroes both headline the run distance (the
        // number their rows contextualise); the analytics pages headline their
        // one derived value, `--` when inactive.
        Page::Splits => glance_hero(GlanceMetric::Distance, snap),
        Page::DistanceBand => glance_hero(GlanceMetric::Distance, snap),
        Page::TrainingLoad => {
            let mut row = Row::new();
            match snap.training_stress {
                Some(s) => {
                    let _ = write!(row, "{}", (s as u32).min(9999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Roadbook => {
            let mut row = Row::new();
            match snap.roadbook.filter(|rb| rb.upcoming_len > 0) {
                Some(rb) => {
                    let km = (rb.upcoming[0].cum_dist_m as f64 / 1000.0).min(999.99);
                    let _ = write!(row, "{:.2}", km);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Fuel => {
            let mut row = Row::new();
            match snap.fuel.and_then(|f| f.carry) {
                Some(c) => {
                    let _ = write!(row, "{}", (c.carbs_g as u32).min(9999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::GearWear => {
            let mut row = Row::new();
            match snap.gear.and_then(|g| g.fraction) {
                Some(fr) => {
                    let _ = write!(row, "{}", ((fr * 100.0) as u32).min(999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The easy pace — the day-to-day training pace runners glance at most —
        // rides the hero as `m:ss`; the page's rows carry the whole zone ladder.
        Page::TrainingPaces => {
            let mut row = Row::new();
            match snap.training_paces {
                Some(tp) => {
                    let s = tp.paces.easy as u32;
                    let _ = write!(row, "{}:{:02}", (s / 60).min(99), s % 60);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The synced VO2 max ceiling — the recognisable fitness number — is the
        // hero, `--` until the phone pushes a snapshot.
        Page::Fitness => {
            let mut row = Row::new();
            match snap.fitness.and_then(|f| f.vo2_max) {
                Some(v) => {
                    let _ = write!(row, "{}", (v as u32).min(999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The current altitude (the run's latest banked sample) headlines the
        // profile; `--` until the first altitude sample lands.
        Page::ElevationProfile => {
            let mut row = Row::new();
            let ep = &snap.elev_profile;
            if ep.len > 0 {
                let _ = write!(row, "{}", ep.samples[ep.len - 1].clamp(-99_999, 99_999));
            } else {
                let _ = write!(row, "--");
            }
            row
        }
        Page::BackToStart => {
            let mut row = Row::new();
            match trackback_distance(tb) {
                Some(d) if d < 1000.0 => {
                    let _ = write!(row, "{:.0}", d);
                }
                Some(d) => {
                    let _ = write!(row, "{:.2}", (d / 1000.0).min(9999.99));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The twelve 2026-07-11 synced-summary pages are rows-only (no 2x hero):
        // each headlines its number in the rows, like the Nav page.
        Page::Recap
        | Page::Streaks
        | Page::RunStats
        | Page::PrRecency
        | Page::PlanReplan
        | Page::Readiness
        | Page::Goals
        | Page::TurnCue
        | Page::RouteSimplify
        | Page::AutoEffort
        | Page::RouteElev
        | Page::RaceDay => return None,
    })
}

/// The back-to-start distance, or `None` before the run has a start anchor.
fn trackback_distance(tb: Option<&TrackbackView>) -> Option<f32> {
    tb.filter(|n| n.active()).map(|n| n.distance_to_start_m)
}

#[derive(Clone, Copy)]
enum GlanceMetric {
    Distance,
    Pace,
}

/// A single-metric glance page: the metric up large in the rows-0-2 3x hero
/// (drawn by the app from [`page_hero`]), a unit label on row 3, then time /
/// the other metric / HR / GPS as 1x context — the "one big number" view for a
/// mid-run glance. The pace glance adds the live grade-adjusted pace under HR,
/// so raw and effort-equivalent pace read together on a hill.
#[allow(clippy::too_many_arguments)]
fn glance(
    metric: GlanceMetric,
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-2 hold the 3x hero (the app draws the single-metric pages' headline
    // number triple-size — the glance a runner takes at arm's length); only the
    // state tag rides row 0's right cells, clear of the hero digits, blinking for
    // REC while `animate` is on and steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    let label = match metric {
        GlanceMetric::Distance => "DISTANCE  KM",
        GlanceMetric::Pace => "AVG PACE  /KM",
    };
    let _ = write!(rows[3], "{}", label);

    let (h, m, s) = hms(snap.elapsed_s);
    let _ = write!(rows[4], "{:<5}{}:{:02}:{:02}", "TIME", h.min(999), m, s);

    // The metric NOT already up large fills the secondary line.
    match metric {
        GlanceMetric::Distance => write_pace(&mut rows[5], "PACE", snap.avg_pace_s_per_km),
        GlanceMetric::Pace => {
            let km = (snap.distance_m / 1000.0).min(9999.99);
            let _ = write!(rows[5], "{:<5}{:.2} KM", "DIST", km);
        }
    }

    write_hr(&mut rows[6], "HR", hr_bpm, &snap.zone_cutoffs);

    // The pace glance pairs the average-pace hero with the live grade-adjusted
    // pace, so raw and effort-equivalent read side by side on a hill.
    if matches!(metric, GlanceMetric::Pace) {
        write_pace(&mut rows[7], "GAP", snap.gap_s_per_km);
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The big headline value for a glance page's hero (no unit — the label row
/// carries it): distance to two decimals, or `M:SS` average pace / `--:--`.
fn glance_hero(metric: GlanceMetric, snap: &Snapshot) -> Row {
    let mut row = Row::new();
    match metric {
        GlanceMetric::Distance => {
            let km = (snap.distance_m / 1000.0).min(9999.99);
            let _ = write!(row, "{:.2}", km);
        }
        GlanceMetric::Pace => match snap.avg_pace_s_per_km {
            Some(p) => {
                let _ = write!(row, "{}:{:02}", (p / 60).min(99), p % 60);
            }
            None => {
                let _ = write!(row, "--:--");
            }
        },
    }
    row
}

/// The lap glance page: the current lap's running time up large in the rows-0-1
/// hero (drawn by the app from [`page_hero`] via [`split_row`]), the lap number
/// as the label, then last-lap split / lap distance / HR / GPS as 1x context —
/// what a runner checks right after pressing Lap (or hearing the 1 km auto-lap
/// tick over): which lap am I on, and what did the last one take.
#[allow(clippy::too_many_arguments)]
fn lap_glance(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    let _ = write!(rows[2], "LAP {}", snap.lap.min(9999));

    match snap.last_lap {
        Some(lap) => {
            let _ = write!(
                rows[4],
                "{:<5}{}",
                "LAST",
                split_row(lap.elapsed_s).as_str()
            );
        }
        None => {
            let _ = write!(rows[4], "{:<5}--", "LAST");
        }
    }

    let km = (snap.lap_distance_m / 1000.0).min(9999.99);
    let _ = write!(rows[5], "{:<5}{:.2} KM", "DIST", km);

    write_hr(&mut rows[6], "HR", hr_bpm, &snap.zone_cutoffs);

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The zone rows sit on rows 3..=7 under the label; they must fit above the
/// GPS row.
const _: () = assert!(3 + ZONE_COUNT < ROWS);

/// The HR/zones glance page: the live BPM up large in the rows-0-1 hero (drawn
/// by the app from [`page_hero`]), the current zone beside the label, then one
/// row per zone — the moving time banked in that zone plus a bar scaled to the
/// fullest zone — and the GPS glance. Zone time accrues exactly where moving
/// time does (see `Recorder`), so a paused / auto-paused / pulse-less stretch
/// banks nothing and the rows read as "where has this run's effort gone".
#[allow(clippy::too_many_arguments)]
fn zones_glance(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match hr_bpm {
        Some(bpm) => {
            let zone = hr_zones::zone_for_bpm(bpm, &snap.zone_cutoffs);
            let _ = write!(rows[2], "{:<14}ZONE {}", "HR  BPM", zone);
        }
        None => {
            let _ = write!(rows[2], "{:<14}ZONE --", "HR  BPM");
        }
    }

    // Per-zone moving-time label; the app draws the scaled bar beside it into
    // the trailing cells this leaves blank (`render::widgets::draw_zones_overlay`)
    // — a smooth pixel bar in place of the `#` glyphs, and a frame on the live
    // zone. The `{:<9}` pads the time so the bar always starts in the same column.
    for (i, &t) in snap.zone_time_s.iter().enumerate() {
        let _ = write!(rows[3 + i], "Z{} {:<9}", i + 1, split_row(t).as_str());
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The pacer glance page: the virtual-partner delta up large in the rows-0-1
/// hero (drawn by the app from [`page_hero`] via [`signed_split`] — `+` is
/// AHEAD of the partner, `-` is BEHIND, and the verdict word beside the label
/// spells the sign out so it is never ambiguous), then the goal distance +
/// target time, the projected finish at the current whole-run average (the
/// actual crossing time once finished), the distance delta in metres, and the
/// GPS glance. With no goal configured the page is honestly inactive —
/// `PACER --` and a how-to-set hint, never zeros pretending to be on pace.
#[allow(clippy::too_many_arguments)]
fn pacer_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.pacer {
        None => {
            let _ = write!(rows[2], "PACER --");
            let _ = write!(rows[4], "NO GOAL SET");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(status) => {
            let verdict = match status.verdict {
                PaceVerdict::Ahead => "AHEAD",
                PaceVerdict::OnPace => "ON PACE",
                PaceVerdict::Behind => "BEHIND",
            };
            let _ = write!(rows[2], "{:<14}{}", "PACER", verdict);

            let goal_km = (status.goal.distance_m as f64 / 1000.0).min(9999.99);
            let _ = write!(rows[4], "{:<5}{:.2} KM", "GOAL", goal_km);
            let _ = write!(
                rows[5],
                "{:<5}{}",
                "TGT",
                split_row(status.goal.time_s).as_str()
            );

            match status.projected_finish_s {
                Some(finish_s) => {
                    let _ = write!(rows[6], "{:<5}{}", "PROJ", split_row(finish_s).as_str());
                }
                None => {
                    let _ = write!(rows[6], "{:<5}--", "PROJ");
                }
            }

            let delta_m = status.ahead_m as i64;
            let clamped = delta_m.clamp(-99_999, 99_999);
            let sign = if clamped < 0 { '-' } else { '+' };
            let _ = write!(rows[7], "{:<5}{}{} M", "DIST", sign, clamped.unsigned_abs());
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// One ladder row: the distance label, the projected finish (H:MM:SS past an
/// hour, else M:SS), and a one-glyph confidence flag — ` ` solid, `?` moderate,
/// `~` low — so a runner reads at a glance how much to trust each rung.
fn pred_row(row: &mut Row, label: &str, rung: &LadderRung) {
    let flag = match rung.quality.confidence {
        PredictionConfidence::High => ' ',
        PredictionConfidence::Moderate => '?',
        PredictionConfidence::Low => '~',
    };
    let (h, m, s) = hms(rung.predicted_s as u32);
    if h > 0 {
        let _ = write!(row, "{:<5}{}:{:02}:{:02} {}", label, h.min(99), m, s, flag);
    } else {
        let _ = write!(row, "{:<5}{}:{:02} {}", label, m, s, flag);
    }
}

/// The race-predictor glance page: the 10K projection up large in the rows-0-1
/// hero (drawn by [`page_hero`]), then the whole 5K / 10K / Half / Marathon
/// ladder as rows — each with a confidence flag — under the run distance the
/// projection is based on. Honestly blank ("NEED 1 KM") until the run clears
/// [`crate::record::MIN_PREDICT_DISTANCE_M`]: no fabricated race time off a
/// warm-up.
#[allow(clippy::too_many_arguments)]
fn race_predictor_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match &snap.race_prediction {
        None => {
            let _ = write!(rows[2], "PREDICT --");
            let _ = write!(rows[4], "NEED 1 KM");
        }
        Some(pred) => {
            let from_km = (pred.anchor.distance_m / 1000.0).min(9999.99);
            let _ = write!(rows[2], "{:<9}{:.2} KM", "FROM", from_km);
            const LABELS: [&str; 4] = ["5K", "10K", "HALF", "MAR"];
            for (i, rung) in pred.rungs.iter().enumerate() {
                pred_row(&mut rows[3 + i], LABELS[i], rung);
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The cut-off ETA glance page: the margin to the next cut-off up large in the
/// rows-0-1 hero (drawn by [`page_hero`] via [`signed_split`] — `+` slack, `-`
/// over the limit), then the verdict word, the distance to the cut-off, and the
/// projected arrival clock. Honest inactive states: "NO CUTOFFS" when the
/// course carries none, "NO CUTOFF AHEAD" once past the last one, and a `--`
/// ETA when the fix is too stale (or the pace too uncertain) to project.
#[allow(clippy::too_many_arguments)]
fn cutoff_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.cutoff {
        None => {
            let _ = write!(rows[2], "CUTOFF --");
            let _ = write!(rows[4], "NO CUTOFFS");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(eta) if !eta.has_cutoff => {
            let _ = write!(rows[2], "CUTOFF --");
            let _ = write!(rows[4], "NO CUTOFF AHEAD");
        }
        Some(eta) => {
            let verdict = match eta.status {
                CutoffEtaStatus::On => "ON",
                CutoffEtaStatus::Tight => "TIGHT",
                CutoffEtaStatus::Behind => "BEHIND",
                CutoffEtaStatus::Unknown => "--",
            };
            let _ = write!(rows[2], "{:<14}{}", "CUTOFF", verdict);

            if eta.distance_to_m < 1000.0 {
                let _ = write!(rows[4], "{:<5}{:.0} M", "TO", eta.distance_to_m.max(0.0));
            } else {
                let km = (eta.distance_to_m / 1000.0).min(9999.99);
                let _ = write!(rows[4], "{:<5}{:.2} KM", "TO", km);
            }

            match eta.projected_arrival_elapsed_s {
                Some(arrival_s) => {
                    let (h, m, s) = hms(arrival_s);
                    let _ = write!(rows[5], "{:<5}{}:{:02}:{:02}", "ETA", h.min(999), m, s);
                }
                None => {
                    let _ = write!(rows[5], "{:<5}--", "ETA");
                }
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The splits glance: the pace-distribution histogram — distance banked in
/// each pace bucket (slowest .. fastest, from [`crate::pace_segments`]) drawn
/// by the app as bottom-aligned pixel bars over rows 3..8, with an axis label
/// on row 2 and the total distance up in the hero.
fn splits_glance(
    fix: Option<&Fix>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    // The pace-distribution histogram fills rows 3..8 as pixel bars the app
    // draws (`render::widgets::draw_splits_overlay`, slowest bucket left →
    // fastest right); this labels the axis and leaves those rows blank for it.
    let _ = write!(rows[2], "PACE DIST  SLOW>FAST");

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The training-load glance: this run's single-run stress up large in the hero
/// (drawn by [`page_hero`]), with the distance + moving time it is derived
/// from. The rolling CTL/ATL/TSB needs multi-day history the watch doesn't
/// hold, so it reads an honest "ROLLING: SYNC" rather than a fabricated trend.
/// "LOAD --" until the run accrues distance.
#[allow(clippy::too_many_arguments)]
fn training_load_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.training_stress {
        None => {
            let _ = write!(rows[2], "LOAD --");
            let _ = write!(rows[4], "NEED DISTANCE");
        }
        Some(_) => {
            let _ = write!(rows[2], "LOAD  POINTS");
            let km = (snap.distance_m / 1000.0).min(9999.99);
            let _ = write!(rows[4], "{:<7}{:.2} KM", "DIST", km);
            let (h, m, s) = hms(snap.moving_s);
            let _ = write!(rows[5], "{:<7}{}:{:02}:{:02}", "MOVING", h.min(999), m, s);
            let _ = write!(rows[6], "{:<7}SYNC", "ROLLING");
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The distance-band glance: the run distance up large in the hero, the race
/// band it falls in as the label, and the band's window. "NO RACE BAND" in a
/// gap between bands (a 15 km run matches nothing).
#[allow(clippy::too_many_arguments)]
fn distance_band_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    let km = (snap.distance_m / 1000.0).min(9999.99);
    match snap.band {
        None => {
            let _ = write!(rows[2], "BAND --");
            let _ = write!(rows[4], "NO RACE BAND");
            let _ = write!(rows[5], "{:<6}{:.2} KM", "DIST", km);
        }
        Some(b) => {
            let _ = write!(rows[2], "{:<11}{}", "BAND", b.label);
            let lo = (b.min_m / 1000.0) as u32;
            match b.max_m {
                Some(max) => {
                    let _ = write!(rows[4], "{:<6}{}-{} KM", "RANGE", lo, (max / 1000.0) as u32);
                }
                None => {
                    let _ = write!(rows[4], "{:<6}{}+ KM", "RANGE", lo);
                }
            }
            let _ = write!(rows[5], "{:<6}{:.2} KM", "DIST", km);
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// A one-glyph cutoff flag for a roadbook row: ` ` safe, `!` tight, `X` miss,
/// `.` no cutoff on that checkpoint.
fn cutoff_flag(status: Option<CutoffStatus>) -> char {
    match status {
        Some(CutoffStatus::Safe) => ' ',
        Some(CutoffStatus::Tight) => '!',
        Some(CutoffStatus::Miss) => 'X',
        None => '.',
    }
}

/// The roadbook glance: the total checkpoint count beside the label, then the
/// next few checkpoints ahead of the current position — each its distance,
/// projected arrival clock, and safe/tight/miss cutoff flag. The next
/// checkpoint's distance rides the hero. "NO ROADBOOK" when none is loaded.
#[allow(clippy::too_many_arguments)]
fn roadbook_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match &snap.roadbook {
        None => {
            let _ = write!(rows[2], "ROADBOOK --");
            let _ = write!(rows[4], "NO ROADBOOK");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(rb) => {
            let _ = write!(rows[2], "{:<11}{} CP", "ROADBOOK", rb.total.min(99));
            for i in 0..(rb.upcoming_len as usize).min(rb.upcoming.len()) {
                let leg = rb.upcoming[i];
                let km = (leg.cum_dist_m as f64 / 1000.0).min(999.99);
                let (h, m, s) = hms(leg.projected_elapsed_s);
                let _ = write!(
                    rows[3 + i],
                    "{:>6.2}K {}:{:02}:{:02} {}",
                    km,
                    h.min(99),
                    m,
                    s,
                    cutoff_flag(leg.cutoff)
                );
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The fuel glance: the carbs to carry to the next aid up large in the hero,
/// with the fluid to carry and the whole-plan totals. "NO FUEL PLAN" without a
/// roadbook; "LAST AID PASSED" once past the final refill.
#[allow(clippy::too_many_arguments)]
fn fuel_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match &snap.fuel {
        None => {
            let _ = write!(rows[2], "FUEL --");
            let _ = write!(rows[4], "NO FUEL PLAN");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(f) => {
            let _ = write!(rows[2], "FUEL  TO NEXT AID");
            match f.carry {
                Some(c) => {
                    let _ = write!(rows[4], "{:<7}{} G", "CARB", (c.carbs_g as u32).min(9999));
                    let _ = write!(rows[5], "{:<7}{} ML", "FLUID", (c.fluid_ml as u32));
                }
                None => {
                    let _ = write!(rows[4], "{:<7}--", "CARB");
                    let _ = write!(rows[5], "LAST AID PASSED");
                }
            }
            let _ = write!(
                rows[6],
                "{:<7}{}G {}ML",
                "TOTAL",
                (f.total_carbs_g as u32).min(9999),
                (f.total_fluid_ml as u32)
            );
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The gear-wear glance: the active shoe's wear percent up large in the hero,
/// the OK/DUE/WORN verdict beside the label, and the accumulated distance vs
/// its target. "NO GEAR SYNCED" when no gear is configured.
#[allow(clippy::too_many_arguments)]
fn gear_wear_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.gear {
        None => {
            let _ = write!(rows[2], "GEAR --");
            let _ = write!(rows[4], "NO GEAR SYNCED");
        }
        Some(g) => {
            let word = match g.status {
                GearWearStatus::Untracked => "UNTRACKED",
                GearWearStatus::Ok => "OK",
                GearWearStatus::Due => "DUE",
                GearWearStatus::Worn => "WORN",
            };
            let _ = write!(rows[2], "{:<11}{}", "GEAR", word);
            match g.fraction {
                Some(fr) => {
                    let _ = write!(rows[4], "{:<6}{} %", "WEAR", ((fr * 100.0) as u32).min(999));
                }
                None => {
                    let _ = write!(rows[4], "{:<6}--", "WEAR");
                }
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// Write a `M:SS /KM` training-zone pace onto a row behind `label` (padded to a
/// six-cell gutter so five-letter zone labels still clear the value). Minutes
/// clamp to 99 so a very slow easy pace can't overflow the grid.
fn write_zone_pace(row: &mut Row, label: &str, pace_s_per_km: u32) {
    let (m, s) = ((pace_s_per_km / 60).min(99), pace_s_per_km % 60);
    let _ = write!(row, "{:<6}{}:{:02} /KM", label, m, s);
}

/// The training-paces glance: the five Daniels intensity-zone paces derived from
/// the synced goal-race pace — easy / marathon / tempo / interval / repetition,
/// one per row with the source goal on the header. The easy pace rides the hero.
/// "PACES --" / "NO GOAL SET" until a goal pace is synced.
#[allow(clippy::too_many_arguments)]
fn training_paces_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.training_paces {
        None => {
            let _ = write!(rows[2], "PACES --");
            let _ = write!(rows[4], "NO GOAL SET");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(tp) => {
            let (gm, gs) = (
                (tp.goal_pace_s_per_km / 60).min(99),
                tp.goal_pace_s_per_km % 60,
            );
            let _ = write!(rows[2], "{:<7}GOAL {}:{:02}", "PACES", gm, gs);
            write_zone_pace(&mut rows[3], "EASY", tp.paces.easy as u32);
            write_zone_pace(&mut rows[4], "MARA", tp.paces.marathon as u32);
            write_zone_pace(&mut rows[5], "TEMPO", tp.paces.tempo as u32);
            write_zone_pace(&mut rows[6], "INTVL", tp.paces.interval as u32);
            write_zone_pace(&mut rows[7], "REP", tp.paces.repetition as u32);
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// A short all-caps word for a [`RecoveryAdvice`] verdict — the presentation
/// wording the pure core deliberately leaves to the display layer.
fn recovery_word(advice: RecoveryAdvice) -> &'static str {
    match advice {
        RecoveryAdvice::NotEnoughData => "NO DATA",
        RecoveryAdvice::ReturningFromLayoff => "LAYOFF",
        RecoveryAdvice::HeavilyLoaded => "REST",
        RecoveryAdvice::StillBuilding => "BUILD",
        RecoveryAdvice::LoadedBuildTerritory => "EASY",
        RecoveryAdvice::SweetSpot => "SWEET",
        RecoveryAdvice::Tapering => "TAPER",
        RecoveryAdvice::VeryFresh => "FRESH",
    }
}

/// The fitness glance: the synced VO2 max ceiling up large in the hero, with the
/// recovery-advice verdict beside the label and the VO2 number on its own row.
/// Only what a single synced snapshot honestly holds — the rolling CTL/ATL/TSB
/// needs multi-day history the watch doesn't keep, so it is deliberately absent.
/// "FITNESS --" / "NOT SYNCED" until the phone pushes a snapshot.
#[allow(clippy::too_many_arguments)]
fn fitness_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match snap.fitness {
        None => {
            let _ = write!(rows[2], "FITNESS --");
            let _ = write!(rows[4], "NOT SYNCED");
            let _ = write!(rows[5], "SET VIA PHONE SYNC");
        }
        Some(f) => {
            let word = f.recovery.map(recovery_word).unwrap_or("--");
            let _ = write!(rows[2], "{:<11}{}", "FITNESS", word);
            match f.vo2_max {
                Some(v) => {
                    let _ = write!(rows[4], "{:<9}{}", "VO2 MAX", (v as u32).min(999));
                }
                None => {
                    let _ = write!(rows[4], "{:<9}--", "VO2 MAX");
                }
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// The elevation-profile glance: the run's decimated elevation series drawn as
/// a mini-profile sparkline the app paints (`render::widgets::draw_mini_profile`)
/// into rows 3..8, with the total ascent / descent from the baro task's
/// [`elevation::Reading`] as the context row and the current altitude on the
/// hero. "ELEV --" / "NO ELEVATION" until the first altitude sample lands, so a
/// baro-less (or pre-fix) run reads honestly rather than as a flat sea-level
/// line. The vert totals come from the authoritative accumulator, not the lossy
/// decimated series, so a between-samples peak is never dropped from D+.
#[allow(clippy::too_many_arguments)]
fn elevation_profile_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    elev: Option<&elevation::Reading>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    if snap.elev_profile.len == 0 {
        let _ = write!(rows[2], "ELEV --");
        let _ = write!(rows[4], "NO ELEVATION");
        let _ = write!(rows[5], "AWAITING BARO");
    } else {
        // rows 3..8 are the sparkline cell the app draws into.
        match elev {
            Some(e) => {
                let _ = write!(
                    rows[2],
                    "ELEV D+{} D-{}",
                    (e.gain_m as u32).min(99_999),
                    (e.loss_m as u32).min(99_999)
                );
            }
            None => {
                let _ = write!(rows[2], "ELEV PROFILE");
            }
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// Write the common tag row (row 0) and GPS row (row 8) shared by every
/// synced-summary glance, blinking the REC tag with the animation window.
fn summary_frame(
    rows: &mut [Row; ROWS],
    fix: Option<&Fix>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) {
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }
    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
}

/// The Recap glance: the synced Year/Month-in-Running totals. "RECAP --" /
/// "NOT SYNCED" until the phone pushes a summary.
#[allow(clippy::too_many_arguments)]
fn recap_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.recap {
        None => {
            let _ = write!(rows[2], "RECAP --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "{:<7}{} RUNS", "RECAP", v.runs.min(9999));
            let _ = write!(rows[4], "{:<7}{} KM", "DIST", v.distance_km);
            let _ = write!(rows[5], "{:<7}{} KM", "LONGEST", v.longest_km.min(9999));
            let _ = write!(rows[6], "{:<7}{}D", "STREAK", v.best_streak_days.min(9999));
        }
    }
    rows
}

/// The Streaks glance: current + best run-streak day counts.
#[allow(clippy::too_many_arguments)]
fn streaks_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.streaks {
        None => {
            let _ = write!(rows[2], "STREAK --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "{:<7}{}D", "CURRENT", v.current_days.min(9999));
            let _ = write!(rows[4], "{:<7}{}D", "BEST", v.best_days.min(9999));
        }
    }
    rows
}

/// The RunStats glance: a synced moving-time / gain / split-count summary.
#[allow(clippy::too_many_arguments)]
fn run_stats_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.run_stats {
        None => {
            let _ = write!(rows[2], "STATS --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let (h, m, s) = hms(v.moving_s);
            let _ = write!(rows[2], "{:<7}{}:{:02}:{:02}", "MOVING", h.min(999), m, s);
            let _ = write!(rows[4], "{:<7}{} M", "GAIN", v.gain_m);
            let _ = write!(rows[5], "{:<7}{}", "SPLITS", v.splits.min(9999));
        }
    }
    rows
}

/// The PrRecency glance: how long ago the current PR was set, bucketed into
/// today / days / weeks / months / years.
#[allow(clippy::too_many_arguments)]
fn pr_recency_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.pr_recency {
        None => {
            let _ = write!(rows[2], "PR AGE --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "PR AGE");
            let d = v.days_ago;
            if d == 0 {
                let _ = write!(rows[4], "TODAY");
            } else if d < 7 {
                let _ = write!(rows[4], "{} DAYS", d);
            } else if d < 31 {
                let _ = write!(rows[4], "{} WEEKS", d / 7);
            } else if d < 365 {
                let _ = write!(rows[4], "{} MONTHS", d / 30);
            } else {
                let _ = write!(rows[4], "{} YEARS", d / 365);
            }
        }
    }
    rows
}

/// The PlanReplan glance: the re-plan proposal counts (total / make-ups /
/// ease-offs).
#[allow(clippy::too_many_arguments)]
fn plan_replan_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.plan_replan {
        None => {
            let _ = write!(rows[2], "REPLAN --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "{:<8}{}", "REPLAN", v.changes);
            let _ = write!(rows[4], "{:<8}{}", "MAKE-UP", v.make_ups);
            let _ = write!(rows[5], "{:<8}{}", "EASE-OFF", v.ease_offs);
        }
    }
    rows
}

/// The Readiness glance: the training-readiness score + its band.
#[allow(clippy::too_many_arguments)]
fn readiness_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.readiness {
        None => {
            let _ = write!(rows[2], "READY --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let band = match v.band {
                0 => "LOW",
                1 => "MODERATE",
                _ => "HIGH",
            };
            let _ = write!(rows[2], "{:<7}{}", "READY", v.score.min(100));
            let _ = write!(rows[4], "{}", band);
        }
    }
    rows
}

/// The Goals glance: the primary goal's ring percent + complete flag.
#[allow(clippy::too_many_arguments)]
fn goals_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.goals {
        None => {
            let _ = write!(rows[2], "GOAL --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "{:<7}{}%", "GOAL", v.percent.min(100));
            let _ = write!(
                rows[4],
                "{}",
                if v.complete {
                    "COMPLETE"
                } else {
                    "IN PROGRESS"
                }
            );
        }
    }
    rows
}

/// The TurnCue glance: the next turn on the loaded course — direction, distance
/// to it, and how many cues remain. "NO COURSE" until one is synced.
#[allow(clippy::too_many_arguments)]
fn turn_cue_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.turn_cue {
        None => {
            let _ = write!(rows[2], "TURN --");
            let _ = write!(rows[4], "NO COURSE");
        }
        Some(v) => {
            let dir = match v.direction {
                0 => "STRAIGHT",
                1 => "SLIGHT L",
                2 => "LEFT",
                3 => "SHARP L",
                4 => "SLIGHT R",
                5 => "RIGHT",
                6 => "SHARP R",
                _ => "U-TURN",
            };
            let _ = write!(rows[2], "{:<7}{}", "TURN", dir);
            let _ = write!(rows[4], "{:<7}{} M", "IN", v.distance_m);
            let _ = write!(rows[5], "{:<7}{}", "REMAIN", v.remaining);
        }
    }
    rows
}

/// The RouteSimplify glance: the simplified-course point count + length.
#[allow(clippy::too_many_arguments)]
fn route_simplify_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.route_simplify {
        None => {
            let _ = write!(rows[2], "COURSE --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "{:<7}{} PTS", "COURSE", v.points);
            let _ = write!(rows[4], "{:<7}{} KM", "LENGTH", v.distance_km);
        }
    }
    rows
}

/// The AutoEffort glance: how many considered segments matched the run.
#[allow(clippy::too_many_arguments)]
fn auto_effort_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.auto_effort {
        None => {
            let _ = write!(rows[2], "SEGMENTS --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "SEGMENTS");
            let _ = write!(rows[4], "{:<7}{}/{}", "MATCH", v.matched, v.considered);
        }
    }
    rows
}

/// The RouteElev glance: the loaded course's total gain / loss + point count.
#[allow(clippy::too_many_arguments)]
fn route_elev_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.route_elev {
        None => {
            let _ = write!(rows[2], "CRS ELEV --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let _ = write!(rows[2], "CRS ELEV");
            let _ = write!(rows[4], "{:<7}{} M", "GAIN", v.gain_m);
            let _ = write!(rows[5], "{:<7}{} M", "LOSS", v.loss_m);
            let _ = write!(rows[6], "{:<7}{}", "PTS", v.points);
        }
    }
    rows
}

/// The RaceDay glance: the countdown to the race + the goal-feasibility verdict.
#[allow(clippy::too_many_arguments)]
fn race_day_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.race_day {
        None => {
            let _ = write!(rows[2], "RACE --");
            let _ = write!(rows[4], "NOT SYNCED");
        }
        Some(v) => {
            let d = v.days_until;
            let _ = write!(rows[2], "RACE DAY");
            if d > 0 {
                let _ = write!(rows[4], "IN {} DAYS", d.min(9999));
            } else if d == 0 {
                let _ = write!(rows[4], "TODAY");
            } else {
                let _ = write!(rows[4], "{} DAYS AGO", (-d).min(9999));
            }
            let feas = match v.feasible {
                0 => "BEHIND",
                1 => "ON TRACK",
                _ => "AHEAD",
            };
            let _ = write!(rows[5], "{}", feas);
        }
    }
    rows
}

/// The Nav page: the breadcrumb map panel on rows [`NAV_PANEL_TOP_ROW`]..+
/// [`NAV_PANEL_ROWS`] (left empty here — the app draws the course polyline +
/// position marker into those pixels, and the 2x [`nav_alert_row`] overlay on
/// top while the off-course alert is latched), with distance-along-course and
/// the perpendicular offset on the info row and the GPS glance at the bottom.
/// Without a course (or before the first projected fix) the info row says why,
/// so the page never reads as a silently-empty map.
#[allow(clippy::too_many_arguments)]
fn nav_page(
    nav: NavView,
    fix: Option<&Fix>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Row 0: the page label left, the state tag right — blinking for REC while
    // `animate` is on like every other run page. No hero: the panel owns rows 1+.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "NAV{:>width$}", tag, width = COLS - 3);
    } else {
        let _ = write!(rows[0], "NAV");
    }

    let info = &mut rows[NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS];
    match nav {
        NavView::NoCourse => {
            let _ = write!(info, "NO COURSE LOADED");
        }
        NavView::NoFix => {
            let _ = write!(info, "AWAITING FIX");
        }
        NavView::Status(s) => {
            // Clamps keep the row inside COLS at any input: 999.99 km along +
            // a 9999 m offset is exactly 21 cells.
            let km = (s.along_m / 1000.0).min(999.99);
            let off = (s.off_m as u32).min(9999);
            let _ = write!(info, "{:.2} KM  OFF {} M", km, off);
        }
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// A signed lap-style split for the pacer hero: `+` = ahead of the partner,
/// `-` = behind, then the magnitude in the same grow-to-hours format as
/// [`split_row`]. Zero reads `+0:00` — level with the partner, never blank.
fn signed_split(delta_s: i32) -> Row {
    let mut row = Row::new();
    let _ = row.push(if delta_s < 0 { '-' } else { '+' });
    let _ = row.push_str(split_row(delta_s.unsigned_abs()).as_str());
    row
}

/// Cells (from the left) the back-to-start page's text may occupy on rows 3-7:
/// the right of those rows is the breadcrumb-map pixel region the app draws
/// after the text, so a longer row would collide with it.
pub const TRACKBACK_TEXT_COLS: usize = 10;

/// The back-to-start glance: distance back to the run's start up large in the
/// rows-0-1 hero (drawn by the app from [`page_hero`] — metres under a
/// kilometre, km with decimals beyond, the unit named on the label row), then
/// HDG (course over ground from the last two well-separated accepted fixes —
/// tier 1 has no magnetometer, so it is only meaningful while moving) and BRG
/// (great-circle bearing back to the start) as 16-wind names. The app overlays
/// the left of rows 5-7 with the relative direction arrow and the right of
/// rows 3-7 with the TrackBack breadcrumb map (see `trackback::project_track`);
/// this text layer only reserves that space. A missing or stale heading shows
/// `--` in the arrow's spot — an honest placeholder, never a stale arrow.
#[allow(clippy::too_many_arguments)]
fn back_to_start_glance(
    fix: Option<&Fix>,
    tb: Option<&TrackbackView>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x hero; only the state tag rides row 0, blinking for
    // REC while `animate` is on, steady-on otherwise.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    match trackback_distance(tb) {
        Some(d) if d < 1000.0 => {
            let _ = write!(rows[2], "TO START  M");
        }
        Some(_) => {
            let _ = write!(rows[2], "TO START  KM");
        }
        None => {
            let _ = write!(rows[2], "TO START");
        }
    }

    let heading = tb.and_then(|n| n.heading_sector(uptime_s));
    let bearing = tb.filter(|n| n.active()).and_then(|n| n.bearing_sector());
    match heading {
        Some(s) => {
            let _ = write!(
                rows[3],
                "{:<5}{}",
                "HDG",
                trackback::SECTOR_NAMES[s as usize]
            );
        }
        None => {
            let _ = write!(rows[3], "{:<5}--", "HDG");
        }
    }
    match bearing {
        Some(s) => {
            let _ = write!(
                rows[4],
                "{:<5}{}",
                "BRG",
                trackback::SECTOR_NAMES[s as usize]
            );
        }
        None => {
            let _ = write!(rows[4], "{:<5}--", "BRG");
        }
    }

    // The arrow's spot: blank when the app will draw the arrow there, an
    // honest placeholder when it can't (no or stale heading, or still at the
    // start) — never a stale arrow.
    if tb.and_then(|n| n.arrow_sector(uptime_s)).is_none() {
        let _ = write!(rows[6], "  --");
    }

    write_gps_row(&mut rows[8], "GPS", fix, uptime_s, mode);
    rows
}

/// A lap split as `M:SS`, growing to `H:MM:SS` past the hour — laps are
/// usually minutes, so the shorter form keeps the 2x hero digits big without
/// a misleading leading zero-hour.
fn split_row(total_s: u32) -> Row {
    let (h, m, s) = hms(total_s);
    let mut row = Row::new();
    if h > 0 {
        let _ = write!(row, "{}:{:02}:{:02}", h.min(999), m, s);
    } else {
        let _ = write!(row, "{}:{:02}", m, s);
    }
    row
}

/// The HR gutter frame: a ~1 Hz liveness pulse (big/small heart) while a pulse
/// is detected — a "still recording, still beating" cue, not a beat-accurate
/// BPM sync. Steady when HR is absent, or when `animate` is off (the app gates
/// animation to the seconds after an interaction to spare the display the
/// per-second redraw an idle wrist would otherwise pay all run long).
fn heart_icon(hr_bpm: Option<u16>, uptime_s: u32, animate: bool) -> FaceIcon {
    match hr_bpm {
        Some(_) if animate && uptime_s % 2 == 1 => FaceIcon::HeartSmall,
        _ => FaceIcon::Heart,
    }
}

/// The GPS gutter frame: the full satellite once a fresh fix is locked, else a
/// growing-arc search cycle so a lost or not-yet-acquired fix reads as actively
/// hunting. When `animate` is off the search holds one steady frame instead of
/// cycling — the fix state still shows, without the per-second redraw.
fn gps_icon(fix: Option<&Fix>, uptime_s: u32, animate: bool, stale_after: u32) -> FaceIcon {
    if gps_fresh(fix, uptime_s, stale_after) {
        FaceIcon::Satellite
    } else if !animate {
        FaceIcon::SatSearch1
    } else {
        match uptime_s % 3 {
            0 => FaceIcon::SatSearch0,
            1 => FaceIcon::SatSearch1,
            _ => FaceIcon::Satellite,
        }
    }
}

fn gps_fresh(fix: Option<&Fix>, uptime_s: u32, stale_after: u32) -> bool {
    matches!(fix, Some(f) if uptime_s.saturating_sub(f.uptime_s) <= stale_after)
}

/// The active-run layout. Rows 0-1 are the elapsed-time hero — left empty here
/// and drawn at 2x by the app from [`hero_line`], with only the recording-state
/// tag riding the top-right corner. Rows 2/5/6/7/8 carry a gutter icon (see
/// [`face_icons`]) so they leave their first five cells blank; the two pace rows
/// keep a text label. Every value aligns at column 5 so the numbers stack in one
/// glanceable column regardless of icon-vs-label gutter.
#[allow(clippy::too_many_arguments)]
fn dashboard(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    snap: &Snapshot,
    tag: &str,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    const GUTTER: &str = "     ";
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x elapsed-time hero (drawn by the app). Only the
    // recording-state tag lives here, pinned top-right clear of the hero digits.
    // Blink it at ~1 Hz for REC so a live recording is unmistakable; PAU / FIN
    // (and any state once `animate` is off) stay steady-on.
    let tag_shown = tag != "REC" || !animate || uptime_s.is_multiple_of(2);
    if tag_shown {
        let _ = write!(rows[0], "{:>width$}", tag, width = COLS);
    }

    let km = (snap.distance_m / 1000.0).min(9999.99);
    let _ = write!(rows[2], "{}{:.2} KM", GUTTER, km);

    write_pace(&mut rows[3], "PACE", snap.avg_pace_s_per_km);
    write_pace(&mut rows[4], "NOW", snap.current_pace_s_per_km);

    write_hr(&mut rows[5], "", hr_bpm, &snap.zone_cutoffs);

    match elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        Some(alt) => {
            let _ = write!(rows[6], "{}{:.0} M", GUTTER, alt.min(99_999.0));
        }
        None => {
            let _ = write!(rows[6], "{}--", GUTTER);
        }
    }

    match elev {
        Some(e) => {
            let gain = (e.gain_m as u32).min(99_999);
            let loss = (e.loss_m as u32).min(99_999);
            let _ = write!(rows[7], "{}+{} -{} M", GUTTER, gain, loss);
        }
        None => {
            let _ = write!(rows[7], "{}--", GUTTER);
        }
    }

    write_gps_row(&mut rows[8], "", fix, uptime_s, mode);
    rows
}

/// The idle / bench layout — brand, the selected GNSS mode with its projected
/// hours, GPS status, last-known position, speed, altitude, HR, and vert
/// (falling back to the UTC clock with no baro). The title row is deliberately
/// static (no ticking uptime): the screen task is event-driven, so a resting
/// idle face with no per-second element lets the CPU sleep instead of waking
/// every second to advance a cosmetic clock. Time of day still shows on the
/// bottom row from the GPS fix, updating on each fix.
///
/// Row 1 is the mode picker's read-out — BTN3 cycles it while idle — pairing
/// the mode tag with its battery figure. The `~` marks the hours as the
/// projection they are (tier-2 estimates derived in [`crate::gnss_mode`]; the
/// tier-1 bench can't measure power at all).
fn status_face(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let _ = write!(rows[0], "THREKIR");
    let _ = write!(
        rows[1],
        "MODE {:<5}~{}H",
        mode.label(),
        mode.battery_est_h()
    );

    match fix {
        None => {
            let _ = write!(rows[2], "GPS  ACQUIRING");
            let _ = write!(rows[3], "LAT  --");
            let _ = write!(rows[4], "LON  --");
        }
        Some(fix) => {
            let age = uptime_s.saturating_sub(fix.uptime_s);
            if age > STALE_AFTER_S {
                let _ = write!(rows[2], "GPS  STALE {}S", age.min(999));
            } else {
                let _ = write!(rows[2], "GPS  {} SATS", fix.sats);
            }
            let _ = write!(rows[3], "LAT  {:11.5}", fix.lat_deg);
            let _ = write!(rows[4], "LON  {:11.5}", fix.lon_deg);
            let _ = write!(rows[5], "SPD  {:.1} M/S", fix.speed_mps);
        }
    }

    // Altitude: the barometer beats the GPS fix when it is live (baro works
    // without a fix, so this row can render on the bench with no satellites).
    if let Some(alt) = elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        let _ = write!(rows[6], "ALT  {:.0} M", alt);
    }

    if let Some(bpm) = hr_bpm {
        let _ = write!(rows[7], "HR   {} BPM", bpm);
    }

    // Bottom row: cumulative vert while the baro streams, else the GPS wall
    // clock. Metres clamped to five digits so the row can't overflow COLS.
    match elev {
        Some(e) => {
            let gain = (e.gain_m as u32).min(99_999);
            let loss = (e.loss_m as u32).min(99_999);
            let _ = write!(rows[8], "VERT +{} -{} M", gain, loss);
        }
        None => {
            if let Some(tod) = fix.and_then(|f| f.time_of_day) {
                let (th, tm, ts) = hms(tod);
                let _ = write!(rows[8], "UTC  {:02}:{:02}:{:02}", th, tm, ts);
            }
        }
    }
    rows
}

/// Write a `M:SS /KM` pace onto a dashboard row behind `label` (padded to the
/// five-cell value gutter), or a `--` placeholder when pace is not yet
/// meaningful. The pace rows are text-labelled rather than iconned: an icon
/// can't distinguish average from current pace, but the words can.
fn write_pace(row: &mut Row, label: &str, pace_s_per_km: Option<u32>) {
    match pace_s_per_km {
        Some(p) => {
            let (pm, ps) = ((p / 60).min(99), p % 60);
            let _ = write!(row, "{:<5}{}:{:02} /KM", label, pm, ps);
        }
        None => {
            let _ = write!(row, "{:<5}--", label);
        }
    }
}

/// Write the run-view HR value — `152 BPM Z3`, the BPM with its live zone on
/// the run's ladder — behind a five-cell label (or the blank icon gutter when
/// `label` is empty), with the usual `--` placeholder while no pulse is
/// detected. Only run layouts carry the zone: the idle status face keeps its
/// plain BPM, since zones frame effort within a recording.
fn write_hr(row: &mut Row, label: &str, hr_bpm: Option<u16>, cutoffs: &ZoneCutoffs) {
    match hr_bpm {
        Some(bpm) => {
            let zone = hr_zones::zone_for_bpm(bpm, cutoffs);
            let _ = write!(row, "{:<5}{} BPM Z{}", label, bpm, zone);
        }
        None => {
            let _ = write!(row, "{:<5}--", label);
        }
    }
}

/// The GPS glance shared by both layouts: satellite count, a staleness flag, or
/// `ACQUIRING` before the first fix. Value only — the caller supplies the label
/// and the staleness budget in force (see [`stale_after_s`]).
fn gps_value(fix: Option<&Fix>, uptime_s: u32, stale_after: u32) -> Row {
    let mut v = Row::new();
    match fix {
        None => {
            let _ = write!(v, "ACQUIRING");
        }
        Some(fix) => {
            let age = uptime_s.saturating_sub(fix.uptime_s);
            if age > stale_after {
                let _ = write!(v, "STALE {}S", age.min(999));
            } else {
                let _ = write!(v, "{} SATS", fix.sats);
            }
        }
    }
    v
}

/// Write a run-view GPS row: the glance value under the mode-stretched
/// staleness budget, tagged with the active GNSS mode so a mid-run glance
/// always shows which fix cadence (and battery trade) the run is on. Run
/// layouts only — the idle status face pairs its plain GPS row with the
/// dedicated MODE row instead.
fn write_gps_row(row: &mut Row, label: &str, fix: Option<&Fix>, uptime_s: u32, mode: GnssMode) {
    let _ = write!(
        row,
        "{:<5}{} {}",
        label,
        gps_value(fix, uptime_s, stale_after_s(mode, true)).as_str(),
        mode.label()
    );
}

fn hms(total_s: u32) -> (u32, u32, u32) {
    (total_s / 3600, total_s / 60 % 60, total_s % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The bulk of the suite exercises the default Performance mode (the 1 Hz
    // behaviour that predates selectable modes); these shadows keep those
    // call sites at the historical shape. Mode-specific behaviour calls
    // `super::` directly with an explicit mode.
    fn face_rows(
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        elev: Option<&elevation::Reading>,
        uptime_s: u32,
    ) -> [Row; ROWS] {
        super::face_rows(fix, hr_bpm, rec, elev, uptime_s, GnssMode::Performance)
    }

    fn face_icons(
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        uptime_s: u32,
    ) -> [Option<FaceIcon>; ROWS] {
        super::face_icons(fix, hr_bpm, rec, uptime_s, GnssMode::Performance)
    }

    #[allow(clippy::too_many_arguments)]
    fn page_rows(
        page: Page,
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        elev: Option<&elevation::Reading>,
        nav: NavView,
        tb: Option<&TrackbackView>,
        uptime_s: u32,
        animate: bool,
    ) -> [Row; ROWS] {
        super::page_rows(
            page,
            fix,
            hr_bpm,
            rec,
            elev,
            nav,
            tb,
            uptime_s,
            animate,
            GnssMode::Performance,
        )
    }

    fn page_icons(
        page: Page,
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        uptime_s: u32,
        animate: bool,
    ) -> [Option<FaceIcon>; ROWS] {
        super::page_icons(
            page,
            fix,
            hr_bpm,
            rec,
            uptime_s,
            animate,
            GnssMode::Performance,
        )
    }

    fn fix() -> Fix {
        Fix {
            lat_deg: 40.01502,
            lon_deg: -105.2705,
            speed_mps: 3.0,
            course_deg: Some(90.0),
            sats: 8,
            alt_m: Some(1624.0),
            time_of_day: Some(7 * 3600 + 30 * 60 + 15),
            uptime_s: 41,
        }
    }

    fn snapshot(state: RecordState, distance_m: f64) -> Snapshot {
        Snapshot {
            state,
            distance_m,
            elapsed_s: 0,
            moving_s: 0,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
            gap_s_per_km: None,
            lap: 1,
            lap_distance_m: 0.0,
            lap_elapsed_s: 0,
            last_lap: None,
            pacer: None,
            zone_cutoffs: hr_zones::zone_cutoffs_from_max_hr(hr_zones::DEFAULT_MAX_HR_BPM),
            zone_time_s: [0; ZONE_COUNT],
            cutoff: None,
            race_prediction: None,
            pace_bucket_m: [0.0; crate::record::PACE_BUCKET_COUNT],
            training_stress: None,
            band: None,
            gear: None,
            roadbook: None,
            fuel: None,
            training_paces: None,
            fitness: None,
            elev_profile: crate::record::ElevProfileView::empty(),
            recap: None,
            streaks: None,
            run_stats: None,
            pr_recency: None,
            plan_replan: None,
            readiness: None,
            goals: None,
            turn_cue: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            race_day: None,
        }
    }

    fn elev(alt_m: f32, gain_m: f32, loss_m: f32) -> elevation::Reading {
        elevation::Reading {
            alt_m,
            gain_m,
            loss_m,
        }
    }

    #[test]
    fn all_rows_fit_the_grid() {
        // Dashboard at extreme values.
        let mut rec = snapshot(RecordState::Recording, 9_999_990.0);
        rec.elapsed_s = 999 * 3600 + 59 * 60 + 59;
        rec.avg_pace_s_per_km = Some(99 * 60 + 59);
        rec.current_pace_s_per_km = Some(99 * 60 + 59);
        let e = elev(99_999.0, 99_999.0, 99_999.0);
        for row in face_rows(Some(&fix()), Some(220), Some(&rec), Some(&e), 42) {
            assert!(row.len() <= COLS, "dashboard row too wide: {:?}", row);
        }
        // Idle status face at extreme values.
        for row in face_rows(Some(&fix()), Some(220), None, Some(&e), 999_999) {
            assert!(row.len() <= COLS, "status row too wide: {:?}", row);
        }
    }

    #[test]
    fn every_page_fits_the_grid_active_and_inactive() {
        use crate::record::{
            AutoEffortView, ElevProfileView, FitnessView, FuelCarryView, FuelView, GoalsView,
            PlanReplanView, PrRecencyView, RaceDayView, ReadinessView, RecapView, RoadbookLegView,
            RoadbookView, RouteElevView, RouteSimplifyView, RunStatsView, StreaksView,
            TrainingPacesView, TurnCueView, ELEV_PROFILE_CAP,
        };
        // An active run with every new page's data at extreme values.
        let mut rec = snapshot(RecordState::Recording, 9_999_990.0);
        rec.elapsed_s = 999 * 3600 + 59 * 60 + 59;
        rec.moving_s = 999 * 3600 + 59 * 60 + 59;
        rec.avg_pace_s_per_km = Some(99 * 60 + 59);
        rec.current_pace_s_per_km = Some(99 * 60 + 59);
        rec.gap_s_per_km = Some(99 * 60 + 59);
        rec.pace_bucket_m = [12_345.6; crate::record::PACE_BUCKET_COUNT];
        rec.training_stress = Some(9999.0);
        rec.band = crate::distance_bands::band_for_distance(42_200.0);
        rec.gear = Some(crate::gear_wear::gear_wear(
            Some(1_200_000.0),
            Some(800_000.0),
        ));
        rec.roadbook = Some(RoadbookView {
            total: 99,
            upcoming: [RoadbookLegView {
                cum_dist_m: 999_990.0,
                projected_elapsed_s: 99 * 3600 + 59 * 60 + 59,
                cutoff: Some(CutoffStatus::Miss),
            }; crate::record::ROADBOOK_WINDOW],
            upcoming_len: crate::record::ROADBOOK_WINDOW as u8,
        });
        rec.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 9999.0,
                fluid_ml: 99_999.0,
            }),
            total_carbs_g: 9999.0,
            total_fluid_ml: 999_999.0,
        });
        // A slow goal pace stresses the widest zone-pace rows; "NO DATA" is the
        // longest recovery word and 999 the widest VO2.
        rec.training_paces = Some(TrainingPacesView {
            goal_pace_s_per_km: 99 * 60 + 59,
            paces: crate::training_paces::paces_from_goal_pace(
                1200.0,
                crate::training_paces::TrainingGender::None,
            ),
        });
        rec.fitness = Some(FitnessView {
            vo2_max: Some(999.0),
            recovery: Some(RecoveryAdvice::NotEnoughData),
        });
        rec.elev_profile = ElevProfileView {
            samples: [99_999; ELEV_PROFILE_CAP],
            len: ELEV_PROFILE_CAP,
        };
        rec.recap = Some(RecapView {
            runs: 9999,
            distance_km: 65535,
            longest_km: 9999,
            best_streak_days: 9999,
        });
        rec.streaks = Some(StreaksView {
            current_days: 9999,
            best_days: 9999,
        });
        rec.run_stats = Some(RunStatsView {
            moving_s: 999 * 3600 + 59 * 60 + 59,
            gain_m: 65535,
            splits: 9999,
        });
        rec.pr_recency = Some(PrRecencyView { days_ago: 9999 });
        rec.plan_replan = Some(PlanReplanView {
            changes: 255,
            make_ups: 255,
            ease_offs: 255,
        });
        rec.readiness = Some(ReadinessView {
            score: 100,
            band: 1,
        });
        rec.goals = Some(GoalsView {
            percent: 100,
            complete: false,
        });
        rec.turn_cue = Some(TurnCueView {
            direction: 0,
            distance_m: 65535,
            remaining: 255,
        });
        rec.route_simplify = Some(RouteSimplifyView {
            points: 65535,
            distance_km: 65535,
        });
        rec.auto_effort = Some(AutoEffortView {
            matched: 255,
            considered: 255,
        });
        rec.route_elev = Some(RouteElevView {
            gain_m: 65535,
            loss_m: 65535,
            points: 65535,
        });
        rec.race_day = Some(RaceDayView {
            days_until: -9999,
            feasible: 1,
        });
        let e = elev(99_999.0, 99_999.0, 99_999.0);

        let mut p = Page::default();
        for _ in 0..31 {
            let rows = page_rows(
                p,
                Some(&fix()),
                Some(220),
                Some(&rec),
                Some(&e),
                NavView::NoCourse,
                None,
                42,
                true,
            );
            for row in rows {
                assert!(
                    row.len() <= COLS,
                    "active page {:?} row too wide: {:?}",
                    p,
                    row
                );
            }
            if let Some(h) = page_hero(p, Some(220), Some(&rec), None) {
                assert!(
                    h.len() <= COLS,
                    "active page {:?} hero too wide: {:?}",
                    p,
                    h
                );
            }
            p = p.next();
        }

        // Inactive: a short run with no pushed roadbook / fuel / gear — every new
        // page must render its honest empty state and still fit the grid.
        let inactive = snapshot(RecordState::Recording, 15_000.0);
        let mut p = Page::default();
        for _ in 0..31 {
            let rows = page_rows(
                p,
                None,
                None,
                Some(&inactive),
                None,
                NavView::NoCourse,
                None,
                42,
                true,
            );
            for row in rows {
                assert!(
                    row.len() <= COLS,
                    "inactive page {:?} row too wide: {:?}",
                    p,
                    row
                );
            }
            p = p.next();
        }
    }

    #[test]
    fn idle_renders_the_status_face() {
        let rows = face_rows(Some(&fix()), None, None, None, 42);
        // Title row is static (no ticking uptime) so the idle screen doesn't
        // force a per-second wake; time of day still shows on the UTC row.
        assert_eq!(rows[0].as_str(), "THREKIR");
        assert_eq!(rows[1].as_str(), "MODE PERF ~110H");
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        assert_eq!(rows[4].as_str(), "LON   -105.27050");
        assert_eq!(rows[5].as_str(), "SPD  3.0 M/S");
        assert_eq!(rows[6].as_str(), "ALT  1624 M");
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn idle_stale_fix_is_flagged_not_shown_as_fresh() {
        let rows = face_rows(Some(&fix()), None, None, None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[2].as_str(), "GPS  STALE 8S");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
    }

    #[test]
    fn idle_no_fix_renders_acquiring() {
        let rows = face_rows(None, None, None, None, 9);
        assert_eq!(rows[2].as_str(), "GPS  ACQUIRING");
        assert_eq!(rows[5].as_str(), "");
    }

    #[test]
    fn recording_renders_the_run_dashboard() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 3 * 3600 + 24 * 60 + 7;
        rec.avg_pace_s_per_km = Some(5 * 60 + 12);
        rec.current_pace_s_per_km = Some(4 * 60 + 58);
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42);
        // Rows 0-1 are the hero band: only the tag (top-right), hero drawn 2x.
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert!(rows[0].as_str().ends_with("REC"));
        assert_eq!(rows[1].as_str(), "");
        assert_eq!(hero_line(Some(&rec)).unwrap().as_str(), "3:24:07");
        assert_eq!(rows[2].as_str(), "     12.34 KM");
        assert_eq!(rows[3].as_str(), "PACE 5:12 /KM");
        assert_eq!(rows[4].as_str(), "NOW  4:58 /KM");
        assert_eq!(rows[5].as_str(), "     152 BPM Z3");
        assert_eq!(rows[6].as_str(), "     1600 M");
        assert_eq!(rows[7].as_str(), "     +540 -120 M");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
    }

    #[test]
    fn hero_shows_elapsed_only_while_a_run_is_active() {
        let mut rec = snapshot(RecordState::Recording, 100.0);
        rec.elapsed_s = 24 * 3600 + 15 * 60 + 30;
        assert_eq!(hero_line(Some(&rec)).unwrap().as_str(), "24:15:30");
        // Finished keeps the final time; idle / absent have no hero.
        let fin = snapshot(RecordState::Finished, 100.0);
        assert!(hero_line(Some(&fin)).is_some());
        assert!(hero_line(Some(&snapshot(RecordState::Idle, 0.0))).is_none());
        assert!(hero_line(None).is_none());
    }

    #[test]
    fn dashboard_icons_pair_with_the_iconned_rows() {
        let rec = snapshot(RecordState::Recording, 12_340.0);
        // Fresh fix (uptime 42 vs fix uptime 41) + HR present + even uptime, so
        // both animated icons sit on their steady frame.
        let icons = face_icons(Some(&fix()), Some(152), Some(&rec), 42);
        assert_eq!(icons[0], None); // hero band
        assert_eq!(icons[1], None); // hero band
        assert_eq!(icons[2], Some(FaceIcon::Footsteps));
        assert_eq!(icons[3], None); // PACE — text label
        assert_eq!(icons[4], None); // NOW — text label
        assert_eq!(icons[5], Some(FaceIcon::Heart));
        assert_eq!(icons[6], Some(FaceIcon::Mountain));
        assert_eq!(icons[7], Some(FaceIcon::Vert));
        assert_eq!(icons[8], Some(FaceIcon::Satellite));

        // The idle status face is all text — no gutter icons.
        assert!(face_icons(None, None, None, 0).iter().all(Option::is_none));
        let idle = snapshot(RecordState::Idle, 0.0);
        assert!(face_icons(None, None, Some(&idle), 0)
            .iter()
            .all(Option::is_none));
    }

    #[test]
    fn heart_icon_pulses_once_per_second_while_hr_is_present() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // HR present: big heart on even seconds, small on odd.
        assert_eq!(
            face_icons(Some(&fix()), Some(150), Some(&rec), 42)[5],
            Some(FaceIcon::Heart)
        );
        assert_eq!(
            face_icons(Some(&fix()), Some(150), Some(&rec), 43)[5],
            Some(FaceIcon::HeartSmall)
        );
        // No HR: steady big heart, no pulse.
        assert_eq!(
            face_icons(Some(&fix()), None, Some(&rec), 43)[5],
            Some(FaceIcon::Heart)
        );
    }

    #[test]
    fn gps_icon_cycles_search_arcs_until_a_fresh_fix_locks() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // No fix: arcs grow 0 -> 1 -> 2 with uptime % 3.
        assert_eq!(
            face_icons(None, None, Some(&rec), 0)[8],
            Some(FaceIcon::SatSearch0)
        );
        assert_eq!(
            face_icons(None, None, Some(&rec), 1)[8],
            Some(FaceIcon::SatSearch1)
        );
        assert_eq!(
            face_icons(None, None, Some(&rec), 2)[8],
            Some(FaceIcon::Satellite)
        );
        // A stale fix still reads as searching, not locked.
        let stale_uptime = 41 + STALE_AFTER_S + 3;
        assert!(matches!(
            face_icons(Some(&fix()), None, Some(&rec), stale_uptime)[8],
            Some(FaceIcon::SatSearch0 | FaceIcon::SatSearch1 | FaceIcon::Satellite)
        ));
        // A fresh fix locks the full satellite regardless of the second.
        assert_eq!(
            face_icons(Some(&fix()), None, Some(&rec), 43)[8],
            Some(FaceIcon::Satellite)
        );
    }

    #[test]
    fn rec_tag_blinks_but_pause_and_finish_stay_steady() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // REC visible on even seconds, hidden on odd.
        assert_eq!(
            face_rows(None, None, Some(&rec), None, 10)[0]
                .as_str()
                .trim(),
            "REC"
        );
        assert_eq!(face_rows(None, None, Some(&rec), None, 11)[0].as_str(), "");
        // Paused / finished tags never blink.
        let paused = snapshot(RecordState::Paused, 100.0);
        assert_eq!(
            face_rows(None, None, Some(&paused), None, 11)[0]
                .as_str()
                .trim(),
            "PAU"
        );
    }

    #[test]
    fn iconned_rows_leave_the_gutter_blank_for_the_glyph() {
        // Every row that face_icons places a glyph on must start with the
        // five-cell blank gutter, or the icon would collide with text.
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 42;
        rec.avg_pace_s_per_km = Some(300);
        rec.current_pace_s_per_km = Some(280);
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42);
        let icons = face_icons(Some(&fix()), Some(152), Some(&rec), 42);
        for (row, icon) in icons.iter().enumerate() {
            if icon.is_some() {
                assert!(
                    rows[row].starts_with("     "),
                    "iconned row {} lacks a blank gutter: {:?}",
                    row,
                    rows[row]
                );
            }
        }
    }

    #[test]
    fn dashboard_shows_placeholders_before_metrics_are_available() {
        // Recording, but no pace yet, no HR sensor, no baro. Even second so
        // the blinking REC tag is on its visible frame.
        let rec = snapshot(RecordState::Recording, 0.0);
        let rows = face_rows(None, None, Some(&rec), None, 2);
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[1].as_str(), "");
        assert_eq!(hero_line(Some(&rec)).unwrap().as_str(), "0:00:00");
        assert_eq!(rows[2].as_str(), "     0.00 KM");
        assert_eq!(rows[3].as_str(), "PACE --");
        assert_eq!(rows[4].as_str(), "NOW  --");
        assert_eq!(rows[5].as_str(), "     --");
        assert_eq!(rows[6].as_str(), "     --");
        assert_eq!(rows[7].as_str(), "     --");
        assert_eq!(rows[8].as_str(), "     ACQUIRING PERF");
    }

    #[test]
    fn dashboard_alt_falls_back_to_the_gps_fix_without_a_baro() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = face_rows(Some(&fix()), None, Some(&rec), None, 42);
        assert_eq!(rows[6].as_str(), "     1624 M");
        assert_eq!(rows[7].as_str(), "     --");
    }

    #[test]
    fn dashboard_flags_a_stale_fix_on_the_gps_line() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = face_rows(Some(&fix()), None, Some(&rec), None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[8].as_str(), "     STALE 8S PERF");
    }

    #[test]
    fn paused_and_finished_runs_keep_the_dashboard() {
        let rows = face_rows(
            None,
            None,
            Some(&snapshot(RecordState::Paused, 5_000.0)),
            None,
            3,
        );
        assert_eq!(rows[0].as_str().trim(), "PAU");
        assert_eq!(rows[2].as_str(), "     5.00 KM");

        let rows = face_rows(
            None,
            None,
            Some(&snapshot(RecordState::Finished, 42_195.0)),
            None,
            3,
        );
        assert_eq!(rows[0].as_str().trim(), "FIN");
        assert_eq!(rows[2].as_str(), "     42.20 KM");
    }

    #[test]
    fn page_dashboard_matches_the_bare_dashboard_entry_points() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 3 * 3600 + 24 * 60 + 7;
        let e = elev(1600.0, 540.0, 120.0);
        // The Dashboard page (animated) delegates to face_rows / face_icons.
        assert_eq!(
            page_rows(
                Page::Dashboard,
                Some(&fix()),
                Some(152),
                Some(&rec),
                Some(&e),
                NavView::NoCourse,
                None,
                42,
                true
            ),
            face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42)
        );
        assert_eq!(
            page_icons(
                Page::Dashboard,
                Some(&fix()),
                Some(152),
                Some(&rec),
                42,
                true
            ),
            face_icons(Some(&fix()), Some(152), Some(&rec), 42)
        );
        assert_eq!(
            page_hero(Page::Dashboard, Some(152), Some(&rec), None),
            hero_line(Some(&rec))
        );
    }

    #[test]
    fn distance_glance_puts_distance_up_large() {
        let mut rec = snapshot(RecordState::Recording, 42_190.0);
        rec.elapsed_s = 3 * 3600 + 24 * 60 + 7;
        rec.avg_pace_s_per_km = Some(5 * 60 + 12);
        let rows = page_rows(
            Page::Distance,
            Some(&fix()),
            Some(152),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Distance, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "42.19"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        // Rows 0-2 are the 3x hero (drawn by the app); the label rides row 3.
        assert_eq!(rows[2].as_str(), "");
        assert_eq!(rows[3].as_str(), "DISTANCE  KM");
        assert_eq!(rows[4].as_str(), "TIME 3:24:07");
        assert_eq!(rows[5].as_str(), "PACE 5:12 /KM");
        assert_eq!(rows[6].as_str(), "HR   152 BPM Z3");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Glance pages carry no gutter icons.
        assert!(page_icons(
            Page::Distance,
            Some(&fix()),
            Some(152),
            Some(&rec),
            42,
            true
        )
        .iter()
        .all(Option::is_none));
    }

    #[test]
    fn pace_glance_puts_pace_up_large_with_distance_secondary() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.avg_pace_s_per_km = Some(5 * 60 + 12);
        rec.gap_s_per_km = Some(4 * 60 + 52);
        let rows = page_rows(
            Page::Pace,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Pace, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "5:12"
        );
        assert_eq!(rows[3].as_str(), "AVG PACE  /KM");
        assert_eq!(rows[5].as_str(), "DIST 12.34 KM");
        assert_eq!(rows[6].as_str(), "HR   --");
        assert_eq!(rows[7].as_str(), "GAP  4:52 /KM");
        // No pace yet -> the hero placeholder, never a bogus number.
        let fresh = snapshot(RecordState::Recording, 5.0);
        assert_eq!(
            page_hero(Page::Pace, None, Some(&fresh), None)
                .unwrap()
                .as_str(),
            "--:--"
        );
    }

    #[test]
    fn pace_glance_gap_shows_a_placeholder_until_available() {
        // Stopped / walking / no signal: GAP is None and the row keeps its
        // fixed slot with the same placeholder the other metrics use; the
        // distance glance never carries a GAP row.
        let rec = snapshot(RecordState::Recording, 12_340.0);
        let rows = page_rows(
            Page::Pace,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[7].as_str(), "GAP  --");
        let rows = page_rows(
            Page::Distance,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn lap_glance_shows_lap_number_current_time_and_last_split() {
        let mut rec = snapshot(RecordState::Recording, 3_400.0);
        rec.lap = 4;
        rec.lap_distance_m = 420.0;
        rec.lap_elapsed_s = 2 * 60 + 5;
        rec.last_lap = Some(crate::record::Lap {
            index: 3,
            distance_m: 1002.0,
            elapsed_s: 4 * 60 + 58,
            moving_s: 4 * 60 + 50,
        });
        let rows = page_rows(
            Page::Lap,
            Some(&fix()),
            Some(152),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Lap, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "2:05"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "LAP 4");
        assert_eq!(rows[4].as_str(), "LAST 4:58");
        assert_eq!(rows[5].as_str(), "DIST 0.42 KM");
        assert_eq!(rows[6].as_str(), "HR   152 BPM Z3");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Glance pages carry no gutter icons.
        assert!(
            page_icons(Page::Lap, Some(&fix()), Some(152), Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn lap_glance_first_lap_has_no_last_split() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = page_rows(
            Page::Lap,
            None,
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(rows[2].as_str(), "LAP 1");
        assert_eq!(rows[4].as_str(), "LAST --");
        assert_eq!(rows[6].as_str(), "HR   --");
        assert_eq!(
            page_hero(Page::Lap, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "0:00"
        );
    }

    #[test]
    fn lap_splits_grow_to_hours_past_sixty_minutes() {
        // An ultra checkpoint-to-checkpoint "lap" can run past an hour: the
        // split format grows rather than wrapping the minutes.
        let mut rec = snapshot(RecordState::Recording, 100.0);
        rec.lap_elapsed_s = 59 * 60 + 59;
        assert_eq!(
            page_hero(Page::Lap, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "59:59"
        );
        rec.lap_elapsed_s = 3600 + 2 * 60 + 3;
        assert_eq!(
            page_hero(Page::Lap, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1:02:03"
        );
    }

    #[test]
    fn gating_animation_off_freezes_every_animated_element() {
        // Odd second, HR present, no fresh fix: with animation ON everything is
        // on its alternate frame; with it OFF each holds a steady frame so the
        // display pays no per-second redraw for them.
        let rec = snapshot(RecordState::Recording, 100.0);
        let odd = 41 + STALE_AFTER_S + 5; // odd, and past STALE so GPS is searching
        assert_eq!(odd % 2, 1);

        // REC tag: blinks off when animating, steady-on when gated.
        assert_eq!(
            page_rows(
                Page::Dashboard,
                None,
                Some(150),
                Some(&rec),
                None,
                NavView::NoCourse,
                None,
                odd,
                true
            )[0]
            .as_str(),
            ""
        );
        assert_eq!(
            page_rows(
                Page::Dashboard,
                None,
                Some(150),
                Some(&rec),
                None,
                NavView::NoCourse,
                None,
                odd,
                false
            )[0]
            .as_str()
            .trim(),
            "REC"
        );

        // Heart: HeartSmall frame when animating, steady Heart when gated.
        let on = page_icons(
            Page::Dashboard,
            Some(&fix()),
            Some(150),
            Some(&rec),
            odd,
            true,
        );
        let off = page_icons(
            Page::Dashboard,
            Some(&fix()),
            Some(150),
            Some(&rec),
            odd,
            false,
        );
        assert_eq!(on[5], Some(FaceIcon::HeartSmall));
        assert_eq!(off[5], Some(FaceIcon::Heart));

        // GPS search: cycles a frame when animating, one steady frame when gated.
        assert_eq!(off[8], Some(FaceIcon::SatSearch1));
        // A fresh fix locks the full satellite either way (nothing to gate).
        let fresh_on = page_icons(
            Page::Dashboard,
            Some(&fix()),
            Some(150),
            Some(&rec),
            42,
            true,
        );
        let fresh_off = page_icons(
            Page::Dashboard,
            Some(&fix()),
            Some(150),
            Some(&rec),
            42,
            false,
        );
        assert_eq!(fresh_on[8], Some(FaceIcon::Satellite));
        assert_eq!(fresh_off[8], Some(FaceIcon::Satellite));
    }

    #[test]
    fn every_page_falls_back_to_the_status_face_when_idle() {
        for page in [
            Page::Dashboard,
            Page::Distance,
            Page::Pace,
            Page::Lap,
            Page::Zones,
            Page::Pacer,
            Page::Nav,
            Page::BackToStart,
        ] {
            let rows = page_rows(
                page,
                Some(&fix()),
                None,
                None,
                None,
                NavView::NoCourse,
                None,
                42,
                true,
            );
            assert_eq!(rows[2].as_str(), "GPS  8 SATS"); // status-face signature
            assert!(page_hero(page, None, None, None).is_none());
            assert!(page_icons(page, Some(&fix()), None, None, 42, true)
                .iter()
                .all(Option::is_none));
        }
    }

    #[test]
    fn glance_rows_fit_the_grid_at_extremes() {
        let mut rec = snapshot(RecordState::Recording, 9_999_990.0);
        rec.elapsed_s = 999 * 3600 + 59 * 60 + 59;
        rec.avg_pace_s_per_km = Some(99 * 60 + 59);
        rec.gap_s_per_km = Some(99 * 60 + 59);
        rec.lap = 9999;
        rec.lap_distance_m = 9_999_990.0;
        rec.lap_elapsed_s = 999 * 3600 + 59 * 60 + 59;
        rec.last_lap = Some(crate::record::Lap {
            index: 9998,
            distance_m: 9_999_990.0,
            elapsed_s: 999 * 3600 + 59 * 60 + 59,
            moving_s: 999 * 3600 + 59 * 60 + 59,
        });
        rec.zone_time_s = [u32::MAX; ZONE_COUNT];
        rec.pacer = Some(crate::pacer::PacerStatus {
            goal: crate::pacer::PacerGoal {
                distance_m: 1_000_000,
                time_s: 1_000_000,
            },
            ahead_m: -9_999_999.0,
            ahead_s: i32::MIN,
            projected_finish_s: Some(u32::MAX),
            verdict: PaceVerdict::OnPace,
            finished: false,
        });
        for page in [
            Page::Distance,
            Page::Pace,
            Page::Lap,
            Page::Zones,
            Page::Pacer,
        ] {
            for row in page_rows(
                page,
                Some(&fix()),
                Some(u16::MAX),
                Some(&rec),
                None,
                NavView::NoCourse,
                None,
                43,
                true,
            ) {
                assert!(row.len() <= COLS, "glance row too wide: {:?}", row);
            }
            assert!(
                page_hero(page, Some(u16::MAX), Some(&rec), None)
                    .unwrap()
                    .len()
                    <= COLS
            );
        }
    }

    #[test]
    fn zones_glance_shows_hr_zone_and_the_per_zone_breakdown() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        // Z2-dominant run: bars scale to the fullest zone (Z2 = 8 cells).
        rec.zone_time_s = [10 * 60, 40 * 60, 20 * 60, 5 * 60, 0];
        let rows = page_rows(
            Page::Zones,
            Some(&fix()),
            Some(152),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Zones, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "152"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        // 152 bpm on the default 190 ladder is the Z3 cutoff itself.
        assert_eq!(rows[2].as_str(), "HR  BPM       ZONE 3");
        // The `{:<9}` pad keeps the (app-drawn) pixel bar's start column fixed;
        // the row text itself is now just the label + banked time.
        assert_eq!(rows[3].as_str(), "Z1 10:00    ");
        assert_eq!(rows[4].as_str(), "Z2 40:00    ");
        assert_eq!(rows[5].as_str(), "Z3 20:00    ");
        assert_eq!(rows[6].as_str(), "Z4 5:00     ");
        assert_eq!(rows[7].as_str(), "Z5 0:00     ");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Text-only page: no gutter icons.
        assert!(
            page_icons(Page::Zones, Some(&fix()), Some(152), Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn zones_glance_without_hr_shows_placeholders_and_no_bars() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = page_rows(
            Page::Zones,
            None,
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(
            page_hero(Page::Zones, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        assert_eq!(rows[2].as_str(), "HR  BPM       ZONE --");
        // Nothing banked: times at zero, no bars drawn.
        for row in &rows[3..8] {
            assert!(row.as_str().ends_with("0:00     "), "row: {:?}", row);
            assert!(!row.as_str().contains('#'));
        }
        assert_eq!(rows[8].as_str(), "GPS  ACQUIRING PERF");
    }

    #[test]
    fn zone_times_grow_to_hours_on_the_zones_glance() {
        // An ultra banks hours per zone; the split format grows like laps do.
        let mut rec = snapshot(RecordState::Recording, 100.0);
        rec.zone_time_s = [3600 + 2 * 60 + 3, 0, 0, 0, 0];
        let rows = page_rows(
            Page::Zones,
            None,
            Some(120),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(rows[3].as_str(), "Z1 1:02:03  ");
    }

    fn pacer_status(
        ahead_m: f64,
        ahead_s: i32,
        verdict: PaceVerdict,
        projected_finish_s: Option<u32>,
    ) -> crate::pacer::PacerStatus {
        crate::pacer::PacerStatus {
            goal: crate::pacer::PacerGoal {
                distance_m: 10_000,
                time_s: 3_000,
            },
            ahead_m,
            ahead_s,
            projected_finish_s,
            verdict,
            finished: false,
        }
    }

    #[test]
    fn pacer_glance_shows_the_partner_delta_ahead() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        rec.pacer = Some(pacer_status(140.0, 42, PaceVerdict::Ahead, Some(2_857)));
        let rows = page_rows(
            Page::Pacer,
            Some(&fix()),
            Some(152),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Pacer, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "+0:42"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "PACER         AHEAD");
        assert_eq!(rows[4].as_str(), "GOAL 10.00 KM");
        assert_eq!(rows[5].as_str(), "TGT  50:00");
        assert_eq!(rows[6].as_str(), "PROJ 47:37");
        assert_eq!(rows[7].as_str(), "DIST +140 M");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Text-only page: no gutter icons.
        assert!(
            page_icons(Page::Pacer, Some(&fix()), Some(152), Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn pacer_glance_spells_out_behind_with_the_minus_sign() {
        let mut rec = snapshot(RecordState::Recording, 1_780.0);
        rec.pacer = Some(pacer_status(-216.7, -65, PaceVerdict::Behind, Some(3_370)));
        let rows = page_rows(
            Page::Pacer,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Pacer, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "-1:05"
        );
        assert_eq!(rows[2].as_str(), "PACER         BEHIND");
        assert_eq!(rows[6].as_str(), "PROJ 56:10");
        assert_eq!(rows[7].as_str(), "DIST -216 M");

        // Level with the partner: an explicit +0:00 ON PACE, never blank.
        rec.pacer = Some(pacer_status(0.0, 0, PaceVerdict::OnPace, None));
        let rows = page_rows(
            Page::Pacer,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(
            page_hero(Page::Pacer, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "+0:00"
        );
        assert_eq!(rows[2].as_str(), "PACER         ON PACE");
        assert_eq!(rows[6].as_str(), "PROJ --");
        assert_eq!(rows[7].as_str(), "DIST +0 M");
    }

    #[test]
    fn pacer_glance_without_a_goal_is_honestly_inactive() {
        // Recording, no goal configured: the page says so instead of showing
        // zeros that read as "perfectly on pace".
        let rec = snapshot(RecordState::Recording, 2_100.0);
        assert!(rec.pacer.is_none());
        let rows = page_rows(
            Page::Pacer,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(
            page_hero(Page::Pacer, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "PACER --");
        assert_eq!(rows[4].as_str(), "NO GOAL SET");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(rows[7].as_str(), "");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
    }

    #[test]
    fn pacer_hero_grows_to_hours_and_keeps_the_sign() {
        let mut rec = snapshot(RecordState::Recording, 50_000.0);
        rec.pacer = Some(pacer_status(
            -18_000.0,
            -(3600 + 2 * 60 + 3),
            PaceVerdict::Behind,
            None,
        ));
        assert_eq!(
            page_hero(Page::Pacer, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "-1:02:03"
        );
    }

    #[test]
    fn run_view_hr_rows_carry_the_zone_from_the_snapshot_ladder() {
        // The zone beside HR follows the run's own cutoffs, not a fixed
        // ladder: 135 bpm reads Z3 at max 190 but Z2 at max 200.
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.zone_cutoffs = hr_zones::zone_cutoffs_from_max_hr(200);
        let rows = face_rows(Some(&fix()), Some(135), Some(&rec), None, 42);
        assert_eq!(rows[5].as_str(), "     135 BPM Z2");
        let rows = page_rows(
            Page::Lap,
            Some(&fix()),
            Some(135),
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[6].as_str(), "HR   135 BPM Z2");
        // The idle status face keeps its plain BPM — zones frame a recording.
        let rows = face_rows(Some(&fix()), Some(152), None, None, 42);
        assert_eq!(rows[7].as_str(), "HR   152 BPM");
    }

    #[test]
    fn idle_recorder_shows_the_status_face_not_the_dashboard() {
        let rows = face_rows(
            Some(&fix()),
            None,
            Some(&snapshot(RecordState::Idle, 0.0)),
            None,
            42,
        );
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[1].as_str(), "MODE PERF ~110H");
    }

    #[test]
    fn idle_mode_row_pairs_each_mode_with_its_projected_hours() {
        // The BTN3 mode picker's read-out: the tag plus the (projection-marked)
        // battery figure, one per mode, in the fixed row-1 slot.
        for (mode, expected) in [
            (GnssMode::Performance, "MODE PERF ~110H"),
            (GnssMode::Balanced, "MODE BAL  ~180H"),
            (GnssMode::Expedition, "MODE EXP  ~220H"),
        ] {
            let rows = super::face_rows(Some(&fix()), None, None, None, 42, mode);
            assert_eq!(rows[1].as_str(), expected);
            assert!(rows[1].len() <= COLS);
        }
    }

    #[test]
    fn run_gps_rows_carry_the_active_mode_tag() {
        let rec = snapshot(RecordState::Recording, 12_340.0);
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&rec),
            None,
            42,
            GnssMode::Expedition,
        );
        assert_eq!(rows[8].as_str(), "     8 SATS EXP");
        let rows = super::page_rows(
            Page::Distance,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
            GnssMode::Balanced,
        );
        assert_eq!(rows[8].as_str(), "GPS  8 SATS BAL");
    }

    #[test]
    fn run_staleness_budget_follows_the_mode_cadence() {
        // A 40 s-old fix mid-run: signal lost at the 1 Hz cadence, but exactly
        // the chosen rhythm one Expedition interval apart — SATS, not STALE,
        // and the locked satellite icon rather than the search arcs.
        let rec = snapshot(RecordState::Recording, 12_340.0);
        let aged = 41 + 40;
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&rec),
            None,
            aged,
            GnssMode::Performance,
        );
        assert_eq!(rows[8].as_str(), "     STALE 40S PERF");
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&rec),
            None,
            aged,
            GnssMode::Expedition,
        );
        assert_eq!(rows[8].as_str(), "     8 SATS EXP");
        let icons = super::face_icons(Some(&fix()), None, Some(&rec), aged, GnssMode::Expedition);
        assert_eq!(icons[8], Some(FaceIcon::Satellite));
        // Past even the Expedition budget (64 s) the flag comes back — a
        // genuinely lost signal is never dressed up as the mode's cadence.
        let lost = 41 + 65;
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&rec),
            None,
            lost,
            GnssMode::Expedition,
        );
        assert_eq!(rows[8].as_str(), "     STALE 65S EXP");
    }

    #[test]
    fn idle_staleness_keeps_the_tight_budget_in_every_mode() {
        // Idle publication is de-rated to just under STALE_AFTER_S regardless
        // of mode (the mode throttles recording, not idle), so the idle face
        // must flag a 40 s-old fix even in Expedition mode.
        assert_eq!(stale_after_s(GnssMode::Expedition, false), STALE_AFTER_S);
        assert_eq!(stale_after_s(GnssMode::Performance, true), STALE_AFTER_S);
        assert_eq!(stale_after_s(GnssMode::Balanced, true), 19);
        assert_eq!(stale_after_s(GnssMode::Expedition, true), 64);
        let rows = super::face_rows(
            Some(&fix()),
            None,
            None,
            None,
            41 + 40,
            GnssMode::Expedition,
        );
        assert_eq!(rows[2].as_str(), "GPS  STALE 40S");
    }

    #[test]
    fn mode_tagged_rows_fit_the_grid_at_extremes() {
        let rec = snapshot(RecordState::Recording, 9_999_990.0);
        for mode in [
            GnssMode::Performance,
            GnssMode::Balanced,
            GnssMode::Expedition,
        ] {
            for page in [
                Page::Dashboard,
                Page::Distance,
                Page::Pace,
                Page::Lap,
                Page::Zones,
            ] {
                let rows = super::page_rows(
                    page,
                    Some(&fix()),
                    Some(u16::MAX),
                    Some(&rec),
                    None,
                    NavView::NoCourse,
                    None,
                    999_999,
                    true,
                    mode,
                );
                for row in rows {
                    assert!(row.len() <= COLS, "row too wide in {:?}: {:?}", mode, row);
                }
            }
            let idle = super::face_rows(Some(&fix()), Some(u16::MAX), None, None, 999_999, mode);
            for row in idle {
                assert!(
                    row.len() <= COLS,
                    "idle row too wide in {:?}: {:?}",
                    mode,
                    row
                );
            }
        }
    }

    fn nav_status(along_m: f64, off_m: f64, alerting: bool) -> NavView {
        NavView::Status(NavStatus {
            along_m,
            off_m,
            alerting,
        })
    }

    #[test]
    fn nav_page_shows_along_and_off_distance() {
        let rec = snapshot(RecordState::Recording, 12_340.0);
        let rows = page_rows(
            Page::Nav,
            Some(&fix()),
            Some(152),
            Some(&rec),
            None,
            nav_status(12_340.0, 23.4, false),
            None,
            42,
            true,
        );
        assert_eq!(rows[0].as_str(), "NAV               REC");
        assert_eq!(rows[7].as_str(), "12.34 KM  OFF 23 M");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // No hero and no gutter icons — the map panel owns rows 1-6.
        assert!(page_hero(Page::Nav, Some(152), Some(&rec), None).is_none());
        assert!(
            page_icons(Page::Nav, Some(&fix()), Some(152), Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn nav_page_keeps_the_panel_rows_empty_in_every_state() {
        let rec = snapshot(RecordState::Recording, 100.0);
        for nav in [
            NavView::NoCourse,
            NavView::NoFix,
            nav_status(1_000.0, 55.0, true),
        ] {
            let rows = page_rows(
                Page::Nav,
                Some(&fix()),
                None,
                Some(&rec),
                None,
                nav,
                None,
                42,
                true,
            );
            for row in &rows[NAV_PANEL_TOP_ROW..NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS] {
                assert_eq!(row.as_str(), "", "panel row not empty for {:?}", nav);
            }
        }
    }

    #[test]
    fn nav_page_says_why_the_map_is_empty() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = page_rows(
            Page::Nav,
            None,
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(rows[7].as_str(), "NO COURSE LOADED");
        let rows = page_rows(
            Page::Nav,
            None,
            None,
            Some(&rec),
            None,
            NavView::NoFix,
            None,
            2,
            true,
        );
        assert_eq!(rows[7].as_str(), "AWAITING FIX");
        assert_eq!(rows[8].as_str(), "GPS  ACQUIRING PERF");
    }

    #[test]
    fn nav_alert_row_shows_only_while_the_alert_is_latched() {
        assert!(nav_alert_row(NavView::NoCourse).is_none());
        assert!(nav_alert_row(NavView::NoFix).is_none());
        assert!(nav_alert_row(nav_status(500.0, 30.0, false)).is_none());
        let row = nav_alert_row(nav_status(500.0, 55.0, true)).unwrap();
        assert_eq!(row.as_str(), "OFF COURSE");
        // The 2x overlay is two cells per char: it must fit the panel width.
        assert!(row.chars().count() * 2 <= COLS);
    }

    #[test]
    fn nav_rec_tag_blinks_but_the_label_stays() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let nav = nav_status(500.0, 5.0, false);
        let even = page_rows(Page::Nav, None, None, Some(&rec), None, nav, None, 10, true);
        assert_eq!(even[0].as_str(), "NAV               REC");
        let odd = page_rows(Page::Nav, None, None, Some(&rec), None, nav, None, 11, true);
        assert_eq!(odd[0].as_str(), "NAV");
        // Gated animation holds the tag steady-on.
        let gated = page_rows(
            Page::Nav,
            None,
            None,
            Some(&rec),
            None,
            nav,
            None,
            11,
            false,
        );
        assert_eq!(gated[0].as_str(), "NAV               REC");
    }

    #[test]
    fn nav_rows_fit_the_grid_at_extremes() {
        let rec = snapshot(RecordState::Recording, 9_999_990.0);
        let nav = nav_status(9_999_999.0, 99_999.0, true);
        let rows = page_rows(
            Page::Nav,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            nav,
            None,
            43,
            true,
        );
        for row in &rows {
            assert!(row.len() <= COLS, "nav row too wide: {:?}", row);
        }
        // Both values clamp rather than overflow the 21-cell info row.
        assert_eq!(rows[7].as_str(), "999.99 KM  OFF 9999 M");
    }

    /// A TrackbackView from a due-east walk: `steps` hops of `step_m`, one per second.
    fn nav_east(steps: u32, step_m: f64) -> TrackbackView {
        let mut tb = trackback::Trackback::new();
        let lon_per_m = 1.0 / (crate::record::METRES_PER_DEGREE_LAT * (40.0f64.to_radians()).cos());
        for i in 0..=steps {
            tb.on_point(40.0, -105.0 + i as f64 * step_m * lon_per_m, i);
        }
        tb.view()
    }

    #[test]
    fn back_to_start_shows_distance_heading_and_bearing() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let nav = nav_east(20, 6.0); // ~120 m due east, heading E, start W
        let rows = page_rows(
            Page::BackToStart,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            Some(&nav),
            20,
            true,
        );
        assert_eq!(
            page_hero(Page::BackToStart, None, Some(&rec), Some(&nav))
                .unwrap()
                .as_str(),
            "120"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "TO START  M");
        assert_eq!(rows[3].as_str(), "HDG  E");
        assert_eq!(rows[4].as_str(), "BRG  W");
        // A live arrow: its text spot stays blank for the app's drawing.
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Text-only page: no gutter icons.
        assert!(
            page_icons(Page::BackToStart, Some(&fix()), None, Some(&rec), 20, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn back_to_start_hero_switches_to_km_past_a_kilometre() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let nav = nav_east(500, 6.0); // ~3 km due east
        let rows = page_rows(
            Page::BackToStart,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            Some(&nav),
            500,
            true,
        );
        assert_eq!(rows[2].as_str(), "TO START  KM");
        assert_eq!(
            page_hero(Page::BackToStart, None, Some(&rec), Some(&nav))
                .unwrap()
                .as_str(),
            "3.00"
        );
    }

    #[test]
    fn back_to_start_placeholders_without_nav_and_with_a_stale_heading() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // No nav yet (recording started, no accepted fix): placeholders all round.
        let rows = page_rows(
            Page::BackToStart,
            None,
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            2,
            true,
        );
        assert_eq!(rows[2].as_str(), "TO START");
        assert_eq!(rows[3].as_str(), "HDG  --");
        assert_eq!(rows[4].as_str(), "BRG  --");
        assert_eq!(rows[6].as_str(), "  --");
        assert_eq!(
            page_hero(Page::BackToStart, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        // A stopped runner: the heading goes stale, so HDG and the arrow blank
        // while the bearing (position-only) stays live.
        let nav = nav_east(20, 6.0);
        let stale_s = 21 + trackback::HEADING_STALE_S;
        let rows = page_rows(
            Page::BackToStart,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            Some(&nav),
            stale_s,
            true,
        );
        assert_eq!(rows[3].as_str(), "HDG  --");
        assert_eq!(rows[4].as_str(), "BRG  W");
        assert_eq!(rows[6].as_str(), "  --");
    }

    #[test]
    fn back_to_start_text_keeps_clear_of_the_map_region() {
        // Rows 3-7 share the screen with the breadcrumb map (right of
        // TRACKBACK_TEXT_COLS) and the arrow; their text must stay inside the
        // reserved columns in every state.
        let rec = snapshot(RecordState::Recording, 100.0);
        let mut extreme = nav_east(20, 6.0);
        extreme.distance_to_start_m = 20_000_000.0;
        for nav in [None, Some(&extreme)] {
            for uptime_s in [2, 20, 21 + trackback::HEADING_STALE_S] {
                let rows = page_rows(
                    Page::BackToStart,
                    Some(&fix()),
                    None,
                    Some(&rec),
                    None,
                    NavView::NoCourse,
                    nav,
                    uptime_s,
                    true,
                );
                for row in &rows[3..8] {
                    assert!(
                        row.len() <= TRACKBACK_TEXT_COLS,
                        "nav row collides with the map: {:?}",
                        row
                    );
                }
                for row in &rows {
                    assert!(row.len() <= COLS, "nav row too wide: {:?}", row);
                }
            }
        }
        // The km hero clamps like the distance glance's.
        assert_eq!(
            page_hero(Page::BackToStart, None, Some(&rec), Some(&extreme))
                .unwrap()
                .as_str(),
            "9999.99"
        );
    }

    #[test]
    fn cutoff_glance_shows_the_next_cutoff_verdict_and_eta() {
        let mut rec = snapshot(RecordState::Recording, 15_000.0);
        rec.cutoff = Some(crate::cutoff_eta::CutoffEta {
            has_cutoff: true,
            distance_to_m: 10_000.0,
            projected_arrival_elapsed_s: Some(5_400),
            margin_s: Some(1_800),
            status: crate::cutoff_eta::CutoffEtaStatus::On,
        });
        let rows = page_rows(
            Page::CutoffEta,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        // Hero: the margin as a signed split, `+` = slack to the cutoff.
        assert_eq!(
            page_hero(Page::CutoffEta, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "+30:00"
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "CUTOFF        ON");
        assert_eq!(rows[4].as_str(), "TO   10.00 KM");
        assert_eq!(rows[5].as_str(), "ETA  1:30:00");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        assert!(
            page_icons(Page::CutoffEta, Some(&fix()), None, Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn cutoff_glance_honest_inactive_states() {
        // No legs loaded: honest "no cutoffs" with the how-to hint.
        let rec = snapshot(RecordState::Recording, 500.0);
        let rows = page_rows(
            Page::CutoffEta,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "CUTOFF --");
        assert_eq!(rows[4].as_str(), "NO CUTOFFS");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(
            page_hero(Page::CutoffEta, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );

        // Past the last cutoff: distinct message, still no fabricated time.
        let mut past = snapshot(RecordState::Recording, 500.0);
        past.cutoff = Some(crate::cutoff_eta::CutoffEta {
            has_cutoff: false,
            distance_to_m: 0.0,
            projected_arrival_elapsed_s: None,
            margin_s: None,
            status: crate::cutoff_eta::CutoffEtaStatus::Unknown,
        });
        let rows = page_rows(
            Page::CutoffEta,
            Some(&fix()),
            None,
            Some(&past),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[4].as_str(), "NO CUTOFF AHEAD");
    }

    #[test]
    fn race_predictor_glance_shows_the_ladder_with_confidence_flags() {
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        rec.race_prediction = Some(
            crate::race_predictor::predict_race_ladder(&[crate::race_predictor::Effort {
                distance_m: 5_000.0,
                duration_s: 1_200,
                age_days: 0.0,
            }])
            .unwrap(),
        );
        let rows = page_rows(
            Page::RacePredictor,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "FROM     5.00 KM");
        // 5K off a 5K anchor is exact (1200 s = 20:00); a single effort is
        // thinly sampled, so even the closest rung flags moderate (`?`).
        assert_eq!(rows[3].as_str(), "5K   20:00 ?");
        assert!(rows[4].as_str().starts_with("10K "));
        assert!(rows[5].as_str().starts_with("HALF "));
        // Marathon is >4x the anchor: low confidence, flagged `~`.
        assert!(rows[6].as_str().starts_with("MAR "));
        assert!(rows[6].as_str().ends_with('~'));
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Hero echoes the 10K rung and is a real time, not `--`.
        let hero = page_hero(Page::RacePredictor, None, Some(&rec), None).unwrap();
        assert_ne!(hero.as_str(), "--");
        assert!(page_icons(
            Page::RacePredictor,
            Some(&fix()),
            None,
            Some(&rec),
            42,
            true
        )
        .iter()
        .all(Option::is_none));
    }

    #[test]
    fn race_predictor_glance_blank_until_enough_distance() {
        let rec = snapshot(RecordState::Recording, 500.0);
        let rows = page_rows(
            Page::RacePredictor,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "PREDICT --");
        assert_eq!(rows[4].as_str(), "NEED 1 KM");
        assert_eq!(
            page_hero(Page::RacePredictor, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
    }

    #[test]
    fn training_paces_glance_shows_the_zone_ladder() {
        use crate::record::TrainingPacesView;
        use crate::training_paces::{paces_from_goal_pace, TrainingGender};
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        // A 4:00/km (240 s/km) goal — the same input the core's ordering test uses.
        rec.training_paces = Some(TrainingPacesView {
            goal_pace_s_per_km: 240,
            paces: paces_from_goal_pace(240.0, TrainingGender::None),
        });
        let rows = page_rows(
            Page::TrainingPaces,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "PACES  GOAL 4:00");
        // Zone rows slow → fast, each a `m:ss /KM`.
        assert!(rows[3].as_str().starts_with("EASY  "));
        assert!(rows[3].as_str().ends_with(" /KM"));
        assert!(rows[4].as_str().starts_with("MARA  "));
        assert!(rows[5].as_str().starts_with("TEMPO "));
        assert!(rows[6].as_str().starts_with("INTVL "));
        assert!(rows[7].as_str().starts_with("REP   "));
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Hero echoes the easy pace and is a real time, not `--`.
        let hero = page_hero(Page::TrainingPaces, None, Some(&rec), None).unwrap();
        assert_ne!(hero.as_str(), "--");
        assert!(page_icons(
            Page::TrainingPaces,
            Some(&fix()),
            None,
            Some(&rec),
            42,
            true
        )
        .iter()
        .all(Option::is_none));
    }

    #[test]
    fn training_paces_glance_honest_inactive() {
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let rows = page_rows(
            Page::TrainingPaces,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "PACES --");
        assert_eq!(rows[4].as_str(), "NO GOAL SET");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(
            page_hero(Page::TrainingPaces, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
    }

    #[test]
    fn fitness_glance_shows_vo2_and_recovery() {
        use crate::record::FitnessView;
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        rec.fitness = Some(FitnessView {
            vo2_max: Some(52.0),
            recovery: Some(RecoveryAdvice::SweetSpot),
        });
        let rows = page_rows(
            Page::Fitness,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert_eq!(rows[2].as_str(), "FITNESS    SWEET");
        assert_eq!(rows[4].as_str(), "VO2 MAX  52");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        assert_eq!(
            page_hero(Page::Fitness, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "52"
        );
        assert!(
            page_icons(Page::Fitness, Some(&fix()), None, Some(&rec), 42, true)
                .iter()
                .all(Option::is_none)
        );
    }

    #[test]
    fn fitness_glance_recovery_alone_shows_dash_vo2() {
        use crate::record::FitnessView;
        // A verdict but no VO2 (the phone had load history but no qualifying run)
        // keeps the page active with an honest `--` where the number would be.
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        rec.fitness = Some(FitnessView {
            vo2_max: None,
            recovery: Some(RecoveryAdvice::HeavilyLoaded),
        });
        let rows = page_rows(
            Page::Fitness,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "FITNESS    REST");
        assert_eq!(rows[4].as_str(), "VO2 MAX  --");
        assert_eq!(
            page_hero(Page::Fitness, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
    }

    #[test]
    fn fitness_glance_honest_inactive() {
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let rows = page_rows(
            Page::Fitness,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "FITNESS --");
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(
            page_hero(Page::Fitness, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
    }

    #[test]
    fn elevation_profile_glance_shows_context_and_leaves_the_cell_blank() {
        use crate::record::{ElevProfileView, ELEV_PROFILE_CAP};
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        let mut samples = [0i32; ELEV_PROFILE_CAP];
        samples[..3].copy_from_slice(&[1000, 1100, 1250]);
        rec.elev_profile = ElevProfileView { samples, len: 3 };
        let e = elev(1250.0, 300.0, 50.0);
        let rows = page_rows(
            Page::ElevationProfile,
            Some(&fix()),
            None,
            Some(&rec),
            Some(&e),
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[0].as_str().trim(), "REC");
        // Total ascent / descent from the authoritative accumulator.
        assert_eq!(rows[2].as_str(), "ELEV D+300 D-50");
        // rows 3..8 are left blank for the sparkline pixel layer.
        assert_eq!(rows[3].as_str(), "");
        assert_eq!(rows[7].as_str(), "");
        assert_eq!(rows[8].as_str(), "GPS  8 SATS PERF");
        // Hero echoes the current (latest) altitude, not `--`.
        assert_eq!(
            page_hero(Page::ElevationProfile, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1250"
        );
        assert!(page_icons(
            Page::ElevationProfile,
            Some(&fix()),
            None,
            Some(&rec),
            42,
            true
        )
        .iter()
        .all(Option::is_none));
    }

    #[test]
    fn elevation_profile_glance_without_baro_reading_labels_the_profile() {
        use crate::record::{ElevProfileView, ELEV_PROFILE_CAP};
        // A series banked off GPS altitude, but the baro task published no vert
        // Reading: show the profile, no fabricated D+/D-.
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        let mut samples = [0i32; ELEV_PROFILE_CAP];
        samples[..2].copy_from_slice(&[12, 20]);
        rec.elev_profile = ElevProfileView { samples, len: 2 };
        let rows = page_rows(
            Page::ElevationProfile,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "ELEV PROFILE");
        assert_eq!(
            page_hero(Page::ElevationProfile, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "20"
        );
    }

    #[test]
    fn elevation_profile_glance_honest_inactive() {
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let rows = page_rows(
            Page::ElevationProfile,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[2].as_str(), "ELEV --");
        assert_eq!(rows[4].as_str(), "NO ELEVATION");
        assert_eq!(rows[5].as_str(), "AWAITING BARO");
        assert_eq!(
            page_hero(Page::ElevationProfile, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
    }

    #[test]
    fn synced_summary_glances_render_content_and_empty_states() {
        // Empty state — nothing pushed yet.
        let inactive = snapshot(RecordState::Recording, 5000.0);
        let rows = page_rows(
            Page::Recap,
            Some(&fix()),
            None,
            Some(&inactive),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[2].as_str(), "RECAP --");
        assert_eq!(rows[4].as_str(), "NOT SYNCED");

        // Populated recap.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.recap = Some(crate::record::RecapView {
            runs: 120,
            distance_km: 1500,
            longest_km: 42,
            best_streak_days: 30,
        });
        let rows = page_rows(
            Page::Recap,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert!(
            rows[2].as_str().contains("120 RUNS"),
            "row2 was {:?}",
            rows[2]
        );
        assert!(rows[4].as_str().contains("1500 KM"));

        // Race-day countdown + verdict.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.race_day = Some(crate::record::RaceDayView {
            days_until: 3,
            feasible: 1,
        });
        let rows = page_rows(
            Page::RaceDay,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[4].as_str(), "IN 3 DAYS");
        assert_eq!(rows[5].as_str(), "ON TRACK");

        // PR recency buckets whole days into a human unit.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.pr_recency = Some(crate::record::PrRecencyView { days_ago: 60 });
        let rows = page_rows(
            Page::PrRecency,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[4].as_str(), "2 MONTHS");
    }
}
