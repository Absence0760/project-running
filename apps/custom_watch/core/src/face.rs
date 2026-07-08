//! Watch-face layout: state in, text rows out.
//!
//! The face is a fixed grid of [`ROWS`] lines x [`COLS`] characters — the
//! 168x144 Sharp MIP divided by the 8x16 font cell. Producing plain rows
//! (rather than drawing) keeps layout pure and host-testable; the `app/`
//! ui task pushes each row through the `sharp_mip` text renderer and the
//! display driver only redraws lines whose content changed.

use core::fmt::Write;

use crate::fix::Fix;

pub const COLS: usize = 21;
pub const ROWS: usize = 9;

/// A fix older than this (in seconds of uptime) renders as signal lost.
pub const STALE_AFTER_S: u32 = 5;

pub type Row = heapless::String<COLS>;

/// Render the status face. Rows are truncated at [`COLS`], never wrapped.
pub fn face_rows(fix: Option<&Fix>, uptime_s: u32) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let (h, m, s) = (uptime_s / 3600, uptime_s / 60 % 60, uptime_s % 60);
    let _ = write!(rows[0], "THREKIR     {:02}:{:02}:{:02}", h.min(99), m, s);

    match fix {
        None => {
            let _ = write!(rows[2], "GPS  ACQUIRING");
            let _ = write!(rows[3], "LAT  --");
            let _ = write!(rows[4], "LON  --");
        }
        Some(fix) => {
            let age = uptime_s.saturating_sub(fix.uptime_s);
            if age > STALE_AFTER_S {
                let _ = write!(rows[2], "GPS  STALE {}S", age.min(999));
            } else {
                let _ = write!(rows[2], "GPS  {} SATS", fix.sats);
            }
            let _ = write!(rows[3], "LAT  {:11.5}", fix.lat_deg);
            let _ = write!(rows[4], "LON  {:11.5}", fix.lon_deg);
            let _ = write!(rows[5], "SPD  {:.1} M/S", fix.speed_mps);
            if let Some(alt) = fix.alt_m {
                let _ = write!(rows[6], "ALT  {:.0} M", alt);
            }
            if let Some(tod) = fix.time_of_day {
                let (th, tm, ts) = (tod / 3600, tod / 60 % 60, tod % 60);
                let _ = write!(rows[8], "UTC  {:02}:{:02}:{:02}", th, tm, ts);
            }
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fix() -> Fix {
        Fix {
            lat_deg: 40.01502,
            lon_deg: -105.2705,
            speed_mps: 3.0,
            course_deg: Some(90.0),
            sats: 8,
            alt_m: Some(1624.0),
            time_of_day: Some(7 * 3600 + 30 * 60 + 15),
            uptime_s: 41,
        }
    }

    #[test]
    fn all_rows_fit_the_grid() {
        for row in face_rows(Some(&fix()), 42) {
            assert!(row.len() <= COLS, "row too wide: {:?}", row);
        }
    }

    #[test]
    fn fresh_fix_renders_position() {
        let rows = face_rows(Some(&fix()), 42);
        assert_eq!(rows[0].as_str(), "THREKIR     00:00:42");
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        assert_eq!(rows[4].as_str(), "LON   -105.27050");
        assert_eq!(rows[5].as_str(), "SPD  3.0 M/S");
        assert_eq!(rows[6].as_str(), "ALT  1624 M");
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
    }

    #[test]
    fn stale_fix_is_flagged_not_shown_as_fresh() {
        let rows = face_rows(Some(&fix()), 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[2].as_str(), "GPS  STALE 8S");
        // Position is still shown — last-known beats blank on a run.
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
    }

    #[test]
    fn no_fix_renders_acquiring() {
        let rows = face_rows(None, 9);
        assert_eq!(rows[2].as_str(), "GPS  ACQUIRING");
        assert_eq!(rows[5].as_str(), "");
    }
}
