//! Daylight remaining — the sunset/sunrise countdown behind [`crate::page::Page::Daylight`].
//!
//! The solar model is a faithful port of the seasonal half of web
//! `safety/safety_nudge.ts` (`solarDeclinationDeg` + `isSunDown`, the
//! TS↔Dart parity pair): Cooper's declination approximation, solar noon
//! modelled at local 12:00, symmetric sunrise/sunset from the day's
//! half-arc at the standard −0.833° horizon, polar day/night at the
//! `cos H` clamps. It deliberately ignores longitude-within-timezone,
//! equation of time, and DST — up to ~1 h of clock error, exactly the
//! error band the web helper documents — so the countdown is a planning
//! glance ("headlamp in about two hours"), not an almanac. The port is
//! mirrored test-for-test against the web suite's seasonal cases.
//!
//! What the watch adds is input shaping, not algorithm (the § 215
//! precedent): the RMC stream already carries the UTC clock + date and
//! the fix carries latitude, and the phone's `SET1` push carries the
//! timezone offset — [`daylight_at`] extrapolates the fix clock the way
//! the idle face's clock does, shifts it into local civil time (date
//! included: a timezone crosses midnight in both directions), and asks
//! the ported model what the sun does next. No timezone synced, no
//! page — a countdown against the wrong midnight would be off by whole
//! hours, which on this surface is the difference between "sunset after
//! the aid station" and "sunset before it".

use libm::{acos, cos, floor, round, sin};

/// Sun altitude (degrees) at/below which the sun counts as down — the
/// standard sunrise/sunset value (geometric horizon − mean refraction −
/// solar semidiameter). Same constant, same sign, as the web helper.
pub const SUN_DOWN_ALTITUDE_DEG: f64 = -0.833;

const RAD: f64 = core::f64::consts::PI / 180.0;
const MIN_PER_DAY: u32 = 1440;
const SEC_PER_DAY: u32 = 86_400;

/// A civil calendar date. Assembled from the RMC ddmmyy field by
/// [`crate::fix::FixAccumulator`], which owns the plausibility gate — the
/// date math here is total over any in-range month/day but does not try
/// to repair garbage.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Date {
    pub year: u16,
    pub month: u8,
    pub day: u8,
}

fn is_leap(year: u16) -> bool {
    year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
}

