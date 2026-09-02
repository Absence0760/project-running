//! Pure geometry helpers for a planned route polyline — the canonical
//! standalone port of web `routes/route_geometry.ts` (twin of
//! `route_geometry.dart`). Keep the algorithm and edge cases in lockstep so the
//! route-detail scrubber and the predictive-live-tracking projection agree
//! across every platform. Web additionally carries `markerPointAtDistance`, the
//! marker-authoring inverse; it has no wrist surface and is not ported, which is
//! why the suites are 36 here against web's 43 rather than equal.
//!
//! Three helpers:
//! - [`interpolate_along_route`] — a normalised `fraction` in `0..=1` to the
//!   distance-weighted position on the polyline, so dragging the scrubber at a
//!   constant rate walks the marker at a constant pace.
//! - [`distance_along_route`] — the inverse: project an arbitrary point onto the
//!   nearest segment and return its cumulative distance-along-route in metres.
//! - [`polyline_length_metres`] — cumulative haversine length.
//!
//! [`crate::course`] mirrors the `distance_along_route` shape for the on-run
//! nav overlay in a per-segment planar frame; this module is the faithful,
//! self-contained port and shares no code with it. Pure logic, no peripherals,
//! no allocator.

use crate::geo::{lon_delta_deg, wrap_lon_deg};
use crate::grade_adjusted_pace::haversine_metres;

const R_M: f64 = 6_371_000.0;

/// A route waypoint in degrees, with an optional elevation the interpolation
/// lerps when both endpoints carry it.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RouteWaypoint {
    pub lat: f64,
    pub lng: f64,
    pub elevation_m: Option<f64>,
}

/// Interpolate the position along `waypoints` at the normalised `fraction`
/// (`0.0` = start, `1.0` = end). `None` when the polyline is too short to
/// interpolate (`< 2` waypoints) or `fraction` is not finite (NaN / ±Infinity)
/// — clamping a non-finite fraction would propagate NaN into the returned
/// lat/lng. Distance-weighted: a long segment takes proportionally more of the
/// range than a short one. An all-coincident polyline (zero total length) snaps
/// to the start.
pub fn interpolate_along_route(
    waypoints: &[RouteWaypoint],
    fraction: f64,
) -> Option<RouteWaypoint> {
    if waypoints.len() < 2 {
        return None;
    }
    if !fraction.is_finite() {
        return None;
    }
    let f = fraction.clamp(0.0, 1.0);
    let total_len = cumulative_length_m(waypoints);
    if total_len <= 0.0 {
        return Some(waypoints[0]);
    }
    let target = total_len * f;
    let last = waypoints.len() - 1;
    let mut seen = 0.0;
    for i in 1..waypoints.len() {
        let a = waypoints[i - 1];
        let b = waypoints[i];
        let seg_len = haversine_metres(a.lat, a.lng, b.lat, b.lng);
        if seg_len <= 0.0 {
            continue;
        }
        let seg_end = seen + seg_len;
        if target <= seg_end || i == last {
            let local_t = ((target - seen) / seg_len).clamp(0.0, 1.0);
            return Some(RouteWaypoint {
                lat: a.lat + (b.lat - a.lat) * local_t,
                lng: wrap_lon_deg(a.lng + lon_delta_deg(a.lng, b.lng) * local_t),
                elevation_m: lerp_nullable(a.elevation_m, b.elevation_m, local_t),
            });
        }
        seen = seg_end;
    }
    Some(waypoints[last])
}

