//! Segment-effort extraction + leaderboard shaping (decisions §37).
//!
//! Parity port of the web/Dart helper — keep the algorithm, constants, and
//! edge cases in lockstep with:
//! - `apps/web/src/lib/segments/segments.ts` (canonical),
//! - `apps/mobile_android/lib/segments.dart` (Dart twin).
//!
//! v1 segments are slices of a *saved route* — `(start_distance_m,
//! end_distance_m)`. [`compute_effort_from_track`] walks a run's track once,
//! accumulating cumulative distance via haversine, and interpolates the
//! timestamps at the moments cumulative distance crosses the window bounds.
//! [`assign_competition_ranks`] is the 1224 standard-competition-rank pass the
//! leaderboard fetcher uses; [`SEGMENT_AGE_BANDS`] / [`SegmentAgeBand`] /
//! [`SegmentGenderFilter`] / [`crown_label`] are the KOM/QOM leaderboard-filter
//! vocabulary.
//!
//! Two ports-only shape choices, both because this is `no_std`:
//! - web timestamps are ISO strings parsed with `Date.parse`; the watch carries
//!   epoch-**milliseconds** directly ([`TrackPoint::ts`]) and returns the start
//!   crossing as [`EffortResult::started_at_ms`] rather than an ISO string,
//!   since there is no allocator-free ISO formatter here (the phone formats).
//! - [`assign_competition_ranks`] writes ranks into a caller-provided slice
//!   parallel to `rows` rather than returning an owned list. The web `{ row,
//!   rank }[]` payload preservation is inherent — the caller keeps `rows` — and
//!   a caller slice sidesteps a multi-KB owned `Vec` on the leaderboard path.
//!
//! Pure logic, no peripherals, no allocator.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

/// Longest track [`compute_effort_from_track`] analyses. A longer track is
/// trusted only up to this many points (the crate's `.take(MAX)` convention),
/// so the cumulative + step buffers stay stack-bounded.
pub const MAX_EFFORT_TRACK_POINTS: usize = 512;

/// A `(start, end)` distance window into a saved route, in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct SegmentSlice {
    pub start_distance_m: f64,
    pub end_distance_m: f64,
}

/// Elapsed time over the window + the epoch-ms of the start crossing (the web
/// `started_at` ISO string is this same instant, formatted phone-side).
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct EffortResult {
    pub time_seconds: f64,
    pub started_at_ms: f64,
}

/// One track waypoint. `ts` is the fix time in epoch **milliseconds** (web
/// parses its ISO string to the same via `Date.parse`); `None` models a fix
/// with no timestamp, which kills the crossing interpolation like web's `!a.ts`.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TrackPoint {
    pub lat: f64,
    pub lng: f64,
    pub ts: Option<f64>,
}

/// Elapsed time over the `(start, end)` window of a run track. Returns `None`
/// when the track is too short to cover the segment, has no timestamps, or is
/// too sparsely sampled to resolve the crossings (median sample step > segment
/// length / 5, per §37 trade-off 2).
pub fn compute_effort_from_track(
    track: &[TrackPoint],
    segment: SegmentSlice,
) -> Option<EffortResult> {
    if track.len() < 2 {
        return None;
    }
    let seg_len = segment.end_distance_m - segment.start_distance_m;
    if seg_len <= 0.0 {
        return None;
    }

    let track = &track[..track.len().min(MAX_EFFORT_TRACK_POINTS)];

    let mut cum: Vec<f64, MAX_EFFORT_TRACK_POINTS> = Vec::new();
    let _ = cum.push(0.0);
    let mut steps: Vec<f64, MAX_EFFORT_TRACK_POINTS> = Vec::new();
    for w in track.windows(2) {
        let d = haversine_metres(w[0].lat, w[0].lng, w[1].lat, w[1].lng);
        let last = *cum.last().unwrap();
        let _ = cum.push(last + d);
        if d > 0.0 {
            let _ = steps.push(d);
        }
    }
    if *cum.last().unwrap() < segment.end_distance_m {
        return None;
    }
    if steps.is_empty() {
        return None;
    }

    // Sparsity guard: the median sample step must be at least 5x smaller than
    // the segment so the start / end crossings are well-resolved.
    steps.sort_unstable_by(|a, b| a.partial_cmp(b).unwrap_or(core::cmp::Ordering::Equal));
    let median = steps[steps.len() / 2];
    if median > seg_len / 5.0 {
        return None;
    }

    let start_ts = timestamp_at_distance(track, &cum, segment.start_distance_m)?;
    let end_ts = timestamp_at_distance(track, &cum, segment.end_distance_m)?;

    let elapsed = (end_ts - start_ts) / 1000.0;
    if elapsed.is_nan() || elapsed <= 0.0 {
        return None;
    }

    Some(EffortResult {
        time_seconds: elapsed,
        started_at_ms: start_ts,
    })
}

