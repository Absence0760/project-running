//! Ramer-Douglas-Peucker track simplification + the route summary a saved
//! `routes` row needs.
//!
//! A parity port of web `routes/route_simplify.ts` (twin of the Android
//! `route_simplify.dart`). [`simplify_track`] returns the subset of a noisy GPS
//! track that preserves its shape within `epsilon_metres` of perpendicular
//! distance from the straight-line chords; [`summarize_route_from_track`] folds
//! that into the three numbers a route row carries — simplified waypoints,
//! equirectangular distance, positive elevation gain. Perpendicular distance
//! uses an equirectangular projection centred on the chord's start, which is
//! cheap and accurate enough at the scale RDP cares about (tens of metres).
//!
//! RDP is recursive on the growable web/Dart sides. Without an allocator the
//! watch runs it iteratively over an explicit fixed-capacity stack of pending
//! `(first, last)` ranges, and the kept-point flags live in a fixed bool array
//! rather than a heap-allocated one — same kept set, same output, no recursion.
//!
//! Pure logic, no peripherals, no allocator.

use core::f64::consts::PI;

use heapless::Vec;

const R_M: f64 = 6_371_000.0;

/// Default simplification epsilon in metres — the web `simplifyTrack` default.
/// 10 m keeps the turns that matter for a running route while collapsing GPS
/// jitter; tighter keeps more turns, looser collapses more.
pub const DEFAULT_EPSILON_METRES: f64 = 10.0;

/// Point capacity. A tier-1 recording is bounded like a course polyline
/// ([`crate::course::MAX_COURSE_POINTS`]); an input longer than this is clamped
/// to its first [`MAX_SIMPLIFY_POINTS`] points rather than overflowing the fixed
/// buffers. The RDP pending-range stack and the kept-point flags are sized to
/// this cap: in the pathological all-kept case the stack holds one range per
/// point, so it can never overflow at or below the cap.
pub const MAX_SIMPLIFY_POINTS: usize = 256;

/// A track / route waypoint in degrees, with an optional elevation. Mirrors the
/// web `LatLng` — a missing elevation is `None` (the web omits the `ele` key).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct LatLng {
    pub lat: f64,
    pub lng: f64,
    pub ele: Option<f64>,
}

/// The route-row inputs derived from a raw track: simplified waypoints, the
/// summed equirectangular distance, and the positive elevation gain. Mirrors
/// the web `RouteSummary`.
pub struct RouteSummary {
    pub waypoints: Vec<LatLng, MAX_SIMPLIFY_POINTS>,
    pub distance_m: f64,
    pub elevation_m: f64,
}

/// Simplify `points` with Ramer-Douglas-Peucker, keeping a subset that stays
/// within `epsilon_metres` of the straight-line chords. Fewer than three points
/// are returned unchanged. The first and last points are always retained.
pub fn simplify_track(points: &[LatLng], epsilon_metres: f64) -> Vec<LatLng, MAX_SIMPLIFY_POINTS> {
    let n = points.len().min(MAX_SIMPLIFY_POINTS);
    let mut out: Vec<LatLng, MAX_SIMPLIFY_POINTS> = Vec::new();
    if n < 3 {
        for p in points.iter().take(n) {
            let _ = out.push(*p);
        }
        return out;
    }
    let mut keep = [false; MAX_SIMPLIFY_POINTS];
    keep[0] = true;
    keep[n - 1] = true;
    dp_step(points, 0, n - 1, epsilon_metres, &mut keep);
    for i in 0..n {
        if keep[i] {
            let _ = out.push(points[i]);
        }
    }
    out
}

fn dp_step(points: &[LatLng], first: usize, last: usize, eps: f64, keep: &mut [bool]) {
    let mut stack: Vec<(usize, usize), MAX_SIMPLIFY_POINTS> = Vec::new();
    let _ = stack.push((first, last));
    while let Some((first, last)) = stack.pop() {
        if last <= first + 1 {
            continue;
        }
        let mut max_dist = 0.0;
        let mut max_index = first;
        for i in (first + 1)..last {
            let d = perp_distance_metres(&points[i], &points[first], &points[last]);
            if d > max_dist {
                max_dist = d;
                max_index = i;
            }
        }
        if max_dist > eps {
            keep[max_index] = true;
            let _ = stack.push((first, max_index));
            let _ = stack.push((max_index, last));
        }
    }
}

