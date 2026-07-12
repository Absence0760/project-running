//! Nav task — projects each GPS fix onto the loaded breadcrumb course and
//! publishes the result to `state::NAV`.
//!
//! Thin glue by design: the projection math and the off-course alert latch
//! live in host-tested `watch_core::course`. This task only feeds fixes in and
//! publishes what came out, logging the alert's rising edge and the recovery
//! so an off-course excursion is visible in the defmt stream regardless of
//! which display page is up.
//!
//! The task follows one of two courses: the canned sim course carried at boot
//! behind the default-OFF `sim-course` feature (built by `bin/watch-sim.sh`), or
//! a course the phone pushes over BLE (`course_store` frame reassembled by the
//! `ble` task → `state::COURSE`, simplified phone-side to `MAX_COURSE_POINTS`). A
//! pushed course takes over from `NoCourse` / the boot course and a later push
//! replaces it. Without any course the task reports `NoCourse` and waits — the
//! Nav page then says so instead of showing a silently-empty map — until a push
//! arrives, at which point it starts projecting fixes onto the loaded course.

use defmt::{info, unwrap, warn};
use embassy_futures::select::{select, Either};
use watch_core::course::{Course, NavStatus, OffCourseAlert};
use watch_core::face::NavView;
use watch_core::record::TurnCueView;
use watch_core::turn_cues::{
    direction_code, generate_turn_cues, next_turn_ahead, TurnCue, TurnCueOptions, TurnCueWaypoint,
    MAX_TURN_CUES, MAX_TURN_CUE_WAYPOINTS,
};

use crate::state;

/// The canned sim course: the west + south edges of `bench_jog.nmea`'s
/// ~90 m x ~90 m rectangle, NW -> SW -> SE. Two of the jog loop's four legs
/// deliberately leave it, so every lap of the fixture exercises the whole
/// surface: on-course following down the west edge and along the south edge,
/// the > 40 m off-course alert climbing the east edge, and the re-arm as the
/// north leg closes back on the NW corner.
#[cfg(feature = "sim-course")]
static SIM_COURSE: [watch_core::course::CoursePoint; 3] = [
    watch_core::course::CoursePoint {
        lat_deg: 40.0158083,
        lon_deg: -105.2705,
    },
    watch_core::course::CoursePoint {
        lat_deg: 40.015,
        lon_deg: -105.2705,
    },
    watch_core::course::CoursePoint {
        lat_deg: 40.015,
        lon_deg: -105.269445,
    },
];

/// The course this build carries, if any — shared by this task (projection)
/// and the ui task (breadcrumb drawing), so the ~4 KiB point buffer exists
/// once. `None` on the hardware build until a course-push path lands.
#[cfg(feature = "sim-course")]
pub fn course() -> Option<&'static Course> {
    static COURSE: static_cell::StaticCell<Course> = static_cell::StaticCell::new();
    Course::from_points(&SIM_COURSE).map(|c| &*COURSE.init(c))
}

#[cfg(not(feature = "sim-course"))]
pub fn course() -> Option<&'static Course> {
    None
}

/// Precompute the turn cues for a course — the run-view TurnCue page source.
/// Recomputed whenever the active course changes (boot → pushed, or a re-push).
fn compute_cues(course: &Course) -> heapless::Vec<TurnCue, MAX_TURN_CUES> {
    let mut waypoints: heapless::Vec<TurnCueWaypoint, MAX_TURN_CUE_WAYPOINTS> = heapless::Vec::new();
    for cp in course.points() {
        let _ = waypoints.push(TurnCueWaypoint {
            lat: cp.lat_deg,
            lng: cp.lon_deg,
        });
    }
    generate_turn_cues(&waypoints, TurnCueOptions::default())
}

#[embassy_executor::task]
pub async fn run(boot_course: Option<&'static Course>) {
    let sender = state::NAV.sender();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut course_rx = unwrap!(state::COURSE.receiver());
    let mut pushed: Option<Course> = None;
    let mut alert = OffCourseAlert::new();
    // Forward-progress bias anchor (course::project_from); reset whenever the
    // active course changes so along-distance restarts on a new route.
    let mut prev_along: Option<f64> = None;
    // Turn cues for the ACTIVE course, recomputed on a course change so a
    // phone-pushed course drives the TurnCue page too.
    let mut cues: heapless::Vec<TurnCue, MAX_TURN_CUES> = heapless::Vec::new();

    // Announce the active course (boot or pushed) and (re)compute its cues.
    // Inlined rather than closured because it mutates `cues`.
    match pushed.as_ref().or(boot_course) {
        Some(c) => {
            info!(
                "nav: course loaded, {} points, {} m",
                c.points().len(),
                c.total_m() as u32
            );
            cues = compute_cues(c);
            sender.send(NavView::NoFix);
        }
        None => {
            info!("nav: no course loaded");
            sender.send(NavView::NoCourse);
        }
    }

    loop {
        match select(fix_rx.changed(), course_rx.changed()).await {
            Either::First(fix) => {
                let Some(course) = pushed.as_ref().or(boot_course) else {
                    continue;
                };
                // Forward-progress-biased projection keeps along-distance
                // monotonic on a retracing course (course::project_from).
                let projected = match prev_along {
                    Some(prev) => course.project_from(fix.lat_deg, fix.lon_deg, prev),
                    None => course.project(fix.lat_deg, fix.lon_deg),
                };
                let Some(p) = projected else {
                    continue;
                };
                prev_along = Some(p.along_m);
                let was_active = alert.active();
                if alert.update(p.off_m) {
                    warn!(
                        "nav: OFF COURSE ({} m off, {} m along)",
                        p.off_m as u32, p.along_m as u32
                    );
                } else if was_active && !alert.active() {
                    info!("nav: back on course ({} m along)", p.along_m as u32);
                }
                let next_turn = next_turn_ahead(&cues, p.along_m).map(|(c, remaining)| TurnCueView {
                    direction: direction_code(c.direction),
                    distance_m: (c.position_m - p.along_m).max(0.0).min(u16::MAX as f64) as u16,
                    remaining,
                });
                sender.send(NavView::Status(NavStatus {
                    off_m: p.off_m,
                    along_m: p.along_m,
                    alerting: alert.active(),
                    next_turn,
                }));
            }
            // A phone-pushed course arrived (or replaced the current one): swap to
            // it, re-arm the off-course latch, restart along-distance, recompute
            // cues, and re-announce so the Nav page leaves NO COURSE LOADED.
            Either::Second(new_course) => {
                pushed = new_course;
                alert = OffCourseAlert::new();
                prev_along = None;
                match pushed.as_ref().or(boot_course) {
                    Some(c) => {
                        info!(
                            "nav: course loaded, {} points, {} m",
                            c.points().len(),
                            c.total_m() as u32
                        );
                        cues = compute_cues(c);
                        sender.send(NavView::NoFix);
                    }
                    None => {
                        info!("nav: no course loaded");
                        sender.send(NavView::NoCourse);
                    }
                }
            }
        }
    }
}
