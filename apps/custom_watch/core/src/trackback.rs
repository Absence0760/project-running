//! Back-to-start navigation: the TrackBack breadcrumb + the direction arrow.
//!
//! [`Trackback`] reduces the recorder's accepted fixes (the same seam the flash
//! run-store consumes — see `Recorder::last_fix_stored`) into what a
//! back-to-start glance needs: the live distance and great-circle initial
//! bearing to the run's start point, the runner's current heading, and a
//! fixed-capacity, distance-decimated breadcrumb of the track for a thumbnail
//! map. Pure logic like the rest of `core` — no peripherals, no allocator; the
//! whole buffer lives in RAM and the flash run-store wire format is untouched.
//!
//! The heading is **course over ground**: the bearing between the last two
//! accepted fixes at least [`HEADING_MIN_SEP_M`] apart. There is no
//! magnetometer at tier 1 (the roadmap's compass row is separate hardware), so
//! the arrow is only meaningful while moving — a stationary or jittering runner
//! produces no heading update, and a heading older than [`HEADING_STALE_S`]
//! renders as unknown rather than as a stale arrow.

use crate::grade_adjusted_pace::haversine_metres;
use crate::record::METRES_PER_DEGREE_LAT;

/// Breadcrumb capacity, in stored points. With the initial spacing this covers
/// ~1.9 km before the first thinning; each thinning halves the count and
/// doubles the spacing, so capacity grows logarithmically with run length
/// (seven doublings cover ~245 km) at a fixed ~768 B of RAM.
pub const BREADCRUMB_CAP: usize = 96;

/// Initial breadcrumb spacing: a new point is kept once the runner is at least
/// this far from the last kept point. Doubles on each thinning pass.
pub const BREADCRUMB_SPACING_M: f32 = 20.0;

/// Minimum separation between the two fixes a heading is derived from. The
/// recorder's acceptance filter already rejects sub-3 m jitter, but a bearing
/// over a few metres is still mostly GPS noise — below this gate the previous
/// heading is kept (and left to go stale) rather than replaced by noise.
pub const HEADING_MIN_SEP_M: f64 = 5.0;

/// A heading older than this (seconds of uptime) is unknown, not current — a
/// stopped runner must see `--`, never the arrow their last movement left
/// behind.
pub const HEADING_STALE_S: u32 = 10;

/// Within this distance of the start the bearing is unstable and meaningless
/// ("you have arrived"), so it reads as unknown.
pub const BEARING_MIN_DISTANCE_M: f32 = 5.0;

/// Compass sectors the arrow and the HDG/BRG rows quantise to (22.5° each).
pub const SECTOR_COUNT: u8 = 16;

/// 16-wind compass names, clockwise from north, indexed by sector.
pub const SECTOR_NAMES: [&str; SECTOR_COUNT as usize] = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW",
    "NNW",
];

/// Quantise a compass angle (degrees, any range) to its 16-wind sector,
/// 0 = north / straight ahead, clockwise.
pub fn sector_of_deg(deg: f32) -> u8 {
    let mut d = libm::fmodf(deg, 360.0);
    if d < 0.0 {
        d += 360.0;
    }
    (((d + 11.25) / 22.5) as u8) % SECTOR_COUNT
}

/// Great-circle initial bearing from point 1 toward point 2, degrees clockwise
/// from north in `[0, 360)`.
fn initial_bearing_deg(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let p1 = lat1.to_radians();
    let p2 = lat2.to_radians();
    let dl = (lon2 - lon1).to_radians();
    let y = libm::sin(dl) * libm::cos(p2);
    let x = libm::cos(p1) * libm::sin(p2) - libm::sin(p1) * libm::cos(p2) * libm::cos(dl);
    (libm::atan2(y, x).to_degrees() + 360.0) % 360.0
}

