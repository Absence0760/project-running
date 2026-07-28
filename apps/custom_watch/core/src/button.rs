//! Button → recording-command decision — the pure half of the button task.
//!
//! The `app/` button task owns only the hardware it can't test on the host:
//! edge detection and debounce. *Which* command a press should issue, given
//! the run's current state, is this pure reducer — host-tested here, exactly
//! like [`crate::record`] holds the state machine the record task drives.
//!
//! The five-slot grammar (decisions §350, within §81's 3+2 Fenix shape):
//! the page ring renders horizontally (the top-edge position thumb), so the
//! paging keys are spatially congruent with it — the lower-LEFT button pages
//! left, the lower-RIGHT button pages right, both plain taps, and holding
//! either past [`PAGE_HOLD_MS`] opens the page grid. BTN1 (upper-right)
//! stays start/pause/resume/dismiss, BTN2 (mid-left) the guarded stop, and
//! BTN5 (upper-left) is the manual lap.

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

/// The physical buttons wired to recording control.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Button {
    /// BTN1 (upper-right) — a context-sensitive start / pause / resume toggle.
    Primary,
    /// BTN2 (mid-left) — stop.
    Stop,
    /// BTN5 (upper-left) — manual lap. Its own key, like Polar's OK-marks-a-lap:
    /// the paging pair below it must stay plain taps (decisions §350), so the
    /// lap cannot share the lower-right slot the Fenix layout gives it.
    Lap,
}

/// Map a button press, given the current recorder state, to the command it
/// should issue — or `None` when the press is a no-op in that state.
///
/// BTN1 is a single context toggle: it starts an idle run, pauses a running
/// one, resumes a paused one, and dismisses a finished one back to the idle
/// face (the stored run was committed at stop, so the dismissal is view-only
/// — without it `Finished` was a dead end that held the run view until
/// reboot). BTN2 stops whenever a run is in progress and stays inert once
/// finished. BTN5 closes the current lap whenever a run is in progress and is
/// otherwise inert — the paging keys BTN3/BTN4 never reach this reducer.
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

/// How long a paging key (BTN3 / BTN4) was held: released before
/// [`PAGE_HOLD_MS`] is a tap, anything longer is a hold. Two tiers only —
/// the old middle tier (release-between-thresholds paged backward) died with
/// §350, because backward paging became the BTN3 tap.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PageBtnPress {
    Tap,
    Hold,
}

/// The tap / hold boundary for the two paging keys, in milliseconds.
///
/// Deliberately conventional rather than tuned: 500 ms is the long-press
/// default of both phone platforms — Android's
/// `ViewConfiguration.DEFAULT_LONG_PRESS_TIMEOUT` and iOS's
/// `UILongPressGestureRecognizer.minimumPressDuration` (0.5 s) — so a gloved
/// thumb arrives already trained on it, and it is 25x the button task's 20 ms
/// contact debounce, which is what keeps bounce from ever promoting a tap.
/// The hold's action fires AT this threshold while the button is still down
/// (the grid appearing / the re-zero banner IS the feedback), so the runner
/// never times a release blind.
pub const PAGE_HOLD_MS: u32 = 500;

/// Classify a completed paging-key hold by its duration — the release-path
/// classification the sim button task applies verbatim (the hardware task
/// reproduces the same boundary with a select timer).
pub fn classify_page_hold(held_ms: u32) -> PageBtnPress {
    if held_ms >= PAGE_HOLD_MS {
        PageBtnPress::Hold
    } else {
        PageBtnPress::Tap
    }
}

/// What a BTN3 (lower-left) press does, given the run state and press tier.
/// The run-view pages only exist once a run is under way (the idle status face
/// ignores the page entirely — see [`crate::face`]), so while idle the
/// otherwise-dead paging key doubles as the GNSS-mode selector and its hold as
/// the manual QNH re-zero, keeping both surfaces inside decisions §81's
/// five-button, no-chord budget. Any non-idle state (recording, paused,
/// finished — all of which show a run view) keeps BTN3 on pages: tap pages
/// LEFT (the spatial mirror of BTN4's page-right tap), hold opens the
/// [`crate::page_grid`] overview. Which also freezes the GNSS mode (and parks
/// the re-zero) for the duration of a run: mid-run the elevation complementary
/// filter auto-corrects drift, so the manual snap is an idle (trailhead)
/// affordance and a run's recording controls stay untouched.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn3Action {
    PagePrev,
    OpenGrid,
    CycleGnssMode,
    QnhRezero,
}

pub fn btn3_action(state: RecordState, press: PageBtnPress) -> Btn3Action {
    match (state, press) {
        (RecordState::Idle, PageBtnPress::Tap) => Btn3Action::CycleGnssMode,
        (RecordState::Idle, PageBtnPress::Hold) => Btn3Action::QnhRezero,
        (_, PageBtnPress::Tap) => Btn3Action::PagePrev,
        (_, PageBtnPress::Hold) => Btn3Action::OpenGrid,
    }
}