fn days_in_month(year: u16, month: u8) -> u8 {
    match month {
        2 => {
            if is_leap(year) {
                29
            } else {
                28
            }
        }
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// 1-based day of year, leap-aware. The month is clamped into 1..=12 so a
/// malformed date degrades to a nearby day instead of indexing garbage —
/// the declination curve moves ~0.4°/day at its steepest, so "nearby" is
/// visually indistinguishable on this surface.
pub fn day_of_year(d: Date) -> u16 {
    let month = d.month.clamp(1, 12);
    let mut doy = u16::from(d.day);
    for m in 1..month {
        doy += u16::from(days_in_month(d.year, m));
    }
    doy
}

/// The next civil day.
pub fn next_day(d: Date) -> Date {
    if d.day < days_in_month(d.year, d.month.clamp(1, 12)) {
        Date {
            day: d.day + 1,
            ..d
        }
    } else if d.month < 12 {
        Date {
            year: d.year,
            month: d.month + 1,
            day: 1,
        }
    } else {
        Date {
            year: d.year + 1,
            month: 1,
            day: 1,
        }
    }
}

/// The previous civil day.
pub fn prev_day(d: Date) -> Date {
    if d.day > 1 {
        Date {
            day: d.day - 1,
            ..d
        }
    } else if d.month > 1 {
        Date {
            year: d.year,
            month: d.month - 1,
            day: days_in_month(d.year, d.month - 1),
        }
    } else {
        Date {
            year: d.year - 1,
            month: 12,
            day: 31,
        }
    }
}

/// Solar declination (degrees) for a 1-based day-of-year — Cooper's
/// approximation, normalised into 1..=365 like the web original so an
/// out-of-range day (a leap year's 366) folds instead of throwing the
/// trig off.
pub fn solar_declination_deg(day_of_year: i32) -> f64 {
    let d = (day_of_year - 1).rem_euclid(365) + 1;
    -23.44 * cos((2.0 * core::f64::consts::PI / 365.0) * (f64::from(d) + 10.0))
}

/// What the sun does at `latitude_deg` on `day_of_year`: rises and sets at
/// the returned local minutes (solar noon at 720, fractional), or never —
/// the two polar cases. A degenerate `cos H` (`NaN`, at the poles) reads
/// as polar night, the web original's fail-safe-dark.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SunTimes {
    PolarDay,
    PolarNight,
    RiseSet { sunrise_min: f64, sunset_min: f64 },
}

pub fn sun_times(latitude_deg: f64, day_of_year: i32) -> SunTimes {
    let decl = solar_declination_deg(day_of_year) * RAD;
    let lat = latitude_deg * RAD;
    let h0 = SUN_DOWN_ALTITUDE_DEG * RAD;
    let cos_h = (sin(h0) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl));
    if cos_h.is_nan() {
        return SunTimes::PolarNight;
    }
    if cos_h <= -1.0 {
        return SunTimes::PolarDay;
    }
    if cos_h >= 1.0 {
        return SunTimes::PolarNight;
    }
    // 4 minutes of clock per degree of hour angle.
    let half_day_min = (acos(cos_h) / RAD) * 4.0;
    SunTimes::RiseSet {
        sunrise_min: 720.0 - half_day_min,
        sunset_min: 720.0 + half_day_min,
    }
}

/// The web `isSunDown`, bit for bit: true when the sun is at/below the
/// horizon constant at `latitude_deg` on `day_of_year` at
/// `now_local_minutes` (normalised into the day like the original).
pub fn is_sun_down(now_local_minutes: i32, latitude_deg: f64, day_of_year: i32) -> bool {
    let m = f64::from(now_local_minutes.rem_euclid(MIN_PER_DAY as i32));
    match sun_times(latitude_deg, day_of_year) {
        SunTimes::PolarDay => false,
        SunTimes::PolarNight => true,
        SunTimes::RiseSet {
            sunrise_min,
            sunset_min,
        } => m < sunrise_min || m >= sunset_min,
    }
}

/// Which sun event the countdown is running toward.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NextSunEvent {
    Sunrise,
    Sunset,
}

/// The Daylight page's numbers: the next event, whole minutes until it
/// (floored — the page must never promise light it may not have), the
/// event's local clock minute, and today's total day length.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DaylightView {
    pub event: NextSunEvent,
    pub countdown_min: u32,
    pub event_clock_min: u16,
    pub daylight_min: u16,
}

/// The page's state for one local instant. After sunset the countdown
/// crosses midnight to *tomorrow's* sunrise (its own declination day); a
/// tomorrow that answers polar reports that polar state — the model
/// cannot place a rise time inside a polar transition, and a wrong clock
/// time is worse than the honest season label.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Daylight {
    PolarDay,
    PolarNight,
    Sun(DaylightView),
}

