//! FIFO drain decisions for the app's `hr` task — the demux + between-window
//! wait that used to be inlined in the async task body.
//!
//! [`crate::hr_duty`] owns *when* the MAX86177 samples (the mode-keyed duty
//! schedule) and the driver's `peak_detect` owns the pulse maths. This module
//! owns the two decisions in between:
//!
//! - **Slot demux.** The FIFO interleaves two measurement slots — MEAS1
//!   (LED-on PPG) and MEAS2 (LED-off ambient) — told apart only by their word
//!   tags. Each PPG count must be paired with the *latest* ambient count for
//!   subtraction (bright-sun recovery), and a word carrying a tag we never
//!   enabled must be **dropped**, never fed to the detector as PPG: a marker
//!   or mis-decoded word pushed through as a pulse sample corrupts the
//!   estimate. [`FifoDemux`] holds that latch and that rule.
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
    use crate::hr_duty::{duty_window, BALANCED_PERIOD_S, ON_S};

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