/// A `Copy` view of the navigation state, published to the UI. Breadcrumb
/// points are metre offsets east/north of the run's start (equirectangular at
/// the start latitude), which keeps the map projection a plain affine fit.
#[derive(Clone, Copy, Debug)]
pub struct TrackbackView {
    pub points: [(f32, f32); BREADCRUMB_CAP],
    pub len: usize,
    pub current_e_m: f32,
    pub current_n_m: f32,
    pub distance_to_start_m: f32,
    /// Great-circle initial bearing from the current position back to the
    /// start; `None` until the runner is [`BEARING_MIN_DISTANCE_M`] away.
    pub bearing_to_start_deg: Option<f32>,
    /// Course over ground from the last two sufficiently-separated accepted
    /// fixes; `None` until the first qualifying move. Judge freshness with
    /// [`heading_fresh`](TrackbackView::heading_fresh) before rendering.
    pub heading_deg: Option<f32>,
    /// Uptime second the heading was last derived.
    pub heading_uptime_s: u32,
}

impl TrackbackView {
    pub const fn empty() -> Self {
        Self {
            points: [(0.0, 0.0); BREADCRUMB_CAP],
            len: 0,
            current_e_m: 0.0,
            current_n_m: 0.0,
            distance_to_start_m: 0.0,
            bearing_to_start_deg: None,
            heading_deg: None,
            heading_uptime_s: 0,
        }
    }

    /// Whether a run has produced at least one accepted fix (the start anchor).
    pub fn active(&self) -> bool {
        self.len > 0
    }

    pub fn heading_fresh(&self, uptime_s: u32) -> bool {
        self.heading_deg.is_some()
            && uptime_s.saturating_sub(self.heading_uptime_s) <= HEADING_STALE_S
    }

    /// The heading's 16-wind sector, or `None` when absent or stale.
    pub fn heading_sector(&self, uptime_s: u32) -> Option<u8> {
        self.heading_fresh(uptime_s)
            .then(|| sector_of_deg(self.heading_deg.unwrap_or(0.0)))
    }

    /// The bearing-to-start's 16-wind sector, or `None` near the start.
    pub fn bearing_sector(&self) -> Option<u8> {
        self.bearing_to_start_deg.map(sector_of_deg)
    }

    /// The relative direction arrow: bearing-to-start minus current heading,
    /// quantised to a 16-wind sector where 0 = straight ahead, clockwise.
    /// `None` whenever either input is unknown or the heading is stale — the
    /// honest placeholder beats a stale arrow.
    pub fn arrow_sector(&self, uptime_s: u32) -> Option<u8> {
        if !self.heading_fresh(uptime_s) {
            return None;
        }
        let bearing = self.bearing_to_start_deg?;
        let heading = self.heading_deg?;
        Some(sector_of_deg(bearing - heading))
    }
}

/// The breadcrumb map projected into a pixel region: `out[..len]` is the
/// polyline (breadcrumb points, then the current position as the final vertex),
/// with the start and current markers called out.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackMap {
    pub len: usize,
    pub start: (u16, u16),
    pub current: (u16, u16),
}

/// Fit the breadcrumb (plus start + current) into a `w` x `h` pixel region,
/// north up, aspect preserved, centred, with a 2 px margin. `None` while the
/// view is inactive or the region is too small to read.
pub fn project_track(
    view: &TrackbackView,
    w: u16,
    h: u16,
    out: &mut [(u16, u16); BREADCRUMB_CAP + 1],
) -> Option<TrackMap> {
    if !view.active() || w < 8 || h < 8 {
        return None;
    }
    let mut min_e: f32 = 0.0;
    let mut max_e: f32 = 0.0;
    let mut min_n: f32 = 0.0;
    let mut max_n: f32 = 0.0;
    let current = (view.current_e_m, view.current_n_m);
    for &(e, n) in view.points[..view.len].iter().chain([&current]) {
        min_e = min_e.min(e);
        max_e = max_e.max(e);
        min_n = min_n.min(n);
        max_n = max_n.max(n);
    }
    const MARGIN: f32 = 2.0;
    // A degenerate span (single point) still projects — to the region centre.
    let span_e = (max_e - min_e).max(1.0);
    let span_n = (max_n - min_n).max(1.0);
    let scale =
        ((w as f32 - 1.0 - 2.0 * MARGIN) / span_e).min((h as f32 - 1.0 - 2.0 * MARGIN) / span_n);
    let mid_e = (min_e + max_e) / 2.0;
    let mid_n = (min_n + max_n) / 2.0;
    let cx = (w as f32 - 1.0) / 2.0;
    let cy = (h as f32 - 1.0) / 2.0;
    let px = |e: f32, n: f32| {
        let x = (cx + (e - mid_e) * scale).clamp(0.0, w as f32 - 1.0);
        let y = (cy - (n - mid_n) * scale).clamp(0.0, h as f32 - 1.0);
        (x as u16, y as u16)
    };
    for (i, &(e, n)) in view.points[..view.len].iter().enumerate() {
        out[i] = px(e, n);
    }
    out[view.len] = px(current.0, current.1);
    Some(TrackMap {
        len: view.len + 1,
        start: px(0.0, 0.0),
        current: out[view.len],
    })
}

