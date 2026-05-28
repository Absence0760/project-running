//! UI task — drives the Sharp MIP display + handles button input.
//!
//! Tier 1 deliverable: blink the user LED at 1 Hz. Display driver bring-up
//! comes in step 4 of `apps/custom_watch/README.md`; button handling and
//! screen layout follow.

use defmt::*;
use embassy_nrf::{
    gpio::{AnyPin, Level, Output, OutputDrive},
    Peri,
};
use embassy_time::{Duration, Timer};

#[embassy_executor::task]
pub async fn blink_task(pin: Peri<'static, AnyPin>) {
    // LEDs on the nRF52840 DK are active-low (cathode tied to MCU pin, anode
    // to VDD via a series resistor); Level::High here starts the LED OFF.
    let mut led = Output::new(pin, Level::High, OutputDrive::Standard);
    info!("ui::blink_task started");
    loop {
        led.toggle();
        Timer::after(Duration::from_millis(500)).await;
    }
}
