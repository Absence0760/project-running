//! Turn-by-turn navigation cues from a planned route polyline — the offline
//! turn-by-turn baseline behind the watch Nav page.
//!
//! Turns are derived purely from the saved line's geometry (the bearing change
//! at each interior vertex) with no routing service, no network, no key: it
//! announces *geometric* bends ("turn left"), not road-name-aware instructions.
//! That is the deliberate trade for an always-works offline cue list.
//!
//! A turn is the NET direction change accumulated within `merge_within_m`
//! metres of where the turning starts, reported at the vertex where that
//! turning passes its halfway point. The two knobs then read as one sentence:
//! at least `min_turn_angle_deg` of direction change within `merge_within_m`
//! metres is a turn; anything slacker is a curve and is not announced. Every
//! bearing is measured on a segment that TOUCHES the vertex it is measured at,
//! never one that spans it: a segment drawn across a corner carries half that
//! corner's angle and none of its position.
//!
//! Parity port of web `routes/turn_cues.ts` `generateTurnCues` (twin of
//! `apps/mobile_android/lib/turn_cues.dart`) — keep the algorithm, edge cases,
//! and the fourteen twin tests in lockstep. The turn direction is carried as
//! the [`TurnDirection`] enum, not an English display string.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

const DEFAULT_MIN_TURN_ANGLE_DEG: f64 = 30.0;
const DEFAULT_MERGE_WITHIN_M: f64 = 15.0;
const SLIGHT_MAX_DEG: f64 = 45.0;
const UTURN_MIN_DEG: f64 = 150.0;
/// A leg shorter than this carries no usable bearing, so its far vertex is
/// dropped. Far below any route's vertex resolution, so dropping it cannot move
/// a corner.
const MIN_LEG_M: f64 = 0.05;
/// A vertex bending less than this does not open a turn window. A corner built
/// from bends this small would need more vertices inside one window than any
/// drawn or imported route carries.
const TURN_EPSILON_DEG: f64 = 0.5;

