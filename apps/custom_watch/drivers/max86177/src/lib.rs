//! Driver for the Maxim MAX86177 optical heart-rate AFE.
//!
//! Register-level bring-up over blocking I2C: soft-reset, configure a single
//! PPG measurement channel with one LED, and drain raw photodiode counts from
//! the FIFO. Tier 1 stops at raw samples — [`peak_detect`] turns the stream
//! into a BPM estimate in pure, host-testable logic. The licensed Maxim HR
//! algorithm is C and gets pulled in via `bindgen` post-tier-1; see
//! `docs/architecture/decisions.md` § 80 ("Trade-offs we accept") for the FFI
//! budget.
//!
//! No community Rust crate exists for this part, so the register map is
//! hand-rolled. Real implementation for step 5 of `apps/custom_watch/README.md`.

#![no_std]

pub mod peak_detect;

use embedded_hal::i2c::I2c;

/// 7-bit I2C address with the device's `ADDR` pin tied low.
pub const I2C_ADDR: u8 = 0x62;

/// Register map. Addresses and bitfield encodings follow the MAX8617x family
/// layout; the exact values are a bench-verify target against the final
/// MAX86177 datasheet before the first on-board read.
mod reg {
    pub const FIFO_COUNTER: u8 = 0x0B;
    pub const FIFO_DATA: u8 = 0x0C;
    pub const FIFO_CONFIG_1: u8 = 0x0D;
    pub const FIFO_CONFIG_2: u8 = 0x0E;
    pub const SYSTEM_CONFIG_1: u8 = 0x10;
    pub const PPG_CONFIG_1: u8 = 0x11;
    pub const PPG_CONFIG_2: u8 = 0x12;
    pub const MEAS_ENABLE: u8 = 0x13;
    pub const MEAS1_SELECT: u8 = 0x14;
    pub const MEAS1_CONFIG_1: u8 = 0x15;
    pub const MEAS1_CONFIG_2: u8 = 0x16;
    pub const MEAS1_LEDA_CURRENT: u8 = 0x19;
    pub const TEMP_CONFIG: u8 = 0x20;
    pub const TEMP_INT: u8 = 0x21;
    pub const TEMP_FRAC: u8 = 0x22;
}

const SW_RESET: u8 = 1 << 0;
const SHUTDOWN: u8 = 1 << 1;
const FIFO_FLUSH: u8 = 1 << 4;
const FIFO_ROLLOVER: u8 = 1 << 1;
const MEAS1_ENABLE: u8 = 1 << 0;

/// Almost-full interrupt threshold, in samples remaining. Unused at tier 1
/// (we poll the counter) but set so the pin is meaningful once wired.
const FIFO_A_FULL: u8 = 0x0F;

/// One green LED on MEAS1, 100 Hz output, no on-chip averaging, mid-scale ADC
/// range and drive current. `LEDA_CURRENT` is the one value most likely to
/// need a bench tweak — raise it if the resting DC level sits too low to see a
/// pulse, lower it if the ADC rails.
const PPG_CONFIG_1: u8 = 0x24;
const PPG_CONFIG_2: u8 = 0x18;
const MEAS1_SELECT: u8 = 0x01;
const MEAS1_CONFIG_1: u8 = 0x20;
const MEAS1_CONFIG_2: u8 = 0x00;
const MEAS1_LEDA_CURRENT: u8 = 0x40;

/// FIFO words are three bytes: a tag in the upper bits and a 19-bit photodiode
/// count in the lower bits.
const SAMPLE_BYTES: usize = 3;
const PPG_DATA_MASK: u32 = 0x0007_FFFF;

/// Bounded read budget for the reset bit to self-clear, so a dead bus fails
/// fast instead of hanging `init`.
const RESET_POLL_MAX: u32 = 256;

/// One-shot die-temperature conversion enable in `TEMP_CONFIG`; self-clears
/// when the result latches into `TEMP_INT` / `TEMP_FRAC`.
const TEMP_EN: u8 = 1 << 0;

/// `TEMP_FRAC` carries the fraction in its low nibble, one LSB = 1/16 degC.
const TEMP_FRAC_MASK: u8 = 0x0F;

