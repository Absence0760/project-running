//! Watch-face layout: state in, text rows out.
//!
//! The face is a fixed grid of [`ROWS`] lines x [`COLS`] characters — the
//! 168x144 Sharp MIP divided by the 8x16 font cell. Producing plain rows
//! (rather than drawing) keeps layout pure and host-testable; the `app/`
//! ui task pushes each row through the `sharp_mip` text renderer and the
//! display driver only redraws lines whose content changed.
//!
//! Two layouts, chosen by whether a run is under way:
//!
//! - **Run dashboard** (recording / paused / finished) — the metrics a runner
//!   actually reads on the move: elapsed run time, distance, average + current
//!   pace, heart rate, altitude, and cumulative vert — the ultra headline
//!   pair — with a one-line GPS glance at the bottom. Raw position is
//!   deliberately absent: nobody reads lat/lon mid-ultra, and the fix still
//!   feeds the track, the flash store, and the phone link. Rows keep a fixed
//!   position with a `--` placeholder when a metric is not yet available, so a
//!   glance always finds a value in the same spot rather than a jumping grid.
//! - **Status face** (idle) — the bench / acquisition view: uptime clock, GPS
//!   status, last-known position, speed, altitude, HR, and vert. This is what
//!   shows before a run starts and while the first fix is being acquired.

use core::fmt::Write;

use crate::elevation;
use crate::fix::Fix;
use crate::record::{RecordState, Snapshot};

pub const COLS: usize = 21;
pub const ROWS: usize = 9;

/// A fix older than this (in seconds of uptime) renders as signal lost.
pub const STALE_AFTER_S: u32 = 5;

pub type Row = heapless::String<COLS>;

/// A display-agnostic icon slot the dashboard places in a row's left gutter.
/// `core` stays free of the `sharp_mip` crate (it must not know the panel), so
/// the app maps each variant onto the driver's own `Icon` when it blits — an
/// exhaustive match there catches any drift at compile time, the same way the
/// `COLS == TEXT_COLS` asserts pin the two grids together.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FaceIcon {
    Stopwatch,
    Footsteps,
    Heart,
    /// The small-heart frame of the ~1 Hz HR pulse; alternates with [`Heart`].
    HeartSmall,
    Mountain,
    Vert,
    Satellite,
    /// GPS-searching frames — arcs grow `SatSearch0` -> `SatSearch1` ->
    /// [`Satellite`] once per second while no fresh fix is locked.
    SatSearch0,
    SatSearch1,
}

fn rec_tag(state: RecordState) -> Option<&'static str> {
    match state {
        RecordState::Idle => None,
        RecordState::Recording => Some("REC"),
        RecordState::Paused => Some("PAU"),
        RecordState::Finished => Some("FIN"),
    }
}

/// Render the face. Rows are truncated at [`COLS`], never wrapped.
///
/// A run in progress (recording / paused / finished) draws the run dashboard;
/// otherwise the idle status face. `hr_bpm` is `None` until the peak detector
/// reports a stable pulse; `rec` is the live recording snapshot (its state
/// selects the layout); `elev` is the latest barometric reading (`None` until
/// the baro streams — the dashboard's ALT then falls back to the GPS fix and
/// VERT shows a placeholder).
pub fn face_rows(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
) -> [Row; ROWS] {
    match rec.and_then(|snap| rec_tag(snap.state).map(|tag| (snap, tag))) {
        Some((snap, tag)) => dashboard(fix, hr_bpm, snap, tag, elev, uptime_s),
        None => status_face(fix, hr_bpm, elev, uptime_s),
    }
}

/// The icon that sits in each row's left gutter, paired 1:1 with [`face_rows`].
/// Only the run dashboard carries icons — the idle status face is all text, so
/// every slot is `None` there. The dashboard's icon rows leave their gutter (the
/// first five cells) blank so the blitted 16x16 glyph never collides with text.
///
/// Two gutter icons animate off `uptime_s` (so the choice stays a pure,
/// host-tested function of the inputs, not a hidden timer): the HR heart pulses
/// while a pulse is detected, and the GPS satellite cycles its search arcs while
/// no fresh fix is locked.
pub fn face_icons(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    rec: Option<&Snapshot>,
    uptime_s: u32,
) -> [Option<FaceIcon>; ROWS] {
    let mut icons = [None; ROWS];
    if rec.and_then(|snap| rec_tag(snap.state)).is_some() {
        icons[1] = Some(FaceIcon::Stopwatch);
        icons[2] = Some(FaceIcon::Footsteps);
        icons[5] = Some(heart_icon(hr_bpm, uptime_s));
        icons[6] = Some(FaceIcon::Mountain);
        icons[7] = Some(FaceIcon::Vert);
        icons[8] = Some(gps_icon(fix, uptime_s));
    }
    icons
}

