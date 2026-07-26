//! Button-task flow decisions — the pure half of the press handling that
//! [`crate::button`]'s reducers don't already cover.
//!
//! The hardware task times a BTN3 hold with nested Embassy selects and the sim
//! task polls pin levels, so the two arrive at a press class by different
//! mechanics. Everything downstream of "how long was it held" — how a hold
//! resolves tier by tier, what the grid cursor does, which page a press lands
//! on, and where a dismissed run leaves the view — lives here so the two task
//! variants cannot drift from each other or from the tests.

use crate::button::{
    btn3_action, Btn3Action, Btn3Press, RecordCommand, BTN3_GRID_HOLD_MS, BTN3_LONG_PRESS_MS,
};
use crate::face::IdleView;
use crate::page::Page;
use crate::page_grid::PageGrid;
use crate::record::RecordState;

/// A level transition on an active-low button pin: a press pulls the line low.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Edge {
    Press,
    Release,
}

/// The edge between two sampled pin levels — the sim task's software edge
/// detection, where Renode's GPIO model offers no SENSE/DETECT event.
pub fn edge(was_pressed: bool, now_pressed: bool) -> Option<Edge> {
    match (was_pressed, now_pressed) {
        (false, true) => Some(Edge::Press),
        (true, false) => Some(Edge::Release),
        _ => None,
    }
}

/// The second timing leg the hardware task waits out after the long-press
/// threshold has already elapsed.
pub const BTN3_GRID_LEG_MS: u32 = BTN3_GRID_HOLD_MS - BTN3_LONG_PRESS_MS;

/// Where a BTN3 hold stands once the long-press threshold has elapsed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3Stage {
    Resolved(Btn3Press),
    /// Still held on a surface that has a third tier — keep timing towards the
    /// grid threshold.
    AwaitGridHold,
}

/// Classify a BTN3 hold at the long-press threshold. The idle face has only two
/// tiers (a hold of any length is the QNH re-zero), so it resolves here
/// regardless of the pin; a run view has three, so a still-held button carries
/// on towards the grid.
///
/// `still_held` is the pin level read after the threshold timer won: the timer
/// arm drops the losing edge future, so a release landing in the re-arm gap
/// would otherwise go unseen and stretch the classification a whole tier.
pub fn btn3_after_long_press(state: RecordState, still_held: bool) -> Btn3Stage {
    if state == RecordState::Idle || !still_held {
        Btn3Stage::Resolved(Btn3Press::Long)
    } else {
        Btn3Stage::AwaitGridHold
    }
}

/// Classify a BTN3 hold at the grid threshold — the same lost-release level
/// check as [`btn3_after_long_press`], one tier up.
pub fn btn3_after_grid_hold(still_held: bool) -> Btn3Press {
    if still_held {
        Btn3Press::GridHold
    } else {
        Btn3Press::Long
    }
}

/// A BTN3 action that fires while the button is still held — the press tier
/// whose feedback IS the screen changing under the thumb.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3HoldFire {
    GridRowDown,
    OpenGrid,
}

/// What a BTN3 hold of `held_ms` fires without waiting for its release: inside
/// the grid a long-press drops a whole row, and on a run view a full hold opens
/// the grid. The idle face fires nothing mid-press — its hold stays the re-zero,
/// resolved on release, so duration never changes an idle gesture mid-motion.
pub fn btn3_hold_fire(grid_open: bool, state: RecordState, held_ms: u32) -> Option<Btn3HoldFire> {
    if grid_open {
        (held_ms >= BTN3_LONG_PRESS_MS).then_some(Btn3HoldFire::GridRowDown)
    } else if held_ms >= BTN3_GRID_HOLD_MS
        && btn3_action(state, Btn3Press::GridHold) == Btn3Action::OpenGrid
    {
        Some(Btn3HoldFire::OpenGrid)
    } else {
        None
    }
}