/// Linearly interpolates the epoch-ms at the moment cumulative distance crosses
/// `target`. Returns `None` when no two adjacent points carry timestamps to
/// bracket the crossing.
fn timestamp_at_distance(track: &[TrackPoint], cum: &[f64], target: f64) -> Option<f64> {
    for i in 1..track.len() {
        if cum[i] < target {
            continue;
        }
        let prev = cum[i - 1];
        let here = cum[i];
        let a = &track[i - 1];
        let b = &track[i];
        let (t_a, t_b) = match (a.ts, b.ts) {
            (Some(x), Some(y)) => (x, y),
            _ => return None,
        };
        if t_a.is_nan() || t_b.is_nan() {
            return None;
        }
        let span = here - prev;
        let frac = if span > 0.0 {
            (target - prev) / span
        } else {
            0.0
        };
        return Some(t_a + (t_b - t_a) * frac);
    }
    None
}

/// A leaderboard row that carries a finish time to rank on.
pub trait HasTimeSeconds {
    fn time_seconds(&self) -> f64;
}

/// Standard competition rank (1224) for an ascending-time leaderboard: tied
/// times share the lower rank, the next distinct time jumps to its natural
/// ordinal slot (times `[10, 10, 15]` -> `[1, 1, 3]`). Writes one rank per row
/// into `out` and returns how many were written (`min(rows.len(), out.len())`).
/// Caller must pass `rows` pre-sorted ascending by time.
pub fn assign_competition_ranks<T: HasTimeSeconds>(rows: &[T], out: &mut [u32]) -> usize {
    let n = rows.len().min(out.len());
    let mut last_time = f64::NAN;
    let mut last_rank: u32 = 0;
    for (i, (slot, row)) in out.iter_mut().zip(rows.iter()).enumerate() {
        let t = row.time_seconds();
        // NaN seed never === any number, so the first row always gets rank 1
        // and a 0-second effort can't inherit rank 0 from the sentinel.
        let rank = if t == last_time {
            last_rank
        } else {
            i as u32 + 1
        };
        last_time = t;
        last_rank = rank;
        *slot = rank;
    }
    n
}

/// Strava-style age band labels — 5-year bins starting at 18-19, then
/// 20-24 / 25-29 / ... up to `75+`. The tokens are locale-agnostic and the
/// `segment_leaderboard_tiered` RPC accepts any of them; pass `None` for
/// "all ages".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SegmentAgeBand {
    A1819,
    A2024,
    A2529,
    A3034,
    A3539,
    A4044,
    A4549,
    A5054,
    A5559,
    A6064,
    A6569,
    A7074,
    A75Plus,
}

