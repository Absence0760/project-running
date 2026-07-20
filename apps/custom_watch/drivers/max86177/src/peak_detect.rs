//! Naive PPG -> BPM peak detector for the MAX86177 raw sample stream.
//!
//! Integer / fixed-point only — no floats, no allocation, no `libm` — so it
//! runs cheaply on the Cortex-M4F and is exercised on the host via
//! `tests/peak_detect.rs`. This is deliberately *not* the licensed HR
//! algorithm; it is the always-works baseline that turns a clean finger-on-
//! sensor pulse into a heart rate, and honestly reports "no signal" otherwise.
//!
//! Pipeline per sample:
//! 1. Remove the DC baseline with a slow exponential moving average, leaving
//!    the AC pulse waveform.
//! 2. Lightly low-pass the AC signal to reject high-frequency noise.
//! 3. Track a decaying envelope of the systolic upstroke and detect a beat
//!    when the signal crosses a fraction of that envelope, gated by a
//!    physiological refractory period so one pulse counts once.
//! 4. Convert the inter-beat interval to BPM, smooth it across beats, and only
//!    report valid once several consecutive intervals agree.
//!
//! A companion [`PeakDetector::contact`] reuses that same DC baseline and AC
//! envelope to tell a worn sensor from an off-wrist one — a worn sensor rests
//! at a plausible mid-scale DC with a pulsatile envelope, an unworn one reads a
//! dark floor or a saturated rail with little AC. A reading is forced invalid
//! whenever the sensor is off the wrist, so ambient light can never masquerade
//! as a heart rate.
//!
//! In blinding sun the ambient light bleeding into the photodiode rails the
//! LED-on PPG channel's DC before any of this can help — an honest but useless
//! `Contact::Saturated`. To *recover* a real pulse there, [`PeakDetector::push_ambient`]
//! takes the AFE's ambient (LED-off) sample alongside the PPG sample and
//! subtracts it, so the railing ambient DC is cancelled and the LED-reflected
//! pulse envelope survives. The honesty contract is unchanged: if even the
//! ambient-subtracted DC is railed (`Saturated`) or collapses to the dark floor
//! (`OffWrist`), the reading stays invalid — subtraction recovers a real pulse,
//! it never fabricates one.
//!
//! Subtraction has one hard limit: it can only cancel ambient the ADC actually
//! resolved. Once the *raw* LED-on sample pins at (or hovers just under) the
//! 19-bit full scale, the converter is clipping — the pulse information is
//! destroyed before subtraction runs, and the "corrected" difference is
//! arithmetic over a flat rail, not a signal. The detector therefore tracks the
//! raw DC alongside the corrected one and classifies a pinned raw baseline as
//! `Saturated` even when the corrected DC lands back inside the worn band.

/// DC-baseline EMA shift: alpha = 1/64, ~0.64 s time constant at 100 Hz, a
/// corner well below the heart-rate band.
const BASELINE_SHIFT: u32 = 6;

/// AC-smoothing EMA shift: alpha = 1/4, trims sample-to-sample noise without
/// blunting the upstroke.
const SMOOTH_SHIFT: u32 = 2;

/// Envelope decay shift: alpha = 1/128, so the systolic-peak envelope holds
/// steady across a beat interval and only sags over seconds.
const ENVELOPE_DECAY_SHIFT: u32 = 7;

/// Detect threshold as a fraction of the envelope (60 %), re-arm below 30 %.
/// The gap is hysteresis against a noisy crossing.
const THRESH_HIGH_NUM: i32 = 6;
const THRESH_LOW_NUM: i32 = 3;
const THRESH_DEN: i32 = 10;

/// Minimum envelope, in raw counts, below which the signal is treated as no
/// finger / no pulse. Amplitude scales with LED current and skin contact, so
/// this floor is a bench-verify value; kept low enough to accept a weak pulse.
const MIN_ENVELOPE: i32 = 20;

/// Plausible worn-DC band, in raw 19-bit photodiode counts (full scale
/// 0x7_FFFF = 524287). Below the floor the diode sees almost no reflected light
/// — the sensor is face-up off the wrist or against a dark surface; above the
/// ceiling it is railing on bright ambient or an over-driven LED. Both are
/// bench-verify values: they track LED current and the optical stack, so retune
/// them on the bench alongside `MEAS1_LEDA_CURRENT`.
const CONTACT_DC_MIN: i32 = 2_000;
const CONTACT_DC_MAX: i32 = 480_000;

