//! Spectator freshness: how old the last live ping is, and whether it is stale
//! enough that the position can no longer be trusted as the runner's *current*
//! location. A lost-signal runner must read stale, not as a permanently-fresh
//! "LIVE" dot — the difference between "is my person OK?" answered honestly and
//! a false reassurance off an hours-old fix.
//!
//! A parity port of web `runs/live_freshness.ts` `freshnessFor` (twin of
//! `live_freshness.dart`): an age clamp + a stale flag + a coarsened display
//! bucket. The web/Dart pair carries two timestamps (`sentAtMs`, `nowMs`) and
//! subtracts them; on a `no_std` device the honest input is a single monotonic
//! **age in seconds** — a negative age models a future-dated ping from clock
//! skew and clamps to 0, exactly as web's `Math.max(0, nowMs - sentAtMs)` does.
//! The display bucket is returned as an enum (no language) so each platform
//! localizes it identically. Pure integer logic, no floats, no allocator.

/// A ping older than this is treated as stale. 90 s ~= 18 missed 5 s
/// broadcaster pings: long enough to ride out ordinary cellular flakiness,
/// short enough that a real signal loss surfaces within a minute and a half.
/// The web twin's `LIVE_STALE_AFTER_MS` is the same span in milliseconds.
pub const LIVE_STALE_AFTER_S: u32 = 90;

/// Coarsened time bucket for display; pair with [`Freshness::value`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum FreshnessBucket {
    Now,
    Seconds,
    Minutes,
    Hours,
    Days,
}

/// An honest age + stale verdict + display bucket for a live ping.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Freshness {
    /// Age of the last ping in seconds, clamped to `>= 0` (a future-dated ping
    /// from clock skew reads as "just now", never a negative age).
    pub age_s: u32,
    /// True once `age_s >= stale_after_s` — the caller should stop presenting
    /// the position as live-current.
    pub stale: bool,
    /// Coarsened time bucket for display; pair with `value`.
    pub bucket: FreshnessBucket,
    /// The number to show for the bucket (e.g. bucket `Minutes`, value 3 →
    /// "Updated 3 min ago"). 0 for `Now`.
    pub value: u32,
}

/// Classify a live ping's freshness from its monotonic age in seconds. A
/// negative age (future-dated ping / clock skew) clamps to 0. `stale_after_s`
/// is the staleness threshold; pass [`LIVE_STALE_AFTER_S`] for the default.
pub fn freshness_for(age_s: i64, stale_after_s: u32) -> Freshness {
    let s = age_s.max(0) as u32;
    let stale = s >= stale_after_s;
    let (bucket, value) = if s < 10 {
        (FreshnessBucket::Now, 0)
    } else if s < 60 {
        (FreshnessBucket::Seconds, s)
    } else {
        let min = s / 60;
        if min < 60 {
            (FreshnessBucket::Minutes, min)
        } else {
            let h = min / 60;
            if h < 24 {
                (FreshnessBucket::Hours, h)
            } else {
                (FreshnessBucket::Days, h / 24)
            }
        }
    };
    Freshness {
        age_s: s,
        stale,
        bucket,
        value,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh(age_s: i64) -> Freshness {
        freshness_for(age_s, LIVE_STALE_AFTER_S)
    }

    #[test]
    fn future_dated_ping_clamps_to_age_zero_never_negative() {
        let f = fresh(-5);
        assert_eq!(f.age_s, 0);
        assert!(!f.stale);
        assert_eq!(f.bucket, FreshnessBucket::Now);
    }

    #[test]
    fn stale_threshold_is_inclusive_at_the_boundary() {
        let just_fresh = fresh((LIVE_STALE_AFTER_S - 1) as i64);
        assert!(
            !just_fresh.stale,
            "one second under the threshold is still fresh"
        );
        let just_stale = fresh(LIVE_STALE_AFTER_S as i64);
        assert!(just_stale.stale, "exactly at the threshold is stale");
    }

    #[test]
    fn a_long_no_signal_stretch_is_honestly_stale_not_a_fresh_live_dot() {
        let eighteen_hours = fresh(18 * 3600);
        assert!(eighteen_hours.stale);
        assert_eq!(eighteen_hours.bucket, FreshnessBucket::Hours);
        assert_eq!(eighteen_hours.value, 18);
    }

    #[test]
    fn bucket_boundaries() {
        let pick = |age: i64| {
            let f = fresh(age);
            (f.bucket, f.value)
        };
        assert_eq!(pick(9), (FreshnessBucket::Now, 0));
        assert_eq!(pick(10), (FreshnessBucket::Seconds, 10));
        assert_eq!(pick(59), (FreshnessBucket::Seconds, 59));
        assert_eq!(pick(60), (FreshnessBucket::Minutes, 1));
        assert_eq!(pick(59 * 60), (FreshnessBucket::Minutes, 59));
        assert_eq!(pick(3600), (FreshnessBucket::Hours, 1));
        assert_eq!(pick(23 * 3600), (FreshnessBucket::Hours, 23));
        assert_eq!(pick(24 * 3600), (FreshnessBucket::Days, 1));
        assert_eq!(pick(50 * 3600), (FreshnessBucket::Days, 2));
    }

    #[test]
    fn an_exactly_now_ping_reads_as_fresh_now() {
        let f = fresh(0);
        assert_eq!(f.age_s, 0);
        assert_eq!(f.bucket, FreshnessBucket::Now);
        assert!(!f.stale);
    }
}
