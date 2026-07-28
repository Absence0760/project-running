//! The idle-face settings menu — the on-watch home for every setting a runner
//! can change without a phone (decisions §351, key map revised same-day).
//!
//! Opened by a BTN5 tap on the idle face (the lap key is dead while idle, so
//! the press gets the obvious meaning — the same dead-key repurposing as §290
//! and §291). Inside, every key is spatially true to the case:
//!
//! - **BTN2 / BTN3** (mid-left / lower-left — the §81 slots Garmin literally
//!   names UP and DOWN, stacked vertically on the case) move the cursor up
//!   and down the list.
//! - **BTN5 / BTN1** (the upper-left / upper-right corners — a horizontal
//!   pair) edit the selected row: left = off / decrease, right = on /
//!   increase, and right also fires an action row. Directional, not a blind
//!   toggle: pressing the side that matches the value you want is idempotent,
//!   so a double-press can never overshoot.
//! - **BTN4** (lower-right — the §81 BACK/LAP slot) exits, exactly where
//!   every five-button watch puts BACK.
//!
//! This deliberately diverges from the page grid's key map (BTN3/BTN4 cursor,
//! B1 GO, B2 EXIT): the grid's cursor walks the *horizontal* page ring, so
//! its keys are the paging pair; a settings list is *vertical* with a value
//! axis across each row, so its keys are the vertical pair plus the
//! horizontal pair. Each modal is spatially true to what it shows. The one
//! §337-class surprise — EXIT living on BTN4 here but BTN2 in the grid — is
//! why the legend row names `B4 EXIT` (and the novel edit pair), while the
//! self-revealing cursor keys stay unlabelled.
//!
//! The quick paths stay: idle BTN3 still cycles the GNSS mode blind and its
//! hold still fires the QNH re-zero — the menu is the discoverable,
//! read-the-value-first route to the same state, not a replacement press tax.

use core::fmt::Write;

use crate::face::{Row, ROWS};
use crate::gnss_mode::GnssMode;
use crate::profiles::ActivityProfile;

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
    /// The Performance ↔ Balanced ↔ Expedition ladder, edited directionally:
    /// right = more projected hours, left = more fixes, clamped at the ends
    /// (the idle BTN3 quick path keeps its wrap-around cycle).
    GnssMode,
    /// The §284 hide-empty-pages filter, watch-editable: right = ON, left =
    /// OFF. The one curation lever that makes sense on the wrist (the full
    /// per-page mask stays a phone surface — 34 checkboxes do not belong on
    /// five buttons).
    HideEmpty,
    /// The activity-profile ladder (Run → Trail → Ultra → Hike), edited
    /// directionally like the mode ladder: right toward the longer / more-
    /// battery activities, clamped at the ends. Selecting a rung APPLIES its
    /// preset ([`crate::profiles::preset`]) — a macro over the pages mask +
    /// GNSS mode, per §353 — and the row shows the last-applied profile
    /// (`--` until one is ever chosen).
    Profile,
    /// An action row: right (BTN1) fires the same request as the idle BTN3
    /// hold and closes the menu; the idle face's transient banner
    /// (`SET 1610M` / `NO GPS FIX` / `NO BARO`) answers, exactly as it
    /// answers the hold. Left does nothing — an action has no "off".
    QnhRezero,
}

pub const MENU_ITEMS: usize = 4;

const ITEMS: [MenuItem; MENU_ITEMS] = [
    MenuItem::GnssMode,
    MenuItem::HideEmpty,
    MenuItem::Profile,
    MenuItem::QnhRezero,
];

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

    /// Cursor down (BTN3 — the lower-left DOWN slot), wrapping.
    pub fn down(&mut self) {
        self.cursor = (self.cursor + 1) % MENU_ITEMS as u8;
    }

    /// Cursor up (BTN2 — the mid-left UP slot), wrapping.
    pub fn up(&mut self) {
        self.cursor = (self.cursor + MENU_ITEMS as u8 - 1) % MENU_ITEMS as u8;
    }
}

impl Default for Menu {
    fn default() -> Self {
        Self::new()
    }
}

/// Which side of the horizontal edit pair was pressed: BTN5 = `Left`
/// (off / decrease), BTN1 = `Right` (on / increase / fire).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ValueDir {
    Left,
    Right,
}

/// What an edit press asks for — computed against the *current* values, so
/// the task applies exactly the state change the runner saw, or nothing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum MenuEdit {
    /// Move the GNSS mode one rung along the ladder (already clamped —
    /// never equal to the current mode).
    SetGnssMode(GnssMode),
    /// Set the hide-empty filter (already different from the current value).
    SetHideEmpty(bool),
    /// Apply an activity profile's preset (already different from the current
    /// selection — the ladder never re-applies the rung it is on).
    SetProfile(ActivityProfile),
    /// Fire the QNH re-zero and close the menu.
    RequestQnhRezero,
    /// The press asked for the state it is already in (a clamped ladder end,
    /// an idempotent on/on) or has no meaning (left on an action row).
    Nothing,
}

