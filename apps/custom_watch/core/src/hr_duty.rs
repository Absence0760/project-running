//! Optical-HR duty-cycling — the deliberate mode/fidelity trade the README's
//! power discipline owes: the MAX86177's LED drive dominates HR power, so a
//! throttled recording mode samples the pulse in short windows instead of
//! 100 Hz continuously, and every consumer of the reading honours the same
//! bounded staleness so a duty-cycled HR never *looks* continuous.
//!
//! The schedule keys off the one battery surface the watch already has —
//! [`GnssMode`] (Performance / Balanced / Expedition) — rather than a second
//! picker: a runner who chose a multi-day GNSS cadence has already chosen
//! hours over fidelity, and BTN3 freezes the mode for a run's duration
//! (`crate::button::btn3_action`), so the schedule can never shift mid-run.
//!
//! Window choices, from the detector's own convergence needs (derivations,
//! not measurements — the tier-1 DK cannot measure power, same honesty rule
//! as [`crate::gnss_mode`]'s battery projections):
//! - **On-window [`ON_S`] = 15 s.** A freshly woken detector must re-settle
//!   its DC baseline (~0.64 s EMA corner) and then see [`MIN_GOOD_BEATS`-class]
//!   agreeing inter-beat intervals before it reports valid — ~2–3 s at a
//!   running 140–170 bpm, ~6 s at the 30 bpm floor. 15 s covers the worst
//!   case ~2× over and still yields several seconds of trusted readings per
//!   window.
//! - **Balanced: one window per 60 s** — LED on 25 % of the time, an HR
//!   sample rate matching the mode's own 15 s fix cadence class.
//! - **Expedition: one window per 120 s** — LED on 12.5 %, the multi-day
//!   setting where hours beat per-minute HR fidelity.
//!
//! The saving is *additive to and not folded into* `GnssMode::battery_est_h`:
//! that derivation charges only the GNSS receiver's half of the recording
//! draw, and quantifying the HR half honestly needs a PPK2 on real parts.
//!
//! Staleness contract (`hold_budget_s` / [`shown_bpm`]): the last valid
//! reading may be shown — and may keep banking its HR zone — for at most one
//! full schedule period, i.e. through one off-window while the next window
//! gets its own on-window to re-converge; past that the value blanks and
//! banks nothing. Continuous mode keeps the face's ordinary
//! [`crate::face::STALE_AFTER_S`] freshness budget, so a wedged sensor bus
//! can no longer freeze a reading on screen forever. The reading must never
//! look fresher than it is.

use crate::face::STALE_AFTER_S;
use crate::gnss_mode::GnssMode;

/// Seconds the sensor samples at the start of each duty-cycled period. See
/// the module docs for the convergence derivation.
pub const ON_S: u32 = 15;

/// Duty-cycled period per throttled mode, seconds. One on-window of [`ON_S`]
/// opens at each period boundary.
pub const BALANCED_PERIOD_S: u32 = 60;
pub const EXPEDITION_PERIOD_S: u32 = 120;

/// The latest HR estimate as published on the `HR` watch: the detector's
/// valid BPM (or `None` while no pulse is trusted) stamped with the uptime it
/// was produced at, so every consumer can age it against [`shown_bpm`]'s hold
/// budget instead of trusting a value of unknown vintage.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HrSample {
    pub bpm: Option<u16>,
    pub at_s: u32,
}

/// One duty-cycled sampling schedule: `on_s` seconds of sampling at the start
/// of every `period_s`-second period, phase-locked to uptime zero.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct DutyWindow {
    pub on_s: u32,
    pub period_s: u32,
}

impl DutyWindow {
    /// Whether the sensor should be sampling at this uptime.
    pub const fn is_on(&self, uptime_s: u32) -> bool {
        uptime_s % self.period_s < self.on_s
    }