/// Inverse of [`interpolate_along_route`]: given an arbitrary point, find the
/// nearest point on the polyline and return its cumulative
/// distance-along-route in metres (`0` = start). `None` when the polyline has
/// `< 2` waypoints, and `None` for a non-finite fix — an unknown position is not
/// the start line, and a caller substituting 0 names the FIRST cutoff and
/// measures its distance-to-go from the start.
///
/// The live position is rarely exactly on the planned line (GPS drift, course
/// offset), so each segment is projected in its own local planar frame — where
/// it is anchored and accurate — but the candidates are **ranked by the
/// great-circle distance to the projected foot**, not by the residual inside
/// that frame. A perpendicular measured inside a segment's frame is scaled by
/// the cosine of that segment's own start latitude, so the numbers are not
/// comparable across segments: on an out-and-back the return limb anchors
/// further along and always reports the smaller offset to a point equidistant
/// from both, which flips the answer by the length of a limb.
pub fn distance_along_route(
    point_lat: f64,
    point_lng: f64,
    waypoints: &[RouteWaypoint],
) -> Option<f64> {
    if waypoints.len() < 2 {
        return None;
    }
    if !point_lat.is_finite() || !point_lng.is_finite() {
        return None;
    }
    let deg = core::f64::consts::PI / 180.0;
    let r_per_deg = R_M * deg;
    let mut seen = 0.0;
    let mut best = 0.0;
    let mut best_offset = f64::INFINITY;
    for i in 1..waypoints.len() {
        let a = waypoints[i - 1];
        let b = waypoints[i];
        let seg_len = haversine_metres(a.lat, a.lng, b.lat, b.lng);
        let cos_lat = libm::cos(a.lat * deg);
        let bx = lon_delta_deg(a.lng, b.lng) * cos_lat * r_per_deg;
        let by = (b.lat - a.lat) * r_per_deg;
        let px = lon_delta_deg(a.lng, point_lng) * cos_lat * r_per_deg;
        let py = (point_lat - a.lat) * r_per_deg;
        let ab_len_sq = bx * bx + by * by;
        let t = if ab_len_sq <= 0.0 {
            0.0
        } else {
            ((px * bx + py * by) / ab_len_sq).clamp(0.0, 1.0)
        };
        let foot_lat = a.lat + (b.lat - a.lat) * t;
        let foot_lng = wrap_lon_deg(a.lng + lon_delta_deg(a.lng, b.lng) * t);
        let offset = haversine_metres(point_lat, point_lng, foot_lat, foot_lng);
        if offset < best_offset {
            best_offset = offset;
            best = seen + t * seg_len;
        }
        seen += seg_len;
    }
    Some(seen.min(best.max(0.0)))
}

/// Total polyline length in metres via cumulative haversine. `O(n)`.
pub fn polyline_length_metres(waypoints: &[RouteWaypoint]) -> f64 {
    cumulative_length_m(waypoints)
}

fn cumulative_length_m(waypoints: &[RouteWaypoint]) -> f64 {
    let mut total = 0.0;
    for i in 1..waypoints.len() {
        let a = waypoints[i - 1];
        let b = waypoints[i];
        total += haversine_metres(a.lat, a.lng, b.lat, b.lng);
    }
    total
}

