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
use watch_core::record::{
    FuelBasis, FuelCarryView, FuelView, RecordState, Snapshot, PACE_BUCKET_COUNT,
};
use watch_core::ui_frame::{self, HeroBand, HeroFrame};

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
        signal_lost: false,
        backyard: None,
        distance_m: 32_400.0,
        elapsed_s: 3 * 3600 + 12 * 60 + 5,
        moving_s: 3 * 3600,
        current_speed_mps: 2.6,
        avg_pace_s_per_km: Some(6 * 60 + 20),
        current_pace_s_per_km: Some(6 * 60 + 5),
        gap_s_per_km: Some(5 * 60 + 55),
        gap_held: false,
        lap: 5,
        lap_distance_m: 400.0,
        lap_elapsed_s: 150,
        last_lap: None,
        pacer: None,
        zone_cutoffs: zone_cutoffs_from_max_hr(DEFAULT_MAX_HR_BPM),
        zone_ceiling: None,
        hr_source: None,
        pace_band: None,
        zone_time_s: [0; 5],
        cutoffs_loaded: false,
        cutoff: None,
        sleep: None,
        race_prediction: None,
        pace_bucket_m: [0.0; PACE_BUCKET_COUNT],
        training_stress: None,
        training_stress_trimp: false,
        load_trend: None,
        band: None,
        gear: None,
        roadbook_loaded: false,
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
        guided_run: None,
        workout: None,
        readiness: None,
        goals: None,
        turn_cue: None,
        nav_off_course: None,
        route_simplify: None,
        auto_effort: None,
        route_elev: None,
        route_position_permille: None,
        race_day: None,
        race_phase: None,
        climb: Default::default(),
        waypoint: None,
        waypoint_count: 0,
        waypoint_mark_seq: 0,
        waypoint_refuse_seq: 0,
        run_lost_seq: 0,
        push_outcome: watch_core::ble_sync::PushOutcome::DEFAULT,
        timer: None,
        storm: None,
        auto_lap: watch_core::auto_lap::AUTO_LAP_DEFAULT,
        track_thinning: 1,
        pages_mask: u64::MAX,
        hide_empty_pages: true,
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
        date: Some(watch_core::daylight::Date {
            year: 2026,
            month: 7,
            day: 8,
        }),
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
        None,
        None,
    );
    let layout = ui_frame::FrameLayout {
        page,
        run_view: snap.is_some(),
        idle_view: IdleView::Home,
        panel_active: false,
        panel_repaint: false,
    };
    for (r, row) in rows.iter().enumerate() {
        match ui_frame::row_paint(r, layout) {
            ui_frame::RowPaint::Skip => {}
            ui_frame::RowPaint::Ruled => widgets::ruled_dashboard_row(fb, r, row),
            ui_frame::RowPaint::Chrome => fb.draw_text_row_small(r, row),
            ui_frame::RowPaint::Text => fb.draw_text_row(r, row),
        }
    }
    draw_hero(
        fb,
        page,
        face::page_hero(page, Some(&fix), hr, snap, None, 100, None).as_deref(),
        face::page_hero_unit(page, snap, None),
    );
}

// Through `ui_frame::hero_band`, not a second copy of the face test the ui task
// runs — the preview's whole value is being the same composition. Same order as
// the ui task: unit before the band (it is part of the tall face's width
// budget), hero, then the unit on the number's baseline.
fn draw_hero(fb: &mut Framebuffer, page: Page, hero: Option<&str>, unit: Option<&'static str>) {
    let unit = hero.filter(|h| ui_frame::hero_has_value(h)).and(unit);
    let band = ui_frame::hero_band(HeroFrame {
        alert: false,
        rezero_banner: false,
        hero: hero.is_some(),
        numeral: hero.is_some_and(ui_frame::numeral_hero),
        fits_tall: hero.is_some_and(|h| ui_frame::tall_hero_fits(h, unit)),
        stop_pending: false,
        page,
    });
    match band {
        HeroBand::BigNumHero => fb.draw_bignum_hero(0, hero.unwrap()),
        HeroBand::MedNumHero => fb.draw_bignum_med_hero(0, hero.unwrap()),
        HeroBand::TextHero => fb.draw_text_2x(0, 0, hero.unwrap()),
        HeroBand::AlertBanner | HeroBand::RezeroBanner | HeroBand::None => {}
    }
    if let Some(((col, row), u)) = hero
        .zip(unit)
        .and_then(|(h, u)| ui_frame::hero_unit_cell(band, h, u).map(|cell| (cell, u)))
    {
        fb.draw_text(col, row, u);
    }
}

