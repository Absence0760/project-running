//! The BLE re-pair window — the wearer's own gate on bond formation
//! (decisions §432, superseding the lost-phone half of §378's FACTORY ERASE
//! answer and closing the audit gap against §285).
//!
//! A bonded watch refuses every pairing attempt outright (`Bonder::can_bond`
//! plus the MITM-requirement refusal — see `app`'s ble task), because a
//! just-works pairing completes with no interaction at either end and the
//! bond it forms replaces the owner's. That left a runner whose phone died or
//! vanished exactly one path back: FACTORY ERASE, which also destroys any
//! run the phone never pulled. This module is the deliberate exception — a
//! time-boxed window the wearer arms from the settings menu's PAIR PHONE row,
//! inside which (and only inside which) a bonded watch will accept a
//! replacement bond. An unbonded watch needs no window: first-time setup has
//! nothing to protect yet.
//!
//! The row is guarded the way FACTORY ERASE is (§378's two-press confirm in
//! the stop guard's window), because a single fumbled press opening 90 s of
//! radio-range takeover is exactly the class of accident the bond gate
//! exists to prevent. The confirm's LEFT sibling closes an open window early
//! — the directional grammar's "off" side, unguarded because closing a
//! security window needs no ceremony.
//!
//! Pure and host-tested. The app mirrors the deadline this module computes
//! into an atomic the SoftDevice's event-context callbacks can read
//! (`state::PAIRING_WINDOW_UNTIL_S`) — they can neither await nor hold a
//! `Watch` receiver — and a reboot zeroes the atomic, so the gate fails
//! closed.

use core::cell::Cell;
use core::fmt::Write;

use crate::button::STOP_CONFIRM_WINDOW_S;
use crate::face::Row;

/// Seconds a wearer-armed pairing window stays open. Long enough to put the
/// watch down, pick the phone up, and walk its pairing flow once; short
/// enough that a window opened and forgotten is not a standing invitation.
pub const PAIRING_WINDOW_S: u32 = 90;

/// Seconds an armed PAIR PHONE row waits for its confirming press — the stop
/// guard's window, like the erase's: one learned dwell for every guarded
/// action on the device.
pub const PAIR_CONFIRM_WINDOW_S: u32 = STOP_CONFIRM_WINDOW_S;

/// The atomic's closed sentinel: no deadline, no window.
pub const WINDOW_CLOSED: u32 = 0;

/// The settings row's resting text.
pub const PAIR_ROW: &str = "PAIR PHONE";

/// The row's text while the guard is armed — the `ERASE ALL? B1` register,
/// naming the key that commits.
pub const PAIR_ROW_ARMED: &str = "PAIR NEW? B1";

/// The menu's legend row while a pair arm is pending, replacing the resting
/// legend for §378's reason verbatim: both named presses change meaning while
/// armed, and a whole changed chrome row is what keeps the arm from being
/// missed.
pub const PAIR_LEGEND_ARMED: &str = "B1 PAIR     B4 CANCEL";

/// The row's text while the window is open — the countdown is the state, so
/// the row reads it.
pub fn pair_open_row(remaining_s: u32) -> Row {
    let mut row = Row::new();
    let _ = write!(row, "PAIRING OPEN {remaining_s}S");
    row
}

/// When a window opened at `now_s` closes. Never [`WINDOW_CLOSED`]: the
/// saturating add can only reach `u32::MAX`.
pub fn window_deadline(now_s: u32) -> u32 {
    now_s.saturating_add(PAIRING_WINDOW_S)
}

/// Seconds an open window has left, or `None` when it is closed — by the
/// sentinel, or by its deadline having passed.
pub fn window_remaining_s(until_s: u32, now_s: u32) -> Option<u32> {
    (until_s != WINDOW_CLOSED && now_s < until_s).then(|| until_s - now_s)
}

