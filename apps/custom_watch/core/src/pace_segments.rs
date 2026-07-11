//! NRC-style pace-heatmap segmentation.
//!
//! A parity port of web `segments/pace_segments.ts` (canonical) and its Dart
//! twin `widgets/pace_segments.dart`: classify each track segment into a speed
//! bucket (activity-scaled) and an age band (oldest tail → newest head), then
//! coalesce consecutive segments sharing both into a single coloured polyline
//! so a renderer draws one primitive per run rather than one per GPS fix. The
//! colour ramp + alpha bands are the same the app paints, so a run coloured on
//! the watch matches the phone and web pixel-for-pixel.
//!
//! [`compute_pace_buckets`] + [`pace_bucket_for_segment`] are the Dart twin's
//! live-cache helpers: a segment's endpoints never move once both fixes exist
//! (the recorder only appends), so the buckets can be classified once and the
//! cache extended by the tail instead of re-walking the whole track per fix.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`. A
//! [`PaceSegment`] stores the inclusive point-index span into the caller's
//! track rather than a copy of the coordinates, so the output stays cheap.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

/// Output capacity: worst case one segment per track segment. A tier-1 track
/// is bounded like a course polyline; longer inputs are clamped to this many
/// segments rather than overflowing.
pub const MAX_PACE_SEGMENTS: usize = 256;

/// Slow → fast colour ramp, 6 buckets as `(r, g, b)`. Five breakpoints
/// partition speed into six buckets; the ramp has one colour per bucket.
pub const PACE_RAMP: [(u8, u8, u8); 6] = [
    (0xEF, 0x44, 0x44), // red — slowest
    (0xF9, 0x73, 0x16), // orange
    (0xFB, 0xBF, 0x24), // amber
    (0xA3, 0xE6, 0x35), // lime
    (0x10, 0xB9, 0x81), // emerald
    (0x22, 0xD3, 0xEE), // cyan — fastest
];

/// Three age bands (oldest → newest) applied as alpha over the pace colour.
/// The tail fades like a comet; the segment nearest the runner is opaque.
pub const AGE_ALPHAS: [f32; 3] = [0.55, 0.80, 1.0];

/// Which activity's speed ladder to bucket against. Four activities use pace
/// (min/km); cycling is displayed as speed but the buckets are expressed in
/// m/s so one helper handles both.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ActivityKind {
    Run,
    Walk,
    Cycle,
    Hike,
}

/// Speed break-points (m/s), slow → fast, per activity. Mirrors the web
/// `SPEED_BREAKPOINTS` record / the Dart `_speedBreakpoints` map.
const fn breakpoints(activity: ActivityKind) -> [f64; 5] {
    match activity {
        ActivityKind::Run => [2.2, 2.7, 3.2, 3.7, 4.4],
        ActivityKind::Walk => [1.0, 1.3, 1.6, 1.8, 2.2],
        ActivityKind::Cycle => [3.3, 5.0, 6.7, 8.3, 10.0],
        ActivityKind::Hike => [0.8, 1.1, 1.4, 1.7, 2.2],
    }
}

/// One track waypoint. `secs` is the fix time in seconds; a segment whose
/// endpoints both carry a time can be given a pace, otherwise it falls back to
/// the slowest bucket (matching the web/Dart twin).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackPoint {
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub secs: Option<f64>,
}

/// A colour with a fractional alpha, as the ramp + age band resolve to.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: f32,
}

/// One coalesced run of same-`(bucket, band)` segments. `first_point` and
/// `last_point` are inclusive indices into the track the caller passed to
/// [`build_pace_segments`] — the polyline is `track[first_point..=last_point]`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PaceSegment {
    pub first_point: usize,
    pub last_point: usize,
    pub pace_bucket: usize,
    pub age_band: usize,
}

impl PaceSegment {
    /// The polyline this segment covers, borrowed from the source track.
    pub fn points<'a>(&self, track: &'a [TrackPoint]) -> &'a [TrackPoint] {
        &track[self.first_point..=self.last_point]
    }

    /// The rgba colour this segment paints with.
    pub fn rgba(&self) -> Rgba {
        rgba_for(self.pace_bucket, self.age_band)
    }
}

