//! Face widgets: gauges, bars, the GPS signal meter, and the page indicator.
//!
//! Each public `draw_*_overlay` takes the same `watch_core` state the ui task
//! already holds and paints its pixels onto the shared framebuffer, folding in
//! the pure `gauge` / `statusbar` math so the whole widget — geometry included
//! — is exercised by `cargo test`, not just its arithmetic. Coordinates are
//! derived from the panel's cell grid so they track the text layout the face
//! renders underneath.
//!
//! Placement contract with `watch_core::face`: these overlays draw into cells
//! the face leaves blank on the matching page (the fuel page's row 3, the gear
//! page's row 5, the trailing bar columns of the zone / split / pacer rows, the
//! split page's rows 3..8). Change one side and the other must follow — the
//! tests here pin the columns each overlay owns, and
//! `overlay_never_paints_over_face_text` sweeps every pair for the collision
//! that contract exists to prevent, so adding a text row to a page whose bar
//! already owned it fails here instead of on the glass.

use sharp_mip::{Framebuffer, RowRules, HEIGHT, TEXT_COLS, TEXT_ROWS, WIDTH};
use watch_core::bar_chart::{bar_chart, Bar};
use watch_core::battery;
use watch_core::course::Course;
use watch_core::face;
use watch_core::fix::Fix;
use watch_core::gauge;
use watch_core::nav_map::{NavPanel, NavPanelGeom};
use watch_core::page_grid;
use watch_core::record::{Snapshot, COURSE_PROFILE_CAP};
use watch_core::statusbar::{self, PageIndicator};
use watch_core::trackback::{self, TrackbackView};

const CELL_W: usize = WIDTH / TEXT_COLS; // 8
const CELL_H: usize = HEIGHT / TEXT_ROWS; // 16

/// Left column (in pixels) where a single-metric page's in-row bar starts —
/// clear of the ~11-char label gutter the pacer / gear / fuel rows carry.
const BAR_X: usize = 11 * CELL_W; // 88
const BAR_W: usize = WIDTH - BAR_X - 3; // to just shy of the right edge
const BAR_H: usize = 8; // sits inside a 16-px row with 4 px of margin above/below

/// Vertical offset of a bar within its text row: centres the 8-px bar in the
/// 16-px cell.
const BAR_DY: usize = (CELL_H - BAR_H) / 2;

fn bar_y(row: usize) -> usize {
    row * CELL_H + BAR_DY
}

// ---------------------------------------------------------------------------
// GPS signal meter (idle status face)
// ---------------------------------------------------------------------------

const SIGNAL_TICKS: usize = statusbar::MAX_BARS as usize;
const TICK_W: usize = 4;
const TICK_GAP: usize = 2;
const TICK_STEP: usize = TICK_W + TICK_GAP;
const TICK_GROW: usize = 3; // each tick is 3 px taller than the one left of it
const TICK_BASE_H: usize = 4;

/// Total pixel width the [`draw_signal_bars`] meter occupies.
pub const SIGNAL_METER_W: usize = SIGNAL_TICKS * TICK_W + (SIGNAL_TICKS - 1) * TICK_GAP;

/// Draw the GPS acquisition-confidence meter: a rising staircase of
/// [`statusbar::MAX_BARS`] ticks whose bottom-right corner sits at
/// `(right_x, baseline_y)`. The leftmost `bars` ticks are filled, the rest are
/// hollow, so "searching" (0) still shows the empty frame and never a blank gap
/// the runner could mistake for "no widget".
pub fn draw_signal_bars(fb: &mut Framebuffer, right_x: usize, baseline_y: usize, bars: u8) {
    let left = (right_x + 1).saturating_sub(SIGNAL_METER_W);
    for i in 0..SIGNAL_TICKS {
        let h = TICK_BASE_H + i * TICK_GROW;
        let x = left + i * TICK_STEP;
        let top = (baseline_y + 1).saturating_sub(h);
        if (i as u8) < bars {
            fb.fill_rect(x, top, TICK_W, h, true);
        } else {
            fb.stroke_rect(x, top, TICK_W, h, true);
        }
    }
}

/// Idle-face GPS signal meter, top-right of the brand row (row 0), from the live
/// fix + its freshness. Drawn only on the idle status face; a run view shows the
/// per-row GPS glance instead.
pub fn draw_idle_signal(
    fb: &mut Framebuffer,
    fix: Option<&Fix>,
    uptime_s: u32,
    stale_after_s: u32,
) {
    let bars = statusbar::gps_bars(fix, uptime_s, stale_after_s);
    draw_signal_bars(fb, WIDTH - 2, CELL_H - 2, bars);
}

// ---------------------------------------------------------------------------
// Battery gauge (idle faces, title row)
// ---------------------------------------------------------------------------

const BATT_BODY_W: usize = 15;
const BATT_BODY_H: usize = 9;
const BATT_NUB_W: usize = 2;
const BATT_NUB_H: usize = 3;
const BATT_INNER_W: usize = BATT_BODY_W - 4; // 1-px frame + 1-px gap each side

/// Total pixel width the [`draw_battery`] icon occupies (body + terminal nub).
pub const BATTERY_W: usize = BATT_BODY_W + BATT_NUB_W;

const BATTERY_METER_GAP: usize = 6;

/// Right edge (x) of the idle battery icon: immediately left of the GPS
/// meter's leftmost tick with [`BATTERY_METER_GAP`] clear pixels between, so
/// the two widgets read as separate glyphs.
pub const BATTERY_RIGHT_X: usize = WIDTH - 1 - SIGNAL_METER_W - BATTERY_METER_GAP;

const BATTERY_TOP_Y: usize = 3;

/// Draw a battery outline (terminal nub on the right) with a proportional
/// left-anchored fill, its rightmost pixel at `right_x`. The fill fraction and
/// the low threshold come from `watch_core::battery` (the `gauge` split:
/// decision in core, pixels here). 0 draws the empty outline — like the
/// signal meter's zero-bar frames, an empty battery must never read as "no
/// widget" — and at/below `battery::LOW_PCT` an exclamation joins the empty
/// body: blinking is off the table (animations are gated to the post-press
/// window, where this icon yields the row), so low must read from a steady
/// frame.
pub fn draw_battery(fb: &mut Framebuffer, right_x: usize, top_y: usize, percent: u8) {
    let left = (right_x + 1).saturating_sub(BATTERY_W);
    fb.stroke_rect(left, top_y, BATT_BODY_W, BATT_BODY_H, true);
    fb.fill_rect(
        left + BATT_BODY_W,
        top_y + (BATT_BODY_H - BATT_NUB_H) / 2,
        BATT_NUB_W,
        BATT_NUB_H,
        true,
    );
    let fill_w = (BATT_INNER_W as f32 * battery::fill_fraction(percent) + 0.5) as usize;
    if fill_w > 0 {
        fb.fill_rect(left + 2, top_y + 2, fill_w, BATT_BODY_H - 4, true);
    }
    if battery::is_low(percent) {
        let ex = left + 2 + BATT_INNER_W / 2;
        fb.fill_rect(ex, top_y + 2, 2, 3, true);
        fb.fill_rect(ex, top_y + 6, 2, 1, true);
    }
}

/// Idle-face battery gauge on the title row, left of the GPS meter. Drawn
/// only while the title shows the short brand: `title_busy` is true inside
/// the post-press window (the BTN3 hint runs to within three cells of the
/// meter, straight through these columns) and while a transient 2x banner
/// owns the title band. `None` — no plausible battery stream (the sim, a
/// USB-powered DK) — draws nothing, the honest absent state every other
/// missing signal shows.
pub fn draw_idle_battery(fb: &mut Framebuffer, percent: Option<u8>, title_busy: bool) {
    if title_busy {
        return;
    }
    let Some(pct) = percent else {
        return;
    };
    draw_battery(fb, BATTERY_RIGHT_X, BATTERY_TOP_Y, pct);
}

// ---------------------------------------------------------------------------
// Page-position indicator (run view, top edge)
// ---------------------------------------------------------------------------

/// Thumb rows, above the 1-px track on row 3.
const THUMB_H: usize = 3;

/// The run-view page-position indicator: a full-width track along the top edge
/// with a filled thumb over the active page's segment, so paging is a thumb
/// sliding left-to-right. Sits in the top 4 px — blank on every page because the
/// 2x hero's ink starts well below it and the state tag rides row 0's right cells.
/// The span comes from `statusbar::page_thumb`, so the rounding that decides
/// which columns the segment owns is host-tested arithmetic rather than a
/// division inlined here.
pub fn draw_page_indicator(fb: &mut Framebuffer, indicator: PageIndicator) {
    let Some(thumb) = statusbar::page_thumb(indicator, WIDTH) else {
        return;
    };
    fb.hline(0, 3, WIDTH, true);
    fb.fill_rect(thumb.x, 0, thumb.w, THUMB_H, true);
}

// ---------------------------------------------------------------------------
// Page-grid cursor (the navigation-grid overview)
// ---------------------------------------------------------------------------

/// The page grid's cursor: a one-pixel frame around the selected cell's
/// four-glyph code. Geometry only — which cell comes from the host-tested
/// `page_grid::grid_cell`, and the codes themselves are text rows the ui task
/// draws from `page_grid::grid_rows`. The frame hugs the 32-px code inside
/// its own 16-px row band, so it never touches a neighbouring cell (columns
/// are 40 px apart) or the rows above/below.
pub fn draw_grid_cursor(fb: &mut Framebuffer, cell: (usize, usize)) {
    let (col, row) = cell;
    let x = col * page_grid::GRID_CELL_CHARS * CELL_W;
    let y = (page_grid::GRID_TOP_ROW + row) * CELL_H;
    fb.stroke_rect(x.saturating_sub(2), y, 4 * CELL_W + 3, CELL_H, true);
}

// ---------------------------------------------------------------------------
// Run-dashboard field grid (hairline dividers)
// ---------------------------------------------------------------------------

/// Horizontal rules start past the two icon-gutter cells: `draw_icon` blits
/// its full 16-px band after the row is drawn, so a rule crossing those
/// cells would be re-cleared — and its lines re-dirtied — every frame.
const RULE_X0: usize = 2 * CELL_W;

/// Draw one run-dashboard text row with its share of the Garmin-style field
/// grid composed in: a hairline over the first field row (closing the hero
/// band), one under every field but the last (the panel edge closes it), and
/// a vertical rule splitting the NOW | GAP pace pair. The rules ride
/// [`Framebuffer::draw_text_row_ruled`]'s single compare-write, so a resting
/// dashboard still flushes zero lines.
pub fn ruled_dashboard_row(fb: &mut Framebuffer, row: usize, text: &str) {
    let rules = RowRules {
        top: row == face::DASH_FIELD_TOP_ROW,
        bottom: (face::DASH_FIELD_TOP_ROW..TEXT_ROWS - 1).contains(&row),
        vline_x: (row == face::DASH_SPLIT_ROW)
            .then_some(face::DASH_SPLIT_COL * CELL_W + CELL_W / 2),
        x0: RULE_X0,
    };
    fb.draw_text_row_ruled(row, text, rules);
}

// ---------------------------------------------------------------------------
// Single-value gauges (pacer / gear / fuel pages)
// ---------------------------------------------------------------------------

/// Left edge of the pacer's in-row centre bar — past the widest `DIST` value
/// the face can write on row 7 (`DIST -99999 M`, 13 cells).
const PACER_BAR_X: usize = 14 * CELL_W;
const PACER_BAR_W: usize = WIDTH - PACER_BAR_X - 3;

/// The pacer page's ahead/behind gauge: a centre-out bar fed by
/// [`gauge::pacer_fill`]. No-op without a configured pacer goal, so the honest
/// "NO GOAL SET" text the face draws stands alone.
///
/// In-row on row 7, beside `DIST`, not full-width on row 3. Row 3 was the
/// original home — directly under the hero whose signed time the fill encodes —
/// but #609 gave that row to the race-phase line, and a full-width bar there
/// painted straight through it (the collision the `overlay_never_paints_over_*`
/// guard below now pins). The page carries nine rows of content in nine rows,
/// so there is no blank row to move to; row 7 is the one whose value agrees with
/// the bar in sign, which is what a centre-out bar communicates.
pub fn draw_pacer_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(status) = snap.pacer {
        fb.draw_center_bar(
            PACER_BAR_X,
            bar_y(7),
            PACER_BAR_W,
            BAR_H,
            gauge::pacer_fill(&status),
        );
    }
}

/// The gear page's wear gauge: a progress bar on row 5 fed by
/// [`gauge::gear_fill`], plus an end-of-bar alert block once the shoe is
/// [`gauge::gear_overdue`] so "replace me" reads without counting pixels.
pub fn draw_gear_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(gear) = snap.gear {
        fb.draw_progress_bar(BAR_X, bar_y(5), BAR_W, BAR_H, gauge::gear_fill(&gear));
        if gauge::gear_overdue(&gear) {
            fb.fill_rect(WIDTH - 3, 5 * CELL_H + 2, 2, CELL_H - 4, true);
        }
    }
}

