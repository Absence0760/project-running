//! Nav task — projects each GPS fix onto the loaded breadcrumb course and
//! publishes the result to `state::NAV`.
//!
//! Thin glue by design: the projection math and the off-course alert latch
//! live in host-tested `watch_core::course`, and their per-fix composition —
//! biased projection, latch edges, next turn ahead — in
//! `watch_core::nav_project`. This task only feeds fixes in and publishes what
//! came out, logging the alert's rising edge and the recovery so an off-course
//! excursion is visible in the defmt stream regardless of which display page is
//! up. Fixes pass `nav_project::FixGate` first: the recorder never lets an
//! impossible-speed fix move the track, and the off-course latch deserves the
//! same protection from a multipath teleport.
//!
//! Because it owns the active course it also shapes that course's climb profile
//! (`course_profile::course_elev_view`) on every course change and publishes it
//! to `state::ROUTE_PROFILE` for the RouteElev page — the same seam as the turn
//! cues, and it keeps the ~4.5 KiB polyline from needing a second copy in the
//! `record` task.
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
use watch_core::course::{Course, OffCourseAlert};
use watch_core::course_profile::course_elev_view;
use watch_core::face::NavView;
use watch_core::nav_project::{course_cues, project_fix, FixGate};
use watch_core::turn_cues::{TurnCue, MAX_TURN_CUES};

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

/// Canned per-point altitudes for the sim course (Boulder sits at ~1650 m), so
/// the RouteElev page draws a real climb profile under the sim. Hardware carries
/// none until a phone pushes a v2 course frame that includes elevation — the
/// page then shows the course's geometry and says NO ELEVATION.
///
/// The summit is the LAST point, not the middle one. Both NMEA fixtures start
/// at the course's middle point and run the east leg away from it, so a middle
/// summit is a crest the runner has already crossed — `climb::crest_ahead`
/// correctly returned `None` for the whole run and the §359 crest rail could
/// not be armed in the sim at all. Same shape of fix as the GSA fix-type
/// transitions added to `gps_dropout.nmea` so the honest signal meter became
/// testable: demo data that does not reach the surface it is demoing is not
/// demo data.
#[cfg(feature = "sim-course")]
static SIM_COURSE_ELEV_M: [i16; 3] = [1650, 1655, 1675];

/// The course this build carries, if any — shared by this task (projection)
/// and the ui task (breadcrumb drawing), so the ~4 KiB point buffer exists
/// once. `None` on the hardware build until a course-push path lands.
#[cfg(feature = "sim-course")]
pub fn course() -> Option<&'static Course> {
    static COURSE: static_cell::StaticCell<Course> = static_cell::StaticCell::new();
    Course::from_points_with_elevation(&SIM_COURSE, &SIM_COURSE_ELEV_M).map(|c| &*COURSE.init(c))
}

#[cfg(not(feature = "sim-course"))]
pub fn course() -> Option<&'static Course> {
    None
}

#[embassy_executor::task]
pub async fn run(boot_course: Option<&'static Course>) {
    let sender = state::NAV.sender();
    let profile_sender = state::ROUTE_PROFILE.sender();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut course_rx = unwrap!(state::COURSE.receiver());
    let mut pushed: Option<Course> = None;
    let mut alert = OffCourseAlert::new();
    // Rejects the finite-but-impossible fix (canyon multipath) before it can
    // fire or clear the off-course latch; the recorder gates its own feed the
    // same way. Deliberately NOT reset on a course swap — see FixGate's docs.
    let mut gate = FixGate::new();
    // Forward-progress bias anchor (course::project_from); reset whenever the
    // active course changes so along-distance restarts on a new route. A lap of
    // a loop course is deliberately NOT a reset event — the projector knows the
    // along-axis wraps, so nothing here has to be told a new lap started.
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
            cues = course_cues(c);
            profile_sender.send(Some(course_elev_view(c)));
            sender.send(NavView::NoFix);
        }
        None => {
            info!("nav: no course loaded");
            profile_sender.send(None);
            sender.send(NavView::NoCourse);
        }
    }

    loop {
        match select(fix_rx.changed(), course_rx.changed()).await {
            Either::First(fix) => {
                let Some(course) = pushed.as_ref().or(boot_course) else {
                    continue;
                };
                if !gate.accept(fix.lat_deg, fix.lon_deg, fix.uptime_s) {
                    warn!("nav: implausible fix rejected before projection");
                    continue;
                }
                // Forward-progress-biased projection keeps along-distance
                // monotonic on a retracing course (course::project_from).
                let Some(out) = project_fix(
                    course,
                    &mut alert,
                    prev_along,
                    &cues,
                    fix.lat_deg,
                    fix.lon_deg,
                ) else {
                    continue;
                };
                prev_along = Some(out.status.along_m);
                if out.went_off_course {
                    warn!(
                        "nav: OFF COURSE ({} m off, {} m along)",
                        out.status.off_m as u32, out.status.along_m as u32
                    );
                } else if out.back_on_course {
                    info!(
                        "nav: back on course ({} m along)",
                        out.status.along_m as u32
                    );
                }
                sender.send(NavView::Status(out.status));
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
                        cues = course_cues(c);
                        profile_sender.send(Some(course_elev_view(c)));
                        sender.send(NavView::NoFix);
                    }
                    None => {
                        info!("nav: no course loaded");
                        profile_sender.send(None);
                        sender.send(NavView::NoCourse);
                    }
                }
            }
        }
    }
}
