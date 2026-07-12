//! Breadcrumb course following + off-course detection.
//!
//! The fifth parity port: the projection math mirrors the main app's
//! `route_snap.ts` `snapToPolyline` (web canonical, the nearest perpendicular
//! foot on the closest segment — not merely the nearest vertex — in a local
//! equirectangular frame per segment) and its along-course accumulation, the
//! same shape `route_geometry.ts` `distanceAlongRoute` resolves for the
//! predictive-live-tracking input. The off-course detector reproduces the
//! mobile run screen's route-overlay behaviour: alert past 40 m, re-arm only
//! once back within half that, so the boundary can't flap an alert on GPS
//! jitter. Tests mirror `route_snap.test.ts` + the `distanceAlongRoute` cases
//! in `route_geometry.test.ts` case-for-case, plus firmware-specific ones.
//!
//! [`Course::project_from`] layers a watch-local forward-progress bias on top
//! of that ported geometry so along-course distance stays monotonic-friendly
//! on a retracing course (out-and-back / lollipop / parallel legs) instead of
//! collapsing onto the outbound leg on the return — it is NOT part of the
//! `snapToPolyline` parity port; the plain `project` math is left untouched.
//!
//! [`PanelFit`] is the display half kept host-testable: it fits the course's
//! bounding box into a pixel panel (longitude scaled by cos(mid-latitude), the
//! same correction `track_projection.ts` applies so a square loop renders
//! square) and maps lat/lon to pixel coordinates; the app's ui task only blits
//! lines between the points this module hands it.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

/// Fixed course capacity: 256 points x 16 B = 4 KiB of RAM, one flash-slot's
/// worth — enough for a phone-simplified ultra course polyline at tier 1 (the
/// canned sim course uses 5). A longer course must be simplified phone-side
/// before the (future) BLE push; `from_points` rejects an overflow rather than
/// silently truncating a course mid-race.
pub const MAX_COURSE_POINTS: usize = 256;

/// Perpendicular distance past which the runner is off course — the mobile
/// run screen's `_offRouteThresholdMetres`.
pub const OFF_COURSE_THRESHOLD_M: f64 = 40.0;

/// Back within this (threshold / 2) re-arms the alert — the mobile run
/// screen's re-arm branch, so hovering at the boundary can't flap.
pub const OFF_COURSE_REARM_M: f64 = OFF_COURSE_THRESHOLD_M / 2.0;

const R_M: f64 = 6_371_000.0;

/// [`Course::project_from`] biases an overlapping-segment tie toward the one
/// consistent with forward progress from the last along-distance by charging
/// each candidate for how far its along-distance sits from the previous one,
/// in metres of equivalent perpendicular offset. Moving *backward* costs far
/// more than moving *forward* ([`ALONG_BACK_BIAS_PER_M`] >
/// [`ALONG_FWD_BIAS_PER_M`]): the heavy backward charge stops the return leg
/// snapping onto the outbound leg at the turnaround, while the light forward
/// charge still prefers the nearer of two forward candidates so an early fix
/// doesn't jump ahead to a far retraced leg (a lollipop's return stem). Both
/// are small enough that a genuinely closer segment (a real backtrack, offset
/// gap outweighing the along difference) still wins outright.
const ALONG_FWD_BIAS_PER_M: f64 = 0.05;
const ALONG_BACK_BIAS_PER_M: f64 = 0.5;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CoursePoint {
    pub lat_deg: f64,
    pub lon_deg: f64,
}

/// The nearest-point-on-course projection of one position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Projection {
    /// Snapped latitude — on the course line.
    pub lat_deg: f64,
    /// Snapped longitude — on the course line.
    pub lon_deg: f64,
    /// Index `i` of the segment `[points[i], points[i+1]]` the position fell on.
    pub segment: usize,
    /// Fraction in [0,1] along that segment to the foot of the projection.
    pub t: f64,
    /// Cumulative distance from the course start to the snapped point, metres.
    pub along_m: f64,
    /// Perpendicular distance from the position to the course, metres.
    pub off_m: f64,
}

/// A compact in-RAM course: a fixed-capacity polyline plus its cached length.
pub struct Course {
    points: Vec<CoursePoint, MAX_COURSE_POINTS>,
    total_m: f64,
}

impl Course {
    /// `None` when the polyline is too short to follow (< 2 points) or over
    /// the tier-1 capacity (> [`MAX_COURSE_POINTS`]).
    pub fn from_points(points: &[CoursePoint]) -> Option<Self> {
        if points.len() < 2 {
            return None;
        }
        let mut v: Vec<CoursePoint, MAX_COURSE_POINTS> = Vec::new();
        v.extend_from_slice(points).ok()?;
        let mut total_m = 0.0;
        for w in points.windows(2) {
            total_m += haversine_metres(w[0].lat_deg, w[0].lon_deg, w[1].lat_deg, w[1].lon_deg);
        }
        Some(Self { points: v, total_m })
    }

