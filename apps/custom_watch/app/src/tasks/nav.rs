//! Nav task — projects each GPS fix onto the loaded breadcrumb course and
//! publishes the result to `state::NAV`.
//!
//! Thin glue by design: the projection math and the off-course alert latch
//! live in host-tested `watch_core::course`. This task only feeds fixes in and
//! publishes what came out, logging the alert's rising edge and the recovery
//! so an off-course excursion is visible in the defmt stream regardless of
//! which display page is up.
//!
//! The course itself is static at tier 1: the canned sim course behind the
//! default-OFF `sim-course` feature (built by `bin/watch-sim.sh`). A phone
//! push over BLE — simplified phone-side to `MAX_COURSE_POINTS` — is the
//! tier-2 path. Without a course the task reports `NoCourse` once and ends;
//! the Nav page then says so instead of showing a silently-empty map.

use defmt::{info, unwrap, warn};
use watch_core::course::{Course, NavStatus, OffCourseAlert};
use watch_core::face::NavView;

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

#[embassy_executor::task]
pub async fn run(course: Option<&'static Course>) {
    let sender = state::NAV.sender();
    let Some(course) = course else {
        info!("nav: no course loaded");
        sender.send(NavView::NoCourse);
        return;
    };
    info!(
        "nav: course loaded, {} points, {} m",
        course.points().len(),
        course.total_m() as u32
    );
    sender.send(NavView::NoFix);
    let mut alert = OffCourseAlert::new();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    // Bias each projection toward forward progress from the last reported
    // along-distance, so on an out-and-back / lollipop the return leg doesn't
    // snap onto the coincident outbound segment (course::project_from).
    let mut prev_along: Option<f64> = None;
    loop {
        let fix = fix_rx.changed().await;
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
        sender.send(NavView::Status(NavStatus {
            off_m: p.off_m,
            along_m: p.along_m,
            alerting: alert.active(),
        }));
    }
}
