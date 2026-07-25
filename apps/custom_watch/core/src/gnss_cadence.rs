//! Fix publication cadence — the decisions the app's `gps` task makes about
//! *which* of the ~1 Hz fixes streaming off the MAX-M10S it forwards to the
//! recorder / face / phone consumers, and whether the fix it just forwarded
//! earns the receiver a nap.
//!
//! [`crate::gnss_mode`] owns the mode catalogue (interval + projected hours)
//! and [`crate::gnss_power`] owns the receiver power-down schedule. This
//! module is the seam between them and the recording state machine: it answers
//! "what cadence is owed right now" and "may the receiver sleep in this state",
//! which is exactly the logic that used to be inlined in the async task body
//! and therefore untestable.
//!
//! Two cadences exist:
//!
//! - **Idle** (no run): at most one fix per [`IDLE_FIX_MIN_INTERVAL_S`] rather
//!   than every ~1 s, so a standing wrist stops waking the UI, record, and
//!   phone consumers each second for a position nobody is recording.
//! - **Live run** ([`crate::record_cadence::run_active`]): the selected mode's
//!   [`GnssMode::fix_interval_s`] — every fix in Performance (the historical
//!   full-rate path), one per 15 s in Balanced, one per 60 s in Expedition.
//!
//! The receiver may only sleep while a run is actually *Recording*
//! ([`receiver_may_sleep`]). Paused keeps it on because an auto-pause resumes
//! off the next moving fix, and idle keeps it on because the idle face owes a
//! live position within seconds of a glance.

use crate::face::STALE_AFTER_S;
use crate::gnss_mode::GnssMode;
use crate::gnss_power::{sleep_window, SleepWindow};
use crate::record::RecordState;
use crate::record_cadence::run_active;

/// While no run is live, forward at most one fix per this interval instead of
/// every ~1 s fix.
///
/// Held one second under the face's [`STALE_AFTER_S`] freshness budget so the
/// idle status face still shows a locked fix as fresh; a longer gap would flip
/// it to the "searching" state even though GNSS has a lock. The receiver itself
/// stays on while idle: a ~4 s gap is under [`crate::gnss_power::MIN_SLEEP_S`],
/// and the idle face owes a live position within seconds of a glance.
pub const IDLE_FIX_MIN_INTERVAL_S: u32 = STALE_AFTER_S - 1;

/// Minimum seconds between forwarded fixes right now. `1` means every ~1 s fix
/// goes through (Performance while a run is live — the historical full-rate
/// recording path).
pub const fn min_interval_s(state: RecordState, mode: GnssMode) -> u32 {
    if run_active(state) {
        mode.fix_interval_s()
    } else {
        IDLE_FIX_MIN_INTERVAL_S
    }
}

/// Whether a fix completed at `uptime_s` clears the throttle, given the uptime
/// of the last published fix.
///
/// An interval of 1 publishes unconditionally: the uptime clock is
/// second-resolution, so comparing ages would drop a same-second fix the
/// full-rate path delivers today.
pub const fn publish_due(interval_s: u32, uptime_s: u32, last_published_s: u32) -> bool {
    interval_s <= 1 || uptime_s.saturating_sub(last_published_s) >= interval_s
}

/// Whether the receiver may be powered down between the fixes this state owes.
/// Only while Recording: Paused must keep seeing fixes for the auto-pause
/// resume gate, and the idle face wants a live position within seconds.
pub const fn receiver_may_sleep(state: RecordState) -> bool {
    matches!(state, RecordState::Recording)
}

