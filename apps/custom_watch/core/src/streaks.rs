//! Run-streak computation — the longest and current runs of consecutive local
//! days that each contain at least one run.
//!
//! Strava-style grace rule: a missing today does not break the streak — it
//! stays alive as long as yesterday had a run, so the morning after a late run
//! still shows the streak until end-of-today. The streak only resets when a
//! full day goes by without a run.
//!
//! Parity port of web `runs/streaks.ts` `computeRunStreaks` (twin of
//! `apps/mobile_android/lib/streaks.dart`) — keep the algorithm, edge cases,
//! and test count in lockstep.
//!
//! The one representational change from the web/Dart copies: those bucketise
//! each run's `Date` into a local `yyyy-mm-dd` key, clamp to today, and walk
//! days with DST-safe `Date` arithmetic. Neither ISO parsing nor a timezone
//! database belongs in a `no_std` firmware core, so here each run carries a
//! plain **day index** — a calendar day count in the runner's local zone,
//! exactly the integer the phone derives from a local date key — and "today"
//! is the integer `today_day`. Consecutiveness is then just `d == prev + 1`
//! and the grace / walk-back step is `anchor - 1`: DST-safe by construction,
//! with no 23/25-hour day to misalign the keys (the gotcha the web helper's
//! `previousLocalDay` documents). Every web `Date` maps to a day-index offset
//! one-for-one.
//!
//! Pure logic, no peripherals, no allocator.

use heapless::Vec;

/// Cap on distinct run days considered. A streak core is fed a bounded window
/// of run starts; days beyond this are ignored (the web `Set` is unbounded).
pub const MAX_STREAK_DAYS: usize = 512;

/// The two streak counts. `best >= current` always.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RunStreaks {
    /// Days in the user's current active streak (0 if broken).
    pub current: u32,
    /// Longest historical streak.
    pub best: u32,
}

