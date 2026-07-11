//! Race roadbook — the crew sheet a route's course markers + a goal time imply.
//!
//! Given a route's waypoints, its course markers (aid stations / cutoffs / crew
//! access), and a goal finish time, [`build_roadbook`] produces the
//! per-checkpoint schedule ultra crews currently build by hand: cumulative
//! distance, projected arrival (elapsed + wall clock), cutoff margin, and
//! per-leg vert.
//!
//! The differentiator over even splits: goal time is allocated by
//! **grade-adjusted effort** ([`grade_factor`], Minetti) — the climbs get
//! proportionally more time than the flats — not by even distance. With no
//! elevation data the effort model degrades cleanly to even pace.
//!
//! Parity port of web `routes/roadbook.ts` `buildRoadbook` (twin of
//! `apps/mobile_android/lib/roadbook.dart`) — keep the allocation, cutoff
//! rules, edge cases, and test count in lockstep. The 30-minute "tight" span is
//! the crate-shared [`CUTOFF_TIGHT_S`] reused from `cutoff_eta`; the grade
//! factor and trusted-segment length come from `grade_adjusted_pace`. The web
//! canonical (and the Dart twin) each define the roadbook `CutoffStatus`
//! verdict locally, so this port does the same rather than borrow the
//! semantically-distinct `cutoff_eta::CutoffEtaStatus` (on/tight/behind).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

use crate::cutoff_eta::CUTOFF_TIGHT_S;
use crate::grade_adjusted_pace::{grade_factor, MIN_SEGMENT_M};

/// Route polyline capacity — one flash-slot's worth, matching `course`'s
/// [`crate::course::MAX_COURSE_POINTS`]. A longer course is trusted only up to
/// this many points (the excess is dropped, as `record` trims cutoff legs).
pub const MAX_ROADBOOK_WAYPOINTS: usize = 256;

/// Maximum placed course markers folded into the schedule; the excess is
/// dropped rather than growing.
pub const MAX_ROADBOOK_MARKERS: usize = 32;

/// Legs = synthetic start + markers + synthetic finish.
pub const MAX_ROADBOOK_LEGS: usize = MAX_ROADBOOK_MARKERS + 2;

const MINUTES_PER_DAY: f64 = 1440.0;

/// One route polyline vertex. `ele` metres, `None` where the route has no
/// elevation data at that point.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookWaypoint {
    pub lat: f64,
    pub lng: f64,
    pub ele: Option<f64>,
}

/// A course marker. The jsonb `meta` bag the web reads is flattened to the
/// fields the roadbook actually consumes: aid `services`, and the cutoff's
/// clock / elapsed limit (only read when `kind == "cutoff"`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookMarker<'a> {
    /// Distance along the route from the start, metres. `None` = no geom yet.
    pub position_m: Option<f64>,
    pub kind: &'a str,
    pub label: &'a str,
    pub services: &'a [&'a str],
    /// Wall-clock cutoff "HH:MM" (24h), when set.
    pub cutoff_clock: Option<&'a str>,
    /// Elapsed-seconds cutoff from the start, when set.
    pub cutoff_elapsed_s: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PacingModel {
    Effort,
    Even,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum CutoffStatus {
    Safe,
    Tight,
    Miss,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookOptions {
    pub goal_seconds: f64,
    /// Race start, minutes past local midnight. `None` for elapsed-only.
    pub start_clock_min: Option<f64>,
    pub model: PacingModel,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookCutoff {
    pub limit_elapsed_s: u32,
    pub margin_s: f64,
    pub status: CutoffStatus,
}

/// One schedule row. `kind` is `None` on the synthetic start/finish, `Some` on
/// a marker; `label` is "start" / "finish" or the marker's label.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RoadbookLeg<'a> {
    pub kind: Option<&'a str>,
    pub label: &'a str,
    pub cum_dist_m: f64,
    pub leg_dist_m: f64,
    pub leg_gain_m: f64,
    pub leg_loss_m: f64,
    pub projected_elapsed_s: f64,
    /// Wall-clock arrival, minutes past midnight (mod 1440). `None` if no start.
    pub projected_clock_min: Option<f64>,
    pub cutoff: Option<RoadbookCutoff>,
    pub services: &'a [&'a str],
}

impl RoadbookLeg<'_> {
    pub fn is_start(&self) -> bool {
        self.kind.is_none() && self.label == "start"
    }
    pub fn is_finish(&self) -> bool {
        self.kind.is_none() && self.label == "finish"
    }
}

