//! Race-day mode: days-until, pacing strategy, the pre-race checklist, and a
//! goal-feasibility verdict.
//!
//! Parity port of web `runs/race_day.ts` — keep the pacing math, checklist
//! shape, verdict bands, edge cases, and test count in lockstep.
//!
//! Two representational changes fall out of `no_std`:
//!
//!   - The web `daysUntilRace` parses a `YYYY-MM-DD` string and a `Date` into
//!     local midnights and diffs the milliseconds. Neither ISO parsing nor a
//!     timezone database belongs in firmware, so here both the race and "today"
//!     arrive as integer **day indices** (calendar days since any fixed epoch,
//!     in the runner's local zone — the same integer the phone derives from a
//!     local date key, see [`current_week`](crate::current_week)). The diff is
//!     then a plain subtraction, matching the web round-to-days result.
//!   - The checklist items are i18n display strings on web (resolved at render
//!     via `m(key)`). Here each item is an enum **identifier**
//!     ([`ChecklistItem`]) the presentation layer resolves to a localized
//!     label + detail — no English prose lives in the core, mirroring how
//!     [`badges`](crate::badges) carries key identifiers rather than strings.
//!
//! Pure logic, no peripherals, no allocator. `f64` matches the web `number`
//! math; `libm` supplies `floor`/`ceil` off-test.

use core::fmt::Write;

use heapless::{String, Vec};

/// 1 mile in metres. Pass as the `unit_metres` arg to switch per-km splits to
/// per-mile splits for imperial users.
pub const MILE_METRES: f64 = 1609.344;

/// Upper bound on per-unit splits a [`PacingStrategy`] can carry. 256 covers a
/// 256 km race in per-km splits (a 100-mile ultra is ~161) or a ~412 km race in
/// per-mile splits; a longer race truncates its split list — the average pace
/// is unaffected.
pub const MAX_PACING_SPLITS: usize = 256;

/// Fraction-of-goal band inside which a projection counts as "on track".
/// Mirrors web `GOAL_ONTRACK_BAND`.
pub const GOAL_ONTRACK_BAND: f64 = 0.02;
/// Slower than goal by more than this fraction → "far behind". Between the
/// on-track band and this is a recoverable "behind". Mirrors web
/// `GOAL_FARBEHIND_BAND`.
pub const GOAL_FARBEHIND_BAND: f64 = 0.08;

/// Human-readable pacing-strategy name. `PositiveSplit` exists in the web union
/// but no builder emits it yet; kept for parity with the source type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PacingLabel {
    Even,
    NegativeSplit,
    PositiveSplit,
}

/// A pacing plan: the whole-race average (always per-km, unit-agnostic so a
/// caller can format one pace string without branching on the split unit) plus
/// one rounded seconds target per `unit_metres` of distance.
#[derive(Clone, Debug, PartialEq)]
pub struct PacingStrategy {
    pub avg_sec_per_km: f64,
    pub splits_sec: Vec<i32, MAX_PACING_SPLITS>,
    pub label: PacingLabel,
}

/// The section a checklist item belongs to. Order in [`race_checklist`] is
/// `MorningOf`, `Gear`, `Fueling`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ChecklistSectionTitle {
    MorningOf,
    Gear,
    Fueling,
}

/// One pre-race checklist item, as an identifier the display layer resolves to
/// a localized label + optional detail. Variants are grouped by section.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ChecklistItem {
    // Morning of
    MorningWakeUp,
    MorningHydrate,
    MorningArriveEarly,
    MorningWarmup,
    // Gear
    GearShoes,
    GearWatch,
    GearBib,
    GearAntiChafe,
    GearSocks,
    GearSpareLaces,
    GearToiletPlan,
    // Fueling
    FuelLightBreakfastShort,
    FuelLightBreakfastHalf,
    FuelGelsHalf,
    FuelPreRaceCaffeine,
    FuelCarbLoad,
    FuelBigBreakfast,
    FuelGelsFull,
    FuelElectrolyte,
}

