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
//! The link runs at the receiver's factory-default **38400 baud** (decisions.md
//! § 622), not a configured rate: the breakout's backup cell holds a u-center
//! setting for about a fortnight, so a firmware that assumed anything else would
//! work on the bench and go silent after a holiday.
//!
//! Reads are ring-DMA: the UARTE fills a [`RX_RING_LEN`]-byte ring over
//! EasyDMA in half-buffer transfers, and `BufferedUarte` **pre-arms the next
//! transfer and chains it over PPI** (ENDRX -> STARTRX), so the receiver is
//! never disarmed waiting for a task to run again. A byte-at-a-time loop woke
//! the executor hundreds of times a second; this is the same data for a
//! fraction of the active-CPU time — the DMA-not-polling lever in
//! `docs/custom_watch/performance_path.md`, which ports straight to tier-2.
//!
//! **The ring's depth is what makes a flash write survivable, and its size is
//! derived rather than picked.** An NVMC page erase halts the CPU for ~85 ms —
//! a bus stall, so yielding buys nothing, every other task lives in flash too
//! (decisions.md § 419). The old single 32-byte transfer filled in 8.3 ms at
//! this baud and then sat disarmed, losing up to 326 bytes of NMEA per erase
//! (§ 622): an L4 flash write degrading L1 distance, which the layering
//! contract forbids. The hardware chain removes the disarm, so what remains is
//! ring capacity. `BufferedUarte`'s *guaranteed* headroom is `half_len` —
//! the pre-armed transfer's size, since the in-flight one may be about to end —
//! so at 38400 (3840 B/s) a 512-byte ring buys 256 B = 66.7 ms and does **not**
//! cover one erase, while [`RX_RING_LEN`] = 2048 buys 1024 B = 267 ms, three
//! erases' worth. The 512 figure the earlier notes carried was a 9600 number,
//! where the same ring covered three (§ 622, § 698).
//!
//! `split_with_idle` is **not** the tool for it, even though UARTE1's settings
//! pipe uses exactly that (`phone::settings_rx`, decisions.md § 407): a
//! settings frame is a short burst delimited by silence while NMEA is
//! continuous, so `read_until_idle` would end a transfer two byte-times into
//! every inter-sentence gap and leave the receiver disarmed *more* often, not
//! less. Nor was a bigger single buffer a fix — it lowers the odds of a stall
//! landing in the disarmed window without bounding the loss.
//!
//! One thing the ring fixes that the old read could not: cancellation. The
//! sleep-window `select3` below drops its read future on every wake, and
//! `UarteRx::read` resolves only when its buffer is full, so a cancelled read
//! discarded whatever had already landed in it. `BufferedUarteRx::read` has a
//! single await point — the ring fill — with the copy-out and `consume` after
//! it, so a future dropped while pending leaves every byte in the ring.
//!
use defmt::{debug, info, unwrap, warn};
use embassy_futures::select::{select3, Either3};
use embassy_nrf::buffered_uarte::{BufferedUarteRx, BufferedUarteTx, Error as BufferedError};
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

/// The DMA ring behind the receiver, sized so its guaranteed `half_len`
/// headroom (1024 B = 267 ms at 38400) covers the ~85 ms CPU halt an NVMC page
/// erase costs — see the module header for the derivation. `BufferedUarte`
/// requires an even length.
pub const RX_RING_LEN: usize = 2048;

/// Transmit ring. Only ever carries one UBX frame at a time: a 24-byte
/// `pmreq_backup` or the single wake byte, at most one per fix interval.
pub const TX_RING_LEN: usize = 32;

/// How much of the ring one `read` copies out. Not a DMA transfer size any
/// more — the hardware chain owns those — just the staging chunk the parser is
/// fed in. The parser is byte-stateful, so a sentence split across two reads is
/// fine.
const RX_CHUNK: usize = 32;

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
                // One line per published fix is a complete track of whoever is
                // wearing this, so the coordinates are behind the default-off
                // `log-personal-data` gate; speed + satellites are what the
                // GNSS chain is debugged against and identify no one.
                #[cfg(feature = "log-personal-data")]
                debug!(
                    "gps: fix lat={} lon={} speed={} sats={}",
                    fix.lat_deg, fix.lon_deg, fix.speed_mps, fix.sats
                );
                #[cfg(not(feature = "log-personal-data"))]
                debug!("gps: fix speed={} sats={}", fix.speed_mps, fix.sats);
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

/// Queue a whole frame into the transmit ring. A buffered `write` reports how
/// many bytes it took rather than writing them all, so a single call would
/// silently truncate a frame that met a partly-drained ring — the same trap
/// § 407 named on the read side. It cannot spin: an empty push slice yields
/// `Pending` rather than `Ok(0)`.
async fn write_frame(tx: &mut BufferedUarteTx<'static>, frame: &[u8]) -> Result<(), BufferedError> {
    let mut sent = 0;
    while sent < frame.len() {
        sent += tx.write(&frame[sent..]).await?;
    }
    Ok(())
}

/// Wake a sleeping receiver: any RX-line activity does it, and 0xFF is the
/// documented dummy byte it consumes without parsing. Best-effort — the
/// PMREQ's bounded duration is the self-wake backstop if this write fails.
async fn wake_receiver(tx: &mut BufferedUarteTx<'static>, why: &str) {
    let wake = [ubx::WAKE_BYTE];
    match write_frame(tx, &wake).await {
        Ok(()) => info!("gps: wake byte sent ({=str})", why),
        Err(e) => warn!(
            "gps: wake byte failed {:?} ({=str}); PMREQ backstop will self-wake the receiver",
            e, why
        ),
    }
}

#[embassy_executor::task]
pub async fn run(mut tx: BufferedUarteTx<'static>, mut rx: BufferedUarteRx<'static>) {
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
    let mut buf = [0u8; RX_CHUNK];
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
                Either3::Second(Ok(n)) => {
                    pipe.feed(&buf[..n], min_interval_s(rec_state, mode));
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
            Ok(n) => {
                let published = pipe.feed(&buf[..n], min_interval_s(rec_state, mode));
                let window = published.and_then(|at_s| earned_sleep_window(rec_state, mode, at_s));
                if let Some(w) = window {
                    // Power the receiver down until the next fix is owed.
                    // Best-effort (L4): a failed send leaves it on — the
                    // status-quo full-rate draw, never a lost fix.
                    let frame = ubx::pmreq_backup(w.duration_ms);
                    match write_frame(&mut tx, &frame).await {
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
