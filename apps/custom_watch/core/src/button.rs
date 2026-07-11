//! Button → recording-command decision — the pure half of the button task.
//!
//! The `app/` button task owns only the hardware it can't test on the host:
//! edge detection and debounce. *Which* command a press should issue, given
//! the run's current state, is this pure reducer — host-tested here, exactly
//! like [`crate::record`] holds the state machine the record task drives.

use crate::record::RecordState;

/// A control command for the recording state machine, produced by a button
/// press and consumed by the record task. One variant per [`crate::record`]
/// method: `start` / `pause` / `resume` / `stop` / `lap`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RecordCommand {
    Start,
    Pause,
    Resume,
    Stop,
    Lap,
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
/// one, and resumes a paused one. BTN2 stops whenever a run is in progress.
/// BTN4 closes the current lap whenever a run is in progress. All are inert
/// once the run is finished (a new run needs a fresh recorder).
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
        (Button::Stop, RecordState::Recording | RecordState::Paused) => Some(RecordCommand::Stop),
        (Button::Lap, RecordState::Recording | RecordState::Paused) => Some(RecordCommand::Lap),
        _ => None,
    }
}

/// What BTN3 does in the current run state. The run-view pages only exist
/// once a run is under way (the idle status face ignores the page entirely —
/// see [`crate::face`]), so while idle the otherwise-dead page button doubles
/// as the GNSS-mode selector, keeping the mode surface inside decisions §81's
/// five-button budget with no chorded or long-press input. Any non-idle state
/// (recording, paused, finished — all of which show a run view) keeps BTN3 on
/// pages, which also freezes the GNSS mode for the duration of a run.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3Action {
    CyclePage,
    CycleGnssMode,
}

pub fn btn3_action(state: RecordState) -> Btn3Action {
    match state {
        RecordState::Idle => Btn3Action::CycleGnssMode,
        _ => Btn3Action::CyclePage,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primary_is_a_start_pause_resume_toggle() {
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
        assert_eq!(btn3_action(RecordState::Idle), Btn3Action::CycleGnssMode);
        // Every run-view state keeps BTN3 on pages — a mid-run (or post-run)
        // press must never silently change the GNSS mode.
        assert_eq!(btn3_action(RecordState::Recording), Btn3Action::CyclePage);
        assert_eq!(btn3_action(RecordState::Paused), Btn3Action::CyclePage);
        assert_eq!(btn3_action(RecordState::Finished), Btn3Action::CyclePage);
    }

    #[test]
    fn everything_is_inert_once_finished() {
        assert_eq!(command_for(Button::Primary, RecordState::Finished), None);
        assert_eq!(command_for(Button::Stop, RecordState::Finished), None);
        assert_eq!(command_for(Button::Lap, RecordState::Finished), None);
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
        // Post-finish presses are inert.
        apply(Button::Primary, 4, &mut r);
        apply(Button::Stop, 5, &mut r);
        assert_eq!(r.state(), RecordState::Finished);
    }
}
