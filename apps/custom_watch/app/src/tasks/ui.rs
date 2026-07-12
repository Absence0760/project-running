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
use watch_core::course::{Course, CoursePoint, PanelFit};
use watch_core::elevation::Reading as ElevationReading;
use watch_core::face::{self, FaceIcon, NavView};
use watch_core::fix::Fix;
use watch_core::gnss_mode::GnssMode;
use watch_core::page::Page;
use watch_core::record::{RecordState, Snapshot};
use watch_core::statusbar;
use watch_core::trackback::{self, TrackbackView};
use watch_render::widgets;

use crate::state;

// The face's text grid and the panel's cell grid are defined in separate
// crates on purpose (core is display-agnostic); this pins them together.
const _: () = core::assert!(face::COLS == sharp_mip::TEXT_COLS);
const _: () = core::assert!(face::ROWS == sharp_mip::TEXT_ROWS);

// Seconds after the last button press for which the face keeps animating (REC
// blink, HR pulse, GPS search). Outside this window every animation holds a
// steady frame, so an idle wrist stops paying the per-second display redraw on
// a reflective panel where dark pixels save nothing — only fewer updates do.
const ANIM_WINDOW_S: u32 = 8;

// The screen task is event-driven: it re-renders when a state Watch changes and
// otherwise sleeps. A short tick still fires while there's a *time-based* reason
// to refresh — an animation frame to advance, or a fresh GPS fix that needs to
// flip to STALE once fixes stop. With none of those, it falls back to a long
// heartbeat so a truly idle wrist wakes the CPU seconds apart, not every second.
const TICK_ACTIVE: Duration = Duration::from_secs(1);
const TICK_IDLE: Duration = Duration::from_secs(30);

// The Nav page's map panel in panel pixels: full display width, the
// face-declared text rows tall. `core` speaks rows; only this task knows the
// panel's 16-px cell height.
const CELL_H: usize = sharp_mip::HEIGHT / sharp_mip::TEXT_ROWS;
const CELL_W: usize = sharp_mip::WIDTH / sharp_mip::TEXT_COLS;
const PANEL_TOP_PX: i32 = (face::NAV_PANEL_TOP_ROW * CELL_H) as i32;
const PANEL_H_PX: u32 = (face::NAV_PANEL_ROWS * CELL_H) as u32;
const PANEL_ROWS: core::ops::Range<usize> =
    face::NAV_PANEL_TOP_ROW..face::NAV_PANEL_TOP_ROW + face::NAV_PANEL_ROWS;

// Half-length of the position marker's 5-px cross. The marker is drawn only
// when its centre sits at least this far inside the panel, so the cross never
// scribbles on the text rows above/below AND a runner whose fix falls off the
// panel shows no marker at all — honest, since the OFF COURSE banner carries
// that story — rather than a clamped edge-pinned dot that reads as near-course.
const MARKER_ARM_PX: i32 = 2;

// Long-course auto-zoom. Fitting a whole 50 km course into the ~168 px panel is
// ~300 m/px, so its forks collapse to sub-pixel and the map is an unreadable
// scribble. Once the course bounding box exceeds this span (either axis), the
// panel stops fitting the whole route and instead windows a fixed real-world
// span centred on the runner, so the nearest forks stay resolvable; a course
// that already fits keeps the whole-course overview. The span is expressed in
// degrees (not metres) so the cos-lat correction stays inside `PanelFit` —
// `ui.rs` has no trig of its own (`libm` is not an `app` dependency). ~0.0054°
// latitude ~= 600 m, so the window spans ~1.2 km N-S (~13 m/px on the 96 px-tall
// panel); the E-W half is doubled so the wider panel isn't letterboxed.
const WIN_HALF_LAT_DEG: f64 = 0.0054;
const WIN_HALF_LON_DEG: f64 = 0.0108;

