//! Board-support crate for the Nordic nRF52840 DK (PCA10056).
//!
//! Centralises the pin assignments + peripheral choices that are board-
//! specific. When we migrate to a custom PCB in tier 2+, only this crate
//! changes — the task code in `app/src/tasks/` stays untouched.
//!
//! [`Board::split`] consumes the HAL's `Peripherals` and hands back named
//! per-subsystem bundles, so `main.rs` reads as "give the GPS task the GPS
//! port", not as a list of pin numbers. Breakout wiring below is the
//! breadboard plan; revisit against the physical build at bench time.
//!
//! Reference: <https://infocenter.nordicsemi.com/topic/ug_nrf52840_dk/UG/dk/intro.html>

#![no_std]

use embassy_nrf::gpio::AnyPin;
use embassy_nrf::peripherals::{NVMC, P0_14, P0_15, P0_16, SPI3, TWISPI0, TWISPI1, UARTE0, UARTE1};
use embassy_nrf::{Peri, Peripherals};

/// u-blox MAX-M10S breakout on UARTE0. NMEA flows watch<-GPS on `rx`;
/// `tx` is only used for UBX config commands (none at tier 1).
pub struct GpsPort {
    pub uarte: Peri<'static, UARTE0>,
    pub rx: Peri<'static, AnyPin>,
    pub tx: Peri<'static, AnyPin>,
}

/// Sharp Memory LCD breakout on SPIM3 — the dedicated high-speed SPIM
/// instance (no SPIS/TWI sharing, and its 0x4002F000 slot is undeclared
/// in Renode's stock platform, so the sim can construct it with EasyDMA
/// enabled). CS is a plain GPIO because the panel's SCS is active-HIGH —
/// the inverse of what an SPI controller's hardware CS assumes.
pub struct DisplayPort {
    pub spim: Peri<'static, SPI3>,
    pub sck: Peri<'static, AnyPin>,
    pub mosi: Peri<'static, AnyPin>,
    pub cs: Peri<'static, AnyPin>,
}

/// Phone-link transport on UARTE1. Simulator-era stand-in for the
/// step-6 BLE GATT service: same status frames, different pipe.
pub struct PhonePort {
    pub uarte: Peri<'static, UARTE1>,
    pub tx: Peri<'static, AnyPin>,
    pub rx: Peri<'static, AnyPin>,
}

/// MAX86177 optical-HR breakout on the TWISPI0 I²C bus. Pins are the DK's
/// header I²C pair (P0.26 SDA / P0.27 SCL); breadboard plan, bench-verify.
pub struct HrPort {
    pub twim: Peri<'static, TWISPI0>,
    pub sda: Peri<'static, AnyPin>,
    pub scl: Peri<'static, AnyPin>,
}

/// BMP581 barometer on a separate TWISPI1 I²C bus (P1.10 SDA / P1.11 SCL) so
/// it never contends with the HR AFE's traffic; breadboard plan, bench-verify.
pub struct BaroPort {
    pub twim: Peri<'static, TWISPI1>,
    pub sda: Peri<'static, AnyPin>,
    pub scl: Peri<'static, AnyPin>,
}

/// Internal-flash controller (NVMC) for the on-device run store. The store's
/// reserved region is the top of flash (see `app/memory.x` / `memory-ble.x`);
/// the NVMC addresses the whole 1 MB, the linker keeps code out of the region.
pub struct FlashPort {
    pub nvmc: Peri<'static, NVMC>,
}

pub struct Leds {
    /// LED1 (P0.13, active-low) — the 1 Hz liveness blinker.
    pub led1: Peri<'static, AnyPin>,
    pub led2: Peri<'static, P0_14>,
    pub led3: Peri<'static, P0_15>,
    pub led4: Peri<'static, P0_16>,
}

/// The four user buttons. Active-LOW with the pin idle-high: a press pulls the
/// line to GND, so each needs an internal pull-up and reads pressed as low.
/// Pins per [`buttons`]. BTN1/BTN2 drive recording control today (see the
/// `button` task); BTN3/BTN4 are exposed but unassigned.
pub struct Buttons {
    /// BTN1 — P0.11.
    pub btn1: Peri<'static, AnyPin>,
    /// BTN2 — P0.12.
    pub btn2: Peri<'static, AnyPin>,
    /// BTN3 — P0.24.
    pub btn3: Peri<'static, AnyPin>,
    /// BTN4 — P0.25.
    pub btn4: Peri<'static, AnyPin>,
}

pub struct Board {
    pub leds: Leds,
    pub buttons: Buttons,
    pub gps: GpsPort,
    pub display: DisplayPort,
    pub phone: PhonePort,
    pub hr: HrPort,
    pub baro: BaroPort,
    pub flash: FlashPort,
}

impl Board {
    pub fn split(p: Peripherals) -> Self {
        Self {
            leds: Leds {
                led1: p.P0_13.into(),
                led2: p.P0_14,
                led3: p.P0_15,
                led4: p.P0_16,
            },
            buttons: Buttons {
                btn1: p.P0_11.into(),
                btn2: p.P0_12.into(),
                btn3: p.P0_24.into(),
                btn4: p.P0_25.into(),
            },
            gps: GpsPort {
                uarte: p.UARTE0,
                rx: p.P1_01.into(),
                tx: p.P1_02.into(),
            },
            display: DisplayPort {
                spim: p.SPI3,
                sck: p.P1_13.into(),
                mosi: p.P1_14.into(),
                cs: p.P1_12.into(),
            },
            phone: PhonePort {
                uarte: p.UARTE1,
                tx: p.P1_03.into(),
                rx: p.P1_04.into(),
            },
            hr: HrPort {
                twim: p.TWISPI0,
                sda: p.P0_26.into(),
                scl: p.P0_27.into(),
            },
            baro: BaroPort {
                twim: p.TWISPI1,
                sda: p.P1_10.into(),
                scl: p.P1_11.into(),
            },
            flash: FlashPort { nvmc: p.NVMC },
        }
    }
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
