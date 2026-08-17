//! Host-side tests for the MAX30101 driver. Run via `bin/watch-test.sh` from
//! the repo root, or `cargo test --target <HOST_TRIPLE> -p max30101` from
//! anywhere.
//!
//! The centre of gravity here is **slot phase**. This part's FIFO carries no
//! per-sample tag — samples arrive one per enabled slot, in slot order — so the
//! driver derives the tag from read position, and a single sample read out of
//! step transposes PPG and ambient for the rest of the window. Nothing
//! downstream can detect that: `hr_drain` demuxes on the tag it is handed, and
//! a transposed stream produces a plausible, wrong heart rate. So the tests
//! that matter are the ones that try to slip the phase.

use max30101::{
    assign_tag, decode_die_temp_milli_c, decode_sample, Error, Max30101, AMBIENT_TAG, I2C_ADDR,
    LED_PA_DEFAULT, PART_ID, PPG_TAG, SLOTS,
};
use watch_core::ppg::{FifoWord, PpgAfe, PpgScale};

use std::cell::RefCell;
use std::rc::Rc;

/// FIFO pointer registers, so a fixture can stage exactly N unread samples.
const REG_FIFO_WR_PTR: u8 = 0x04;
const REG_FIFO_RD_PTR: u8 = 0x06;
const REG_FIFO_DATA: u8 = 0x07;
const REG_MODE_CONFIG: u8 = 0x09;
const REG_PART_ID: u8 = 0xFF;

const REG_OVF_COUNTER: u8 = 0x05;

#[derive(Default)]
struct Bus {
    writes: Vec<Vec<u8>>,
    /// Samples staged for `FIFO_DATA` to hand back, oldest first.
    fifo: Vec<u32>,
    /// What `OVF_COUNTER` reports — non-zero means the part dropped samples.
    overflow: u8,
    part_id: u8,
}

/// A mock that answers register reads plausibly enough to drive the real code
/// path: `PART_ID` returns a configurable id, `MODE_CONFIG` reads back
/// self-cleared (so the reset poll terminates), the FIFO pointers report the
/// staged sample count, and `FIFO_DATA` serves staged samples as 3-byte words.
#[derive(Clone, Default)]
struct MockI2c(Rc<RefCell<Bus>>);

impl MockI2c {
    fn new(part_id: u8) -> Self {
        let m = Self::default();
        m.0.borrow_mut().part_id = part_id;
        m
    }

    fn stage(&self, samples: &[u32]) {
        self.0.borrow_mut().fifo.extend_from_slice(samples);
    }

    fn set_overflow(&self, n: u8) {
        self.0.borrow_mut().overflow = n;
    }

    fn writes(&self) -> Vec<Vec<u8>> {
        self.0.borrow().writes.clone()
    }

    fn clear_writes(&self) {
        self.0.borrow_mut().writes.clear();
    }
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
        let mut pending: Option<u8> = None;
        for op in operations {
            match op {
                embedded_hal::i2c::Operation::Write(bytes) => {
                    if bytes.len() == 1 {
                        pending = Some(bytes[0]);
                    } else {
                        let mut bus = self.0.borrow_mut();
                        bus.writes.push(bytes.to_vec());
                        // Honour the two writes that change what a later read
                        // sees, like the real part: zeroing the read pointer
                        // discards unread samples, and writing the overflow
                        // counter sets it. A mock that ignored these would let
                        // a flush test pass while stale samples were still
                        // being served.
                        match (bytes[0], bytes[1]) {
                            (REG_FIFO_RD_PTR, 0) => bus.fifo.clear(),
                            (REG_OVF_COUNTER, v) => bus.overflow = v,
                            _ => {}
                        }
                    }
                }
                embedded_hal::i2c::Operation::Read(buf) => {
                    let reg = pending.expect("read without a register address");
                    let mut bus = self.0.borrow_mut();
                    match reg {
                        REG_PART_ID => buf[0] = bus.part_id,
                        // Reset bit reads back clear, so `wait_reset` returns.
                        REG_MODE_CONFIG => buf[0] = 0,
                        REG_OVF_COUNTER => buf[0] = bus.overflow,
                        REG_FIFO_WR_PTR => buf[0] = bus.fifo.len() as u8,
                        REG_FIFO_RD_PTR => buf[0] = 0,
                        REG_FIFO_DATA => {
                            for chunk in buf.chunks_mut(3) {
                                let v = if bus.fifo.is_empty() {
                                    0
                                } else {
                                    bus.fifo.remove(0)
                                };
                                chunk[0] = (v >> 16) as u8;
                                chunk[1] = (v >> 8) as u8;
                                chunk[2] = v as u8;
                            }
                        }
                        _ => buf.fill(0),
                    }
                }
            }
        }
        Ok(())
    }
}

