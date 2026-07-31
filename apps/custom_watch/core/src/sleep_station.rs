//! Sleep-station mode — how long a 200-mile racer may lie down and still make
//! the next cut-off.
//!
//! At 3 a.m. at mile 140 the runner does not want a stopwatch they have to
//! programme; they want the race to answer the question. Both halves of the
//! answer are already on the wrist, so this module computes rather than asks:
//! [`crate::cutoff_eta::next_cutoff_eta`] already picks the nearest cut-off
//! ahead and returns `margin_s` = *(limit − elapsed) − (time still needed to
//! cover the remaining distance)*, which is the nap budget before a safety
//! reserve. Nothing about cut-off selection or projection is re-derived here —
//! the only new arithmetic is the reserve and the honesty rules around it.
//!
//! **The budget is its own countdown.** The race clock keeps running through a
//! pause ([`crate::alerts`] makes the same call for the time alert), so
//! recomputing the budget each tick makes it fall one second per second while
//! the runner sleeps. There is no nap timer to start and no nap state to
//! recover after a reboot: lie down, and the number on the wrist is what is
//! left.
//!
//! **Every term can be unknown, and an unknown term withholds the number.**
//! `cutoff_eta` refuses to project off a stale fix — a lost-signal runner must
//! not read as "on pace" — and a sleep budget is that same projection minus a
//! reserve, so it inherits the refusal whole: [`SleepStatus::Unknown`] renders
//! as `--`, never as a plausible-looking count of minutes. The failure this
//! feature exists to prevent is a runner who oversleeps because the watch
//! guessed, so every rounding, every pace choice and every clamp below leans
//! the same way: **wake early, never late**.
//!
//! Three deliberate conservatisms, in the order they apply:
//!
//! 1. **The pace is the slower of two** ([`conservative_pace_s_per_km`]) — the
//!    run's moving pace (what `cutoff_eta` projects the live page from) and the
//!    run's race pace including every stop so far. Moving pace alone ignores
//!    the aid stations that will keep happening; race pace alone is optimistic
//!    at hour 40 when a runner is coming apart. The slower of the two is wrong
//!    in only one direction.
//! 2. **The reserve is floor-plus-proportional**, because it covers two error
//!    sources of different shapes — see [`SLEEP_RESERVE_FLOOR_S`] and
//!    [`SLEEP_RESERVE_FRACTION`].
//! 3. **The budget floors to whole minutes** and a sub-minute answer settles to
//!    [`SleepStatus::NoBudget`] rather than rounding up to one.
//!
//! One term stays outside the model on purpose: the leg ahead may be steeper
//! than the ground behind, and the projection is flat-pace like the cut-off
//! ETA's. That is a further reason the reserve exists, not a reason to grade
//! the budget on terrain the runner has not walked yet.
//!
//! What this module does **not** do is wake anyone. The tier-1 prototype has no
//! vibration motor and no buzzer — every alert in this firmware is display-only
//! — so the page states [`NO_WAKE_NOTICE`] permanently rather than implying an
//! alarm. A crew member reading the wrist is the tier-1 wake mechanism; there
//! is no other.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`. Watch-
//! native: there is no web or Dart twin to keep in lockstep.

use crate::cutoff_eta::{next_cutoff_eta, CutoffLeg, CUTOFF_TIGHT_S};

/// Reserve held back from the margin no matter how short the leg —
/// [`CUTOFF_TIGHT_S`], the same 30 minutes the app already calls "tight".
///
/// Reused rather than invented: the product has already decided that a cut-off
/// made by under half an hour is not comfortable, and a nap that eats into that
/// span has spent margin the rest of the product treats as spoken for. It also
/// covers the fixed costs a stop carries whatever its length — getting up,
/// shoes and socks back on, a refill — which do not scale with the leg ahead
/// and so cannot be expressed proportionally.
pub const SLEEP_RESERVE_FLOOR_S: u32 = CUTOFF_TIGHT_S;

/// Reserve held back as a fraction of the time still needed to reach the
/// cut-off, when that exceeds the floor.
///
/// The dominant error in the budget is that post-nap pace is slower than the
/// pace it was projected from, and that error scales with the leg: a 25 % slip
/// costs five minutes on a twenty-minute leg and ninety on a six-hour one. A
/// fixed reserve is therefore either useless on a long leg or absurd on a short
/// one, which is why the two terms coexist.
///
/// **A judgement call, not a measurement** — no post-sleep pace-degradation
/// corpus exists here to derive it from. It is registered as
/// derived-not-measured in `docs/custom_watch/quality_standards.md` alongside
/// the battery projections.
pub const SLEEP_RESERVE_FRACTION: f64 = 0.25;

