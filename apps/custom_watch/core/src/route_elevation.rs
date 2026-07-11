//! Route elevation shaping — the pure half of web `routes/elevation.ts`
//! (renamed from the source basename to avoid colliding with [`crate::elevation`],
//! the barometric-altitude accumulator).
//!
//! Two helpers:
//! - [`calculate_elevation_gain`] — sum of the positive elevation deltas along a
//!   profile, rounded like the web `Math.round`.
//! - [`sample_coordinates`] — thin a coordinate list to at most `max_points`
//!   evenly-spaced picks (with the source indices), so the elevation lookup need
//!   not query every GPS point.
//!
//! The source's `fetchElevations` is web-only: it is an Open-Meteo network hop
//! gated on the browser cookie-consent record, which has no meaning on a
//! peripheral-free `no_std` core, so it is not ported (its three consent /
//! network tests likewise have no analogue here).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// Total elevation gain: the sum of the positive point-to-point deltas, rounded.
/// Mirrors web `calculateElevationGain` — descents contribute nothing, and an
/// empty or single-point profile is `0`.
pub fn calculate_elevation_gain(elevations: &[f64]) -> f64 {
    let mut gain = 0.0;
    for i in 1..elevations.len() {
        let diff = elevations[i] - elevations[i - 1];
        if diff > 0.0 {
            gain += diff;
        }
    }
    libm::round(gain)
}

/// A thinned coordinate list plus the source index each pick came from. `N` is
/// the fixed capacity; callers must size it `>= max_points` (the web default is
/// `100`, matching Open-Meteo's ~100-point batch ceiling), which also covers the
/// pass-through branch since that only fires when `coordinates.len() <=
/// max_points`.
pub struct SampledCoordinates<const N: usize> {
    pub sampled: Vec<(f64, f64), N>,
    pub indices: Vec<usize, N>,
}

/// Sample `coordinates` down to at most `max_points` evenly-spaced picks,
/// mirroring web `sampleCoordinates`. When the input already fits it passes
/// through unchanged; otherwise it emits exactly `max_points` picks with the
/// first and last coordinate as the boundaries, choosing each source index with
/// the same `Math.round` step arithmetic.
pub fn sample_coordinates<const N: usize>(
    coordinates: &[(f64, f64)],
    max_points: usize,
) -> SampledCoordinates<N> {
    let mut sampled: Vec<(f64, f64), N> = Vec::new();
    let mut indices: Vec<usize, N> = Vec::new();

    if coordinates.len() <= max_points {
        for (i, c) in coordinates.iter().enumerate() {
            let _ = sampled.push(*c);
            let _ = indices.push(i);
        }
        return SampledCoordinates { sampled, indices };
    }

    let step = (coordinates.len() - 1) as f64 / (max_points - 1) as f64;
    for i in 0..max_points {
        let idx = libm::round(i as f64 * step) as usize;
        let _ = sampled.push(coordinates[idx]);
        let _ = indices.push(idx);
    }

    SampledCoordinates { sampled, indices }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gain_accumulates_only_positive_deltas() {
        assert!((calculate_elevation_gain(&[100.0, 110.0, 105.0, 120.0]) - 25.0).abs() < 1e-9);
    }

    #[test]
    fn gain_flat_profile_returns_zero() {
        assert_eq!(calculate_elevation_gain(&[100.0, 100.0, 100.0, 100.0]), 0.0);
    }

    #[test]
    fn gain_descending_profile_returns_zero() {
        assert_eq!(calculate_elevation_gain(&[200.0, 150.0, 100.0, 50.0]), 0.0);
    }

    #[test]
    fn gain_empty_or_single_point_returns_zero() {
        assert_eq!(calculate_elevation_gain(&[]), 0.0);
        assert_eq!(calculate_elevation_gain(&[100.0]), 0.0);
    }

    #[test]
    fn gain_rounds_the_result() {
        // Three +0.4 deltas sum to 1.2 → rounds to 1.
        assert_eq!(calculate_elevation_gain(&[0.0, 0.4, 0.8, 1.2]), 1.0);
    }

    #[test]
    fn sample_passes_through_when_fewer_than_max_points() {
        let coords = [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)];
        let out = sample_coordinates::<100>(&coords, 100);
        assert_eq!(&out.sampled[..], &coords[..]);
        assert_eq!(&out.indices[..], &[0, 1, 2][..]);
    }

    #[test]
    fn sample_equal_count_input_passes_through() {
        let coords: [(f64, f64); 10] = core::array::from_fn(|i| (i as f64, i as f64));
        let out = sample_coordinates::<100>(&coords, 10);
        assert_eq!(&out.sampled[..], &coords[..]);
        assert_eq!(out.indices.len(), 10);
    }

    #[test]
    fn sample_produces_exactly_max_points_when_input_is_larger() {
        let coords: [(f64, f64); 1000] = core::array::from_fn(|i| (i as f64, i as f64));
        let out = sample_coordinates::<100>(&coords, 50);
        assert_eq!(out.sampled.len(), 50);
        assert_eq!(out.indices.len(), 50);
        assert_eq!(out.sampled[0], coords[0]);
        assert_eq!(out.sampled[49], coords[999]);
        assert_eq!(out.indices[0], 0);
        assert_eq!(out.indices[49], 999);
    }

    #[test]
    fn sample_indices_align_with_the_sampled_coordinates() {
        let coords: [(f64, f64); 200] = core::array::from_fn(|i| (i as f64, i as f64 * 2.0));
        let out = sample_coordinates::<100>(&coords, 20);
        for k in 0..out.sampled.len() {
            assert_eq!(out.sampled[k], coords[out.indices[k]]);
        }
    }
}
