//! Button-task flow decisions — the pure half of the press handling that
//! [`crate::button`]'s reducers don't already cover.
//!
//! The hardware task times a paging-key hold with an Embassy select and the
//! sim task polls pin levels, so the two arrive at a press class by different
//! mechanics. Everything downstream of "how long was it held" — what fires at
//! the hold threshold, what the grid cursor does, and where a dismissed run
//! leaves the view — lives here so the two task variants cannot drift from
//! each other or from the tests.
//!
//! The §350 timing rule is one sentence: a paging key's Hold action fires AT
//! [`crate::button::PAGE_HOLD_MS`] while the button is still down (the grid
//! opening / the re-zero banner is its own feedback), a release before the
//! threshold fires the Tap action, and a release after a threshold-fire is
//! inert. One boundary, no middle tier, no on-screen countdown needed.

use crate::button::{
    btn3_action, btn4_action, Btn3Action, Btn4Action, PageBtnPress, RecordCommand,
};
use crate::face::IdleView;
use crate::page::Page;
use crate::page_grid::PageGrid;
use crate::record::RecordState;
use crate::timers::TimerKey;

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

/// Which paging key a press arrived on. The two are spatial mirrors: Left is
/// the lower-left BTN3 (pages left), Right the lower-right BTN4 (pages right).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PagingKey {
    Left,
    Right,
}

/// What a paging key does outside the grid, resolved from the shared reducers
/// so the two task variants and the tests read one truth.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PagingAction {
    PagePrev,
    PageNext,
    OpenGrid,
    CycleGnssMode,
    QnhRezero,
    ToggleDiagnostics,
}

/// The action a `key` press of `press` tier takes in `state` — the one lookup
/// both task variants dispatch on, whether the tier came from a select timer
/// or a poll-measured duration.
pub fn paging_action(key: PagingKey, state: RecordState, press: PageBtnPress) -> PagingAction {
    match key {
        PagingKey::Left => match btn3_action(state, press) {
            Btn3Action::PagePrev => PagingAction::PagePrev,
            Btn3Action::OpenGrid => PagingAction::OpenGrid,
            Btn3Action::CycleGnssMode => PagingAction::CycleGnssMode,
            Btn3Action::QnhRezero => PagingAction::QnhRezero,
        },
        PagingKey::Right => match btn4_action(state, press) {
            Btn4Action::PageNext => PagingAction::PageNext,
            Btn4Action::OpenGrid => PagingAction::OpenGrid,
            Btn4Action::ToggleDiagnostics => PagingAction::ToggleDiagnostics,
        },
    }
}

/// The page a paging action lands on, walking the filtered cycle
/// (data-present ∩ curated) so a tap never lands on an empty glance. An
/// action that isn't a page walk leaves the page alone.
pub fn paged(page: Page, action: PagingAction, mask: u64) -> Page {
    match action {
        PagingAction::PageNext => page.next_in(mask),
        PagingAction::PagePrev => page.prev_in(mask),
        PagingAction::OpenGrid
        | PagingAction::CycleGnssMode
        | PagingAction::QnhRezero
        | PagingAction::ToggleDiagnostics => page,
    }
}

/// The cursor direction a paging key drives while the grid is open — the same
/// directions the keys page, so the modal never inverts the spatial mapping.
pub fn grid_cursor_key(key: PagingKey) -> GridCursorKey {
    match key {
        PagingKey::Left => GridCursorKey::Back,
        PagingKey::Right => GridCursorKey::Forward,
    }
}

/// Which timer-modal key a paging press is (§375). The lower-left DOWN slot
/// shortens the preset — the vertical pair carries the value axis here because
/// the modal shows one value and no list, the mirror of §351's rule that each
/// modal is spatially true to what it shows. The lower-right key exits, the §81
/// BACK slot where the settings menu already puts it.
pub fn timer_paging_key(key: PagingKey) -> TimerKey {
    match key {
        PagingKey::Left => TimerKey::Shorter,
        PagingKey::Right => TimerKey::Exit,
    }
}

