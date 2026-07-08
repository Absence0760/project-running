//! The Sharp MIP wire protocol.
//!
//! Frame shape (all bytes composed for LSB-first transmission — configure
//! the SPI controller accordingly; the datasheet's M0/M1/M2 mode bits are
//! then simply bits 0/1/2 of the first byte):
//!
//! ```text
//! write:  [mode|vcom] ( [line addr, 1-based] [21 data bytes] [0x00] )+ [0x00]
//! clear:  [mode=CLEAR|vcom] [0x00]
//! vcom:   [mode=vcom only]  [0x00]
//! ```
//!
//! Data bytes carry 1 = white on the wire; the framebuffer stores 1 = ink,
//! inverted here during encode. SCS is a plain GPIO held high across the
//! frame — the panel's chip-select is active-HIGH, the inverse of SPI
//! convention, which is why the driver never uses controller-managed CS.
//!
//! VCOM (the liquid-crystal polarity bias) rides bit M1 of every frame and
//! must alternate at ~1 Hz to prevent DC damage to the glass; the ui task's
//! once-a-second flush cadence provides that for free. Bench bring-up note:
//! SCS setup/hold wants ~3 us/1 us of margin around the transfer — revisit
//! with a DelayNs if the real panel glitches at speed; the simulator model
//! doesn't care.

use embedded_hal::digital::OutputPin;
use embedded_hal::spi::SpiBus;

use crate::framebuffer::{Framebuffer, HEIGHT, LINE_BYTES};

const MODE_WRITE: u8 = 0x01;
const MODE_VCOM: u8 = 0x02;
const MODE_CLEAR: u8 = 0x04;

pub struct SharpMip<SPI, CS> {
    spi: SPI,
    cs: CS,
    vcom: bool,
}

impl<SPI: SpiBus, CS: OutputPin> SharpMip<SPI, CS> {
    pub fn new(spi: SPI, cs: CS) -> Self {
        Self {
            spi,
            cs,
            vcom: false,
        }
    }

    /// Tear down into the underlying bus + pin. Lets tests inspect what was
    /// written, and a future power path release the bus.
    pub fn into_parts(self) -> (SPI, CS) {
        (self.spi, self.cs)
    }

    /// Push every dirty framebuffer line to the panel; clears dirty flags on
    /// success. With nothing dirty this still sends the 2-byte VCOM frame,
    /// so calling it on a timer keeps the bias alternating.
    pub fn flush(&mut self, fb: &mut Framebuffer) -> Result<(), SPI::Error> {
        let mode = self.next_mode();
        let result = self.frame(fb, mode);
        if result.is_ok() {
            fb.clear_dirty();
        }
        result
    }

    /// Panel-side all-clear (M2). The framebuffer is not touched; pair with
    /// `fb.clear()` when the in-RAM image should follow.
    pub fn clear_all(&mut self) -> Result<(), SPI::Error> {
        let mode = self.next_mode() & !MODE_WRITE | MODE_CLEAR;
        self.cs.set_high().ok();
        let result = self.spi.write(&[mode, 0x00]);
        self.cs.set_low().ok();
        result
    }

    fn next_mode(&mut self) -> u8 {
        self.vcom = !self.vcom;
        let vcom_bit = if self.vcom { MODE_VCOM } else { 0 };
        MODE_WRITE | vcom_bit
    }

    fn frame(&mut self, fb: &Framebuffer, mode: u8) -> Result<(), SPI::Error> {
        let any_dirty = (0..HEIGHT).any(|y| fb.is_dirty(y));
        self.cs.set_high().ok();
        let result = (|| {
            if !any_dirty {
                return self.spi.write(&[mode & !MODE_WRITE, 0x00]);
            }
            self.spi.write(&[mode])?;
            for y in 0..HEIGHT {
                if !fb.is_dirty(y) {
                    continue;
                }
                let mut packet = [0u8; 2 + LINE_BYTES];
                packet[0] = (y + 1) as u8;
                for (i, &b) in fb.line(y).iter().enumerate() {
                    packet[1 + i] = !b; // ink -> white-is-1 wire polarity
                }
                self.spi.write(&packet)?;
            }
            self.spi.write(&[0x00])
        })();
        self.cs.set_low().ok();
        result
    }
}
