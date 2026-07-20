//! GNSS receiver power-down between fixes — the deeper half of the
//! Balanced / Expedition recording modes ([`crate::gnss_mode`]), and the
//! GNSS twin of the HR trade in [`crate::hr_duty`]: those modes throttle
//! *publication* to one fix per 15 s / 60 s, but the u-blox module keeps
//! streaming NMEA continuously and the CPU keeps waking per RX burst to
//! drain it. This module schedules the windows in which the receiver itself
//! is put into backup mode (UBX-RXM-PMREQ over the UART — encoded by
//! `ublox_nmea::ubx`; the tier-1 breakout has no load switch) and woken
//! again in time to deliver the next fix the mode owes. The gps task
//! consumes it: after each *published* fix while a run is Recording it sends
//! the PMREQ, then at [`SleepWindow::wake_at_s`] sends the RX-activity wake
//! byte and drains until the next good fix.
//!
//! **Windows are relative to the last published fix, not phase-locked to
//! uptime-period boundaries** — a deliberate departure from `hr_duty`. The
//! gps task's publication throttle opens `fix_interval_s` after the last
//! publish, wherever that lands, so a boundary-locked wake falls inside its
//! own reacquire margin whenever the publish phase drifts late — and since
//! each publish re-locks the phase, it would stay there, silently never
//! sleeping again. Keying the window off the publish instant guarantees a
//! fixed [`REACQUIRE_S`] of receiver-on margin before the throttle re-opens,
//! every cycle, with no unrecoverable phase.
//!
//! That relation is also what makes the schedule **safe under a receiver
//! that never sleeps** (the Renode sim's UART feed ignores PMREQ): every fix
//! such a receiver delivers inside a sleep window is younger than the mode
//! interval relative to the publish that opened the window — exactly a fix
//! the publication throttle already drops — so sleeping and non-sleeping
//! receivers publish identical sequences, and no fix is ever faked fresher
//! or dropped later than today. Host-pinned below.
//!
//! Constants are **derivations, not measurements** — the tier-1 DK cannot
//! measure power (`docs/custom_watch/performance_path.md`), the same honesty
//! rule as `gnss_mode`'s battery projections and `hr_duty`'s windows:
//!
//! - **[`REACQUIRE_S`] = 5 s.** Backup mode keeps ephemeris + RTC alive, so
//!   the wake is a hot start: ~1 s to first fix under open sky per the
//!   u-blox datasheet class, a few seconds under canopy. 5 s covers the
//!   typical case with margin; a genuinely slower reacquire surfaces
//!   honestly as a stretched fix gap through the face's existing staleness
//!   budget (`face::stale_after_s`) — never as a faked-fresh fix.
//! - **[`MIN_SLEEP_S`] = 5 s.** Below this the backup saving can't outweigh
//!   the reacquisition burn (the `gnss_mode` projection already charges ~3 s
//!   of receiver-on time per duty-cycled fix), so the scheduler stays awake
//!   rather than thrash sleep/wake. This rules Performance (interval 1 s)
//!   out entirely: continuous fixes need a continuously-on receiver.
//! - **[`BACKSTOP_SLACK_S`] = 2 s.** The PMREQ always carries a bounded
//!   duration as the self-wake backstop for a lost wake byte, set this far
//!   *after* the scheduled wake so the two wake paths never race: the wake
//!   byte is the wake, the duration is the recovery. A backstop-woken
//!   receiver still has `REACQUIRE_S - BACKSTOP_SLACK_S` = 3 s before the
//!   throttle re-opens.
//!
//! The saving is deliberately **not** folded into `GnssMode::battery_est_h`:
//! those projections already assume this lever lands (their derivation
//! charges duty-cycled receiver-on time, not continuous), and re-quantifying
//! them honestly needs a PPK2 on real parts — the same rule `hr_duty`
//! followed.

use crate::gnss_mode::GnssMode;

/// Receiver-on margin scheduled ahead of the next owed fix. See the module
/// docs for the hot-start derivation.
pub const REACQUIRE_S: u32 = 5;

/// Shortest sleep worth its reacquisition cost; anything shorter keeps the
/// receiver on.
pub const MIN_SLEEP_S: u32 = 5;

/// How far past the scheduled wake the PMREQ's bounded-duration self-wake
/// backstop fires when the wake byte is lost.
pub const BACKSTOP_SLACK_S: u32 = 2;

/// One receiver power-down window, keyed to the published fix it follows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct SleepWindow {
    /// Uptime second to wake the receiver at (send the wake byte): the
    /// publish instant plus the mode interval, less [`REACQUIRE_S`].
    pub wake_at_s: u32,
    /// Bounded PMREQ duration — the self-wake backstop, [`BACKSTOP_SLACK_S`]
    /// past the scheduled wake. Never 0 (the spec's "no time limit").
    pub duration_ms: u32,
}

