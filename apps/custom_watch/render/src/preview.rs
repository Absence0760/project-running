//! ASCII preview of composed pages — the stand-in for a display sim on a host
//! with no Renode. Each test builds a representative recording snapshot, draws
//! the face text + the widget overlay exactly as the ui task would, and dumps
//! the framebuffer as text. They assert the panel is non-blank; run with
//! `--nocapture` to eyeball the layout:
//!
//! ```text
//! bin/watch-test.sh preview -- --nocapture
//! ```

use sharp_mip::{Framebuffer, HEIGHT, WIDTH};
use watch_core::face::{self, IdleView, NavView};
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::hr_zones::{zone_cutoffs_from_max_hr, DEFAULT_MAX_HR_BPM};
use watch_core::page::Page;
use watch_core::record::{FuelCarryView, FuelView, RecordState, Snapshot, PACE_BUCKET_COUNT};

use crate::widgets;

// Downsample 2x in each axis so a 168x144 panel prints as 84x72 — dense enough
// to read a layout, small enough to scan in a terminal. A cell is ink if any of
// its four source pixels is set.
fn ascii_dump(fb: &Framebuffer) -> String {
    let mut out = String::new();
    let mut y = 0;
    while y < HEIGHT {
        let mut x = 0;
        while x < WIDTH {
            let ink = fb.pixel(x, y)
                || fb.pixel(x + 1, y)
                || fb.pixel(x, y + 1)
                || fb.pixel(x + 1, y + 1);
            out.push(if ink { '#' } else { '.' });
            x += 2;
        }
        out.push('\n');
        y += 2;
    }
    out
}

fn base_snapshot() -> Snapshot {
    Snapshot {
        state: RecordState::Recording,
        manual_paused: false,
        distance_m: 32_400.0,
        elapsed_s: 3 * 3600 + 12 * 60 + 5,
        moving_s: 3 * 3600,
        current_speed_mps: 2.6,
        avg_pace_s_per_km: Some(6 * 60 + 20),
        current_pace_s_per_km: Some(6 * 60 + 5),
        gap_s_per_km: Some(5 * 60 + 55),
        lap: 5,
        lap_distance_m: 400.0,
        lap_elapsed_s: 150,
        last_lap: None,
        pacer: None,
        zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
        zone_time_s: [0; 5],
        cutoff: None,
        race_prediction: None,
        pace_bucket_m: [0.0; PACE_BUCKET_COUNT],
        training_stress: None,
        band: None,
        gear: None,
        roadbook: None,
        fuel: None,
        training_paces: None,
        fitness: None,
        elev_profile: watch_core::record::ElevProfileView::empty(),
        recap: None,
        streaks: None,
        run_stats: None,
        pr_recency: None,
        plan_replan: None,
        plan_adaptive: None,
        readiness: None,
        goals: None,
        turn_cue: None,
        route_simplify: None,
        auto_effort: None,
        route_elev: None,
        race_day: None,
        track_thinning: 1,
        pages_mask: u32::MAX,
    }
}

fn sample_fix() -> Fix {
    Fix {
        lat_deg: 40.1,
        lon_deg: -105.2,
        speed_mps: 2.6,
        course_deg: Some(90.0),
        sats: 8,
        alt_m: Some(1650.0),
        time_of_day: Some(12 * 3600),
        uptime_s: 100,
    }
}

// Draw the face rows + hero the way the ui task does, so the preview shows
// the widget over its real text underlay.
fn draw_face(fb: &mut Framebuffer, page: Page, snap: Option<&Snapshot>, hr: Option<u16>) {
    let fix = sample_fix();
    let rows = face::page_rows(
        page,
        Some(&fix),
        hr,
        snap,
        None,
        NavView::NoCourse,
        None,
        100,
        false,
        GnssMode::default(),
        IdleView::Home,
        None,
    );
    let field_grid = page == Page::Dashboard && snap.is_some();
    for (r, row) in rows.iter().enumerate() {
        if field_grid {
            widgets::ruled_dashboard_row(fb, r, row);
        } else {
            fb.draw_text_row(r, row);
        }
    }
    if let Some(hero) = face::page_hero(page, hr, snap, None) {
        if matches!(page, Page::Distance | Page::Pace) {
            fb.draw_bignum_hero(0, &hero);
        } else {
            fb.draw_text_2x(0, 0, &hero);
        }
    }
}

fn show(name: &str, fb: &Framebuffer) {
    println!("\n== {name} ==\n{}", ascii_dump(fb));
    assert!(
        (0..HEIGHT).any(|y| (0..WIDTH).any(|x| fb.pixel(x, y))),
        "{name} rendered a blank panel"
    );
}

