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
//! Two further watch-local departures from the port. The per-segment frame and
//! the panel fit take their longitude differences through [`crate::geo`], so a
//! course straddling 180 deg projects onto itself instead of ~40,000 km away —
//! the web original has the same defect and is not fixed here (its own bug, its
//! own lockstep). And [`Course::is_loop`] closes the along-axis into a circle on
//! a course whose ends meet, which web has no concept of at all. Both are
//! additive: on a course that neither straddles the line nor closes, every
//! value is what the port produced, bit for bit.
//!
//! [`PanelFit`] is the display half kept host-testable: it fits the course's
//! bounding box into a pixel panel (longitude scaled by cos(mid-latitude), the
//! same correction `track_projection.ts` applies so a square loop renders
//! square) and maps lat/lon to pixel coordinates; the app's ui task only blits
//! lines between the points this module hands it.

use heapless::Vec;

use crate::geo::{lon_delta_deg, unwrap_lon_deg, wrap_lon_deg};
use crate::grade_adjusted_pace::haversine_metres;

/// Fixed course capacity: 256 points x 16 B = 4 KiB of RAM for the polyline
/// (plus 512 B when a push carries per-point elevation), one flash-slot's
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

/// Ceiling on what the forward-progress bias is ever worth, in metres of
/// equivalent perpendicular offset ([`Course::along_bias_m`] saturates strictly
/// below it).
///
/// The bias exists to break a tie between candidates the geometry cannot
/// separate; charged on the raw along-gap it instead grew without bound, so a
/// stale anchor could outrank kilometres of perpendicular offset and pick a
/// segment the runner is nowhere near — reporting that segment's offset and
/// latching `! OFF CRS` on it. Bounding it at the re-arm radius makes that
/// impossible by construction: no candidate more than this far off the nearest
/// one can win, so a runner within [`OFF_COURSE_REARM_M`] of the line is never
/// reported past [`OFF_COURSE_THRESHOLD_M`] off it.
const MAX_ALONG_BIAS_M: f64 = OFF_COURSE_REARM_M;

/// Tie-break weight on the *unwrapped* along-gap, in metres of equivalent
/// offset per metre of gap.
///
/// A closed course's two ends are the same place, so at the shared start/finish
/// vertex the wrapped gap cannot separate `along = 0` from `along = total_m`:
/// both sit the same distance from the anchor and carry the same perpendicular
/// offset. Nor can the segment order — the earlier representative is the honest
/// one when a run *starts* on the line, the later one when a lap *finishes* on
/// it. This settles the pair in favour of continuity with the last reading, at
/// a weight far below anything the geometry can notice: a whole 100 km lap of
/// unwrapped gap buys 10 cm of offset.
const ALONG_CONTINUITY_PER_M: f64 = 1e-6;

/// A course whose ends sit within this of each other is closed, and its
/// along-axis is a circle rather than a line ([`Course::is_loop`]).
///
/// The off-course threshold is the honest cut: inside it, a runner standing at
/// the finish also projects on-course at the start, so the two ends are one
/// place as far as anything downstream can tell.
pub const LOOP_CLOSURE_M: f64 = OFF_COURSE_THRESHOLD_M;

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

/// A course's bounding box plus the cos(mid-latitude) longitude correction the
/// panel fit scales by — computed once per course, since neither depends on the
/// runner's position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CourseBounds {
    pub min_lat: f64,
    pub max_lat: f64,
    pub min_lon: f64,
    pub max_lon: f64,
    pub cos_mid_lat: f64,
}

impl CourseBounds {
    /// A box from its corners, deriving the cos(mid-latitude) correction.
    pub fn of(min_lat: f64, max_lat: f64, min_lon: f64, max_lon: f64) -> Self {
        Self {
            min_lat,
            max_lat,
            min_lon,
            max_lon,
            cos_mid_lat: libm::cos(to_rad((min_lat + max_lat) / 2.0)),
        }
    }
}

/// A compact in-RAM course: a fixed-capacity polyline, its cached length, the
/// optional per-point elevation the phone pushed alongside it, and the
/// course-invariant geometry every projection would otherwise re-derive.
///
/// `seg_len_m` + `seg_cos_lat` are the two per-segment terms that cost
/// transcendental calls: one haversine (7 of them) and one cosine. Both depend
/// only on the course's own fixed points, so [`Course::project_biased`] — which
/// runs on every published fix while a course is loaded, over up to
/// [`MAX_COURSE_POINTS`] - 1 segments — reads them instead of recomputing them
/// 2,040 times per fix. The segment's local-frame `(bx, by)` deltas are *not*
/// cached: deriving them from `seg_cos_lat` costs no transcendental at all, and
/// two more f64 arrays would double this struct's growth against a RAM budget
/// that already holds three live copies of a course (the `COURSE` watch plus the
/// `nav` and `ui` tasks' own).
#[derive(Clone)]
pub struct Course {
    points: Vec<CoursePoint, MAX_COURSE_POINTS>,
    elev_m: Vec<i16, MAX_COURSE_POINTS>,
    seg_len_m: Vec<f64, MAX_COURSE_POINTS>,
    seg_cos_lat: Vec<f64, MAX_COURSE_POINTS>,
    total_m: f64,
    bounds: CourseBounds,
    is_loop: bool,
}