/// Which direction an in-grid press drives the cursor.
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
pub fn grid_cursor_op(key: GridCursorKey, held_past_hold: bool) -> GridCursorOp {
    match (key, held_past_hold) {
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

/// The idle face BTN4 walks to (decisions §291, extended by §358).
///
/// A one-way cycle, not a toggle: the ICE card is a third face, and the key
/// has only one tier while idle (an idle gesture must never change meaning
/// mid-press — `btn4_action`). Home is one press from either of the other two,
/// which is the property that matters: a runner who lands somewhere they did
/// not mean to is never more than a press from the clock.
pub fn idle_view_toggled(view: IdleView) -> IdleView {
    match view {
        IdleView::Home => IdleView::Diagnostics,
        IdleView::Diagnostics => IdleView::Ice,
        IdleView::Ice => IdleView::Home,
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
        // A waypoint mark deliberately does NOT move the view: the runner is
        // holding BTN5 while reading some other page, and yanking them onto
        // the Waypoint page would cost a press to undo (and hide whatever
        // they were watching at the moment they marked).
        RecordCommand::Start
        | RecordCommand::Pause
        | RecordCommand::Resume
        | RecordCommand::Stop
        | RecordCommand::Lap
        | RecordCommand::MarkWaypoint => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::button::{classify_page_hold, PAGE_HOLD_MS};

    #[test]
    fn edges_fire_once_per_transition() {
        assert_eq!(edge(false, true), Some(Edge::Press));
        assert_eq!(edge(true, false), Some(Edge::Release));
        assert_eq!(edge(false, false), None);
        assert_eq!(edge(true, true), None);
    }

    #[test]
    fn the_paging_keys_mirror_in_every_run_view() {
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(
                paging_action(PagingKey::Left, state, PageBtnPress::Tap),
                PagingAction::PagePrev
            );
            assert_eq!(
                paging_action(PagingKey::Right, state, PageBtnPress::Tap),
                PagingAction::PageNext
            );
            // Either key held opens the same grid.
            assert_eq!(
                paging_action(PagingKey::Left, state, PageBtnPress::Hold),
                PagingAction::OpenGrid
            );
            assert_eq!(
                paging_action(PagingKey::Right, state, PageBtnPress::Hold),
                PagingAction::OpenGrid
            );
        }
    }

    #[test]
    fn idle_keeps_its_own_meanings_on_both_keys() {
        assert_eq!(
            paging_action(PagingKey::Left, RecordState::Idle, PageBtnPress::Tap),
            PagingAction::CycleGnssMode
        );
        assert_eq!(
            paging_action(PagingKey::Left, RecordState::Idle, PageBtnPress::Hold),
            PagingAction::QnhRezero
        );
        // Duration-stable: an idle BTN4 gesture is the diagnostics toggle
        // whatever its length.
        assert_eq!(
            paging_action(PagingKey::Right, RecordState::Idle, PageBtnPress::Tap),
            PagingAction::ToggleDiagnostics
        );
        assert_eq!(
            paging_action(PagingKey::Right, RecordState::Idle, PageBtnPress::Hold),
            PagingAction::ToggleDiagnostics
        );
    }

    #[test]
    fn the_release_classification_matches_the_threshold() {
        assert_eq!(classify_page_hold(PAGE_HOLD_MS - 1), PageBtnPress::Tap);
        assert_eq!(classify_page_hold(PAGE_HOLD_MS), PageBtnPress::Hold);
    }

    #[test]
    fn the_timer_modal_puts_exit_where_the_settings_menu_does() {
        // §337's rule is about surprises: the grid's BTN2-exit is already one
        // remap a runner has to read. A second modal exiting on a third key
        // would be another, so the timer takes the settings menu's BACK slot.
        assert_eq!(timer_paging_key(PagingKey::Right), TimerKey::Exit);
        assert_eq!(timer_paging_key(PagingKey::Left), TimerKey::Shorter);
    }

    #[test]
    fn the_grid_cursor_moves_the_way_the_key_pages() {
        assert_eq!(grid_cursor_key(PagingKey::Left), GridCursorKey::Back);
        assert_eq!(grid_cursor_key(PagingKey::Right), GridCursorKey::Forward);
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
        assert_eq!(
            paged(page, PagingAction::PageNext, mask),
            page.next_in(mask)
        );
        assert_eq!(
            paged(page, PagingAction::PagePrev, mask),
            page.prev_in(mask)
        );
        for action in [
            PagingAction::OpenGrid,
            PagingAction::CycleGnssMode,
            PagingAction::QnhRezero,
            PagingAction::ToggleDiagnostics,
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
            page = paged(page, PagingAction::PageNext, mask);
            seen += 1;
            if page == Page::default() {
                break;
            }
            assert!(seen < 128, "the forward cycle never returned home");
        }
        // A full walk backward returns home in exactly as many presses.
        for _ in 0..seen {
            page = paged(page, PagingAction::PagePrev, mask);
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
            page = paged(page, PagingAction::PageNext, mask);
            assert!(page == Page::Dashboard || page == Page::Pace, "{page:?}");
        }
        for _ in 0..8 {
            page = paged(page, PagingAction::PagePrev, mask);
            assert!(page == Page::Dashboard || page == Page::Pace, "{page:?}");
        }
    }

    #[test]
    fn the_page_walk_direction_matches_the_key_that_produced_it() {
        // A left-key tap must land on the previous page and a right-key tap on
        // the next, in every run-view state — or the spatial mapping lies.
        let mask = u64::MAX;
        let page = Page::default();
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(
                paged(
                    page,
                    paging_action(PagingKey::Left, state, PageBtnPress::Tap),
                    mask
                ),
                page.prev_in(mask)
            );
            assert_eq!(
                paged(
                    page,
                    paging_action(PagingKey::Right, state, PageBtnPress::Tap),
                    mask
                ),
                page.next_in(mask)
            );
        }
    }

    #[test]
    fn btn4_walks_the_three_idle_faces_and_returns_home() {
        assert_eq!(idle_view_toggled(IdleView::Home), IdleView::Diagnostics);
        assert_eq!(idle_view_toggled(IdleView::Diagnostics), IdleView::Ice);
        assert_eq!(idle_view_toggled(IdleView::Ice), IdleView::Home);
        // The property that matters on a one-way cycle: home is never more
        // than the cycle away, and the walk visits every face exactly once.
        let mut v = IdleView::Home;
        let mut seen = [v; 3];
        for slot in seen.iter_mut().skip(1) {
            v = idle_view_toggled(v);
            *slot = v;
        }
        assert_eq!(seen, [IdleView::Home, IdleView::Diagnostics, IdleView::Ice]);
        assert_eq!(idle_view_toggled(v), IdleView::Home);
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
