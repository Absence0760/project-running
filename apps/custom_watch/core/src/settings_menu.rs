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

use crate::erase::{erase_stake_row, ERASE_LEGEND_ARMED, ERASE_ROW, ERASE_ROW_ARMED};
use crate::face::{Row, ROWS};
use crate::gnss_mode::GnssMode;
use crate::pairing::{pair_open_row, PAIR_LEGEND_ARMED, PAIR_ROW, PAIR_ROW_ARMED};
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
    /// per-page mask stays a phone surface — one checkbox per page does not
    /// belong on five buttons).
    HideEmpty,
    /// The activity-profile ladder (Run → Trail → Ultra → Hike), edited
    /// directionally like the mode ladder: right toward the longer / more-
    /// battery activities, clamped at the ends. Selecting a rung APPLIES its
    /// preset ([`crate::profiles::preset`]) — a macro over the pages mask +
    /// GNSS mode, per §353 — and the row shows the last-applied profile
    /// (`--` until one is ever chosen).
    Profile,
    /// Backyard-ultra mode (§372), edited directionally like the hide-empty
    /// toggle: right = ON, left = OFF. It lives on the watch rather than on a
    /// phone push because a runner arms it at a start line in a field, and
    /// idle-only because arming it re-points the auto-lap onto the corral
    /// bell — a run has to be wholly inside the mode or wholly outside it.
    Backyard,
    /// The BLE re-pair window (§432) — the wearer's way to hand a bonded
    /// watch to a NEW phone without the FACTORY ERASE below it. Guarded like
    /// the erase: right (BTN1) *arms* [`crate::pairing::PairGuard`] and only
    /// a second right inside its window opens the 90 s pairing window; left
    /// closes an open window early (the directional "off", unguarded —
    /// closing a security door needs no ceremony). Seated at index 4, the
    /// 8-ring's one true far seat: the eighth row's only zero-tax placement
    /// (§378's arithmetic, one ring wider), and the hardest row for a
    /// fumbling hand to land on — which a row that opens the bond gate
    /// should be.
    PairPhone,
    /// The factory erase (§378) — the wearer's own way to sanitise a watch they
    /// are about to lose, sell, or hand on, with no phone in reach. An action
    /// row like the two below it, but guarded: right (BTN1) *arms*
    /// [`crate::erase::EraseGuard`] and only a second right inside its window
    /// wipes. Went in at the 7-ring's second far point for two reasons that
    /// agree — it is the row a fumbling hand should be least likely to land on,
    /// and index 4 was one of the only two seats a seventh row could take
    /// without raising any existing row's cursor cost (§378). §432's PairPhone
    /// took that seat on the 8-ring; this row slid to index 5 at its exact old
    /// cost of 3 steps.
    Erase,
    /// An action row: right (BTN1) fires the same request as the idle BTN3
    /// hold and closes the menu; the idle face's transient banner
    /// (`SET 1610M` / `NO GPS FIX` / `NO BARO`) answers, exactly as it
    /// answers the hold. Left does nothing — an action has no "off".
    QnhRezero,
    /// An action row: right (BTN1) closes the menu onto the §358 ICE /
    /// medical-ID face. The BTN4 idle walk reaches that face too, but only
    /// by knowing it is there — a named row is how a runner finds out the
    /// card exists at all, and how they check it is right before a race.
    /// Left does nothing, like every other action row.
    Ice,
}

pub const MENU_ITEMS: usize = 8;

const ITEMS: [MenuItem; MENU_ITEMS] = [
    MenuItem::GnssMode,
    MenuItem::HideEmpty,
    MenuItem::Profile,
    MenuItem::Backyard,
    MenuItem::PairPhone,
    MenuItem::Erase,
    MenuItem::QnhRezero,
    MenuItem::Ice,
];