// The ElevationProfile page's mini-profile sparkline: the rows the face leaves
// blank below its vert-totals context row (rows 3..8), full width with a small
// margin — the elevation analogue of the splits histogram panel.
const ELEV_PROFILE_X: usize = 6;
const ELEV_PROFILE_Y: usize = 3 * CELL_H;
const ELEV_PROFILE_W: usize = sharp_mip::WIDTH - 2 * ELEV_PROFILE_X;
const ELEV_PROFILE_H: usize = 5 * CELL_H - 4;

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
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut interaction_rx = unwrap!(state::INTERACTION.receiver());
    let mut alert_rx = unwrap!(state::ALERT.receiver());
    let mut nav_rx = unwrap!(state::NAV.receiver());
    let mut course_rx = unwrap!(state::COURSE.receiver());
    let mut tb_rx = unwrap!(state::TRACKBACK.receiver());
    let mut sats_rx = unwrap!(state::SATS.receiver());
    let mut fix_quality_rx = unwrap!(state::FIX_QUALITY.receiver());
    let mut latest: Option<Fix> = None;
    let mut hr_bpm: Option<u16> = None;
    let mut rec: Option<Snapshot> = None;
    let mut elev: Option<ElevationReading> = None;
    let mut tb: Option<TrackbackView> = None;
    let mut sats: Option<u8> = None;
    let mut fix_quality: Option<u8> = None;
    let mut page = Page::default();
    let mut mode = GnssMode::default();
    let mut last_interaction_s: u32 = 0;
    let mut alert: Option<Alert> = None;
    // Latches the transient fuel banner into a standing "fuel overdue" marker
    // (the DK has no haptics, so an 8 s banner alone is missable). Fed from the
    // same `alert` stream the face already receives — no extra cross-task wire.
    let mut fuel_overdue = alerts::FuelOverdueTracker::new();
    let mut nav = NavView::NoCourse;
    // A phone-pushed course (state::COURSE) drives the Nav map's drawn polyline;
    // a pushed course takes over from the boot/sim course, mirroring what the nav
    // task follows for the status. Owned (the buffer lives here), so drawing uses
    // `pushed_course.as_ref().or(course)`.
    let mut pushed_course: Option<Course> = None;
    // A long course auto-zooms to a window around the runner, so the map's fit
    // now depends on the live fix and is recomputed each frame (`nav_fit`) — not
    // once. The panel's whole live pixel state is (runner tracking key, whether
    // the marker is drawn, whether the off-course banner is shown); remembering
    // the last drawn triple lets an unchanged panel skip its redraw entirely.
    let mut last_panel: Option<((i32, i32), bool, bool)> = None;

    if let Err(e) = display.clear_all() {
        warn!("ui: display clear failed: {:?}", e);
    }
    info!("ui::screen_task started");
    loop {
        if let Some(fix) = fix_rx.try_changed() {
            latest = Some(fix);
        }
        if let Some(reading) = hr_rx.try_changed() {
            hr_bpm = reading.valid.then_some(reading.bpm);
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
            last_panel = None;
        }
        if let Some(v) = tb_rx.try_changed() {
            tb = Some(v);
        }
        if let Some(s) = sats_rx.try_changed() {
            sats = Some(s);
        }
        if let Some(q) = fix_quality_rx.try_changed() {
            fix_quality = Some(q);
        }
        let uptime_s = Instant::now().as_secs() as u32;
        // Animate only in the window after a button press; otherwise hold steady
        // frames so an unattended run stops redrawing the display every second.
        let animate = uptime_s.saturating_sub(last_interaction_s) < ANIM_WINDOW_S;
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
        );
        // Persist the fuel reminder past its transient banner: latch the standing
        // overdue state off the same `alert` value and paint a compact marker.
        // `run_active` mirrors the alert engine's in-run states (Recording /
        // Paused); the Fuel glance page being open is the acknowledgement.
        let alerts_run_active = rec
            .as_ref()
            .is_some_and(|s| matches!(s.state, RecordState::Recording | RecordState::Paused));
        let overdue = fuel_overdue.observe(alert, alerts_run_active, page == Page::Fuel);
        face::apply_fuel_marker(&mut rows, overdue, page);
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
        // cross, drawn into the pixel rows the face leaves empty. `nav_fit` picks
        // the transform per frame — whole-course for a short route, an auto-zoom
        // window centred on the runner for a long one — so the fit tracks the
        // fix. The panel's live state is (runner tracking key, marker drawn,
        // alert shown); when none changed the panel rows are skipped below and
        // their pixels stand, so a resting Nav page still flushes zero lines. A
        // repaint first lets draw_text_row blank the rows, then redraws; only
        // lines whose bytes actually changed go dirty.
        let nav_alert = face::nav_alert_row(nav);
        let nav_draw = if page == Page::Nav && face::run_view(rec.as_ref()) {
            // Prefer a phone-pushed course over the boot/sim one for the drawn map.
            pushed_course.as_ref().or(course).map(|c| {
                let runner = latest.as_ref().map(|f| (f.lat_deg, f.lon_deg));
                let (fit, windowed) = nav_fit(c, runner, sharp_mip::WIDTH as u32, PANEL_H_PX);
                // Marker: drawn only when the runner's fix falls with its whole
                // 5-px cross inside the panel. No clamp — an off-panel (far
                // off-course, or outside the auto-zoom window) runner shows no
                // marker rather than a dishonest edge-pinned one; the OFF COURSE
                // banner is the source of truth. In the auto-zoom window the
                // runner is the panel centre, so the marker is always shown.
                let marker = runner.and_then(|(la, lo)| {
                    let (x, y) = fit.to_px(la, lo);
                    let (mx, my) = (x, y + PANEL_TOP_PX);
                    let inside = (MARKER_ARM_PX..sharp_mip::WIDTH as i32 - MARKER_ARM_PX)
                        .contains(&mx)
                        && (PANEL_TOP_PX + MARKER_ARM_PX
                            ..PANEL_TOP_PX + PANEL_H_PX as i32 - MARKER_ARM_PX)
                            .contains(&my);
                    inside.then_some((mx, my))
                });
                // Repaint tracking key: the runner in a course-anchored ~pixel
                // grid. In the whole-course fit that is just the marker's pixel;
                // in the auto-zoom window the marker holds at panel centre, so a
                // separate world-anchored grid is what advances as the runner
                // scrolls the map — otherwise a windowed map would freeze.
                let track = runner.map_or((0, 0), |(la, lo)| track_key(&fit, windowed, la, lo));
                (c, fit, marker, track)
            })
        } else {
            None
        };
        let panel_state = nav_draw
            .as_ref()
            .map(|(_, _, marker, track)| (*track, marker.is_some(), nav_alert.is_some()));
        let panel_repaint = panel_state.is_some() && panel_state != last_panel;
        last_panel = panel_state;
        for (row, text) in rows.iter().enumerate() {
            if PANEL_ROWS.contains(&row) && panel_state.is_some() && !panel_repaint {
                continue;
            }
            fb.draw_text_row(row, text);
            if let Some(icon) = icons[row] {
                fb.draw_icon(0, row, driver_icon(icon));
            }
        }
        if panel_repaint {
            let (course, fit, marker, _) = unwrap!(nav_draw.as_ref());
            for w in course.points().windows(2) {
                let (x0, y0) = fit.to_px(w[0].lat_deg, w[0].lon_deg);
                let (x1, y1) = fit.to_px(w[1].lat_deg, w[1].lon_deg);
                fb.draw_line(x0, y0 + PANEL_TOP_PX, x1, y1 + PANEL_TOP_PX, true);
            }
            if let Some(&(mx, my)) = marker.as_ref() {
                fb.draw_line(mx - MARKER_ARM_PX, my, mx + MARKER_ARM_PX, my, true);
                fb.draw_line(mx, my - MARKER_ARM_PX, mx, my + MARKER_ARM_PX, true);
            }
            // The off-course treatment: a steady 2x banner centred over the
            // breadcrumb, drawn last so it wins the panel pixels.
            if let Some(text) = &nav_alert {
                let col = sharp_mip::TEXT_COLS.saturating_sub(text.chars().count() * 2) / 2;
                fb.draw_text_2x(col, face::NAV_ALERT_ROW, text);
            }
        }
        // The 2x hero (elapsed time, or the glance page's headline metric)
        // overlays rows 0-1 (drawn after them so it wins); the state tag in
        // row 0 sits top-right, clear of the digits. An active on-run alert
        // takes the hero band over for its TTL — the banner ("! DRINK") is the
        // most unmissable treatment a 1-bit panel gives, and the alert engine
        // only emits during a run, so the idle face never loses its title.
        if let Some(a) = alert {
            fb.draw_text_2x(0, 0, &alerts::banner(a));
        } else if let Some(hero) = face::page_hero(page, hr_bpm, rec.as_ref(), tb.as_ref()) {
            // The single-metric glance pages headline their number triple-size
            // (their face reserves rows 0-2 + puts the label on row 3); every
            // other hero stays 2x over rows 0-1.
            if matches!(page, Page::Distance | Page::Pace) {
                fb.draw_text_3x(0, 0, &hero);
            } else {
                fb.draw_text_2x(0, 0, &hero);
            }
        }
        // Widget overlays (host-tested in `watch_render`): the render layer
        // paints into the cells the face leaves blank. A run view gets the
        // top-edge page-position indicator plus its page's gauge / bars; the
        // idle status face gets the GPS signal meter instead. Unchanged pixels
        // dirty nothing, so a resting page still flushes zero lines.
        if face::run_view(rec.as_ref()) {
            widgets::draw_page_indicator(&mut fb, statusbar::page_indicator(page));
            if let Some(snap) = rec.as_ref() {
                match page {
                    Page::Pacer => widgets::draw_pacer_overlay(&mut fb, snap),
                    Page::Fuel => widgets::draw_fuel_overlay(&mut fb, snap),
                    Page::GearWear => widgets::draw_gear_overlay(&mut fb, snap),
                    Page::Zones => widgets::draw_zones_overlay(&mut fb, snap, hr_bpm),
                    Page::Splits => widgets::draw_splits_overlay(&mut fb, snap),
                    Page::ElevationProfile => {
                        let ep = &snap.elev_profile;
                        if ep.len > 0 {
                            widgets::draw_mini_profile(
                                &mut fb,
                                &widgets::MiniProfile {
                                    x: ELEV_PROFILE_X,
                                    y: ELEV_PROFILE_Y,
                                    w: ELEV_PROFILE_W,
                                    h: ELEV_PROFILE_H,
                                    samples: &ep.samples[..ep.len],
                                },
                            );
                        }
                    }
                    _ => {}
                }
            }
        } else {
            let bars = statusbar::bars_for_fix(sats.unwrap_or(0), fix_quality.unwrap_or(0));
            widgets::draw_signal_bars(&mut fb, sharp_mip::WIDTH - 2, CELL_H - 2, bars);
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
                draw_trackback_overlay(&mut fb, view, uptime_s);
            }
        }
        if let Err(e) = display.flush(&mut fb) {
            warn!("ui: display flush failed: {:?}", e);
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
        let fix_fresh = latest
            .as_ref()
            .is_some_and(|f| uptime_s.saturating_sub(f.uptime_s) <= stale_after);
        let tick = if animate || fix_fresh {
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
                sats_rx.changed(),
                select(fix_quality_rx.changed(), Timer::after(tick)),
            ),
        )
        .await
        {
            Either3::First(Either4::First(fix)) => latest = Some(fix),
            Either3::First(Either4::Second(reading)) => {
                hr_bpm = reading.valid.then_some(reading.bpm)
            }
            Either3::First(Either4::Third(snap)) => rec = Some(snap),
            Either3::First(Either4::Fourth(reading)) => elev = Some(reading),
            Either3::Second(Either4::First(p)) => page = p,
            Either3::Second(Either4::Second(t)) => last_interaction_s = t,
            Either3::Second(Either4::Third(a)) => alert = a,
            Either3::Second(Either4::Fourth(v)) => nav = v,
            Either3::Third(Either4::First(v)) => tb = Some(v),
            Either3::Third(Either4::Second(m)) => mode = m,
            Either3::Third(Either4::Third(s)) => sats = Some(s),
            Either3::Third(Either4::Fourth(Either::First(q))) => fix_quality = Some(q),
            Either3::Third(Either4::Fourth(Either::Second(()))) => {}
        }
    }
}

