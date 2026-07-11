//! Host-side conversion tests. Run via `bin/watch-test.sh` from the repo root,
//! or `cargo test --target <HOST_TRIPLE> -p bmp581` from anywhere.

use bmp581::{altitude_from_pressure_m, raw_to_celsius, raw_to_pa, Bmp581, STANDARD_SEA_LEVEL_PA};
use embedded_hal::i2c::{ErrorType, I2c, Operation};

fn approx(a: f32, b: f32, tol: f32) -> bool {
    (a - b).abs() <= tol
}

/// A one-register-at-a-time fake bus: replies to INT_STATUS with data-ready and
/// to the pressure burst with a fixed 24-bit count, so the driver's altitude
/// path can be exercised on the host without hardware.
struct FakeBus {
    press_raw: u32,
}

impl ErrorType for FakeBus {
    type Error = core::convert::Infallible;
}

impl I2c for FakeBus {
    fn transaction(&mut self, _addr: u8, ops: &mut [Operation<'_>]) -> Result<(), Self::Error> {
        let mut reg = 0u8;
        for op in ops {
            match op {
                Operation::Write(bytes) => reg = bytes[0],
                Operation::Read(buf) => match reg {
                    0x27 => buf[0] = 0x01,
                    0x20 => {
                        let b = self.press_raw.to_le_bytes();
                        buf[..3].copy_from_slice(&b[..3]);
                    }
                    _ => {}
                },
            }
        }
        Ok(())
    }
}

fn driver_at_pa(pressure_pa: f32) -> Bmp581<FakeBus> {
    Bmp581::new(FakeBus {
        press_raw: (pressure_pa * 64.0) as u32,
    })
}

#[test]
fn sea_level_pressure() {
    // 101325 Pa * 64 counts/Pa = 6_484_800 raw.
    assert!(approx(raw_to_pa(6_484_800), 101_325.0, 0.01));
}

#[test]
fn zero_reads_zero() {
    assert_eq!(raw_to_pa(0), 0.0);
}

#[test]
fn high_altitude_low_pressure() {
    // ~9 km up, roughly 30 kPa: 30000 Pa * 64 = 1_920_000 raw.
    assert!(approx(raw_to_pa(1_920_000), 30_000.0, 0.01));
}

#[test]
fn one_count_is_a_sixty_fourth_pa() {
    assert!(approx(raw_to_pa(6_484_801), 101_325.015_625, 0.001));
}

#[test]
fn full_scale_24bit() {
    assert!(approx(raw_to_pa(0x00FF_FFFF), 262_143.98, 0.05));
}

#[test]
fn room_temperature() {
    // 25 °C * 65536 counts/°C = 1_638_400 raw.
    assert!(approx(raw_to_celsius(1_638_400), 25.0, 0.001));
}

#[test]
fn temperature_zero_reads_zero() {
    assert_eq!(raw_to_celsius(0), 0.0);
}

#[test]
fn sub_zero_temperature() {
    // -10 °C * 65536 = -655_360, two's-complement in 24 bits = 0xF6_0000.
    assert!(approx(raw_to_celsius(0x00F6_0000), -10.0, 0.001));
}

#[test]
fn one_count_is_a_sixty_five_thousandth_c() {
    assert!(approx(raw_to_celsius(1), 1.0 / 65_536.0, 1e-9));
}

#[test]
fn coldest_signed_temperature() {
    // Most-negative 24-bit value 0x80_0000 = -8_388_608 counts = -128 °C.
    assert!(approx(raw_to_celsius(0x0080_0000), -128.0, 0.001));
}

#[test]
fn sea_level_pressure_is_zero_altitude() {
    assert!(approx(
        altitude_from_pressure_m(STANDARD_SEA_LEVEL_PA, STANDARD_SEA_LEVEL_PA),
        0.0,
        0.01
    ));
}

#[test]
fn lower_pressure_is_positive_altitude() {
    // 44330 * (1 - (90000/101325)^(1/5.255)) = 988.647 m (hand-computed).
    assert!(approx(
        altitude_from_pressure_m(90_000.0, STANDARD_SEA_LEVEL_PA),
        988.647,
        0.5
    ));
}

#[test]
fn read_altitude_uses_default_reference() {
    let mut dev = driver_at_pa(90_000.0);
    let alt = dev.read_altitude_m().unwrap().unwrap();
    assert!(approx(alt, 988.647, 0.5));
}

#[test]
fn calibrating_reference_shifts_altitude() {
    let mut dev = driver_at_pa(90_000.0);
    dev.set_sea_level_pa(90_000.0);
    let alt = dev.read_altitude_m().unwrap().unwrap();
    assert!(approx(alt, 0.0, 0.01));
}

#[test]
fn implausible_qnh_is_rejected() {
    let mut dev = driver_at_pa(90_000.0);
    let baseline = dev.read_altitude_m().unwrap().unwrap();
    dev.set_sea_level_pa(f32::NAN);
    dev.set_sea_level_pa(50_000.0);
    dev.set_sea_level_pa(200_000.0);
    let after = dev.read_altitude_m().unwrap().unwrap();
    assert!(approx(after, baseline, 0.001));
}