/// A course is one of the largest structures the firmware holds, and it is held
/// more than once at a time — the `COURSE` watch plus the `nav` and `ui` tasks'
/// own copies — so every byte added here costs that multiple. Adding a field is
/// allowed; doing it without noticing the RAM it multiplies into is not, so the
/// figure is pinned on both targets.
///
/// The two now differ, and in the device's favour: `heapless::Vec`'s length is a
/// 4-byte `usize` on `thumbv7em-none-eabihf` against 8 on the host, so the three
/// of them leave padding holes that `is_loop` drops into for free. It costs the
/// watch nothing and the host 8 B.
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<Course>() == 8784);
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<Course>() == 8792);

impl Course {
    /// `None` when the polyline is too short to follow (< 2 points) or over
    /// the tier-1 capacity (> [`MAX_COURSE_POINTS`]).
    pub fn from_points(points: &[CoursePoint]) -> Option<Self> {
        Self::build(points, None)
    }

    /// [`Course::from_points`] with the per-point elevation profile a `CRS1` v2
    /// push carries (metres, one entry per point). `None` on the same rejections
    /// plus a length that disagrees with the polyline — a course whose elevation
    /// doesn't line up point-for-point would place the profile marker on the
    /// wrong climb, so it is refused rather than trimmed.
    pub fn from_points_with_elevation(points: &[CoursePoint], elev_m: &[i16]) -> Option<Self> {
        if elev_m.len() != points.len() {
            return None;
        }
        Self::build(points, Some(elev_m))
    }

    fn build(points: &[CoursePoint], elev_m: Option<&[i16]>) -> Option<Self> {
        if points.len() < 2 {
            return None;
        }
        let mut v: Vec<CoursePoint, MAX_COURSE_POINTS> = Vec::new();
        v.extend_from_slice(points).ok()?;
        let mut e: Vec<i16, MAX_COURSE_POINTS> = Vec::new();
        if let Some(elev_m) = elev_m {
            e.extend_from_slice(elev_m).ok()?;
        }
        let mut seg_len_m: Vec<f64, MAX_COURSE_POINTS> = Vec::new();
        let mut seg_cos_lat: Vec<f64, MAX_COURSE_POINTS> = Vec::new();
        let mut total_m = 0.0;
        for w in points.windows(2) {
            let len = haversine_metres(w[0].lat_deg, w[0].lon_deg, w[1].lat_deg, w[1].lon_deg);
            seg_len_m.push(len).ok()?;
            seg_cos_lat.push(libm::cos(to_rad(w[0].lat_deg))).ok()?;
            total_m += len;
        }
        let mut min_lat = f64::INFINITY;
        let mut max_lat = f64::NEG_INFINITY;
        let mut min_lon = f64::INFINITY;
        let mut max_lon = f64::NEG_INFINITY;
        for p in points {
            min_lat = min_lat.min(p.lat_deg);
            max_lat = max_lat.max(p.lat_deg);
            // Unwrapped onto the first point's side of the antimeridian, so a
            // course straddling it spans its own width rather than 359-odd
            // degrees — which would collapse the panel fit's scale and draw the
            // whole course as a dot. Identity for a course that doesn't.
            let lon = unwrap_lon_deg(points[0].lon_deg, p.lon_deg);
            min_lon = min_lon.min(lon);
            max_lon = max_lon.max(lon);
        }
        let first = points[0];
        let last = points[points.len() - 1];
        Some(Self {
            points: v,
            elev_m: e,
            seg_len_m,
            seg_cos_lat,
            total_m,
            bounds: CourseBounds::of(min_lat, max_lat, min_lon, max_lon),
            is_loop: haversine_metres(first.lat_deg, first.lon_deg, last.lat_deg, last.lon_deg)
                <= LOOP_CLOSURE_M,
        })
    }

    /// Whether the course closes on itself ([`LOOP_CLOSURE_M`]) — a lap, a
    /// backyard-ultra loop, an out-and-back. Its along-axis wraps, so the
    /// second traversal restarts at zero instead of running past the total.
    pub fn is_loop(&self) -> bool {
        self.is_loop
    }

