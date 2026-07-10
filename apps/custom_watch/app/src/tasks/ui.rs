//! UI task — drives the Sharp MIP status face and the liveness LED.
//!
//! Rendering is delegated: `watch_core::face` decides what the rows say
//! (host-tested), `sharp_mip` turns rows into dirty-line SPI traffic
//! (host-tested). This task owns only the 1 Hz cadence and the peripheral
//! handles. The once-a-second flush doubles as the display's VCOM
//! alternation, which the glass needs regardless of content changes.

use defmt::*;
use embassy_futures::select::{select, select4, Either, Either4};
use embassy_nrf::gpio::{AnyPin, Level, Output, OutputDrive};
use embassy_nrf::peripherals::PWM0;
use embassy_nrf::pwm::{DutyCycle, Prescaler, SimpleConfig, SimplePwm};
use embassy_nrf::spim::Spim;
use embassy_nrf::Peri;
use embassy_time::{Duration, Instant, Timer};
use sharp_mip::{Framebuffer, Icon, SharpMip};
use watch_core::alerts::{self, Alert};
use watch_core::elevation::Reading as ElevationReading;
use watch_core::face::{self, FaceIcon};
use watch_core::fix::Fix;
use watch_core::page::Page;
use watch_core::record::Snapshot;

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
pub async fn screen_task(spim: Spim<'static>, cs: Output<'static>) {
    // Hardware VCOM: EXTCOMIN (driven by vcom_task) carries the bias, so a clean
    // framebuffer flushes nothing and a static screen costs zero SPI.
    let mut display = SharpMip::new_external_vcom(spim, cs);
    let mut fb = Framebuffer::new();
    let mut fix_rx = unwrap!(state::FIX.receiver());
    let mut hr_rx = unwrap!(state::HR.receiver());
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut elev_rx = unwrap!(state::ELEVATION.receiver());
    let mut page_rx = unwrap!(state::PAGE.receiver());
    let mut interaction_rx = unwrap!(state::INTERACTION.receiver());
    let mut alert_rx = unwrap!(state::ALERT.receiver());
    let mut latest: Option<Fix> = None;
    let mut hr_bpm: Option<u16> = None;
    let mut rec: Option<Snapshot> = None;
    let mut elev: Option<ElevationReading> = None;
    let mut page = Page::default();
    let mut last_interaction_s: u32 = 0;
    let mut alert: Option<Alert> = None;

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
        if let Some(t) = interaction_rx.try_changed() {
            last_interaction_s = t;
        }
        if let Some(a) = alert_rx.try_changed() {
            alert = a;
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
            uptime_s,
            animate,
        );
        let icons = face::page_icons(
            page,
            latest.as_ref(),
            hr_bpm,
            rec.as_ref(),
            uptime_s,
            animate,
        );
        for (row, text) in rows.iter().enumerate() {
            fb.draw_text_row(row, text);
            if let Some(icon) = icons[row] {
                fb.draw_icon(0, row, driver_icon(icon));
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
        } else if let Some(hero) = face::page_hero(page, hr_bpm, rec.as_ref()) {
            fb.draw_text_2x(0, 0, &hero);
        }
        if let Err(e) = display.flush(&mut fb) {
            warn!("ui: display flush failed: {:?}", e);
        }

        // Sleep until a state change or the next time-based refresh. Recording
        // wakes us via RECORD snapshots each second; a moving GPS fix wakes us
        // via FIX; a button press via INTERACTION. The only refreshes with no
        // event behind them are the animation frame and the fresh→stale flip.
        let fix_fresh = latest
            .as_ref()
            .is_some_and(|f| uptime_s.saturating_sub(f.uptime_s) <= face::STALE_AFTER_S);
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
            Timer::after(tick),
        );
        // Apply the value the winning `changed()` yields. `changed()` advances
        // the receiver's seen-marker when it resolves, so the top-of-loop
        // `try_changed()` will NOT re-observe it — a one-shot change (a PAGE
        // switch, an INTERACTION stamp) would be lost if we discarded it here.
        // Continuously-updated signals (FIX/RECORD) happen to self-heal on the
        // next tick, but PAGE only changes on a button press. The losing
        // futures are dropped un-consumed, so `try_changed()` still coalesces
        // any other simultaneous changes on the next iteration.
        match select(sensors, controls).await {
            Either::First(Either4::First(fix)) => latest = Some(fix),
            Either::First(Either4::Second(reading)) => {
                hr_bpm = reading.valid.then_some(reading.bpm)
            }
            Either::First(Either4::Third(snap)) => rec = Some(snap),
            Either::First(Either4::Fourth(reading)) => elev = Some(reading),
            Either::Second(Either4::First(p)) => page = p,
            Either::Second(Either4::Second(t)) => last_interaction_s = t,
            Either::Second(Either4::Third(a)) => alert = a,
            Either::Second(Either4::Fourth(())) => {}
        }
    }
}
