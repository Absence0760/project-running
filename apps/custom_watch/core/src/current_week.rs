//! Current-calendar-week strip — bucket a runner's activities onto the seven
//! days of the REAL calendar week containing "now", honouring the `week_start`
//! preference (Sunday- vs Monday-first) with local-day bucketing.
//!
//! Parity port of web `apps/web/src/lib/training/current_week.ts` (twin of
//! `apps/mobile_android/lib/widgets/current_week.dart`) — the dashboard
//! "This Week" ribbon aggregation. Distinct from the plan-anchored
//! current-week strip, which windows on `start_date + week_index*7`.
//!
//! The one representational change from the web/Dart copies: those parse each
//! activity's `started_at` ISO timestamp into a local `yyyy-mm-dd` key and walk
//! the week with `Date` arithmetic, deriving the day-of-week from `Date.getDay`.
//! Neither ISO parsing nor a timezone database belongs in a `no_std` firmware
//! core, so here an activity carries a plain **day index** ([`WeekActivity::day`])
//! and "now" is an integer `now_day` — calendar days since the Unix epoch
//! (1970-01-01, a Thursday), in the runner's local zone, exactly the integer the
//! phone derives from a local date key. Pinning the epoch (unlike
//! `training_load`, which only needs relative differences) lets the module
//! recover the day-of-week with [`dow_of`] instead of a timezone DB, so the
//! window edges and each cell's `dow` match the web numbers. Every test maps a
//! web `Date` offset to a day-index offset one-for-one.
//!
//! Pure logic, no peripherals, no allocator. `f64` distance is kept (web uses
//! `number`) so sums match.

/// Which weekday the calendar week starts on. Mirrors the web
/// `'monday' | 'sunday'` union; Monday is the default, as on web.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum WeekStart {
    Sunday,
    #[default]
    Monday,
}

/// The minimum an activity exposes to the strip: which local day it happened on
/// (a day index; see the module docs) and how far it went, in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WeekActivity {
    pub day: i32,
    pub distance_m: f64,
}

/// One day of the strip. `dow` is the JS day-of-week (0 = Sunday) so the caller
/// can index localized weekday labels; `distance_m` / `count` aggregate the
/// day's activities; `is_today` / `is_future` drive the cell's highlight +
/// dimming.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct WeekDay {
    pub day: i32,
    pub dow: u8,
    pub distance_m: f64,
    pub count: u32,
    pub is_today: bool,
    pub is_future: bool,
}

/// The whole strip: its seven ordered days plus the week's running totals, so a
/// header can show "12.4 km / 3 activities" without re-summing.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct CurrentWeek {
    pub days: [WeekDay; 7],
    pub total_distance_m: f64,
    pub total_count: u32,
}

/// JS day-of-week (0 = Sunday .. 6 = Saturday) for a day index. 1970-01-01 is
/// day 0 and a Thursday (`getDay` 4), so `(day + 4) mod 7` — `rem_euclid` keeps
/// it non-negative for pre-epoch indices.
pub fn dow_of(day: i32) -> u8 {
    (day + 4).rem_euclid(7) as u8
}

