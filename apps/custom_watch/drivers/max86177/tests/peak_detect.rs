//! Host-side tests for the PPG peak detector. Run via `bin/watch-test.sh` from
//! the repo root, or `cargo test --target <HOST_TRIPLE> -p max86177` from
//! anywhere. Each test synthesizes a PPG-like waveform (a pulse train plus
//! additive noise and slow DC drift) and asserts the detector's behaviour.

use std::f64::consts::PI;

use max86177::peak_detect::{Contact, PeakDetector, Reading};

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

#[test]
fn clean_signal_unchanged_by_the_guards() {
    // Regression guard: the motion/outlier gates must not perturb a clean
    // finger-on-sensor pulse. A steady 60 bpm still settles valid and correct.
    converges_to(100, 60.0, 3);
}

#[test]
fn implausibly_fast_rhythm_is_rejected() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);

    assert!(
        synth.run(&mut det, 60.0, 15).valid,
        "clean rhythm reads valid first"
    );

    // A ~240 bpm "rhythm" is a motion / electrical artifact: every implied
    // inter-beat interval sits outside the human band, so none is admitted to
    // the smoothed rate. The detector must fall back to invalid rather than
    // ever reporting a super-physiological heart rate as real.
    let mut last = Reading {
        bpm: 0,
        valid: false,
    };
    for _ in 0..rate * 6 {
        last = synth.step(&mut det, 240.0);
        assert!(
            !(last.valid && last.bpm > 220),
            "must never report a valid rate above the plausible band, got {}",
            last.bpm
        );
    }
    assert!(
        !last.valid,
        "a super-physiological rhythm must read invalid"
    );
}

#[test]
fn low_amplitude_bumps_are_rejected() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);

    assert!(
        synth.run(&mut det, 72.0, 15).valid,
        "strong signal establishes the amplitude reference"
    );

    // Collapse the pulse to a small fraction of the established amplitude while
    // keeping a heartbeat cadence. These bumps clear the decayed envelope
    // threshold and the absolute floor, but sit far below the held systolic
    // reference, so the SNR gate refuses them. Give the envelope a few seconds
    // to decay so the bumps actually fire, then require sustained invalid.
    synth.amplitude = 25.0;
    synth.run(&mut det, 72.0, 4);
    for _ in 0..rate * 4 {
        let r = synth.step(&mut det, 72.0);
        assert!(
            !r.valid,
            "a low-SNR bump train must not manufacture a heart rate"
        );
    }
}

#[test]
fn recovers_to_valid_after_artifacts_pass() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);

    assert!(synth.run(&mut det, 72.0, 15).valid);

    // A burst of fast motion artifact knocks the reading invalid...
    assert!(!synth.run(&mut det, 240.0, 5).valid);

    // ...and once a clean pulse returns the detector re-establishes a valid,
    // correct rate — the invalidation was honest, not a latched dead state.
    let recovered = synth.run(&mut det, 72.0, 15);
    assert!(recovered.valid, "must recover once the artifact clears");
    assert!(
        recovered.bpm.abs_diff(72) <= 3,
        "recovered rate should be correct, got {}",
        recovered.bpm
    );
}

#[test]
fn worn_signal_reports_contact() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    let r = synth.run(&mut det, 72.0, 20);
    assert_eq!(det.contact(), Contact::Worn, "a real pulse means worn");
    assert!(r.valid);
}

#[test]
fn floor_signal_reads_off_wrist() {
    // A dark floor: the diode sits near zero counts. Even a heartbeat-cadence
    // AC riding it — which the beat detector alone would latch onto — must read
    // off-wrist, because the DC baseline is nowhere near a wrist's.
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    synth.dc = 0.0;
    let r = synth.run(&mut det, 72.0, 20);
    assert_eq!(det.contact(), Contact::OffWrist);
    assert!(!r.valid, "off-wrist must never report a heart rate");
    assert_eq!(r.bpm, 0);
}