/// The power-down window earned by a fix published at `published_at_s` in
/// `mode`, or `None` when the receiver must stay on: Performance (continuous
/// fixes), or any interval too short for a sleep worth its reacquisition.
pub const fn sleep_window(mode: GnssMode, published_at_s: u32) -> Option<SleepWindow> {
    let interval_s = mode.fix_interval_s();
    if interval_s < REACQUIRE_S + MIN_SLEEP_S {
        return None;
    }
    let sleep_s = interval_s - REACQUIRE_S;
    Some(SleepWindow {
        wake_at_s: published_at_s.saturating_add(sleep_s),
        duration_ms: (sleep_s + BACKSTOP_SLACK_S).saturating_mul(1000),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const MODES: [GnssMode; 3] = [
        GnssMode::Performance,
        GnssMode::Balanced,
        GnssMode::Expedition,
    ];

    const THROTTLED: [GnssMode; 2] = [GnssMode::Balanced, GnssMode::Expedition];

    #[test]
    fn performance_never_sleeps() {
        // Continuous ~1 s fixes need a continuously-on receiver.
        for t in [0, 1, 59, 3600, u32::MAX] {
            assert_eq!(sleep_window(GnssMode::Performance, t), None);
        }
    }

    #[test]
    fn window_constants_are_pinned() {
        // The module docs derive the margins from these; drifting them
        // silently would invalidate the derivation — same discipline as
        // hr_duty's window pins.
        assert_eq!((REACQUIRE_S, MIN_SLEEP_S, BACKSTOP_SLACK_S), (5, 5, 2));
        let b = sleep_window(GnssMode::Balanced, 100).unwrap();
        let e = sleep_window(GnssMode::Expedition, 100).unwrap();
        // Balanced: 10 s asleep of every 15; Expedition: 55 of every 60.
        assert_eq!((b.wake_at_s, b.duration_ms), (110, 12_000));
        assert_eq!((e.wake_at_s, e.duration_ms), (155, 57_000));
    }

    #[test]
    fn receiver_wakes_a_reacquire_margin_before_the_throttle_reopens() {
        // The load-bearing invariant: the gps task publishes the next fix no
        // earlier than published_at + interval, and the receiver must be
        // awake — with the full margin to reacquire — by then.
        for mode in THROTTLED {
            for t in [0, 7, 44, 3600, 99_999] {
                let w = sleep_window(mode, t).unwrap();
                assert_eq!(w.wake_at_s + REACQUIRE_S, t + mode.fix_interval_s());
            }
        }
    }

    #[test]
    fn a_receiver_that_never_sleeps_changes_nothing() {
        // The Renode sim ignores PMREQ and keeps streaming. Every fix such a
        // receiver delivers inside the sleep window is younger than the mode
        // interval relative to the publish that opened it — exactly a fix
        // the publication throttle already drops — so the sleeping and
        // non-sleeping receiver publish identical sequences.
        for mode in THROTTLED {
            let t = 123;
            let w = sleep_window(mode, t).unwrap();
            for arrival in t..=w.wake_at_s {
                assert!(arrival - t < mode.fix_interval_s());
            }
        }
    }

    #[test]
    fn wake_byte_leads_the_backstop() {
        // The self-wake duration must fire strictly after the scheduled wake
        // byte (never before — the two wake paths must not race), but early
        // enough that a lost byte still leaves reacquire time before the
        // throttle re-opens.
        for mode in THROTTLED {
            for t in [0, 31, 600] {
                let w = sleep_window(mode, t).unwrap();
                let backstop_at_ms = u64::from(t) * 1000 + u64::from(w.duration_ms);
                assert_eq!(
                    backstop_at_ms,
                    u64::from(w.wake_at_s + BACKSTOP_SLACK_S) * 1000
                );
                assert!(BACKSTOP_SLACK_S < REACQUIRE_S);
            }
        }
    }

    #[test]
    fn duration_is_never_unbounded() {
        // PMREQ duration 0 means "sleep until a wake source fires" — with a
        // lost wake byte, forever. The scheduler must never request it.
        for mode in MODES {
            for t in [0, 1, 3600] {
                if let Some(w) = sleep_window(mode, t) {
                    assert!(w.duration_ms > 0);
                }
            }
        }
    }

    #[test]
    fn every_window_is_worth_its_reacquisition() {
        for mode in MODES {
            if let Some(w) = sleep_window(mode, 1000) {
                assert!(w.wake_at_s - 1000 >= MIN_SLEEP_S);
            }
        }
    }

    #[test]
    fn longer_interval_modes_sleep_longer() {
        // The point of tying the schedule to the mode picker: a mode that
        // trades fix rate for hours must never sleep the receiver less than
        // a higher-fidelity mode.
        let sleep_s = |m: GnssMode| sleep_window(m, 0).map_or(0, |w| w.wake_at_s);
        for pair in MODES.windows(2) {
            assert!(sleep_s(pair[0]) < sleep_s(pair[1]));
        }
    }

    #[test]
    fn windows_are_relative_not_phase_locked() {
        // The failure mode the module docs derive: publish phases that drift
        // late relative to any fixed boundary must still earn the same full
        // window. Awkward phases across several Balanced periods all sleep
        // identically.
        for t in [0, 7, 14, 22, 37, 53] {
            let w = sleep_window(GnssMode::Balanced, t).unwrap();
            assert_eq!(w.wake_at_s - t, 10);
            assert_eq!(w.duration_ms, 12_000);
        }
    }

    #[test]
    fn late_uptime_saturates_instead_of_wrapping() {
        // Uptime near u32::MAX (a ~136-year run) must not wrap the wake time
        // into the past.
        for mode in THROTTLED {
            let w = sleep_window(mode, u32::MAX - 1).unwrap();
            assert_eq!(w.wake_at_s, u32::MAX);
        }
    }
}