    pub fn points(&self) -> &[CoursePoint] {
        &self.points
    }

    pub fn total_m(&self) -> f64 {
        self.total_m
    }

    /// Project a position onto the course: the nearest on-line point, which
    /// segment it fell on, the distance along the course to it, and the
    /// perpendicular offset. `None` for a non-finite position (a course always
    /// has >= 2 points by construction). Mirrors `snapToPolyline`.
    pub fn project(&self, lat_deg: f64, lon_deg: f64) -> Option<Projection> {
        self.project_biased(lat_deg, lon_deg, None)
    }

    /// [`Course::project`] biased toward forward progress along the course.
    ///
    /// Same per-segment nearest-perpendicular-foot geometry as `project`, but
    /// when two segments are near-equally close — an out-and-back / lollipop /
    /// parallel-leg course whose return leg retraces the outbound line — it
    /// prefers the segment at or ahead of `prev_along_m` (the last reported
    /// along-distance) over the earlier one. That keeps along-distance
    /// monotonic-friendly for a runner physically progressing along the route,
    /// so the "distance along course" number no longer stalls, reads ~0, or
    /// jumps backward when the return snaps onto the outbound leg. A genuinely
    /// closer segment still wins — the perpendicular-offset term dominates the
    /// small backward penalty — so a real backtrack along the current leg is
    /// still reported. Watch-local; NOT part of the `snapToPolyline` parity
    /// port. The off-course offset and snapped point are unchanged; only which
    /// overlapping segment (and thus the along-distance) is chosen differs.
    pub fn project_from(
        &self,
        lat_deg: f64,
        lon_deg: f64,
        prev_along_m: f64,
    ) -> Option<Projection> {
        self.project_biased(lat_deg, lon_deg, Some(prev_along_m))
    }

    fn project_biased(
        &self,
        lat_deg: f64,
        lon_deg: f64,
        prev_along_m: Option<f64>,
    ) -> Option<Projection> {
        if !lat_deg.is_finite() || !lon_deg.is_finite() {
            return None;
        }
        let mut best: Option<Projection> = None;
        let mut best_cost = f64::INFINITY;
        let mut cumulative = 0.0;
        for i in 0..self.points.len() - 1 {
            let a = self.points[i];
            let b = self.points[i + 1];
            let seg_len = haversine_metres(a.lat_deg, a.lon_deg, b.lat_deg, b.lon_deg);

            // Local planar frame: metres east/north of segment start `a`, with
            // longitude scaled by cos(lat) so a degree of lon matches a degree
            // of lat in ground distance.
            let cos_lat = libm::cos(to_rad(a.lat_deg));
            let bx = to_rad(b.lon_deg - a.lon_deg) * R_M * cos_lat;
            let by = to_rad(b.lat_deg - a.lat_deg) * R_M;
            let px = to_rad(lon_deg - a.lon_deg) * R_M * cos_lat;
            let py = to_rad(lat_deg - a.lat_deg) * R_M;

            let len_sq = bx * bx + by * by;
            // Degenerate (duplicate) vertices: treat as the start point.
            let t = if len_sq > 0.0 {
                ((px * bx + py * by) / len_sq).clamp(0.0, 1.0)
            } else {
                0.0
            };

            let s_lat = a.lat_deg + (b.lat_deg - a.lat_deg) * t;
            let s_lon = a.lon_deg + (b.lon_deg - a.lon_deg) * t;
            let off = haversine_metres(lat_deg, lon_deg, s_lat, s_lon);
            let along = cumulative + seg_len * t;

            // Unbiased (`prev_along_m` is `None`): pure nearest offset, the
            // strict `<` keeping the earlier segment on a tie — the exact
            // `snapToPolyline` contract. Biased: add a small forward / large
            // backward charge on how far this candidate's along-distance sits
            // from the last one, so an equal-offset retrace overlap resolves to
            // the segment the runner is actually on instead of snapping onto
            // the outbound leg, while a clearly-closer segment still wins.
            let cost = match prev_along_m {
                Some(prev) => {
                    off + ALONG_FWD_BIAS_PER_M * (along - prev).max(0.0)
                        + ALONG_BACK_BIAS_PER_M * (prev - along).max(0.0)
                }
                None => off,
            };

            if cost < best_cost {
                best_cost = cost;
                best = Some(Projection {
                    lat_deg: s_lat,
                    lon_deg: s_lon,
                    segment: i,
                    t,
                    along_m: along,
                    off_m: off,
                });
            }
            cumulative += seg_len;
        }
        best
    }
}

