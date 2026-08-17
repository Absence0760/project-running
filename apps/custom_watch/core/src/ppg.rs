//! Part-agnostic PPG logic: the naive raw-sample -> BPM peak detector, the LED
//! auto-gain loop, and the [`PpgAfe`] contract an optical front-end driver
//! implements to feed them.
//!
//! **Why this lives in `watch_core` and not in a driver crate** (decisions.md
//! § 623). It used to be a module of `max86177`, which read as tidy while there
//! was one AFE and became a trap the moment there were two: a second driver
//! either depends on the first for its peak detector, or forks it — and two
//! detectors is two things to tune against one wrist. Nothing here touches a
//! bus or a register, so nothing here belongs to a part.
//!
//! What *is* part-specific is the **ADC scale** the thresholds are quoted in.
//! Every DC bound below is a photodiode count, and a count means nothing
//! without knowing the converter's full scale — the same optical scene reads
//! half as many counts on an 18-bit part as on a 19-bit one. [`PpgScale`]
//! carries that, so a new AFE is a constructor argument rather than a second
//! copy of this file with the numbers edited.
//!
//! Integer / fixed-point only — no floats, no allocation, no `libm` — so it
//! runs cheaply on the Cortex-M4F and is exercised on the host via
//! `tests/ppg.rs`. This is deliberately *not* the licensed HR
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

/// The ADC-scale-dependent thresholds, in raw photodiode counts.
///
/// Every bound here is a count, and a count is meaningless without the
/// converter's full scale behind it: an 18-bit part reports half the counts an
/// 19-bit part does for the identical optical scene, so a threshold ported
/// across unchanged silently doubles in strictness. Holding them as data keeps
/// a new AFE to a constructor argument instead of a second copy of this file.
///
/// **All four are bench-verify values** — they track LED current and the
/// optical stack, and no wrist has ever been read through either. Scaling one
/// set to another converter does not make either measured; it makes them
/// consistently unmeasured, which is the honest starting point.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PpgScale {
    /// The converter's full-scale count.
    pub full_scale: u32,
    /// Below this the diode sees almost no reflected light — the sensor is
    /// face-up off the wrist or against a dark surface.
    pub contact_dc_min: i32,
    /// Above this the corrected DC is railing on bright ambient or an
    /// over-driven LED.
    pub contact_dc_max: i32,
    /// A *raw* (pre-subtraction) DC baseline above this is a pinned ADC: too
    /// little headroom for the pulsatile AC to swing without clipping, which
    /// destroys the pulse before ambient subtraction can recover it. Sits above
    /// [`AgcConfig::raw_ceiling`] so the auto-gain loop sheds drive well before
    /// a read has to be declared dead.
    pub raw_rail_dc: i32,
    /// Minimum AC envelope below which the signal is treated as no finger / no
    /// pulse. Kept low enough to accept a weak pulse.
    pub min_envelope: i32,
}

impl PpgScale {
    /// The 19-bit reference the thresholds were originally chosen against (the
    /// MAX86177's converter, full scale `0x7_FFFF` = 524287). Held as literals
    /// rather than derived so this — the set every existing test pins — is
    /// exactly what it always was, and [`scaled_to`](Self::scaled_to) is the
    /// only thing that ever moves a number.
    pub const BITS_19: Self = Self {
        full_scale: 0x0007_FFFF,
        contact_dc_min: 2_000,
        contact_dc_max: 480_000,
        raw_rail_dc: 515_000,
        min_envelope: 20,
    };

    /// The 18-bit set, for a MAX30101-class converter (full scale `0x3_FFFF` =
    /// 262143). Proportional to [`BITS_19`], because the quantity each bound
    /// describes — a fraction of the converter's range — is what carries across
    /// parts, not the count.
    pub const BITS_18: Self = Self::BITS_19.scaled_to(0x0003_FFFF);

    /// Re-express this set against a different converter full scale, holding
    /// each bound at the same fraction of range.
    ///
    /// Rounding is deliberately **downward** on every field, including
    /// `min_envelope`: rounding a contact floor down widens what counts as
    /// worn, rounding a rail down declares saturation slightly early, and
    /// rounding an envelope floor down accepts a slightly weaker pulse. Each is
    /// the direction that fails toward reporting a reading rather than toward
    /// silently withholding one, and the contact gates stay honest either way
    /// because they are checked against the same scale that produced them.
    pub const fn scaled_to(self, full_scale: u32) -> Self {
        Self {
            full_scale,
            contact_dc_min: rescale(self.contact_dc_min, self.full_scale, full_scale),
            contact_dc_max: rescale(self.contact_dc_max, self.full_scale, full_scale),
            raw_rail_dc: rescale(self.raw_rail_dc, self.full_scale, full_scale),
            min_envelope: rescale(self.min_envelope, self.full_scale, full_scale),
        }
    }
}

