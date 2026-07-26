//! The pushed course's climb profile, shaped for the RouteElev glance page.
//!
//! [`course_elev_view`] turns a loaded [`Course`] into the [`RouteElevView`] the
//! face + render layer draw: total gain / loss, the point count, the course
//! length, and a fixed-length elevation series the `MiniProfile` sparkline plots
//! as a shape.
//!
//! The series is sampled at **even distance along the course**, not one sample
//! per course point: a phone-simplified polyline puts its points where the
//! *line* bends, so a switchback carries twenty points over 200 m while a
//! straight flat leg carries two over 3 km. Plotting index-evenly would let the
//! switchback eat most of the panel and squash the climb — a distance-even
//! series is the only one whose x axis matches the runner's along-course
//! position, which is also what lets the marker sit at
//! `along_m / total_m` of the panel width.
//!
//! Gain and loss are summed over the **whole** pushed series, not the resampled
//! one, so a col between two display samples still counts toward D+ — the same
//! discipline the run's own elevation page follows by taking its totals from the
//! baro accumulator rather than its decimated sparkline.
//!
//! Integer metres throughout: the wire carries `i16` metres, so the sums are
//! exact and need none of `route_elevation`'s `f64` web-parity arithmetic (which
//! would also want a 2 KiB stack buffer here).
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use crate::course::Course;
use crate::grade_adjusted_pace::haversine_metres;
use crate::record::{RouteElevView, COURSE_PROFILE_CAP};

/// Shape `course` into the RouteElev page's view. A course pushed without
/// elevation still yields a view — with `len == 0`, so the page shows the point
/// count and course length and no profile, rather than a flat line at zero.
pub fn course_elev_view(course: &Course) -> RouteElevView {
    let points = course.points();
    let total_m = course.total_m();
    let mut view = RouteElevView {
        gain_m: 0,
        loss_m: 0,
        points: points.len().min(u16::MAX as usize) as u16,
        total_m: total_m.max(0.0).min(u32::MAX as f64) as u32,
        samples: [0; COURSE_PROFILE_CAP],
        len: 0,
    };
    let Some(elev) = course.elevations() else {
        return view;
    };

    let mut gain: i32 = 0;
    let mut loss: i32 = 0;
    for w in elev.windows(2) {
        let d = w[1] as i32 - w[0] as i32;
        if d > 0 {
            gain += d;
        } else {
            loss -= d;
        }
    }
    view.gain_m = gain.clamp(0, u16::MAX as i32) as u16;
    view.loss_m = loss.clamp(0, u16::MAX as i32) as u16;

    // A zero-length course (duplicate points) has no distance axis to sample
    // along, so it keeps the honest empty profile above.
    if total_m <= 0.0 {
        return view;
    }
    resample(points, elev, total_m, &mut view.samples);
    view.len = COURSE_PROFILE_CAP;
    view
}