/// The numeral-face glyph set is decided in `watch_core` (the face choice is a
/// frame decision) and rasterised in `sharp_mip` (the pixels are a driver
/// asset). This crate is the only one that sees both, so it is where the two
/// are pinned: a regeneration that adds a glyph fails here until the decision
/// side learns about it. That is how the `+` landed — the table grew, this
/// assertion caught it, and the signed Pacer / cut-off heroes then promoted out
/// of the text font on the glyph rule alone.
#[test]
fn the_numeral_glyph_set_matches_the_generated_tables() {
    assert_eq!(
        watch_core::ui_frame::NUMERAL_GLYPHS,
        sharp_mip::bignum::BIGNUM_GLYPHS.as_slice()
    );
}

/// The other half of that pin. `ui_frame` budgets the three-row hero in text
/// cells so it need not know the panel's pixel width, which only works while a
/// cell really is one glyph's width divided by the font cell — the same split
/// this crate can see both sides of. A regenerated face at a different cell
/// size would otherwise let an over-wide hero back through the fit rule and
/// truncate on the panel.
#[test]
fn the_numeral_cell_widths_match_the_generated_faces() {
    let cell_w = WIDTH / sharp_mip::TEXT_COLS;
    assert_eq!(
        watch_core::ui_frame::NUMERAL_CELLS,
        sharp_mip::bignum::BIGNUM_WIDTH / cell_w
    );
    assert_eq!(
        watch_core::ui_frame::NUMERAL_MED_CELLS,
        sharp_mip::bignum::BIGNUM_MED_WIDTH / cell_w
    );
    assert_eq!(watch_core::face::COLS, sharp_mip::TEXT_COLS);
}

// With `WATCH_PREVIEW_DIR` set, each preview also lands as a 1:1 P6 PPM named
// after its caption — the same format the sim's DumpFrame writes, so the host
// compositions are viewable (and diffable) without Renode. See
// `bin/watch-preview.sh` for the wrapper that converts + contact-sheets them.
fn dump_ppm(name: &str, fb: &Framebuffer) {
    let Ok(dir) = std::env::var("WATCH_PREVIEW_DIR") else {
        return;
    };
    let slug: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    let mut bytes = format!("P6\n{WIDTH} {HEIGHT}\n255\n").into_bytes();
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let v = if fb.pixel(x, y) { 0u8 } else { 255u8 };
            bytes.extend_from_slice(&[v, v, v]);
        }
    }
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        std::path::Path::new(&dir).join(format!("{slug}.ppm")),
        bytes,
    )
    .unwrap();
}

fn show(name: &str, fb: &Framebuffer) {
    println!("\n== {name} ==\n{}", ascii_dump(fb));
    dump_ppm(name, fb);
    assert!(
        (0..HEIGHT).any(|y| (0..WIDTH).any(|x| fb.pixel(x, y))),
        "{name} rendered a blank panel"
    );
}

/// The four-pixel indicator band at 1:1, undownsampled — [`ascii_dump`]'s 2x
/// halving hides exactly the single-pixel seams and edge gaps this band is
/// made of, so it cannot be used to judge the indicator.
fn show_indicator_band(name: &str, fb: &Framebuffer) {
    let mut out = String::new();
    for y in 0..4 {
        for x in 0..WIDTH {
            out.push(if fb.pixel(x, y) { '#' } else { '.' });
        }
        out.push('\n');
    }
    println!("\n== {name} ==\n{out}");
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
        None,
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
        watch_core::statusbar::page_indicator(Page::Dashboard, u64::MAX),
    );
    show("run dashboard: hero + field grid + NOW/GAP pairing", &fb);
}

