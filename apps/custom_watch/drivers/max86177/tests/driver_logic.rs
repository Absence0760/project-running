//! Host-side tests for the driver's pure register-logic helpers: the LED-current
//! auto-gain step and the internal die-temperature decode. Run via
//! `bin/watch-test.sh` from the repo root, or `cargo test --target <HOST_TRIPLE>
//! -p max86177` from anywhere. These touch no peripheral, only the integer math
//! that decides a register value.

use max86177::{
    agc_next_pa, agc_next_pa_ambient, decode_die_temp_milli_c, decode_fifo_word, AgcConfig,
    FifoWord, Max86177, I2C_ADDR, LED_PA_MAX, MEAS1_TAG, MEAS2_TAG,
};

use std::cell::RefCell;
use std::rc::Rc;

/// Records every register write into a shared log so a test can pin the exact
/// wire traffic a driver method produces (the driver owns the bus, so the log
/// handle is what stays inspectable); reads return zeroes.
#[derive(Clone, Default)]
struct MockI2c {
    writes: Rc<RefCell<Vec<Vec<u8>>>>,
}

impl embedded_hal::i2c::ErrorType for MockI2c {
    type Error = core::convert::Infallible;
}

impl embedded_hal::i2c::I2c for MockI2c {
    fn transaction(
        &mut self,
        address: u8,
        operations: &mut [embedded_hal::i2c::Operation<'_>],
    ) -> Result<(), Self::Error> {
        assert_eq!(address, I2C_ADDR);
        for op in operations {
            match op {
                embedded_hal::i2c::Operation::Write(bytes) => {
                    self.writes.borrow_mut().push(bytes.to_vec())
                }
                embedded_hal::i2c::Operation::Read(buf) => buf.fill(0),
            }
        }
        Ok(())
    }
}

#[test]
fn dim_signal_steps_current_up() {
    let cfg = AgcConfig::default();
    let next = agc_next_pa(cfg.target_low - 50_000, 0x40, &cfg);
    assert_eq!(next, 0x40 + cfg.step, "a dim DC must raise the LED drive");
}

#[test]
fn saturating_signal_steps_current_down() {
    let cfg = AgcConfig::default();
    let next = agc_next_pa(cfg.target_high + 50_000, 0x40, &cfg);
    assert_eq!(
        next,
        0x40 - cfg.step,
        "a railing DC must lower the LED drive"
    );
}

#[test]
fn in_window_holds_the_current() {
    let cfg = AgcConfig::default();
    let mid = (cfg.target_low + cfg.target_high) / 2;
    assert_eq!(
        agc_next_pa(mid, 0x40, &cfg),
        0x40,
        "a DC inside the target band must not move the drive"
    );
    assert_eq!(
        agc_next_pa(cfg.target_low, 0x40, &cfg),
        0x40,
        "the low edge is inside the band"
    );
    assert_eq!(
        agc_next_pa(cfg.target_high, 0x40, &cfg),
        0x40,
        "the high edge is inside the band"
    );
}

#[test]
fn step_up_clamps_at_max() {
    let cfg = AgcConfig::default();
    let near_max = cfg.max_pa - cfg.step / 2;
    let next = agc_next_pa(0, near_max, &cfg);
    assert_eq!(next, cfg.max_pa, "stepping up must not exceed max_pa");
}

#[test]
fn step_down_clamps_at_min() {
    let cfg = AgcConfig::default();
    let near_min = cfg.min_pa + cfg.step / 2;
    let next = agc_next_pa(u32::MAX, near_min, &cfg);
    assert_eq!(next, cfg.min_pa, "stepping down must not fall below min_pa");
}

#[test]
fn saturating_add_cannot_wrap_past_the_register() {
    let cfg = AgcConfig {
        max_pa: LED_PA_MAX,
        ..AgcConfig::default()
    };
    let next = agc_next_pa(0, LED_PA_MAX - 1, &cfg);
    assert_eq!(
        next, LED_PA_MAX,
        "a near-full code must saturate, not wrap to 0"
    );
}

#[test]
fn converges_into_the_window_and_holds() {
    // A simple monotone optical model: DC scales with the drive code. Closing the
    // loop must walk the drive until the DC lands inside the band and then leave
    // it there forever — the anti-oscillation guarantee, not just a single step.
    let cfg = AgcConfig::default();
    let gain = 3_000u32;
    let mut pa = cfg.min_pa;

    for _ in 0..256 {
        let dc = u32::from(pa) * gain;
        pa = agc_next_pa(dc, pa, &cfg);
    }

    let settled = pa;
    let dc = u32::from(settled) * gain;
    assert!(
        dc >= cfg.target_low && dc <= cfg.target_high,
        "loop must settle inside the window, got dc {dc} at pa {settled}"
    );

    for _ in 0..32 {
        let dc = u32::from(pa) * gain;
        pa = agc_next_pa(dc, pa, &cfg);
        assert_eq!(pa, settled, "a settled loop must not oscillate");
    }
}

#[test]
fn fifo_word_splits_tag_from_count() {
    // Low 19 bits are the count; the five bits above carry the measurement tag.
    // A MEAS1 word (tag 0x01) at 0x12345 counts.
    let count = 0x1_2345u32;
    let raw = (u32::from(MEAS1_TAG) << 19) | count;
    let buf = [(raw >> 16) as u8, (raw >> 8) as u8, raw as u8];
    assert_eq!(
        decode_fifo_word(buf),
        FifoWord {
            tag: MEAS1_TAG,
            value: count
        }
    );
}

#[test]
fn fifo_word_distinguishes_ambient_from_ppg() {
    let count = 0x7_FFFFu32;
    let ppg = (u32::from(MEAS1_TAG) << 19) | count;
    let amb = (u32::from(MEAS2_TAG) << 19) | count;
    let ppg_buf = [(ppg >> 16) as u8, (ppg >> 8) as u8, ppg as u8];
    let amb_buf = [(amb >> 16) as u8, (amb >> 8) as u8, amb as u8];
    assert_eq!(decode_fifo_word(ppg_buf).tag, MEAS1_TAG);
    assert_eq!(decode_fifo_word(amb_buf).tag, MEAS2_TAG);
    // Same underlying count, told apart only by the tag.
    assert_eq!(decode_fifo_word(ppg_buf).value, count);
    assert_eq!(decode_fifo_word(amb_buf).value, count);
}

#[test]
fn fifo_word_masks_the_full_data_field() {
    // A max-scale count with a tag set must return the count intact, never
    // letting the tag bleed into the value.
    let raw = 0xFF_FFFFu32;
    let buf = [(raw >> 16) as u8, (raw >> 8) as u8, raw as u8];
    let w = decode_fifo_word(buf);
    assert_eq!(w.value, 0x7_FFFF, "value is the low 19 bits");
    assert_eq!(w.tag, 0x1F, "tag is the five bits above");
}

#[test]
fn decode_temp_whole_degrees() {
    assert_eq!(decode_die_temp_milli_c(25, 0), 25_000);
    assert_eq!(decode_die_temp_milli_c(37, 0), 37_000);
}

#[test]
fn decode_temp_fractional_bits() {
    assert_eq!(decode_die_temp_milli_c(25, 8), 25_500, "8/16 = 0.5 degC");
    assert_eq!(decode_die_temp_milli_c(37, 4), 37_250, "4/16 = 0.25 degC");
    assert_eq!(
        decode_die_temp_milli_c(36, 15),
        36_938,
        "15/16 = 0.9375 degC, rounded to milli"
    );
}

#[test]
fn decode_temp_ignores_upper_frac_bits() {
    // Only the low nibble of TEMP_FRAC is the fraction; reserved upper bits set
    // must not leak into the reading.
    assert_eq!(
        decode_die_temp_milli_c(20, 0xF8),
        decode_die_temp_milli_c(20, 0x08)
    );
}

#[test]
fn decode_temp_negative() {
    // Two's-complement whole part with a positive added fraction: -6 + 8/16.
    assert_eq!(decode_die_temp_milli_c(0xFA, 8), -5_500);
    assert_eq!(decode_die_temp_milli_c(0xFF, 0), -1_000);
}

#[test]
fn rail_guard_sheds_drive_even_when_corrected_is_dim() {
    // Blinding ambient: the raw DC is past the clip guard while the corrected
    // (LED-reflected) DC reads dim. A corrected-only loop would step UP into
    // the rail; the guard must win and step DOWN — driving the LED harder into
    // an ADC near its rail only deepens the clip.
    let cfg = AgcConfig::default();
    let next = agc_next_pa_ambient(cfg.raw_ceiling + 10_000, 1_000, 0x40, &cfg);
    assert_eq!(next, 0x40 - cfg.step);
}

#[test]
fn rail_guard_clamps_at_min_pa() {
    let cfg = AgcConfig::default();
    let next = agc_next_pa_ambient(cfg.raw_ceiling + 10_000, 1_000, cfg.min_pa, &cfg);
    assert_eq!(next, cfg.min_pa, "the guard clamps at min_pa, never wraps");
}

#[test]
fn ambient_swings_below_the_ceiling_never_move_the_drive() {
    // The anti-oscillation property: with the corrected DC parked inside the
    // target band, raw-DC excursions from ambient (clouds, shade, a headlamp)
    // anywhere up to the ceiling must not walk the LED current — ambient
    // cancels out of the corrected level the band judges.
    let cfg = AgcConfig::default();
    let corrected = (cfg.target_low + cfg.target_high) / 2;
    for raw in [corrected, 350_000, 460_000, cfg.raw_ceiling] {
        assert_eq!(
            agc_next_pa_ambient(raw, corrected, 0x40, &cfg),
            0x40,
            "raw {raw} at/below the ceiling must hold the drive"
        );
    }
}

#[test]
fn ambient_loop_converges_and_holds_under_steady_ambient() {
    // Closed-loop model with a large but sub-rail ambient bleed: raw = ambient
    // + gain*pa, corrected = gain*pa. Starting over-driven (raw past the
    // ceiling), the guard walks the drive down until conversion headroom is
    // back, the band then finishes the job, and the settled point holds — the
    // whole-loop anti-oscillation guarantee of `converges_into_the_window_and_
    // holds`, under ambient.
    let cfg = AgcConfig::default();
    let ambient = 150_000u32;
    let gain = 3_000u32;
    let mut pa = cfg.max_pa;

    for _ in 0..256 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
    }

