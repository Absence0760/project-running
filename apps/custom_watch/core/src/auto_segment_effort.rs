//! Auto segment-effort shaping: pick the saved route an imported (route-less)
//! run clearly *followed*, then batch the effort rows it earned over that
//! route's segments (strava persona #21).
//!
//! [`pick_auto_effort_route`] is the unambiguous-match gate: it auto-computes
//! only when EXACTLY ONE candidate is an end-to-end match — both endpoints
//! project near the route ends and the run's length is within 20% of the route
//! length. Anything ambiguous (multiple strong matches, partial overlap, a run
//! that merely crosses the route) yields `None` — better no efforts than wrong
//! ones. [`build_segment_effort_rows`] then walks the track once via
//! [`crate::segments::compute_effort_from_track`], emitting one insert row per
//! matchable segment (the sparse / out-of-range ones drop out).
//!
//! Parity port of web `segments/auto_segment_effort.ts` — keep the heuristic,
//! edge cases, and test count in lockstep.
//!
//! Two ports-only shape choices, both `no_std`:
//! - web's numeric distance columns can arrive as strings over the wire, so it
//!   `Number(...)`-coerces; the watch carries `f64` and never sees the wire, so
//!   [`SegmentForEffort`] holds `f64` directly.
//! - [`SegmentEffortInsert`] carries `started_at_ms: f64` (the epoch-ms start
//!   crossing) rather than web's `started_at` ISO string, the same choice
//!   [`crate::segments::EffortResult`] makes — there is no allocator-free ISO
//!   formatter here (the phone formats).
//!
//! Pure logic, no peripherals, no allocator.

use heapless::Vec;

use crate::segments::{compute_effort_from_track, SegmentSlice, TrackPoint};

/// The endpoint-offset tolerance web defaults `toleranceM` to. Half a route's
/// combined start+end offset must fall inside this for a strong match.
pub const DEFAULT_AUTO_EFFORT_TOLERANCE_M: f64 = 100.0;

/// Longest segment set [`build_segment_effort_rows`] emits rows for. A v1 route
/// rarely carries more than ~30 segments; 64 leaves generous headroom while
/// keeping the row buffer stack-bounded.
pub const MAX_AUTO_EFFORT_SEGMENTS: usize = 64;

/// A saved route offered as a match for a route-less run, with how far its ends
/// project from the run's ends (`start_offset_m` / `end_offset_m`) and the
/// route's own length (`distance_m`).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct AutoEffortCandidate<'a> {
    pub id: &'a str,
    pub distance_m: f64,
    pub start_offset_m: f64,
    pub end_offset_m: f64,
}

/// Pick the route to auto-compute efforts against, or `None` when the match is
/// ambiguous. Mirrors web `pickAutoEffortRoute`; pass
/// [`DEFAULT_AUTO_EFFORT_TOLERANCE_M`] for the web default tolerance.
pub fn pick_auto_effort_route<'a>(
    candidates: &[AutoEffortCandidate<'a>],
    track_length_m: f64,
    tolerance_m: f64,
) -> Option<&'a str> {
    if track_length_m <= 0.0 {
        return None;
    }
    let mut count = 0usize;
    let mut found: Option<&'a str> = None;
    for c in candidates {
        let strong = c.start_offset_m + c.end_offset_m < 2.0 * tolerance_m
            && c.distance_m > 0.0
            && libm::fabs(c.distance_m - track_length_m) / track_length_m < 0.2;
        if strong {
            count += 1;
            found = Some(c.id);
        }
    }
    if count == 1 {
        found
    } else {
        None
    }
}

/// One route segment to compute an effort for, `(start, end)` distance-along
/// the route in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct SegmentForEffort<'a> {
    pub id: &'a str,
    pub start_distance_m: f64,
    pub end_distance_m: f64,
}

/// The run / user the emitted efforts belong to.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct EffortIds<'a> {
    pub run_id: &'a str,
    pub user_id: &'a str,
}

/// A segment-effort row ready to upsert.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct SegmentEffortInsert<'a> {
    pub segment_id: &'a str,
    pub run_id: &'a str,
    pub user_id: &'a str,
    pub time_seconds: f64,
    pub started_at_ms: f64,
}