/// The direction arrow as three line segments (shaft + two barbs) in screen
/// coordinates (y down), pointing along `sector` (0 = up / straight ahead,
/// clockwise) from centre `(cx, cy)` with shaft half-length `r`.
pub fn arrow_lines(sector: u8, cx: i32, cy: i32, r: i32) -> [((i32, i32), (i32, i32)); 3] {
    let theta = (sector % SECTOR_COUNT) as f64 * 22.5f64.to_radians();
    let dir = (libm::sin(theta), -libm::cos(theta));
    let at = |d: (f64, f64), len: f64| {
        (
            cx + libm::round(d.0 * len) as i32,
            cy + libm::round(d.1 * len) as i32,
        )
    };
    let tip = at(dir, r as f64);
    let tail = at(dir, -(r as f64));
    let barb = |off_rad: f64| {
        let a = theta + core::f64::consts::PI + off_rad;
        let d = (libm::sin(a), -libm::cos(a));
        (
            tip.0 + libm::round(d.0 * r as f64 * 0.5) as i32,
            tip.1 + libm::round(d.1 * r as f64 * 0.5) as i32,
        )
    };
    let quarter = core::f64::consts::FRAC_PI_4;
    [(tail, tip), (tip, barb(quarter)), (tip, barb(-quarter))]
}

struct Origin {
    lat_deg: f64,
    lon_deg: f64,
    m_per_deg_lon: f64,
}

pub struct Trackback {
    origin: Option<Origin>,
    current_lat_deg: f64,
    current_lon_deg: f64,
    points: [(f32, f32); BREADCRUMB_CAP],
    len: usize,
    spacing_m: f32,
    anchor_lat_deg: f64,
    anchor_lon_deg: f64,
    heading_deg: Option<f32>,
    heading_uptime_s: u32,
}

impl Default for Trackback {
    fn default() -> Self {
        Self::new()
    }
}

impl Trackback {
    pub const fn new() -> Self {
        Self {
            origin: None,
            current_lat_deg: 0.0,
            current_lon_deg: 0.0,
            points: [(0.0, 0.0); BREADCRUMB_CAP],
            len: 0,
            spacing_m: BREADCRUMB_SPACING_M,
            anchor_lat_deg: 0.0,
            anchor_lon_deg: 0.0,
            heading_deg: None,
            heading_uptime_s: 0,
        }
    }