pub struct Roadbook<'a> {
    pub legs: Vec<RoadbookLeg<'a>, MAX_ROADBOOK_LEGS>,
    pub total_dist_m: f64,
    pub total_gain_m: f64,
    pub total_seconds: f64,
    pub has_elevation: bool,
}

fn haversine_m(a: &RoadbookWaypoint, b: &RoadbookWaypoint) -> f64 {
    const R: f64 = 6_371_000.0;
    let deg = core::f64::consts::PI / 180.0;
    let d_lat = (b.lat - a.lat) * deg;
    let d_lng = (b.lng - a.lng) * deg;
    let s_lat = libm::sin(d_lat / 2.0);
    let s_lng = libm::sin(d_lng / 2.0);
    let h = s_lat * s_lat + libm::cos(a.lat * deg) * libm::cos(b.lat * deg) * s_lng * s_lng;
    R * 2.0 * libm::asin(libm::sqrt(h).min(1.0))
}

struct Cumulative {
    dist: Vec<f64, MAX_ROADBOOK_WAYPOINTS>,
    gap: Vec<f64, MAX_ROADBOOK_WAYPOINTS>,
    gain: Vec<f64, MAX_ROADBOOK_WAYPOINTS>,
    loss: Vec<f64, MAX_ROADBOOK_WAYPOINTS>,
    has_elevation: bool,
}

/// Per-waypoint cumulative distance / grade-adjusted distance / gain / loss.
fn walk(waypoints: &[RoadbookWaypoint]) -> Cumulative {
    let mut dist: Vec<f64, MAX_ROADBOOK_WAYPOINTS> = Vec::new();
    let mut gap: Vec<f64, MAX_ROADBOOK_WAYPOINTS> = Vec::new();
    let mut gain: Vec<f64, MAX_ROADBOOK_WAYPOINTS> = Vec::new();
    let mut loss: Vec<f64, MAX_ROADBOOK_WAYPOINTS> = Vec::new();
    let _ = dist.push(0.0);
    let _ = gap.push(0.0);
    let _ = gain.push(0.0);
    let _ = loss.push(0.0);

    // hasElevation = at least two distinct elevation values, matching the web
    // `Set(eles).size >= 2`. min < max is that test without a float `==`.
    let mut min_ele = f64::INFINITY;
    let mut max_ele = f64::NEG_INFINITY;
    for w in waypoints.iter().take(MAX_ROADBOOK_WAYPOINTS) {
        if let Some(e) = w.ele {
            if e < min_ele {
                min_ele = e;
            }
            if e > max_ele {
                max_ele = e;
            }
        }
    }

    let n = waypoints.len().min(MAX_ROADBOOK_WAYPOINTS);
    for i in 1..n {
        let a = &waypoints[i - 1];
        let b = &waypoints[i];
        let horiz = haversine_m(a, b);
        let d_ele = match (a.ele, b.ele) {
            (Some(ae), Some(be)) => be - ae,
            _ => 0.0,
        };
        // Below the trusted-segment length, GPS/SRTM altitude noise dominates —
        // treat as flat (factor 1) rather than amplify a phantom grade.
        let grade = if horiz >= MIN_SEGMENT_M {
            d_ele / horiz
        } else {
            0.0
        };
        let _ = dist.push(dist[i - 1] + horiz);
        let _ = gap.push(gap[i - 1] + horiz * grade_factor(grade));
        let _ = gain.push(gain[i - 1] + d_ele.max(0.0));
        let _ = loss.push(loss[i - 1] + (-d_ele).max(0.0));
    }

    Cumulative {
        dist,
        gap,
        gain,
        loss,
        has_elevation: max_ele > min_ele,
    }
}