/// The shortest budget the mode will offer. Below a whole minute the hero
/// floors to `0`, and a page whose entire job is "how long may I sleep"
/// answering `0` reads as broken rather than as *no*; that answer settles to
/// [`SleepStatus::NoBudget`] instead, which says it in words.
pub const MIN_SLEEP_BUDGET_S: u32 = 60;

/// What the page states permanently, in every state, because the hardware
/// cannot do otherwise.
///
/// The tier-1 BOM has no vibration motor and no buzzer, so nothing this
/// firmware can do will rouse a sleeping runner. A nap-budget surface that
/// stayed quiet about that would be read as an alarm clock by exactly the
/// person least able to check — and would cause the oversleep it exists to
/// prevent. Exactly [`crate::face::COLS`] cells wide (const-asserted below).
pub const NO_WAKE_NOTICE: &str = "WATCH CANNOT WAKE YOU";

/// Whether a nap budget exists, and if not, why not. Four states, because the
/// three ways of having no number mean different things to the runner and only
/// one of them is a fault.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SleepStatus {
    /// A term of the budget is missing — a stale route position, or no pace
    /// banked yet. Renders `--`. Never a number: this is the state a confident
    /// guess would come from.
    #[default]
    Unknown,
    /// The course carries cut-offs and none remains ahead. Nothing bounds the
    /// nap, so the mode has no answer — and must not read as "sleep freely".
    NoCutoff,
    /// Computed, and the answer is under a minute (or already negative): there
    /// is no time to lie down.
    NoBudget,
    /// Computed, positive, at least [`MIN_SLEEP_BUDGET_S`].
    Budget,
}

/// The nap budget at the runner's current position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SleepBudget {
    pub status: SleepStatus,
    /// Sleep seconds still available; 0 unless `status` is
    /// [`SleepStatus::Budget`].
    pub budget_s: u32,
    /// Seconds held back from the margin. 0 when no budget was computed — a
    /// reserve against a projection that does not exist would be theatre.
    pub reserve_s: u32,
    /// The cut-off margin the budget was cut from, before the reserve; `None`
    /// exactly when the projection was withheld.
    pub margin_s: Option<i32>,
    /// The pace the projection used — the slower of the two fed in. `None` when
    /// neither was usable, which is one of the two reasons for
    /// [`SleepStatus::Unknown`] and the one the runner can fix by running.
    pub pace_s_per_km: Option<f64>,
    /// Distance from the runner to the cut-off the budget is measured against,
    /// metres; 0 when there is none. Reported even when the projection is
    /// withheld, exactly as [`crate::cutoff_eta::CutoffEta::distance_to_m`] is.
    pub distance_to_m: f64,
    /// The cut-off's limit is already in the past. Distinct from a merely
    /// exhausted budget: no amount of moving faster recovers it.
    pub limit_passed: bool,
}

impl Default for SleepBudget {
    fn default() -> Self {
        SleepBudget {
            status: SleepStatus::Unknown,
            budget_s: 0,
            reserve_s: 0,
            margin_s: None,
            pace_s_per_km: None,
            distance_to_m: 0.0,
            limit_passed: false,
        }
    }
}

impl SleepBudget {
    /// The budget in whole minutes — the hero's number — or `None` whenever
    /// there is no positive budget to show.
    ///
    /// **Floored, not rounded.** A 9 min 59 s budget shown as 10 would hand the
    /// runner a minute the race has not got; the same value shown as 9 costs
    /// them 59 seconds of sleep. Only one of those two errors ends a race.
    pub fn budget_min(&self) -> Option<u32> {
        (self.status == SleepStatus::Budget).then_some(self.budget_s / 60)
    }
}

/// The slower (numerically larger) of two paces, ignoring any that is not a
/// finite positive; `None` when neither is usable.
///
/// Both inputs are seconds per kilometre. See the module docs for why the
/// slower one is the right input to a sleep budget.
pub fn conservative_pace_s_per_km(recent: Option<f64>, race: Option<f64>) -> Option<f64> {
    let usable = |p: Option<f64>| p.filter(|p| p.is_finite() && *p > 0.0);
    match (usable(recent), usable(race)) {
        (Some(a), Some(b)) => Some(if a >= b { a } else { b }),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    }
}