#[test]
fn preview_run_view_low_battery_marker() {
    // The only battery signal a run view has: a standing right-anchored tag on
    // the hero band's blank lower row, clear of the elapsed digits.
    use watch_core::alerts::FuelOverdue;
    let snap = base_snapshot();
    let mut fb = Framebuffer::new();
    let mut rows = face::page_rows(
        Page::Dashboard,
        Some(&sample_fix()),
        Some(150),
        Some(&snap),
        None,
        NavView::NoCourse,
        None,
        100,
        false,
        GnssMode::default(),
        IdleView::Home,
        None,
        None,
        None,
    );
    let hero = face::page_hero(
        Page::Dashboard,
        None,
        Some(150),
        Some(&snap),
        None,
        100,
        None,
    );
    face::apply_run_marker(
        &mut rows,
        Page::Dashboard,
        FuelOverdue::None,
        Some(12),
        ui_frame::hero_row_cells(
            ui_frame::HeroBand::MedNumHero,
            hero.as_deref().unwrap_or(""),
            None,
        ),
    );
    for (r, row) in rows.iter().enumerate() {
        widgets::ruled_dashboard_row(&mut fb, r, row);
    }
    draw_hero(
        &mut fb,
        Page::Dashboard,
        hero.as_deref(),
        face::page_hero_unit(Page::Dashboard, Some(&snap), None),
    );
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Dashboard, u64::MAX),
    );
    show(
        "run dashboard: standing 12% battery marker beside the hero",
        &fb,
    );
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
        watch_core::statusbar::page_indicator(Page::Distance, u64::MAX),
    );
    show("distance glance: 32.40 in the numeral faces", &fb);

    let mut fb2 = Framebuffer::new();
    draw_face(&mut fb2, Page::Pace, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb2,
        watch_core::statusbar::page_indicator(Page::Pace, u64::MAX),
    );
    show("pace glance: 6:20 in the numeral faces", &fb2);
}

/// The § 364 composed screens — the one family the preview sheet never showed,
/// and the one whose lead slot was drawn in the wrong face.
///
/// `slot_placements` seats slot 0 in the 32x48 band at row 0 and labels it on
/// row 3, exactly as a tall glance page does, but `hero_band` read that band off
/// `face::body_top_row`, which a composed screen declared as 0 — so a Duo drew
/// its LEAD value at half the size of the value beneath it. Rendering both
/// layouts here is what makes that visible on the host rung rather than only
/// under Renode, where a captured frame can arrive with a banner over the band.
#[test]
fn preview_composed_screens() {
    use watch_core::screens::{Layout, Screen, Screens};
    let snap = base_snapshot();
    let screens = Screens::from_slice(&[
        Screen::new(
            Layout::Duo,
            &[
                watch_core::face::Metric::Distance,
                watch_core::face::Metric::Elapsed,
            ],
        )
        .unwrap(),
        Screen::new(
            Layout::Trio,
            &[
                watch_core::face::Metric::AvgPace,
                watch_core::face::Metric::HeartRate,
                watch_core::face::Metric::Distance,
            ],
        )
        .unwrap(),
    ])
    .unwrap();

    for (page, name) in [
        (
            Page::Screen1,
            "composed screen: a Duo, both values in the 32x48 face",
        ),
        (
            Page::Screen2,
            "composed screen: a Trio, the tall lead over two medium rows",
        ),
    ] {
        let mut fb = Framebuffer::new();
        draw_screen(&mut fb, page, &snap, Some(150), &screens);
        show(name, &fb);
    }
}

