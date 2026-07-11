//! UI task — drives the Sharp MIP status face and the liveness LED.
//!
//! Rendering is delegated: `watch_core::face` decides what the rows say
//! (host-tested), `sharp_mip` turns rows into dirty-line SPI traffic
//! (host-tested). This task owns only the 1 Hz cadence and the peripheral
//! handles. The once-a-second flush doubles as the display's VCOM
//! alternation, which the glass needs regardless of content changes.

use defmt::*;
use embassy_futures::select::{select3, select4, Either3, Either4};
use embassy_nrf::gpio::{AnyPin, Level, Output, OutputDrive};
use embassy_nrf::peripherals::PWM0;
use embassy_nrf::pwm::{DutyCycle, Prescaler, SimpleConfig, SimplePwm};
use embassy_nrf::spim::Spim;
use embassy_nrf::Peri;
use embassy_time::{Duration, Instant, Timer};
use sharp_mip::{Framebuffer, Icon, SharpMip};
use watch_core::alerts::{self, Alert};
use watch_core::course::{Course, PanelFit};
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

// Keep the position marker's 5-px cross inside the panel, so an off-course
// (or clamped off-panel) marker pins at the edge instead of scribbling on the
// text rows above and below.
const MARKER_ARM_PX: i32 = 2;

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
    let mut tb_rx = unwrap!(state::TRACKBACK.receiver());
    let mut sats_rx = unwrap!(state::SATS.receiver());
    let mut latest: Option<Fix> = None;
    let mut hr_bpm: Option<u16> = None;
    let mut rec: Option<Snapshot> = None;
    let mut elev: Option<ElevationReading> = None;
    let mut tb: Option<TrackbackView> = None;
    let mut sats: Option<u8> = None;
    let mut page = Page::default();
    let mut mode = GnssMode::default();
    let mut last_interaction_s: u32 = 0;
    let mut alert: Option<Alert> = None;
    let mut nav = NavView::NoCourse;
    // The course geometry never changes at tier 1, so its panel fit is computed
    // once; (marker, alert) is the panel's whole live state — remembering the
    // last drawn pair lets an unchanged panel skip its redraw entirely.
    let panel = course.map(|c| (c, PanelFit::fit(c, sharp_mip::WIDTH as u32, PANEL_H_PX)));
    let mut last_panel: Option<(Option<(i32, i32)>, bool)> = None;

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
        if let Some(v) = tb_rx.try_changed() {
            tb = Some(v);
        }
        if let Some(s) = sats_rx.try_changed() {
            sats = Some(s);
        }
        let uptime_s = Instant::now().as_secs() as u32;
        // Animate only in the window after a button press; otherwise hold steady
        // frames so an unattended run stops redrawing the display every second.
        let animate = uptime_s.saturating_sub(last_interaction_s) < ANIM_WINDOW_S;
        let rows = face::page_rows(
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
        // cross, drawn into the pixel rows the face leaves empty. The panel's
        // live state is just (marker position, alert shown) — when neither
        // changed the panel rows are skipped below and their pixels stand, so
        // a resting Nav page still flushes zero lines. A repaint first lets
        // draw_text_row blank the rows, then redraws; only lines whose bytes
        // actually changed go dirty.
        let nav_panel = if page == Page::Nav && face::run_view(rec.as_ref()) {
            panel.as_ref()
        } else {
            None
        };
        let marker_px = nav_panel.and_then(|(_, fit)| {
            latest.as_ref().map(|f| {
                let (x, y) = fit.to_px(f.lat_deg, f.lon_deg);
                (
                    x.clamp(MARKER_ARM_PX, sharp_mip::WIDTH as i32 - 1 - MARKER_ARM_PX),
                    (y + PANEL_TOP_PX).clamp(
                        PANEL_TOP_PX + MARKER_ARM_PX,
                        PANEL_TOP_PX + PANEL_H_PX as i32 - 1 - MARKER_ARM_PX,
                    ),
                )
            })
        });
        let nav_alert = face::nav_alert_row(nav);
        let panel_state = nav_panel.map(|_| (marker_px, nav_alert.is_some()));
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
            let (course, fit) = unwrap!(nav_panel);
            for w in course.points().windows(2) {
                let (x0, y0) = fit.to_px(w[0].lat_deg, w[0].lon_deg);
                let (x1, y1) = fit.to_px(w[1].lat_deg, w[1].lon_deg);
                fb.draw_line(x0, y0 + PANEL_TOP_PX, x1, y1 + PANEL_TOP_PX, true);
            }
            if let Some((mx, my)) = marker_px {
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
            let bars = sats.map_or(0, statusbar::bars_for_sats);
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
                Timer::after(tick),
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
            Either3::Third(Either4::Fourth(())) => {}
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
