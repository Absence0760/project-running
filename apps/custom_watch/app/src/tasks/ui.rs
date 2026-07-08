//! UI task — drives the Sharp MIP status face and the liveness LED.
//!
//! Rendering is delegated: `watch_core::face` decides what the rows say
//! (host-tested), `sharp_mip` turns rows into dirty-line SPI traffic
//! (host-tested). This task owns only the 1 Hz cadence and the peripheral
//! handles. The once-a-second flush doubles as the display's VCOM
//! alternation, which the glass needs regardless of content changes.

use defmt::*;
use embassy_nrf::gpio::{AnyPin, Level, Output, OutputDrive};
use embassy_nrf::spim::Spim;
use embassy_nrf::Peri;
use embassy_time::{Duration, Instant, Timer};
use sharp_mip::{Framebuffer, SharpMip};
use watch_core::face;
use watch_core::fix::Fix;

use crate::state;

// The face's text grid and the panel's cell grid are defined in separate
// crates on purpose (core is display-agnostic); this pins them together.
const _: () = core::assert!(face::COLS == sharp_mip::TEXT_COLS);
const _: () = core::assert!(face::ROWS == sharp_mip::TEXT_ROWS);

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

#[embassy_executor::task]
pub async fn screen_task(spim: Spim<'static>, cs: Output<'static>) {
    let mut display = SharpMip::new(spim, cs);
    let mut fb = Framebuffer::new();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut latest: Option<Fix> = None;

    if let Err(e) = display.clear_all() {
        warn!("ui: display clear failed: {:?}", e);
    }
    info!("ui::screen_task started");
    loop {
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
        }
        let uptime_s = Instant::now().as_secs() as u32;
        let rows = face::face_rows(latest.as_ref(), uptime_s);
        for (row, text) in rows.iter().enumerate() {
            fb.draw_text_row(row, text);
        }
        if let Err(e) = display.flush(&mut fb) {
            warn!("ui: display flush failed: {:?}", e);
        }
        Timer::after(Duration::from_secs(1)).await;
    }
}
