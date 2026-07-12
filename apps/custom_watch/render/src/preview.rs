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
use watch_core::face::{self, NavView};
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
        readiness: None,
        goals: None,
        turn_cue: None,
        route_simplify: None,
        auto_effort: None,
        route_elev: None,
        race_day: None,
        track_full: false,
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

// Draw the face rows + 2x hero the way the ui task does, so the preview shows
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
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    if let Some(hero) = face::page_hero(page, hr, snap, None) {
        fb.draw_text_2x(0, 0, &hero);
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
fn preview_idle_face_with_signal_meter() {
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Dashboard, None, Some(132));
    widgets::draw_idle_signal(&mut fb, Some(&sample_fix()), 100, face::STALE_AFTER_S);
    show("idle: brand + GPS signal meter", &fb);
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
    });
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Pacer, Some(&snap), Some(150));
    widgets::draw_page_indicator(&mut fb, watch_core::statusbar::page_indicator(Page::Pacer));
    widgets::draw_pacer_overlay(&mut fb, &snap);
    show("pacer: +75s ahead centre-bar", &fb);
}

#[test]
fn preview_zones_page() {
    let mut snap = base_snapshot();
    snap.zone_time_s = [1800, 2400, 1500, 600, 120];
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Zones, Some(&snap), Some(150));
    widgets::draw_page_indicator(&mut fb, watch_core::statusbar::page_indicator(Page::Zones));
    widgets::draw_zones_overlay(&mut fb, &snap, Some(150));
    show("zones: per-zone bars + live-zone frame", &fb);
}

#[test]
fn preview_splits_page() {
    let mut snap = base_snapshot();
    snap.pace_bucket_m = [800.0, 3200.0, 6400.0, 4100.0, 1500.0, 300.0];
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Splits, Some(&snap), None);
    widgets::draw_page_indicator(&mut fb, watch_core::statusbar::page_indicator(Page::Splits));
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