    /// Uptime of the next window start strictly after `uptime_s` — where the
    /// hr task sleeps to between windows, and where a failed wake retries.
    pub const fn next_start_s(&self, uptime_s: u32) -> u32 {
        (uptime_s / self.period_s)
            .saturating_add(1)
            .saturating_mul(self.period_s)
    }
}

/// The sampling schedule for a mode, or `None` for continuous sampling
/// (Performance — the current-behaviour safe default).
pub const fn duty_window(mode: GnssMode) -> Option<DutyWindow> {
    match mode {
        GnssMode::Performance => None,
        GnssMode::Balanced => Some(DutyWindow {
            on_s: ON_S,
            period_s: BALANCED_PERIOD_S,
        }),
        GnssMode::Expedition => Some(DutyWindow {
            on_s: ON_S,
            period_s: EXPEDITION_PERIOD_S,
        }),
    }
}

/// Whether the sensor should be sampling right now in this mode.
pub const fn sampling_on(mode: GnssMode, uptime_s: u32) -> bool {
    match duty_window(mode) {
        None => true,
        Some(w) => w.is_on(uptime_s),
    }
}

/// How long a valid reading may be shown (and bank zone time) after it was
/// produced. One full period in a duty-cycled mode — through one off-window,
/// giving the next window its own [`ON_S`] to re-converge before the value
/// blanks; the face's ordinary freshness budget in continuous mode.
pub const fn hold_budget_s(mode: GnssMode) -> u32 {
    match duty_window(mode) {
        None => STALE_AFTER_S,
        Some(w) => w.period_s,
    }
}

