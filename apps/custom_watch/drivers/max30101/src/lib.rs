//! Driver for the Maxim MAX30101 optical heart-rate / pulse-oximetry AFE —
//! tier 1's optical front end (decisions.md § 623).
//!
//! Chosen over the production MAX86177 for the bench prototype because its
//! register map is **public**, which the MAX86177's is not: every address and
//! bitfield below is read off the MAX30101 datasheet rather than modelled on a
//! family idiom, so a wrong value here is a bug rather than a guess. The part
//! is also a commodity — the same map answers on a SparkFun, Pimoroni or
//! generic module, so board sourcing stops being a single point of failure.
//!
//! **Green LED, deliberately.** The MAX30101 carries red, IR and green
//! emitters; this driver drives **green** for the PPG slot. Green is absorbed
//! strongly by haemoglobin and penetrates shallowly, which is why every
//! wrist-worn optical sensor uses it and why the red/IR-only MAX30102 is the
//! wrong part for a watch even though it is otherwise a near-twin.
//!
//! **And the near-twin cannot be told apart by its part number.** Every member
//! of the MAX3010x family — 30101, 30102, 30105 — reports the same `0x15` in
//! `PART_ID`, so the id read rules out an unrelated device on the address and
//! nothing more. What distinguishes them is which emitters were bonded out, so
//! [`Max30101::init`] tests for the green channel by *capability*: it writes
//! `LED3_PA` and reads it back, and a part with no third LED cannot hold it.
//! See [`Error::NoGreenChannel`] and decisions.md § 625.
//!
//! ## The FIFO is positional, and that is the whole design problem
//!
//! The MAX86177 tags each FIFO word with the measurement that produced it. The
//! MAX30101 does not: it writes **one 3-byte sample per enabled slot, in slot
//! order, every sample period**, and labels nothing. Which sample you are
//! holding is a function of how many you have read, so a read that returns a
//! partial frame slips the phase permanently — every subsequent ambient sample
//! is then fed to the detector as PPG and vice versa, which does not look like
//! a bug from downstream. It looks like a wandering heart rate.
//!
//! Two things prevent that, and both are load-bearing:
//!
//! 1. **Reads are whole frames.** [`Max30101::read_tagged_sample`] refills an
//!    internal frame buffer only when it can take [`SLOTS`] complete samples,
//!    then serves them one at a time. A FIFO holding a partial frame is left
//!    alone until the rest of it arrives.
//! 2. **Phase is re-derived, never carried.** The frame index resets on every
//!    flush ([`init`](Max30101::init), [`wake`](Max30101::wake)), so a
//!    duty-cycle window can never inherit the previous window's alignment.
//!
//! The logical tags this driver reports ([`PPG_TAG`], [`AMBIENT_TAG`]) are
//! therefore *assigned from position*, not decoded from the wire —
//! `watch_core::ppg::FifoWord` documents that distinction, and it is what lets
//! `watch_core::hr_drain` demux both parts with one implementation.
//!
//! ## The ambient slot
//!
//! Slot 2 is configured to drive **no LED**, so it samples only the ambient
//! light bleeding into the photodiode. Subtracting it from the LED-on sample is
//! what recovers a pulse in blinding sun (see
//! `watch_core::ppg::PeakDetector::push_ambient`). The MAX86177 reaches the
//! same design through a second tagged measurement channel; here it is a
//! multi-LED slot with an empty LED selection.
//!
//! ## What is not verified
//!
//! No silicon has answered any of this. The register map is datasheet-derived
//! and the *configuration values* — sample rate, pulse width, ADC range, the
//! LED drive seed — are conservative starting points chosen without a wrist,
//! exactly like their MAX86177 counterparts. `docs/custom_watch/quality_standards.md`
//! step 5 is where they get settled.

#![no_std]

use embedded_hal::i2c::I2c;
use watch_core::hr_drain::FifoTags;
use watch_core::ppg::{AgcConfig, FifoWord, PpgAfe, PpgScale};

/// 7-bit I2C address. Unlike the MAX86177's, this is fixed — the part has no
/// address-select pin, so a bus can carry exactly one.
pub const I2C_ADDR: u8 = 0x57;