pub fn daylight(now_local_min: u32, latitude_deg: f64, day_of_year: i32) -> Daylight {
    let m = f64::from(now_local_min % MIN_PER_DAY);
    let (sunrise_min, sunset_min) = match sun_times(latitude_deg, day_of_year) {
        SunTimes::PolarDay => return Daylight::PolarDay,
        SunTimes::PolarNight => return Daylight::PolarNight,
        SunTimes::RiseSet {
            sunrise_min,
            sunset_min,
        } => (sunrise_min, sunset_min),
    };
    let daylight_min = round(sunset_min - sunrise_min) as u16;
    let view = |event, until_min: f64, at_min: f64| {
        Daylight::Sun(DaylightView {
            event,
            countdown_min: floor(until_min) as u32,
            event_clock_min: (round(at_min) as u16) % (MIN_PER_DAY as u16),
            daylight_min,
        })
    };
    if m < sunrise_min {
        view(NextSunEvent::Sunrise, sunrise_min - m, sunrise_min)
    } else if m < sunset_min {
        view(NextSunEvent::Sunset, sunset_min - m, sunset_min)
    } else {
        match sun_times(latitude_deg, day_of_year + 1) {
            SunTimes::PolarDay => Daylight::PolarDay,
            SunTimes::PolarNight => Daylight::PolarNight,
            SunTimes::RiseSet { sunrise_min, .. } => view(
                NextSunEvent::Sunrise,
                f64::from(MIN_PER_DAY) - m + sunrise_min,
                sunrise_min,
            ),
        }
    }
}

/// UTC seconds-of-day + date shifted into local civil time. The offset
/// can carry the clock across midnight in either direction, so the date
/// moves with it — the declination day must be the runner's day, not
/// Greenwich's.
pub fn local_civil(tod_utc_s: u32, date_utc: Date, tz_offset_min: i16) -> (u32, Date) {
    let t = (tod_utc_s % SEC_PER_DAY) as i32 + i32::from(tz_offset_min) * 60;
    if t < 0 {
        (((t + SEC_PER_DAY as i32) / 60) as u32, prev_day(date_utc))
    } else if t >= SEC_PER_DAY as i32 {
        (((t - SEC_PER_DAY as i32) / 60) as u32, next_day(date_utc))
    } else {
        ((t / 60) as u32, date_utc)
    }
}

/// The page's entry point: the state for *now*, from the last fix's UTC
/// clock + date extrapolated by elapsed uptime (fixes are up to a minute
/// apart in Expedition mode, and a countdown frozen at the fix's minute
/// reads as a hung watch — the same rule as the idle clock), shifted into
/// local civil time by the synced offset.
pub fn daylight_at(
    latitude_deg: f64,
    tod_utc_s: u32,
    date_utc: Date,
    fix_uptime_s: u32,
    now_uptime_s: u32,
    tz_offset_min: i16,
) -> Daylight {
    let mut tod =
        u64::from(tod_utc_s % SEC_PER_DAY) + u64::from(now_uptime_s.saturating_sub(fix_uptime_s));
    let mut date = date_utc;
    while tod >= u64::from(SEC_PER_DAY) {
        tod -= u64::from(SEC_PER_DAY);
        date = next_day(date);
    }
    let (local_min, local_date) = local_civil(tod as u32, date, tz_offset_min);
    daylight(local_min, latitude_deg, i32::from(day_of_year(local_date)))
}

#[cfg(test)]
mod tests {
    use super::*;

    // The web suite's seasonal-day constants.
    const DEC_21: i32 = 355;
    const JUN_21: i32 = 172;

    const JUL_8_2026: Date = Date {
        year: 2026,
        month: 7,
        day: 8,
    };

    #[test]
    fn winter_pre_dawn_at_high_latitude_is_dark() {
        assert!(
            is_sun_down(7 * 60, 60.0, DEC_21),
            "07:00 at 60°N in December is before sunrise"
        );
    }

    #[test]
    fn winter_midday_at_high_latitude_is_light() {
        assert!(
            !is_sun_down(12 * 60, 60.0, DEC_21),
            "the sun is up at solar noon even in deep winter"
        );
    }

    #[test]
    fn summer_0630_at_high_latitude_is_already_light() {
        assert!(
            !is_sun_down(6 * 60 + 30, 60.0, JUN_21),
            "high-latitude summer sun rises well before 06:30"
        );
    }

    #[test]
    fn polar_night_is_always_dark() {
        assert!(
            is_sun_down(12 * 60, 80.0, DEC_21),
            "the sun never rises at 80°N in December"
        );
    }

    #[test]
    fn polar_day_midnight_sun_is_never_dark() {
        assert!(
            !is_sun_down(0, 80.0, JUN_21),
            "the sun never sets at 80°N in June"
        );
    }