#[test]
fn preview_idle_home_face_with_clock_hero() {
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Dashboard, None, Some(132));
    widgets::draw_idle_signal(&mut fb, Some(&sample_fix()), 100, face::STALE_AFTER_S);
    widgets::draw_idle_battery(&mut fb, Some(87), false);
    // The ui task draws the generated numeral clock into the band the home
    // face leaves blank — replicate it so the preview shows the real layout.
    let clock = face::home_clock_text(Some(&sample_fix()), 100, None);
    fb.draw_bignum_band(
        face::CLOCK_HERO_TOP_ROW * (HEIGHT / sharp_mip::TEXT_ROWS),
        &clock,
    );
    show("idle home: clock hero + battery + GPS signal meter", &fb);
}

#[test]
fn preview_idle_diagnostics_face() {
    let mut fb = Framebuffer::new();
    let mut rows = face::page_rows(
        Page::Dashboard,
        Some(&sample_fix()),
        Some(132),
        None,
        None,
        NavView::NoCourse,
        None,
        100,
        false,
        GnssMode::default(),
        IdleView::Diagnostics,
        None,
    );
    face::apply_battery_row(&mut rows, IdleView::Diagnostics, Some(12));
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    widgets::draw_idle_signal(&mut fb, Some(&sample_fix()), 100, face::STALE_AFTER_S);
    // A low cell, so the preview shows the icon's exclamation frame beside
    // the numeric BAT row.
    widgets::draw_idle_battery(&mut fb, Some(12), false);
    show(
        "idle diagnostics: bench acquisition view + low battery",
        &fb,
    );
}

#[test]
fn preview_run_dashboard() {
    use sharp_mip::Icon;
    use watch_core::face::FaceIcon;

    let snap = base_snapshot();
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Dashboard, Some(&snap), Some(150));
    // The gutter icons, mapped the way the ui task's driver_icon does.
    let fix = sample_fix();
    let icons = face::page_icons(
        Page::Dashboard,
        Some(&fix),
        Some(150),
        Some(&snap),
        100,
        false,
        GnssMode::default(),
    );
    for (row, icon) in icons.iter().enumerate() {
        if let Some(icon) = icon {
            fb.draw_icon(
                0,
                row,
                match icon {
                    FaceIcon::Stopwatch => Icon::Stopwatch,
                    FaceIcon::Footsteps => Icon::Footsteps,
                    FaceIcon::Heart => Icon::Heart,
                    FaceIcon::HeartSmall => Icon::HeartSmall,
                    FaceIcon::Mountain => Icon::Mountain,
                    FaceIcon::Vert => Icon::Vert,
                    FaceIcon::Satellite => Icon::Satellite,
                    FaceIcon::SatSearch0 => Icon::SatSearch0,
                    FaceIcon::SatSearch1 => Icon::SatSearch1,
                },
            );
        }
    }
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Dashboard, u32::MAX),
    );
    show("run dashboard: hero + field grid + NOW/GAP pairing", &fb);
}

#[test]
fn preview_inverse_alert_banner() {
    // An on-run alert takes the hero band over as an inverse-video banner —
    // light text knocked out of a solid band, the loudest treatment the 1-bit
    // panel gives (fg/bg swap at draw time; the panel has no polarity of its
    // own).
    let snap = base_snapshot();
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Dashboard, Some(&snap), Some(150));
    fb.draw_banner_2x(0, "! DRINK");
    show("alert banner: inverse video over the hero band", &fb);
}

#[test]
fn preview_distance_and_pace_bignum_heroes() {
    // The single-metric glances: big integers / minutes with the medium face
    // carrying the decimals / seconds on the shared baseline.
    let snap = base_snapshot();
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Distance, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Distance, u32::MAX),
    );
    show("distance glance: 32.40 in the numeral faces", &fb);

    let mut fb2 = Framebuffer::new();
    draw_face(&mut fb2, Page::Pace, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb2,
        watch_core::statusbar::page_indicator(Page::Pace, u32::MAX),
    );
    show("pace glance: 6:20 in the numeral faces", &fb2);
}

#[test]
fn preview_pacer_page() {
    use watch_core::pacer::{PaceVerdict, PacerGoal, PacerStatus};
    let mut snap = base_snapshot();
    snap.pacer = Some(PacerStatus {
        goal: PacerGoal {
            distance_m: 42_195,
            time_s: 4 * 3600,
        },
        ahead_m: 120.0,
        ahead_s: 75,
        projected_finish_s: Some(3 * 3600 + 55 * 60),
        verdict: PaceVerdict::Ahead,
        finished: false,
        terrain_aware: false,
    });
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Pacer, Some(&snap), Some(150));
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Pacer, u32::MAX),
    );
    widgets::draw_pacer_overlay(&mut fb, &snap);
    show("pacer: +75s ahead centre-bar", &fb);
}