/// Register map, from the MAX30101 datasheet.
mod reg {
    pub const FIFO_WR_PTR: u8 = 0x04;
    pub const OVF_COUNTER: u8 = 0x05;
    pub const FIFO_RD_PTR: u8 = 0x06;
    pub const FIFO_DATA: u8 = 0x07;
    pub const FIFO_CONFIG: u8 = 0x08;
    pub const MODE_CONFIG: u8 = 0x09;
    pub const SPO2_CONFIG: u8 = 0x0A;
    pub const LED1_PA: u8 = 0x0C;
    pub const LED2_PA: u8 = 0x0D;
    pub const LED3_PA: u8 = 0x0E;
    pub const LED4_PA: u8 = 0x0F;
    pub const MULTI_LED_SLOT_12: u8 = 0x11;
    pub const MULTI_LED_SLOT_34: u8 = 0x12;
    pub const TEMP_INT: u8 = 0x1F;
    pub const TEMP_FRAC: u8 = 0x20;
    pub const TEMP_CONFIG: u8 = 0x21;
    pub const PART_ID: u8 = 0xFF;
}

/// `PART_ID` value the MAX30101 reports — and the value a MAX30102 and a
/// MAX30105 report as well. The register identifies the *family*, not the
/// part, so checking it refuses an unrelated device answering on 0x57 and
/// achieves nothing against the near-twin actually worth refusing. That is
/// what the green-channel check exists for ([`Error::NoGreenChannel`]).
pub const PART_ID: u8 = 0x15;

/// `MODE_CONFIG` bits.
const MODE_RESET: u8 = 1 << 6;
const MODE_SHUTDOWN: u8 = 1 << 7;
/// Multi-LED mode — the only mode in which the slot registers apply, and so
/// the only one that can carry an LED-off ambient slot alongside the PPG one.
const MODE_MULTI_LED: u8 = 0x07;

/// `FIFO_CONFIG`: roll over on full (a stalled reader must not wedge the
/// writer), no sample averaging, almost-full at 15 remaining. Averaging is left
/// off deliberately — it would low-pass the pulse upstream of a detector whose
/// own smoothing is tuned against un-averaged samples.
const FIFO_CONFIG: u8 = 0x10;

/// `SPO2_CONFIG`: 4096 nA full-scale ADC range, 100 Hz sample rate, 411 µs
/// pulse width (which is what buys the full 18-bit conversion). The rate must
/// match the `hr` task's `SAMPLE_RATE_HZ`, since the detector derives its
/// refractory and timeout windows from it.
const SPO2_CONFIG: u8 = 0x27;

/// Slot assignments. `MULTI_LED_SLOT_12` packs slot 1 in the low nibble and
/// slot 2 in the high one; a slot value of 0 is "no LED", which is exactly what
/// makes slot 2 a dark read. Slot 1 selects **LED3 — the green emitter**.
const SLOT1_GREEN: u8 = 0x03;
const SLOT2_AMBIENT: u8 = 0x00;
const MULTI_LED_SLOT_12: u8 = SLOT1_GREEN | (SLOT2_AMBIENT << 4);
/// Slots 3 and 4 disabled: two enabled slots is two samples per frame.
const MULTI_LED_SLOT_34: u8 = 0x00;

/// Enabled slots, and therefore samples per FIFO frame.
pub const SLOTS: usize = 2;

/// Bytes per FIFO sample: three, MSB first, of which the low 18 bits are the
/// count.
const SAMPLE_BYTES: usize = 3;

/// 18-bit ADC. Narrower than the MAX86177's 19-bit converter, which is why
/// [`PpgScale::BITS_18`] exists — a threshold in counts means nothing without
/// this number behind it.
const ADC_MASK: u32 = 0x0003_FFFF;

/// Green LED drive seed. The value most likely to want a bench tweak: raise it
/// if the resting DC sits too low to see a pulse, lower it if the ADC rails.
const LED_PA_DEFAULT_CODE: u8 = 0x24;

/// The LED drive code [`Max30101::init`] programs.
pub const LED_PA_DEFAULT: u8 = LED_PA_DEFAULT_CODE;

/// Largest LEDx_PA code. The field is a full 8-bit current DAC.
pub const LED_PA_MAX: u8 = 0xFF;

/// Logical tag this driver assigns to the LED-on (green) slot.
pub const PPG_TAG: u8 = 1;

/// Logical tag this driver assigns to the LED-off ambient slot.
pub const AMBIENT_TAG: u8 = 2;

/// FIFO depth in samples, from the datasheet. Used to bound a drain so a
/// runaway loop cannot spin on a misbehaving part.
const FIFO_DEPTH_SAMPLES: usize = 32;

/// Bounded read budget for the reset bit to self-clear, so a dead bus fails
/// fast instead of hanging `init`.
const RESET_POLL_MAX: u32 = 256;

/// Bounded read budget for the one-shot temperature conversion.
const TEMP_POLL_MAX: u32 = 256;