/// The reserve to hold back from a margin, given the seconds still needed to
/// reach the cut-off. Rounds up — the reserve is the term biased toward waking
/// early.
fn reserve_s(time_needed_s: f64) -> u32 {
    let proportional = SLEEP_RESERVE_FRACTION * time_needed_s;
    let floor = f64::from(SLEEP_RESERVE_FLOOR_S);
    let held = if proportional.is_finite() && proportional > floor {
        proportional
    } else {
        floor
    };
    let ceiled = libm::ceil(held);
    if ceiled >= f64::from(u32::MAX) {
        u32::MAX
    } else {
        ceiled as u32
    }
}

/// How long the runner may sleep and still make the next cut-off.
///
/// `legs` need not be sorted — leg selection is [`next_cutoff_eta`]'s, called
/// once with the conservative pace. `stale` is the same lost-signal flag the
/// cut-off ETA takes, and has the same effect: no projection, no budget.
pub fn sleep_budget(
    dist_along_route_m: f64,
    elapsed_s: u32,
    recent_pace_s_per_km: Option<f64>,
    race_pace_s_per_km: Option<f64>,
    stale: bool,
    legs: &[CutoffLeg],
) -> SleepBudget {
    let pace = conservative_pace_s_per_km(recent_pace_s_per_km, race_pace_s_per_km);
    let eta = next_cutoff_eta(dist_along_route_m, elapsed_s, pace, stale, legs);

    let base = SleepBudget {
        pace_s_per_km: pace,
        distance_to_m: eta.distance_to_m,
        limit_passed: eta.limit_passed,
        ..Default::default()
    };

    if !eta.has_cutoff {
        return SleepBudget {
            status: SleepStatus::NoCutoff,
            ..base
        };
    }

    // A limit already behind the clock is settled, not unknown — the answer is
    // "do not lie down" whether or not a pace exists to project with, and
    // reporting it as unknown would leave the runner to guess.
    if eta.limit_passed {
        return SleepBudget {
            status: SleepStatus::NoBudget,
            margin_s: eta.margin_s,
            ..base
        };
    }

    let (Some(margin_s), Some(pace)) = (eta.margin_s, pace) else {
        return base;
    };

    let time_needed_s = (eta.distance_to_m / 1000.0) * pace;
    let reserve = reserve_s(time_needed_s);
    let budget = f64::from(margin_s) - f64::from(reserve);

    if budget < f64::from(MIN_SLEEP_BUDGET_S) {
        return SleepBudget {
            status: SleepStatus::NoBudget,
            reserve_s: reserve,
            margin_s: Some(margin_s),
            ..base
        };
    }

    let budget_s = if budget >= f64::from(u32::MAX) {
        u32::MAX
    } else {
        budget as u32
    };
    SleepBudget {
        status: SleepStatus::Budget,
        budget_s,
        reserve_s: reserve,
        margin_s: Some(margin_s),
        ..base
    }
}

const _: () = {
    assert!(NO_WAKE_NOTICE.len() <= crate::face::COLS);
};

#[cfg(test)]
mod tests {
    use super::*;

    /// A cut-off 10 km further on, four hours into the race.
    const AID: CutoffLeg = CutoffLeg {
        cum_dist_m: 20_000.0,
        limit_elapsed_s: 14_400,
    };
    const FINISH: CutoffLeg = CutoffLeg {
        cum_dist_m: 40_000.0,
        limit_elapsed_s: 40_000,
    };

    /// 10 km along at 2:00:00 elapsed, both clocks reading `pace`, fresh fix.
    fn budget(pace: Option<f64>, legs: &[CutoffLeg]) -> SleepBudget {
        sleep_budget(10_000.0, 7_200, pace, pace, false, legs)
    }

    // ─────────── the budget itself ───────────

    #[test]
    fn the_budget_is_the_margin_less_the_reserve() {
        // 14 400 limit − 7 200 elapsed = 7 200 s for 10 km. At 600 s/km the leg
        // needs 6 000 s, leaving a 1 200 s margin; the reserve is the 1 800 s
        // floor (25 % of 6 000 = 1 500, under it), so nothing is left.
        let b = budget(Some(600.0), &[AID, FINISH]);
        assert_eq!(b.margin_s, Some(1_200));
        assert_eq!(b.reserve_s, 1_800);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert_eq!(b.budget_s, 0);
    }

    #[test]
    fn a_comfortable_margin_buys_a_nap() {
        // 300 s/km over 10 km needs 3 000 s, leaving 4 200 s of margin; the
        // reserve is max(1 800, 750) = 1 800, so 2 400 s = 40 minutes.
        let b = budget(Some(300.0), &[AID, FINISH]);
        assert_eq!(b.margin_s, Some(4_200));
        assert_eq!(b.reserve_s, 1_800);
        assert_eq!(b.status, SleepStatus::Budget);
        assert_eq!(b.budget_s, 2_400);
        assert_eq!(b.budget_min(), Some(40));
    }

