//! Button → recording-command decision — the pure half of the button task.
//!
//! The `app/` button task owns only the hardware it can't test on the host:
//! edge detection and debounce. *Which* command a press should issue, given
//! the run's current state, is this pure reducer — host-tested here, exactly
//! like [`crate::record`] holds the state machine the record task drives.

use crate::record::RecordState;

/// A control command for the recording state machine, produced by a button
/// press and consumed by the record task. One variant per [`crate::record`]
/// method: `start` / `pause` / `resume` / `stop` / `lap` / `reset`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RecordCommand {
    Start,
    Pause,
    Resume,
    Stop,
    Lap,
    Reset,
}

/// The physical buttons wired to recording control on the nRF52840 DK.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Button {
    /// BTN1 — a context-sensitive start / pause / resume toggle.
    Primary,
    /// BTN2 — stop.
    Stop,
    /// BTN4 — manual lap, standing in for the Garmin Fenix layout's
    /// lower-right Lap/Back button (decisions.md § 81).
    Lap,
}

/// Map a button press, given the current recorder state, to the command it
/// should issue — or `None` when the press is a no-op in that state.
///
/// BTN1 is a single context toggle: it starts an idle run, pauses a running
/// one, resumes a paused one, and dismisses a finished one back to the idle
/// face (the stored run was committed at stop, so the dismissal is view-only
/// — without it `Finished` was a dead end that held the run view until
/// reboot). BTN2 stops whenever a run is in progress. BTN4 closes the current
/// lap whenever a run is in progress; both stay inert once finished.
///
/// The state comes from the published [`crate::record::Snapshot`], which does
/// not distinguish a manual pause from a speed-derived auto-pause — so a
/// `Primary` press during an auto-pause maps to `Resume`, which the recorder
/// treats as inert (an auto-pause only resumes from the next moving fix). That
/// is the intended, safe behaviour: a physical press never corrupts the run.
pub fn command_for(button: Button, state: RecordState) -> Option<RecordCommand> {
    match (button, state) {
        (Button::Primary, RecordState::Idle) => Some(RecordCommand::Start),
        (Button::Primary, RecordState::Recording) => Some(RecordCommand::Pause),
        (Button::Primary, RecordState::Paused) => Some(RecordCommand::Resume),
        (Button::Primary, RecordState::Finished) => Some(RecordCommand::Reset),
        (Button::Stop, RecordState::Recording | RecordState::Paused) => Some(RecordCommand::Stop),
        (Button::Lap, RecordState::Recording | RecordState::Paused) => Some(RecordCommand::Lap),
        _ => None,
    }
}

/// How long BTN3 was held, classified by the app's button task: a tap
/// released before the long-press threshold, a long press released between
/// the two thresholds, or a hold carried past the grid threshold (which fires
/// while still held — the page grid opening IS the feedback that the hold
/// registered).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3Press {
    Short,
    Long,
    GridHold,
}

/// The BTN3 press-class thresholds, in milliseconds of hold. The app's button
/// task owns the timing mechanics (hardware: nested selects; sim: level
/// polling) but the boundaries live here, host-tested, so the two task
/// variants and the tests can't drift.
pub const BTN3_LONG_PRESS_MS: u32 = 500;
pub const BTN3_GRID_HOLD_MS: u32 = 1500;
// The hardware task times the grid tier as a second select leg of
// (GRID_HOLD - LONG_PRESS); reordering the constants would underflow it.
const _: () = assert!(BTN3_GRID_HOLD_MS > BTN3_LONG_PRESS_MS);

/// Classify a completed BTN3 hold by its duration — the release-path
/// classification the sim button task applies verbatim (the hardware task
/// reproduces the same boundaries with select timers).
pub fn classify_btn3_hold(held_ms: u32) -> Btn3Press {
    if held_ms >= BTN3_GRID_HOLD_MS {
        Btn3Press::GridHold
    } else if held_ms >= BTN3_LONG_PRESS_MS {
        Btn3Press::Long
    } else {
        Btn3Press::Short
    }
}