/// The off-course alert latch — the mobile run screen's exact behaviour: the
/// alert fires once when the offset first exceeds [`OFF_COURSE_THRESHOLD_M`],
/// stays latched while the runner is out, and re-arms only once they are back
/// within [`OFF_COURSE_REARM_M`], so drifting along the boundary can't
/// re-trigger it every fix.
#[derive(Default)]
pub struct OffCourseAlert {
    active: bool,
}

impl OffCourseAlert {
    pub const fn new() -> Self {
        Self { active: false }
    }

    /// Feed the latest perpendicular offset; `true` exactly on the
    /// off-course rising edge.
    pub fn update(&mut self, off_m: f64) -> bool {
        if off_m > OFF_COURSE_THRESHOLD_M {
            if !self.active {
                self.active = true;
                return true;
            }
        } else if off_m < OFF_COURSE_REARM_M {
            self.active = false;
        }
        false
    }

    pub fn active(&self) -> bool {
        self.active
    }
}

/// What the Nav page shows for the current position, derived per fix from
/// [`Course::project`] + [`OffCourseAlert`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NavStatus {
    pub off_m: f64,
    pub along_m: f64,
    pub alerting: bool,
    /// The next turn ahead on the course ([`crate::turn_cues`]), carried so the
    /// `record` task can feed the recorder's TurnCue page without owning the
    /// course. `None` when there is no upcoming turn (past the last one, or a
    /// course with no turns).
    pub next_turn: Option<crate::record::TurnCueView>,
}

/// Pixels of breathing room the fit keeps inside each panel edge.
pub const PANEL_MARGIN_PX: u32 = 2;

/// Uniform-scale fit of a course's bounding box into a `w x h` pixel panel,
/// north up, centred on the shorter axis. Longitude spans are scaled by
/// cos(mid-latitude) before fitting — the `track_projection.ts` correction —
/// so a square loop renders square at any latitude.
pub struct PanelFit {
    min_lat: f64,
    min_lon: f64,
    lat_range: f64,
    cos_mid_lat: f64,
    scale: f64,
    x_off: f64,
    y_off: f64,
}

impl PanelFit {
    pub fn fit(course: &Course, w_px: u32, h_px: u32) -> Self {
        let mut min_lat = f64::INFINITY;
        let mut max_lat = f64::NEG_INFINITY;
        let mut min_lon = f64::INFINITY;
        let mut max_lon = f64::NEG_INFINITY;
        for p in course.points() {
            min_lat = min_lat.min(p.lat_deg);
            max_lat = max_lat.max(p.lat_deg);
            min_lon = min_lon.min(p.lon_deg);
            max_lon = max_lon.max(p.lon_deg);
        }
        let lat_range = max_lat - min_lat;
        let cos_mid_lat = libm::cos(to_rad((min_lat + max_lat) / 2.0));
        let x_range = (max_lon - min_lon) * cos_mid_lat;

        let usable_w = (w_px.saturating_sub(1 + 2 * PANEL_MARGIN_PX)) as f64;
        let usable_h = (h_px.saturating_sub(1 + 2 * PANEL_MARGIN_PX)) as f64;
        // Uniform scale: the tighter of the two constraints, each skipped when
        // that axis is degenerate (a straight N-S or E-W course).
        let mut scale = f64::INFINITY;
        if x_range > 0.0 {
            scale = scale.min(usable_w / x_range);
        }
        if lat_range > 0.0 {
            scale = scale.min(usable_h / lat_range);
        }
        if !scale.is_finite() {
            // All points coincident — nothing to scale, centre the dot.
            scale = 0.0;
        }
        let x_off = PANEL_MARGIN_PX as f64 + (usable_w - x_range * scale) / 2.0;
        let y_off = PANEL_MARGIN_PX as f64 + (usable_h - lat_range * scale) / 2.0;
        Self {
            min_lat,
            min_lon,
            lat_range,
            cos_mid_lat,
            scale,
            x_off,
            y_off,
        }
    }

    /// Panel-relative pixel coordinates for a position. On-course points land
    /// inside the panel by construction; an off-course runner's marker can
    /// fall outside — the caller clamps (or clips) as its surface needs.
    pub fn to_px(&self, lat_deg: f64, lon_deg: f64) -> (i32, i32) {
        let x = (lon_deg - self.min_lon) * self.cos_mid_lat * self.scale + self.x_off;
        let y = (self.lat_range - (lat_deg - self.min_lat)) * self.scale + self.y_off;
        (libm::round(x) as i32, libm::round(y) as i32)
    }
}

