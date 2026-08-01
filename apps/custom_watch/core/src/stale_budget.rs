//! The shape two independent staleness budgets on this device share: a window
//! chosen at the 1 Hz baseline, widened by exactly as long as the active GNSS
//! cadence leaves that window unable to refresh.
//!
//! Both budgets judge a value derived from accepted GPS fixes, so neither can
//! be refreshed faster than fixes arrive — 1 s in Performance, 15 s in
//! Balanced, 60 s in Expedition. A budget sized for 1 Hz therefore expires
//! mid-gap in the throttled modes and withholds the value for the rest of every
//! gap, in the mode a multi-day runner picks for battery. [`for_cadence`] adds
//! one whole inter-fix gap, so a value always survives to the next fix that
//! could refresh or retire it, while the baseline window is preserved
//! bit-for-bit at 1 Hz.
//!
//! One gap, not a multiple: one gap is exactly the span during which no update
//! *can* arrive, whereas a second gap of slack would keep serving a value from
//! before a change the runner has already made. Reached independently for the
//! GAP hold (decisions.md § 394) and the TrackBack heading (§ 412) and
//! collapsed here; `face::stale_after_s` computes the same sum for the
//! GPS-signal row behind an additional run-active gate.
//!
//! The helper is deliberately unit-agnostic — [`crate::grade_adjusted_pace`]
//! counts snapshot ticks, [`crate::trackback`] counts seconds — and takes the
//! baseline window as an argument rather than owning it, because **the baseline
//! is a per-budget design choice, not a shared constant.** How long a held pace
//! stays meaningful and how long a bearing does are unrelated questions: a
//! stale pace misreads effort, a stale bearing walks a runner down the wrong
//! leg, and § 406 measured that bearing math is far the more error-sensitive of
//! the two. That the two baselines are both 10 today is a coincidence, and
//! folding them into one constant would silently couple two decisions that must
//! stay free to move apart.

/// A staleness budget for one GNSS fix cadence: `base_at_1hz` plus the units
/// one full inter-fix gap occupies beyond the 1 Hz baseline.
///
/// Saturating in both directions: a zero interval (no cadence configured) can't
/// underflow into a huge budget, and an absurd one can't wrap into a tiny one.
pub const fn for_cadence(base_at_1hz: u32, fix_interval_s: u32) -> u32 {
    base_at_1hz.saturating_add(fix_interval_s.saturating_sub(1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gnss_mode::GnssMode;
    use crate::grade_adjusted_pace::{gap_hold_ticks, GAP_HOLD_WINDOW};
    use crate::trackback::{heading_stale_after_s, HEADING_STALE_S};

    /// The three cadences a runner can actually select, in catalogue order.
    const MODES: [GnssMode; 3] = [
        GnssMode::Performance,
        GnssMode::Balanced,
        GnssMode::Expedition,
    ];

    #[test]
    fn both_ladders_are_the_ones_their_call_sites_shipped() {
        // The full ladders, spelled out rather than derived, so a change to the
        // shared shape or to either baseline fails here as a number.
        let heading: [u32; 3] = MODES.map(|m| heading_stale_after_s(m.fix_interval_s()));
        assert_eq!(heading, [10, 24, 69], "TrackBack heading, seconds");

        let gap_hold: [u32; 3] = MODES.map(|m| gap_hold_ticks(m.fix_interval_s()));
        assert_eq!(
            gap_hold,
            [10, 24, 69],
            "GAP power-hike hold, snapshot ticks"
        );
    }

    #[test]
    fn the_two_baselines_stay_independent() {
        // Equal today, but each is its own design choice: a held pace's useful
        // life and a bearing's are unrelated, so this asserts the *shape* is
        // shared, not the window. Perturbing one baseline must move only its
        // own ladder.
        assert_eq!(
            for_cadence(HEADING_STALE_S, 60),
            heading_stale_after_s(60),
            "the heading budget is this shape over its own baseline"
        );
        assert_eq!(
            for_cadence(GAP_HOLD_WINDOW, 60),
            gap_hold_ticks(60),
            "the GAP hold budget is this shape over its own baseline"
        );
        assert_eq!(for_cadence(HEADING_STALE_S + 5, 60), 74);
        assert_eq!(for_cadence(GAP_HOLD_WINDOW, 60), 69);
    }

    #[test]
    fn the_baseline_survives_the_1hz_cadence_untouched() {
        for base in [0, 1, 10, 1_000] {
            assert_eq!(for_cadence(base, 1), base, "1 Hz adds nothing");
            assert_eq!(for_cadence(base, 0), base, "no cadence adds nothing");
        }
    }

    #[test]
    fn every_budget_spans_its_own_gap_and_grows_with_it() {
        // A value must always survive to the fix that could refresh it, and a
        // slower cadence can never buy a *tighter* budget.
        let mut previous = 0;
        for mode in MODES {
            let interval = mode.fix_interval_s();
            let budget = for_cadence(HEADING_STALE_S, interval);
            assert!(budget >= interval, "{mode:?}: budget spans the gap");
            assert!(budget >= previous, "{mode:?}: monotonic in the interval");
            previous = budget;
        }
    }

    #[test]
    fn absurd_inputs_saturate_rather_than_wrap() {
        assert_eq!(for_cadence(10, u32::MAX), u32::MAX);
        assert_eq!(for_cadence(u32::MAX, u32::MAX), u32::MAX);
        assert_eq!(for_cadence(0, 0), 0);
    }
}
