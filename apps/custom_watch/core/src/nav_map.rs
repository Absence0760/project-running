//! Nav-page map panel decisions — the pure half of the screen task's map.
//!
//! The task owns the framebuffer; everything it needs to *decide* before
//! drawing lives here: which lat/lon -> pixel transform to draw the breadcrumb
//! with (whole-course overview, or an auto-zoom window around the runner),
//! whether the position marker is drawn at all, and the repaint key that lets
//! an unchanged panel skip its redraw entirely.

use crate::course::{Course, CourseBounds, PanelFit};

/// Long-course auto-zoom half-spans. Fitting a whole 50 km course into a
/// ~168 px panel is ~300 m/px, so its forks collapse to sub-pixel and the map
/// is an unreadable scribble. Once the course bounding box exceeds these spans
/// (either axis) the panel stops fitting the whole route and instead windows a
/// fixed real-world span centred on the runner, so the nearest forks stay
/// resolvable; a course that already fits keeps the whole-course overview.
///
/// Expressed in degrees (not metres) so the cos-lat correction stays inside
/// [`PanelFit`] — the window is built as a runner-centred box and fed through
/// the same fit the whole-course path uses. ~0.0054 deg latitude ~= 600 m, so
/// the window spans ~1.2 km N-S (~13 m/px on a 96 px-tall panel); the E-W half
/// is doubled so the wider panel isn't letterboxed.
pub const WIN_HALF_LAT_DEG: f64 = 0.0054;
pub const WIN_HALF_LON_DEG: f64 = 0.0108;

/// The map panel's pixel geometry, in display pixels: the panel spans the full
/// width, starts `top_px` down the screen and is `h_px` tall. `marker_arm_px`
/// is the half-length of the position marker's cross.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NavPanelGeom {
    pub w_px: u32,
    pub top_px: i32,
    pub h_px: u32,
    pub marker_arm_px: i32,
}

/// Everything the screen task needs to paint one frame of the map panel.
pub struct NavPanel {
    pub fit: PanelFit,
    /// Screen pixel of the position marker's centre, or `None` when the
    /// runner's fix falls outside the panel (see [`marker_px`]).
    pub marker: Option<(i32, i32)>,
    /// The repaint tracking key's runner component (see [`track_key`]).
    pub track: (i32, i32),
}

pub fn nav_panel(course: &Course, runner: Option<(f64, f64)>, geom: NavPanelGeom) -> NavPanel {
    let (fit, windowed) = nav_fit(course, runner, geom.w_px, geom.h_px);
    let marker = runner.and_then(|(lat, lon)| marker_px(&fit, lat, lon, geom));
    let track = runner.map_or((0, 0), |(lat, lon)| {
        track_key(&fit, windowed, geom.h_px, lat, lon)
    });
    NavPanel { fit, marker, track }
}

/// Pick the lat/lon -> panel-pixel transform to draw the breadcrumb with, and
/// report whether it auto-zoomed. A course whose bounding box already fits
/// inside a window-sized box renders whole (the situational overview); a larger
/// one auto-zooms to a fixed span centred on the runner. `runner` `None` (no
/// fix yet) always fits the whole course.
///
/// Fitting a box whose centre is the runner lands the runner at the panel
/// centre.
///
/// The course's own bounding box is read from [`Course::bounds`] (computed once
/// at build time) rather than rescanned per call — this runs on every UI render
/// the Nav page is up for, including wakes caused by unrelated state.
pub fn nav_fit(
    course: &Course,
    runner: Option<(f64, f64)>,
    w_px: u32,
    h_px: u32,
) -> (PanelFit, bool) {
    let whole = course.bounds();
    let Some((rlat, rlon)) = runner else {
        return (PanelFit::from_bounds(whole, w_px, h_px), false);
    };
    if (whole.max_lat - whole.min_lat) <= 2.0 * WIN_HALF_LAT_DEG
        && (whole.max_lon - whole.min_lon) <= 2.0 * WIN_HALF_LON_DEG
    {
        return (PanelFit::from_bounds(whole, w_px, h_px), false);
    }
    // Fitting the window's corners puts the runner (the box centre) at the panel
    // centre and renders the surrounding course at a readable scale; points
    // outside the box clip when drawn.
    let window = CourseBounds::of(
        rlat - WIN_HALF_LAT_DEG,
        rlat + WIN_HALF_LAT_DEG,
        rlon - WIN_HALF_LON_DEG,
        rlon + WIN_HALF_LON_DEG,
    );
    (PanelFit::from_bounds(window, w_px, h_px), true)
}

/// Screen pixel of the position marker, drawn only when its whole cross sits
/// inside the panel. No clamp — an off-panel runner (far off-course, or outside
/// the auto-zoom window) shows no marker rather than a dishonest edge-pinned
/// one; the OFF COURSE banner is the source of truth. In the auto-zoom window
/// the runner is the panel centre, so the marker is always shown.
pub fn marker_px(
    fit: &PanelFit,
    lat_deg: f64,
    lon_deg: f64,
    geom: NavPanelGeom,
) -> Option<(i32, i32)> {
    let (x, y) = fit.to_px(lat_deg, lon_deg);
    let (mx, my) = (x, y + geom.top_px);
    let inside = (geom.marker_arm_px..geom.w_px as i32 - geom.marker_arm_px).contains(&mx)
        && (geom.top_px + geom.marker_arm_px..geom.top_px + geom.h_px as i32 - geom.marker_arm_px)
            .contains(&my);
    inside.then_some((mx, my))
}