/// The power-down window a fix published at `published_at_s` earns, or `None`
/// when the receiver must stay on — this state does not allow sleeping, or the
/// mode's interval is too short to be worth the reacquisition
/// ([`crate::gnss_power::sleep_window`]).
pub const fn earned_sleep_window(
    state: RecordState,
    mode: GnssMode,
    published_at_s: u32,
) -> Option<SleepWindow> {
    if !receiver_may_sleep(state) {
        return None;
    }
    sleep_window(mode, published_at_s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gnss_power::REACQUIRE_S;

    const MODES: [GnssMode; 3] = [
        GnssMode::Performance,
        GnssMode::Balanced,
        GnssMode::Expedition,
    ];

    const THROTTLED: [GnssMode; 2] = [GnssMode::Balanced, GnssMode::Expedition];

    const INERT: [RecordState; 2] = [RecordState::Idle, RecordState::Finished];

    #[test]
    fn a_live_run_publishes_at_the_selected_modes_cadence() {
        for (mode, interval) in [
            (GnssMode::Performance, 1),
            (GnssMode::Balanced, 15),
            (GnssMode::Expedition, 60),
        ] {
            assert_eq!(min_interval_s(RecordState::Recording, mode), interval);
            assert_eq!(min_interval_s(RecordState::Paused, mode), interval);
        }
    }

    #[test]
    fn an_inert_state_uses_the_idle_de_rate_whatever_the_mode() {
        // The mode picker only governs recording cadence; a standing wrist gets
        // the same de-rate in every mode, so an Expedition runner still sees a
        // live idle-face position.
        for state in INERT {
            for mode in MODES {
                assert_eq!(min_interval_s(state, mode), IDLE_FIX_MIN_INTERVAL_S);
            }
        }
    }

    #[test]
    fn the_idle_de_rate_stays_inside_the_faces_freshness_budget() {
        // A gap at or past STALE_AFTER_S would flip the idle face to
        // "searching" while GNSS actually has a lock — the de-rate crying wolf
        // about itself.
        assert!(IDLE_FIX_MIN_INTERVAL_S < STALE_AFTER_S);
        assert_eq!(IDLE_FIX_MIN_INTERVAL_S, 4);
    }

    #[test]
    fn performance_never_drops_a_fix() {
        // Interval 1 is the historical full-rate path: the second-resolution
        // clock must not let an age comparison drop a same-second fix.
        for uptime in [0, 1, 42, u32::MAX] {
            assert!(publish_due(1, uptime, uptime));
        }
        assert!(publish_due(0, 5, 5), "an interval of 0 is not a throttle");
    }

    #[test]
    fn a_throttled_fix_publishes_exactly_at_the_interval() {
        for interval in [4, 15, 60] {
            let last = 1_000;
            assert!(!publish_due(interval, last, last), "same second");
            assert!(
                !publish_due(interval, last + interval - 1, last),
                "one short"
            );
            assert!(publish_due(interval, last + interval, last), "on the nose");
            assert!(publish_due(interval, last + interval + 1, last));
        }
    }

    #[test]
    fn a_fix_stamped_before_the_last_publish_is_dropped_not_wrapped() {
        // Clock skew between the parse instant and the stored publish instant
        // must saturate to age zero, never wrap to a huge age that would let a
        // stale fix through the throttle.
        assert!(!publish_due(15, 100, 200));
        assert!(publish_due(1, 100, 200), "full rate still publishes");
    }

    #[test]
    fn only_recording_lets_the_receiver_sleep() {
        assert!(receiver_may_sleep(RecordState::Recording));
        assert!(!receiver_may_sleep(RecordState::Paused));
        for state in INERT {
            assert!(!receiver_may_sleep(state));
        }
    }

    #[test]
    fn a_paused_run_keeps_the_receiver_on() {
        // The auto-pause resumes off the next moving fix, so sleeping the
        // receiver while Paused could strand a moving runner in Paused for a
        // whole mode interval.
        for mode in MODES {
            assert_eq!(earned_sleep_window(RecordState::Paused, mode, 100), None);
        }
    }

    #[test]
    fn no_state_but_recording_earns_a_window() {
        for state in INERT {
            for mode in MODES {
                assert_eq!(earned_sleep_window(state, mode, 100), None);
            }
        }
    }

    #[test]
    fn performance_earns_no_window_even_while_recording() {
        // Continuous ~1 s fixes need a continuously-on receiver.
        assert_eq!(
            earned_sleep_window(RecordState::Recording, GnssMode::Performance, 100),
            None
        );
    }

    #[test]
    fn a_throttled_recording_wakes_before_the_throttle_reopens() {
        // The load-bearing tie between the two halves: the receiver must be
        // awake, with its full reacquire margin, by the time this module's
        // throttle would publish the next fix.
        for mode in THROTTLED {
            for at in [0, 7, 44, 3_600] {
                let w = earned_sleep_window(RecordState::Recording, mode, at).unwrap();
                assert_eq!(
                    w.wake_at_s + REACQUIRE_S,
                    at + min_interval_s(RecordState::Recording, mode)
                );
            }
        }
    }

    #[test]
    fn every_fix_arriving_inside_a_window_is_one_the_throttle_drops() {
        // Why a receiver that ignores PMREQ (the Renode sim) changes nothing:
        // each fix delivered before the scheduled wake is younger than the mode
        // interval relative to the publish that opened the window.
        for mode in THROTTLED {
            let at = 500;
            let w = earned_sleep_window(RecordState::Recording, mode, at).unwrap();
            let interval = min_interval_s(RecordState::Recording, mode);
            for arrival in at..=w.wake_at_s {
                assert!(!publish_due(interval, arrival, at));
            }
        }
    }
}
