//! The page-grid overview — the run view's navigation map.
//!
//! The BTN3 cycle is a linear walk; fine for the handful of near pages, but a
//! late page in a wide mask is many blind presses out, and nothing on screen
//! says what pages even exist. The grid is the fix: hold BTN3 (past the
//! page-back long-press) and every enabled page appears at once as a grid of
//! four-glyph codes in cycle order, with a cursor box on the current page.
//! Tap BTN3 to step the cursor (BTN1 taps backward; holds jump a row either
//! way), BTN4 to jump — or just stop pressing: after [`GRID_AUTOSELECT_S`]
//! with no input the grid jumps to the cursor on its own, so the entire flow
//! needs one finger and no confirm press. BTN2 cancels; every in-grid press
//! is swallowed — a navigation modal must never pause or stop the recording.
//!
//! Because the modal remaps buttons, it **states its own map**: row 0 is the
//! button legend and row 1 the cursor page's full name, so no jump commits off
//! a four-glyph code alone and BTN2's loss of the stop is on screen rather than
//! discovered. Both rows cost body capacity, which §333's scrolling window
//! makes affordable — before it, the body was a hard 32-cell assert.
//!
//! Pure state + layout, like the rest of `core`: the app's button task owns
//! the press timing and the deadline timer, the ui task draws the rows this
//! module lays out (`grid_rows`) plus the cursor box (`grid_cell` → pixels in
//! `watch_render::widgets`). Everything here is host-tested.

use core::fmt::Write;

use crate::face::{Row, ROWS};
use crate::page::Page;

/// Cells per grid row. Four five-cell columns (a four-glyph code + one gap)
/// span 20 of the 21 text columns.
pub const GRID_COLS: usize = 4;

/// Text row carrying the cursor page's full name.
pub const GRID_NAME_ROW: usize = 1;

/// First text row of the grid body; row 0 is the button legend, row 1 the
/// cursor's name.
pub const GRID_TOP_ROW: usize = 2;

/// Body rows available to cells.
pub const GRID_BODY_ROWS: usize = ROWS - GRID_TOP_ROW;

/// Cells one screenful of grid shows. The enabled set can exceed it (33 pages
/// need nine rows of four and the body has seven), so the body is a window onto
/// the cycle anchored on the cursor rather than a silent truncation of the
/// tail — see [`window_origin_row`].
pub const GRID_CAPACITY: usize = GRID_COLS * GRID_BODY_ROWS;

/// Seconds of grid inactivity after which the cursor page is selected on its
/// own — the no-confirm-press path: hold to open, tap to the target, lower
/// the wrist.
pub const GRID_AUTOSELECT_S: u32 = 3;

/// One grid column's width in text cells: four code glyphs + a gap. Public so
/// the render widget's cursor-box geometry derives from the same constant the
/// row layout uses.
pub const GRID_CELL_CHARS: usize = 5;

/// The open grid: just the cursor — the layout is a pure function of the
/// mask, so nothing else is state. Movement walks the same filtered cycle
/// BTN3 walks ([`Page::next_in`]), so the grid can never reach a page the
/// cycle couldn't.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PageGrid {
    cursor: Page,
}

impl PageGrid {
    /// Open on the current page — or, when the runner is parked on a page
    /// whose data has since vanished from the mask, on the next enabled one
    /// (the same move-off-and-don't-return rule the cycle applies).
    pub fn open(current: Page, mask: u64) -> Self {
        let cursor = if enabled(current, mask) {
            current
        } else {
            current.next_in(mask)
        };
        Self { cursor }
    }

    pub fn cursor(&self) -> Page {
        self.cursor
    }

    /// A BTN3 tap: cursor one cell forward, wrapping with the cycle.
    pub fn tap(&mut self, mask: u64) {
        self.cursor = self.cursor.next_in(mask);
    }

    /// A BTN3 hold: cursor one grid row down — [`GRID_COLS`] steps along the
    /// enabled cycle, so it lands directly below (and wraps like a tap past
    /// the tail). The long-jump that makes the grid faster than the walk.
    pub fn row_down(&mut self, mask: u64) {
        for _ in 0..GRID_COLS {
            self.cursor = self.cursor.next_in(mask);
        }
    }

    /// A BTN1 tap: cursor one cell back — [`Self::tap`]'s exact inverse.
    /// Forward-only movement made the cells just behind the cursor the most
    /// expensive on the whole grid (a near-full lap); the symmetric grammar
    /// (BTN3 forward, BTN1 back, hold = a row either way) caps any cell under
    /// the full mask at six actions.
    pub fn back(&mut self, mask: u64) {
        self.cursor = self.cursor.prev_in(mask);
    }