#[test]
fn preview_zones_page() {
    let mut snap = base_snapshot();
    snap.zone_time_s = [1800, 2400, 1500, 600, 120];
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Zones, Some(&snap), Some(150));
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Zones, u32::MAX),
    );
    widgets::draw_zones_overlay(&mut fb, &snap, Some(150));
    show("zones: per-zone bars + live-zone frame", &fb);
}

#[test]
fn preview_splits_page() {
    let mut snap = base_snapshot();
    snap.pace_bucket_m = [800.0, 3200.0, 6400.0, 4100.0, 1500.0, 300.0];
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Splits, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Splits, u32::MAX),
    );
    widgets::draw_splits_overlay(&mut fb, &snap);
    show("splits: pace-distribution histogram", &fb);
}

#[test]
fn preview_gear_and_fuel_pages() {
    let mut gear_snap = base_snapshot();
    gear_snap.gear = Some(watch_core::gear_wear::gear_wear(
        Some(920_000.0),
        Some(800_000.0),
    ));
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::GearWear, Some(&gear_snap), None);
    widgets::draw_gear_overlay(&mut fb, &gear_snap);
    show("gear: worn shoe bar + overdue block", &fb);

    let mut fuel_snap = base_snapshot();
    fuel_snap.fuel = Some(FuelView {
        carry: Some(FuelCarryView {
            carbs_g: 60.0,
            fluid_ml: 500.0,
        }),
        total_carbs_g: 240.0,
        total_fluid_ml: 2000.0,
    });
    let mut fb2 = Framebuffer::new();
    draw_face(&mut fb2, Page::Fuel, Some(&fuel_snap), None);
    widgets::draw_fuel_overlay(&mut fb2, &fuel_snap);
    show("fuel: carry-load bar", &fb2);
}

#[test]
fn preview_page_grid() {
    use watch_core::page_grid;

    // The full 32-page grid with the cursor a row-down + a tap from home.
    let mut fb = Framebuffer::new();
    let mask = u32::MAX;
    let mut grid = page_grid::PageGrid::open(Page::Dashboard, mask);
    grid.row_down(mask);
    grid.tap(mask);
    for (row, text) in page_grid::grid_rows(mask).iter().enumerate() {
        fb.draw_text_row(row, text);
    }
    if let Some(cell) = page_grid::grid_cell(mask, grid.cursor()) {
        widgets::draw_grid_cursor(&mut fb, cell);
    }
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(grid.cursor(), mask),
    );
    show("page grid: full mask, cursor on row 2", &fb);

    // A realistically filtered mask — the grid packs to two rows.
    let mask = Page::Dashboard.bit()
        | Page::Pace.bit()
        | Page::Zones.bit()
        | Page::Nav.bit()
        | Page::CutoffEta.bit()
        | Page::Roadbook.bit()
        | Page::Fuel.bit()
        | Page::BackToStart.bit();
    let mut fb2 = Framebuffer::new();
    let grid = page_grid::PageGrid::open(Page::Roadbook, mask);
    for (row, text) in page_grid::grid_rows(mask).iter().enumerate() {
        fb2.draw_text_row(row, text);
    }
    if let Some(cell) = page_grid::grid_cell(mask, grid.cursor()) {
        widgets::draw_grid_cursor(&mut fb2, cell);
    }
    show("page grid: filtered mask, cursor on ROAD", &fb2);
}

#[test]
fn preview_elevation_profile_page() {
    // The recorder's banked altitude series over its own glance page, so the
    // sparkline is shown against the vert-totals context row it sits under.
    let elevation: [i32; 18] = [
        1600, 1612, 1648, 1705, 1782, 1851, 1884, 1902, 1868, 1801, 1744, 1712, 1690, 1701, 1748,
        1690, 1632, 1604,
    ];
    let mut snap = base_snapshot();
    let mut view = watch_core::record::ElevProfileView::empty();
    view.samples[..elevation.len()].copy_from_slice(&elevation);
    view.len = elevation.len();
    snap.elev_profile = view;

    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::ElevationProfile, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::ElevationProfile, u32::MAX),
    );
    widgets::draw_elev_profile_overlay(&mut fb, &snap);
    show("elevation profile: banked altitude sparkline", &fb);
}

#[test]
fn preview_mini_profile() {
    // A synthetic climb-then-descend altitude series — the shape a future glance
    // page would show for a route's elevation profile, auto-scaled to the cell.
    let elevation: [i32; 14] = [
        1600, 1615, 1650, 1710, 1790, 1855, 1880, 1860, 1795, 1720, 1680, 1650, 1625, 1605,
    ];
    let mut fb = Framebuffer::new();
    let (x, y, w, h) = (6, 20, WIDTH - 12, 100);
    fb.stroke_rect(x - 2, y - 2, w + 4, h + 4, true);
    widgets::draw_mini_profile(
        &mut fb,
        &widgets::MiniProfile {
            x,
            y,
            w,
            h,
            samples: &elevation,
        },
    );
    show("mini-profile: elevation climb + descent", &fb);
}