/// What a BTN3 press does, given the run state and how long it was held. The
/// run-view pages only exist once a run is under way (the idle status face
/// ignores the page entirely — see [`crate::face`]), so while idle the
/// otherwise-dead page button doubles as the GNSS-mode selector and its
/// long-press as the manual QNH re-zero, keeping both surfaces inside
/// decisions §81's five-button, no-chord budget. Any non-idle state
/// (recording, paused, finished — all of which show a run view) keeps BTN3 on
/// pages — short forward, long backward, and a hold past the long-press opens
/// the [`crate::page_grid`] overview — which also freezes the GNSS mode (and
/// parks the re-zero) for the duration of a run: mid-run the elevation
/// complementary filter auto-corrects drift, so the manual snap is an idle
/// (trailhead) affordance and a run's recording controls stay untouched. The
/// idle face has no pages and therefore no grid: a hold there stays the
/// re-zero, so the trailhead gesture is one motion regardless of duration.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3Action {
    PageNext,
    PagePrev,
    OpenGrid,
    CycleGnssMode,
    QnhRezero,
}

pub fn btn3_action(state: RecordState, press: Btn3Press) -> Btn3Action {
    match (state, press) {
        (RecordState::Idle, Btn3Press::Short) => Btn3Action::CycleGnssMode,
        (RecordState::Idle, _) => Btn3Action::QnhRezero,
        (_, Btn3Press::Short) => Btn3Action::PageNext,
        (_, Btn3Press::Long) => Btn3Action::PagePrev,
        (_, Btn3Press::GridHold) => Btn3Action::OpenGrid,
    }
}

/// What a non-BTN3 press does while the page grid is open: BTN4 confirms the
/// jump, BTN1 drives the cursor backward (tap = one cell, hold = one row up —
/// the symmetric mirror of BTN3, Garmin's up/down idiom), BTN2 cancels. Every
/// one of them is swallowed — a press inside a navigation modal must never
/// reach the recorder, so the picker can't pause, stop-arm, or lap a run by
/// accident.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GridPress {
    Select,
    Cancel,
    CursorBack,
}

pub fn grid_press(button: Button) -> GridPress {
    match button {
        Button::Lap => GridPress::Select,
        Button::Primary => GridPress::CursorBack,
        Button::Stop => GridPress::Cancel,
    }
}

/// How long an armed stop stays armed. A first BTN2 press only *arms* the stop;
/// a second press within this window confirms it. A single stray press expires
/// harmlessly after this many seconds.
pub const STOP_CONFIRM_WINDOW_S: u32 = 4;

/// The 2x banner the face shows while a stop is armed. Without it the first
/// BTN2 press is invisible — a runner meaning to stop reads the silence as a
/// dead button, and a runner who brushed BTN2 never learns the next brush
/// would end the run.
pub const STOP_ARMED_BANNER: &str = "STOP? BTN2";

/// Whether an arm stamped at `armed_at_s` still awaits its confirm — the
/// face's banner window, sharing [`STOP_CONFIRM_WINDOW_S`] with the guard so
/// the prompt can never outlive (or undercut) the press that would confirm.
pub fn stop_arm_pending(armed_at_s: u32, now_s: u32) -> bool {
    now_s.saturating_sub(armed_at_s) <= STOP_CONFIRM_WINDOW_S
}

/// The outcome of feeding a BTN2 press to the [`StopGuard`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum StopPress {
    /// The press armed the guard — nothing stops yet. The runner must press
    /// BTN2 again within [`STOP_CONFIRM_WINDOW_S`] to actually stop.
    Armed,
    /// A second press inside the confirm window — the run should stop now.
    Confirmed,
    /// BTN2 is a no-op in this state (idle / finished); the guard is disarmed.
    Inert,
}