    /// A BTN1 hold: cursor one grid row up — [`Self::row_down`]'s inverse.
    pub fn row_up(&mut self, mask: u64) {
        for _ in 0..GRID_COLS {
            self.cursor = self.cursor.prev_in(mask);
        }
    }
}

fn enabled(page: Page, mask: u64) -> bool {
    page.bit() & (mask | Page::Dashboard.bit()) != 0
}

/// Visit the enabled pages in cycle order (Dashboard first — it is always
/// enabled and the cycle's anchor).
fn for_each_enabled(mask: u64, mut f: impl FnMut(usize, Page)) {
    let mut i = 0;
    let mut p = Page::Dashboard;
    loop {
        f(i, p);
        i += 1;
        p = p.next_in(mask);
        if p == Page::Dashboard {
            break;
        }
    }
}

/// Where the cursor sits in the enabled cycle, and how many pages that cycle
/// has. A cursor whose bit has since cleared reports index 0, which anchors the
/// window at the top — it loses its box either way (see [`grid_cell`]).
fn cursor_index(mask: u64, cursor: Page) -> (usize, usize) {
    let mut index = 0;
    let mut count = 0;
    for_each_enabled(mask, |i, p| {
        count = i + 1;
        if p == cursor {
            index = i;
        }
    });
    (index, count)
}

/// First cycle row the body window shows: 0 while the enabled set fits one
/// screenful, otherwise the smallest scroll that keeps the cursor's row on
/// screen, never past the tail.
fn window_origin_row(cursor_index: usize, enabled_count: usize) -> usize {
    let last_origin = enabled_count
        .div_ceil(GRID_COLS)
        .saturating_sub(GRID_BODY_ROWS);
    (cursor_index / GRID_COLS)
        .saturating_sub(GRID_BODY_ROWS - 1)
        .min(last_origin)
}

/// The body row cell `i` of the cycle occupies in a window starting at
/// `origin`, or `None` when it falls outside the window.
fn windowed_row(i: usize, origin: usize) -> Option<usize> {
    let row = i / GRID_COLS;
    row.checked_sub(origin).filter(|r| *r < GRID_BODY_ROWS)
}

/// The grid's text rows: the button legend, the cursor page's full name, then
/// the enabled pages' codes in cycle order, [`GRID_COLS`] per row. The ui task
/// draws these exactly like face rows; the cursor box is pixel work
/// ([`grid_cell`] + the widget).
///
/// The body shows [`GRID_CAPACITY`] cells; a wider enabled set scrolls in whole
/// rows around `cursor` so the cursor's row is always on screen.
///
/// Row 0 names BTN2 and BTN1 — the two buttons whose in-grid meaning is not
/// self-revealing, because pressing them leaves the modal. BTN3/BTN4 are
/// deliberately unlabelled: a press moves the visible cursor one cell in the
/// same direction it pages and commits nothing, so the runner learns them for
/// free. BTN2 is the one whose remap is a *safety* surprise — outside the grid
/// it arms the stop, in here it cancels, and a runner who mashes it cannot
/// tell from the closing grid whether the stop armed (it did not). `B2 EXIT`
/// names the way back to where BTN2 stops, and the run view's own `STOP? BTN2`
/// banner takes it from there. `B1 GO` is the START-confirms idiom every
/// five-button watch trains (§350).
pub fn grid_rows(mask: u64, cursor: Page) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    let _ = write!(rows[0], "{:<16}B1 GO", "B2 EXIT");
    let _ = rows[GRID_NAME_ROW].push_str(cursor.name());
    let (index, count) = cursor_index(mask, cursor);
    let origin = window_origin_row(index, count);
    for_each_enabled(mask, |i, p| {
        let Some(row) = windowed_row(i, origin).map(|r| GRID_TOP_ROW + r) else {
            return;
        };
        let col_start = (i % GRID_COLS) * GRID_CELL_CHARS;
        while rows[row].len() < col_start {
            let _ = rows[row].push(' ');
        }
        let _ = rows[row].push_str(p.code());
    });
    rows
}