/// A course whose bounding box is far larger than one auto-zoom window — the
/// shape every real ultra course has, so the panel windows around the runner
/// and most of the polyline falls outside the panel rows.
fn long_course() -> watch_core::course::Course {
    use watch_core::course::CoursePoint;
    let pt = |lat_deg, lon_deg| CoursePoint { lat_deg, lon_deg };
    watch_core::course::Course::from_points(&[
        pt(40.080, -105.215),
        pt(40.094, -105.204),
        pt(40.100, -105.198),
        pt(40.104, -105.186),
        pt(40.118, -105.180),
    ])
    .unwrap()
}

fn draw_nav_page(fb: &mut Framebuffer, nav: NavView, alert: Option<&str>) {
    let course = long_course();
    let snap = base_snapshot();
    let fix = sample_fix();
    let rows = face::page_rows(
        Page::Nav,
        Some(&fix),
        None,
        Some(&snap),
        None,
        nav,
        None,
        100,
        false,
        GnssMode::default(),
        IdleView::Home,
        None,
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    widgets::draw_page_indicator(
        fb,
        watch_core::statusbar::page_indicator(Page::Nav, u32::MAX),
    );
    let panel = watch_core::nav_map::nav_panel(
        &course,
        Some((fix.lat_deg, fix.lon_deg)),
        widgets::NAV_PANEL_GEOM,
    );
    widgets::draw_nav_panel(fb, &course, &panel, alert);
}

#[test]
fn preview_nav_map_panel() {
    // An auto-zoomed long course: the window keeps the runner mid-panel and the
    // legs running off it are clipped at the panel rows, so the NAV title row
    // above and the along-course / GPS rows below stay legible.
    let status = watch_core::course::NavStatus {
        along_m: 18_400.0,
        off_m: 12.0,
        alerting: false,
        next_turn: None,
    };
    let mut fb = Framebuffer::new();
    draw_nav_page(&mut fb, NavView::Status(status), None);
    show("nav: auto-zoomed course + position marker", &fb);

    let off_course = NavView::Status(watch_core::course::NavStatus {
        off_m: 180.0,
        alerting: true,
        ..status
    });
    let mut fb2 = Framebuffer::new();
    draw_nav_page(
        &mut fb2,
        off_course,
        face::nav_alert_row(off_course).as_deref(),
    );
    show("nav: off-course banner over the breadcrumb", &fb2);
}

/// A trackback view walked north-east away from its start, one accepted fix a
/// second — a crumb with a real shape, a bearing back to the start and a fresh
/// heading, so the preview shows the map and the arrow together.
fn sample_trackback() -> watch_core::trackback::TrackbackView {
    use watch_core::record::METRES_PER_DEGREE_LAT;
    let (lat0, lon0): (f64, f64) = (40.1, -105.2);
    let lon_per_m = 1.0 / (METRES_PER_DEGREE_LAT * lat0.to_radians().cos());
    let mut tb = watch_core::trackback::Trackback::new();
    for i in 0..=60u32 {
        let along = i as f64 * 12.0;
        // An outbound east leg that turns north halfway, so the crumb is a dog-leg.
        let (e, n) = if along < 360.0 {
            (along, 0.0)
        } else {
            (360.0, along - 360.0)
        };
        tb.on_point(lat0 + n / METRES_PER_DEGREE_LAT, lon0 + e * lon_per_m, i);
    }
    tb.view()
}

#[test]
fn preview_back_to_start_page() {
    let snap = base_snapshot();
    let view = sample_trackback();
    let mut fb = Framebuffer::new();
    let rows = face::page_rows(
        Page::BackToStart,
        Some(&sample_fix()),
        None,
        Some(&snap),
        None,
        NavView::NoCourse,
        Some(&view),
        60,
        false,
        GnssMode::default(),
        IdleView::Home,
        None,
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    if let Some(hero) = face::page_hero(Page::BackToStart, None, Some(&snap), Some(&view)) {
        fb.draw_text_2x(0, 0, &hero);
    }
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::BackToStart, u32::MAX),
    );
    widgets::draw_trackback_overlay(&mut fb, &view, 60);
    show("back to start: breadcrumb map + relative arrow", &fb);
}

#[test]
fn preview_dial_and_compass() {
    // The navigation-glance shape a future page would show: a fuel-fraction ring
    // dial with a trackback bearing-to-start arrow nested inside it.
    let mut fb = Framebuffer::new();
    let (cx, cy) = (WIDTH / 2, HEIGHT / 2);
    widgets::draw_dial(&mut fb, cx, cy, 56, 12, 0.66);
    widgets::draw_compass(&mut fb, cx, cy, 34, 300);
    show("dial + compass: fuel ring + bearing-to-start", &fb);
}