/// Fill `out` with `COURSE_PROFILE_CAP` elevation samples spaced evenly by
/// distance from the course start to its finish, interpolating within whichever
/// segment each target distance falls in. Targets ascend, so one forward walk
/// over the segments covers them all.
fn resample(
    points: &[crate::course::CoursePoint],
    elev: &[i16],
    total_m: f64,
    out: &mut [i16; COURSE_PROFILE_CAP],
) {
    let mut seg = 0usize;
    let mut seg_start_m = 0.0;
    let mut seg_len = segment_len(points, 0);
    for (k, slot) in out.iter_mut().enumerate() {
        let target = total_m * k as f64 / (COURSE_PROFILE_CAP - 1) as f64;
        while seg + 2 < points.len() && target > seg_start_m + seg_len {
            seg_start_m += seg_len;
            seg += 1;
            seg_len = segment_len(points, seg);
        }
        let t = if seg_len > 0.0 {
            ((target - seg_start_m) / seg_len).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let a = elev[seg] as f64;
        let b = elev[seg + 1] as f64;
        *slot = libm::round(a + (b - a) * t) as i16;
    }
}

fn segment_len(points: &[crate::course::CoursePoint], i: usize) -> f64 {
    let a = points[i];
    let b = points[i + 1];
    haversine_metres(a.lat_deg, a.lon_deg, b.lat_deg, b.lon_deg)
}

/// Where the runner sits along the course, as parts-per-thousand of its length
/// — the profile marker's x position. `None` without a live along-course
/// distance or on a zero-length course; clamped so an over-run past the finish
/// marks the end rather than running off the panel.
pub fn position_permille(along_m: f64, total_m: u32) -> Option<u16> {
    if total_m == 0 || !along_m.is_finite() {
        return None;
    }
    let frac = along_m / total_m as f64;
    Some((libm::round(frac * 1000.0)).clamp(0.0, 1000.0) as u16)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::course::CoursePoint;

    /// Points spaced ~111 m apart in latitude (1e-3 deg), so the distance axis
    /// is easy to reason about.
    fn pts(n: usize) -> std::vec::Vec<CoursePoint> {
        (0..n)
            .map(|i| CoursePoint {
                lat_deg: 51.5 + i as f64 * 1e-3,
                lon_deg: -0.1,
            })
            .collect()
    }

    fn with_elev(elev: &[i16]) -> Course {
        Course::from_points_with_elevation(&pts(elev.len()), elev).expect("builds")
    }

    #[test]
    fn a_course_without_elevation_reports_geometry_and_an_empty_profile() {
        let view = course_elev_view(&Course::from_points(&pts(4)).unwrap());
        assert_eq!(view.len, 0);
        assert_eq!(view.points, 4);
        assert_eq!(view.gain_m, 0);
        assert_eq!(view.loss_m, 0);
        assert!(view.total_m > 300 && view.total_m < 350, "{}", view.total_m);
    }

    #[test]
    fn gain_and_loss_sum_the_whole_pushed_series() {
        let view = course_elev_view(&with_elev(&[100, 140, 120, 160]));
        assert_eq!(view.gain_m, 80);
        assert_eq!(view.loss_m, 20);
        assert_eq!(view.points, 4);
    }

    #[test]
    fn a_descending_course_reports_loss_only() {
        let view = course_elev_view(&with_elev(&[900, 700, 400]));
        assert_eq!(view.gain_m, 0);
        assert_eq!(view.loss_m, 500);
    }

    #[test]
    fn gain_and_loss_saturate_rather_than_wrap() {
        // A sawtooth of 9000 m swings: 8 rises of 9000 m clamps at u16::MAX.
        let mut series = std::vec::Vec::new();
        for i in 0..18 {
            series.push(if i % 2 == 0 { -500 } else { 9000 });
        }
        let view = course_elev_view(&with_elev(&series));
        assert_eq!(view.gain_m, u16::MAX);
        assert_eq!(view.loss_m, u16::MAX);
    }

    #[test]
    fn the_series_fills_the_fixed_capacity_and_keeps_the_endpoints() {
        let view = course_elev_view(&with_elev(&[100, 200, 150]));
        assert_eq!(view.len, COURSE_PROFILE_CAP);
        assert_eq!(view.samples[0], 100);
        assert_eq!(view.samples[COURSE_PROFILE_CAP - 1], 150);
    }

    #[test]
    fn the_series_is_sampled_evenly_by_distance_not_by_point_index() {
        // Three points: a 111 m leg climbing 100 m, then a ~1111 m leg flat.
        // Index-even sampling would give the short leg half the series; a
        // distance-even one gives it a tenth.
        let points = [
            CoursePoint {
                lat_deg: 51.5,
                lon_deg: -0.1,
            },
            CoursePoint {
                lat_deg: 51.501,
                lon_deg: -0.1,
            },
            CoursePoint {
                lat_deg: 51.511,
                lon_deg: -0.1,
            },
        ];
        let course = Course::from_points_with_elevation(&points, &[100, 200, 200]).unwrap();
        let view = course_elev_view(&course);
        let climbing = view.samples[..view.len]
            .iter()
            .filter(|&&v| v < 200)
            .count();
        assert!(
            climbing < COURSE_PROFILE_CAP / 4,
            "{climbing} of {COURSE_PROFILE_CAP} samples on a leg that is a tenth of the course"
        );
    }

    #[test]
    fn a_flat_course_samples_flat() {
        let view = course_elev_view(&with_elev(&[1500; 5]));
        assert!(view.samples[..view.len].iter().all(|&v| v == 1500));
        assert_eq!(view.gain_m, 0);
        assert_eq!(view.loss_m, 0);
    }

    #[test]
    fn a_zero_length_course_keeps_the_empty_profile() {
        let same = [
            CoursePoint {
                lat_deg: 51.5,
                lon_deg: -0.1,
            },
            CoursePoint {
                lat_deg: 51.5,
                lon_deg: -0.1,
            },
        ];
        let course = Course::from_points_with_elevation(&same, &[100, 400]).unwrap();
        let view = course_elev_view(&course);
        assert_eq!(view.len, 0);
        assert_eq!(view.total_m, 0);
        // The totals still come off the pushed series, which is real data.
        assert_eq!(view.gain_m, 300);
    }

    #[test]
    fn the_marker_position_is_a_clamped_fraction_of_the_course() {
        assert_eq!(position_permille(0.0, 1000), Some(0));
        assert_eq!(position_permille(500.0, 1000), Some(500));
        assert_eq!(position_permille(1000.0, 1000), Some(1000));
        assert_eq!(position_permille(1500.0, 1000), Some(1000));
        assert_eq!(position_permille(-10.0, 1000), Some(0));
    }

    #[test]
    fn the_marker_position_is_withheld_without_a_course_length_or_a_finite_fix() {
        assert_eq!(position_permille(100.0, 0), None);
        assert_eq!(position_permille(f64::NAN, 1000), None);
        assert_eq!(position_permille(f64::INFINITY, 1000), None);
    }
}
