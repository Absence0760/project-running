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
//!   BTN3 — cycle the run-view page (dashboard / distance / pace)
//! The buttons are active-LOW (idle high, press pulls low), so a press is a
//! falling edge and a held press reads `is_low()`. BTN3 carries no recording
//! command — it just advances `state::PAGE`, which the `ui` face reads.

use defmt::*;
use embassy_futures::select::{select3, Either3};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Instant, Timer};
use watch_core::button::{command_for, Button};
use watch_core::page::Page;
use watch_core::record::RecordState;

use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
const DEBOUNCE: Duration = Duration::from_millis(20);

#[embassy_executor::task]
pub async fn run(mut btn1: Input<'static>, mut btn2: Input<'static>, mut btn3: Input<'static>) {
    let mut record_rx = unwrap!(state::RECORD.receiver());
    let page_tx = state::PAGE.sender();
    let interaction_tx = state::INTERACTION.sender();
    let mut page = Page::default();
    info!("button: BTN1 start/pause, BTN2 stop, BTN3 page");
    loop {
        // Wait for whichever button is pressed first (falling edge = press).
        let button = match select3(
            btn1.wait_for_falling_edge(),
            btn2.wait_for_falling_edge(),
            btn3.wait_for_falling_edge(),
        )
        .await
        {
            Either3::First(()) => Button::Primary,
            Either3::Second(()) => Button::Stop,
            Either3::Third(()) => {
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
        };

        // Debounce: let the contacts settle, then confirm the press held. A
        // bounce that has already released by now is dropped.
        Timer::after(DEBOUNCE).await;
        let held = match button {
            Button::Primary => btn1.is_low(),
            Button::Stop => btn2.is_low(),
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