/// Guards the terminal `Stop` behind a deliberate double-press so one cold or
/// gloved mis-press can't end a multi-hour recording.
///
/// `Stop` is irreversible — a finished run parks every button and cannot resume
/// ([`command_for`] is inert once `Finished`). So rather than let a single BTN2
/// press stop, the first press *arms* the guard (a no-op the runner sees didn't
/// stop) and only a second press within [`STOP_CONFIRM_WINDOW_S`] confirms it.
/// A single accidental brush expires on its own. This is the lowest-friction
/// guard that stays inside the five-button, no-chord budget (decisions §81) —
/// no long-hold timing, no chord, no extra button — and it never touches the
/// recorder until the runner confirms, so the run data is preserved exactly as
/// before.
///
/// The state lives here (host-tested) rather than in the app's button task; the
/// task supplies only the current [`RecordState`] and a monotonic `now_s`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StopGuard {
    armed_at_s: Option<u32>,
}

impl StopGuard {
    pub const fn new() -> Self {
        Self { armed_at_s: None }
    }

    /// Feed a BTN2 press. `state` is the latest published recorder state and
    /// `now_s` a monotonic seconds counter (the app passes uptime seconds).
    pub fn press(&mut self, state: RecordState, now_s: u32) -> StopPress {
        // BTN2 does nothing unless a run is in progress; a press in any other
        // state disarms so a later run can't inherit a stale arm.
        if command_for(Button::Stop, state).is_none() {
            self.armed_at_s = None;
            return StopPress::Inert;
        }
        match self.armed_at_s {
            Some(armed) if now_s.saturating_sub(armed) <= STOP_CONFIRM_WINDOW_S => {
                self.armed_at_s = None;
                StopPress::Confirmed
            }
            // First press, or a press after the window lapsed — (re)arm.
            _ => {
                self.armed_at_s = Some(now_s);
                StopPress::Armed
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primary_is_a_start_pause_resume_dismiss_toggle() {
        assert_eq!(
            command_for(Button::Primary, RecordState::Idle),
            Some(RecordCommand::Start)
        );
        assert_eq!(
            command_for(Button::Primary, RecordState::Recording),
            Some(RecordCommand::Pause)
        );
        assert_eq!(
            command_for(Button::Primary, RecordState::Paused),
            Some(RecordCommand::Resume)
        );
        assert_eq!(
            command_for(Button::Primary, RecordState::Finished),
            Some(RecordCommand::Reset)
        );
    }

    #[test]
    fn stop_only_acts_while_a_run_is_in_progress() {
        assert_eq!(
            command_for(Button::Stop, RecordState::Recording),
            Some(RecordCommand::Stop)
        );
        assert_eq!(
            command_for(Button::Stop, RecordState::Paused),
            Some(RecordCommand::Stop)
        );
        assert_eq!(command_for(Button::Stop, RecordState::Idle), None);
        assert_eq!(command_for(Button::Stop, RecordState::Finished), None);
    }

    #[test]
    fn lap_only_acts_while_a_run_is_in_progress() {
        assert_eq!(
            command_for(Button::Lap, RecordState::Recording),
            Some(RecordCommand::Lap)
        );
        assert_eq!(
            command_for(Button::Lap, RecordState::Paused),
            Some(RecordCommand::Lap)
        );
        assert_eq!(command_for(Button::Lap, RecordState::Idle), None);
        assert_eq!(command_for(Button::Lap, RecordState::Finished), None);
    }

    #[test]
    fn btn3_cycles_gnss_mode_only_while_idle() {
        assert_eq!(
            btn3_action(RecordState::Idle, Btn3Press::Short),
            Btn3Action::CycleGnssMode
        );
        // Every run-view state keeps BTN3 on pages — a mid-run (or post-run)
        // press must never silently change the GNSS mode.
        assert_eq!(
            btn3_action(RecordState::Recording, Btn3Press::Short),
            Btn3Action::PageNext
        );
        assert_eq!(
            btn3_action(RecordState::Paused, Btn3Press::Short),
            Btn3Action::PageNext
        );
        assert_eq!(
            btn3_action(RecordState::Finished, Btn3Press::Short),
            Btn3Action::PageNext
        );
    }

    #[test]
    fn btn3_long_press_is_rezero_while_idle_and_page_back_in_a_run() {
        assert_eq!(
            btn3_action(RecordState::Idle, Btn3Press::Long),
            Btn3Action::QnhRezero
        );
        // Every run-view state keeps the long-press on the reverse page walk —
        // a mid-run hold must never re-zero the altitude reference out from
        // under a recording. §286's safety contract stands: Back-to-start
        // stays exactly one long-press from home.
        assert_eq!(
            btn3_action(RecordState::Recording, Btn3Press::Long),
            Btn3Action::PagePrev
        );
        assert_eq!(
            btn3_action(RecordState::Paused, Btn3Press::Long),
            Btn3Action::PagePrev
        );
        assert_eq!(
            btn3_action(RecordState::Finished, Btn3Press::Long),
            Btn3Action::PagePrev
        );
    }

    #[test]
    fn btn3_grid_hold_opens_the_grid_in_a_run_and_stays_rezero_while_idle() {
        // The idle face has no pages, so a hold of any length stays the
        // trailhead re-zero — duration must never change what an idle hold
        // does mid-gesture.
        assert_eq!(
            btn3_action(RecordState::Idle, Btn3Press::GridHold),
            Btn3Action::QnhRezero
        );
        assert_eq!(
            btn3_action(RecordState::Recording, Btn3Press::GridHold),
            Btn3Action::OpenGrid
        );
        assert_eq!(
            btn3_action(RecordState::Paused, Btn3Press::GridHold),
            Btn3Action::OpenGrid
        );
        assert_eq!(
            btn3_action(RecordState::Finished, Btn3Press::GridHold),
            Btn3Action::OpenGrid
        );
    }

    #[test]
    fn grid_swallows_every_button_select_back_and_cancel() {
        assert_eq!(grid_press(Button::Lap), GridPress::Select);
        assert_eq!(grid_press(Button::Primary), GridPress::CursorBack);
        assert_eq!(grid_press(Button::Stop), GridPress::Cancel);
    }

    #[test]
    fn stop_armed_banner_fits_the_hero_band_and_tracks_the_guard_window() {
        // 2x glyphs are two cells wide; the banner must fit the 21-cell grid.
        assert!(STOP_ARMED_BANNER.chars().count() * 2 <= crate::face::COLS);
        assert!(stop_arm_pending(10, 10));
        assert!(stop_arm_pending(10, 10 + STOP_CONFIRM_WINDOW_S));
        assert!(!stop_arm_pending(10, 11 + STOP_CONFIRM_WINDOW_S));
        // Clock skew (a stamp from the future) reads as pending, not as a
        // wrapped-around expiry.
        assert!(stop_arm_pending(10, 9));
    }

    #[test]
    fn hold_classification_boundaries_are_inclusive_at_each_threshold() {
        assert_eq!(classify_btn3_hold(0), Btn3Press::Short);
        assert_eq!(classify_btn3_hold(BTN3_LONG_PRESS_MS - 1), Btn3Press::Short);
        assert_eq!(classify_btn3_hold(BTN3_LONG_PRESS_MS), Btn3Press::Long);
        assert_eq!(classify_btn3_hold(BTN3_GRID_HOLD_MS - 1), Btn3Press::Long);
        assert_eq!(classify_btn3_hold(BTN3_GRID_HOLD_MS), Btn3Press::GridHold);
        assert_eq!(classify_btn3_hold(u32::MAX), Btn3Press::GridHold);
    }

    #[test]
    fn only_the_dismiss_survives_a_finished_run() {
        // Stop and lap park once finished; BTN1 stays live as the way home.
        assert_eq!(
            command_for(Button::Primary, RecordState::Finished),
            Some(RecordCommand::Reset)
        );
        assert_eq!(command_for(Button::Stop, RecordState::Finished), None);
        assert_eq!(command_for(Button::Lap, RecordState::Finished), None);
    }

    #[test]
    fn stop_needs_two_presses_within_the_window() {
        let mut g = StopGuard::new();
        // First press only arms — the run is untouched.
        assert_eq!(g.press(RecordState::Recording, 0), StopPress::Armed);
        // A second press inside the window confirms.
        assert_eq!(g.press(RecordState::Recording, 2), StopPress::Confirmed);
        // After a confirm the guard is disarmed again — the next press re-arms.
        assert_eq!(g.press(RecordState::Recording, 3), StopPress::Armed);
    }

    #[test]
    fn a_single_stray_press_expires_without_stopping() {
        let mut g = StopGuard::new();
        assert_eq!(g.press(RecordState::Recording, 0), StopPress::Armed);
        // A second press only past the window re-arms rather than confirming —
        // the stray first press never stopped the run.
        assert_eq!(
            g.press(RecordState::Recording, STOP_CONFIRM_WINDOW_S + 1),
            StopPress::Armed
        );
        // Confirming still needs a further prompt press inside the window.
        assert_eq!(
            g.press(RecordState::Recording, STOP_CONFIRM_WINDOW_S + 2),
            StopPress::Confirmed
        );
    }

    #[test]
    fn confirm_works_from_paused_and_across_pause() {
        let mut g = StopGuard::new();
        // Arming while recording then confirming while paused is a valid stop —
        // command_for allows Stop from both.
        assert_eq!(g.press(RecordState::Recording, 0), StopPress::Armed);
        assert_eq!(g.press(RecordState::Paused, 1), StopPress::Confirmed);
    }

    #[test]
    fn press_is_inert_and_disarms_when_no_run_is_in_progress() {
        let mut g = StopGuard::new();
        assert_eq!(g.press(RecordState::Idle, 0), StopPress::Inert);
        assert_eq!(g.press(RecordState::Finished, 0), StopPress::Inert);
        // An arm that is followed by the run finishing must not survive: the
        // Inert branch clears it, so a later run starts unarmed.
        assert_eq!(g.press(RecordState::Recording, 1), StopPress::Armed);
        assert_eq!(g.press(RecordState::Finished, 2), StopPress::Inert);
        assert_eq!(g.press(RecordState::Recording, 3), StopPress::Armed);
    }

    // Driving the emitted commands through a real Recorder proves the mapping
    // matches what the state machine actually accepts — start, pause, resume,
    // stop advance the state as the toggle promises.
    #[test]
    fn commands_drive_the_recorder_through_a_full_cycle() {
        use crate::record::Recorder;

        let mut r = Recorder::new();
        let apply = |b: Button, now: u32, r: &mut Recorder| {
            if let Some(cmd) = command_for(b, r.state()) {
                match cmd {
                    RecordCommand::Start => r.start(now),
                    RecordCommand::Pause => r.pause(now),
                    RecordCommand::Resume => r.resume(now),
                    RecordCommand::Stop => r.stop(now),
                    RecordCommand::Lap => r.lap(now),
                    RecordCommand::Reset => r.reset(now),
                }
            }
        };

        apply(Button::Primary, 0, &mut r);
        assert_eq!(r.state(), RecordState::Recording);
        apply(Button::Primary, 1, &mut r);
        assert_eq!(r.state(), RecordState::Paused);
        apply(Button::Primary, 2, &mut r);
        assert_eq!(r.state(), RecordState::Recording);
        // A lap press mid-run closes the lap without touching the run state.
        apply(Button::Lap, 3, &mut r);
        assert_eq!(r.state(), RecordState::Recording);
        assert_eq!(r.snapshot().lap, 2);
        assert_eq!(r.snapshot().last_lap.unwrap().index, 1);
        apply(Button::Stop, 3, &mut r);
        assert_eq!(r.state(), RecordState::Finished);
        // Stop / lap park once finished; BTN1 dismisses home and a fresh run
        // can start with cleared totals.
        apply(Button::Stop, 4, &mut r);
        apply(Button::Lap, 4, &mut r);
        assert_eq!(r.state(), RecordState::Finished);
        apply(Button::Primary, 5, &mut r);
        assert_eq!(r.state(), RecordState::Idle);
        apply(Button::Primary, 6, &mut r);
        assert_eq!(r.state(), RecordState::Recording);
        assert_eq!(r.snapshot().distance_m, 0.0);
        assert_eq!(r.snapshot().lap, 1);
    }
}