/// Linear-interpolate a cumulative array at a target distance along the route.
fn value_at(cum: &[f64], dist: &[f64], target: f64) -> f64 {
    let total = dist[dist.len() - 1];
    if target <= 0.0 {
        return cum[0];
    }
    if target >= total {
        return cum[cum.len() - 1];
    }
    for i in 1..dist.len() {
        if target <= dist[i] {
            let span = dist[i] - dist[i - 1];
            let t = if span <= 0.0 {
                0.0
            } else {
                (target - dist[i - 1]) / span
            };
            return cum[i - 1] + (cum[i] - cum[i - 1]) * t;
        }
    }
    cum[cum.len() - 1]
}

fn metric_at(use_effort: bool, cum: &Cumulative, pos: f64) -> f64 {
    if use_effort {
        value_at(&cum.gap, &cum.dist, pos)
    } else {
        pos
    }
}

#[derive(Clone, Copy)]
struct Stop<'a> {
    pos: f64,
    kind: Option<&'a str>,
    label: &'a str,
    services: &'a [&'a str],
    cutoff_clock: Option<&'a str>,
    cutoff_elapsed_s: Option<f64>,
    is_cutoff: bool,
}

/// Build the roadbook. Checkpoints are: synthetic start (0), each marker with a
/// non-null `position_m` (ordered by distance), and synthetic finish (total).
pub fn build_roadbook<'a>(
    waypoints: &[RoadbookWaypoint],
    markers: &[RoadbookMarker<'a>],
    opts: RoadbookOptions,
) -> Roadbook<'a> {
    let cum = walk(waypoints);
    let total_dist_m = *cum.dist.last().unwrap_or(&0.0);
    let total_gain_m = *cum.gain.last().unwrap_or(&0.0);
    let goal = opts.goal_seconds.max(0.0);

    let mut placed: Vec<Stop<'a>, MAX_ROADBOOK_MARKERS> = Vec::new();
    for m in markers {
        let Some(pos) = m.position_m else { continue };
        let stop = Stop {
            pos: pos.max(0.0).min(total_dist_m),
            kind: Some(m.kind),
            label: m.label,
            services: m.services,
            cutoff_clock: m.cutoff_clock,
            cutoff_elapsed_s: m.cutoff_elapsed_s,
            is_cutoff: m.kind == "cutoff",
        };
        if placed.push(stop).is_err() {
            break;
        }
    }
    placed.sort_unstable_by(|a, b| {
        a.pos
            .partial_cmp(&b.pos)
            .unwrap_or(core::cmp::Ordering::Equal)
    });

    let mut stops: Vec<Stop<'a>, MAX_ROADBOOK_LEGS> = Vec::new();
    let _ = stops.push(Stop {
        pos: 0.0,
        kind: None,
        label: "start",
        services: &[],
        cutoff_clock: None,
        cutoff_elapsed_s: None,
        is_cutoff: false,
    });
    for s in &placed {
        let _ = stops.push(*s);
    }
    let _ = stops.push(Stop {
        pos: total_dist_m,
        kind: None,
        label: "finish",
        services: &[],
        cutoff_clock: None,
        cutoff_elapsed_s: None,
        is_cutoff: false,
    });

    // Allocation metric per leg: grade-adjusted distance (effort) or raw
    // distance (even). Degrade to even when there's no elevation.
    let use_effort = opts.model == PacingModel::Effort && cum.has_elevation;
    let total_metric = metric_at(use_effort, &cum, total_dist_m);

    let mut legs: Vec<RoadbookLeg<'a>, MAX_ROADBOOK_LEGS> = Vec::new();
    let mut prev_pos = 0.0;
    let mut prev_gain = 0.0;
    let mut prev_loss = 0.0;
    let mut prev_metric = 0.0;
    let mut elapsed = 0.0;

    for stop in &stops {
        let cum_gain = value_at(&cum.gain, &cum.dist, stop.pos);
        let cum_loss = value_at(&cum.loss, &cum.dist, stop.pos);
        let metric = metric_at(use_effort, &cum, stop.pos);
        let leg_time = if total_metric > 0.0 {
            goal * (metric - prev_metric) / total_metric
        } else {
            0.0
        };
        elapsed += leg_time;

        let projected_clock_min = opts.start_clock_min.map(|start| {
            (((start + elapsed / 60.0) % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
        });

        let cutoff = if stop.is_cutoff {
            cutoff_limit_s(stop, opts.start_clock_min).map(|limit| {
                let margin = limit as f64 - elapsed;
                RoadbookCutoff {
                    limit_elapsed_s: limit,
                    margin_s: margin,
                    status: if margin < 0.0 {
                        CutoffStatus::Miss
                    } else if margin < CUTOFF_TIGHT_S as f64 {
                        CutoffStatus::Tight
                    } else {
                        CutoffStatus::Safe
                    },
                }
            })
        } else {
            None
        };

        let _ = legs.push(RoadbookLeg {
            kind: stop.kind,
            label: stop.label,
            cum_dist_m: stop.pos,
            leg_dist_m: stop.pos - prev_pos,
            leg_gain_m: cum_gain - prev_gain,
            leg_loss_m: cum_loss - prev_loss,
            projected_elapsed_s: elapsed,
            projected_clock_min,
            cutoff,
            services: stop.services,
        });

        prev_pos = stop.pos;
        prev_gain = cum_gain;
        prev_loss = cum_loss;
        prev_metric = metric;
    }

    Roadbook {
        legs,
        total_dist_m,
        total_gain_m,
        total_seconds: goal,
        has_elevation: cum.has_elevation,
    }
}

struct CutoffParts<'a> {
    clock: Option<&'a str>,
    elapsed_s: Option<u32>,
}