/// What a BTN4 (lower-right) press does — the spatial mirror of
/// [`btn3_action`]. In every run view a tap pages RIGHT and a hold opens the
/// same page grid (either paging key reaches it, so whichever hand is free
/// works). While idle it toggles the home face against the diagnostics face
/// (decisions §291) whatever the duration — the idle face has no pages, and
/// an idle gesture must never change meaning mid-press.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Btn4Action {
    PageNext,
    OpenGrid,
    ToggleDiagnostics,
}

pub fn btn4_action(state: RecordState, press: PageBtnPress) -> Btn4Action {
    match (state, press) {
        (RecordState::Idle, _) => Btn4Action::ToggleDiagnostics,
        (_, PageBtnPress::Tap) => Btn4Action::PageNext,
        (_, PageBtnPress::Hold) => Btn4Action::OpenGrid,
    }
}

/// What a non-paging press does while the page grid is open: BTN1 confirms
/// the jump — the START-confirms idiom every 5-button watch trains (Garmin,
/// Polar, Suunto) — BTN2 cancels, and BTN5 is swallowed whole. Every press
/// inside a navigation modal must never reach the recorder, so the picker
/// can't pause, stop-arm, or lap a run by accident; the cursor itself belongs
/// to the paging keys (BTN3 back / BTN4 forward, the same directions they
/// page).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GridPress {
    Select,
    Cancel,
    Swallow,
}

pub fn grid_press(button: Button) -> GridPress {
    match button {
        Button::Primary => GridPress::Select,
        Button::Stop => GridPress::Cancel,
        Button::Lap => GridPress::Swallow,
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
    fn the_paging_taps_mirror_spatially_in_every_run_view() {
        // The whole point of §350: in any state that shows pages, the
        // lower-left key pages left and the lower-right key pages right, both
        // on a plain tap — no state may bend either tap to anything else.
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(
                btn3_action(state, PageBtnPress::Tap),
                Btn3Action::PagePrev,
                "{state:?}"
            );
            assert_eq!(
                btn4_action(state, PageBtnPress::Tap),
                Btn4Action::PageNext,
                "{state:?}"
            );
        }
    }

    #[test]
    fn either_paging_key_held_opens_the_grid_in_every_run_view() {
        for state in [
            RecordState::Recording,
            RecordState::Paused,
            RecordState::Finished,
        ] {
            assert_eq!(
                btn3_action(state, PageBtnPress::Hold),
                Btn3Action::OpenGrid,
                "{state:?}"
            );
            assert_eq!(
                btn4_action(state, PageBtnPress::Hold),
                Btn4Action::OpenGrid,
                "{state:?}"
            );
        }
    }

    #[test]
    fn btn3_cycles_gnss_mode_and_rezeroes_only_while_idle() {
        assert_eq!(
            btn3_action(RecordState::Idle, PageBtnPress::Tap),
            Btn3Action::CycleGnssMode
        );
        // A mid-run hold must never re-zero the altitude reference out from
        // under a recording, and a mid-run (or post-run) tap must never
        // silently change the GNSS mode.
        assert_eq!(
            btn3_action(RecordState::Idle, PageBtnPress::Hold),
            Btn3Action::QnhRezero
        );
    }

    #[test]
    fn btn4_toggles_diagnostics_while_idle_whatever_the_duration() {
        // The idle face has no pages and no grid; an idle gesture must never
        // change meaning mid-press, so both tiers land on the same toggle.
        assert_eq!(
            btn4_action(RecordState::Idle, PageBtnPress::Tap),
            Btn4Action::ToggleDiagnostics
        );
        assert_eq!(
            btn4_action(RecordState::Idle, PageBtnPress::Hold),
            Btn4Action::ToggleDiagnostics
        );
    }

    #[test]
    fn grid_swallows_every_button_select_cancel_and_lap() {
        assert_eq!(grid_press(Button::Primary), GridPress::Select);
        assert_eq!(grid_press(Button::Stop), GridPress::Cancel);
        assert_eq!(grid_press(Button::Lap), GridPress::Swallow);
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
    fn the_hold_threshold_is_the_platform_long_press_default() {
        // Pinned so a future change has to argue with the doc comment above:
        // 500 ms is the platform long-press default (Android
        // ViewConfiguration / iOS UILongPressGestureRecognizer), 25x the
        // 20 ms contact debounce.
        assert_eq!(PAGE_HOLD_MS, 500);
    }

    #[test]
    fn hold_classification_is_inclusive_at_the_threshold() {
        assert_eq!(classify_page_hold(0), PageBtnPress::Tap);
        assert_eq!(classify_page_hold(PAGE_HOLD_MS - 1), PageBtnPress::Tap);
        assert_eq!(classify_page_hold(PAGE_HOLD_MS), PageBtnPress::Hold);
        assert_eq!(classify_page_hold(u32::MAX), PageBtnPress::Hold);
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
