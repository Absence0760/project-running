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

use crate::geo::unwrap_lon_deg;

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

/// A positive, finite span for the projection scale. Mirrors web's
/// `spanOrEpsilon` and the Dart twin's `_spanOrEpsilon`.
///
/// Deliberately NOT the JS `value || 1e-6` this port was first written against.
/// That form is falsy-only: it catches an exact zero and lets a 1e-7 span
/// through, which fits a stationary jitter cluster — a runner who hit Start and
/// Stop indoors — across the whole panel instead of collapsing it to the dot it
/// is. Web fixed that; this rail did not follow.
///
/// The `is_finite` half mirrors web's `Number.isFinite` and is belt-and-braces
/// on both rails rather than a live path: reaching an infinite span needs an
/// infinite latitude, and `cos(inf)` has already poisoned `lng_scale` to NaN by
/// then, so both forms hand back NaN either way. It is untested for that
/// reason, not by omission.
fn span_or_epsilon(value: f64) -> f64 {
    if value.is_finite() && value > 1e-6 {
        value
    } else {
        1e-6
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
    // Longitudes are expressed on the first point's side of the antimeridian,
    // so a track that crosses it spans its own width instead of ~360 deg (which
    // collapsed the fitted scale to a dot). Identity inside a hemisphere.
    let ref_lng = points[0].lng;
    let mut min_lat = points[0].lat;
    let mut max_lat = points[0].lat;
    let mut min_lng = ref_lng;
    let mut max_lng = ref_lng;
    for p in points {
        if p.lat < min_lat {
            min_lat = p.lat;
        }
        if p.lat > max_lat {
            max_lat = p.lat;
        }
        let lng = unwrap_lon_deg(ref_lng, p.lng);
        if lng < min_lng {
            min_lng = lng;
        }
        if lng > max_lng {
            max_lng = lng;
        }
    }
    // A degree of longitude is shorter than a degree of latitude everywhere
    // except the equator — at 51 °N (London) it's only ~62 % of a latitude
    // degree. Scaling lng by cos(mid_lat) projects the box into equal-distance
    // units so a square loop renders square.
    let mid_lat = (min_lat + max_lat) / 2.0;
    let lng_scale = libm::fabs(libm::cos(mid_lat * PI / 180.0));
    let d_lat = span_or_epsilon(max_lat - min_lat);
    let d_lng = span_or_epsilon((max_lng - min_lng) * lng_scale);
    let scale_x = (vb_w - pad * 2.0) / d_lng;
    let scale_y = (vb_h - pad * 2.0) / d_lat;
    let scale = if scale_x < scale_y { scale_x } else { scale_y };
    let off_x = pad + (vb_w - pad * 2.0 - d_lng * scale) / 2.0;
    let off_y = pad + (vb_h - pad * 2.0 - d_lat * scale) / 2.0;
    for p in points {
        let projected = Projected {
            x: off_x + (unwrap_lon_deg(ref_lng, p.lng) - min_lng) * lng_scale * scale,
            // SVG y grows downward; invert latitude so north is up.
            y: off_y + (max_lat - p.lat) * scale,
        };
        if out.push(projected).is_err() {
            break;
        }
    }
    out
}

/// True iff the track's bounding-box diagonal exceeds ~5 m — i.e. it is worth
/// drawing at panel scale. A runner who hits Start + Stop indoors records a
/// non-empty run of near-identical fixes; without this gate the preview
/// projects them all onto one pixel and renders a meaningless dot.
///
/// Longitudes are unwrapped onto the first fix's side of the antimeridian
/// first: a raw min/max reads a jitter cluster AT the line as a 359.99 deg span,
/// which defeats the gate for exactly the stationary case it exists to catch.
///
/// Port of web `isTrackRenderable`; the Dart twin lives inside
/// `track_preview.dart`.
pub fn is_track_renderable(track: &[TrackPoint]) -> bool {
    if track.len() < 2 {
        return false;
    }
    let ref_lng = track[0].lng;
    let mut min_lat = track[0].lat;
    let mut max_lat = track[0].lat;
    let mut min_lng = ref_lng;
    let mut max_lng = ref_lng;
    for p in track {
        if p.lat < min_lat {
            min_lat = p.lat;
        }
        if p.lat > max_lat {
            max_lat = p.lat;
        }
        let lng = unwrap_lon_deg(ref_lng, p.lng);
        if lng < min_lng {
            min_lng = lng;
        }
        if lng > max_lng {
            max_lng = lng;
        }
    }
    let d_lat_m = (max_lat - min_lat) * 111_320.0;
    let d_lng_m = (max_lng - min_lng) * 111_320.0 * libm::cos(min_lat * PI / 180.0);
    libm::sqrt(d_lat_m * d_lat_m + d_lng_m * d_lng_m) > 5.0
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

    // Web's `spanOrEpsilon` clamps at 1e-6; the falsy-only `|| 1e-6` this port
    // was written against caught only an exact zero. A sub-epsilon span is the
    // stationary jitter cluster the preview exists to collapse, so the two
    // forms disagree by four orders of magnitude on exactly that track.
    #[test]
    fn a_sub_epsilon_span_is_clamped_not_fitted_to_the_panel() {
        // ~1 cm of jitter in both axes at the equator: both spans land far
        // under 1e-6 deg, so the clamp decides the whole fit.
        let jitter = [pt(0.0, 0.0), pt(9e-8, 9e-8)];
        let projected = project_track(&jitter, 100.0, 100.0, DEFAULT_PROJECT_PAD);
        assert_eq!(projected.len(), 2);
        let spread_y = libm::fabs(projected[1].y - projected[0].y);
        let spread_x = libm::fabs(projected[1].x - projected[0].x);
        // 9e-8 / 1e-6 of the 92 px drawable band is ~8.3 px. Passing the raw
        // span through instead would fit the cluster across the whole 92 px.
        assert!(
            spread_y < 12.0 && spread_x < 12.0,
            "a centimetre of jitter must stay a blob: x={spread_x} y={spread_y}"
        );
    }

    #[test]
    fn a_track_across_the_antimeridian_fits_its_own_width_not_the_whole_world() {
        // A 0.01 deg x 0.01 deg box straddling the line. Its longitudes span
        // 0.01 deg, not the 359.99 deg a raw min/max reads, so the fit is the
        // same one the identical box a degree west of the line gets.
        let across = [
            pt(0.0, 179.995),
            pt(0.01, 179.995),
            pt(0.01, -179.995),
            pt(0.0, -179.995),
        ];
        let west = [
            pt(0.0, 178.995),
            pt(0.01, 178.995),
            pt(0.01, 179.005),
            pt(0.0, 179.005),
        ];
        let a = project_track(&across, 100.0, 100.0, DEFAULT_PROJECT_PAD);
        let w = project_track(&west, 100.0, 100.0, DEFAULT_PROJECT_PAD);
        assert_eq!(a.len(), 4);
        for i in 0..a.len() {
            assert!(
                libm::fabs(a[i].x - w[i].x) < 1e-6,
                "x[{}] {} vs {}",
                i,
                a[i].x,
                w[i].x
            );
            assert!(
                libm::fabs(a[i].y - w[i].y) < 1e-6,
                "y[{}] {} vs {}",
                i,
                a[i].y,
                w[i].y
            );
        }
        // And the box actually uses the panel rather than collapsing to a dot.
        assert!(
            libm::fabs(a[2].x - a[0].x) > 50.0,
            "span {}",
            libm::fabs(a[2].x - a[0].x)
        );
    }

    #[test]
    fn renderable_rejects_empty_single_point_and_sub_5m_jitter() {
        assert!(!is_track_renderable(&[]));
        assert!(!is_track_renderable(&[pt(51.5074, -0.1278)]));
        // ~1 m diagonal - GPS noise from a stationary device.
        assert!(!is_track_renderable(&[
            pt(51.5074, -0.1278),
            pt(51.507_400_9, -0.127_800_9),
        ]));
    }

    #[test]
    fn renderable_accepts_a_tiny_but_genuine_lap() {
        // ~14 m diagonal - small but real.
        assert!(is_track_renderable(&[
            pt(51.5074, -0.1278),
            pt(51.507_49, -0.127_81),
        ]));
    }

    #[test]
    fn renderable_rejects_a_stationary_jitter_cluster_on_the_antimeridian() {
        // ~2 m of jitter straddling 180 deg. A raw min/max reads the span as
        // 359.99 deg (~40,000 km), so the gate passes exactly the standing-still
        // case it exists to catch.
        assert!(!is_track_renderable(&[
            pt(0.0, 179.999_992),
            pt(0.0, -179.999_992),
            pt(0.000_009, 179.999_995),
        ]));
    }

    #[test]
    fn renderable_accepts_a_genuine_run_crossing_the_antimeridian() {
        assert!(is_track_renderable(&[
            pt(0.0, 179.999_5),
            pt(0.0, -179.999_5),
        ]));
    }
}