fn inited(bus: &MockI2c) -> Max30101<MockI2c> {
    let mut s = Max30101::new(bus.clone());
    s.init().unwrap();
    bus.clear_writes();
    s
}

#[test]
fn sample_decode_masks_to_eighteen_bits() {
    // The top six bits of the 24-bit word are not data. A part that leaves them
    // set must not inflate the count — an 18-bit rail read as a 24-bit value
    // would sail past every contact threshold.
    assert_eq!(decode_sample([0xFF, 0xFF, 0xFF]), 0x3_FFFF);
    assert_eq!(decode_sample([0x00, 0x01, 0x02]), 0x102);
    assert_eq!(decode_sample([0x03, 0xFF, 0xFF]), 0x3_FFFF);
    assert_eq!(decode_sample([0x00, 0x00, 0x00]), 0);
}

#[test]
fn tags_alternate_by_position() {
    assert_eq!(assign_tag(0), PPG_TAG);
    assert_eq!(assign_tag(1), AMBIENT_TAG);
}

#[test]
fn an_out_of_range_index_folds_onto_ambient_not_ppg() {
    // The fail-safe direction: a mis-indexed sample fed as ambient perturbs a
    // subtraction, one fed as PPG is a fabricated pulse sample.
    for i in SLOTS..SLOTS + 8 {
        if i % SLOTS != 0 {
            assert_eq!(assign_tag(i), AMBIENT_TAG, "index {i}");
        }
    }
}

#[test]
fn wrong_part_id_is_refused_before_anything_is_configured() {
    // A MAX30102 answers on the same address and takes most of the same
    // configuration, but has no green emitter. Discovering that after
    // programming it leaves a device streaming a plausible, wrong pulse.
    let bus = MockI2c::new(0x11);
    let mut sensor = Max30101::new(bus.clone());
    match sensor.init() {
        Err(Error::WrongPart(id)) => assert_eq!(id, 0x11),
        other => panic!("expected WrongPart, got {other:?}"),
    }
    assert!(
        bus.writes().is_empty(),
        "no register may be written before the part is identified"
    );
}

#[test]
fn init_configures_green_ppg_plus_a_dark_ambient_slot() {
    // The config wire format. Two things are load-bearing: slot 1 selects LED3
    // (green — the wrist wavelength), and slot 2 selects nothing (0x00), which
    // is what makes it a dark read on the same photodiode and the same scale.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = Max30101::new(bus.clone());
    sensor.init().unwrap();
    assert_eq!(
        bus.writes(),
        vec![
            vec![0x09, 0x40],           // MODE_CONFIG <- RESET
            vec![0x08, 0x10],           // FIFO_CONFIG <- rollover, no averaging
            vec![0x0A, 0x27],           // SPO2_CONFIG <- 4096nA, 100 Hz, 411us
            vec![0x0C, 0x00],           // LED1_PA (red) dark
            vec![0x0D, 0x00],           // LED2_PA (IR) dark
            vec![0x0E, LED_PA_DEFAULT], // LED3_PA (green) <- drive seed
            vec![0x0F, 0x00],           // LED4_PA (second green) dark
            vec![0x11, 0x03],           // SLOT_12 <- slot1 = LED3 green, slot2 = none
            vec![0x12, 0x00],           // SLOT_34 <- disabled
            vec![0x09, 0x07],           // MODE_CONFIG <- multi-LED
            vec![0x04, 0x00],           // FIFO_WR_PTR <- 0
            vec![0x05, 0x00],           // OVF_COUNTER <- 0
            vec![0x06, 0x00],           // FIFO_RD_PTR <- 0
        ]
    );
}

