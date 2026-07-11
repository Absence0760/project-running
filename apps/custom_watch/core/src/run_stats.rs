//! On-demand run statistics derived from a GPS track — moving time, positive
//! elevation gain, and per-unit splits.
//!
//! Parity port of web `runs/run_stats.ts` (twin of
//! `apps/mobile_android/lib/run_stats.dart`) — keep the algorithm, edge cases,
//! and the test count in lockstep. Both clients compute these at display time
//! rather than storing them, so the metric stays consistent if the algorithm is
//! tuned later.
//!
//! One ports-only shape choice, because this is `no_std`: web timestamps are
//! ISO strings parsed with `Date.parse`; the watch carries epoch-**milliseconds**
//! directly ([`TrackPoint::ts`]), and there is no allocator-free ISO formatter
//! here. The web `Number.isFinite`/NaN dance around an unparseable stamp maps to
//! a `None` ts (skipped) or the `f64::NAN` sentinel threaded through the split
//! start anchor, so the "first fix lands before the clock is stamped" edge case
//! ports faithfully.
//!
//! The rounded outputs the web returns as `number` become `i32` here (the km
//! index, seconds, and metres are all integer-valued after `Math.round`);
//! [`js_round`] mirrors JS `Math.round`'s round-half-up so a negative
//! elevation-loss delta rounds the same way it does on web.
//!
//! Reuses [`crate::grade_adjusted_pace::haversine_metres`] (R = 6371 km), the
//! same great-circle distance the web helper inlines, so the ports agree
//! segment for segment. Pure logic, no peripherals, no allocator.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

/// Default moving-time speed floor: ~1.8 km/h, slower than a slow walk but above
/// the noise floor when the runner is standing still.
pub const DEFAULT_MIN_SPEED_MPS: f64 = 0.5;

/// The km split-boundary length; the caller passes 1609.344 for mile splits.
pub const KM_TICK_METRES: f64 = 1000.0;

/// Longest split list [`compute_real_splits`] emits. A 512 km / 512 mi run is
/// well beyond any real event; the bound keeps the buffer stack-allocated.
pub const MAX_SPLITS: usize = 512;

/// One track waypoint. `ts` is the fix time in epoch **milliseconds** (web
/// parses its ISO string to the same via `Date.parse`); `None` models a fix with
/// no timestamp, which the algorithms skip like web's `!p.ts`.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrackPoint {
    pub lat: f64,
    pub lng: f64,
    pub ts: Option<f64>,
    pub ele: Option<f64>,
}

/// One per-unit split. `pace_s` is canonical seconds-per-km regardless of the
/// tick length; the caller converts to the display unit.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct Split {
    pub km: i32,
    pub pace_s: i32,
    pub distance_m: i32,
    pub elevation_m: Option<i32>,
}

fn js_round(x: f64) -> i32 {
    libm::floor(x + 0.5) as i32
}

/// Moving time in seconds — elapsed with stops excluded. Walks consecutive
/// waypoint pairs, and counts only segments whose speed is at or above
/// `min_speed_mps` (pass [`DEFAULT_MIN_SPEED_MPS`] for the default). A pair with
/// a missing or non-positive `dt` is skipped.
pub fn moving_time_seconds(track: &[TrackPoint], min_speed_mps: f64) -> i32 {
    if track.len() < 2 {
        return 0;
    }
    let mut moving_ms = 0.0_f64;
    for w in track.windows(2) {
        let (Some(ta), Some(tb)) = (w[0].ts, w[1].ts) else {
            continue;
        };
        let dt_ms = tb - ta;
        if !dt_ms.is_finite() || dt_ms <= 0.0 {
            continue;
        }
        let distance = haversine_metres(w[0].lat, w[0].lng, w[1].lat, w[1].lng);
        let speed = distance / (dt_ms / 1000.0);
        if speed >= min_speed_mps {
            moving_ms += dt_ms;
        }
    }
    js_round(moving_ms / 1000.0)
}

/// Total positive elevation gain in metres. Sums upward deltas between
/// consecutive points, ignoring descents; a pair missing either `ele` is
/// skipped.
pub fn elevation_gain_metres(track: &[TrackPoint]) -> i32 {
    if track.len() < 2 {
        return 0;
    }
    let mut gain = 0.0_f64;
    for w in track.windows(2) {
        let (Some(prev), Some(curr)) = (w[0].ele, w[1].ele) else {
            continue;
        };
        if curr > prev {
            gain += curr - prev;
        }
    }
    js_round(gain)
}

