//! Driver for the Bosch BMP581 barometric pressure sensor over I²C.
//!
//! Delivers raw barometric pressure in Pascals plus the sensor's calibrated
//! ambient temperature in °C, and a QNH-calibrated altitude convenience
//! (`read_altitude_m`) off a settable sea-level reference; vertical-speed
//! derivation still lives in `watch_core::elevation`, not here. The `baro` task (per
//! `docs/architecture/decisions.md` § 90, the Apollo510B / BMP581 BOM refresh)
//! polls `read_pressure_pa` / `read_sample` and hands the reading upward.
//!
//! Generic over any blocking `embedded_hal::i2c::I2c`, so the same code runs on
//! the nRF52840 TWIM and under a mock bus in `cargo test`.

#![no_std]

use embedded_hal::i2c::I2c;

/// BMP581 7-bit I²C address with SDO tied low. The alternate address is `0x47`
/// (SDO high).
pub const I2C_ADDR: u8 = 0x46;

const EXPECTED_CHIP_ID: u8 = 0x50;
const CMD_SOFT_RESET: u8 = 0xB6;

// Output data rate field (ODR_CONFIG bits 6:2) selecting 50 Hz. Held fixed
// while the power mode varies; the `baro` task polls slower than this anyway.
const ODR_50HZ: u8 = 0x0F;

// INT_STATUS bit 0 asserts when a fresh sample is latched into the data regs.
const INT_STATUS_DRDY: u8 = 0x01;

mod reg {
    //! Addresses follow the BMP581 datasheet; bench-verify before the first
    //! on-board read.
    pub const CHIP_ID: u8 = 0x01;
    pub const INT_STATUS: u8 = 0x27;
    pub const TEMP_DATA_XLSB: u8 = 0x1D;
    pub const PRESS_DATA_XLSB: u8 = 0x20;
    pub const DSP_CONFIG: u8 = 0x30;
    pub const DSP_IIR: u8 = 0x31;
    pub const OSR_CONFIG: u8 = 0x36;
    pub const ODR_CONFIG: u8 = 0x37;
    pub const CMD: u8 = 0x7E;
}

/// Per-channel oversampling ratio. Each step doubles the number of internal
/// samples the sensor averages into one reading, trading conversion time and
/// current for lower noise. The discriminant is the raw `osr_p` / `osr_t`
/// field value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
#[repr(u8)]
pub enum Oversampling {
    X1 = 0,
    X2 = 1,
    X4 = 2,
    X8 = 3,
    X16 = 4,
    X32 = 5,
    X64 = 6,
    X128 = 7,
}

/// IIR low-pass filter coefficient. A higher coefficient smooths more heavily
/// (lower altitude jitter) at the cost of step-response lag. The discriminant
/// is the raw `set_iir_p` / `set_iir_t` field value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
#[repr(u8)]
pub enum IirFilter {
    Off = 0,
    Coeff1 = 1,
    Coeff3 = 2,
    Coeff7 = 3,
    Coeff15 = 4,
    Coeff31 = 5,
    Coeff63 = 6,
    Coeff127 = 7,
}

/// Sensor power / conversion mode. The discriminant is the raw `pwr_mode` field
/// in ODR_CONFIG. `Forced` runs one conversion then self-clears to `Standby`;
/// `Continuous` free-runs ignoring the ODR setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
#[repr(u8)]
pub enum PowerMode {
    Standby = 0,
    Normal = 1,
    Forced = 2,
    Continuous = 3,
}

/// Signal-conditioning configuration for the pressure/temperature pipeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Config {
    pub osr_pressure: Oversampling,
    pub osr_temperature: Oversampling,
    pub iir_pressure: IirFilter,
    pub iir_temperature: IirFilter,
    pub power_mode: PowerMode,
}

impl Default for Config {
    /// Ultra-watch altitude default: 16x pressure oversampling with a
    /// coefficient-7 IIR filter holds the altitude signal steady against
    /// second-to-second baro noise (the dominant error in the vert / GAP path),
    /// while keeping temperature light (2x, coefficient-1) since it only trims
    /// the pressure compensation. Normal mode free-runs at the configured ODR.
    fn default() -> Self {
        Self {
            osr_pressure: Oversampling::X16,
            osr_temperature: Oversampling::X2,
            iir_pressure: IirFilter::Coeff7,
            iir_temperature: IirFilter::Coeff1,
            power_mode: PowerMode::Normal,
        }
    }
}