/// Largest a single checklist section gets: the 5 core gear items plus the
/// spare-laces and toilet-plan add-ons.
pub const MAX_CHECKLIST_ITEMS: usize = 8;

#[derive(Clone, Debug, PartialEq)]
pub struct ChecklistSection {
    pub title: ChecklistSectionTitle,
    pub items: Vec<ChecklistItem, MAX_CHECKLIST_ITEMS>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum GoalFeasibilityVerdict {
    Ahead,
    OnTrack,
    Behind,
    FarBehind,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GoalFeasibility {
    pub verdict: GoalFeasibilityVerdict,
    /// `predicted - goal`, rounded. Negative = projection faster than goal.
    pub delta_sec: i32,
}

/// JS `Math.round` semantics (half toward +infinity), so a negative half-value
/// rounds the same way the web splits do.
fn js_round(x: f64) -> f64 {
    libm::floor(x + 0.5)
}

/// Days from `today_day` to `race_day`, both day indices (see the module docs).
/// Non-negative on race day or later (race day itself is 0); negative for a
/// past race so the caller can hide the panel.
pub fn days_until_race(race_day: i32, today_day: i32) -> i32 {
    race_day - today_day
}

/// Even-split pacing — every unit at the same pace. Total seconds is preserved;
/// the last split absorbs the partial-unit tail plus the accumulated per-split
/// rounding error so the splits sum to `total_sec`. `unit_metres` = 1000 for
/// per-km splits, [`MILE_METRES`] for per-mile.
pub fn even_split_pacing(distance_m: f64, total_sec: f64, unit_metres: f64) -> PacingStrategy {
    if distance_m <= 0.0 || total_sec <= 0.0 {
        return PacingStrategy {
            avg_sec_per_km: 0.0,
            splits_sec: Vec::new(),
            label: PacingLabel::Even,
        };
    }
    let units = libm::ceil(distance_m / unit_metres) as usize;
    let avg_sec_per_km = total_sec / (distance_m / 1000.0);
    let avg_per_unit = total_sec / (distance_m / unit_metres);
    let mut splits: Vec<i32, MAX_PACING_SPLITS> = Vec::new();
    for _ in 0..units.saturating_sub(1) {
        if splits.push(js_round(avg_per_unit) as i32).is_err() {
            break;
        }
    }
    let summed: i32 = splits.iter().sum();
    let _ = splits.push(js_round(total_sec) as i32 - summed);
    PacingStrategy {
        avg_sec_per_km,
        splits_sec: splits,
        label: PacingLabel::Even,
    }
}

/// Negative-split pacing — second half faster than the first by `delta_percent`.
/// Halves are by *distance*, not unit count; each split's pace is the pace at
/// its midpoint unit. `unit_metres` as in [`even_split_pacing`].
pub fn negative_split_pacing(
    distance_m: f64,
    total_sec: f64,
    delta_percent: f64,
    unit_metres: f64,
) -> PacingStrategy {
    if distance_m <= 0.0 || total_sec <= 0.0 {
        return PacingStrategy {
            avg_sec_per_km: 0.0,
            splits_sec: Vec::new(),
            label: PacingLabel::NegativeSplit,
        };
    }
    let avg_sec_per_km = total_sec / (distance_m / 1000.0);
    let avg_per_unit = total_sec / (distance_m / unit_metres);
    let delta = (avg_per_unit * delta_percent) / 100.0;
    let first_half_pace = avg_per_unit + delta;
    let second_half_pace = avg_per_unit - delta;
    let units = libm::ceil(distance_m / unit_metres) as usize;
    let total_units = distance_m / unit_metres;
    let half_units = total_units / 2.0;
    let mut splits: Vec<i32, MAX_PACING_SPLITS> = Vec::new();
    for i in 0..units {
        let start_u = i as f64;
        let end_u = ((i + 1) as f64).min(total_units);
        let seg_u = end_u - start_u;
        let mid_u = start_u + seg_u / 2.0;
        let pace = if mid_u < half_units {
            first_half_pace
        } else {
            second_half_pace
        };
        if splits.push(js_round(pace * seg_u) as i32).is_err() {
            break;
        }
    }
    PacingStrategy {
        avg_sec_per_km,
        splits_sec: splits,
        label: PacingLabel::NegativeSplit,
    }
}

/// Distance-aware pre-race checklist. Marathon distances pick up fuel + gear
/// items a 5k doesn't need; everything <= 10.5 km stays light. Weather is left
/// to the caller.
pub fn race_checklist(distance_m: f64) -> Vec<ChecklistSection, 3> {
    let is_short = distance_m <= 10_500.0;
    let is_half = distance_m > 10_500.0 && distance_m <= 22_000.0;
    let is_full = distance_m > 22_000.0;

    let mut fuel: Vec<ChecklistItem, MAX_CHECKLIST_ITEMS> = Vec::new();
    if is_short {
        let _ = fuel.push(ChecklistItem::FuelLightBreakfastShort);
    } else if is_half {
        let _ = fuel.push(ChecklistItem::FuelLightBreakfastHalf);
        let _ = fuel.push(ChecklistItem::FuelGelsHalf);
        let _ = fuel.push(ChecklistItem::FuelPreRaceCaffeine);
    } else if is_full {
        let _ = fuel.push(ChecklistItem::FuelCarbLoad);
        let _ = fuel.push(ChecklistItem::FuelBigBreakfast);
        let _ = fuel.push(ChecklistItem::FuelGelsFull);
        let _ = fuel.push(ChecklistItem::FuelElectrolyte);
    }

    let mut gear: Vec<ChecklistItem, MAX_CHECKLIST_ITEMS> = Vec::new();
    let _ = gear.push(ChecklistItem::GearShoes);
    let _ = gear.push(ChecklistItem::GearWatch);
    let _ = gear.push(ChecklistItem::GearBib);
    let _ = gear.push(ChecklistItem::GearAntiChafe);
    let _ = gear.push(ChecklistItem::GearSocks);
    if !is_short {
        let _ = gear.push(ChecklistItem::GearSpareLaces);
    }
    if is_full {
        let _ = gear.push(ChecklistItem::GearToiletPlan);
    }

    let mut morning_of: Vec<ChecklistItem, MAX_CHECKLIST_ITEMS> = Vec::new();
    let _ = morning_of.push(ChecklistItem::MorningWakeUp);
    let _ = morning_of.push(ChecklistItem::MorningHydrate);
    let _ = morning_of.push(ChecklistItem::MorningArriveEarly);
    let _ = morning_of.push(ChecklistItem::MorningWarmup);

    let mut sections: Vec<ChecklistSection, 3> = Vec::new();
    let _ = sections.push(ChecklistSection {
        title: ChecklistSectionTitle::MorningOf,
        items: morning_of,
    });
    let _ = sections.push(ChecklistSection {
        title: ChecklistSectionTitle::Gear,
        items: gear,
    });
    let _ = sections.push(ChecklistSection {
        title: ChecklistSectionTitle::Fueling,
        items: fuel,
    });
    sections
}

/// Grade a goal time against a fitness-derived prediction for the same
/// distance. `None` when either input is missing / non-positive (the caller
/// hides the signal rather than showing a verdict off no data).
pub fn goal_feasibility(goal_sec: f64, predicted_sec: f64) -> Option<GoalFeasibility> {
    // Positive form (not `x <= 0.0`) so a NaN input maps to None, matching the
    // web `!(x > 0)` guard; `+inf` stays valid as it does there.
    let inputs_valid = goal_sec > 0.0 && predicted_sec > 0.0;
    if !inputs_valid {
        return None;
    }
    let delta_sec = predicted_sec - goal_sec;
    let ratio = delta_sec / goal_sec;
    let verdict = if ratio < -GOAL_ONTRACK_BAND {
        GoalFeasibilityVerdict::Ahead
    } else if ratio <= GOAL_ONTRACK_BAND {
        GoalFeasibilityVerdict::OnTrack
    } else if ratio <= GOAL_FARBEHIND_BAND {
        GoalFeasibilityVerdict::Behind
    } else {
        GoalFeasibilityVerdict::FarBehind
    };
    Some(GoalFeasibility {
        verdict,
        delta_sec: js_round(delta_sec) as i32,
    })
}

/// Pretty-print seconds as `M:SS` (or `H:MM:SS` for splits over an hour).
pub fn fmt_split_time(seconds: f64) -> String<16> {
    let total = js_round(seconds) as i64;
    let h = total / 3600;
    let m = (total % 3600) / 60;
    let s = total % 60;
    let mut out: String<16> = String::new();
    if h > 0 {
        let _ = write!(out, "{}:{:02}:{:02}", h, m, s);
    } else {
        let _ = write!(out, "{}:{:02}", m, s);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // Mirror of `apps/web/src/lib/runs/race_day.test.ts` — same scenarios, same
    // expected values, so the ports can't drift.

    // ─────────── days_until_race ───────────
    // The web dates anchor "today" at 2026-05-13; TODAY is that local day's
    // index (2026-06-10 is 20_614, so 2026-05-13 is 28 days earlier).
    const TODAY: i32 = 20_586;

    #[test]
    fn days_until_race_today_is_zero() {
        assert_eq!(days_until_race(TODAY, TODAY), 0);
    }

    #[test]
    fn days_until_race_tomorrow_is_one() {
        assert_eq!(days_until_race(TODAY + 1, TODAY), 1);
    }

    #[test]
    fn days_until_race_two_months_out() {
        // May 13 to July 13 = 61 days.
        assert_eq!(days_until_race(TODAY + 61, TODAY), 61);
    }

    #[test]
    fn days_until_race_in_the_past_is_negative() {
        assert_eq!(days_until_race(TODAY - 30, TODAY), -30);
    }

    #[test]
    fn days_until_race_local_day_is_stable_across_midnight() {
        // Web guards a 23:30-local vs 00:30-next-day wall-clock difference by
        // comparing calendar dates. The day index already encodes the LOCAL
        // calendar day (collapsed on the phone), so the delta is exact here.
        assert_eq!(days_until_race(TODAY + 1, TODAY), 1);
        assert_eq!(days_until_race(TODAY, TODAY), 0);
    }

    // ─────────── even_split_pacing ───────────

    #[test]
    fn even_split_5k_at_25_min_is_5min_per_km() {
        let s = even_split_pacing(5000.0, 1500.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 5);
        for &sp in &s.splits_sec {
            assert_eq!(sp, 300);
        }
        assert_eq!(js_round(s.avg_sec_per_km) as i32, 300);
    }

    #[test]
    fn even_split_10_5km_gives_11_splits_last_partial() {
        let s = even_split_pacing(10_500.0, 3150.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 11);
        for i in 0..10 {
            assert_eq!(s.splits_sec[i], 300);
        }
        assert_eq!(s.splits_sec[10], 150);
    }

    #[test]
    fn even_split_sums_to_target_with_fractional_avg() {
        let s = even_split_pacing(10_000.0, 3005.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 10);
        assert_eq!(s.splits_sec.iter().sum::<i32>(), 3005);
    }

    #[test]
    fn even_split_partial_tail_total_preserved_with_fractional_avg() {
        let s = even_split_pacing(10_300.0, 3091.0, 1000.0);
        assert_eq!(s.splits_sec.iter().sum::<i32>(), 3091);
    }

    #[test]
    fn even_split_marathon_at_3_30() {
        let total = 3.0 * 3600.0 + 30.0 * 60.0;
        let s = even_split_pacing(42195.0, total, 1000.0);
        assert_eq!(s.splits_sec.len(), 43);
        assert!((s.avg_sec_per_km - 298.65).abs() < 0.5);
    }

    #[test]
    fn even_split_zero_or_negative_is_empty() {
        assert!(even_split_pacing(0.0, 1500.0, 1000.0).splits_sec.is_empty());
        assert!(even_split_pacing(5000.0, 0.0, 1000.0).splits_sec.is_empty());
    }

    #[test]
    fn even_split_mile_mode_5k_four_splits() {
        let s = even_split_pacing(5000.0, 1500.0, MILE_METRES);
        assert_eq!(s.splits_sec.len(), 4);
        for i in 0..3 {
            assert!(
                (s.splits_sec[i] - 483).abs() <= 1,
                "split {} should be ~483s, got {}",
                i,
                s.splits_sec[i]
            );
        }
        assert_eq!(js_round(s.avg_sec_per_km) as i32, 300);
    }

    #[test]
    fn even_split_mile_mode_avg_stays_per_km() {
        let total = 3.0 * 3600.0 + 30.0 * 60.0;
        let km = even_split_pacing(42195.0, total, 1000.0);
        let mi = even_split_pacing(42195.0, total, MILE_METRES);
        assert!((km.avg_sec_per_km - mi.avg_sec_per_km).abs() < 0.01);
    }

    #[test]
    fn even_split_count_derives_from_unit_metres() {
        let km = even_split_pacing(10_000.0, 3000.0, 1000.0);
        let mi = even_split_pacing(10_000.0, 3000.0, MILE_METRES);
        assert_eq!(km.splits_sec.len(), 10);
        assert_eq!(mi.splits_sec.len(), 7);
    }

    // ─────────── negative_split_pacing — mile mode ───────────

    #[test]
    fn negative_split_mile_mode_preserves_slow_then_fast() {
        let s = negative_split_pacing(10_000.0, 3000.0, 2.0, MILE_METRES);
        assert_eq!(s.splits_sec.len(), 7);
        let avg_mi = 3000.0 / (10_000.0 / MILE_METRES);
        assert!(s.splits_sec[0] as f64 > avg_mi);
        assert!((s.splits_sec[s.splits_sec.len() - 1] as f64) < avg_mi);
    }

    #[test]
    fn negative_split_mile_mode_zero_delta_yields_even() {
        let s = negative_split_pacing(10_000.0, 3000.0, 0.0, MILE_METRES);
        let avg_mi = 3000.0 / (10_000.0 / MILE_METRES);
        for i in 0..s.splits_sec.len() - 1 {
            assert!(
                (s.splits_sec[i] as f64 - avg_mi).abs() <= 1.0,
                "split {}: {} should be ~{}",
                i,
                s.splits_sec[i],
                avg_mi
            );
        }
    }

    // ─────────── negative_split_pacing ───────────

    #[test]
    fn negative_split_first_half_slower_second_faster() {
        let s = negative_split_pacing(10_000.0, 3000.0, 2.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 10);
        for i in 0..5 {
            assert!(s.splits_sec[i] > 300, "split {} should be > avg", i);
        }
        for i in 5..10 {
            assert!(s.splits_sec[i] < 300, "split {} should be < avg", i);
        }
    }

    #[test]
    fn negative_split_sum_approximates_total() {
        let s = negative_split_pacing(10_000.0, 3000.0, 2.0, 1000.0);
        let sum: i32 = s.splits_sec.iter().sum();
        assert!((sum - 3000).abs() <= 10);
    }

    #[test]
    fn negative_split_zero_delta_yields_even() {
        let s = negative_split_pacing(5000.0, 1500.0, 0.0, 1000.0);
        for &sp in &s.splits_sec {
            assert_eq!(sp, 300);
        }
    }

    // ─────────── race_checklist ───────────

    fn section(c: &Vec<ChecklistSection, 3>, title: ChecklistSectionTitle) -> &ChecklistSection {
        c.iter().find(|s| s.title == title).unwrap()
    }

    fn has(sec: &ChecklistSection, item: ChecklistItem) -> bool {
        sec.items.contains(&item)
    }

    #[test]
    fn checklist_5k_has_no_gels() {
        let c = race_checklist(5000.0);
        let fuel = section(&c, ChecklistSectionTitle::Fueling);
        assert!(!has(fuel, ChecklistItem::FuelGelsHalf));
        assert!(!has(fuel, ChecklistItem::FuelGelsFull));
    }

    #[test]
    fn checklist_half_marathon_prescribes_gels() {
        let c = race_checklist(21097.0);
        let fuel = section(&c, ChecklistSectionTitle::Fueling);
        assert!(has(fuel, ChecklistItem::FuelGelsHalf));
    }

    #[test]
    fn checklist_marathon_prescribes_gels_and_carb_load() {
        let c = race_checklist(42195.0);
        let fuel = section(&c, ChecklistSectionTitle::Fueling);
        assert!(has(fuel, ChecklistItem::FuelGelsFull));
        assert!(has(fuel, ChecklistItem::FuelCarbLoad));
    }

    #[test]
    fn checklist_always_has_three_sections() {
        let c = race_checklist(10000.0);
        assert!(c
            .iter()
            .any(|s| s.title == ChecklistSectionTitle::MorningOf));
        assert!(c.iter().any(|s| s.title == ChecklistSectionTitle::Gear));
        assert!(c.iter().any(|s| s.title == ChecklistSectionTitle::Fueling));
    }

    #[test]
    fn checklist_marathon_adds_toilet_plan() {
        let c = race_checklist(42195.0);
        let gear = section(&c, ChecklistSectionTitle::Gear);
        assert!(has(gear, ChecklistItem::GearToiletPlan));
    }

    #[test]
    fn checklist_10k_boundary_is_short() {
        let c10k = race_checklist(10000.0);
        let fuel10k = section(&c10k, ChecklistSectionTitle::Fueling);
        assert!(!has(fuel10k, ChecklistItem::FuelGelsHalf));

        let c11k = race_checklist(11000.0);
        let fuel11k = section(&c11k, ChecklistSectionTitle::Fueling);
        assert!(has(fuel11k, ChecklistItem::FuelGelsHalf));
    }

    #[test]
    fn checklist_gear_has_core_five() {
        let c = race_checklist(5000.0);
        let gear = section(&c, ChecklistSectionTitle::Gear);
        assert!(has(gear, ChecklistItem::GearShoes));
        assert!(has(gear, ChecklistItem::GearWatch));
        assert!(has(gear, ChecklistItem::GearBib));
        assert!(has(gear, ChecklistItem::GearAntiChafe));
        assert!(has(gear, ChecklistItem::GearSocks));
    }

    // ─────────── fmt_split_time ───────────

    #[test]
    fn fmt_split_time_under_an_hour() {
        assert_eq!(fmt_split_time(305.0).as_str(), "5:05");
        assert_eq!(fmt_split_time(60.0).as_str(), "1:00");
    }

    #[test]
    fn fmt_split_time_over_an_hour() {
        assert_eq!(fmt_split_time(3725.0).as_str(), "1:02:05");
        assert_eq!(
            fmt_split_time(3.0 * 3600.0 + 30.0 * 60.0).as_str(),
            "3:30:00"
        );
    }

    #[test]
    fn fmt_split_time_rounds_to_nearest_second() {
        assert_eq!(fmt_split_time(305.6).as_str(), "5:06");
    }

    // ─────────── Round 3 edge cases ───────────

    #[test]
    fn even_split_exact_whole_km_has_no_partial_tail() {
        let s = even_split_pacing(5000.0, 1500.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 5);
        for &sp in &s.splits_sec {
            assert_eq!(sp, 300);
        }
    }

    #[test]
    fn negative_split_large_delta_preserves_total() {
        let s = negative_split_pacing(10_000.0, 3000.0, 10.0, 1000.0);
        let sum: i32 = s.splits_sec.iter().sum();
        assert!((sum - 3000).abs() <= 10, "total drifted: {}", sum);
        assert!(s.splits_sec[0] > s.splits_sec[9]);
        assert!(s.splits_sec[0] - s.splits_sec[9] >= 50);
    }

    #[test]
    fn even_split_marathon_partial_last() {
        let s = even_split_pacing(42195.0, 12000.0, 1000.0);
        assert_eq!(s.splits_sec.len(), 43);
        let partial = s.splits_sec[42];
        let full_km = s.splits_sec[0];
        assert!(partial < full_km);
    }

    #[test]
    fn fmt_split_time_zero_and_small() {
        assert_eq!(fmt_split_time(0.0).as_str(), "0:00");
        assert_eq!(fmt_split_time(0.4).as_str(), "0:00");
        assert_eq!(fmt_split_time(0.5).as_str(), "0:01");
    }

    // ─────────── goal_feasibility ───────────

    #[test]
    fn goal_feasibility_much_faster_is_ahead() {
        let f = goal_feasibility(12600.0, 11700.0).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::Ahead);
        assert_eq!(f.delta_sec, -900);
    }

    #[test]
    fn goal_feasibility_within_band_is_on_track() {
        let goal = 12600.0;
        let f = goal_feasibility(goal, js_round(goal * 1.01)).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::OnTrack);
    }

    #[test]
    fn goal_feasibility_1pct_faster_is_on_track() {
        let goal = 12600.0;
        let f = goal_feasibility(goal, js_round(goal * 0.99)).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::OnTrack);
    }

