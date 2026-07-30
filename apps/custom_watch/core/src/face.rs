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
//!   actually reads on the move: elapsed run time, distance, average pace,
//!   current pace beside its grade-adjusted twin, heart rate, altitude, and
//!   cumulative vert — the ultra headline pair — with a one-line GPS glance
//!   at the bottom. Raw position is
//!   deliberately absent: nobody reads lat/lon mid-ultra, and the fix still
//!   feeds the track, the flash store, and the phone link. Rows keep a fixed
//!   position with a `--` placeholder when a metric is not yet available, so a
//!   glance always finds a value in the same spot rather than a jumping grid.
//!   A page with no body at all takes its wording from [`crate::unfed`] — the
//!   one vocabulary for empty states, so no page invents its own phrase.
//! - **Status face** (idle) — the bench / acquisition view: uptime clock, GPS
//!   status, last-known position, speed, altitude, HR, and vert. This is what
//!   shows before a run starts and while the first fix is being acquired.

use core::fmt::Write;

use crate::alerts::FuelOverdue;
use crate::battery;
use crate::course::NavStatus;
use crate::cutoff_eta::CutoffEtaStatus;
use crate::daylight;
use crate::elevation;
use crate::fitness::RecoveryAdvice;
use crate::fix::Fix;
use crate::gear_wear::GearWearStatus;
use crate::gnss_mode::GnssMode;
use crate::hr_zones::{self, ZoneCutoffs, ZONE_COUNT};
use crate::ice;
use crate::pacer::PaceVerdict;
use crate::page::Page;
use crate::race_phases::RacePhaseIntent;
use crate::race_predictor::{LadderRung, PredictionConfidence};
use crate::record::{RacePhaseView, RecordState, Snapshot};
use crate::roadbook::CutoffStatus;
use crate::trackback::{self, TrackbackView};
use crate::unfed::Unfed;
use crate::workout::{PaceAdherence, WorkoutStepKind};

pub const COLS: usize = 21;

/// The ICE face's title and its two section labels (§358). Consts rather than
/// literals so the const asserts below can pin them inside the row width — a
/// responder-facing line that silently clips is the failure this whole
/// surface exists to avoid.
pub const ICE_TITLE: &str = "ICE / MEDICAL ID";
pub const ICE_CONDITIONS_LABEL: &str = "ALLERGY / CONDITION";
pub const ICE_CONTACT_LABEL: &str = "EMERGENCY CONTACT";

const _: () = {
    assert!(ICE_TITLE.len() <= COLS);
    assert!(ICE_CONDITIONS_LABEL.len() <= COLS);
    assert!(ICE_CONTACT_LABEL.len() <= COLS);
};
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

/// Which idle-face layout is showing: the home face (clock hero + a summary
/// band) or the diagnostics face (the bench acquisition view — LAT/LON/SPD
/// and the seconds clock). BTN4 toggles them while no run is under way; the
/// toggle state lives in the button task, this enum only names the layouts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum IdleView {
    #[default]
    Home,
    Diagnostics,
    /// The ICE / medical-ID card ([`crate::ice`], §358) — what a responder
    /// reads off the wrist. Idle-only, like the other two: a run view's rows
    /// belong to the run.
    Ice,
}

/// The home face's clock hero band: these text rows stay blank in the face
/// and the app draws the generated 32x48 numeral clock into their pixels —
/// the same face-leaves-blank / widget-overlay contract as the Nav panel
/// rows. Three 16 px rows = exactly the numeral height.
pub const CLOCK_HERO_TOP_ROW: usize = 2;
pub const CLOCK_HERO_ROWS: usize = 3;

/// The clock hero text — `HH:MM`, extrapolated to the *current* minute from
/// the last fix's wall clock plus elapsed uptime (fixes can be minutes apart
/// in Expedition mode, and a clock frozen at the fix's minute reads as a hung
/// watch), or the honest `--:--` before any fix carries a clock. Minute
/// resolution on purpose: the hero must never owe the panel a redraw per
/// second. Local time when a settings push has carried the phone's timezone
/// offset (`tz_offset_min`, minutes east of UTC — wraps across midnight in
/// both directions), UTC until then; the summary row's label says which.
pub type ClockText = heapless::String<5>;

pub fn home_clock_text(fix: Option<&Fix>, uptime_s: u32, tz_offset_min: Option<i16>) -> ClockText {
    let mut t = ClockText::new();
    match fix.and_then(|f| f.time_of_day.map(|tod| (tod, f.uptime_s))) {
        Some((tod, at)) => {
            let utc = (tod + uptime_s.saturating_sub(at)) % 86_400;
            let s =
                (utc as i32 + i32::from(tz_offset_min.unwrap_or(0)) * 60).rem_euclid(86_400) as u32;
            let _ = write!(t, "{:02}:{:02}", s / 3600, s / 60 % 60);
        }
        None => {
            let _ = write!(t, "--:--");
        }
    }
    t
}

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

/// The row a run view's standing markers ride — the blank lower half of the
/// hero band. Row 1 keeps them clear of the row-0 state tag and of every metric
/// row (2..8), and the hero digits sit to their left.
pub const RUN_MARKER_ROW: usize = 1;

/// The short right-anchored tag for a standing [`FuelOverdue`], or `None` when
/// nothing is overdue. A plain 1x tag — deliberately NOT the transient 2x
/// "! DRINK" banner treatment — kept `<= 5` cells so it sits at the panel's
/// right edge past the hero. The DK has no haptics, so this lingering tag is the
/// only way a heads-down runner learns a fuel reminder fired after its banner
/// expired.
pub fn fuel_overdue_tag(overdue: FuelOverdue) -> Option<&'static str> {
    match overdue {
        FuelOverdue::None => None,
        FuelOverdue::Drink => Some("DRINK"),
        FuelOverdue::Eat => Some("EAT"),
        FuelOverdue::Both => Some("D+E"),
    }
}

/// The standing marker a run view carries this frame, or `None` for none.
///
/// Two conditions want the one marker row, so the precedence is stated rather
/// than left to call order: **a critical cell outranks a fuel reminder, and a
/// fuel reminder outranks a merely low one.** A sip can wait a kilometre; a
/// watch that dies ends the recording, and the runner's remedy (drop to
/// Expedition at the next stop, reach the power bank in the drop bag) needs
/// lead time. Below [`battery::LOW_PCT`] but above critical the fuel state is
/// the more actionable of the two, and the battery tag returns the moment the
/// reminder is acknowledged.
///
/// A `None` percent — no plausible cell, the honest absent state the battery
/// task publishes on the USB-powered DK — contributes nothing, exactly as it
/// does on the idle faces.
///
/// The battery form is a bare `12%`, not `BAT 12%`. Three cells is what
/// survives the hero this marker most needs to sit beside: an elapsed time past
/// 100 hours is nine glyphs, eighteen of the panel's twenty-one cells, and a
/// seven-cell tag would be refused for clearance exactly on the multi-day runs
/// where the cell is the thing at stake. Unambiguous where it sits — the only
/// other tenants of this row are words.
pub fn run_marker(overdue: FuelOverdue, battery: Option<u8>) -> Option<Row> {
    let mut row = Row::new();
    let battery_tag = |pct: u8, row: &mut Row| {
        let _ = write!(row, "{}%", pct.min(100));
    };
    match (battery, fuel_overdue_tag(overdue)) {
        (Some(pct), _) if battery::is_critical(pct) => battery_tag(pct, &mut row),
        (_, Some(tag)) => {
            let _ = write!(row, "{tag}");
        }
        (Some(pct), None) if battery::is_low(pct) => battery_tag(pct, &mut row),
        _ => return None,
    }
    Some(row)
}

/// Overlay the run view's standing marker onto an already-rendered page by
/// writing it right-anchored into [`RUN_MARKER_ROW`]. Writing it into the row
/// text (rather than a separate framebuffer blit) keeps the dirty-line flush
/// honest — a steady marker re-emits identical bytes, so a resting page still
/// flushes zero SPI.
///
/// `hero_cells` is how far across the marker row the hero band's pixels reach
/// this frame ([`crate::ui_frame::hero_row_cells`]). The hero is drawn *after*
/// the text rows and composes its span from scratch, so anything it overlaps is
/// erased — and a marker half-eaten from the left is worse than none: `DRINK`
/// clipped to `INK` reads as neither a word nor an absence. So the marker
/// refuses when it would not clear the hero, the same refuse-rather-than-
/// truncate rule [`write_tag`] follows. That case is real, not theoretical: a
/// 100-hour dashboard hero is nine glyphs, eighteen of the twenty-one cells,
/// which the three-cell battery form clears and the five-cell fuel tag does not
/// — the fuel reminder still gets its transient banner, and this row is only
/// its standing backstop.
///
/// Also a no-op on the Nav page (whose map panel owns that row) or when the row
/// is already occupied, so it can only ever add a glance, never clobber a metric
/// or the map.
pub fn apply_run_marker(
    rows: &mut [Row; ROWS],
    page: Page,
    overdue: FuelOverdue,
    battery: Option<u8>,
    hero_cells: usize,
) {
    if page == Page::Nav {
        return;
    }
    let Some(tag) = run_marker(overdue, battery) else {
        return;
    };
    let row = &mut rows[RUN_MARKER_ROW];
    if !row.is_empty() || hero_cells + tag.len() > COLS {
        return;
    }
    let _ = write!(row, "{:>width$}", tag, width = COLS);
}

/// Blank any hero-band row whose text the hero's own glyphs would overwrite,
/// given the rows the band covers and how far across them it reaches
/// ([`crate::ui_frame::hero_band_rows`] + [`crate::ui_frame::hero_row_cells`]).
///
/// The band's only text tenant is a right-anchored tag or marker
/// (`every_page_leaves_its_hero_band_blank` asserts nothing else rides there),
/// and the hero is drawn *after* the text rows over exactly its own span — so a
/// hero wide enough to reach the tag eats its leading glyphs and `AUTO` renders
/// as `UTO`, a tag that reads as some other state rather than as a missing one.
/// That is precisely what [`write_tag`]'s refuse-rather-than-truncate rule
/// exists to prevent; it simply could not see the hero, which is not row text.
///
/// Not hypothetical: past 100 hours the elapsed hero is nine medium glyphs,
/// eighteen of the twenty-one cells, which leaves three for `REC` and one too
/// few for `AUTO` — on the dashboard, on exactly the multi-day runs where
/// knowing the recorder auto-paused matters most.
pub fn apply_hero_clearance(rows: &mut [Row; ROWS], hero_rows: usize, hero_cells: usize) {
    for row in rows.iter_mut().take(hero_rows) {
        let text = row.as_str();
        let first_ink = text.len() - text.trim_start().len();
        if !text.trim().is_empty() && first_ink < hero_cells {
            row.clear();
        }
    }
}

/// Rows the hero band covers on a page whose body needs row 2 — the 16x32
/// medium numeral face, the same cell size as the doubled text font.
pub const HERO_BAND_ROWS: usize = 2;

/// Rows the hero band covers on a page whose body leaves row 2 free — the
/// 32x48 numeral face, half again as tall.
pub const TALL_HERO_BAND_ROWS: usize = 3;

/// The first row `page`'s own text may write: everything above it belongs to
/// the hero band (or, on [`Page::Nav`], to nothing — that page owns its whole
/// grid and draws its title on row 0).
///
/// Three rows buys the 32x48 numeral face over the 16x32 medium one, which is
/// the difference between a number a rested runner reads and one a runner at
/// hour 60 reads by headlamp. Which pages can afford it is a property of their
/// layout, not a preference: the zones / splits / roadbook / predictor /
/// training-paces pages fill rows 3..7 with a ladder, the pacer and
/// back-to-start pages label row 3, and the fuel / gear / elevation pages hand
/// row 3 (or rows 3..8) to a `watch_render` overlay — so on all of those, row 2
/// is the only row their header can have. The rest give it up, and their
/// header moves down to row 3 alongside the state tag, which is where the
/// Distance / Pace glances have carried theirs since § 292.
///
/// Matched exhaustively so a new page cannot compile until it is classified,
/// and pinned against the builders by `every_page_leaves_its_hero_band_blank`
/// — a page cannot claim three rows and then write into them.
pub fn body_top_row(page: Page) -> usize {
    match page {
        // The map panel owns rows 1..6 and the title rides row 0.
        Page::Nav => 0,
        Page::Distance
        | Page::Pace
        | Page::Lap
        | Page::GuidedRun
        | Page::CutoffEta
        | Page::TrainingLoad
        | Page::DistanceBand
        | Page::GearWear
        | Page::Fitness
        | Page::Daylight => TALL_HERO_BAND_ROWS,
        Page::Dashboard
        | Page::Zones
        | Page::Splits
        | Page::Pacer
        | Page::Workout
        | Page::RacePredictor
        | Page::Roadbook
        | Page::Fuel
        | Page::ElevationProfile
        | Page::TrainingPaces
        | Page::BackToStart
        | Page::Recap
        | Page::Streaks
        | Page::RunStats
        | Page::PrRecency
        | Page::PlanReplan
        | Page::PlanAdaptive
        | Page::Readiness
        | Page::Goals
        | Page::TurnCue
        | Page::RouteSimplify
        | Page::AutoEffort
        | Page::RouteElev
        | Page::RaceDay
        | Page::Waypoint
        | Page::Climb => HERO_BAND_ROWS,
    }
}

/// Whether `page` gives its hero the three-row band (and therefore the 32x48
/// numeral face, if the value fits it — see [`crate::ui_frame::hero_band`]).
pub fn tall_hero(page: Page) -> bool {
    body_top_row(page) == TALL_HERO_BAND_ROWS
}

/// Cells the widest run-state tag needs. `AUTO` — a genuinely stationary
/// stretch — is the long one; see [`rec_tag`].
pub const TAG_COLS: usize = 4;

/// Whether the run-state tag is drawn this frame: `REC` blinks at ~1 Hz while
/// the face is animating, so a live recording is unmistakable, and every other
/// tag holds steady (an animation the runner cannot act on is a per-second
/// redraw for nothing).
fn tag_shown(tag: &str, uptime_s: u32, animate: bool) -> bool {
    tag != "REC" || !animate || uptime_s.is_multiple_of(2)
}

/// Right-anchor the run-state tag onto `row`, padding out from whatever the
/// row already holds.
///
/// Refuses rather than truncates when the row's own text has taken the cells
/// the tag needs — the [`apply_battery_row`] rule, and here it matters more: a
/// half-written `RE` is not a degraded `REC`, it is a tag that reads as some
/// other state. `the_state_tag_survives_on_every_page` asserts no page ever
/// hits the refusal, so a header that grows into the tag's cells fails the
/// suite instead of silently dropping the recording indicator.
fn write_tag(row: &mut Row, tag: &str) {
    if row.len() + 1 + tag.len() > COLS {
        return;
    }
    let _ = write!(row, "{:>width$}", tag, width = COLS - row.len());
}

/// The run dashboard's field grid, for the hairline dividers `watch_render`
/// rules between its rows: fields start at [`DASH_FIELD_TOP_ROW`] (the rows
/// above are the hero band), the NOW / GAP pace pair shares
/// [`DASH_SPLIT_ROW`], and [`DASH_SPLIT_COL`] is the blank spacer cell
/// between the pair that the vertical rule crosses — kept in lockstep with
/// the row layout in `dashboard()`.
pub const DASH_FIELD_TOP_ROW: usize = 2;
pub const DASH_SPLIT_ROW: usize = 4;
pub const DASH_SPLIT_COL: usize = 10;

/// The blank five cells an iconned row leaves for its 16x16 gutter glyph. Two
/// cells carry the icon; the other three are the gap before the value, so a
/// glyph and a numeral never touch.
const GUTTER: &str = "     ";

/// The bottom row. Every run page ends on the GPS glance, so this is the one
/// row whose meaning is fixed across the whole cycle — which is what lets
/// [`page_icons`] label it with the satellite glyph everywhere instead of each
/// page spelling the word `GPS` in five of its twenty-one cells (§ 361).
pub const GPS_ROW: usize = ROWS - 1;

/// The diagnostics row carrying the numeric battery read-out: the HR row —
/// every diagnostics row is claimed, and this is the one with slack
/// (`HR   152 BPM` is 12 cells, the widest `BAT 100%` tag needs 8, COLS is
/// 21).
pub const BATTERY_ROW: usize = 7;

/// Overlay the diagnostics face's `BAT n%` read-out right-anchored onto
/// [`BATTERY_ROW`] — a post-pass like [`apply_run_marker`], so the battery
/// doesn't thread a parameter through every layout that ignores it. Only the
/// diagnostics view carries the number; the home face (and the run views,
/// which the app gates before calling) get the icon widget the render layer
/// draws instead. No-op when `percent` is `None` (no plausible battery — the
/// honest absent state) or when the row's text would leave no gap before the
/// tag, so it can only ever add a glance, never clobber the HR value.
pub fn apply_battery_row(rows: &mut [Row; ROWS], view: IdleView, percent: Option<u8>) {
    if view != IdleView::Diagnostics {
        return;
    }
    let Some(pct) = percent else {
        return;
    };
    let mut tag: heapless::String<8> = heapless::String::new();
    let _ = write!(tag, "BAT {}%", pct.min(100));
    let row = &mut rows[BATTERY_ROW];
    if !row.is_empty() && row.len() + tag.len() >= COLS {
        return;
    }
    let _ = write!(row, "{:>width$}", tag, width = COLS - row.len());
}

/// The home face row the recovered-run marker rides: the blank breathing row
/// directly under the clock hero band (rows 2-4), so the marker reads as a
/// footnote to the clock and collides with neither the hero nor the HR/ALT
/// summary below it.
pub const PENDING_RUN_ROW: usize = CLOCK_HERO_TOP_ROW + CLOCK_HERO_ROWS;

const _: () = assert!(PENDING_RUN_ROW < ROWS);
const _: () = assert!(PENDING_RUN_ROW != RUN_MARKER_ROW && PENDING_RUN_ROW != BATTERY_ROW);

/// Overlay the home face's recovered-run marker — right-anchored onto
/// [`PENDING_RUN_ROW`], a post-pass like [`apply_run_marker`]. `pending` is how
/// many runs on flash are a mid-run checkpoint the phone has not pulled
/// ([`crate::flash_store::SlotDir::pending_partial_count`]): a brown-out or
/// battery swap mid-ultra leaves the run-so-far on flash, and without this the
/// idle face after one looks exactly like a normal boot, so the runner has no way
/// to know the interrupted run is there to be synced.
///
/// A standing 1x tag, deliberately not a modal or a banner — it must not stand
/// between the runner and the next start. It retires itself as the phone pulls
/// each run. No-op at zero, off the home view (the diagnostics face's rows are
/// all claimed, and it is the bench readout, not the runner's face), and when the
/// row is already occupied, so it can only ever add a glance.
pub fn apply_pending_run_marker(rows: &mut [Row; ROWS], view: IdleView, pending: u8) {
    if view != IdleView::Home || pending == 0 {
        return;
    }
    let row = &mut rows[PENDING_RUN_ROW];
    if !row.is_empty() {
        return;
    }
    // Sized for the widest a u8 count can render (`255 RUNS RECOVERED`, 18
    // cells): a `heapless` write that overruns leaves the piece it managed
    // behind, so a bare count with no label is the failure mode to design out.
    let mut tag: heapless::String<18> = heapless::String::new();
    if pending == 1 {
        let _ = write!(tag, "1 RUN RECOVERED");
    } else {
        let _ = write!(tag, "{} RUNS RECOVERED", pending);
    }
    let _ = write!(row, "{:>width$}", tag, width = COLS);
}

/// Whether the run view is showing — i.e. [`page_rows`] draws a run layout
/// rather than the idle status face. The app keys page-specific drawing (the
/// Nav page's map panel) off the same predicate the layout selection uses.
pub fn run_view(rec: Option<&Snapshot>) -> bool {
    rec.and_then(rec_tag).is_some()
}

