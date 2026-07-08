//! Host-side tests for the PPG peak detector. Run via `bin/watch-test.sh` from
//! the repo root, or `cargo test --target <HOST_TRIPLE> -p max86177` from
//! anywhere. Each test synthesizes a PPG-like waveform (a pulse train plus
//! additive noise and slow DC drift) and asserts the detector's behaviour.

use std::f64::consts::PI;

use max86177::peak_detect::{PeakDetector, Reading};

/// Deterministic pseudo-noise so the tests don't pull in a rand dependency.
struct Noise(u64);

impl Noise {
    fn new(seed: u64) -> Self {
        Noise(seed)
    }

    /// Uniform integer in [-amp, amp].
    fn sample(&mut self, amp: i32) -> i32 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let span = 2 * amp + 1;
        ((self.0 >> 33) as i32).rem_euclid(span) - amp
    }
}

struct Synth {
    rate: u32,
    dc: f64,
    amplitude: f64,
    drift_per_s: f64,
    noise_amp: i32,
    noise: Noise,
    phase: f64,
    sample_index: u32,
}

impl Synth {
    fn new(rate: u32) -> Self {
        Self {
            rate,
            dc: 120_000.0,
            amplitude: 400.0,
            drift_per_s: 0.0,
            noise_amp: 6,
            noise: Noise::new(0x51ED),
            phase: 0.0,
            sample_index: 0,
        }
    }

    /// Advance one sample at the given instantaneous heart rate and push it into
    /// the detector, returning the resulting reading.
    fn step(&mut self, det: &mut PeakDetector, bpm: f64) -> Reading {
        self.phase += 2.0 * PI * (bpm / 60.0) / self.rate as f64;
        let t = self.sample_index as f64 / self.rate as f64;
        let value = self.dc
            + self.drift_per_s * t
            + self.amplitude * self.phase.sin()
            + self.noise.sample(self.noise_amp) as f64;
        self.sample_index += 1;
        det.push(value as i32)
    }

    fn run(&mut self, det: &mut PeakDetector, bpm: f64, secs: u32) -> Reading {
        let mut last = Reading {
            bpm: 0,
            valid: false,
        };
        for _ in 0..self.rate * secs {
            last = self.step(det, bpm);
        }
        last
    }
}

fn converges_to(rate: u32, bpm: f64, tolerance: u16) {
    let mut det = PeakDetector::new(rate);
    let final_reading = Synth::new(rate).run(&mut det, bpm, 25);
    assert!(final_reading.valid, "{bpm} bpm should read valid");
    let target = bpm as u16;
    assert!(
        final_reading.bpm.abs_diff(target) <= tolerance,
        "{bpm} bpm: got {} bpm",
        final_reading.bpm
    );
}

#[test]
fn converges_at_50_bpm() {
    converges_to(100, 50.0, 3);
}

#[test]
fn converges_at_72_bpm() {
    converges_to(100, 72.0, 3);
}

#[test]
fn converges_at_120_bpm() {
    converges_to(100, 120.0, 4);
}

#[test]
fn converges_at_a_different_sample_rate() {
    converges_to(64, 88.0, 4);
}

#[test]
fn fresh_detector_is_invalid() {
    let det = PeakDetector::new(100);
    // A detector that has seen no samples must not claim a heart rate; drive one
    // baseline sample and confirm it is still invalid.
    let mut det = det;
    let r = det.push(120_000);
    assert!(!r.valid);
    assert_eq!(r.bpm, 0);
}

#[test]
fn flat_signal_with_noise_is_invalid() {
    let mut det = PeakDetector::new(100);
    let mut synth = Synth::new(100);
    synth.amplitude = 0.0;
    synth.noise_amp = 8;
    let r = synth.run(&mut det, 0.0, 20);
    assert!(!r.valid, "pure noise must not report a heart rate");
    assert_eq!(r.bpm, 0);
}

#[test]
fn weak_signal_below_floor_is_invalid() {
    let mut det = PeakDetector::new(100);
    let mut synth = Synth::new(100);
    synth.amplitude = 5.0;
    synth.noise_amp = 3;
    let r = synth.run(&mut det, 70.0, 20);
    assert!(
        !r.valid,
        "sub-floor amplitude must read invalid, not a guess"
    );
}

#[test]
fn dc_drift_alone_produces_no_valid_beats() {
    let mut det = PeakDetector::new(100);
    let mut synth = Synth::new(100);
    synth.amplitude = 0.0;
    synth.noise_amp = 2;
    synth.drift_per_s = 400.0;
    for _ in 0..100 * 25 {
        let r = synth.step(&mut det, 0.0);
        assert!(!r.valid, "a slow DC ramp must never manufacture a beat");
    }
}

#[test]
fn abrupt_rate_change_is_tracked() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);

    let settled = synth.run(&mut det, 60.0, 20);
    assert!(settled.valid);
    assert!(
        settled.bpm.abs_diff(60) <= 3,
        "before the step: got {} bpm",
        settled.bpm
    );

    let after = synth.run(&mut det, 100.0, 20);
    assert!(after.valid);
    assert!(
        after.bpm.abs_diff(100) <= 4,
        "after the step: got {} bpm",
        after.bpm
    );
}

#[test]
fn reset_clears_the_estimate() {
    let mut det = PeakDetector::new(100);
    let mut synth = Synth::new(100);
    assert!(synth.run(&mut det, 72.0, 20).valid);

    det.reset();
    let r = det.push(120_000);
    assert!(!r.valid);
    assert_eq!(r.bpm, 0);
}
