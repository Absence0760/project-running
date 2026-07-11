//! Button task — turns the DK's control buttons into `RecordCommand`s.
//!
//! Thin glue by design: the press → command decision lives in the host-tested
//! `watch_core::button` (which command a button issues in a given run state);
//! this task owns only the hardware that module can't reach — edge detection
//! and contact debounce.
//!
//! Mapping (see `watch_core::button::command_for`):
//!   BTN1 — start / pause / resume toggle
//!   BTN2 — stop
//!   BTN3 — cycle the run-view page (dashboard / distance / pace / lap /
//!          zones / pacer / nav / back-to-start) while a run is under way;
//!          cycle the GNSS recording mode (Performance / Balanced /
//!          Expedition) on the idle face
//!   BTN4 — manual lap (the Fenix layout's lower-right Lap, decisions §81)
//! The buttons are active-LOW (idle high, press pulls low), so a press is a
//! falling edge and a held press reads `is_low()`. BTN3 carries no recording
//! command — which of its two cycles a press lands on is the host-tested
//! `watch_core::button::btn3_action` (idle = mode, any run view = pages, so a
//! run's mode is frozen for its duration).

use defmt::*;
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select, Either};
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select4, Either4};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Instant, Timer};
use watch_core::button::{
    btn3_action, command_for, Btn3Action, Button, RecordCommand, StopGuard, StopPress,
    STOP_CONFIRM_WINDOW_S,
};
use watch_core::gnss_mode::GnssMode;
use watch_core::page::Page;
use watch_core::record::RecordState;

use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
#[cfg(not(feature = "sim-buttons"))]
const DEBOUNCE: Duration = Duration::from_millis(20);

/// How long BTN3 must be held to count as a long-press. A short BTN3 press
/// still cycles forward (page next / GNSS mode); a long-press cycles the run
/// pages *backward*, so a late page in the 31-page cycle is one press away
/// instead of ~30. A deliberate hold, not a chord — inside decisions §81's
/// five-button, no-chord budget.
const BTN3_LONG_PRESS: Duration = Duration::from_millis(500);

#[cfg(not(feature = "sim-buttons"))]
#[embassy_executor::task]
pub async fn run(
    mut btn1: Input<'static>,
    mut btn2: Input<'static>,
    mut btn3: Input<'static>,
    mut btn4: Input<'static>,
) {
    let mut record_rx = unwrap!(state::RECORD.receiver());
    let page_tx = state::PAGE.sender();
    let mode_tx = state::GNSS_MODE.sender();
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    let mut mode = GnssMode::default();
    let mut stop_guard = StopGuard::new();
    info!("button: BTN1 start/pause, BTN2 stop, BTN3 page/mode, BTN4 lap");
    loop {
        // Wait for whichever button is pressed first (falling edge = press).
        let button = match select4(
            btn1.wait_for_falling_edge(),
            btn2.wait_for_falling_edge(),
            btn3.wait_for_falling_edge(),
            btn4.wait_for_falling_edge(),
        )
        .await
        {
            Either4::First(()) => Button::Primary,
            Either4::Second(()) => Button::Stop,
            Either4::Third(()) => {
                // BTN3 is its own concern — no recording command. Debounce,
                // confirm the press held, then cycle whichever surface the run
                // state puts it on (idle = GNSS mode, run view = pages).
                Timer::after(DEBOUNCE).await;
                if btn3.is_low() {
                    // Time the hold: a long-press cycles pages backward so a
                    // late page is one press away, not ~30. The idle GNSS-mode
                    // selector ignores the distinction (only three modes, no
                    // reverse), keeping the idle/run split intact.
                    let long = matches!(
                        select(Timer::after(BTN3_LONG_PRESS), btn3.wait_for_rising_edge()).await,
                        Either::First(()),
                    );
                    interaction_tx.send(Instant::now().as_secs() as u32);
                    let state = record_rx
                        .try_get()
                        .map(|snap| snap.state)
                        .unwrap_or(RecordState::Idle);
                    match btn3_action(state) {
                        Btn3Action::CyclePage => {
                            page = if long { page.prev() } else { page.next() };
                            info!("button: BTN3 -> page {}", page);
                            page_tx.send(page);
                        }
                        Btn3Action::CycleGnssMode => {
                            mode = mode.next();
                            info!(
                                "button: BTN3 -> gnss mode {} (fix interval {=u32}s, ~{=u32}h)",
                                mode,
                                mode.fix_interval_s(),
                                mode.battery_est_h()
                            );
                            mode_tx.send(mode);
                        }
                    }
                }
                continue;
            }
            Either4::Fourth(()) => Button::Lap,
        };

        // Debounce: let the contacts settle, then confirm the press held. A
        // bounce that has already released by now is dropped.
        Timer::after(DEBOUNCE).await;
        let held = match button {
            Button::Primary => btn1.is_low(),
            Button::Stop => btn2.is_low(),
            Button::Lap => btn4.is_low(),
        };
        if !held {
            continue;
        }
        // A confirmed press is an interaction, whether or not it maps to a
        // command in the current state — it wakes the face's animation window.
        let now_s = Instant::now().as_secs() as u32;
        interaction_tx.send(now_s);

        // The toggle keys off the latest published run state. `try_get` never
        // waits: before the first snapshot the run is idle, which is correct.
        let state = record_rx
            .try_get()
            .map(|snap| snap.state)
            .unwrap_or(RecordState::Idle);
        dispatch(button, state, now_s, &mut stop_guard).await;
    }
}