/// Compute the effort rows a run earned over a set of route segments — the
/// matchable subset (segments the track actually covered) in one walk. Mirrors
/// web `buildSegmentEffortRows`; drops any segment past `MAX_AUTO_EFFORT_SEGMENTS`.
pub fn build_segment_effort_rows<'a>(
    segments: &[SegmentForEffort<'a>],
    track: &[TrackPoint],
    ids: EffortIds<'a>,
) -> Vec<SegmentEffortInsert<'a>, MAX_AUTO_EFFORT_SEGMENTS> {
    let mut rows: Vec<SegmentEffortInsert<'a>, MAX_AUTO_EFFORT_SEGMENTS> = Vec::new();
    for seg in segments {
        let Some(eff) = compute_effort_from_track(
            track,
            SegmentSlice {
                start_distance_m: seg.start_distance_m,
                end_distance_m: seg.end_distance_m,
            },
        ) else {
            continue;
        };
        if rows
            .push(SegmentEffortInsert {
                segment_id: seg.id,
                run_id: ids.run_id,
                user_id: ids.user_id,
                time_seconds: eff.time_seconds,
                started_at_ms: eff.started_at_ms,
            })
            .is_err()
        {
            break;
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::segments::MAX_EFFORT_TRACK_POINTS;

    /// 2026-01-01T00:00:00Z in epoch ms, matching the web test's
    /// `Date.UTC(2026, 0, 1, 0, 0, 0)`.
    const T0_MS: f64 = 1_767_225_600_000.0;

    /// A straight constant-pace track ~`step_m` per sample, ~`step_s` per
    /// sample (mirror of the web test's `straightTrack`).
    fn straight_track(samples: usize) -> Vec<TrackPoint, MAX_EFFORT_TRACK_POINTS> {
        let step_m = 10.0;
        let step_s = 5.0;
        let d_lat = step_m / 111_320.0;
        let mut out: Vec<TrackPoint, MAX_EFFORT_TRACK_POINTS> = Vec::new();
        for i in 0..samples {
            let _ = out.push(TrackPoint {
                lat: 40.0 + i as f64 * d_lat,
                lng: -105.0,
                ts: Some(T0_MS + i as f64 * step_s * 1000.0),
            });
        }
        out
    }

    // ─────────── pick_auto_effort_route ───────────

    #[test]
    fn one_strong_end_to_end_match_returns_its_id() {
        let id = pick_auto_effort_route(
            &[AutoEffortCandidate {
                id: "r1",
                distance_m: 5000.0,
                start_offset_m: 20.0,
                end_offset_m: 30.0,
            }],
            5050.0,
            DEFAULT_AUTO_EFFORT_TOLERANCE_M,
        );
        assert_eq!(id, Some("r1"));
    }

    #[test]
    fn length_mismatch_over_20pct_is_not_a_match() {
        let id = pick_auto_effort_route(
            &[AutoEffortCandidate {
                id: "r1",
                distance_m: 5000.0,
                start_offset_m: 20.0,
                end_offset_m: 30.0,
            }],
            8000.0,
            DEFAULT_AUTO_EFFORT_TOLERANCE_M,
        );
        assert_eq!(id, None);
    }

    #[test]
    fn high_offsets_run_only_crosses_the_route_is_not_a_match() {
        let id = pick_auto_effort_route(
            &[AutoEffortCandidate {
                id: "r1",
                distance_m: 5000.0,
                start_offset_m: 1800.0,
                end_offset_m: 2200.0,
            }],
            5000.0,
            DEFAULT_AUTO_EFFORT_TOLERANCE_M,
        );
        assert_eq!(id, None);
    }

    #[test]
    fn ambiguous_two_strong_matches_returns_none() {
        let id = pick_auto_effort_route(
            &[
                AutoEffortCandidate {
                    id: "r1",
                    distance_m: 5000.0,
                    start_offset_m: 20.0,
                    end_offset_m: 30.0,
                },
                AutoEffortCandidate {
                    id: "r2",
                    distance_m: 5020.0,
                    start_offset_m: 15.0,
                    end_offset_m: 25.0,
                },
            ],
            5000.0,
            DEFAULT_AUTO_EFFORT_TOLERANCE_M,
        );
        assert_eq!(id, None);
    }

    #[test]
    fn empty_candidates_or_zero_length_return_none() {
        assert_eq!(
            pick_auto_effort_route(&[], 5000.0, DEFAULT_AUTO_EFFORT_TOLERANCE_M),
            None
        );
        assert_eq!(
            pick_auto_effort_route(
                &[AutoEffortCandidate {
                    id: "r1",
                    distance_m: 5000.0,
                    start_offset_m: 0.0,
                    end_offset_m: 0.0,
                }],
                0.0,
                DEFAULT_AUTO_EFFORT_TOLERANCE_M,
            ),
            None
        );
    }

    // ─────────── build_segment_effort_rows ───────────

    #[test]
    fn one_row_per_matched_segment_unmatched_skipped() {
        let track = straight_track(200); // ~2 km, dense
        let segments = [
            SegmentForEffort {
                id: "seg-1",
                start_distance_m: 100.0,
                end_distance_m: 600.0,
            },
            SegmentForEffort {
                id: "seg-2",
                start_distance_m: 800.0,
                end_distance_m: 1400.0,
            },
            SegmentForEffort {
                id: "seg-off-track",
                start_distance_m: 5000.0,
                end_distance_m: 6000.0, // beyond track -> skipped
            },
        ];
        let rows = build_segment_effort_rows(
            &segments,
            &track,
            EffortIds {
                run_id: "run-1",
                user_id: "user-1",
            },
        );
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].segment_id, "seg-1");
        assert_eq!(rows[1].segment_id, "seg-2");
        for r in &rows {
            assert_eq!(r.run_id, "run-1");
            assert_eq!(r.user_id, "user-1");
            assert!(r.time_seconds > 0.0);
            assert!(r.started_at_ms.is_finite());
        }
    }

    #[test]
    fn accepts_a_single_matched_segment() {
        // Web's twin test proves the string-typed wire distance columns coerce;
        // the watch carries f64 so there is nothing to coerce — this pins the
        // single-segment happy path directly.
        let rows = build_segment_effort_rows(
            &[SegmentForEffort {
                id: "seg-1",
                start_distance_m: 100.0,
                end_distance_m: 600.0,
            }],
            &straight_track(200),
            EffortIds {
                run_id: "r",
                user_id: "u",
            },
        );
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn empty_segment_set_returns_empty() {
        let rows = build_segment_effort_rows(
            &[],
            &straight_track(50),
            EffortIds {
                run_id: "r",
                user_id: "u",
            },
        );
        assert!(rows.is_empty());
    }
}