/// Validate + normalise a cutoff's clock / elapsed inputs — the roadbook half
/// of web `route_markers.ts` `parseCutoff` (not ported as its own module here).
/// `None` when neither a valid clock nor a valid elapsed is present.
fn parse_cutoff(clock: Option<&str>, elapsed: Option<f64>) -> Option<CutoffParts<'_>> {
    let out_clock = clock.filter(|c| valid_clock(c));
    let out_elapsed = elapsed
        .filter(|e| e.is_finite() && *e >= 0.0)
        .map(|e| libm::floor(e) as u32);
    if out_clock.is_some() || out_elapsed.is_some() {
        Some(CutoffParts {
            clock: out_clock,
            elapsed_s: out_elapsed,
        })
    } else {
        None
    }
}

/// Resolve a cutoff to a limit in elapsed seconds from the start. Prefers the
/// elapsed field; otherwise derives from the clock minus the start clock,
/// wrapping a clock at or before the start to the next day (a 24h+ race
/// expressing its overall limit as the start wall-clock one day on).
fn cutoff_limit_s(stop: &Stop, start_clock_min: Option<f64>) -> Option<u32> {
    let parts = parse_cutoff(stop.cutoff_clock, stop.cutoff_elapsed_s)?;
    if let Some(e) = parts.elapsed_s {
        return Some(e);
    }
    if let (Some(clock), Some(start)) = (parts.clock, start_clock_min) {
        let mut cutoff_min = clock_minutes(clock) as f64;
        if cutoff_min <= start {
            cutoff_min += MINUTES_PER_DAY;
        }
        return Some(libm::round((cutoff_min - start) * 60.0) as u32);
    }
    None
}

