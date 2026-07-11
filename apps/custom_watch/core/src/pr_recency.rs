//! Plain-relative age of a personal-record date — "today", "3 weeks ago",
//! "2 years ago" — used to soften the PR card for a returning runner, so an
//! all-time best from years back reads as context, not a taunt (comeback
//! persona #28).
//!
//! Parity port of web `runs/pr_recency.ts` `relativeAge` (twin of
//! `apps/mobile_android/lib/pr_recency.dart`) — keep the day thresholds and
//! bucket boundaries in lockstep.
//!
//! Two representational changes from the web/Dart copies. First, they parse the
//! PR's `started_at` ISO timestamp and `Date.now()` into milliseconds and floor
//! their difference into days; a `no_std` core has neither ISO parsing nor a
//! timezone database, so here the PR and "now" arrive as integer **day
//! indices** (calendar days since the Unix epoch in the runner's local zone —
//! exactly the integer the phone derives from a local date key, as in
//! [`current_week`](crate::current_week)) and the day count is their plain
//! difference. Second, the web returns a localized English string; this returns
//! a language-free [`RelativeAge`] enum carrying the bucket count so each
//! platform renders singular/plural itself. The web NaN-guard (an unparseable
//! date yields `''`) maps to a `None` day index yielding `None`.
//!
//! Pure integer logic, no floats, no allocator — like the rest of `core`.

/// The relative-age bucket for a PR date, with its count. `Weeks(1)` /
/// `Months(1)` / `Years(1)` are the web "a week/month/year ago" singular cases;
/// the caller localizes singular vs plural off the count. `Days` only ever
/// carries 2..=6 (a one-day gap is [`RelativeAge::Yesterday`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RelativeAge {
    Today,
    Yesterday,
    Days(u32),
    Weeks(u32),
    Months(u32),
    Years(u32),
}

/// The relative age of a PR on `then_day` as seen on `now_day`, both day
/// indices (see the module docs). `None` `then_day` — the phone could not parse
/// the timestamp — yields `None`, mirroring the web empty-string guard.
pub fn relative_age(then_day: Option<i32>, now_day: i32) -> Option<RelativeAge> {
    let then = then_day?;
    let days = now_day - then;
    Some(if days <= 0 {
        RelativeAge::Today
    } else if days == 1 {
        RelativeAge::Yesterday
    } else if days < 7 {
        RelativeAge::Days(days as u32)
    } else if days < 31 {
        RelativeAge::Weeks((days / 7) as u32)
    } else if days < 365 {
        RelativeAge::Months((days / 30) as u32)
    } else {
        RelativeAge::Years((days / 365) as u32)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm) so
    /// each test date converts to the same day index the phone would derive
    /// from a local date key — the day count then matches the web ms floor.
    fn days_from_civil(y: i32, m: i32, d: i32) -> i32 {
        let y = if m <= 2 { y - 1 } else { y };
        let era = if y >= 0 { y } else { y - 399 } / 400;
        let yoe = y - era * 400;
        let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        era * 146097 + doe - 719468
    }

    /// Mirror of `apps/web/src/lib/runs/pr_recency.test.ts` — same NOW, same
    /// dates, same expected buckets, so the ports can't drift.
    fn now() -> i32 {
        days_from_civil(2026, 5, 1)
    }

    fn day(y: i32, m: i32, d: i32) -> Option<i32> {
        Some(days_from_civil(y, m, d))
    }

    #[test]
    fn today_yesterday_days() {
        let n = now();
        assert_eq!(relative_age(day(2026, 5, 1), n), Some(RelativeAge::Today));
        assert_eq!(
            relative_age(day(2026, 4, 30), n),
            Some(RelativeAge::Yesterday)
        );
        assert_eq!(
            relative_age(day(2026, 4, 28), n),
            Some(RelativeAge::Days(3))
        );
    }

    #[test]
    fn weeks_months_years() {
        let n = now();
        assert_eq!(
            relative_age(day(2026, 4, 20), n),
            Some(RelativeAge::Weeks(1))
        );
        assert_eq!(
            relative_age(day(2026, 4, 1), n),
            Some(RelativeAge::Weeks(4))
        );
        assert_eq!(
            relative_age(day(2026, 2, 20), n),
            Some(RelativeAge::Months(2))
        );
        assert_eq!(
            relative_age(day(2024, 4, 15), n),
            Some(RelativeAge::Years(2))
        );
        assert_eq!(
            relative_age(day(2025, 4, 15), n),
            Some(RelativeAge::Years(1))
        );
    }

    #[test]
    fn invalid_date_yields_none() {
        assert_eq!(relative_age(None, now()), None);
    }
}
