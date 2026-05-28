//! Board-support crate for the Nordic nRF52840 DK (PCA10056).
//!
//! Centralises the pin assignments + peripheral choices that are board-
//! specific. When we migrate to a custom PCB in tier 2+, only this crate
//! changes — the task code in `app/src/tasks/` stays untouched.
//!
//! Reference: <https://infocenter.nordicsemi.com/topic/ug_nrf52840_dk/UG/dk/intro.html>

#![no_std]

/// User LEDs on the DK (active-low to ground).
pub mod leds {
    /// LED1 — `P0.13`.
    pub const LED1_PIN: u8 = 13;
    /// LED2 — `P0.14`.
    pub const LED2_PIN: u8 = 14;
    /// LED3 — `P0.15`.
    pub const LED3_PIN: u8 = 15;
    /// LED4 — `P0.16`.
    pub const LED4_PIN: u8 = 16;
}

/// User buttons on the DK (active-low, need internal pullup).
pub mod buttons {
    /// Button1 — `P0.11`.
    pub const BTN1_PIN: u8 = 11;
    /// Button2 — `P0.12`.
    pub const BTN2_PIN: u8 = 12;
    /// Button3 — `P0.24`.
    pub const BTN3_PIN: u8 = 24;
    /// Button4 — `P0.25`.
    pub const BTN4_PIN: u8 = 25;
}

// TODO step 4+: add SPI pin assignments for the Sharp MIP, I²C for the
// MAX86177 + BMP390, UART for the GPS, etc. as drivers come online.
