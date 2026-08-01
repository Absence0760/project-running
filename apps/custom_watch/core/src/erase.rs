//! The factory erase — the wearer's own way to sanitise the watch, with no
//! phone in reach (decisions §378).
//!
//! Everything durable this device holds is personal: four run slots of
//! latitude/longitude at 1e-7° with a bpm per point, eight marked waypoints, an
//! ICE card carrying special-category health data and a next-of-kin's phone
//! number, and the paired phone's long-term and identity-resolution keys.
//! Until §378 none of it could be removed by the person wearing it — the ICE
//! card could only be cleared by a *phone* push, and the runs and the bond could
//! not be cleared at all. A lost, stolen, or handed-on watch could not be
//! sanitised. This module is the pure half of closing that.
//!
//! **The guard is [`crate::button::StopGuard`]'s shape, deliberately.** An erase
//! is the second irreversible action on the device, and the first one already
//! taught the runner a two-press confirm inside a window: the first press arms
//! and visibly says so, a second press inside [`ERASE_CONFIRM_WINDOW_S`]
//! commits, and anything else — any other key, or the window lapsing — cancels.
//! Reusing the learned shape is worth more than inventing a second one, so the
//! window IS [`crate::button::STOP_CONFIRM_WINDOW_S`] rather than a number of
//! its own.
//!
//! **A hold tier was considered and refused.** Hold-to-confirm is the other
//! guarded-destructive idiom in this workspace (the page grid's 0.5 s
//! hold-to-open), and it cannot be used here: the settings menu is an idle
//! surface, and *idle gestures are duration-stable* is a pinned navigation
//! invariant — §375 declined to split BTN2 by duration for exactly this reason.
//! A duration-split inside an idle modal would be the first gesture to break it.
//! Two presses it is.

use core::fmt::Write;

use crate::button::STOP_CONFIRM_WINDOW_S;
use crate::face::Row;

/// Seconds an armed erase waits for its confirming press. The stop guard's
/// window, not a second one — one learned dwell on a device with two
/// irreversible actions.
pub const ERASE_CONFIRM_WINDOW_S: u32 = STOP_CONFIRM_WINDOW_S;

/// The settings row's resting text.
pub const ERASE_ROW: &str = "FACTORY ERASE";

/// The row's text while the guard is armed — the `STOP? BTN2` register, naming
/// the key that commits. An arm nobody can see reads as a dead button.
pub const ERASE_ROW_ARMED: &str = "ERASE ALL? B1";

/// The menu's legend row while an erase is armed. §337's rule is that a modal
/// names the presses that leave it, and while armed BOTH of them change
/// meaning: BTN1 stops being "edit right" and becomes the commit, and BTN4
/// stops being a bare exit and becomes the cancel that also exits. A whole
/// changed chrome row is additionally what stops the arm from being missed —
/// one row of nine can be.
pub const ERASE_LEGEND_ARMED: &str = "B1 ERASE    B4 CANCEL";

/// The armed prompt's stake row — `N RUNS NOT SYNCED` — or `None` when the
/// store holds nothing the phone has not pulled.
///
/// A factory erase is two different acts wearing one prompt. The settings, the
/// ICE card, the screens and the bond are all *recoverable* — the phone
/// authored them and re-pushes each in one action — but a finished run the
/// phone has never pulled exists nowhere else on earth, and `ERASE ALL? B1`
/// prices both losses identically. While any such run is on flash, the confirm
/// names the stake; when everything is synced (or the store is empty) the
/// prompt stays exactly what it was, so the line can never cry wolf and its
/// appearance always means something.
///
/// It replaces the menu *title*, not the armed row, and adds no press: the
/// item row's cells behind the cursor marker cannot carry both the count and
/// the key that commits — and §337 says the key is the part that may not be
/// dropped — while replacing a whole chrome row is already how this arm
/// announces itself (the legend row is replaced on the same trigger). The
/// two-press guard is untouched.
pub fn erase_stake_row(unsynced_runs: u8) -> Option<Row> {
    if unsynced_runs == 0 {
        return None;
    }
    let mut row = Row::new();
    let plural = if unsynced_runs == 1 { "" } else { "S" };
    let _ = write!(row, "{unsynced_runs} RUN{plural} NOT SYNCED");
    Some(row)
}

/// What a press on the erase row produced.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ErasePress {
    /// The guard armed — nothing is erased yet. A second press inside
    /// [`ERASE_CONFIRM_WINDOW_S`] commits.
    Armed,
    /// A second press inside the window: wipe now.
    Confirmed,
}

/// Guards the factory erase behind a deliberate double-press, so a fried runner
/// at hour 60 cannot wipe their race by fumbling one button.
///
/// State lives here (host-tested) rather than in the app's button task, exactly
/// like [`crate::button::StopGuard`]; the task supplies a monotonic `now_s` and
/// disarms on every press that is not the confirm.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct EraseGuard {
    armed_at_s: Option<u32>,
}

impl EraseGuard {
    pub const fn new() -> Self {
        Self { armed_at_s: None }
    }