struct SplitStart {
    dist: f64,
    time_ms: f64,
    ele: Option<f64>,
}

/// Per-unit splits from a GPS track. Requires timestamps; returns empty when the
/// track has fewer than two points or none carry a timestamp. `tick_metres` is
/// the split-boundary length ([`KM_TICK_METRES`] for km, 1609.344 for miles).
/// Elevation per split is the net gain/loss over the segment, `None` when the
/// track has no elevation data.
pub fn compute_real_splits(track: &[TrackPoint], tick_metres: f64) -> Vec<Split, MAX_SPLITS> {
    let mut splits: Vec<Split, MAX_SPLITS> = Vec::new();
    if track.len() < 2 {
        return splits;
    }
    if !track.iter().any(|p| p.ts.is_some()) {
        return splits;
    }
    let has_ele = track.iter().any(|p| p.ele.is_some());

    // Seed the start time from the first point that actually carries a finite
    // timestamp, not track[0]: a first fix stamped before the clock started
    // would otherwise seed NaN and emit the first split at pace 0.
    let start_ms = track
        .iter()
        .find_map(|p| p.ts.filter(|t| t.is_finite()))
        .unwrap_or(f64::NAN);
    let mut cum_dist = 0.0_f64;
    let mut split_start = SplitStart {
        dist: 0.0,
        time_ms: start_ms,
        ele: track[0].ele,
    };

    for w in track.windows(2) {
        let a = w[0];
        let b = w[1];
        cum_dist += haversine_metres(a.lat, a.lng, b.lat, b.lng);
        let boundary = (splits.len() + 1) as i32;

        if cum_dist >= boundary as f64 * tick_metres {
            let end_time_ms = b.ts.unwrap_or(f64::NAN);
            let duration_s = if end_time_ms.is_finite() {
                (end_time_ms - split_start.time_ms) / 1000.0
            } else {
                0.0
            };
            let split_dist = cum_dist - split_start.dist;
            let pace_s = if duration_s > 0.0 && split_dist > 0.0 {
                js_round(duration_s / (split_dist / 1000.0))
            } else {
                0
            };
            let ele_net = match (has_ele, b.ele, split_start.ele) {
                (true, Some(be), Some(se)) => Some(js_round(be - se)),
                _ => None,
            };

            if splits
                .push(Split {
                    km: boundary,
                    pace_s,
                    distance_m: js_round(split_dist),
                    elevation_m: ele_net,
                })
                .is_err()
            {
                break;
            }

            split_start = SplitStart {
                dist: cum_dist,
                time_ms: end_time_ms,
                ele: b.ele,
            };
        }
    }

    if !splits.is_empty() || cum_dist > 0.0 {
        let last_point = track[track.len() - 1];
        let end_time_ms = last_point.ts.unwrap_or(f64::NAN);
        let duration_s = if end_time_ms.is_finite() {
            (end_time_ms - split_start.time_ms) / 1000.0
        } else {
            0.0
        };
        let remaining_dist = cum_dist - split_start.dist;
        if remaining_dist > 50.0 {
            let pace_s = if duration_s > 0.0 && remaining_dist > 0.0 {
                js_round(duration_s / (remaining_dist / 1000.0))
            } else {
                0
            };
            let ele_net = match (has_ele, last_point.ele, split_start.ele) {
                (true, Some(le), Some(se)) => Some(js_round(le - se)),
                _ => None,
            };
            let km = (splits.len() + 1) as i32;
            let _ = splits.push(Split {
                km,
                pace_s,
                distance_m: js_round(remaining_dist),
                elevation_m: ele_net,
            });
        }
    }

    splits
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/runs/run_stats.test.ts` — same scenarios,
    /// same expected values, so the ports can't drift. Absolute epoch is
    /// irrelevant (every computation is a difference), so the synthetic track
    /// seeds t0 = 0.
    const METRES_PER_DEG_LNG: f64 = 111_320.0;

    struct TrackOpts {
        start_ele: Option<f64>,
        ele_step: f64,
    }

    impl Default for TrackOpts {
        fn default() -> Self {
            TrackOpts {
                start_ele: None,
                ele_step: 0.0,
            }
        }
    }

    fn track(step_m: f64, interval_s: f64, n: usize, opts: TrackOpts) -> Vec<TrackPoint, 512> {
        let mut out: Vec<TrackPoint, 512> = Vec::new();
        for i in 0..n {
            let ele = opts.start_ele.map(|e| e + i as f64 * opts.ele_step);
            let _ = out.push(TrackPoint {
                lat: 0.0,
                lng: (i as f64 * step_m) / METRES_PER_DEG_LNG,
                ts: Some(i as f64 * interval_s * 1000.0),
                ele,
            });
        }
        out
    }

    #[test]
    fn moving_time_empty_or_single_point_is_zero() {
        assert_eq!(moving_time_seconds(&[], DEFAULT_MIN_SPEED_MPS), 0);
        assert_eq!(
            moving_time_seconds(
                &[TrackPoint {
                    lat: 0.0,
                    lng: 0.0,
                    ts: Some(0.0),
                    ele: None,
                }],
                DEFAULT_MIN_SPEED_MPS
            ),
            0
        );
    }

    #[test]
    fn moving_time_counts_segments_at_or_above_threshold() {
        let t = track(5.0, 1.0, 6, TrackOpts::default());
        assert_eq!(moving_time_seconds(&t, DEFAULT_MIN_SPEED_MPS), 5);
    }

    #[test]
    fn moving_time_drops_sub_threshold_stopped_segments() {
        let stopped = track(0.1, 1.0, 11, TrackOpts::default());
        assert_eq!(moving_time_seconds(&stopped, DEFAULT_MIN_SPEED_MPS), 0);
    }

    #[test]
    fn moving_time_mixed_running_and_long_stop_counts_only_running() {
        let pts = [
            TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: Some(0.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 5.0 / METRES_PER_DEG_LNG,
                ts: Some(1000.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 10.0 / METRES_PER_DEG_LNG,
                ts: Some(2000.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 10.0 / METRES_PER_DEG_LNG,
                ts: Some(62000.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 15.0 / METRES_PER_DEG_LNG,
                ts: Some(63000.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 20.0 / METRES_PER_DEG_LNG,
                ts: Some(64000.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 25.0 / METRES_PER_DEG_LNG,
                ts: Some(65000.0),
                ele: None,
            },
        ];
        assert_eq!(moving_time_seconds(&pts, DEFAULT_MIN_SPEED_MPS), 5);
    }

    #[test]
    fn moving_time_custom_min_speed_overrides_default() {
        let t = track(0.6, 1.0, 11, TrackOpts::default());
        assert_eq!(moving_time_seconds(&t, DEFAULT_MIN_SPEED_MPS), 10);
        assert_eq!(moving_time_seconds(&t, 1.0), 0);
    }

    #[test]
    fn moving_time_same_timestamp_pairs_are_skipped() {
        let pts = [
            TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: Some(0.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 1.0 / METRES_PER_DEG_LNG,
                ts: Some(0.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 2.0 / METRES_PER_DEG_LNG,
                ts: Some(1000.0),
                ele: None,
            },
        ];
        assert_eq!(moving_time_seconds(&pts, DEFAULT_MIN_SPEED_MPS), 1);
    }

    #[test]
    fn moving_time_points_without_ts_are_skipped() {
        let pts = [
            TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: Some(0.0),
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 5.0 / METRES_PER_DEG_LNG,
                ts: None,
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 10.0 / METRES_PER_DEG_LNG,
                ts: Some(2000.0),
                ele: None,
            },
        ];
        assert_eq!(moving_time_seconds(&pts, DEFAULT_MIN_SPEED_MPS), 0);
    }

    #[test]
    fn elevation_gain_sums_positive_deltas_only() {
        let pts = [
            TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: None,
                ele: Some(100.0),
            },
            TrackPoint {
                lat: 0.0,
                lng: 0.001,
                ts: None,
                ele: Some(110.0),
            },
            TrackPoint {
                lat: 0.0,
                lng: 0.002,
                ts: None,
                ele: Some(105.0),
            },
            TrackPoint {
                lat: 0.0,
                lng: 0.003,
                ts: None,
                ele: Some(130.0),
            },
        ];
        assert_eq!(elevation_gain_metres(&pts), 35);
    }

    #[test]
    fn elevation_gain_null_elevations_skipped() {
        let pts = [
            TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: None,
                ele: Some(100.0),
            },
            TrackPoint {
                lat: 0.0,
                lng: 0.001,
                ts: None,
                ele: None,
            },
            TrackPoint {
                lat: 0.0,
                lng: 0.002,
                ts: None,
                ele: Some(110.0),
            },
        ];
        assert_eq!(elevation_gain_metres(&pts), 0);
    }

    #[test]
    fn elevation_gain_empty_or_single_point_returns_zero() {
        assert_eq!(elevation_gain_metres(&[]), 0);
        assert_eq!(
            elevation_gain_metres(&[TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: None,
                ele: Some(100.0),
            }]),
            0
        );
    }

    #[test]
    fn splits_short_track_returns_none() {
        assert!(compute_real_splits(&[], KM_TICK_METRES).is_empty());
        assert!(compute_real_splits(
            &[TrackPoint {
                lat: 0.0,
                lng: 0.0,
                ts: Some(0.0),
                ele: None
            }],
            KM_TICK_METRES
        )
        .is_empty());
    }

    #[test]
    fn splits_track_without_timestamps_yields_none() {
        let mut pts: Vec<TrackPoint, 512> = Vec::new();
        for i in 0..50 {
            let _ = pts.push(TrackPoint {
                lat: 0.0,
                lng: (i as f64 * 100.0) / METRES_PER_DEG_LNG,
                ts: None,
                ele: None,
            });
        }
        assert!(compute_real_splits(&pts, KM_TICK_METRES).is_empty());
    }

    #[test]
    fn splits_even_paced_3km_produces_three_full_splits() {
        let pts = track(10.0, 2.0, 301, TrackOpts::default());
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        assert_eq!(splits.len(), 3);
        for s in &splits {
            assert!(
                (s.pace_s - 200).abs() <= 2,
                "pace {} not near 200",
                s.pace_s
            );
            assert!((s.distance_m - 1000).abs() <= 15, "dist {}", s.distance_m);
        }
        let kms: Vec<i32, 8> = splits.iter().map(|s| s.km).collect();
        assert_eq!(&kms[..], &[1, 2, 3]);
    }

    #[test]
    fn splits_first_split_timed_even_when_point_zero_lacks_timestamp() {
        let mut pts = track(10.0, 2.0, 301, TrackOpts::default());
        pts[0].ts = None;
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        assert_eq!(splits.len(), 3);
        assert!(
            splits[0].pace_s > 0,
            "first split pace was {}",
            splits[0].pace_s
        );
        assert!(
            (splits[0].pace_s - 200).abs() <= 4,
            "first split pace {} not near 200",
            splits[0].pace_s
        );
    }

    #[test]
    fn splits_final_partial_emitted_when_remainder_over_50m() {
        let pts = track(10.0, 2.0, 151, TrackOpts::default());
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        assert_eq!(splits.len(), 2);
        assert_eq!(splits[0].km, 1);
        assert_eq!(splits[1].km, 2);
        assert!(splits[1].distance_m >= 450 && splits[1].distance_m <= 550);
    }

    #[test]
    fn splits_final_partial_under_50m_is_dropped() {
        let pts = track(10.0, 2.0, 104, TrackOpts::default());
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        assert_eq!(splits.len(), 1);
        assert_eq!(splits[0].km, 1);
    }

    #[test]
    fn splits_elevation_gain_or_loss_carried_per_split() {
        let pts = track(
            10.0,
            2.0,
            110,
            TrackOpts {
                start_ele: Some(100.0),
                ele_step: 10.0,
            },
        );
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        assert!(!splits.is_empty());
        let e = splits[0].elevation_m.expect("elevation present");
        assert!((e - 1000).abs() <= 20);
    }

    #[test]
    fn splits_mile_tick_produces_mile_long_splits_pace_stays_sec_per_km() {
        let pts = track(10.0, 2.0, 162, TrackOpts::default());
        let km_splits = compute_real_splits(&pts, KM_TICK_METRES);
        let mi_splits = compute_real_splits(&pts, 1609.344);
        assert_eq!(km_splits.len(), 2);
        assert_eq!(mi_splits.len(), 1);
        assert!(
            (mi_splits[0].distance_m - 1609).abs() <= 20,
            "dist {}",
            mi_splits[0].distance_m
        );
        assert!(
            (mi_splits[0].pace_s - 200).abs() <= 2,
            "pace {}",
            mi_splits[0].pace_s
        );
    }

    #[test]
    fn splits_track_without_elevation_leaves_elevation_none() {
        let pts = track(10.0, 2.0, 105, TrackOpts::default());
        let splits = compute_real_splits(&pts, KM_TICK_METRES);
        for s in &splits {
            assert_eq!(s.elevation_m, None);
        }
    }
}