/// What the ui task needs to draw the menu: where the cursor is, and whether
/// either guarded row is armed. Travels as one value because all of it is
/// modal state the button task owns and the composer only renders —
/// publishing them separately would let the panel show an armed legend over
/// an un-armed row.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MenuView {
    pub cursor: u8,
    pub erase_armed: bool,
    pub pair_armed: bool,
}

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
    /// Arm or disarm backyard-ultra mode (already different from the current
    /// value).
    SetBackyard(bool),
    /// A right press on the PAIR PHONE row (§432). Not an answer, for the
    /// erase row's reason verbatim: this module has no clock, so whether the
    /// press arms or opens is [`crate::pairing::PairGuard`]'s call.
    PairRow,
    /// A left press on the PAIR PHONE row while its window is open: close it
    /// now. Only offered while open — left on a closed row has no "off" to
    /// mean, like every action row.
    ClosePairing,
    /// A right press on the factory-erase row (§378). Deliberately *not* an
    /// answer — this module has no clock, and whether the press arms or wipes
    /// is [`crate::erase::EraseGuard`]'s call, exactly as BTN2's stop is
    /// [`crate::button::StopGuard`]'s rather than [`crate::button::command_for`]'s.
    EraseRow,
    /// Fire the QNH re-zero and close the menu.
    RequestQnhRezero,
    /// Close the menu onto the ICE / medical-ID idle face (§358).
    ShowIce,
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
/// press then starts the ladder at its first rung. `pairing_open` is whether
/// a §432 window is currently open, so a left on the PAIR PHONE row closes
/// exactly the state the runner just read, or nothing.
pub fn edit(
    item: MenuItem,
    dir: ValueDir,
    mode: GnssMode,
    hide_empty: bool,
    profile: Option<ActivityProfile>,
    backyard: bool,
    pairing_open: bool,
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
        (MenuItem::Backyard, ValueDir::Right) => {
            if backyard {
                MenuEdit::Nothing
            } else {
                MenuEdit::SetBackyard(true)
            }
        }
        (MenuItem::Backyard, ValueDir::Left) => {
            if backyard {
                MenuEdit::SetBackyard(false)
            } else {
                MenuEdit::Nothing
            }
        }
        (MenuItem::PairPhone, ValueDir::Right) => MenuEdit::PairRow,
        // The one action row whose left is NOT inert: an open window is a
        // state, and left is its "off" side. On a closed row (or a merely
        // armed one — the generic disarm-on-any-other-press rule covers the
        // arm) left means nothing, like every other action row.
        (MenuItem::PairPhone, ValueDir::Left) => {
            if pairing_open {
                MenuEdit::ClosePairing
            } else {
                MenuEdit::Nothing
            }
        }
        // Left is inert on every action row, and on this one that inertness is
        // load-bearing rather than incidental: the task disarms the guard on
        // every press that is not the confirming right, so BTN5 on an armed
        // erase row is exactly the cancel its legend names.
        (MenuItem::Erase, ValueDir::Right) => MenuEdit::EraseRow,
        (MenuItem::Erase, ValueDir::Left) => MenuEdit::Nothing,
        (MenuItem::QnhRezero, ValueDir::Right) => MenuEdit::RequestQnhRezero,
        (MenuItem::QnhRezero, ValueDir::Left) => MenuEdit::Nothing,
        (MenuItem::Ice, ValueDir::Right) => MenuEdit::ShowIce,
        (MenuItem::Ice, ValueDir::Left) => MenuEdit::Nothing,
    }
}

