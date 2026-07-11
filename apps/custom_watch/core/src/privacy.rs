//! Privacy zones — geofences clipped from the start and end of any track
//! before it leaves the wrist for a public surface.
//!
//! A parity port of web `routes/privacy.ts` (twin of `privacy.dart`). Zones
//! carry a centre + radius; a point inside any zone is masked. We drop the
//! leading and trailing in-zone runs and keep the contiguous middle — we
//! deliberately don't gap out *interior* in-zone segments (a loop that passes
//! home mid-run and leaves again), because the leak we protect against is
//! "where you live," not "where you've ever been," and gapping the polyline
//! mid-track looks broken. When every point falls in a zone the result is
//! empty, so a caller renders no polyline at all rather than a lone point that
//! gives the location away.
//!
//! Great-circle distance uses the same haversine (`atan2` form) the web/Dart
//! twins use, so a watch clips a track identically to the phone and server.
//! Pure logic, no peripherals, no allocator.

use core::f64::consts::PI;

use heapless::Vec;

/// The `user_device_settings`/`user_settings` prefs key the zone list lives
/// under, mirroring the web `PRIVACY_ZONES_KEY`.
pub const PRIVACY_ZONES_KEY: &str = "privacy_zones";

/// Output capacity for a clipped track. A tier-1 recording is bounded like a
/// course polyline ([`crate::course::MAX_COURSE_POINTS`]); a longer input is
/// clamped to this many points rather than overflowing the fixed buffer.
pub const MAX_CLIPPED_TRACK_POINTS: usize = 256;

/// A privacy geofence: centre coordinate + radius in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PrivacyZone {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub radius_m: f64,
}

/// A track point. The clipping algorithm only reads the coordinate, so that is
/// all this local model carries (mirrors the web `LatLng` the port operates
/// over, not the full recorder fix).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrackPoint {
    pub lat_deg: f64,
    pub lon_deg: f64,
}

/// True when `point` is within any of `zones` by haversine distance. An empty
/// zone list is always false.
pub fn is_in_any_zone(point: &TrackPoint, zones: &[PrivacyZone]) -> bool {
    for z in zones {
        if haversine_metres(point.lat_deg, point.lon_deg, z.lat_deg, z.lon_deg) <= z.radius_m {
            return true;
        }
    }
    false
}

/// Walk forward from the start dropping in-zone points, walk backward from the
/// end doing the same, and keep the contiguous middle. Empty zones or empty
/// input returns the input unchanged (clamped to [`MAX_CLIPPED_TRACK_POINTS`]);
/// an all-in-zone input returns empty.
pub fn clip_points_to_zones(
    points: &[TrackPoint],
    zones: &[PrivacyZone],
) -> Vec<TrackPoint, MAX_CLIPPED_TRACK_POINTS> {
    if zones.is_empty() || points.is_empty() {
        return collect_clamped(points);
    }

    let mut start = 0;
    while start < points.len() && is_in_any_zone(&points[start], zones) {
        start += 1;
    }
    if start >= points.len() {
        return Vec::new();
    }

    let mut end = points.len() - 1;
    while end > start && is_in_any_zone(&points[end], zones) {
        end -= 1;
    }

    collect_clamped(&points[start..=end])
}

fn collect_clamped(points: &[TrackPoint]) -> Vec<TrackPoint, MAX_CLIPPED_TRACK_POINTS> {
    let mut out: Vec<TrackPoint, MAX_CLIPPED_TRACK_POINTS> = Vec::new();
    for p in points {
        if out.push(*p).is_err() {
            break;
        }
    }
    out
}

fn haversine_metres(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    const R: f64 = 6_371_000.0;
    let d_lat = (lat2 - lat1) * PI / 180.0;
    let d_lng = (lng2 - lng1) * PI / 180.0;
    let sin_lat = libm::sin(d_lat / 2.0);
    let sin_lng = libm::sin(d_lng / 2.0);
    let a = sin_lat * sin_lat
        + libm::cos(lat1 * PI / 180.0) * libm::cos(lat2 * PI / 180.0) * sin_lng * sin_lng;
    R * 2.0 * libm::atan2(libm::sqrt(a), libm::sqrt(1.0 - a))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOME: PrivacyZone = PrivacyZone {
        lat_deg: 40.7128,
        lon_deg: -74.006,
        radius_m: 200.0,
    };

    fn offset(lat: f64, lng: f64, d_lng: f64) -> TrackPoint {
        TrackPoint {
            lat_deg: lat,
            lon_deg: lng + d_lng,
        }
    }

    fn at(z: &PrivacyZone) -> TrackPoint {
        TrackPoint {
            lat_deg: z.lat_deg,
            lon_deg: z.lon_deg,
        }
    }

    #[test]
    fn is_in_any_zone_empty_zones() {
        assert!(!is_in_any_zone(
            &TrackPoint {
                lat_deg: 0.0,
                lon_deg: 0.0
            },
            &[]
        ));
    }

    #[test]
    fn is_in_any_zone_center_is_in_zone() {
        assert!(is_in_any_zone(&at(&HOME), &[HOME]));
    }

    #[test]
    fn is_in_any_zone_far_point_is_not() {
        assert!(!is_in_any_zone(
            &offset(HOME.lat_deg, HOME.lon_deg, 0.01),
            &[HOME]
        ));
    }

    #[test]
    fn clip_empty_zones_returns_input() {
        let pts = [
            TrackPoint {
                lat_deg: 1.0,
                lon_deg: 1.0,
            },
            TrackPoint {
                lat_deg: 2.0,
                lon_deg: 2.0,
            },
        ];
        assert_eq!(&clip_points_to_zones(&pts, &[])[..], &pts[..]);
    }

    #[test]
    fn clip_drops_leading_and_trailing_in_zone() {
        let pts = [
            at(&HOME),
            at(&HOME),
            offset(HOME.lat_deg, HOME.lon_deg, 0.01),
            offset(HOME.lat_deg, HOME.lon_deg, 0.02),
            at(&HOME),
        ];
        let out = clip_points_to_zones(&pts, &[HOME]);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0], pts[2]);
        assert_eq!(out[1], pts[3]);
    }

    #[test]
    fn clip_keeps_interior_in_zone_segments() {
        let pts = [
            offset(HOME.lat_deg, HOME.lon_deg, 0.01),
            at(&HOME),
            offset(HOME.lat_deg, HOME.lon_deg, 0.02),
        ];
        assert_eq!(&clip_points_to_zones(&pts, &[HOME])[..], &pts[..]);
    }

    #[test]
    fn clip_every_point_in_zone_returns_empty() {
        let pts = [
            at(&HOME),
            TrackPoint {
                lat_deg: HOME.lat_deg + 0.0001,
                lon_deg: HOME.lon_deg + 0.0001,
            },
        ];
        assert!(clip_points_to_zones(&pts, &[HOME]).is_empty());
    }

    #[test]
    fn clip_multiple_zones() {
        let work = PrivacyZone {
            lat_deg: 40.75,
            lon_deg: -73.99,
            radius_m: 200.0,
        };
        let pts = [
            at(&HOME),
            offset(HOME.lat_deg, HOME.lon_deg, 0.01),
            at(&work),
        ];
        let out = clip_points_to_zones(&pts, &[HOME, work]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0], pts[1]);
    }
}