/// One-shot die-temperature conversion enable; self-clears when the result
/// latches.
const TEMP_EN: u8 = 1 << 0;

/// `TEMP_FRAC` carries the fraction in its low nibble, one LSB = 1/16 degC.
const TEMP_FRAC_MASK: u8 = 0x0F;

#[derive(Debug)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Error<E> {
    I2c(E),
    /// `PART_ID` did not read back [`PART_ID`], so whatever answered on 0x57
    /// is not a MAX3010x at all. Note what this does *not* catch: every part
    /// in the family reports the same id, so a MAX30102 passes here.
    WrongPart(u8),
    /// `LED3_PA` would not hold the drive code written to it — the part has no
    /// third LED channel, which is the signature of a MAX30102 fitted in place
    /// of a MAX30101. Carries the value that read back.
    ///
    /// Green is the wrist wavelength; red and IR are a fingertip-SpO2 pair. A
    /// part missing it configures cleanly through every other register in this
    /// driver and then samples ambient light on the slot the detector treats
    /// as the pulse, so the mistake has to be caught here.
    ///
    /// **What this check can and cannot promise.** A MAX30101 always holds the
    /// register, so a genuine part is never refused. A MAX30102 has no such
    /// register, and reserved-address behaviour is not specified — the likely
    /// read is `0x00`, but silicon whose register file happens to echo writes
    /// would slip through. `watch_core::ppg::EmitterCheck` is the backstop for
    /// that case: it watches for LED drive pinned at its ceiling with no
    /// LED-reflected DC to show for it.
    NoGreenChannel(u8),
    /// The reset bit never cleared within [`RESET_POLL_MAX`] reads.
    ResetTimeout,
    /// The temperature conversion never completed within [`TEMP_POLL_MAX`]
    /// reads.
    TempTimeout,
}

/// Decode one 3-byte FIFO sample into its 18-bit photodiode count.
///
/// Pure so it is exercised on the host. There is no tag to extract — that is
/// the point of this part's FIFO, and why [`assign_tag`] exists separately.
pub fn decode_sample(buf: [u8; SAMPLE_BYTES]) -> u32 {
    ((u32::from(buf[0]) << 16) | (u32::from(buf[1]) << 8) | u32::from(buf[2])) & ADC_MASK
}

/// The logical tag for the sample at `index_in_frame`.
///
/// This is the positional-FIFO half of the contract: slot order is the only
/// thing that identifies a sample, so the tag is derived from where the sample
/// sat in its frame rather than read from it. Out-of-range indices fold onto
/// the ambient slot, which is the fail-safe direction — a mis-indexed sample
/// fed to the detector as *ambient* perturbs a subtraction, whereas one fed as
/// *PPG* is a fabricated pulse sample.
pub fn assign_tag(index_in_frame: usize) -> u8 {
    if index_in_frame.is_multiple_of(SLOTS) {
        PPG_TAG
    } else {
        AMBIENT_TAG
    }
}

/// Decode the die-temperature registers to milli-degrees Celsius. `TEMP_INT` is
/// a signed whole-degree count (two's complement) and `TEMP_FRAC` adds a
/// positive 1/16-degC fraction from its low nibble, so a sub-zero reading is
/// e.g. int = -6, frac = 8 -> -5.500 degC.
pub fn decode_die_temp_milli_c(temp_int: u8, temp_frac: u8) -> i32 {
    let whole = (temp_int as i8) as i32;
    let frac = (temp_frac & TEMP_FRAC_MASK) as i32;
    whole * 1000 + (frac * 625 + 5) / 10
}

pub struct Max30101<I2C> {
    i2c: I2C,
    /// Buffered whole frame, plus how far into it the caller has read. Holding
    /// a frame rather than a sample is what keeps slot phase from slipping.
    frame: [u32; SLOTS],
    frame_len: usize,
    frame_pos: usize,
}

impl<I2C: I2c> Max30101<I2C> {
    pub fn new(i2c: I2C) -> Self {
        Self {
            i2c,
            frame: [0; SLOTS],
            frame_len: 0,
            frame_pos: 0,
        }
    }