#[test]
fn ambient_railed_reads_saturated_not_off_wrist() {
    // Blinding sun: ambient IR bleeds into the photodiode and drives the DC near
    // full scale (0x7_FFFF) on a well-worn wrist. A flickering ambient AC on top
    // is not a pulse. This must read Saturated — an honest "signal unavailable,
    // too much light" — NOT off-wrist (the wrist is worn) and NEVER a fabricated
    // BPM. The LED-current AGC cannot pull an ambient-sourced rail down, so the
    // contact classifier is the only thing standing between bright sun and a
    // garbage reading.
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    synth.dc = 524_000.0;
    let r = synth.run(&mut det, 72.0, 20);
    assert_eq!(det.contact(), Contact::Saturated);
    assert_ne!(
        det.contact(),
        Contact::OffWrist,
        "a worn-but-sunlit wrist must not be reported off-wrist"
    );
    assert!(!r.valid, "a railed signal must never report a heart rate");
    assert_eq!(r.bpm, 0);
}

#[test]
fn ambient_railed_with_no_ac_reads_saturated() {
    // The pure railing signature: DC pinned near full scale with no AC envelope
    // at all (a flat, saturated diode). Still Saturated, still no BPM.
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    synth.dc = 524_000.0;
    synth.amplitude = 0.0;
    synth.noise_amp = 2;
    let r = synth.run(&mut det, 0.0, 20);
    assert_eq!(det.contact(), Contact::Saturated);
    assert!(!r.valid);
    assert_eq!(r.bpm, 0);
}

#[test]
fn ambient_railed_is_distinguishable_from_off_wrist() {
    // The two invalid states must be told apart: a dark floor (diode near zero)
    // is genuinely off-wrist, while a full-scale rail is saturation on a possibly
    // worn wrist. Both blank the BPM, but the attribution differs — the point of
    // the fix.
    let rate = 100;

    let mut dark = PeakDetector::new(rate);
    let mut dark_synth = Synth::new(rate);
    dark_synth.dc = 0.0;
    dark_synth.run(&mut dark, 72.0, 20);

    let mut bright = PeakDetector::new(rate);
    let mut bright_synth = Synth::new(rate);
    bright_synth.dc = 524_000.0;
    bright_synth.run(&mut bright, 72.0, 20);

    assert_eq!(dark.contact(), Contact::OffWrist);
    assert_eq!(bright.contact(), Contact::Saturated);
    assert_ne!(
        dark.contact(),
        bright.contact(),
        "off-wrist and ambient-railed must be reported as distinct states"
    );
}

#[test]
fn plausible_dc_without_ac_reads_off_wrist() {
    // Boundary: the DC sits inside the worn band but the pulse is below the
    // envelope floor — a static reflector, not skin. Contact must still read
    // off-wrist, so a plausible resting level alone can't unlock a reading.
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    synth.amplitude = 5.0;
    synth.noise_amp = 2;
    let r = synth.run(&mut det, 72.0, 20);
    assert_eq!(det.contact(), Contact::OffWrist);
    assert!(!r.valid);
}

#[test]
fn worn_weak_but_real_pulse_keeps_contact() {
    // The other side of the boundary: a genuinely weak pulse (a looser strap)
    // on a plausible DC must still read worn and valid — the contact gate must
    // not suppress a real, if faint, heartbeat.
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);
    synth.amplitude = 60.0;
    let r = synth.run(&mut det, 72.0, 20);
    assert_eq!(det.contact(), Contact::Worn);
    assert!(r.valid);
    assert!(r.bpm.abs_diff(72) <= 3, "weak-but-worn rate, got {}", r.bpm);
}

#[test]
fn fresh_detector_reads_off_wrist() {
    // Fail-closed: before any sample, the sensor is off-wrist, not worn.
    let det = PeakDetector::new(100);
    assert_eq!(det.contact(), Contact::OffWrist);
}

#[test]
fn sustained_weaker_signal_is_not_suppressed() {
    let rate = 100;
    let mut det = PeakDetector::new(rate);
    let mut synth = Synth::new(rate);

    assert!(synth.run(&mut det, 72.0, 15).valid);

    // A genuinely weaker (but real) pulse — a looser strap, not noise — must not
    // be permanently rejected by the SNR gate: the amplitude reference bleeds
    // down so the detector relearns the new level and reports again.
    synth.amplitude = 60.0;
    let relearned = synth.run(&mut det, 72.0, 12);
    assert!(
        relearned.valid,
        "a sustained weaker pulse must not be suppressed for good"
    );
    assert!(
        relearned.bpm.abs_diff(72) <= 3,
        "relearned rate should be correct, got {}",
        relearned.bpm
    );
}
