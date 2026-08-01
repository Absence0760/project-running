//! UI task — drives the Sharp MIP status face and the liveness LED.
//!
//! Rendering is delegated: `watch_core::face` decides what the rows say
//! (host-tested), `sharp_mip` turns rows into dirty-line SPI traffic
//! (host-tested). This task owns only the 1 Hz cadence and the peripheral
//! handles. The once-a-second flush doubles as the display's VCOM
//! alternation, which the glass needs regardless of content changes.

use defmt::*;
use embassy_futures::select::{select, select3, select4, Either, Either3, Either4};
use embassy_nrf::gpio::{AnyPin, Level, Output, OutputDrive};
use embassy_nrf::peripherals::PWM0;
use embassy_nrf::pwm::{DutyCycle, Prescaler, SimpleConfig, SimplePwm};
use embassy_nrf::spim::Spim;
use embassy_nrf::Peri;
use embassy_time::{Duration, Instant, Timer};
use sharp_mip::{Framebuffer, Icon, SharpMip};
use watch_core::alerts::{self, Alert};
use watch_core::button;
use watch_core::course::Course;
use watch_core::elevation::{self, Reading as ElevationReading, RezeroStatus};
use watch_core::face::{self, FaceIcon, IdleView, NavView};
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::gnss_signal::SignalSample;
use watch_core::hr_duty::{self, HrSample};
use watch_core::ice::IceCard;
use watch_core::nav_map::{self, PanelCache, PanelKey};
use watch_core::page::Page;
use watch_core::page_grid;
use watch_core::record::{RecordState, Snapshot};
use watch_core::settings_menu;
use watch_core::statusbar;
use watch_core::timers;
use watch_core::trackback::TrackbackView;
use watch_core::ui_frame::{self, FrameLayout, HeroBand, HeroFrame, RowPaint};
use watch_render::widgets;

use crate::state;

// The face's text grid and the panel's cell grid are defined in separate
// crates on purpose (core is display-agnostic); this pins them together.
const _: () = core::assert!(face::COLS == sharp_mip::TEXT_COLS);
const _: () = core::assert!(face::ROWS == sharp_mip::TEXT_ROWS);

// The screen task is event-driven: it re-renders when a state Watch changes and
// otherwise sleeps. A short tick still fires while there's a *time-based* reason
// to refresh — an animation frame to advance, or a fresh GPS fix that needs to
// flip to STALE once fixes stop. With none of those, it falls back to a long
// heartbeat so a truly idle wrist wakes the CPU seconds apart, not every second.
const TICK_ACTIVE: Duration = Duration::from_secs(1);
const TICK_IDLE: Duration = Duration::from_secs(30);

const CELL_H: usize = sharp_mip::HEIGHT / sharp_mip::TEXT_ROWS;

/// Bench/sim liveness blinker — toggles LED1 at 2 Hz so you can see the
/// firmware is alive before the display or defmt tells you. Gated behind the
/// default-OFF `dev-blink` feature: a free-running 2 Hz waker + LED current is
/// exactly the kind of unjustified always-on draw the power path warns against
/// (`docs/custom_watch/performance_path.md` — "every wake justifiable"), so it
/// is a debug affordance the lean default build omits and the sim/flash helpers
/// opt back in. The dev-board's own LEDs dominate tier-1 draw regardless; this
/// keeps the *firmware* honest for the tier-2 port.
#[cfg(feature = "dev-blink")]
#[embassy_executor::task]
pub async fn blink_task(pin: Peri<'static, AnyPin>) {
    // LEDs on the nRF52840 DK are active-low (cathode tied to MCU pin, anode
    // to VDD via a series resistor); Level::High here starts the LED OFF.
    let mut led = Output::new(pin, Level::High, OutputDrive::Standard);
    info!("ui::blink_task started");
    loop {
        led.toggle();
        Timer::after(Duration::from_millis(500)).await;
    }
}

/// Map a display-agnostic [`FaceIcon`] (decided in host-tested `watch_core`)
/// onto the panel driver's own [`Icon`]. Exhaustive on purpose: adding a
/// `FaceIcon` variant without a glyph here is a compile error, not a blank row.
fn driver_icon(icon: FaceIcon) -> Icon {
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
    }
}

