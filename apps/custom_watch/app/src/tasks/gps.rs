//! GPS task — reads NMEA from the u-blox MAX-M10S over UARTE0, parses
//! sentences, publishes merged fixes to `state::FIX`, and powers the
//! receiver down between the fixes a throttled recording mode owes.
//!
//! Thin glue by design: byte assembly + parsing live in `ublox_nmea`,
//! RMC/GGA merging in `watch_core::fix`, the publication cadence + the
//! may-the-receiver-sleep decision in `watch_core::gnss_cadence`, the
//! power-down schedule in `watch_core::gnss_power`, the GSV/GSA signal-meter
//! gate in `watch_core::gnss_signal` — all host-tested. This task only moves
//! bytes between the peripheral and those modules.
//!
//! Publication is **throttled to the cadence the current situation needs**
//! (`gnss_cadence::min_interval_s`), generalised from the original idle-only
//! de-rate:
//!
//! - **Idle** (no run): at most one fix per
//!   `gnss_cadence::IDLE_FIX_MIN_INTERVAL_S` rather than every ~1 s, so a
//!   standing wrist stops waking the UI / record / phone consumers each second
//!   for a position nobody is recording.
//! - **Recording / Paused**: the selected `state::GNSS_MODE`'s
//!   `fix_interval_s` — every fix in Performance (interval 1, the historical
//!   full-rate path), one per 15 s in Balanced, one per 60 s in Expedition
//!   (`watch_core::gnss_mode`).
//!
//! The GSV/GSA side channel is throttled on the same principle. The parser
//! emits one `Sentence::Gsv` per GSV *sentence*, so a multi-sentence group
//! repeats its in-view total several times a second and a multi-constellation
//! receiver stacks a group per constellation on top; GSA adds one more.
//! Publishing each of them woke the screen task for a meter that had not
//! moved, so the pair goes out as one `gnss_signal::SignalSample` only when
//! `gnss_signal::should_publish` says the drawn bar count would change.
//!
//! On top of the throttle, **the receiver itself now sleeps between the
//! fixes a throttled mode owes** — the deeper win the README's power
//! discipline owed: while a run is *Recording* in Balanced / Expedition,
//! each published fix earns a `gnss_power::sleep_window`, the task sends
//! UBX-RXM-PMREQ (backup mode, bounded duration — `ublox_nmea::ubx`) on the
//! module's UART, and at the scheduled wake writes the 0xFF RX-activity wake
//! byte, leaving the reacquire margin before the next fix is due. Paused and
//! idle keep the receiver on (an auto-pause resumes off the next moving fix;
//! the idle face wants a live position within seconds), and a run-state
//! change mid-window wakes the receiver early. Everything is best-effort /
//! L4: a failed PMREQ or wake write only costs the power it was meant to
//! save — the receiver stays (or self-wakes) on, never a lost fix. The
//! Renode sim's UART feed ignores PMREQ entirely; that is tolerated by
//! construction, because every fix a never-sleeping receiver delivers inside
//! a sleep window is one the publication throttle already drops (host-pinned
//! in `gnss_power`). The receiver's *actual* power state is bench-gated
//! until the dev kit lands.
//!
//! Reads are burst-DMA: the UARTE fills an [`RX_BURST`]-byte buffer over
//! EasyDMA and wakes the CPU once per buffer, not once per byte. A
//! byte-at-a-time loop woke the executor hundreds of times a second at 9600
//! baud; the burst read is the same data for a fraction of the active-CPU
//! time — the DMA-not-polling lever in `docs/custom_watch/performance_path.md`,
//! which ports straight to tier-2. (The further refinement is idle-line
//! detection via `split_with_idle` so a buffer never waits on the next burst to
//! fill; it needs a free TIMER + 2 PPI channels and can't be Renode-verified,
//! so it's a tier-2 profiling item, not a bench-prototype one.)

