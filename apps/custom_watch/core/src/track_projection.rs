//! Track → viewBox projection for the SVG-style track-preview thumbnail.
//!
//! A parity port of web `routes/track_projection.ts` (canonical). The Dart
//! twin is not a standalone file — it lives inside
//! `apps/mobile_android/lib/widgets/track_preview.dart` as `projectTrack`.
//! Keep all three in lockstep: a route saved on the web must render the same
//! shape on the phone list and on the watch.
//!
//! [`project_track`] maps a track into a `[0, vb_w] × [0, vb_h]` box with a
//! `cos(mid_lat)` longitude correction so a square loop at any latitude
//! renders square instead of a horizontally-stretched rectangle. `pad` is the
//! inset margin on every side (web defaults it to [`DEFAULT_PROJECT_PAD`]).
//! Tracks with fewer than two points project to nothing.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use core::f64::consts::PI;

use heapless::Vec;

/// Web's default `pad` argument, exposed so callers match the browser inset.
pub const DEFAULT_PROJECT_PAD: f64 = 4.0;

/// Output capacity: one projected point per input point. A tier-1 preview
/// track is bounded like a course polyline; a longer input has its bounding
/// box computed over every point but only the first this-many are projected,
/// clamped rather than overflowing.
pub const MAX_PROJECTED_POINTS: usize = 256;

/// A track point in degrees. Only `lat` / `lng` drive the projection; a
/// caller's richer point type collapses to these two fields.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrackPoint {
    pub lat: f64,
    pub lng: f64,
}

/// A projected point in viewBox pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Projected {
    pub x: f64,
    pub y: f64,
}

/// Mirrors JS `value || 1e-6`: a zero (or NaN) span collapses to a tiny
/// positive number so a degenerate track can't divide by zero.
fn or_epsilon(value: f64) -> f64 {
    if value == 0.0 || value.is_nan() {
        1e-6
    } else {
        value
    }
}

/// Project `points` into a `[0, vb_w] × [0, vb_h]` viewBox with a
/// `cos(mid_lat)` longitude correction. Returns an empty vec for tracks with
/// fewer than two points.
pub fn project_track(
    points: &[TrackPoint],
    vb_w: f64,
    vb_h: f64,
    pad: f64,
) -> Vec<Projected, MAX_PROJECTED_POINTS> {
    let mut out: Vec<Projected, MAX_PROJECTED_POINTS> = Vec::new();
    if points.len() < 2 {
        return out;
    }
    let mut min_lat = points[0].lat;
    let mut max_lat = points[0].lat;
    let mut min_lng = points[0].lng;
    let mut max_lng = points[0].lng;
    for p in points {
        if p.lat < min_lat {
            min_lat = p.lat;
        }
        if p.lat > max_lat {
            max_lat = p.lat;
        }
        if p.lng < min_lng {
            min_lng = p.lng;
        }
        if p.lng > max_lng {
            max_lng = p.lng;
        }
    }
    // A degree of longitude is shorter than a degree of latitude everywhere
    // except the equator — at 51 °N (London) it's only ~62 % of a latitude
    // degree. Scaling lng by cos(mid_lat) projects the box into equal-distance
    // units so a square loop renders square.
    let mid_lat = (min_lat + max_lat) / 2.0;
    let lng_scale = libm::fabs(libm::cos(mid_lat * PI / 180.0));
    let d_lat = or_epsilon(max_lat - min_lat);
    let d_lng = or_epsilon((max_lng - min_lng) * lng_scale);
    let scale_x = (vb_w - pad * 2.0) / d_lng;
    let scale_y = (vb_h - pad * 2.0) / d_lat;
    let scale = if scale_x < scale_y { scale_x } else { scale_y };
    let off_x = pad + (vb_w - pad * 2.0 - d_lng * scale) / 2.0;
    let off_y = pad + (vb_h - pad * 2.0 - d_lat * scale) / 2.0;
    for p in points {
        let projected = Projected {
            x: off_x + (p.lng - min_lng) * lng_scale * scale,
            // SVG y grows downward; invert latitude so north is up.
            y: off_y + (max_lat - p.lat) * scale,
        };
        if out.push(projected).is_err() {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pt(lat: f64, lng: f64) -> TrackPoint {
        TrackPoint { lat, lng }
    }

    #[test]
    fn returns_empty_for_tracks_under_two_points() {
        assert!(project_track(&[], 100.0, 100.0, DEFAULT_PROJECT_PAD).is_empty());
        assert!(project_track(&[pt(0.0, 0.0)], 100.0, 100.0, DEFAULT_PROJECT_PAD).is_empty());
    }

    #[test]
    fn square_loop_at_51n_renders_square_not_stretched() {
        let d_lat = 100.0 / 111_320.0;
        let d_lng = 100.0 / (111_320.0 * 0.629_320_391);
        let points = [
            pt(51.5074, -0.1278),
            pt(51.5074 + d_lat, -0.1278),
            pt(51.5074 + d_lat, -0.1278 + d_lng),
            pt(51.5074, -0.1278 + d_lng),
            pt(51.5074, -0.1278),
        ];
        let projected = project_track(&points, 240.0, 100.0, DEFAULT_PROJECT_PAD);
        let mut min_x = projected[0].x;
        let mut max_x = projected[0].x;
        let mut min_y = projected[0].y;
        let mut max_y = projected[0].y;
        for p in projected.iter() {
            if p.x < min_x {
                min_x = p.x;
            }
            if p.x > max_x {
                max_x = p.x;
            }
            if p.y < min_y {
                min_y = p.y;
            }
            if p.y > max_y {
                max_y = p.y;
            }
        }
        let width = max_x - min_x;
        let height = max_y - min_y;
        assert!(
            (width - height).abs() / height < 0.02,
            "a 100 m x 100 m loop at 51 N must render square: width={width} height={height}"
        );
    }

    #[test]
    fn preserves_diagonal_of_degenerate_horizontal_segment() {
        let projected = project_track(
            &[pt(0.0, 0.0), pt(0.0, 0.01)],
            100.0,
            100.0,
            DEFAULT_PROJECT_PAD,
        );
        assert_eq!(projected.len(), 2);
        assert!((projected[0].y - projected[1].y).abs() < 1e-6);
    }

    #[test]
    fn honours_custom_pad_value() {
        let points = [pt(0.0, 0.0), pt(0.001, 0.001)];
        let tight = project_track(&points, 100.0, 100.0, 0.0);
        let padded = project_track(&points, 100.0, 100.0, 20.0);
        let tight_span = (tight[1].x - tight[0].x).abs();
        let padded_span = (padded[1].x - padded[0].x).abs();
        assert!(
            padded_span < tight_span,
            "padded {padded_span} should be < tight {tight_span}"
        );
    }
}
