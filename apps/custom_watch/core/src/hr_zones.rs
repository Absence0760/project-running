//! Heart-rate zones — the five-zone %-of-max ladder the main app uses.
//!
//! Mirrors the product's default zone derivation (web
//! `apps/web/src/lib/training/hr_zones.ts`, canonical, with its Dart and
//! Wear OS twins): zone upper bounds Z1..Z5 at 60/70/80/90/100 % of a max
//! heart rate, rounded half-up like `Math.round`, and the same inclusive
//! boundary rule (`bpm <= cutoffs[0]` is Z1, anything past `cutoffs[3]` is
//! Z5 — even above the configured max). The watch is display-only firmware,
//! so per §24 it mirrors the model rather than inventing one; the runner's
//! explicit `hr_zones` / Tanaka-from-age precedence stays a phone/web
//! concern — tier 1 carries only the max-HR ladder with the same legacy
//! 190 bpm fallback the app defaults to.
//!
//! Pure logic like the rest of `core`: no peripherals, no allocator.

/// Number of zones in the ladder.
pub const ZONE_COUNT: usize = 5;

/// Zone upper bounds Z1..Z5, in BPM. `cutoffs[4]` is the max HR itself.
pub type ZoneCutoffs = [u16; ZONE_COUNT];

/// The legacy fallback max HR when nothing better is configured — the same
/// 190 bpm the app's `defaultZoneCutoffs({})` bottoms out at.
pub const DEFAULT_MAX_HR_BPM: u16 = 190;

/// The plausibility window for a configured max HR, matching the web
/// helper's override validation — values outside it are sensor-bag garbage
/// and must not rebuild the ladder.
pub const MAX_HR_PLAUSIBLE_MIN: u16 = 80;
pub const MAX_HR_PLAUSIBLE_MAX: u16 = 240;

/// Zone upper bounds (Z1..Z5) at 60/70/80/90/100 % of a max HR, rounded
/// half-up — the integer twin of web's `zoneCutoffsFromMaxHr`
/// (`Math.round(maxHr * p)` for positive inputs).
pub const fn zone_cutoffs_from_max_hr(max_hr_bpm: u16) -> ZoneCutoffs {
    const fn pct(max_hr_bpm: u16, p: u32) -> u16 {
        ((max_hr_bpm as u32 * p + 50) / 100) as u16
    }
    [
        pct(max_hr_bpm, 60),
        pct(max_hr_bpm, 70),
        pct(max_hr_bpm, 80),
        pct(max_hr_bpm, 90),
        pct(max_hr_bpm, 100),
    ]
}

/// The 1-based zone (1..=5) a BPM falls in. Cutoffs are inclusive upper
/// bounds, mirroring web's `zoneIndex`: `bpm <= cutoffs[0]` is Z1, and
/// anything above `cutoffs[3]` — including past the max itself — is Z5.
pub fn zone_for_bpm(bpm: u16, cutoffs: &ZoneCutoffs) -> u8 {
    if bpm <= cutoffs[0] {
        1
    } else if bpm <= cutoffs[1] {
        2
    } else if bpm <= cutoffs[2] {
        3
    } else if bpm <= cutoffs[3] {
        4
    } else {
        5
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cutoffs_match_the_web_ladder() {
        // The two fixtures web's zoneCutoffsFromMaxHr test pins.
        assert_eq!(
            zone_cutoffs_from_max_hr(190),
            [114, 133, 152, 171, 190],
            "the legacy 190 ladder"
        );
        assert_eq!(zone_cutoffs_from_max_hr(200), [120, 140, 160, 180, 200]);
    }

    #[test]
    fn cutoffs_round_half_up_like_math_round() {
        // 185 * 0.7 = 129.5 -> Math.round gives 130, not 129.
        assert_eq!(zone_cutoffs_from_max_hr(185)[1], 130);
        // 183 * 0.9 = 164.7 -> 165.
        assert_eq!(zone_cutoffs_from_max_hr(183)[3], 165);
    }

    #[test]
    fn default_is_the_legacy_190_ladder() {
        assert_eq!(
            zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
            [114, 133, 152, 171, 190]
        );
    }

    #[test]
    fn zone_boundaries_are_inclusive_upper_bounds() {
        let c = zone_cutoffs_from_max_hr(190);
        // Each cutoff belongs to its own zone; one BPM past it is the next.
        assert_eq!(zone_for_bpm(114, &c), 1);
        assert_eq!(zone_for_bpm(115, &c), 2);
        assert_eq!(zone_for_bpm(133, &c), 2);
        assert_eq!(zone_for_bpm(134, &c), 3);
        assert_eq!(zone_for_bpm(152, &c), 3);
        assert_eq!(zone_for_bpm(153, &c), 4);
        assert_eq!(zone_for_bpm(171, &c), 4);
        assert_eq!(zone_for_bpm(172, &c), 5);
    }

    #[test]
    fn zone_extremes_clamp_into_the_ladder() {
        let c = zone_cutoffs_from_max_hr(190);
        assert_eq!(zone_for_bpm(0, &c), 1, "a rest-low BPM is still Z1");
        assert_eq!(zone_for_bpm(190, &c), 5, "the max itself is Z5");
        assert_eq!(zone_for_bpm(240, &c), 5, "above max stays Z5, never panics");
    }
}
