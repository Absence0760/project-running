//! Personal run-track heatmap aggregation.
//!
//! A parity port of web `routes/run_heatmap.ts` (twin of `run_heatmap.dart`).
//! Grid-quantises many of the runner's own GPS tracks into weighted cells:
//! repeated routes accumulate weight in the same cell instead of exploding the
//! point count, so a renderer draws a manageable heat cloud rather than every
//! raw sample. [`build_heat_cells`] does the quantise; [`heat_bounds`] returns
//! the fit box over the resulting cells.
//!
//! SCOPE: only the pure aggregation is ported. The web module's MapLibre
//! GeoJSON emitters (`toHeatGeoJSON` / `toTrackLinesGeoJSON`) are renderer-
//! specific, have no Dart twin, and are omitted here.
//!
//! Pure logic, no peripherals, no allocator. The grid quantiser rounds half
//! toward +Infinity via `floor(x + 0.5)` to match JS `Math.round` (and the
//! Dart twin's `(x + 0.5).floor()`) exactly — `f64::round` rounds half away
//! from zero, which would shift a negative-coordinate cell by one grid step
//! and desync the watch from web + mobile.

use heapless::Vec;

/// ~33 m at the equator. Fine enough that distinct streets stay distinct,
/// coarse enough that one route's thousands of samples collapse to a
/// manageable cell count.
pub const DEFAULT_GRID_DEG: f64 = 0.0003;

/// Largest weight a single cell reports. A daily-commute cell would otherwise
/// dwarf everything else and flatten the gradient to one colour; clamping
/// keeps it legible. A renderer still interpolates over `[0, MAX_CELL_WEIGHT]`.
pub const MAX_CELL_WEIGHT: u32 = 50;

/// Output capacity. The web keeps an unbounded `Map` of cells; without an
/// allocator the watch bounds the distinct-cell count. Once full, further
/// *new* cells are dropped, but cells already present keep accumulating
/// weight — so a dense repeated route still reads hot.
pub const MAX_HEAT_CELLS: usize = 512;

/// A single GPS sample. Mirrors the web `HeatLatLng`.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HeatLatLng {
    pub lat: f64,
    pub lng: f64,
}

/// A grid cell: its centre coordinate + the clamped hit count. Mirrors the web
/// `HeatCell`. `weight` is `f64` to match the web `number`.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HeatCell {
    pub lat: f64,
    pub lng: f64,
    pub weight: f64,
}

/// Bounding box of a set of cells. The web returns MapLibre's
/// `[[west, south], [east, north]]`; the watch uses named fields.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct HeatBounds {
    pub west: f64,
    pub south: f64,
    pub east: f64,
    pub north: f64,
}

fn is_finite_point(p: &HeatLatLng) -> bool {
    p.lat.is_finite()
        && p.lng.is_finite()
        && libm::fabs(p.lat) <= 90.0
        && libm::fabs(p.lng) <= 180.0
}

/// Quantise every point of every track into a grid and sum hits per cell. Each
/// cell's coordinate is its grid-centre; weight is the clamped hit count.
/// Empty / all-invalid input yields an empty result; a non-positive `grid_deg`
/// falls back to [`DEFAULT_GRID_DEG`].
pub fn build_heat_cells(
    tracks: &[&[HeatLatLng]],
    mut grid_deg: f64,
) -> Vec<HeatCell, MAX_HEAT_CELLS> {
    // Negated `>` (not `<= 0.0`) so a NaN grid_deg also falls back, matching
    // the web `!(gridDeg > 0)`: NaN fails every comparison, and `<= 0.0` would
    // let it slip through and poison every quantise.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(grid_deg > 0.0) {
        grid_deg = DEFAULT_GRID_DEG;
    }
    let mut counts: Vec<(i32, i32, u32), MAX_HEAT_CELLS> = Vec::new();
    for track in tracks {
        for p in *track {
            if !is_finite_point(p) {
                continue;
            }
            let gx = libm::floor(p.lng / grid_deg + 0.5) as i32;
            let gy = libm::floor(p.lat / grid_deg + 0.5) as i32;
            if let Some(entry) = counts.iter_mut().find(|(x, y, _)| *x == gx && *y == gy) {
                entry.2 += 1;
            } else {
                let _ = counts.push((gx, gy, 1));
            }
        }
    }
    let mut cells: Vec<HeatCell, MAX_HEAT_CELLS> = Vec::new();
    for (gx, gy, count) in counts {
        let _ = cells.push(HeatCell {
            lng: f64::from(gx) * grid_deg,
            lat: f64::from(gy) * grid_deg,
            weight: f64::from(count.min(MAX_CELL_WEIGHT)),
        });
    }
    cells
}