    #[test]
    fn out_of_range_minutes_normalise_into_the_day() {
        assert_eq!(
            is_sun_down(-60, 60.0, DEC_21),
            is_sun_down(1380, 60.0, DEC_21)
        );
        assert_eq!(
            is_sun_down(1440 + 720, 60.0, DEC_21),
            is_sun_down(720, 60.0, DEC_21)
        );
    }

    #[test]
    fn out_of_range_days_fold_like_the_web_original() {
        assert_eq!(solar_declination_deg(366), solar_declination_deg(1));
        assert_eq!(solar_declination_deg(0), solar_declination_deg(365));
    }

    #[test]
    fn declination_matches_the_solstices() {
        assert!(solar_declination_deg(JUN_21) > 23.0);
        assert!(solar_declination_deg(DEC_21) < -23.0);
        // Near an equinox the sun crosses the equator.
        assert!(solar_declination_deg(81).abs() < 1.0);
    }

    #[test]
    fn equator_day_is_about_twelve_hours() {
        let SunTimes::RiseSet {
            sunrise_min,
            sunset_min,
        } = sun_times(0.0, 81)
        else {
            panic!("the equator is never polar");
        };
        // Slightly over 720: the −0.833° horizon buys a few extra minutes.
        let len = sunset_min - sunrise_min;
        assert!((len - 720.0).abs() < 15.0, "day length {len}");
    }

    #[test]
    fn sun_times_and_is_sun_down_agree_at_the_boundaries() {
        let SunTimes::RiseSet {
            sunrise_min,
            sunset_min,
        } = sun_times(60.0, DEC_21)
        else {
            panic!("60°N in December still has a day");
        };
        let before_rise = floor(sunrise_min) as i32;
        let after_set = floor(sunset_min) as i32 + 1;
        assert!(is_sun_down(before_rise, 60.0, DEC_21));
        assert!(!is_sun_down(before_rise + 1, 60.0, DEC_21));
        assert!(is_sun_down(after_set, 60.0, DEC_21));
        assert!(!is_sun_down(after_set - 1, 60.0, DEC_21));
    }

    #[test]
    fn pre_dawn_counts_to_sunrise() {
        let Daylight::Sun(v) = daylight(90, 40.0, 189) else {
            panic!("40°N in July is not polar");
        };
        assert_eq!(v.event, NextSunEvent::Sunrise);
        assert_eq!(u32::from(v.event_clock_min), 90 + v.countdown_min + 1);
        assert!(v.daylight_min > 720, "July at 40°N is a long day");
    }

    #[test]
    fn midday_counts_to_sunset() {
        let Daylight::Sun(v) = daylight(720, 40.0, 189) else {
            panic!("40°N in July is not polar");
        };
        assert_eq!(v.event, NextSunEvent::Sunset);
        assert!(v.countdown_min > 5 * 60, "solar noon is far from sunset");
    }

    #[test]
    fn after_sunset_counts_across_midnight_to_tomorrows_sunrise() {
        let Daylight::Sun(v) = daylight(23 * 60, 40.0, 189) else {
            panic!("40°N in July is not polar");
        };
        assert_eq!(v.event, NextSunEvent::Sunrise);
        // 60 minutes to midnight plus tomorrow's pre-dawn stretch.
        assert_eq!(
            v.countdown_min,
            60 + u32::from(v.event_clock_min),
            "the countdown crosses midnight to the sunrise clock"
        );
    }

