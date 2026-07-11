//! Gauge fractions — reduce run-view metrics to normalised bar fills the face
//! draws as visual gauges. Pure math: every function turns a domain struct into
//! an `f32` (or an array of them) in a documented range and does no drawing, so
//! the same numbers feed the MIP face, a future colour panel, or a host-side
//! preview unchanged.
//!
//! Every ratio is division-guarded — a zero or non-finite denominator yields the
//! low end of the range, never a `NaN`/`inf` that would poison a bar width — and
//! `f32::clamp`ed to that range (the comparison-based clamp is in `core`, so it
//! links in this `no_std` crate; only the transcendental float ops need `libm`).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use crate::gear_wear::{GearWear, GearWearStatus};
use crate::hr_zones::{zone_for_bpm, ZoneCutoffs};
use crate::pacer::PacerStatus;
use crate::record::FuelView;

/// Full-scale window for the centre-out pacer bar: a ±120 s (two-minute) lead
/// or deficit fills the bar to its end. Two minutes is a meaningful gap over an
/// ultra's hours, without pinning the needle on every small surge.
pub const PACER_FULL_SCALE_S: i32 = 120;

/// Signed fill for the centre-out virtual-partner bar, in `-1.0..=1.0`: positive
/// = ahead of the partner, negative = behind, normalised over
/// ±[`PACER_FULL_SCALE_S`] and clamped. Reads the pacer's own signed `ahead_s`
/// (lead positive, deficit negative), so a runner ahead of the partner fills the
/// bar towards the positive end.
pub fn pacer_fill(status: &PacerStatus) -> f32 {
    (status.ahead_s as f32 / PACER_FULL_SCALE_S as f32).clamp(-1.0, 1.0)
}

/// Fill for the gear-wear bar, in `0.0..=1.0`: accumulated distance over the
/// replacement target, capped at 1.0 once at/over target. [`GearWear::fraction`]
/// is uncapped (a 120%-worn shoe reads 1.2 there); the bar caps it. Untracked
/// gear (no target, `fraction == None`) reads 0.0.
pub fn gear_fill(gear: &GearWear) -> f32 {
    match gear.fraction {
        Some(f) if f.is_finite() => clamp01(f as f32),
        _ => 0.0,
    }
}

/// Whether the gear is at/over its replacement target — a bool projection of the
/// existing [`GearWearStatus::Worn`] verdict, so the bar can switch to its
/// overdue colour without matching the enum itself.
pub fn gear_overdue(gear: &GearWear) -> bool {
    gear.status == GearWearStatus::Worn
}

/// Fill for the fuel bar, in `0.0..=1.0`. [`FuelView`] carries what to carry out
/// to the next aid plus the whole-plan totals — not a carried-vs-needed split —
/// so the most honest single ratio it supports is the carry-to-next-aid
/// carbohydrate as a share of the whole plan's carbohydrate: the visual weight
/// of the current leg's fuel load against the race. A `None` carry (past the
/// final aid) or a zero / non-finite plan total reads 0.0.
pub fn fuel_fill(fuel: &FuelView) -> f32 {
    let Some(carry) = fuel.carry else { return 0.0 };
    if !fuel.total_carbs_g.is_finite() || fuel.total_carbs_g <= 0.0 || !carry.carbs_g.is_finite() {
        return 0.0;
    }
    clamp01(carry.carbs_g / fuel.total_carbs_g)
}

/// 0-based index of the live zone (`0..ZONE_COUNT`) for a BPM, delegating to the
/// [`zone_for_bpm`] ladder lookup rather than re-deriving thresholds. That helper
/// returns the 1-based zone, so this shifts it down by one.
pub fn current_zone(bpm: u16, cutoffs: &ZoneCutoffs) -> usize {
    (zone_for_bpm(bpm, cutoffs) - 1) as usize
}