/// Draw the BackToStart page's pixel layer: the north-up TrackBack breadcrumb
/// map (right of the reserved text columns, rows 3-7) with a hollow-box start
/// marker + filled-dot current position, and the relative back-to-start arrow
/// (left, rows 5-7) whenever a fresh heading makes it meaningful — the face's
/// text layer shows `--` in the arrow's spot otherwise, so the two never
/// overlap.
fn draw_trackback_overlay(fb: &mut Framebuffer, view: &TrackbackView, uptime_s: u32) {
    const MAP_X: i32 = (face::TRACKBACK_TEXT_COLS * CELL_W) as i32;
    const MAP_Y: i32 = (3 * CELL_H) as i32;
    const MAP_W: u16 = (sharp_mip::WIDTH - face::TRACKBACK_TEXT_COLS * CELL_W) as u16;
    const MAP_H: u16 = (5 * CELL_H) as u16;

    let mut pts = [(0u16, 0u16); trackback::BREADCRUMB_CAP + 1];
    if let Some(map) = trackback::project_track(view, MAP_W, MAP_H, &mut pts) {
        for pair in pts[..map.len].windows(2) {
            fb.draw_line(
                MAP_X + pair[0].0 as i32,
                MAP_Y + pair[0].1 as i32,
                MAP_X + pair[1].0 as i32,
                MAP_Y + pair[1].1 as i32,
                true,
            );
        }
        let (sx, sy) = (MAP_X + map.start.0 as i32, MAP_Y + map.start.1 as i32);
        fb.draw_line(sx - 2, sy - 2, sx + 2, sy - 2, true);
        fb.draw_line(sx + 2, sy - 2, sx + 2, sy + 2, true);
        fb.draw_line(sx + 2, sy + 2, sx - 2, sy + 2, true);
        fb.draw_line(sx - 2, sy + 2, sx - 2, sy - 2, true);
        let (cx, cy) = (MAP_X + map.current.0 as i32, MAP_Y + map.current.1 as i32);
        for dy in -1..=1 {
            fb.draw_line(cx - 1, cy + dy, cx + 1, cy + dy, true);
        }
    }

    if let Some(sector) = view.arrow_sector(uptime_s) {
        const ARROW_CX: i32 = (face::TRACKBACK_TEXT_COLS * CELL_W / 2) as i32;
        const ARROW_CY: i32 = (13 * CELL_H / 2) as i32; // centre of rows 5-7
        const ARROW_R: i32 = (3 * CELL_H) as i32 / 2 - 6;
        for ((x0, y0), (x1, y1)) in trackback::arrow_lines(sector, ARROW_CX, ARROW_CY, ARROW_R) {
            fb.draw_line(x0, y0, x1, y1, true);
        }
    }
}