    #[test]
    fn a_long_leg_holds_back_a_proportional_reserve() {
        // 186 km still to run at 300 s/km needs 55 800 s; a quarter of that is
        // 13 950 s, far past the 1 800 s floor, so the proportional term rules.
        let leg = CutoffLeg {
            cum_dist_m: 386_000.0,
            limit_elapsed_s: 400_000,
        };
        let b = sleep_budget(200_000.0, 200_000, Some(300.0), Some(300.0), false, &[leg]);
        assert_eq!(b.margin_s, Some(144_200));
        assert_eq!(b.reserve_s, 13_950);
        assert_eq!(b.budget_s, 130_250);
        assert_eq!(b.status, SleepStatus::Budget);
    }

    #[test]
    fn the_reserve_never_falls_below_the_tight_span() {
        // 50 m to go: the proportional term is seconds, the floor is what holds.
        let b = sleep_budget(19_950.0, 7_200, Some(300.0), Some(300.0), false, &[AID]);
        assert_eq!(b.reserve_s, SLEEP_RESERVE_FLOOR_S);
        assert_eq!(SLEEP_RESERVE_FLOOR_S, CUTOFF_TIGHT_S);
    }

    // ─────────── every term can be unknown ───────────

    #[test]
    fn a_stale_fix_yields_no_number() {
        let b = sleep_budget(10_000.0, 7_200, Some(300.0), Some(300.0), true, &[AID]);
        assert_eq!(b.status, SleepStatus::Unknown);
        assert_eq!(b.budget_s, 0);
        assert_eq!(b.budget_min(), None);
        assert_eq!(b.margin_s, None);
        assert_eq!(b.reserve_s, 0);
        // The checkpoint is still reported, as the cut-off page reports it.
        assert!((b.distance_to_m - 10_000.0).abs() < 1e-9);
    }

    #[test]
    fn no_pace_at_all_yields_no_number() {
        let b = sleep_budget(10_000.0, 7_200, None, None, false, &[AID]);
        assert_eq!(b.status, SleepStatus::Unknown);
        assert_eq!(b.pace_s_per_km, None);
        assert_eq!(b.margin_s, None);
    }