/// Raw-rail floor, in raw 19-bit counts: a *raw* (pre-subtraction) DC baseline
/// above this is treated as a pinned ADC. Full scale is 0x7_FFFF = 524287, so
/// this leaves ~9k counts (<2 %) of headroom — too little for the pulsatile AC
/// to swing in without clipping, which destroys the pulse before ambient
/// subtraction can recover it. Sits above the AGC's `raw_ceiling` (the loop
/// sheds LED drive well before the read has to be declared dead) and above the
/// headline recovery scene (~500k raw), and is a bench-verify value like the
/// contact band.
const RAW_RAIL_DC: i32 = 515_000;

/// Reportable physiological band. An inter-beat interval implying a rate
/// outside this is a double-trigger or a dropout, not a heartbeat, and is
/// refused entry to the smoothed estimate. 220 bpm is the classic HR-max
/// ceiling (the 220 - age formula at age 0 — nobody sustains a higher rate);
/// 30 bpm is a severe-bradycardia floor below which a "beat" is a stalled
/// signal or motion, not a pulse. `MAX_BPM` also sets the refractory spacing,
/// so a tighter crossing is silently blocked before it can register at all.
const MIN_BPM: u32 = 30;
const MAX_BPM: u32 = 220;

/// SNR floor: a candidate beat whose systolic envelope has collapsed below
/// 1/4 of the slow running amplitude reference is a low-amplitude noise bump
/// riding a decayed threshold, not a pulse. Kept conservative (1/4) so a merely
/// weak but real beat still counts.
const SNR_MIN_NUM: i32 = 1;
const SNR_MIN_DEN: i32 = 4;

/// Amplitude-reference release shift: the reference is a peak-hold that snaps
/// up to a stronger envelope instantly but bleeds down at alpha = 1/1024
/// (~10 s at 100 Hz) — far slower than the ~1.3 s envelope decay. Holding the
/// recent systolic level well past a transient dropout is what gives the SNR
/// gate a stable margin to judge a bump against; the slow bleed still lets it
/// relearn a genuinely weaker signal, so a real weak pulse is never suppressed
/// for good.
const BEAT_REF_DECAY_SHIFT: u32 = 10;

/// Consecutive intervals that must agree before a reading is reported valid.
const MIN_GOOD_BEATS: u32 = 3;

/// An interval within +/-30 % of the previous one counts as agreeing.
const INTERVAL_TOL_NUM: u32 = 3;
const INTERVAL_TOL_DEN: u32 = 10;

/// Inter-beat BPM smoothing: alpha = 1/4 in Q8.
const BPM_SMOOTH_SHIFT: i32 = 2;
const BPM_Q: i32 = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Reading {
    pub bpm: u16,
    pub valid: bool,
}

/// Whether the optical stack is looking at skin (a worn wrist), nothing useful
/// (off-wrist dark floor), or a rail it cannot see through (ambient-light
/// saturation). Gates HR validity so the detector reports the reason for "no
/// contact" rather than a BPM synthesised from ambient light. `Saturated` is
/// distinct from `OffWrist` so a worn-but-sunlight-blinded wrist is reported
/// honestly and separately from a bare-off-wrist read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Contact {
    Worn,
    OffWrist,
    /// The DC baseline is railed near full scale even after ambient
    /// subtraction — bright ambient the LED cannot out-shine, not a pulse.
    Saturated,
}

pub struct PeakDetector {
    samples_per_min: u32,
    refractory_samples: u32,
    timeout_samples: u32,

    initialized: bool,
    baseline: i32,
    raw_baseline: i32,
    smoothed: i32,
    envelope: i32,
    beat_ref: i32,
    armed: bool,

    samples_since_beat: u32,
    last_interval: u32,
    good_beats: u32,
    bpm_q8: i32,
}