/// Whether a pairing request may form a bond: always while no bond exists
/// (first-time setup — there is no owner to evict yet), otherwise only inside
/// a wearer-opened window. The app's `request_mitm_protection` asserts the
/// negation of this, because refusing only the *bond* is not enough —
/// just-works is Security Mode 1 Level 2 and a bond-less pairing still
/// reaches Level 2, which is exactly what every characteristic's gate
/// accepts. Naming a requirement `IoCapabilities::None` cannot satisfy fails
/// the pairing procedure itself.
/// Whether a stored bond is still the wearer's, given the factory-erase
/// generation it was formed under and the device's current one.
///
/// FACTORY ERASE (§ 378) wipes the `BND1` flash record, but the live keys sit
/// in RAM inside the SoftDevice security handler and the firmware never
/// reboots — so before this predicate existed an erased watch kept serving the
/// previous owner's phone its LTK until the battery died. `privacy.md` calls
/// the bond "a live credential, not a stale record"; that is exactly what made
/// the gap matter, and the erase's whole purpose is a watch that is lost,
/// stolen, or handed on.
///
/// The generation is compared, never a boolean "erased" flag, because the
/// watch must be able to pair again immediately afterwards: a re-pair records
/// the generation it happened under, so the next erase invalidates it in turn.
/// An equal generation is the only live case; a stored bond from any earlier
/// generation is treated as absent, which also makes `may_bond` see an
/// unbonded watch and restores first-time-setup pairing with no window.
pub fn bond_is_live(bonded_at_gen: u32, current_gen: u32) -> bool {
    bonded_at_gen == current_gen
}

/// A stored bond together with the erase generation it was formed under, held
/// so that [`bond_is_live`] **cannot be skipped**.
///
/// The predicate above is the whole gate, and a caller that reads the peer
/// without consulting it serves an erased owner's keys. That had already
/// happened twice — once as the round-3 bond defect this predicate was written
/// for, and again in `load_sys_attrs`, which read the field directly while the
/// accessor beside it documented that nothing may (issue #664) — so the fix is
/// not a third careful call site but a type with no way to get the peer out
/// except through the check. Both fields are private to this module; the app's
/// `Bonder` holds one of these and supplies `current_gen` from its atomic.
///
/// Generic over the peer because the SoftDevice key types live in the `app`
/// crate and must not be dragged into this `no_std` core — `Copy` is all this
/// needs, and it is what a `Cell` requires anyway.
pub struct BondCell<P: Copy> {
    peer: Cell<Option<P>>,
    formed_at_gen: Cell<u32>,
}

impl<P: Copy> BondCell<P> {
    pub const fn new() -> Self {
        BondCell {
            peer: Cell::new(None),
            formed_at_gen: Cell::new(0),
        }
    }

    /// The stored peer, or `None` once a factory erase has retired it. The
    /// ONLY way out.
    pub fn live(&self, current_gen: u32) -> Option<P> {
        bond_is_live(self.formed_at_gen.get(), current_gen)
            .then(|| self.peer.get())
            .flatten()
    }

    /// Whether a live bond is held — [`Self::live`] for callers that need only
    /// the question, so `Copy`-ing a peer out to test it for `None` is not the
    /// idiom that spreads.
    pub fn is_live(&self, current_gen: u32) -> bool {
        self.live(current_gen).is_some()
    }

    /// Adopt `peer` as of `current_gen`. Storing the generation is not
    /// optional — it is the same write.
    pub fn set(&self, peer: Option<P>, current_gen: u32) {
        self.peer.set(peer);
        self.formed_at_gen.set(current_gen);
    }
}

impl<P: Copy> Default for BondCell<P> {
    fn default() -> Self {
        Self::new()
    }
}

pub fn may_bond(bonded: bool, window_open: bool) -> bool {
    !bonded || window_open
}

/// What a right-press on the PAIR PHONE row produced.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PairPress {
    /// The guard armed — nothing is open yet. A second press inside
    /// [`PAIR_CONFIRM_WINDOW_S`] opens the window.
    Armed,
    /// A second press inside the window: open the pairing window now.
    Opened,
}

/// Guards the pairing window behind a deliberate double-press —
/// [`crate::erase::EraseGuard`]'s shape at the other security boundary the
/// menu carries. State lives here (host-tested); the task supplies a
/// monotonic `now_s` and disarms on every press that is not the confirm.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PairGuard {
    armed_at_s: Option<u32>,
}

impl PairGuard {
    pub const fn new() -> Self {
        Self { armed_at_s: None }
    }

    /// Feed a right-press on the PAIR PHONE row.
    pub fn press(&mut self, now_s: u32) -> PairPress {
        match self.armed_at_s {
            Some(at) if now_s.saturating_sub(at) <= PAIR_CONFIRM_WINDOW_S => {
                self.armed_at_s = None;
                PairPress::Opened
            }
            _ => {
                self.armed_at_s = Some(now_s);
                PairPress::Armed
            }
        }
    }