#[derive(Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Error<E> {
    I2c(E),
    BadChipId,
}

/// One BMP581 conversion: barometric pressure in Pascals and the sensor's
/// calibrated ambient temperature in °C, both from the same data burst.
#[derive(Debug, Clone, Copy, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Sample {
    pub pressure_pa: f32,
    pub temperature_c: f32,
}

pub struct Bmp581<I2C> {
    i2c: I2C,
    addr: u8,
    sea_level_pa: f32,
}

impl<I2C, E> Bmp581<I2C>
where
    I2C: I2c<Error = E>,
{
    pub fn new(i2c: I2C) -> Self {
        Self {
            i2c,
            addr: I2C_ADDR,
            sea_level_pa: STANDARD_SEA_LEVEL_PA,
        }
    }

    /// Sets the sea-level reference pressure (QNH) used by `read_altitude_m`,
    /// e.g. from an aviation METAR or a known-elevation calibration point.
    /// Non-finite values or values outside the physically plausible QNH range
    /// are ignored, so a garbage reading can never poison the reference.
    pub fn set_sea_level_pa(&mut self, pa: f32) {
        if pa.is_finite() && (87_000.0..=108_500.0).contains(&pa) {
            self.sea_level_pa = pa;
        }
    }

    /// Reads pressure and converts it to altitude in metres against the
    /// calibrated sea-level reference. `Ok(None)` when no fresh sample is ready,
    /// mirroring `read_pressure_pa`.
    pub fn read_altitude_m(&mut self) -> Result<Option<f32>, Error<E>> {
        Ok(self
            .read_pressure_pa()?
            .map(|pa| altitude_from_pressure_m(pa, self.sea_level_pa)))
    }

    pub fn init(&mut self) -> Result<(), Error<E>> {
        self.write_reg(reg::CMD, CMD_SOFT_RESET)?;
        let id = self.read_reg(reg::CHIP_ID)?;
        if id != EXPECTED_CHIP_ID {
            return Err(Error::BadChipId);
        }
        self.configure(&Config::default())
    }

    /// Programs oversampling, the IIR filter and the power mode from `cfg`. The
    /// OSR and DSP registers latch cleanly only while not actively converting,
    /// so the sensor is dropped to standby first and the requested power mode is
    /// brought up last.
    pub fn configure(&mut self, cfg: &Config) -> Result<(), Error<E>> {
        self.write_reg(
            reg::ODR_CONFIG,
            encode_odr_config(ODR_50HZ, PowerMode::Standby),
        )?;
        self.write_reg(
            reg::OSR_CONFIG,
            encode_osr_config(cfg.osr_pressure, cfg.osr_temperature),
        )?;
        self.write_reg(
            reg::DSP_CONFIG,
            encode_dsp_config(cfg.iir_pressure, cfg.iir_temperature),
        )?;
        self.write_reg(
            reg::DSP_IIR,
            encode_dsp_iir(cfg.iir_pressure, cfg.iir_temperature),
        )?;
        self.write_reg(reg::ODR_CONFIG, encode_odr_config(ODR_50HZ, cfg.power_mode))?;
        Ok(())
    }

    pub fn read_pressure_pa(&mut self) -> Result<Option<f32>, Error<E>> {
        if self.read_reg(reg::INT_STATUS)? & INT_STATUS_DRDY == 0 {
            return Ok(None);
        }
        let mut buf = [0u8; 3];
        self.read_regs(reg::PRESS_DATA_XLSB, &mut buf)?;
        let raw = u32::from(buf[0]) | (u32::from(buf[1]) << 8) | (u32::from(buf[2]) << 16);
        Ok(Some(raw_to_pa(raw)))
    }

    /// Reads temperature and pressure from the single 6-byte data burst
    /// (`TEMP_DATA_XLSB`..`PRESS_DATA_MSB`). Temperature registers precede
    /// pressure in the readout, so one `write_read` fetches both.
    pub fn read_sample(&mut self) -> Result<Option<Sample>, Error<E>> {
        if self.read_reg(reg::INT_STATUS)? & INT_STATUS_DRDY == 0 {
            return Ok(None);
        }
        let mut buf = [0u8; 6];
        self.read_regs(reg::TEMP_DATA_XLSB, &mut buf)?;
        let temp_raw = u32::from(buf[0]) | (u32::from(buf[1]) << 8) | (u32::from(buf[2]) << 16);
        let press_raw = u32::from(buf[3]) | (u32::from(buf[4]) << 8) | (u32::from(buf[5]) << 16);
        Ok(Some(Sample {
            pressure_pa: raw_to_pa(press_raw),
            temperature_c: raw_to_celsius(temp_raw),
        }))
    }

    fn write_reg(&mut self, reg: u8, val: u8) -> Result<(), Error<E>> {
        self.i2c.write(self.addr, &[reg, val]).map_err(Error::I2c)
    }

    fn read_reg(&mut self, reg: u8) -> Result<u8, Error<E>> {
        let mut buf = [0u8; 1];
        self.i2c
            .write_read(self.addr, &[reg], &mut buf)
            .map_err(Error::I2c)?;
        Ok(buf[0])
    }

    fn read_regs(&mut self, reg: u8, buf: &mut [u8]) -> Result<(), Error<E>> {
        self.i2c
            .write_read(self.addr, &[reg], buf)
            .map_err(Error::I2c)
    }
}