/// The menu's text rows: a legend naming what §337 says must be named — the
/// exit (which lives on BTN4 here, not the grid's BTN2) and the novel
/// horizontal edit pair — then a title, then one row per item with the
/// cursor marked `>` and the current value inline: a setting is read before
/// it is changed. The cursor keys go unlabelled, exactly like the grid's:
/// they move something visible and commit nothing, so they are discovered
/// for free.
///
/// While the §378 erase is armed the legend row is *replaced* rather than
/// appended to: both of the presses it names change meaning for the duration,
/// and a whole changed chrome row is what keeps the arm from being missed on a
/// nine-row panel where the row itself is one line. On the same trigger the
/// title row yields to [`erase_stake_row`] whenever the run store still holds
/// runs the phone has not pulled (`unsynced_runs`), because those are the one
/// thing the wipe destroys that nothing can re-push — a fully-synced store
/// keeps the prompt byte-identical, so the stake line never cries wolf. The
/// §432 pair arm replaces the legend on the same rule (the two arms are
/// mutually exclusive — any press off a row disarms it, so both can never
/// stand at once).
///
/// Eight items over seven body rows since §432: the body is §333's
/// row-scrolling window ported from the grid — the smallest scroll that keeps
/// the cursor's row on screen, never past the tail ([`window_origin`]).
/// `pairing_remaining_s` is the open §432 window's countdown (`None` =
/// closed), read at render time so the row can never show an expired window
/// as open.
pub fn menu_rows(
    view: MenuView,
    mode: GnssMode,
    hide_empty: bool,
    profile: Option<ActivityProfile>,
    backyard: bool,
    unsynced_runs: u8,
    pairing_remaining_s: Option<u32>,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();
    if view.erase_armed {
        let _ = rows[0].push_str(ERASE_LEGEND_ARMED);
    } else if view.pair_armed {
        let _ = rows[0].push_str(PAIR_LEGEND_ARMED);
    } else {
        let _ = write!(rows[0], "{:<14}B4 EXIT", "B5- B1+");
    }
    match view
        .erase_armed
        .then(|| erase_stake_row(unsynced_runs))
        .flatten()
    {
        Some(stake) => rows[1] = stake,
        None => {
            let _ = rows[1].push_str("SETTINGS");
        }
    }
    let origin = window_origin(view.cursor);
    for (i, item) in ITEMS.iter().enumerate().skip(origin).take(MENU_VISIBLE) {
        let row = MENU_TOP_ROW + (i - origin);
        let marker = if view.cursor as usize == i { '>' } else { ' ' };
        let _ = rows[row].push(marker);
        let _ = rows[row].push(' ');
        match item {
            MenuItem::GnssMode => {
                // The cadence, not the battery hours, for the same reason the
                // idle face dropped them: those hours are a projection for
                // tier-2 hardware using a receiver power-down this firmware
                // does not implement, so no qualifier short enough for the row
                // is honest — `EST` reads as this watch's own estimate. The fix
                // interval is a fact about the device in front of the wearer
                // and carries the same battery/fidelity ordering.
                let _ = write!(
                    rows[row],
                    "GNSS {:<4} {}",
                    mode.label(),
                    mode.cadence_label()
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
            MenuItem::Backyard => {
                let _ = write!(
                    rows[row],
                    "BACKYARD {}",
                    if backyard { "ON" } else { "OFF" }
                );
            }
            MenuItem::PairPhone => {
                if view.pair_armed {
                    let _ = rows[row].push_str(PAIR_ROW_ARMED);
                } else if let Some(remaining) = pairing_remaining_s {
                    let _ = rows[row].push_str(pair_open_row(remaining).as_str());
                } else {
                    let _ = rows[row].push_str(PAIR_ROW);
                }
            }
            MenuItem::Erase => {
                let _ = rows[row].push_str(if view.erase_armed {
                    ERASE_ROW_ARMED
                } else {
                    ERASE_ROW
                });
            }
            MenuItem::QnhRezero => {
                let _ = rows[row].push_str("RE-ZERO ALTITUDE");
            }
            MenuItem::Ice => {
                let _ = rows[row].push_str("MEDICAL ID");
            }
        }
    }
    rows
}

/// First row of the item list, directly under the legend and title.
///
/// It was row 3 until §378, with row 2 held blank so the title band read as
/// chrome. Seven rows spent that blank — the layout's last slack — and §432's
/// eighth row therefore rides §333's row-scrolling window instead of another
/// reclaimed line. The list is still legible without the spacer — every item
/// row is indented two cells behind its cursor marker and the title is flush
/// left, so the indentation does the separating the blank row did.
const MENU_TOP_ROW: usize = 2;

/// Items one screenful of menu shows.
const MENU_VISIBLE: usize = ROWS - MENU_TOP_ROW;

/// First item the body window shows — §333's grammar verbatim: the smallest
/// scroll that keeps the cursor's row on screen, never past the tail.
fn window_origin(cursor: u8) -> usize {
    (cursor as usize)
        .saturating_sub(MENU_VISIBLE - 1)
        .min(MENU_ITEMS - MENU_VISIBLE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::COLS;

    /// The pre-§372 arities, so every case written before the BACKYARD row
    /// keeps reading as exactly what it pins. Backyard mode is off and the
    /// §432 pairing window closed in all of them; the cases that exercise
    /// either call `super::` directly.
    fn edit(
        item: MenuItem,
        dir: ValueDir,
        mode: GnssMode,
        hide_empty: bool,
        profile: Option<ActivityProfile>,
    ) -> MenuEdit {
        super::edit(item, dir, mode, hide_empty, profile, false, false)
    }

    fn menu_rows(
        cursor: u8,
        mode: GnssMode,
        hide_empty: bool,
        profile: Option<ActivityProfile>,
    ) -> [Row; ROWS] {
        super::menu_rows(view(cursor), mode, hide_empty, profile, false, 0, None)
    }

    /// An un-armed cursor — what every case written before §378's erase row
    /// means by a bare cursor index.
    fn view(cursor: u8) -> MenuView {
        MenuView {
            cursor,
            erase_armed: false,
            pair_armed: false,
        }
    }

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
        assert_eq!(m.item(), MenuItem::Backyard);
        m.down();
        assert_eq!(m.item(), MenuItem::PairPhone);
        m.down();
        assert_eq!(m.item(), MenuItem::Erase);
        m.down();
        assert_eq!(m.item(), MenuItem::QnhRezero);
        m.down();
        assert_eq!(m.item(), MenuItem::Ice);
        m.down();
        assert_eq!(m.item(), MenuItem::GnssMode);
        m.up();
        assert_eq!(m.item(), MenuItem::Ice);
    }

    #[test]
    fn the_medical_id_row_fires_right_and_is_inert_left() {
        // Every action row behaves the same way: right fires, left has no
        // "off" to mean. Pinned beside the re-zero row so the two cannot
        // drift into different action grammars.
        assert_eq!(
            edit(
                MenuItem::Ice,
                ValueDir::Right,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::ShowIce
        );
        assert_eq!(
            edit(
                MenuItem::Ice,
                ValueDir::Left,
                GnssMode::Performance,
                true,
                None
            ),
            MenuEdit::Nothing
        );
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
        // The fix cadence, not the tier-2 battery projection — this row was the
        // last seat still stating those hours as if they were this watch's.
        assert_eq!(rows[2].as_str(), "> GNSS PERF 1 FIX/1S");
        assert_eq!(rows[3].as_str(), "  HIDE EMPTY ON");
        assert_eq!(rows[4].as_str(), "  PROFILE --");
        assert_eq!(rows[5].as_str(), "  BACKYARD OFF");
        assert_eq!(rows[6].as_str(), "  PAIR PHONE");
        assert_eq!(rows[7].as_str(), "  FACTORY ERASE");
        assert_eq!(rows[8].as_str(), "  RE-ZERO ALTITUDE");
        let rows = menu_rows(1, GnssMode::Expedition, false, Some(ActivityProfile::Ultra));
        // 21 cells exactly — the widest this row gets, so it also pins the fit.
        assert_eq!(rows[2].as_str(), "  GNSS EXP  1 FIX/60S");
        assert_eq!(rows[3].as_str(), "> HIDE EMPTY OFF");
        assert_eq!(rows[4].as_str(), "  PROFILE ULTRA");
    }

    #[test]
    fn the_body_window_scrolls_to_the_cursor_and_never_hides_it() {
        // §333's grammar on the menu: eight items, seven body rows. At the
        // top the window rests at the head and MEDICAL ID waits below the
        // fold; on the last row the window slides one, GNSS MODE leaves the
        // top, and the cursor is on screen — always.
        let rows = menu_rows(6, GnssMode::Performance, true, None);
        assert_eq!(rows[2].as_str(), "  GNSS PERF 1 FIX/1S");
        assert_eq!(rows[8].as_str(), "> RE-ZERO ALTITUDE");
        let rows = menu_rows(7, GnssMode::Performance, true, None);
        assert_eq!(rows[2].as_str(), "  HIDE EMPTY ON");
        assert_eq!(rows[8].as_str(), "> MEDICAL ID");
        for cursor in 0..MENU_ITEMS as u8 {
            let rows = menu_rows(cursor, GnssMode::Performance, true, None);
            let marked = rows.iter().filter(|r| r.starts_with('>')).count();
            assert_eq!(marked, 1, "cursor {cursor} fell out of the window");
        }
    }

    #[test]
    fn the_erase_row_arms_on_right_and_is_inert_left() {
        // The action-row grammar, unchanged: right fires, left has no "off".
        // What is NOT here is the arm/confirm decision — this module has no
        // clock, so the press only reports which row it landed on and
        // `erase::EraseGuard` decides, exactly as `StopGuard` does for BTN2.
        let e = |dir| edit(MenuItem::Erase, dir, GnssMode::Performance, true, None);
        assert_eq!(e(ValueDir::Right), MenuEdit::EraseRow);
        assert_eq!(e(ValueDir::Left), MenuEdit::Nothing);
    }

    #[test]
    fn an_armed_erase_replaces_the_legend_and_names_the_key_that_wipes() {
        // An arm that showed only in one row of nine could be missed on the
        // way past; the legend row is the whole width of the panel and it is
        // where §337 says a changed press meaning has to be read.
        let armed = MenuView {
            cursor: 5,
            erase_armed: true,
            pair_armed: false,
        };
        let rows = super::menu_rows(armed, GnssMode::Performance, true, None, false, 0, None);
        assert_eq!(rows[0].as_str(), "B1 ERASE    B4 CANCEL");
        assert_eq!(rows[7].as_str(), "> ERASE ALL? B1");
        // Nothing else moves: the runner reads the rest of the menu unchanged,
        // so the arm reads as one row's state and not as a new screen. With
        // nothing unsynced this pins the whole armed prompt byte-for-byte —
        // the stake line may only ever exist when there is a stake.
        let resting = super::menu_rows(view(5), GnssMode::Performance, true, None, false, 0, None);
        assert_eq!(rows[1], resting[1]);
        assert_eq!(rows[1].as_str(), "SETTINGS");
        for row in 2..ROWS {
            if row != 7 {
                assert_eq!(rows[row], resting[row], "row {row} moved under the arm");
            }
        }
        assert_eq!(resting[7].as_str(), "> FACTORY ERASE");
    }

    #[test]
    fn an_armed_erase_with_unsynced_runs_names_the_stake_in_the_title_row() {
        // The confirm must not price a settings reset and the destruction of
        // never-pulled race data as the same act: while the store holds runs
        // the phone has not synced, the title row yields to the count. Only
        // while armed — the resting menu is not a warning surface — and every
        // other row stays exactly as the count-free arm renders it.
        let armed = MenuView {
            cursor: 5,
            erase_armed: true,
            pair_armed: false,
        };
        let rows = super::menu_rows(armed, GnssMode::Performance, true, None, false, 3, None);
        assert_eq!(rows[0].as_str(), "B1 ERASE    B4 CANCEL");
        assert_eq!(rows[1].as_str(), "3 RUNS NOT SYNCED");
        assert_eq!(rows[7].as_str(), "> ERASE ALL? B1");
        let quiet = super::menu_rows(armed, GnssMode::Performance, true, None, false, 0, None);
        for row in 2..ROWS {
            assert_eq!(rows[row], quiet[row], "row {row} moved under the stake");
        }
        let resting = super::menu_rows(view(5), GnssMode::Performance, true, None, false, 3, None);
        assert_eq!(
            resting[1].as_str(),
            "SETTINGS",
            "an un-armed menu never carries the stake line"
        );
    }

    #[test]
    fn the_guarded_rows_sit_where_no_existing_row_pays_for_them() {
        // §378's press-cost argument, pinned rather than restated: on a
        // wrapping ring the cursor distance to index k is min(k, n - k). The
        // seventh row (§378's erase) took the 7-ring's second far seat; the
        // eighth (§432's pair) takes the 8-ring's one TRUE far seat — the
        // only zero-tax placement left, and the hardest row to land on by
        // accident. Computed here from the ITEMS array, so a reorder that
        // quietly taxes a mid-race row fails.
        let steps = |n: usize, k: usize| k.min(n - k);
        let before = [
            MenuItem::GnssMode,
            MenuItem::HideEmpty,
            MenuItem::Profile,
            MenuItem::Backyard,
            MenuItem::Erase,
            MenuItem::QnhRezero,
            MenuItem::Ice,
        ];
        for (was, item) in before.iter().enumerate() {
            let now = ITEMS.iter().position(|i| i == item).expect("row kept");
            assert_eq!(
                steps(MENU_ITEMS, now),
                steps(before.len(), was),
                "{item:?} costs more cursor steps than it did at seven rows"
            );
        }
        let pair = ITEMS
            .iter()
            .position(|i| *i == MenuItem::PairPhone)
            .expect("the pair row exists");
        assert_eq!(
            steps(MENU_ITEMS, pair),
            4,
            "the pair row belongs on the ring's far seat — the hardest row \
             to land on by accident"
        );
        let erase = ITEMS
            .iter()
            .position(|i| *i == MenuItem::Erase)
            .expect("the erase row exists");
        assert_eq!(
            steps(MENU_ITEMS, erase),
            3,
            "the erase kept its 7-ring cost"
        );
        // Every mid-race row (one the runner reaches for during a run) still
        // costs open + steps + edit <= 4, which is §351's real budget.
        for item in [MenuItem::GnssMode, MenuItem::HideEmpty, MenuItem::Profile] {
            let k = ITEMS.iter().position(|i| *i == item).expect("row exists");
            assert!(
                steps(MENU_ITEMS, k) + 2 <= 4,
                "{item:?} broke the ≤ 4 bound"
            );
        }
    }

    #[test]
    fn the_pair_row_arms_on_right_and_left_only_closes_an_open_window() {
        // Right is the guarded arm/open path — like the erase, the module
        // reports which row the press landed on and `pairing::PairGuard`
        // decides. Left is the one action-row left that means something: the
        // "off" side of an OPEN window, and nothing at all when it is closed
        // (there is no off to press for).
        let e = |dir, open| {
            super::edit(
                MenuItem::PairPhone,
                dir,
                GnssMode::Performance,
                true,
                None,
                false,
                open,
            )
        };
        assert_eq!(e(ValueDir::Right, false), MenuEdit::PairRow);
        assert_eq!(e(ValueDir::Right, true), MenuEdit::PairRow);
        assert_eq!(e(ValueDir::Left, true), MenuEdit::ClosePairing);
        assert_eq!(e(ValueDir::Left, false), MenuEdit::Nothing);
    }

    #[test]
    fn an_armed_pair_replaces_the_legend_and_names_the_key_that_opens() {
        // §378's rule at the other guarded row: both named presses change
        // meaning while armed, so the whole chrome row changes with them.
        let armed = MenuView {
            cursor: 4,
            erase_armed: false,
            pair_armed: true,
        };
        let rows = super::menu_rows(armed, GnssMode::Performance, true, None, false, 0, None);
        assert_eq!(rows[0].as_str(), "B1 PAIR     B4 CANCEL");
        assert_eq!(rows[6].as_str(), "> PAIR NEW? B1");
        // Nothing else moves — the arm reads as one row's state, and the
        // title never carries the erase's stake line for a pair arm: nothing
        // a re-pair does destroys a run.
        let resting = super::menu_rows(view(4), GnssMode::Performance, true, None, false, 3, None);
        assert_eq!(rows[1].as_str(), "SETTINGS");
        for row in 2..ROWS {
            if row != 6 {
                assert_eq!(rows[row], resting[row], "row {row} moved under the arm");
            }
        }
        assert_eq!(resting[6].as_str(), "> PAIR PHONE");
    }

    #[test]
    fn an_open_window_reads_its_countdown_on_the_row() {
        // The countdown is the state, read at render time — so an expired
        // window (the caller passes None) drops straight back to the resting
        // text and the row can never advertise a door that is shut.
        let rows = super::menu_rows(
            view(4),
            GnssMode::Performance,
            true,
            None,
            false,
            0,
            Some(88),
        );
        assert_eq!(rows[6].as_str(), "> PAIRING OPEN 88S");
        let rows = super::menu_rows(view(4), GnssMode::Performance, true, None, false, 0, None);
        assert_eq!(rows[6].as_str(), "> PAIR PHONE");
    }

    #[test]
    fn the_backyard_row_reads_its_state_and_edits_idempotently() {
        // The hide-empty grammar, for the same reason: a runner arming this at
        // a start line presses the side they want, and a double press must not
        // undo it.
        let e = |dir, on| {
            super::edit(
                MenuItem::Backyard,
                dir,
                GnssMode::Performance,
                true,
                None,
                on,
                false,
            )
        };
        assert_eq!(e(ValueDir::Right, false), MenuEdit::SetBackyard(true));
        assert_eq!(e(ValueDir::Right, true), MenuEdit::Nothing);
        assert_eq!(e(ValueDir::Left, true), MenuEdit::SetBackyard(false));
        assert_eq!(e(ValueDir::Left, false), MenuEdit::Nothing);
        let rows = super::menu_rows(view(3), GnssMode::Performance, true, None, true, 0, None);
        assert_eq!(rows[5].as_str(), "> BACKYARD ON");
    }

    #[test]
    fn every_menu_row_fits_the_body_it_is_drawn_into() {
        // Eight items over the seven rows under the two chrome rows — §378
        // spent the blank spacer, §432 spent the last whole-list layout, so
        // the body is now §333's scrolling window and the pinned fact is the
        // window's size, not the list's.
        for erase_armed in [false, true] {
            for pair_armed in [false, true] {
                for unsynced in [0, 4] {
                    for pairing in [None, Some(90), Some(1)] {
                        let rows = super::menu_rows(
                            MenuView {
                                cursor: 0,
                                erase_armed,
                                pair_armed,
                            },
                            GnssMode::Expedition,
                            false,
                            Some(ActivityProfile::Ultra),
                            true,
                            unsynced,
                            pairing,
                        );
                        for row in rows.iter() {
                            assert!(row.len() <= COLS, "menu row too wide: {row:?}");
                        }
                    }
                }
            }
        }
        assert_eq!(
            MENU_TOP_ROW + MENU_VISIBLE,
            ROWS,
            "the window fills the body"
        );
        assert_eq!(
            MENU_ITEMS,
            MENU_VISIBLE + 1,
            "one item past a screenful — the smallest window the list needs"
        );
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
    #[test]
    fn every_menu_item_the_enum_can_hold_is_on_the_ring() {
        // ITEMS is a hand-written array and MENU_ITEMS its hand-written
        // length; the array literal's type checks the two against each other
        // and nothing checks either against the ENUM. A variant added to
        // MenuItem and not to ITEMS compiles, because `edit`'s exhaustive
        // match is satisfied by the arm the author did write — and the row
        // then exists in the firmware and can never be selected, because the
        // cursor only ever walks ITEMS.
        //
        // The match below is what closes it: adding a variant fails to
        // compile here until it is listed, and listing it fails the assertion
        // until it is also seated on the ring.
        let every = [
            MenuItem::GnssMode,
            MenuItem::HideEmpty,
            MenuItem::Profile,
            MenuItem::Backyard,
            MenuItem::PairPhone,
            MenuItem::Erase,
            MenuItem::QnhRezero,
            MenuItem::Ice,
        ];
        for item in every {
            // Exhaustive by construction: a new variant makes this match
            // non-exhaustive and the crate stops building.
            let named = match item {
                MenuItem::GnssMode
                | MenuItem::HideEmpty
                | MenuItem::Profile
                | MenuItem::Backyard
                | MenuItem::PairPhone
                | MenuItem::Erase
                | MenuItem::QnhRezero
                | MenuItem::Ice => item,
            };
            assert_eq!(
                ITEMS.iter().filter(|i| **i == named).count(),
                1,
                "{named:?} is not seated exactly once on the cursor ring, so it \
                 is either unreachable or reachable twice"
            );
        }
        assert_eq!(ITEMS.len(), every.len());
        assert_eq!(MENU_ITEMS, every.len());
    }

    #[test]
    fn a_guarded_row_is_on_screen_at_every_cursor_position() {
        // The two-press guards put a destructive key behind a legend that
        // names it ("B1 WIPES"). A body window that could scroll the row
        // itself past the fold would leave that legend describing a row the
        // wearer cannot see — the §337 surprise the legend exists to prevent,
        // arriving through the §333 scroll instead of through the key map.
        //
        // Holds today because eight items over a seven-row window leave only
        // two window positions and both guarded rows sit inside both. A ninth
        // row opens a third position, and this is what says which rows fell
        // out of it.
        for cursor in 0..MENU_ITEMS as u8 {
            let rows = super::menu_rows(
                MenuView {
                    cursor,
                    erase_armed: false,
                    pair_armed: false,
                },
                GnssMode::Balanced,
                false,
                None,
                false,
                0,
                None,
            );
            let body: heapless::Vec<&str, ROWS> =
                rows.iter().map(|r| r.as_str()).collect();
            for needle in [ERASE_ROW, PAIR_ROW] {
                assert!(
                    body.iter().any(|r| r.contains(needle)),
                    "cursor {cursor}: {needle:?} is off the fold, so its armed \
                     legend would name a row nobody can see"
                );
            }
        }
    }
}