/// Compute `{ current, best }` from a list of run day indices. Order does not
/// matter — the helper dedupes and sorts internally. Days after `today_day`
/// are ignored so a phone clock running ahead can't add a phantom future day.
pub fn compute_run_streaks(run_days: &[i32], today_day: i32) -> RunStreaks {
    let mut days: Vec<i32, MAX_STREAK_DAYS> = Vec::new();
    for &d in run_days {
        if d <= today_day && !days.contains(&d) && days.push(d).is_err() {
            break;
        }
    }
    if days.is_empty() {
        return RunStreaks {
            current: 0,
            best: 0,
        };
    }
    days.sort_unstable();

    let mut best: u32 = 1;
    let mut run: u32 = 1;
    for i in 1..days.len() {
        if days[i] == days[i - 1] + 1 {
            run += 1;
            if run > best {
                best = run;
            }
        } else {
            run = 1;
        }
    }

    let contains = |d: i32| days.binary_search(&d).is_ok();
    let mut anchor = today_day;
    if !contains(anchor) {
        anchor -= 1;
        if !contains(anchor) {
            return RunStreaks { current: 0, best };
        }
    }
    let mut current: u32 = 0;
    while contains(anchor) {
        current += 1;
        anchor -= 1;
    }
    RunStreaks { current, best }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/runs/streaks.test.ts` — same scenarios, same
    /// expected values, with each web `Date` mapped to a day-index offset from
    /// `T` (the anchor "today", `localNoon(2026, 5, 13)` on web). The absolute
    /// value is irrelevant to streaks; only the relative offsets matter.
    const T: i32 = 20_586;

    #[test]
    fn empty_input_yields_zero() {
        assert_eq!(
            compute_run_streaks(&[], T),
            RunStreaks {
                current: 0,
                best: 0,
            }
        );
    }

    #[test]
    fn single_run_today_is_current_one_best_one() {
        assert_eq!(
            compute_run_streaks(&[T], T),
            RunStreaks {
                current: 1,
                best: 1,
            }
        );
    }

    #[test]
    fn multiple_runs_same_day_count_once() {
        assert_eq!(
            compute_run_streaks(&[T, T, T], T),
            RunStreaks {
                current: 1,
                best: 1,
            }
        );
    }

    #[test]
    fn three_day_streak_ending_today() {
        assert_eq!(
            compute_run_streaks(&[T - 2, T - 1, T], T),
            RunStreaks {
                current: 3,
                best: 3,
            }
        );
    }

    #[test]
    fn strava_grace_missing_today_but_yesterday_present() {
        assert_eq!(
            compute_run_streaks(&[T - 2, T - 1], T),
            RunStreaks {
                current: 2,
                best: 2,
            }
        );
    }

    #[test]
    fn two_consecutive_days_missing_breaks_the_streak() {
        assert_eq!(
            compute_run_streaks(&[T - 4, T - 3], T),
            RunStreaks {
                current: 0,
                best: 2,
            }
        );
    }

    #[test]
    fn best_preserves_a_historical_longer_run() {
        assert_eq!(
            compute_run_streaks(&[T - 42, T - 41, T - 40, T - 39, T - 38, T - 1, T], T),
            RunStreaks {
                current: 2,
                best: 5,
            }
        );
    }

    #[test]
    fn future_dated_runs_are_clamped_to_today() {
        assert_eq!(
            compute_run_streaks(&[T, T + 1, T + 2], T),
            RunStreaks {
                current: 1,
                best: 1,
            }
        );
    }

    #[test]
    fn long_single_streak_current_equals_best() {
        let days: [i32; 30] = core::array::from_fn(|i| T - 29 + i as i32);
        let out = compute_run_streaks(&days, T);
        assert_eq!(out.current, 30);
        assert_eq!(out.best, 30);
    }

    #[test]
    fn input_order_does_not_matter() {
        let ordered = compute_run_streaks(&[T - 2, T - 1, T], T);
        let shuffled = compute_run_streaks(&[T, T - 2, T - 1], T);
        assert_eq!(ordered, shuffled);
    }

    #[test]
    fn month_boundary_is_consecutive() {
        // Apr 30 / May 1 / May 13 → offsets -13, -12, 0.
        assert_eq!(
            compute_run_streaks(&[T - 13, T - 12, T], T),
            RunStreaks {
                current: 1,
                best: 2,
            }
        );
    }

    #[test]
    fn year_boundary_is_consecutive() {
        // Dec 31 / Jan 1, today Jan 1 → offsets -1, 0.
        assert_eq!(
            compute_run_streaks(&[T - 1, T], T),
            RunStreaks {
                current: 2,
                best: 2,
            }
        );
    }

    #[test]
    fn gap_of_exactly_one_day_breaks_the_streak() {
        assert_eq!(
            compute_run_streaks(&[T - 2, T], T),
            RunStreaks {
                current: 1,
                best: 1,
            }
        );
    }

    #[test]
    fn spring_forward_day_plus_next_day_register_as_consecutive() {
        // The web guards a 23-hour DST spring-forward day. Day indices are
        // integer local calendar days, so the pair is exactly one apart.
        assert_eq!(
            compute_run_streaks(&[T - 1, T], T),
            RunStreaks {
                current: 2,
                best: 2,
            }
        );
    }

    #[test]
    fn fall_back_day_plus_next_day_register_as_consecutive() {
        // Likewise the 25-hour DST fall-back day.
        assert_eq!(
            compute_run_streaks(&[T - 1, T], T),
            RunStreaks {
                current: 2,
                best: 2,
            }
        );
    }

    #[test]
    fn day_index_arithmetic_is_dst_safe_by_construction() {
        // The web guard reads streaks.ts to forbid subtracting 86_400_000 ms
        // from a Date (which crosses a DST boundary as a 23/25-hour day and
        // misaligns the local-day keys). This port has no millisecond
        // arithmetic to guard: the grace step and walk-back are `anchor - 1`
        // over integer day indices, so a five-day streak walked back across
        // any would-be DST boundary counts exactly five, never four or six.
        let out = compute_run_streaks(&[T - 4, T - 3, T - 2, T - 1, T], T);
        assert_eq!(out.current, 5);
        assert_eq!(out.best, 5);
    }
}