/// One rung right on the mode ladder — toward more projected hours; clamped.
fn mode_right(mode: GnssMode) -> GnssMode {
    match mode {
        GnssMode::Performance => GnssMode::Balanced,
        GnssMode::Balanced | GnssMode::Expedition => GnssMode::Expedition,
    }
}

/// One rung left — toward more fixes; clamped.
fn mode_left(mode: GnssMode) -> GnssMode {
    match mode {
        GnssMode::Expedition => GnssMode::Balanced,
        GnssMode::Balanced | GnssMode::Performance => GnssMode::Performance,
    }
}

/// Resolve an edit press on `item` against the current values. Pure and
/// host-tested; both task variants dispatch on the result. `profile` is the
/// last-applied activity profile, `None` until one is ever chosen — a right
/// press then starts the ladder at its first rung.
pub fn edit(
    item: MenuItem,
    dir: ValueDir,
    mode: GnssMode,
    hide_empty: bool,
    profile: Option<ActivityProfile>,
) -> MenuEdit {
    match (item, dir) {
        (MenuItem::GnssMode, ValueDir::Right) => {
            let next = mode_right(mode);
            if next == mode {
                MenuEdit::Nothing
            } else {
                MenuEdit::SetGnssMode(next)
            }
        }
        (MenuItem::GnssMode, ValueDir::Left) => {
            let next = mode_left(mode);
            if next == mode {
                MenuEdit::Nothing
            } else {
                MenuEdit::SetGnssMode(next)
            }
        }
        (MenuItem::HideEmpty, ValueDir::Right) => {
            if hide_empty {
                MenuEdit::Nothing
            } else {
                MenuEdit::SetHideEmpty(true)
            }
        }
        (MenuItem::HideEmpty, ValueDir::Left) => {
            if hide_empty {
                MenuEdit::SetHideEmpty(false)
            } else {
                MenuEdit::Nothing
            }
        }
        (MenuItem::Profile, ValueDir::Right) => match profile {
            // First-ever selection starts the ladder at its first rung.
            None => MenuEdit::SetProfile(ActivityProfile::Run),
            Some(p) => {
                let next = p.right();
                if next == p {
                    MenuEdit::Nothing
                } else {
                    MenuEdit::SetProfile(next)
                }
            }
        },
        (MenuItem::Profile, ValueDir::Left) => match profile {
            // No selection to step back from — and "left of the ladder" must
            // not surprise-apply a preset.
            None => MenuEdit::Nothing,
            Some(p) => {
                let next = p.left();
                if next == p {
                    MenuEdit::Nothing
                } else {
                    MenuEdit::SetProfile(next)
                }
            }
        },
        (MenuItem::QnhRezero, ValueDir::Right) => MenuEdit::RequestQnhRezero,
        (MenuItem::QnhRezero, ValueDir::Left) => MenuEdit::Nothing,
    }
}