fn to_rad(deg: f64) -> f64 {
    deg * core::f64::consts::PI / 180.0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `route_snap.test.ts`'s LINE: a ~1.4 km west-east leg at
    /// latitude 51.5, then a ~1.1 km leg turning north.
    fn line() -> Course {
        Course::from_points(&[pt(51.5, -0.12), pt(51.5, -0.1), pt(51.51, -0.1)]).unwrap()
    }

    fn pt(lat_deg: f64, lon_deg: f64) -> CoursePoint {
        CoursePoint { lat_deg, lon_deg }
    }

    /// Ground metres per degree along a great circle — the haversine's own
    /// scale, so distance-anchored fixtures agree with the module under test.
    const M_PER_DEG: f64 = R_M * core::f64::consts::PI / 180.0;

    /// A waypoint `m` metres east of the origin along the equator, matching
    /// `route_geometry.test.ts`'s distWp fixtures.
    fn dist_pt(m: f64) -> CoursePoint {
        pt(0.0, m / M_PER_DEG)
    }

    /// A waypoint `east` metres east and `north` metres north of the origin,
    /// for building out-and-back / lollipop courses whose return retraces the
    /// outbound line. Longitude carries the cos(lat) correction so `east` is a
    /// true ground metre at the (small) test latitude.
    fn en_pt(east_m: f64, north_m: f64) -> CoursePoint {
        let lat = north_m / M_PER_DEG;
        pt(lat, east_m / (M_PER_DEG * libm::cos(to_rad(lat))))
    }

    /// East to 300 m then back to 0 along the same equatorial line: the return
    /// leg is geometrically coincident with the outbound one (~600 m total).
    fn out_and_back() -> Course {
        Course::from_points(&[
            en_pt(0.0, 0.0),
            en_pt(100.0, 0.0),
            en_pt(200.0, 0.0),
            en_pt(300.0, 0.0),
            en_pt(200.0, 0.0),
            en_pt(100.0, 0.0),
            en_pt(0.0, 0.0),
        ])
        .unwrap()
    }

    /// A 200 m stem out (coincident with the stem back) around a distinct
    /// rectangular loop — the stem is retraced, the loop is not (~800 m total).
    fn lollipop() -> Course {
        Course::from_points(&[
            en_pt(0.0, 0.0),
            en_pt(200.0, 0.0),
            en_pt(200.0, 100.0),
            en_pt(300.0, 100.0),
            en_pt(300.0, 0.0),
            en_pt(200.0, 0.0),
            en_pt(0.0, 0.0),
        ])
        .unwrap()
    }

    /// An out-and-back whose return leg runs 30 m north of the outbound leg (a
    /// divided path): the legs are NOT coincident, so offset distinguishes them
    /// and a genuine backtrack is unambiguous (~630 m total).
    fn separated_out_and_back() -> Course {
        Course::from_points(&[
            en_pt(0.0, 0.0),
            en_pt(150.0, 0.0),
            en_pt(300.0, 0.0),
            en_pt(300.0, 30.0),
            en_pt(150.0, 30.0),
            en_pt(0.0, 30.0),
        ])
        .unwrap()
    }

    #[test]
    fn out_and_back_return_collapses_with_project_but_project_from_stays_forward() {
        let c = out_and_back();
        let q = en_pt(150.0, 3.0);
        // Plain `project` can't tell the return leg from the outbound one, so
        // it snaps to the earlier segment: along collapses to ~150 m.
        let plain = c.project(q.lat_deg, q.lon_deg).unwrap();
        assert!(plain.along_m < 200.0, "plain along {}", plain.along_m);
        // A runner whose last along was ~460 m (on the return) is kept forward.
        let biased = c.project_from(q.lat_deg, q.lon_deg, 460.0).unwrap();
        assert!(biased.along_m > 400.0, "biased along {}", biased.along_m);
        // The snapped offset is unchanged — only which segment was chosen.
        assert!((biased.off_m - plain.off_m).abs() < 1.0, "offset moved");
    }

    #[test]
    fn project_from_keeps_along_monotonic_walking_an_out_and_back() {
        let c = out_and_back();
        let total = c.total_m();
        let mut easts: std::vec::Vec<f64> = (0..=30).map(|k| k as f64 * 10.0).collect();
        easts.extend((0..30).rev().map(|k| k as f64 * 10.0));
        let mut prev = 0.0;
        for (i, e) in easts.iter().enumerate() {
            let q = en_pt(*e, 3.0);
            let p = c.project_from(q.lat_deg, q.lon_deg, prev).unwrap();
            assert!(
                p.along_m.is_finite() && p.off_m.is_finite(),
                "nan at step {}",
                i
            );
            assert!(
                p.along_m + 1.0 >= prev,
                "along went back at step {} ({} < {})",
                i,
                p.along_m,
                prev
            );
            prev = p.along_m;
        }
        // Back near the start, but the along-distance has climbed to the far
        // end of the course rather than collapsing to ~0.
        assert!(prev > total - 20.0, "final along {} of {}", prev, total);
    }

    #[test]
    fn project_from_keeps_along_monotonic_walking_a_lollipop() {
        let c = lollipop();
        let total = c.total_m();
        // Plain project on the return stem collapses onto the outbound stem.
        let stem = en_pt(100.0, 0.0);
        let plain = c.project(stem.lat_deg, stem.lon_deg).unwrap();
        assert!(plain.along_m < 200.0, "plain stem along {}", plain.along_m);

        // Walk the polyline itself, four sub-steps per segment, threading the
        // previous along-distance into project_from.
        let pts = c.points();
        let mut prev = 0.0;
        for w in pts.windows(2) {
            for s in 0..4 {
                let f = s as f64 / 4.0;
                let lat = w[0].lat_deg + (w[1].lat_deg - w[0].lat_deg) * f;
                let lon = w[0].lon_deg + (w[1].lon_deg - w[0].lon_deg) * f;
                let p = c.project_from(lat, lon, prev).unwrap();
                assert!(
                    p.along_m + 2.0 >= prev,
                    "along regressed to {} from {}",
                    p.along_m,
                    prev
                );
                prev = p.along_m;
            }
        }
        // Ended on the return stem, not collapsed back to the outbound one.
        assert!(prev > 600.0, "final along {} of {}", prev, total);
    }

    #[test]
    fn project_from_still_reports_a_genuine_backtrack_along_the_current_leg() {
        let c = separated_out_and_back();
        // Forward on the return leg to east=200 m (along ~430)...
        let ahead_q = en_pt(200.0, 30.0);
        let ahead = c
            .project_from(ahead_q.lat_deg, ahead_q.lon_deg, 400.0)
            .unwrap();
        // ...then the runner genuinely reverses to east=250 m (earlier on the
        // same return leg). Its offset is clearly smallest, so it still wins
        // and the along-distance is reported as having gone backward.
        let back_q = en_pt(250.0, 30.0);
        let back = c
            .project_from(back_q.lat_deg, back_q.lon_deg, ahead.along_m)
            .unwrap();
        assert!(
            back.along_m < ahead.along_m,
            "expected a backtrack: {} !< {}",
            back.along_m,
            ahead.along_m
        );
        assert!(
            back.off_m < 5.0,
            "should still be on the return leg, off {}",
            back.off_m
        );
    }

    #[test]
    fn project_from_matches_project_on_a_forward_only_course() {
        // No overlapping segments: the forward bias must not perturb the
        // result — the uniquely-nearest segment always wins.
        let c =
            Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0), dist_pt(300.0)])
                .unwrap();
        for &(east, prev) in &[(50.0, 0.0), (150.0, 100.0), (250.0, 200.0)] {
            let lat = 5.0 / M_PER_DEG;
            let lon = east / M_PER_DEG;
            let plain = c.project(lat, lon).unwrap();
            let biased = c.project_from(lat, lon, prev).unwrap();
            assert_eq!(plain.segment, biased.segment, "segment differs at {}", east);
            assert!(
                (plain.along_m - biased.along_m).abs() < 1e-9,
                "along differs at {}",
                east
            );
        }
    }

    #[test]
    fn from_points_rejects_too_short_and_over_capacity() {
        assert!(Course::from_points(&[]).is_none());
        assert!(Course::from_points(&[pt(51.5, -0.12)]).is_none());
        let too_many: std::vec::Vec<CoursePoint> = (0..=MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        assert!(Course::from_points(&too_many).is_none());
        let at_cap: std::vec::Vec<CoursePoint> = (0..MAX_COURSE_POINTS)
            .map(|i| pt(0.0, i as f64 * 1e-4))
            .collect();
        assert!(Course::from_points(&at_cap).is_some());
    }

    #[test]
    fn project_rejects_a_non_finite_position() {
        let c = line();
        assert_eq!(c.project(f64::NAN, -0.11), None);
        assert_eq!(c.project(51.5, f64::INFINITY), None);
    }

    #[test]
    fn snaps_a_point_above_the_first_segment_straight_down_onto_the_line() {
        let p = line().project(51.502, -0.11).unwrap();
        assert_eq!(p.segment, 0);
        assert!((p.lon_deg - -0.11).abs() < 1e-6, "lon {}", p.lon_deg);
        assert!((p.lat_deg - 51.5).abs() < 1e-6, "lat {}", p.lat_deg);
        assert!((p.t - 0.5).abs() < 0.01, "t {}", p.t);
        // Offset ~0.002 deg latitude ~ 222 m.
        assert!(p.off_m > 180.0 && p.off_m < 260.0, "off {}", p.off_m);
    }

    #[test]
    fn clamps_to_the_start_vertex_for_a_point_before_the_line_begins() {
        let p = line().project(51.5, -0.13).unwrap();
        assert_eq!(p.segment, 0);
        assert_eq!(p.t, 0.0);
        assert!((p.lon_deg - -0.12).abs() < 1e-9);
        assert!(p.along_m.abs() < 1e-6, "along {}", p.along_m);
    }

    #[test]
    fn clamps_to_the_end_vertex_for_a_point_past_the_line_end() {
        let p = line().project(51.52, -0.1).unwrap();
        assert_eq!(p.segment, 1);
        assert_eq!(p.t, 1.0);
        assert!((p.lat_deg - 51.51).abs() < 1e-9);
    }

    #[test]
    fn picks_the_nearer_segment_when_two_are_in_range() {
        let p = line().project(51.505, -0.099).unwrap();
        assert_eq!(p.segment, 1);
    }

    #[test]
    fn along_accumulates_across_segments() {
        // Projecting onto the middle of the second (vertical) leg: the whole
        // first leg plus half the second.
        let p = line().project(51.505, -0.1).unwrap();
        assert_eq!(p.segment, 1);
        assert!((p.t - 0.5).abs() < 0.02, "t {}", p.t);
        assert!(
            p.along_m > 1800.0 && p.along_m < 2050.0,
            "along {}",
            p.along_m
        );
    }

    #[test]
    fn a_point_already_on_the_line_snaps_to_itself_with_zero_offset() {
        let p = line().project(51.5, -0.11).unwrap();
        assert!(p.off_m < 1.0, "off {}", p.off_m);
        assert!((p.lat_deg - 51.5).abs() < 1e-6);
    }

    #[test]
    fn tolerates_duplicate_consecutive_vertices_without_dividing_by_zero() {
        let c = Course::from_points(&[pt(51.5, -0.12), pt(51.5, -0.12), pt(51.5, -0.1)]).unwrap();
        let p = c.project(51.501, -0.11).unwrap();
        assert!(p.along_m.is_finite());
        assert!(p.t.is_finite());
    }

    #[test]
    fn projection_is_deterministic_for_the_same_input() {
        let c = line();
        assert_eq!(c.project(51.503, -0.105), c.project(51.503, -0.105));
    }

    #[test]
    fn along_at_a_vertex_is_its_cumulative_distance() {
        // Three 100 m legs along the equator; the third vertex sits at 200 m.
        let c =
            Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0), dist_pt(300.0)])
                .unwrap();
        let v = dist_pt(200.0);
        let p = c.project(v.lat_deg, v.lon_deg).unwrap();
        assert!((p.along_m - 200.0).abs() < 1.0, "along {}", p.along_m);
    }

    #[test]
    fn along_mid_segment_interpolates() {
        let c = Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0)]).unwrap();
        let mid = dist_pt(150.0);
        let p = c.project(mid.lat_deg, mid.lon_deg).unwrap();
        assert!((p.along_m - 150.0).abs() < 1.0, "along {}", p.along_m);
    }

    #[test]
    fn perpendicular_offset_still_maps_to_the_right_along_distance() {
        // 50 m north of the 150 m mark projects straight back down to 150 m.
        let c = Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0)]).unwrap();
        let p = c.project(50.0 / M_PER_DEG, 150.0 / M_PER_DEG).unwrap();
        assert!((p.along_m - 150.0).abs() < 1.0, "along {}", p.along_m);
        assert!((p.off_m - 50.0).abs() < 1.0, "off {}", p.off_m);
    }

    #[test]
    fn along_stays_within_zero_and_the_total_length() {
        let c = Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0)]).unwrap();
        let total = c.total_m();
        assert!((total - 200.0).abs() < 1.0, "total {}", total);
        let far = dist_pt(10_000.0);
        let p = c.project(far.lat_deg, far.lon_deg).unwrap();
        assert!(
            p.along_m >= 0.0 && p.along_m <= total + 1e-6,
            "along {}",
            p.along_m
        );
    }

    #[test]
    fn projecting_exactly_onto_a_vertex_snaps_there_and_the_earlier_segment_wins() {
        // The 100 m vertex is shared by segments 0 and 1; a fix landing exactly
        // on it has a zero offset to both, and the strict `<` keeps the earlier
        // segment (t == 1) so the along-distance is the vertex's cumulative
        // metres, never re-counted onto the next segment at t == 0.
        let c =
            Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0), dist_pt(300.0)])
                .unwrap();
        let v = dist_pt(100.0);
        let p = c.project(v.lat_deg, v.lon_deg).unwrap();
        assert_eq!(p.segment, 0);
        assert!((p.t - 1.0).abs() < 1e-9, "t {}", p.t);
        assert!(p.off_m < 1e-6, "off {}", p.off_m);
        assert!((p.along_m - 100.0).abs() < 1.0, "along {}", p.along_m);
    }

    #[test]
    fn a_foot_past_the_segment_end_clamps_to_the_end_vertex() {
        // A fix whose perpendicular foot lands beyond the segment end clamps to
        // t == 1 and snaps to that endpoint — never reads past the vertex.
        let c = Course::from_points(&[dist_pt(0.0), dist_pt(100.0)]).unwrap();
        let end = dist_pt(100.0);
        let p = c.project(50.0 / M_PER_DEG, 150.0 / M_PER_DEG).unwrap();
        assert_eq!(p.segment, 0);
        assert_eq!(p.t, 1.0);
        assert!((p.lon_deg - end.lon_deg).abs() < 1e-9, "lon {}", p.lon_deg);
        assert!((p.along_m - c.total_m()).abs() < 1.0, "along {}", p.along_m);
        assert!(p.off_m.is_finite() && p.off_m > 0.0, "off {}", p.off_m);
    }

    #[test]
    fn a_far_off_position_clamps_in_bounds_without_nan() {
        // Ten degrees off a London-scale course: every field stays finite, `t`
        // is a real fraction, the segment index is valid, and along-distance is
        // pinned inside [0, total] by an endpoint clamp — never out of range.
        let c = line();
        let total = c.total_m();
        let p = c.project(61.5, 9.88).unwrap();
        assert!(p.segment < c.points().len() - 1, "segment {}", p.segment);
        assert!((0.0..=1.0).contains(&p.t), "t {}", p.t);
        assert!(p.off_m.is_finite() && p.off_m > 0.0, "off {}", p.off_m);
        assert!(
            p.along_m.is_finite() && p.along_m >= 0.0 && p.along_m <= total + 1e-6,
            "along {}",
            p.along_m
        );
    }

    #[test]
    fn along_distance_is_monotonic_and_finite_walking_the_course() {
        // March a fix east along a three-leg equatorial course, a few metres
        // off the line each step: the reported along-distance never goes
        // backwards and never turns NaN as the runner progresses.
        let c =
            Course::from_points(&[dist_pt(0.0), dist_pt(100.0), dist_pt(200.0), dist_pt(300.0)])
                .unwrap();
        let mut prev = -1.0;
        for k in 0..=30 {
            let east_m = k as f64 * 10.0;
            let p = c.project(5.0 / M_PER_DEG, east_m / M_PER_DEG).unwrap();
            assert!(p.along_m.is_finite(), "along NaN at {}", east_m);
            assert!(p.off_m.is_finite(), "off NaN at {}", east_m);
            assert!(p.along_m + 1e-6 >= prev, "along went back at {}", east_m);
            prev = p.along_m;
        }
    }

    #[test]
    fn a_max_capacity_course_projects_without_panic() {
        let pts: std::vec::Vec<CoursePoint> = (0..MAX_COURSE_POINTS)
            .map(|i| dist_pt(i as f64 * 10.0))
            .collect();
        let c = Course::from_points(&pts).unwrap();
        assert_eq!(c.points().len(), MAX_COURSE_POINTS);
        let p = c.project(3.0 / M_PER_DEG, 1234.0 / M_PER_DEG).unwrap();
        assert!(p.along_m.is_finite() && p.off_m.is_finite());
        assert!(p.segment < MAX_COURSE_POINTS - 1);
    }

    #[test]
    fn off_course_alert_fires_once_and_stays_latched_while_out() {
        let mut a = OffCourseAlert::new();
        assert!(!a.update(10.0));
        assert!(!a.active());
        // Exactly at the threshold is still on course (strict >).
        assert!(!a.update(OFF_COURSE_THRESHOLD_M));
        assert!(!a.active());
        // Crossing fires exactly once; staying out does not re-fire.
        assert!(a.update(41.0));
        assert!(a.active());
        assert!(!a.update(80.0));
        assert!(a.active());
    }

    #[test]
    fn off_course_alert_rearms_only_below_half_the_threshold() {
        let mut a = OffCourseAlert::new();
        assert!(a.update(50.0));
        // Back inside the threshold but above the re-arm band: still latched,
        // and drifting out again does NOT re-fire (the mobile hysteresis).
        assert!(!a.update(30.0));
        assert!(a.active());
        assert!(!a.update(50.0));
        // Fully back on course re-arms; the next excursion fires again.
        assert!(!a.update(10.0));
        assert!(!a.active());
        assert!(a.update(45.0));
    }

    #[test]
    fn off_course_alert_does_not_rearm_exactly_at_the_rearm_boundary() {
        let mut a = OffCourseAlert::new();
        assert!(a.update(50.0));
        assert!(a.active());
        // Exactly at the re-arm distance is still "out" (strict <), matching
        // the mobile run screen's `off < threshold / 2` branch: no re-arm.
        assert!(!a.update(OFF_COURSE_REARM_M));
        assert!(a.active());
        // A hair below re-arms; the next excursion can fire again.
        assert!(!a.update(OFF_COURSE_REARM_M - 0.001));
        assert!(!a.active());
        assert!(a.update(45.0));
    }

    #[test]
    fn off_course_alert_does_not_flap_hovering_at_the_threshold() {
        // Jittering either side of the 40 m boundary fires exactly once — the
        // hysteresis band (re-arm only under 20 m) is what stops a per-fix
        // re-alert.
        let mut a = OffCourseAlert::new();
        let mut fires = 0;
        for off in [39.999, 40.001, 39.999, 40.001, 40.0, 40.001] {
            if a.update(off) {
                fires += 1;
            }
        }
        assert_eq!(fires, 1);
        assert!(a.active());
    }

    #[test]
    fn panel_fit_keeps_course_points_inside_the_panel() {
        // The sim course rectangle at latitude ~40.
        let c = Course::from_points(&[
            pt(40.015, -105.2705),
            pt(40.015, -105.269445),
            pt(40.0158083, -105.269445),
            pt(40.0158083, -105.2705),
            pt(40.015, -105.2705),
        ])
        .unwrap();
        let f = PanelFit::fit(&c, 168, 96);
        for p in c.points() {
            let (x, y) = f.to_px(p.lat_deg, p.lon_deg);
            assert!((0..168).contains(&x), "x {}", x);
            assert!((0..96).contains(&y), "y {}", y);
        }
        // North up: the max-latitude corner renders above the min-latitude one.
        let (_, y_north) = f.to_px(40.0158083, -105.2705);
        let (_, y_south) = f.to_px(40.015, -105.2705);
        assert!(y_north < y_south, "north {} south {}", y_north, y_south);
    }

    #[test]
    fn panel_fit_scales_uniformly_with_the_cos_lat_correction() {
        // A ground-square loop at latitude 60 (lon range = lat range / cos60,
        // i.e. doubled in degrees): with the correction its pixel spans match.
        let lat0 = 60.0;
        let d_lat = 0.001;
        let d_lon = d_lat / libm::cos(to_rad(60.0005));
        let c = Course::from_points(&[
            pt(lat0, 0.0),
            pt(lat0, d_lon),
            pt(lat0 + d_lat, d_lon),
            pt(lat0 + d_lat, 0.0),
        ])
        .unwrap();
        let f = PanelFit::fit(&c, 200, 200);
        let (x0, y0) = f.to_px(lat0, 0.0);
        let (x1, y1) = f.to_px(lat0 + d_lat, d_lon);
        let w = (x1 - x0).abs();
        let h = (y1 - y0).abs();
        assert!((w - h).abs() <= 1, "w {} h {}", w, h);
    }

    #[test]
    fn panel_fit_centres_a_degenerate_axis() {
        // A straight N-S course has no longitude range: it centres on x and
        // still spans the panel height.
        let c = Course::from_points(&[pt(40.0, -105.0), pt(40.001, -105.0)]).unwrap();
        let f = PanelFit::fit(&c, 168, 96);
        let (x0, y0) = f.to_px(40.0, -105.0);
        let (x1, y1) = f.to_px(40.001, -105.0);
        assert_eq!(x0, x1);
        assert!((x0 - 84).abs() <= 2, "x {}", x0);
        assert_eq!(y1 as u32, PANEL_MARGIN_PX);
        assert_eq!(y0 as u32, 96 - 1 - PANEL_MARGIN_PX);
    }

    #[test]
    fn panel_fit_centres_a_fully_degenerate_course() {
        let c = Course::from_points(&[pt(40.0, -105.0), pt(40.0, -105.0)]).unwrap();
        let f = PanelFit::fit(&c, 168, 96);
        let (x, y) = f.to_px(40.0, -105.0);
        assert!((x - 84).abs() <= 2, "x {}", x);
        assert!((y - 48).abs() <= 2, "y {}", y);
    }
}