    let settled = pa;
    let corrected = u32::from(settled) * gain;
    assert!(
        corrected >= cfg.target_low && corrected <= cfg.target_high,
        "loop must settle the corrected DC inside the window, got {corrected} at pa {settled}"
    );
    assert!(
        ambient + corrected <= cfg.raw_ceiling,
        "the settled raw level must respect the ceiling"
    );

    for _ in 0..32 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
        assert_eq!(pa, settled, "a settled ambient loop must not oscillate");
    }
}

#[test]
fn blinding_ambient_walks_to_the_floor_and_stays() {
    // Ambient alone far past the ceiling, whatever the LED does: the loop must
    // walk the drive to min_pa and hold — the honest floor while the peak
    // detector reports Saturated. It must never bounce back up against the dim
    // corrected read that scene produces.
    let cfg = AgcConfig::default();
    let ambient = 520_000u32;
    let gain = 500u32;
    let mut pa = 0x40;
    for _ in 0..64 {
        let corrected = u32::from(pa) * gain;
        pa = agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg);
    }
    assert_eq!(pa, cfg.min_pa);
    let corrected = u32::from(pa) * gain; // dim — unguarded, this would step up
    assert_eq!(
        agc_next_pa_ambient(ambient + corrected, corrected, pa, &cfg),
        cfg.min_pa
    );
}