/// Perpendicular distance from `p` to the segment `a`-`b`, in metres, over an
/// equirectangular projection centred on `a`.
fn perp_distance_metres(p: &LatLng, a: &LatLng, b: &LatLng) -> f64 {
    let lat_rad = a.lat * PI / 180.0;
    let cos_lat = libm::cos(lat_rad);
    let x = |w: &LatLng| (w.lng * PI / 180.0) * cos_lat * R_M;
    let y = |w: &LatLng| (w.lat * PI / 180.0) * R_M;

    let ax = x(a);
    let ay = y(a);
    let bx = x(b);
    let by = y(b);
    let px = x(p);
    let py = y(p);

    let dx = bx - ax;
    let dy = by - ay;
    let len_sq = dx * dx + dy * dy;
    if len_sq == 0.0 {
        let ex = px - ax;
        let ey = py - ay;
        return libm::sqrt(ex * ex + ey * ey);
    }
    let t = ((px - ax) * dx + (py - ay) * dy) / len_sq;
    let t_clamped = t.clamp(0.0, 1.0);
    let proj_x = ax + t_clamped * dx;
    let proj_y = ay + t_clamped * dy;
    let fx = px - proj_x;
    let fy = py - proj_y;
    libm::sqrt(fx * fx + fy * fy)
}

/// Total positive elevation change across the polyline, in metres. A waypoint
/// pair contributes only when both carry an elevation and the second is higher;
/// a `None` in the middle breaks the chain rather than bridging it.
pub fn compute_elevation_gain(track: &[LatLng]) -> f64 {
    let mut gain = 0.0;
    for i in 1..track.len() {
        if let (Some(prev), Some(curr)) = (track[i - 1].ele, track[i].ele) {
            if curr > prev {
                gain += curr - prev;
            }
        }
    }
    gain
}