impl SegmentAgeBand {
    /// The RPC / display token for this band ("18-19" ... "75+").
    pub const fn as_str(self) -> &'static str {
        match self {
            SegmentAgeBand::A1819 => "18-19",
            SegmentAgeBand::A2024 => "20-24",
            SegmentAgeBand::A2529 => "25-29",
            SegmentAgeBand::A3034 => "30-34",
            SegmentAgeBand::A3539 => "35-39",
            SegmentAgeBand::A4044 => "40-44",
            SegmentAgeBand::A4549 => "45-49",
            SegmentAgeBand::A5054 => "50-54",
            SegmentAgeBand::A5559 => "55-59",
            SegmentAgeBand::A6064 => "60-64",
            SegmentAgeBand::A6569 => "65-69",
            SegmentAgeBand::A7074 => "70-74",
            SegmentAgeBand::A75Plus => "75+",
        }
    }
}

/// The thirteen age bands, oldest bookend first, matching the web const array.
pub const SEGMENT_AGE_BANDS: [SegmentAgeBand; 13] = [
    SegmentAgeBand::A1819,
    SegmentAgeBand::A2024,
    SegmentAgeBand::A2529,
    SegmentAgeBand::A3034,
    SegmentAgeBand::A3539,
    SegmentAgeBand::A4044,
    SegmentAgeBand::A4549,
    SegmentAgeBand::A5054,
    SegmentAgeBand::A5559,
    SegmentAgeBand::A6064,
    SegmentAgeBand::A6569,
    SegmentAgeBand::A7074,
    SegmentAgeBand::A75Plus,
];

/// The gender leaderboard filter.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SegmentGenderFilter {
    Male,
    Female,
    Nonbinary,
}

/// Which KOM/QOM crown tier the rank-1 holder owns, given the active filter.
/// An enum (not a formatted English string) so the display / aria label is
/// localised at the render site — the badges / onboarding convention.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum CrownLabel {
    Overall,
    Gender(SegmentGenderFilter),
    Age(SegmentAgeBand),
    GenderAge(SegmentGenderFilter, SegmentAgeBand),
}