/// Which direction an in-grid press drives the cursor: BTN3 forward, BTN1 back
/// (Garmin's up/down idiom).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GridCursorKey {
    Forward,
    Back,
}

/// One step of the page-grid cursor.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GridCursorOp {
    Tap,
    RowDown,
    Back,
    RowUp,
}

/// A tap steps one cell, a hold jumps a whole grid row — the long jump — in
/// whichever direction the key drives.
pub fn grid_cursor_op(key: GridCursorKey, held_past_long: bool) -> GridCursorOp {
    match (key, held_past_long) {
        (GridCursorKey::Forward, false) => GridCursorOp::Tap,
        (GridCursorKey::Forward, true) => GridCursorOp::RowDown,
        (GridCursorKey::Back, false) => GridCursorOp::Back,
        (GridCursorKey::Back, true) => GridCursorOp::RowUp,
    }
}

impl GridCursorOp {
    pub fn apply(self, grid: &mut PageGrid, mask: u64) {
        match self {
            GridCursorOp::Tap => grid.tap(mask),
            GridCursorOp::RowDown => grid.row_down(mask),
            GridCursorOp::Back => grid.back(mask),
            GridCursorOp::RowUp => grid.row_up(mask),
        }
    }
}

/// The page a BTN3 press lands on, walking the filtered cycle (data-present and
/// curated) so a press never lands on an empty glance. An action that isn't a
/// page walk leaves the page alone.
pub fn paged(page: Page, action: Btn3Action, mask: u64) -> Page {
    match action {
        Btn3Action::PageNext => page.next_in(mask),
        Btn3Action::PagePrev => page.prev_in(mask),
        Btn3Action::OpenGrid | Btn3Action::CycleGnssMode | Btn3Action::QnhRezero => page,
    }
}

/// The idle face BTN4 toggles to (decisions §291).
pub fn idle_view_toggled(view: IdleView) -> IdleView {
    match view {
        IdleView::Home => IdleView::Diagnostics,
        IdleView::Diagnostics => IdleView::Home,
    }
}

/// Where a recorder command leaves the view.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ViewLanding {
    pub page: Page,
    pub idle_view: IdleView,
}