/// The menu's text rows: a legend naming what §337 says must be named — the
/// exit (which lives on BTN4 here, not the grid's BTN2) and the novel
/// horizontal edit pair — then a title, then one row per item with the
/// cursor marked `>` and the current value inline: a setting is read before
/// it is changed. The cursor keys go unlabelled, exactly like the grid's:
/// they move something visible and commit nothing, so they are discovered
/// for free.
pub fn menu_rows(
    cursor: u8,
    mode: GnssMode,
    hide_empty: bool,
    profile: Option<ActivityProfile>,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    let _ = write!(rows[0], "{:<14}B4 EXIT", "B5- B1+");
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
            MenuItem::Profile => {
                let _ = write!(
                    rows[row],
                    "PROFILE {}",
                    profile.map_or("--", ActivityProfile::label)
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

    #[test]
    fn the_legend_names_the_exit_and_the_edit_pair() {
        // §337: name what leaves the modal and what is not self-revealing.
        // EXIT lives on BTN4 here (the grid trained BTN2), so it MUST be
        // read, not discovered; the horizontal edit pair is the novel
        // gesture. The cursor keys move a visible marker and stay unlabelled.
        let rows = menu_rows(0, GnssMode::Performance, true, None);
        assert_eq!(rows[0].as_str(), "B5- B1+       B4 EXIT");
        assert_eq!(rows[0].len(), COLS, "the legend should fill the row");
    }

    #[test]
    fn the_cursor_wraps_both_ways() {
        let mut m = Menu::new();
        assert_eq!(m.item(), MenuItem::GnssMode);
        m.down();
        assert_eq!(m.item(), MenuItem::HideEmpty);
        m.down();
        assert_eq!(m.item(), MenuItem::Profile);
        m.down();
        assert_eq!(m.item(), MenuItem::QnhRezero);
        m.down();
        assert_eq!(m.item(), MenuItem::GnssMode);
        m.up();
        assert_eq!(m.item(), MenuItem::QnhRezero);
    }

    #[test]
    fn the_mode_ladder_clamps_at_both_ends() {
        use GnssMode::*;
        // Right walks toward Expedition (more hours) and stops there —
        // "increase" semantics never wrap, or a press past the end would
        // teleport to the opposite extreme.
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Right, Performance, true, None),
            MenuEdit::SetGnssMode(Balanced)
        );
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Right, Balanced, true, None),
            MenuEdit::SetGnssMode(Expedition)
        );
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Right, Expedition, true, None),
            MenuEdit::Nothing
        );
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Left, Expedition, true, None),
            MenuEdit::SetGnssMode(Balanced)
        );
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Left, Balanced, true, None),
            MenuEdit::SetGnssMode(Performance)
        );
        assert_eq!(
            edit(MenuItem::GnssMode, ValueDir::Left, Performance, true, None),
            MenuEdit::Nothing
        );
    }

    #[test]
    fn hide_empty_is_directional_and_idempotent() {
        // Right = ON, left = OFF — pressing the side that matches the value
        // you want can never overshoot into the other state.
        assert_eq!(
            edit(
                MenuItem::HideEmpty,
                ValueDir::Right,
                GnssMode::Performance,
                false,
                None
            ),
            MenuEdit::SetHideEmpty(true)
        );
        assert_eq!(
            edit(
                MenuItem::HideEmpty,
                ValueDir::Right,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::Nothing
        );
        assert_eq!(
            edit(
                MenuItem::HideEmpty,
                ValueDir::Left,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::SetHideEmpty(false)
        );
        assert_eq!(
            edit(
                MenuItem::HideEmpty,
                ValueDir::Left,
                GnssMode::Performance,
                false,
                None
            ),
            MenuEdit::Nothing
        );
    }

    #[test]
    fn the_action_row_fires_on_right_only() {
        // Right is GO everywhere on this device; an action has no "off", so
        // left is inert rather than a second trigger a fumbling hand hits.
        assert_eq!(
            edit(
                MenuItem::QnhRezero,
                ValueDir::Right,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::RequestQnhRezero
        );
        assert_eq!(
            edit(
                MenuItem::QnhRezero,
                ValueDir::Left,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::Nothing
        );
    }

    #[test]
    fn every_row_fits_the_face_for_every_mode_and_value() {
        for mode in [
            GnssMode::Performance,
            GnssMode::Balanced,
            GnssMode::Expedition,
        ] {
            for hide in [true, false] {
                for profile in [
                    None,
                    Some(ActivityProfile::Run),
                    Some(ActivityProfile::Trail),
                    Some(ActivityProfile::Ultra),
                    Some(ActivityProfile::Hike),
                ] {
                    for cursor in 0..MENU_ITEMS as u8 {
                        let rows = menu_rows(cursor, mode, hide, profile);
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
    }

    #[test]
    fn the_value_rows_read_the_current_state() {
        let rows = menu_rows(0, GnssMode::Performance, true, None);
        assert_eq!(rows[1].as_str(), "SETTINGS");
        assert_eq!(rows[3].as_str(), "> GNSS MODE PERF 110H");
        assert_eq!(rows[4].as_str(), "  HIDE EMPTY ON");
        assert_eq!(rows[5].as_str(), "  PROFILE --");
        assert_eq!(rows[6].as_str(), "  RE-ZERO ALTITUDE");
        let rows = menu_rows(1, GnssMode::Expedition, false, Some(ActivityProfile::Ultra));
        assert_eq!(rows[3].as_str(), "  GNSS MODE EXP  220H");
        assert_eq!(rows[4].as_str(), "> HIDE EMPTY OFF");
        assert_eq!(rows[5].as_str(), "  PROFILE ULTRA");
    }

    #[test]
    fn the_profile_ladder_clamps_and_an_unset_row_only_starts_on_right() {
        use ActivityProfile::*;
        let e = |dir, p| edit(MenuItem::Profile, dir, GnssMode::Performance, true, p);
        // First-ever selection starts the ladder; left of nothing applies
        // nothing — "left of the ladder" must not surprise-apply a preset.
        assert_eq!(e(ValueDir::Right, None), MenuEdit::SetProfile(Run));
        assert_eq!(e(ValueDir::Left, None), MenuEdit::Nothing);
        // The ladder walks rightward toward the longer activities and clamps.
        assert_eq!(e(ValueDir::Right, Some(Run)), MenuEdit::SetProfile(Trail));
        assert_eq!(e(ValueDir::Right, Some(Trail)), MenuEdit::SetProfile(Ultra));
        assert_eq!(e(ValueDir::Right, Some(Ultra)), MenuEdit::SetProfile(Hike));
        assert_eq!(e(ValueDir::Right, Some(Hike)), MenuEdit::Nothing);
        assert_eq!(e(ValueDir::Left, Some(Hike)), MenuEdit::SetProfile(Ultra));
        assert_eq!(e(ValueDir::Left, Some(Run)), MenuEdit::Nothing);
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