    #[test]
    fn a_corrupt_pace_yields_no_number() {
        // The web helper's `Number.isFinite` gate, inherited: an infinite or NaN
        // pace must not saturate into a plausible count of minutes.
        for p in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 0.0, -5.0] {
            let b = budget(Some(p), &[AID]);
            assert_eq!(b.status, SleepStatus::Unknown, "pace {p} projected");
            assert_eq!(b.budget_min(), None);
        }
    }

    #[test]
    fn no_cutoff_ahead_is_settled_not_unknown() {
        let b = sleep_budget(
            45_000.0,
            7_200,
            Some(300.0),
            Some(300.0),
            false,
            &[AID, FINISH],
        );
        assert_eq!(b.status, SleepStatus::NoCutoff);
        assert_eq!(b.budget_min(), None);
        assert_eq!(b.distance_to_m, 0.0);
    }

    #[test]
    fn an_empty_course_has_no_cutoff() {
        let b = budget(Some(300.0), &[]);
        assert_eq!(b.status, SleepStatus::NoCutoff);
    }

    #[test]
    fn a_passed_limit_is_no_budget_even_with_no_pace() {
        // Behind the limit, the answer is known — do not lie down — so it must
        // not degrade to `--` merely because the pace is missing.
        let b = sleep_budget(10_000.0, 20_000, None, None, false, &[AID]);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert!(b.limit_passed);
        assert_eq!(b.budget_min(), None);
    }

    #[test]
    fn a_passed_limit_with_a_pace_is_still_no_budget() {
        let b = sleep_budget(10_000.0, 20_000, Some(300.0), Some(300.0), false, &[AID]);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert!(b.limit_passed);
    }

    // ─────────── conservatism ───────────

    #[test]
    fn the_projection_uses_the_slower_of_the_two_paces() {
        // Moving pace 300, race pace 400 (the stops so far): the budget must be
        // the one 400 implies, not the flattering one.
        let mixed = sleep_budget(10_000.0, 7_200, Some(300.0), Some(400.0), false, &[AID]);
        let slow = sleep_budget(10_000.0, 7_200, Some(400.0), Some(400.0), false, &[AID]);
        assert_eq!(mixed.pace_s_per_km, Some(400.0));
        assert_eq!(mixed.budget_s, slow.budget_s);
        assert!(mixed.budget_s < budget(Some(300.0), &[AID]).budget_s);
    }

    #[test]
    fn conservative_pace_prefers_the_slower_and_tolerates_a_missing_one() {
        assert_eq!(
            conservative_pace_s_per_km(Some(300.0), Some(400.0)),
            Some(400.0)
        );
        assert_eq!(
            conservative_pace_s_per_km(Some(500.0), Some(400.0)),
            Some(500.0)
        );
        assert_eq!(conservative_pace_s_per_km(Some(300.0), None), Some(300.0));
        assert_eq!(conservative_pace_s_per_km(None, Some(400.0)), Some(400.0));
        assert_eq!(conservative_pace_s_per_km(None, None), None);
        assert_eq!(
            conservative_pace_s_per_km(Some(f64::NAN), Some(400.0)),
            Some(400.0)
        );
        assert_eq!(conservative_pace_s_per_km(Some(f64::INFINITY), None), None);
        assert_eq!(conservative_pace_s_per_km(Some(0.0), Some(-1.0)), None);
    }

    #[test]
    fn the_budget_floors_to_the_minute_rather_than_rounding_up() {
        // Contrive a surplus over the reserve of 119 s: 1 minute 59 seconds of
        // sleep must read as 1, never 2.
        let leg = CutoffLeg {
            cum_dist_m: 20_000.0,
            limit_elapsed_s: 7_200 + 6_000 + 1_800 + 119,
        };
        let b = budget(Some(600.0), &[leg]);
        assert_eq!(b.budget_s, 119);
        assert_eq!(b.budget_min(), Some(1));
    }

    #[test]
    fn a_sub_minute_budget_settles_rather_than_showing_zero() {
        let leg = CutoffLeg {
            cum_dist_m: 20_000.0,
            limit_elapsed_s: 7_200 + 6_000 + 1_800 + 59,
        };
        let b = budget(Some(600.0), &[leg]);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert_eq!(b.budget_min(), None);
        assert_eq!(b.budget_s, 0);
    }

    #[test]
    fn exactly_one_minute_is_a_budget() {
        let leg = CutoffLeg {
            cum_dist_m: 20_000.0,
            limit_elapsed_s: 7_200 + 6_000 + 1_800 + 60,
        };
        let b = budget(Some(600.0), &[leg]);
        assert_eq!(b.status, SleepStatus::Budget);
        assert_eq!(b.budget_min(), Some(1));
    }

    #[test]
    fn the_budget_counts_itself_down_as_the_race_clock_runs() {
        // The nap needs no timer: the same inputs half an hour later, with the
        // runner stationary, yield a budget 1 800 s smaller.
        let now = sleep_budget(10_000.0, 7_200, Some(300.0), Some(300.0), false, &[AID]);
        let later = sleep_budget(10_000.0, 9_000, Some(300.0), Some(300.0), false, &[AID]);
        assert_eq!(now.budget_s - later.budget_s, 1_800);
    }

    #[test]
    fn a_nap_that_outlasts_the_budget_reaches_no_budget_not_a_negative() {
        let b = sleep_budget(10_000.0, 12_000, Some(300.0), Some(300.0), false, &[AID]);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert_eq!(b.budget_s, 0);
        assert!(b.margin_s.unwrap() < SLEEP_RESERVE_FLOOR_S as i32);
    }

    #[test]
    fn an_absurd_pace_saturates_into_no_budget_rather_than_panicking() {
        let b = budget(Some(1e12), &[AID]);
        assert_eq!(b.status, SleepStatus::NoBudget);
        assert_eq!(b.budget_s, 0);
    }

    #[test]
    fn the_nearest_cutoff_ahead_is_the_one_the_budget_is_measured_against() {
        let b = sleep_budget(
            5_000.0,
            7_200,
            Some(300.0),
            Some(300.0),
            false,
            &[FINISH, AID],
        );
        assert!((b.distance_to_m - 15_000.0).abs() < 1e-9);
    }

    #[test]
    fn the_default_budget_shows_nothing() {
        let b = SleepBudget::default();
        assert_eq!(b.status, SleepStatus::Unknown);
        assert_eq!(b.budget_min(), None);
    }

    #[test]
    fn the_no_wake_notice_fits_the_panel_and_names_the_watch() {
        assert_eq!(NO_WAKE_NOTICE.len(), crate::face::COLS);
        assert!(NO_WAKE_NOTICE.contains("CANNOT"));
    }
}
