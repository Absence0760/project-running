//! Exercise-calorie estimator — energy burned by a run or a gym session, for
//! the dynamic-TDEE "base + exercise" nutrition goal.
//!
//! A parity port of web `nutrition/exercise_calories.ts` (twin of
//! `exercise_calories.dart`). Deliberately simple + conservative heuristics:
//! running costs ~1.036 kcal per kg of bodyweight per km (roughly
//! pace-independent), gym uses a MET model (resistance training ~5.0 MET,
//! kcal = MET · kg · hours). Gross, not net of resting metabolism, by design.
//!
//! Missing / non-positive weight or metric yields 0 — can't estimate without
//! both. The day aggregate sums the unrounded per-activity figures and rounds
//! ONCE at the end, so the displayed total matches the sum of its parts. Pure
//! logic, no peripherals, no allocator.

/// Gross running energy cost, kcal per kg of bodyweight per km.
pub const KCAL_PER_KG_PER_KM: f64 = 1.036;
/// MET for resistance training (Compendium "vigorous effort").
pub const GYM_MET: f64 = 5.0;

/// Calories burned by one run. 0 when distance or bodyweight is missing /
/// non-physical (can't estimate without both).
pub fn run_calories(distance_m: Option<f64>, weight_kg: Option<f64>) -> f64 {
    let w = match weight_kg {
        Some(w) if w > 0.0 => w,
        _ => return 0.0,
    };
    let d = match distance_m {
        Some(d) if d > 0.0 => d,
        _ => return 0.0,
    };
    KCAL_PER_KG_PER_KM * w * (d / 1000.0)
}

/// Calories burned by one gym session. 0 when duration or bodyweight is
/// missing / non-physical.
pub fn gym_calories(duration_s: Option<f64>, weight_kg: Option<f64>) -> f64 {
    let w = match weight_kg {
        Some(w) if w > 0.0 => w,
        _ => return 0.0,
    };
    let s = match duration_s {
        Some(s) if s > 0.0 => s,
        _ => return 0.0,
    };
    GYM_MET * w * (s / 3600.0)
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RunActivity {
    pub distance_m: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GymActivity {
    pub duration_s: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct DayActivityInput<'a> {
    pub runs: &'a [RunActivity],
    pub gym_sessions: &'a [GymActivity],
    pub weight_kg: Option<f64>,
}

/// Total whole-kcal burned across a day's runs + gym sessions. Returns 0 when
/// bodyweight is unknown (can't estimate) or nothing qualifies. Rounded once,
/// at the end, so the displayed total matches the sum of its parts.
pub fn exercise_calories_for_day(input: DayActivityInput) -> f64 {
    let weight = match input.weight_kg {
        Some(w) if w > 0.0 => w,
        _ => return 0.0,
    };
    let mut total = 0.0;
    for r in input.runs {
        total += run_calories(r.distance_m, Some(weight));
    }
    for g in input.gym_sessions {
        total += gym_calories(g.duration_s, Some(weight));
    }
    libm::round(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_calories_70kg_over_10km() {
        assert!(
            (run_calories(Some(10000.0), Some(70.0)) - KCAL_PER_KG_PER_KM * 70.0 * 10.0).abs()
                < 1e-9
        );
    }

    #[test]
    fn run_calories_scales_linearly_with_distance() {
        assert!(
            (run_calories(Some(5000.0), Some(70.0))
                - run_calories(Some(10000.0), Some(70.0)) / 2.0)
                .abs()
                < 1e-9
        );
    }

    #[test]
    fn run_calories_missing_or_non_physical_inputs_are_zero() {
        assert_eq!(run_calories(None, Some(70.0)), 0.0);
        assert_eq!(run_calories(Some(10000.0), None), 0.0);
        assert_eq!(run_calories(Some(0.0), Some(70.0)), 0.0);
        assert_eq!(run_calories(Some(10000.0), Some(0.0)), 0.0);
        assert_eq!(run_calories(Some(-100.0), Some(70.0)), 0.0);
        assert_eq!(run_calories(Some(10000.0), Some(-5.0)), 0.0);
    }

    #[test]
    fn gym_calories_70kg_for_1h() {
        assert!((gym_calories(Some(3600.0), Some(70.0)) - GYM_MET * 70.0).abs() < 1e-9);
    }

    #[test]
    fn gym_calories_half_duration_half_burn() {
        assert!(
            (gym_calories(Some(1800.0), Some(70.0)) - gym_calories(Some(3600.0), Some(70.0)) / 2.0)
                .abs()
                < 1e-9
        );
    }

    #[test]
    fn gym_calories_missing_or_non_physical_inputs_are_zero() {
        assert_eq!(gym_calories(None, Some(70.0)), 0.0);
        assert_eq!(gym_calories(Some(3600.0), None), 0.0);
        assert_eq!(gym_calories(Some(0.0), Some(70.0)), 0.0);
        assert_eq!(gym_calories(Some(3600.0), Some(0.0)), 0.0);
    }

    #[test]
    fn day_sums_runs_and_gym_rounded_once() {
        let runs = [
            RunActivity {
                distance_m: Some(10000.0),
            },
            RunActivity {
                distance_m: Some(5000.0),
            },
        ];
        let gym = [GymActivity {
            duration_s: Some(3600.0),
        }];
        let total = exercise_calories_for_day(DayActivityInput {
            runs: &runs,
            gym_sessions: &gym,
            weight_kg: Some(70.0),
        });
        let expected =
            (KCAL_PER_KG_PER_KM * 70.0 * 10.0 + KCAL_PER_KG_PER_KM * 70.0 * 5.0 + GYM_MET * 70.0)
                .round();
        assert_eq!(total, expected);
    }

    #[test]
    fn day_unknown_bodyweight_is_zero() {
        let runs = [RunActivity {
            distance_m: Some(10000.0),
        }];
        let gym = [GymActivity {
            duration_s: Some(3600.0),
        }];
        assert_eq!(
            exercise_calories_for_day(DayActivityInput {
                runs: &runs,
                gym_sessions: &gym,
                weight_kg: None,
            }),
            0.0
        );
    }

    #[test]
    fn day_no_activities_is_zero() {
        assert_eq!(
            exercise_calories_for_day(DayActivityInput {
                runs: &[],
                gym_sessions: &[],
                weight_kg: Some(70.0),
            }),
            0.0
        );
    }

    #[test]
    fn day_ignores_rows_missing_their_metric() {
        let runs = [RunActivity { distance_m: None }];
        let gym = [GymActivity { duration_s: None }];
        assert_eq!(
            exercise_calories_for_day(DayActivityInput {
                runs: &runs,
                gym_sessions: &gym,
                weight_kg: Some(70.0),
            }),
            0.0
        );
    }

    #[test]
    fn day_rounds_the_total_not_each_item() {
        // Two 100 m runs at 1 kg each cost 0.1036 kcal apiece. Rounding each to
        // 0 would give 0; rounding the 0.2072 sum once gives 0 too — so pick a
        // weight where per-item rounding would diverge from single-round.
        // 300 m at 5 kg = 1.554 kcal per run; three of them = 4.662 → round 5.
        // Per-item rounding would be round(1.554)*3 = 2*3 = 6.
        let runs = [
            RunActivity {
                distance_m: Some(300.0),
            },
            RunActivity {
                distance_m: Some(300.0),
            },
            RunActivity {
                distance_m: Some(300.0),
            },
        ];
        let total = exercise_calories_for_day(DayActivityInput {
            runs: &runs,
            gym_sessions: &[],
            weight_kg: Some(5.0),
        });
        assert_eq!(total, 5.0);
    }
}