    #[test]
    fn goal_feasibility_moderately_slower_is_behind() {
        let goal = 12600.0;
        let f = goal_feasibility(goal, js_round(goal * 1.05)).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::Behind);
        assert!(f.delta_sec > 0);
    }

    #[test]
    fn goal_feasibility_far_slower_is_far_behind() {
        let goal = 12600.0;
        let f = goal_feasibility(goal, js_round(goal * 1.12)).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::FarBehind);
    }

    #[test]
    fn goal_feasibility_on_track_band_edge_stays_on_track() {
        let goal = 10000.0;
        let slow = goal_feasibility(goal, goal * (1.0 + GOAL_ONTRACK_BAND)).unwrap();
        assert_eq!(slow.verdict, GoalFeasibilityVerdict::OnTrack);
        let fast = goal_feasibility(goal, goal * (1.0 - GOAL_ONTRACK_BAND)).unwrap();
        assert_eq!(fast.verdict, GoalFeasibilityVerdict::OnTrack);
    }

    #[test]
    fn goal_feasibility_far_behind_band_edge_stays_behind() {
        let goal = 10000.0;
        let f = goal_feasibility(goal, goal * (1.0 + GOAL_FARBEHIND_BAND)).unwrap();
        assert_eq!(f.verdict, GoalFeasibilityVerdict::Behind);
        let past = goal_feasibility(goal, goal * (1.0 + GOAL_FARBEHIND_BAND) + 1.0).unwrap();
        assert_eq!(past.verdict, GoalFeasibilityVerdict::FarBehind);
    }

    #[test]
    fn goal_feasibility_null_on_non_positive_inputs() {
        assert!(goal_feasibility(0.0, 12600.0).is_none());
        assert!(goal_feasibility(12600.0, 0.0).is_none());
        assert!(goal_feasibility(-1.0, 100.0).is_none());
        assert!(goal_feasibility(f64::NAN, 100.0).is_none());
    }

    #[test]
    fn goal_feasibility_delta_is_rounded() {
        let f = goal_feasibility(1000.0, 1000.6).unwrap();
        assert_eq!(f.delta_sec, 1);
        assert_eq!(f.verdict, GoalFeasibilityVerdict::OnTrack);
    }
}