/// Turn a confirmed press into a recording command, gating the terminal `Stop`
/// behind the host-tested [`StopGuard`] double-press so a single cold/gloved
/// mis-press can't end a multi-hour recording. Shared by the hardware and sim
/// button tasks.
async fn dispatch(button: Button, state: RecordState, now_s: u32, stop_guard: &mut StopGuard) {
    match button {
        Button::Stop => match stop_guard.press(state, now_s) {
            StopPress::Confirmed => {
                info!("button: BTN2 -> stop (confirmed)");
                state::RECORD_CMD.send(RecordCommand::Stop).await;
            }
            StopPress::Armed => info!(
                "button: BTN2 armed — press again within {=u32}s to stop",
                STOP_CONFIRM_WINDOW_S
            ),
            StopPress::Inert => {}
        },
        _ => {
            if let Some(cmd) = command_for(button, state) {
                info!("button: {} -> {}", button, cmd);
                state::RECORD_CMD.send(cmd).await;
            }
        }
    }
}

/// Sim-only button task — polls the DK button pin levels instead of waiting on
/// a hardware falling edge.
///
/// The hardware `run` above waits on `wait_for_falling_edge`, which the
/// nRF52840 drives from the GPIO SENSE/DETECT + PORT-event mechanism. Renode's
/// nRF52840 GPIO model implements the IN register (pin level) but not
/// SENSE/DETECT, so that edge future never wakes under the sim. This variant
/// samples the pin levels on a short timer and detects the falling edge in
/// software, so the `btn1`/`btn2`/`btn3`/`btn4` monitor macros in
/// `sim/watch.resc` drive the SAME `command_for` / page logic the real task
/// uses. The mapping is identical (BTN1 start/pause/resume, BTN2 stop, BTN3
/// page / idle GNSS mode, BTN4 lap). Renode has no contact bounce, so a clean
/// edge needs no debounce confirm.
///
/// Feature-gated to the sim build; the hardware task keeps the low-power SENSE
/// path (docs/custom_watch/performance_path.md — "every wake justifiable").
#[cfg(feature = "sim-buttons")]
#[embassy_executor::task]
pub async fn run(
    btn1: Input<'static>,
    btn2: Input<'static>,
    btn3: Input<'static>,
    btn4: Input<'static>,
) {
    /// Poll cadence. The `click` macro holds a press ~0.3 s, so any interval
    /// well under that catches the edge; short enough to feel instant.
    const POLL: Duration = Duration::from_millis(10);

    let mut record_rx = unwrap!(state::RECORD.receiver());
    let page_tx = state::PAGE.sender();
    let mode_tx = state::GNSS_MODE.sender();
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    let mut mode = GnssMode::default();
    let mut stop_guard = StopGuard::new();

    // Active-low: pressed pulls the line low. Track the previous level per
    // button so a release→press transition (high→low) fires exactly once.
    let btns = [btn1, btn2, btn3, btn4];
    let mut prev = [
        btns[0].is_low(),
        btns[1].is_low(),
        btns[2].is_low(),
        btns[3].is_low(),
    ];
    // BTN3 acts on release so its hold duration can pick short (forward) vs
    // long (backward); this remembers when the current BTN3 press began.
    let mut btn3_down_at: Option<Instant> = None;
    info!("button(sim): polling BTN1 start/pause, BTN2 stop, BTN3 page/mode, BTN4 lap");

    loop {
        Timer::after(POLL).await;
        for (i, b) in btns.iter().enumerate() {
            let pressed = b.is_low();
            let was = prev[i];
            prev[i] = pressed;
            let falling = pressed && !was;
            let rising = !pressed && was;

            if i == 2 {
                // BTN3 times its hold: press starts the clock, release decides
                // short (forward) vs long (backward) and acts — the same
                // short/long split the hardware task makes with a select.
                if falling {
                    btn3_down_at = Some(Instant::now());
                    continue;
                }
                if !rising {
                    continue;
                }
                let long = btn3_down_at.take().is_some_and(|t| {
                    Instant::now().saturating_duration_since(t) >= BTN3_LONG_PRESS
                });
                let now_s = Instant::now().as_secs() as u32;
                interaction_tx.send(now_s);
                let state = record_rx
                    .try_get()
                    .map(|snap| snap.state)
                    .unwrap_or(RecordState::Idle);
                match btn3_action(state) {
                    Btn3Action::CyclePage => {
                        page = if long { page.prev() } else { page.next() };
                        info!("button: BTN3 -> page {}", page);
                        page_tx.send(page);
                    }
                    Btn3Action::CycleGnssMode => {
                        mode = mode.next();
                        info!(
                            "button: BTN3 -> gnss mode {} (fix interval {=u32}s, ~{=u32}h)",
                            mode,
                            mode.fix_interval_s(),
                            mode.battery_est_h()
                        );
                        mode_tx.send(mode);
                    }
                }
                continue;
            }

            if !falling {
                continue;
            }
            // A press is an interaction whether or not it issues a command —
            // it wakes the face's animation window, same as the hardware task.
            let now_s = Instant::now().as_secs() as u32;
            interaction_tx.send(now_s);
            let state = record_rx
                .try_get()
                .map(|snap| snap.state)
                .unwrap_or(RecordState::Idle);
            let button = match i {
                0 => Button::Primary,
                1 => Button::Stop,
                _ => Button::Lap,
            };
            dispatch(button, state, now_s, &mut stop_guard).await;
        }
    }
}
