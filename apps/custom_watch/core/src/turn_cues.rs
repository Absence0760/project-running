//! Turn-by-turn navigation cues from a planned route polyline — the offline
//! turn-by-turn baseline behind the watch Nav page.
//!
//! Turns are derived purely from the saved line's geometry (the bearing change
//! at each interior vertex) with no routing service, no network, no key: it
//! announces *geometric* bends ("turn left"), not road-name-aware instructions.
//! That is the deliberate trade for an always-works offline cue list.
//!
//! Parity port of web `routes/turn_cues.ts` `generateTurnCues` (twin of
//! `apps/mobile_android/lib/turn_cues.dart`) — keep the algorithm, edge cases,
//! and the ten twin tests in lockstep. The turn direction is carried as the
//! [`TurnDirection`] enum, not an English display string.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::grade_adjusted_pace::haversine_metres;

const DEFAULT_MIN_TURN_ANGLE_DEG: f64 = 30.0;
const DEFAULT_MERGE_WITHIN_M: f64 = 15.0;
const SLIGHT_MAX_DEG: f64 = 45.0;
const UTURN_MIN_DEG: f64 = 150.0;

/// Interior-vertex bound for the collapse pass; a route with more waypoints is
/// truncated at this many surviving vertices.
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
    /// Suppress vertices whose absolute bearing change is below this — GPS /
    /// drawing noise on a roughly-straight line. `None` = default 30°.
    pub min_turn_angle_deg: Option<f64>,
    /// Merge a vertex into the previous cue when it falls within this many
    /// metres of it (coincident / densely-sampled vertices). `None` = 15 m.
    pub merge_within_m: Option<f64>,
}

#[derive(Clone, Copy)]
struct Collapsed {
    wp: TurnCueWaypoint,
    cum_m: f64,
}

/// Generate an ordered list of turn cues from `waypoints`. A cue is emitted at
/// each interior vertex whose bearing change exceeds `min_turn_angle_deg`,
/// classified by signed turn angle into left/right/slight/uturn. Coincident
/// vertices and vertices within `merge_within_m` of the previous cue are merged
/// so a densely-sampled corner produces one cue, not a burst. Returns an empty
/// list for a straight line or fewer than 3 waypoints.
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

    // Collapse coincident / sub-merge-distance vertices first, carrying the
    // cumulative distance of each surviving vertex along the ORIGINAL line, so a
    // densely-sampled corner fires one cue instead of a burst of zero-length-leg
    // skips.
    let mut collapsed: Vec<Collapsed, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
    let mut cum = 0.0_f64;
    let _ = collapsed.push(Collapsed {
        wp: waypoints[0],
        cum_m: 0.0,
    });
    for i in 1..waypoints.len() {
        cum += haversine_metres(
            waypoints[i - 1].lat,
            waypoints[i - 1].lng,
            waypoints[i].lat,
            waypoints[i].lng,
        );
        if let Some(prev) = collapsed.last_mut() {
            if cum - prev.cum_m <= merge_within {
                prev.wp = waypoints[i];
                continue;
            }
        }
        if collapsed
            .push(Collapsed {
                wp: waypoints[i],
                cum_m: cum,
            })
            .is_err()
        {
            break;
        }
    }
    if collapsed.len() < 3 {
        return cues;
    }

    for i in 1..collapsed.len() - 1 {
        let bearing_in = bearing_deg(&collapsed[i - 1].wp, &collapsed[i].wp);
        let bearing_out = bearing_deg(&collapsed[i].wp, &collapsed[i + 1].wp);
        let delta = signed_turn(bearing_in, bearing_out);
        if delta.abs() < min_angle {
            continue;
        }
        let position_m = collapsed[i].cum_m;
        if cues
            .push(TurnCue {
                position_m,
                bearing_in_deg: bearing_in,
                bearing_out_deg: bearing_out,
                direction: classify(delta),
                distance_from_start_m: position_m,
            })
            .is_err()
        {
            break;
        }
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

    /// Mirror of `apps/web/src/lib/routes/turn_cues.test.ts` — same ten inputs,
    /// same expected directions, so the ports can't drift. Coordinates are built
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