/// `value * to / from`, in `i64` so the intermediate cannot overflow at any
/// plausible converter width.
const fn rescale(value: i32, from: u32, to: u32) -> i32 {
    ((value as i64 * to as i64) / from as i64) as i32
}

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
    scale: PpgScale,
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
    /// The `scale` is deliberately required rather than defaulted: a detector
    /// that quietly assumes a converter width is exactly how a 19-bit threshold
    /// ends up judging an 18-bit stream (decisions.md § 623).
    pub fn new(sample_rate_hz: u32, scale: PpgScale) -> Self {
        let samples_per_min = sample_rate_hz.max(1) * 60;
        Self {
            scale,
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
            && self.envelope >= self.scale.min_envelope
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
    /// corrected DC is fiction no matter where it lands — see
    /// [`PpgScale::raw_rail_dc`]),
    /// and a corrected DC still railed past the worn band. A dark floor, a flat
    /// (non-pulsatile) reflector, or a fresh detector are `OffWrist`.
    /// Fail-closed: uninitialised is `OffWrist`.
    pub fn contact(&self) -> Contact {
        if !self.initialized {
            return Contact::OffWrist;
        }
        if self.raw_baseline > self.scale.raw_rail_dc || self.baseline > self.scale.contact_dc_max {
            return Contact::Saturated;
        }
        if self.baseline >= self.scale.contact_dc_min && self.envelope >= self.scale.min_envelope {
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

/// LED-current auto-gain window for [`agc_next_pa`] / [`agc_next_pa_ambient`].
/// `target_low`/`target_high` are the desired DC operating band in raw
/// photodiode counts; the band itself is the hysteresis dead-zone, so a level
/// already inside it never moves the drive. `raw_ceiling` is the *raw*
/// (pre-subtraction) DC bound the ambient-aware loop guards clipping headroom
/// against. `step` is how many LEDx_PA codes each correction walks, and
/// `min_pa`/`max_pa` clamp the result.
///
/// The three DC bounds are counts, so they carry a [`PpgScale`] the same way
/// the detector's do — see [`AgcConfig::for_scale`]. The three *drive* bounds
/// do not: an LED current code is a property of the part's current DAC, not of
/// its converter, so they stay put across a rescale and are the fields to
/// revisit when the part changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct AgcConfig {
    pub target_low: u32,
    pub target_high: u32,
    pub raw_ceiling: u32,
    pub step: u8,
    pub min_pa: u8,
    pub max_pa: u8,
}

impl AgcConfig {
    /// The 19-bit reference window, matching [`PpgScale::BITS_19`]. Centres the
    /// DC on roughly a quarter-to-three-fifths of the 0x7_FFFF full scale,
    /// leaving headroom for the pulsatile AC before the ADC rails.
    /// `raw_ceiling` keeps ~44k counts (~8 % of full scale) of raw headroom —
    /// enough for the pulse swing plus ambient flicker — and sits below the
    /// detector's [`PpgScale::raw_rail_dc`], so the loop sheds drive before the
    /// read has to be declared `Saturated`. Bench-verify values.
    pub const BITS_19: Self = Self {
        target_low: 130_000,
        target_high: 300_000,
        raw_ceiling: 480_000,
        step: 8,
        min_pa: 0x08,
        max_pa: 0xC0,
    };

    /// Re-express the DC window against a different converter full scale,
    /// holding each bound at the same fraction of range and leaving the drive
    /// codes alone.
    ///
    /// The invariant this must preserve is `raw_ceiling < raw_rail_dc` — the
    /// loop has to shed drive *before* the detector gives up on the read.
    /// Proportional scaling preserves it by construction (both sides scale by
    /// the same ratio), and a test pins it at both widths rather than trusting
    /// that argument.
    pub const fn for_scale(self, to: PpgScale, from: PpgScale) -> Self {
        Self {
            target_low: rescale(self.target_low as i32, from.full_scale, to.full_scale) as u32,
            target_high: rescale(self.target_high as i32, from.full_scale, to.full_scale) as u32,
            raw_ceiling: rescale(self.raw_ceiling as i32, from.full_scale, to.full_scale) as u32,
            ..self
        }
    }

    /// The 18-bit window, for a MAX30101-class converter.
    pub const BITS_18: Self = Self::BITS_19.for_scale(PpgScale::BITS_18, PpgScale::BITS_19);
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

/// Ambient-aware LED auto-gain step, for a two-slot (PPG + ambient)
/// configuration. Which magnitude drives the decision is deliberate:
///
/// - **The brightness target judges the *corrected* DC** (`raw - ambient`, the
///   LED-reflected operating point the pulse rides on). Ambient cancels out of
///   it by construction, so a cloud passing or an arm swinging through shade
///   cannot walk the LED drive — the loop cannot oscillate against ambient
///   swings. Judging the raw DC here would do exactly that.
/// - **A one-sided rail guard judges the *raw* DC** (what the ADC actually
///   converts — clipping happens there, corrected or not). A raw DC above
///   `cfg.raw_ceiling` sheds one `step` of drive to recover conversion
///   headroom, overriding a dim corrected level: stepping the LED *up* into an
///   ADC that is already near its rail only deepens the clip that destroys the
///   pulse. Under ambient the LED cannot out-shine, the guard walks the drive
///   to `min_pa` and holds — the honest floor; the peak detector reports that
///   scene `Saturated`.
///
/// The guard never steps up, so ambient variation below the ceiling leaves the
/// drive untouched unless the corrected band asks for a change. Result is
/// clamped into `[min_pa, max_pa]` like [`agc_next_pa`].
pub fn agc_next_pa_ambient(raw_dc: u32, corrected_dc: u32, current_pa: u8, cfg: &AgcConfig) -> u8 {
    if raw_dc > cfg.raw_ceiling {
        return current_pa
            .saturating_sub(cfg.step)
            .clamp(cfg.min_pa, cfg.max_pa);
    }
    agc_next_pa(corrected_dc, current_pa, cfg)
}

/// One decoded FIFO word: which measurement slot produced it, and its raw
/// photodiode count.
///
/// The `tag` is a *logical* slot identifier, not necessarily a field the part
/// transmits. A tagging FIFO (the MAX86177) reads it out of the word; a
/// positional FIFO (the MAX30101, which writes one sample per enabled slot in
/// slot order and labels nothing) has its driver assign the tag from the read
/// position. Either way the consumer demuxes on the tag alone, so
/// [`crate::hr_drain`] never learns which kind of FIFO it is draining.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct FifoWord {
    pub tag: u8,
    pub value: u32,
}

/// What the `hr` task needs from an optical front-end, so it names a capability
/// rather than a part (decisions.md § 623).
///
/// Every method is best-effort from the task's point of view — optical HR is an
/// L4 auxiliary layer, so an implementation returning `Err` costs a window's
/// heart rate and must never cost a recording. Implementations are blocking;
/// the task fronts them with a timeout-bounded presence probe so a bus that
/// never answers parks the task instead of wedging the executor.
pub trait PpgAfe {
    type Error;

    /// Reset, configure the PPG + ambient slots, and leave the part streaming
    /// into its FIFO.
    fn init(&mut self) -> Result<(), Self::Error>;

    /// Pop the next sample, or `None` when the FIFO is empty.
    fn read_tagged_sample(&mut self) -> Result<Option<FifoWord>, Self::Error>;

    /// Set the PPG slot's LED drive current (the part's own DAC code).
    fn set_led_current(&mut self, pa: u8) -> Result<(), Self::Error>;

    /// Release the LED drive and stop sampling.
    fn shutdown(&mut self) -> Result<(), Self::Error>;

    /// Resume sampling, flushing the FIFO so counts buffered before the
    /// shutdown cannot replay into a freshly reset detector as a live pulse.
    fn wake(&mut self) -> Result<(), Self::Error>;

    /// The converter scale this part's counts are quoted in, for the detector
    /// and the auto-gain window.
    fn scale(&self) -> PpgScale;

    /// The auto-gain window matching [`scale`](Self::scale).
    fn agc_config(&self) -> AgcConfig;

    /// The LED drive code [`init`](Self::init) programs, so an auto-gain loop
    /// seeds its notion of the current drive from what the part is actually
    /// doing.
    fn led_pa_default(&self) -> u8;

    /// The logical slot tags [`read_tagged_sample`](Self::read_tagged_sample)
    /// emits, for [`crate::hr_drain::FifoDemux`].
    fn tags(&self) -> crate::hr_drain::FifoTags;
}
