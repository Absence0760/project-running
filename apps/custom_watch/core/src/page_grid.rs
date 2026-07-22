//! The page-grid overview — the run view's navigation map.
//!
//! The BTN3 cycle is a linear walk; fine for the handful of near pages, but a
//! late page in a wide mask is many blind presses out, and nothing on screen
//! says what pages even exist. The grid is the fix: hold BTN3 (past the
//! page-back long-press) and every enabled page appears at once as a grid of
//! four-glyph codes in cycle order, with a cursor box on the current page.
//! Tap BTN3 to step the cursor, hold to drop a whole row, BTN4 to jump —
//! or just stop pressing: after [`GRID_AUTOSELECT_S`] with no input the grid
//! jumps to the cursor on its own, so the entire flow needs one finger and no
//! confirm press. BTN1 / BTN2 close the grid and are swallowed — a press
//! inside a navigation modal must never pause or stop the recording.
//!
//! Pure state + layout, like the rest of `core`: the app's button task owns
//! the press timing and the deadline timer, the ui task draws the rows this
//! module lays out (`grid_rows`) plus the cursor box (`grid_cell` → pixels in
//! `watch_render::widgets`). Everything here is host-tested.

use core::fmt::Write;

use crate::face::{Row, ROWS};
use crate::page::Page;

/// Cells per grid row. Four five-cell columns (a four-glyph code + one gap)
/// span 20 of the 21 text columns, and four columns times the
/// [`GRID_BODY_ROWS`] body rows seat all 32 pages exactly.
pub const GRID_COLS: usize = 4;

/// First text row of the grid body; row 0 is the title + BTN4 hint.
pub const GRID_TOP_ROW: usize = 1;

/// Body rows available to cells.
pub const GRID_BODY_ROWS: usize = ROWS - GRID_TOP_ROW;

// Every page must seat even under the full mask — a 33rd page needs a layout
// change here, not a silent truncation.
const _: () = assert!(GRID_COLS * GRID_BODY_ROWS >= 32);

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
    pub fn open(current: Page, mask: u32) -> Self {
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
    pub fn tap(&mut self, mask: u32) {
        self.cursor = self.cursor.next_in(mask);
    }

    /// A BTN3 hold: cursor one grid row down — [`GRID_COLS`] steps along the
    /// enabled cycle, so it lands directly below (and wraps like a tap past
    /// the tail). The long-jump that makes the grid faster than the walk.
    pub fn row_down(&mut self, mask: u32) {
        for _ in 0..GRID_COLS {
            self.cursor = self.cursor.next_in(mask);
        }
    }

    /// A BTN1 tap: cursor one cell back — [`Self::tap`]'s exact inverse.
    /// Forward-only movement made the cells just behind the cursor the most
    /// expensive on the whole grid (a near-full lap); the symmetric grammar
    /// (BTN3 forward, BTN1 back, hold = a row either way) caps any cell under
    /// the full mask at six actions.
    pub fn back(&mut self, mask: u32) {
        self.cursor = self.cursor.prev_in(mask);
    }

    /// A BTN1 hold: cursor one grid row up — [`Self::row_down`]'s inverse.
    pub fn row_up(&mut self, mask: u32) {
        for _ in 0..GRID_COLS {
            self.cursor = self.cursor.prev_in(mask);
        }
    }
}

fn enabled(page: Page, mask: u32) -> bool {
    page.bit() & (mask | Page::Dashboard.bit()) != 0
}

/// Visit the enabled pages in cycle order (Dashboard first — it is always
/// enabled and the cycle's anchor).
fn for_each_enabled(mask: u32, mut f: impl FnMut(usize, Page)) {
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

/// The grid's text rows: the title row, then the enabled pages' codes in
/// cycle order, [`GRID_COLS`] per row. The ui task draws these exactly like
/// face rows; the cursor box is pixel work ([`grid_cell`] + the widget).
pub fn grid_rows(mask: u32) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    let _ = write!(rows[0], "{:<16}B4 GO", "PAGES");
    for_each_enabled(mask, |i, p| {
        let row = GRID_TOP_ROW + i / GRID_COLS;
        if row >= ROWS {
            return;
        }
        let col_start = (i % GRID_COLS) * GRID_CELL_CHARS;
        while rows[row].len() < col_start {
            let _ = rows[row].push(' ');
        }
        let _ = rows[row].push_str(p.code());
    });
    rows
}