fn clamp01(v: f32) -> f32 {
    v.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gear_wear::gear_wear;
    use crate::hr_zones::zone_cutoffs_from_max_hr;
    use crate::pacer::{PaceVerdict, PacerGoal};
    use crate::record::FuelCarryView;

    fn pacer(ahead_s: i32) -> PacerStatus {
        PacerStatus {
            goal: PacerGoal {
                distance_m: 10_000,
                time_s: 3_000,
            },
            ahead_m: 0.0,
            ahead_s,
            projected_finish_s: None,
            verdict: PaceVerdict::OnPace,
            finished: false,
        }
    }

    #[test]
    fn pacer_ahead_is_positive_behind_is_negative() {
        // The ultra runner a minute up on the partner fills the bar positive.
        let ahead = pacer_fill(&pacer(60));
        assert!(ahead > 0.0, "ahead of the partner must read positive");
        assert!((ahead - 0.5).abs() < 1e-6, "60 s over the 120 s scale is +0.5");
        // A minute down mirrors it.
        let behind = pacer_fill(&pacer(-60));
        assert!(behind < 0.0, "behind the partner must read negative");
        assert!((behind + 0.5).abs() < 1e-6);
    }

    #[test]
    fn pacer_clamps_at_and_beyond_full_scale() {
        assert_eq!(pacer_fill(&pacer(PACER_FULL_SCALE_S)), 1.0);
        assert_eq!(pacer_fill(&pacer(PACER_FULL_SCALE_S * 3)), 1.0);
        assert_eq!(pacer_fill(&pacer(-PACER_FULL_SCALE_S)), -1.0);
        assert_eq!(pacer_fill(&pacer(-PACER_FULL_SCALE_S * 4)), -1.0);
    }

    #[test]
    fn pacer_zero_delta_is_centred() {
        assert_eq!(pacer_fill(&pacer(0)), 0.0);
    }

    #[test]
    fn gear_half_worn_is_half_full() {
        let g = gear_wear(Some(400_000.0), Some(800_000.0));
        assert!((gear_fill(&g) - 0.5).abs() < 1e-6);
        assert!(!gear_overdue(&g));
    }

    #[test]
    fn gear_at_target_is_full_and_overdue() {
        let g = gear_wear(Some(800_000.0), Some(800_000.0));
        assert_eq!(gear_fill(&g), 1.0);
        assert!(gear_overdue(&g));
    }

    #[test]
    fn gear_over_target_clamps_to_full() {
        let g = gear_wear(Some(960_000.0), Some(800_000.0)); // 1.2 uncapped
        assert_eq!(gear_fill(&g), 1.0);
        assert!(gear_overdue(&g));
    }

    #[test]
    fn gear_untracked_reads_empty_and_not_overdue() {
        let g = gear_wear(Some(500_000.0), None);
        assert_eq!(gear_fill(&g), 0.0);
        assert!(!gear_overdue(&g));
    }

    #[test]
    fn gear_overdue_boundary_flips_at_target() {
        // Just short of target: worn-in but not overdue.
        assert!(!gear_overdue(&gear_wear(Some(799_999.0), Some(800_000.0))));
        // At target: overdue.
        assert!(gear_overdue(&gear_wear(Some(800_000.0), Some(800_000.0))));
    }

    fn fuel(carry_carbs: Option<f32>, total_carbs: f32) -> FuelView {
        FuelView {
            carry: carry_carbs.map(|c| FuelCarryView {
                carbs_g: c,
                fluid_ml: 0.0,
            }),
            total_carbs_g: total_carbs,
            total_fluid_ml: 0.0,
        }
    }

    #[test]
    fn fuel_full_carry_leg_reads_full() {
        // A single-leg plan where the whole race's carbs are the next carry-out.
        assert_eq!(fuel_fill(&fuel(Some(120.0), 120.0)), 1.0);
    }

    #[test]
    fn fuel_partial_carry_leg_reads_partial() {
        assert!((fuel_fill(&fuel(Some(60.0), 120.0)) - 0.5).abs() < 1e-6);
    }

    #[test]
    fn fuel_degenerate_inputs_read_empty_not_nan() {
        // Zero plan total: guarded, no divide-by-zero NaN.
        let f = fuel_fill(&fuel(Some(60.0), 0.0));
        assert_eq!(f, 0.0);
        assert!(!f.is_nan());
        // No carry (past the final aid): empty.
        assert_eq!(fuel_fill(&fuel(None, 120.0)), 0.0);
    }

    #[test]
    fn current_zone_maps_bpm_to_zero_based_index() {
        let c = zone_cutoffs_from_max_hr(190); // [114, 133, 152, 171, 190]
        assert_eq!(current_zone(100, &c), 0, "rest-low BPM is Z1 -> index 0");
        assert_eq!(current_zone(115, &c), 1, "just over Z1 is Z2 -> index 1");
        assert_eq!(current_zone(160, &c), 3, "index 3 is Z4");
        assert_eq!(current_zone(200, &c), 4, "above max stays Z5 -> index 4");
    }
}