/// The run-state tag, from the whole snapshot rather than the raw
/// [`RecordState`]: `Paused` means three different things in the recorder (a
/// manual pause, a speed-derived auto-pause, and the min-move filter's
/// sampling artifact on a slow climb — see [`Snapshot::manual_paused`] and
/// `Recorder::is_moving`), and only the first is a pause the runner must
/// resume by hand. Rendering them all as `PAU` made a power-hiked climb read
/// as "the watch keeps pausing my run" — the tag flickered REC/PAU fix by fix
/// while distance accrued normally. So: `PAU` is manual-only, a genuinely
/// stationary stretch reads `AUTO` (steady — it resumes itself), and the
/// artifact keeps the plain `REC` the run is actually in.
fn rec_tag(snap: &Snapshot) -> Option<&'static str> {
    match snap.state {
        RecordState::Idle => None,
        RecordState::Recording => Some("REC"),
        RecordState::Paused if snap.manual_paused => Some("PAU"),
        RecordState::Paused => {
            if snap.is_moving() {
                Some("REC")
            } else {
                Some("AUTO")
            }
        }
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
#[allow(clippy::too_many_arguments)]
pub fn face_rows(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
    view: IdleView,
    tz_offset_min: Option<i16>,
    ice: Option<&ice::IceCard>,
) -> [Row; ROWS] {
    match rec.and_then(|snap| rec_tag(snap).map(|tag| (snap, tag))) {
        Some((snap, tag)) => dashboard(fix, hr_bpm, snap, tag, elev, uptime_s, true, mode),
        None => status_face(
            fix,
            hr_bpm,
            elev,
            uptime_s,
            mode,
            false,
            view,
            tz_offset_min,
            ice,
        ),
    }
}

/// The icon that sits in each row's left gutter, paired 1:1 with [`face_rows`].
/// The idle status face is all text, so every slot is `None` there. An iconned
/// row leaves its gutter (the first five cells, [`GUTTER`]) blank so the
/// blitted 16x16 glyph never collides with text.
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
    page_icons(Page::Dashboard, fix, hr_bpm, rec, uptime_s, true, mode)
}

/// The elapsed run time for the dashboard's 2x hero band (rows 0-1), or `None`
/// when no run is under way (the idle status face has no hero). The app draws
/// this with the `sharp_mip` framebuffer's `draw_text_2x`; keeping the string
/// here keeps the hero's content host-tested alongside the rest of the face.
pub fn hero_line(rec: Option<&Snapshot>) -> Option<Row> {
    let snap = rec.filter(|snap| rec_tag(snap).is_some())?;
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
    view: IdleView,
    tz_offset_min: Option<i16>,
    ice: Option<&ice::IceCard>,
) -> [Row; ROWS] {
    match rec.and_then(|snap| rec_tag(snap).map(|tag| (snap, tag))) {
        None => status_face(
            fix,
            hr_bpm,
            elev,
            uptime_s,
            mode,
            animate,
            view,
            tz_offset_min,
            ice,
        ),
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
            Page::GuidedRun => guided_run_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Workout => workout_glance(fix, snap, tag, uptime_s, animate, mode),
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
            Page::PlanAdaptive => plan_adaptive_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Readiness => readiness_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Goals => goals_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::TurnCue => turn_cue_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RouteSimplify => route_simplify_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::AutoEffort => auto_effort_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RouteElev => route_elev_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::RaceDay => race_day_glance(fix, snap, tag, uptime_s, animate, mode),
            Page::Daylight => daylight_glance(fix, tag, uptime_s, animate, mode, tz_offset_min),
            Page::Waypoint => waypoint_glance(fix, snap, tb, tag, uptime_s, animate, mode),
            Page::Climb => climb_glance(fix, snap, tag, uptime_s, animate, mode),
        },
    }
}

/// Gutter icons for `page`. `animate` gates the heart pulse + GPS-search cycle.
///
/// Every run page ends on the GPS glance ([`GPS_ROW`]), so the satellite glyph
/// labels that row on all of them rather than only on the dashboard (§ 361).
/// The word `GPS` cost five of twenty-one cells on twenty-one pages to say
/// what the glyph the dashboard already used says in two — and its search-arc
/// frames additionally say *acquiring* without spending a cell on the word.
/// The dashboard's other four icons are its own: it is the only page whose
/// rows are a fixed metric list.
pub fn page_icons(
    page: Page,
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Option<FaceIcon>; ROWS] {
    let mut icons = [None; ROWS];
    // The idle status face is all text — it pairs a spelled-out GPS row with a
    // dedicated MODE row, and has no icon gutter to blit into.
    if rec.and_then(rec_tag).is_none() {
        return icons;
    }
    icons[GPS_ROW] = Some(gps_icon(fix, uptime_s, animate, stale_after_s(mode, true)));
    if page == Page::Dashboard {
        // Rows 0-1 are the 2x time hero (no gutter icon). Row 2 down carry them.
        icons[2] = Some(FaceIcon::Footsteps);
        icons[5] = Some(heart_icon(hr_bpm, uptime_s, animate));
        icons[6] = Some(FaceIcon::Mountain);
        icons[7] = Some(FaceIcon::Vert);
    }
    icons
}