/// The crown tier for a `(gender, age)` filter pair. Mirrors web `crownLabel`'s
/// four branches.
pub fn crown_label(gender: Option<SegmentGenderFilter>, age: Option<SegmentAgeBand>) -> CrownLabel {
    match (gender, age) {
        (None, None) => CrownLabel::Overall,
        (Some(g), None) => CrownLabel::Gender(g),
        (None, Some(a)) => CrownLabel::Age(a),
        (Some(g), Some(a)) => CrownLabel::GenderAge(g, a),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0_MS: f64 = 1_767_225_600_000.0;

    /// Straight-line track at constant pace: each step adds ~`step_m` metres and
    /// `step_s` seconds. Lat advances along a meridian so haversine-cumulated
    /// distance tracks `i * step_m` to sub-metre precision (mirror of the web
    /// test's `straightTrack`).
    fn straight_track(
        points: usize,
        step_m: f64,
        step_s: f64,
    ) -> Vec<TrackPoint, MAX_EFFORT_TRACK_POINTS> {
        let start_lat = 37.0;
        let lng = -122.0;
        let deg_per_m = 1.0 / 111_320.0;
        let mut out: Vec<TrackPoint, MAX_EFFORT_TRACK_POINTS> = Vec::new();
        for i in 0..points {
            let _ = out.push(TrackPoint {
                lat: start_lat + i as f64 * step_m * deg_per_m,
                lng,
                ts: Some(T0_MS + i as f64 * step_s * 1000.0),
            });
        }
        out
    }

    #[derive(Clone, Copy)]
    struct Row {
        time_seconds: f64,
    }
    impl HasTimeSeconds for Row {
        fn time_seconds(&self) -> f64 {
            self.time_seconds
        }
    }

    #[derive(Clone, Copy)]
    struct RichRow {
        time_seconds: f64,
        id: char,
        extra: char,
    }
    impl HasTimeSeconds for RichRow {
        fn time_seconds(&self) -> f64 {
            self.time_seconds
        }
    }

    fn ranks<T: HasTimeSeconds>(rows: &[T]) -> std::vec::Vec<u32> {
        let mut out = std::vec![0u32; rows.len()];
        let n = assign_competition_ranks(rows, &mut out);
        out.truncate(n);
        out
    }

    fn rows_of(times: &[f64]) -> std::vec::Vec<Row> {
        times.iter().map(|&t| Row { time_seconds: t }).collect()
    }

    // ─────────── compute_effort_from_track ───────────

    #[test]
    fn computes_elapsed_time_over_a_clean_segment() {
        let track = straight_track(200, 5.0, 1.0); // 5 m/s
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 100.0,
                end_distance_m: 600.0,
            },
        )
        .unwrap();
        assert!((eff.time_seconds - 100.0).abs() < 1.0);
        assert!(eff.started_at_ms.is_finite());
    }

    #[test]
    fn returns_none_when_run_shorter_than_segment_end() {
        let track = straight_track(50, 5.0, 1.0); // ~245 m
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 0.0,
                end_distance_m: 1000.0,
            },
        );
        assert_eq!(eff, None);
    }

    #[test]
    fn returns_none_on_tracks_shorter_than_two_points() {
        assert_eq!(
            compute_effort_from_track(
                &[],
                SegmentSlice {
                    start_distance_m: 0.0,
                    end_distance_m: 100.0,
                }
            ),
            None
        );
        assert_eq!(
            compute_effort_from_track(
                &[TrackPoint {
                    lat: 0.0,
                    lng: 0.0,
                    ts: Some(T0_MS),
                }],
                SegmentSlice {
                    start_distance_m: 0.0,
                    end_distance_m: 100.0,
                }
            ),
            None
        );
    }

    #[test]
    fn returns_none_on_zero_or_negative_window_length() {
        let track = straight_track(50, 5.0, 1.0);
        assert_eq!(
            compute_effort_from_track(
                &track,
                SegmentSlice {
                    start_distance_m: 100.0,
                    end_distance_m: 100.0,
                }
            ),
            None
        );
        assert_eq!(
            compute_effort_from_track(
                &track,
                SegmentSlice {
                    start_distance_m: 200.0,
                    end_distance_m: 100.0,
                }
            ),
            None
        );
    }

    #[test]
    fn rejects_sparse_sampling() {
        // 10 s sampling at 5 m/s = 50 m steps; segment of 100 m -> ratio 0.5,
        // above 0.2, so rejected.
        let track = straight_track(30, 50.0, 10.0);
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 100.0,
                end_distance_m: 200.0,
            },
        );
        assert_eq!(eff, None);
    }

    #[test]
    fn returns_none_when_adjacent_points_lack_timestamps() {
        // Window 50-55 m falls in the bracket [10, 11]; stripping ts on that
        // bracket kills the interpolation.
        let mut track = straight_track(50, 5.0, 1.0);
        track[10].ts = None;
        track[11].ts = None;
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 50.0,
                end_distance_m: 55.0,
            },
        );
        assert_eq!(eff, None);
    }

    #[test]
    fn interpolates_start_and_end_timestamps_mid_segment() {
        let track = straight_track(200, 10.0, 2.0); // 5 m/s
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 105.0,
                end_distance_m: 605.0,
            },
        )
        .unwrap();
        assert!((eff.time_seconds - 100.0).abs() < 1.0);
    }

    #[test]
    fn handles_endpoints_landing_near_sample_crossings() {
        let track = straight_track(100, 10.0, 2.0);
        let eff = compute_effort_from_track(
            &track,
            SegmentSlice {
                start_distance_m: 100.0,
                end_distance_m: 500.0,
            },
        )
        .unwrap();
        assert!((eff.time_seconds - 80.0).abs() < 1.0);
    }

    // ─────────── assign_competition_ranks ───────────

    #[test]
    fn ranks_empty_input_returns_empty() {
        let rows: [Row; 0] = [];
        assert_eq!(ranks(&rows), std::vec::Vec::<u32>::new());
    }

    #[test]
    fn ranks_distinct_times_yield_one_to_n() {
        assert_eq!(ranks(&rows_of(&[10.0, 20.0, 30.0])), std::vec![1, 2, 3]);
    }

    #[test]
    fn ranks_ties_share_rank_next_jumps_to_ordinal() {
        assert_eq!(
            ranks(&rows_of(&[10.0, 10.0, 15.0, 15.0, 20.0])),
            std::vec![1, 1, 3, 3, 5]
        );
    }

    #[test]
    fn ranks_leading_tie_of_three_shares_rank_one() {
        assert_eq!(
            ranks(&rows_of(&[60.0, 60.0, 60.0, 65.0])),
            std::vec![1, 1, 1, 4]
        );
    }

    #[test]
    fn ranks_zero_time_does_not_collide_with_nan_seed() {
        assert_eq!(ranks(&rows_of(&[0.0, 0.0, 5.0])), std::vec![1, 1, 3]);
    }

    #[test]
    fn ranks_preserve_the_original_row_payload() {
        let rows = [
            RichRow {
                time_seconds: 10.0,
                id: 'a',
                extra: 'x',
            },
            RichRow {
                time_seconds: 10.0,
                id: 'b',
                extra: 'y',
            },
        ];
        let mut out = [0u32; 2];
        assign_competition_ranks(&rows, &mut out);
        assert_eq!(out, [1, 1]);
        assert_eq!(rows[0].id, 'a');
        assert_eq!(rows[1].id, 'b');
        assert_eq!(rows[0].extra, 'x');
    }

    #[test]
    fn ranks_single_element_gets_rank_one() {
        assert_eq!(ranks(&rows_of(&[42.0])), std::vec![1]);
    }

    #[test]
    fn ranks_every_row_tied_produces_all_rank_one() {
        assert_eq!(
            ranks(&rows_of(&[100.0, 100.0, 100.0, 100.0])),
            std::vec![1, 1, 1, 1]
        );
    }

    #[test]
    fn ranks_tie_cluster_in_the_middle() {
        assert_eq!(
            ranks(&rows_of(&[50.0, 60.0, 60.0, 60.0, 75.0])),
            std::vec![1, 2, 2, 2, 5]
        );
    }

    #[test]
    fn ranks_alternating_ties() {
        assert_eq!(
            ranks(&rows_of(&[10.0, 10.0, 20.0, 30.0, 30.0])),
            std::vec![1, 1, 3, 4, 4]
        );
    }

    #[test]
    fn ranks_floating_point_times_by_strict_equality() {
        assert_eq!(
            ranks(&rows_of(&[10.5, 10.5, 10.5000001])),
            std::vec![1, 1, 3]
        );
    }

    #[test]
    fn ranks_one_thousand_rows_well_formed() {
        let rows: std::vec::Vec<Row> = (0..1000)
            .map(|i| Row {
                time_seconds: i as f64,
            })
            .collect();
        let mut out = std::vec![0u32; 1000];
        let n = assign_competition_ranks(&rows, &mut out);
        assert_eq!(n, 1000);
        assert_eq!(out[0], 1);
        assert_eq!(out[999], 1000);
    }

    // ─────────── SEGMENT_AGE_BANDS shape ───────────

    #[test]
    fn age_bands_have_thirteen_entries() {
        assert_eq!(SEGMENT_AGE_BANDS.len(), 13);
    }

    #[test]
    fn age_bands_start_at_1819_end_at_75plus() {
        assert_eq!(SEGMENT_AGE_BANDS[0].as_str(), "18-19");
        assert_eq!(
            SEGMENT_AGE_BANDS[SEGMENT_AGE_BANDS.len() - 1].as_str(),
            "75+"
        );
    }

    #[test]
    fn age_bands_every_entry_matches_the_rpc_parser() {
        for band in SEGMENT_AGE_BANDS {
            assert!(
                is_rpc_age_token(band.as_str()),
                "band {} would crash the RPC",
                band.as_str()
            );
        }
    }

    #[test]
    fn age_bands_contiguous_five_year_bins() {
        for band in SEGMENT_AGE_BANDS {
            if band.as_str() == "75+" {
                continue;
            }
            let s = band.as_str();
            let (lo_s, hi_s) = s.split_once('-').unwrap();
            let lo: i32 = lo_s.parse().unwrap();
            let hi: i32 = hi_s.parse().unwrap();
            if s == "18-19" {
                assert_eq!(lo, 18);
                assert_eq!(hi, 19);
                continue;
            }
            assert_eq!(hi - lo, 4, "band {s} not a 5-year bin");
            assert_eq!(lo % 5, 0, "band {s} not anchored on a multiple of 5");
        }
    }

    // ─────────── SEGMENT_AGE_BANDS — vs the RPC's regex ───────────

    #[test]
    fn age_bands_every_band_the_rpc_accepts() {
        // The plpgsql RPC accepts `^[0-9]+-[0-9]+$` OR the literal '75+'
        // (migration 20260829_001). Pin every band against that contract so
        // client / server drift can't slip past review.
        for band in SEGMENT_AGE_BANDS {
            assert!(
                is_rpc_age_token(band.as_str()),
                "band '{}' would be rejected by the RPC",
                band.as_str()
            );
        }
    }

    /// Hand-rolled matcher for the RPC's `^[0-9]+-[0-9]+$` OR literal '75+'.
    fn is_rpc_age_token(s: &str) -> bool {
        if s == "75+" {
            return true;
        }
        match s.split_once('-') {
            Some((lo, hi)) => {
                !lo.is_empty()
                    && !hi.is_empty()
                    && lo.bytes().all(|b| b.is_ascii_digit())
                    && hi.bytes().all(|b| b.is_ascii_digit())
            }
            None => false,
        }
    }

    // ─────────── crown_label ───────────

    #[test]
    fn crown_no_filter_is_overall() {
        assert_eq!(crown_label(None, None), CrownLabel::Overall);
    }

    #[test]
    fn crown_gender_only() {
        assert_eq!(
            crown_label(Some(SegmentGenderFilter::Male), None),
            CrownLabel::Gender(SegmentGenderFilter::Male)
        );
        assert_eq!(
            crown_label(Some(SegmentGenderFilter::Female), None),
            CrownLabel::Gender(SegmentGenderFilter::Female)
        );
        assert_eq!(
            crown_label(Some(SegmentGenderFilter::Nonbinary), None),
            CrownLabel::Gender(SegmentGenderFilter::Nonbinary)
        );
    }

    #[test]
    fn crown_age_band_only() {
        assert_eq!(
            crown_label(None, Some(SegmentAgeBand::A3539)),
            CrownLabel::Age(SegmentAgeBand::A3539)
        );
        assert_eq!(
            crown_label(None, Some(SegmentAgeBand::A75Plus)),
            CrownLabel::Age(SegmentAgeBand::A75Plus)
        );
    }

    #[test]
    fn crown_gender_and_age_band_combined() {
        assert_eq!(
            crown_label(
                Some(SegmentGenderFilter::Female),
                Some(SegmentAgeBand::A3034)
            ),
            CrownLabel::GenderAge(SegmentGenderFilter::Female, SegmentAgeBand::A3034)
        );
        assert_eq!(
            crown_label(
                Some(SegmentGenderFilter::Male),
                Some(SegmentAgeBand::A75Plus)
            ),
            CrownLabel::GenderAge(SegmentGenderFilter::Male, SegmentAgeBand::A75Plus)
        );
        assert_eq!(
            crown_label(
                Some(SegmentGenderFilter::Nonbinary),
                Some(SegmentAgeBand::A1819)
            ),
            CrownLabel::GenderAge(SegmentGenderFilter::Nonbinary, SegmentAgeBand::A1819)
        );
    }
}