/// Bounded read budget for the temperature conversion to complete, matching the
/// `wait_reset` pattern so a dead bus fails fast instead of hanging.
const TEMP_POLL_MAX: u32 = 256;

/// Largest LEDx_PA register code. The field is a full 8-bit current DAC, so the
/// AGC clamps against this unless a lower `max_pa` caps the drive for thermal or
/// battery reasons.
pub const LED_PA_MAX: u8 = 0xFF;

#[derive(Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Error<E> {
    I2c(E),
    /// The reset bit never cleared within [`RESET_POLL_MAX`] reads.
    ResetTimeout,
    /// The temperature conversion never completed within [`TEMP_POLL_MAX`]
    /// reads.
    TempTimeout,
}

/// LED-current auto-gain window for [`agc_next_pa`]. `target_low`/`target_high`
/// are the desired DC operating band in raw 19-bit photodiode counts; the band
/// itself is the hysteresis dead-zone, so a level already inside it never moves
/// the drive. `step` is how many LEDx_PA codes each correction walks, and
/// `min_pa`/`max_pa` clamp the result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct AgcConfig {
    pub target_low: u32,
    pub target_high: u32,
    pub step: u8,
    pub min_pa: u8,
    pub max_pa: u8,
}

impl Default for AgcConfig {
    /// Centres the DC on roughly a quarter-to-three-fifths of the 0x7_FFFF full
    /// scale, leaving headroom for the pulsatile AC before the ADC rails. Bench-
    /// verify values alongside `MEAS1_LEDA_CURRENT`.
    fn default() -> Self {
        Self {
            target_low: 130_000,
            target_high: 300_000,
            step: 8,
            min_pa: 0x08,
            max_pa: 0xC0,
        }
    }
}

/// Propose the next LEDx_PA drive code from the measured DC level. Steps the
/// current up when the diode reads too dim (DC below the window), down when it
/// is saturating (DC above the window), and holds when the DC already sits in
/// the target band — the band is the hysteresis that stops one bright/dim pair
/// of samples from oscillating the drive. The result is clamped into
/// `[min_pa, max_pa]`, so a level pinned past a bound returns the bound rather
/// than wrapping.
pub fn agc_next_pa(dc: u32, current_pa: u8, cfg: &AgcConfig) -> u8 {
    let next = if dc < cfg.target_low {
        current_pa.saturating_add(cfg.step)
    } else if dc > cfg.target_high {
        current_pa.saturating_sub(cfg.step)
    } else {
        current_pa
    };
    next.clamp(cfg.min_pa, cfg.max_pa)
}

/// Decode the MAX86177 internal temperature channel to milli-degrees Celsius.
/// `TEMP_INT` is a signed whole-degree count (two's complement) and `TEMP_FRAC`
/// adds a positive 1/16-degC fraction from its low nibble, so a sub-zero reading
/// is e.g. int = -6, frac = 8 -> -5.500 degC. Milli-degC keeps the 0.0625-degC
/// LSB exact under integer division (62.5 milli-degC rounds half-up).
pub fn decode_die_temp_milli_c(temp_int: u8, temp_frac: u8) -> i32 {
    let whole = (temp_int as i8) as i32;
    let frac = (temp_frac & TEMP_FRAC_MASK) as i32;
    whole * 1000 + (frac * 625 + 5) / 10
}

pub struct Max86177<I2C> {
    i2c: I2C,
}

impl<I2C: I2c> Max86177<I2C> {
    pub fn new(i2c: I2C) -> Self {
        Self { i2c }
    }