#[test]
fn a_partial_frame_yields_nothing_rather_than_slipping_phase() {
    // The bug this driver exists to prevent. One sample sitting in the FIFO is
    // the first half of a frame still being written; serving it would make the
    // NEXT read return the ambient sample tagged as PPG, and every sample after
    // that would be transposed too.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = inited(&bus);
    bus.stage(&[1234]);
    assert_eq!(sensor.read_tagged_sample().unwrap(), None);

    // The partial frame is still there; completing it releases both, in order.
    bus.stage(&[5678]);
    assert_eq!(
        sensor.read_tagged_sample().unwrap(),
        Some(FifoWord {
            tag: PPG_TAG,
            value: 1234
        })
    );
    assert_eq!(
        sensor.read_tagged_sample().unwrap(),
        Some(FifoWord {
            tag: AMBIENT_TAG,
            value: 5678
        })
    );
}

#[test]
fn a_long_drain_keeps_every_frame_in_phase() {
    // Ten frames drained in one pass: PPG counts are even, ambient odd, so a
    // single slipped sample shows up as a parity mismatch rather than as a
    // subtly wrong number.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = inited(&bus);
    let staged: Vec<u32> = (0..20).collect();
    bus.stage(&staged);

    let mut got = Vec::new();
    while let Some(w) = sensor.read_tagged_sample().unwrap() {
        got.push(w);
    }
    assert_eq!(got.len(), 20);
    for (i, w) in got.iter().enumerate() {
        assert_eq!(w.value, i as u32);
        let expected = if i % 2 == 0 { PPG_TAG } else { AMBIENT_TAG };
        assert_eq!(w.tag, expected, "sample {i} landed on the wrong slot");
    }
}

#[test]
fn a_duty_cycle_wake_restarts_phase_rather_than_inheriting_it() {
    // A window that ends mid-frame must not leave the next window reading the
    // leftover sample as its first PPG count. wake() flushes, which resets both
    // the part's pointers and the host-side frame index.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = inited(&bus);

    bus.stage(&[100, 200]);
    assert_eq!(sensor.read_tagged_sample().unwrap().unwrap().tag, PPG_TAG);
    // Window closes with the ambient half of the frame unread.
    sensor.shutdown().unwrap();
    sensor.wake().unwrap();

    bus.stage(&[300, 400]);
    let first = sensor.read_tagged_sample().unwrap().unwrap();
    assert_eq!(
        first.tag, PPG_TAG,
        "the new window must open on a PPG sample"
    );
    assert_eq!(first.value, 300, "the stale sample must not be served");
}

#[test]
fn shutdown_preserves_the_mode_so_wake_does_not_change_it() {
    // A bare shutdown-bit write would select heart-rate mode (0x00) alongside
    // it, and the slot registers only apply in multi-LED mode — so waking would
    // silently lose the ambient channel.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = inited(&bus);
    sensor.shutdown().unwrap();
    sensor.wake().unwrap();
    let traffic = bus.writes();
    assert_eq!(traffic[0], vec![0x09, 0x87], "SHUTDOWN | MULTI_LED");
    assert_eq!(traffic[1], vec![0x09, 0x07], "MULTI_LED, shutdown cleared");
    for w in &traffic {
        assert!(
            !matches!(w[0], 0x11 | 0x12 | 0x0A),
            "shutdown/wake must not rewrite the slot or sample config"
        );
    }
}