fn lerp_nullable(a: Option<f64>, b: Option<f64>, t: f64) -> Option<f64> {
    match (a, b) {
        (None, None) => None,
        (None, Some(b)) => Some(b),
        (Some(a), None) => Some(a),
        (Some(a), Some(b)) => Some(a + (b - a) * t),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wp(lat: f64, lng: f64) -> RouteWaypoint {
        RouteWaypoint {
            lat,
            lng,
            elevation_m: None,
        }
    }

    fn wpe(lat: f64, lng: f64, elev: f64) -> RouteWaypoint {
        RouteWaypoint {
            lat,
            lng,
            elevation_m: Some(elev),
        }
    }

    const M_PER_DEG_LNG: f64 = 111_320.0;

    fn dist_wp(lng_m: f64) -> RouteWaypoint {
        wp(0.0, lng_m / M_PER_DEG_LNG)
    }

    #[test]
    fn interpolate_null_on_empty_waypoints() {
        assert_eq!(interpolate_along_route(&[], 0.5), None);
    }

    #[test]
    fn interpolate_null_on_single_waypoint() {
        assert_eq!(interpolate_along_route(&[wp(0.0, 0.0)], 0.5), None);
    }

    #[test]
    fn interpolate_all_coincident_snaps_to_start() {
        let out =
            interpolate_along_route(&[wp(1.0, 1.0), wp(1.0, 1.0), wp(1.0, 1.0)], 0.5).unwrap();
        assert_eq!(out.lat, 1.0);
        assert_eq!(out.lng, 1.0);
    }

    #[test]
    fn interpolate_fraction_below_zero_clamps_to_start() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.001)], -1.0).unwrap();
        assert!((out.lng - 0.0).abs() < 1e-9);
    }

    #[test]
    fn interpolate_fraction_above_one_clamps_to_end() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.001)], 2.0).unwrap();
        assert!((out.lng - 0.001).abs() < 1e-9);
    }

    #[test]
    fn interpolate_fraction_zero_returns_start_exactly() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.005), wp(0.0, 0.010)], 0.0).unwrap();
        assert_eq!(out.lat, 0.0);
        assert!((out.lng - 0.0).abs() < 1e-9);
    }

    #[test]
    fn interpolate_fraction_one_returns_end_exactly() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.005), wp(0.0, 0.010)], 1.0).unwrap();
        assert_eq!(out.lat, 0.0);
        assert!((out.lng - 0.010).abs() < 1e-9);
    }

    #[test]
    fn interpolate_fraction_half_even_spaced_lands_at_midpoint() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.005), wp(0.0, 0.010)], 0.5).unwrap();
        assert!((out.lng - 0.005).abs() < 1e-6);
    }

    #[test]
    fn interpolate_distance_weighted_long_segment_dominates() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.001), wp(0.0, 0.010)], 0.5).unwrap();
        assert!((out.lng - 0.005).abs() < 1e-6);
    }

    #[test]
    fn interpolate_four_equal_leg_at_quarter_lands_at_first_corner() {
        let out = interpolate_along_route(
            &[
                wp(0.0, 0.0),
                wp(0.0, 0.001),
                wp(0.0, 0.002),
                wp(0.0, 0.003),
                wp(0.0, 0.004),
            ],
            0.25,
        )
        .unwrap();
        assert!((out.lng - 0.001).abs() < 1e-6);
    }

    #[test]
    fn interpolate_out_and_back_uses_path_distance_not_chord() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.001), wp(0.0, 0.0)], 0.5).unwrap();
        assert!((out.lng - 0.001).abs() < 1e-6);
    }

    #[test]
    fn interpolate_elevation_lerps_linearly() {
        let out =
            interpolate_along_route(&[wpe(0.0, 0.0, 100.0), wpe(0.0, 0.001, 200.0)], 0.5).unwrap();
        assert!((out.elevation_m.unwrap_or(0.0) - 150.0).abs() < 0.01);
    }

    #[test]
    fn interpolate_lerp_tolerates_one_sided_null() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wpe(0.0, 0.001, 50.0)], 0.5).unwrap();
        assert_eq!(out.elevation_m, Some(50.0));
    }

    #[test]
    fn interpolate_returns_null_elevation_when_both_sides_null() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.001)], 0.5).unwrap();
        assert_eq!(out.elevation_m, None);
    }

    #[test]
    fn interpolate_non_finite_fraction_returns_none() {
        let line = [wp(0.0, 0.0), wp(0.0, 0.010)];
        assert_eq!(interpolate_along_route(&line, f64::NAN), None);
        assert_eq!(interpolate_along_route(&line, f64::INFINITY), None);
        assert_eq!(interpolate_along_route(&line, f64::NEG_INFINITY), None);
    }

    #[test]
    fn polyline_length_empty_or_single_is_zero() {
        assert_eq!(polyline_length_metres(&[]), 0.0);
        assert_eq!(polyline_length_metres(&[wp(0.0, 0.0)]), 0.0);
    }

    #[test]
    fn polyline_length_hundred_metre_segment_at_equator() {
        let out = polyline_length_metres(&[wp(0.0, 0.0), wp(0.0, 100.0 / M_PER_DEG_LNG)]);
        assert!((out - 100.0).abs() < 1.0);
    }

    #[test]
    fn polyline_length_multi_segment_sums() {
        let step = 100.0 / M_PER_DEG_LNG;
        let out = polyline_length_metres(&[wp(0.0, 0.0), wp(0.0, step), wp(0.0, 2.0 * step)]);
        assert!((out - 200.0).abs() < 1.0);
    }

    #[test]
    fn interpolate_southern_hemisphere_is_symmetric() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(-0.005, 0.0), wp(-0.010, 0.0)], 0.5)
            .unwrap();
        assert!((out.lat - -0.005).abs() < 1e-6);
        assert_eq!(out.lng, 0.0);
    }

    #[test]
    fn interpolate_negative_longitude_is_safe() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, -0.005), wp(0.0, -0.010)], 0.5)
            .unwrap();
        assert!((out.lng - -0.005).abs() < 1e-6);
    }

    #[test]
    fn interpolate_two_waypoint_at_half_is_midpoint() {
        let out = interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.010)], 0.5).unwrap();
        assert!((out.lng - 0.005).abs() < 1e-6);
    }

    #[test]
    fn interpolate_skips_zero_length_segments() {
        let out =
            interpolate_along_route(&[wp(0.0, 0.0), wp(0.0, 0.0), wp(0.0, 0.010)], 0.5).unwrap();
        assert!((out.lng - 0.005).abs() < 1e-6);
    }

    #[test]
    fn interpolate_two_hundred_point_polyline_is_linear() {
        let mut wps: std::vec::Vec<RouteWaypoint> = std::vec::Vec::new();
        for i in 0..=200 {
            wps.push(wp(0.0, i as f64 * 0.0001));
        }
        let out = interpolate_along_route(&wps, 0.5).unwrap();
        assert!((out.lng - 100.0 * 0.0001).abs() < 1e-6, "lng {}", out.lng);
    }

    #[test]
    fn distance_null_on_under_two_waypoints() {
        assert_eq!(distance_along_route(0.0, 0.0, &[]), None);
        assert_eq!(distance_along_route(0.0, 0.0, &[wp(0.0, 0.0)]), None);
    }

    #[test]
    fn distance_point_on_a_vertex_returns_its_cumulative_distance() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0), dist_wp(300.0)];
        let d = distance_along_route(wps[2].lat, wps[2].lng, &wps).unwrap();
        assert!((d - 200.0).abs() < 1.0, "got {}", d);
    }

    #[test]
    fn distance_point_mid_segment_returns_the_interpolated_distance() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0)];
        let d = distance_along_route(0.0, 150.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!((d - 150.0).abs() < 1.0, "got {}", d);
    }

    #[test]
    fn distance_perpendicular_offset_still_maps_to_the_right_along_distance() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0)];
        let d = distance_along_route(50.0 / M_PER_DEG_LNG, 150.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!((d - 150.0).abs() < 1.0, "got {}", d);
    }

    #[test]
    fn distance_point_near_the_end_maps_near_total_length() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0)];
        let total = polyline_length_metres(&wps);
        let d = distance_along_route(0.0, 199.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!((d - 199.0).abs() < 1.0, "got {}", d);
        assert!(d <= total + 1e-6);
    }

    #[test]
    fn distance_picks_the_nearest_of_two_close_segments() {
        let corner = dist_wp(100.0);
        let up = wp(100.0 / M_PER_DEG_LNG, 100.0 / M_PER_DEG_LNG);
        let wps = [dist_wp(0.0), corner, up];
        let d = distance_along_route(-2.0 / M_PER_DEG_LNG, 50.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!(d < 100.0, "expected on the first leg, got {}", d);
        assert!((d - 50.0).abs() < 2.0, "got {}", d);
    }

    #[test]
    fn distance_clamps_to_zero_and_total_length() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0)];
        let total = polyline_length_metres(&wps);
        let d = distance_along_route(0.0, 10_000.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!(d >= 0.0 && d <= total + 1e-6, "got {} (total {})", d, total);
    }

    #[test]
    fn distance_a_later_segment_can_still_win() {
        // Guard against a fix that degenerates into "always the first segment":
        // an L (east 100 m, then north 100 m) probed 2 m east of the vertical
        // leg, near its top, must resolve into the SECOND leg (> 100 m).
        let wps = [
            dist_wp(0.0),
            dist_wp(100.0),
            wp(100.0 / M_PER_DEG_LNG, 100.0 / M_PER_DEG_LNG),
        ];
        let d = distance_along_route(90.0 / M_PER_DEG_LNG, 102.0 / M_PER_DEG_LNG, &wps).unwrap();
        assert!(
            libm::fabs(d - 190.0) < 2.0,
            "expected ~190 m on the second leg, got {}",
            d
        );
    }

    #[test]
    fn distance_out_and_back_does_not_flip_limbs_on_one_centimetre_of_jitter() {
        // 3.47 km due north and back. Ranking candidates by a perpendicular
        // measured inside each segment's OWN planar frame compares
        // incommensurable numbers: the return limb anchors its frame 3.5 km
        // further north, where cos(lat) is smaller, so it always reports the
        // smaller "distance" to a point exactly as far from both. A fix 1 cm
        // off the line then resolves a whole limb further along the course.
        let oab = [wp(45.0, 0.0), wp(45.031_25, 0.0), wp(45.0, 0.0)];
        let total = polyline_length_metres(&oab);
        let mid = 45.015_625;
        let one_cm = 0.01 / (M_PER_DEG_LNG * libm::cos(mid * core::f64::consts::PI / 180.0));

        let on_line = distance_along_route(mid, 0.0, &oab).unwrap();
        let east = distance_along_route(mid, one_cm, &oab).unwrap();
        let west = distance_along_route(mid, -one_cm, &oab).unwrap();

        assert!(
            libm::fabs(east - on_line) < 1.0,
            "1 cm east moved the answer {} m",
            libm::fabs(east - on_line)
        );
        assert!(
            libm::fabs(west - on_line) < 1.0,
            "1 cm west moved the answer {} m",
            libm::fabs(west - on_line)
        );
        assert!(
            libm::fabs(on_line - total / 4.0) < 1.0,
            "expected the outbound limb (~{} m), got {}",
            total / 4.0,
            on_line
        );
    }

    #[test]
    fn distance_none_on_a_non_finite_point_never_zero() {
        let wps = [dist_wp(0.0), dist_wp(100.0), dist_wp(200.0)];
        assert!(distance_along_route(0.0, 100.0 / M_PER_DEG_LNG, &wps).is_some());
        // A NaN or infinite fix is "unknown position", not "at the start" —
        // a caller substituting 0 names the FIRST cutoff and measures the
        // distance-to-go from the start line.
        assert_eq!(distance_along_route(f64::NAN, 0.0, &wps), None);
        assert_eq!(distance_along_route(0.0, f64::INFINITY, &wps), None);
    }

    #[test]
    fn interpolate_a_leg_across_the_antimeridian_stays_on_the_leg() {
        let wps = [wp(0.0, 179.99), wp(0.0, -179.97)];
        let out = interpolate_along_route(&wps, 0.5).unwrap();
        // The midpoint of a 0.04 deg leg anchored at 179.99 is 180.01, which
        // wraps to -179.99 — not 0.01, half a world away.
        assert!(libm::fabs(out.lng - -179.99) < 1e-9, "got {}", out.lng);
        assert_eq!(out.lat, 0.0);
    }

    #[test]
    fn distance_a_point_past_the_antimeridian_projects_onto_the_leg() {
        let wps = [wp(0.0, 179.98), wp(0.0, -179.96)];
        let total = polyline_length_metres(&wps);
        let along = distance_along_route(0.0, -179.99, &wps).unwrap();
        assert!(
            libm::fabs(along - total / 2.0) < 1.0,
            "got {} of {}",
            along,
            total
        );
    }

    #[test]
    fn polyline_length_across_the_antimeridian_spans_the_short_way() {
        let wps = [wp(0.0, 179.98), wp(0.0, -179.96)];
        assert!(libm::fabs(polyline_length_metres(&wps) - 6671.7) < 1.0);
    }
}