/// Build the current calendar week from `activities`, bucketing each onto its
/// day index. Activities outside the week — or with a non-positive / non-finite
/// distance — are ignored. `now_day` is today's day index (see the module docs).
pub fn current_week(
    activities: &[WeekActivity],
    week_start: WeekStart,
    now_day: i32,
) -> CurrentWeek {
    let offset = match week_start {
        WeekStart::Sunday => dow_of(now_day) as i32,
        WeekStart::Monday => (dow_of(now_day) as i32 + 6) % 7,
    };
    let start_day = now_day - offset;

    let days: [WeekDay; 7] = core::array::from_fn(|i| {
        let day = start_day + i as i32;
        let mut distance_m = 0.0;
        let mut count = 0u32;
        for a in activities {
            // `> 0.0` rejects zero, negative, AND non-finite (NaN) distances —
            // the web guard's `!(dist > 0)`, phrased positively for clippy.
            if a.day == day && a.distance_m > 0.0 {
                distance_m += a.distance_m;
                count += 1;
            }
        }
        WeekDay {
            day,
            dow: dow_of(day),
            distance_m,
            count,
            is_today: day == now_day,
            is_future: day > now_day,
        }
    });

    let mut total_distance_m = 0.0;
    let mut total_count = 0u32;
    for d in &days {
        total_distance_m += d.distance_m;
        total_count += d.count;
    }

    CurrentWeek {
        days,
        total_distance_m,
        total_count,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/current_week.test.ts` — same
    /// scenarios, same expected values, with each web `Date` mapped to its day
    /// index. 2026-06-10 is a Wednesday; its Unix-epoch day index is 20_614, so
    /// `dow_of(REF) == 3` (Wed) by construction.
    const REF: i32 = 20_614;

    fn days_of(w: &CurrentWeek) -> [i32; 7] {
        core::array::from_fn(|i| w.days[i].day)
    }

    #[test]
    fn monday_start_window_spans_mon_sun_containing_now() {
        let w = current_week(&[], WeekStart::Monday, REF);
        assert_eq!(
            days_of(&w),
            [REF - 2, REF - 1, REF, REF + 1, REF + 2, REF + 3, REF + 4]
        );
        assert_eq!(w.days.len(), 7);
    }

    #[test]
    fn sunday_start_window_spans_sun_sat_containing_now() {
        let w = current_week(&[], WeekStart::Sunday, REF);
        assert_eq!(
            days_of(&w),
            [REF - 3, REF - 2, REF - 1, REF, REF + 1, REF + 2, REF + 3]
        );
    }

    #[test]
    fn dow_is_js_day_of_week_for_each_cell() {
        let w = current_week(&[], WeekStart::Monday, REF);
        let dows: [u8; 7] = core::array::from_fn(|i| w.days[i].dow);
        assert_eq!(dows, [1, 2, 3, 4, 5, 6, 0]);
    }

    #[test]
    fn flags_today_and_future_days() {
        let w = current_week(&[], WeekStart::Monday, REF);
        let today = w.days.iter().find(|d| d.day == REF).unwrap();
        assert!(today.is_today);
        assert!(!today.is_future);
        assert!(!w.days.iter().find(|d| d.day == REF - 1).unwrap().is_future);
        assert!(w.days.iter().find(|d| d.day == REF + 1).unwrap().is_future);
    }

    #[test]
    fn buckets_activities_onto_their_day_and_sums_distance_and_count() {
        let acts = [
            WeekActivity {
                day: REF - 2,
                distance_m: 5000.0,
            },
            WeekActivity {
                day: REF - 2,
                distance_m: 3000.0,
            },
            WeekActivity {
                day: REF,
                distance_m: 10_000.0,
            },
        ];
        let w = current_week(&acts, WeekStart::Monday, REF);
        let mon = w.days.iter().find(|d| d.day == REF - 2).unwrap();
        assert_eq!(mon.distance_m, 8000.0);
        assert_eq!(mon.count, 2);
        let wed = w.days.iter().find(|d| d.day == REF).unwrap();
        assert_eq!(wed.distance_m, 10_000.0);
        assert_eq!(wed.count, 1);
        assert_eq!(w.total_distance_m, 18_000.0);
        assert_eq!(w.total_count, 3);
    }

    #[test]
    fn ignores_activities_outside_the_current_week() {
        let acts = [
            WeekActivity {
                day: REF - 9,
                distance_m: 5000.0,
            },
            WeekActivity {
                day: REF + 6,
                distance_m: 5000.0,
            },
            WeekActivity {
                day: REF - 1,
                distance_m: 4000.0,
            },
        ];
        let w = current_week(&acts, WeekStart::Monday, REF);
        assert_eq!(w.total_distance_m, 4000.0);
        assert_eq!(w.total_count, 1);
    }

    #[test]
    fn ignores_zero_or_negative_distance_activities() {
        let acts = [
            WeekActivity {
                day: REF - 1,
                distance_m: 0.0,
            },
            WeekActivity {
                day: REF - 1,
                distance_m: -100.0,
            },
            WeekActivity {
                day: REF - 1,
                distance_m: 2000.0,
            },
        ];
        let w = current_week(&acts, WeekStart::Monday, REF);
        assert_eq!(w.total_distance_m, 2000.0);
        assert_eq!(w.total_count, 1);
    }

    #[test]
    fn ignores_activities_with_a_non_finite_distance() {
        // The no_std analog of the web "unparseable timestamp" case: the day
        // index is parsed upstream on the phone, so a malformed activity can
        // only reach the core as a bad distance. `!(d > 0)` drops NaN too.
        let acts = [
            WeekActivity {
                day: REF - 1,
                distance_m: f64::NAN,
            },
            WeekActivity {
                day: REF - 1,
                distance_m: 3000.0,
            },
        ];
        let w = current_week(&acts, WeekStart::Monday, REF);
        assert_eq!(w.total_distance_m, 3000.0);
        assert_eq!(w.total_count, 1);
    }

    #[test]
    fn a_local_day_activity_buckets_onto_its_own_day_not_the_next() {
        // Web guards a 23:30 local run from rolling to the next UTC day. The
        // day index already encodes the LOCAL calendar day (collapsed on the
        // phone), so a Tuesday activity stays on Tuesday here by construction.
        let acts = [WeekActivity {
            day: REF - 1,
            distance_m: 6000.0,
        }];
        let w = current_week(&acts, WeekStart::Monday, REF);
        assert_eq!(
            w.days.iter().find(|d| d.day == REF - 1).unwrap().distance_m,
            6000.0
        );
        assert_eq!(
            w.days.iter().find(|d| d.day == REF).unwrap().distance_m,
            0.0
        );
    }

    #[test]
    fn empty_input_yields_a_zeroed_seven_day_week() {
        let w = current_week(&[], WeekStart::Monday, REF);
        assert_eq!(w.total_distance_m, 0.0);
        assert_eq!(w.total_count, 0);
        assert!(w.days.iter().all(|d| d.distance_m == 0.0 && d.count == 0));
    }
}
