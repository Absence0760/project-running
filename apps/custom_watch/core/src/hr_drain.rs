//! FIFO drain decisions for the app's `hr` task — the demux, the LED auto-gain
//! cadence, and the between-window wait that used to be inlined in the async
//! task body.
//!
//! [`crate::hr_duty`] owns *when* the MAX86177 samples (the mode-keyed duty
//! schedule) and the driver's `peak_detect` owns the pulse maths. This module
//! owns the three decisions in between:
//!
//! - **Slot demux.** The FIFO interleaves two measurement slots — MEAS1
//!   (LED-on PPG) and MEAS2 (LED-off ambient) — told apart only by their word
//!   tags. Each PPG count must be paired with the *latest* ambient count for
//!   subtraction (bright-sun recovery), and a word carrying a tag we never
//!   enabled must be **dropped**, never fed to the detector as PPG: a marker
//!   or mis-decoded word pushed through as a pulse sample corrupts the
//!   estimate. [`FifoDemux`] holds that latch and that rule.
//! - **LED auto-gain cadence.** [`AgcCadence`] decides *when* the drive may be
//!   stepped; the driver's `agc_next_pa_ambient` decides *by how much*. The
//!   loop holds its drive both before a full period of pulse samples has been
//!   drained and while the detector has no DC baseline to judge, and a
//!   duty-cycle wake buys the freshly-woken part a whole fresh period before
//!   its first step.
//! - **Between-window wait.** [`next_window_wait_s`] is how long the task
//!   sleeps once a duty-cycled window closes (and how long it defers after a
//!   failed wake). Never zero — a zero-duration timer would spin the drain
//!   loop at executor pace instead of parking it.
//!
//! The tags themselves live in the driver crate, so they are passed in
//! ([`FifoTags`]) rather than imported: `watch_core` stays hardware-free.

use crate::hr_duty::DutyWindow;

/// The measurement slots the `hr` task enables, by FIFO word tag. Named fields
/// because the two are indistinguishable as bare `u8`s at a call site and
/// swapping them would feed ambient counts to the pulse detector.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct FifoTags {
    /// MEAS1 — the LED-on photoplethysmogram the detector consumes.
    pub ppg: u8,
    /// MEAS2 — the LED-off ambient reading each PPG count is corrected against.
    pub ambient: u8,
}

/// What one drained FIFO word turned out to be.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum FifoSlot {
    /// A pulse sample: push it to the detector, corrected against
    /// [`FifoDemux::ambient`].
    Ppg,
    /// An ambient sample: latched, nothing else to do.
    Ambient,
    /// Not a slot we enabled — dropped. A persistent one means config drift.
    Unknown,
}

/// The ambient latch every drained PPG word is corrected against.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FifoDemux {
    tags: FifoTags,
    ambient: i32,
}

impl FifoDemux {
    pub const fn new(tags: FifoTags) -> Self {
        Self { tags, ambient: 0 }
    }

    /// Classify one drained word, latching it when it is the ambient slot.
    ///
    /// The ambient slot is tested first, so a misconfiguration that gave both
    /// slots the same tag latches ambient rather than feeding raw LED-off
    /// counts to the pulse detector.
    pub fn apply(&mut self, tag: u8, value: i32) -> FifoSlot {
        if tag == self.tags.ambient {
            self.ambient = value;
            FifoSlot::Ambient
        } else if tag == self.tags.ppg {
            FifoSlot::Ppg
        } else {
            FifoSlot::Unknown
        }
    }

    /// The latest ambient count, or `0` before the first ambient word of this
    /// sampling window has arrived — no subtraction, i.e. an honest raw read
    /// rather than a guess.
    pub const fn ambient(&self) -> i32 {
        self.ambient
    }

    /// Drop the latch on a duty-cycle wake: the pre-shutdown ambient level is
    /// a whole off-window old and the light the wrist sits in may have changed
    /// completely, so correcting the first fresh pulse samples against it would
    /// be worse than not correcting them at all.
    pub fn reset(&mut self) {
        self.ambient = 0;
    }
}

/// The detector's two DC estimates at the moment the LED auto-gain loop is
/// allowed to look. Named fields because they are indistinguishable as bare
/// `u32`s and the loop judges them for different things: `corrected` for
/// brightness (ambient cancels out of it, so sunlight flicker cannot walk the
/// drive), `raw` for the ADC clipping headroom that subtraction cannot recover.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct AgcDc {
    pub raw: u32,
    pub corrected: u32,
}