// The composed-screen half of the ui task: slot 0 through the ordinary hero
// pipeline, the slots under it at the placement's own band.
fn draw_screen(
    fb: &mut Framebuffer,
    page: Page,
    snap: &Snapshot,
    hr: Option<u16>,
    screens: &watch_core::screens::Screens,
) {
    let fix = sample_fix();
    let rows = face::page_rows(
        page,
        Some(&fix),
        hr,
        Some(snap),
        None,
        NavView::NoCourse,
        None,
        100,
        false,
        GnssMode::default(),
        IdleView::Home,
        None,
        None,
        Some(screens),
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    let render = face::screen_page_slots(
        page,
        Some(screens),
        Some(&fix),
        hr,
        Some(snap),
        None,
        100,
        None,
    )
    .expect("a composed screen renders");
    let lead = &render.slots[0];
    draw_hero(fb, page, Some(lead.value.as_str()), lead.unit);
    for (slot, at) in render
        .slots
        .iter()
        .zip(ui_frame::slot_placements(render.layout))
        .skip(1)
    {
        let y = at.value_row * (HEIGHT / sharp_mip::TEXT_ROWS);
        match ui_frame::slot_band(at.band, &slot.value) {
            HeroBand::BigNumHero => fb.draw_bignum_hero(y, &slot.value),
            HeroBand::MedNumHero => fb.draw_bignum_med_hero(y, &slot.value),
            _ => fb.draw_text_2x(0, at.value_row, &slot.value),
        }
    }
}

#[test]
fn preview_lap_page_tall_numeral_hero() {
    // The lap page gave row 2 up to the hero band, so its split renders in the
    // three-row treatment with the lap number + state tag on row 3.
    let snap = base_snapshot();
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Lap, Some(&snap), Some(132));
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Lap, u64::MAX),
    );
    show("lap glance: 2:30 in the tall numeral hero", &fb);
}

#[test]
fn preview_a_hero_too_wide_for_the_tall_face() {
    // The fallback the fit rule buys: a multi-day guided run's remaining time
    // needs 24 of the panel's 21 cells at the tall size, so it drops to the
    // medium face and shows the number whole rather than losing its last digit
    // off the right edge.
    let mut snap = base_snapshot();
    snap.guided_run = Some(watch_core::record::GuidedRunView {
        cue_index: 12,
        cue_count: 40,
        next_cue_in_s: Some(300),
        duration_s: 200 * 3600,
        remaining_s: 100 * 3600 + 5 * 60 + 30,
    });
    let hero = face::page_hero(Page::GuidedRun, None, None, Some(&snap), None, 100, None).unwrap();
    assert!(!ui_frame::tall_hero_fits(&hero, None), "{hero}");
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::GuidedRun, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::GuidedRun, u64::MAX),
    );
    show("guided run: 100:05:30 falls back to the medium face", &fb);
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
        watch_core::statusbar::page_indicator(Page::Pacer, u64::MAX),
    );
    widgets::draw_pacer_overlay(&mut fb, &snap);
    show("pacer: +75s ahead centre-bar", &fb);
}

#[test]
fn preview_cutoff_eta_page() {
    // The other signed hero: margin to the next cut-off, `+` slack / `-` over.
    // Shown at an hours-wide margin, the widest a signed hero realistically
    // gets — 8 glyphs of the 16 px medium cell is 128 px of a 168 px panel.
    use watch_core::cutoff_eta::{CutoffEta, CutoffEtaStatus};
    let mut snap = base_snapshot();
    snap.cutoffs_loaded = true;
    snap.cutoff = Some(CutoffEta {
        has_cutoff: true,
        distance_to_m: 8_400.0,
        projected_arrival_elapsed_s: Some(4 * 3600 + 10 * 60),
        margin_s: Some(3930),
        required_pace_s_per_km: Some(7.0 * 60.0 + 30.0),
        limit_passed: false,
        status: CutoffEtaStatus::On,
    });
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::CutoffEta, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::CutoffEta, u64::MAX),
    );
    show("cut-off eta: +1:05:30 margin in the tall numeral hero", &fb);
}