/// The hero string for `page`: elapsed time on the dashboard, the page's
/// headline metric on a glance page (the live BPM on the zones page, `--`
/// without a pulse), or `None` when no run is under way. The Nav page never
/// has a hero — its map panel owns the rows the hero would cover. Which face
/// draws it is [`crate::ui_frame::hero_band`]'s call, off the glyphs the
/// string uses — so a signed hero, whose `+` the numeral faces lack, keeps its
/// sign by staying in the text font. `fix` + `uptime_s` + `tz_offset_min`
/// feed the Daylight countdown, the one hero derived from the clock rather
/// than the snapshot.
#[allow(clippy::too_many_arguments)]
pub fn page_hero(
    page: Page,
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    tb: Option<&TrackbackView>,
    uptime_s: u32,
    tz_offset_min: Option<i16>,
) -> Option<Row> {
    let snap = rec.filter(|snap| rec_tag(snap).is_some())?;
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
        // The guided run's countdown to its own target duration — the number a
        // runner on a scripted coach run glances at; `--` until one is armed.
        Page::GuidedRun => match snap.guided_run {
            Some(v) => split_row(v.remaining_s),
            None => {
                let mut row = Row::new();
                let _ = write!(row, "--");
                row
            }
        },
        // What's left of the active step on its own end axis — the number an
        // interval runner glances at mid-rep; DONE once the workout is, `--`
        // until one is pushed.
        Page::Workout => match snap.workout {
            Some(w) if w.complete => {
                let mut row = Row::new();
                let _ = write!(row, "DONE");
                row
            }
            Some(w) if w.duration_based => split_row(w.remaining_s),
            Some(w) => {
                let mut row = Row::new();
                if w.remaining_m >= 1000 {
                    let _ = write!(
                        row,
                        "{:.2}",
                        (f64::from(w.remaining_m) / 1000.0).min(999.99)
                    );
                } else {
                    let _ = write!(row, "{}", w.remaining_m);
                }
                row
            }
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
                    let _ = write!(row, "{}:{:02}:{:02}", h.min(999), m, s);
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
        // The countdown to the next sun event as H:MM (floored — the page must
        // never promise light it may not have); `--` while unfed or polar.
        Page::Daylight => {
            let mut row = Row::new();
            match daylight_now(fix, uptime_s, tz_offset_min) {
                Some(daylight::Daylight::Sun(v)) => {
                    let _ = write!(row, "{}:{:02}", v.countdown_min / 60, v.countdown_min % 60);
                }
                _ => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // Distance to the newest mark, in the same m-then-km shape the
        // back-to-start hero uses — the two pages answer the same question
        // about different anchors and must not read differently.
        Page::Waypoint => {
            let mut row = Row::new();
            match snap.waypoint.map(|w| w.distance_m) {
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
        // Metres still to climb when a course names a crest — the ClimbPro
        // headline — falling back to the gain banked in the climb underfoot
        // when there is no course to look ahead down. Both are metres of
        // ascent, so the hero never changes what it means, only where it was
        // measured from; the label row says which.
        Page::Climb => {
            let mut row = Row::new();
            match climb_hero_gain(snap) {
                Some(g) => {
                    let _ = write!(row, "{:.0}", g.clamp(0.0, 99_999.0));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The phone-pushed synced-summary pages headline their number too
        // (§ 361). They had been rows-only, which meant every one of them
        // reserved the two-row hero band ([`body_top_row`]) and then left it
        // blank — a fifth of the panel, at the top, on thirteen pages — while
        // stating its headline in an 8x16 row indistinguishable from the rows
        // contextualising it. Each hero here is the number the page is *about*,
        // and the row that used to carry it is dropped rather than kept as a
        // small copy of the big one.
        Page::Recap => {
            let mut row = Row::new();
            match snap.recap {
                Some(v) => {
                    let _ = write!(row, "{}", v.distance_km);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Streaks => {
            let mut row = Row::new();
            match snap.streaks {
                Some(v) => {
                    let _ = write!(row, "{}", v.current_days.min(9999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::RunStats => match snap.run_stats {
            Some(v) => {
                let (h, m, s) = hms(v.moving_s);
                let mut row = Row::new();
                let _ = write!(row, "{}:{:02}:{:02}", h.min(999), m, s);
                row
            }
            None => {
                let mut row = Row::new();
                let _ = write!(row, "--");
                row
            }
        },
        Page::PrRecency => {
            let mut row = Row::new();
            match snap.pr_recency {
                Some(v) => {
                    let _ = write!(row, "{}", v.days_ago.min(9999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::PlanReplan => {
            let mut row = Row::new();
            match snap.plan_replan {
                Some(v) => {
                    let _ = write!(row, "{}", v.changes);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::PlanAdaptive => {
            let mut row = Row::new();
            match snap.plan_adaptive {
                Some(v) => {
                    let _ = write!(row, "{}", v.changes);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Readiness => {
            let mut row = Row::new();
            match snap.readiness {
                Some(v) => {
                    let _ = write!(row, "{}", v.score.min(100));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::Goals => {
            let mut row = Row::new();
            match snap.goals {
                Some(v) => {
                    let _ = write!(row, "{}", v.percent.min(100));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The distance still to run to the turn — the number that counts down.
        // Its direction is a word, so it stays on the label row.
        Page::TurnCue => {
            let mut row = Row::new();
            match snap.turn_cue {
                Some(v) if v.distance_m >= 1000 => {
                    let _ = write!(row, "{:.2}", f64::from(v.distance_m) / 1000.0);
                }
                Some(v) => {
                    let _ = write!(row, "{}", v.distance_m);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::RouteSimplify => {
            let mut row = Row::new();
            match snap.route_simplify {
                Some(v) => {
                    let _ = write!(row, "{}", v.distance_km);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        Page::AutoEffort => {
            let mut row = Row::new();
            match snap.auto_effort {
                Some(v) => {
                    let _ = write!(row, "{}", v.matched);
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // The course's length, not its climb: the gain / loss pair already has
        // the page's one text row, and rows 3..8 are the drawn profile.
        Page::RouteElev => {
            let mut row = Row::new();
            match snap.route_elev.as_ref() {
                Some(v) => {
                    let km = v.total_m / 1000;
                    if km > 9999 {
                        let _ = write!(row, "9999");
                    } else {
                        let _ = write!(row, "{}.{}", km, (v.total_m % 1000) / 100);
                    }
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
        // Days either side of the race, unsigned — the row below says which
        // side, because a minus sign in front of a countdown reads as a
        // negative number of days rather than as a date already past.
        Page::RaceDay => {
            let mut row = Row::new();
            match snap.race_day {
                Some(v) => {
                    let _ = write!(row, "{}", v.days_until.unsigned_abs().min(9999));
                }
                None => {
                    let _ = write!(row, "--");
                }
            }
            row
        }
    })
}

/// The back-to-start distance, or `None` before the run has a start anchor.
fn trackback_distance(tb: Option<&TrackbackView>) -> Option<f32> {
    tb.filter(|n| n.active()).map(|n| n.distance_to_start_m)
}

/// The unit a sub-kilometre distance is read in, and the one it is read in
/// beyond — the same threshold [`page_hero`] switches its own formatting at, so
/// the unit and the number it labels can never disagree about scale.
fn distance_unit(m: f32) -> &'static str {
    if m < 1000.0 {
        "M"
    } else {
        "KM"
    }
}

/// The unit belonging with `page`'s hero number, drawn at 1x against the hero's
/// own baseline — `None` when the hero needs none (a clock time reads as a
/// time) or when the page has no hero at all.
///
/// The unit cannot simply be appended to the hero string. The numeral faces
/// carry digits, `.`, `:`, `-` and `+` and nothing else, so one letter demotes
/// the whole value to the pixel-doubled text font
/// ([`crate::ui_frame::numeral_hero`]) — which is exactly why these units had
/// drifted down onto the label row, two rows under the number they measure,
/// leaving a bare `0.08` over a `DISTANCE  KM` that reads as a heading rather
/// than as this number's unit. Returning it separately lets the app keep the
/// numeral face *and* keep the unit with its number
/// ([`crate::ui_frame::hero_unit_cell`] places it, § 361).
///
/// Whether it is actually drawn is the app's call, gated on
/// [`crate::ui_frame::hero_has_value`]: a unit beside a `--` placeholder
/// measures nothing. That gate is one rule for every page rather than each arm
/// here re-deriving its own fed check.
pub fn page_hero_unit(
    page: Page,
    rec: Option<&Snapshot>,
    tb: Option<&TrackbackView>,
) -> Option<&'static str> {
    let snap = rec.filter(|snap| rec_tag(snap).is_some())?;
    match page {
        Page::Distance
        | Page::Splits
        | Page::DistanceBand
        | Page::Roadbook
        | Page::Recap
        | Page::RouteSimplify
        | Page::RouteElev => Some("KM"),
        Page::Pace | Page::TrainingPaces => Some("/KM"),
        Page::Zones => Some("BPM"),
        Page::Streaks | Page::PrRecency | Page::RaceDay => Some("DAYS"),
        Page::Goals => Some("%"),
        Page::TurnCue => snap
            .turn_cue
            .map(|v| distance_unit(f32::from(v.distance_m))),
        // Both are metres of altitude — ascent still to climb, and the run's
        // latest banked sample.
        Page::Climb | Page::ElevationProfile => Some("M"),
        Page::Fuel => Some("G"),
        Page::GearWear => Some("%"),
        Page::BackToStart => trackback_distance(tb).map(distance_unit),
        Page::Waypoint => snap.waypoint.map(|w| distance_unit(w.distance_m)),
        // A duration step's hero is a countdown; only the distance axis has a
        // unit, and only while the workout is still running.
        Page::Workout => snap
            .workout
            .filter(|w| !w.complete && !w.duration_based)
            .map(|w| distance_unit(w.remaining_m as f32)),
        // Times (elapsed, lap, partner delta, cut-off margin, cue countdown,
        // projected race time, daylight countdown, synced moving time) carry
        // their own meaning; the training-load score, the VO2 ceiling, a
        // readiness score, a change count and a segment-match count are
        // dimensionless as shown; Nav has no hero at all.
        Page::Dashboard
        | Page::Lap
        | Page::Pacer
        | Page::GuidedRun
        | Page::CutoffEta
        | Page::RacePredictor
        | Page::TrainingLoad
        | Page::Fitness
        | Page::Daylight
        | Page::Nav
        | Page::RunStats
        | Page::PlanReplan
        | Page::PlanAdaptive
        | Page::Readiness
        | Page::AutoEffort => None,
    }
}

/// The row a glance page's empty-body reason rides, and the row its remedy
/// follows on. Fixed across every page so the wording is always in the same
/// place — the Nav page is the one exception, its map panel owns these rows and
/// it writes the same reason into its own info row.
const UNFED_REASON_ROW: usize = 4;
const UNFED_HINT_ROW: usize = 5;

/// Write a page's empty body: the headline label with the absent-value marker
/// on the page's own header row ([`body_top_row`] — a three-row hero band still
/// owns rows 0-2 when the value is an honest `--`), then the reason and its
/// remedy taken from the one sanctioned vocabulary ([`crate::unfed`]) rather
/// than spelled per page.
fn write_unfed(rows: &mut [Row; ROWS], page: Page, label: &str, why: Unfed) {
    let _ = write!(rows[body_top_row(page)], "{label} --");
    let _ = write!(rows[UNFED_REASON_ROW], "{}", why.reason());
    if let Some(hint) = why.hint() {
        let _ = write!(rows[UNFED_HINT_ROW], "{hint}");
    }
}

#[derive(Clone, Copy)]
enum GlanceMetric {
    Distance,
    Pace,
}

/// A single-metric glance page: the metric up large in the rows-0-2 numeral
/// hero band (drawn by the app from [`page_hero`] via the generated bignum
/// faces), a unit label + the state tag on row 3, then time / the other
/// metric / HR / GPS as 1x context — the "one big number" view for a mid-run
/// glance. The pace glance adds the live grade-adjusted pace under HR, so raw
/// and effort-equivalent pace read together on a hill.
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

    // Rows 0-2 hold the numeral-face hero band (the app draws the single-metric
    // pages' headline from the generated 32x48/16x32 bignum faces — the glance a
    // runner takes at arm's length); the state tag rides the label row's right
    // cells instead, clear of the digits.
    let label = match metric {
        GlanceMetric::Distance => "DISTANCE",
        GlanceMetric::Pace => "AVG PACE",
    };
    let _ = write!(rows[3], "{}", label);
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[3], tag);
    }

    let (h, m, s) = hms(snap.elapsed_s);
    let _ = write!(rows[4], "{:<5}{}:{:02}:{:02}", "TIME", h.min(999), m, s);

    // The metric NOT already up large fills the secondary line.
    match metric {
        GlanceMetric::Distance => {
            write_pace(&mut rows[5], "PACE", snap.avg_pace_s_per_km);
            // Row 7 is otherwise free on the Distance page (the Pace page uses it
            // for GAP): surface an honest notice once the tier-1 flash slot has
            // forced the stored track down to a coarser resolution — the whole
            // run is still kept (decimated, not truncated), and the distance /
            // time above are unaffected.
            if snap.track_thinning > 1 {
                let _ = write!(rows[7], "! TRACK 1/{} RES", snap.track_thinning);
            }
        }
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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The big headline value for a glance page's hero (no unit — the label row
/// carries it): distance to two decimals (one from 1000 km, so the numeral
/// band rounds rather than truncates a four-digit ultra total), or `M:SS`
/// average pace / `--:--`.
fn glance_hero(metric: GlanceMetric, snap: &Snapshot) -> Row {
    let mut row = Row::new();
    match metric {
        GlanceMetric::Distance => {
            let km = (snap.distance_m / 1000.0).min(9999.9);
            if km < 1000.0 {
                let _ = write!(row, "{:.2}", km);
            } else {
                let _ = write!(row, "{:.1}", km);
            }
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

/// The lap glance page: the current lap's running time up large in the
/// rows-0-2 hero (drawn by the app from [`page_hero`] via [`split_row`]), the
/// lap number as the label, then last-lap split / lap distance / HR / GPS as 1x
/// context — what a runner checks right after pressing Lap (or hearing the 1 km
/// auto-lap tick over): which lap am I on, and what did the last one take.
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

    let _ = write!(rows[3], "LAP {}", snap.lap.min(9999));
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[3], tag);
    }

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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The pacer glance page: the virtual-partner delta up large in the rows-0-1
/// hero (drawn by the app from [`page_hero`] via [`signed_split`] — `+` is
/// AHEAD of the partner, `-` is BEHIND, and the verdict word beside the label
/// spells the sign out so it is never ambiguous), then the race pacing-strategy
/// phase in force ([`write_phase_row`]), the goal distance + target time, the
/// projected finish at the current whole-run average (the actual crossing time
/// once finished), the distance delta in metres, and the GPS glance. With no goal
/// configured the page is honestly unfed — never zeros pretending to be on
/// pace.
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    match snap.pacer {
        None => write_unfed(&mut rows, Page::Pacer, "PACER", Unfed::NotSynced),
        Some(status) => {
            let verdict = match status.verdict {
                PaceVerdict::Ahead => "AHEAD",
                PaceVerdict::OnPace => "ON PACE",
                PaceVerdict::Behind => "BEHIND",
            };
            let _ = write!(rows[2], "{:<14}{}", "PACER", verdict);
            write_phase_row(&mut rows[3], snap.race_phase, status.terrain_aware);

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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// Write the race pacing-strategy phase onto the pacer page's one spare row: the
/// intent word — the label [`crate::race_phases`] deliberately doesn't carry —
/// and the phase's target pace, with a `TERR` tag appended when the virtual
/// partner is also terrain-allocated (both fit the 21-cell row, so neither is
/// lost). Without a pushed plan the row keeps the partner's `TERRAIN SPLITS`
/// marker, or reads `PHASE --`: an unfed phase says so instead of leaving a blank
/// a runner could read as "no phase change due".
fn write_phase_row(row: &mut Row, phase: Option<RacePhaseView>, terrain_aware: bool) {
    let Some(v) = phase else {
        let _ = write!(
            row,
            "{}",
            if terrain_aware {
                "TERRAIN SPLITS"
            } else {
                "PHASE --"
            }
        );
        return;
    };
    let intent = match v.intent {
        RacePhaseIntent::HoldBack => "HOLD",
        RacePhaseIntent::Settle => "SETTLE",
        RacePhaseIntent::Race => "RACE",
        RacePhaseIntent::Even => "EVEN",
    };
    match v.target_pace_s_per_km {
        Some(pace) => {
            let (m, s) = ((pace / 60).min(99), pace % 60);
            let _ = write!(row, "{intent:<7}{m}:{s:02} /KM");
        }
        None => {
            let _ = write!(row, "{intent:<7}--");
        }
    }
    if terrain_aware {
        let _ = write!(row, " TERR");
    }
}

/// The GuidedRun glance: the armed scripted coach run
/// ([`crate::guided_runs`]) — its target duration, which cue the elapsed time
/// has reached, and the countdown to the next one, over a hero holding the time
/// left in the run.
///
/// The cue's own line is NOT shown: the watch carries cue text as i18n key
/// identifiers, never prose (see the [`crate::guided_runs`] module docs), and it
/// has no voice. The wrist reads the schedule; the phone speaks the line.
#[allow(clippy::too_many_arguments)]
fn guided_run_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    match snap.guided_run {
        None => write_unfed(&mut rows, Page::GuidedRun, "GUIDED", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(
                rows[3],
                "{:<8}{} MIN",
                "GUIDED",
                (v.duration_s / 60).min(999)
            );
            let _ = write!(rows[4], "{:<8}{}/{}", "CUE", v.cue_index, v.cue_count);
            match v.next_cue_in_s {
                Some(s) => {
                    let _ = write!(rows[5], "{:<8}{}", "NEXT", split_row(s).as_str());
                }
                None => {
                    let _ = write!(rows[5], "{:<8}LAST CUE", "NEXT");
                }
            }
            let _ = write!(
                rows[6],
                "{:<8}{}",
                "LEFT",
                split_row(v.remaining_s).as_str()
            );
        }
    }
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::GuidedRun)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The step's identity word: `WARMUP`, `REP 2/6`, `RECOVERY 2/5`, `WALK 2/7`,
/// `STEADY`, `COOLDOWN` — the face's rendering of the identifier-only kind +
/// rep numbering the [`crate::workout`] core carries (no prose on the wire).
fn write_workout_step_label(row: &mut Row, kind: WorkoutStepKind, rep_index: u8, rep_total: u8) {
    let word = match kind {
        WorkoutStepKind::Warmup => "WARMUP",
        WorkoutStepKind::Rep => "REP",
        WorkoutStepKind::Recovery => "RECOVERY",
        WorkoutStepKind::Walk => "WALK",
        WorkoutStepKind::Steady => "STEADY",
        WorkoutStepKind::Cooldown => "COOLDOWN",
    };
    if rep_total > 0 {
        let _ = write!(row, "{word} {rep_index}/{rep_total}");
    } else {
        let _ = write!(row, "{word}");
    }
}

/// The step's target on its end axis plus its pace: `400 M @ 4:00` or
/// `1:30 @ 7:00`.
fn write_workout_target(row: &mut Row, w: &crate::workout::WorkoutView) {
    if w.duration_based {
        let _ = write!(
            row,
            "{}",
            split_row(u32::from(w.target_duration_s)).as_str()
        );
    } else if w.target_distance_m >= 1000 {
        let _ = write!(
            row,
            "{:.2} KM",
            (f64::from(w.target_distance_m) / 1000.0).min(999.99)
        );
    } else {
        let _ = write!(row, "{} M", w.target_distance_m);
    }
    let pace = u32::from(w.target_pace_s_per_km);
    let _ = write!(row, " @ {}:{:02}", (pace / 60).min(99), pace % 60);
}

/// The Workout glance: the active step of the pushed structured workout
/// ([`crate::workout`]) — its identity, target, live progress, whole-step pace
/// against the target band, and the step that follows — over a hero holding
/// what's left of the step on its own end axis. A finished workout reads DONE
/// with the ≥80 % roll-up verdict; unarmed reads the honest inactive state.
/// The adherence words reuse the pace-band alert's TOO FAST / TOO SLOW
/// vocabulary so the two surfaces can't disagree about what "off pace" means.
#[allow(clippy::too_many_arguments)]
fn workout_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    match snap.workout {
        None => write_unfed(&mut rows, Page::Workout, "WORKOUT", Unfed::NotSynced),
        Some(w) if w.complete => {
            let _ = write!(rows[2], "WORKOUT");
            let _ = write!(rows[4], "WORKOUT DONE");
            let _ = write!(
                rows[5],
                "{}",
                match w.rollup {
                    Some(crate::workout::WorkoutAdherence::Completed) => "TARGETS HIT",
                    _ => "PARTIAL",
                }
            );
            let _ = write!(rows[7], "{:<5}{}/{}", "STEP", w.step_total, w.step_total);
        }
        Some(w) => {
            write_workout_step_label(&mut rows[2], w.kind, w.rep_index, w.rep_total);
            let _ = write!(rows[3], "{:<5}", "TGT");
            write_workout_target(&mut rows[3], &w);
            let _ = write!(rows[4], "{:<5}", "GONE");
            if w.duration_based {
                let _ = write!(rows[4], "{}", split_row(w.step_elapsed_s).as_str());
            } else {
                let _ = write!(rows[4], "{} M", w.step_distance_m.min(999_999));
            }
            let _ = write!(rows[4], "  {}%", u32::from(w.progress_permille) / 10);
            let _ = write!(rows[5], "{:<5}", "PACE");
            match w.step_pace_s_per_km {
                Some(p) => {
                    let _ = write!(rows[5], "{}:{:02}", (p / 60).min(99), p % 60);
                }
                None => {
                    let _ = write!(rows[5], "--");
                }
            }
            let _ = write!(
                rows[5],
                "  {}",
                match w.adherence {
                    PaceAdherence::OnPace => "ON PACE",
                    PaceAdherence::Ahead => "AHEAD",
                    PaceAdherence::Behind => "BEHIND",
                    PaceAdherence::WayAhead => "TOO FAST",
                    PaceAdherence::WayBehind => "TOO SLOW",
                }
            );
            match w.next {
                Some(n) => {
                    let _ = write!(rows[6], "{:<5}", "NEXT");
                    // Un-numbered on purpose: RECOVERY 2/5 + an amount
                    // overflows the row, and the numbering arrives with the
                    // step's own banner + header when it becomes current.
                    write_workout_step_label(&mut rows[6], n.kind, 0, 0);
                    if n.target_duration_s > 0 {
                        let _ = write!(
                            rows[6],
                            " {}",
                            split_row(u32::from(n.target_duration_s)).as_str()
                        );
                    } else if n.target_distance_m >= 1000 {
                        let _ = write!(
                            rows[6],
                            " {:.1}K",
                            (f64::from(n.target_distance_m) / 1000.0).min(999.9)
                        );
                    } else {
                        let _ = write!(rows[6], " {} M", n.target_distance_m);
                    }
                }
                None => {
                    let _ = write!(rows[6], "LAST STEP");
                }
            }
            let _ = write!(
                rows[7],
                "{:<5}{}/{}",
                "STEP",
                w.step_index + 1,
                w.step_total
            );
        }
    }
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::Workout)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
        let _ = write!(row, "{:<5}{}:{:02}:{:02} {}", label, h.min(999), m, s, flag);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    match &snap.race_prediction {
        None => write_unfed(&mut rows, Page::RacePredictor, "PREDICT", Unfed::NeedOneKm),
        Some(pred) => {
            let from_km = (pred.anchor.distance_m / 1000.0).min(9999.99);
            let _ = write!(rows[2], "{:<9}{:.2} KM", "FROM", from_km);
            const LABELS: [&str; 4] = ["5K", "10K", "HALF", "MAR"];
            for (i, rung) in pred.rungs.iter().enumerate() {
                pred_row(&mut rows[3 + i], LABELS[i], rung);
            }
        }
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The cut-off ETA glance page: the margin to the next cut-off up large in the
/// rows-0-2 hero (drawn by [`page_hero`] via [`signed_split`] — `+` slack, `-`
/// over the limit), then the verdict word, the distance to the cut-off, and the
/// projected arrival clock, then the flat pace still needed to make it. Honest
/// inactive states: unfed when no course cut-offs are loaded, "NO CUTOFF AHEAD"
/// once past the last one, a `--` ETA when the fix is too stale (or the pace too
/// uncertain) to project, and a `--` NEED when the cutoff is under 50 m out or
/// its limit has already passed.
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

    match snap.cutoff {
        None => write_unfed(&mut rows, Page::CutoffEta, "CUTOFF", Unfed::NotSynced),
        Some(eta) if !eta.has_cutoff => {
            write_unfed(&mut rows, Page::CutoffEta, "CUTOFF", Unfed::NoCutoffAhead)
        }
        Some(eta) => {
            let verdict = match eta.status {
                CutoffEtaStatus::On => "ON",
                CutoffEtaStatus::Tight => "TIGHT",
                CutoffEtaStatus::Behind => "BEHIND",
                CutoffEtaStatus::Unknown => "--",
            };
            // The verdict sits one gap past the label rather than out at column
            // 14: the header row now shares its right cells with the state tag.
            let _ = write!(rows[3], "{:<8}{}", "CUTOFF", verdict);

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

            // Independent of recent pace, so it stays readable when the ETA is
            // withheld; `--` also covers "the limit has already passed".
            write_pace(
                &mut rows[6],
                "NEED",
                eta.required_pace_s_per_km.map(|p| libm::round(p) as u32),
            );
        }
    }
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::CutoffEta)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    // The pace-distribution histogram fills rows 3..8 as pixel bars the app
    // draws (`render::widgets::draw_splits_overlay`, slowest bucket left →
    // fastest right); this labels the axis and leaves those rows blank for it.
    let _ = write!(rows[2], "PACE DIST  SLOW>FAST");

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The training-load glance: this run's single-run stress up large in the hero
/// (drawn by [`page_hero`]), with the distance + moving time it is derived
/// from. The rolling CTL/ATL/TSB needs multi-day history the watch doesn't
/// hold, so the ROLLING row carries the same unfed wording as a whole unfed
/// page rather than a fabricated trend. "NEED DISTANCE" until the run accrues
/// some.
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

    match snap.training_stress {
        None => write_unfed(&mut rows, Page::TrainingLoad, "LOAD", Unfed::NeedDistance),
        Some(_) => {
            // The stress model, honestly labelled: TRIMP only when the synced
            // HR pair + a live average actually scored it (the web chart's
            // "HR-based" vs "volume-based" split).
            let model = if snap.training_stress_trimp {
                "TRIMP"
            } else {
                "DIST"
            };
            let _ = write!(rows[3], "{:<7}{}", "LOAD", model);
            let km = (snap.distance_m / 1000.0).min(9999.99);
            let _ = write!(rows[4], "{:<7}{:.2} KM", "DIST", km);
            let (h, m, s) = hms(snap.moving_s);
            let _ = write!(rows[5], "{:<7}{}:{:02}:{:02}", "MOVING", h.min(999), m, s);
            match snap.load_trend {
                None => {
                    let _ = write!(rows[6], "{:<8}{}", "ROLLING", Unfed::NotSynced.reason());
                }
                Some(t) => {
                    let clamp = |x: f32| (x.max(0.0) as u32).min(999);
                    let _ = write!(rows[6], "CTL {:<4}ATL {}", clamp(t.ctl), clamp(t.atl));
                    let tsb = (t.tsb as i32).clamp(-999, 999);
                    let _ = write!(rows[7], "{:<7}{:+}", "FORM", tsb);
                }
            }
        }
    }
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::TrainingLoad)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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

    let km = (snap.distance_m / 1000.0).min(9999.99);
    match snap.band {
        None => {
            write_unfed(&mut rows, Page::DistanceBand, "BAND", Unfed::NoRaceBand);
            let _ = write!(rows[5], "{:<6}{:.2} KM", "DIST", km);
        }
        Some(b) => {
            // The ported catalogue spells its labels for the web ("Marathon");
            // every other word on this panel is upper case, so the face raises
            // them here rather than diverging the shared table.
            let _ = write!(rows[3], "{:<6}", "BAND");
            for c in b.label.chars() {
                let _ = rows[3].push(c.to_ascii_uppercase());
            }
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::DistanceBand)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
/// checkpoint's distance rides the hero. Unfed until a roadbook is pushed.
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

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    match &snap.roadbook {
        None => write_unfed(&mut rows, Page::Roadbook, "ROADBOOK", Unfed::NotSynced),
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
                    h.min(999),
                    m,
                    s,
                    cutoff_flag(leg.cutoff)
                );
            }
        }
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The fuel glance: the carbs to carry to the next aid up large in the hero,
/// with the fluid to carry and the whole-plan totals. Unfed without a roadbook;
/// "LAST AID PASSED" once past the final refill.
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

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    match &snap.fuel {
        None => write_unfed(&mut rows, Page::Fuel, "FUEL", Unfed::NotSynced),
        Some(f) => {
            let _ = write!(rows[2], "FUEL  TO NEXT AID");
            match f.carry {
                Some(c) => {
                    let _ = write!(rows[4], "{:<7}{} G", "CARB", (c.carbs_g as u32).min(9999));
                    let _ = write!(rows[5], "{:<7}{} ML", "FLUID", (c.fluid_ml as u32));
                }
                None => {
                    let _ = write!(rows[4], "{:<7}--", "CARB");
                    let _ = write!(rows[5], "{}", Unfed::LastAidPassed.reason());
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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The gear-wear glance: the active shoe's wear percent up large in the hero,
/// the OK/DUE/WORN verdict beside the label, and the accumulated distance vs
/// its target. Unfed until the phone pushes the active shoe.
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

    match snap.gear {
        None => write_unfed(&mut rows, Page::GearWear, "GEAR", Unfed::NotSynced),
        Some(g) => {
            let word = match g.status {
                GearWearStatus::Untracked => "UNTRACKED",
                GearWearStatus::Ok => "OK",
                GearWearStatus::Due => "DUE",
                GearWearStatus::Worn => "WORN",
            };
            // One gap past the label, not out at column 11: the header row now
            // shares its right cells with the state tag.
            let _ = write!(rows[3], "{:<6}{}", "GEAR", word);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::GearWear)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
/// Unfed until a goal pace is synced.
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

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    match snap.training_paces {
        None => write_unfed(&mut rows, Page::TrainingPaces, "PACES", Unfed::NotSynced),
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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
/// Unfed until the phone pushes a snapshot.
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

    match snap.fitness {
        None => write_unfed(&mut rows, Page::Fitness, "FITNESS", Unfed::NotSynced),
        Some(f) => {
            let word = f.recovery.map(recovery_word).unwrap_or("--");
            // One gap past the label, not out at column 11: the header row now
            // shares its right cells with the state tag.
            let _ = write!(rows[3], "{:<8}{}", "FITNESS", word);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::Fitness)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The Daylight page's model answer for *now*, or `None` while an input is
/// missing: the synced timezone first (without it the countdown runs against
/// the wrong midnight), then a fix carrying the RMC clock + date. The two
/// absences render differently ([`Unfed::NotSynced`] vs [`Unfed::AwaitingFix`])
/// so the glance body asks in that order too.
fn daylight_now(
    fix: Option<&Fix>,
    uptime_s: u32,
    tz_offset_min: Option<i16>,
) -> Option<daylight::Daylight> {
    let tz = tz_offset_min?;
    let f = fix?;
    Some(daylight::daylight_at(
        f.lat_deg,
        f.time_of_day?,
        f.date?,
        f.uptime_s,
        uptime_s,
        tz,
    ))
}

/// The daylight glance: the countdown to the next sun event up large in the
/// hero, the event's name on the header row, its local clock time and today's
/// day length below. Unfed until the phone syncs a timezone (`NOT SYNCED`) and
/// until a fix carries the RMC clock + date (`AWAITING FIX`); inside a polar
/// season the honest answer is the season itself, not a fabricated clock.
#[allow(clippy::too_many_arguments)]
fn daylight_glance(
    fix: Option<&Fix>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
    tz_offset_min: Option<i16>,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    match daylight_now(fix, uptime_s, tz_offset_min) {
        None if tz_offset_min.is_none() => {
            write_unfed(&mut rows, Page::Daylight, "DAYLIGHT", Unfed::NotSynced)
        }
        None => write_unfed(&mut rows, Page::Daylight, "DAYLIGHT", Unfed::AwaitingFix),
        Some(daylight::Daylight::PolarDay) => {
            write_unfed(&mut rows, Page::Daylight, "DAYLIGHT", Unfed::MidnightSun)
        }
        Some(daylight::Daylight::PolarNight) => {
            write_unfed(&mut rows, Page::Daylight, "DAYLIGHT", Unfed::PolarNight)
        }
        Some(daylight::Daylight::Sun(v)) => {
            let event = match v.event {
                daylight::NextSunEvent::Sunrise => "SUNRISE",
                daylight::NextSunEvent::Sunset => "SUNSET",
            };
            let _ = write!(rows[3], "{event}");
            let _ = write!(
                rows[4],
                "{:<9}{:02}:{:02}",
                "AT",
                v.event_clock_min / 60,
                v.event_clock_min % 60
            );
            let _ = write!(
                rows[5],
                "{:<9}{}:{:02}",
                "DAYLIGHT",
                v.daylight_min / 60,
                v.daylight_min % 60
            );
        }
    }
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[body_top_row(Page::Daylight)], tag);
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The elevation-profile glance: the run's decimated elevation series drawn as
/// a mini-profile sparkline the app paints (`render::widgets::draw_mini_profile`)
/// into rows 3..8, with the total ascent / descent from the baro task's
/// [`elevation::Reading`] as the context row and the current altitude on the
/// hero. "AWAITING BARO" until the first altitude sample lands, so a baro-less
/// (or pre-fix) run reads honestly rather than as a flat sea-level line. The
/// vert totals come from the authoritative accumulator, not the lossy decimated
/// series, so a between-samples peak is never dropped from D+.
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

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    if snap.elev_profile.len == 0 {
        write_unfed(
            &mut rows,
            Page::ElevationProfile,
            "ELEV",
            Unfed::AwaitingBaro,
        );
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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }
    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
}

/// The Recap glance: the synced Year/Month-in-Running totals. Unfed until the
/// phone pushes a summary.
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
        None => write_unfed(&mut rows, Page::Recap, "RECAP", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "{:<7}{} RUNS", "RECAP", v.runs.min(9999));
            let _ = write!(rows[4], "{:<7}{} KM", "LONGEST", v.longest_km.min(9999));
            let _ = write!(
                rows[5],
                "{:<7}{} DAYS",
                "STREAK",
                v.best_streak_days.min(9999)
            );
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
        None => write_unfed(&mut rows, Page::Streaks, "STREAK", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "CURRENT STREAK");
            let _ = write!(rows[4], "{:<7}{} DAYS", "BEST", v.best_days.min(9999));
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
        None => write_unfed(&mut rows, Page::RunStats, "STATS", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "MOVING TIME");
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
        None => write_unfed(&mut rows, Page::PrRecency, "PR AGE", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "PR AGE");
            let d = v.days_ago;
            if d == 0 {
                let _ = write!(rows[4], "TODAY");
            } else if d < 7 {
                // The hero already reads `5 DAYS`; a bucket row would repeat it.
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
        None => write_unfed(&mut rows, Page::PlanReplan, "REPLAN", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "REPLAN CHANGES");
            let _ = write!(rows[4], "{:<8}{}", "MAKE-UP", v.make_ups);
            let _ = write!(rows[5], "{:<8}{}", "EASE-OFF", v.ease_offs);
        }
    }
    rows
}

/// The PlanAdaptive glance: the multi-week adherence trend behind the adaptive
/// re-plan — verdict, flagged weeks over the window, proposed change count, and
/// confidence (or the fatigue hold that withheld a do-more suggestion).
#[allow(clippy::too_many_arguments)]
fn plan_adaptive_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    summary_frame(&mut rows, fix, tag, uptime_s, animate, mode);
    match snap.plan_adaptive {
        None => write_unfed(&mut rows, Page::PlanAdaptive, "ADAPT", Unfed::NotSynced),
        Some(v) => {
            let trend = match v.trend {
                0 => "ON TRACK",
                1 => "DO MORE",
                _ => "EASE OFF",
            };
            let _ = write!(rows[2], "{:<8}{}", "ADAPT", trend);
            let _ = write!(
                rows[4],
                "{:<8}{}/{}",
                "WEEKS", v.flagged_weeks, v.window_weeks
            );
            if v.fitness_gated {
                let _ = write!(rows[5], "HELD FATIGUE");
            } else {
                let conf = match v.confidence {
                    0 => "LOW",
                    1 => "MEDIUM",
                    _ => "HIGH",
                };
                let _ = write!(rows[5], "{:<8}{}", "CONF", conf);
            }
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
        None => write_unfed(&mut rows, Page::Readiness, "READY", Unfed::NotSynced),
        Some(v) => {
            let band = match v.band {
                0 => "LOW",
                1 => "MODERATE",
                _ => "HIGH",
            };
            let _ = write!(rows[2], "READINESS");
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
        None => write_unfed(&mut rows, Page::Goals, "GOAL", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "GOAL");
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
/// to it, and how many cues remain. Unfed until a course is synced.
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
        None => write_unfed(&mut rows, Page::TurnCue, "TURN", Unfed::NotSynced),
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
            let _ = write!(rows[4], "{:<7}{}", "REMAIN", v.remaining);
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
        None => write_unfed(&mut rows, Page::RouteSimplify, "COURSE", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "COURSE LENGTH");
            let _ = write!(rows[4], "{:<7}{}", "POINTS", v.points);
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
        None => write_unfed(&mut rows, Page::AutoEffort, "SEGMENTS", Unfed::NotSynced),
        Some(v) => {
            let _ = write!(rows[2], "SEGMENTS MATCHED");
            let _ = write!(rows[4], "{:<7}{}", "OF", v.considered);
        }
    }
    rows
}

/// The RouteElev glance: the loaded course's climb profile, drawn as a shape the
/// app paints (`render::widgets::draw_route_elev_overlay`) into rows 3..8 with
/// the runner's along-course position marked on it, and the total gain / loss as
/// the context row. Three honest states: unfed with no course loaded,
/// "NO COURSE ELEV" plus the geometry rows and no shape when a course was pushed
/// *without* elevation (never a flat line at zero), and the profile once it
/// carries one.
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
    match snap.route_elev.as_ref() {
        None => write_unfed(&mut rows, Page::RouteElev, "CRS ELEV", Unfed::NotSynced),
        Some(v) if v.len == 0 => {
            write_unfed(
                &mut rows,
                Page::RouteElev,
                "CRS ELEV",
                Unfed::NoCourseElevation,
            );
            let _ = write!(rows[5], "{} PTS", v.points);
        }
        // rows 3..8 are the profile cell the app draws into.
        Some(v) => {
            let _ = write!(rows[2], "CRS D+{} D-{}", v.gain_m, v.loss_m);
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
        None => write_unfed(&mut rows, Page::RaceDay, "RACE", Unfed::NotSynced),
        Some(v) => {
            let d = v.days_until;
            let _ = write!(rows[2], "RACE DAY");
            if d > 0 {
                let _ = write!(rows[4], "TO GO");
            } else if d == 0 {
                let _ = write!(rows[4], "TODAY");
            } else {
                let _ = write!(rows[4], "AGO");
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
    let _ = write!(rows[0], "NAV");
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    let info = &mut rows[NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS];
    match nav {
        NavView::NoCourse => {
            let _ = write!(info, "{}", Unfed::NotSynced.reason());
        }
        NavView::NoFix => {
            let _ = write!(info, "{}", Unfed::AwaitingFix.reason());
        }
        NavView::Status(s) => {
            // Clamps keep the row inside COLS at any input: 999.99 km along +
            // a 9999 m offset is exactly 21 cells.
            let km = (s.along_m / 1000.0).min(999.99);
            let off = (s.off_m as u32).min(9999);
            let _ = write!(info, "{:.2} KM  OFF {} M", km, off);
        }
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    let _ = write!(rows[2], "TO START");

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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The gain the Climb hero shows: what is left to the crest when a course
/// names one, else what has been banked in the climb underfoot. `None` when
/// neither exists — the page is then in its empty state and shows no number.
fn climb_hero_gain(snap: &Snapshot) -> Option<f32> {
    snap.climb
        .ahead
        .map(|a| a.gain_m)
        .or_else(|| snap.climb.active.map(|c| c.gain_m))
}

/// A distance in the unit a climber reads it in: whole metres close in, one
/// decimal of a kilometre once "how many metres" stops being the question.
fn write_climb_distance(row: &mut Row, label: &str, m: f32) {
    if m < 1000.0 {
        let _ = write!(row, "{:<8}{:.0} M", label, m.max(0.0));
    } else {
        let _ = write!(row, "{:<8}{:.1} KM", label, (m / 1000.0).min(9999.9));
    }
}

/// The climb page (§359). The hero is metres of ascent — remaining to the
/// crest when the pushed course names one, banked in the climb underfoot
/// otherwise — and the label row says which, because the same number measured
/// from two different places is only useful if the runner knows where from.
///
/// When both halves have something, the crest block leads and the banked
/// block follows: on a climb, what is left outranks what is done.
fn climb_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    if snap.climb.is_empty() {
        // Settled, not unfed: flat ground with no ascent ahead is a real
        // answer, and it must not read like a sync that never happened.
        write_unfed(&mut rows, Page::Climb, "CLIMB", Unfed::NoClimb);
        write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
        return rows;
    }

    match snap.climb.ahead {
        Some(a) => {
            let _ = write!(rows[2], "TO CREST");
            write_climb_distance(&mut rows[3], "IN", a.distance_m);
            let _ = write!(rows[4], "{:<8}{:.0}%", "GRADE", a.avg_grade_pct);
            if let Some(c) = snap.climb.active {
                let _ = write!(rows[6], "{:<8}{:.0} M", "CLIMBED", c.gain_m.max(0.0));
                write_climb_distance(&mut rows[7], "OVER", c.distance_m);
            }
        }
        None => {
            // No course to look ahead down: the banked gain IS the headline,
            // and the rows describe the climb it came from rather than
            // inventing a crest the watch cannot see.
            let c = snap.climb.active.unwrap_or_default();
            let _ = write!(rows[2], "CLIMBED");
            write_climb_distance(&mut rows[3], "OVER", c.distance_m);
            let _ = write!(rows[4], "{:<8}{:.0}%", "GRADE", c.avg_grade_pct);
        }
    }

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The marked-waypoint page (§357): distance to the NEWEST mark up large,
/// then the same heading / bearing pair [`back_to_start_glance`] shows — the
/// two pages answer "which way, and how far" about different anchors, so they
/// deliberately read the same. The age row is what tells a runner at hour 40
/// whether the mark is this loop's water stash or yesterday's recce, and the
/// count row is the only place the store's depth is visible at all.
///
/// Two honest empty states, and they are NOT the same thing: nothing marked
/// (the runner can fix that with a hold, so the reason carries the gesture),
/// versus marks that exist with no position anchor to measure them from yet.
fn waypoint_glance(
    fix: Option<&Fix>,
    snap: &Snapshot,
    tb: Option<&TrackbackView>,
    tag: &str,
    uptime_s: u32,
    animate: bool,
    mode: GnssMode,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    let Some(w) = snap.waypoint else {
        let why = if snap.waypoint_count == 0 {
            Unfed::NoWaypoints
        } else {
            Unfed::AwaitingFix
        };
        write_unfed(&mut rows, Page::Waypoint, "WAYPOINT", why);
        write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
        return rows;
    };

    let _ = write!(rows[2], "TO WPT");

    match tb.and_then(|n| n.heading_sector(uptime_s)) {
        Some(s) => {
            let _ = write!(
                rows[3],
                "{:<6}{}",
                "HDG",
                trackback::SECTOR_NAMES[s as usize]
            );
        }
        None => {
            let _ = write!(rows[3], "{:<6}--", "HDG");
        }
    }
    let _ = write!(
        rows[4],
        "{:<6}{}",
        "BRG",
        trackback::SECTOR_NAMES[trackback::sector_of_deg(w.bearing_deg) as usize]
    );

    // Clock skew (a mark stamped after `uptime_s`, which a reboot's restarted
    // uptime makes real for a restored mark) saturates to 0 rather than
    // wrapping into a fake multi-century age.
    let (h, m, s) = hms(uptime_s.saturating_sub(w.marked_uptime_s));
    if h > 0 {
        let _ = write!(rows[5], "{:<6}{}:{:02}:{:02}", "AGO", h.min(999), m, s);
    } else {
        let _ = write!(rows[5], "{:<6}{}:{:02}", "AGO", m, s);
    }
    let _ = write!(rows[6], "{:<6}{}", "MARKS", w.count);

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
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
    let mut rows: [Row; ROWS] = Default::default();

    // Rows 0-1 hold the 2x elapsed-time hero (drawn by the app). Only the
    // recording-state tag lives here, pinned top-right clear of the hero digits.
    // Blink it at ~1 Hz for REC so a live recording is unmistakable; PAU / FIN
    // (and any state once `animate` is off) stay steady-on.
    if tag_shown(tag, uptime_s, animate) {
        write_tag(&mut rows[0], tag);
    }

    let km = (snap.distance_m / 1000.0).min(9999.99);
    let _ = write!(rows[2], "{}{:.2} KM", GUTTER, km);

    write_pace(&mut rows[3], "PACE", snap.avg_pace_s_per_km);

    // Current pace pairs with its grade-adjusted twin — the same raw-vs-effort
    // pairing the Pace glance makes, on the page a runner actually lives on
    // mid-climb. Fixed columns (the DASH_SPLIT_COL spacer stays blank for the
    // field grid's vertical rule, GAP right after it), and the /KM the PACE
    // row above carries speaks for all three paces. Worst case fits:
    // "NOW  99:59 GAP 99:59" is 20 cells.
    let _ = write!(rows[DASH_SPLIT_ROW], "{:<5}", "NOW");
    write_pace_value(&mut rows[DASH_SPLIT_ROW], snap.current_pace_s_per_km);
    while rows[DASH_SPLIT_ROW].len() < DASH_SPLIT_COL + 1 {
        let _ = rows[DASH_SPLIT_ROW].push(' ');
    }
    let _ = write!(rows[DASH_SPLIT_ROW], "GAP ");
    write_pace_value(&mut rows[DASH_SPLIT_ROW], snap.gap_s_per_km);

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

    write_gps_row(&mut rows[GPS_ROW], fix, uptime_s, mode);
    rows
}

/// The idle face's title row, shared by both idle views. While `animate` is
/// on (the post-press interaction window — exactly when someone is working
/// the buttons), it shows a BTN3 hint (`B3 MODE/HLD REZERO`), because nothing
/// on the hardware says what the un-labelled DK buttons do. Steady, not
/// alternating with the brand: a 2 s dwell was too short to read. Capped at
/// `COLS - 3` cells — the GPS meter is drawn over the row's last three
/// columns (`SIGNAL_METER_W` in `watch_render::widgets`), and the face
/// contract is to leave overlay cells blank. Outside the window the brand
/// holds steady, keeping the idle face free of per-second redraws.
fn write_idle_title(row: &mut Row, animate: bool) {
    if animate {
        let _ = write!(row, "B3 MODE/HLD REZERO");
    } else {
        let _ = write!(row, "THREKIR");
    }
}

/// The idle face: the home view unless BTN4 has toggled the diagnostics view
/// (see [`IdleView`]). Only the home view takes the timezone offset — the
/// diagnostics view is the bench view, and raw receiver (UTC) time is a
/// feature there.
#[allow(clippy::too_many_arguments)]
fn status_face(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
    animate: bool,
    view: IdleView,
    tz_offset_min: Option<i16>,
    ice: Option<&ice::IceCard>,
) -> [Row; ROWS] {
    match view {
        IdleView::Home => home_face(fix, hr_bpm, elev, uptime_s, mode, animate, tz_offset_min),
        IdleView::Diagnostics => diagnostics_face(fix, hr_bpm, elev, uptime_s, mode, animate),
        IdleView::Ice => ice_face(ice),
    }
}

/// The ICE / medical-ID face (§358): the lines a responder needs off a
/// stranger's wrist, each on its own row under its own label.
///
/// Label-above-value rather than label-and-value sharing 21 cells, because a
/// responder has no context to expand an abbreviation from — `PENICILLIN,
/// ASTHMA` must arrive whole or not at all, and [`crate::ice`] guarantees it
/// fits a row by refusing anything wider at the door. An empty field reads
/// `--` (nothing recorded) rather than a blank row, which would be
/// indistinguishable from a render that failed.
fn ice_face(card: Option<&ice::IceCard>) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    let _ = write!(rows[0], "{}", ICE_TITLE);
    let Some(c) = card.filter(|c| !c.is_blank()) else {
        // No card, or one cleared to blank: say which of the app's sanctioned
        // reasons applies rather than showing five `--` rows, which would read
        // as a runner who declined to answer.
        let _ = write!(rows[2], "{}", Unfed::NotSynced.reason());
        if let Some(hint) = Unfed::NotSynced.hint() {
            let _ = write!(rows[3], "{hint}");
        }
        return rows;
    };
    fn or_dash(s: &str) -> &str {
        if s.is_empty() {
            "--"
        } else {
            s
        }
    }
    let _ = write!(rows[1], "{}", or_dash(c.holder()));
    let _ = write!(rows[2], "{:<6}{}", "BLOOD", or_dash(c.blood()));
    let _ = write!(rows[3], "{}", ICE_CONDITIONS_LABEL);
    let _ = write!(rows[4], "{}", or_dash(c.conditions()));
    let _ = write!(rows[5], "{}", ICE_CONTACT_LABEL);
    let _ = write!(rows[6], "{}", or_dash(c.contact()));
    let _ = write!(rows[7], "{}", or_dash(c.phone()));
    rows
}

/// The home layout — a watch face, not a debug readout (decisions §291): the
/// clock hero band (rows 2-4, drawn by the app from the generated numeral
/// face — this function leaves them blank per the widget-overlay contract),
/// then one summary row (HR + baro-preferred altitude), the GPS glance with
/// the hero's honesty label (LOCAL once a settings push has carried the
/// phone's timezone offset, UTC until then — the label must match what the
/// hero actually shows, so both derive from the same input), and the mode
/// picker's read-out. Everything here is minute-or-slower: the home face at
/// rest owes the panel zero redraws, where the old bench view's seconds row
/// redrew every fix.
#[allow(clippy::too_many_arguments)]
fn home_face(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
    animate: bool,
    tz_offset_min: Option<i16>,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    write_idle_title(&mut rows[0], animate);

    // Rows 1..=5 stay blank: 2..=4 are the clock hero band, 1 and 5 its
    // breathing room.
    let mut hr: heapless::String<10> = heapless::String::new();
    match hr_bpm {
        Some(bpm) => {
            let _ = write!(hr, "HR {} BPM", bpm.min(999));
        }
        None => {
            let _ = write!(hr, "HR --");
        }
    }
    let mut alt: heapless::String<11> = heapless::String::new();
    match elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        Some(alt_m) => {
            let _ = write!(alt, "ALT {:.0} M", alt_m.clamp(-9_999.0, 99_999.0));
        }
        None => {
            let _ = write!(alt, "ALT --");
        }
    }
    let _ = write!(rows[6], "{:<10}{:>11}", hr, alt);

    let mut gps: heapless::String<14> = heapless::String::new();
    let _ = write!(gps, "GPS {}", gps_value(fix, uptime_s, STALE_AFTER_S));
    let zone = if tz_offset_min.is_some() {
        "LOCAL"
    } else {
        "UTC"
    };
    let _ = write!(rows[7], "{:<14}{:>7}", gps, zone);

    write_mode_row(&mut rows[8], mode);
    rows
}

/// The mode picker's read-out — BTN3 cycles the GNSS mode while idle —
/// pairing the mode tag with its battery figure. "EST" marks the figure as an
/// unmeasured estimate, not a guaranteed runtime — the tier-1 bench can't
/// measure power at all, so the number is a tier-2 projection derived in
/// `gnss_mode`. Reading it as a spec ("~220H") would over-promise; "EST 220H"
/// is honest at a glance.
fn write_mode_row(row: &mut Row, mode: GnssMode) {
    let _ = write!(row, "MODE {:<5}EST {}H", mode.label(), mode.battery_est_h());
}

/// The diagnostics layout — the bench acquisition view the idle face was
/// before §291: the selected GNSS mode with its projected hours, GPS status,
/// last-known position, speed, altitude, HR, and the seconds clock (falling
/// back to cumulative vert with no fix). Kept verbatim behind BTN4: bench
/// bring-up still needs raw LAT/LON and a per-fix clock, they just no longer
/// masquerade as the home screen.
fn diagnostics_face(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
    mode: GnssMode,
    animate: bool,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    write_idle_title(&mut rows[0], animate);
    write_mode_row(&mut rows[1], mode);

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

    // Bottom row: the GPS wall clock whenever the fix carries it — else
    // cumulative vert while the baro streams (the bench case: baro without
    // GPS). Vert used to displace the clock here, which left a baro-equipped
    // watch with no time of day at all. Deliberately UTC and unshifted even
    // when a pushed timezone offset is live: this is the bench view, and the
    // raw receiver time is a feature here. Metres clamped to five digits so
    // the row can't overflow COLS.
    match fix.and_then(|f| f.time_of_day) {
        Some(tod) => {
            let (th, tm, ts) = hms(tod);
            let _ = write!(rows[8], "UTC  {:02}:{:02}:{:02}", th, tm, ts);
        }
        None => {
            if let Some(e) = elev {
                let gain = (e.gain_m as u32).min(99_999);
                let loss = (e.loss_m as u32).min(99_999);
                let _ = write!(rows[8], "VERT +{} -{} M", gain, loss);
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

/// Append a bare `M:SS` pace value (or the `--` placeholder) to a row — the
/// unit-less half the dashboard's NOW / GAP pairing writes twice per row.
fn write_pace_value(row: &mut Row, pace_s_per_km: Option<u32>) {
    match pace_s_per_km {
        Some(p) => {
            let _ = write!(row, "{}:{:02}", (p / 60).min(99), p % 60);
        }
        None => {
            let _ = write!(row, "--");
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
///
/// The label is always the blank icon gutter: [`page_icons`] blits the
/// satellite glyph into those cells on every run page, so the row never spells
/// the word (see the § 361 note on [`GPS_ROW`]).
fn write_gps_row(row: &mut Row, fix: Option<&Fix>, uptime_s: u32, mode: GnssMode) {
    let _ = write!(
        row,
        "{GUTTER}{} {}",
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
        super::face_rows(
            fix,
            hr_bpm,
            rec,
            elev,
            uptime_s,
            GnssMode::Performance,
            IdleView::Home,
            None,
            None,
        )
    }

    // The diagnostics idle view (§291) — the pre-§291 idle tests moved here
    // verbatim, since BTN4 keeps that layout reachable unchanged.
    fn diag_rows(
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        elev: Option<&elevation::Reading>,
        uptime_s: u32,
    ) -> [Row; ROWS] {
        super::face_rows(
            fix,
            hr_bpm,
            None,
            elev,
            uptime_s,
            GnssMode::Performance,
            IdleView::Diagnostics,
            None,
            None,
        )
    }

    fn face_icons(
        fix: Option<&Fix>,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        uptime_s: u32,
    ) -> [Option<FaceIcon>; ROWS] {
        super::face_icons(fix, hr_bpm, rec, uptime_s, GnssMode::Performance)
    }

    /// The header row a three-row-hero page renders: its label, then the state
    /// tag right-anchored at the panel edge. Spelled here rather than as a
    /// literal per assertion so the padding can't be miscounted by hand.
    fn header(label: &str, tag: &str) -> Row {
        let mut row = Row::new();
        let _ = write!(row, "{}{:>width$}", label, tag, width = COLS - label.len());
        row
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
            IdleView::Home,
            None,
            None,
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

    fn page_hero(
        page: Page,
        hr_bpm: Option<u16>,
        rec: Option<&Snapshot>,
        tb: Option<&TrackbackView>,
    ) -> Option<Row> {
        super::page_hero(page, Some(&fix()), hr_bpm, rec, tb, 42, None)
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
            date: Some(daylight::Date {
                year: 2026,
                month: 7,
                day: 8,
            }),
            uptime_s: 41,
        }
    }

    fn snapshot(state: RecordState, distance_m: f64) -> Snapshot {
        Snapshot {
            state,
            manual_paused: false,
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
            training_stress_trimp: false,
            load_trend: None,
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
            plan_adaptive: None,
            guided_run: None,
            workout: None,
            readiness: None,
            goals: None,
            turn_cue: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            route_position_permille: None,
            race_day: None,
            race_phase: None,
            climb: Default::default(),
            waypoint: None,
            waypoint_count: 0,
            track_thinning: 1,
            pages_mask: u64::MAX,
            hide_empty_pages: true,
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
        rec.gap_s_per_km = Some(99 * 60 + 59);
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
    fn fuel_overdue_tag_maps_each_state_and_fits_the_slot() {
        assert_eq!(fuel_overdue_tag(FuelOverdue::None), None);
        assert_eq!(fuel_overdue_tag(FuelOverdue::Drink), Some("DRINK"));
        assert_eq!(fuel_overdue_tag(FuelOverdue::Eat), Some("EAT"));
        assert_eq!(fuel_overdue_tag(FuelOverdue::Both), Some("D+E"));
        for o in [FuelOverdue::Drink, FuelOverdue::Eat, FuelOverdue::Both] {
            assert!(fuel_overdue_tag(o).unwrap().chars().count() <= 5);
        }
    }

    #[test]
    fn the_run_marker_shows_the_fuel_tag_only_when_overdue() {
        let snap = snapshot(RecordState::Recording, 4200.0);
        let base = page_rows(
            Page::Dashboard,
            Some(&fix()),
            Some(150),
            Some(&snap),
            None,
            NavView::NoCourse,
            None,
            10,
            false,
        );

        // Nothing overdue -> the page is untouched.
        let mut rows = base.clone();
        apply_run_marker(&mut rows, Page::Dashboard, FuelOverdue::None, None, 0);
        assert_eq!(rows, base);

        // Overdue -> the compact tag lands right-anchored on the marker row and
        // no other row (hero digits, metrics) is disturbed.
        let mut rows = base.clone();
        apply_run_marker(&mut rows, Page::Dashboard, FuelOverdue::Drink, None, 0);
        assert!(rows[RUN_MARKER_ROW].as_str().ends_with("DRINK"));
        assert!(rows[RUN_MARKER_ROW].as_str().starts_with(' '));
        assert!(rows[RUN_MARKER_ROW].len() <= COLS);
        for r in 0..ROWS {
            if r != RUN_MARKER_ROW {
                assert_eq!(rows[r], base[r], "row {r} changed");
            }
        }
    }

    #[test]
    fn the_run_marker_is_a_noop_on_nav_and_over_occupied_rows() {
        let snap = snapshot(RecordState::Recording, 4200.0);
        // Nav page: its map panel owns the marker row, so the marker is skipped.
        let nav = page_rows(
            Page::Nav,
            Some(&fix()),
            None,
            Some(&snap),
            None,
            NavView::NoCourse,
            None,
            10,
            false,
        );
        let mut rows = nav.clone();
        apply_run_marker(&mut rows, Page::Nav, FuelOverdue::Both, Some(5), 0);
        assert_eq!(rows, nav);

        // An occupied marker row is never overwritten.
        let mut rows: [Row; ROWS] = Default::default();
        let _ = write!(rows[RUN_MARKER_ROW], "BUSY");
        let before = rows.clone();
        apply_run_marker(&mut rows, Page::Dashboard, FuelOverdue::Drink, None, 0);
        assert_eq!(rows, before);
    }

    /// A run view carries no battery icon and no BAT row, so before this the
    /// runner could not learn the cell was going without stopping the run.
    #[test]
    fn the_run_marker_states_a_low_battery_and_ranks_a_critical_one_first() {
        let tag = |overdue, battery| {
            run_marker(overdue, battery)
                .map(|r| r.as_str().to_owned())
                .unwrap_or_default()
        };
        // Healthy cell, nothing overdue: no marker at all.
        assert_eq!(tag(FuelOverdue::None, Some(80)), "");
        // No plausible cell (the USB-powered DK) contributes nothing, so the
        // fuel tag still stands alone.
        assert_eq!(tag(FuelOverdue::None, None), "");
        assert_eq!(tag(FuelOverdue::Drink, None), "DRINK");

        assert_eq!(tag(FuelOverdue::None, Some(battery::LOW_PCT)), "20%");
        assert_eq!(tag(FuelOverdue::None, Some(battery::LOW_PCT + 1)), "");

        // A sip can wait a kilometre, so the fuel reminder outranks a low cell —
        // and the battery tag returns as soon as the reminder is acknowledged.
        assert_eq!(tag(FuelOverdue::Eat, Some(battery::LOW_PCT)), "EAT");
        // A dead watch ends the recording, so a critical cell outranks the sip.
        assert_eq!(tag(FuelOverdue::Eat, Some(battery::CRITICAL_PCT)), "10%");
        assert_eq!(tag(FuelOverdue::Both, Some(0)), "0%");

        // The battery form is three cells at its widest, which is what lets it
        // clear a nine-glyph hero. Shown only at or below LOW_PCT, so it can
        // never widen past two digits and a sign.
        for pct in 0..=battery::LOW_PCT {
            assert!(tag(FuelOverdue::None, Some(pct)).len() <= 3, "{pct}");
        }
    }

    /// The hero is drawn over the marker row after the text, composing its span
    /// from scratch — so a marker it overlaps is erased from the left, and
    /// `DRINK` clipped to `INK` is worse than no tag at all. Real at ultra
    /// distances: a 100-hour elapsed hero is nine glyphs, eighteen cells.
    #[test]
    fn the_run_marker_refuses_rather_than_let_the_hero_clip_it() {
        let fits = |overdue, battery, hero_cells| {
            let mut rows: [Row; ROWS] = Default::default();
            apply_run_marker(&mut rows, Page::Dashboard, overdue, battery, hero_cells);
            !rows[RUN_MARKER_ROW].is_empty()
        };
        // "5%" is 2 cells; the hero may run right up to it, since a numeral
        // glyph carries its own side bearing where two text cells would not.
        assert!(fits(FuelOverdue::None, Some(5), COLS - 2));
        assert!(!fits(FuelOverdue::None, Some(5), COLS - 1));
        assert!(!fits(FuelOverdue::None, Some(5), COLS));

        // The case the three-cell battery form exists for: past 100 hours the
        // elapsed hero leaves three cells, which the battery tag clears and the
        // five-cell `DRINK` does not. The fuel reminder still gets its transient
        // banner — this row is only its standing backstop.
        let wide = crate::ui_frame::hero_row_cells(
            crate::ui_frame::HeroBand::MedNumHero,
            "100:05:30",
            None,
        );
        assert_eq!(wide, 18);
        assert!(fits(FuelOverdue::None, Some(12), wide));
        assert!(!fits(FuelOverdue::Drink, None, wide));
    }

    #[test]
    fn the_hero_row_span_follows_the_face_the_band_chose() {
        use crate::ui_frame::{hero_row_cells, HeroBand};
        // A banner owns the whole band, which is the point of a banner.
        assert_eq!(hero_row_cells(HeroBand::AlertBanner, "", None), COLS);
        assert_eq!(hero_row_cells(HeroBand::RezeroBanner, "", None), COLS);
        assert_eq!(hero_row_cells(HeroBand::None, "3:12:05", None), 0);
        // Two cells per doubled character, four per tall-face leading digit.
        assert_eq!(hero_row_cells(HeroBand::MedNumHero, "3:12:05", None), 14);
        assert_eq!(hero_row_cells(HeroBand::TextHero, "3:12:05", None), 14);
        assert_eq!(hero_row_cells(HeroBand::BigNumHero, "32.40", None), 14);
        // The 100-hour dashboard hero that motivated the clearance rule.
        assert_eq!(hero_row_cells(HeroBand::MedNumHero, "100:05:30", None), 18);
        // A two-row face puts the unit on the marker row, so the marker has to
        // clear it too; the three-row face's unit sits a row lower and cannot
        // reach the marker.
        assert_eq!(hero_row_cells(HeroBand::MedNumHero, "152", Some("BPM")), 9);
        assert_eq!(
            hero_row_cells(HeroBand::BigNumHero, "32.40", Some("KM")),
            14
        );
    }

    /// The tag's refuse-rather-than-truncate rule, extended to the one thing it
    /// could not see: the hero, which is drawn after the rows and is not row
    /// text. Past 100 hours the dashboard hero is eighteen of twenty-one cells,
    /// which `REC` clears and `AUTO` does not — so `AUTO` was rendering as
    /// `UTO`, a tag naming a state the recorder is not in.
    #[test]
    fn a_hero_wide_enough_to_reach_the_state_tag_takes_the_whole_tag() {
        use crate::ui_frame::{hero_band_rows, hero_row_cells, HeroBand};
        let band = HeroBand::MedNumHero;
        let rows_covered = hero_band_rows(band);
        let hero = "100:05:30";
        let cells = hero_row_cells(band, hero, None);

        // `AUTO` right-anchors to cell 17, one inside the hero's span.
        let mut rows: [Row; ROWS] = Default::default();
        write_tag(&mut rows[0], "AUTO");
        assert!(rows[0].as_str().ends_with("AUTO"));
        apply_hero_clearance(&mut rows, rows_covered, cells);
        assert_eq!(rows[0].as_str(), "", "a clipped tag names the wrong state");

        // `REC` right-anchors to cell 18 and clears the same hero, so it stays.
        let mut rows: [Row; ROWS] = Default::default();
        write_tag(&mut rows[0], "REC");
        apply_hero_clearance(&mut rows, rows_covered, cells);
        assert!(rows[0].as_str().ends_with("REC"));

        // No hero, no clearance — the band covers nothing.
        let mut rows: [Row; ROWS] = Default::default();
        write_tag(&mut rows[0], "AUTO");
        apply_hero_clearance(&mut rows, hero_band_rows(HeroBand::None), 0);
        assert!(rows[0].as_str().ends_with("AUTO"));

        // Rows below the band are never touched, whatever they hold — a tall
        // page's tag rides its header row, outside the band.
        let mut rows: [Row; ROWS] = Default::default();
        let _ = write!(rows[TALL_HERO_BAND_ROWS], "DISTANCE");
        apply_hero_clearance(&mut rows, hero_band_rows(HeroBand::BigNumHero), COLS);
        assert_eq!(rows[TALL_HERO_BAND_ROWS].as_str(), "DISTANCE");
    }

    #[test]
    fn the_home_face_says_when_an_interrupted_run_is_waiting() {
        // After a brown-out mid-run the idle face was indistinguishable from a
        // normal boot, so the recovered run sat on flash with nothing on the wrist
        // to say so. One standing tag, right-anchored under the clock.
        let base = face_rows(Some(&fix()), Some(150), None, None, 10);

        let mut rows = base.clone();
        apply_pending_run_marker(&mut rows, IdleView::Home, 0);
        assert_eq!(rows, base, "nothing pending -> the face is untouched");

        let mut rows = base.clone();
        apply_pending_run_marker(&mut rows, IdleView::Home, 1);
        assert_eq!(rows[PENDING_RUN_ROW].as_str().trim(), "1 RUN RECOVERED");
        assert!(rows[PENDING_RUN_ROW].as_str().starts_with(' '));
        assert!(rows[PENDING_RUN_ROW].len() <= COLS);
        for r in 0..ROWS {
            if r != PENDING_RUN_ROW {
                assert_eq!(rows[r], base[r], "row {r} changed");
            }
        }

        let mut rows = base.clone();
        apply_pending_run_marker(&mut rows, IdleView::Home, 3);
        assert_eq!(rows[PENDING_RUN_ROW].as_str().trim(), "3 RUNS RECOVERED");
        assert!(rows[PENDING_RUN_ROW].len() <= COLS);
    }

    #[test]
    fn the_pending_run_marker_never_clobbers_a_row_it_does_not_own() {
        // Off the home view (the diagnostics rows are all claimed) and over an
        // occupied row it does nothing — the same add-a-glance-only contract the
        // fuel and battery post-passes keep. Every count a u8 can hold still fits
        // the row, so a wide count can never render as a bare number.
        let diag = diag_rows(Some(&fix()), Some(150), None, 10);
        let mut rows = diag.clone();
        apply_pending_run_marker(&mut rows, IdleView::Diagnostics, 2);
        assert_eq!(rows, diag);

        let mut rows: [Row; ROWS] = Default::default();
        let _ = write!(rows[PENDING_RUN_ROW], "BUSY");
        let before = rows.clone();
        apply_pending_run_marker(&mut rows, IdleView::Home, 1);
        assert_eq!(rows, before);

        for pending in [2u8, 9, 99, u8::MAX] {
            let mut rows: [Row; ROWS] = Default::default();
            apply_pending_run_marker(&mut rows, IdleView::Home, pending);
            assert!(rows[PENDING_RUN_ROW].len() <= COLS, "count {pending}");
            assert!(
                rows[PENDING_RUN_ROW].as_str().ends_with("RUNS RECOVERED"),
                "count {pending} rendered as {:?}",
                rows[PENDING_RUN_ROW].as_str()
            );
        }
    }

    /// An active run with every page's data present, at extreme values — the
    /// widest each row and hero can render.
    fn fed_snapshot() -> Snapshot {
        use crate::record::{
            AutoEffortView, ElevProfileView, FitnessView, FuelCarryView, FuelView, GoalsView,
            GuidedRunView, PlanAdaptiveView, PlanReplanView, PrRecencyView, RaceDayView,
            ReadinessView, RecapView, RoadbookLegView, RoadbookView, RouteElevView,
            RouteSimplifyView, RunStatsView, StreaksView, TrainingPacesView, TurnCueView,
            ELEV_PROFILE_CAP,
        };
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
        // Raw (setter-unclamped) extremes: the rows must fit even off a view
        // the clamping setter never shaped.
        rec.plan_adaptive = Some(PlanAdaptiveView {
            trend: 255,
            confidence: 1,
            flagged_weeks: 255,
            window_weeks: 255,
            changes: 255,
            fitness_gated: false,
        });
        rec.guided_run = Some(GuidedRunView {
            cue_index: 255,
            cue_count: 255,
            next_cue_in_s: Some(999 * 3600 + 59 * 60 + 59),
            duration_s: 999 * 3600,
            remaining_s: 999 * 3600 + 59 * 60 + 59,
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
            total_m: u32::MAX,
            samples: [i16::MIN; crate::record::COURSE_PROFILE_CAP],
            len: crate::record::COURSE_PROFILE_CAP,
        });
        rec.race_day = Some(RaceDayView {
            days_until: -9999,
            feasible: 1,
        });
        // The live-derived views (no phone push behind them) had been left out,
        // which quietly kept the Pacer / Workout / CutoffEta / Climb /
        // Waypoint / RacePredictor bodies out of every guard that walks this
        // snapshot — those pages were only ever swept in their empty state.
        rec.pacer = Some(crate::pacer::PacerStatus {
            goal: crate::pacer::PacerGoal {
                distance_m: 1_000_000,
                time_s: 1_000_000,
            },
            ahead_m: -9_999_999.0,
            ahead_s: i32::MIN,
            projected_finish_s: Some(u32::MAX),
            verdict: PaceVerdict::Behind,
            finished: false,
            terrain_aware: true,
        });
        rec.race_phase = Some(RacePhaseView {
            index: 255,
            total: 255,
            intent: RacePhaseIntent::HoldBack,
            target_pace_s_per_km: Some(99 * 60 + 59),
        });
        rec.cutoff = Some(crate::cutoff_eta::CutoffEta {
            has_cutoff: true,
            distance_to_m: 999_990.0,
            projected_arrival_elapsed_s: Some(u32::MAX),
            margin_s: Some(i32::MIN),
            required_pace_s_per_km: Some(99.0 * 60.0 + 59.0),
            limit_passed: false,
            status: crate::cutoff_eta::CutoffEtaStatus::Behind,
        });
        rec.workout = Some(workout_view());
        rec.race_prediction = Some(
            crate::race_predictor::predict_race_ladder(&[crate::race_predictor::Effort {
                distance_m: 5_000.0,
                duration_s: 1_200,
                age_days: 0.0,
            }])
            .unwrap(),
        );
        rec.climb = crate::climb::ClimbView {
            active: Some(crate::climb::ActiveClimb {
                gain_m: 99_999.0,
                distance_m: 999_999.0,
                avg_grade_pct: 99.0,
            }),
            ahead: Some(crate::climb::CrestAhead {
                gain_m: 99_999.0,
                distance_m: 999_999.0,
                avg_grade_pct: 99.0,
            }),
        };
        rec.waypoint = Some(crate::waypoints::WaypointView {
            distance_m: 999_999.0,
            bearing_deg: 359.0,
            count: 8,
            marked_uptime_s: 0,
        });
        rec.waypoint_count = 8;
        rec
    }

    #[test]
    fn every_page_fits_the_grid_active_and_inactive() {
        let rec = fed_snapshot();
        let e = elev(99_999.0, 99_999.0, 99_999.0);

        let mut p = Page::default();
        loop {
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
            if p == Page::default() {
                break;
            }
        }

        // Inactive: a short run with no pushed roadbook / fuel / gear — every new
        // page must render its honest empty state and still fit the grid.
        let inactive = snapshot(RecordState::Recording, 15_000.0);
        let mut p = Page::default();
        loop {
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
            if p == Page::default() {
                break;
            }
        }
    }

    /// The other half of [`body_top_row`]'s contract, and the § 361 half: a
    /// page that reserves the hero band has to *use* it. Thirteen of the
    /// phone-pushed summary pages reserved two rows and left them blank while
    /// stating their headline in an 8x16 row — a fifth of the panel, at the
    /// top, indistinguishable from the rows contextualising it.
    ///
    /// [`Page::Nav`] is the one exemption, and a structural one rather than a
    /// list entry: its `body_top_row` is 0, so it reserves no band to waste.
    #[test]
    fn every_page_that_reserves_a_hero_band_fills_it() {
        let fed = fed_snapshot();
        let unfed = snapshot(RecordState::Recording, 15_000.0);
        for rec in [&fed, &unfed] {
            let mut p = Page::default();
            loop {
                let hero = page_hero(p, Some(152), Some(rec), Some(&nav_east(500, 6.0)));
                assert_eq!(
                    hero.is_some(),
                    body_top_row(p) > 0,
                    "page {p:?} reserves {} rows for a hero and has {}",
                    body_top_row(p),
                    if hero.is_some() { "one" } else { "none" }
                );
                p = p.next();
                if p == Page::default() {
                    break;
                }
            }
        }
    }

    /// The guard that makes [`body_top_row`] a contract rather than a comment.
    /// A page that claims the three-row band and then writes a header on row 2
    /// would have that header erased by the hero the app draws over rows 0-2 —
    /// invisibly, since nothing else reads those cells. Walked over the fed and
    /// the unfed body of every page, and over an animating and a steady frame,
    /// because the state tag moves with the header.
    #[test]
    fn every_page_leaves_its_hero_band_blank() {
        let fed = fed_snapshot();
        let unfed = snapshot(RecordState::Recording, 15_000.0);
        let e = elev(99_999.0, 99_999.0, 99_999.0);
        for rec in [&fed, &unfed] {
            for animate in [true, false] {
                let mut p = Page::default();
                loop {
                    let rows = page_rows(
                        p,
                        Some(&fix()),
                        Some(150),
                        Some(rec),
                        Some(&e),
                        NavView::NoCourse,
                        None,
                        42,
                        animate,
                    );
                    for (r, row) in rows.iter().take(body_top_row(p)).enumerate() {
                        let text = row.as_str().trim();
                        if tall_hero(p) {
                            // A tall page moved its tag down to the header row,
                            // so nothing at all may ride the band.
                            assert_eq!(
                                text, "",
                                "page {p:?} writes into its own hero band (animate {animate})"
                            );
                        } else {
                            assert!(
                                text.is_empty() || (r == 0 && rec_tag(rec) == Some(text)),
                                "page {p:?} row {r} holds more than the state tag: {text:?} \
                                 (animate {animate})"
                            );
                        }
                    }
                    p = p.next();
                    if p == Page::default() {
                        break;
                    }
                }
            }
        }
    }

    /// § 361: a unit is a label for a hero, so it must have one to label, and it
    /// must fit beside it in the band the frame would actually choose. Walked
    /// over the fed and the unfed body of every page, because the unit is
    /// suppressed on a placeholder and the two branches produce different hero
    /// widths.
    #[test]
    fn every_hero_unit_has_a_hero_to_label_and_room_beside_it() {
        use crate::ui_frame::{
            hero_band, hero_has_value, hero_unit_cell, numeral_hero, tall_hero_fits, HeroFrame,
        };
        let fed = fed_snapshot();
        let unfed = snapshot(RecordState::Recording, 15_000.0);
        let mut labelled = 0;
        for rec in [&fed, &unfed] {
            let mut p = Page::default();
            loop {
                let hero = page_hero(p, Some(152), Some(rec), Some(&nav_east(500, 6.0)));
                let unit = page_hero_unit(p, Some(rec), Some(&nav_east(500, 6.0)));
                if let Some(unit) = unit {
                    let hero = hero.as_deref().unwrap_or_else(|| {
                        panic!("page {p:?} claims the unit {unit:?} with no hero to label")
                    });
                    assert!(!unit.is_empty(), "page {p:?} claims an empty unit");
                    if !hero_has_value(hero) {
                        // A placeholder body suppresses the unit at the frame,
                        // so there is nothing to place.
                        p = p.next();
                        if p == Page::default() {
                            break;
                        }
                        continue;
                    }
                    let band = hero_band(HeroFrame {
                        alert: false,
                        rezero_banner: false,
                        hero: true,
                        numeral: numeral_hero(hero),
                        fits_tall: tall_hero_fits(hero, Some(unit)),
                        stop_pending: false,
                        page: p,
                    });
                    let (col, row) = hero_unit_cell(band, hero, unit).unwrap_or_else(|| {
                        panic!("page {p:?} has no room for {unit:?} beside {hero:?} ({band:?})")
                    });
                    assert!(
                        col + unit.len() <= COLS,
                        "page {p:?} unit overruns the grid"
                    );
                    // The unit rides the hero band, whose rows every page's own
                    // text already leaves clear — so it can never land on a
                    // metric row.
                    assert!(
                        row < body_top_row(p),
                        "page {p:?} puts {unit:?} on row {row}, inside its own body"
                    );
                    labelled += 1;
                }
                p = p.next();
                if p == Page::default() {
                    break;
                }
            }
        }
        // The sweep is only worth anything if it actually reached some units.
        assert!(labelled >= 12, "only {labelled} hero units placed");
    }

    /// [`write_tag`] refuses rather than truncates, so a header that grew into
    /// the tag's cells would drop the recording indicator instead of corrupting
    /// it. Silent either way on the wrist — so it is asserted here, on the
    /// widest body every page can render.
    #[test]
    fn the_state_tag_survives_on_every_page() {
        let fed = fed_snapshot();
        let unfed = snapshot(RecordState::Recording, 15_000.0);
        let e = elev(99_999.0, 99_999.0, 99_999.0);
        for rec in [&fed, &unfed] {
            let mut p = Page::default();
            loop {
                let rows = page_rows(
                    p,
                    Some(&fix()),
                    Some(150),
                    Some(rec),
                    Some(&e),
                    NavView::NoCourse,
                    None,
                    // An even second, so the blinking REC tag is in its shown
                    // half of the cycle.
                    42,
                    true,
                );
                assert!(
                    rows.iter().any(|r| r.as_str().ends_with("REC")),
                    "page {p:?} dropped the run-state tag"
                );
                p = p.next();
                if p == Page::default() {
                    break;
                }
            }
        }
    }

    #[test]
    fn secondary_time_rows_render_past_99_hours() {
        use crate::record::{RoadbookLegView, RoadbookView};
        // A roadbook checkpoint projected past 99 h is in range for a 112 h
        // cutoff race. The hero clamps hours at 999; the secondary rows must
        // match, so the arrival reads the true hour count, not a clamped 99.
        let mut rec = snapshot(RecordState::Recording, 195_000.0);
        rec.roadbook = Some(RoadbookView {
            total: 1,
            upcoming: [RoadbookLegView {
                cum_dist_m: 195_000.0,
                projected_elapsed_s: 105 * 3600 + 12 * 60 + 34,
                cutoff: Some(CutoffStatus::Safe),
            }; crate::record::ROADBOOK_WINDOW],
            upcoming_len: 1,
        });
        let rows = page_rows(
            Page::Roadbook,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert!(
            rows[3].as_str().contains("105:12:34"),
            "roadbook arrival clamped instead of rendering >99 h: {:?}",
            rows[3]
        );
    }

    #[test]
    fn idle_diagnostics_keeps_the_bench_view() {
        let rows = diag_rows(Some(&fix()), None, None, 42);
        // Title row is static (no ticking uptime) so the idle screen doesn't
        // force a per-second wake; time of day still shows on the UTC row.
        assert_eq!(rows[0].as_str(), "THREKIR");
        assert_eq!(rows[1].as_str(), "MODE PERF EST 110H");
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        assert_eq!(rows[4].as_str(), "LON   -105.27050");
        assert_eq!(rows[5].as_str(), "SPD  3.0 M/S");
        assert_eq!(rows[6].as_str(), "ALT  1624 M");
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn diagnostics_battery_rides_the_hr_row_right_anchored() {
        let mut rows = diag_rows(Some(&fix()), Some(152), None, 42);
        apply_battery_row(&mut rows, IdleView::Diagnostics, Some(87));
        assert_eq!(rows[BATTERY_ROW].as_str(), "HR   152 BPM  BAT 87%");
        assert!(rows[BATTERY_ROW].len() <= COLS);
    }

    #[test]
    fn diagnostics_battery_stands_alone_when_no_pulse() {
        let mut rows = diag_rows(Some(&fix()), None, None, 42);
        apply_battery_row(&mut rows, IdleView::Diagnostics, Some(5));
        assert_eq!(rows[BATTERY_ROW].len(), COLS);
        assert_eq!(rows[BATTERY_ROW].trim_start(), "BAT 5%");
    }

    #[test]
    fn diagnostics_battery_absent_leaves_the_row_untouched() {
        let mut rows = diag_rows(Some(&fix()), Some(152), None, 42);
        apply_battery_row(&mut rows, IdleView::Diagnostics, None);
        assert_eq!(rows[BATTERY_ROW].as_str(), "HR   152 BPM");
    }

    #[test]
    fn battery_row_is_diagnostics_only() {
        // The home face carries the icon widget instead; its rows must come
        // through the post-pass byte-identical.
        let before = face_rows(Some(&fix()), Some(152), None, None, 42);
        let mut after = before.clone();
        apply_battery_row(&mut after, IdleView::Home, Some(87));
        assert_eq!(before, after);
    }

    #[test]
    fn diagnostics_battery_clamps_and_never_overflows_cols() {
        let mut rows = diag_rows(Some(&fix()), Some(999), None, 42);
        apply_battery_row(&mut rows, IdleView::Diagnostics, Some(255));
        assert_eq!(rows[BATTERY_ROW].as_str(), "HR   999 BPM BAT 100%");
        // A row without room for a gap before the tag refuses rather than
        // truncating the HR value.
        let mut wide = diag_rows(Some(&fix()), Some(65535), None, 42);
        apply_battery_row(&mut wide, IdleView::Diagnostics, Some(50));
        assert_eq!(wide[BATTERY_ROW].as_str(), "HR   65535 BPM");
    }

    #[test]
    fn idle_clock_wins_the_bottom_row_over_vert() {
        // A baro-equipped watch used to lose the time of day entirely — vert
        // displaced the clock. Home tells the time; vert keeps the row only
        // when no fix carries a clock (the bench case: baro without GPS).
        let e = elev(1600.0, 120.0, 40.0);
        let rows = diag_rows(Some(&fix()), None, Some(&e), 42);
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
        let rows = diag_rows(None, None, Some(&e), 42);
        assert_eq!(rows[8].as_str(), "VERT +120 -40 M");
    }

    #[test]
    fn idle_title_shows_the_btn3_hint_steady_inside_the_interaction_window() {
        // Post-press (animate on): the hint holds row 0 for the whole window
        // whatever the second — the old 2 s / 2 s alternation with the brand
        // gave a dwell too short to read — and stops short of the GPS meter,
        // which is drawn over the row's last three columns (COLS - 3; the
        // boundary is pinned from the pixel side in watch_render::widgets).
        for uptime in [42, 43, 44, 45] {
            let rows = page_rows(
                Page::Dashboard,
                Some(&fix()),
                None,
                None,
                None,
                NavView::NoCourse,
                None,
                uptime,
                true,
            );
            assert_eq!(rows[0].as_str(), "B3 MODE/HLD REZERO");
            assert!(rows[0].chars().count() <= COLS - 3);
        }
        // Window closed: the brand holds steady whatever the second, so an
        // unattended idle face never redraws row 0.
        for uptime in [42, 43, 44, 45] {
            let rows = page_rows(
                Page::Dashboard,
                Some(&fix()),
                None,
                None,
                None,
                NavView::NoCourse,
                None,
                uptime,
                false,
            );
            assert_eq!(rows[0].as_str(), "THREKIR");
        }
    }

    #[test]
    fn idle_stale_fix_is_flagged_not_shown_as_fresh() {
        let rows = diag_rows(Some(&fix()), None, None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[2].as_str(), "GPS  STALE 8S");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        // The home view flags the same staleness on its summary row.
        let rows = face_rows(Some(&fix()), None, None, None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[7].as_str(), "GPS STALE 8S      UTC");
    }

    #[test]
    fn idle_no_fix_renders_acquiring() {
        let rows = diag_rows(None, None, None, 9);
        assert_eq!(rows[2].as_str(), "GPS  ACQUIRING");
        assert_eq!(rows[5].as_str(), "");
    }

    #[test]
    fn home_face_reserves_the_clock_band_and_summarises() {
        let e = elev(1600.0, 120.0, 40.0);
        let rows = face_rows(Some(&fix()), Some(72), None, Some(&e), 42);
        assert_eq!(rows[0].as_str(), "THREKIR");
        // Rows 1..=5 stay blank: 2..=4 are the clock hero band the app draws
        // the generated numerals into, 1 and 5 its breathing room.
        for row in CLOCK_HERO_TOP_ROW - 1..=CLOCK_HERO_TOP_ROW + CLOCK_HERO_ROWS {
            assert_eq!(rows[row].as_str(), "", "row {row} must stay blank");
        }
        // Baro-preferred altitude, same preference as the diagnostics ALT row.
        assert_eq!(rows[6].as_str(), "HR 72 BPM  ALT 1600 M");
        assert_eq!(rows[7].as_str(), "GPS 8 SATS        UTC");
        assert_eq!(rows[8].as_str(), "MODE PERF EST 110H");
        for row in &rows {
            assert!(row.chars().count() <= COLS);
        }
    }

    #[test]
    fn home_face_holds_honest_placeholders_without_signals() {
        let rows = face_rows(None, None, None, None, 9);
        assert_eq!(rows[6].as_str(), "HR --          ALT --");
        assert_eq!(rows[7].as_str(), "GPS ACQUIRING     UTC");
    }

    #[test]
    fn home_clock_extrapolates_from_the_fix_to_the_current_minute() {
        // fix(): time_of_day 07:30:15 stamped at uptime 41. At uptime 41 the
        // clock reads the fix minute; 105 s later it must have advanced —
        // Expedition-mode fixes arrive minutes apart, and a hero frozen at
        // the fix's minute reads as a hung watch.
        assert_eq!(home_clock_text(Some(&fix()), 41, None).as_str(), "07:30");
        assert_eq!(
            home_clock_text(Some(&fix()), 41 + 105, None).as_str(),
            "07:32"
        );
        // Wraps across midnight rather than showing 24:xx.
        let mut late = fix();
        late.time_of_day = Some(23 * 3600 + 59 * 60 + 50);
        assert_eq!(
            home_clock_text(Some(&late), 41 + 20, None).as_str(),
            "00:00"
        );
        // Honest placeholder before any fix carries a clock.
        assert_eq!(home_clock_text(None, 9, None).as_str(), "--:--");
        let mut clockless = fix();
        clockless.time_of_day = None;
        assert_eq!(home_clock_text(Some(&clockless), 9, None).as_str(), "--:--");
    }

    #[test]
    fn home_clock_shifts_to_local_when_an_offset_is_pushed() {
        // fix(): 07:30:15 UTC stamped at uptime 41.
        assert_eq!(
            home_clock_text(Some(&fix()), 41, Some(120)).as_str(),
            "09:30"
        );
        // Negative offsets shift back.
        assert_eq!(
            home_clock_text(Some(&fix()), 41, Some(-420)).as_str(),
            "00:30"
        );
        // Half- and quarter-hour zones land off the hour grid (+5:45).
        assert_eq!(
            home_clock_text(Some(&fix()), 41, Some(345)).as_str(),
            "13:15"
        );
        assert_eq!(
            home_clock_text(Some(&fix()), 41, Some(-330)).as_str(),
            "02:00"
        );
        // The extrapolated minute shifts with the same offset.
        assert_eq!(
            home_clock_text(Some(&fix()), 41 + 105, Some(345)).as_str(),
            "13:17"
        );
        // The placeholder ignores the offset — no clock is no clock.
        assert_eq!(home_clock_text(None, 9, Some(345)).as_str(), "--:--");
    }

    #[test]
    fn home_clock_offset_wraps_midnight_both_directions() {
        // 23:10 UTC + 2 h => 01:10 the next day, never 25:10.
        let mut late = fix();
        late.time_of_day = Some(23 * 3600 + 10 * 60);
        assert_eq!(
            home_clock_text(Some(&late), 41, Some(120)).as_str(),
            "01:10"
        );
        // 00:10 UTC - 1 h => 23:10 the previous day, never -0:50.
        let mut early = fix();
        early.time_of_day = Some(10 * 60);
        assert_eq!(
            home_clock_text(Some(&early), 41, Some(-60)).as_str(),
            "23:10"
        );
    }

    #[test]
    fn home_face_label_matches_the_clock_zone() {
        // The row-7 label and the hero derive from the same offset input, so
        // LOCAL can only show when the hero is actually shifted — and UTC
        // stays until a push carries an offset.
        let rows = super::face_rows(
            Some(&fix()),
            None,
            None,
            None,
            42,
            GnssMode::Performance,
            IdleView::Home,
            Some(345),
            None,
        );
        assert_eq!(rows[7].as_str(), "GPS 8 SATS      LOCAL");
        let rows = face_rows(Some(&fix()), None, None, None, 42);
        assert_eq!(rows[7].as_str(), "GPS 8 SATS        UTC");
    }

    #[test]
    fn diagnostics_seconds_row_stays_utc_with_an_offset_live() {
        // The bench view keeps raw receiver time on purpose: same offset that
        // shifts the home hero must leave the diagnostics clock untouched.
        let rows = super::face_rows(
            Some(&fix()),
            None,
            None,
            None,
            42,
            GnssMode::Performance,
            IdleView::Diagnostics,
            Some(345),
            None,
        );
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
    }

    #[test]
    fn recording_renders_the_run_dashboard() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 3 * 3600 + 24 * 60 + 7;
        rec.avg_pace_s_per_km = Some(5 * 60 + 12);
        rec.current_pace_s_per_km = Some(4 * 60 + 58);
        rec.gap_s_per_km = Some(4 * 60 + 41);
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42);
        // Rows 0-1 are the hero band: only the tag (top-right), hero drawn 2x.
        assert_eq!(rows[0].as_str().trim(), "REC");
        assert!(rows[0].as_str().ends_with("REC"));
        assert_eq!(rows[1].as_str(), "");
        assert_eq!(hero_line(Some(&rec)).unwrap().as_str(), "3:24:07");
        assert_eq!(rows[2].as_str(), "     12.34 KM");
        assert_eq!(rows[3].as_str(), "PACE 5:12 /KM");
        assert_eq!(rows[4].as_str(), "NOW  4:58  GAP 4:41");
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

    /// Every run page but the dashboard carries exactly one gutter icon: the
    /// satellite labelling [`GPS_ROW`]. Called beside each page's own row
    /// expectations, and swept over the whole cycle by
    /// `every_run_page_labels_its_gps_row_with_the_satellite`.
    fn only_the_gps_icon(page: Page, rec: &Snapshot, uptime_s: u32) {
        let icons = page_icons(page, Some(&fix()), Some(152), Some(rec), uptime_s, true);
        for (row, icon) in icons.iter().enumerate() {
            let want = (row == GPS_ROW).then_some(FaceIcon::Satellite);
            assert_eq!(*icon, want, "{page:?} row {row}");
        }
    }

    /// The § 361 contract: the bottom row means the same thing on every run
    /// page, so the glyph labels it on every run page — and the five cells the
    /// word `GPS` used to hold stay blank for it. Both halves are asserted
    /// together, because an icon without the cleared gutter blits over the
    /// value and a cleared gutter without the icon leaves the row unlabelled.
    #[test]
    fn every_run_page_labels_its_gps_row_with_the_satellite() {
        let rec = fed_snapshot();
        let e = elev(1_650.0, 540.0, 120.0);
        let mut p = Page::default();
        loop {
            let icons = page_icons(p, Some(&fix()), Some(152), Some(&rec), 42, true);
            assert_eq!(
                icons[GPS_ROW],
                Some(FaceIcon::Satellite),
                "{p:?} GPS row unlabelled"
            );
            let rows = page_rows(
                p,
                Some(&fix()),
                Some(152),
                Some(&rec),
                Some(&e),
                NavView::NoCourse,
                None,
                42,
                true,
            );
            assert!(
                rows[GPS_ROW].as_str().starts_with(GUTTER),
                "{p:?} GPS row writes into the icon gutter: {:?}",
                rows[GPS_ROW]
            );
            if p != Page::Dashboard {
                only_the_gps_icon(p, &rec, 42);
            }
            p = p.next();
            if p == Page::default() {
                break;
            }
        }
        // Idle keeps the spelled label and no gutter at all — it has a
        // dedicated MODE row instead, so the mode tag the glyph rows carry is
        // not there to shorten.
        let idle = snapshot(RecordState::Idle, 0.0);
        for page in [Page::Dashboard, Page::Distance] {
            assert!(
                page_icons(page, Some(&fix()), Some(152), Some(&idle), 42, true)
                    .iter()
                    .all(Option::is_none),
                "{page:?} iconned an idle face"
            );
        }
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
        let mut paused = snapshot(RecordState::Paused, 100.0);
        paused.manual_paused = true;
        assert_eq!(
            face_rows(None, None, Some(&paused), None, 11)[0]
                .as_str()
                .trim(),
            "PAU"
        );
    }

    #[test]
    fn pause_tag_distinguishes_manual_auto_and_the_min_move_artifact() {
        // Manual pause: the runner pressed the button — PAU, steady.
        let mut manual = snapshot(RecordState::Paused, 100.0);
        manual.manual_paused = true;
        assert_eq!(
            face_rows(None, None, Some(&manual), None, 11)[0]
                .as_str()
                .trim(),
            "PAU"
        );

        // Speed-derived auto-pause (stationary at an aid station): AUTO,
        // steady on odd seconds too — it resumes itself, no button owed.
        let auto = snapshot(RecordState::Paused, 100.0);
        assert_eq!(auto.current_speed_mps, 0.0);
        assert_eq!(
            face_rows(None, None, Some(&auto), None, 11)[0]
                .as_str()
                .trim(),
            "AUTO"
        );

        // Min-move sampling artifact (power-hiking a climb at ~1 m/s covers
        // under the 3 m gate per 1 Hz fix): the run is recording — REC, with
        // the normal blink, never a flicker through PAU.
        let mut artifact = snapshot(RecordState::Paused, 100.0);
        artifact.current_speed_mps = 1.0;
        assert_eq!(
            face_rows(None, None, Some(&artifact), None, 10)[0]
                .as_str()
                .trim(),
            "REC"
        );
        assert_eq!(
            face_rows(None, None, Some(&artifact), None, 11)[0].as_str(),
            ""
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
        assert_eq!(rows[4].as_str(), "NOW  --    GAP --");
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
        let mut paused = snapshot(RecordState::Paused, 5_000.0);
        paused.manual_paused = true;
        let rows = face_rows(None, None, Some(&paused), None, 3);
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
        // Rows 0-2 are the numeral hero band (drawn by the app); the label and
        // the right-anchored state tag share row 3.
        assert_eq!(rows[0].as_str(), "");
        assert_eq!(rows[2].as_str(), "");
        assert_eq!(rows[3].as_str(), "DISTANCE          REC");
        assert_eq!(rows[4].as_str(), "TIME 3:24:07");
        assert_eq!(rows[5].as_str(), "PACE 5:12 /KM");
        assert_eq!(rows[6].as_str(), "HR   152 BPM Z3");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::Distance, &rec, 42);
    }

    #[test]
    fn distance_page_warns_when_the_flash_track_is_thinned() {
        let mut rec = snapshot(RecordState::Recording, 42_195.0);
        rec.track_thinning = 4;
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
        // Row 7 (otherwise free on the Distance page) carries the honest notice.
        assert_eq!(rows[7].as_str(), "! TRACK 1/4 RES");

        // Absent at full resolution.
        rec.track_thinning = 1;
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
        assert_eq!(rows[7].as_str(), "");
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
        assert_eq!(rows[3].as_str(), "AVG PACE          REC");
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
        // Rows 0-2 are the tall hero band; the label row carries the tag.
        assert_eq!(rows[0].as_str(), "");
        assert_eq!(rows[3], header("LAP 4", "REC"));
        assert_eq!(rows[4].as_str(), "LAST 4:58");
        assert_eq!(rows[5].as_str(), "DIST 0.42 KM");
        assert_eq!(rows[6].as_str(), "HR   152 BPM Z3");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::Lap, &rec, 42);
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
        assert_eq!(rows[3], header("LAP 1", "REC"));
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
            // Home-face signature: blank clock band, GPS glance on row 7.
            assert_eq!(rows[2].as_str(), "");
            assert_eq!(rows[7].as_str(), "GPS 8 SATS        UTC");
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
            terrain_aware: false,
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::Zones, &rec, 42);
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
        assert_eq!(rows[8].as_str(), "     ACQUIRING PERF");
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
            terrain_aware: false,
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::Pacer, &rec, 42);
    }

    #[test]
    fn pacer_glance_tags_a_terrain_allocated_partner() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        let mut status = pacer_status(0.0, 0, PaceVerdict::OnPace, Some(3_000));
        status.terrain_aware = true;
        rec.pacer = Some(status);
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
        assert_eq!(rows[3].as_str(), "TERRAIN SPLITS");
        // The flat partner with no pushed phase plan falls through to the
        // phase row's own inactive state.
        let mut flat = rec;
        flat.pacer = Some(pacer_status(0.0, 0, PaceVerdict::OnPace, Some(3_000)));
        let rows = page_rows(
            Page::Pacer,
            Some(&fix()),
            Some(152),
            Some(&flat),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[3].as_str(), "PHASE --");
    }

    #[test]
    fn pacer_glance_names_the_race_phase_and_its_target_pace() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        rec.pacer = Some(pacer_status(140.0, 42, PaceVerdict::Ahead, Some(2_857)));
        rec.race_phase = Some(RacePhaseView {
            index: 1,
            total: 3,
            intent: RacePhaseIntent::HoldBack,
            target_pace_s_per_km: Some(306),
        });
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
        assert_eq!(rows[3].as_str(), "HOLD   5:06 /KM");
        // The partner rows below it are untouched by the phase.
        assert_eq!(rows[4].as_str(), "GOAL 10.00 KM");
        assert_eq!(rows[7].as_str(), "DIST +140 M");

        // The longest label plus the terrain tag still fits the grid.
        rec.race_phase = Some(RacePhaseView {
            index: 2,
            total: 3,
            intent: RacePhaseIntent::Settle,
            target_pace_s_per_km: Some(300),
        });
        let mut status = pacer_status(140.0, 42, PaceVerdict::Ahead, Some(2_857));
        status.terrain_aware = true;
        rec.pacer = Some(status);
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
        assert_eq!(rows[3].as_str(), "SETTLE 5:00 /KM TERR");
        assert!(rows[3].as_str().len() <= COLS);
    }

    #[test]
    fn pacer_glance_phase_without_a_goal_pace_shows_dashes_not_a_zero_target() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        rec.pacer = Some(pacer_status(0.0, 0, PaceVerdict::OnPace, Some(3_000)));
        rec.race_phase = Some(RacePhaseView {
            index: 3,
            total: 3,
            intent: RacePhaseIntent::Race,
            target_pace_s_per_km: None,
        });
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
        assert_eq!(rows[3].as_str(), "RACE   --");
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
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(rows[7].as_str(), "");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
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
    fn guided_run_glance_shows_the_cue_schedule_and_the_time_left() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        rec.guided_run = Some(crate::record::GuidedRunView {
            cue_index: 3,
            cue_count: 8,
            next_cue_in_s: Some(150),
            duration_s: 1_800,
            remaining_s: 765,
        });
        let rows = page_rows(
            Page::GuidedRun,
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
            page_hero(Page::GuidedRun, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "12:45"
        );
        assert_eq!(rows[0].as_str(), "");
        assert_eq!(rows[3], header("GUIDED  30 MIN", "REC"));
        assert_eq!(rows[4].as_str(), "CUE     3/8");
        assert_eq!(rows[5].as_str(), "NEXT    2:30");
        assert_eq!(rows[6].as_str(), "LEFT    12:45");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::GuidedRun, &rec, 42);

        // Past the last cue the row says so rather than showing a 0:00 that
        // reads as a cue about to fire.
        rec.guided_run = Some(crate::record::GuidedRunView {
            cue_index: 8,
            cue_count: 8,
            next_cue_in_s: None,
            duration_s: 1_800,
            remaining_s: 0,
        });
        let rows = page_rows(
            Page::GuidedRun,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[4].as_str(), "CUE     8/8");
        assert_eq!(rows[5].as_str(), "NEXT    LAST CUE");
        assert_eq!(rows[6].as_str(), "LEFT    0:00");
    }

    fn workout_view() -> crate::workout::WorkoutView {
        use crate::workout::{NextStep, PaceAdherence, WorkoutStepKind, WorkoutView};
        WorkoutView {
            step_index: 2,
            step_total: 14,
            kind: WorkoutStepKind::Rep,
            rep_index: 2,
            rep_total: 6,
            duration_based: false,
            target_distance_m: 400,
            target_duration_s: 0,
            target_pace_s_per_km: 240,
            step_distance_m: 280,
            step_elapsed_s: 70,
            remaining_m: 120,
            remaining_s: 0,
            progress_permille: 700,
            step_pace_s_per_km: Some(250),
            adherence: PaceAdherence::Behind,
            next: Some(NextStep {
                kind: WorkoutStepKind::Recovery,
                rep_index: 2,
                rep_total: 5,
                target_distance_m: 200,
                target_duration_s: 0,
            }),
            complete: false,
            rollup: None,
            transition_seq: 3,
            ending_seq: 2,
        }
    }

    #[test]
    fn workout_glance_shows_the_active_step() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        rec.workout = Some(workout_view());
        let rows = page_rows(
            Page::Workout,
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
            page_hero(Page::Workout, Some(152), Some(&rec), None)
                .unwrap()
                .as_str(),
            "120"
        );
        assert_eq!(page_hero_unit(Page::Workout, Some(&rec), None), Some("M"));
        assert_eq!(rows[2], header("REP 2/6", "REC"));
        assert_eq!(rows[3].as_str(), "TGT  400 M @ 4:00");
        assert_eq!(rows[4].as_str(), "GONE 280 M  70%");
        assert_eq!(rows[5].as_str(), "PACE 4:10  BEHIND");
        assert_eq!(rows[6].as_str(), "NEXT RECOVERY 200 M");
        assert_eq!(rows[7].as_str(), "STEP 3/14");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::Workout, &rec, 42);
    }

    #[test]
    fn workout_glance_renders_a_duration_step_on_the_time_axis() {
        use crate::workout::{PaceAdherence, WorkoutStepKind};
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        let mut w = workout_view();
        w.kind = WorkoutStepKind::Walk;
        w.rep_index = 1;
        w.rep_total = 7;
        w.duration_based = true;
        w.target_distance_m = 0;
        w.target_duration_s = 90;
        w.target_pace_s_per_km = 420;
        w.step_elapsed_s = 30;
        w.remaining_m = 0;
        w.remaining_s = 60;
        w.progress_permille = 333;
        w.adherence = PaceAdherence::OnPace;
        w.next = None;
        rec.workout = Some(w);
        let rows = page_rows(
            Page::Workout,
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
            page_hero(Page::Workout, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1:00"
        );
        assert_eq!(rows[2], header("WALK 1/7", "REC"));
        assert_eq!(rows[3].as_str(), "TGT  1:30 @ 7:00");
        assert_eq!(rows[4].as_str(), "GONE 0:30  33%");
        assert_eq!(rows[5].as_str(), "PACE 4:10  ON PACE");
        assert_eq!(rows[6].as_str(), "LAST STEP");
    }

    #[test]
    fn workout_glance_complete_state_shows_the_rollup() {
        use crate::workout::WorkoutAdherence;
        let mut rec = snapshot(RecordState::Recording, 6_000.0);
        let mut w = workout_view();
        w.step_index = 13;
        w.complete = true;
        w.rollup = Some(WorkoutAdherence::Completed);
        rec.workout = Some(w);
        let rows = page_rows(
            Page::Workout,
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
            page_hero(Page::Workout, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "DONE"
        );
        assert_eq!(rows[2], header("WORKOUT", "REC"));
        assert_eq!(rows[4].as_str(), "WORKOUT DONE");
        assert_eq!(rows[5].as_str(), "TARGETS HIT");
        assert_eq!(rows[7].as_str(), "STEP 14/14");

        let mut w = workout_view();
        w.complete = true;
        w.rollup = Some(WorkoutAdherence::Partial);
        rec.workout = Some(w);
        let rows = page_rows(
            Page::Workout,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[5].as_str(), "PARTIAL");
    }

    #[test]
    fn workout_glance_without_a_pushed_workout_is_honestly_inactive() {
        let rec = snapshot(RecordState::Recording, 2_100.0);
        assert!(rec.workout.is_none());
        let rows = page_rows(
            Page::Workout,
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
            page_hero(Page::Workout, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        assert_eq!(rows[2], header("WORKOUT --", "REC"));
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
    }

    #[test]
    fn workout_hero_reads_kilometres_past_a_thousand_metres() {
        let mut rec = snapshot(RecordState::Recording, 2_100.0);
        let mut w = workout_view();
        w.remaining_m = 9_600;
        rec.workout = Some(w);
        assert_eq!(
            page_hero(Page::Workout, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "9.60"
        );
        // The unit moved to its own channel, which is what lets the number
        // itself render in the numeral face: `9.60 KM` had a space and two
        // letters the faces cannot spell, so the whole hero fell back to the
        // pixel-doubled text font.
        assert_eq!(page_hero_unit(Page::Workout, Some(&rec), None), Some("KM"));
        assert!(crate::ui_frame::numeral_hero("9.60"));
    }

    #[test]
    fn guided_run_glance_without_an_armed_run_is_honestly_inactive() {
        // Recording with nothing armed: the page says so instead of a 0/0 cue
        // count that reads as a guided run that has finished.
        let rec = snapshot(RecordState::Recording, 2_100.0);
        assert!(rec.guided_run.is_none());
        let rows = page_rows(
            Page::GuidedRun,
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
            page_hero(Page::GuidedRun, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        assert_eq!(rows[3], header("GUIDED --", "REC"));
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
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
        // The idle faces keep their plain BPM — zones frame a recording.
        let rows = face_rows(Some(&fix()), Some(152), None, None, 42);
        assert_eq!(rows[6].as_str(), "HR 152 BPM ALT 1624 M");
        let rows = diag_rows(Some(&fix()), Some(152), None, 42);
        assert_eq!(rows[7].as_str(), "HR   152 BPM");
    }

    #[test]
    fn idle_recorder_shows_the_status_face_not_the_dashboard() {
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&snapshot(RecordState::Idle, 0.0)),
            None,
            42,
            GnssMode::Performance,
            IdleView::Diagnostics,
            None,
            None,
        );
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[1].as_str(), "MODE PERF EST 110H");
    }

    #[test]
    fn idle_mode_row_pairs_each_mode_with_its_projected_hours() {
        // The BTN3 mode picker's read-out: the tag plus the (projection-marked)
        // battery figure, one per mode — row 1 on the diagnostics view, the
        // bottom row on the home view.
        for (mode, expected) in [
            (GnssMode::Performance, "MODE PERF EST 110H"),
            (GnssMode::Balanced, "MODE BAL  EST 180H"),
            (GnssMode::Expedition, "MODE EXP  EST 220H"),
        ] {
            let rows = super::face_rows(
                Some(&fix()),
                None,
                None,
                None,
                42,
                mode,
                IdleView::Diagnostics,
                None,
                None,
            );
            assert_eq!(rows[1].as_str(), expected);
            assert!(rows[1].len() <= COLS);
            let rows = super::face_rows(
                Some(&fix()),
                None,
                None,
                None,
                42,
                mode,
                IdleView::Home,
                None,
                None,
            );
            assert_eq!(rows[8].as_str(), expected);
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
            IdleView::Home,
            None,
            None,
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
            IdleView::Home,
            None,
            None,
        );
        assert_eq!(rows[8].as_str(), "     8 SATS BAL");
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
            IdleView::Home,
            None,
            None,
        );
        assert_eq!(rows[8].as_str(), "     STALE 40S PERF");
        let rows = super::face_rows(
            Some(&fix()),
            None,
            Some(&rec),
            None,
            aged,
            GnssMode::Expedition,
            IdleView::Home,
            None,
            None,
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
            IdleView::Home,
            None,
            None,
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
            IdleView::Diagnostics,
            None,
            None,
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
                    IdleView::Home,
                    None,
                    None,
                );
                for row in rows {
                    assert!(row.len() <= COLS, "row too wide in {:?}: {:?}", mode, row);
                }
            }
            for view in [IdleView::Home, IdleView::Diagnostics] {
                let idle = super::face_rows(
                    Some(&fix()),
                    Some(u16::MAX),
                    None,
                    None,
                    999_999,
                    mode,
                    view,
                    None,
                    None,
                );
                for row in idle {
                    assert!(
                        row.len() <= COLS,
                        "idle row too wide in {:?} {:?}: {:?}",
                        mode,
                        view,
                        row
                    );
                }
            }
        }
    }

    fn nav_status(along_m: f64, off_m: f64, alerting: bool) -> NavView {
        NavView::Status(NavStatus {
            along_m,
            off_m,
            alerting,
            next_turn: None,
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        // No hero — the map panel owns rows 1-6 — and no gutter icon above the
        // GPS row it shares with every other page.
        assert!(page_hero(Page::Nav, Some(152), Some(&rec), None).is_none());
        only_the_gps_icon(Page::Nav, &rec, 42);
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
        assert_eq!(rows[7].as_str(), "NOT SYNCED");
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
        assert_eq!(rows[8].as_str(), "     ACQUIRING PERF");
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

    fn ice_card() -> ice::IceCard {
        ice::IceCard::new(
            "ALEX MORGAN",
            "O NEG",
            "PENICILLIN, ASTHMA",
            "JAMIE MORGAN",
            "+1 555 0134",
        )
        .unwrap()
    }

    fn ice_rows(card: Option<&ice::IceCard>) -> [Row; ROWS] {
        super::face_rows(
            Some(&fix()),
            Some(150),
            None,
            None,
            42,
            GnssMode::Performance,
            IdleView::Ice,
            None,
            card,
        )
    }

    #[test]
    fn the_ice_face_gives_every_line_its_own_row() {
        // A responder reading a stranger's wrist cannot expand an
        // abbreviation, so nothing here shares a row with a label it would
        // have to be squeezed beside — and nothing clips.
        let card = ice_card();
        let rows = ice_rows(Some(&card));
        assert_eq!(rows[0].as_str(), "ICE / MEDICAL ID");
        assert_eq!(rows[1].as_str(), "ALEX MORGAN");
        assert_eq!(rows[2].as_str(), "BLOOD O NEG");
        assert_eq!(rows[3].as_str(), "ALLERGY / CONDITION");
        assert_eq!(rows[4].as_str(), "PENICILLIN, ASTHMA");
        assert_eq!(rows[5].as_str(), "EMERGENCY CONTACT");
        assert_eq!(rows[6].as_str(), "JAMIE MORGAN");
        assert_eq!(rows[7].as_str(), "+1 555 0134");
        for (i, row) in rows.iter().enumerate() {
            assert!(row.len() <= COLS, "row {i} overflows: {row:?}");
        }
    }

    #[test]
    fn an_empty_ice_field_reads_as_nothing_recorded_not_as_a_blank_row() {
        // A runner with no known allergies still has a card; the row must say
        // so, because an empty row is indistinguishable from a failed render.
        let card = ice::IceCard::new("ALEX MORGAN", "", "", "JAMIE", "").unwrap();
        let rows = ice_rows(Some(&card));
        assert_eq!(rows[2].as_str(), "BLOOD --");
        assert_eq!(rows[4].as_str(), "--");
        assert_eq!(rows[6].as_str(), "JAMIE");
        assert_eq!(rows[7].as_str(), "--");
    }

    #[test]
    fn no_ice_card_says_so_rather_than_showing_five_dashes() {
        // Five `--` rows would read as a runner who declined to answer. The
        // honest statement is that nothing was ever synced — and a card
        // cleared to all-blank is the same fact, so it takes the same words.
        for card in [None, Some(ice::IceCard::new("", "", "", "", "").unwrap())] {
            let rows = ice_rows(card.as_ref());
            assert_eq!(rows[0].as_str(), "ICE / MEDICAL ID");
            assert_eq!(rows[1].as_str(), "");
            assert_eq!(rows[2].as_str(), "NOT SYNCED");
            assert_eq!(rows[3].as_str(), "SET VIA PHONE SYNC");
        }
    }

    #[test]
    fn the_ice_face_never_leaks_into_a_run_view() {
        // Idle-only, like the other two idle faces: with a run under way the
        // rows belong to the run whatever the idle view last was.
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let card = ice_card();
        let rows = super::face_rows(
            Some(&fix()),
            Some(150),
            Some(&rec),
            None,
            42,
            GnssMode::Performance,
            IdleView::Ice,
            None,
            Some(&card),
        );
        for row in rows.iter() {
            assert!(
                !row.as_str().contains("MORGAN"),
                "the card reached a run view: {row:?}"
            );
        }
    }

    fn climb_rows(view: crate::climb::ClimbView) -> [Row; ROWS] {
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        rec.climb = view;
        page_rows(
            Page::Climb,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        )
    }

    fn climb_hero(view: crate::climb::ClimbView) -> Row {
        let mut rec = snapshot(RecordState::Recording, 5_000.0);
        rec.climb = view;
        page_hero(Page::Climb, None, Some(&rec), None).unwrap()
    }

    const ON_A_CLIMB: crate::climb::ActiveClimb = crate::climb::ActiveClimb {
        gain_m: 120.0,
        distance_m: 1_400.0,
        avg_grade_pct: 8.571,
    };
    const CREST: crate::climb::CrestAhead = crate::climb::CrestAhead {
        distance_m: 600.0,
        gain_m: 80.0,
        avg_grade_pct: 13.333,
    };

    #[test]
    fn the_climb_page_leads_with_what_is_left_when_a_course_names_a_crest() {
        // On a climb, what remains outranks what is done — so the crest block
        // takes the hero and the top rows, and the banked climb follows.
        let rows = climb_rows(crate::climb::ClimbView {
            active: Some(ON_A_CLIMB),
            ahead: Some(CREST),
        });
        assert_eq!(rows[2].as_str(), "TO CREST");
        assert_eq!(rows[3].as_str(), "IN      600 M");
        assert_eq!(rows[4].as_str(), "GRADE   13%");
        assert_eq!(rows[6].as_str(), "CLIMBED 120 M");
        assert_eq!(rows[7].as_str(), "OVER    1.4 KM");
        assert_eq!(
            climb_hero(crate::climb::ClimbView {
                active: Some(ON_A_CLIMB),
                ahead: Some(CREST),
            })
            .as_str(),
            "80"
        );
    }

    #[test]
    fn without_a_course_the_climb_page_reports_only_what_is_banked() {
        // The watch cannot see the hill, so there is no crest row to fill —
        // and a `--` remaining would read as a crest at zero metres.
        let view = crate::climb::ClimbView {
            active: Some(ON_A_CLIMB),
            ahead: None,
        };
        let rows = climb_rows(view);
        assert_eq!(rows[2].as_str(), "CLIMBED");
        assert_eq!(rows[3].as_str(), "OVER    1.4 KM");
        assert_eq!(rows[4].as_str(), "GRADE   9%");
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(climb_hero(view).as_str(), "120");
    }

    #[test]
    fn flat_ground_is_settled_not_unsynced() {
        // Nothing underfoot and nothing ahead is a real answer. Saying NOT
        // SYNCED would send a runner looking for a phone over a page that is
        // working exactly as intended.
        let rows = climb_rows(crate::climb::ClimbView::default());
        assert_eq!(rows[2].as_str(), "CLIMB --");
        assert_eq!(rows[4].as_str(), "NO CLIMB");
        assert_eq!(rows[5].as_str(), "", "a settled state owes no remedy line");
        assert_eq!(
            climb_hero(crate::climb::ClimbView::default()).as_str(),
            "--"
        );
    }

    #[test]
    fn a_crest_before_the_detector_opens_a_climb_still_shows() {
        // The two halves are independent: a course can name the col ahead
        // before 20 m of gain has been banked, and holding that back until
        // the detector agrees would blank the page at the foot of the climb —
        // exactly when it is most useful.
        let rows = climb_rows(crate::climb::ClimbView {
            active: None,
            ahead: Some(CREST),
        });
        assert_eq!(rows[2].as_str(), "TO CREST");
        assert_eq!(rows[6].as_str(), "", "no banked block without a climb");
    }

    #[test]
    fn waypoint_page_reads_like_back_to_start_about_a_different_anchor() {
        let mut rec = snapshot(RecordState::Recording, 100.0);
        rec.waypoint = Some(crate::waypoints::WaypointView {
            distance_m: 250.0,
            bearing_deg: 45.0,
            count: 3,
            marked_uptime_s: 10,
        });
        rec.waypoint_count = 3;
        let nav = nav_east(20, 6.0); // heading due east
        let rows = page_rows(
            Page::Waypoint,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            Some(&nav),
            20,
            false,
        );
        assert_eq!(rows[2].as_str(), "TO WPT");
        assert_eq!(rows[3].as_str(), "HDG   E");
        assert_eq!(rows[4].as_str(), "BRG   NE");
        assert_eq!(rows[5].as_str(), "AGO   0:10");
        assert_eq!(rows[6].as_str(), "MARKS 3");
        assert_eq!(
            page_hero(Page::Waypoint, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "250"
        );
        // Past a kilometre the hero switches unit exactly where the
        // back-to-start hero does — one shape for one question.
        rec.waypoint = Some(crate::waypoints::WaypointView {
            distance_m: 1_500.0,
            ..rec.waypoint.unwrap()
        });
        let rows = page_rows(
            Page::Waypoint,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            Some(&nav),
            20,
            false,
        );
        assert_eq!(rows[2].as_str(), "TO WPT");
        assert_eq!(
            page_hero(Page::Waypoint, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1.50"
        );
    }

    #[test]
    fn waypoint_page_distinguishes_nothing_marked_from_no_position_yet() {
        // Nothing marked: the reason names the gesture, because a hold has no
        // affordance to discover and this page is where it can be learned.
        let mut rec = snapshot(RecordState::Recording, 100.0);
        let rows = page_rows(
            Page::Waypoint,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            20,
            false,
        );
        assert_eq!(rows[2].as_str(), "WAYPOINT --");
        assert_eq!(rows[4].as_str(), "NO WAYPOINTS");
        assert_eq!(rows[5].as_str(), "HOLD BTN5 TO MARK");
        // Marks restored from flash with no anchor this run yet: a different
        // fact, and telling the runner to mark another would be nonsense.
        rec.waypoint_count = 2;
        let rows = page_rows(
            Page::Waypoint,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            20,
            false,
        );
        assert_eq!(rows[4].as_str(), "AWAITING FIX");
        assert_eq!(rows[5].as_str(), "");
    }

    #[test]
    fn a_mark_stamped_after_the_clock_reads_zero_rather_than_centuries() {
        // A restored mark carries the PREVIOUS boot's uptime, which can sit
        // far ahead of this boot's — the age must saturate, not wrap.
        let mut rec = snapshot(RecordState::Recording, 100.0);
        rec.waypoint = Some(crate::waypoints::WaypointView {
            distance_m: 40.0,
            bearing_deg: 0.0,
            count: 1,
            marked_uptime_s: 90_000,
        });
        rec.waypoint_count = 1;
        let rows = page_rows(
            Page::Waypoint,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            20,
            false,
        );
        assert_eq!(rows[5].as_str(), "AGO   0:00");
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
        assert_eq!(rows[2].as_str(), "TO START");
        assert_eq!(rows[3].as_str(), "HDG  E");
        assert_eq!(rows[4].as_str(), "BRG  W");
        // A live arrow: its text spot stays blank for the app's drawing.
        assert_eq!(rows[6].as_str(), "");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::BackToStart, &rec, 20);
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
        assert_eq!(rows[2].as_str(), "TO START");
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
            required_pace_s_per_km: Some(360.0),
            limit_passed: false,
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
        assert_eq!(rows[0].as_str(), "");
        assert_eq!(rows[3], header("CUTOFF  ON", "REC"));
        assert_eq!(rows[4].as_str(), "TO   10.00 KM");
        assert_eq!(rows[5].as_str(), "ETA  1:30:00");
        assert_eq!(rows[6].as_str(), "NEED 6:00 /KM");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        only_the_gps_icon(Page::CutoffEta, &rec, 42);
    }

    #[test]
    fn cutoff_glance_honest_inactive_states() {
        // No legs loaded: honestly unfed with the how-to hint. The watch cannot
        // tell "this course has no cut-offs" from "no course was pushed" — it
        // sees one absent field — so it claims neither.
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
        assert_eq!(rows[3], header("CUTOFF --", "REC"));
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
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
            required_pace_s_per_km: None,
            limit_passed: false,
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

        // A cutoff ahead whose limit has passed: no pace can make it, so the
        // NEED row reads `--` rather than a number the runner could chase.
        let mut expired = snapshot(RecordState::Recording, 500.0);
        expired.cutoff = Some(crate::cutoff_eta::CutoffEta {
            has_cutoff: true,
            distance_to_m: 10_000.0,
            projected_arrival_elapsed_s: Some(11_600),
            margin_s: Some(-4_400),
            required_pace_s_per_km: None,
            limit_passed: true,
            status: crate::cutoff_eta::CutoffEtaStatus::Behind,
        });
        let rows = page_rows(
            Page::CutoffEta,
            Some(&fix()),
            None,
            Some(&expired),
            None,
            NavView::NoCourse,
            None,
            42,
            true,
        );
        assert_eq!(rows[3], header("CUTOFF  BEHIND", "REC"));
        assert_eq!(rows[6].as_str(), "NEED --");
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        // Hero echoes the 10K rung and is a real time, not `--`.
        let hero = page_hero(Page::RacePredictor, None, Some(&rec), None).unwrap();
        assert_ne!(hero.as_str(), "--");
        only_the_gps_icon(Page::RacePredictor, &rec, 42);
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        // Hero echoes the easy pace and is a real time, not `--`.
        let hero = page_hero(Page::TrainingPaces, None, Some(&rec), None).unwrap();
        assert_ne!(hero.as_str(), "--");
        only_the_gps_icon(Page::TrainingPaces, &rec, 42);
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
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
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
        assert_eq!(rows[0].as_str(), "");
        assert_eq!(rows[3], header("FITNESS SWEET", "REC"));
        assert_eq!(rows[4].as_str(), "VO2 MAX  52");
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        assert_eq!(
            page_hero(Page::Fitness, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "52"
        );
        only_the_gps_icon(Page::Fitness, &rec, 42);
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
        assert_eq!(rows[3], header("FITNESS REST", "REC"));
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
        assert_eq!(rows[3], header("FITNESS --", "REC"));
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
        assert_eq!(rows[8].as_str(), "     8 SATS PERF");
        // Hero echoes the current (latest) altitude, not `--`.
        assert_eq!(
            page_hero(Page::ElevationProfile, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1250"
        );
        only_the_gps_icon(Page::ElevationProfile, &rec, 42);
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
        assert_eq!(rows[4].as_str(), "AWAITING BARO");
        // A sensor the runner is waiting on carries no phone-sync remedy: there
        // is nothing to do but let the barometer produce its first sample.
        assert_eq!(rows[5].as_str(), "");
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
        assert_eq!(rows[5].as_str(), "SET VIA PHONE SYNC");

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
        // The year's distance is the hero now, with its unit beside it; the
        // rows carry what the hero cannot.
        assert_eq!(
            page_hero(Page::Recap, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1500"
        );
        assert_eq!(page_hero_unit(Page::Recap, Some(&rec), None), Some("KM"));
        assert!(rows[4].as_str().contains("42 KM"));

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
        assert_eq!(
            page_hero(Page::RaceDay, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "3"
        );
        assert_eq!(
            page_hero_unit(Page::RaceDay, Some(&rec), None),
            Some("DAYS")
        );
        assert_eq!(rows[4].as_str(), "TO GO");
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
        assert_eq!(
            page_hero(Page::PrRecency, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "60"
        );
        assert_eq!(rows[4].as_str(), "2 MONTHS");

        // Inside a week the bucket row would only repeat the hero, so it is
        // left blank rather than saying `5 DAYS` under a big 5 DAYS.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.pr_recency = Some(crate::record::PrRecencyView { days_ago: 5 });
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
        assert_eq!(
            page_hero(Page::PrRecency, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "5"
        );
        assert_eq!(rows[4].as_str(), "");
    }

    #[test]
    fn route_elev_glance_separates_no_course_no_elevation_and_a_drawn_profile() {
        let rows_for = |snap: &Snapshot| {
            page_rows(
                Page::RouteElev,
                Some(&fix()),
                None,
                Some(snap),
                None,
                NavView::NoCourse,
                None,
                42,
                false,
            )
        };

        // No course pushed at all.
        let rows = rows_for(&snapshot(RecordState::Recording, 5000.0));
        assert_eq!(rows[2].as_str(), "CRS ELEV --");
        assert_eq!(rows[4].as_str(), "NOT SYNCED");

        // A course pushed WITHOUT elevation: geometry only, no fabricated shape.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.route_elev = Some(crate::record::RouteElevView {
            gain_m: 0,
            loss_m: 0,
            points: 48,
            total_m: 42_195,
            samples: [0; crate::record::COURSE_PROFILE_CAP],
            len: 0,
        });
        let rows = rows_for(&rec);
        assert_eq!(rows[2].as_str(), "CRS ELEV --");
        assert_eq!(rows[4].as_str(), "NO COURSE ELEV");
        // Settled, not unfed: the course IS synced, so no sync remedy displaces
        // the geometry row. Its length moved to the hero, so the row keeps only
        // the point count.
        assert_eq!(rows[5].as_str(), "48 PTS");
        assert_eq!(
            page_hero(Page::RouteElev, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "42.1"
        );

        // With a profile: the vert totals ride row 2 and rows 3..8 are left to
        // the drawn shape.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.route_elev = Some(crate::record::RouteElevView {
            gain_m: 1820,
            loss_m: 1755,
            points: 48,
            total_m: 42_195,
            samples: [1500; crate::record::COURSE_PROFILE_CAP],
            len: crate::record::COURSE_PROFILE_CAP,
        });
        let rows = rows_for(&rec);
        assert_eq!(rows[2].as_str(), "CRS D+1820 D-1755");
        // The hero is the course's LENGTH — the gain / loss pair already owns
        // the page's one text row, and rows 3..8 are the drawn shape.
        assert_eq!(
            page_hero(Page::RouteElev, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "42.1"
        );
        assert_eq!(
            page_hero_unit(Page::RouteElev, Some(&rec), None),
            Some("KM")
        );
        for r in rows.iter().take(8).skip(3) {
            assert!(r.is_empty(), "row reserved for the profile shape: {:?}", r);
        }
    }

    #[test]
    fn plan_adaptive_glance_renders_trend_weeks_changes_and_the_fatigue_hold() {
        // Empty state — nothing pushed yet.
        let inactive = snapshot(RecordState::Recording, 5000.0);
        let rows = page_rows(
            Page::PlanAdaptive,
            Some(&fix()),
            None,
            Some(&inactive),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[2].as_str(), "ADAPT --");
        assert_eq!(rows[4].as_str(), "NOT SYNCED");

        // A sustained under-trend with proposed changes.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.plan_adaptive = Some(crate::record::PlanAdaptiveView {
            trend: 1,
            confidence: 1,
            flagged_weeks: 2,
            window_weeks: 3,
            changes: 1,
            fitness_gated: false,
        });
        let rows = page_rows(
            Page::PlanAdaptive,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[2].as_str(), "ADAPT   DO MORE");
        assert_eq!(rows[4].as_str(), "WEEKS   2/3");
        // The proposed-change count is the hero; confidence moved up into the
        // row it vacated.
        assert_eq!(
            page_hero(Page::PlanAdaptive, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "1"
        );
        assert_eq!(rows[5].as_str(), "CONF    MEDIUM");
        assert_eq!(rows[6].as_str(), "");

        // The fatigue hold: a suppressed do-more shows the hold, not a
        // confidence that pretends a verdict was issued.
        let mut rec = snapshot(RecordState::Recording, 5000.0);
        rec.plan_adaptive = Some(crate::record::PlanAdaptiveView {
            trend: 0,
            confidence: 0,
            flagged_weeks: 3,
            window_weeks: 3,
            changes: 0,
            fitness_gated: true,
        });
        let rows = page_rows(
            Page::PlanAdaptive,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[2].as_str(), "ADAPT   ON TRACK");
        assert_eq!(rows[4].as_str(), "WEEKS   3/3");
        assert_eq!(rows[5].as_str(), "HELD FATIGUE");
    }

    /// The row a page writes its empty-body reason on: [`UNFED_REASON_ROW`] for
    /// every glance, and the Nav page's info row (its map panel owns rows 1-6).
    fn reason_row(page: Page) -> usize {
        if matches!(page, Page::Nav) {
            NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS
        } else {
            UNFED_REASON_ROW
        }
    }

    /// What each page says when nothing has fed it — exhaustive over [`Page`] on
    /// purpose, so adding a page is a compile error until its empty state has
    /// been classified. `None` is the live-metric pages, whose numbers are
    /// legitimately zero at the start of a run and owe no reason line.
    fn declared_unfed(page: Page) -> Option<Unfed> {
        match page {
            Page::Dashboard
            | Page::Distance
            | Page::Pace
            | Page::Lap
            | Page::Zones
            | Page::Splits
            | Page::BackToStart => None,
            Page::Pacer
            | Page::GuidedRun
            | Page::Workout
            | Page::Nav
            | Page::TurnCue
            | Page::CutoffEta
            | Page::Roadbook
            | Page::Fuel
            | Page::GearWear
            | Page::TrainingPaces
            | Page::Fitness
            | Page::Readiness
            | Page::Goals
            | Page::RaceDay
            | Page::PlanReplan
            | Page::PlanAdaptive
            | Page::Recap
            | Page::Streaks
            | Page::RunStats
            | Page::PrRecency
            | Page::RouteSimplify
            | Page::RouteElev
            | Page::AutoEffort
            | Page::Daylight => Some(Unfed::NotSynced),
            Page::ElevationProfile => Some(Unfed::AwaitingBaro),
            Page::RacePredictor => Some(Unfed::NeedOneKm),
            Page::TrainingLoad => Some(Unfed::NeedDistance),
            Page::DistanceBand => Some(Unfed::NoRaceBand),
            Page::Waypoint => Some(Unfed::NoWaypoints),
            Page::Climb => Some(Unfed::NoClimb),
        }
    }

    /// The drift guard for the empty-state vocabulary: every page's unfed body
    /// must use a reason from [`crate::unfed`] and no page may invent its own
    /// phrasing. This is the assertion that fails when a new page reaches for
    /// `NO WIDGET` — the per-page string tests above pin one page each, this
    /// pins that they all speak the same language.
    #[test]
    fn every_page_unfed_body_speaks_one_vocabulary() {
        let reasons = Unfed::ALL.map(|u| u.reason());
        let sanctioned =
            |text: &str| reasons.contains(&text) || text == crate::unfed::PHONE_SYNC_HINT;

        // A 15 km run so the live-metric pages have real numbers to render and
        // the distance band is genuinely between windows; nothing pushed, no
        // baro, no course.
        let unfed = snapshot(RecordState::Recording, 15_000.0);
        let mut p = Page::default();
        loop {
            let rows = page_rows(
                p,
                Some(&fix()),
                Some(140),
                Some(&unfed),
                None,
                NavView::NoCourse,
                None,
                42,
                false,
            );

            match declared_unfed(p) {
                Some(why) => {
                    assert_eq!(
                        rows[reason_row(p)].as_str(),
                        why.reason(),
                        "page {p:?} does not render its declared unfed reason"
                    );
                    let hint = rows[UNFED_HINT_ROW].as_str();
                    match why.hint() {
                        // The Nav page has no row to spare under its map panel,
                        // so it carries the reason without the remedy.
                        Some(h) if !matches!(p, Page::Nav) => {
                            assert_eq!(hint, h, "page {p:?} drops the remedy its class owes")
                        }
                        Some(_) => {}
                        None => assert_ne!(
                            hint,
                            crate::unfed::PHONE_SYNC_HINT,
                            "page {p:?} offers a phone-sync remedy for a state the phone \
                             cannot fix"
                        ),
                    }
                }
                None => {
                    for row in &rows {
                        assert!(
                            !sanctioned(row.as_str()),
                            "page {p:?} claims an unfed state it did not declare: {row:?}"
                        );
                    }
                }
            }

            // Nothing anywhere may reach for empty-state-shaped wording that is
            // not in the vocabulary. A row carrying `--` is exempt: that marker
            // is the sanctioned way to say one VALUE is absent (`NEED --`,
            // `WEAR --`), and is not a reason line.
            for row in &rows {
                let text = row.as_str();
                if text.contains("--") {
                    continue;
                }
                if ["NO ", "NOT ", "AWAITING ", "NEED "]
                    .iter()
                    .any(|prefix| text.starts_with(prefix))
                {
                    assert!(
                        sanctioned(text),
                        "page {p:?} invents empty-state wording: {row:?}"
                    );
                }
            }

            p = p.next();
            if p == Page::default() {
                break;
            }
        }
    }

    #[test]
    fn training_load_rolling_row_names_the_phone_in_the_shared_vocabulary() {
        // The rolling CTL/ATL/TSB trend lives on the phone, and the row saying so
        // used to run its label into its value ("ROLLINGSYNC" — `{:<7}` pads a
        // seven-character label to nothing).
        let mut rec = snapshot(RecordState::Recording, 12_000.0);
        rec.training_stress = Some(84.0);
        rec.moving_s = 3_725;
        let rows = page_rows(
            Page::TrainingLoad,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[3], header("LOAD   DIST", "REC"));
        assert_eq!(rows[4].as_str(), "DIST   12.00 KM");
        assert_eq!(rows[5].as_str(), "MOVING 1:02:05");
        assert_eq!(rows[6].as_str(), "ROLLING NOT SYNCED");
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn training_load_shows_the_synced_rolling_trio_and_the_trimp_label() {
        let mut rec = snapshot(RecordState::Recording, 12_000.0);
        rec.training_stress = Some(84.0);
        rec.training_stress_trimp = true;
        rec.load_trend = Some(crate::training_load::LoadTrendView {
            ctl: 82.4,
            atl: 95.0,
            tsb: -12.6,
        });
        rec.moving_s = 3_725;
        let rows = page_rows(
            Page::TrainingLoad,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[3], header("LOAD   TRIMP", "REC"));
        assert_eq!(rows[6].as_str(), "CTL 82  ATL 95");
        assert_eq!(rows[7].as_str(), "FORM   -12");
    }

    #[test]
    fn daylight_glance_counts_down_to_sunrise_before_dawn() {
        // The bench_jog opening fix (40.015°N, 07:30 UTC, 2026-07-08) at the
        // sim's demo Mountain offset: 01:30 local, pre-dawn — the same case
        // golden-tested in `daylight::tests`.
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let rows = super::page_rows(
            Page::Daylight,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
            GnssMode::Performance,
            IdleView::Home,
            Some(-360),
            None,
        );
        assert_eq!(rows[3], header("SUNRISE", "REC"));
        assert_eq!(rows[4].as_str(), "AT       04:34");
        assert_eq!(rows[5].as_str(), "DAYLIGHT 14:53");
        assert_eq!(
            super::page_hero(
                Page::Daylight,
                Some(&fix()),
                None,
                Some(&rec),
                None,
                42,
                Some(-360)
            )
            .unwrap()
            .as_str(),
            "3:03"
        );
    }

    #[test]
    fn daylight_glance_unfed_states_name_the_missing_input() {
        let rec = snapshot(RecordState::Recording, 5_000.0);
        // No timezone: the phone owns it, whatever the fix carries.
        let rows = page_rows(
            Page::Daylight,
            Some(&fix()),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
        );
        assert_eq!(rows[3], header("DAYLIGHT --", "REC"));
        assert_eq!(rows[4].as_str(), "NOT SYNCED");
        assert_eq!(rows[5].as_str(), crate::unfed::PHONE_SYNC_HINT);
        assert_eq!(
            page_hero(Page::Daylight, None, Some(&rec), None)
                .unwrap()
                .as_str(),
            "--"
        );
        // Timezone synced, fix without an RMC date: wait for the receiver.
        let mut dateless = fix();
        dateless.date = None;
        let rows = super::page_rows(
            Page::Daylight,
            Some(&dateless),
            None,
            Some(&rec),
            None,
            NavView::NoCourse,
            None,
            42,
            false,
            GnssMode::Performance,
            IdleView::Home,
            Some(-360),
            None,
        );
        assert_eq!(rows[4].as_str(), "AWAITING FIX");
        assert_eq!(rows[5].as_str(), "", "a sensor wait owes no phone remedy");
    }

    #[test]
    fn daylight_glance_reports_a_polar_season_not_a_clock() {
        let rec = snapshot(RecordState::Recording, 5_000.0);
        let mut polar = fix();
        polar.lat_deg = 80.0;
        polar.time_of_day = Some(12 * 3600);
        for (month, day, reason) in [(12, 21, "POLAR NIGHT"), (6, 21, "MIDNIGHT SUN")] {
            polar.date = Some(daylight::Date {
                year: 2026,
                month,
                day,
            });
            let rows = super::page_rows(
                Page::Daylight,
                Some(&polar),
                None,
                Some(&rec),
                None,
                NavView::NoCourse,
                None,
                42,
                false,
                GnssMode::Performance,
                IdleView::Home,
                Some(0),
                None,
            );
            assert_eq!(rows[4].as_str(), reason);
            assert_eq!(rows[5].as_str(), "", "a settled state owes no remedy");
            assert_eq!(
                super::page_hero(
                    Page::Daylight,
                    Some(&polar),
                    None,
                    Some(&rec),
                    None,
                    42,
                    Some(0)
                )
                .unwrap()
                .as_str(),
                "--"
            );
        }
    }
}