impl PeakDetector {
    pub fn new(sample_rate_hz: u32) -> Self {
        let samples_per_min = sample_rate_hz.max(1) * 60;
        Self {
            samples_per_min,
            refractory_samples: samples_per_min / MAX_BPM,
            timeout_samples: samples_per_min / MIN_BPM,
            initialized: false,
            baseline: 0,
            raw_baseline: 0,
            smoothed: 0,
            envelope: 0,
            beat_ref: 0,
            armed: false,
            samples_since_beat: 0,
            last_interval: 0,
            good_beats: 0,
            bpm_q8: 0,
        }
    }

    pub fn reset(&mut self) {
        self.initialized = false;
        self.baseline = 0;
        self.raw_baseline = 0;
        self.smoothed = 0;
        self.envelope = 0;
        self.beat_ref = 0;
        self.armed = false;
        self.samples_since_beat = 0;
        self.last_interval = 0;
        self.good_beats = 0;
        self.bpm_q8 = 0;
    }

    /// Feed one PPG (LED-on) count together with the AFE's ambient (LED-off)
    /// count for the same instant, subtracting the ambient before the DC/AC
    /// pipeline runs. In bright sun the ambient bleed rails the PPG channel;
    /// removing it recovers the LED-reflected pulse that would otherwise be lost
    /// to `Contact::Saturated`.
    ///
    /// The subtraction is saturating and floored at zero — the LED can only
    /// *add* reflected light, so a negative net is sensor noise, not a signal,
    /// and no argument pair can overflow the integer math. Headroom assumption:
    /// both counts are 19-bit ADC values on the same scale (MEAS2 mirrors
    /// MEAS1's ADC config), so their true difference always fits an `i32` with
    /// room to spare. The *raw* count is tracked separately so [`contact`]
    /// (Self::contact) can spot a pinned ADC — once the raw sample clips at
    /// full scale the corrected difference is arithmetic over a flat rail, and
    /// subtraction must not launder it into a plausible-looking DC. With
    /// `ambient == 0` this is exactly [`push`](Self::push), so the
    /// single-channel path is unchanged.
    pub fn push_ambient(&mut self, ppg: i32, ambient: i32) -> Reading {
        if !self.initialized {
            self.raw_baseline = ppg;
        }
        self.raw_baseline += ppg.saturating_sub(self.raw_baseline) >> BASELINE_SHIFT;
        self.process(ppg.saturating_sub(ambient).max(0))
    }

    /// Feed one raw photodiode count. Returns the current estimate; `valid` is
    /// false until a stable pulse is established and again once it is lost.
    /// Identical to [`push_ambient`](Self::push_ambient) with `ambient == 0`.
    pub fn push(&mut self, sample: i32) -> Reading {
        self.push_ambient(sample, 0)
    }

    /// The shared DC/AC pipeline over the (ambient-corrected) sample.
    fn process(&mut self, sample: i32) -> Reading {
        if !self.initialized {
            self.baseline = sample;
            self.initialized = true;
        }

        self.baseline += (sample - self.baseline) >> BASELINE_SHIFT;
        let ac = sample - self.baseline;
        self.smoothed += (ac - self.smoothed) >> SMOOTH_SHIFT;

        if self.smoothed > self.envelope {
            self.envelope = self.smoothed;
        } else {
            self.envelope -= self.envelope >> ENVELOPE_DECAY_SHIFT;
        }

        // Slow peak-hold of the systolic amplitude for the SNR gate: it matches
        // the envelope on the way up (so warm-up and a genuine step-up never
        // trip the gate) but bleeds down far slower than the envelope, so a
        // transient dropout leaves it holding the real signal level to judge a
        // suspiciously small bump against.
        if self.envelope > self.beat_ref {
            self.beat_ref = self.envelope;
        } else {
            self.beat_ref -= self.beat_ref >> BEAT_REF_DECAY_SHIFT;
        }

        self.samples_since_beat = self.samples_since_beat.saturating_add(1);

        let thresh_high = self.envelope * THRESH_HIGH_NUM / THRESH_DEN;
        let thresh_low = self.envelope * THRESH_LOW_NUM / THRESH_DEN;

        if self.smoothed < thresh_low {
            self.armed = true;
        }

        if self.armed
            && self.envelope >= MIN_ENVELOPE
            && self.smoothed >= thresh_high
            && self.samples_since_beat >= self.refractory_samples
        {
            self.register_beat();
        }

        if self.samples_since_beat > self.timeout_samples {
            self.good_beats = 0;
        }

        self.reading()
    }

