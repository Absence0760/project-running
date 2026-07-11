//! Templated route describer — turn a route's stored stats into structured,
//! locale/unit-agnostic facts plus a canonical English sentence, without
//! calling any model. This is the always-works L1 baseline for the
//! "Describe this route" affordance: it runs offline, costs nothing, and is
//! the fallback the model-enhancement path degrades to.
//!
//! A parity port of web `routes/route_description.ts` (twin of
//! `route_description.dart`): keep the classification thresholds, clause set,
//! ordering, edge cases, and the twelve twin tests in lockstep. The web
//! `localisedTemplate` helper is a UI/i18n concern and has no watch port.
//!
//! Reuses [`crate::distance_bands::band_for_distance`] for the race-distance
//! band — the band catalogue is not re-declared here. Pure logic, no
//! peripherals, no allocator.

use crate::distance_bands::{band_for_distance, DistanceBandKey};
use crate::grade_adjusted_pace::haversine_metres;
use core::fmt::Write;
use heapless::String;

/// Route shape inferred from the endpoints.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RouteShape {
    Loop,
    OutAndBack,
    PointToPoint,
}

/// Elevation character bucketed from total gain over distance (m/km).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ElevationProfile {
    Flat,
    Rolling,
    Hilly,
    Mountainous,
}

/// The route surface narrow-union (web `RouteSurface`): `road`/`trail`/`mixed`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RouteSurface {
    Road,
    Trail,
    Mixed,
}

/// A lat/lng point in degrees.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct GeoPoint {
    pub lat: f64,
    pub lng: f64,
}

/// Inputs to [`describe_route`]. `start`/`end` (first and last waypoint, when
/// known) let it infer loop vs point-to-point.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RouteDescriptionInput {
    pub distance_m: f64,
    pub elevation_m: Option<f64>,
    pub surface: Option<RouteSurface>,
    pub start: Option<GeoPoint>,
    pub end: Option<GeoPoint>,
}

/// The structured facts the UI + model prompt build on.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct RouteDescriptionParts {
    /// Named race-distance band, or `None` if the distance sits in a gap.
    pub band: Option<DistanceBandKey>,
    pub distance_m: f64,
    pub surface: Option<RouteSurface>,
    pub elevation_m: f64,
    pub elevation: ElevationProfile,
    /// Gain per kilometre, rounded — drives the elevation bucket + UI detail.
    pub gain_per_km: f64,
    pub shape: RouteShape,
}

/// [`elevation_profile`] output: the bucket + the rounded gain-per-km it used.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ElevationBucket {
    pub profile: ElevationProfile,
    pub gain_per_km: f64,
}

/// Two endpoints within this distance are treated as the same point — the
/// route returns to where it started, so it's a loop. Matches the route-loop
/// builder's near-point tolerance.
pub const LOOP_CLOSE_M: f64 = 75.0;

/// m/km thresholds for the elevation buckets. Inclusive lower bound.
pub const ELEVATION_ROLLING_M_PER_KM: f64 = 10.0;
pub const ELEVATION_HILLY_M_PER_KM: f64 = 30.0;
pub const ELEVATION_MOUNTAINOUS_M_PER_KM: f64 = 70.0;

/// Bucket total gain (m) over distance into a coarse elevation character.
pub fn elevation_profile(distance_m: f64, elevation_m: f64) -> ElevationBucket {
    if distance_m <= 0.0 || elevation_m <= 0.0 {
        return ElevationBucket {
            profile: ElevationProfile::Flat,
            gain_per_km: 0.0,
        };
    }
    let gain_per_km = libm::round((elevation_m / distance_m) * 1000.0);
    let profile = if gain_per_km >= ELEVATION_MOUNTAINOUS_M_PER_KM {
        ElevationProfile::Mountainous
    } else if gain_per_km >= ELEVATION_HILLY_M_PER_KM {
        ElevationProfile::Hilly
    } else if gain_per_km >= ELEVATION_ROLLING_M_PER_KM {
        ElevationProfile::Rolling
    } else {
        ElevationProfile::Flat
    };
    ElevationBucket {
        profile,
        gain_per_km,
    }
}

/// Infer route shape from endpoints. Without both endpoints we can't tell, so
/// default to `PointToPoint` (never asserts a loop that isn't there). When
/// start ≈ end the route closes on itself and reads as a loop.
pub fn route_shape(input: &RouteDescriptionInput) -> RouteShape {
    match (input.start, input.end) {
        (Some(s), Some(e)) if haversine_metres(s.lat, s.lng, e.lat, e.lng) <= LOOP_CLOSE_M => {
            RouteShape::Loop
        }
        _ => RouteShape::PointToPoint,
    }
}