/// When the LED auto-gain loop may step the drive. The step size, hysteresis
/// and clamps belong to the driver's `agc_next_pa_ambient`; this is only the
/// cadence around it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AgcCadence {
    period_samples: u32,
    samples: u32,
}

impl AgcCadence {
    /// At most one step per second of pulse samples: the detector's DC baseline
    /// (tau ~0.64 s at 100 Hz) has to re-settle between corrections, and the
    /// target band's hysteresis absorbs the residual lag, so the loop converges
    /// without hunting. The period is at least one sample, so a nonsense
    /// sampling rate cannot make every single sample due.
    pub const fn per_second(sample_rate_hz: u32) -> Self {
        Self {
            period_samples: if sample_rate_hz < 1 {
                1
            } else {
                sample_rate_hz
            },
            samples: 0,
        }
    }

    /// Count one PPG word drained from the FIFO. Ambient and dropped words do
    /// not count: the DC baseline the loop judges only advances on pulse
    /// samples, so a window that yields nothing but ambient never comes due.
    pub fn sample(&mut self) {
        self.samples = self.samples.saturating_add(1);
    }

    /// The DC pair the drive may be stepped from right now, or `None` to hold
    /// it — before the period has elapsed, or while the detector has no
    /// baseline yet.
    ///
    /// The period is consumed only when a step is actually authorised. A period
    /// that elapses with no baseline therefore leaves the count standing, and
    /// the loop steps on the first check at or after the period with both
    /// estimates present rather than throwing the elapsed period away and
    /// waiting a whole second more.
    pub fn due(&mut self, raw_dc: Option<u32>, corrected_dc: Option<u32>) -> Option<AgcDc> {
        if self.samples < self.period_samples {
            return None;
        }
        let dc = AgcDc {
            raw: raw_dc?,
            corrected: corrected_dc?,
        };
        self.samples = 0;
        Some(dc)
    }

    /// Drop the count on a duty-cycle wake, so the freshly-woken part gets a
    /// full period of live samples before its first gain step.
    ///
    /// This — not the detector's DC estimates — is what holds the loop after a
    /// wake. `PeakDetector::reset` clears the estimates, but they read `Some`
    /// again from the very first pushed sample, so without this reset the first
    /// poll of a new window would step the drive off a one-sample-old baseline.
    pub fn reset(&mut self) {
        self.samples = 0;
    }
}