/// The HR gutter frame: a ~1 Hz liveness pulse (big/small heart) while a pulse
/// is detected — a "still recording, still beating" cue, not a beat-accurate
/// BPM sync. Steady when HR is absent. Note: continuous pulsing redraws one
/// cell each second; harmless on the bench, a power line-item on real silicon.
fn heart_icon(hr_bpm: Option<u16>, uptime_s: u32) -> FaceIcon {
    match hr_bpm {
        Some(_) if uptime_s % 2 == 1 => FaceIcon::HeartSmall,
        _ => FaceIcon::Heart,
    }
}

/// The GPS gutter frame: the full satellite once a fresh fix is locked, else a
/// once-per-second growing-arc search cycle so a lost or not-yet-acquired fix
/// reads as actively hunting rather than frozen.
fn gps_icon(fix: Option<&Fix>, uptime_s: u32) -> FaceIcon {
    if gps_fresh(fix, uptime_s) {
        FaceIcon::Satellite
    } else {
        match uptime_s % 3 {
            0 => FaceIcon::SatSearch0,
            1 => FaceIcon::SatSearch1,
            _ => FaceIcon::Satellite,
        }
    }
}

fn gps_fresh(fix: Option<&Fix>, uptime_s: u32) -> bool {
    matches!(fix, Some(f) if uptime_s.saturating_sub(f.uptime_s) <= STALE_AFTER_S)
}

/// The active-run layout. Rows 1/2/5/6/7/8 carry a gutter icon (see
/// [`face_icons`]) so they leave their first five cells blank; the two pace
/// rows keep a text label. Every value aligns at column 5 so the numbers stack
/// in one glanceable column regardless of icon-vs-label gutter.
fn dashboard(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    snap: &Snapshot,
    tag: &str,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
) -> [Row; ROWS] {
    const GUTTER: &str = "     ";
    let mut rows: [Row; ROWS] = Default::default();

    // Blink the REC tag at ~1 Hz so a live recording is unmistakable at a
    // glance; PAU / FIN stay steady (a blink reads as "in progress").
    let tag_shown = tag != "REC" || uptime_s % 2 == 0;
    if tag_shown {
        let _ = write!(rows[0], "{:<18}{}", "THREKIR", tag);
    } else {
        let _ = write!(rows[0], "THREKIR");
    }

    let (h, m, s) = hms(snap.elapsed_s);
    let _ = write!(rows[1], "{}{}:{:02}:{:02}", GUTTER, h.min(999), m, s);

    let km = (snap.distance_m / 1000.0).min(9999.99);
    let _ = write!(rows[2], "{}{:.2} KM", GUTTER, km);

    write_pace(&mut rows[3], "PACE", snap.avg_pace_s_per_km);
    write_pace(&mut rows[4], "NOW", snap.current_pace_s_per_km);

    match hr_bpm {
        Some(bpm) => {
            let _ = write!(rows[5], "{}{} BPM", GUTTER, bpm);
        }
        None => {
            let _ = write!(rows[5], "{}--", GUTTER);
        }
    }

    match elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        Some(alt) => {
            let _ = write!(rows[6], "{}{:.0} M", GUTTER, alt.min(99_999.0));
        }
        None => {
            let _ = write!(rows[6], "{}--", GUTTER);
        }
    }

    match elev {
        Some(e) => {
            let gain = (e.gain_m as u32).min(99_999);
            let loss = (e.loss_m as u32).min(99_999);
            let _ = write!(rows[7], "{}+{} -{} M", GUTTER, gain, loss);
        }
        None => {
            let _ = write!(rows[7], "{}--", GUTTER);
        }
    }

    let _ = write!(rows[8], "{}{}", GUTTER, gps_value(fix, uptime_s).as_str());
    rows
}