/// Hardware VCOM: hold EXTMODE high and drive EXTCOMIN with a continuous PWM
/// square wave so the panel's bias inversion happens in hardware and the CPU
/// never wakes to toggle it. The screen task can then flush only when content
/// changes (see [`screen_task`] + `SharpMip::new_external_vcom`) instead of
/// sending a VCOM frame every second. `>=1 Hz` is the Sharp requirement to
/// avoid DC bias; ~3.8 Hz is the slowest a single nRF PWM reaches (Div128
/// prescaler x the max 32767 countertop), which keeps switching power minimal.
/// The task owns the PWM + EXTMODE pin for the device's lifetime and then
/// parks — the waveform runs autonomously, no further wakes.
#[embassy_executor::task]
pub async fn vcom_task(
    pwm: Peri<'static, PWM0>,
    extcomin: Peri<'static, AnyPin>,
    extmode: Peri<'static, AnyPin>,
) {
    let _extmode = Output::new(extmode, Level::High, OutputDrive::Standard);
    // Div128 prescaler x the max 32767 countertop = 16 MHz / 128 / 32767 ~= 3.8
    // Hz, the slowest a single PWM reaches; 50% duty.
    let mut config = SimpleConfig::default();
    config.prescaler = Prescaler::Div128;
    config.max_duty = 32767;
    let mut vcom = SimplePwm::new_1ch(pwm, extcomin, &config);
    vcom.set_duty(0, DutyCycle::normal(16384));
    info!("ui::vcom_task started (hardware EXTCOMIN)");
    // Keep the PWM + EXTMODE pin alive forever; the waveform is autonomous.
    core::future::pending::<()>().await;
}

