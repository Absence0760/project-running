//! Watch-face layout: state in, text rows out.
//!
//! The face is a fixed grid of [`ROWS`] lines x [`COLS`] characters — the
//! 168x144 Sharp MIP divided by the 8x16 font cell. Producing plain rows
//! (rather than drawing) keeps layout pure and host-testable; the `app/`
//! ui task pushes each row through the `sharp_mip` text renderer and the
//! display driver only redraws lines whose content changed.

use core::fmt::Write;

use crate::elevation;
use crate::fix::Fix;
use crate::record::{RecordState, Snapshot};

pub const COLS: usize = 21;
pub const ROWS: usize = 9;

/// A fix older than this (in seconds of uptime) renders as signal lost.
pub const STALE_AFTER_S: u32 = 5;

pub type Row = heapless::String<COLS>;

fn rec_tag(state: RecordState) -> Option<&'static str> {
    match state {
        RecordState::Idle => None,
        RecordState::Recording => Some("REC"),
        RecordState::Paused => Some("PAU"),
        RecordState::Finished => Some("FIN"),
    }
}

/// Render the status face. Rows are truncated at [`COLS`], never wrapped.
/// `hr_bpm` is `None` until the peak detector reports a stable pulse; `rec` is
/// the live recording snapshot (its own state gates whether a line shows);
/// `elev` is the latest barometric reading (`None` until the baro streams).
///
/// The 9-row grid is full, so the barometer, when present, takes over two rows
/// symmetrically: the ALT row prefers the barometric altitude over the GPS
/// fix's, and the bottom row shows cumulative vert — the ultra headline metric
/// — in place of the GPS wall clock. Both fall back to their GPS source when
/// no baro reading is available.
pub fn face_rows(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let (h, m, s) = (uptime_s / 3600, uptime_s / 60 % 60, uptime_s % 60);
    let _ = write!(rows[0], "THREKIR     {:02}:{:02}:{:02}", h.min(99), m, s);

    if let Some(tag) = rec.and_then(|r| rec_tag(r.state)) {
        let km = rec.unwrap().distance_m / 1000.0;
        let _ = write!(rows[1], "{} {:.2} KM", tag, km);
    }
    if let Some(bpm) = hr_bpm {
        let _ = write!(rows[7], "HR   {} BPM", bpm);
    }

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
        }
    }

    // Altitude: the barometer beats the GPS fix when it is live (baro works
    // without a fix, so this row can render on the bench with no satellites).
    if let Some(alt) = elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        let _ = write!(rows[6], "ALT  {:.0} M", alt);
    }

    // Bottom row: cumulative vert while the baro streams, else the GPS wall
    // clock. Metres clamped to five digits so the row can't overflow COLS.
    match elev {
        Some(e) => {
            let gain = (e.gain_m as u32).min(99_999);
            let loss = (e.loss_m as u32).min(99_999);
            let _ = write!(rows[8], "VERT +{} -{} M", gain, loss);
        }
        None => {
            if let Some(tod) = fix.and_then(|f| f.time_of_day) {
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

    fn snapshot(state: RecordState, distance_m: f64) -> Snapshot {
        Snapshot {
            state,
            distance_m,
            elapsed_s: 0,
            moving_s: 0,
            current_speed_mps: 0.0,
            avg_pace_s_per_km: None,
            current_pace_s_per_km: None,
        }
    }

    fn elev(alt_m: f32, gain_m: f32, loss_m: f32) -> elevation::Reading {
        elevation::Reading {
            alt_m,
            gain_m,
            loss_m,
        }
    }

    #[test]
    fn all_rows_fit_the_grid() {
        let rec = snapshot(RecordState::Recording, 99_990.0);
        let e = elev(4321.0, 99_999.0, 99_999.0);
        for row in face_rows(Some(&fix()), Some(220), Some(&rec), Some(&e), 42) {
            assert!(row.len() <= COLS, "row too wide: {:?}", row);
        }
    }

    #[test]
    fn fresh_fix_renders_position() {
        let rows = face_rows(Some(&fix()), None, None, None, 42);
        assert_eq!(rows[0].as_str(), "THREKIR     00:00:42");
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        assert_eq!(rows[4].as_str(), "LON   -105.27050");
        assert_eq!(rows[5].as_str(), "SPD  3.0 M/S");
        assert_eq!(rows[6].as_str(), "ALT  1624 M");
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
        // No recording, no HR: those rows stay blank.
        assert_eq!(rows[1].as_str(), "");
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn stale_fix_is_flagged_not_shown_as_fresh() {
        let rows = face_rows(Some(&fix()), None, None, None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[2].as_str(), "GPS  STALE 8S");
        // Position is still shown — last-known beats blank on a run.
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
    }

    #[test]
    fn no_fix_renders_acquiring() {
        let rows = face_rows(None, None, None, None, 9);
        assert_eq!(rows[2].as_str(), "GPS  ACQUIRING");
        assert_eq!(rows[5].as_str(), "");
    }

    #[test]
    fn recording_and_hr_render_on_their_rows() {
        let rec = snapshot(RecordState::Recording, 12_340.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), None, 42);
        assert_eq!(rows[1].as_str(), "REC 12.34 KM");
        assert_eq!(rows[7].as_str(), "HR   152 BPM");
    }

    #[test]
    fn idle_recorder_shows_no_line() {
        let rec = snapshot(RecordState::Idle, 0.0);
        let rows = face_rows(None, None, Some(&rec), None, 3);
        assert_eq!(rows[1].as_str(), "");
    }

    #[test]
    fn paused_recorder_is_tagged() {
        let rec = snapshot(RecordState::Paused, 5_000.0);
        let rows = face_rows(None, None, Some(&rec), None, 3);
        assert_eq!(rows[1].as_str(), "PAU 5.00 KM");
    }

    #[test]
    fn baro_altitude_and_vert_take_over_the_alt_and_bottom_rows() {
        // Baro reading present: ALT prefers the barometric altitude over the
        // GPS fix's 1624 m, and the bottom row shows vert instead of UTC.
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), None, None, Some(&e), 42);
        assert_eq!(rows[6].as_str(), "ALT  1600 M");
        assert_eq!(rows[8].as_str(), "VERT +540 -120 M");
    }

    #[test]
    fn baro_altitude_shows_without_a_fix() {
        // The barometer needs no satellites — ALT + VERT render on the bench.
        let e = elev(1600.0, 50.0, 0.0);
        let rows = face_rows(None, None, None, Some(&e), 3);
        assert_eq!(rows[6].as_str(), "ALT  1600 M");
        assert_eq!(rows[8].as_str(), "VERT +50 -0 M");
    }
}