    #[test]
    fn a_polar_transition_reports_the_season_not_a_fabricated_clock() {
        // At 80°N the model leaves polar day in late summer: walking the days
        // finds the boundary where "after sunset" meets a tomorrow that is
        // still (or again) polar. The page must answer with the season.
        let mut saw_polar_answer = false;
        for doy in 1..=365 {
            if matches!(sun_times(80.0, doy), SunTimes::RiseSet { .. })
                && !matches!(sun_times(80.0, doy + 1), SunTimes::RiseSet { .. })
            {
                saw_polar_answer = true;
                assert!(
                    !matches!(daylight(1439, 80.0, doy), Daylight::Sun(_)),
                    "day {doy}: a clock time fabricated into a polar tomorrow"
                );
            }
        }
        assert!(saw_polar_answer, "80°N never bordered a polar stretch");
    }

    #[test]
    fn day_of_year_is_leap_aware() {
        assert_eq!(
            day_of_year(Date {
                year: 2026,
                month: 3,
                day: 1
            }),
            60
        );
        assert_eq!(
            day_of_year(Date {
                year: 2028,
                month: 3,
                day: 1
            }),
            61
        );
        assert_eq!(
            day_of_year(Date {
                year: 2026,
                month: 12,
                day: 31
            }),
            365
        );
        assert_eq!(
            day_of_year(Date {
                year: 2028,
                month: 12,
                day: 31
            }),
            366
        );
        assert_eq!(day_of_year(JUL_8_2026), 189);
    }

    #[test]
    fn next_and_prev_day_roll_months_and_years() {
        let nye = Date {
            year: 2026,
            month: 12,
            day: 31,
        };
        let nyd = Date {
            year: 2027,
            month: 1,
            day: 1,
        };
        assert_eq!(next_day(nye), nyd);
        assert_eq!(prev_day(nyd), nye);
        let leap_boundary = Date {
            year: 2028,
            month: 2,
            day: 29,
        };
        assert_eq!(
            next_day(Date {
                year: 2028,
                month: 2,
                day: 28
            }),
            leap_boundary
        );
        assert_eq!(
            prev_day(Date {
                year: 2028,
                month: 3,
                day: 1
            }),
            leap_boundary
        );
    }

    #[test]
    fn local_civil_shifts_the_date_in_both_directions() {
        // 01:00 UTC at Marquesas offset (−9:30) is yesterday 15:30.
        let (min, date) = local_civil(3600, JUL_8_2026, -570);
        assert_eq!(min, 15 * 60 + 30);
        assert_eq!(date, prev_day(JUL_8_2026));
        // 23:00 UTC at Kathmandu offset (+5:45) is tomorrow 04:45.
        let (min, date) = local_civil(23 * 3600, JUL_8_2026, 345);
        assert_eq!(min, 4 * 60 + 45);
        assert_eq!(date, next_day(JUL_8_2026));
        // No shift stays inside the day.
        let (min, date) = local_civil(12 * 3600, JUL_8_2026, 0);
        assert_eq!(min, 720);
        assert_eq!(date, JUL_8_2026);
    }

    #[test]
    fn extrapolation_rolls_the_utc_date() {
        // A fix stamped just before UTC midnight, asked about 20 s later:
        // the declination day must advance with the clock.
        let a = daylight_at(40.0, SEC_PER_DAY - 10, JUL_8_2026, 100, 120, 0);
        let b = daylight(0, 40.0, i32::from(day_of_year(next_day(JUL_8_2026))));
        assert_eq!(a, b);
    }

    #[test]
    fn the_bench_jog_fixture_reads_a_pre_dawn_sunrise_countdown() {
        // The sim fixture's opening fix (40.015°N, 07:30:00 UTC, 2026-07-08)
        // with the sim's demo Mountain-time offset: 01:30 local, pre-dawn.
        let got = daylight_at(40.015, 7 * 3600 + 30 * 60, JUL_8_2026, 3, 3, -360);
        let Daylight::Sun(v) = got else {
            panic!("Colorado in July is not polar: {got:?}");
        };
        assert_eq!(v.event, NextSunEvent::Sunrise);
        // The model's 40°N July half-day is ~446 min around local noon.
        assert_eq!(v.event_clock_min, 274);
        assert_eq!(v.countdown_min, 183);
        assert_eq!(v.daylight_min, 893);
    }
}