#[test]
fn preview_sleep_station_page() {
    // The same projection one page along: what that margin buys in sleep, and
    // the row that stops the number being read as an alarm clock.
    use watch_core::sleep_station::SleepBudget;
    let mut snap = base_snapshot();
    snap.cutoffs_loaded = true;
    snap.sleep = Some(SleepBudget {
        status: watch_core::sleep_station::SleepStatus::Budget,
        budget_s: 35 * 60,
        reserve_s: 1_800,
        margin_s: Some(3_930),
        pace_s_per_km: Some(7.0 * 60.0 + 30.0),
        distance_to_m: 8_400.0,
        limit_passed: false,
    });
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::SleepStation, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::SleepStation, u64::MAX),
    );
    show("sleep station: 35 min of nap the race can afford", &fb);
}

#[test]
fn preview_zones_page() {
    let mut snap = base_snapshot();
    snap.zone_time_s = [1800, 2400, 1500, 600, 120];
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Zones, Some(&snap), Some(150));
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Zones, u64::MAX),
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
        watch_core::statusbar::page_indicator(Page::Splits, u64::MAX),
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
        basis: FuelBasis::NextAid {
            total: FuelCarryView {
                carbs_g: 240.0,
                fluid_ml: 2000.0,
            },
        },
    });
    let mut fb2 = Framebuffer::new();
    draw_face(&mut fb2, Page::Fuel, Some(&fuel_snap), None);
    widgets::draw_fuel_overlay(&mut fb2, &fuel_snap);
    show("fuel: carry-load bar", &fb2);
}

#[test]
fn preview_page_grid() {
    use watch_core::page_grid;

    // The full grid with the cursor a row-down + a tap from home.
    let mut fb = Framebuffer::new();
    let mask = u64::MAX;
    let mut grid = page_grid::PageGrid::open(Page::Dashboard, mask);
    grid.row_down(mask);
    grid.tap(mask);
    for (row, text) in page_grid::grid_rows(mask, grid.cursor()).iter().enumerate() {
        fb.draw_text_row(row, text);
    }
    if let Some(cell) = page_grid::grid_cell(mask, grid.cursor(), grid.cursor()) {
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
    for (row, text) in page_grid::grid_rows(mask, grid.cursor()).iter().enumerate() {
        fb2.draw_text_row(row, text);
    }
    if let Some(cell) = page_grid::grid_cell(mask, grid.cursor(), grid.cursor()) {
        widgets::draw_grid_cursor(&mut fb2, cell);
    }
    show("page grid: filtered mask, cursor on ROAD", &fb2);
}

#[test]
fn preview_climb_page() {
    // Mid-climb with a named crest: the crest block, the banked block, and
    // the § 430 crest thermometer filled to the banked share of the height.
    use watch_core::climb::{ActiveClimb, ClimbView, CrestAhead};
    let mut snap = base_snapshot();
    snap.climb = ClimbView {
        active: Some(ActiveClimb {
            gain_m: 220.0,
            distance_m: 1_400.0,
            avg_grade_pct: 15.7,
        }),
        ahead: Some(CrestAhead {
            distance_m: 600.0,
            gain_m: 110.0,
            avg_grade_pct: 18.3,
        }),
    };
    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::Climb, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::Climb, u64::MAX),
    );
    widgets::draw_climb_overlay(&mut fb, &snap);
    show("climb: crest ahead + banked-height thermometer", &fb);
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
        watch_core::statusbar::page_indicator(Page::ElevationProfile, u64::MAX),
    );
    widgets::draw_elev_profile_overlay(&mut fb, &snap);
    show("elevation profile: banked altitude sparkline", &fb);
}

#[test]
fn preview_route_elev_page() {
    // The pushed course's climb profile with the runner marked a third of the
    // way along it — the RouteElev glance.
    let profile: [i16; 24] = [
        1650, 1668, 1704, 1760, 1840, 1930, 2010, 2060, 2040, 1980, 1900, 1850, 1830, 1870, 1950,
        2030, 2080, 2040, 1960, 1870, 1790, 1720, 1680, 1655,
    ];
    let mut snap = base_snapshot();
    let mut view = watch_core::record::RouteElevView {
        gain_m: 690,
        loss_m: 685,
        points: 128,
        total_m: 42_195,
        samples: [0; watch_core::record::COURSE_PROFILE_CAP],
        len: profile.len(),
    };
    view.samples[..profile.len()].copy_from_slice(&profile);
    snap.route_elev = Some(view);
    snap.route_position_permille = Some(333);

    let mut fb = Framebuffer::new();
    draw_face(&mut fb, Page::RouteElev, Some(&snap), None);
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::RouteElev, u64::MAX),
    );
    widgets::draw_route_elev_overlay(&mut fb, &snap);
    show("route elevation: course profile + position marker", &fb);
}