    /// Verify the part, soft-reset it, configure the green PPG slot plus the
    /// LED-off ambient slot, and start sampling into the FIFO.
    ///
    /// Two checks guard this, because the obvious one is not enough. The
    /// `PART_ID` read runs **first**, before any write, and rules out an
    /// unrelated device answering on 0x57. It cannot rule out a MAX30102: the
    /// whole family reports the same id. So the emitter that actually matters
    /// is checked by capability rather than by nameplate — `LED3_PA` is
    /// written and read back, and a part with no third LED channel cannot hold
    /// it. Both run before the mode write, so a part that fails either never
    /// streams a sample.
    pub fn init(&mut self) -> Result<(), Error<I2C::Error>> {
        let id = self.read_reg(reg::PART_ID)?;
        if id != PART_ID {
            return Err(Error::WrongPart(id));
        }

        self.write_reg(reg::MODE_CONFIG, MODE_RESET)?;
        self.wait_reset()?;

        self.write_reg(reg::FIFO_CONFIG, FIFO_CONFIG)?;
        self.write_reg(reg::SPO2_CONFIG, SPO2_CONFIG)?;

        // Every emitter except the green one on slot 1 stays dark: this is a
        // wrist HR sensor, and an emitter nothing samples is only heat and
        // battery. The reset above already zeroed these, so the writes are
        // documentary — they say "considered, and deliberately off", which is
        // the difference between a dark LED4 and an LED4 nobody thought about.
        self.write_reg(reg::LED1_PA, 0)?;
        self.write_reg(reg::LED2_PA, 0)?;
        self.write_reg(reg::LED3_PA, LED_PA_DEFAULT_CODE)?;
        let led3 = self.read_reg(reg::LED3_PA)?;
        if led3 != LED_PA_DEFAULT_CODE {
            return Err(Error::NoGreenChannel(led3));
        }
        self.write_reg(reg::LED4_PA, 0)?;

        self.write_reg(reg::MULTI_LED_SLOT_12, MULTI_LED_SLOT_12)?;
        self.write_reg(reg::MULTI_LED_SLOT_34, MULTI_LED_SLOT_34)?;

        self.write_reg(reg::MODE_CONFIG, MODE_MULTI_LED)?;
        self.flush_fifo()
    }

    /// Number of unread samples in the FIFO, from the write/read pointer pair.
    ///
    /// Wraps modulo the FIFO depth, so a writer that has lapped the reader
    /// reports as full rather than as empty — the ambiguity the overflow
    /// counter exists to resolve, and which [`read_tagged_sample`] handles by
    /// resynchronising rather than by trusting the difference.
    ///
    /// [`read_tagged_sample`]: Max30101::read_tagged_sample
    pub fn available(&mut self) -> Result<usize, Error<I2C::Error>> {
        let wr = usize::from(self.read_reg(reg::FIFO_WR_PTR)? & 0x1F);
        let rd = usize::from(self.read_reg(reg::FIFO_RD_PTR)? & 0x1F);
        Ok((wr + FIFO_DEPTH_SAMPLES - rd) % FIFO_DEPTH_SAMPLES)
    }

    /// Pop the next sample with its positionally-assigned tag, or `None` when
    /// no whole frame is available.
    ///
    /// Never returns a sample from a partial frame. If the FIFO holds fewer
    /// than [`SLOTS`] samples the frame is still being written, and taking the
    /// first of them would put every later sample on the wrong slot.
    pub fn read_tagged_sample(&mut self) -> Result<Option<FifoWord>, Error<I2C::Error>> {
        if self.frame_pos == self.frame_len && !self.refill_frame()? {
            return Ok(None);
        }
        let value = self.frame[self.frame_pos];
        let tag = assign_tag(self.frame_pos);
        self.frame_pos += 1;
        Ok(Some(FifoWord { tag, value }))
    }