/// Pure Nav map-fit decision (no framebuffer, no peripherals): pick the
/// lat/lon -> panel-pixel transform to draw the breadcrumb with, and report
/// whether it auto-zoomed. A course whose bounding box already fits inside a
/// window-sized box renders whole (the situational overview, as before); a
/// larger one — where the whole-course fit would squeeze forks to sub-pixel —
/// auto-zooms to a fixed span centred on the runner, so the nearest forks stay
/// resolvable. `runner` None (no fix yet) always fits the whole course.
///
/// The auto-zoom window is built as a runner-centred box in *degrees* and fed
/// through `PanelFit`, so the cos-lat correction (and all the trig) stays in
/// `watch_core::course` — `ui.rs` has no `libm`. Fitting a box whose centre is
/// the runner lands the runner at the panel centre.
///
/// Not host-tested: the `app` crate is board-only (`[[bin]] test = false`, no
/// host target, embedded-only deps), and the edit scope for this fix is `ui.rs`
/// alone — the cos-lat geometry it needs is reachable only through `PanelFit`,
/// which stays authoritative. Kept a pure function of its inputs so it could be
/// lifted to a core module (where `cargo test` reaches) if that ever comes into
/// scope; the windowing decision, marker-in-window, and off-window states are
/// what such tests would pin.
fn nav_fit(course: &Course, runner: Option<(f64, f64)>, w: u32, h: u32) -> (PanelFit, bool) {
    let Some((rlat, rlon)) = runner else {
        return (PanelFit::fit(course, w, h), false);
    };
    let mut min_lat = f64::INFINITY;
    let mut max_lat = f64::NEG_INFINITY;
    let mut min_lon = f64::INFINITY;
    let mut max_lon = f64::NEG_INFINITY;
    for p in course.points() {
        min_lat = min_lat.min(p.lat_deg);
        max_lat = max_lat.max(p.lat_deg);
        min_lon = min_lon.min(p.lon_deg);
        max_lon = max_lon.max(p.lon_deg);
    }
    // Fits within a window-sized box -> keep the whole-course overview.
    if (max_lat - min_lat) <= 2.0 * WIN_HALF_LAT_DEG
        && (max_lon - min_lon) <= 2.0 * WIN_HALF_LON_DEG
    {
        return (PanelFit::fit(course, w, h), false);
    }
    // Auto-zoom: fit a fixed-span box centred on the runner. `PanelFit` fits the
    // box's bounding corners, so the runner (the box centre) maps to the panel
    // centre and the surrounding course renders at a readable scale; points
    // outside the box clip in `draw_line`. If the two corners somehow fail to
    // form a course (they never coincide), fall back to the whole-course fit.
    let corners = [
        CoursePoint {
            lat_deg: rlat - WIN_HALF_LAT_DEG,
            lon_deg: rlon - WIN_HALF_LON_DEG,
        },
        CoursePoint {
            lat_deg: rlat + WIN_HALF_LAT_DEG,
            lon_deg: rlon + WIN_HALF_LON_DEG,
        },
    ];
    match Course::from_points(&corners) {
        Some(window) => (PanelFit::fit(&window, w, h), true),
        None => (PanelFit::fit(course, w, h), false),
    }
}