#[test]
fn init_configures_the_interleaved_ambient_channel() {
    // Pin the full init register sequence — the config "wire format". The
    // ambient path hinges on the MEAS2 block: the same ADC config as MEAS1
    // (same scale, so the two counts subtract directly) with NO LED selected
    // (0x00 — what makes it a dark read), and BOTH measurement slots enabled
    // (0x03) so the FIFO interleaves tagged PPG + ambient words. Reads (the
    // reset poll) aren't writes and don't appear in the log.
    let bus = MockI2c::default();
    let log = bus.writes.clone();
    let mut sensor = Max86177::new(bus);
    sensor.init().unwrap();
    // A register write is a 2-byte [reg, val] transfer; the reset poll's read
    // addressing shows up as a 1-byte [reg] write — drop it, keep the config.
    let writes: Vec<Vec<u8>> = log
        .borrow()
        .iter()
        .filter(|w| w.len() == 2)
        .cloned()
        .collect();
    assert_eq!(
        writes,
        vec![
            vec![0x10, 0x01], // SYSTEM_CONFIG_1 <- SW_RESET
            vec![0x0E, 0x12], // FIFO_CONFIG_2 <- FLUSH | ROLLOVER
            vec![0x0D, 0x0F], // FIFO_CONFIG_1 <- almost-full threshold
            vec![0x11, 0x24], // PPG_CONFIG_1 <- 100 Hz, no averaging
            vec![0x12, 0x18], // PPG_CONFIG_2 <- mid-scale ADC range
            vec![0x14, 0x01], // MEAS1_SELECT <- LED A: the PPG slot
            vec![0x15, 0x20], // MEAS1_CONFIG_1
            vec![0x16, 0x00], // MEAS1_CONFIG_2
            vec![0x19, 0x40], // MEAS1_LEDA_CURRENT <- LED_PA_DEFAULT
            vec![0x1A, 0x00], // MEAS2_SELECT <- no LED: the ambient slot
            vec![0x1B, 0x20], // MEAS2_CONFIG_1 == MEAS1_CONFIG_1 (same scale)
            vec![0x1C, 0x00], // MEAS2_CONFIG_2 == MEAS1_CONFIG_2
            vec![0x13, 0x03], // MEAS_ENABLE <- MEAS1 | MEAS2 (interleaved)
            vec![0x10, 0x00], // SYSTEM_CONFIG_1 <- run
        ]
    );
}