use defmt::{debug, info, unwrap, warn};
use embassy_futures::select::{select3, Either3};
use embassy_nrf::uarte::{UarteRx, UarteTx};
use embassy_sync::watch::DynSender;
use embassy_time::{Duration, Instant, Timer};
use ublox_nmea::{ubx, Parser, Sentence};
use watch_core::fix::{Fix, FixAccumulator};
use watch_core::gnss_cadence::{
    earned_sleep_window, min_interval_s, publish_due, receiver_may_sleep,
};
use watch_core::gnss_mode::GnssMode;
use watch_core::gnss_power::SleepWindow;
use watch_core::gnss_signal::{self, SignalSample};
use watch_core::record::RecordState;

use crate::state;

/// Burst-read size. Small enough to bound the tail latency (a partly-filled
/// buffer waits for the next bytes to top it off) while cutting UART wakes ~30x
/// versus one byte per read at 9600 baud. The parser is byte-stateful, so a
/// sentence split across two reads is fine.
const RX_BURST: usize = 32;

/// The parse→merge→publish pipeline both loop branches feed: byte assembly +
/// sentence parsing (`ublox_nmea`), best-effort GSV/GSA side channels, RMC/GGA
/// merging (`watch_core::fix`), and the publication throttle.
struct Pipeline {
    parser: Parser,
    acc: FixAccumulator,
    fix_tx: DynSender<'static, Fix>,
    signal_tx: DynSender<'static, SignalSample>,
    signal: SignalSample,
    published_signal: Option<SignalSample>,
    last_published_s: u32,
}

impl Pipeline {
    /// Feed one burst buffer through the pipeline; returns the uptime a fix
    /// was published at, if this buffer completed one that cleared the
    /// throttle.
    fn feed(&mut self, buf: &[u8], interval_s: u32) -> Option<u32> {
        let mut published = None;
        for &b in buf {
            let Some(sentence) = self.parser.feed(b) else {
                continue;
            };
            let uptime_s = Instant::now().as_secs() as u32;
            // Best-effort satellite count + GSA fix mode for an honest signal
            // meter (L4): tracked alongside the fix pipeline, never gating it.
            // Fix mode lets the meter read "searching" on a no-fix even under a
            // full sky in view.
            match sentence {
                Sentence::Gsv { sats_in_view } => {
                    self.signal.sats = sats_in_view;
                    self.publish_signal();
                }
                Sentence::Gsa { fix_type, .. } => {
                    self.signal.fix_type = fix_type;
                    self.publish_signal();
                }
                _ => {}
            }
            if let Some(fix) = self.acc.apply(&sentence, uptime_s) {
                // Throttle to the cadence in force: the idle de-rate, or the
                // selected mode's interval while a run is live
                // (`gnss_cadence::publish_due`).
                if !publish_due(interval_s, uptime_s, self.last_published_s) {
                    continue;
                }
                self.last_published_s = uptime_s;
                debug!(
                    "gps: fix lat={} lon={} speed={} sats={}",
                    fix.lat_deg, fix.lon_deg, fix.speed_mps, fix.sats
                );
                self.fix_tx.send(fix);
                published = Some(uptime_s);
            }
        }
        published
    }

    fn publish_signal(&mut self) {
        if gnss_signal::should_publish(self.published_signal, self.signal) {
            self.published_signal = Some(self.signal);
            self.signal_tx.send(self.signal);
        }
    }
}

/// Wake a sleeping receiver: any RX-line activity does it, and 0xFF is the
/// documented dummy byte it consumes without parsing. Best-effort — the
/// PMREQ's bounded duration is the self-wake backstop if this write fails.
async fn wake_receiver(tx: &mut UarteTx<'static>, why: &str) {
    let wake = [ubx::WAKE_BYTE];
    match tx.write(&wake).await {
        Ok(()) => info!("gps: wake byte sent ({=str})", why),
        Err(e) => warn!(
            "gps: wake byte failed {:?} ({=str}); PMREQ backstop will self-wake the receiver",
            e, why
        ),
    }
}

