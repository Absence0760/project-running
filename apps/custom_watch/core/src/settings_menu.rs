//! The idle-face settings menu — the on-watch home for every setting a runner
//! can change without a phone (decisions §351).
//!
//! Opened by a BTN5 tap on the idle face (the lap key is dead while idle, so
//! the press gets the obvious meaning — the same dead-key repurposing as §290
//! and §291). It is a modal like [`crate::page_grid`], and deliberately speaks
//! the grid's exact dialect so nothing new has to be learned: BTN4/BTN3 move
//! the cursor down/up, BTN1 activates (`B1 GO`), BTN2 exits (`B2 EXIT`), and
//! the legend row is byte-identical to the grid's (pinned by a test). Every
//! press inside it is swallowed — a menu press must never start, pause, or lap
//! a run, and the menu only exists while the recorder is idle.
//!
//! The quick paths stay: idle BTN3 still cycles the GNSS mode blind and its
//! hold still fires the QNH re-zero — the menu is the discoverable,
//! read-the-value-first route to the same state, not a replacement press tax.
//! Item activation is one press: an enum setting cycles in place, an action
//! item fires and closes. Nothing here adds a press to any pre-§351 flow.

use core::fmt::Write;

use crate::face::{Row, ROWS};
use crate::gnss_mode::GnssMode;

/// Seconds of inactivity before an open menu closes itself back to the home
/// face. Unlike the grid's 3 s auto-select (mid-run, urgency), the menu is an
/// idle surface — but it covers the clock, and "the home face always tells
/// the time" is a navigation invariant, so an abandoned menu may not stand
/// forever. Long enough to read every row twice; the timer exists only while
/// the menu is open, so it adds no standing wake (§328).
pub const MENU_TIMEOUT_S: u32 = 30;

/// The menu's items, in cursor order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum MenuItem {
    /// Performance / Balanced / Expedition — the same cycle idle BTN3 taps
    /// through, with the projected hours readable before committing.
    GnssMode,
    /// The §284 hide-empty-pages filter, watch-editable: the one curation
    /// lever that makes sense on the wrist (the full per-page mask stays a
    /// phone surface — 33 checkboxes do not belong on four buttons).
    HideEmpty,
    /// Fires the same request as the idle BTN3 hold and closes the menu; the
    /// idle face's transient banner (`SET 1610M` / `NO GPS FIX` / `NO BARO`)
    /// answers, exactly as it answers the hold.
    QnhRezero,
}

pub const MENU_ITEMS: usize = 3;

const ITEMS: [MenuItem; MENU_ITEMS] =
    [MenuItem::GnssMode, MenuItem::HideEmpty, MenuItem::QnhRezero];

/// The open menu: a cursor over [`ITEMS`]. The button task owns it (like the
/// grid state machine); the ui task renders the published cursor.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Menu {
    cursor: u8,
}

impl Menu {
    pub const fn new() -> Self {
        Self { cursor: 0 }
    }

    pub fn cursor(&self) -> u8 {
        self.cursor
    }

    pub fn item(&self) -> MenuItem {
        ITEMS[self.cursor as usize]
    }

    /// Cursor down (BTN4 — the same key that pages right), wrapping.
    pub fn next(&mut self) {
        self.cursor = (self.cursor + 1) % MENU_ITEMS as u8;
    }

    /// Cursor up (BTN3 — the same key that pages left), wrapping.
    pub fn prev(&mut self) {
        self.cursor = (self.cursor + MENU_ITEMS as u8 - 1) % MENU_ITEMS as u8;
    }
}

impl Default for Menu {
    fn default() -> Self {
        Self::new()
    }
}

/// What activating (BTN1) the cursor item does. The menu itself owns no
/// state beyond the cursor — the actions land on the same sinks the quick
/// paths use, so the two routes cannot diverge.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum MenuAction {
    CycleGnssMode,
    ToggleHideEmpty,
    RequestQnhRezero,
}

pub fn activate(item: MenuItem) -> MenuAction {
    match item {
        MenuItem::GnssMode => MenuAction::CycleGnssMode,
        MenuItem::HideEmpty => MenuAction::ToggleHideEmpty,
        MenuItem::QnhRezero => MenuAction::RequestQnhRezero,
    }
}

/// Whether activating this item closes the menu. Value items stay open — the
/// row re-renders with the new value, which is the confirmation; the action
/// item hands the screen to the idle face, whose banner is its answer.
pub fn closes_menu(item: MenuItem) -> bool {
    matches!(item, MenuItem::QnhRezero)
}

