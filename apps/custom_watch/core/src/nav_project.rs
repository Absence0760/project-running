//! Per-fix course projection — what the app's `nav` task publishes to
//! `state::NAV` for every fix, lifted out of the async task body.
//!
//! [`crate::course`] owns the projection geometry and the off-course latch,
//! [`crate::turn_cues`] the cue generation and the next-turn read. This module
//! owns the composition the task performed inline: pick the biased or unbiased
//! projection, feed the latch, read the next turn ahead, and report the latch's
//! two *edges* separately from its steady state so the caller can log an
//! excursion and a recovery exactly once each.
//!
//! The precomputed cue list is per-course, not per-fix, so [`course_cues`] is
//! recomputed only when the active course changes (boot course → a phone push,
//! or a re-push).

use heapless::Vec;

use crate::course::{Course, NavStatus, OffCourseAlert};
use crate::grade_adjusted_pace::haversine_metres;
use crate::record::{TurnCueView, MAX_SPEED_MPS};
use crate::trackback::{initial_bearing_deg, BEARING_MIN_DISTANCE_M};
use crate::turn_cues::{
    direction_code, generate_turn_cues, next_turn_ahead, TurnCue, TurnCueOptions, TurnCueWaypoint,
    MAX_TURN_CUES, MAX_TURN_CUE_WAYPOINTS,
};

/// Precompute a course's turn cues — the run-view TurnCue page's source.
pub fn course_cues(course: &Course) -> Vec<TurnCue, MAX_TURN_CUES> {
    let mut waypoints: Vec<TurnCueWaypoint, MAX_TURN_CUE_WAYPOINTS> = Vec::new();
    for cp in course.points() {
        let _ = waypoints.push(TurnCueWaypoint {
            lat: cp.lat_deg,
            lng: cp.lon_deg,
        });
    }
    generate_turn_cues(&waypoints, TurnCueOptions::default())
}

/// Physical-plausibility gate on the fixes the nav task projects.
///
/// The recorder rejects a fix implying an impossible speed before it can move
/// the track ([`crate::record::MAX_SPEED_MPS`]); the nav task consumed the raw
/// fix channel with no such gate, so one canyon-multipath teleport could fire
/// `! OFF CRS` — since the cross-page banners landed, on every page at once —
/// or, worse, clear a live alert while the runner stands exactly as lost as
/// they were. [`project_fix`] already refuses a non-finite position; this gate
/// refuses the finite-but-impossible one, with the same shape the recorder
/// uses for throttled GNSS modes: the ceiling is `MAX_SPEED_MPS * dt` from the
/// last *accepted* fix, so a rejected outlier never moves the anchor, and a
/// genuine relocation (a signal void crossed on foot) self-heals as `dt`
/// grows the ceiling past any real displacement.
///
/// A `dt` of zero is a timestamp duplicate and fails closed, mirroring the
/// recorder. The gate is course-independent — it judges the position stream,
/// not the projection — so a course swap must NOT reset it: the runner did not
/// teleport because the phone pushed a new route.
pub struct FixGate {
    last: Option<(f64, f64, u32)>,
}

impl FixGate {
    pub const fn new() -> Self {
        Self { last: None }
    }

    /// Accept or reject one fix; an accepted fix becomes the new anchor.
    pub fn accept(&mut self, lat_deg: f64, lon_deg: f64, uptime_s: u32) -> bool {
        if !lat_deg.is_finite() || !lon_deg.is_finite() {
            return false;
        }
        let Some((last_lat, last_lon, last_s)) = self.last else {
            self.last = Some((lat_deg, lon_deg, uptime_s));
            return true;
        };
        let dt = uptime_s.saturating_sub(last_s);
        if dt == 0 {
            return false;
        }
        let delta_m = haversine_metres(last_lat, last_lon, lat_deg, lon_deg);
        if delta_m > MAX_SPEED_MPS * dt as f64 {
            return false;
        }
        self.last = Some((lat_deg, lon_deg, uptime_s));
        true
    }
}

impl Default for FixGate {
    fn default() -> Self {
        Self::new()
    }
}

/// One fix projected onto the active course: what to publish, plus the two
/// latch edges worth a log line.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NavOutcome {
    /// The view to publish for this fix.
    pub status: NavStatus,
    /// The off-course latch just fired — a rising edge, once per excursion.
    pub went_off_course: bool,
    /// The latch just re-armed — the runner is back inside the rearm radius.
    pub back_on_course: bool,
}