/// The Climb page's crest thermometer (§ 430): a vertical gauge on the right
/// shoulder — the column of rows the crest and banked blocks leave blank —
/// filled bottom-up by [`ClimbView::crest_progress`], height banked over the
/// climb's whole height. Vertical because the number it draws IS a height.
/// No-op without both halves of the view: a fraction of an unknown total
/// would render a guess as progress.
///
/// [`ClimbView::crest_progress`]: watch_core::climb::ClimbView::crest_progress
pub fn draw_climb_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    let Some(frac) = snap.climb.crest_progress() else {
        return;
    };
    const X: usize = WIDTH - 26;
    const W: usize = 22;
    const Y: usize = 3 * CELL_H + 2;
    const H: usize = 5 * CELL_H - 6;
    fb.stroke_rect(X, Y, W, H, true);
    let inner_h = H - 2;
    let filled = (inner_h as f32 * frac.clamp(0.0, 1.0)) as usize;
    // Cleared above, filled below — the same erase-your-own-tail discipline
    // as draw_progress_bar, rotated: a shrinking fill must not strand ink.
    fb.fill_rect(X + 1, Y + 1, W - 2, inner_h - filled, false);
    fb.fill_rect(X + 1, Y + 1 + (inner_h - filled), W - 2, filled, true);
}

/// The fuel page's carry-load gauge: a progress bar on row 3 fed by
/// [`gauge::fuel_fill`] (share of the plan's carbohydrate riding in the next
/// carry-out). No-op without a loaded fuel plan, and no-op on the cadence
/// basis, which has no race for the carry to be a share of.
pub fn draw_fuel_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(fill) = snap.fuel.as_ref().and_then(gauge::fuel_fill) {
        fb.draw_progress_bar(BAR_X, bar_y(3), BAR_W, BAR_H, fill);
    }
}

/// Left edge of the workout step-progress bar — past the "STEP 14/64" text the
/// face writes on its row (the zone-bar in-row placement).
const WORKOUT_BAR_X: usize = 12 * CELL_W;
const WORKOUT_BAR_W: usize = WIDTH - WORKOUT_BAR_X - 3;