/// The menu's text rows: the grid's legend verbatim, a title, then one row
/// per item with the cursor marked `>` and the current value inline — a
/// setting is read before it is changed, the same read-before-commit rule as
/// the grid's name row (§337).
pub fn menu_rows(cursor: u8, mode: GnssMode, hide_empty: bool) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    let _ = write!(rows[0], "{:<16}B1 GO", "B2 EXIT");
    let _ = rows[1].push_str("SETTINGS");
    for (i, item) in ITEMS.iter().enumerate() {
        let row = MENU_TOP_ROW + i;
        let marker = if cursor as usize == i { '>' } else { ' ' };
        let _ = rows[row].push(marker);
        let _ = rows[row].push(' ');
        match item {
            MenuItem::GnssMode => {
                let _ = write!(
                    rows[row],
                    "GNSS MODE {:<4} {}H",
                    mode.label(),
                    mode.battery_est_h()
                );
            }
            MenuItem::HideEmpty => {
                let _ = write!(
                    rows[row],
                    "HIDE EMPTY {}",
                    if hide_empty { "ON" } else { "OFF" }
                );
            }
            MenuItem::QnhRezero => {
                let _ = rows[row].push_str("RE-ZERO ALTITUDE");
            }
        }
    }
    rows
}

/// First row of the item list — row 2 stays blank so the title band reads as
/// chrome, mirroring the grid's two chrome rows over a body.
const MENU_TOP_ROW: usize = 3;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::COLS;
    use crate::page::Page;
    use crate::page_grid::grid_rows;

    #[test]
    fn the_legend_is_byte_identical_to_the_grids() {
        // One dialect for every modal on the device: B2 EXIT, B1 GO. A menu
        // that relabels the exit or the confirm is a new grammar to learn.
        let menu = menu_rows(0, GnssMode::Performance, true);
        let grid = grid_rows(u64::MAX, Page::Dashboard);
        assert_eq!(menu[0], grid[0]);
    }

    #[test]
    fn the_cursor_wraps_both_ways() {
        let mut m = Menu::new();
        assert_eq!(m.item(), MenuItem::GnssMode);
        m.next();
        assert_eq!(m.item(), MenuItem::HideEmpty);
        m.next();
        assert_eq!(m.item(), MenuItem::QnhRezero);
        m.next();
        assert_eq!(m.item(), MenuItem::GnssMode);
        m.prev();
        assert_eq!(m.item(), MenuItem::QnhRezero);
    }

    #[test]
    fn activation_maps_each_item_to_its_action() {
        assert_eq!(activate(MenuItem::GnssMode), MenuAction::CycleGnssMode);
        assert_eq!(activate(MenuItem::HideEmpty), MenuAction::ToggleHideEmpty);
        assert_eq!(activate(MenuItem::QnhRezero), MenuAction::RequestQnhRezero);
        // Value items stay open (the row re-rendering is the confirmation);
        // only the action item hands the screen back.
        assert!(!closes_menu(MenuItem::GnssMode));
        assert!(!closes_menu(MenuItem::HideEmpty));
        assert!(closes_menu(MenuItem::QnhRezero));
    }

    #[test]
    fn every_row_fits_the_face_for_every_mode_and_value() {
        for mode in [
            GnssMode::Performance,
            GnssMode::Balanced,
            GnssMode::Expedition,
        ] {
            for hide in [true, false] {
                for cursor in 0..MENU_ITEMS as u8 {
                    let rows = menu_rows(cursor, mode, hide);
                    for row in rows.iter() {
                        assert!(row.len() <= COLS, "row too wide: {row:?}");
                    }
                    // The cursor marks exactly one row.
                    let marked = rows.iter().filter(|r| r.starts_with('>')).count();
                    assert_eq!(marked, 1);
                }
            }
        }
    }

    #[test]
    fn the_value_rows_read_the_current_state() {
        let rows = menu_rows(0, GnssMode::Performance, true);
        assert_eq!(rows[0].as_str(), "B2 EXIT         B1 GO");
        assert_eq!(rows[1].as_str(), "SETTINGS");
        assert_eq!(rows[3].as_str(), "> GNSS MODE PERF 110H");
        assert_eq!(rows[4].as_str(), "  HIDE EMPTY ON");
        assert_eq!(rows[5].as_str(), "  RE-ZERO ALTITUDE");
        let rows = menu_rows(1, GnssMode::Expedition, false);
        assert_eq!(rows[3].as_str(), "  GNSS MODE EXP  220H");
        assert_eq!(rows[4].as_str(), "> HIDE EMPTY OFF");
    }

    #[test]
    fn the_timeout_is_long_enough_to_read_but_never_standing() {
        // The menu hides the home clock, so it must close itself; but the
        // timer may only exist while the menu is open (§328's no-standing-wake
        // rule) — MENU_TIMEOUT_S is a deadline the button task arms per press,
        // not a periodic tick.
        assert!(MENU_TIMEOUT_S >= 15);
        assert!(MENU_TIMEOUT_S <= 60);
    }
}