/// The view a completed command lands on, or `None` when the command leaves the
/// view where it was. Dismissing a finished run goes home: the next run opens on
/// the Dashboard — not on whatever page the last one was parked on — and on the
/// home clock, not wherever a pre-run diagnostics toggle left the idle face.
pub fn landing_after(cmd: RecordCommand) -> Option<ViewLanding> {
    match cmd {
        RecordCommand::Reset => Some(ViewLanding {
            page: Page::default(),
            idle_view: IdleView::Home,
        }),
        RecordCommand::Start
        | RecordCommand::Pause
        | RecordCommand::Resume
        | RecordCommand::Stop
        | RecordCommand::Lap => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::button::classify_btn3_hold;

    #[test]
    fn edges_fire_once_per_transition() {
        assert_eq!(edge(false, true), Some(Edge::Press));
        assert_eq!(edge(true, false), Some(Edge::Release));
        assert_eq!(edge(false, false), None);
        assert_eq!(edge(true, true), None);
    }

    #[test]
    fn an_idle_hold_resolves_at_the_long_threshold_whatever_the_pin_says() {
        // Two tiers only: the trailhead re-zero is one motion regardless of how
        // long it is held, so a still-held idle button must not start timing a
        // third tier.
        assert_eq!(
            btn3_after_long_press(RecordState::Idle, true),
            Btn3Stage::Resolved(Btn3Press::Long)
        );
        assert_eq!(
            btn3_after_long_press(RecordState::Idle, false),
            Btn3Stage::Resolved(Btn3Press::Long)
        );
    }

    #[test]
    fn a_run_view_hold_carries_on_to_the_grid_tier_only_while_held() {
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(btn3_after_long_press(state, true), Btn3Stage::AwaitGridHold);
            // A release lost in the re-arm gap is classified by the pin, not by
            // the timer that won — otherwise it would stretch a page-back into
            // a grid open.
            assert_eq!(
                btn3_after_long_press(state, false),
                Btn3Stage::Resolved(Btn3Press::Long)
            );
        }
    }

    #[test]
    fn the_grid_tier_needs_the_button_still_down() {
        assert_eq!(btn3_after_grid_hold(true), Btn3Press::GridHold);
        assert_eq!(btn3_after_grid_hold(false), Btn3Press::Long);
    }

    #[test]
    fn the_timed_tiers_agree_with_the_duration_classification() {
        // The hardware task's select tiers and the sim task's duration
        // classification must land on the same press class for the same hold.
        for held_ms in [
            0,
            BTN3_LONG_PRESS_MS - 1,
            BTN3_LONG_PRESS_MS,
            BTN3_GRID_HOLD_MS - 1,
            BTN3_GRID_HOLD_MS,
            u32::MAX,
        ] {
            let by_duration = classify_btn3_hold(held_ms);
            let timed = if held_ms < BTN3_LONG_PRESS_MS {
                Btn3Press::Short
            } else {
                match btn3_after_long_press(RecordState::Recording, true) {
                    Btn3Stage::Resolved(p) => p,
                    Btn3Stage::AwaitGridHold => btn3_after_grid_hold(held_ms >= BTN3_GRID_HOLD_MS),
                }
            };
            assert_eq!(timed, by_duration, "held {held_ms}ms");
        }
        assert_eq!(BTN3_GRID_LEG_MS, BTN3_GRID_HOLD_MS - BTN3_LONG_PRESS_MS);
    }

    #[test]
    fn a_hold_fires_a_grid_row_inside_the_grid_and_the_grid_itself_on_a_run() {
        assert_eq!(
            btn3_hold_fire(true, RecordState::Recording, BTN3_LONG_PRESS_MS),
            Some(Btn3HoldFire::GridRowDown)
        );
        assert_eq!(
            btn3_hold_fire(true, RecordState::Recording, BTN3_LONG_PRESS_MS - 1),
            None
        );
        assert_eq!(
            btn3_hold_fire(false, RecordState::Recording, BTN3_GRID_HOLD_MS),
            Some(Btn3HoldFire::OpenGrid)
        );
        assert_eq!(
            btn3_hold_fire(false, RecordState::Recording, BTN3_GRID_HOLD_MS - 1),
            None
        );
    }

    #[test]
    fn an_idle_hold_fires_nothing_mid_press() {
        // The idle face has no pages and therefore no grid: its hold resolves on
        // release as the re-zero.
        assert_eq!(
            btn3_hold_fire(false, RecordState::Idle, BTN3_GRID_HOLD_MS),
            None
        );
        assert_eq!(btn3_hold_fire(false, RecordState::Idle, u32::MAX), None);
        // A grid can't be open while idle, but if one somehow were, the cursor
        // still belongs to the grid.
        assert_eq!(
            btn3_hold_fire(true, RecordState::Idle, BTN3_GRID_HOLD_MS),
            Some(Btn3HoldFire::GridRowDown)
        );
    }

    #[test]
    fn the_grid_cursor_steps_a_cell_on_a_tap_and_a_row_on_a_hold() {
        assert_eq!(
            grid_cursor_op(GridCursorKey::Forward, false),
            GridCursorOp::Tap
        );
        assert_eq!(
            grid_cursor_op(GridCursorKey::Forward, true),
            GridCursorOp::RowDown
        );
        assert_eq!(
            grid_cursor_op(GridCursorKey::Back, false),
            GridCursorOp::Back
        );
        assert_eq!(
            grid_cursor_op(GridCursorKey::Back, true),
            GridCursorOp::RowUp
        );
    }

    #[test]
    fn cursor_ops_drive_the_grid_and_the_two_directions_mirror() {
        let mask = u64::MAX;
        let mut grid = PageGrid::open(Page::default(), mask);
        let opened_at = grid.cursor();
        grid_cursor_op(GridCursorKey::Forward, false).apply(&mut grid, mask);
        let after_tap = grid.cursor();
        assert_ne!(after_tap, opened_at);
        grid_cursor_op(GridCursorKey::Back, false).apply(&mut grid, mask);
        assert_eq!(grid.cursor(), opened_at);
        grid_cursor_op(GridCursorKey::Forward, true).apply(&mut grid, mask);
        let after_row = grid.cursor();
        assert_ne!(after_row, opened_at);
        grid_cursor_op(GridCursorKey::Back, true).apply(&mut grid, mask);
        assert_eq!(grid.cursor(), opened_at);
    }

    #[test]
    fn a_page_walk_follows_the_action_and_nothing_else_moves_the_page() {
        let mask = u64::MAX;
        let page = Page::default();
        assert_eq!(paged(page, Btn3Action::PageNext, mask), page.next_in(mask));
        assert_eq!(paged(page, Btn3Action::PagePrev, mask), page.prev_in(mask));
        for action in [
            Btn3Action::OpenGrid,
            Btn3Action::CycleGnssMode,
            Btn3Action::QnhRezero,
        ] {
            assert_eq!(paged(page, action, mask), page);
        }
    }

    #[test]
    fn a_page_walk_wraps_the_cycle_in_both_directions() {
        let mask = u64::MAX;
        let mut page = Page::default();
        let mut seen = 0usize;
        loop {
            page = paged(page, Btn3Action::PageNext, mask);
            seen += 1;
            if page == Page::default() {
                break;
            }
            assert!(seen < 128, "the forward cycle never returned home");
        }
        // A full walk backward returns home in exactly as many presses.
        for _ in 0..seen {
            page = paged(page, Btn3Action::PagePrev, mask);
        }
        assert_eq!(page, Page::default());
    }

    #[test]
    fn a_masked_out_page_is_never_landed_on() {
        // Only the Dashboard and one glance page are present: the walk bounces
        // between exactly those two rather than stepping onto an empty glance.
        let mask = Page::Dashboard.bit() | Page::Pace.bit();
        let mut page = Page::default();
        for _ in 0..8 {
            page = paged(page, Btn3Action::PageNext, mask);
            assert!(page == Page::Dashboard || page == Page::Pace, "{page:?}");
        }
        for _ in 0..8 {
            page = paged(page, Btn3Action::PagePrev, mask);
            assert!(page == Page::Dashboard || page == Page::Pace, "{page:?}");
        }
    }

    #[test]
    fn the_page_walk_direction_matches_the_press_that_produced_it() {
        // The task derives the action from the press; the two must agree for
        // every run-view state, or a long press would page the wrong way.
        let mask = u64::MAX;
        let page = Page::default();
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(
                paged(page, btn3_action(state, Btn3Press::Short), mask),
                page.next_in(mask)
            );
            assert_eq!(
                paged(page, btn3_action(state, Btn3Press::Long), mask),
                page.prev_in(mask)
            );
        }
    }

    #[test]
    fn btn4_toggles_the_idle_face_both_ways() {
        assert_eq!(idle_view_toggled(IdleView::Home), IdleView::Diagnostics);
        assert_eq!(idle_view_toggled(IdleView::Diagnostics), IdleView::Home);
    }

    #[test]
    fn only_a_dismissed_run_resets_the_view() {
        assert_eq!(
            landing_after(RecordCommand::Reset),
            Some(ViewLanding {
                page: Page::Dashboard,
                idle_view: IdleView::Home,
            })
        );
        assert_eq!(Page::default(), Page::Dashboard);
        for cmd in [
            RecordCommand::Start,
            RecordCommand::Pause,
            RecordCommand::Resume,
            RecordCommand::Stop,
            RecordCommand::Lap,
        ] {
            assert_eq!(landing_after(cmd), None);
        }
    }
}