    /// Set the green LED's drive current (LED3_PA).
    pub fn set_led_current(&mut self, pa: u8) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::LED3_PA, pa)
    }

    /// Trigger a one-shot die-temperature conversion and return milli-degrees
    /// Celsius.
    pub fn read_die_temp_milli_c(&mut self) -> Result<i32, Error<I2C::Error>> {
        self.write_reg(reg::TEMP_CONFIG, TEMP_EN)?;
        self.wait_temp()?;
        let whole = self.read_reg(reg::TEMP_INT)?;
        let frac = self.read_reg(reg::TEMP_FRAC)?;
        Ok(decode_die_temp_milli_c(whole, frac))
    }

    /// Put the part into shutdown, releasing the LED drive current.
    ///
    /// Preserves the mode bits, so [`wake`](Self::wake) restores multi-LED mode
    /// rather than leaving the part in the heart-rate mode a bare write of the
    /// shutdown bit would select. Register state is documented to survive
    /// shutdown; that it actually does is a bench item, and it is a *new* one
    /// against this part rather than one inherited from the MAX86177
    /// (decisions.md § 623).
    pub fn shutdown(&mut self) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::MODE_CONFIG, MODE_SHUTDOWN | MODE_MULTI_LED)
    }

    /// Wake from shutdown and resume sampling, flushing the FIFO so counts
    /// buffered before the shutdown cannot replay into a freshly reset detector
    /// as a live pulse — and so the new window starts on a frame boundary.
    pub fn wake(&mut self) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::MODE_CONFIG, MODE_MULTI_LED)?;
        self.flush_fifo()
    }

    /// Zero the FIFO pointers and the overflow counter, and drop any buffered
    /// frame. Resetting the host-side frame index here is what makes slot phase
    /// re-derived per window rather than carried across one.
    fn flush_fifo(&mut self) -> Result<(), Error<I2C::Error>> {
        self.write_reg(reg::FIFO_WR_PTR, 0)?;
        self.write_reg(reg::OVF_COUNTER, 0)?;
        self.write_reg(reg::FIFO_RD_PTR, 0)?;
        self.frame_len = 0;
        self.frame_pos = 0;
        Ok(())
    }

    /// Read one whole frame into the buffer. Returns `false` when the FIFO does
    /// not hold a complete one, or when an overflow has made its alignment
    /// unknowable.
    fn refill_frame(&mut self) -> Result<bool, Error<I2C::Error>> {
        // An overflow means the part overwrote samples the host never read. If
        // it dropped an ODD number, slot phase has slipped and every later
        // frame is transposed — the exact failure whole-frame reads exist to
        // prevent, arriving by a different door. `OVF_COUNTER` saturates and so
        // cannot say how many were lost, and the pointer pair cannot either
        // (`wr - rd` is the same modulo the depth), so parity is genuinely
        // unrecoverable. Give up the window's alignment and re-derive it: a few
        // lost samples cost a fraction of a second of pulse, a transposed
        // stream costs a plausible wrong heart rate for the whole window.
        if self.read_reg(reg::OVF_COUNTER)? != 0 {
            self.flush_fifo()?;
            return Ok(false);
        }
        let avail = self.available()?;
        if avail < SLOTS {
            return Ok(false);
        }
        let mut buf = [0u8; SLOTS * SAMPLE_BYTES];
        self.read_regs(reg::FIFO_DATA, &mut buf)?;
        for (i, chunk) in buf.chunks_exact(SAMPLE_BYTES).enumerate() {
            self.frame[i] = decode_sample([chunk[0], chunk[1], chunk[2]]);
        }
        self.frame_len = SLOTS;
        self.frame_pos = 0;
        Ok(true)
    }

    fn wait_reset(&mut self) -> Result<(), Error<I2C::Error>> {
        for _ in 0..RESET_POLL_MAX {
            if self.read_reg(reg::MODE_CONFIG)? & MODE_RESET == 0 {
                return Ok(());
            }
        }
        Err(Error::ResetTimeout)
    }

    fn wait_temp(&mut self) -> Result<(), Error<I2C::Error>> {
        for _ in 0..TEMP_POLL_MAX {
            if self.read_reg(reg::TEMP_CONFIG)? & TEMP_EN == 0 {
                return Ok(());
            }
        }
        Err(Error::TempTimeout)
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

/// The MAX30101 half of the [`PpgAfe`] contract.
impl<I2C: I2c> PpgAfe for Max30101<I2C> {
    type Error = Error<I2C::Error>;

    fn init(&mut self) -> Result<(), Self::Error> {
        Max30101::init(self)
    }

    fn read_tagged_sample(&mut self) -> Result<Option<FifoWord>, Self::Error> {
        Max30101::read_tagged_sample(self)
    }

    fn set_led_current(&mut self, pa: u8) -> Result<(), Self::Error> {
        Max30101::set_led_current(self, pa)
    }

    fn shutdown(&mut self) -> Result<(), Self::Error> {
        Max30101::shutdown(self)
    }

    fn wake(&mut self) -> Result<(), Self::Error> {
        Max30101::wake(self)
    }

    /// 18-bit converter — half the MAX86177's counts for the same scene, which
    /// is the whole reason [`PpgScale`] is data rather than constants.
    fn scale(&self) -> PpgScale {
        PpgScale::BITS_18
    }

    fn agc_config(&self) -> AgcConfig {
        AgcConfig::BITS_18
    }

    fn led_pa_default(&self) -> u8 {
        LED_PA_DEFAULT
    }

    /// Positional tags this driver assigns, not fields the hardware transmits.
    fn tags(&self) -> FifoTags {
        FifoTags {
            ppg: PPG_TAG,
            ambient: AMBIENT_TAG,
        }
    }
}