/// The runner's position in a course-anchored integer grid ~1 display pixel per
/// cell — the panel's repaint trigger. In the whole-course fit the marker's own
/// pixel already moves with the runner, so [`PanelFit::to_px`] is the key. In
/// the auto-zoom window the marker holds at the panel centre (the window
/// recentres on the runner every fix), so the key instead quantises the raw
/// position onto a fixed latitude-degree grid sized to one window pixel; it
/// advances ~1 per pixel of real movement independent of the recentring, and a
/// resting runner leaves it unchanged (so the panel still flushes zero SPI).
/// Longitude shares the latitude grid — slightly coarser in ground metres E-W
/// at high latitude, harmless for a trigger — which keeps this cos-free.
pub fn track_key(
    fit: &PanelFit,
    windowed: bool,
    panel_h_px: u32,
    lat_deg: f64,
    lon_deg: f64,
) -> (i32, i32) {
    if windowed {
        let grid = 2.0 * WIN_HALF_LAT_DEG / panel_h_px as f64;
        (round_i32(lat_deg / grid), round_i32(lon_deg / grid))
    } else {
        fit.to_px(lat_deg, lon_deg)
    }
}

fn round_i32(v: f64) -> i32 {
    libm::round(v) as i32
}

/// The panel's whole live pixel state: where the runner is tracking, whether
/// the marker is drawn, and whether the off-course banner is shown.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PanelKey {
    pub track: (i32, i32),
    pub marker: bool,
    pub alert: bool,
}

/// Remembers the last painted [`PanelKey`] so an unchanged panel skips its
/// redraw — the map's pixels stand and a resting Nav page flushes zero lines.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PanelCache {
    last: Option<PanelKey>,
}

impl PanelCache {
    pub const fn new() -> Self {
        Self { last: None }
    }

    /// Fold this frame's key in and report whether the panel must repaint. A
    /// frame with no panel (the Nav page isn't showing) paints nothing and
    /// clears the memo, so the next Nav frame repaints from scratch.
    pub fn observe(&mut self, key: Option<PanelKey>) -> bool {
        let repaint = key.is_some() && key != self.last;
        self.last = key;
        repaint
    }