/// The runner's position in a course-anchored integer grid ~1 display pixel per
/// cell — the Nav panel's repaint trigger. In the whole-course fit the marker's
/// own pixel already moves with the runner, so `PanelFit::to_px` is the key. In
/// the auto-zoom window the marker holds at the panel centre (the window
/// recentres on the runner every fix), so the key instead quantises the raw
/// position onto a fixed latitude-degree grid sized to one window pixel; it
/// advances ~1 per pixel of real movement independent of the recentring, and a
/// resting runner leaves it unchanged (so the panel still flushes zero SPI).
/// Longitude shares the latitude grid — slightly coarser in ground metres E-W
/// at high latitude, harmless for a trigger — which keeps this cos-free.
fn track_key(fit: &PanelFit, windowed: bool, lat: f64, lon: f64) -> (i32, i32) {
    if windowed {
        let grid = 2.0 * WIN_HALF_LAT_DEG / PANEL_H_PX as f64;
        (round_i32(lat / grid), round_i32(lon / grid))
    } else {
        fit.to_px(lat, lon)
    }
}

/// Round to the nearest `i32` without `libm` (unavailable in the `app` crate):
/// `as i32` truncates toward zero and saturates out-of-range, so nudging by a
/// half in the value's own direction first gives round-half-away-from-zero.
fn round_i32(v: f64) -> i32 {
    if v >= 0.0 {
        (v + 0.5) as i32
    } else {
        (v - 0.5) as i32
    }
}
