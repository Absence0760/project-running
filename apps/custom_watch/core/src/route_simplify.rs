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
//! RDP is recursive on the growable web/Dart sides, with no output cap. Without
//! an allocator the watch can't size a per-input-point flag array — the input
//! track can be far longer than the output capacity — so it runs a priority
//! variant iteratively: it repeatedly splits the kept polyline at the segment
//! whose farthest point deviates most, holding only the kept input indices in a
//! fixed-capacity sorted list. Below the [`MAX_SIMPLIFY_POINTS`] budget the kept
//! set is identical to the recursive twin (RDP's kept set is independent of
//! split order); at the budget it degrades by keeping the most significant
//! points — the whole line is thinned, the tail is never truncated. No recursion.
//!
//! Pure logic, no peripherals, no allocator.

use core::f64::consts::PI;

use heapless::Vec;

const R_M: f64 = 6_371_000.0;

/// Default simplification epsilon in metres — the web `simplifyTrack` default.
/// 10 m keeps the turns that matter for a running route while collapsing GPS
/// jitter; tighter keeps more turns, looser collapses more.
pub const DEFAULT_EPSILON_METRES: f64 = 10.0;

/// Output point budget. The simplified polyline is capped at this many
/// waypoints — a tier-1 course polyline is bounded the same way
/// ([`crate::course::MAX_COURSE_POINTS`]). The input track may be longer: RDP
/// runs over the whole line and, if the epsilon-driven result would exceed the
/// budget, keeps the most significant points up to it rather than truncating the
/// tail. The kept-index list is sized to this cap and can never overflow it.
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
    let n = points.len();
    let mut out: Vec<LatLng, MAX_SIMPLIFY_POINTS> = Vec::new();
    if n < 3 {
        for p in points.iter() {
            let _ = out.push(*p);
        }
        return out;
    }
    for &i in dp_budgeted(points, epsilon_metres).iter() {
        let _ = out.push(points[i]);
    }
    out
}

/// Priority Ramer-Douglas-Peucker over the whole line, bounded to
/// [`MAX_SIMPLIFY_POINTS`] output points. Returns the kept input indices in
/// ascending order, endpoints always included. Repeatedly splits the kept
/// polyline at the segment carrying the point of greatest perpendicular
/// deviation, stopping when no segment's farthest point exceeds `eps` or the
/// budget is reached — so below the budget the kept set matches the recursive
/// twin, and at the budget the most significant points survive across the whole
/// line rather than the tail being dropped. `points.len()` must be >= 3.
fn dp_budgeted(points: &[LatLng], eps: f64) -> Vec<usize, MAX_SIMPLIFY_POINTS> {
    let mut kept: Vec<usize, MAX_SIMPLIFY_POINTS> = Vec::new();
    let _ = kept.push(0);
    let _ = kept.push(points.len() - 1);
    while kept.len() < MAX_SIMPLIFY_POINTS {
        let mut best_dev = eps;
        let mut best_slot = 0;
        let mut best_index = 0;
        let mut found = false;
        for slot in 0..kept.len() - 1 {
            let a = kept[slot];
            let b = kept[slot + 1];
            if b <= a + 1 {
                continue;
            }
            let mut seg_dev = 0.0;
            let mut seg_index = a;
            for i in (a + 1)..b {
                let d = perp_distance_metres(&points[i], &points[a], &points[b]);
                if d > seg_dev {
                    seg_dev = d;
                    seg_index = i;
                }
            }
            if seg_dev > best_dev {
                best_dev = seg_dev;
                best_slot = slot;
                best_index = seg_index;
                found = true;
            }
        }
        if !found {
            break;
        }
        let _ = kept.insert(best_slot + 1, best_index);
    }
    kept
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
    fn simplify_over_256_points_keeps_a_tail_feature_and_endpoints_within_budget() {
        // A mostly-straight line far longer than the output budget, with a sharp
        // detour living well past index 256. The old code truncated to the first
        // 256 points and lost the tail entirely; RDP must now thin the whole line.
        let mut pts: std::vec::Vec<LatLng> = (0..400).map(|i| ll(0.0, i as f64 * 0.001)).collect();
        for p in pts.iter_mut().take(381).skip(370) {
            p.lat = 0.01;
        }
        let out = simplify_track(&pts, DEFAULT_EPSILON_METRES);
        assert!(
            out.len() <= MAX_SIMPLIFY_POINTS,
            "must respect the output budget"
        );
        assert!(out.len() >= 3, "endpoints plus the tail feature survive");
        assert_eq!(out[0], pts[0], "first point preserved");
        assert_eq!(
            out[out.len() - 1],
            pts[399],
            "last point preserved, not the truncated points[255]"
        );
        assert!(
            out.iter().any(|p| p.lat > 0.005),
            "the tail detour past index 256 must survive simplification"
        );
    }

    #[test]
    fn simplify_caps_a_dense_zigzag_at_the_budget_without_dropping_the_tail() {
        // Every interior point is a corner far above epsilon, so unbounded RDP
        // would keep all 600. The budget forces a thinning of the WHOLE line: the
        // output caps at MAX_SIMPLIFY_POINTS, keeps both endpoints, and still
        // represents the tail rather than truncating past index 256.
        let n = 600usize;
        let pts: std::vec::Vec<LatLng> = (0..n)
            .map(|i| ll(if i % 2 == 0 { 0.0 } else { 0.0005 }, i as f64 * 0.001))
            .collect();
        let out = simplify_track(&pts, DEFAULT_EPSILON_METRES);
        assert_eq!(
            out.len(),
            MAX_SIMPLIFY_POINTS,
            "dense corners fill the point budget exactly"
        );
        let idx: std::vec::Vec<usize> = out
            .iter()
            .map(|p| (p.lng / 0.001).round() as usize)
            .collect();
        assert_eq!(*idx.first().unwrap(), 0, "first endpoint kept");
        assert_eq!(
            *idx.last().unwrap(),
            n - 1,
            "last endpoint kept, tail not truncated"
        );
        assert!(
            idx.iter().any(|&i| i > MAX_SIMPLIFY_POINTS && i < n - 1),
            "an interior corner past the 256th point must survive"
        );
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