/// True when `s` is a "HH:MM" 24-hour clock — the web `CLOCK_RE` regex.
fn valid_clock(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 5 || b[2] != b':' {
        return false;
    }
    if !(b[0].is_ascii_digit()
        && b[1].is_ascii_digit()
        && b[3].is_ascii_digit()
        && b[4].is_ascii_digit())
    {
        return false;
    }
    let hh = (b[0] - b'0') * 10 + (b[1] - b'0');
    let mm = (b[3] - b'0') * 10 + (b[4] - b'0');
    hh <= 23 && mm <= 59
}

/// Minutes-past-midnight for a clock already validated by [`valid_clock`].
fn clock_minutes(s: &str) -> u32 {
    let b = s.as_bytes();
    let hh = (b[0] - b'0') as u32 * 10 + (b[1] - b'0') as u32;
    let mm = (b[3] - b'0') as u32 * 10 + (b[4] - b'0') as u32;
    hh * 60 + mm
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/routes/roadbook.test.ts` /
    /// `apps/mobile_android/test/roadbook_test.dart` — same scenarios, same
    /// expected values, so the ports can't drift.

    /// ~2 km course heading north from (0,0): flat first half, second half
    /// climbing 30 m per step, so the effort model has something to bite on.
    fn course() -> Vec<RoadbookWaypoint, 32> {
        let mut pts: Vec<RoadbookWaypoint, 32> = Vec::new();
        for i in 0..=18 {
            let ele = if i > 9 { ((i - 9) * 30) as f64 } else { 0.0 };
            let _ = pts.push(RoadbookWaypoint {
                lat: i as f64 * 0.001,
                lng: 0.0,
                ele: Some(ele),
            });
        }
        pts
    }

    fn even(goal: f64) -> RoadbookOptions {
        RoadbookOptions {
            goal_seconds: goal,
            start_clock_min: None,
            model: PacingModel::Even,
        }
    }

    fn total_of(wp: &[RoadbookWaypoint]) -> f64 {
        build_roadbook(wp, &[], even(1.0)).total_dist_m
    }

    #[test]
    fn legs_run_start_markers_ordered_finish() {
        let wp = course();
        let markers = [
            RoadbookMarker {
                position_m: Some(1500.0),
                kind: "aid_station",
                label: "Aid 2",
                services: &[],
                cutoff_clock: None,
                cutoff_elapsed_s: None,
            },
            RoadbookMarker {
                position_m: Some(500.0),
                kind: "aid_station",
                label: "Aid 1",
                services: &[],
                cutoff_clock: None,
                cutoff_elapsed_s: None,
            },
        ];
        let rb = build_roadbook(&wp, &markers, even(3600.0));
        assert_eq!(rb.legs.len(), 4);
        assert!(rb.legs[0].is_start());
        assert_eq!(rb.legs[1].kind, Some("aid_station"));
        assert_eq!(rb.legs[1].label, "Aid 1");
        assert_eq!(rb.legs[2].kind, Some("aid_station"));
        assert_eq!(rb.legs[2].label, "Aid 2");
        assert!(rb.legs[3].is_finish());
        assert!(rb.legs[1].cum_dist_m < rb.legs[2].cum_dist_m);
        assert_eq!(rb.legs[3].cum_dist_m, rb.total_dist_m);
    }

    #[test]
    fn even_model_splits_goal_time_proportional_to_distance() {
        let wp = course();
        let half = total_of(&wp) / 2.0;
        let markers = [RoadbookMarker {
            position_m: Some(half),
            kind: "aid_station",
            label: "Mid",
            services: &[],
            cutoff_clock: None,
            cutoff_elapsed_s: None,
        }];
        let rb = build_roadbook(&wp, &markers, even(4000.0));
        let mid = rb.legs[1].projected_elapsed_s;
        assert!((mid - 2000.0).abs() < 50.0, "mid elapsed {mid}");
        assert_eq!(libm::round(rb.legs[2].projected_elapsed_s), 4000.0);
    }

    #[test]
    fn effort_model_gives_the_climb_leg_more_time_than_even_pace() {
        let wp = course();
        let mid = total_of(&wp) / 2.0;
        let marker = [RoadbookMarker {
            position_m: Some(mid),
            kind: "aid_station",
            label: "Mid",
            services: &[],
            cutoff_clock: None,
            cutoff_elapsed_s: None,
        }];
        let even_rb = build_roadbook(&wp, &marker, even(3600.0));
        let effort_rb = build_roadbook(
            &wp,
            &marker,
            RoadbookOptions {
                goal_seconds: 3600.0,
                start_clock_min: None,
                model: PacingModel::Effort,
            },
        );
        // The flat first half should be reached SOONER under effort than even.
        assert!(
            effort_rb.legs[1].projected_elapsed_s < even_rb.legs[1].projected_elapsed_s,
            "effort mid {} should be < even mid {}",
            effort_rb.legs[1].projected_elapsed_s,
            even_rb.legs[1].projected_elapsed_s
        );
        assert_eq!(libm::round(effort_rb.legs[2].projected_elapsed_s), 3600.0);
    }

    #[test]
    fn effort_degrades_to_even_when_there_is_no_elevation() {
        let mut flat: Vec<RoadbookWaypoint, 32> = Vec::new();
        for i in 0..11 {
            let _ = flat.push(RoadbookWaypoint {
                lat: i as f64 * 0.001,
                lng: 0.0,
                ele: None,
            });
        }
        let mid = total_of(&flat) / 2.0;
        let marker = [RoadbookMarker {
            position_m: Some(mid),
            kind: "aid_station",
            label: "Mid",
            services: &[],
            cutoff_clock: None,
            cutoff_elapsed_s: None,
        }];
        let even_rb = build_roadbook(&flat, &marker, even(3600.0));
        let effort_rb = build_roadbook(
            &flat,
            &marker,
            RoadbookOptions {
                goal_seconds: 3600.0,
                start_clock_min: None,
                model: PacingModel::Effort,
            },
        );
        assert!(!effort_rb.has_elevation);
        assert_eq!(
            libm::round(effort_rb.legs[1].projected_elapsed_s),
            libm::round(even_rb.legs[1].projected_elapsed_s)
        );
    }

    #[test]
    fn cutoff_from_cutoff_elapsed_s_yields_a_margin_and_status() {
        let wp = course();
        let total = total_of(&wp);
        let markers = [RoadbookMarker {
            position_m: Some(total / 2.0),
            kind: "cutoff",
            label: "Gate",
            services: &[],
            cutoff_clock: None,
            cutoff_elapsed_s: Some(2000.0),
        }];
        let rb = build_roadbook(&wp, &markers, even(3600.0));
        let gate = &rb.legs[1];
        let cutoff = gate.cutoff.expect("cutoff present");
        assert_eq!(cutoff.limit_elapsed_s, 2000);
        // Mid elapsed ~1800 → margin ~+200 → tight (within 30 min).
        assert!(cutoff.margin_s > 0.0 && cutoff.margin_s < 30.0 * 60.0);
        assert_eq!(cutoff.status, CutoffStatus::Tight);
    }

    #[test]
    fn a_too_slow_goal_turns_a_cutoff_red_miss() {
        let wp = course();
        let total = total_of(&wp);
        let markers = [RoadbookMarker {
            position_m: Some(total / 2.0),
            kind: "cutoff",
            label: "Gate",
            services: &[],
            cutoff_clock: None,
            cutoff_elapsed_s: Some(600.0),
        }];
        let rb = build_roadbook(&wp, &markers, even(7200.0));
        let cutoff = rb.legs[1].cutoff.expect("cutoff present");
        assert_eq!(cutoff.status, CutoffStatus::Miss);
        assert!(cutoff.margin_s < 0.0);
    }

    #[test]
    fn cutoff_from_cutoff_clock_needs_a_start_clock() {
        let wp = course();
        let total = total_of(&wp);
        let markers = [RoadbookMarker {
            position_m: Some(total / 2.0),
            kind: "cutoff",
            label: "Gate",
            services: &[],
            cutoff_clock: Some("06:45"),
            cutoff_elapsed_s: None,
        }];
        // Start 06:00 (360 min). Cutoff clock 06:45 → limit 2700 s.
        let rb = build_roadbook(
            &wp,
            &markers,
            RoadbookOptions {
                goal_seconds: 3600.0,
                start_clock_min: Some(360.0),
                model: PacingModel::Even,
            },
        );
        assert_eq!(
            rb.legs[1].cutoff.expect("cutoff present").limit_elapsed_s,
            2700
        );
        // Without a start clock the clock-only cutoff can't resolve.
        let no_start = build_roadbook(&wp, &markers, even(3600.0));
        assert_eq!(no_start.legs[1].cutoff, None);
    }

    #[test]
    fn cutoff_clock_equal_to_the_start_clock_resolves_to_a_24h_limit_not_0s() {
        let wp = course();
        let total = total_of(&wp);
        let markers = [RoadbookMarker {
            position_m: Some(total / 2.0),
            kind: "cutoff",
            label: "Gate",
            services: &[],
            cutoff_clock: Some("06:00"),
            cutoff_elapsed_s: None,
        }];
        let rb = build_roadbook(
            &wp,
            &markers,
            RoadbookOptions {
                goal_seconds: 3600.0,
                start_clock_min: Some(360.0),
                model: PacingModel::Even,
            },
        );
        let cutoff = rb.legs[1].cutoff.expect("cutoff present");
        assert_eq!(cutoff.limit_elapsed_s, 86_400);
        assert_eq!(cutoff.status, CutoffStatus::Safe);
    }

    #[test]
    fn projected_clock_advances_from_the_start_and_wraps_past_midnight() {
        let wp = course();
        let rb = build_roadbook(
            &wp,
            &[],
            RoadbookOptions {
                goal_seconds: 3600.0,
                start_clock_min: Some(23.0 * 60.0 + 30.0),
                model: PacingModel::Even,
            },
        );
        // Start 23:30, +60 min finish → 00:30 next day → 30 min past midnight.
        assert_eq!(libm::round(rb.legs[1].projected_clock_min.unwrap()), 30.0);
    }

    #[test]
    fn markers_with_null_position_m_are_dropped_from_the_schedule() {
        let wp = course();
        let markers = [
            RoadbookMarker {
                position_m: None,
                kind: "aid_station",
                label: "Floating",
                services: &[],
                cutoff_clock: None,
                cutoff_elapsed_s: None,
            },
            RoadbookMarker {
                position_m: Some(500.0),
                kind: "aid_station",
                label: "Real",
                services: &[],
                cutoff_clock: None,
                cutoff_elapsed_s: None,
            },
        ];
        let rb = build_roadbook(&wp, &markers, even(3600.0));
        assert_eq!(rb.legs.len(), 3); // start, Real, finish
        assert_eq!(rb.legs[1].label, "Real");
    }

    #[test]
    fn aid_services_flow_through_to_the_leg() {
        let wp = course();
        let svc = ["water", "food"];
        let markers = [RoadbookMarker {
            position_m: Some(500.0),
            kind: "aid_station",
            label: "Aid",
            services: &svc,
            cutoff_clock: None,
            cutoff_elapsed_s: None,
        }];
        let rb = build_roadbook(&wp, &markers, even(3600.0));
        assert_eq!(rb.legs[1].services, &["water", "food"]);
    }
}