    /// Soft-reset the part, configure a single-LED PPG channel, and start
    /// sampling into the FIFO. Leaves the device streaming.
    pub fn init(&mut self) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::SYSTEM_CONFIG_1, SW_RESET)?;
        self.wait_reset()?;

        self.write_reg(reg::FIFO_CONFIG_2, FIFO_FLUSH | FIFO_ROLLOVER)?;
        self.write_reg(reg::FIFO_CONFIG_1, FIFO_A_FULL)?;

        self.write_reg(reg::PPG_CONFIG_1, PPG_CONFIG_1)?;
        self.write_reg(reg::PPG_CONFIG_2, PPG_CONFIG_2)?;

        self.write_reg(reg::MEAS1_SELECT, MEAS1_SELECT)?;
        self.write_reg(reg::MEAS1_CONFIG_1, MEAS1_CONFIG_1)?;
        self.write_reg(reg::MEAS1_CONFIG_2, MEAS1_CONFIG_2)?;
        self.write_reg(reg::MEAS1_LEDA_CURRENT, MEAS1_LEDA_CURRENT)?;
        self.write_reg(reg::MEAS_ENABLE, MEAS1_ENABLE)?;

        self.write_reg(reg::SYSTEM_CONFIG_1, 0)?;
        Ok(())
    }

    /// Number of samples currently waiting in the FIFO.
    pub fn available(&mut self) -> Result<usize, Error<I2C::Error>> {
        Ok(self.read_reg(reg::FIFO_COUNTER)? as usize)
    }

    /// Pop one raw photodiode count from the FIFO, or `None` if it is empty.
    pub fn read_sample(&mut self) -> Result<Option<u32>, Error<I2C::Error>> {
        if self.available()? == 0 {
            return Ok(None);
        }
        let mut buf = [0u8; SAMPLE_BYTES];
        self.read_regs(reg::FIFO_DATA, &mut buf)?;
        let raw = (u32::from(buf[0]) << 16) | (u32::from(buf[1]) << 8) | u32::from(buf[2]);
        Ok(Some(raw & PPG_DATA_MASK))
    }

    /// Set the MEAS1 LED-A drive current (LEDx_PA register code). Pair with
    /// [`agc_next_pa`] to close the auto-gain loop over the streamed DC level.
    pub fn set_led_current(&mut self, pa: u8) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::MEAS1_LEDA_CURRENT, pa)
    }

    /// Trigger a one-shot internal die-temperature conversion and return it in
    /// milli-degrees Celsius. Blocks (bounded by [`TEMP_POLL_MAX`]) until the
    /// `TEMP_EN` bit self-clears, then reads and decodes the int/frac pair.
    pub fn read_die_temp_milli_c(&mut self) -> Result<i32, Error<I2C::Error>> {
        self.write_reg(reg::TEMP_CONFIG, TEMP_EN)?;
        self.wait_temp()?;
        let whole = self.read_reg(reg::TEMP_INT)?;
        let frac = self.read_reg(reg::TEMP_FRAC)?;
        Ok(decode_die_temp_milli_c(whole, frac))
    }

    /// Put the part into shutdown, releasing the LED drive current.
    pub fn shutdown(&mut self) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::SYSTEM_CONFIG_1, SHUTDOWN)
    }

    fn wait_temp(&mut self) -> Result<(), Error<I2C::Error>> {
        for _ in 0..TEMP_POLL_MAX {
            if self.read_reg(reg::TEMP_CONFIG)? & TEMP_EN == 0 {
                return Ok(());
            }
        }
        Err(Error::TempTimeout)
    }

    fn wait_reset(&mut self) -> Result<(), Error<I2C::Error>> {
        for _ in 0..RESET_POLL_MAX {
            if self.read_reg(reg::SYSTEM_CONFIG_1)? & SW_RESET == 0 {
                return Ok(());
            }
        }
        Err(Error::ResetTimeout)
    }

    fn write_reg(&mut self, reg: u8, val: u8) -> Result<(), Error<I2C::Error>> {
        self.i2c.write(I2C_ADDR, &[reg, val]).map_err(Error::I2c)
    }

    fn read_reg(&mut self, reg: u8) -> Result<u8, Error<I2C::Error>> {
        let mut buf = [0u8; 1];
        self.read_regs(reg, &mut buf)?;
        Ok(buf[0])
    }

    fn read_regs(&mut self, reg: u8, buf: &mut [u8]) -> Result<(), Error<I2C::Error>> {
        self.i2c
            .write_read(I2C_ADDR, &[reg], buf)
            .map_err(Error::I2c)
    }
}