/// Compute the structured facts the UI + model prompt build on. Non-finite /
/// negative distance and elevation clamp to 0.
pub fn describe_route(input: &RouteDescriptionInput) -> RouteDescriptionParts {
    let distance_m = if input.distance_m.is_finite() {
        input.distance_m.max(0.0)
    } else {
        0.0
    };
    let elevation_m = match input.elevation_m {
        Some(e) if e.is_finite() => e.max(0.0),
        _ => 0.0,
    };
    let bucket = elevation_profile(distance_m, elevation_m);
    RouteDescriptionParts {
        band: band_for_distance(distance_m).map(|b| b.key),
        distance_m,
        surface: input.surface,
        elevation_m,
        elevation: bucket.profile,
        gain_per_km: bucket.gain_per_km,
        shape: route_shape(input),
    }
}

fn shape_word(shape: RouteShape) -> &'static str {
    match shape {
        RouteShape::Loop => "loop",
        RouteShape::OutAndBack => "out-and-back",
        RouteShape::PointToPoint => "point-to-point",
    }
}

/// Surface word with its trailing space, or empty when surface-less — so the
/// assembled sentence never leaves a dangling separator.
fn surface_word(surface: Option<RouteSurface>) -> &'static str {
    match surface {
        Some(RouteSurface::Road) => "road ",
        Some(RouteSurface::Trail) => "trail ",
        Some(RouteSurface::Mixed) => "mixed-surface ",
        None => "",
    }
}

fn elevation_word(profile: ElevationProfile) -> &'static str {
    match profile {
        ElevationProfile::Flat => "flat",
        ElevationProfile::Rolling => "gently rolling",
        ElevationProfile::Hilly => "hilly",
        ElevationProfile::Mountainous => "mountainous",
    }
}