/// The idle / bench layout — uptime clock, GPS status, last-known position,
/// speed, altitude, HR, and vert (falling back to the UTC clock with no baro).
fn status_face(
    fix: Option<&Fix>,
    hr_bpm: Option<u16>,
    elev: Option<&elevation::Reading>,
    uptime_s: u32,
) -> [Row; ROWS] {
    let mut rows: [Row; ROWS] = Default::default();

    let (h, m, s) = hms(uptime_s);
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
        }
    }

    // Altitude: the barometer beats the GPS fix when it is live (baro works
    // without a fix, so this row can render on the bench with no satellites).
    if let Some(alt) = elev.map(|e| e.alt_m).or_else(|| fix.and_then(|f| f.alt_m)) {
        let _ = write!(rows[6], "ALT  {:.0} M", alt);
    }

    if let Some(bpm) = hr_bpm {
        let _ = write!(rows[7], "HR   {} BPM", bpm);
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
                let (th, tm, ts) = hms(tod);
                let _ = write!(rows[8], "UTC  {:02}:{:02}:{:02}", th, tm, ts);
            }
        }
    }
    rows
}

/// Write a `M:SS /KM` pace onto a dashboard row behind `label` (padded to the
/// five-cell value gutter), or a `--` placeholder when pace is not yet
/// meaningful. The pace rows are text-labelled rather than iconned: an icon
/// can't distinguish average from current pace, but the words can.
fn write_pace(row: &mut Row, label: &str, pace_s_per_km: Option<u32>) {
    match pace_s_per_km {
        Some(p) => {
            let (pm, ps) = ((p / 60).min(99), p % 60);
            let _ = write!(row, "{:<5}{}:{:02} /KM", label, pm, ps);
        }
        None => {
            let _ = write!(row, "{:<5}--", label);
        }
    }
}

/// The GPS glance shared by both layouts: satellite count, a staleness flag, or
/// `ACQUIRING` before the first fix. Value only — the caller supplies the label.
fn gps_value(fix: Option<&Fix>, uptime_s: u32) -> Row {
    let mut v = Row::new();
    match fix {
        None => {
            let _ = write!(v, "ACQUIRING");
        }
        Some(fix) => {
            let age = uptime_s.saturating_sub(fix.uptime_s);
            if age > STALE_AFTER_S {
                let _ = write!(v, "STALE {}S", age.min(999));
            } else {
                let _ = write!(v, "{} SATS", fix.sats);
            }
        }
    }
    v
}