#[embassy_executor::task]
pub async fn run(mut tx: UarteTx<'static>, mut rx: UarteRx<'static>) {
    let mut pipe = Pipeline {
        parser: Parser::new(),
        acc: FixAccumulator::new(),
        fix_tx: state::FIX.dyn_sender(),
        signal_tx: state::SIGNAL.dyn_sender(),
        signal: SignalSample::default(),
        published_signal: None,
        last_published_s: 0,
    };
    let mut rec_rx = unwrap!(state::RECORD.receiver());
    let mut mode_rx = unwrap!(state::GNSS_MODE.receiver());
    let mut buf = [0u8; RX_BURST];
    let mut rec_state = RecordState::Idle;
    let mut mode = GnssMode::default();
    // The window a sent PMREQ opened, `None` while the receiver is (believed)
    // on. The mode is frozen mid-run (BTN3 cycles pages then), so a window
    // never spans a mode change.
    let mut sleep: Option<SleepWindow> = None;
    info!("gps: listening on UARTE0");
    loop {
        // Pick up run start/stop and mode changes without blocking on them;
        // buffers arrive every few tens of ms while the GNSS streams, so a
        // change is observed well within a fix interval.
        if let Some(snap) = rec_rx.try_changed() {
            rec_state = snap.state;
        }
        if let Some(m) = mode_rx.try_changed() {
            mode = m;
            info!(
                "gps: mode {} — forwarding one fix per {=u32}s while recording",
                mode,
                mode.fix_interval_s()
            );
        }

        if let Some(w) = sleep {
            // Receiver believed asleep (PMREQ sent). Wait for the wake time —
            // or a run-state change ending the recording the window was for —
            // while still draining the UART: the Renode sim ignores PMREQ and
            // keeps streaming, and every fix arriving inside the window is
            // younger than the mode interval, i.e. one the publication
            // throttle drops anyway (host-pinned in `gnss_power`). The timer
            // leads the select so a stream that never pauses can't starve the
            // wake past its slot.
            match select3(
                Timer::at(Instant::from_secs(u64::from(w.wake_at_s))),
                rx.read(&mut buf),
                rec_rx.changed(),
            )
            .await
            {
                Either3::First(()) => {
                    wake_receiver(&mut tx, "window over").await;
                    sleep = None;
                }
                Either3::Second(Ok(())) => {
                    pipe.feed(&buf, min_interval_s(rec_state, mode));
                }
                Either3::Second(Err(e)) => {
                    warn!("gps: uart read error {:?}, backing off", e);
                    Timer::after(Duration::from_millis(100)).await;
                }
                Either3::Third(snap) => {
                    rec_state = snap.state;
                    if !receiver_may_sleep(rec_state) {
                        // The run stopped or paused mid-window: the idle face
                        // (or the pause's resume gate) wants live fixes now,
                        // not at the next scheduled wake.
                        wake_receiver(&mut tx, "run state changed").await;
                        sleep = None;
                    }
                }
            }
            continue;
        }

        match rx.read(&mut buf).await {
            Ok(()) => {
                let published = pipe.feed(&buf, min_interval_s(rec_state, mode));
                let window = published.and_then(|at_s| earned_sleep_window(rec_state, mode, at_s));
                if let Some(w) = window {
                    // Power the receiver down until the next fix is owed.
                    // Best-effort (L4): a failed send leaves it on — the
                    // status-quo full-rate draw, never a lost fix.
                    let frame = ubx::pmreq_backup(w.duration_ms);
                    match tx.write(&frame).await {
                        Ok(()) => {
                            info!(
                                "gps: receiver to backup until {=u32}s ({=u32} ms backstop)",
                                w.wake_at_s, w.duration_ms
                            );
                            sleep = Some(w);
                        }
                        Err(e) => warn!("gps: PMREQ send failed {:?}; receiver stays on", e),
                    }
                }
            }
            Err(e) => {
                warn!("gps: uart read error {:?}, backing off", e);
                Timer::after(Duration::from_millis(100)).await;
            }
        }
    }
}
