//! Nutrition targets — daily calorie + macro goals from body metrics.
//!
//! A parity port of web `nutrition/nutrition_targets.ts` (twin of
//! `nutrition_targets.dart`). Keep the algorithm, constants, edge cases, and
//! test count in lockstep with those.
//!
//! The numbers are well-known sports-nutrition heuristics, not proprietary
//! research, and are deliberately conservative — a default the user can
//! override, not a prescription:
//!
//! - **BMR (Mifflin-St Jeor):** `10·kg + 6.25·cm − 5·age + sexOffset`, where the
//!   sex offset is +5 (male) / −161 (female) / −78 (the average, for
//!   non-binary / withheld / unknown) so a target still computes without
//!   forcing a binary answer.
//! - **Base TDEE:** BMR × a baseline (non-exercise) activity factor plus a goal
//!   delta (−500 lose / 0 maintain / +300 gain kcal).
//! - **Dynamic TDEE:** measured workout calories add ON TOP of the base — the
//!   "base + exercise" model. `calories` is the eat-to goal, `base_calories`
//!   the non-exercise floor, `exercise_kcal` the day's add-on.
//! - **Macros:** protein at 1.8 g/kg bodyweight, fat at 30% of calories,
//!   carbohydrate filling the remainder (floored at 0).
//!
//! [`compute_nutrition_targets`] returns `None` when any required metric is
//! missing or non-physical, so the caller hides the rings rather than render a
//! zeroed/garbage target. Pure logic, no peripherals, no allocator.

/// The five baseline (non-exercise) activity levels, in Settings display order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ActivityLevel {
    Sedentary,
    Light,
    Moderate,
    Active,
    VeryActive,
}

/// The user's weight goal — a −500 / 0 / +300 kcal daily delta.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WeightGoal {
    Lose,
    Maintain,
    Gain,
}

/// One row of [`ACTIVITY_LEVELS`]: the key, its Settings label, and the BMR
/// multiplier.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ActivityLevelOption {
    pub key: ActivityLevel,
    pub label: &'static str,
    pub factor: f64,
}

/// Baseline (non-exercise) activity multipliers applied to BMR. Order is the
/// display order in Settings (least → most active). Labels describe daily
/// lifestyle EXCLUDING logged workouts — those are added separately as
/// `exercise_kcal`.
pub const ACTIVITY_LEVELS: [ActivityLevelOption; 5] = [
    ActivityLevelOption {
        key: ActivityLevel::Sedentary,
        label: "Mostly sitting (desk job)",
        factor: 1.2,
    },
    ActivityLevelOption {
        key: ActivityLevel::Light,
        label: "Lightly active (light daily movement)",
        factor: 1.375,
    },
    ActivityLevelOption {
        key: ActivityLevel::Moderate,
        label: "Moderately active (on your feet often)",
        factor: 1.55,
    },
    ActivityLevelOption {
        key: ActivityLevel::Active,
        label: "Very active day (physical job)",
        factor: 1.725,
    },
    ActivityLevelOption {
        key: ActivityLevel::VeryActive,
        label: "Extremely active (hard physical labour)",
        factor: 1.9,
    },
];

/// Grams of protein per kg of bodyweight (endurance-athlete default).
pub const PROTEIN_G_PER_KG: f64 = 1.8;
/// Share of total calories from fat.
pub const FAT_KCAL_FRACTION: f64 = 0.3;
/// Lowest calorie target we will ever recommend — a safety floor.
pub const MIN_CALORIE_TARGET: f64 = 1200.0;

const KCAL_PER_G_PROTEIN: f64 = 4.0;
const KCAL_PER_G_CARB: f64 = 4.0;
const KCAL_PER_G_FAT: f64 = 9.0;

/// Daily calorie delta applied after TDEE for the user's weight goal. The
/// closed enum makes a stale/typo'd goal unrepresentable, so unlike web (a raw
/// jsonb string coalesced with `?? 0`) there is no NaN path to guard.
pub const fn goal_kcal_delta(goal: WeightGoal) -> f64 {
    match goal {
        WeightGoal::Lose => -500.0,
        WeightGoal::Maintain => 0.0,
        WeightGoal::Gain => 300.0,
    }
}

/// Daily calorie + macro targets.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct NutritionTargets {
    /// Final daily eat-to goal = `base_calories + exercise_kcal`.
    pub calories: f64,
    /// Non-exercise goal (BMR × baseline factor + goal delta), floored.
    pub base_calories: f64,
    /// Measured workout calories added on top for the day (0 when none).
    pub exercise_kcal: f64,
    pub protein_g: f64,
    pub carbs_g: f64,
    pub fat_g: f64,
}

