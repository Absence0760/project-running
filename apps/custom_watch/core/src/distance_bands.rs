//! Race-distance bands for route discovery.
//!
//! A parity port of web `routes/distance_bands.ts` (twin of
//! `distance_bands.dart`): runners think in race distances, not raw
//! kilometres, so a route's stored distance buckets into a named window.
//! This module is the single source of truth for the band ranges.
//!
//! Windows are deliberately tolerant (a "5K" route is rarely exactly
//! 5.00 km) and leave gaps between bands (a 15 km route is no race distance
//! and matches nothing). Bounds are metres: [`min_m`](DistanceBand::min_m)
//! inclusive, [`max_m`](DistanceBand::max_m) exclusive, `max_m == None`
//! open-ended (ultra).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// The five named race-distance windows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum DistanceBandKey {
    FiveK,
    TenK,
    Half,
    Marathon,
    Ultra,
}

/// One race-distance band: a half-open `[min_m, max_m)` window in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct DistanceBand {
    pub key: DistanceBandKey,
    pub label: &'static str,
    /// Inclusive lower bound, metres.
    pub min_m: f64,
    /// Exclusive upper bound, metres; `None` is open-ended (ultra).
    pub max_m: Option<f64>,
}

/// The band catalogue, in display / output order.
pub const DISTANCE_BANDS: [DistanceBand; 5] = [
    DistanceBand {
        key: DistanceBandKey::FiveK,
        label: "5K",
        min_m: 4000.0,
        max_m: Some(6000.0),
    },
    DistanceBand {
        key: DistanceBandKey::TenK,
        label: "10K",
        min_m: 8000.0,
        max_m: Some(12000.0),
    },
    DistanceBand {
        key: DistanceBandKey::Half,
        label: "Half",
        min_m: 19000.0,
        max_m: Some(23000.0),
    },
    DistanceBand {
        key: DistanceBandKey::Marathon,
        label: "Marathon",
        min_m: 40000.0,
        max_m: Some(44500.0),
    },
    DistanceBand {
        key: DistanceBandKey::Ultra,
        label: "Ultra",
        min_m: 44500.0,
        max_m: None,
    },
];

/// The band a given route distance falls into, or `None` if it sits in a gap
/// between bands. Used to badge route rows in the list.
pub fn band_for_distance(distance_m: f64) -> Option<DistanceBand> {
    for b in &DISTANCE_BANDS {
        let in_band = match b.max_m {
            Some(max) => distance_m >= b.min_m && distance_m < max,
            None => distance_m >= b.min_m,
        };
        if in_band {
            return Some(*b);
        }
    }
    None
}

/// Parallel min/max bound arrays for the discovery RPC, built from the
/// selected band keys. `None` when nothing is selected so the caller skips
/// the distance predicate entirely. A `None` element in [`max`](Self::max) is
/// an open-ended upper bound (ultra). Output order always follows
/// [`DISTANCE_BANDS`], independent of the order keys were passed in.
#[derive(Clone, Debug, PartialEq)]
pub struct BandRanges {
    pub min: Vec<f64, 5>,
    pub max: Vec<Option<f64>, 5>,
}

/// Build the parallel min/max arrays for the selected band keys. Returns
/// `None` when nothing is selected.
pub fn bands_to_ranges(keys: &[DistanceBandKey]) -> Option<BandRanges> {
    let mut min: Vec<f64, 5> = Vec::new();
    let mut max: Vec<Option<f64>, 5> = Vec::new();
    for b in &DISTANCE_BANDS {
        if keys.contains(&b.key) {
            let _ = min.push(b.min_m);
            let _ = max.push(b.max_m);
        }
    }
    if min.is_empty() {
        return None;
    }
    Some(BandRanges { min, max })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_nominal_race_distances_to_their_band() {
        assert_eq!(
            band_for_distance(5000.0).unwrap().key,
            DistanceBandKey::FiveK
        );
        assert_eq!(
            band_for_distance(10000.0).unwrap().key,
            DistanceBandKey::TenK
        );
        assert_eq!(
            band_for_distance(21097.0).unwrap().key,
            DistanceBandKey::Half
        );
        assert_eq!(
            band_for_distance(42195.0).unwrap().key,
            DistanceBandKey::Marathon
        );
        assert_eq!(
            band_for_distance(50000.0).unwrap().key,
            DistanceBandKey::Ultra
        );
        assert_eq!(
            band_for_distance(160934.0).unwrap().key,
            DistanceBandKey::Ultra
        );
    }

    #[test]
    fn tolerates_real_world_wobble_around_the_nominal() {
        assert_eq!(
            band_for_distance(4200.0).unwrap().key,
            DistanceBandKey::FiveK
        );
        assert_eq!(
            band_for_distance(5900.0).unwrap().key,
            DistanceBandKey::FiveK
        );
        assert_eq!(
            band_for_distance(11500.0).unwrap().key,
            DistanceBandKey::TenK
        );
    }

    #[test]
    fn returns_none_in_the_gaps_between_race_distances() {
        assert!(band_for_distance(3000.0).is_none());
        assert!(band_for_distance(7000.0).is_none());
        assert!(band_for_distance(15000.0).is_none());
        assert!(band_for_distance(30000.0).is_none());
    }

    #[test]
    fn band_edges_are_half_open() {
        assert!(band_for_distance(6000.0).is_none());
        assert_eq!(
            band_for_distance(44499.0).unwrap().key,
            DistanceBandKey::Marathon
        );
        assert_eq!(
            band_for_distance(44500.0).unwrap().key,
            DistanceBandKey::Ultra
        );
    }

    #[test]
    fn bands_to_ranges_returns_none_when_nothing_is_selected() {
        assert!(bands_to_ranges(&[]).is_none());
    }

    #[test]
    fn bands_to_ranges_builds_parallel_arrays_for_a_single_band() {
        let r = bands_to_ranges(&[DistanceBandKey::FiveK]).unwrap();
        assert_eq!(&r.min[..], &[4000.0]);
        assert_eq!(&r.max[..], &[Some(6000.0)]);
    }

    #[test]
    fn bands_to_ranges_carries_an_open_ended_upper_bound_for_ultra() {
        let r = bands_to_ranges(&[DistanceBandKey::Ultra]).unwrap();
        assert_eq!(&r.min[..], &[44500.0]);
        assert_eq!(&r.max[..], &[None]);
    }

    #[test]
    fn bands_to_ranges_output_order_follows_the_catalogue() {
        let r = bands_to_ranges(&[
            DistanceBandKey::Ultra,
            DistanceBandKey::FiveK,
            DistanceBandKey::Half,
        ])
        .unwrap();
        assert_eq!(&r.min[..], &[4000.0, 19000.0, 44500.0]);
        assert_eq!(&r.max[..], &[Some(6000.0), Some(23000.0), None]);
    }

    #[test]
    fn every_band_key_round_trips() {
        let keys: Vec<DistanceBandKey, 5> = DISTANCE_BANDS.iter().map(|b| b.key).collect();
        let r = bands_to_ranges(&keys).unwrap();
        assert_eq!(r.min.len(), DISTANCE_BANDS.len());
        assert_eq!(r.max.len(), DISTANCE_BANDS.len());
    }
}