/// Which pace bucket the given speed falls into. Bucket 0 is slowest, 5
/// (`breakpoints.len()`) is fastest. Clamped at both ends.
pub fn pace_bucket_for_speed(mps: f64, activity: ActivityKind) -> usize {
    let breaks = breakpoints(activity);
    for (i, b) in breaks.iter().enumerate() {
        if mps < *b {
            return i;
        }
    }
    breaks.len()
}

/// Which age band the segment at `segment_index` falls into, given
/// `segment_count` segments. 0 = oldest, 2 = newest. Short tracks (≤ 1
/// segment) are treated as fully newest.
pub fn age_band_for(segment_index: usize, segment_count: usize) -> usize {
    if segment_count <= 1 {
        return 2;
    }
    let f = segment_index as f64 / (segment_count - 1) as f64;
    if f < 1.0 / 3.0 {
        0
    } else if f < 2.0 / 3.0 {
        1
    } else {
        2
    }
}

/// Pace bucket for the single segment `a`→`b` under `activity`. A timestamp-less
/// (or non-positive-interval) segment falls back to the slowest bucket.
pub fn pace_bucket_for_segment(a: &TrackPoint, b: &TrackPoint, activity: ActivityKind) -> usize {
    match segment_speed_mps(a, b) {
        Some(mps) => pace_bucket_for_speed(mps, activity),
        None => 0,
    }
}

/// Per-segment pace buckets for `track` under `activity`. Segment `i` spans
/// `track[i]`→`track[i+1]`. Empty for tracks shorter than two points. This is
/// the O(n) haversine pass [`build_pace_segments`] would otherwise run every
/// rebuild; cache it and extend only the tail during recording.
pub fn compute_pace_buckets(
    track: &[TrackPoint],
    activity: ActivityKind,
) -> Vec<u8, MAX_PACE_SEGMENTS> {
    let mut out = Vec::new();
    for w in track.windows(2) {
        if out
            .push(pace_bucket_for_segment(&w[0], &w[1], activity) as u8)
            .is_err()
        {
            break;
        }
    }
    out
}

/// True iff at least one consecutive pair of waypoints carries usable times, so
/// a meaningful pace can be computed. A cheap precondition the caller can use
/// to gate the heatmap render path.
pub fn has_track_timestamps(track: &[TrackPoint]) -> bool {
    track
        .windows(2)
        .any(|w| w[0].secs.is_some() && w[1].secs.is_some())
}

fn segment_speed_mps(a: &TrackPoint, b: &TrackPoint) -> Option<f64> {
    let (ta, tb) = (a.secs?, b.secs?);
    let dt = tb - ta;
    if !dt.is_finite() || dt <= 0.0 {
        return None;
    }
    let d = haversine_metres(a.lat_deg, a.lon_deg, b.lat_deg, b.lon_deg);
    if d <= 0.0 {
        return None;
    }
    Some(d / dt)
}

fn rgba_for(bucket: usize, age_band: usize) -> Rgba {
    let (r, g, b) = PACE_RAMP[bucket.min(PACE_RAMP.len() - 1)];
    let a = AGE_ALPHAS[age_band.min(AGE_ALPHAS.len() - 1)];
    Rgba { r, g, b, a }
}