/// Project one fix onto `course`, advancing `alert`'s latch.
///
/// `prev_along_m` is the last reported along-course distance, which biases the
/// projection toward forward progress on a retracing course
/// ([`Course::project_from`]); `None` on the first fix of a course takes the
/// unbiased projection.
///
/// `None` when the position does not project at all (a non-finite fix). The
/// latch is then left exactly as it was: a garbage fix must not clear a live
/// off-course alert, nor manufacture one.
pub fn project_fix(
    course: &Course,
    alert: &mut OffCourseAlert,
    prev_along_m: Option<f64>,
    cues: &[TurnCue],
    lat_deg: f64,
    lon_deg: f64,
) -> Option<NavOutcome> {
    let projected = match prev_along_m {
        Some(prev) => course.project_from(lat_deg, lon_deg, prev),
        None => course.project(lat_deg, lon_deg),
    };
    let p = projected?;
    let was_alerting = alert.active();
    let went_off_course = alert.update(p.off_m);
    let next_turn = next_turn_ahead(cues, p.along_m).map(|(c, remaining)| TurnCueView {
        direction: direction_code(c.direction),
        distance_m: (c.position_m - p.along_m).max(0.0).min(u16::MAX as f64) as u16,
        remaining,
    });
    // The snapped point is the nearest place back on the line, so the bearing
    // toward it is the escape direction the Nav page shows while alerting.
    // Gated on the same stability floor the trackback BRG uses: under it the
    // projection foot wobbles with GPS jitter and the bearing means nothing.
    let back_to_course_deg = (p.off_m >= BEARING_MIN_DISTANCE_M as f64)
        .then(|| initial_bearing_deg(lat_deg, lon_deg, p.lat_deg, p.lon_deg) as f32);
    Some(NavOutcome {
        status: NavStatus {
            off_m: p.off_m,
            along_m: p.along_m,
            alerting: alert.active(),
            next_turn,
            back_to_course_deg,
        },
        went_off_course,
        back_on_course: was_alerting && !alert.active(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::course::CoursePoint;

    /// A right-angle course at Boulder's latitude: ~90 m north-to-south down a
    /// meridian, then ~90 m east along a parallel. One interior vertex, so it
    /// carries exactly one turn cue.
    fn corner_course() -> Course {
        Course::from_points(&[
            CoursePoint {
                lat_deg: 40.0158083,
                lon_deg: -105.2705,
            },
            CoursePoint {
                lat_deg: 40.015,
                lon_deg: -105.2705,
            },
            CoursePoint {
                lat_deg: 40.015,
                lon_deg: -105.269445,
            },
        ])
        .unwrap()
    }

    /// Degrees of longitude for `m` metres east at the course's latitude.
    fn lon_offset_deg(m: f64) -> f64 {
        m / (111_320.0 * libm::cos(40.015 * core::f64::consts::PI / 180.0))
    }

    #[test]
    fn an_on_course_fix_publishes_a_quiet_status() {
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let out = project_fix(&course, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        assert!(out.status.off_m < 1.0);
        assert!(out.status.along_m > 0.0);
        assert!(!out.status.alerting);
        assert!(!out.went_off_course);
        assert!(!out.back_on_course);
    }

    #[test]
    fn the_off_course_edge_fires_once_per_excursion() {
        // The latch's whole point: an unmissable alert on the way out, then
        // silence while the runner is still out, so a long excursion doesn't
        // re-announce itself every fix.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let far = -105.2705 + lon_offset_deg(80.0);
        let first = project_fix(&course, &mut alert, None, &cues, 40.0155, far).unwrap();
        assert!(first.went_off_course);
        assert!(first.status.alerting);
        for _ in 0..3 {
            let again = project_fix(
                &course,
                &mut alert,
                Some(first.status.along_m),
                &cues,
                40.0155,
                far,
            )
            .unwrap();
            assert!(!again.went_off_course, "must not re-fire while still out");
            assert!(again.status.alerting);
            assert!(!again.back_on_course);
        }
    }

    #[test]
    fn the_recovery_edge_fires_once_when_back_inside_the_rearm_radius() {
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let far = -105.2705 + lon_offset_deg(80.0);
        project_fix(&course, &mut alert, None, &cues, 40.0155, far).unwrap();
        let back = project_fix(&course, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        assert!(back.back_on_course);
        assert!(!back.status.alerting);
        let still_back = project_fix(&course, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        assert!(
            !still_back.back_on_course,
            "recovery is an edge, not a state"
        );
    }

    #[test]
    fn a_fix_between_the_thresholds_holds_the_latch() {
        // The hysteresis band: 30 m off is past the rearm radius but not past
        // the trigger, so a runner drifting along the boundary neither clears
        // nor re-fires the alert.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        project_fix(
            &course,
            &mut alert,
            None,
            &cues,
            40.0155,
            -105.2705 + lon_offset_deg(80.0),
        )
        .unwrap();
        let drifting = project_fix(
            &course,
            &mut alert,
            None,
            &cues,
            40.0155,
            -105.2705 + lon_offset_deg(30.0),
        )
        .unwrap();
        assert!(drifting.status.alerting);
        assert!(!drifting.back_on_course);
        assert!(!drifting.went_off_course);
    }

    #[test]
    fn a_non_finite_fix_projects_to_nothing_and_leaves_the_latch_alone() {
        // A garbage position must not clear a live off-course alert — a lost
        // runner would see the warning vanish without moving.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        project_fix(
            &course,
            &mut alert,
            None,
            &cues,
            40.0155,
            -105.2705 + lon_offset_deg(80.0),
        )
        .unwrap();
        assert!(alert.active());
        for (lat, lon) in [
            (f64::NAN, -105.2705),
            (40.0155, f64::NAN),
            (f64::INFINITY, f64::NEG_INFINITY),
        ] {
            assert!(project_fix(&course, &mut alert, None, &cues, lat, lon).is_none());
            assert!(alert.active(), "the latch must survive a garbage fix");
        }
    }

    #[test]
    fn the_next_turn_is_the_corner_ahead_and_its_distance_never_goes_negative() {
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        assert_eq!(cues.len(), 1, "the corner is one cue");
        let approaching =
            project_fix(&course, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        let turn = approaching.status.next_turn.unwrap();
        assert!(turn.distance_m > 0);
        assert_eq!(turn.remaining, 1);
        // Past the corner there is no turn left, rather than a negative-distance
        // cue clamped to zero and shown forever.
        let past = project_fix(
            &course,
            &mut alert,
            Some(approaching.status.along_m),
            &cues,
            40.015,
            -105.2698,
        )
        .unwrap();
        assert!(past.status.next_turn.is_none());
    }

    #[test]
    fn a_course_with_no_turns_carries_no_cues() {
        // A straight line (and a two-point course) has no interior vertex to
        // turn at, so the TurnCue page has nothing to show — not a bogus cue at
        // the finish.
        let straight = Course::from_points(&[
            CoursePoint {
                lat_deg: 40.015,
                lon_deg: -105.2705,
            },
            CoursePoint {
                lat_deg: 40.016,
                lon_deg: -105.2705,
            },
        ])
        .unwrap();
        let cues = course_cues(&straight);
        assert!(cues.is_empty());
        let mut alert = OffCourseAlert::new();
        let out = project_fix(&straight, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        assert!(out.status.next_turn.is_none());
    }

    #[test]
    fn a_forward_bias_anchor_keeps_along_distance_from_snapping_backward() {
        // On a course whose second leg retraces the first, an unbiased
        // projection can snap the return onto the outbound leg and report the
        // along-distance going backward. The anchor is what stops it.
        let out_and_back = Course::from_points(&[
            CoursePoint {
                lat_deg: 40.015,
                lon_deg: -105.2705,
            },
            CoursePoint {
                lat_deg: 40.016,
                lon_deg: -105.2705,
            },
            CoursePoint {
                lat_deg: 40.015,
                lon_deg: -105.2705,
            },
        ])
        .unwrap();
        let cues = course_cues(&out_and_back);
        let mut alert = OffCourseAlert::new();
        let unbiased =
            project_fix(&out_and_back, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        let biased = project_fix(
            &out_and_back,
            &mut alert,
            Some(out_and_back.total_m() * 0.75),
            &cues,
            40.0155,
            -105.2705,
        )
        .unwrap();
        assert!(biased.status.along_m > unbiased.status.along_m);
        assert!((biased.status.off_m - unbiased.status.off_m).abs() < 1e-6);
    }

    #[test]
    fn an_off_course_fix_carries_the_bearing_back_toward_the_course() {
        // A fix due EAST of the course's north-south leg (near its top, so
        // that leg — not the east-west one below — is nearest): the way back
        // is west, so the published bearing must read ~270 — pointing the
        // runner TOWARD the line, never along their own displacement away
        // from it. This is the path the Nav page's escape line renders from.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let far = -105.2705 + lon_offset_deg(60.0);
        let out = project_fix(&course, &mut alert, None, &cues, 40.0157, far).unwrap();
        assert!(out.status.alerting);
        let deg = out.status.back_to_course_deg.unwrap();
        assert!((deg - 270.0).abs() < 2.0, "bearing {}", deg);
        assert_eq!(crate::trackback::sector_of_deg(deg), 12, "expected W");
    }

    #[test]
    fn a_fix_on_the_line_carries_no_back_bearing() {
        // Under the trackback stability floor the projection foot wobbles
        // with GPS jitter, so the bearing would be noise — and there is
        // nothing to escape from.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let out = project_fix(&course, &mut alert, None, &cues, 40.0155, -105.2705).unwrap();
        assert!(out.status.off_m < 1.0);
        assert_eq!(out.status.back_to_course_deg, None);
    }

    #[test]
    fn the_back_bearing_survives_the_hysteresis_band_while_still_latched() {
        // The latch holds between 20 and 40 m out; the escape line renders on
        // `alerting`, so the bearing must still be published there, not only
        // past the 40 m trigger.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        project_fix(
            &course,
            &mut alert,
            None,
            &cues,
            40.0157,
            -105.2705 + lon_offset_deg(60.0),
        )
        .unwrap();
        let drifting = project_fix(
            &course,
            &mut alert,
            None,
            &cues,
            40.0157,
            -105.2705 + lon_offset_deg(30.0),
        )
        .unwrap();
        assert!(drifting.status.alerting);
        let deg = drifting.status.back_to_course_deg.unwrap();
        assert!((deg - 270.0).abs() < 2.0, "bearing {}", deg);
    }

    #[test]
    fn the_gate_accepts_a_first_fix_and_a_plausible_walk() {
        let mut gate = FixGate::new();
        assert!(gate.accept(40.0155, -105.2705, 100));
        // ~8 m east over 1 s is a fast runner, not a teleport.
        assert!(gate.accept(40.0155, -105.2705 + lon_offset_deg(8.0), 101));
    }

    #[test]
    fn a_multipath_teleport_is_rejected_and_never_moves_the_anchor() {
        // The finding this gate exists for: one canyon-bounce fix 500 m out
        // must not reach the projection, and the NEXT honest fix — judged
        // against the un-moved anchor — must still pass.
        let mut gate = FixGate::new();
        assert!(gate.accept(40.0155, -105.2705, 100));
        assert!(!gate.accept(40.0155, -105.2705 + lon_offset_deg(500.0), 101));
        assert!(gate.accept(40.0155, -105.2705 + lon_offset_deg(5.0), 102));
    }

    #[test]
    fn a_real_relocation_self_heals_as_the_ceiling_grows_with_dt() {
        // A runner crosses a 10-minute signal void on foot and reappears
        // 1.5 km away: 600 s at the ceiling covers 6 km, so the reappearance
        // is accepted rather than locking the gate against reality forever.
        let mut gate = FixGate::new();
        assert!(gate.accept(40.0155, -105.2705, 100));
        assert!(gate.accept(40.0155, -105.2705 + lon_offset_deg(1500.0), 700));
    }

    #[test]
    fn a_timestamp_duplicate_fails_closed() {
        let mut gate = FixGate::new();
        assert!(gate.accept(40.0155, -105.2705, 100));
        assert!(!gate.accept(40.0155, -105.2705 + lon_offset_deg(1.0), 100));
    }

    #[test]
    fn a_non_finite_position_is_rejected_without_becoming_the_anchor() {
        let mut gate = FixGate::new();
        assert!(!gate.accept(f64::NAN, -105.2705, 100));
        // The first FINITE fix is still treated as the first fix.
        assert!(gate.accept(40.0155, -105.2705, 101));
    }

    #[test]
    fn the_published_status_mirrors_the_projection() {
        // The status the Nav page renders must be the projection, not a
        // re-derivation that could drift from it.
        let course = corner_course();
        let mut alert = OffCourseAlert::new();
        let cues = course_cues(&course);
        let p = course.project(40.0155, -105.27045).unwrap();
        let out = project_fix(&course, &mut alert, None, &cues, 40.0155, -105.27045).unwrap();
        assert_eq!(out.status.off_m, p.off_m);
        assert_eq!(out.status.along_m, p.along_m);
    }
}