/// Packs OSR_CONFIG (0x36): `press_en` (bit 6, always set so pressure is
/// enabled alongside temperature) | `osr_p` (bits 5:3) | `osr_t` (bits 2:0).
pub fn encode_osr_config(osr_p: Oversampling, osr_t: Oversampling) -> u8 {
    const PRESS_EN: u8 = 1 << 6;
    PRESS_EN | ((osr_p as u8) << 3) | (osr_t as u8)
}

/// Packs ODR_CONFIG (0x37): `odr` (bits 6:2) | `pwr_mode` (bits 1:0). `deep_dis`
/// (bit 7) is left clear so deep-standby stays available from `Standby`.
pub fn encode_odr_config(odr: u8, power_mode: PowerMode) -> u8 {
    ((odr & 0x1F) << 2) | (power_mode as u8)
}

/// Packs DSP_IIR (0x31): `set_iir_p` (bits 5:3) | `set_iir_t` (bits 2:0).
pub fn encode_dsp_iir(iir_p: IirFilter, iir_t: IirFilter) -> u8 {
    ((iir_p as u8) << 3) | (iir_t as u8)
}

/// Packs DSP_CONFIG (0x30) so the data registers read back the IIR-filtered,
/// compensated values. `comp_pt_en` (bits 1:0) enables pressure+temperature
/// compensation; the `shdw_sel_iir_*` bits route the filtered signal into the
/// data registers, but only for a channel whose filter is actually engaged —
/// with `IirFilter::Off` the raw compensated value is what we want.
pub fn encode_dsp_config(iir_p: IirFilter, iir_t: IirFilter) -> u8 {
    const COMP_PT_EN: u8 = 0x03;
    const SHDW_SEL_IIR_T: u8 = 1 << 3;
    const SHDW_SEL_IIR_P: u8 = 1 << 5;
    let mut v = COMP_PT_EN;
    if !matches!(iir_t, IirFilter::Off) {
        v |= SHDW_SEL_IIR_T;
    }
    if !matches!(iir_p, IirFilter::Off) {
        v |= SHDW_SEL_IIR_P;
    }
    v
}

/// BMP581 pressure is a 24-bit fixed-point count with an LSB of 1/64 Pa, so
/// dividing by 64 yields Pascals directly.
pub fn raw_to_pa(raw: u32) -> f32 {
    raw as f32 / 64.0
}

/// BMP581 temperature is a *signed* 24-bit fixed-point count with an LSB of
/// 1/65536 °C, so sign-extending the 24-bit value to `i32` and dividing by
/// 2^16 yields °C directly.
pub fn raw_to_celsius(raw: u32) -> f32 {
    let signed = ((raw << 8) as i32) >> 8;
    signed as f32 / 65536.0
}

/// ISA sea-level standard pressure (101.325 kPa), the default QNH reference.
pub const STANDARD_SEA_LEVEL_PA: f32 = 101_325.0;

/// International barometric altitude formula: converts a pressure reading to a
/// height above the `sea_level_pa` reference. The `44330.0` scale and `5.255`
/// exponent are the standard-atmosphere constants (0–11 km troposphere), so the
/// result is metres above the surface where pressure equals `sea_level_pa`.
/// Feeding a QNH-calibrated reference removes the day's weather bias.
pub fn altitude_from_pressure_m(pressure_pa: f32, sea_level_pa: f32) -> f32 {
    44330.0 * (1.0 - libm::powf(pressure_pa / sea_level_pa, 1.0 / 5.255))
}