/// Where `page` sits in the grid for `mask` with the window anchored on
/// `cursor`: `(column, body row)` — the body row is relative to
/// [`GRID_TOP_ROW`]. `None` when the page is not enabled (a cursor parked on a
/// page whose data vanished mid-grid simply loses its box until the next move)
/// or when it scrolled off the window.
pub fn grid_cell(mask: u64, page: Page, cursor: Page) -> Option<(usize, usize)> {
    let (index, count) = cursor_index(mask, cursor);
    let origin = window_origin_row(index, count);
    let mut found = None;
    for_each_enabled(mask, |i, p| {
        if p == page {
            found = windowed_row(i, origin).map(|row| (i % GRID_COLS, row));
        }
    });
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::COLS;

    #[test]
    fn open_starts_on_the_current_page() {
        let g = PageGrid::open(Page::Fuel, u64::MAX);
        assert_eq!(g.cursor(), Page::Fuel);
    }

    #[test]
    fn open_moves_off_a_disabled_page() {
        let mask = Page::Dashboard.bit() | Page::Pace.bit() | Page::Nav.bit();
        // Parked on Zones (disabled): the cursor opens on the next enabled
        // page forward in cycle order.
        let g = PageGrid::open(Page::Zones, mask);
        assert_eq!(g.cursor(), Page::Nav, "next enabled page after Zones");
        // Parked past the last enabled page: the walk wraps home.
        let g = PageGrid::open(Page::Roadbook, mask);
        assert_eq!(g.cursor(), Page::Dashboard);
    }

    #[test]
    fn tap_walks_the_filtered_cycle_and_wraps() {
        let mask = Page::Dashboard.bit() | Page::Pace.bit() | Page::Nav.bit();
        let mut g = PageGrid::open(Page::Dashboard, mask);
        g.tap(mask);
        assert_eq!(g.cursor(), Page::Pace);
        g.tap(mask);
        assert_eq!(g.cursor(), Page::Nav);
        g.tap(mask);
        assert_eq!(g.cursor(), Page::Dashboard, "wraps the subset");
    }

    #[test]
    fn row_down_drops_a_full_grid_row() {
        let mut g = PageGrid::open(Page::Dashboard, u64::MAX);
        g.row_down(u64::MAX);
        // Four steps along the full cycle: Dashboard -> Zones.
        assert_eq!(g.cursor(), Page::Zones);
        assert_eq!(
            grid_cell(u64::MAX, g.cursor(), g.cursor()),
            Some((0, 1)),
            "directly below the origin cell"
        );
    }

    #[test]
    fn row_down_wraps_past_the_tail() {
        // BackToStart is the last cell; a row-down from it wraps through the
        // cycle rather than falling off the grid.
        let mut g = PageGrid::open(Page::BackToStart, u64::MAX);
        g.row_down(u64::MAX);
        assert_eq!(g.cursor(), Page::Lap);
    }

    #[test]
    fn full_mask_seats_a_screenful_and_scrolls_to_the_rest() {
        let rows = grid_rows(u64::MAX, Page::Dashboard);
        assert_eq!(rows[0].as_str(), "B2 EXIT         B1 GO");
        // A cursor at the top shows the first GRID_CAPACITY cells, four per
        // body row, none truncated.
        for row in rows.iter().skip(GRID_TOP_ROW) {
            assert!(!row.is_empty());
            assert!(row.len() <= COLS, "grid row too wide: {row:?}");
        }
        assert!(rows[GRID_TOP_ROW]
            .as_str()
            .starts_with("DASH DIST PACE LAP"));
        // The cycle is one page wider than the body: the tail is off-window
        // until the cursor reaches its row, and then the window scrolls to it
        // rather than the cell being silently dropped.
        assert_eq!(
            grid_cell(u64::MAX, Page::BackToStart, Page::Dashboard),
            None
        );
        assert_eq!(
            grid_cell(u64::MAX, Page::BackToStart, Page::BackToStart),
            Some((1, GRID_BODY_ROWS - 1)),
            "the last page seats on the bottom body row once it is the cursor"
        );
        let scrolled = grid_rows(u64::MAX, Page::BackToStart);
        assert!(
            !scrolled[GRID_TOP_ROW].as_str().starts_with("DASH"),
            "the window scrolled off the first row: {:?}",
            scrolled[GRID_TOP_ROW]
        );
        assert_eq!(scrolled[ROWS - 1].as_str(), "AEFF BACK");
        for row in scrolled.iter() {
            assert!(row.len() <= COLS, "scrolled row too wide: {row:?}");
        }
    }

    #[test]
    fn a_cycle_that_fits_never_scrolls() {
        // The whole enabled set inside one screenful is the everyday case
        // (hide-empty is on by default), and it must render identically wherever
        // the cursor sits — the window only engages past GRID_CAPACITY.
        let mut mask = 0u64;
        let mut p = Page::Dashboard;
        for _ in 0..GRID_CAPACITY {
            mask |= p.bit();
            p = p.next();
        }
        let from_top = grid_rows(mask, Page::Dashboard);
        for cursor in [Page::Dashboard, p.prev(), Page::Pace] {
            // Only the body: the name row tracks the cursor by design.
            assert_eq!(
                grid_rows(mask, cursor)[GRID_TOP_ROW..],
                from_top[GRID_TOP_ROW..],
                "{cursor:?} scrolled"
            );
        }
    }

    #[test]
    fn filtered_mask_packs_cells_in_cycle_order() {
        let mask = Page::Dashboard.bit()
            | Page::Pace.bit()
            | Page::Nav.bit()
            | Page::Fuel.bit()
            | Page::BackToStart.bit();
        let rows = grid_rows(mask, Page::Dashboard);
        assert_eq!(rows[GRID_TOP_ROW].as_str(), "DASH PACE NAV  FUEL");
        assert_eq!(rows[GRID_TOP_ROW + 1].as_str(), "BACK");
        for row in rows.iter().skip(GRID_TOP_ROW + 2) {
            assert!(row.is_empty(), "no cells past the enabled set: {row:?}");
        }
        assert_eq!(
            grid_cell(mask, Page::Dashboard, Page::Dashboard),
            Some((0, 0))
        );
        assert_eq!(grid_cell(mask, Page::Fuel, Page::Dashboard), Some((3, 0)));
        assert_eq!(
            grid_cell(mask, Page::BackToStart, Page::Dashboard),
            Some((0, 1))
        );
        assert_eq!(
            grid_cell(mask, Page::Roadbook, Page::Dashboard),
            None,
            "disabled page"
        );
    }

    #[test]
    fn the_legend_names_the_two_buttons_that_leave_the_modal() {
        // BTN2's remap is the one that is not self-revealing: outside the grid
        // it arms the stop, in here it cancels, and the closing grid looks the
        // same either way. BTN3/BTN4 move a visible cursor and commit nothing.
        let legend = grid_rows(u64::MAX, Page::Dashboard)[0].clone();
        assert!(legend.contains("B2"), "no stop-path hint: {legend:?}");
        assert!(
            legend.contains("EXIT"),
            "BTN2's meaning unnamed: {legend:?}"
        );
        assert!(
            legend.contains("B1 GO"),
            "the jump hint was lost: {legend:?}"
        );
        assert_eq!(legend.len(), COLS, "the legend should fill the row exactly");
        // Static: it can never redraw, whatever the cursor or mask.
        for (mask, cursor) in [(u64::MAX, Page::BackToStart), (0, Page::Dashboard)] {
            assert_eq!(grid_rows(mask, cursor)[0], legend);
        }
    }

    #[test]
    fn the_name_row_shows_the_cursor_page_in_full() {
        // The confusable pair the persona review hit: LOAD / ROAD are one edit
        // apart in the cells, so the jump must not commit off the code alone.
        let mask = u64::MAX;
        let load = grid_rows(mask, Page::TrainingLoad)[GRID_NAME_ROW].clone();
        let road = grid_rows(mask, Page::Roadbook)[GRID_NAME_ROW].clone();
        assert_eq!(load.as_str(), "TRAINING LOAD");
        assert_eq!(road.as_str(), "ROADBOOK");
        assert_ne!(load, road);
        // It tracks every move, so what the box sits on is always spelled out.
        let mut g = PageGrid::open(Page::Dashboard, mask);
        assert_eq!(
            grid_rows(mask, g.cursor())[GRID_NAME_ROW].as_str(),
            "DASHBOARD"
        );
        g.tap(mask);
        assert_eq!(
            grid_rows(mask, g.cursor())[GRID_NAME_ROW].as_str(),
            "DISTANCE"
        );
        g.row_down(mask);
        assert_eq!(
            grid_rows(mask, g.cursor())[GRID_NAME_ROW].as_str(),
            g.cursor().name()
        );
    }

    #[test]
    fn the_chrome_rows_never_take_a_cell() {
        // The legend and the name row sit above the body, so no cell can land
        // on them and no cursor box can be drawn over them — whatever the mask
        // and wherever the window scrolled to.
        for cursor in [Page::Dashboard, Page::Roadbook, Page::BackToStart] {
            for mask in [u64::MAX, 0, Page::Dashboard.bit() | Page::Fuel.bit()] {
                let mut p = Page::Dashboard;
                loop {
                    if let Some((_, row)) = grid_cell(mask, p, cursor) {
                        assert!(row < GRID_BODY_ROWS, "{p:?} outside the body");
                    }
                    p = p.next();
                    if p == Page::Dashboard {
                        break;
                    }
                }
                assert_eq!(
                    grid_rows(mask, cursor)[GRID_NAME_ROW].as_str(),
                    cursor.name()
                );
            }
        }
    }

    #[test]
    fn the_rows_are_a_pure_function_of_mask_and_cursor() {
        // A resting grid must flush zero SPI: the ui task redraws these rows
        // every frame and the framebuffer only dirties lines that changed, so
        // nothing here may vary on anything but an input.
        for cursor in [Page::Dashboard, Page::Fuel, Page::BackToStart] {
            let first = grid_rows(u64::MAX, cursor);
            for _ in 0..3 {
                assert_eq!(grid_rows(u64::MAX, cursor), first, "{cursor:?} redrew");
            }
        }
    }

    #[test]
    fn every_row_fits_the_grid_at_full_mask() {
        for row in grid_rows(u64::MAX, Page::Dashboard).iter() {
            assert!(row.len() <= COLS, "row overflows: {row:?}");
        }
    }

    #[test]
    fn dashboard_is_always_seated() {
        let rows = grid_rows(0, Page::Dashboard);
        assert_eq!(rows[GRID_TOP_ROW].as_str(), "DASH");
        assert_eq!(grid_cell(0, Page::Dashboard, Page::Dashboard), Some((0, 0)));
    }

    #[test]
    fn empty_mask_pins_the_cursor_to_dashboard() {
        // An empty mask leaves only the forced Dashboard: open lands there
        // and every move is a stationary wrap, never a walk off the grid.
        let mut g = PageGrid::open(Page::Fuel, 0);
        assert_eq!(g.cursor(), Page::Dashboard);
        g.tap(0);
        assert_eq!(g.cursor(), Page::Dashboard);
        g.row_down(0);
        assert_eq!(g.cursor(), Page::Dashboard);
    }

    #[test]
    fn a_mask_shrink_under_an_open_grid_recovers_on_the_next_move() {
        // The button task re-samples pages_mask on every press, so a page's
        // data can vanish while its cell is the cursor: the box disappears
        // (grid_cell None) and the next move walks onto an enabled page.
        let wide = Page::Dashboard.bit() | Page::Pace.bit() | Page::Nav.bit();
        let mut g = PageGrid::open(Page::Nav, wide);
        assert_eq!(g.cursor(), Page::Nav);
        let shrunk = Page::Dashboard.bit() | Page::Pace.bit();
        assert_eq!(grid_cell(shrunk, g.cursor(), g.cursor()), None);
        g.tap(shrunk);
        assert_eq!(g.cursor(), Page::Dashboard);
    }

    #[test]
    fn back_and_row_up_are_the_exact_inverses_of_tap_and_row_down() {
        let mask = Page::Dashboard.bit()
            | Page::Pace.bit()
            | Page::Nav.bit()
            | Page::Fuel.bit()
            | Page::BackToStart.bit();
        let mut g = PageGrid::open(Page::Dashboard, mask);
        g.tap(mask);
        g.back(mask);
        assert_eq!(g.cursor(), Page::Dashboard);
        g.row_down(mask);
        g.row_up(mask);
        assert_eq!(g.cursor(), Page::Dashboard);
        // Backward wraps to the tail — the last page is one back-tap away,
        // mirroring the cycle's own reverse walk.
        g.back(mask);
        assert_eq!(g.cursor(), Page::BackToStart);
        let mut full = PageGrid::open(Page::Dashboard, u64::MAX);
        full.row_up(u64::MAX);
        assert_eq!(
            grid_cell(u64::MAX, full.cursor(), full.cursor()),
            Some((2, GRID_BODY_ROWS - 1)),
            "one row up from home wraps into the grid's tail"
        );
    }

    #[test]
    fn row_down_wraps_a_cycle_narrower_than_the_grid() {
        // Two enabled pages: the four-step row-down laps the cycle twice and
        // lands back where it started, rather than walking off the end.
        let mask = Page::Dashboard.bit() | Page::Pace.bit();
        let mut g = PageGrid::open(Page::Dashboard, mask);
        g.row_down(mask);
        assert_eq!(g.cursor(), Page::Dashboard);
        g.tap(mask);
        g.row_down(mask);
        assert_eq!(g.cursor(), Page::Pace);
    }
}
