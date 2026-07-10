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
//!          zones / pacer)
//!   BTN4 — manual lap (the Fenix layout's lower-right Lap, decisions §81)
//! The buttons are active-LOW (idle high, press pulls low), so a press is a
//! falling edge and a held press reads `is_low()`. BTN3 carries no recording
//! command — it just advances `state::PAGE`, which the `ui` face reads.

use defmt::*;
#[cfg(not(feature = "sim-buttons"))]
use embassy_futures::select::{select4, Either4};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Instant, Timer};
use watch_core::button::{command_for, Button};
use watch_core::page::Page;
use watch_core::record::RecordState;

use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
#[cfg(not(feature = "sim-buttons"))]
const DEBOUNCE: Duration = Duration::from_millis(20);

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
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    info!("button: BTN1 start/pause, BTN2 stop, BTN3 page, BTN4 lap");
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
                // The page button is its own concern — no recording command.
                // Debounce, confirm the press held, then advance the page.
                Timer::after(DEBOUNCE).await;
                if btn3.is_low() {
                    interaction_tx.send(Instant::now().as_secs() as u32);
                    page = page.next();
                    info!("button: BTN3 -> page {}", page);
                    page_tx.send(page);
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
        interaction_tx.send(Instant::now().as_secs() as u32);

        // The toggle keys off the latest published run state. `try_get` never
        // waits: before the first snapshot the run is idle, which is correct.
        let state = record_rx
            .try_get()
            .map(|snap| snap.state)
            .unwrap_or(RecordState::Idle);
        if let Some(cmd) = command_for(button, state) {
            info!("button: {} -> {}", button, cmd);
            state::RECORD_CMD.send(cmd).await;
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
/// page, BTN4 lap). Renode has no contact bounce, so a clean edge needs no
/// debounce confirm.
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
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();

    // Active-low: pressed pulls the line low. Track the previous level per
    // button so a release→press transition (high→low) fires exactly once.
    let btns = [btn1, btn2, btn3, btn4];
    let mut prev = [
        btns[0].is_low(),
        btns[1].is_low(),
        btns[2].is_low(),
        btns[3].is_low(),
    ];
    info!("button(sim): polling BTN1 start/pause, BTN2 stop, BTN3 page, BTN4 lap");

    loop {
        Timer::after(POLL).await;
        for (i, b) in btns.iter().enumerate() {
            let pressed = b.is_low();
            let falling = pressed && !prev[i];
            prev[i] = pressed;
            if !falling {
                continue;
            }
            // A press is an interaction whether or not it issues a command —
            // it wakes the face's animation window, same as the hardware task.
            interaction_tx.send(Instant::now().as_secs() as u32);
            if i == 2 {
                // BTN3 is its own concern — no recording command, just a page.
                page = page.next();
                info!("button: BTN3 -> page {}", page);
                page_tx.send(page);
                continue;
            }
            let button = match i {
                0 => Button::Primary,
                1 => Button::Stop,
                _ => Button::Lap,
            };
            let state = record_rx
                .try_get()
                .map(|snap| snap.state)
                .unwrap_or(RecordState::Idle);
            if let Some(cmd) = command_for(button, state) {
                info!("button: {} -> {}", button, cmd);
                state::RECORD_CMD.send(cmd).await;
            }
        }
    }
}