    fn register_beat(&mut self) {
        let interval = self.samples_since_beat;
        self.samples_since_beat = 0;
        self.armed = false;

        let bpm = self.samples_per_min / interval.max(1);
        if !(MIN_BPM..=MAX_BPM).contains(&bpm) {
            self.good_beats = 0;
            return;
        }

        // SNR gate: reject a crossing whose envelope has fallen far below the
        // running amplitude reference — a low-amplitude noise bump, not a pulse.
        // A sustained artifact keeps failing here, so `good_beats` stays low and
        // the reading is honestly invalid rather than a stale last value.
        if self.beat_ref > 0 && self.envelope * SNR_MIN_DEN < self.beat_ref * SNR_MIN_NUM {
            self.good_beats = 0;
            return;
        }

        let inst_q8 = (bpm as i32) << BPM_Q;

        let agrees = self.last_interval != 0 && interval_agrees(interval, self.last_interval);
        if agrees {
            self.bpm_q8 += (inst_q8 - self.bpm_q8) >> BPM_SMOOTH_SHIFT;
            self.good_beats += 1;
        } else {
            self.bpm_q8 = inst_q8;
            self.good_beats = 1;
        }
        self.last_interval = interval;
    }

    /// Skin-contact state from the DC baselines + AC envelope the beat detector
    /// already tracks — no second pass over the samples. When fed via
    /// [`push_ambient`](Self::push_ambient) the baseline is the ambient-subtracted
    /// DC, so a bright-sun wrist whose raw PPG would rail can still read `Worn`.
    /// `Worn` requires the corrected DC to sit inside the plausible band *and*
    /// the envelope to clear the pulse floor. Two rails read `Saturated`: a
    /// *raw* baseline pinned at/near full scale (the ADC is clipping, so the
    /// corrected DC is fiction no matter where it lands — see [`RAW_RAIL_DC`]),
    /// and a corrected DC still railed past the worn band. A dark floor, a flat
    /// (non-pulsatile) reflector, or a fresh detector are `OffWrist`.
    /// Fail-closed: uninitialised is `OffWrist`.
    pub fn contact(&self) -> Contact {
        if !self.initialized {
            return Contact::OffWrist;
        }
        if self.raw_baseline > RAW_RAIL_DC || self.baseline > CONTACT_DC_MAX {
            return Contact::Saturated;
        }
        if self.baseline >= CONTACT_DC_MIN && self.envelope >= MIN_ENVELOPE {
            Contact::Worn
        } else {
            Contact::OffWrist
        }
    }

    /// The slow DC estimate of the *raw* (LED-on, pre-subtraction) stream, or
    /// `None` before the first sample. This is the level the ADC actually
    /// converts, so it is what an LED auto-gain loop must judge clipping
    /// headroom against (see `agc_next_pa_ambient` in the driver crate).
    pub fn raw_dc(&self) -> Option<u32> {
        self.initialized.then(|| self.raw_baseline.max(0) as u32)
    }

    /// The slow DC estimate of the ambient-corrected stream — the LED-reflected
    /// operating point the pulse rides on — or `None` before the first sample.
    /// The AGC's brightness target judges this level: ambient cancels out of
    /// it, so ambient swings can't walk the LED drive.
    pub fn corrected_dc(&self) -> Option<u32> {
        self.initialized.then(|| self.baseline.max(0) as u32)
    }

    fn reading(&self) -> Reading {
        let valid = self.contact() == Contact::Worn
            && self.good_beats >= MIN_GOOD_BEATS
            && self.samples_since_beat <= self.timeout_samples;
        let bpm = if valid {
            (((self.bpm_q8 + (1 << (BPM_Q - 1))) >> BPM_Q) as u16).max(1)
        } else {
            0
        };
        Reading { bpm, valid }
    }
}

fn interval_agrees(interval: u32, reference: u32) -> bool {
    let delta = interval.abs_diff(reference);
    delta * INTERVAL_TOL_DEN <= reference * INTERVAL_TOL_NUM
}