/// Interior-vertex bound; a route with more waypoints is truncated at this many
/// surviving vertices.
pub const MAX_TURN_CUE_WAYPOINTS: usize = 256;
/// Emitted-cue bound (at most `waypoints - 2` interior vertices fire).
pub const MAX_TURN_CUES: usize = 256;

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TurnCueWaypoint {
    pub lat: f64,
    pub lng: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum TurnDirection {
    Left,
    Right,
    SlightLeft,
    SlightRight,
    Straight,
    Uturn,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct TurnCue {
    /// Distance along the route, in metres from the start, at the turn vertex.
    pub position_m: f64,
    /// Bearing (degrees, 0–360, 0 = north) approaching the vertex.
    pub bearing_in_deg: f64,
    /// Bearing leaving the vertex.
    pub bearing_out_deg: f64,
    pub direction: TurnDirection,
    /// Alias of `position_m` kept explicit for the cue-firing consumer.
    pub distance_from_start_m: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct TurnCueOptions {
    /// Suppress turns whose accumulated direction change is below this — GPS /
    /// drawing noise on a roughly-straight line. `None` = default 30°.
    pub min_turn_angle_deg: Option<f64>,
    /// The window one turn is accumulated over: vertices within this many
    /// metres of where the turning starts belong to the same turn, so a
    /// densely-sampled or rounded corner fires once at its full angle.
    /// `None` = 15 m.
    pub merge_within_m: Option<f64>,
}

#[derive(Clone, Copy)]
struct Vertex {
    wp: TurnCueWaypoint,
    cum_m: f64,
}

#[derive(Clone, Copy)]
struct Bend {
    position_m: f64,
    bearing_in_deg: f64,
    bearing_out_deg: f64,
    delta_deg: f64,
}

/// Generate an ordered list of turn cues from `waypoints`. Returns an empty
/// list for a straight line or fewer than 3 waypoints (no interior vertex to
/// turn at).
pub fn generate_turn_cues(
    waypoints: &[TurnCueWaypoint],
    options: TurnCueOptions,
) -> Vec<TurnCue, MAX_TURN_CUES> {
    let min_angle = options
        .min_turn_angle_deg
        .unwrap_or(DEFAULT_MIN_TURN_ANGLE_DEG);
    let merge_within = options.merge_within_m.unwrap_or(DEFAULT_MERGE_WITHIN_M);
    let mut cues: Vec<TurnCue, MAX_TURN_CUES> = Vec::new();
    if waypoints.len() < 3 {
        return cues;
    }

    let mut pts: Vec<Vertex, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
    let _ = pts.push(Vertex {
        wp: waypoints[0],
        cum_m: 0.0,
    });
    let mut cum = 0.0_f64;
    for i in 1..waypoints.len() {
        cum += haversine_metres(
            waypoints[i - 1].lat,
            waypoints[i - 1].lng,
            waypoints[i].lat,
            waypoints[i].lng,
        );
        if let Some(prev) = pts.last() {
            if cum - prev.cum_m < MIN_LEG_M {
                continue;
            }
        }
        if pts
            .push(Vertex {
                wp: waypoints[i],
                cum_m: cum,
            })
            .is_err()
        {
            break;
        }
    }
    if pts.len() < 3 {
        return cues;
    }

    let mut bends: Vec<Bend, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
    for i in 1..pts.len() - 1 {
        let bearing_in_deg = bearing_deg(&pts[i - 1].wp, &pts[i].wp);
        let bearing_out_deg = bearing_deg(&pts[i].wp, &pts[i + 1].wp);
        if bends
            .push(Bend {
                position_m: pts[i].cum_m,
                bearing_in_deg,
                bearing_out_deg,
                delta_deg: signed_turn(bearing_in_deg, bearing_out_deg),
            })
            .is_err()
        {
            break;
        }
    }

    let mut i = 0;
    while i < bends.len() {
        if libm::fabs(bends[i].delta_deg) < TURN_EPSILON_DEG {
            i += 1;
            continue;
        }
        let mut net = 0.0_f64;
        let mut swept = 0.0_f64;
        let mut end = i;
        while end < bends.len() && bends[end].position_m - bends[i].position_m <= merge_within {
            net += bends[end].delta_deg;
            swept += libm::fabs(bends[end].delta_deg);
            end += 1;
        }
        if libm::fabs(net) < min_angle {
            // Not a turn over this window. Slide by one rather than consuming
            // the window, so a corner that starts just inside it still opens
            // its own.
            i += 1;
            continue;
        }
        let mut run = 0.0_f64;
        let mut position_m = bends[i].position_m;
        for k in i..end {
            run += libm::fabs(bends[k].delta_deg);
            if run * 2.0 >= swept {
                position_m = bends[k].position_m;
                break;
            }
        }
        if cues
            .push(TurnCue {
                position_m,
                bearing_in_deg: bends[i].bearing_in_deg,
                bearing_out_deg: bends[end - 1].bearing_out_deg,
                direction: classify(net),
                distance_from_start_m: position_m,
            })
            .is_err()
        {
            break;
        }
        i = end;
    }
    cues
}

/// Signed turn angle in degrees, `(-180, 180]`. Positive = right turn
/// (clockwise), negative = left turn — matching compass convention.
fn signed_turn(bearing_in: f64, bearing_out: f64) -> f64 {
    let mut d = bearing_out - bearing_in;
    while d > 180.0 {
        d -= 360.0;
    }
    while d <= -180.0 {
        d += 360.0;
    }
    d
}

fn classify(delta: f64) -> TurnDirection {
    let a = delta.abs();
    if a >= UTURN_MIN_DEG {
        TurnDirection::Uturn
    } else if delta > 0.0 {
        if a <= SLIGHT_MAX_DEG {
            TurnDirection::SlightRight
        } else {
            TurnDirection::Right
        }
    } else if a <= SLIGHT_MAX_DEG {
        TurnDirection::SlightLeft
    } else {
        TurnDirection::Left
    }
}

fn bearing_deg(a: &TurnCueWaypoint, b: &TurnCueWaypoint) -> f64 {
    let deg = core::f64::consts::PI / 180.0;
    let lat1 = a.lat * deg;
    let lat2 = b.lat * deg;
    let d_lng = (b.lng - a.lng) * deg;
    let y = libm::sin(d_lng) * libm::cos(lat2);
    let x =
        libm::cos(lat1) * libm::sin(lat2) - libm::sin(lat1) * libm::cos(lat2) * libm::cos(d_lng);
    let brng = libm::atan2(y, x) / deg;
    (brng + 360.0) % 360.0
}

/// The first turn strictly ahead of `along_m` (metres from the course start) and
/// how many turns remain from it onward (including it), capped at `u8::MAX`.
/// `None` once the runner is past the last turn. Watch-local runtime read over
/// the ported [`generate_turn_cues`] output — NOT part of the web/Dart parity.
pub fn next_turn_ahead(cues: &[TurnCue], along_m: f64) -> Option<(TurnCue, u8)> {
    let idx = cues.iter().position(|c| c.position_m > along_m)?;
    let remaining = (cues.len() - idx).min(u8::MAX as usize) as u8;
    Some((cues[idx], remaining))
}

/// The compact direction code the run-view TurnCue page renders (0 straight /
/// 1 slight-left / 2 left / 4 slight-right / 5 right / 7 u-turn; the 3 sharp-left
/// and 6 sharp-right codes are unused — the model has no sharp class). Watch-local.
pub fn direction_code(d: TurnDirection) -> u8 {
    match d {
        TurnDirection::Straight => 0,
        TurnDirection::SlightLeft => 1,
        TurnDirection::Left => 2,
        TurnDirection::SlightRight => 4,
        TurnDirection::Right => 5,
        TurnDirection::Uturn => 7,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/routes/turn_cues.test.ts` — same fourteen
    /// inputs, same expected directions, so the ports can't drift. Coordinates are built
    /// at a low latitude (~0) where 0.01° lng ≈ 0.01° lat in metres, so an
    /// axis-aligned right-angle reads as a clean 90° turn.
    fn wp(lat: f64, lng: f64) -> TurnCueWaypoint {
        TurnCueWaypoint { lat, lng }
    }

    fn gen(waypoints: &[TurnCueWaypoint]) -> Vec<TurnCue, MAX_TURN_CUES> {
        generate_turn_cues(waypoints, TurnCueOptions::default())
    }

    // A square corner: east then north → a 90° LEFT turn at the vertex.
    fn left_corner() -> [TurnCueWaypoint; 3] {
        [wp(0.0, 0.0), wp(0.0, 0.02), wp(0.02, 0.02)]
    }

    // East then south → a 90° RIGHT turn.
    fn right_corner() -> [TurnCueWaypoint; 3] {
        [wp(0.0, 0.0), wp(0.0, 0.02), wp(-0.02, 0.02)]
    }

    #[test]
    fn a_straight_line_produces_no_cues() {
        let w = [wp(0.0, 0.0), wp(0.0, 0.01), wp(0.0, 0.02), wp(0.0, 0.03)];
        assert!(gen(&w).is_empty());
    }

    #[test]
    fn empty_input_produces_no_cues() {
        assert!(gen(&[]).is_empty());
    }

    #[test]
    fn a_single_point_input_produces_no_cues() {
        assert!(gen(&[wp(0.0, 0.0)]).is_empty());
    }

    #[test]
    fn a_two_point_line_has_no_interior_vertex_so_no_cues() {
        assert!(gen(&[wp(0.0, 0.0), wp(0.0, 0.02)]).is_empty());
    }

    #[test]
    fn a_90_degree_left_turn_yields_one_left_cue_at_the_vertex() {
        let cues = gen(&left_corner());
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Left);
        assert!(cues[0].position_m > 0.0);
        assert_eq!(cues[0].position_m, cues[0].distance_from_start_m);
    }

    #[test]
    fn a_90_degree_right_turn_yields_one_right_cue() {
        let cues = gen(&right_corner());
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Right);
    }

    #[test]
    fn a_sub_threshold_wiggle_is_suppressed() {
        // ~10° kink, below the default 30° threshold.
        let w = [wp(0.0, 0.0), wp(0.0, 0.02), wp(0.0035, 0.04)];
        assert!(gen(&w).is_empty());
    }

    #[test]
    fn a_slight_bend_just_over_threshold_classifies_as_slight() {
        // ~40° left bend → slight_left (<= 45°).
        let w = [wp(0.0, 0.0), wp(0.0, 0.02), wp(0.017, 0.04)];
        let cues = gen(&w);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::SlightLeft);
    }

    #[test]
    fn a_near_reversal_is_detected_as_a_uturn() {
        // Out east, back west → ~180° → uturn.
        let w = [wp(0.0, 0.0), wp(0.0, 0.02), wp(0.0005, 0.0)];
        let cues = gen(&w);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Uturn);
    }

    #[test]
    fn coincident_vertices_at_one_corner_merge_into_a_single_cue() {
        // A duplicated vertex right at the corner must not double-fire.
        let w = [wp(0.0, 0.0), wp(0.0, 0.02), wp(0.0, 0.02), wp(0.02, 0.02)];
        let cues = gen(&w);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Left);
    }

    const M_PER_DEG: f64 = 111_320.0;

    /// A course that runs `corner_at_m` metres due north, turns `turn_deg` to
    /// the left over `corner_length_m` metres, then runs `tail_m` metres on the
    /// new heading — every leg sampled at `spacing_m`. The densely-sampled
    /// corner is what a pushed course actually looks like.
    fn cornering_course(
        spacing_m: f64,
        corner_at_m: f64,
        tail_m: f64,
        turn_deg: f64,
        corner_length_m: f64,
    ) -> Vec<TurnCueWaypoint, MAX_TURN_CUE_WAYPOINTS> {
        let mut pts: Vec<TurnCueWaypoint, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
        let mut north = -corner_at_m;
        let mut east = 0.0_f64;
        let mut heading_deg = 0.0_f64;
        let _ = pts.push(wp(north / M_PER_DEG, east / M_PER_DEG));
        let steps = libm::round(corner_length_m / spacing_m) as usize;
        let mut legs: Vec<f64, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
        let mut d = spacing_m;
        while d <= corner_at_m {
            let _ = legs.push(0.0);
            d += spacing_m;
        }
        for _ in 0..steps {
            let _ = legs.push(turn_deg / steps as f64);
        }
        if steps == 0 {
            let _ = legs.push(turn_deg);
        }
        d = spacing_m;
        while d <= tail_m {
            let _ = legs.push(0.0);
            d += spacing_m;
        }
        for bend in legs.iter() {
            heading_deg -= bend;
            let rad = heading_deg * core::f64::consts::PI / 180.0;
            north += spacing_m * libm::cos(rad);
            east += spacing_m * libm::sin(rad);
            let _ = pts.push(wp(north / M_PER_DEG, east / M_PER_DEG));
        }
        pts
    }

    /// The round-1/round-2 bug: a single 90° corner at 100 m sampled every 10 m
    /// used to collapse onto a segment drawn ACROSS the corner, so the one turn
    /// was announced twice (SlightLeft at 80 m AND SlightLeft at 100 m) — both
    /// under-classified, the first 20 m early, and "turns remaining" reading 2.
    #[test]
    fn a_densely_sampled_90_degree_corner_fires_exactly_one_left_cue_at_the_corner() {
        let cues = gen(&cornering_course(10.0, 100.0, 100.0, 90.0, 0.0));
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Left);
        assert!(libm::fabs(cues[0].position_m - 100.0) < 1.0);
        assert_eq!(cues[0].position_m, cues[0].distance_from_start_m);
        // "Turns remaining" on a one-corner course is 1, not 2.
        let (turn, remaining) = next_turn_ahead(&cues, 0.0).unwrap();
        assert_eq!(turn.direction, TurnDirection::Left);
        assert_eq!(remaining, 1);
    }

    #[test]
    fn a_densely_sampled_40_degree_bend_still_fires_its_slight_cue() {
        // Split across the collapsed segment this was two sub-threshold 20°
        // halves and vanished entirely.
        let cues = gen(&cornering_course(10.0, 100.0, 100.0, 40.0, 0.0));
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::SlightLeft);
        assert!(libm::fabs(cues[0].position_m - 100.0) < 1.0);
    }

    #[test]
    fn a_corner_rounded_over_several_vertices_fires_one_cue_at_its_full_angle() {
        // 90° spread over three 30° vertices 5 m apart: one corner, not three
        // sub-threshold fragments and not a 30° slight.
        let cues = gen(&cornering_course(5.0, 100.0, 100.0, 90.0, 15.0));
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].direction, TurnDirection::Left);
        assert!(cues[0].position_m > 100.0 && cues[0].position_m < 115.0);
    }

    #[test]
    fn a_90_degree_corner_reports_once_at_any_sampling() {
        // The old collapse's answer depended on where the corner fell relative
        // to the 15 m merge window, so a different spacing produced a different
        // (and differently wrong) cue list for the same course. 120 m is a whole
        // number of every spacing, so the corner sits at the same distance in
        // all five courses.
        for spacing_m in [4.0_f64, 6.0, 8.0, 10.0, 12.0] {
            let cues = gen(&cornering_course(spacing_m, 120.0, 120.0, 90.0, 0.0));
            assert_eq!(cues.len(), 1, "spacing {spacing_m}");
            assert_eq!(
                cues[0].direction,
                TurnDirection::Left,
                "spacing {spacing_m}"
            );
            assert!(
                libm::fabs(cues[0].position_m - 120.0) < 1.0,
                "spacing {spacing_m}: {}",
                cues[0].position_m
            );
        }
    }

    fn cue_at(position_m: f64, direction: TurnDirection) -> TurnCue {
        TurnCue {
            position_m,
            bearing_in_deg: 0.0,
            bearing_out_deg: 0.0,
            direction,
            distance_from_start_m: position_m,
        }
    }

    #[test]
    fn next_turn_ahead_picks_the_first_turn_past_the_runner() {
        let cues = [
            cue_at(100.0, TurnDirection::Left),
            cue_at(500.0, TurnDirection::Right),
            cue_at(900.0, TurnDirection::Uturn),
        ];
        // Before any turn: the first, all three remaining.
        let (c, rem) = next_turn_ahead(&cues, 0.0).unwrap();
        assert_eq!(c.direction, TurnDirection::Left);
        assert_eq!(rem, 3);
        // Between turns 1 and 2: the second, two remaining.
        let (c, rem) = next_turn_ahead(&cues, 200.0).unwrap();
        assert_eq!(c.direction, TurnDirection::Right);
        assert_eq!(rem, 2);
        // Exactly at a turn counts as passed (strictly ahead) → the next one.
        let (c, _) = next_turn_ahead(&cues, 500.0).unwrap();
        assert_eq!(c.direction, TurnDirection::Uturn);
        // Past the last turn, and an empty course, both yield nothing.
        assert!(next_turn_ahead(&cues, 1000.0).is_none());
        assert!(next_turn_ahead(&[], 0.0).is_none());
    }

    #[test]
    fn direction_code_maps_every_variant() {
        assert_eq!(direction_code(TurnDirection::Straight), 0);
        assert_eq!(direction_code(TurnDirection::SlightLeft), 1);
        assert_eq!(direction_code(TurnDirection::Left), 2);
        assert_eq!(direction_code(TurnDirection::SlightRight), 4);
        assert_eq!(direction_code(TurnDirection::Right), 5);
        assert_eq!(direction_code(TurnDirection::Uturn), 7);
    }
}
