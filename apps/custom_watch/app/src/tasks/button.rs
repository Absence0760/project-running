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
//! The buttons are active-LOW (idle high, press pulls low), so a press is a
//! falling edge and a held press reads `is_low()`.

use defmt::*;
use embassy_futures::select::{select, Either};
use embassy_nrf::gpio::Input;
use embassy_time::{Duration, Timer};
use watch_core::button::{command_for, Button};
use watch_core::record::RecordState;

use crate::state;

/// Settle time after an edge before the level is trusted — long enough to ride
/// out contact bounce on the DK's tactile switches, short enough to feel
/// instant.
const DEBOUNCE: Duration = Duration::from_millis(20);

#[embassy_executor::task]
pub async fn run(mut btn1: Input<'static>, mut btn2: Input<'static>) {
    let mut record_rx = unwrap!(state::RECORD.receiver());
    info!("button: BTN1 start/pause, BTN2 stop");
    loop {
        // Wait for whichever button is pressed first (falling edge = press).
        let button = match select(btn1.wait_for_falling_edge(), btn2.wait_for_falling_edge()).await
        {
            Either::First(()) => Button::Primary,
            Either::Second(()) => Button::Stop,
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