/// The workout page's step-progress gauge: an in-row bar beside the STEP
/// counter on row 7, fed by [`gauge::workout_fill`] (the active step's own end
/// condition, so a distance rep and a timed recovery fill the same way).
/// No-op without an armed workout or once it completes (the row reads DONE).
pub fn draw_workout_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    if let Some(w) = snap.workout {
        if !w.complete {
            fb.draw_progress_bar(
                WORKOUT_BAR_X,
                bar_y(7),
                WORKOUT_BAR_W,
                BAR_H,
                gauge::workout_fill(&w),
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Zone bars (zones page, rows 3..8)
// ---------------------------------------------------------------------------

/// Left column of the zone / split in-row bar — past the "Z1 12:34" (12-char)
/// label the face writes.
const ZONE_BAR_X: usize = 12 * CELL_W; // 96
const ZONE_BAR_W: usize = WIDTH - ZONE_BAR_X - 3;

/// The zones page's per-zone bars: one horizontal bar per zone row (rows 3..8),
/// each scaled to the fullest zone so the dominant effort reads at full width —
/// the pixel form of the `#` bars the face used to spell out. The live zone
/// (from [`gauge::current_zone`]) gets a hollow frame so a glance finds "where
/// am I now" among the five.
pub fn draw_zones_overlay(fb: &mut Framebuffer, snap: &Snapshot, hr_bpm: Option<u16>) {
    let max = snap.zone_time_s.iter().copied().max().unwrap_or(0);
    let current = hr_bpm.map(|bpm| gauge::current_zone(bpm, &snap.zone_cutoffs));
    for (i, &t) in snap.zone_time_s.iter().enumerate() {
        let row = 3 + i;
        let y = bar_y(row);
        if max > 0 {
            let w = (ZONE_BAR_W as u64 * t as u64 / max as u64) as usize;
            if w > 0 {
                fb.fill_rect(ZONE_BAR_X, y, w, BAR_H, true);
            }
        }
        if current == Some(i) {
            fb.stroke_rect(
                ZONE_BAR_X - 2,
                row * CELL_H + 2,
                ZONE_BAR_W + 4,
                CELL_H - 4,
                true,
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Splits histogram (splits page, rows 3..8)
// ---------------------------------------------------------------------------

const HIST_X: usize = 6;
const HIST_TOP_ROW: usize = 3;
const HIST_W: usize = WIDTH - 2 * HIST_X;
const HIST_H: usize = (TEXT_ROWS - HIST_TOP_ROW - 1) * CELL_H - 4; // rows 3..8, minus baseline gap
const HIST_GAP: usize = 4;

/// The splits page's pace-distribution histogram: the per-bucket banked
/// distance (slowest bucket left, fastest right) as bottom-aligned vertical
/// bars via [`bar_chart`], with a baseline rule. A histogram reads the *shape*
/// of where the run's distance sat, pace-wise, at a glance — what the per-row
/// `#` bars only approximated.
pub fn draw_splits_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    let py = HIST_TOP_ROW * CELL_H;
    let mut bars = [Bar {
        x: 0,
        y: 0,
        w: 0,
        h: 0,
    }; 8];
    let n = bar_chart(
        &snap.pace_bucket_m,
        HIST_W as u16,
        HIST_H as u16,
        HIST_GAP as u16,
        &mut bars,
    );
    fb.hline(HIST_X, py + HIST_H, HIST_W, true);
    for b in &bars[..n] {
        if b.h > 0 {
            fb.fill_rect(
                HIST_X + b.x as usize,
                py + b.y as usize,
                b.w as usize,
                b.h as usize,
                true,
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Mini-profile sparkline (elevation / pace shape)
// ---------------------------------------------------------------------------

/// Geometry description for a mini-profile: where it sits (a cell rect) and the
/// series it plots. The range it normalises against is derived from the samples
/// themselves, so a caller hands over raw elevation / pace values and gets a
/// shape that fills the cell. A future glance page owns the rect + supplies the
/// series; keeping it a plain struct lets the placement be unit-tested without a
/// live snapshot.
pub struct MiniProfile<'a> {
    pub x: usize,
    pub y: usize,
    pub w: usize,
    pub h: usize,
    pub samples: &'a [i32],
}

/// Draw a [`MiniProfile`] as a baseline-aligned sparkline via
/// [`Framebuffer::draw_sparkline`], auto-scaling the series to its own min..max
/// so the shape uses the full cell height. A flat series (min == max) or fewer
/// than two samples degrades to the baseline / a single point rather than a
/// misleading full-height line.
pub fn draw_mini_profile(fb: &mut Framebuffer, profile: &MiniProfile) {
    let (min, max) = profile
        .samples
        .iter()
        .fold((i32::MAX, i32::MIN), |(lo, hi), &v| (lo.min(v), hi.max(v)));
    fb.draw_sparkline(
        profile.x,
        profile.y,
        profile.w,
        profile.h,
        profile.samples,
        (min, max),
    );
}

/// The elevation-profile page's mini-profile: the rows the face leaves blank
/// below its vert-totals context row, full width with a small margin — the same
/// page-body rect the splits histogram uses.
const ELEV_PROFILE_X: usize = HIST_X;
const ELEV_PROFILE_Y: usize = HIST_TOP_ROW * CELL_H;
const ELEV_PROFILE_W: usize = HIST_W;
const ELEV_PROFILE_H: usize = HIST_H;

/// The elevation-profile page's overlay: the run's banked altitude series as a
/// sparkline across the page body. No-op until the recorder has banked a
/// sample, so the face's own empty state stands alone rather than being
/// underlined by a flat baseline that reads as "dead level".
pub fn draw_elev_profile_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    let ep = &snap.elev_profile;
    if ep.len == 0 {
        return;
    }
    draw_mini_profile(
        fb,
        &MiniProfile {
            x: ELEV_PROFILE_X,
            y: ELEV_PROFILE_Y,
            w: ELEV_PROFILE_W,
            h: ELEV_PROFILE_H,
            samples: &ep.samples[..ep.len],
        },
    );
}

/// Dash pattern for the course-profile position marker: broken enough to read as
/// a marker rather than as part of the profile line on a 1-bit panel.
const ROUTE_ELEV_MARKER_DASH: (u32, u32) = (3, 3);

/// The RouteElev page's overlay: the pushed course's climb profile as a
/// sparkline across the page body, with a dashed vertical marker where the
/// runner sits along it. No-op when no course is loaded or the course carries no
/// elevation (`len == 0`) — the face's "NO ELEVATION" state must not be
/// underlined by a flat baseline that reads as "dead level". The marker is drawn
/// only while the recorder has a fresh along-course position, so a lost-signal
/// runner loses the marker instead of seeing it frozen.
pub fn draw_route_elev_overlay(fb: &mut Framebuffer, snap: &Snapshot) {
    let Some(view) = snap.route_elev.as_ref() else {
        return;
    };
    if view.len == 0 {
        return;
    }
    let mut samples = [0i32; COURSE_PROFILE_CAP];
    for (dst, src) in samples.iter_mut().zip(view.samples.iter()) {
        *dst = *src as i32;
    }
    draw_mini_profile(
        fb,
        &MiniProfile {
            x: ELEV_PROFILE_X,
            y: ELEV_PROFILE_Y,
            w: ELEV_PROFILE_W,
            h: ELEV_PROFILE_H,
            samples: &samples[..view.len.min(COURSE_PROFILE_CAP)],
        },
    );
    if let Some(permille) = snap.route_position_permille {
        let x = ELEV_PROFILE_X + (permille.min(1000) as usize * (ELEV_PROFILE_W - 1)) / 1000;
        fb.draw_dashed_line(
            x as i32,
            ELEV_PROFILE_Y as i32,
            x as i32,
            (ELEV_PROFILE_Y + ELEV_PROFILE_H - 1) as i32,
            ROUTE_ELEV_MARKER_DASH,
            true,
        );
    }
}

// ---------------------------------------------------------------------------
// Nav map panel (course polyline + position marker + off-course banner)
// ---------------------------------------------------------------------------

/// The Nav page's map panel in panel pixels: full display width, the
/// face-declared text rows tall. `watch_core::face` speaks rows; only the
/// render layer knows the panel's 16-px cell height.
const PANEL_TOP_PX: i32 = (face::NAV_PANEL_TOP_ROW * CELL_H) as i32;
const PANEL_H_PX: u32 = (face::NAV_PANEL_ROWS * CELL_H) as u32;

/// Half-length of the position marker's 5-px cross.
const MARKER_ARM_PX: i32 = 2;

/// The panel geometry the host-tested `nav_map` decisions are taken against.
/// The ui task hands it straight to [`watch_core::nav_map::nav_panel`], so the
/// transform, the marker's on-panel test and the pixels drawn here can't
/// disagree.
pub const NAV_PANEL_GEOM: NavPanelGeom = NavPanelGeom {
    w_px: WIDTH as u32,
    top_px: PANEL_TOP_PX,
    h_px: PANEL_H_PX,
    marker_arm_px: MARKER_ARM_PX,
};

const PANEL_X_MAX: i32 = WIDTH as i32 - 1;
const PANEL_Y_MAX: i32 = PANEL_TOP_PX + PANEL_H_PX as i32 - 1;

const OUT_LEFT: u8 = 1;
const OUT_RIGHT: u8 = 2;
const OUT_ABOVE: u8 = 4;
const OUT_BELOW: u8 = 8;

fn panel_outcode(x: i32, y: i32) -> u8 {
    let mut code = 0;
    if x < 0 {
        code |= OUT_LEFT;
    } else if x > PANEL_X_MAX {
        code |= OUT_RIGHT;
    }
    if y < PANEL_TOP_PX {
        code |= OUT_ABOVE;
    } else if y > PANEL_Y_MAX {
        code |= OUT_BELOW;
    }
    code
}

/// Cohen-Sutherland clip of one course segment to the panel rect, or `None`
/// when the segment misses the panel entirely. [`Framebuffer::draw_line`] only
/// clips at the *display* edge, and the panel is a band inside it: on the
/// auto-zoom window a course point a few hundred metres outside the window
/// projects a handful of pixels past the panel, which is still on-screen — it
/// would scribble the NAV title row above the panel or the along-course / GPS
/// rows below it, and those rows are painted *before* this one.
fn clip_to_panel(
    mut x0: i32,
    mut y0: i32,
    mut x1: i32,
    mut y1: i32,
) -> Option<((i32, i32), (i32, i32))> {
    let mut c0 = panel_outcode(x0, y0);
    let mut c1 = panel_outcode(x1, y1);
    loop {
        if c0 | c1 == 0 {
            return Some(((x0, y0), (x1, y1)));
        }
        if c0 & c1 != 0 {
            return None;
        }
        // The endpoint being pulled in is outside on the axis its outcode
        // names, and the other endpoint is not (the shared-side case returned
        // above), so the divisor below is never zero and the ratio is in
        // [0, 1] — the clipped point always lands between the two endpoints.
        // The intermediate product does NOT fit i32 though: an auto-zoom fit is
        // ~8400 px per degree of latitude, so a wild GPS fix (a cold-start
        // position on the far side of the planet) projects the course hundreds
        // of thousands of pixels away, and a wrapped multiply would put a
        // garbage line back inside the panel.
        let out = if c0 != 0 { c0 } else { c1 };
        let (dx, dy) = ((x1 - x0) as i64, (y1 - y0) as i64);
        let lerp = |num: i32, den: i64, along: i64, from: i32| {
            (from as i64 + along * num as i64 / den) as i32
        };
        let (x, y) = if out & OUT_BELOW != 0 {
            (lerp(PANEL_Y_MAX - y0, dy, dx, x0), PANEL_Y_MAX)
        } else if out & OUT_ABOVE != 0 {
            (lerp(PANEL_TOP_PX - y0, dy, dx, x0), PANEL_TOP_PX)
        } else if out & OUT_RIGHT != 0 {
            (PANEL_X_MAX, lerp(PANEL_X_MAX - x0, dx, dy, y0))
        } else {
            (0, lerp(-x0, dx, dy, y0))
        };
        if out == c0 {
            x0 = x;
            y0 = y;
            c0 = panel_outcode(x0, y0);
        } else {
            x1 = x;
            y1 = y;
            c1 = panel_outcode(x1, y1);
        }
    }
}

/// Draw one frame of the Nav page's map panel: the course polyline, the
/// position-marker cross, and — last, so it wins the panel pixels — the
/// off-course banner. Everything decided (which transform, whether the marker
/// is on-panel at all) comes in via [`watch_core::nav_map::nav_panel`]; this is
/// the pixels.
pub fn draw_nav_panel(
    fb: &mut Framebuffer,
    course: &Course,
    panel: &NavPanel,
    alert: Option<&str>,
) {
    for w in course.points().windows(2) {
        let (x0, y0) = panel.fit.to_px(w[0].lat_deg, w[0].lon_deg);
        let (x1, y1) = panel.fit.to_px(w[1].lat_deg, w[1].lon_deg);
        if let Some(((cx0, cy0), (cx1, cy1))) =
            clip_to_panel(x0, y0 + PANEL_TOP_PX, x1, y1 + PANEL_TOP_PX)
        {
            fb.draw_line(cx0, cy0, cx1, cy1, true);
        }
    }
    if let Some(&(mx, my)) = panel.marker.as_ref() {
        // A cleared halo first: at a fork the course segments converge on
        // exactly the runner's position, and a cross drawn with the same
        // 1-bit ink as the polyline melts into it. One blank ring is the
        // only contrast a 1-bit panel has to spend — clipped to the panel
        // band so the halo can't blank the title or GPS rows beside it.
        let halo = MARKER_ARM_PX + 1;
        for y in (my - halo)..=(my + halo) {
            if !(PANEL_TOP_PX..=PANEL_Y_MAX).contains(&y) {
                continue;
            }
            for x in (mx - halo)..=(mx + halo) {
                if (0..=PANEL_X_MAX).contains(&x) {
                    fb.set_pixel(x as usize, y as usize, false);
                }
            }
        }
        fb.draw_line(mx - MARKER_ARM_PX, my, mx + MARKER_ARM_PX, my, true);
        fb.draw_line(mx, my - MARKER_ARM_PX, mx, my + MARKER_ARM_PX, true);
    }
    // The auto-zoom label, bottom-right of the panel, drawn after the lines
    // so the word stays legible over a dense breadcrumb. Only the zoomed
    // state is labelled: whole-course is the default a runner has read since
    // the panel existed, and a label on both states is a label on neither.
    if panel.windowed {
        fb.draw_text(
            face::COLS - ZOOM_LABEL.len(),
            face::NAV_PANEL_TOP_ROW + face::NAV_PANEL_ROWS - 1,
            ZOOM_LABEL,
        );
    }
    if let Some(text) = alert {
        fb.draw_banner_2x(face::NAV_ALERT_ROW, text);
    }
}

/// The nav panel's auto-zoom state label (see [`NavPanel::windowed`]).
const ZOOM_LABEL: &str = "ZOOM";

// ---------------------------------------------------------------------------
// Back-to-start overlay (breadcrumb map + relative direction arrow)
// ---------------------------------------------------------------------------

/// The TrackBack breadcrumb map's pixel rect: right of the text cells the face
/// reserves ([`face::TRACKBACK_TEXT_COLS`]), rows 3-7.
const MAP_X: i32 = (face::TRACKBACK_TEXT_COLS * CELL_W) as i32;
const MAP_Y: i32 = (TB_MAP_TOP_ROW * CELL_H) as i32;
const MAP_W: u16 = (WIDTH - face::TRACKBACK_TEXT_COLS * CELL_W) as u16;
const MAP_H: u16 = (TB_MAP_ROWS * CELL_H) as u16;
const TB_MAP_TOP_ROW: usize = 3;
const TB_MAP_ROWS: usize = 5;

/// Half-side of the hollow start-marker box. `project_track` insets its
/// projection by the same margin, which is what keeps the box inside the map
/// rect when the start lands on the polyline's extreme.
const START_MARK_ARM: i32 = 2;

/// Relative direction arrow: centred in the reserved text cells over rows 5-7,
/// the band the face blanks whenever a fresh heading makes the arrow meaningful
/// (it writes `--` there otherwise, so the two never overlap).
const ARROW_CX: i32 = (face::TRACKBACK_TEXT_COLS * CELL_W / 2) as i32;
const ARROW_CY: i32 = (13 * CELL_H / 2) as i32;
const ARROW_R: i32 = (3 * CELL_H) as i32 / 2 - 6;

/// Draw the BackToStart page's pixel layer: the north-up TrackBack breadcrumb
/// map with a hollow-box start marker + a filled current-position dot, and the
/// relative back-to-start arrow whenever a fresh heading makes it meaningful.
/// An inactive view (no accepted fix yet) draws no map, so the page reads as
/// honestly empty rather than showing a crumb of nowhere.
pub fn draw_trackback_overlay(fb: &mut Framebuffer, view: &TrackbackView, uptime_s: u32) {
    let mut pts = [(0u16, 0u16); trackback::BREADCRUMB_CAP + 1];
    if let Some(map) = trackback::project_track(view, MAP_W, MAP_H, &mut pts) {
        for pair in pts[..map.len].windows(2) {
            fb.draw_line(
                MAP_X + pair[0].0 as i32,
                MAP_Y + pair[0].1 as i32,
                MAP_X + pair[1].0 as i32,
                MAP_Y + pair[1].1 as i32,
                true,
            );
        }
        let (sx, sy) = (MAP_X + map.start.0 as i32, MAP_Y + map.start.1 as i32);
        fb.draw_line(
            sx - START_MARK_ARM,
            sy - START_MARK_ARM,
            sx + START_MARK_ARM,
            sy - START_MARK_ARM,
            true,
        );
        fb.draw_line(
            sx + START_MARK_ARM,
            sy - START_MARK_ARM,
            sx + START_MARK_ARM,
            sy + START_MARK_ARM,
            true,
        );
        fb.draw_line(
            sx + START_MARK_ARM,
            sy + START_MARK_ARM,
            sx - START_MARK_ARM,
            sy + START_MARK_ARM,
            true,
        );
        fb.draw_line(
            sx - START_MARK_ARM,
            sy + START_MARK_ARM,
            sx - START_MARK_ARM,
            sy - START_MARK_ARM,
            true,
        );
        let (cx, cy) = (MAP_X + map.current.0 as i32, MAP_Y + map.current.1 as i32);
        for dy in -1..=1 {
            fb.draw_line(cx - 1, cy + dy, cx + 1, cy + dy, true);
        }
    }

    if let Some(sector) = view.arrow_sector(uptime_s) {
        for ((x0, y0), (x1, y1)) in trackback::arrow_lines(sector, ARROW_CX, ARROW_CY, ARROW_R) {
            fb.draw_line(x0, y0, x1, y1, true);
        }
    }
}

// ---------------------------------------------------------------------------
// Integer trig (no libm) — a quarter-turn sine table + octant reflection so the
// ring dial and compass arrow place points around a circle without linking a
// float math library into the firmware.
// ---------------------------------------------------------------------------

const TRIG_SCALE: i32 = 10_000;

/// `sin(0deg)..sin(90deg)` scaled by [`TRIG_SCALE`]; every other quadrant is a
/// reflection of these 91 values, so the whole circle is one small table.
const SIN_Q: [i32; 91] = [
    0, 175, 349, 523, 698, 872, 1045, 1219, 1392, 1564, 1736, 1908, 2079, 2250, 2419, 2588, 2756,
    2924, 3090, 3256, 3420, 3584, 3746, 3907, 4067, 4226, 4384, 4540, 4695, 4848, 5000, 5150, 5299,
    5446, 5592, 5736, 5878, 6018, 6157, 6293, 6428, 6561, 6691, 6820, 6947, 7071, 7193, 7314, 7431,
    7547, 7660, 7771, 7880, 7986, 8090, 8192, 8290, 8387, 8480, 8572, 8660, 8746, 8829, 8910, 8988,
    9063, 9135, 9205, 9272, 9336, 9397, 9455, 9511, 9563, 9613, 9659, 9703, 9744, 9781, 9816, 9848,
    9877, 9903, 9925, 9945, 9962, 9976, 9986, 9994, 9998, 10000,
];

fn isin(deg: i32) -> i32 {
    let d = deg.rem_euclid(360);
    match d {
        0..=90 => SIN_Q[d as usize],
        91..=180 => SIN_Q[(180 - d) as usize],
        181..=270 => -SIN_Q[(d - 180) as usize],
        _ => -SIN_Q[(360 - d) as usize],
    }
}

fn icos(deg: i32) -> i32 {
    isin(deg + 90)
}

/// Point at `bearing` degrees clockwise from north (screen up) on a circle of
/// radius `r` about `(cx, cy)`, in screen coordinates (y grows downward).
fn ring_point(cx: i32, cy: i32, r: i32, bearing: i32) -> (i32, i32) {
    (
        cx + r * isin(bearing) / TRIG_SCALE,
        cy - r * icos(bearing) / TRIG_SCALE,
    )
}

// ---------------------------------------------------------------------------
// Segmented ring dial (a fraction shown as a dial rather than a bar)
// ---------------------------------------------------------------------------

const DIAL_SEG: usize = 6; // side of each square ring segment, px

/// Draw a `segments`-block ring dial about `(cx, cy)` at radius `r`: the first
/// `frac` (clamped 0..=1) share of the ring, clockwise from the top, are solid
/// blocks and the rest hollow frames — so a zero fraction still shows the empty
/// ring, never a blank gap a glance could mistake for "no widget". A `segments`
/// of 0 draws nothing.
pub fn draw_dial(fb: &mut Framebuffer, cx: usize, cy: usize, r: usize, segments: usize, frac: f32) {
    if segments == 0 {
        return;
    }
    let lit = (frac.clamp(0.0, 1.0) * segments as f32 + 0.5) as usize;
    let half = DIAL_SEG as i32 / 2;
    for i in 0..segments {
        let bearing = (i * 360 / segments) as i32;
        let (px, py) = ring_point(cx as i32, cy as i32, r as i32, bearing);
        let x = (px - half).max(0) as usize;
        let y = (py - half).max(0) as usize;
        if i < lit {
            fb.fill_rect(x, y, DIAL_SEG, DIAL_SEG, true);
        } else {
            fb.stroke_rect(x, y, DIAL_SEG, DIAL_SEG, true);
        }
    }
}

// ---------------------------------------------------------------------------
// Compass arrow (e.g. trackback bearing-to-start)
// ---------------------------------------------------------------------------

const COMPASS_HEAD_LEN: i32 = 6; // arrowhead barb reach back from the tip
const COMPASS_HEAD_W: i32 = 4; // arrowhead half-width
const COMPASS_N_TICK: i32 = 5; // north reference tick length outside the ring

/// Draw a directional arrow from `(cx, cy)` pointing `bearing` degrees clockwise
/// from north (screen up), tip on a circle of radius `r`, plus a fixed north
/// reference tick + 'N' so the arrow reads against true north rather than alone.
/// `bearing` wraps mod 360, so 360 renders as 0.
pub fn draw_compass(fb: &mut Framebuffer, cx: usize, cy: usize, r: usize, bearing: u16) {
    let (cxi, cyi, ri) = (cx as i32, cy as i32, r as i32);
    let b = bearing as i32;
    let (tx, ty) = ring_point(cxi, cyi, ri, b);
    fb.draw_line(cxi, cyi, tx, ty, true);

    let (bx, by) = ring_point(cxi, cyi, (ri - COMPASS_HEAD_LEN).max(0), b);
    let (ox, oy) = ring_point(0, 0, COMPASS_HEAD_W, b + 90);
    fb.draw_line(tx, ty, bx + ox, by + oy, true);
    fb.draw_line(tx, ty, bx - ox, by - oy, true);

    fb.draw_line(cxi, cyi - ri, cxi, cyi - ri - COMPASS_N_TICK, true);
    let nx = cxi - CELL_W as i32 / 2;
    let ny = cyi - ri - COMPASS_N_TICK - CELL_H as i32;
    if nx >= 0 && ny >= 0 {
        fb.draw_text(nx as usize / CELL_W, ny as usize / CELL_H, "N");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use watch_core::face::{IdleView, NavView};
    use watch_core::gear_wear::gear_wear;
    use watch_core::gnss_mode::GnssMode;
    use watch_core::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM, ZONE_COUNT};
    use watch_core::pacer::{PaceVerdict, PacerGoal, PacerStatus};
    use watch_core::page::Page;
    use watch_core::record::{FuelBasis, FuelCarryView, FuelView, RecordState, PACE_BUCKET_COUNT};
    use watch_core::workout::{PaceAdherence, WorkoutStepKind, WorkoutView};

    // Count set pixels inside a rectangle — the tests assert *where* ink lands.
    fn ink_in(fb: &Framebuffer, x: usize, y: usize, w: usize, h: usize) -> usize {
        let mut n = 0;
        for yy in y..y + h {
            for xx in x..x + w {
                if fb.pixel(xx, yy) {
                    n += 1;
                }
            }
        }
        n
    }

    // A live-recording base snapshot with every optional overlay input empty;
    // each test sets just the field its overlay reads.
    fn snapshot() -> Snapshot {
        Snapshot {
            state: RecordState::Recording,
            manual_paused: false,
            signal_lost: false,
            backyard: None,
            distance_m: 0.0,
            elapsed_s: 0,
            moving_s: 0,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
            gap_s_per_km: None,
            gap_held: false,
            lap: 1,
            lap_distance_m: 0.0,
            lap_elapsed_s: 0,
            last_lap: None,
            pacer: None,
            zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            zone_ceiling: None,
            hr_source: None,
            pace_band: None,
            zone_time_s: [0; ZONE_COUNT],
            cutoffs_loaded: false,
            cutoff: None,
            sleep: None,
            race_prediction: None,
            pace_bucket_m: [0.0; PACE_BUCKET_COUNT],
            training_stress: None,
            training_stress_trimp: false,
            load_trend: None,
            band: None,
            gear: None,
            roadbook: None,
            fuel: None,
            training_paces: None,
            fitness: None,
            elev_profile: watch_core::record::ElevProfileView::empty(),
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
            nav_off_course: None,
            route_simplify: None,
            auto_effort: None,
            route_elev: None,
            route_position_permille: None,
            race_day: None,
            race_phase: None,
            climb: Default::default(),
            waypoint: None,
            waypoint_count: 0,
            waypoint_mark_seq: 0,
            waypoint_refuse_seq: 0,
            run_lost_seq: 0,
            course_reject_seq: 0,
            timer: None,
            storm: None,
            auto_lap: watch_core::auto_lap::AUTO_LAP_DEFAULT,
            track_thinning: 1,
            pages_mask: u64::MAX,
            hide_empty_pages: true,
        }
    }

    #[test]
    fn signal_meter_stays_inside_the_rows_last_three_text_cells() {
        // The idle face caps its title hint at TEXT_COLS - 3 cells on the
        // promise that the meter owns the row's tail; if the meter ever grows
        // left of that boundary the hint and the ticks collide again.
        let left = (WIDTH - 2 + 1) - SIGNAL_METER_W;
        assert!(left >= (TEXT_COLS - 3) * CELL_W);
    }

    #[test]
    fn signal_meter_fills_left_to_right() {
        let mut fb = Framebuffer::new();
        let (right_x, baseline_y) = (WIDTH - 2, CELL_H - 2);
        draw_signal_bars(&mut fb, right_x, baseline_y, 2);
        // With 2 bars lit, the left ticks are SOLID (interior inked) and the
        // right ticks are HOLLOW (interior blank, frame inked) — the per-tick
        // fill/frame distinction, independent of the staircase heights.
        let left = (right_x + 1) - SIGNAL_METER_W;
        let interior = |i: usize| {
            let x = left + i * TICK_STEP + TICK_W / 2;
            let y = baseline_y - 2; // a couple of px up from the base, inside every tick
            (x, y)
        };
        let (x0, y0) = interior(0);
        assert!(fb.pixel(x0, y0), "lit tick 0 is solid");
        let (x3, y3) = interior(3);
        assert!(!fb.pixel(x3, y3), "unlit tick 3 is hollow (blank interior)");
        // ...but its frame is drawn: the tick's left edge column carries ink.
        assert!(
            fb.pixel(left + 3 * TICK_STEP, baseline_y),
            "hollow tick keeps its frame"
        );
    }

    #[test]
    fn signal_meter_zero_is_all_frames_not_blank() {
        let mut fb = Framebuffer::new();
        draw_signal_bars(&mut fb, WIDTH - 2, CELL_H - 2, 0);
        let left = WIDTH - 1 - SIGNAL_METER_W;
        assert!(ink_in(&fb, left, 0, SIGNAL_METER_W, CELL_H) > 0);
    }

    #[test]
    fn signal_meter_full_beats_partial() {
        let mut a = Framebuffer::new();
        let mut b = Framebuffer::new();
        draw_signal_bars(&mut a, WIDTH - 2, CELL_H - 2, 4);
        draw_signal_bars(&mut b, WIDTH - 2, CELL_H - 2, 1);
        let left = WIDTH - 1 - SIGNAL_METER_W;
        assert!(
            ink_in(&a, left, 0, SIGNAL_METER_W, CELL_H)
                > ink_in(&b, left, 0, SIGNAL_METER_W, CELL_H)
        );
    }

    #[test]
    fn battery_icon_stays_left_of_the_gps_meter_and_inside_row_0() {
        // The meter owns the row's last three text cells; the battery must end
        // short of its leftmost tick and start clear of the 7-cell brand.
        let meter_left = (WIDTH - 2 + 1) - SIGNAL_METER_W;
        assert!(BATTERY_RIGHT_X < meter_left);
        let left = BATTERY_RIGHT_X + 1 - BATTERY_W;
        assert!(left >= 7 * CELL_W, "clear of the THREKIR brand cells");
        let mut fb = Framebuffer::new();
        draw_idle_battery(&mut fb, Some(100), false);
        // Every inked pixel sits inside the icon's own box in row 0.
        assert!(ink_in(&fb, left, 0, BATTERY_W, CELL_H) > 0);
        assert_eq!(
            ink_in(&fb, 0, 0, left, HEIGHT),
            0,
            "nothing left of the icon"
        );
        assert_eq!(
            ink_in(
                &fb,
                BATTERY_RIGHT_X + 1,
                0,
                WIDTH - BATTERY_RIGHT_X - 1,
                HEIGHT
            ),
            0,
            "nothing bleeds toward the meter"
        );
        assert_eq!(
            ink_in(&fb, 0, CELL_H, WIDTH, HEIGHT - CELL_H),
            0,
            "row 0 only"
        );
    }

    #[test]
    fn battery_fill_grows_with_percent_and_empty_keeps_its_frame() {
        let (mut empty, mut half, mut full) =
            (Framebuffer::new(), Framebuffer::new(), Framebuffer::new());
        draw_idle_battery(&mut empty, Some(0), false);
        draw_idle_battery(&mut half, Some(50), false);
        draw_idle_battery(&mut full, Some(100), false);
        let left = BATTERY_RIGHT_X + 1 - BATTERY_W;
        let e = ink_in(&empty, left, 0, BATTERY_W, CELL_H);
        let h = ink_in(&half, left, 0, BATTERY_W, CELL_H);
        let f = ink_in(&full, left, 0, BATTERY_W, CELL_H);
        assert!(e > 0, "0% still draws the outline + nub (+ low mark)");
        assert!(h > e && f > h, "fill is proportional");
    }

    #[test]
    fn battery_low_state_adds_the_exclamation_inside_the_body() {
        // LOW_PCT and LOW_PCT + 1 round to the same fill width, so the only
        // ink difference between the two frames is the low mark itself.
        let (mut low, mut ok) = (Framebuffer::new(), Framebuffer::new());
        draw_idle_battery(&mut low, Some(battery::LOW_PCT), false);
        draw_idle_battery(&mut ok, Some(battery::LOW_PCT + 1), false);
        let left = BATTERY_RIGHT_X + 1 - BATTERY_W;
        let ex = left + 2 + (BATT_BODY_W - 4) / 2;
        assert!(
            ink_in(&low, ex, 0, 2, CELL_H) > ink_in(&ok, ex, 0, 2, CELL_H),
            "low frame carries the mark"
        );
        assert!(ink_in(&low, left, 0, BATTERY_W, CELL_H) > ink_in(&ok, left, 0, BATTERY_W, CELL_H));
        // The mark stays inside the body's inner region: strip the two frames
        // down to their difference and it must all sit within the inner box.
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                if low.pixel(x, y) && !ok.pixel(x, y) {
                    assert!(
                        (left + 2..left + BATT_BODY_W - 2).contains(&x),
                        "mark ink at x={x} outside the body interior"
                    );
                    assert!(
                        (BATTERY_TOP_Y + 2..BATTERY_TOP_Y + BATT_BODY_H - 2).contains(&y),
                        "mark ink at y={y} outside the body interior"
                    );
                }
            }
        }
    }

    #[test]
    fn battery_overfull_clamps_to_full() {
        let (mut over, mut full) = (Framebuffer::new(), Framebuffer::new());
        draw_idle_battery(&mut over, Some(255), false);
        draw_idle_battery(&mut full, Some(100), false);
        assert!(fb_eq(&over, &full));
    }

    #[test]
    fn battery_absent_or_busy_title_draws_nothing() {
        let mut none = Framebuffer::new();
        draw_idle_battery(&mut none, None, false);
        assert_eq!(ink_in(&none, 0, 0, WIDTH, HEIGHT), 0);
        let mut busy = Framebuffer::new();
        draw_idle_battery(&mut busy, Some(80), true);
        assert_eq!(ink_in(&busy, 0, 0, WIDTH, HEIGHT), 0);
    }

    #[test]
    fn page_indicator_thumb_moves_with_the_active_page() {
        let mut early = Framebuffer::new();
        let mut late = Framebuffer::new();
        draw_page_indicator(
            &mut early,
            PageIndicator {
                active: 0,
                total: 16,
            },
        );
        draw_page_indicator(
            &mut late,
            PageIndicator {
                active: 15,
                total: 16,
            },
        );
        // Thumb ink (rows 0..3) sits at the left for page 0, the right for the last.
        assert!(ink_in(&early, 0, 0, 12, 3) > 0);
        assert_eq!(ink_in(&early, WIDTH - 12, 0, 12, 3), 0);
        assert!(ink_in(&late, WIDTH - 12, 0, 12, 3) > 0);
        assert_eq!(ink_in(&late, 0, 0, 12, 3), 0);
        // Both draw the full-width track on row 3.
        assert_eq!(ink_in(&late, 0, 3, WIDTH, 1), WIDTH);
    }

    #[test]
    fn page_indicator_thumbs_tile_the_track_at_the_live_page_count() {
        // The pixel counterpart of statusbar's partition test: walking the full
        // 33-page cycle must light every track column exactly once, which is
        // what makes the first page's thumb touch the left edge and the last
        // page's touch the right. Before the geometry moved into `page_thumb`
        // this failed on three columns (55, 111, 167) because the width was a
        // separately-truncated WIDTH / total.
        let mut lit_by = [0u8; WIDTH];
        for active in 0..33 {
            let mut fb = Framebuffer::new();
            draw_page_indicator(&mut fb, PageIndicator { active, total: 33 });
            for (x, count) in lit_by.iter_mut().enumerate() {
                if fb.pixel(x, 0) {
                    *count += 1;
                }
            }
        }
        for (x, count) in lit_by.iter().enumerate() {
            assert_eq!(*count, 1, "track column {x} is owned by {count} pages");
        }
    }

    #[test]
    fn page_indicator_thumb_height_clears_the_track_row() {
        let mut fb = Framebuffer::new();
        draw_page_indicator(
            &mut fb,
            PageIndicator {
                active: 4,
                total: 33,
            },
        );
        // Rows 0..3 are the thumb, row 3 the track, row 4 belongs to the face.
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, THUMB_H), 5 * THUMB_H);
        assert_eq!(ink_in(&fb, 0, 3, WIDTH, 1), WIDTH);
        assert_eq!(ink_in(&fb, 0, 4, WIDTH, CELL_H - 4), 0);
    }

    #[test]
    fn page_indicator_zero_total_is_a_noop() {
        let mut fb = Framebuffer::new();
        draw_page_indicator(
            &mut fb,
            PageIndicator {
                active: 0,
                total: 0,
            },
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, CELL_H), 0);
    }

    #[test]
    fn grid_rows_fully_erase_an_alert_banner_underneath() {
        // The ui task draws the grid AFTER the composed page, relying on
        // draw_text_row overwriting each full 16-px band — this pins that an
        // alert banner drawn first leaves no residue, so the deferred-banner
        // rule in the ui task can't ghost. The inverse-video band makes this
        // the worst case: every pixel of rows 0-1 starts inked.
        use watch_core::alerts::{banner, Alert};
        use watch_core::page::Page;
        let mut with_banner = Framebuffer::new();
        with_banner.draw_banner_2x(0, &banner(Alert::Drink));
        let mut clean = Framebuffer::new();
        for (row, text) in page_grid::grid_rows(u64::MAX, Page::Dashboard)
            .iter()
            .enumerate()
        {
            with_banner.draw_text_row(row, text);
            clean.draw_text_row(row, text);
        }
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                assert_eq!(
                    with_banner.pixel(x, y),
                    clean.pixel(x, y),
                    "banner residue at ({x},{y})"
                );
            }
        }
    }

    #[test]
    fn grid_cursor_frames_its_cell_and_stays_clear_of_neighbours() {
        let mut fb = Framebuffer::new();
        // Cell (1, 2): third body row, second column.
        draw_grid_cursor(&mut fb, (1, 2));
        let x = page_grid::GRID_CELL_CHARS * CELL_W; // col 1
        let y = (page_grid::GRID_TOP_ROW + 2) * CELL_H;
        // Frame ink on all four edges of the cell's own band.
        assert!(ink_in(&fb, x - 2, y, 4 * CELL_W + 3, 1) > 0, "top edge");
        assert!(
            ink_in(&fb, x - 2, y + CELL_H - 1, 4 * CELL_W + 3, 1) > 0,
            "bottom edge"
        );
        assert!(ink_in(&fb, x - 2, y, 1, CELL_H) > 0, "left edge");
        assert!(ink_in(&fb, x + 4 * CELL_W, y, 1, CELL_H) > 0, "right edge");
        // Nothing bleeds into the neighbouring column or adjacent rows.
        assert_eq!(
            ink_in(
                &fb,
                x + page_grid::GRID_CELL_CHARS * CELL_W,
                y,
                CELL_W,
                CELL_H
            ),
            0
        );
        assert_eq!(ink_in(&fb, x - 2, y - CELL_H, 4 * CELL_W + 3, CELL_H), 0);
        assert_eq!(ink_in(&fb, x - 2, y + CELL_H, 4 * CELL_W + 3, CELL_H), 0);
        // Column 0 clamps its left overhang instead of underflowing.
        let mut fb0 = Framebuffer::new();
        draw_grid_cursor(&mut fb0, (0, 0));
        assert!(ink_in(&fb0, 0, page_grid::GRID_TOP_ROW * CELL_H, 1, CELL_H) > 0);
    }

    #[test]
    fn dashboard_grid_rules_the_field_boundaries() {
        let mut fb = Framebuffer::new();
        for row in 0..TEXT_ROWS {
            ruled_dashboard_row(&mut fb, row, "");
        }
        // The hero band (rows 0-1) carries no rules; the grid opens with a
        // hairline over the first field row and closes every field but the
        // last — the panel edge finishes the grid.
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, 2 * CELL_H), 0);
        let mut rule_ys = vec![face::DASH_FIELD_TOP_ROW * CELL_H];
        for row in face::DASH_FIELD_TOP_ROW..TEXT_ROWS - 1 {
            rule_ys.push((row + 1) * CELL_H - 1);
        }
        for y in rule_ys {
            assert_eq!(
                ink_in(&fb, RULE_X0, y, WIDTH - RULE_X0, 1),
                WIDTH - RULE_X0,
                "missing hairline at y={y}"
            );
        }
        assert_eq!(ink_in(&fb, 0, HEIGHT - 1, WIDTH, 1), 0, "panel edge ruled");
        // The icon gutter stays clear of every rule...
        assert_eq!(ink_in(&fb, 0, 0, RULE_X0, HEIGHT), 0);
        // ...and the NOW | GAP splitter spans exactly its own row band.
        let vx = face::DASH_SPLIT_COL * CELL_W + CELL_W / 2;
        assert_eq!(
            ink_in(&fb, vx, face::DASH_SPLIT_ROW * CELL_H, 1, CELL_H),
            CELL_H
        );
        assert_eq!(
            ink_in(&fb, vx, (face::DASH_SPLIT_ROW + 1) * CELL_H, 1, CELL_H - 1),
            0
        );
    }

    #[test]
    fn dashboard_grid_redraw_flushes_nothing_and_spares_the_icons() {
        // The zero-flush-at-rest contract, grid included: the rules compose
        // into each row's own compare-write, so an unchanged ruled frame
        // dirties no line...
        let rows = [
            "",
            "",
            "     9.87 KM",
            "PACE 5:12 /KM",
            "NOW  5:55 GAP 5:41",
        ];
        let mut fb = Framebuffer::new();
        for (row, text) in rows.iter().enumerate() {
            ruled_dashboard_row(&mut fb, row, text);
        }
        fb.clear_dirty();
        for (row, text) in rows.iter().enumerate() {
            ruled_dashboard_row(&mut fb, row, text);
        }
        assert_eq!(fb.dirty_count(), 0, "an unchanged ruled frame flushed");
        // ...and because the rules stop short of the icon gutter, an icon
        // blitted over its two cells leaves every rule pixel standing (a
        // full-width rule would be re-cleared by the blit each frame).
        use sharp_mip::Icon;
        fb.draw_icon(0, 2, Icon::Footsteps);
        let y = 3 * CELL_H - 1;
        assert_eq!(ink_in(&fb, RULE_X0, y, WIDTH - RULE_X0, 1), WIDTH - RULE_X0);
    }

    fn pacer(ahead_s: i32) -> PacerStatus {
        PacerStatus {
            goal: PacerGoal {
                distance_m: 10_000,
                time_s: 3_000,
            },
            ahead_m: 0.0,
            ahead_s,
            projected_finish_s: None,
            verdict: PaceVerdict::OnPace,
            finished: false,
            terrain_aware: false,
        }
    }

    #[test]
    fn pacer_overlay_leans_right_when_ahead_left_when_behind() {
        let mut ahead = snapshot();
        ahead.pacer = Some(pacer(90));
        let mut behind = snapshot();
        behind.pacer = Some(pacer(-90));
        let (mut fa, mut fb) = (Framebuffer::new(), Framebuffer::new());
        draw_pacer_overlay(&mut fa, &ahead);
        draw_pacer_overlay(&mut fb, &behind);
        let y = bar_y(7);
        let half = PACER_BAR_W / 2;
        let mid = PACER_BAR_X + half;
        // Ahead fills right of the bar's centre; behind fills left of it.
        let right = |f: &Framebuffer| ink_in(f, mid + 1, y, half - 1, BAR_H);
        let left = |f: &Framebuffer| ink_in(f, PACER_BAR_X, y, half - 1, BAR_H);
        assert!(right(&fa) > left(&fa));
        assert!(left(&fb) > right(&fb));
    }

    #[test]
    fn pacer_overlay_stays_clear_of_the_dist_value_it_sits_beside() {
        // The widest DIST the face can write is `DIST -99999 M` — 13 cells — so
        // the bar starting at cell 14 leaves the value intact at full extension.
        let mut leading = snapshot();
        leading.pacer = Some(pacer(gauge::PACER_FULL_SCALE_S));
        let mut trailing = snapshot();
        trailing.pacer = Some(pacer(-gauge::PACER_FULL_SCALE_S));
        for snap in [&leading, &trailing] {
            let mut fb = Framebuffer::new();
            draw_pacer_overlay(&mut fb, snap);
            assert_eq!(ink_in(&fb, 0, 7 * CELL_H, PACER_BAR_X, CELL_H), 0);
        }
    }

    #[test]
    fn pacer_overlay_without_goal_draws_nothing() {
        let mut fb = Framebuffer::new();
        draw_pacer_overlay(&mut fb, &snapshot());
        assert_eq!(ink_in(&fb, 0, bar_y(7), WIDTH, BAR_H), 0);
    }

    // -----------------------------------------------------------------------
    // The placement contract, swept
    // -----------------------------------------------------------------------

    fn guard_fix() -> Fix {
        Fix {
            lat_deg: 40.1,
            lon_deg: -105.2,
            speed_mps: 2.6,
            course_deg: Some(90.0),
            sats: 9,
            alt_m: Some(1650.0),
            time_of_day: Some(12 * 3600),
            date: None,
            uptime_s: 100,
        }
    }

    fn workout_view() -> WorkoutView {
        WorkoutView {
            step_index: 13,
            step_total: 64,
            kind: WorkoutStepKind::Rep,
            rep_index: 7,
            rep_total: 12,
            duration_based: false,
            target_distance_m: 400,
            target_duration_s: 0,
            target_pace_s_per_km: 240,
            step_distance_m: 200,
            step_elapsed_s: 60,
            remaining_m: 200,
            remaining_s: 0,
            progress_permille: 500,
            step_pace_s_per_km: Some(250),
            adherence: PaceAdherence::OnPace,
            next: None,
            complete: false,
            rollup: None,
            transition_seq: 0,
            ending_seq: 0,
        }
    }

    /// Assert an overlay paints into no cell the face wrote a glyph into.
    ///
    /// Cell granularity, not pixel: an in-row bar legitimately shares a *row*
    /// with text (the workout and zone bars do), but a bar and a glyph in the
    /// same 8x16 cell is corruption whether or not their ink happens to
    /// interleave. Draws the two layers into separate framebuffers so the
    /// question "who owns this cell" has an answer, which a single composed
    /// buffer cannot give.
    fn assert_no_overlap(
        page: Page,
        snap: &Snapshot,
        hr: Option<u16>,
        draw: impl Fn(&mut Framebuffer, &Snapshot),
    ) {
        let fix = guard_fix();
        let rows = face::page_rows(
            page,
            Some(&fix),
            hr,
            Some(snap),
            None,
            NavView::NoCourse,
            None,
            100,
            false,
            GnssMode::default(),
            IdleView::Home,
            None,
            None,
            None,
        );
        let mut text = Framebuffer::new();
        for (r, row) in rows.iter().enumerate() {
            text.draw_text_row(r, row);
        }
        let mut over = Framebuffer::new();
        draw(&mut over, snap);

        for row in 0..TEXT_ROWS {
            for col in 0..TEXT_COLS {
                let (x, y) = (col * CELL_W, row * CELL_H);
                let t = ink_in(&text, x, y, CELL_W, CELL_H);
                let o = ink_in(&over, x, y, CELL_W, CELL_H);
                assert!(
                    t == 0 || o == 0,
                    "{page:?}: cell (col {col}, row {row}) carries both face text \
                     ({t} px) and overlay ink ({o} px) — the overlay paints over the \
                     glyph. Either move the bar or free the cell; the face row is \
                     {:?}",
                    rows[row].as_str()
                );
            }
        }
    }

    /// Every page whose bar shares the panel with face text, at the widest
    /// values the face can write — a bar clear of a typical value but not of an
    /// extreme one is still a collision waiting for a long run.
    ///
    /// This is the guard the placement contract never had. #609 added the
    /// race-phase line to the pacer page's row 3 while the ahead/behind bar
    /// already owned that row full-width, and nothing failed: the face tests
    /// assert row strings, the widget tests assert bar columns, and no test
    /// composed the two. The bar painted through the phase text on the glass
    /// for four batches.
    #[test]
    fn overlay_never_paints_over_face_text() {
        let mut pacer_snap = snapshot();
        // Widest DIST (`DIST -99999 M`) with the bar at full extension.
        pacer_snap.pacer = Some(PacerStatus {
            ahead_m: -123_456.0,
            ..pacer(-gauge::PACER_FULL_SCALE_S)
        });
        assert_no_overlap(Page::Pacer, &pacer_snap, Some(150), draw_pacer_overlay);

        let mut gear_snap = snapshot();
        gear_snap.gear = Some(gear_wear(Some(900_000.0), Some(800_000.0)));
        assert_no_overlap(Page::GearWear, &gear_snap, None, draw_gear_overlay);

        let mut fuel_snap = snapshot();
        fuel_snap.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 120.0,
                fluid_ml: 1_500.0,
            }),
            basis: FuelBasis::NextAid {
                total: FuelCarryView {
                    carbs_g: 120.0,
                    fluid_ml: 1_500.0,
                },
            },
        });
        assert_no_overlap(Page::Fuel, &fuel_snap, None, draw_fuel_overlay);

        let mut workout_snap = snapshot();
        workout_snap.workout = Some(workout_view());
        assert_no_overlap(Page::Workout, &workout_snap, None, draw_workout_overlay);

        let mut splits_snap = snapshot();
        splits_snap.pace_bucket_m = [1_000.0, 4_000.0, 2_000.0, 500.0, 0.0, 0.0];
        assert_no_overlap(Page::Splits, &splits_snap, None, draw_splits_overlay);

        let mut zones_snap = snapshot();
        zones_snap.zone_time_s = [6_000, 3_000, 1_200, 600, 60];
        zones_snap.zone_cutoffs = zone_cutoffs_from_max_hr(190);
        assert_no_overlap(Page::Zones, &zones_snap, Some(150), |fb, snap| {
            draw_zones_overlay(fb, snap, Some(150))
        });
    }

    #[test]
    fn gear_overlay_bar_grows_with_wear_and_flags_overdue() {
        let mut half = snapshot();
        half.gear = Some(gear_wear(Some(400_000.0), Some(800_000.0)));
        let mut worn = snapshot();
        worn.gear = Some(gear_wear(Some(900_000.0), Some(800_000.0)));
        let (mut fh, mut fw) = (Framebuffer::new(), Framebuffer::new());
        draw_gear_overlay(&mut fh, &half);
        draw_gear_overlay(&mut fw, &worn);
        let y = bar_y(5);
        // A worn shoe's bar carries more fill than a half-worn one...
        assert!(ink_in(&fw, BAR_X, y, BAR_W, BAR_H) > ink_in(&fh, BAR_X, y, BAR_W, BAR_H));
        // ...and only the worn one paints the end-of-bar alert block.
        assert!(ink_in(&fw, WIDTH - 3, 5 * CELL_H, 2, CELL_H) > 0);
        assert_eq!(ink_in(&fh, WIDTH - 3, 5 * CELL_H, 2, CELL_H), 0);
    }

    #[test]
    fn fuel_overlay_bar_scales_with_carry_share() {
        let mut full = snapshot();
        full.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 120.0,
                fluid_ml: 0.0,
            }),
            basis: FuelBasis::NextAid {
                total: FuelCarryView {
                    carbs_g: 120.0,
                    fluid_ml: 0.0,
                },
            },
        });
        let mut part = snapshot();
        part.fuel = Some(FuelView {
            carry: Some(FuelCarryView {
                carbs_g: 30.0,
                fluid_ml: 0.0,
            }),
            basis: FuelBasis::NextAid {
                total: FuelCarryView {
                    carbs_g: 120.0,
                    fluid_ml: 0.0,
                },
            },
        });
        let (mut ff, mut fp) = (Framebuffer::new(), Framebuffer::new());
        draw_fuel_overlay(&mut ff, &full);
        draw_fuel_overlay(&mut fp, &part);
        let y = bar_y(3);
        assert!(ink_in(&ff, BAR_X, y, BAR_W, BAR_H) > ink_in(&fp, BAR_X, y, BAR_W, BAR_H));
    }

    #[test]
    fn workout_overlay_bar_scales_with_step_progress_and_stops_on_done() {
        use watch_core::workout::{PaceAdherence, WorkoutStepKind, WorkoutView};
        let view = |progress_permille: u16, complete: bool| WorkoutView {
            step_index: 0,
            step_total: 3,
            kind: WorkoutStepKind::Rep,
            rep_index: 1,
            rep_total: 2,
            duration_based: false,
            target_distance_m: 400,
            target_duration_s: 0,
            target_pace_s_per_km: 240,
            step_distance_m: 0,
            step_elapsed_s: 0,
            remaining_m: 400,
            remaining_s: 0,
            progress_permille,
            step_pace_s_per_km: None,
            adherence: PaceAdherence::OnPace,
            next: None,
            complete,
            rollup: None,
            transition_seq: 1,
            ending_seq: 0,
        };
        let mut far = snapshot();
        far.workout = Some(view(800, false));
        let mut near = snapshot();
        near.workout = Some(view(200, false));
        let mut ff = Framebuffer::new();
        let mut fn_ = Framebuffer::new();
        draw_workout_overlay(&mut ff, &far);
        draw_workout_overlay(&mut fn_, &near);
        let y = bar_y(7);
        assert!(
            ink_in(&ff, WORKOUT_BAR_X, y, WORKOUT_BAR_W, BAR_H)
                > ink_in(&fn_, WORKOUT_BAR_X, y, WORKOUT_BAR_W, BAR_H),
            "the bar fills with step progress"
        );
        // A finished workout's row reads DONE — no bar under it.
        let mut done = snapshot();
        done.workout = Some(view(1000, true));
        let mut fd = Framebuffer::new();
        draw_workout_overlay(&mut fd, &done);
        assert_eq!(ink_in(&fd, WORKOUT_BAR_X, y, WORKOUT_BAR_W, BAR_H), 0);
        // And no armed workout draws nothing at all.
        let mut fe = Framebuffer::new();
        draw_workout_overlay(&mut fe, &snapshot());
        assert_eq!(ink_in(&fe, 0, 0, WIDTH, HEIGHT), 0);
    }

    #[test]
    fn zones_overlay_dominant_zone_is_widest_and_current_is_framed() {
        let mut snap = snapshot();
        snap.zone_time_s = [600, 300, 120, 0, 0];
        snap.zone_cutoffs = zone_cutoffs_from_max_hr(190);
        let mut fb = Framebuffer::new();
        draw_zones_overlay(&mut fb, &snap, Some(140)); // ~Z3
                                                       // Z1 (row 3, biggest time) out-fills Z2 (row 4) out-fills Z3 (row 5).
        let w1 = ink_in(&fb, ZONE_BAR_X, bar_y(3), ZONE_BAR_W, BAR_H);
        let w2 = ink_in(&fb, ZONE_BAR_X, bar_y(4), ZONE_BAR_W, BAR_H);
        let w3 = ink_in(&fb, ZONE_BAR_X, bar_y(5), ZONE_BAR_W, BAR_H);
        assert!(w1 > w2 && w2 > w3, "bars scale to the fullest zone");
        // A hollow frame marks the live zone row (Z3 -> row 5); the empty
        // zones 4/5 draw no bar fill.
        assert!(ink_in(&fb, ZONE_BAR_X - 2, 5 * CELL_H + 2, 2, CELL_H - 4) > 0);
    }

    #[test]
    fn zones_overlay_sensorless_run_draws_no_bars() {
        let mut fb = Framebuffer::new();
        draw_zones_overlay(&mut fb, &snapshot(), None);
        assert_eq!(
            ink_in(&fb, ZONE_BAR_X, 3 * CELL_H, ZONE_BAR_W, 5 * CELL_H),
            0
        );
    }

    #[test]
    fn splits_overlay_taller_bar_for_the_bigger_bucket() {
        let mut snap = snapshot();
        snap.pace_bucket_m = [1000.0, 4000.0, 2000.0, 0.0, 0.0, 0.0];
        let mut fb = Framebuffer::new();
        draw_splits_overlay(&mut fb, &snap);
        // The histogram panel carries ink, and the baseline rule spans it.
        let py = HIST_TOP_ROW * CELL_H;
        assert!(ink_in(&fb, HIST_X, py, HIST_W, HIST_H) > 0);
        assert_eq!(ink_in(&fb, HIST_X, py + HIST_H, HIST_W, 1), HIST_W);
    }

    #[test]
    fn mini_profile_auto_ranges_to_fill_the_cell() {
        let mut fb = Framebuffer::new();
        let samples = [10, 20, 40, 30, 50];
        draw_mini_profile(
            &mut fb,
            &MiniProfile {
                x: 4,
                y: 4,
                w: 60,
                h: 30,
                samples: &samples,
            },
        );
        // The series scales to its own span: the min sample (first, left column)
        // rides the baseline row and the max sample (last) reaches the top row —
        // not left hugging the middle of the cell.
        assert!(fb.pixel(4, 33), "min sample should sit on the baseline");
        assert!(fb.pixel(63, 4), "max sample should reach the top row"); // plot_x(4)=4+4*59/4
    }

    #[test]
    fn mini_profile_flat_series_sits_on_the_baseline() {
        let mut fb = Framebuffer::new();
        let samples = [1500, 1500, 1500];
        draw_mini_profile(
            &mut fb,
            &MiniProfile {
                x: 0,
                y: 0,
                w: 40,
                h: 20,
                samples: &samples,
            },
        );
        // Auto-range collapses to min == max; the primitive flattens onto the
        // baseline instead of dividing by zero or drawing a full-height line.
        let baseline = 19;
        assert!(fb.pixel(0, baseline) && fb.pixel(39, baseline));
        assert_eq!(ink_in(&fb, 0, 0, 40, baseline), 0);
    }

    #[test]
    fn mini_profile_empty_series_draws_nothing() {
        let mut fb = Framebuffer::new();
        let samples: [i32; 0] = [];
        draw_mini_profile(
            &mut fb,
            &MiniProfile {
                x: 0,
                y: 0,
                w: 40,
                h: 20,
                samples: &samples,
            },
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0);
    }

    // Centre + radius used by the dial/compass tests: a ring wholly on-panel so
    // every cardinal tip (cx±r, cy±r) is a real pixel to assert against.
    const CX: usize = WIDTH / 2; // 84
    const CY: usize = HEIGHT / 2; // 72
    const R: usize = 40;

    #[test]
    fn dial_full_fraction_lights_every_segment_solid() {
        let mut fb = Framebuffer::new();
        draw_dial(&mut fb, CX, CY, R, 8, 1.0);
        // The top segment (bearing 0) is centred on (cx, cy - r); a solid block
        // inks its centre pixel.
        assert!(
            fb.pixel(CX, CY - R),
            "top segment centre is inked when solid"
        );
    }

    #[test]
    fn dial_zero_fraction_is_hollow_frames_not_blank() {
        let mut fb = Framebuffer::new();
        draw_dial(&mut fb, CX, CY, R, 8, 0.0);
        // Hollow: the top segment's centre pixel is blank...
        assert!(
            !fb.pixel(CX, CY - R),
            "top segment centre is blank when hollow"
        );
        // ...but its frame still carries ink, so the empty ring is visible.
        assert!(
            ink_in(
                &fb,
                CX - DIAL_SEG,
                CY - R - DIAL_SEG,
                2 * DIAL_SEG,
                2 * DIAL_SEG
            ) > 0,
            "hollow segment keeps its frame"
        );
    }

    #[test]
    fn dial_half_fills_the_first_half_clockwise() {
        let mut fb = Framebuffer::new();
        draw_dial(&mut fb, CX, CY, R, 8, 0.5);
        // 4 of 8 lit: the top segment (i=0) is solid, the bottom (i=4, bearing
        // 180 -> centre (cx, cy + r)) is still hollow.
        assert!(fb.pixel(CX, CY - R), "first segment solid at half");
        assert!(!fb.pixel(CX, CY + R), "fifth segment still hollow at half");
    }

    #[test]
    fn dial_fill_grows_with_fraction() {
        let (mut lo, mut hi) = (Framebuffer::new(), Framebuffer::new());
        draw_dial(&mut lo, CX, CY, R, 12, 0.25);
        draw_dial(&mut hi, CX, CY, R, 12, 0.75);
        assert!(
            ink_in(&hi, 0, 0, WIDTH, HEIGHT) > ink_in(&lo, 0, 0, WIDTH, HEIGHT),
            "a bigger fraction inks more of the ring"
        );
    }

    #[test]
    fn dial_out_of_range_fractions_clamp() {
        let (mut over, mut full) = (Framebuffer::new(), Framebuffer::new());
        draw_dial(&mut over, CX, CY, R, 8, 2.0);
        draw_dial(&mut full, CX, CY, R, 8, 1.0);
        assert_eq!(
            ink_in(&over, 0, 0, WIDTH, HEIGHT),
            ink_in(&full, 0, 0, WIDTH, HEIGHT),
            "frac > 1 clamps to full"
        );
        let (mut under, mut empty) = (Framebuffer::new(), Framebuffer::new());
        draw_dial(&mut under, CX, CY, R, 8, -1.0);
        draw_dial(&mut empty, CX, CY, R, 8, 0.0);
        assert_eq!(
            ink_in(&under, 0, 0, WIDTH, HEIGHT),
            ink_in(&empty, 0, 0, WIDTH, HEIGHT),
            "frac < 0 clamps to empty"
        );
    }

    #[test]
    fn dial_zero_segments_is_a_noop() {
        let mut fb = Framebuffer::new();
        draw_dial(&mut fb, CX, CY, R, 0, 0.5);
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0);
    }

    #[test]
    fn compass_points_to_each_cardinal_bearing() {
        for (bearing, (tx, ty)) in [
            (0u16, (CX, CY - R)),
            (90, (CX + R, CY)),
            (180, (CX, CY + R)),
            (270, (CX - R, CY)),
        ] {
            let mut fb = Framebuffer::new();
            draw_compass(&mut fb, CX, CY, R, bearing);
            assert!(
                fb.pixel(tx, ty),
                "bearing {bearing} should reach the tip at ({tx}, {ty})"
            );
        }
    }

    #[test]
    fn compass_360_matches_0() {
        let (mut a, mut b) = (Framebuffer::new(), Framebuffer::new());
        draw_compass(&mut a, CX, CY, R, 0);
        draw_compass(&mut b, CX, CY, R, 360);
        assert_eq!(
            ink_in(&a, 0, 0, WIDTH, HEIGHT),
            ink_in(&b, 0, 0, WIDTH, HEIGHT),
            "360 wraps to 0"
        );
        assert!(fb_eq(&a, &b), "360 renders identically to 0");
    }

    #[test]
    fn compass_keeps_a_fixed_north_tick_when_pointing_away() {
        let mut fb = Framebuffer::new();
        draw_compass(&mut fb, CX, CY, R, 180); // arrow points south
        assert!(
            ink_in(
                &fb,
                CX - 1,
                CY - R - COMPASS_N_TICK as usize,
                3,
                COMPASS_N_TICK as usize
            ) > 0,
            "north reference tick is drawn regardless of bearing"
        );
    }

    fn fb_eq(a: &Framebuffer, b: &Framebuffer) -> bool {
        (0..HEIGHT).all(|y| (0..WIDTH).all(|x| a.pixel(x, y) == b.pixel(x, y)))
    }

    use watch_core::course::CoursePoint;
    use watch_core::nav_map;
    use watch_core::record::{ElevProfileView, ELEV_PROFILE_CAP};

    fn elev_snapshot(series: &[i32]) -> Snapshot {
        let mut snap = snapshot();
        let mut view = ElevProfileView::empty();
        view.samples[..series.len()].copy_from_slice(series);
        view.len = series.len();
        snap.elev_profile = view;
        snap
    }

    #[test]
    fn elev_profile_fills_the_page_body_and_spares_the_hero_and_baseline_rows() {
        let series: [i32; 9] = [1600, 1660, 1740, 1830, 1880, 1810, 1720, 1655, 1602];
        let mut fb = Framebuffer::new();
        draw_elev_profile_overlay(&mut fb, &elev_snapshot(&series));
        assert!(
            ink_in(
                &fb,
                ELEV_PROFILE_X,
                ELEV_PROFILE_Y,
                ELEV_PROFILE_W,
                ELEV_PROFILE_H
            ) > 0,
            "the profile drew nothing"
        );
        // Rows 0-2 are the hero + the vert-totals context row the face owns.
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, ELEV_PROFILE_Y), 0, "hero rows");
        // The bottom band the face keeps for its GPS row stays clear, as do the
        // side margins.
        let below = ELEV_PROFILE_Y + ELEV_PROFILE_H;
        assert_eq!(ink_in(&fb, 0, below, WIDTH, HEIGHT - below), 0, "below");
        assert_eq!(ink_in(&fb, 0, 0, ELEV_PROFILE_X, HEIGHT), 0, "left margin");
        let right = ELEV_PROFILE_X + ELEV_PROFILE_W;
        assert_eq!(ink_in(&fb, right, 0, WIDTH - right, HEIGHT), 0, "right");
    }

    #[test]
    fn elev_profile_shares_the_splits_histogram_panel() {
        // Both glance pages plot into the same page-body rect below the context
        // row; a drift between them would put one of the two over a face row.
        assert_eq!(ELEV_PROFILE_X, HIST_X);
        assert_eq!(ELEV_PROFILE_Y, HIST_TOP_ROW * CELL_H);
        assert_eq!(ELEV_PROFILE_W, HIST_W);
        assert_eq!(ELEV_PROFILE_H, HIST_H);
    }

    #[test]
    fn elev_profile_empty_series_draws_nothing() {
        let mut fb = Framebuffer::new();
        draw_elev_profile_overlay(&mut fb, &snapshot());
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0);
    }

    #[test]
    fn elev_profile_flat_series_sits_on_the_baseline_not_mid_panel() {
        // A dead-level treadmill leg auto-ranges to min == max; it must read as
        // flat along the bottom rather than as a full-height climb.
        let mut fb = Framebuffer::new();
        draw_elev_profile_overlay(&mut fb, &elev_snapshot(&[1500; 6]));
        let baseline = ELEV_PROFILE_Y + ELEV_PROFILE_H - 1;
        assert!(fb.pixel(ELEV_PROFILE_X, baseline));
        assert_eq!(
            ink_in(
                &fb,
                ELEV_PROFILE_X,
                ELEV_PROFILE_Y,
                ELEV_PROFILE_W,
                ELEV_PROFILE_H - 1
            ),
            0
        );
    }

    #[test]
    fn elev_profile_a_full_buffer_stays_inside_the_panel() {
        // The recorder's whole banked series at once — the multi-day ultra case,
        // where a per-sample column is a fraction of a pixel wide.
        let series: [i32; ELEV_PROFILE_CAP] = core::array::from_fn(|i| 1000 + (i as i32 % 37) * 25);
        let mut fb = Framebuffer::new();
        draw_elev_profile_overlay(&mut fb, &elev_snapshot(&series));
        assert!(
            ink_in(
                &fb,
                ELEV_PROFILE_X,
                ELEV_PROFILE_Y,
                ELEV_PROFILE_W,
                ELEV_PROFILE_H
            ) > 0
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, ELEV_PROFILE_Y), 0);
        let below = ELEV_PROFILE_Y + ELEV_PROFILE_H;
        assert_eq!(ink_in(&fb, 0, below, WIDTH, HEIGHT - below), 0);
    }

    fn route_elev_snapshot(series: &[i16], permille: Option<u16>) -> Snapshot {
        let mut snap = snapshot();
        let mut view = watch_core::record::RouteElevView {
            gain_m: 100,
            loss_m: 50,
            points: 12,
            total_m: 42_195,
            samples: [0; COURSE_PROFILE_CAP],
            len: series.len(),
        };
        view.samples[..series.len()].copy_from_slice(series);
        snap.route_elev = Some(view);
        snap.route_position_permille = permille;
        snap
    }

    #[test]
    fn route_elev_profile_fills_the_page_body_it_shares_with_the_run_profile() {
        let series: [i16; 9] = [1600, 1660, 1740, 1830, 1880, 1810, 1720, 1655, 1602];
        let mut fb = Framebuffer::new();
        draw_route_elev_overlay(&mut fb, &route_elev_snapshot(&series, None));
        assert!(
            ink_in(
                &fb,
                ELEV_PROFILE_X,
                ELEV_PROFILE_Y,
                ELEV_PROFILE_W,
                ELEV_PROFILE_H
            ) > 0,
            "the course profile drew nothing"
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, ELEV_PROFILE_Y), 0, "hero rows");
        let below = ELEV_PROFILE_Y + ELEV_PROFILE_H;
        assert_eq!(ink_in(&fb, 0, below, WIDTH, HEIGHT - below), 0, "below");
        assert_eq!(ink_in(&fb, 0, 0, ELEV_PROFILE_X, HEIGHT), 0, "left margin");
        let right = ELEV_PROFILE_X + ELEV_PROFILE_W;
        assert_eq!(ink_in(&fb, right, 0, WIDTH - right, HEIGHT), 0, "right");
    }

    #[test]
    fn route_elev_draws_nothing_without_a_course_or_without_elevation() {
        let mut fb = Framebuffer::new();
        draw_route_elev_overlay(&mut fb, &snapshot());
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0, "no course pushed");
        // A course pushed without elevation must not be drawn as a flat line.
        draw_route_elev_overlay(&mut fb, &route_elev_snapshot(&[], Some(500)));
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0, "course, no elevation");
    }

    #[test]
    fn route_elev_marks_the_runners_position_along_the_profile() {
        let series: [i16; 4] = [1500, 1500, 1500, 1500];
        // A flat series sits on the baseline, so any ink above it is the marker.
        let mut without = Framebuffer::new();
        draw_route_elev_overlay(&mut without, &route_elev_snapshot(&series, None));
        let above_baseline =
            |fb: &Framebuffer, x: usize| ink_in(fb, x, ELEV_PROFILE_Y, 1, ELEV_PROFILE_H - 1);
        let mid_x = ELEV_PROFILE_X + (ELEV_PROFILE_W - 1) / 2;
        assert_eq!(
            above_baseline(&without, mid_x),
            0,
            "no marker without a fix"
        );

        let mut half = Framebuffer::new();
        draw_route_elev_overlay(&mut half, &route_elev_snapshot(&series, Some(500)));
        assert!(above_baseline(&half, mid_x) > 0, "marker at half distance");
        assert_eq!(
            above_baseline(&half, ELEV_PROFILE_X),
            0,
            "the marker is not at the start"
        );

        // At the start and at the finish the marker rides the panel edges.
        let mut start = Framebuffer::new();
        draw_route_elev_overlay(&mut start, &route_elev_snapshot(&series, Some(0)));
        assert!(above_baseline(&start, ELEV_PROFILE_X) > 0);
        let mut finish = Framebuffer::new();
        draw_route_elev_overlay(&mut finish, &route_elev_snapshot(&series, Some(1000)));
        assert!(above_baseline(&finish, ELEV_PROFILE_X + ELEV_PROFILE_W - 1) > 0);
    }

    #[test]
    fn route_elev_a_full_capacity_series_and_an_over_range_marker_stay_inside_the_panel() {
        let series: [i16; COURSE_PROFILE_CAP] =
            core::array::from_fn(|i| 1000 + (i as i16 % 37) * 25);
        let mut fb = Framebuffer::new();
        // A marker over its declared range must clamp to the panel, never index
        // past it.
        draw_route_elev_overlay(&mut fb, &route_elev_snapshot(&series, Some(u16::MAX)));
        assert!(
            ink_in(
                &fb,
                ELEV_PROFILE_X,
                ELEV_PROFILE_Y,
                ELEV_PROFILE_W,
                ELEV_PROFILE_H
            ) > 0
        );
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, ELEV_PROFILE_Y), 0);
        let below = ELEV_PROFILE_Y + ELEV_PROFILE_H;
        assert_eq!(ink_in(&fb, 0, below, WIDTH, HEIGHT - below), 0);
        let right = ELEV_PROFILE_X + ELEV_PROFILE_W;
        assert_eq!(ink_in(&fb, right, 0, WIDTH - right, HEIGHT), 0);
    }

    fn cp(lat_deg: f64, lon_deg: f64) -> CoursePoint {
        CoursePoint { lat_deg, lon_deg }
    }

    /// A course far larger than one auto-zoom window on both axes — the shape
    /// every real ultra course has, so the panel windows around the runner and
    /// most of the polyline projects off-panel.
    fn long_course() -> Course {
        Course::from_points(&[
            cp(40.00, -105.00),
            cp(40.05, -105.02),
            cp(40.10, -105.00),
            cp(40.15, -105.03),
        ])
        .unwrap()
    }

    #[test]
    fn nav_panel_never_paints_outside_its_own_rows() {
        // An auto-zoomed long course projects its far points tens of pixels
        // above and below the window. The framebuffer only clips at the display
        // edge, so an unclipped polyline scribbles the NAV title row above the
        // panel and the along-course / GPS rows below it.
        let course = long_course();
        let runner = (40.05, -105.02);
        let panel = nav_map::nav_panel(&course, Some(runner), NAV_PANEL_GEOM);
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        let top = PANEL_TOP_PX as usize;
        let h = PANEL_H_PX as usize;
        assert!(ink_in(&fb, 0, top, WIDTH, h) > 0, "the panel drew nothing");
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, top), 0, "ink above the panel");
        assert_eq!(
            ink_in(&fb, 0, top + h, WIDTH, HEIGHT - top - h),
            0,
            "ink below the panel"
        );
    }

    /// A course comfortably inside one auto-zoom window, so the panel keeps
    /// the whole-course overview.
    fn short_course() -> Course {
        Course::from_points(&[
            cp(40.000, -105.000),
            cp(40.001, -105.002),
            cp(40.002, -105.000),
        ])
        .unwrap()
    }

    #[test]
    fn the_marker_halo_separates_the_cross_from_a_course_leg_under_it() {
        // A runner ON the line (the normal case, and exactly where forks
        // converge): the halo ring around the cross is blank even though the
        // polyline runs straight through it, and the cross itself is inked.
        let course = short_course();
        let runner = (40.001, -105.001);
        let panel = nav_map::nav_panel(&course, Some(runner), NAV_PANEL_GEOM);
        let (mx, my) = panel.marker.expect("runner projects onto the panel");
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        assert!(
            fb.pixel(mx as usize, my as usize),
            "the cross centre is ink"
        );
        // The ring one past the arms: every cell blank, course or not.
        let halo = MARKER_ARM_PX + 1;
        for x in (mx - halo)..=(mx + halo) {
            for y in [my - halo, my + halo] {
                assert!(
                    !fb.pixel(x as usize, y as usize),
                    "halo cell ({x},{y}) still inked"
                );
            }
        }
        for y in (my - halo)..=(my + halo) {
            for x in [mx - halo, mx + halo] {
                assert!(
                    !fb.pixel(x as usize, y as usize),
                    "halo cell ({x},{y}) still inked"
                );
            }
        }
    }

    #[test]
    fn nav_panel_clipping_leaves_a_fitted_course_untouched() {
        // A course that fits whole projects inside the panel by construction,
        // so the clip must be a no-op there — the fix can't cost the common
        // case a pixel.
        let course = short_course();
        let runner = (40.001, -105.001);
        let panel = nav_map::nav_panel(&course, Some(runner), NAV_PANEL_GEOM);
        let mut clipped = Framebuffer::new();
        draw_nav_panel(&mut clipped, &course, &panel, None);
        let mut raw = Framebuffer::new();
        for w in course.points().windows(2) {
            let (x0, y0) = panel.fit.to_px(w[0].lat_deg, w[0].lon_deg);
            let (x1, y1) = panel.fit.to_px(w[1].lat_deg, w[1].lon_deg);
            raw.draw_line(x0, y0 + PANEL_TOP_PX, x1, y1 + PANEL_TOP_PX, true);
        }
        let (mx, my) = panel.marker.unwrap();
        raw.draw_line(mx - MARKER_ARM_PX, my, mx + MARKER_ARM_PX, my, true);
        raw.draw_line(mx, my - MARKER_ARM_PX, mx, my + MARKER_ARM_PX, true);
        assert!(fb_eq(&clipped, &raw));
    }

    #[test]
    fn nav_panel_marker_cross_stays_whole_inside_the_panel() {
        let course = short_course();
        let runner = (40.001, -105.001);
        let panel = nav_map::nav_panel(&course, Some(runner), NAV_PANEL_GEOM);
        let (mx, my) = panel.marker.expect("an on-panel runner has a marker");
        // The whole 5-px cross fits: `marker_px` refuses a marker whose arms
        // would reach past an edge, so no arm may be clipped or wrap.
        assert!(mx - MARKER_ARM_PX >= 0 && mx + MARKER_ARM_PX <= PANEL_X_MAX);
        assert!(my - MARKER_ARM_PX >= PANEL_TOP_PX && my + MARKER_ARM_PX <= PANEL_Y_MAX);
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        for arm in -MARKER_ARM_PX..=MARKER_ARM_PX {
            assert!(fb.pixel((mx + arm) as usize, my as usize), "h arm {arm}");
            assert!(fb.pixel(mx as usize, (my + arm) as usize), "v arm {arm}");
        }
    }

    #[test]
    fn nav_panel_off_panel_runner_draws_no_marker() {
        // Far north of a whole-course fit: the cross would land on the rows
        // above the panel, so `nav_map` withholds it and the banner is the
        // source of truth. Compare against the courseless frame to prove no
        // marker ink appears anywhere.
        let course = short_course();
        let panel = nav_map::nav_panel(&course, Some((41.0, -105.0)), NAV_PANEL_GEOM);
        assert_eq!(panel.marker, None);
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        let mut line_only = Framebuffer::new();
        for w in course.points().windows(2) {
            let (x0, y0) = panel.fit.to_px(w[0].lat_deg, w[0].lon_deg);
            let (x1, y1) = panel.fit.to_px(w[1].lat_deg, w[1].lon_deg);
            line_only.draw_line(x0, y0 + PANEL_TOP_PX, x1, y1 + PANEL_TOP_PX, true);
        }
        assert!(fb_eq(&fb, &line_only));
    }

    #[test]
    fn nav_panel_all_identical_points_draw_a_dot_not_garbage() {
        // A degenerate course (every point coincident) makes `PanelFit`'s scale
        // zero. It must collapse to the panel centre rather than dividing by
        // zero or smearing the whole band.
        let course =
            Course::from_points(&[cp(40.0, -105.0), cp(40.0, -105.0), cp(40.0, -105.0)]).unwrap();
        let panel = nav_map::nav_panel(&course, Some((40.0, -105.0)), NAV_PANEL_GEOM);
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        let top = PANEL_TOP_PX as usize;
        let h = PANEL_H_PX as usize;
        let ink = ink_in(&fb, 0, top, WIDTH, h);
        assert!(ink > 0, "a degenerate course still shows where it is");
        assert!(ink <= 10, "and stays a dot + cross, not a smear: {ink}");
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, top), 0);
        assert_eq!(ink_in(&fb, 0, top + h, WIDTH, HEIGHT - top - h), 0);
    }

    #[test]
    fn nav_panel_off_course_banner_is_drawn_last_and_wins_the_panel() {
        // Z-order: the inverse-video banner must survive the polyline and the
        // marker underneath it, so a lost runner can't read a crumb through
        // the alert. Drawing the same frame with the banner alone on top of the
        // same underlay must land identically.
        let course = long_course();
        let runner = (40.05, -105.02);
        let panel = nav_map::nav_panel(&course, Some(runner), NAV_PANEL_GEOM);
        let mut composed = Framebuffer::new();
        draw_nav_panel(&mut composed, &course, &panel, Some("OFF COURSE"));
        let mut layered = Framebuffer::new();
        draw_nav_panel(&mut layered, &course, &panel, None);
        layered.draw_banner_2x(face::NAV_ALERT_ROW, "OFF COURSE");
        assert!(fb_eq(&composed, &layered));
        // The banner's two rows sit inside the panel, so it can't cover the
        // rows the face owns.
        let banner_top = face::NAV_ALERT_ROW * CELL_H;
        assert!(banner_top >= PANEL_TOP_PX as usize);
        assert!(banner_top + 2 * CELL_H <= (PANEL_TOP_PX + PANEL_H_PX as i32) as usize);
    }

    #[test]
    fn nav_panel_survives_a_wild_fix_without_wrapping_a_line_back_in() {
        // A cold-start GPS reporting a position on the far side of the planet
        // auto-zooms a window there, projecting the real course hundreds of
        // thousands of pixels away. The clip's interpolation must not wrap and
        // put a garbage line back inside the panel — the marker at the window's
        // centre is all that's left to draw.
        let course = long_course();
        let panel = nav_map::nav_panel(&course, Some((-40.0, 75.0)), NAV_PANEL_GEOM);
        let mut fb = Framebuffer::new();
        draw_nav_panel(&mut fb, &course, &panel, None);
        let (mx, my) = panel.marker.expect("the window centres on the runner");
        let mut marker_only = Framebuffer::new();
        marker_only.draw_line(mx - MARKER_ARM_PX, my, mx + MARKER_ARM_PX, my, true);
        marker_only.draw_line(mx, my - MARKER_ARM_PX, mx, my + MARKER_ARM_PX, true);
        // The wild fix auto-zoomed, so the panel also carries its ZOOM label.
        marker_only.draw_text(
            face::COLS - ZOOM_LABEL.len(),
            face::NAV_PANEL_TOP_ROW + face::NAV_PANEL_ROWS - 1,
            ZOOM_LABEL,
        );
        assert!(fb_eq(&fb, &marker_only), "a course leg came back into view");
    }

    #[test]
    fn nav_panel_clip_interpolates_a_far_off_panel_endpoint() {
        // Both ends beyond i32's product range for the naive multiply, crossing
        // the panel diagonally: the clipped span stays on the panel boundary.
        let ((cx0, cy0), (cx1, cy1)) = clip_to_panel(
            -600_000,
            PANEL_TOP_PX - 600_000,
            600_000,
            PANEL_Y_MAX + 600_000,
        )
        .unwrap();
        for (x, y) in [(cx0, cy0), (cx1, cy1)] {
            assert!((0..=PANEL_X_MAX).contains(&x), "x {x}");
            assert!((PANEL_TOP_PX..=PANEL_Y_MAX).contains(&y), "y {y}");
        }
    }

    #[test]
    fn nav_panel_segment_wholly_off_panel_is_dropped_not_wrapped() {
        assert_eq!(clip_to_panel(10, 0, 100, PANEL_TOP_PX - 1), None);
        assert_eq!(clip_to_panel(10, PANEL_Y_MAX + 1, 100, HEIGHT as i32), None);
        assert_eq!(clip_to_panel(-40, 20, -1, 60), None);
        assert_eq!(clip_to_panel(WIDTH as i32, 20, 400, 60), None);
        // A segment crossing the panel keeps both ends on the boundary.
        let ((cx0, cy0), (cx1, cy1)) =
            clip_to_panel(84, PANEL_TOP_PX - 40, 84, PANEL_Y_MAX + 40).unwrap();
        assert_eq!((cx0, cy0), (84, PANEL_TOP_PX));
        assert_eq!((cx1, cy1), (84, PANEL_Y_MAX));
    }

    /// A trackback view walked `steps` hops of `step_m` due east from an
    /// arbitrary origin, one second apart — enough movement to bank a
    /// breadcrumb, a bearing back to the start and a fresh heading.
    fn trackback_east(steps: u32, step_m: f64) -> TrackbackView {
        const LAT0: f64 = 40.0;
        const LON0: f64 = -105.0;
        let lon_per_m = 1.0 / (watch_core::record::METRES_PER_DEGREE_LAT * LAT0.to_radians().cos());
        let mut tb = trackback::Trackback::new();
        for i in 0..=steps {
            tb.on_point(LAT0, LON0 + i as f64 * step_m * lon_per_m, i);
        }
        tb.view()
    }

    #[test]
    fn trackback_overlay_stays_inside_the_map_rect_and_the_arrow_band() {
        let view = trackback_east(40, 6.0);
        let mut fb = Framebuffer::new();
        draw_trackback_overlay(&mut fb, &view, 40);
        let (mx, my) = (MAP_X as usize, MAP_Y as usize);
        assert!(
            ink_in(&fb, mx, my, MAP_W as usize, MAP_H as usize) > 0,
            "map"
        );
        // Nothing above the map rows, and nothing on the bottom GPS row.
        assert_eq!(ink_in(&fb, mx, 0, MAP_W as usize, my), 0, "above the map");
        assert_eq!(
            ink_in(
                &fb,
                mx,
                my + MAP_H as usize,
                MAP_W as usize,
                HEIGHT - my - MAP_H as usize
            ),
            0,
            "below the map"
        );
        // The arrow keeps to the reserved text cells over rows 5-7 — clear of
        // the map, and clear of the HDG / BRG rows the face writes above it.
        assert!(ink_in(&fb, 0, 5 * CELL_H, mx, 3 * CELL_H) > 0, "arrow");
        assert_eq!(ink_in(&fb, 0, 0, mx, 5 * CELL_H), 0, "arrow band only");
        assert_eq!(ink_in(&fb, 0, 8 * CELL_H, mx, CELL_H), 0, "clear of row 8");
    }

    #[test]
    fn trackback_start_marker_box_clears_the_map_edge_at_every_extreme() {
        // The start box reaches START_MARK_ARM px past the projected start, and
        // `project_track` insets by exactly that margin — so a start that lands
        // on the polyline's extreme still frames inside the rect rather than
        // clipping half away or bleeding into the reserved text cells. Walk each
        // cardinal direction so the start takes each edge in turn.
        for (bearing_e, bearing_n) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            const LAT0: f64 = 40.0;
            const LON0: f64 = -105.0;
            let m_per_deg = watch_core::record::METRES_PER_DEGREE_LAT;
            let lon_per_m = 1.0 / (m_per_deg * LAT0.to_radians().cos());
            let mut tb = trackback::Trackback::new();
            for i in 0..=40u32 {
                tb.on_point(
                    LAT0 + i as f64 * 6.0 * bearing_n / m_per_deg,
                    LON0 + i as f64 * 6.0 * bearing_e * lon_per_m,
                    i,
                );
            }
            let view = tb.view();
            let mut pts = [(0u16, 0u16); trackback::BREADCRUMB_CAP + 1];
            let map = trackback::project_track(&view, MAP_W, MAP_H, &mut pts).unwrap();
            let (sx, sy) = (MAP_X + map.start.0 as i32, MAP_Y + map.start.1 as i32);
            assert!(sx - START_MARK_ARM >= MAP_X, "box left of the map rect");
            assert!(sx + START_MARK_ARM < MAP_X + MAP_W as i32, "box right");
            assert!(sy - START_MARK_ARM >= MAP_Y, "box above the map rect");
            assert!(sy + START_MARK_ARM < MAP_Y + MAP_H as i32, "box below");
        }
    }

    #[test]
    fn trackback_start_and_current_markers_are_distinguishable() {
        let view = trackback_east(40, 6.0);
        let mut fb = Framebuffer::new();
        draw_trackback_overlay(&mut fb, &view, 40);
        let mut pts = [(0u16, 0u16); trackback::BREADCRUMB_CAP + 1];
        let map = trackback::project_track(&view, MAP_W, MAP_H, &mut pts).unwrap();
        let (sx, sy) = (
            (MAP_X + map.start.0 as i32) as usize,
            (MAP_Y + map.start.1 as i32) as usize,
        );
        let (cx, cy) = (
            (MAP_X + map.current.0 as i32) as usize,
            (MAP_Y + map.current.1 as i32) as usize,
        );
        assert!(sx < cx, "start west of the runner on an east walk");
        // The start is a hollow box (frame inked, one-in interior blank on the
        // rows above/below the polyline); the current position is a solid dot.
        assert!(
            fb.pixel(sx - 2, sy - 2) && fb.pixel(sx + 2, sy + 2),
            "box frame"
        );
        assert!(!fb.pixel(sx - 1, sy - 1), "box interior is hollow");
        assert!(fb.pixel(cx, cy) && fb.pixel(cx - 1, cy - 1), "dot is solid");
    }

    #[test]
    fn trackback_inactive_view_draws_nothing() {
        let mut fb = Framebuffer::new();
        draw_trackback_overlay(&mut fb, &TrackbackView::empty(), 100);
        assert_eq!(ink_in(&fb, 0, 0, WIDTH, HEIGHT), 0);
    }

    #[test]
    fn trackback_single_point_draws_a_map_without_an_arrow() {
        // One accepted fix: the whole track is one point, which must still
        // render the start + current markers at the map centre rather than
        // panicking on the degenerate span — and no heading exists yet, so the
        // arrow band stays blank (the face writes `--` there).
        let view = trackback_east(0, 0.0);
        let mut fb = Framebuffer::new();
        draw_trackback_overlay(&mut fb, &view, 0);
        assert!(
            ink_in(
                &fb,
                MAP_X as usize,
                MAP_Y as usize,
                MAP_W as usize,
                MAP_H as usize
            ) > 0
        );
        assert_eq!(ink_in(&fb, 0, 5 * CELL_H, MAP_X as usize, 3 * CELL_H), 0);
    }

    #[test]
    fn trackback_stale_heading_drops_the_arrow_but_keeps_the_map() {
        let view = trackback_east(40, 6.0);
        let stale = 40 + trackback::HEADING_STALE_S + 1;
        assert!(view.arrow_sector(stale).is_none());
        let mut fb = Framebuffer::new();
        draw_trackback_overlay(&mut fb, &view, stale);
        assert_eq!(ink_in(&fb, 0, 5 * CELL_H, MAP_X as usize, 3 * CELL_H), 0);
        assert!(
            ink_in(
                &fb,
                MAP_X as usize,
                MAP_Y as usize,
                MAP_W as usize,
                MAP_H as usize
            ) > 0
        );
    }
}