#[test]
fn preview_mini_profile() {
    // A synthetic climb-then-descend altitude series — the widget the run's
    // ElevationProfile and the course's RouteElev pages both plot with,
    // auto-scaled to the cell.
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
        None,
        None,
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    widgets::draw_page_indicator(
        fb,
        watch_core::statusbar::page_indicator(Page::Nav, u64::MAX),
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
        back_to_course_deg: None,
    };
    let mut fb = Framebuffer::new();
    draw_nav_page(&mut fb, NavView::Status(status), None);
    show("nav: auto-zoomed course + position marker", &fb);

    let off_course = NavView::Status(watch_core::course::NavStatus {
        off_m: 180.0,
        alerting: true,
        back_to_course_deg: Some(300.0),
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
        None,
        None,
    );
    for (r, row) in rows.iter().enumerate() {
        fb.draw_text_row(r, row);
    }
    draw_hero(
        &mut fb,
        Page::BackToStart,
        face::page_hero(
            Page::BackToStart,
            None,
            None,
            Some(&snap),
            Some(&view),
            100,
            None,
        )
        .as_deref(),
        face::page_hero_unit(Page::BackToStart, Some(&snap), Some(&view)),
    );
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::BackToStart, u64::MAX),
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

fn indicator_thumb_row(fb: &Framebuffer) -> String {
    (0..WIDTH)
        .map(|x| if fb.pixel(x, 0) { '#' } else { '.' })
        .collect()
}

fn preview_indicator_over_mask(label: &str, mask: u64) {
    let total = watch_core::statusbar::page_indicator(Page::Dashboard, mask).total;
    println!("\n== page indicator: {label} ({total} enabled pages), thumb row at 1:1 ==");
    let mut union = [false; WIDTH];
    let mut page = Page::Dashboard;
    for _ in 0..total {
        let mut fb = Framebuffer::new();
        widgets::draw_page_indicator(&mut fb, watch_core::statusbar::page_indicator(page, mask));
        println!("{:>4} {}", page.code(), indicator_thumb_row(&fb));
        for (x, seen) in union.iter_mut().enumerate() {
            *seen |= fb.pixel(x, 0);
        }
        page = page.next_in(mask);
    }
    let covered: String = union.iter().map(|&s| if s { '#' } else { '.' }).collect();
    println!("  U: {covered}");
    println!(
        "     union of every thumb covers {}/{WIDTH} track columns",
        union.iter().filter(|&&s| s).count()
    );
}

#[test]
fn preview_page_indicator_at_three_mask_sizes() {
    preview_indicator_over_mask("full cycle", u64::MAX);
    let typical = Page::Dashboard.bit()
        | Page::Distance.bit()
        | Page::Pace.bit()
        | Page::Lap.bit()
        | Page::Zones.bit()
        | Page::Splits.bit()
        | Page::ElevationProfile.bit()
        | Page::RacePredictor.bit()
        | Page::TrainingLoad.bit()
        | Page::DistanceBand.bit()
        | Page::GearWear.bit()
        | Page::BackToStart.bit();
    preview_indicator_over_mask("typical unsynced run", typical);
    let minimal = Page::Dashboard.bit() | Page::Pace.bit() | Page::BackToStart.bit();
    preview_indicator_over_mask("minimal curated", minimal);

    let mut fb = Framebuffer::new();
    widgets::draw_page_indicator(
        &mut fb,
        watch_core::statusbar::page_indicator(Page::BackToStart, u64::MAX),
    );
    show_indicator_band("last page of the full cycle, all four band rows", &fb);
}