    pub fn points(&self) -> &[CoursePoint] {
        &self.points
    }

    /// The pushed per-point elevation (metres), or `None` when the course
    /// arrived without one — the profile page then reads an honest "no
    /// elevation" rather than a flat line at zero.
    pub fn elevations(&self) -> Option<&[i16]> {
        if self.elev_m.is_empty() {
            None
        } else {
            Some(&self.elev_m)
        }
    }

    pub fn total_m(&self) -> f64 {
        self.total_m
    }

    /// The course's bounding box + longitude correction, computed at build time
    /// — what [`PanelFit`] fits, so a Nav-page render costs no rescan of the
    /// polyline however often an unrelated wake redraws it.
    pub fn bounds(&self) -> CourseBounds {
        self.bounds
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
    ///
    /// On a closed course ([`Course::is_loop`]) "forward" wraps: the second
    /// traversal restarts at zero rather than reading a lap ahead of itself.
    /// See [`Course::along_bias_m`] for what the bias may and may not buy.
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
            let seg_len = self.seg_len_m[i];

            // Local planar frame: metres east/north of segment start `a`, with
            // longitude scaled by cos(lat) so a degree of lon matches a degree
            // of lat in ground distance. Both longitude deltas take the short
            // way round the antimeridian ([`crate::geo`]) — a plain subtraction
            // reads a 0.04 deg hop across the line as 359.96 deg the other way,
            // which puts the whole frame ~40,000 km out.
            let cos_lat = self.seg_cos_lat[i];
            let b_east_deg = lon_delta_deg(a.lon_deg, b.lon_deg);
            let bx = to_rad(b_east_deg) * R_M * cos_lat;
            let by = to_rad(b.lat_deg - a.lat_deg) * R_M;
            let px = to_rad(lon_delta_deg(a.lon_deg, lon_deg)) * R_M * cos_lat;
            let py = to_rad(lat_deg - a.lat_deg) * R_M;

            let len_sq = bx * bx + by * by;
            // Degenerate (duplicate) vertices: treat as the start point.
            let t = if len_sq > 0.0 {
                ((px * bx + py * by) / len_sq).clamp(0.0, 1.0)
            } else {
                0.0
            };

            let s_lat = a.lat_deg + (b.lat_deg - a.lat_deg) * t;
            let s_lon = wrap_lon_deg(a.lon_deg + b_east_deg * t);
            // Offset as a GREAT-CIRCLE distance to the foot, not a length in
            // this segment's own planar frame.
            //
            // `t` is found in the per-segment frame and that is fine — it is
            // one segment's internal parameter. The offset is not: it is
            // COMPARED across segments, and each frame scales east by its own
            // start latitude's cosine, so the numbers are not commensurate. On
            // a north-south out-and-back with limbs 20 m apart, true offsets
            // that agree to 1e-12 m read 9.988765 vs 9.981872 in their own
            // frames — a systematic ~7 mm bias toward the pole-ward-starting
            // limb, enough to snap onto the wrong leg and flip along-route
            // distance by the full out-and-back length. Web hit exactly this in
            // distanceAlongRoute and fixed it the same way (5ffceec94).
            let off = haversine_metres(lat_deg, lon_deg, s_lat, s_lon);
            let along = cumulative + seg_len * t;

            // Unbiased (`prev_along_m` is `None`): pure nearest offset, the
            // strict `<` keeping the earlier segment on a tie — the exact
            // `snapToPolyline` contract. Biased: charge the candidate for its
            // distance from the last along-distance, so an equal-offset retrace
            // overlap resolves to the segment the runner is actually on instead
            // of snapping onto the outbound leg, while a clearly-closer segment
            // still wins.
            let cost = match prev_along_m {
                Some(prev) => off + self.along_bias_m(along, prev),
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

    /// What the forward-progress bias charges a candidate sitting at `along_m`
    /// when the last reported along-distance was `prev_along_m`, in metres of
    /// equivalent perpendicular offset.
    ///
    /// The gap is measured on the course's own topology: on a closed course
    /// ([`Course::is_loop`]) the along-axis is a circle, so it is taken the
    /// short way round. Without that, every traversal after the first reports
    /// the runner a lap ahead — the anchor still reads the full loop length
    /// while the runner is metres into the next lap, and a backward charge of
    /// `ALONG_BACK_BIAS_PER_M * total_m` buys the finish segment most of the
    /// lap. On a backyard ultra (the same loop, every hour, for days) that
    /// pinned `along_m` a lap ahead and reported the runner's distance from
    /// the corral as perpendicular offset, latching `! OFF CRS`, for kilometres
    /// of every single lap.
    ///
    /// The charge then saturates strictly below [`MAX_ALONG_BIAS_M`] rather
    /// than growing without bound, so no anchor — stale, wrapped, or merely
    /// separated by a long GNSS dropout — can buy a candidate that far off the
    /// nearest one. It is strictly increasing, so it orders two candidates
    /// exactly as the raw product did: what is bounded is the bias's authority
    /// over the geometry, not its direction.
    ///
    /// [`ALONG_CONTINUITY_PER_M`] then settles the one pair the circle leaves
    /// indistinguishable — the two ends of a loop's along-axis at their shared
    /// vertex.
    fn along_bias_m(&self, along_m: f64, prev_along_m: f64) -> f64 {
        let unwrapped = along_m - prev_along_m;
        let mut gap = unwrapped;
        if self.is_loop {
            if gap > self.total_m / 2.0 {
                gap -= self.total_m;
            } else if gap < -self.total_m / 2.0 {
                gap += self.total_m;
            }
        }
        let raw = if gap >= 0.0 {
            ALONG_FWD_BIAS_PER_M * gap
        } else {
            ALONG_BACK_BIAS_PER_M * -gap
        };
        raw / (1.0 + raw / MAX_ALONG_BIAS_M) + ALONG_CONTINUITY_PER_M * libm::fabs(unwrapped)
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
    /// Absolute great-circle bearing from the fix toward its snapped on-course
    /// point, degrees clockwise from north — the numeric way back when the map
    /// cannot show one. The panel fit keeps only [`PANEL_MARGIN_PX`] of slack,
    /// so by the time the off-course latch trips at [`OFF_COURSE_THRESHOLD_M`]
    /// the position marker has usually left the panel entirely; this bearing is
    /// what the Nav page falls back to, in the same 16-wind absolute convention
    /// the Waypoint / Back-to-start BRG rows use (tier 1 has no magnetometer,
    /// so nothing on the watch renders a heading-relative direction as text).
    /// `None` within [`crate::trackback::BEARING_MIN_DISTANCE_M`] of the line,
    /// where the bearing is noise and there is nothing to escape from.
    pub back_to_course_deg: Option<f32>,
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
        Self::from_bounds(course.bounds(), w_px, h_px)
    }

    /// [`PanelFit::fit`] over any box — the auto-zoom window is a runner-centred
    /// box rather than a course, so it fits one directly instead of wrapping two
    /// corners in a throwaway [`Course`].
    pub fn from_bounds(bounds: CourseBounds, w_px: u32, h_px: u32) -> Self {
        let CourseBounds {
            min_lat,
            max_lat,
            min_lon,
            max_lon,
            cos_mid_lat,
        } = bounds;
        let lat_range = max_lat - min_lat;
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
        let x = lon_delta_deg(self.min_lon, lon_deg) * self.cos_mid_lat * self.scale + self.x_off;
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

    /// A Big's-format backyard-ultra loop: 4.167 mi (6,706 m) as a closed
    /// square, the same one sent off every hour for days.
    fn backyard_loop() -> Course {
        let side = 6_706.0 / 4.0;
        Course::from_points(&[
            en_pt(0.0, 0.0),
            en_pt(side, 0.0),
            en_pt(side, side),
            en_pt(0.0, side),
            en_pt(0.0, 0.0),
        ])
        .unwrap()
    }

    /// Walk the polyline itself in `per_seg` sub-steps, threading each
    /// along-distance into the next projection the way the nav task does, and
    /// return the projections in order.
    fn walk(c: &Course, start_along_m: f64, per_seg: usize) -> std::vec::Vec<Projection> {
        let mut prev = start_along_m;
        let mut out = std::vec::Vec::new();
        let pts: std::vec::Vec<CoursePoint> = c.points().to_vec();
        for w in pts.windows(2) {
            for s in 0..per_seg {
                let f = s as f64 / per_seg as f64;
                let lat = w[0].lat_deg + (w[1].lat_deg - w[0].lat_deg) * f;
                let lon = w[0].lon_deg + (w[1].lon_deg - w[0].lon_deg) * f;
                let p = c.project_from(lat, lon, prev).unwrap();
                prev = p.along_m;
                out.push(p);
            }
        }
        let last = pts[pts.len() - 1];
        out.push(c.project_from(last.lat_deg, last.lon_deg, prev).unwrap());
        out
    }

    /// A course straddling 180 deg — Taveuni, Fiji, where the line runs through
    /// the island. Two ~4.3 km legs, the second crossing.
    fn across_the_antimeridian() -> Course {
        Course::from_points(&[pt(-16.8, 179.95), pt(-16.8, 179.99), pt(-16.8, -179.97)]).unwrap()
    }

    #[test]
    fn a_course_across_the_antimeridian_projects_onto_its_own_line() {
        // Every one of these fixes is standing ON the course. The per-segment
        // planar frame used to difference the longitudes plainly, reading the
        // 0.04 deg hop across the line as 359.96 deg the other way, so a runner
        // on the far side read 532 m off at the crossing and 3,087 m off a
        // kilometre past it — a permanent `! OFF CRS` on the course itself.
        let c = across_the_antimeridian();
        let total = c.total_m();
        assert!((total - 8_515.9).abs() < 1.0, "total {}", total);
        let mut prev = 0.0;
        for lon in [
            179.96,
            179.98,
            179.99,
            179.995,
            180.0 - 360.0,
            -179.99,
            -179.97,
        ] {
            let p = c.project(-16.8, lon).unwrap();
            assert!(p.off_m < 1.0, "lon {} read {} m off the line", lon, p.off_m);
            assert!(p.along_m >= prev, "along went back at lon {}", lon);
            prev = p.along_m;
        }
        assert!((prev - total).abs() < 1.0, "ended at {} of {}", prev, total);
        // The snapped point is a real longitude, not one that ran past 180.
        let snapped = c.project(-16.8, 179.995).unwrap();
        assert!(snapped.lon_deg.abs() <= 180.0, "lon {}", snapped.lon_deg);
    }

    #[test]
    fn a_fix_beside_a_course_across_the_antimeridian_reads_its_true_offset() {
        let c = across_the_antimeridian();
        // ~1.1 km north of the line, a hair past the crossing.
        let p = c.project(-16.79, -179.999).unwrap();
        assert!(
            (p.off_m - 1_111.9).abs() < 5.0,
            "off {} beside the crossing",
            p.off_m
        );
        // And a course that does NOT straddle, with the runner across the line
        // from it: 0.02 deg away, which used to read as 38,310 km.
        let east = Course::from_points(&[pt(-16.8, 179.90), pt(-16.8, 179.99)]).unwrap();
        let far = east.project(-16.8, -179.99).unwrap();
        assert!(
            (far.off_m - 2_129.0).abs() < 5.0,
            "off {} across the line",
            far.off_m
        );
    }

    #[test]
    fn a_course_across_the_antimeridian_fits_its_own_width_not_the_globe() {
        // The bounding box is built on the first point's side of the line, so
        // the span is the course's 0.08 deg rather than 359.92 — which would
        // have collapsed the fit's scale and drawn the whole course as a dot.
        let c = across_the_antimeridian();
        let b = c.bounds();
        assert!(
            (b.max_lon - b.min_lon - 0.08).abs() < 1e-9,
            "span {}",
            b.max_lon - b.min_lon
        );
        let f = PanelFit::fit(&c, 168, 96);
        let (x0, _) = f.to_px(-16.8, 179.95);
        let (xmid, _) = f.to_px(-16.8, 179.99);
        let (x1, _) = f.to_px(-16.8, -179.97);
        assert_eq!(x0, PANEL_MARGIN_PX as i32);
        assert_eq!(x1, 168 - 1 - PANEL_MARGIN_PX as i32);
        assert!(x0 < xmid && xmid < x1, "{} {} {}", x0, xmid, x1);
    }

    #[test]
    fn a_closed_course_is_a_loop_and_a_point_to_point_one_is_not() {
        assert!(backyard_loop().is_loop());
        assert!(out_and_back().is_loop());
        assert!(!line().is_loop());
        // Ends 30 m apart still close: a runner standing at either projects
        // on-course at the other.
        assert!(separated_out_and_back().is_loop());
    }

    #[test]
    fn a_second_traversal_of_a_loop_restarts_along_distance_instead_of_reading_a_lap_ahead() {
        // The backyard-ultra case. Lap one leaves the anchor at the full loop
        // length; lap two starts metres from the corral. Charged on the raw
        // along-gap the finish segment stayed cheapest for kilometres, so
        // `along_m` read a lap ahead and `off_m` reported the runner's distance
        // from the corral — 1,676 m at the first corner — latching `! OFF CRS`
        // on a runner who never left the course.
        let c = backyard_loop();
        let total = c.total_m();
        let lap1 = walk(&c, 0.0, 20);
        let end = lap1.last().unwrap().along_m;
        assert!(end > total - 1.0, "lap 1 ended at {} of {}", end, total);

        let lap2 = walk(&c, end, 20);
        for (i, p) in lap2.iter().enumerate() {
            assert!(
                p.off_m < OFF_COURSE_THRESHOLD_M,
                "step {} reported {} m off a course it is standing on",
                i,
                p.off_m
            );
        }
        // A tenth of the way round, along-distance reads a tenth of the loop —
        // not the whole of it.
        let tenth = &lap2[lap2.len() / 10];
        assert!(
            (tenth.along_m - total / 10.0).abs() < total / 20.0,
            "along {} of {} a tenth into lap 2",
            tenth.along_m,
            total
        );
    }

    #[test]
    fn a_run_that_starts_on_a_loops_line_reads_zero_not_a_full_lap() {
        // The other end of the same ambiguity: at the shared start/finish
        // vertex both `0` and `total_m` are the same place and the same gap
        // from a zero anchor. Continuity with the last reading is what picks.
        let c = backyard_loop();
        let start = c.points()[0];
        let first = c.project_from(start.lat_deg, start.lon_deg, 0.0).unwrap();
        assert!(first.along_m < 1.0, "started at {} m along", first.along_m);
        let finish = c
            .project_from(start.lat_deg, start.lon_deg, 6_700.0)
            .unwrap();
        assert!(
            finish.along_m > c.total_m() - 1.0,
            "finished at {} m along",
            finish.along_m
        );
    }

    #[test]
    fn the_bias_can_never_report_a_runner_on_the_line_as_off_course() {
        // The bound MAX_ALONG_BIAS_M buys: whatever the anchor says, a
        // candidate that far off the nearest one cannot win, so a runner on the
        // course is never handed a segment past the off-course threshold. Swept
        // over anchors from nowhere near the truth to a full lap out.
        let courses = [backyard_loop(), out_and_back(), lollipop(), line()];
        for c in &courses {
            let total = c.total_m();
            for k in 0..=20 {
                let prev = total * k as f64 / 20.0;
                for p in walk(c, prev, 6) {
                    assert!(
                        p.off_m < OFF_COURSE_THRESHOLD_M,
                        "anchor {} reported {} m off",
                        prev,
                        p.off_m
                    );
                }
            }
        }
    }

    #[test]
    fn a_long_gnss_dropout_cannot_buy_a_segment_the_runner_has_left() {
        // The same unbounded charge, forwards. A 3 km out-and-back on a divided
        // path, its return leg 60 m north of the outbound one, so the two are
        // told apart by offset alone. The runner loses GNSS in a canyon and
        // reappears 3 km later on the return leg: the forward charge for that
        // progress used to come to 150 m of equivalent offset, which bought the
        // outbound leg 60 m away — reporting the runner 3 km back and, at 60 m
        // off, latching `! OFF CRS` on a leg they had left half an hour ago.
        let c = Course::from_points(&[
            en_pt(0.0, 0.0),
            en_pt(3_000.0, 0.0),
            en_pt(3_000.0, 60.0),
            en_pt(0.0, 60.0),
        ])
        .unwrap();
        assert!(!c.is_loop(), "the ends are 60 m apart");
        let back = en_pt(1_500.0, 60.0);
        let p = c.project_from(back.lat_deg, back.lon_deg, 1_500.0).unwrap();
        assert!(p.off_m < 1.0, "off {}", p.off_m);
        assert!(
            (p.along_m - 4_560.0).abs() < 5.0,
            "along {} after the dropout",
            p.along_m
        );
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
    fn a_plain_course_carries_no_elevation() {
        assert!(line().elevations().is_none());
    }

    #[test]
    fn from_points_with_elevation_keeps_the_series_and_the_geometry() {
        let pts = [pt(51.5, -0.12), pt(51.5, -0.1), pt(51.51, -0.1)];
        let c = Course::from_points_with_elevation(&pts, &[10, 40, 25]).unwrap();
        assert_eq!(c.elevations(), Some(&[10i16, 40, 25][..]));
        assert_eq!(c.points().len(), 3);
        assert!((c.total_m() - line().total_m()).abs() < 1e-9);
    }

    #[test]
    fn from_points_with_elevation_rejects_a_length_mismatch() {
        let pts = [pt(51.5, -0.12), pt(51.5, -0.1), pt(51.51, -0.1)];
        assert!(Course::from_points_with_elevation(&pts, &[10, 40]).is_none());
        assert!(Course::from_points_with_elevation(&pts, &[10, 40, 25, 30]).is_none());
        assert!(Course::from_points_with_elevation(&pts, &[]).is_none());
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

    /// A full-capacity course climbing north while weaving either side of a
    /// meridian: every segment carries its own cos(latitude) and its own
    /// bearing, so a mis-indexed per-segment cache shows up as a wrong answer
    /// rather than as a harmless one (an equatorial or straight-line course
    /// would hide both — cos(0) is 1 and every segment shares a bearing).
    fn max_capacity_serpentine() -> Course {
        let pts: std::vec::Vec<CoursePoint> = (0..MAX_COURSE_POINTS)
            .map(|i| {
                let k = i as f64;
                pt(40.0 + k * 0.0004, -105.0 + libm::sin(k * 0.15) * 0.002)
            })
            .collect();
        Course::from_points(&pts).unwrap()
    }

    /// Metres the cached-geometry projection may differ from the one that
    /// recomputed a haversine per segment. The segment / fraction / along-course
    /// distance / snapped point are bit-identical — the cache holds exactly the
    /// values the loop used to re-derive — so this covers only the perpendicular
    /// offset, which is now measured in the projection's own planar frame
    /// instead of by a second great-circle call to the same foot point. The
    /// largest disagreement over the pinned fixes below is 5.3e-4 m, on a fix
    /// 99.8 km off course.
    const PINNED_OFF_TOLERANCE_M: f64 = 1e-3;

    #[test]
    fn a_max_capacity_projection_matches_its_pre_cache_values() {
        // Captured from the implementation that recomputed each segment's
        // haversine length, cos(latitude) and a great-circle offset on every
        // call. Fields: fix lat/lon, forward-bias anchor, then the expected
        // segment, t, along_m, off_m, snapped lat/lon. Where `t` is 0 or 1 the
        // foot is a vertex and the segment index is the tie-break between the
        // two segments meeting there.
        let expected: &[(f64, f64, Option<f64>, usize, f64, f64, f64, f64, f64)] = &[
            (40.0, -105.0, None, 0, 0.0, 0.0, 0.0, 40.0, -105.0),
            (
                40.0503,
                -105.0009,
                None,
                124,
                9.93930674606744669e-1,
                5.98988127919088492e3,
                6.83747340120398235e1,
                4.00499975722698380e1,
                -1.05000200574541552e2,
            ),
            (
                40.0503,
                -105.0009,
                Some(5000.0),
                124,
                9.93930674606744669e-1,
                5.98988127919088492e3,
                6.83747340120398235e1,
                4.00499975722698380e1,
                -1.05000200574541552e2,
            ),
            (
                40.0201,
                -104.9985,
                None,
                50,
                1.32927872605171443e-1,
                2.41051774326015129e3,
                3.33614906450876347e1,
                4.00200531711490441e1,
                -1.04998113028763157e2,
            ),
            // Repinned when the bias was bounded at MAX_ALONG_BIAS_M: it used
            // to buy segment 51 — 18 m further off — for 39 m of along-
            // distance, and reported the runner 51.4 m off a course they were
            // 33.4 m from, which is over the off-course threshold. A bias that
            // can do that is a bias that can invent an excursion, so the
            // biased answer here is now the unbiased one.
            (
                40.0201,
                -104.9985,
                Some(2500.0),
                50,
                1.32927872605171443e-1,
                2.41051774326015129e3,
                3.33614906450876347e1,
                4.00200531711490441e1,
                -1.04998113028763157e2,
            ),
            (
                40.0998,
                -105.0021,
                None,
                248,
                2.81626857160122313e-1,
                1.18930219487811992e4,
                1.17038930808320160e2,
                4.00993126507428670e1,
                -1.05000880361204835e2,
            ),
            (
                40.1019,
                -105.0,
                None,
                253,
                9.53369090969234945e-1,
                1.21816219687948942e4,
                7.42546187556864936e1,
                4.01015813476363832e1,
                -1.04999232768080134e2,
            ),
            // Repinned with the row above: the old weighting decided this one
            // by 0.01 m of cost, taking the vertex at the end of segment 187
            // (57.572 m off) over the foot on 188 (57.299 m off) to gain 5.6 m
            // of along-distance. Bounded, the nearer foot wins.
            (
                40.0755,
                -104.9993,
                Some(8000.0),
                188,
                1.09220120695894250e-1,
                9.01628929274550100e3,
                5.72988000064919940e1,
                4.00752436880482800e1,
                -1.04999884204428260e2,
            ),
            (
                41.0,
                -105.0,
                None,
                254,
                1.0,
                1.22338993969919502e4,
                9.98530832992895303e4,
                4.01019999999999968e1,
                -1.04998953111603527e2,
            ),
        ];
        let c = max_capacity_serpentine();
        assert_eq!(c.points().len(), MAX_COURSE_POINTS);
        for &(lat, lon, prev, segment, t, along_m, off_m, s_lat, s_lon) in expected {
            let p = match prev {
                Some(prev) => c.project_from(lat, lon, prev).unwrap(),
                None => c.project(lat, lon).unwrap(),
            };
            assert_eq!(p.segment, segment, "segment for {} {}", lat, lon);
            assert_eq!(p.t, t, "t for {} {}", lat, lon);
            assert_eq!(p.along_m, along_m, "along for {} {}", lat, lon);
            assert_eq!(p.lat_deg, s_lat, "snapped lat for {} {}", lat, lon);
            assert_eq!(p.lon_deg, s_lon, "snapped lon for {} {}", lat, lon);
            assert!(
                (p.off_m - off_m).abs() < PINNED_OFF_TOLERANCE_M,
                "off for {} {}: {} vs {}",
                lat,
                lon,
                p.off_m,
                off_m
            );
        }
    }

    #[test]
    fn a_planar_offset_still_agrees_with_the_great_circle_distance_to_the_foot() {
        // The claim the frame swap rests on: measuring the perpendicular offset
        // inside the same planar frame that located the foot point gives the
        // same metres a great-circle call to that foot point would, so the
        // 40 m / 20 m off-course thresholds see an unchanged number.
        let c = max_capacity_serpentine();
        for k in 0..40 {
            let lat = 40.0 + k as f64 * 0.0025;
            let lon = -105.0 + libm::sin(k as f64 * 0.9) * 0.0006;
            let p = c.project(lat, lon).unwrap();
            let great_circle = haversine_metres(lat, lon, p.lat_deg, p.lon_deg);
            assert!(
                (p.off_m - great_circle).abs() < PINNED_OFF_TOLERANCE_M,
                "off {} vs great-circle {} at {} {}",
                p.off_m,
                great_circle,
                lat,
                lon
            );
        }
    }

    #[test]
    fn a_fix_whose_foot_is_a_shared_vertex_keeps_its_along_distance_either_way() {
        // 42 km west of the course, so the foot clamps to a vertex that two
        // segments share. Each of those segments measures the offset in its own
        // frame, and that far out the two frames disagree by ~0.8 m — enough to
        // decide which side of the vertex wins, where the great-circle offset
        // used to tie exactly and the strict `<` always kept the earlier one.
        // Nothing a caller reads moves: the along-course distance and the
        // snapped point are the same either way, and the offset is four orders
        // of magnitude past OFF_COURSE_THRESHOLD_M.
        let c = max_capacity_serpentine();
        let p = c.project(40.06, -105.5).unwrap();
        assert!(
            p.segment == 156 || p.segment == 157,
            "segment {}",
            p.segment
        );
        assert_eq!(p.t, if p.segment == 156 { 1.0 } else { 0.0 });
        assert_eq!(p.along_m, 7.52663595148482727e3);
        assert_eq!(p.lat_deg, 4.00628000000000029e1);
        assert_eq!(p.lon_deg, -1.05001999857321010e2);
        assert!(
            (p.off_m - 4.23826993177377008e4).abs() < 1.0,
            "off {}",
            p.off_m
        );
        assert!(p.off_m > OFF_COURSE_THRESHOLD_M);
    }

    #[test]
    fn an_out_and_back_snaps_to_the_limb_the_runner_is_on() {
        // Two north-south limbs 20 m apart, queried at the exact midpoint. The
        // true ground offsets are identical to 1e-12 m, but ranking candidates
        // in each segment's OWN planar frame (each scaled by its own start
        // latitude's cosine) put a systematic ~7 mm bias on the
        // pole-ward-starting limb — enough to snap onto the return leg and flip
        // along-route distance by the full out-and-back length.
        let lat0 = 51.5_f64;
        let dlat = 3_500.0 / 111_320.0;
        let dlon = 20.0 / (111_320.0 * libm::cos(lat0 * core::f64::consts::PI / 180.0));
        let pts = [
            (lat0, 0.0),
            (lat0 + dlat, 0.0),
            (lat0 + dlat, dlon),
            (lat0, dlon),
        ];
        let c = Course::from_points(&[
            pt(pts[0].0, pts[0].1),
            pt(pts[1].0, pts[1].1),
            pt(pts[2].0, pts[2].1),
            pt(pts[3].0, pts[3].1),
        ])
        .expect("builds");
        // Midpoint of the OUTBOUND limb, offset half way between the two.
        let q_lat = lat0 + dlat / 2.0;
        let q_lon = dlon / 2.0;
        let p = c.project(q_lat, q_lon).expect("projects");
        // The outbound limb runs 0 -> 3500 m; the return limb starts past
        // 3500 + 20. A correct rank lands on the outbound one.
        assert!(
            p.along_m < 3_600.0,
            "snapped to the return limb: along_m = {}",
            p.along_m
        );
    }
}