/// Bounding box of a set of cells. `None` when there's nothing to fit.
pub fn heat_bounds(cells: &[HeatCell]) -> Option<HeatBounds> {
    if cells.is_empty() {
        return None;
    }
    let mut b = HeatBounds {
        west: f64::INFINITY,
        south: f64::INFINITY,
        east: f64::NEG_INFINITY,
        north: f64::NEG_INFINITY,
    };
    for c in cells {
        if c.lat < b.south {
            b.south = c.lat;
        }
        if c.lat > b.north {
            b.north = c.lat;
        }
        if c.lng < b.west {
            b.west = c.lng;
        }
        if c.lng > b.east {
            b.east = c.lng;
        }
    }
    Some(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cells(tracks: &[&[HeatLatLng]]) -> Vec<HeatCell, MAX_HEAT_CELLS> {
        build_heat_cells(tracks, DEFAULT_GRID_DEG)
    }

    #[test]
    fn collapses_many_points_within_one_grid_cell() {
        let track: heapless::Vec<HeatLatLng, 16> = (0..10)
            .map(|i| HeatLatLng {
                lat: 51.5 + f64::from(i) * 0.00001,
                lng: -0.12 + f64::from(i) * 0.00001,
            })
            .collect();
        let out = cells(&[&track]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].weight, 10.0);
    }

    #[test]
    fn repeated_routes_accumulate_weight_in_shared_cells() {
        let track = [
            HeatLatLng {
                lat: 40.0,
                lng: -75.0,
            },
            HeatLatLng {
                lat: 40.001,
                lng: -75.0,
            },
        ];
        let single = cells(&[&track]);
        let tripled = cells(&[&track, &track, &track]);
        assert_eq!(single.len(), tripled.len());
        let sum_single: f64 = single.iter().map(|c| c.weight).sum();
        let sum_tripled: f64 = tripled.iter().map(|c| c.weight).sum();
        assert_eq!(sum_tripled, sum_single * 3.0);
    }

    #[test]
    fn distinct_locations_produce_distinct_cells() {
        let a = [HeatLatLng {
            lat: 51.5,
            lng: -0.12,
        }];
        let b = [HeatLatLng {
            lat: 48.85,
            lng: 2.35,
        }];
        assert_eq!(cells(&[&a, &b]).len(), 2);
    }

    #[test]
    fn clamps_a_single_cells_weight_at_max_cell_weight() {
        let track: heapless::Vec<HeatLatLng, 300> = (0..MAX_CELL_WEIGHT + 200)
            .map(|_| HeatLatLng {
                lat: 34.05,
                lng: -118.24,
            })
            .collect();
        let out = cells(&[&track]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].weight, f64::from(MAX_CELL_WEIGHT));
    }

    #[test]
    fn quantises_negative_half_boundary_toward_positive_infinity() {
        // lng/lat = -0.5 * gridDeg sits exactly on a grid half-boundary. The
        // quantiser must round half toward +Infinity (gx = 0 → cell centre 0),
        // matching JS Math.round and the Dart twin's (x+0.5).floor() — NOT a
        // round-half-away-from-zero (which yields gx = -1). A drift shifts the
        // cell by one grid step (~33 m) for any west-of-Greenwich track.
        let g = DEFAULT_GRID_DEG;
        let out = cells(&[&[HeatLatLng {
            lat: -0.5 * g,
            lng: -0.5 * g,
        }]]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].lat, 0.0);
        assert_eq!(out[0].lng, 0.0);
    }

    #[test]
    fn drops_invalid_out_of_range_points() {
        let track = [
            HeatLatLng {
                lat: f64::NAN,
                lng: 0.0,
            },
            HeatLatLng {
                lat: 0.0,
                lng: f64::INFINITY,
            },
            HeatLatLng {
                lat: 200.0,
                lng: 0.0,
            },
            HeatLatLng {
                lat: 0.0,
                lng: -400.0,
            },
            HeatLatLng {
                lat: 45.0,
                lng: 9.0,
            },
        ];
        let out = cells(&[&track]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].weight, 1.0);
    }

    #[test]
    fn empty_or_all_invalid_input_yields_no_cells_and_null_bounds() {
        assert_eq!(cells(&[]).len(), 0);
        assert_eq!(cells(&[&[]]).len(), 0);
        assert_eq!(heat_bounds(&[]), None);
    }

    #[test]
    fn heat_bounds_spans_the_cell_extent() {
        let track = [
            HeatLatLng {
                lat: 10.0,
                lng: 20.0,
            },
            HeatLatLng {
                lat: 30.0,
                lng: 40.0,
            },
        ];
        let out = cells(&[&track]);
        let b = heat_bounds(&out).unwrap();
        // Cells snap to grid centres, so each edge sits within one grid step
        // of the raw extent.
        let tol = DEFAULT_GRID_DEG;
        assert!(libm::fabs(b.west - 20.0) <= tol && libm::fabs(b.south - 10.0) <= tol);
        assert!(libm::fabs(b.east - 40.0) <= tol && libm::fabs(b.north - 30.0) <= tol);
        assert!(b.west <= b.east && b.south <= b.north);
    }

    #[test]
    fn invalid_grid_deg_falls_back_to_the_default() {
        let track = [HeatLatLng { lat: 1.0, lng: 1.0 }];
        assert_eq!(
            build_heat_cells(&[&track], 0.0),
            build_heat_cells(&[&track], DEFAULT_GRID_DEG)
        );
        assert_eq!(
            build_heat_cells(&[&track], -5.0),
            build_heat_cells(&[&track], DEFAULT_GRID_DEG)
        );
    }
}