    /// Clear everything for a new run; the first accepted fix becomes the new
    /// start anchor.
    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Consume one accepted fix (a fix the recorder adopted as a new anchor —
    /// the `last_fix_stored` seam, so this sees exactly the points the flash
    /// track stores). The first call anchors the run's start.
    pub fn on_point(&mut self, lat_deg: f64, lon_deg: f64, uptime_s: u32) {
        let origin = match &self.origin {
            Some(o) => o,
            None => {
                self.origin = Some(Origin {
                    lat_deg,
                    lon_deg,
                    m_per_deg_lon: METRES_PER_DEGREE_LAT * libm::cos(lat_deg.to_radians()),
                });
                self.current_lat_deg = lat_deg;
                self.current_lon_deg = lon_deg;
                self.anchor_lat_deg = lat_deg;
                self.anchor_lon_deg = lon_deg;
                self.points[0] = (0.0, 0.0);
                self.len = 1;
                return;
            }
        };
        self.current_lat_deg = lat_deg;
        self.current_lon_deg = lon_deg;

        let e = ((lon_deg - origin.lon_deg) * origin.m_per_deg_lon) as f32;
        let n = ((lat_deg - origin.lat_deg) * METRES_PER_DEGREE_LAT) as f32;
        let (last_e, last_n) = self.points[self.len - 1];
        let (de, dn) = (e - last_e, n - last_n);
        if de * de + dn * dn >= self.spacing_m * self.spacing_m {
            if self.len == BREADCRUMB_CAP {
                self.thin();
            }
            self.points[self.len] = (e, n);
            self.len += 1;
        }

        let sep = haversine_metres(self.anchor_lat_deg, self.anchor_lon_deg, lat_deg, lon_deg);
        if sep >= HEADING_MIN_SEP_M {
            self.heading_deg =
                Some(
                    initial_bearing_deg(self.anchor_lat_deg, self.anchor_lon_deg, lat_deg, lon_deg)
                        as f32,
                );
            self.heading_uptime_s = uptime_s;
            self.anchor_lat_deg = lat_deg;
            self.anchor_lon_deg = lon_deg;
        }
    }

    /// Halve the breadcrumb by keeping every other point and doubling the
    /// spacing — the whole track stays represented at coarser resolution
    /// instead of the tail falling off.
    fn thin(&mut self) {
        let mut kept = 0;
        let mut i = 0;
        while i < self.len {
            self.points[kept] = self.points[i];
            kept += 1;
            i += 2;
        }
        self.len = kept;
        self.spacing_m *= 2.0;
    }

    pub fn view(&self) -> TrackbackView {
        let Some(origin) = &self.origin else {
            return TrackbackView::empty();
        };
        let distance = haversine_metres(
            self.current_lat_deg,
            self.current_lon_deg,
            origin.lat_deg,
            origin.lon_deg,
        ) as f32;
        let bearing = (distance >= BEARING_MIN_DISTANCE_M).then(|| {
            initial_bearing_deg(
                self.current_lat_deg,
                self.current_lon_deg,
                origin.lat_deg,
                origin.lon_deg,
            ) as f32
        });
        TrackbackView {
            points: self.points,
            len: self.len,
            current_e_m: ((self.current_lon_deg - origin.lon_deg) * origin.m_per_deg_lon) as f32,
            current_n_m: ((self.current_lat_deg - origin.lat_deg) * METRES_PER_DEGREE_LAT) as f32,
            distance_to_start_m: distance,
            bearing_to_start_deg: bearing,
            heading_deg: self.heading_deg,
            heading_uptime_s: self.heading_uptime_s,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LAT0: f64 = 40.0;
    const LON0: f64 = -105.0;

    /// Degrees of longitude per metre eastward at the start latitude.
    fn lon_per_m() -> f64 {
        1.0 / (METRES_PER_DEGREE_LAT * (LAT0.to_radians()).cos())
    }

    fn lat_per_m() -> f64 {
        1.0 / METRES_PER_DEGREE_LAT
    }

    /// Walk due east from the origin in `step_m` hops, one second apart.
    fn east_walk(tb: &mut Trackback, steps: u32, step_m: f64) {
        for i in 0..=steps {
            tb.on_point(LAT0, LON0 + i as f64 * step_m * lon_per_m(), i);
        }
    }

    #[test]
    fn empty_and_reset_views_are_inactive() {
        let tb = Trackback::new();
        let v = tb.view();
        assert!(!v.active());
        assert_eq!(v.distance_to_start_m, 0.0);
        assert!(v.bearing_to_start_deg.is_none());
        assert!(v.heading_deg.is_none());
        assert!(v.arrow_sector(100).is_none());

        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0);
        assert!(tb.view().active());
        tb.reset();
        assert!(!tb.view().active());
        assert_eq!(tb.view().len, 0);
    }

    #[test]
    fn first_point_anchors_the_start() {
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        let v = tb.view();
        assert!(v.active());
        assert_eq!(v.len, 1);
        assert_eq!(v.points[0], (0.0, 0.0));
        assert_eq!(v.distance_to_start_m, 0.0);
        assert!(v.bearing_to_start_deg.is_none(), "at the start: no bearing");
    }

    #[test]
    fn distance_and_bearing_to_start_from_an_east_leg() {
        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0); // ~120 m due east
        let v = tb.view();
        assert!(
            (v.distance_to_start_m - 120.0).abs() < 1.0,
            "distance {}",
            v.distance_to_start_m
        );
        // Start is due west of the runner.
        let brg = v.bearing_to_start_deg.unwrap();
        assert!((brg - 270.0).abs() < 1.0, "bearing {}", brg);
        assert_eq!(v.bearing_sector(), Some(12));
        assert_eq!(SECTOR_NAMES[12], "W");
    }

    #[test]
    fn heading_follows_the_course_over_ground() {
        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0);
        let v = tb.view();
        let hdg = v.heading_deg.unwrap();
        assert!((hdg - 90.0).abs() < 1.0, "heading {}", hdg);
        assert_eq!(v.heading_sector(20), Some(4));
        assert_eq!(SECTOR_NAMES[4], "E");
        // Start behind the runner: the arrow points straight back.
        assert_eq!(v.arrow_sector(20), Some(8));
    }