    /// Whether an arm is still awaiting its confirm — what the row and the
    /// legend render from.
    pub fn armed(&self, now_s: u32) -> bool {
        self.armed_at_s
            .is_some_and(|at| now_s.saturating_sub(at) <= PAIR_CONFIRM_WINDOW_S)
    }

    /// Drop the arm — on any press that is not the confirming one, on the
    /// window's expiry, and on the menu closing.
    pub fn disarm(&mut self) {
        self.armed_at_s = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::erase::ERASE_LEGEND_ARMED;
    use crate::face::COLS;

    #[test]
    fn an_unbonded_watch_always_pairs_and_a_bonded_one_only_inside_the_window() {
        // The whole gate in four rows. No bond: first-time setup must work
        // with no passkey face to interact with, window or not. Bonded: the
        // window is the ONLY way in — closed means refused, which is the
        // fail-closed default a reboot restores.
        assert!(may_bond(false, false));
        assert!(may_bond(false, true));
        assert!(!may_bond(true, false));
        assert!(may_bond(true, true));
    }

    #[test]
    fn a_fresh_window_is_open_for_exactly_the_advertised_seconds() {
        let until = window_deadline(1_000);
        assert_eq!(window_remaining_s(until, 1_000), Some(PAIRING_WINDOW_S));
        assert_eq!(
            window_remaining_s(until, 1_000 + PAIRING_WINDOW_S - 1),
            Some(1)
        );
        // The deadline second itself is closed: a gate that errs, errs shut.
        assert_eq!(window_remaining_s(until, 1_000 + PAIRING_WINDOW_S), None);
        assert_eq!(window_remaining_s(until, u32::MAX), None);
    }

    #[test]
    fn the_closed_sentinel_never_reads_open_at_any_clock() {
        for now_s in [0, 1, PAIRING_WINDOW_S, u32::MAX] {
            assert_eq!(window_remaining_s(WINDOW_CLOSED, now_s), None);
        }
        // And a real deadline can never collide with it, even at the clock's
        // end — the one value the atomic treats as "no window".
        assert_ne!(window_deadline(u32::MAX), WINDOW_CLOSED);
    }

    #[test]
    fn the_window_is_long_enough_to_fetch_a_phone_and_never_a_standing_door() {
        assert!(PAIRING_WINDOW_S >= 60);
        assert!(PAIRING_WINDOW_S <= 120);
    }

    #[test]
    fn one_press_arms_and_a_second_inside_the_window_opens() {
        let mut g = PairGuard::new();
        assert!(!g.armed(100));
        assert_eq!(g.press(100), PairPress::Armed);
        assert!(g.armed(100));
        assert_eq!(g.press(100 + PAIR_CONFIRM_WINDOW_S), PairPress::Opened);
        // An open consumes the arm, so the next press starts over.
        assert!(!g.armed(100 + PAIR_CONFIRM_WINDOW_S));
        assert_eq!(g.press(200), PairPress::Armed);
    }

    #[test]
    fn a_press_past_the_window_re_arms_rather_than_opening() {
        let mut g = PairGuard::new();
        assert_eq!(g.press(100), PairPress::Armed);
        assert!(!g.armed(101 + PAIR_CONFIRM_WINDOW_S));
        assert_eq!(g.press(101 + PAIR_CONFIRM_WINDOW_S), PairPress::Armed);
    }

    #[test]
    fn a_disarmed_guard_needs_two_presses_again() {
        let mut g = PairGuard::new();
        assert_eq!(g.press(100), PairPress::Armed);
        g.disarm();
        assert!(!g.armed(100));
        assert_eq!(g.press(100), PairPress::Armed);
        assert_eq!(g.press(100), PairPress::Opened);
    }

    #[test]
    fn a_stamp_from_the_future_reads_armed_not_wrapped() {
        let mut g = PairGuard::new();
        assert_eq!(g.press(100), PairPress::Armed);
        assert!(g.armed(99));
    }

    #[test]
    fn the_confirm_window_is_the_stop_guards_so_the_device_has_one_learned_dwell() {
        assert_eq!(PAIR_CONFIRM_WINDOW_S, STOP_CONFIRM_WINDOW_S);
    }

    #[test]
    fn every_rendered_string_fits_the_face() {
        // The armed legend fills the row exactly, like the erase's, so the
        // chrome row can never read as half-written.
        assert_eq!(PAIR_LEGEND_ARMED.len(), COLS);
        assert_eq!(PAIR_LEGEND_ARMED.len(), ERASE_LEGEND_ARMED.len());
        for s in [PAIR_ROW, PAIR_ROW_ARMED] {
            assert!(s.len() + 2 <= COLS, "row too wide: {s}");
        }
        for remaining in [1u32, PAIRING_WINDOW_S] {
            let row = pair_open_row(remaining);
            assert!(row.len() + 2 <= COLS, "open row too wide: {row}");
        }
        assert_eq!(pair_open_row(90).as_str(), "PAIRING OPEN 90S");
    }

    #[test]
    fn the_armed_row_names_the_key_that_commits() {
        // §337: a press that opens a security window is read, never
        // discovered. The resting row deliberately does not name a key — an
        // unarmed row commits nothing.
        assert!(PAIR_ROW_ARMED.contains("B1"));
        assert!(!PAIR_ROW.contains("B1"));
        assert!(PAIR_LEGEND_ARMED.contains("B1"));
        assert!(PAIR_LEGEND_ARMED.contains("B4"));
    }

    #[test]
    fn a_bond_survives_until_the_erase_generation_moves() {
        assert!(bond_is_live(0, 0));
        assert!(bond_is_live(7, 7));
        assert!(!bond_is_live(0, 1));
    }

    #[test]
    fn an_erased_bond_reads_as_unbonded_so_the_watch_pairs_freely_again() {
        // The erase's point is a watch that can be handed on. Once the stored
        // bond is dead, `may_bond` must see an unbonded device and admit a
        // new phone with no window — first-time setup, which is what a wiped
        // watch is.
        let live_after_erase = bond_is_live(3, 4);
        assert!(!live_after_erase);
        assert!(may_bond(live_after_erase, false));
    }

    #[test]
    fn a_bond_cell_serves_nothing_once_the_erase_generation_moves() {
        // The invariant the type exists to make unskippable: after an erase
        // the keys are still in RAM (the firmware never reboots), and every
        // reader must see them as gone.
        let cell: BondCell<u8> = BondCell::new();
        assert_eq!(cell.live(0), None, "a fresh cell holds nothing");
        cell.set(Some(42), 0);
        assert_eq!(cell.live(0), Some(42));
        assert!(cell.is_live(0));
        assert_eq!(cell.live(1), None, "an erase retires it");
        assert!(!cell.is_live(1));
    }

    #[test]
    fn a_bond_cell_re_pairs_into_the_current_generation() {
        // Setting stores the generation in the SAME write, so a re-pair after
        // an erase is live again — and erasable again in turn. A caller that
        // could set the peer without the generation is exactly the bug the
        // type removes.
        let cell: BondCell<u8> = BondCell::new();
        cell.set(Some(1), 0);
        assert_eq!(cell.live(3), None);
        cell.set(Some(2), 3);
        assert_eq!(cell.live(3), Some(2));
        assert_eq!(cell.live(4), None);
    }

    #[test]
    fn clearing_a_bond_cell_serves_nothing_at_any_generation() {
        let cell: BondCell<u8> = BondCell::new();
        cell.set(Some(9), 5);
        cell.set(None, 5);
        for gen in [0, 5, 6, u32::MAX] {
            assert_eq!(cell.live(gen), None);
        }
    }

    #[test]
    fn a_bond_cell_feeds_may_bond_the_same_answer_it_serves_keys_on() {
        // The two consumers must never disagree: if the keys are dead, the
        // watch must ALSO read as unbonded so first-time-setup pairing works
        // again — which is what makes an erase a usable hand-on.
        let cell: BondCell<u8> = BondCell::new();
        cell.set(Some(7), 2);
        assert!(
            !may_bond(cell.is_live(2), false),
            "a live bond is protected"
        );
        assert!(may_bond(cell.is_live(3), false), "an erased one is not");
    }

    #[test]
    fn re_pairing_after_an_erase_is_itself_erasable() {
        // A boolean "erased" flag would have to be cleared on re-pair, and a
        // missed clear would leave the next erase inert. The generation makes
        // that unrepresentable: the new bond records the CURRENT generation.
        let gen_after_first_erase = 1;
        assert!(bond_is_live(gen_after_first_erase, gen_after_first_erase));
        assert!(!bond_is_live(
            gen_after_first_erase,
            gen_after_first_erase + 1
        ));
    }
}