/// The BPM a consumer may honestly act on right now: the sample's valid BPM
/// while it is within the mode's hold budget, else `None`. Every reader of
/// the HR watch — the face's HR rows, the recorder's zone banking, the
/// zone-ceiling alert, the stored track points — routes through this, so a
/// duty-cycled gap degrades everywhere at the same moment.
pub fn shown_bpm(sample: Option<HrSample>, now_s: u32, mode: GnssMode) -> Option<u16> {
    let s = sample?;
    let bpm = s.bpm?;
    (now_s.saturating_sub(s.at_s) <= hold_budget_s(mode)).then_some(bpm)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MODES: [GnssMode; 3] = [
        GnssMode::Performance,
        GnssMode::Balanced,
        GnssMode::Expedition,
    ];

    fn valid(bpm: u16, at_s: u32) -> Option<HrSample> {
        Some(HrSample {
            bpm: Some(bpm),
            at_s,
        })
    }

    #[test]
    fn performance_samples_continuously() {
        assert_eq!(duty_window(GnssMode::Performance), None);
        for t in [0, 14, 15, 59, 60, 3600, u32::MAX] {
            assert!(sampling_on(GnssMode::Performance, t));
        }
    }

    #[test]
    fn schedule_constants_are_pinned() {
        // The module docs derive the hold rule and the LED duty fractions
        // (25 % / 12.5 %) from these; drifting them silently would invalidate
        // the derivation, same discipline as gnss_mode's interval pins.
        let b = duty_window(GnssMode::Balanced).unwrap();
        let e = duty_window(GnssMode::Expedition).unwrap();
        assert_eq!((b.on_s, b.period_s), (15, 60));
        assert_eq!((e.on_s, e.period_s), (15, 120));
    }

    #[test]
    fn window_opens_at_each_period_boundary() {
        let w = duty_window(GnssMode::Balanced).unwrap();
        assert!(w.is_on(0));
        assert!(w.is_on(14));
        assert!(!w.is_on(15));
        assert!(!w.is_on(59));
        assert!(w.is_on(60));
        assert!(w.is_on(60 + 14));
        assert!(!w.is_on(60 + 15));
    }

    #[test]
    fn next_start_is_strictly_after_now() {
        let w = duty_window(GnssMode::Expedition).unwrap();
        // From inside the on-window, from the off stretch, and from the exact
        // boundary, the next start is always the following period boundary.
        assert_eq!(w.next_start_s(0), 120);
        assert_eq!(w.next_start_s(14), 120);
        assert_eq!(w.next_start_s(15), 120);
        assert_eq!(w.next_start_s(119), 120);
        assert_eq!(w.next_start_s(120), 240);
    }

    #[test]
    fn longer_interval_modes_sample_less_and_hold_longer() {
        // The point of tying HR to the mode picker: a mode that trades fix
        // rate for hours must never sample HR more (or hold it shorter) than
        // a higher-fidelity mode.
        for pair in MODES.windows(2) {
            let duty = |m: GnssMode| match duty_window(m) {
                None => (1, 1),
                Some(w) => (w.on_s, w.period_s),
            };
            let (on_a, per_a) = duty(pair[0]);
            let (on_b, per_b) = duty(pair[1]);
            assert!(on_a * per_b > on_b * per_a || per_a == per_b);
            assert!(hold_budget_s(pair[0]) < hold_budget_s(pair[1]));
        }
    }

    #[test]
    fn hold_budgets_are_pinned() {
        assert_eq!(hold_budget_s(GnssMode::Performance), STALE_AFTER_S);
        assert_eq!(hold_budget_s(GnssMode::Balanced), BALANCED_PERIOD_S);
        assert_eq!(hold_budget_s(GnssMode::Expedition), EXPEDITION_PERIOD_S);
    }

    #[test]
    fn shown_bpm_holds_through_one_off_window_then_blanks() {
        // A reading from the tail of an on-window is still shown just before
        // the next window opens (the held zone keeps banking), and blanks one
        // second past the budget if that window produced nothing.
        let mode = GnssMode::Balanced;
        let s = valid(150, 14);
        assert_eq!(shown_bpm(s, 14, mode), Some(150));
        assert_eq!(shown_bpm(s, 60, mode), Some(150));
        assert_eq!(shown_bpm(s, 14 + BALANCED_PERIOD_S, mode), Some(150));
        assert_eq!(shown_bpm(s, 14 + BALANCED_PERIOD_S + 1, mode), None);
    }

    #[test]
    fn shown_bpm_blanks_an_invalid_reading_immediately() {
        // A published-but-invalid reading (detector lost the pulse, off-wrist,
        // saturated) is never held — validity, not recency, comes first.
        let s = Some(HrSample {
            bpm: None,
            at_s: 100,
        });
        for mode in MODES {
            assert_eq!(shown_bpm(s, 100, mode), None);
        }
    }

    #[test]
    fn shown_bpm_with_no_sample_is_none() {
        for mode in MODES {
            assert_eq!(shown_bpm(None, 1000, mode), None);
        }
    }

    #[test]
    fn continuous_mode_blanks_a_wedged_sensor() {
        // Performance previously held the last reading forever if the bus
        // died; now it blanks on the face's ordinary freshness budget.
        let s = valid(150, 100);
        assert_eq!(
            shown_bpm(s, 100 + STALE_AFTER_S, GnssMode::Performance),
            Some(150)
        );
        assert_eq!(
            shown_bpm(s, 100 + STALE_AFTER_S + 1, GnssMode::Performance),
            None
        );
    }

    #[test]
    fn clock_skew_reads_as_fresh_not_ancient() {
        // A sample stamped ahead of the consumer's clock (task raced the
        // second boundary) saturates to age zero rather than wrapping to a
        // huge age and blanking a genuinely fresh reading.
        let s = valid(150, 101);
        assert_eq!(shown_bpm(s, 100, GnssMode::Expedition), Some(150));
    }

    #[test]
    fn on_window_gives_the_detector_convergence_margin() {
        // The hold rule only bridges an off-window if the next window can
        // re-converge within its own on time; keep every window comfortably
        // above the worst-case ~6 s convergence the module docs derive.
        for mode in [GnssMode::Balanced, GnssMode::Expedition] {
            let w = duty_window(mode).unwrap();
            assert!(w.on_s >= 12, "too little time to re-converge");
            assert!(w.on_s < w.period_s, "a window must actually duty-cycle");
        }
    }
}