    #[test]
    fn jitter_around_a_point_never_derives_a_heading() {
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        // Oscillate ±4 m around the start: each hop clears the recorder's 3 m
        // acceptance filter (so trackback sees it), but no fix ever gets 5 m
        // from the heading anchor — a stationary runner's GPS wander must not
        // manufacture a heading.
        for i in 1..=30u32 {
            let e = if i % 2 == 0 { 0.0 } else { 4.0 };
            tb.on_point(LAT0, LON0 + e * lon_per_m(), i);
        }
        let v = tb.view();
        assert!(v.heading_deg.is_none());
        assert!(v.heading_sector(30).is_none());
        assert!(v.arrow_sector(30).is_none(), "no heading -> no arrow");
    }

    #[test]
    fn slow_but_real_movement_still_derives_a_heading() {
        // 4 m hops east: each is below the 5 m gate, but the anchor only moves
        // when a heading is derived, so genuine displacement accumulates past
        // the gate — a power-hiking ultra runner still gets an arrow.
        let mut tb = Trackback::new();
        east_walk(&mut tb, 30, 4.0);
        let v = tb.view();
        let hdg = v.heading_deg.unwrap();
        assert!((hdg - 90.0).abs() < 1.0, "heading {}", hdg);
    }

    #[test]
    fn a_stale_heading_yields_no_arrow() {
        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0);
        let v = tb.view();
        assert_eq!(v.heading_uptime_s, 20);
        assert!(v.heading_fresh(20 + HEADING_STALE_S));
        assert!(v.arrow_sector(20 + HEADING_STALE_S).is_some());
        // One second past the window: the runner stopped — blank, not stale.
        assert!(!v.heading_fresh(21 + HEADING_STALE_S));
        assert!(v.heading_sector(21 + HEADING_STALE_S).is_none());
        assert!(v.arrow_sector(21 + HEADING_STALE_S).is_none());
    }

    #[test]
    fn arrow_sector_is_relative_to_the_heading() {
        // Northbound runner, start to the east: the arrow points right (E = 4).
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        // West 100 m first (so the start ends up east), then turn north.
        for i in 1..=10 {
            tb.on_point(LAT0, LON0 - i as f64 * 10.0 * lon_per_m(), i);
        }
        for i in 1..=10 {
            tb.on_point(
                LAT0 + i as f64 * 10.0 * lat_per_m(),
                LON0 - 100.0 * lon_per_m(),
                10 + i,
            );
        }
        let v = tb.view();
        assert_eq!(v.heading_sector(20), Some(0), "moving north");
        // Start is ~100 m east, ~100 m south: bearing ~135 (SE), relative ~135.
        assert_eq!(v.arrow_sector(20), Some(6));
    }

    #[test]
    fn breadcrumb_keeps_a_point_per_spacing_interval() {
        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0); // 120 m at 20 m spacing
        let v = tb.view();
        // Origin + one point per 20 m crossed (24, 44, ... — 6 m hops).
        assert_eq!(v.len, 6);
        let (e1, n1) = v.points[1];
        assert!((e1 - 24.0).abs() < 0.5, "first kept point at {}", e1);
        assert!(n1.abs() < 0.01);
    }

    #[test]
    fn full_breadcrumb_thins_by_halving_not_by_dropping_the_tail() {
        let mut tb = Trackback::new();
        // 6 m hops east far enough to overflow the buffer: 96 points cover
        // ~1.9 km at 20 m spacing, so walk 3 km.
        east_walk(&mut tb, 500, 6.0);
        let v = tb.view();
        assert!(v.len <= BREADCRUMB_CAP);
        assert!(v.len > BREADCRUMB_CAP / 2, "still densely populated");
        assert_eq!(v.points[0], (0.0, 0.0), "the start survives thinning");
        // The crumb still spans the whole track, at coarser spacing.
        let (last_e, _) = v.points[v.len - 1];
        assert!(
            last_e > 2_900.0,
            "tail still reaches the runner: {}",
            last_e
        );
        // Spacing doubled: consecutive kept points are now ~40 m apart.
        let (e1, _) = v.points[1];
        assert!((36.0..=48.0).contains(&e1), "post-thin spacing: {}", e1);
    }

    #[test]
    fn project_track_fits_the_region_north_up() {
        let mut tb = Trackback::new();
        east_walk(&mut tb, 20, 6.0); // ~120 m east-west line
        let v = tb.view();
        let mut out = [(0u16, 0u16); BREADCRUMB_CAP + 1];
        let map = project_track(&v, 80, 80, &mut out).unwrap();
        assert_eq!(map.len, v.len + 1);
        // Start at the west (left) edge margin, runner at the east (right).
        assert!(map.start.0 < map.current.0);
        assert_eq!(map.start.0, 2);
        assert_eq!(map.current.0, 77);
        // A flat east-west line sits vertically centred.
        assert!((map.start.1 as i32 - 39).abs() <= 1);
        assert_eq!(map.start.1, map.current.1);
        for &(x, y) in &out[..map.len] {
            assert!(x < 80 && y < 80);
        }
        // Aspect preserved: the polyline is monotonic left-to-right.
        for w in out[..map.len].windows(2) {
            assert!(w[0].0 <= w[1].0);
        }
    }

    #[test]
    fn project_track_handles_a_single_point_and_rejects_tiny_regions() {
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        let v = tb.view();
        let mut out = [(0u16, 0u16); BREADCRUMB_CAP + 1];
        // Degenerate span: the lone point projects to the region centre.
        let map = project_track(&v, 80, 80, &mut out).unwrap();
        assert_eq!(map.len, 2);
        assert!((map.start.0 as i32 - 39).abs() <= 1);
        assert!((map.start.1 as i32 - 39).abs() <= 1);
        assert!(project_track(&v, 4, 80, &mut out).is_none());
        assert!(project_track(&TrackbackView::empty(), 80, 80, &mut out).is_none());
    }

    #[test]
    fn arrow_lines_point_along_the_sector() {
        // Sector 0 = straight ahead = up on screen.
        let [(tail, tip), (t1, b1), (t2, b2)] = arrow_lines(0, 30, 30, 20);
        assert_eq!(tip, (30, 10));
        assert_eq!(tail, (30, 50));
        assert_eq!(t1, tip);
        assert_eq!(t2, tip);
        // Barbs trail below the tip, one to each side.
        assert!(b1.1 > tip.1 && b2.1 > tip.1);
        assert!(b1.0 < tip.0 && b2.0 > tip.0);

        // Sector 4 = right on screen.
        let [(tail, tip), _, _] = arrow_lines(4, 30, 30, 20);
        assert_eq!(tip, (50, 30));
        assert_eq!(tail, (10, 30));

        // Sector 8 = behind = down on screen.
        let [(_, tip), _, _] = arrow_lines(8, 30, 30, 20);
        assert_eq!(tip, (30, 50));
    }

    #[test]
    fn buffer_exactly_full_then_one_more_thins_without_panic() {
        let mut tb = Trackback::new();
        // 25 m hops (> the 20 m spacing) so every hop is kept: origin + 95 hops
        // fills the buffer to exactly BREADCRUMB_CAP.
        for i in 0..=95u32 {
            tb.on_point(LAT0, LON0 + i as f64 * 25.0 * lon_per_m(), i);
        }
        assert_eq!(tb.view().len, BREADCRUMB_CAP, "buffer exactly full");
        // The next qualifying point must thin in place, not index past the end.
        tb.on_point(LAT0, LON0 + 96.0 * 25.0 * lon_per_m(), 96);
        let v = tb.view();
        assert!(v.len <= BREADCRUMB_CAP);
        assert!(
            v.len > BREADCRUMB_CAP / 2,
            "still densely populated after one thin"
        );
        assert_eq!(v.points[0], (0.0, 0.0), "the start survives thinning");
        let (last_e, _) = v.points[v.len - 1];
        assert!(last_e > 2_300.0, "tail still reaches the runner: {last_e}");
    }

    #[test]
    fn returning_to_the_exact_start_blanks_the_bearing() {
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        tb.on_point(LAT0, LON0 + 100.0 * lon_per_m(), 1);
        assert!(
            tb.view().bearing_to_start_deg.is_some(),
            "100 m out: a bearing"
        );
        // Jump back onto the exact start: zero displacement, no meaningful bearing.
        tb.on_point(LAT0, LON0, 2);
        let v = tb.view();
        assert_eq!(v.distance_to_start_m, 0.0);
        assert!(
            v.bearing_to_start_deg.is_none(),
            "on the start the bearing is unstable: blank it"
        );
        assert!(v.bearing_sector().is_none());
    }

    #[test]
    fn heading_gate_holds_just_under_five_metres_and_releases_just_over() {
        // A hair under the 5 m separation gate: a real but tiny hop never
        // manufactures a heading out of GPS noise.
        let mut under = Trackback::new();
        under.on_point(LAT0, LON0, 0);
        under.on_point(LAT0, LON0 + 4.9 * lon_per_m(), 1);
        assert!(under.view().heading_deg.is_none());

        // Just over the gate: the same single hop now yields a heading.
        let mut over = Trackback::new();
        over.on_point(LAT0, LON0, 0);
        over.on_point(LAT0, LON0 + 5.1 * lon_per_m(), 1);
        let hdg = over.view().heading_deg.expect("5.1 m clears the gate");
        assert!((hdg - 90.0).abs() < 1.0, "heading {hdg}");
    }

    #[test]
    fn bearing_to_start_wraps_cleanly_through_north() {
        // Runner due south of the start: the start is due north, so the bearing
        // is ~0 and the (atan2 + 360) % 360 wrap must land in [0, 360), never
        // 360 or a negative angle.
        let mut tb = Trackback::new();
        tb.on_point(LAT0, LON0, 0);
        tb.on_point(LAT0 - 100.0 * lat_per_m(), LON0, 1);
        let brg = tb.view().bearing_to_start_deg.unwrap();
        assert!((0.0..360.0).contains(&brg), "bearing in range: {brg}");
        assert!(
            !(1.0..=359.0).contains(&brg),
            "start due north of the runner: {brg}"
        );
        assert_eq!(tb.view().bearing_sector(), Some(0), "sector N");
    }

    #[test]
    fn sector_quantisation_boundaries() {
        assert_eq!(sector_of_deg(0.0), 0);
        assert_eq!(sector_of_deg(11.2), 0);
        assert_eq!(sector_of_deg(11.3), 1);
        assert_eq!(sector_of_deg(90.0), 4);
        assert_eq!(sector_of_deg(348.8), 0);
        assert_eq!(sector_of_deg(348.7), 15);
        assert_eq!(sector_of_deg(-90.0), 12);
        assert_eq!(sector_of_deg(360.0), 0);
        assert_eq!(SECTOR_NAMES[0], "N");
        assert_eq!(SECTOR_NAMES[15], "NNW");
    }
}
