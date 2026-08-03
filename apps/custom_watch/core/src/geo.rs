//! Longitude arithmetic that survives the antimeridian.
//!
//! Every local planar frame in the firmware — the course projection's
//! per-segment frame, the trackback breadcrumb's origin frame, the recorder's
//! per-segment equirectangular hop — starts by subtracting two longitudes and
//! calling the result "metres east". That subtraction is wrong by a whole turn
//! whenever the two straddle 180 deg: 179.99 to -179.97 is 0.04 deg east, and
//! plain arithmetic reads it as 359.96 deg west, or ~40,000 km. Downstream the
//! error is not subtle — a runner on a course across the line reads hundreds of
//! metres off it, and one on the far side reads tens of thousands of kilometres
//! off, which is a permanent `! OFF CRS` on a runner standing on the course.
//!
//! Trigonometric formulae are immune (`sin` and `cos` are periodic, so the
//! haversine and the great-circle bearing already come out right) — it is only
//! the planar frames that need this. Applying it is free elsewhere: for any pair
//! within 180 deg of each other, every function here returns exactly what the
//! plain arithmetic did, bit for bit.

/// Shortest signed east-west separation from `from_deg` to `to_deg`, in degrees
/// within [-180, 180). Positive is east. Two exactly opposite meridians resolve
/// west rather than flapping between the two equally-correct answers.
pub fn lon_delta_deg(from_deg: f64, to_deg: f64) -> f64 {
    fold_turns(to_deg - from_deg)
}

/// `lon_deg` shifted by whole turns until it is within 180 deg of
/// `reference_deg` — the same meridian, expressed on the reference's side of the
/// line. The result can sit outside [-180, 180]; that is the point, since a
/// course-local frame anchored west of the line needs its eastern points to
/// carry on past 180 rather than jump to -179.
pub fn unwrap_lon_deg(reference_deg: f64, lon_deg: f64) -> f64 {
    reference_deg + lon_delta_deg(reference_deg, lon_deg)
}

/// A longitude folded back onto the [-180, 180) meridian range.
pub fn wrap_lon_deg(lon_deg: f64) -> f64 {
    fold_turns(lon_deg)
}

/// `deg` less however many whole turns leave it in [-180, 180). The `floor`
/// (rather than a `round` that breaks halves away from zero) is what makes the
/// fold idempotent at exactly 180 deg, and it returns any `deg` already in range
/// bit for bit — `floor` is exactly zero there, so nothing is added back.
fn fold_turns(deg: f64) -> f64 {
    deg - 360.0 * libm::floor((deg + 180.0) / 360.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_delta_within_a_hemisphere_is_the_plain_subtraction_bit_for_bit() {
        for &(a, b) in &[
            (-105.2705, -105.269445),
            (51.5, 51.51),
            (0.0, 0.0),
            (-179.0, 179.0 - 360.0),
            (12.34567, -98.7654321),
        ] {
            assert_eq!(lon_delta_deg(a, b), b - a, "{} -> {}", a, b);
        }
    }

    #[test]
    fn a_delta_across_the_antimeridian_takes_the_short_way() {
        assert!((lon_delta_deg(179.99, -179.97) - 0.04).abs() < 1e-9);
        assert!((lon_delta_deg(-179.97, 179.99) + 0.04).abs() < 1e-9);
        assert!((lon_delta_deg(179.9, -179.9) - 0.2).abs() < 1e-9);
        // The plain subtraction is wrong by a whole turn, which is the bug.
        assert!(libm::fabs((-179.97f64 - 179.99) + 359.96) < 1e-9);
    }

    #[test]
    fn opposite_meridians_resolve_consistently_rather_than_flapping() {
        assert_eq!(lon_delta_deg(0.0, 180.0), -180.0);
        assert_eq!(lon_delta_deg(0.0, -180.0), -180.0);
        assert_eq!(wrap_lon_deg(wrap_lon_deg(180.0)), wrap_lon_deg(180.0));
        assert_eq!(wrap_lon_deg(-180.0), -180.0);
    }

    #[test]
    fn unwrapping_leaves_a_longitude_already_near_the_reference_untouched() {
        for &(r, lon) in &[
            (-105.27, -105.26),
            (0.0, 179.9),
            (0.0, -179.9),
            (60.0, 60.0),
        ] {
            assert_eq!(unwrap_lon_deg(r, lon), lon, "{} {}", r, lon);
        }
    }

    #[test]
    fn unwrapping_carries_a_course_past_the_line_instead_of_jumping_it() {
        // A course anchored at 179.98 whose far end is at -179.96: the box
        // spans 0.06 deg, not 359.94.
        let a = 179.98;
        let b = unwrap_lon_deg(a, -179.96);
        assert!((b - 180.04).abs() < 1e-9, "unwrapped to {}", b);
        assert!((b - a - 0.06).abs() < 1e-9);
        assert!((wrap_lon_deg(b) - -179.96).abs() < 1e-9);
    }

    #[test]
    fn a_non_finite_longitude_stays_non_finite_rather_than_becoming_a_number() {
        assert!(lon_delta_deg(f64::NAN, 0.0).is_nan());
        assert!(lon_delta_deg(0.0, f64::NAN).is_nan());
        assert!(wrap_lon_deg(f64::INFINITY).is_nan() || !wrap_lon_deg(f64::INFINITY).is_finite());
    }
}