/// Turn a raw GPS track into the route-row inputs: simplified waypoints,
/// summed equirectangular distance, and positive elevation gain over the
/// simplified polyline. Distance uses a `cos(midLat)` east-west correction, so
/// it is exact for east-west travel at any latitude and close enough at running
/// scales elsewhere.
pub fn summarize_route_from_track(track: &[LatLng], epsilon_metres: f64) -> RouteSummary {
    let simplified = simplify_track(track, epsilon_metres);
    let mut waypoints: Vec<LatLng, MAX_SIMPLIFY_POINTS> = Vec::new();
    for p in simplified.iter() {
        let _ = waypoints.push(LatLng {
            lat: p.lat,
            lng: p.lng,
            ele: p.ele,
        });
    }
    let mut distance = 0.0;
    for i in 1..simplified.len() {
        let a = simplified[i - 1];
        let b = simplified[i];
        let d_lat = (b.lat - a.lat) * PI / 180.0;
        let d_lng = (b.lng - a.lng) * PI / 180.0;
        let mid_lat = ((a.lat + b.lat) / 2.0) * PI / 180.0;
        let x = d_lng * libm::cos(mid_lat);
        let y = d_lat;
        distance += libm::sqrt(x * x + y * y) * R_M;
    }
    RouteSummary {
        waypoints,
        distance_m: distance,
        elevation_m: compute_elevation_gain(&simplified),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ll(lat: f64, lng: f64) -> LatLng {
        LatLng {
            lat,
            lng,
            ele: None,
        }
    }

    fn lle(lat: f64, lng: f64, ele: f64) -> LatLng {
        LatLng {
            lat,
            lng,
            ele: Some(ele),
        }
    }

    #[test]
    fn simplify_fewer_than_three_points_returns_input_unchanged() {
        assert!(simplify_track(&[], DEFAULT_EPSILON_METRES).is_empty());
        let one = [ll(0.0, 0.0)];
        assert_eq!(&simplify_track(&one, DEFAULT_EPSILON_METRES)[..], &one[..]);
        let two = [ll(0.0, 0.0), ll(0.0, 1.0)];
        assert_eq!(&simplify_track(&two, DEFAULT_EPSILON_METRES)[..], &two[..]);
    }

    #[test]
    fn simplify_keeps_clean_straight_line_as_just_its_endpoints() {
        let pts: std::vec::Vec<LatLng> = (0..=10).map(|i| ll(0.0, f64::from(i) * 0.001)).collect();
        let out = simplify_track(&pts, 1.0);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0], pts[0]);
        assert_eq!(out[out.len() - 1], pts[pts.len() - 1]);
    }

    #[test]
    fn simplify_preserves_a_sharp_corner_above_epsilon() {
        let pts = [
            ll(0.0, 0.0),
            ll(0.0, 0.001),
            ll(0.001, 0.001),
            ll(0.001, 0.002),
        ];
        let out = simplify_track(&pts, 5.0);
        assert!(out.len() >= 3);
        let has_corner = out.iter().any(|p| p.lat == 0.001 && p.lng == 0.001);
        assert!(has_corner, "corner waypoint should survive simplification");
    }

    #[test]
    fn simplify_collapses_sub_epsilon_jitter_on_a_straight_line() {
        let pts = [
            ll(0.0, 0.0),
            ll(0.0000001, 0.0005),
            ll(-0.0000002, 0.001),
            ll(0.0, 0.0015),
            ll(0.0, 0.002),
        ];
        let out = simplify_track(&pts, 10.0);
        assert_eq!(
            out.len(),
            2,
            "sub-cm jitter on a 200 m straight line collapses"
        );
    }

    #[test]
    fn simplify_first_and_last_points_always_retained() {
        let pts = [ll(0.0, 0.0), ll(0.0001, 0.0001), ll(0.0, 0.0002)];
        let out = simplify_track(&pts, 1000.0);
        assert_eq!(out[0].lat, 0.0);
        assert_eq!(out[0].lng, 0.0);
        assert_eq!(out[out.len() - 1].lng, 0.0002);
    }

    #[test]
    fn simplify_does_not_mutate_the_input() {
        let pts = [ll(0.0, 0.0), ll(0.0, 0.001), ll(0.0, 0.002)];
        let before = pts;
        let _ = simplify_track(&pts, 1.0);
        assert_eq!(pts, before);
    }

    #[test]
    fn elevation_gain_accumulates_only_positive_deltas() {
        let track = [
            lle(0.0, 0.0, 100.0),
            lle(0.0, 0.001, 110.0),
            lle(0.0, 0.002, 105.0),
            lle(0.0, 0.003, 120.0),
        ];
        assert_eq!(compute_elevation_gain(&track), 25.0);
    }

    #[test]
    fn elevation_gain_tracks_without_elevation_return_zero() {
        let track = [ll(0.0, 0.0), ll(0.0, 0.001), ll(0.0, 0.002)];
        assert_eq!(compute_elevation_gain(&track), 0.0);
    }

    #[test]
    fn elevation_gain_null_elevations_are_skipped() {
        let track = [lle(0.0, 0.0, 100.0), ll(0.0, 0.001), lle(0.0, 0.002, 110.0)];
        assert_eq!(compute_elevation_gain(&track), 0.0);
    }

    #[test]
    fn elevation_gain_empty_or_single_point_track_returns_zero() {
        assert_eq!(compute_elevation_gain(&[]), 0.0);
        assert_eq!(compute_elevation_gain(&[lle(0.0, 0.0, 100.0)]), 0.0);
    }

    #[test]
    fn summarize_produces_waypoints_distance_and_elevation() {
        let deg_per_km = 360.0 / 40_000.0;
        let track: std::vec::Vec<LatLng> = (0..=100)
            .map(|i| lle(0.0, f64::from(i) * deg_per_km * 0.01, f64::from(i) * 0.5))
            .collect();
        let out = summarize_route_from_track(&track, 10.0);
        assert!(out.waypoints.len() <= track.len(), "should simplify");
        assert!(out.waypoints.len() >= 2, "must keep endpoints");
        assert!(
            (out.distance_m - 1000.0).abs() < 10.0,
            "expected ~1000 m, got {}",
            out.distance_m
        );
        assert!(
            out.elevation_m >= 40.0 && out.elevation_m <= 50.0,
            "expected ~50 m gain, got {}",
            out.elevation_m
        );
    }

    #[test]
    fn summarize_passes_ele_through_when_present_drops_when_absent() {
        let track = [lle(0.0, 0.0, 10.0), ll(0.0, 0.01), lle(0.0, 0.02, 20.0)];
        let out = summarize_route_from_track(&track, 5.0);
        let eles: std::vec::Vec<Option<f64>> = out.waypoints.iter().map(|w| w.ele).collect();
        assert_eq!(eles[0], Some(10.0));
        assert_eq!(eles[eles.len() - 1], Some(20.0));
    }

    #[test]
    fn summarize_single_point_track_returns_the_point_with_zero_distance() {
        let out = summarize_route_from_track(&[ll(0.0, 0.0)], 10.0);
        assert_eq!(out.waypoints.len(), 1);
        assert_eq!(out.distance_m, 0.0);
        assert_eq!(out.elevation_m, 0.0);
    }

    #[test]
    fn summarize_empty_track_returns_zeros() {
        let out = summarize_route_from_track(&[], 10.0);
        assert!(out.waypoints.is_empty());
        assert_eq!(out.distance_m, 0.0);
        assert_eq!(out.elevation_m, 0.0);
    }

    #[test]
    fn summarize_distance_is_symmetric_under_reversal() {
        let track = [
            ll(47.0, 8.5),
            ll(47.001, 8.501),
            ll(47.002, 8.502),
            ll(47.003, 8.503),
            ll(47.004, 8.504),
        ];
        let mut reversed = track;
        reversed.reverse();
        let forward = summarize_route_from_track(&track, 5.0);
        let backward = summarize_route_from_track(&reversed, 5.0);
        assert!((forward.distance_m - backward.distance_m).abs() < 0.001);
    }

    #[test]
    fn summarize_cos_midlat_correction_kicks_in_at_high_latitudes() {
        let step_lng = 0.01;
        let at_equator = summarize_route_from_track(&[ll(0.0, 0.0), ll(0.0, step_lng)], 1.0);
        let at_60n = summarize_route_from_track(&[ll(60.0, 0.0), ll(60.0, step_lng)], 1.0);
        let ratio = at_60n.distance_m / at_equator.distance_m;
        assert!(
            (ratio - 0.5).abs() < 0.001,
            "expected cos(60) ~ 0.5 ratio, got {}",
            ratio
        );
    }
}
