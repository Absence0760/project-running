//! Race fueling plan — a per-leg carbs/hr + fluid plan synced to the roadbook's
//! aid-station timeline.
//!
//! [`build_fuel_plan`] takes the roadbook's per-leg schedule and scales a
//! carbs + fluid target onto each leg by its **duration** (carbs/hr ×
//! leg-hours, fluid/hr × heat × leg-hours). On the start line and on each
//! refill checkpoint (one carrying water or food) it also emits
//! [`FuelLeg::carry_to_next_aid`] — the fuel to carry out to reach the next
//! refill (inclusive of the leg arriving there), so a runner knows "carry 3
//! gels + 500 ml out of Aid 1". Optionally estimates per-leg energy burn when a
//! bodyweight is supplied.
//!
//! Parity port of web `routes/fuel_plan.ts` `buildFuelPlan` + `carryToNextAid`
//! (twin of `apps/mobile_android/lib/fuel_plan.dart`) — keep the scaling, carry
//! rules, edge cases, and test count in lockstep. It consumes the
//! [`crate::roadbook`] output: [`FuelLegInput::from_leg`] maps a `RoadbookLeg`
//! into an input row, and the parallel `legs` array is sized to
//! [`MAX_ROADBOOK_LEGS`]. The per-leg kcal reuses the web
//! `exercise_calories.ts` `runCalories` cost (not ported as its own module
//! here — inlined as [`KCAL_PER_KG_PER_KM`]).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::roadbook::{RoadbookLeg, MAX_ROADBOOK_LEGS};

/// Conservative default carbohydrate intake rate, grams per hour.
pub const DEFAULT_CARBS_PER_HOUR_G: f64 = 60.0;
/// Conservative default fluid intake rate, millilitres per hour.
pub const DEFAULT_FLUID_PER_HOUR_ML: f64 = 500.0;
/// Heat toggle multiplier on fluid (not carbs).
pub const HEAT_FLUID_FACTOR: f64 = 1.5;
/// Carbs per gel, for the carry-out gel count.
pub const GEL_CARBS_G: f64 = 25.0;

/// Gross running energy cost, kcal per kg of bodyweight per km — the web
/// `exercise_calories.ts` `KCAL_PER_KG_PER_KM`.
const KCAL_PER_KG_PER_KM: f64 = 1.036;

/// Minimal per-leg input. Map each roadbook `RoadbookLeg` through
/// [`FuelLegInput::from_leg`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelLegInput<'a> {
    pub projected_elapsed_s: f64,
    pub leg_dist_m: f64,
    pub services: &'a [&'a str],
}