/// Canonical English assembler — used to seed the model prompt (plain prose
/// the model enhances) and as the literal offline fallback string. Distance is
/// rendered in km because this string is English-only by contract. The buffer
/// is sized to hold a long route name (~120 chars) plus the ~130-char sentence
/// scaffold with room to spare; a write that would overflow is silently
/// truncated, never a panic.
pub fn assemble_english(parts: &RouteDescriptionParts, name: &str) -> String<256> {
    let mut s: String<256> = String::new();
    let km = parts.distance_m / 1000.0;
    let surface = surface_word(parts.surface);
    let shape = shape_word(parts.shape);
    if parts.distance_m >= 1000.0 {
        let _ = write!(s, "{name} is a {km:.1} km {surface}{shape} route");
    } else {
        let _ = write!(s, "{name} is a {km:.2} km {surface}{shape} route");
    }
    if parts.elevation_m > 0.0 {
        let _ = write!(
            s,
            " with {} m of climbing ({}, about {} m per km).",
            libm::round(parts.elevation_m),
            elevation_word(parts.elevation),
            parts.gain_per_km,
        );
    } else {
        let _ = write!(s, " with little to no elevation change.");
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elevation_profile_buckets_gain_per_km_into_the_four_bands() {
        assert_eq!(
            elevation_profile(10000.0, 0.0).profile,
            ElevationProfile::Flat
        );
        assert_eq!(
            elevation_profile(10000.0, 50.0).profile,
            ElevationProfile::Flat
        );
        assert_eq!(
            elevation_profile(10000.0, 150.0).profile,
            ElevationProfile::Rolling
        );
        assert_eq!(
            elevation_profile(10000.0, 400.0).profile,
            ElevationProfile::Hilly
        );
        assert_eq!(
            elevation_profile(10000.0, 1000.0).profile,
            ElevationProfile::Mountainous
        );
    }

    #[test]
    fn elevation_profile_thresholds_are_inclusive_lower_bounds() {
        assert_eq!(
            elevation_profile(1000.0, 10.0).profile,
            ElevationProfile::Rolling
        );
        assert_eq!(
            elevation_profile(1000.0, 30.0).profile,
            ElevationProfile::Hilly
        );
        assert_eq!(
            elevation_profile(1000.0, 70.0).profile,
            ElevationProfile::Mountainous
        );
    }

    #[test]
    fn elevation_profile_guards_zero_negative_distance() {
        assert_eq!(
            elevation_profile(0.0, 500.0),
            ElevationBucket {
                profile: ElevationProfile::Flat,
                gain_per_km: 0.0
            }
        );
        assert_eq!(
            elevation_profile(-10.0, 500.0),
            ElevationBucket {
                profile: ElevationProfile::Flat,
                gain_per_km: 0.0
            }
        );
    }

    #[test]
    fn route_shape_reports_a_loop_when_start_and_end_coincide() {
        let input = RouteDescriptionInput {
            distance_m: 5000.0,
            elevation_m: Some(20.0),
            surface: Some(RouteSurface::Road),
            start: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
            end: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
        };
        assert_eq!(route_shape(&input), RouteShape::Loop);
    }

    #[test]
    fn route_shape_reports_point_to_point_when_endpoints_differ() {
        let input = RouteDescriptionInput {
            distance_m: 12000.0,
            elevation_m: Some(300.0),
            surface: Some(RouteSurface::Trail),
            start: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
            end: Some(GeoPoint {
                lat: 51.6,
                lng: -0.05,
            }),
        };
        assert_eq!(route_shape(&input), RouteShape::PointToPoint);
    }

    #[test]
    fn route_shape_falls_back_to_point_to_point_without_endpoints() {
        let input = RouteDescriptionInput {
            distance_m: 5000.0,
            elevation_m: None,
            surface: None,
            start: None,
            end: None,
        };
        assert_eq!(route_shape(&input), RouteShape::PointToPoint);
    }

    #[test]
    fn loop_close_m_boundary_a_small_gap_still_reads_as_a_loop() {
        let start = GeoPoint {
            lat: 51.5,
            lng: -0.12,
        };
        let end = GeoPoint {
            lat: 51.5,
            lng: -0.12 + 0.0007,
        };
        assert!(LOOP_CLOSE_M >= 75.0);
        let input = RouteDescriptionInput {
            distance_m: 5000.0,
            elevation_m: Some(0.0),
            surface: None,
            start: Some(start),
            end: Some(end),
        };
        assert_eq!(route_shape(&input), RouteShape::Loop);
    }

    #[test]
    fn describe_route_assembles_the_structured_parts() {
        let parts = describe_route(&RouteDescriptionInput {
            distance_m: 10000.0,
            elevation_m: Some(150.0),
            surface: Some(RouteSurface::Mixed),
            start: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
            end: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
        });
        assert_eq!(parts.band, Some(DistanceBandKey::TenK));
        assert_eq!(parts.surface, Some(RouteSurface::Mixed));
        assert_eq!(parts.elevation, ElevationProfile::Rolling);
        assert_eq!(parts.gain_per_km, 15.0);
        assert_eq!(parts.shape, RouteShape::Loop);
    }

    #[test]
    fn describe_route_returns_a_null_band_for_between_band_distances() {
        let parts = describe_route(&RouteDescriptionInput {
            distance_m: 15000.0,
            elevation_m: Some(0.0),
            surface: Some(RouteSurface::Road),
            start: None,
            end: None,
        });
        assert_eq!(parts.band, None);
    }

    #[test]
    fn describe_route_clamps_non_finite_negative_inputs_to_zero() {
        let parts = describe_route(&RouteDescriptionInput {
            distance_m: f64::NAN,
            elevation_m: Some(-500.0),
            surface: None,
            start: None,
            end: None,
        });
        assert_eq!(parts.distance_m, 0.0);
        assert_eq!(parts.elevation_m, 0.0);
        assert_eq!(parts.elevation, ElevationProfile::Flat);
    }

    #[test]
    fn assemble_english_produces_a_hilly_point_to_point_sentence() {
        let parts = describe_route(&RouteDescriptionInput {
            distance_m: 12000.0,
            elevation_m: Some(480.0),
            surface: Some(RouteSurface::Trail),
            start: Some(GeoPoint {
                lat: 51.5,
                lng: -0.12,
            }),
            end: Some(GeoPoint {
                lat: 51.7,
                lng: 0.0,
            }),
        });
        let text = assemble_english(&parts, "Summit Trail");
        assert!(text.starts_with("Summit Trail is a 12.0 km trail point-to-point route"));
        assert!(text.ends_with("480 m of climbing (hilly, about 40 m per km)."));
    }

    #[test]
    fn assemble_english_handles_a_flat_road_loop_with_no_climbing() {
        let parts = describe_route(&RouteDescriptionInput {
            distance_m: 5000.0,
            elevation_m: Some(0.0),
            surface: Some(RouteSurface::Road),
            start: Some(GeoPoint { lat: 0.0, lng: 0.0 }),
            end: Some(GeoPoint { lat: 0.0, lng: 0.0 }),
        });
        let text = assemble_english(&parts, "Track");
        assert_eq!(
            text.as_str(),
            "Track is a 5.0 km road loop route with little to no elevation change."
        );
    }
}