#[test]
fn the_afe_contract_reports_the_eighteen_bit_scale() {
    // The reason the lift happened: this part's counts are 18-bit, and a
    // detector handed 19-bit thresholds would judge every DC level twice as
    // strictly as intended.
    let bus = MockI2c::new(PART_ID);
    let sensor = inited(&bus);
    assert_eq!(PpgAfe::scale(&sensor), PpgScale::BITS_18);
    assert_eq!(PpgAfe::scale(&sensor).full_scale, 0x3_FFFF);
    assert_eq!(PpgAfe::led_pa_default(&sensor), LED_PA_DEFAULT);
    assert_eq!(PpgAfe::tags(&sensor).ppg, PPG_TAG);
    assert_eq!(PpgAfe::tags(&sensor).ambient, AMBIENT_TAG);
}

#[test]
fn the_agc_window_matches_the_scale_the_same_afe_reports() {
    // Scale and AGC window are asked of the part separately, so nothing stops
    // an implementation returning a mismatched pair. This pins that the loop
    // sheds drive before this part's own detector rail.
    let bus = MockI2c::new(PART_ID);
    let sensor = inited(&bus);
    let scale = PpgAfe::scale(&sensor);
    let agc = PpgAfe::agc_config(&sensor);
    assert!((agc.raw_ceiling as i32) < scale.raw_rail_dc);
    assert!(agc.target_high < agc.raw_ceiling);
}

#[test]
fn decode_temp_matches_the_sixteenth_degree_encoding() {
    assert_eq!(decode_die_temp_milli_c(25, 0), 25_000);
    assert_eq!(decode_die_temp_milli_c(25, 8), 25_500, "8/16 = 0.5 degC");
    assert_eq!(decode_die_temp_milli_c(37, 4), 37_250, "4/16 = 0.25 degC");
    // Reserved upper bits of TEMP_FRAC must not leak into the reading.
    assert_eq!(
        decode_die_temp_milli_c(20, 0xF8),
        decode_die_temp_milli_c(20, 0x08)
    );
    // Two's-complement whole part with a positive added fraction: -6 + 8/16.
    assert_eq!(decode_die_temp_milli_c(0xFA, 8), -5_500);
}

#[test]
fn an_overflow_resyncs_rather_than_risking_a_transposed_stream() {
    // The other door to a phase slip. An overflow means the part overwrote
    // samples the host never read; if it dropped an odd number, every later
    // frame is transposed and nothing downstream can tell. The counter
    // saturates, so parity is unrecoverable — the only safe move is to drop the
    // window's alignment and re-derive it.
    let bus = MockI2c::new(PART_ID);
    let mut sensor = inited(&bus);

    bus.stage(&[10, 20, 30, 40]);
    bus.set_overflow(3);
    assert_eq!(
        sensor.read_tagged_sample().unwrap(),
        None,
        "an overflowed FIFO must not be served, however full it looks"
    );

    // It flushed rather than merely declining: the pointer registers were
    // rewritten, the overflow counter among them.
    let flush: Vec<Vec<u8>> = bus
        .writes()
        .into_iter()
        .filter(|w| matches!(w[0], 0x04 | 0x05 | 0x06))
        .collect();
    assert_eq!(
        flush,
        vec![vec![0x04, 0x00], vec![0x05, 0x00], vec![0x06, 0x00]],
        "the overflow path must clear the counter too, or it re-triggers forever"
    );

    // The driver cleared the counter itself — an overflow path that left it set
    // would re-trigger on every subsequent refill and the stream would never
    // recover. Staging a fresh frame is enough; nothing here re-clears it.
    bus.stage(&[50, 60]);
    let w = sensor.read_tagged_sample().unwrap().unwrap();
    assert_eq!(w.tag, PPG_TAG);
    assert_eq!(w.value, 50);
}