/// Seconds to wait for `window`'s next sampling window to open, from
/// `now_s`. At least 1: a zero-duration timer would spin the drain loop at
/// executor pace instead of parking the task for the off-window.
pub const fn next_window_wait_s(window: DutyWindow, now_s: u32) -> u32 {
    let wait = window.next_start_s(now_s).saturating_sub(now_s);
    if wait < 1 {
        1
    } else {
        wait
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gnss_mode::GnssMode;
    use crate::hr_duty::{duty_window, shown_bpm, HrSample, BALANCED_PERIOD_S, ON_S};

    const TAGS: FifoTags = FifoTags {
        ppg: 0x01,
        ambient: 0x02,
    };

    #[test]
    fn an_ambient_word_is_latched_for_the_next_pulse_sample() {
        let mut d = FifoDemux::new(TAGS);
        assert_eq!(d.apply(TAGS.ambient, 4_200), FifoSlot::Ambient);
        assert_eq!(d.ambient(), 4_200);
        assert_eq!(d.apply(TAGS.ppg, 30_000), FifoSlot::Ppg);
        assert_eq!(d.ambient(), 4_200, "a pulse word must not move the latch");
    }

    #[test]
    fn the_latest_ambient_wins() {
        // Bright-sun recovery depends on the correction tracking the light the
        // wrist is actually in, not the first reading of the window.
        let mut d = FifoDemux::new(TAGS);
        for level in [100, 9_000, 250] {
            d.apply(TAGS.ambient, level);
            assert_eq!(d.ambient(), level);
        }
    }

    #[test]
    fn before_the_first_ambient_word_there_is_no_subtraction() {
        // Zero is the honest raw read; guessing an ambient level would bias
        // every pulse sample of the window.
        let d = FifoDemux::new(TAGS);
        assert_eq!(d.ambient(), 0);
    }

    #[test]
    fn an_unknown_tag_is_dropped_not_treated_as_a_pulse() {
        // A marker or mis-decoded word fed to the detector as PPG corrupts the
        // BPM estimate outright.
        let mut d = FifoDemux::new(TAGS);
        d.apply(TAGS.ambient, 500);
        for tag in [0x00, 0x03, 0x0f, 0xff] {
            assert_eq!(d.apply(tag, 99_999), FifoSlot::Unknown);
        }
        assert_eq!(d.ambient(), 500, "a dropped word must not move the latch");
    }

    #[test]
    fn a_duplicated_tag_config_latches_ambient_rather_than_faking_a_pulse() {
        // Both slots configured to the same tag is config drift; the safe
        // reading of an ambiguous word is "ambient", because the alternative
        // pushes LED-off counts through the pulse detector.
        let mut d = FifoDemux::new(FifoTags {
            ppg: 0x02,
            ambient: 0x02,
        });
        assert_eq!(d.apply(0x02, 777), FifoSlot::Ambient);
    }

    #[test]
    fn a_window_wake_drops_the_stale_ambient_level() {
        let mut d = FifoDemux::new(TAGS);
        d.apply(TAGS.ambient, 8_000);
        d.reset();
        assert_eq!(d.ambient(), 0);
    }

    /// The sampling rate the `hr` task configures the part at.
    const RATE_HZ: u32 = 100;
    const DC: (Option<u32>, Option<u32>) = (Some(200_000), Some(180_000));

    fn drain_pulses(agc: &mut AgcCadence, n: u32) {
        for _ in 0..n {
            agc.sample();
        }
    }

    #[test]
    fn the_drive_holds_until_a_full_period_of_pulse_samples() {
        // Stepping faster than the DC baseline can re-settle (tau ~0.64 s) makes
        // the loop hunt: it would keep correcting against the level it set two
        // corrections ago.
        let mut agc = AgcCadence::per_second(RATE_HZ);
        for _ in 0..RATE_HZ - 1 {
            assert_eq!(agc.due(DC.0, DC.1), None);
            agc.sample();
        }
        agc.sample();
        assert_eq!(
            agc.due(DC.0, DC.1),
            Some(AgcDc {
                raw: 200_000,
                corrected: 180_000,
            })
        );
    }

    #[test]
    fn an_absent_dc_estimate_holds_the_drive_however_long_the_period_ran() {
        // A half-settled or missing baseline is not something to step a gain
        // off; the honest move is to keep the current drive and look again.
        let mut agc = AgcCadence::per_second(RATE_HZ);
        drain_pulses(&mut agc, RATE_HZ * 3);
        assert_eq!(agc.due(None, None), None);
        assert_eq!(agc.due(Some(200_000), None), None);
        assert_eq!(agc.due(None, Some(180_000)), None);
    }

    #[test]
    fn the_step_lands_on_the_first_check_once_the_baseline_arrives() {
        // The elapsed period must not be thrown away by a check that did not
        // step: the loop already waited its second, so it is due the moment it
        // has something to judge, not a whole second later. Holds however long
        // the outage ran.
        let mut agc = AgcCadence::per_second(RATE_HZ);
        drain_pulses(&mut agc, RATE_HZ);
        assert_eq!(agc.due(None, None), None);
        assert!(agc.due(DC.0, DC.1).is_some());

        drain_pulses(&mut agc, RATE_HZ * 5);
        for _ in 0..5 {
            assert_eq!(agc.due(None, None), None);
        }
        assert!(agc.due(DC.0, DC.1).is_some());
    }

    #[test]
    fn a_step_consumes_the_period() {
        let mut agc = AgcCadence::per_second(RATE_HZ);
        drain_pulses(&mut agc, RATE_HZ);
        assert!(agc.due(DC.0, DC.1).is_some());
        assert_eq!(agc.due(DC.0, DC.1), None, "two steps back to back");
        drain_pulses(&mut agc, RATE_HZ - 1);
        assert_eq!(agc.due(DC.0, DC.1), None);
        agc.sample();
        assert!(agc.due(DC.0, DC.1).is_some());
    }

    #[test]
    fn a_duty_cycle_wake_buys_a_full_reconvergence_window() {
        // The DC estimates are `Some` again from the first sample after
        // `PeakDetector::reset`, so they cannot be what holds the loop — only
        // this count reset stops the freshly-woken part taking a gain step off a
        // one-sample-old baseline.
        let mut agc = AgcCadence::per_second(RATE_HZ);
        drain_pulses(&mut agc, RATE_HZ - 1);
        agc.reset();
        agc.sample();
        assert_eq!(agc.due(DC.0, DC.1), None);
        drain_pulses(&mut agc, RATE_HZ - 1);
        assert!(agc.due(DC.0, DC.1).is_some());
    }

    #[test]
    fn only_pulse_words_advance_the_period() {
        // Driven exactly as the drain loop drives it: the demux classifies, and
        // only the PPG slot counts. An ambient-only or stray-tag stretch must
        // not walk the drive on a baseline that never moved.
        let mut demux = FifoDemux::new(TAGS);
        let mut agc = AgcCadence::per_second(RATE_HZ);
        for _ in 0..RATE_HZ * 4 {
            for tag in [TAGS.ambient, 0x7f] {
                if demux.apply(tag, 1_000) == FifoSlot::Ppg {
                    agc.sample();
                }
            }
        }
        assert_eq!(agc.due(DC.0, DC.1), None);
        for _ in 0..RATE_HZ {
            if demux.apply(TAGS.ppg, 200_000) == FifoSlot::Ppg {
                agc.sample();
            }
        }
        assert!(agc.due(DC.0, DC.1).is_some());
    }

    #[test]
    fn the_cadence_is_one_step_per_second_at_the_sampling_rate() {
        // The tau ~0.64 s settling derivation is in samples, so it only holds
        // while the period tracks the rate the part is actually configured at.
        for rate in [50, RATE_HZ, 400] {
            let mut agc = AgcCadence::per_second(rate);
            drain_pulses(&mut agc, rate - 1);
            assert_eq!(agc.due(DC.0, DC.1), None, "rate={rate}");
            agc.sample();
            assert!(agc.due(DC.0, DC.1).is_some(), "rate={rate}");
        }
    }

    #[test]
    fn a_zero_sampling_rate_still_requires_a_pulse_sample() {
        // A zero period would step the drive on a poll that drained nothing at
        // all — a gain walk driven by the executor rather than by the signal.
        let mut agc = AgcCadence::per_second(0);
        assert_eq!(agc.due(DC.0, DC.1), None);
        agc.sample();
        assert!(agc.due(DC.0, DC.1).is_some());
    }

    #[test]
    fn a_reading_is_held_across_an_off_window_rather_than_re_sampled() {
        // The whole point of duty-cycling: through the off-window the task
        // parks, drains nothing, and publishes nothing — so the reading from the
        // tail of the last on-window is still what a consumer shows when the
        // next window opens, and the woken part owes a fresh period before it
        // touches the drive.
        let mode = GnssMode::Balanced;
        let w = duty_window(mode).unwrap();
        let last = Some(HrSample {
            bpm: Some(152),
            at_s: ON_S - 1,
        });
        let mut agc = AgcCadence::per_second(RATE_HZ);
        drain_pulses(&mut agc, RATE_HZ * ON_S);

        let wake_s = ON_S + next_window_wait_s(w, ON_S);
        assert_eq!(wake_s, BALANCED_PERIOD_S);
        assert!(w.is_on(wake_s), "the wait must land inside a window");
        assert_eq!(
            shown_bpm(last, wake_s, mode),
            Some(152),
            "the held reading must survive the gap it was budgeted for"
        );

        agc.reset();
        agc.sample();
        assert_eq!(agc.due(DC.0, DC.1), None);
    }

    #[test]
    fn the_wait_lands_on_the_next_window_boundary() {
        let w = duty_window(GnssMode::Balanced).unwrap();
        // From the instant the window closes, and from deep inside the
        // off-stretch, the wait ends exactly at the next period boundary.
        assert_eq!(next_window_wait_s(w, ON_S), BALANCED_PERIOD_S - ON_S);
        assert_eq!(next_window_wait_s(w, BALANCED_PERIOD_S - 1), 1);
        assert_eq!(next_window_wait_s(w, BALANCED_PERIOD_S), BALANCED_PERIOD_S);
    }

    #[test]
    fn the_wait_is_never_zero() {
        // A zero-duration timer returns immediately, turning the off-window
        // into a busy loop at executor pace — the opposite of duty-cycling.
        for mode in [GnssMode::Balanced, GnssMode::Expedition] {
            let w = duty_window(mode).unwrap();
            for now in [0, 1, 14, 15, 59, 60, 119, 120, u32::MAX - 1, u32::MAX] {
                assert!(next_window_wait_s(w, now) >= 1, "now={now}");
            }
        }
    }

    #[test]
    fn a_saturated_clock_still_parks_the_task() {
        // At the u32 uptime ceiling `next_start_s` saturates to now, so the
        // subtraction is zero and only the floor keeps the task from spinning.
        let w = duty_window(GnssMode::Expedition).unwrap();
        assert_eq!(next_window_wait_s(w, u32::MAX), 1);
    }
}