    /// Feed a right-press on the erase row.
    pub fn press(&mut self, now_s: u32) -> ErasePress {
        match self.armed_at_s {
            Some(at) if now_s.saturating_sub(at) <= ERASE_CONFIRM_WINDOW_S => {
                self.armed_at_s = None;
                ErasePress::Confirmed
            }
            // First press, or one after the window lapsed — (re)arm.
            _ => {
                self.armed_at_s = Some(now_s);
                ErasePress::Armed
            }
        }
    }

    /// Whether an arm is still awaiting its confirm — what the row and the
    /// legend render from, sharing the window with [`press`](Self::press) so the
    /// prompt can never outlive the press that would commit it.
    pub fn armed(&self, now_s: u32) -> bool {
        self.armed_at_s
            .is_some_and(|at| now_s.saturating_sub(at) <= ERASE_CONFIRM_WINDOW_S)
    }

    /// Drop the arm. The task calls this on every press that is not the
    /// confirming one, on the window's expiry, and on the menu closing — an arm
    /// may never outlive the screen that shows it.
    pub fn disarm(&mut self) {
        self.armed_at_s = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::face::COLS;

    #[test]
    fn one_press_arms_and_a_second_inside_the_window_confirms() {
        let mut g = EraseGuard::new();
        assert!(!g.armed(100));
        assert_eq!(g.press(100), ErasePress::Armed);
        assert!(g.armed(100));
        assert_eq!(g.press(100 + ERASE_CONFIRM_WINDOW_S), ErasePress::Confirmed);
        // A confirm consumes the arm, so the next press starts over rather than
        // wiping again off the same arm.
        assert!(!g.armed(100 + ERASE_CONFIRM_WINDOW_S));
        assert_eq!(g.press(200), ErasePress::Armed);
    }

    #[test]
    fn a_press_past_the_window_re_arms_rather_than_confirming() {
        // The failure this guards: a brush that armed the erase minutes ago
        // must not turn the next deliberate press into a wipe.
        let mut g = EraseGuard::new();
        assert_eq!(g.press(100), ErasePress::Armed);
        assert!(!g.armed(101 + ERASE_CONFIRM_WINDOW_S));
        assert_eq!(g.press(101 + ERASE_CONFIRM_WINDOW_S), ErasePress::Armed);
    }

    #[test]
    fn a_disarmed_guard_needs_two_presses_again() {
        // Every press inside the menu that is not the confirm disarms, so a
        // cursor step between the two presses costs the arm — which is the
        // whole point: the confirm has to be the very next thing the runner does.
        let mut g = EraseGuard::new();
        assert_eq!(g.press(100), ErasePress::Armed);
        g.disarm();
        assert!(!g.armed(100));
        assert_eq!(g.press(100), ErasePress::Armed);
        assert_eq!(g.press(100), ErasePress::Confirmed);
    }

    #[test]
    fn a_stamp_from_the_future_reads_armed_not_wrapped() {
        // Racing the second boundary must saturate to age zero, not wrap to a
        // huge age and silently drop a live arm.
        let mut g = EraseGuard::new();
        assert_eq!(g.press(100), ErasePress::Armed);
        assert!(g.armed(99));
    }

    #[test]
    fn the_window_is_the_stop_guards_so_the_device_has_one_learned_dwell() {
        assert_eq!(ERASE_CONFIRM_WINDOW_S, STOP_CONFIRM_WINDOW_S);
    }

    #[test]
    fn every_rendered_string_fits_the_face() {
        // The armed legend fills the row exactly, like the resting one, so the
        // chrome row can never read as half-written.
        assert_eq!(ERASE_LEGEND_ARMED.len(), COLS);
        // The rows are drawn behind a two-cell cursor marker.
        for s in [ERASE_ROW, ERASE_ROW_ARMED] {
            assert!(s.len() + 2 <= COLS, "row too wide: {s}");
        }
    }

    #[test]
    fn no_unsynced_runs_means_no_stake_row() {
        // The line's whole value is that it only ever appears when the wipe
        // would destroy something unrecoverable — a warning that also fires
        // on a fully-synced store is one the runner learns to press through.
        assert_eq!(erase_stake_row(0), None);
    }

    #[test]
    fn the_stake_row_carries_the_count_and_fits_the_face() {
        // A chrome row, drawn flush like the legend — the full COLS budget.
        for n in 1..=4u8 {
            let row = erase_stake_row(n).expect("unsynced runs must be named");
            assert!(row.contains("NOT SYNCED"));
            assert!(row.starts_with(char::from(b'0' + n)));
            assert!(row.len() <= COLS, "stake row too wide: {row}");
        }
        assert_eq!(erase_stake_row(1).unwrap().as_str(), "1 RUN NOT SYNCED");
        assert_eq!(erase_stake_row(3).unwrap().as_str(), "3 RUNS NOT SYNCED");
    }

    #[test]
    fn the_armed_row_names_the_key_that_commits() {
        // §337: a press that commits something irreversible is read, never
        // discovered. The resting row deliberately does not — an unarmed row
        // commits nothing.
        assert!(ERASE_ROW_ARMED.contains("B1"));
        assert!(!ERASE_ROW.contains("B1"));
        assert!(ERASE_LEGEND_ARMED.contains("B1"));
        assert!(ERASE_LEGEND_ARMED.contains("B4"));
    }
}