    /// Force the next panel frame to repaint — the drawn course changed, or
    /// something else painted over the panel's pixels.
    pub fn invalidate(&mut self) {
        self.last = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::course::CoursePoint;

    const GEOM: NavPanelGeom = NavPanelGeom {
        w_px: 168,
        top_px: 16,
        h_px: 96,
        marker_arm_px: 2,
    };

    fn pt(lat: f64, lon: f64) -> CoursePoint {
        CoursePoint {
            lat_deg: lat,
            lon_deg: lon,
        }
    }

    /// A course comfortably inside one auto-zoom window.
    fn short_course() -> Course {
        Course::from_points(&[pt(40.0, -105.0), pt(40.001, -105.002), pt(40.002, -105.0)]).unwrap()
    }

    /// A course far larger than one window on both axes.
    fn long_course() -> Course {
        Course::from_points(&[pt(40.0, -105.0), pt(40.1, -105.1), pt(40.2, -105.0)]).unwrap()
    }

    #[test]
    fn a_short_course_keeps_the_whole_course_overview() {
        let (_, windowed) = nav_fit(&short_course(), Some((40.001, -105.001)), 168, 96);
        assert!(!windowed);
    }

    #[test]
    fn a_long_course_auto_zooms_around_the_runner() {
        let (fit, windowed) = nav_fit(&long_course(), Some((40.05, -105.05)), 168, 96);
        assert!(windowed);
        // The runner is the window's centre, so it lands mid-panel.
        let (x, y) = fit.to_px(40.05, -105.05);
        assert!((x - 84).abs() <= 2, "x {x}");
        assert!((y - 48).abs() <= 2, "y {y}");
    }

    #[test]
    fn no_fix_yet_always_fits_the_whole_course() {
        let (_, windowed) = nav_fit(&long_course(), None, 168, 96);
        assert!(!windowed);
    }

    #[test]
    fn a_span_exactly_one_window_wide_is_not_windowed() {
        // Anchored at zero so the span arithmetic is exact — the comparison is
        // inclusive, so a course that just fits keeps the overview.
        let c = Course::from_points(&[
            pt(0.0, 0.0),
            pt(2.0 * WIN_HALF_LAT_DEG, 2.0 * WIN_HALF_LON_DEG),
        ])
        .unwrap();
        let (_, windowed) = nav_fit(&c, Some((WIN_HALF_LAT_DEG, WIN_HALF_LON_DEG)), 168, 96);
        assert!(!windowed);
    }

    #[test]
    fn either_axis_over_the_window_span_windows_the_fit() {
        let tall = Course::from_points(&[pt(0.0, 0.0), pt(2.1 * WIN_HALF_LAT_DEG, 0.0)]).unwrap();
        assert!(nav_fit(&tall, Some((0.0, 0.0)), 168, 96).1);
        let wide = Course::from_points(&[pt(0.0, 0.0), pt(0.0, 2.1 * WIN_HALF_LON_DEG)]).unwrap();
        assert!(nav_fit(&wide, Some((0.0, 0.0)), 168, 96).1);
    }

    #[test]
    fn the_marker_is_drawn_for_a_runner_on_the_panel() {
        let c = short_course();
        let (fit, _) = nav_fit(&c, Some((40.001, -105.001)), GEOM.w_px, GEOM.h_px);
        let (mx, my) = marker_px(&fit, 40.001, -105.001, GEOM).unwrap();
        assert!((GEOM.marker_arm_px..GEOM.w_px as i32 - GEOM.marker_arm_px).contains(&mx));
        assert!(my >= GEOM.top_px + GEOM.marker_arm_px);
        assert!(my < GEOM.top_px + GEOM.h_px as i32 - GEOM.marker_arm_px);
    }

    #[test]
    fn a_runner_off_the_panel_shows_no_marker() {
        let c = short_course();
        let (fit, _) = nav_fit(&c, Some((41.0, -105.0)), GEOM.w_px, GEOM.h_px);
        // Far north of the course in a whole-course fit: the cross would
        // scribble on the rows above the panel, so no marker at all.
        assert_eq!(marker_px(&fit, 41.0, -105.0, GEOM), None);
        // Far east, likewise off the right edge.
        assert_eq!(marker_px(&fit, 40.001, -100.0, GEOM), None);
    }

    #[test]
    fn the_auto_zoom_window_always_shows_the_marker() {
        let c = long_course();
        let runner = (40.05, -105.05);
        let panel = nav_panel(&c, Some(runner), GEOM);
        assert!(panel.marker.is_some());
    }

    #[test]
    fn the_track_key_is_the_marker_pixel_in_a_whole_course_fit() {
        let c = short_course();
        let (fit, windowed) = nav_fit(&c, Some((40.001, -105.001)), GEOM.w_px, GEOM.h_px);
        assert!(!windowed);
        assert_eq!(
            track_key(&fit, windowed, GEOM.h_px, 40.001, -105.001),
            fit.to_px(40.001, -105.001)
        );
    }

    #[test]
    fn a_windowed_track_key_advances_with_real_movement_and_holds_at_rest() {
        let c = long_course();
        let runner = (40.05, -105.05);
        let (fit, windowed) = nav_fit(&c, Some(runner), GEOM.w_px, GEOM.h_px);
        assert!(windowed);
        let at_rest = track_key(&fit, windowed, GEOM.h_px, runner.0, runner.1);
        assert_eq!(
            track_key(&fit, windowed, GEOM.h_px, runner.0, runner.1),
            at_rest
        );
        // One window pixel of latitude moves the key by one.
        let one_px = 2.0 * WIN_HALF_LAT_DEG / GEOM.h_px as f64;
        let moved = track_key(&fit, windowed, GEOM.h_px, runner.0 + one_px, runner.1);
        assert_eq!(moved.0 - at_rest.0, 1);
        // Sub-pixel drift leaves it alone, so the panel still flushes nothing.
        assert_eq!(
            track_key(&fit, windowed, GEOM.h_px, runner.0 + one_px / 8.0, runner.1),
            at_rest
        );
    }

    #[test]
    fn a_courseless_frame_has_no_marker_and_a_zero_track_key() {
        let panel = nav_panel(&long_course(), None, GEOM);
        assert_eq!(panel.marker, None);
        assert_eq!(panel.track, (0, 0));
    }

    #[test]
    fn the_panel_cache_repaints_only_on_a_changed_key() {
        let mut cache = PanelCache::new();
        let key = PanelKey {
            track: (10, 20),
            marker: true,
            alert: false,
        };
        assert!(cache.observe(Some(key)));
        assert!(!cache.observe(Some(key)));
        assert!(cache.observe(Some(PanelKey {
            track: (11, 20),
            ..key
        })));
        assert!(cache.observe(Some(PanelKey {
            track: (11, 20),
            marker: false,
            alert: false
        })));
        assert!(cache.observe(Some(PanelKey {
            track: (11, 20),
            marker: false,
            alert: true
        })));
    }

    #[test]
    fn a_panel_less_frame_paints_nothing_and_forces_the_next_repaint() {
        let mut cache = PanelCache::new();
        let key = PanelKey {
            track: (1, 2),
            marker: true,
            alert: false,
        };
        assert!(cache.observe(Some(key)));
        // The Nav page left the screen: nothing to paint, and the memo is gone.
        assert!(!cache.observe(None));
        assert!(cache.observe(Some(key)));
        // An explicit invalidation (the drawn course changed) repaints too.
        cache.invalidate();
        assert!(cache.observe(Some(key)));
    }
}