/// Body metrics + goal + optional day's exercise burn feeding
/// [`compute_nutrition_targets`]. `sex` is a raw string (as stored) so any
/// value other than `"male"` / `"female"` folds to the neutral offset.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BodyMetricsInput<'a> {
    pub weight_kg: Option<f64>,
    pub height_cm: Option<f64>,
    pub age_years: Option<f64>,
    pub sex: Option<&'a str>,
    pub activity_level: ActivityLevel,
    pub goal: WeightGoal,
    /// Calories burned by today's logged workouts, added on top of the base
    /// (dynamic TDEE). `None` yields the static base goal.
    pub exercise_kcal: Option<f64>,
}

fn sex_offset(sex: Option<&str>) -> f64 {
    match sex {
        Some("male") => 5.0,
        Some("female") => -161.0,
        _ => -78.0,
    }
}

fn factor_for(level: ActivityLevel) -> f64 {
    ACTIVITY_LEVELS
        .iter()
        .find(|a| a.key == level)
        .map_or(1.55, |a| a.factor)
}

/// Mifflin-St Jeor resting metabolic rate (kcal/day).
pub fn mifflin_st_jeor_bmr(
    weight_kg: f64,
    height_cm: f64,
    age_years: f64,
    sex: Option<&str>,
) -> f64 {
    10.0 * weight_kg + 6.25 * height_cm - 5.0 * age_years + sex_offset(sex)
}

/// Parse an ISO date component the way JS `Number()` + a truthiness check does:
/// a non-numeric string or a zero value is rejected (mirrors web's `!by`).
fn parse_component(s: &str) -> Option<i64> {
    match s.parse::<i64>() {
        Ok(0) | Err(_) => None,
        Ok(v) => Some(v),
    }
}

/// Civil date (year, month, day) from a day count since the Unix epoch, via
/// Howard Hinnant's `civil_from_days`. Pure integer math, matches
/// `Date.getUTC*` for the epoch-day granularity we need.
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Whole-year age from an ISO `YYYY-MM-DD` date of birth, evaluated at
/// `now_ms` (UTC epoch milliseconds). `None` on a missing / malformed date or
/// an out-of-range result. Parsed by calendar components (no timezone
/// dependence) so the TS/Dart twins match exactly.
pub fn age_from_dob(dob_iso: Option<&str>, now_ms: f64) -> Option<i32> {
    let dob = dob_iso?;
    if dob.is_empty() {
        return None;
    }
    let end = dob.char_indices().nth(10).map_or(dob.len(), |(i, _)| i);
    let mut parts = dob[..end].split('-');
    let by = parse_component(parts.next()?)?;
    let bm = parse_component(parts.next()?)?;
    let bd = parse_component(parts.next()?)?;

    let days = libm::floor(now_ms / 86_400_000.0) as i64;
    let (ny, nm, nd) = civil_from_days(days);
    let mut age = ny - by;
    if nm < bm || (nm == bm && nd < bd) {
        age -= 1;
    }
    if !(0..=120).contains(&age) {
        return None;
    }
    Some(age as i32)
}