/// Where `page` sits in the grid for `mask`: `(column, body row)` — the body
/// row is relative to [`GRID_TOP_ROW`]. `None` when the page is not enabled
/// (a cursor parked on a page whose data vanished mid-grid simply loses its
/// box until the next move).
pub fn grid_cell(mask: u32, page: Page) -> Option<(usize, usize)> {
    let mut found = None;
    for_each_enabled(mask, |i, p| {
        if p == page {
            found = Some((i % GRID_COLS, i / GRID_COLS));
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
        let g = PageGrid::open(Page::Fuel, u32::MAX);
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
        let mut g = PageGrid::open(Page::Dashboard, u32::MAX);
        g.row_down(u32::MAX);
        // Four steps along the full cycle: Dashboard -> Zones.
        assert_eq!(g.cursor(), Page::Zones);
        assert_eq!(
            grid_cell(u32::MAX, g.cursor()),
            Some((0, 1)),
            "directly below the origin cell"
        );
    }

    #[test]
    fn row_down_wraps_past_the_tail() {
        // BackToStart is the last cell; a row-down from it wraps through the
        // cycle rather than falling off the grid.
        let mut g = PageGrid::open(Page::BackToStart, u32::MAX);
        g.row_down(u32::MAX);
        assert_eq!(g.cursor(), Page::Lap);
    }

    #[test]
    fn full_mask_seats_all_pages_in_the_body_rows() {
        let rows = grid_rows(u32::MAX);
        assert_eq!(rows[0].as_str(), "PAGES           B4 GO");
        // 32 pages / 4 per row = exactly the 8 body rows, none truncated.
        for row in rows.iter().skip(GRID_TOP_ROW) {
            assert!(!row.is_empty());
            assert!(row.len() <= COLS, "grid row too wide: {row:?}");
        }
        assert!(rows[GRID_TOP_ROW].as_str().starts_with("DASH DIST PACE LAP"));
        assert_eq!(
            grid_cell(u32::MAX, Page::BackToStart),
            Some((3, 7)),
            "the 32nd page fills the last cell"
        );
    }

    #[test]
    fn filtered_mask_packs_cells_in_cycle_order() {
        let mask = Page::Dashboard.bit()
            | Page::Pace.bit()
            | Page::Nav.bit()
            | Page::Fuel.bit()
            | Page::BackToStart.bit();
        let rows = grid_rows(mask);
        assert_eq!(rows[1].as_str(), "DASH PACE NAV  FUEL");
        assert_eq!(rows[2].as_str(), "BACK");
        for row in rows.iter().skip(3) {
            assert!(row.is_empty(), "no cells past the enabled set: {row:?}");
        }
        assert_eq!(grid_cell(mask, Page::Dashboard), Some((0, 0)));
        assert_eq!(grid_cell(mask, Page::Fuel), Some((3, 0)));
        assert_eq!(grid_cell(mask, Page::BackToStart), Some((0, 1)));
        assert_eq!(grid_cell(mask, Page::Roadbook), None, "disabled page");
    }

    #[test]
    fn every_row_fits_the_grid_at_full_mask() {
        for row in grid_rows(u32::MAX).iter() {
            assert!(row.len() <= COLS, "row overflows: {row:?}");
        }
    }

    #[test]
    fn dashboard_is_always_seated() {
        let rows = grid_rows(0);
        assert_eq!(rows[GRID_TOP_ROW].as_str(), "DASH");
        assert_eq!(grid_cell(0, Page::Dashboard), Some((0, 0)));
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
        assert_eq!(grid_cell(shrunk, g.cursor()), None);
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
        let mut full = PageGrid::open(Page::Dashboard, u32::MAX);
        full.row_up(u32::MAX);
        assert_eq!(
            grid_cell(u32::MAX, full.cursor()),
            Some((0, 7)),
            "one row up from home wraps to the last row"
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