#[embassy_executor::task]
pub async fn screen_task(
    spim: Spim<'static>,
    cs: Output<'static>,
    course: Option<&'static Course>,
) {
    // Hardware VCOM: EXTCOMIN (driven by vcom_task) carries the bias, so a clean
    // framebuffer flushes nothing and a static screen costs zero SPI.
    let mut display = SharpMip::new_external_vcom(spim, cs);
    let mut fb = Framebuffer::new();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut hr_rx = unwrap!(state::HR.receiver());
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let mut page_rx = unwrap!(state::PAGE.receiver());
    let mut page_grid_rx = unwrap!(state::PAGE_GRID.receiver());
    let mut idle_view_rx = unwrap!(state::IDLE_VIEW.receiver());
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut interaction_rx = unwrap!(state::INTERACTION.receiver());
    let mut alert_rx = unwrap!(state::ALERT.receiver());
    let mut nav_rx = unwrap!(state::NAV.receiver());
    let mut course_rx = unwrap!(state::COURSE.receiver());
    let mut tb_rx = unwrap!(state::TRACKBACK.receiver());
    let mut signal_rx = unwrap!(state::SIGNAL.receiver());
    let mut battery_rx = unwrap!(state::BATTERY.receiver());
    let mut pending_runs_rx = unwrap!(state::PENDING_RUNS.receiver());
    let mut unsynced_runs_rx = unwrap!(state::UNSYNCED_RUNS.receiver());
    let mut rezero_rx = unwrap!(state::QNH_REZERO.receiver());
    let mut stop_armed_rx = unwrap!(state::STOP_ARMED.receiver());
    let mut menu_rx = unwrap!(state::SETTINGS_MENU.receiver());
    let mut timer_rx = unwrap!(state::TIMER.receiver());
    let mut timer_menu_rx = unwrap!(state::TIMER_MENU.receiver());
    let mut profile_rx = unwrap!(state::PROFILE.receiver());
    let mut tz_offset_rx = unwrap!(state::TZ_OFFSET_MIN.receiver());
    let mut ice_rx = unwrap!(state::ICE.receiver());
    let mut screens_rx = unwrap!(state::SCREENS.receiver());
    let mut latest: Option<Fix> = None;
    let mut hr: Option<HrSample> = None;
    let mut rec: Option<Snapshot> = None;
    let mut elev: Option<ElevationReading> = None;
    let mut tb: Option<TrackbackView> = None;
    let mut signal: Option<SignalSample> = None;
    let mut battery: Option<u8> = None;
    let mut pending_runs: u8 = 0;
    let mut unsynced_runs: u8 = 0;
    let mut page = Page::default();
    let mut logged_page: Option<Page> = None;
    let mut idle_view = IdleView::Home;
    let mut logged_idle_view: Option<IdleView> = None;
    // The page-grid overview's cursor while open (None = closed) — published
    // by the button task, which owns the grid state machine.
    let mut grid: Option<Page> = None;
    // The idle settings menu's cursor while open (§351) — same ownership
    // split as the grid.
    let mut menu: Option<settings_menu::MenuView> = None;
    // The timer instrument and whether its modal is up (§375) — same ownership
    // split as the menu: the button task drives, this task only draws.
    let mut timer = watch_core::timers::Timer::new();
    let mut timer_open = false;
    let mut mode = GnssMode::default();
    let mut profile: Option<watch_core::profiles::ActivityProfile> = None;
    let mut last_interaction_s: u32 = 0;
    let mut alert: Option<Alert> = None;
    let mut rezero: Option<(RezeroStatus, u32)> = None;
    let mut stop_armed: Option<u32> = None;
    // No published offset yet = the home clock stays UTC (and says so).
    let mut tz_offset_min: Option<i16> = None;
    // The responder card (§358); None until the record task publishes one from
    // flash or a phone push, which the ICE face says honestly.
    let mut ice: Option<IceCard> = None;
    // The runner's composed data screens (§364); None until the record task
    // publishes them from flash or a phone push.
    let mut screens: Option<watch_core::screens::Screens> = None;
    // Latches the transient fuel banner into a standing "fuel overdue" marker
    // (the DK has no haptics, so an 8 s banner alone is missable). Fed from the
    // same `alert` stream the face already receives — no extra cross-task wire.
    let mut fuel_overdue = alerts::FuelOverdueTracker::new();
    let mut fuel_ack = alerts::FuelAckDwell::new();
    let mut nav = NavView::NoCourse;
    // A phone-pushed course (state::COURSE) drives the Nav map's drawn polyline;
    // a pushed course takes over from the boot/sim course, mirroring what the nav
    // task follows for the status. Owned (the buffer lives here), so drawing uses
    // `pushed_course.as_ref().or(course)`.
    let mut pushed_course: Option<Course> = None;
    // A long course auto-zooms to a window around the runner, so the map's fit
    // depends on the live fix and is recomputed each frame — not once. The cache
    // remembers the last painted panel key so an unchanged panel skips its
    // redraw entirely.
    let mut panel_cache = PanelCache::new();

    if let Err(e) = display.clear_all() {
        warn!("ui: display clear failed: {:?}", e);
    }
    info!("ui::screen_task started");
    loop {
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
        }
        if let Some(sample) = hr_rx.try_changed() {
            hr = Some(sample);
        }
        if let Some(snap) = rec_rx.try_changed() {
            rec = Some(snap);
        }
        if let Some(reading) = elev_rx.try_changed() {
            elev = Some(reading);
        }
        if let Some(p) = page_rx.try_changed() {
            page = p;
        }
        if let Some(g) = page_grid_rx.try_changed() {
            grid = g;
        }
        if let Some(v) = idle_view_rx.try_changed() {
            idle_view = v;
        }
        if let Some(c) = ice_rx.try_changed() {
            ice = c;
        }
        if let Some(s) = screens_rx.try_changed() {
            screens = s;
        }
        if let Some(m) = mode_rx.try_changed() {
            mode = m;
        }
        if let Some(t) = interaction_rx.try_changed() {
            last_interaction_s = t;
        }
        if let Some(a) = alert_rx.try_changed() {
            alert = a;
        }
        if let Some(v) = nav_rx.try_changed() {
            nav = v;
        }
        if let Some(c) = course_rx.try_changed() {
            pushed_course = c;
            // The drawn course changed — force the Nav panel to repaint next frame.
            panel_cache.invalidate();
        }
        if let Some(v) = tb_rx.try_changed() {
            tb = Some(v);
        }
        if let Some(s) = signal_rx.try_changed() {
            signal = Some(s);
        }
        if let Some(b) = battery_rx.try_changed() {
            battery = b;
        }
        if let Some(n) = pending_runs_rx.try_changed() {
            pending_runs = n;
        }
        if let Some(n) = unsynced_runs_rx.try_changed() {
            unsynced_runs = n;
        }
        if let Some(r) = rezero_rx.try_changed() {
            rezero = Some(r);
        }
        if let Some(v) = stop_armed_rx.try_changed() {
            stop_armed = v;
        }
        if let Some(v) = menu_rx.try_changed() {
            menu = v;
        }
        if let Some(t) = timer_rx.try_changed() {
            timer = t;
        }
        if let Some(open) = timer_menu_rx.try_changed() {
            timer_open = open;
        }
        // No dedicated select arm: a profile only changes on a menu edit,
        // whose preset push always wakes this loop within a tick (the pages
        // push republishes a snapshot; a mode change wakes mode_rx), so the
        // coalescing poll here is enough.
        if let Some(p) = profile_rx.try_changed() {
            profile = p;
        }
        if let Some(m) = tz_offset_rx.try_changed() {
            tz_offset_min = Some(m);
        }
        let uptime_s = Instant::now().as_secs() as u32;
        // Animate only in the window after a button press; otherwise hold steady
        // frames so an unattended run stops redrawing the display every second.
        let animate = ui_frame::animating(uptime_s, last_interaction_s);
        // The face renders only what the duty-cycle hold budget lets it vouch
        // for: the last valid reading holds through one off-window and then
        // blanks to `--` — a duty-cycled HR must never look continuous.
        let hr_bpm = hr_duty::shown_bpm(hr, uptime_s, mode);
        let mut rows = face::page_rows(
            page,
            latest.as_ref(),
            hr_bpm,
            rec.as_ref(),
            elev.as_ref(),
            nav,
            tb.as_ref(),
            uptime_s,
            animate,
            mode,
            idle_view,
            tz_offset_min,
            ice.as_ref(),
            screens.as_ref(),
        );
        // The hero band is decided here rather than at its `match` below,
        // because the standing marker shares row 1 with it and has to know how
        // far its pixels reach before the text rows are committed.
        //
        // The manual QNH re-zero's transient feedback: an inverse banner over
        // the idle face's title band for its TTL. Idle-only — the gesture only
        // exists on the idle face, and a run view's hero band belongs to the
        // run's own alerts.
        let rezero_banner =
            ui_frame::rezero_banner_status(rezero, uptime_s, face::run_view(rec.as_ref()))
                .map(elevation::rezero_banner);
        let stop_pending =
            ui_frame::stop_pending(face::run_view(rec.as_ref()), stop_armed, uptime_s);
        // The pages whose body spares row 2 headline their number in the 32x48 +
        // 16x32 numeral faces over rows 0-2, with the label and state tag on row
        // 3; every other numeral hero takes the 16x32 medium face over rows 0-1,
        // and so does a value too wide to render whole at the taller size.
        //
        // A composed screen (§364) supplies its own slots instead of declaring a
        // static metric, and its FIRST slot is a tall hero at row 0 — exactly
        // what a glance page's is. So it feeds the same `hero` here and inherits
        // the band decision, the unit placement and the run-marker clearance
        // untouched; only the slots beneath it are new drawing.
        let screen_slots = face::screen_page_slots(
            page,
            screens.as_ref(),
            latest.as_ref(),
            hr_bpm,
            rec.as_ref(),
            tb.as_ref(),
            uptime_s,
            tz_offset_min,
        );
        let hero = match screen_slots.as_ref() {
            Some(sc) => sc.slots.first().map(|s| s.value.clone()),
            None => face::page_hero(
                page,
                latest.as_ref(),
                hr_bpm,
                rec.as_ref(),
                tb.as_ref(),
                uptime_s,
                tz_offset_min,
            ),
        };
        // The hero's unit, drawn at 1x on the number's own baseline instead of
        // welded into a string the numeral faces cannot spell (§ 361). Resolved
        // before the band, because it is part of the width the tall face is
        // budgeted against — and then to a cell, once, because the standing
        // marker shares row 1 with it on the two-row faces and has to clear it.
        let unit = hero
            .as_deref()
            .filter(|h| ui_frame::hero_has_value(h))
            .and(match screen_slots.as_ref() {
                Some(sc) => sc.slots.first().and_then(|s| s.unit),
                None => face::page_hero_unit(page, rec.as_ref(), tb.as_ref()),
            });
        let band = ui_frame::hero_band(HeroFrame {
            alert: alert.is_some(),
            rezero_banner: rezero_banner.is_some(),
            hero: hero.is_some(),
            numeral: hero.as_deref().is_some_and(ui_frame::numeral_hero),
            fits_tall: hero
                .as_deref()
                .is_some_and(|h| ui_frame::tall_hero_fits(h, unit)),
            stop_pending,
            page,
        });
        let hero_unit = hero
            .as_deref()
            .zip(unit)
            .and_then(|(h, u)| ui_frame::hero_unit_cell(band, h, u).map(|cell| (u, cell)));
        // Persist the fuel reminder past its transient banner: latch the standing
        // overdue state off the same `alert` value. HOLDING the Fuel glance is
        // the acknowledgement — a fly-by on the way to another page is the
        // same miss the marker exists for (alerts::FUEL_ACK_DWELL_S).
        let overdue = fuel_overdue.observe(
            alert,
            ui_frame::alerts_run_active(rec.as_ref()),
            fuel_ack.observe(page == Page::Fuel, uptime_s),
        );
        let hero_cells = ui_frame::hero_row_cells(
            band,
            hero.as_deref().unwrap_or(""),
            hero_unit.map(|(unit, _)| unit),
        );
        if face::run_view(rec.as_ref()) {
            // A run view carries neither the idle battery icon nor the
            // diagnostics BAT row, so this marker is the only place a runner can
            // learn the cell is going — on a device whose mode picker exists to
            // trade fixes for hours, and whose runs last days.
            face::apply_run_marker(&mut rows, page, overdue, battery, hero_cells);
        } else {
            // The diagnostics face's numeric battery read-out; the idle-face
            // icon is a widget below.
            face::apply_battery_row(&mut rows, idle_view, battery);
            // A run interrupted by a reset (or a failed commit) is on flash and
            // pullable, but nothing else on the idle face distinguishes that boot
            // from any other — so say so, standing, until the phone has it.
            face::apply_pending_run_marker(&mut rows, idle_view, pending_runs);
            // The unsynced-backlog pressure row: from three of the four slots
            // up, the next start can silently destroy a run the phone never
            // pulled, so the face names the stake BEFORE the `! RUN LOST`
            // banner has anything to report. After the recovered marker — it
            // yields the shared row to that sharper fact.
            face::apply_unsynced_run_marker(&mut rows, idle_view, unsynced_runs);
        }
        // Last word on the hero band's text, after every overlay that writes
        // into it: a hero wide enough to reach the state tag takes the tag's
        // cells, so the tag yields whole rather than rendering as a different
        // state's first letters gone.
        face::apply_hero_clearance(&mut rows, ui_frame::hero_band_rows(band), hero_cells);
        let icons = face::page_icons(
            page,
            latest.as_ref(),
            hr_bpm,
            rec.as_ref(),
            uptime_s,
            animate,
            mode,
        );
        // The Nav page's map panel: the course polyline plus a position-marker
        // cross, drawn into the pixel rows the face leaves empty. `nav_map`
        // decides the whole panel per frame (host-tested) — the transform
        // (whole-course for a short route, an auto-zoom window centred on the
        // runner for a long one), whether the marker is drawn, and the repaint
        // key. When the key is unchanged the panel rows are skipped below and
        // their pixels stand, so a resting Nav page still flushes zero lines. A
        // repaint first lets draw_text_row blank the rows, then redraws; only
        // lines whose bytes actually changed go dirty.
        let nav_alert = face::nav_alert_row(nav);
        let nav_draw = if page == Page::Nav && face::run_view(rec.as_ref()) {
            // Prefer a phone-pushed course over the boot/sim one for the drawn map.
            pushed_course.as_ref().or(course).map(|c| {
                let runner = latest.as_ref().map(|f| (f.lat_deg, f.lon_deg));
                (c, nav_map::nav_panel(c, runner, widgets::NAV_PANEL_GEOM))
            })
        } else {
            None
        };
        let panel_key = nav_draw.as_ref().map(|(_, panel)| PanelKey {
            track: panel.track,
            marker: panel.marker.is_some(),
            alert: nav_alert.is_some(),
        });
        let panel_repaint = panel_cache.observe(panel_key);
        let layout = FrameLayout {
            page,
            run_view: face::run_view(rec.as_ref()),
            idle_view,
            panel_active: panel_key.is_some(),
            panel_repaint,
        };
        for (row, text) in rows.iter().enumerate() {
            match ui_frame::row_paint(row, layout) {
                RowPaint::Skip => continue,
                RowPaint::Ruled => widgets::ruled_dashboard_row(&mut fb, row, text),
                RowPaint::Chrome => fb.draw_text_row_small(row, text),
                RowPaint::Text => fb.draw_text_row(row, text),
            }
            if let Some(icon) = icons[row] {
                fb.draw_icon(0, row, driver_icon(icon));
            }
        }
        if panel_repaint {
            let (course, panel) = unwrap!(nav_draw.as_ref());
            widgets::draw_nav_panel(&mut fb, course, panel, nav_alert.as_deref());
        }
        // The hero (elapsed time, or the glance page's headline metric) overlays
        // the top rows, drawn after them so it wins; the state tag sits
        // top-right, clear of the digits. An active on-run alert takes the band
        // over for its TTL — an inverse-video banner ("! DRINK" light on a dark
        // band) is the most unmissable treatment the panel gives, and the alert
        // engine only emits during a run, so the idle face never loses its
        // title. Which band this is was decided above, with the row layout.
        match band {
            HeroBand::AlertBanner => {
                if let Some(a) = alert {
                    fb.draw_banner_2x(0, &alerts::banner(a));
                }
            }
            HeroBand::RezeroBanner => {
                if let Some(banner) = &rezero_banner {
                    fb.draw_banner_2x(0, banner);
                }
            }
            HeroBand::BigNumHero => {
                if let Some(hero) = &hero {
                    fb.draw_bignum_hero(0, hero);
                }
            }
            HeroBand::MedNumHero => {
                if let Some(hero) = &hero {
                    fb.draw_bignum_med_hero(0, hero);
                }
            }
            HeroBand::TextHero => {
                if let Some(hero) = &hero {
                    fb.draw_text_2x(0, 0, hero);
                }
            }
            HeroBand::None => {}
        }
        // The composed screen's remaining slots, under the hero that slot 0
        // already drew. Same two primitives the band above uses, at the row
        // `slot_placements` puts them on — a Duo's second value in the 32x48
        // face, a Trio's two in the 16x32 one. Their labels came through the
        // text rows, to the right of the medium values and clear of the span
        // these draws overwrite.
        if let Some(sc) = screen_slots.as_ref() {
            for (slot, at) in sc
                .slots
                .iter()
                .zip(ui_frame::slot_placements(sc.layout))
                .skip(1)
            {
                let y = at.value_row * CELL_H;
                // The placement's band is a nominal request; a value the
                // numeral faces cannot spell — every unfed class token, and
                // `DONE` — falls back to the doubled text face, or it would
                // draw as nothing at all.
                match ui_frame::slot_band(at.band, &slot.value) {
                    HeroBand::BigNumHero => fb.draw_bignum_hero(y, &slot.value),
                    HeroBand::MedNumHero => fb.draw_bignum_med_hero(y, &slot.value),
                    _ => fb.draw_text_2x(0, at.value_row, &slot.value),
                }
            }
        }
        // After the hero, so the number's own span (composed from scratch, and
        // therefore destructive) can never erase the unit that labels it.
        if let Some((unit, (col, row))) = hero_unit {
            fb.draw_text(col, row, unit);
        }
        // Widget overlays (host-tested in `watch_render`): the render layer
        // paints into the cells the face leaves blank. A run view gets the
        // top-edge page-position indicator plus its page's gauge / bars; the
        // idle status face gets the GPS signal meter instead. Unchanged pixels
        // dirty nothing, so a resting page still flushes zero lines.
        if face::run_view(rec.as_ref()) {
            // The dot row counts the FILTERED cycle (data-present ∩ curated),
            // so it matches what BTN3 actually walks; no snapshot means no
            // filter yet.
            let pages_mask = ui_frame::pages_mask(rec.as_ref());
            widgets::draw_page_indicator(&mut fb, statusbar::page_indicator(page, pages_mask));
            if let Some(snap) = rec.as_ref() {
                match page {
                    Page::Pacer => widgets::draw_pacer_overlay(&mut fb, snap),
                    Page::Workout => widgets::draw_workout_overlay(&mut fb, snap),
                    Page::Fuel => widgets::draw_fuel_overlay(&mut fb, snap),
                    Page::GearWear => widgets::draw_gear_overlay(&mut fb, snap),
                    Page::Zones => widgets::draw_zones_overlay(&mut fb, snap, hr_bpm),
                    Page::Splits => widgets::draw_splits_overlay(&mut fb, snap),
                    Page::ElevationProfile => widgets::draw_elev_profile_overlay(&mut fb, snap),
                    Page::RouteElev => widgets::draw_route_elev_overlay(&mut fb, snap),
                    _ => {}
                }
            }
        } else {
            let bars = signal.unwrap_or_default().bars();
            widgets::draw_signal_bars(&mut fb, sharp_mip::WIDTH - 2, CELL_H - 2, bars);
            // The battery icon shares the title row's mid-band with the
            // post-press BTN3 hint AND the transient re-zero 2x banner, so it
            // yields to both — it only draws while the row shows the brand.
            widgets::draw_idle_battery(&mut fb, battery, animate || rezero_banner.is_some());
            if idle_view == IdleView::Home {
                let clock = face::home_clock_text(latest.as_ref(), uptime_s, tz_offset_min);
                fb.draw_bignum_band(face::CLOCK_HERO_TOP_ROW * CELL_H, &clock);
            }
        }

        // The BackToStart page's pixel layer rides on top of the text rows
        // (which reserve the space — see face::NAV_TEXT_COLS): the TrackBack
        // breadcrumb map on the right of rows 3-7, the relative direction
        // arrow on the left of rows 5-7. Only while a run is under way — the
        // idle status face must never carry a stale crumb.
        let run_active = rec
            .as_ref()
            .is_some_and(|snap| snap.state != RecordState::Idle);
        if page == Page::BackToStart && run_active {
            if let Some(view) = tb.as_ref() {
                widgets::draw_trackback_overlay(&mut fb, view, uptime_s);
            }
        }
        // The armed-stop prompt: the direct answer to a BTN2 press, so for its
        // 4 s confirm window it outranks an alert banner on the hero band. The
        // grid (drawn after) still wins over it — BTN2 inside the grid cancels
        // and disarms, never arms.
        if stop_pending {
            fb.draw_banner_2x(0, button::STOP_ARMED_BANNER);
        }
        // The page-grid overview takes the panel over while open: its rows
        // rewrite every band (erasing the composed page underneath — each
        // draw_text_row overwrites its full 16-px band) and the cursor box +
        // a cursor-tracking page indicator ride on top. Drawn last rather
        // than branching the whole composer: the handful of frames a grid
        // stays open don't justify a second render path. Unlike the hero
        // band, an on-run alert banner does NOT win here — under the full
        // mask the banner's two rows would cover the title AND the first row
        // of cells mid-choice. Deferring costs nothing: the grid closes
        // within ~GRID_AUTOSELECT_S, well inside the alert's TTL, so the
        // banner re-asserts on the landing page, and a fuel reminder
        // additionally latches into the persistent row-1 marker.
        if let Some(cursor) = grid.filter(|_| face::run_view(rec.as_ref())) {
            let pages_mask = ui_frame::pages_mask(rec.as_ref());
            for (row, text) in page_grid::grid_rows(pages_mask, cursor).iter().enumerate() {
                fb.draw_text_row(row, text);
            }
            if let Some(cell) = page_grid::grid_cell(pages_mask, cursor, cursor) {
                widgets::draw_grid_cursor(&mut fb, cell);
            }
            widgets::draw_page_indicator(&mut fb, statusbar::page_indicator(cursor, pages_mask));
            // The Nav map's skip-cache is stale once the grid painted over it.
            panel_cache.invalidate();
        }
        // The settings menu takes the idle face over while open (§351) — the
        // same one-render-path trade as the grid above. Idle-only by
        // construction (the button task closes it when a run starts); the
        // run_view gate keeps a not-yet-closed cursor from painting over a
        // live run in the interim.
        if let Some(view) = menu.filter(|_| !face::run_view(rec.as_ref())) {
            let hide = rec.as_ref().map(|s| s.hide_empty_pages).unwrap_or(true);
            let yard = rec.as_ref().is_some_and(|s| s.backyard.is_some());
            for (row, text) in
                settings_menu::menu_rows(view, mode, hide, profile, yard, unsynced_runs)
                    .iter()
                    .enumerate()
            {
                fb.draw_text_row(row, text);
            }
            panel_cache.invalidate();
        }
        // The timer modal, on the same terms as the settings menu above (§375):
        // idle-only, one render path, and the run_view gate covering the
        // interim before the button task closes it.
        if timer_open && !face::run_view(rec.as_ref()) {
            for (row, text) in timers::timer_rows(&timer, uptime_s).iter().enumerate() {
                fb.draw_text_row(row, text);
            }
            panel_cache.invalidate();
        }
        if let Err(e) = display.flush(&mut fb) {
            warn!("ui: display flush failed: {:?}", e);
        }

        // AFTER the flush, so the line is a claim about the panel rather than
        // about this task's intent. Logged before the draw, it said "I am about
        // to compose Nav" — and a harness that dumps the instant it decodes
        // reads the previous screen, which is how `page-Nav.png` came back
        // byte-identical to `page-Climb.png` on the § 360 sheet: a capture
        // labelled with the page the composer had not drawn yet. The pixel
        // comparison in `sim/screenshots.py` was a detector for this; moving
        // the line removes the race it was detecting.
        //
        // Change-gated, not per-render: the loop also runs for every fix,
        // snapshot, alert and heartbeat tick, and an unconditional log would put
        // a standing per-second reason to emit back into a task whose whole
        // design is to sleep between events. `sim/ci_smoke.py` and
        // `sim/screenshots.py` both match these lines, so their shape is a
        // contract with the harness.
        if logged_page != Some(page) {
            debug!("ui: page {}", page);
            logged_page = Some(page);
        }
        // The idle faces' equivalent. The button task already logs which face a
        // BTN4 press SELECTED; this is the separate claim that the composer
        // followed it onto the panel — the pair the page walk cross-checks,
        // which the idle faces had no way to make. Without it a screenshot or a
        // scenario can only dump and hope the repaint already landed, and an
        // idle_view that never reached this task reads exactly like a face that
        // happens to look the same.
        if logged_idle_view != Some(idle_view) {
            debug!("ui: idle {}", idle_view);
            logged_idle_view = Some(idle_view);
        }

        // Sleep until a state change or the next time-based refresh. Recording
        // wakes us via RECORD snapshots each second; a moving GPS fix wakes us
        // via FIX; a button press via INTERACTION. The only refreshes with no
        // event behind them are the animation frame and the fresh→stale flip.
        // Freshness follows the same mode-aware budget the face renders with
        // (see `face::stale_after_s`), so the fresh→stale redraw is scheduled
        // for the moment the face would actually flip — not 5 s into a
        // throttled mode's perfectly healthy 60 s gap between fixes.
        let run_view = rec
            .as_ref()
            .is_some_and(|snap| snap.state != RecordState::Idle);
        let stale_after = face::stale_after_s(mode, run_view);
        // A shown HR is another time-based refresh owed: its blank must land
        // when the hold budget expires, not at the next long heartbeat — the
        // HR analogue of the fresh→stale fix flip above. A showing re-zero
        // banner needs the same timely tick to expire on schedule.
        let tick = if ui_frame::owes_timed_refresh(
            animate,
            ui_frame::fix_fresh(latest.as_ref(), uptime_s, stale_after),
            hr_bpm.is_some(),
            rezero_banner.is_some(),
        ) {
            TICK_ACTIVE
        } else {
            TICK_IDLE
        };
        let sensors = select4(
            fix_rx.changed(),
            hr_rx.changed(),
            rec_rx.changed(),
            elev_rx.changed(),
        );
        let controls = select4(
            page_rx.changed(),
            interaction_rx.changed(),
            alert_rx.changed(),
            nav_rx.changed(),
        );
        // Apply the value the winning `changed()` yields. `changed()` advances
        // the receiver's seen-marker when it resolves, so the top-of-loop
        // `try_changed()` will NOT re-observe it — a one-shot change (a PAGE
        // switch, an INTERACTION stamp) would be lost if we discarded it here.
        // Continuously-updated signals (FIX/RECORD) happen to self-heal on the
        // next tick, but PAGE only changes on a button press. The losing
        // futures are dropped un-consumed, so `try_changed()` still coalesces
        // any other simultaneous changes on the next iteration.
        match select3(
            sensors,
            controls,
            select4(
                tb_rx.changed(),
                mode_rx.changed(),
                signal_rx.changed(),
                select4(
                    rezero_rx.changed(),
                    page_grid_rx.changed(),
                    stop_armed_rx.changed(),
                    select4(
                        tz_offset_rx.changed(),
                        battery_rx.changed(),
                        // Both flash-store counts wake the face: a phone pull
                        // that only clears the unsynced backlog must retire
                        // the pressure row now, not at the next fix (a minute
                        // away in Expedition mode).
                        select(pending_runs_rx.changed(), unsynced_runs_rx.changed()),
                        // Registered wakers, not timers: at rest these three
                        // arms cost nothing — only the button task's sends while
                        // the settings menu is open, and a phone-pushed
                        // responder card or course, ever resolve them.
                        //
                        // ICE and COURSE need arms of their own where TIMER /
                        // TIMER_MENU / PROFILE / SCREENS get by on the
                        // top-of-loop `try_changed()` alone: every path that
                        // changes those also stamps state::INTERACTION or moves
                        // RECORD's snapshot in the same tick, and both are in
                        // this tree. A phone push carrying only a
                        // `SettingsEffect::Ice`, or only a course, touches
                        // neither — so without these the wearer waits for an
                        // unrelated wake, up to TICK_IDLE on an idle wrist. On
                        // the two surfaces that can least afford it: the face
                        // whose whole purpose is a stranger reading it in an
                        // emergency, and the map at a trail junction, which
                        // would go on drawing the PREVIOUS course.
                        select4(
                            menu_rx.changed(),
                            ice_rx.changed(),
                            course_rx.changed(),
                            Timer::after(tick),
                        ),
                    ),
                ),
            ),
        )
        .await
        {
            Either3::First(Either4::First(fix)) => latest = Some(fix),
            Either3::First(Either4::Second(sample)) => hr = Some(sample),
            Either3::First(Either4::Third(snap)) => rec = Some(snap),
            Either3::First(Either4::Fourth(reading)) => elev = Some(reading),
            Either3::Second(Either4::First(p)) => page = p,
            Either3::Second(Either4::Second(t)) => last_interaction_s = t,
            Either3::Second(Either4::Third(a)) => alert = a,
            Either3::Second(Either4::Fourth(v)) => nav = v,
            Either3::Third(Either4::First(v)) => tb = Some(v),
            Either3::Third(Either4::Second(m)) => mode = m,
            Either3::Third(Either4::Third(s)) => signal = Some(s),
            Either3::Third(Either4::Fourth(Either4::First(r))) => rezero = Some(r),
            Either3::Third(Either4::Fourth(Either4::Second(g))) => grid = g,
            Either3::Third(Either4::Fourth(Either4::Third(v))) => stop_armed = v,
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::First(m)))) => {
                tz_offset_min = Some(m)
            }
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Second(b)))) => battery = b,
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Third(Either::First(n))))) => {
                pending_runs = n
            }
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Third(Either::Second(n))))) => {
                unsynced_runs = n
            }
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Fourth(Either4::First(
                v,
            ))))) => menu = v,
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Fourth(Either4::Second(
                c,
            ))))) => ice = c,
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Fourth(Either4::Third(
                c,
            ))))) => {
                pushed_course = c;
                panel_cache.invalidate();
            }
            Either3::Third(Either4::Fourth(Either4::Fourth(Either4::Fourth(Either4::Fourth(
                (),
            ))))) => {}
        }
    }
}