#[test]
fn duty_cycle_wake_leaves_the_ambient_config_in_place() {
    // The HR duty-cycle path: init once, then shutdown/wake per window. Wake
    // touches only SYSTEM_CONFIG_1 (resume) + FIFO_CONFIG_2 (flush the
    // interleaved pre-shutdown words, PPG and ambient alike) — it must NOT
    // rewrite or clobber the MEAS2 block or MEAS_ENABLE, whose survival across
    // shutdown is register retention (SHDN keeps register state; a datasheet
    // assumption to bench-verify). If wake needed a re-init, the ambient
    // channel would silently drop out after the first duty window.
    let bus = MockI2c::default();
    let log = bus.writes.clone();
    let mut sensor = Max86177::new(bus);
    sensor.init().unwrap();
    log.borrow_mut().clear();
    sensor.shutdown().unwrap();
    sensor.wake().unwrap();
    let traffic = log.borrow().clone();
    assert_eq!(
        traffic,
        vec![vec![0x10, 0x02], vec![0x10, 0x00], vec![0x0E, 0x12]]
    );
    for w in &traffic {
        assert!(
            !matches!(w[0], 0x13 | 0x1A | 0x1B | 0x1C),
            "shutdown/wake must not touch the ambient measurement config"
        );
    }
}

#[test]
fn shutdown_sets_only_the_shutdown_bit() {
    // SYSTEM_CONFIG_1 (0x10) <- SHDN (bit 1), and nothing else: RESET (bit 0)
    // alongside it would wipe the measurement config wake() relies on
    // surviving. A stored wire format in spirit — pin it.
    let bus = MockI2c::default();
    let log = bus.writes.clone();
    let mut sensor = Max86177::new(bus);
    sensor.shutdown().unwrap();
    assert_eq!(*log.borrow(), vec![vec![0x10, 0x02]]);
}

#[test]
fn wake_clears_shutdown_then_flushes_the_fifo() {
    // SYSTEM_CONFIG_1 (0x10) <- 0 resumes sampling; FIFO_CONFIG_2 (0x0E) <-
    // FLUSH|ROLLOVER (0x12) discards counts buffered before the shutdown so
    // they can't replay into a freshly reset detector, keeping the rollover
    // behaviour init configured. Order matters: flushing after the wake also
    // drops any pre-wake residue.
    let bus = MockI2c::default();
    let log = bus.writes.clone();
    let mut sensor = Max86177::new(bus);
    sensor.wake().unwrap();
    assert_eq!(*log.borrow(), vec![vec![0x10, 0x00], vec![0x0E, 0x12]]);
}

#[test]
fn wake_round_trips_a_shutdown() {
    // The duty-cycling pattern: shutdown then wake leaves the part sampling
    // with the same traffic a bare wake produces — no re-init in between.
    let bus = MockI2c::default();
    let log = bus.writes.clone();
    let mut sensor = Max86177::new(bus);
    sensor.shutdown().unwrap();
    sensor.wake().unwrap();
    assert_eq!(
        *log.borrow(),
        vec![vec![0x10, 0x02], vec![0x10, 0x00], vec![0x0E, 0x12]]
    );
}

#[test]
fn decode_temp_smallest_step() {
    assert_eq!(
        decode_die_temp_milli_c(0, 1),
        63,
        "1/16 = 0.0625 degC -> 63 milli"
    );
}