/// Daily calorie + macro targets, or `None` when a required metric is missing
/// or non-physical (so the caller can hide the surface).
pub fn compute_nutrition_targets(input: BodyMetricsInput) -> Option<NutritionTargets> {
    let weight_kg = input.weight_kg?;
    let height_cm = input.height_cm?;
    let age_years = input.age_years?;
    if weight_kg <= 0.0 || height_cm <= 0.0 || age_years <= 0.0 {
        return None;
    }
    if weight_kg > 500.0 || height_cm > 300.0 || age_years > 120.0 {
        return None;
    }

    let bmr = mifflin_st_jeor_bmr(weight_kg, height_cm, age_years, input.sex);
    let base_tdee = bmr * factor_for(input.activity_level) + goal_kcal_delta(input.goal);
    let base_calories = MIN_CALORIE_TARGET.max(libm::round(base_tdee / 10.0) * 10.0);
    let exercise_kcal = 0.0_f64.max(libm::round(input.exercise_kcal.unwrap_or(0.0)));
    let calories = base_calories + exercise_kcal;

    let protein_g = libm::round(PROTEIN_G_PER_KG * weight_kg);
    let fat_g = libm::round(FAT_KCAL_FRACTION * calories / KCAL_PER_G_FAT);
    let carbs_kcal =
        0.0_f64.max(calories - protein_g * KCAL_PER_G_PROTEIN - fat_g * KCAL_PER_G_FAT);
    let carbs_g = libm::round(carbs_kcal / KCAL_PER_G_CARB);

    Some(NutritionTargets {
        calories,
        base_calories,
        exercise_kcal,
        protein_g,
        carbs_g,
        fat_g,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> BodyMetricsInput<'static> {
        BodyMetricsInput {
            weight_kg: Some(70.0),
            height_cm: Some(178.0),
            age_years: Some(35.0),
            sex: Some("male"),
            activity_level: ActivityLevel::Moderate,
            goal: WeightGoal::Maintain,
            exercise_kcal: None,
        }
    }

    /// Days since the Unix epoch for a civil date (Hinnant `days_from_civil`),
    /// the inverse of [`civil_from_days`]; used to build `Date.UTC`-equivalent
    /// timestamps in the age tests.
    fn utc_ms(y: i64, m: i64, d: i64) -> f64 {
        let y2 = if m <= 2 { y - 1 } else { y };
        let era = if y2 >= 0 { y2 } else { y2 - 399 } / 400;
        let yoe = y2 - era * 400;
        let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        let days = era * 146_097 + doe - 719_468;
        days as f64 * 86_400_000.0
    }

    #[test]
    fn bmr_male_offset_is_plus_5() {
        // 10*70 + 6.25*178 - 5*35 + 5 = 1642.5
        assert_eq!(mifflin_st_jeor_bmr(70.0, 178.0, 35.0, Some("male")), 1642.5);
    }

    #[test]
    fn bmr_female_offset_is_minus_161() {
        assert_eq!(
            mifflin_st_jeor_bmr(70.0, 178.0, 35.0, Some("female")),
            1642.5 - 5.0 - 161.0
        );
    }

    #[test]
    fn bmr_neutral_offset_for_nonbinary_withheld_unknown() {
        let neutral = 10.0 * 70.0 + 6.25 * 178.0 - 5.0 * 35.0 - 78.0;
        assert_eq!(
            mifflin_st_jeor_bmr(70.0, 178.0, 35.0, Some("nonbinary")),
            neutral
        );
        assert_eq!(
            mifflin_st_jeor_bmr(70.0, 178.0, 35.0, Some("prefer_not_to_say")),
            neutral
        );
        assert_eq!(mifflin_st_jeor_bmr(70.0, 178.0, 35.0, None), neutral);
    }

    #[test]
    fn applies_the_moderate_activity_factor() {
        // 1642.5 * 1.55 = 2545.875 → round/10 = 2550
        let t = compute_nutrition_targets(base()).unwrap();
        assert_eq!(t.calories, 2550.0);
    }

    #[test]
    fn protein_is_1_8_g_per_kg_fat_is_30_percent_of_kcal() {
        let t = compute_nutrition_targets(base()).unwrap();
        assert_eq!(t.protein_g, libm::round(1.8 * 70.0)); // 126
        assert_eq!(t.fat_g, libm::round(0.3 * 2550.0 / 9.0)); // 85
    }

    #[test]
    fn carbs_fill_the_remaining_calorie_budget() {
        let t = compute_nutrition_targets(base()).unwrap();
        let remaining = 2550.0 - t.protein_g * 4.0 - t.fat_g * 9.0;
        assert_eq!(t.carbs_g, libm::round(remaining / 4.0));
    }

    #[test]
    fn goal_delta_lowers_and_raises_calories() {
        let lose = compute_nutrition_targets(BodyMetricsInput {
            goal: WeightGoal::Lose,
            ..base()
        })
        .unwrap();
        let gain = compute_nutrition_targets(BodyMetricsInput {
            goal: WeightGoal::Gain,
            ..base()
        })
        .unwrap();
        assert_eq!(lose.calories, 2550.0 + goal_kcal_delta(WeightGoal::Lose));
        assert_eq!(gain.calories, 2550.0 + goal_kcal_delta(WeightGoal::Gain));
    }

    #[test]
    fn an_unknown_goal_is_unrepresentable_maintain_is_the_zero_delta() {
        // Web coalesces a stale/typo'd goal string to a 0 kcal delta (`?? 0`) so
        // it can't produce NaN macros. Here `WeightGoal` is a closed enum, so an
        // invalid goal is unrepresentable by construction; `Maintain` is the
        // 0-delta case the web fallback lands on.
        assert_eq!(goal_kcal_delta(WeightGoal::Maintain), 0.0);
        let t = compute_nutrition_targets(base()).unwrap();
        assert!(t.calories.is_finite());
        assert!(t.protein_g.is_finite());
        assert!(t.carbs_g.is_finite());
        assert!(t.fat_g.is_finite());
    }

    #[test]
    fn sedentary_less_than_very_active_for_the_same_body() {
        let sed = compute_nutrition_targets(BodyMetricsInput {
            activity_level: ActivityLevel::Sedentary,
            ..base()
        })
        .unwrap();
        let va = compute_nutrition_targets(BodyMetricsInput {
            activity_level: ActivityLevel::VeryActive,
            ..base()
        })
        .unwrap();
        assert!(va.calories > sed.calories);
    }

    #[test]
    fn calorie_floor_protects_against_a_too_low_default() {
        let t = compute_nutrition_targets(BodyMetricsInput {
            weight_kg: Some(40.0),
            height_cm: Some(150.0),
            age_years: Some(80.0),
            sex: Some("female"),
            activity_level: ActivityLevel::Sedentary,
            goal: WeightGoal::Lose,
            exercise_kcal: None,
        })
        .unwrap();
        assert_eq!(t.calories, MIN_CALORIE_TARGET);
    }

    #[test]
    fn none_on_missing_or_non_physical_metrics() {
        assert!(compute_nutrition_targets(BodyMetricsInput {
            weight_kg: None,
            ..base()
        })
        .is_none());
        assert!(compute_nutrition_targets(BodyMetricsInput {
            height_cm: None,
            ..base()
        })
        .is_none());
        assert!(compute_nutrition_targets(BodyMetricsInput {
            age_years: None,
            ..base()
        })
        .is_none());
        assert!(compute_nutrition_targets(BodyMetricsInput {
            weight_kg: Some(0.0),
            ..base()
        })
        .is_none());
        assert!(compute_nutrition_targets(BodyMetricsInput {
            weight_kg: Some(600.0),
            ..base()
        })
        .is_none());
        assert!(compute_nutrition_targets(BodyMetricsInput {
            height_cm: Some(400.0),
            ..base()
        })
        .is_none());
    }

    #[test]
    fn exercise_kcal_adds_on_top_of_the_base_goal() {
        let base_t = compute_nutrition_targets(base()).unwrap();
        let with_exercise = compute_nutrition_targets(BodyMetricsInput {
            exercise_kcal: Some(450.0),
            ..base()
        })
        .unwrap();
        assert_eq!(with_exercise.base_calories, base_t.calories); // 2550, unchanged
        assert_eq!(with_exercise.exercise_kcal, 450.0);
        assert_eq!(with_exercise.calories, base_t.calories + 450.0); // 3000
    }

    #[test]
    fn omitting_exercise_kcal_is_the_static_base() {
        let t = compute_nutrition_targets(base()).unwrap();
        assert_eq!(t.exercise_kcal, 0.0);
        assert_eq!(t.calories, t.base_calories);
    }

    #[test]
    fn extra_exercise_calories_flow_into_the_macro_budget() {
        let base_t = compute_nutrition_targets(base()).unwrap();
        let with_exercise = compute_nutrition_targets(BodyMetricsInput {
            exercise_kcal: Some(600.0),
            ..base()
        })
        .unwrap();
        // Protein is bodyweight-based (unchanged); the added fuel lands in carbs.
        assert_eq!(with_exercise.protein_g, base_t.protein_g);
        assert!(with_exercise.carbs_g > base_t.carbs_g);
    }

    #[test]
    fn a_negative_exercise_kcal_can_never_lower_the_goal() {
        let base_t = compute_nutrition_targets(base()).unwrap();
        let t = compute_nutrition_targets(BodyMetricsInput {
            exercise_kcal: Some(-500.0),
            ..base()
        })
        .unwrap();
        assert_eq!(t.exercise_kcal, 0.0);
        assert_eq!(t.calories, base_t.calories);
    }

    #[test]
    fn age_from_dob_whole_year_decremented_before_the_birthday() {
        let now = utc_ms(2026, 6, 4); // 2026-06-04
        assert_eq!(age_from_dob(Some("1990-06-04"), now), Some(36)); // birthday today
        assert_eq!(age_from_dob(Some("1990-06-05"), now), Some(35)); // birthday tomorrow
        assert_eq!(age_from_dob(Some("1990-06-03"), now), Some(36)); // birthday yesterday
    }

    #[test]
    fn age_from_dob_none_on_missing_malformed_out_of_range() {
        let now = utc_ms(2026, 6, 4);
        assert_eq!(age_from_dob(None, now), None);
        assert_eq!(age_from_dob(Some(""), now), None);
        assert_eq!(age_from_dob(Some("not-a-date"), now), None);
        assert_eq!(age_from_dob(Some("1850-01-01"), now), None); // > 120
    }

    #[test]
    fn activity_levels_ordered_least_to_most_active_with_rising_factors() {
        for i in 1..ACTIVITY_LEVELS.len() {
            assert!(ACTIVITY_LEVELS[i].factor > ACTIVITY_LEVELS[i - 1].factor);
        }
    }
}