fn hms(total_s: u32) -> (u32, u32, u32) {
    (total_s / 3600, total_s / 60 % 60, total_s % 60)
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
        // Dashboard at extreme values.
        let mut rec = snapshot(RecordState::Recording, 9_999_990.0);
        rec.elapsed_s = 999 * 3600 + 59 * 60 + 59;
        rec.avg_pace_s_per_km = Some(99 * 60 + 59);
        rec.current_pace_s_per_km = Some(99 * 60 + 59);
        let e = elev(99_999.0, 99_999.0, 99_999.0);
        for row in face_rows(Some(&fix()), Some(220), Some(&rec), Some(&e), 42) {
            assert!(row.len() <= COLS, "dashboard row too wide: {:?}", row);
        }
        // Idle status face at extreme values.
        for row in face_rows(Some(&fix()), Some(220), None, Some(&e), 999_999) {
            assert!(row.len() <= COLS, "status row too wide: {:?}", row);
        }
    }

    #[test]
    fn idle_renders_the_status_face() {
        let rows = face_rows(Some(&fix()), None, None, None, 42);
        assert_eq!(rows[0].as_str(), "THREKIR     00:00:42");
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
        assert_eq!(rows[4].as_str(), "LON   -105.27050");
        assert_eq!(rows[5].as_str(), "SPD  3.0 M/S");
        assert_eq!(rows[6].as_str(), "ALT  1624 M");
        assert_eq!(rows[8].as_str(), "UTC  07:30:15");
        assert_eq!(rows[1].as_str(), "");
        assert_eq!(rows[7].as_str(), "");
    }

    #[test]
    fn idle_stale_fix_is_flagged_not_shown_as_fresh() {
        let rows = face_rows(Some(&fix()), None, None, None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[2].as_str(), "GPS  STALE 8S");
        assert_eq!(rows[3].as_str(), "LAT     40.01502");
    }

    #[test]
    fn idle_no_fix_renders_acquiring() {
        let rows = face_rows(None, None, None, None, 9);
        assert_eq!(rows[2].as_str(), "GPS  ACQUIRING");
        assert_eq!(rows[5].as_str(), "");
    }

    #[test]
    fn recording_renders_the_run_dashboard() {
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 3 * 3600 + 24 * 60 + 7;
        rec.avg_pace_s_per_km = Some(5 * 60 + 12);
        rec.current_pace_s_per_km = Some(4 * 60 + 58);
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42);
        assert_eq!(rows[0].as_str(), "THREKIR           REC");
        assert_eq!(rows[1].as_str(), "     3:24:07");
        assert_eq!(rows[2].as_str(), "     12.34 KM");
        assert_eq!(rows[3].as_str(), "PACE 5:12 /KM");
        assert_eq!(rows[4].as_str(), "NOW  4:58 /KM");
        assert_eq!(rows[5].as_str(), "     152 BPM");
        assert_eq!(rows[6].as_str(), "     1600 M");
        assert_eq!(rows[7].as_str(), "     +540 -120 M");
        assert_eq!(rows[8].as_str(), "     8 SATS");
    }

    #[test]
    fn dashboard_icons_pair_with_the_iconned_rows() {
        let rec = snapshot(RecordState::Recording, 12_340.0);
        // Fresh fix (uptime 42 vs fix uptime 41) + HR present + even uptime, so
        // both animated icons sit on their steady frame.
        let icons = face_icons(Some(&fix()), Some(152), Some(&rec), 42);
        assert_eq!(icons[0], None); // title row
        assert_eq!(icons[1], Some(FaceIcon::Stopwatch));
        assert_eq!(icons[2], Some(FaceIcon::Footsteps));
        assert_eq!(icons[3], None); // PACE — text label
        assert_eq!(icons[4], None); // NOW — text label
        assert_eq!(icons[5], Some(FaceIcon::Heart));
        assert_eq!(icons[6], Some(FaceIcon::Mountain));
        assert_eq!(icons[7], Some(FaceIcon::Vert));
        assert_eq!(icons[8], Some(FaceIcon::Satellite));

        // The idle status face is all text — no gutter icons.
        assert!(face_icons(None, None, None, 0).iter().all(Option::is_none));
        let idle = snapshot(RecordState::Idle, 0.0);
        assert!(face_icons(None, None, Some(&idle), 0)
            .iter()
            .all(Option::is_none));
    }

    #[test]
    fn heart_icon_pulses_once_per_second_while_hr_is_present() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // HR present: big heart on even seconds, small on odd.
        assert_eq!(
            face_icons(Some(&fix()), Some(150), Some(&rec), 42)[5],
            Some(FaceIcon::Heart)
        );
        assert_eq!(
            face_icons(Some(&fix()), Some(150), Some(&rec), 43)[5],
            Some(FaceIcon::HeartSmall)
        );
        // No HR: steady big heart, no pulse.
        assert_eq!(
            face_icons(Some(&fix()), None, Some(&rec), 43)[5],
            Some(FaceIcon::Heart)
        );
    }

    #[test]
    fn gps_icon_cycles_search_arcs_until_a_fresh_fix_locks() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // No fix: arcs grow 0 -> 1 -> 2 with uptime % 3.
        assert_eq!(
            face_icons(None, None, Some(&rec), 0)[8],
            Some(FaceIcon::SatSearch0)
        );
        assert_eq!(
            face_icons(None, None, Some(&rec), 1)[8],
            Some(FaceIcon::SatSearch1)
        );
        assert_eq!(
            face_icons(None, None, Some(&rec), 2)[8],
            Some(FaceIcon::Satellite)
        );
        // A stale fix still reads as searching, not locked.
        let stale_uptime = 41 + STALE_AFTER_S + 3;
        assert!(matches!(
            face_icons(Some(&fix()), None, Some(&rec), stale_uptime)[8],
            Some(FaceIcon::SatSearch0 | FaceIcon::SatSearch1 | FaceIcon::Satellite)
        ));
        // A fresh fix locks the full satellite regardless of the second.
        assert_eq!(
            face_icons(Some(&fix()), None, Some(&rec), 43)[8],
            Some(FaceIcon::Satellite)
        );
    }

    #[test]
    fn rec_tag_blinks_but_pause_and_finish_stay_steady() {
        let rec = snapshot(RecordState::Recording, 100.0);
        // REC visible on even seconds, hidden on odd.
        assert_eq!(
            face_rows(None, None, Some(&rec), None, 10)[0].as_str(),
            "THREKIR           REC"
        );
        assert_eq!(
            face_rows(None, None, Some(&rec), None, 11)[0].as_str(),
            "THREKIR"
        );
        // Paused / finished tags never blink.
        let paused = snapshot(RecordState::Paused, 100.0);
        assert_eq!(
            face_rows(None, None, Some(&paused), None, 11)[0].as_str(),
            "THREKIR           PAU"
        );
    }

    #[test]
    fn iconned_rows_leave_the_gutter_blank_for_the_glyph() {
        // Every row that face_icons places a glyph on must start with the
        // five-cell blank gutter, or the icon would collide with text.
        let mut rec = snapshot(RecordState::Recording, 12_340.0);
        rec.elapsed_s = 42;
        rec.avg_pace_s_per_km = Some(300);
        rec.current_pace_s_per_km = Some(280);
        let e = elev(1600.0, 540.0, 120.0);
        let rows = face_rows(Some(&fix()), Some(152), Some(&rec), Some(&e), 42);
        let icons = face_icons(Some(&fix()), Some(152), Some(&rec), 42);
        for (row, icon) in icons.iter().enumerate() {
            if icon.is_some() {
                assert!(
                    rows[row].starts_with("     "),
                    "iconned row {} lacks a blank gutter: {:?}",
                    row,
                    rows[row]
                );
            }
        }
    }

    #[test]
    fn dashboard_shows_placeholders_before_metrics_are_available() {
        // Recording, but no pace yet, no HR sensor, no baro. Even second so
        // the blinking REC tag is on its visible frame.
        let rec = snapshot(RecordState::Recording, 0.0);
        let rows = face_rows(None, None, Some(&rec), None, 2);
        assert_eq!(rows[0].as_str(), "THREKIR           REC");
        assert_eq!(rows[1].as_str(), "     0:00:00");
        assert_eq!(rows[2].as_str(), "     0.00 KM");
        assert_eq!(rows[3].as_str(), "PACE --");
        assert_eq!(rows[4].as_str(), "NOW  --");
        assert_eq!(rows[5].as_str(), "     --");
        assert_eq!(rows[6].as_str(), "     --");
        assert_eq!(rows[7].as_str(), "     --");
        assert_eq!(rows[8].as_str(), "     ACQUIRING");
    }

    #[test]
    fn dashboard_alt_falls_back_to_the_gps_fix_without_a_baro() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = face_rows(Some(&fix()), None, Some(&rec), None, 42);
        assert_eq!(rows[6].as_str(), "     1624 M");
        assert_eq!(rows[7].as_str(), "     --");
    }

    #[test]
    fn dashboard_flags_a_stale_fix_on_the_gps_line() {
        let rec = snapshot(RecordState::Recording, 100.0);
        let rows = face_rows(Some(&fix()), None, Some(&rec), None, 41 + STALE_AFTER_S + 3);
        assert_eq!(rows[8].as_str(), "     STALE 8S");
    }

    #[test]
    fn paused_and_finished_runs_keep_the_dashboard() {
        let rows = face_rows(None, None, Some(&snapshot(RecordState::Paused, 5_000.0)), None, 3);
        assert_eq!(rows[0].as_str(), "THREKIR           PAU");
        assert_eq!(rows[2].as_str(), "     5.00 KM");

        let rows = face_rows(None, None, Some(&snapshot(RecordState::Finished, 42_195.0)), None, 3);
        assert_eq!(rows[0].as_str(), "THREKIR           FIN");
        assert_eq!(rows[2].as_str(), "     42.20 KM");
    }

    #[test]
    fn idle_recorder_shows_the_status_face_not_the_dashboard() {
        let rows = face_rows(Some(&fix()), None, Some(&snapshot(RecordState::Idle, 0.0)), None, 42);
        assert_eq!(rows[2].as_str(), "GPS  8 SATS");
        assert_eq!(rows[1].as_str(), "");
    }
}