impl<'a> FuelLegInput<'a> {
    pub fn from_leg(leg: &RoadbookLeg<'a>) -> Self {
        Self {
            projected_elapsed_s: leg.projected_elapsed_s,
            leg_dist_m: leg.leg_dist_m,
            services: leg.services,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelPlanOptions {
    pub carbs_per_hour_g: f64,
    pub fluid_per_hour_ml: f64,
    /// Multiplier on fluid for hot conditions. `None` → 1 (no bump).
    pub heat_factor: Option<f64>,
    /// Carbs per gel for the carry-out gel count. `None` → [`GEL_CARBS_G`].
    pub gel_carbs_g: Option<f64>,
    /// Bodyweight in kg; when set, each leg gets an estimated kcal burn.
    pub weight_kg: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelCarry {
    pub carbs_g: f64,
    pub fluid_ml: f64,
    pub gels: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FuelLeg {
    pub carbs_g: f64,
    pub fluid_ml: f64,
    /// Estimated energy burn for the leg (0 when no bodyweight supplied).
    pub kcal: f64,
    /// Present on the start + each refill checkpoint — what to carry out.
    pub carry_to_next_aid: Option<FuelCarry>,
}

pub struct FuelPlan {
    pub legs: Vec<FuelLeg, MAX_ROADBOOK_LEGS>,
    pub total_carbs_g: f64,
    pub total_fluid_ml: f64,
}

/// A leg is a refill point when its aid services carry water or food.
fn is_refill(leg: &FuelLegInput) -> bool {
    leg.services.iter().any(|&s| s == "water" || s == "food")
}

/// Calories burned running one leg. 0 when distance or bodyweight is missing /
/// non-physical — the web `exercise_calories.ts` `runCalories`.
fn run_calories(distance_m: f64, weight_kg: Option<f64>) -> f64 {
    let Some(w) = weight_kg else { return 0.0 };
    if w <= 0.0 || distance_m <= 0.0 {
        return 0.0;
    }
    KCAL_PER_KG_PER_KM * w * (distance_m / 1000.0)
}

/// Build the fueling plan. The returned `legs` array is parallel to the input
/// (and to the roadbook's legs), so the surface can render fuel alongside each
/// checkpoint row.
pub fn build_fuel_plan(legs: &[FuelLegInput], opts: FuelPlanOptions) -> FuelPlan {
    let carbs_per_hour = opts.carbs_per_hour_g.max(0.0);
    let fluid_per_hour = opts.fluid_per_hour_ml.max(0.0);
    let heat = match opts.heat_factor {
        Some(h) if h > 0.0 => h,
        _ => 1.0,
    };
    let per_gel = match opts.gel_carbs_g {
        Some(g) if g > 0.0 => g,
        _ => GEL_CARBS_G,
    };
    let weight = opts.weight_kg;

    let mut out: Vec<FuelLeg, MAX_ROADBOOK_LEGS> = Vec::new();
    let mut prev_elapsed = 0.0;
    let mut total_carbs_g = 0.0;
    let mut total_fluid_ml = 0.0;
    for leg in legs.iter().take(MAX_ROADBOOK_LEGS) {
        let dur_s = (leg.projected_elapsed_s - prev_elapsed).max(0.0);
        let h = dur_s / 3600.0;
        let carbs_g = carbs_per_hour * h;
        let fluid_ml = fluid_per_hour * heat * h;
        let _ = out.push(FuelLeg {
            carbs_g,
            fluid_ml,
            kcal: run_calories(leg.leg_dist_m, weight),
            carry_to_next_aid: None,
        });
        total_carbs_g += carbs_g;
        total_fluid_ml += fluid_ml;
        prev_elapsed = leg.projected_elapsed_s;
    }

    // Carry-out at the start (index 0) and at each refill checkpoint: sum the
    // fuel of every leg until the next refill, inclusive of the leg arriving
    // there (you consume it before you can refill).
    let n = out.len();
    for i in 0..n {
        if i != 0 && !is_refill(&legs[i]) {
            continue;
        }
        let mut carbs_g = 0.0;
        let mut fluid_ml = 0.0;
        for j in (i + 1)..n {
            carbs_g += out[j].carbs_g;
            fluid_ml += out[j].fluid_ml;
            if is_refill(&legs[j]) {
                break;
            }
        }
        out[i].carry_to_next_aid = Some(FuelCarry {
            carbs_g,
            fluid_ml,
            gels: if carbs_g > 0.0 {
                libm::ceil(carbs_g / per_gel) as u32
            } else {
                0
            },
        });
    }

    FuelPlan {
        legs: out,
        total_carbs_g,
        total_fluid_ml,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/routes/fuel_plan.test.ts` /
    /// `apps/mobile_android/test/fuel_plan_test.dart` — same scenarios, same
    /// expected values, so the ports can't drift.

    const WATER_FOOD: [&str; 2] = ["water", "food"];

    /// start → aid (1h, refill) → cutoff (0.5h, no services) → finish (0.5h).
    fn legs() -> [FuelLegInput<'static>; 4] {
        [
            FuelLegInput {
                projected_elapsed_s: 0.0,
                leg_dist_m: 0.0,
                services: &[],
            },
            FuelLegInput {
                projected_elapsed_s: 3600.0,
                leg_dist_m: 8000.0,
                services: &WATER_FOOD,
            },
            FuelLegInput {
                projected_elapsed_s: 5400.0,
                leg_dist_m: 4000.0,
                services: &[],
            },
            FuelLegInput {
                projected_elapsed_s: 7200.0,
                leg_dist_m: 4000.0,
                services: &[],
            },
        ]
    }

    fn opts() -> FuelPlanOptions {
        FuelPlanOptions {
            carbs_per_hour_g: 60.0,
            fluid_per_hour_ml: 500.0,
            heat_factor: None,
            gel_carbs_g: None,
            weight_kg: None,
        }
    }

    #[test]
    fn carbs_plus_fluid_scale_with_each_leg_duration() {
        let plan = build_fuel_plan(&legs(), opts());
        assert_eq!(plan.legs[1].carbs_g, 60.0);
        assert_eq!(plan.legs[1].fluid_ml, 500.0);
        assert_eq!(plan.legs[2].carbs_g, 30.0);
        assert_eq!(plan.legs[2].fluid_ml, 250.0);
        assert_eq!(plan.legs[3].carbs_g, 30.0);
    }

    #[test]
    fn zero_duration_leg_start_gets_zero_carbs_plus_fluid() {
        let plan = build_fuel_plan(&legs(), opts());
        assert_eq!(plan.legs[0].carbs_g, 0.0);
        assert_eq!(plan.legs[0].fluid_ml, 0.0);
    }

    #[test]
    fn heat_factor_bumps_fluid_but_not_carbs() {
        let base = build_fuel_plan(&legs(), opts());
        let hot = build_fuel_plan(
            &legs(),
            FuelPlanOptions {
                heat_factor: Some(HEAT_FLUID_FACTOR),
                ..opts()
            },
        );
        assert_eq!(hot.legs[1].carbs_g, base.legs[1].carbs_g);
        assert_eq!(
            hot.legs[1].fluid_ml,
            base.legs[1].fluid_ml * HEAT_FLUID_FACTOR
        );
    }

    #[test]
    fn carry_to_next_aid_sums_legs_up_to_and_including_the_next_refill() {
        let plan = build_fuel_plan(&legs(), opts());
        // Out of the start: only the leg arriving at the aid (the next refill).
        assert_eq!(
            plan.legs[0].carry_to_next_aid,
            Some(FuelCarry {
                carbs_g: 60.0,
                fluid_ml: 500.0,
                gels: 3
            })
        );
        // Out of the aid: cutoff + finish legs (no further refill) → to the end.
        assert_eq!(
            plan.legs[1].carry_to_next_aid,
            Some(FuelCarry {
                carbs_g: 60.0,
                fluid_ml: 500.0,
                gels: 3
            })
        );
    }

    #[test]
    fn carry_is_present_only_on_the_start_plus_refill_checkpoints() {
        let plan = build_fuel_plan(&legs(), opts());
        assert!(plan.legs[0].carry_to_next_aid.is_some()); // start
        assert!(plan.legs[1].carry_to_next_aid.is_some()); // aid (refill)
        assert_eq!(plan.legs[2].carry_to_next_aid, None); // cutoff, no services
        assert_eq!(plan.legs[3].carry_to_next_aid, None); // finish
    }

    #[test]
    fn gel_count_is_ceil_carbs_over_gel_carbs_g() {
        // 70 g/hr over the 1h leg out of the start → 70 g → ceil(70/25) = 3.
        let plan = build_fuel_plan(
            &legs(),
            FuelPlanOptions {
                carbs_per_hour_g: 70.0,
                fluid_per_hour_ml: 500.0,
                heat_factor: None,
                gel_carbs_g: None,
                weight_kg: None,
            },
        );
        let carry = plan.legs[0].carry_to_next_aid.expect("carry present");
        assert_eq!(carry.carbs_g, 70.0);
        assert_eq!(carry.gels, libm::ceil(70.0 / GEL_CARBS_G) as u32);
    }

    #[test]
    fn totals_equal_the_sum_of_the_legs() {
        let plan = build_fuel_plan(&legs(), opts());
        let sum_carbs: f64 = plan.legs.iter().map(|l| l.carbs_g).sum();
        let sum_fluid: f64 = plan.legs.iter().map(|l| l.fluid_ml).sum();
        assert_eq!(plan.total_carbs_g, sum_carbs);
        assert_eq!(plan.total_fluid_ml, sum_fluid);
        assert_eq!(plan.total_carbs_g, 120.0);
        assert_eq!(plan.total_fluid_ml, 1000.0);
    }

    #[test]
    fn kcal_is_estimated_only_when_a_bodyweight_is_supplied() {
        let without = build_fuel_plan(&legs(), opts());
        assert_eq!(without.legs[1].kcal, 0.0);
        let with_weight = build_fuel_plan(
            &legs(),
            FuelPlanOptions {
                weight_kg: Some(70.0),
                ..opts()
            },
        );
        // 1.036 kcal/kg/km × 70 kg × 8 km = 580.16
        assert!((with_weight.legs[1].kcal - 580.16).abs() < 0.01);
    }

    #[test]
    fn non_positive_intake_rates_clamp_to_zero() {
        let plan = build_fuel_plan(
            &legs(),
            FuelPlanOptions {
                carbs_per_hour_g: -10.0,
                fluid_per_hour_ml: -5.0,
                heat_factor: None,
                gel_carbs_g: None,
                weight_kg: None,
            },
        );
        assert_eq!(plan.total_carbs_g, 0.0);
        assert_eq!(plan.total_fluid_ml, 0.0);
    }
}