/// Build the coalesced pace-coloured, age-faded segments for `track`. Each
/// track segment is assigned a `(pace_bucket, age_band)` and consecutive
/// segments sharing both are merged. Returns an empty list for tracks with
/// fewer than two points. Pass a cached `pace_buckets` (from
/// [`compute_pace_buckets`]) to skip the haversine pass; otherwise it is
/// computed internally. Timestamp-less segments fall back to the slowest
/// bucket, matching the web/Dart twin.
pub fn build_pace_segments(
    track: &[TrackPoint],
    activity: ActivityKind,
    pace_buckets: Option<&[u8]>,
) -> Vec<PaceSegment, MAX_PACE_SEGMENTS> {
    let mut out: Vec<PaceSegment, MAX_PACE_SEGMENTS> = Vec::new();
    if track.len() < 2 {
        return out;
    }

    let computed = match pace_buckets {
        Some(_) => None,
        None => Some(compute_pace_buckets(track, activity)),
    };
    let buckets: &[u8] = match pace_buckets {
        Some(b) => b,
        None => computed.as_ref().unwrap(),
    };

    let seg_count = (track.len() - 1).min(buckets.len());
    if seg_count == 0 {
        return out;
    }

    let push_seg =
        |out: &mut Vec<PaceSegment, MAX_PACE_SEGMENTS>, first_seg: usize, last_point: usize| {
            let _ = out.push(PaceSegment {
                first_point: first_seg,
                last_point,
                pace_bucket: buckets[first_seg] as usize,
                age_band: age_band_for(first_seg, seg_count),
            });
        };

    let mut run_start = 0;
    for i in 1..seg_count {
        if buckets[i] != buckets[i - 1]
            || age_band_for(i, seg_count) != age_band_for(i - 1, seg_count)
        {
            push_seg(&mut out, run_start, i);
            run_start = i;
        }
    }
    push_seg(&mut out, run_start, seg_count);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEG_PER_M: f64 = 1.0 / 111_320.0;

    fn tp(lat_deg: f64, lon_deg: f64, secs: Option<f64>) -> TrackPoint {
        TrackPoint {
            lat_deg,
            lon_deg,
            secs,
        }
    }

    /// A straight north-bound track: `points` fixes stepping `step_m` metres
    /// and `step_s` seconds apart. Mirrors the web `straightTrack` helper.
    fn straight_track(points: usize, step_m: f64, step_s: f64) -> std::vec::Vec<TrackPoint> {
        (0..points)
            .map(|i| {
                tp(
                    37.0 + i as f64 * step_m * DEG_PER_M,
                    -122.0,
                    Some(i as f64 * step_s),
                )
            })
            .collect()
    }

    fn alpha_of(seg: &PaceSegment) -> f32 {
        seg.rgba().a
    }

    fn rgb_of(seg: &PaceSegment) -> (u8, u8, u8) {
        let c = seg.rgba();
        (c.r, c.g, c.b)
    }

    #[test]
    fn pace_bucket_clamps_below_the_slowest_break_to_zero() {
        assert_eq!(pace_bucket_for_speed(0.1, ActivityKind::Run), 0);
        assert_eq!(pace_bucket_for_speed(2.1, ActivityKind::Run), 0);
    }

    #[test]
    fn pace_bucket_clamps_above_the_fastest_break_to_length() {
        assert_eq!(pace_bucket_for_speed(99.0, ActivityKind::Run), 5);
        assert_eq!(pace_bucket_for_speed(99.0, ActivityKind::Cycle), 5);
    }

    #[test]
    fn pace_bucket_scales_with_activity() {
        assert_eq!(pace_bucket_for_speed(2.0, ActivityKind::Run), 0);
        assert_eq!(pace_bucket_for_speed(2.0, ActivityKind::Walk), 4);
    }

    #[test]
    fn running_five_min_per_km_lands_mid_ramp() {
        let b = pace_bucket_for_speed(3.33, ActivityKind::Run);
        assert!((2..=4).contains(&b));
    }

    #[test]
    fn running_a_jog_is_in_a_slow_bucket() {
        assert!(pace_bucket_for_speed(2.5, ActivityKind::Run) < 3);
    }

    #[test]
    fn running_a_hard_effort_clamps_to_fastest() {
        assert_eq!(pace_bucket_for_speed(5.0, ActivityKind::Run), 5);
    }

    #[test]
    fn running_near_stationary_clamps_to_slowest() {
        assert_eq!(pace_bucket_for_speed(0.05, ActivityKind::Run), 0);
    }

    #[test]
    fn cycling_mid_speed_lands_mid_ramp() {
        let b = pace_bucket_for_speed(6.94, ActivityKind::Cycle);
        assert!((2..=4).contains(&b));
    }

    #[test]
    fn cycling_fast_clamps_to_fastest() {
        assert_eq!(pace_bucket_for_speed(11.1, ActivityKind::Cycle), 5);
    }

    #[test]
    fn walking_uses_its_own_scale() {
        let walk = pace_bucket_for_speed(1.4, ActivityKind::Walk);
        let run = pace_bucket_for_speed(1.4, ActivityKind::Run);
        assert!(walk > run);
    }

    #[test]
    fn age_band_partitions_into_thirds() {
        assert_eq!(age_band_for(0, 6), 0);
        assert_eq!(age_band_for(2, 6), 1);
        assert_eq!(age_band_for(4, 6), 2);
    }

    #[test]
    fn age_band_on_a_single_segment_is_newest() {
        assert_eq!(age_band_for(0, 1), 2);
    }

    #[test]
    fn age_band_three_segments_splits_across_all_bands() {
        assert_eq!(age_band_for(0, 3), 0);
        assert_eq!(age_band_for(1, 3), 1);
        assert_eq!(age_band_for(2, 3), 2);
    }

    #[test]
    fn age_band_long_track_first_third_oldest_last_third_newest() {
        assert_eq!(age_band_for(0, 100), 0);
        assert_eq!(age_band_for(33, 100), 1);
        assert_eq!(age_band_for(99, 100), 2);
    }

    #[test]
    fn build_returns_empty_for_tracks_under_two_points() {
        assert!(build_pace_segments(&[], ActivityKind::Run, None).is_empty());
        let one = [tp(0.0, 0.0, None)];
        assert!(build_pace_segments(&one, ActivityKind::Run, None).is_empty());
    }

    #[test]
    fn has_track_timestamps_detects_a_meaningful_heatmap() {
        assert!(!has_track_timestamps(&[]));
        assert!(!has_track_timestamps(&[tp(0.0, 0.0, None)]));
        assert!(!has_track_timestamps(&[
            tp(0.0, 0.0, None),
            tp(0.0, 0.0001, None),
        ]));
        assert!(has_track_timestamps(&[
            tp(0.0, 0.0, Some(0.0)),
            tp(0.0, 0.0001, Some(1.0)),
        ]));
    }

    #[test]
    fn build_without_timestamps_falls_back_to_slowest_bucket() {
        let track = [tp(0.0, 0.0, None), tp(0.0001, 0.0, None)];
        let segs = build_pace_segments(&track, ActivityKind::Run, None);
        assert_eq!(segs.len(), 1);
        // Slowest bucket → red, full alpha (single segment → newest band).
        let c = segs[0].rgba();
        assert_eq!((c.r, c.g, c.b), (239, 68, 68));
        assert_eq!(c.a, 1.0);
    }

    #[test]
    fn build_coalesces_a_uniform_pace_track_into_one_polyline_per_age_band() {
        // 11 points → 10 segments, all one pace bucket → 3 age bands → 3 runs.
        let track = straight_track(11, 3.3, 1.0);
        let segs = build_pace_segments(&track, ActivityKind::Run, None);
        assert_eq!(segs.len(), 3);
        assert_eq!(rgb_of(&segs[0]), rgb_of(&segs[1]));
        assert_eq!(rgb_of(&segs[1]), rgb_of(&segs[2]));
        assert!(alpha_of(&segs[0]) < alpha_of(&segs[1]));
        assert!(alpha_of(&segs[1]) < alpha_of(&segs[2]));
    }

    #[test]
    fn build_splits_a_pace_change_into_extra_polylines() {
        // 5 segments at ~3.3 m/s then 5 at ~5 m/s.
        let mut track: std::vec::Vec<TrackPoint> = std::vec::Vec::new();
        track.push(tp(37.0, -122.0, Some(0.0)));
        let mut cum_m = 0.0;
        for i in 1..=5 {
            cum_m += 3.3;
            track.push(tp(37.0 + cum_m * DEG_PER_M, -122.0, Some(i as f64)));
        }
        for i in 1..=5 {
            cum_m += 5.0;
            track.push(tp(37.0 + cum_m * DEG_PER_M, -122.0, Some((5 + i) as f64)));
        }
        let segs = build_pace_segments(&track, ActivityKind::Run, None);
        assert!(segs.len() > 3);
        assert!(segs.len() < 10);
    }

    #[test]
    fn build_shares_a_vertex_between_adjacent_runs() {
        // 3 slow segments (1 m/s) then 3 fast (5 m/s).
        let mut track: std::vec::Vec<TrackPoint> = std::vec::Vec::new();
        let mut cum_lat = 37.0;
        let mut cum_t = 0.0;
        for _ in 0..3 {
            track.push(tp(cum_lat, -122.0, Some(cum_t)));
            cum_lat += 1.0 * DEG_PER_M;
            cum_t += 1.0;
        }
        for _ in 0..4 {
            track.push(tp(cum_lat, -122.0, Some(cum_t)));
            cum_lat += 5.0 * DEG_PER_M;
            cum_t += 1.0;
        }
        let segs = build_pace_segments(&track, ActivityKind::Run, None);
        assert!(segs.len() >= 2);
        // The joining vertex appears in both polylines (no rendered gap).
        assert_eq!(segs[0].last_point, segs[1].first_point);
        assert_eq!(
            segs[0].points(&track).last(),
            segs[1].points(&track).first(),
        );
    }

    #[test]
    fn build_emits_descending_alpha_for_older_bands() {
        let track = straight_track(9, 4.0, 1.0);
        let segs = build_pace_segments(&track, ActivityKind::Run, None);
        let first = alpha_of(&segs[0]);
        let last = alpha_of(&segs[segs.len() - 1]);
        assert!(first < last, "first {first} last {last}");
    }

    #[test]
    fn compute_pace_buckets_is_one_per_segment_empty_under_two_points() {
        assert!(compute_pace_buckets(&[], ActivityKind::Run).is_empty());
        assert!(compute_pace_buckets(&[tp(0.0, 0.0, Some(0.0))], ActivityKind::Run).is_empty());
        let track = straight_track(7, 3.3, 1.0);
        assert_eq!(compute_pace_buckets(&track, ActivityKind::Run).len(), 6);
    }

    #[test]
    fn build_with_precomputed_buckets_yields_the_identical_segment_set() {
        let mut track: std::vec::Vec<TrackPoint> = std::vec::Vec::new();
        let mut cum_m = 0.0;
        for i in 1..=5 {
            cum_m += 3.3;
            track.push(tp(37.0 + cum_m * DEG_PER_M, -122.0, Some(i as f64)));
        }
        for i in 1..=5 {
            cum_m += 5.0;
            track.push(tp(37.0 + cum_m * DEG_PER_M, -122.0, Some((5 + i) as f64)));
        }
        let internal = build_pace_segments(&track, ActivityKind::Run, None);
        let buckets = compute_pace_buckets(&track, ActivityKind::Run);
        let external = build_pace_segments(&track, ActivityKind::Run, Some(&buckets));
        assert_eq!(external.len(), internal.len());
        for (e, i) in external.iter().zip(internal.iter()) {
            assert_eq!(e, i);
        }
    }

    #[test]
    fn appending_a_point_only_adds_tail_buckets() {
        let base = straight_track(9, 3.3, 1.0);
        let mut grown = base.clone();
        grown.push(tp(37.0 + 9.0 * 3.3 * DEG_PER_M, -122.0, Some(9.0)));
        grown.push(tp(37.0 + 10.0 * 3.3 * DEG_PER_M, -122.0, Some(10.0)));
        let base_buckets = compute_pace_buckets(&base, ActivityKind::Run);
        let grown_buckets = compute_pace_buckets(&grown, ActivityKind::Run);
        for (i, b) in base_buckets.iter().enumerate() {
            assert_eq!(grown_buckets[i], *b);
        }
        assert_eq!(grown_buckets.len(), base_buckets.len() + 2);
    }
}
