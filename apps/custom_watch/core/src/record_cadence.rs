//! Task-level cadence + wire-shaping decisions the app's `record` task layers
//! over the [`crate::record`] state machine — the half that used to live inside
//! the async task body and therefore could not be host-tested.
//!
//! [`crate::record`] owns the run maths (distance, moving time, pace, the
//! point-acceptance filter, auto-pause). This module owns the decisions the
//! task makes *around* it: when the 1 Hz wall-clock tick means anything, when
//! the in-progress run is due another best-effort flash checkpoint, how a held
//! HR / barometric altitude narrows into a [`crate::run_store::TrackPoint`]'s
//! frozen field widths, and whether a pushed QNH reference is plausible enough
//! to publish.

use crate::record::RecordState;

/// Whether a run is live: advancing its wall clock and consuming fixes at the
/// selected mode's cadence. Idle and Finished are inert — the `record` task
/// drops its 1 Hz tick there and waits purely on events, and the `gps` task
/// owes only the idle de-rate cadence
/// ([`crate::gnss_cadence::min_interval_s`]). Paused counts as live because an
/// auto-pause resumes off the next moving fix, so it must keep seeing them.
pub const fn run_active(state: RecordState) -> bool {
    matches!(state, RecordState::Recording | RecordState::Paused)
}

/// Mid-run flash-checkpoint cadence. The in-progress run is staged in RAM and
/// only committed to flash at stop, so a battery swap or brown-out mid-run would
/// otherwise lose the whole track. A periodic best-effort checkpoint writes a
/// recoverable blob into the run's slot (`run_flash::RunStore::checkpoint`); the
/// final commit at stop supersedes the last checkpoint (same slot).
///
/// Wear budget: each checkpoint erases one 4 KiB flash page, and the nRF52840's
/// internal flash is rated ~10,000 erase cycles/page. At a 300 s cadence a
/// 100-hour run erases 100·3600/300 = 1,200 times — ~12 % of one page's
/// endurance in a single extreme run — and because a run keeps to a single slot
/// while successive runs round-robin across all 4 slots, real multi-run wear
/// spreads further; a typical sub-24 h ultra is ≤288 erases. A 60 s cadence
/// would burn ~6,000 erases (>½ the page) in one 100 h run, so 300 s is the
/// floor that keeps wear well within endurance.
pub const CHECKPOINT_INTERVAL_S: u32 = 300;

/// Also checkpoint every this many newly-accepted track points, so the early
/// (still-growing) track reaches flash within minutes rather than waiting a full
/// [`CHECKPOINT_INTERVAL_S`]. Bounded by `run_store::MAX_POINTS_PER_RUN`, so at
/// most a handful of point-triggered checkpoints ever fire before the track is
/// full and only the time trigger (refreshing the totals) remains.
pub const CHECKPOINT_POINTS: u32 = 60;

/// Where the last mid-run flash checkpoint left off — the baseline both
/// checkpoint triggers measure against.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct CheckpointMark {
    /// Staged point count at that checkpoint.
    pub points: u32,
    /// Snapshot `elapsed_s` at that checkpoint.
    pub elapsed_s: u32,
}

impl CheckpointMark {
    /// Whether the run staged as `points` points at `elapsed_s` is due another
    /// checkpoint. An empty track never is — there is nothing recoverable to
    /// write yet, so a stopped-at-the-start-line run spends no flash erase.
    pub const fn due(&self, points: u32, elapsed_s: u32) -> bool {
        if points == 0 {
            return false;
        }
        elapsed_s >= self.elapsed_s.saturating_add(CHECKPOINT_INTERVAL_S)
            || points >= self.points.saturating_add(CHECKPOINT_POINTS)
    }
}

/// Altitude in metres → wire-format decimetres, dropping values outside the
/// `i16` decimetre range (about ±3276 m — a frozen
/// [`crate::run_store::TrackPoint`] limit; tier-2 widens it) so an out-of-range
/// reading stores `None`, never a wrong value.
pub fn ele_dm_from_m(alt_m: f32) -> Option<i16> {
    let dm = alt_m * 10.0;
    if dm.is_finite() && dm > i16::MIN as f32 && dm <= i16::MAX as f32 {
        Some(dm as i16)
    } else {
        None
    }
}

/// A held HR estimate ([`crate::hr_duty::shown_bpm`]) → a track point's `bpm`,
/// dropping out-of-`u8` values. Zero is dropped too: the wire format has no
/// sentinel, so a stored 0 would read back as a real 0 bpm pulse.
pub fn bpm_u8(bpm: Option<u16>) -> Option<u8> {
    bpm.and_then(|b| ((1..=255).contains(&b)).then_some(b as u8))
}

/// Plausible QNH sea-level pressure window (Pa). A pushed `sea_level_pa`
/// outside this is ignored — never published — the same "reject, don't clamp"
/// discipline the recorder / alert setters keep for a garbage value. ~870–1080
/// hPa spans every real weather system (record sea-level pressure extremes sit
/// well inside it), so anything outside is a corrupt or misframed push.
pub const MIN_SEA_LEVEL_PA: f32 = 87_000.0;
pub const MAX_SEA_LEVEL_PA: f32 = 108_000.0;

/// Whether a pushed QNH sea-level reference is worth publishing to the baro
/// task. A non-finite value fails, so NaN can never reach the altitude
/// conversion.
pub fn plausible_sea_level_pa(pa: f32) -> bool {
    (MIN_SEA_LEVEL_PA..=MAX_SEA_LEVEL_PA).contains(&pa)
}

#[cfg(test)]
mod tests {
    use super::*;

    const STATES: [RecordState; 4] = [
        RecordState::Idle,
        RecordState::Recording,
        RecordState::Paused,
        RecordState::Finished,
    ];

    #[test]
    fn only_a_live_run_advances_a_clock() {
        assert!(run_active(RecordState::Recording));
        assert!(run_active(RecordState::Paused));
        assert!(!run_active(RecordState::Idle));
        assert!(!run_active(RecordState::Finished));
    }

    #[test]
    fn paused_stays_active_so_auto_pause_can_resume() {
        // The min-move filter parks a genuinely-moving runner in Paused; the
        // resume comes off the next moving fix, so dropping the tick / the fix
        // cadence there would wedge the run paused forever.
        assert!(run_active(RecordState::Paused));
    }

    #[test]
    fn checkpoint_constants_are_pinned() {
        // The wear derivation in the docs is computed from these; drifting them
        // silently would invalidate it (a 60 s cadence burns >½ a page's
        // endurance in one 100 h run).
        assert_eq!((CHECKPOINT_INTERVAL_S, CHECKPOINT_POINTS), (300, 60));
    }

    #[test]
    fn an_empty_track_is_never_checkpointed() {
        // Nothing recoverable is staged yet, so a long idle-at-the-start-line
        // stretch must not spend a flash erase per interval.
        let mark = CheckpointMark::default();
        for elapsed in [0, 300, 3_600, 360_000] {
            assert!(!mark.due(0, elapsed));
        }
    }

    #[test]
    fn time_trigger_fires_exactly_at_the_interval() {
        let mark = CheckpointMark {
            points: 0,
            elapsed_s: 1_000,
        };
        assert!(!mark.due(1, 1_000 + CHECKPOINT_INTERVAL_S - 1));
        assert!(mark.due(1, 1_000 + CHECKPOINT_INTERVAL_S));
    }

    #[test]
    fn point_trigger_fires_exactly_at_the_point_budget() {
        let mark = CheckpointMark {
            points: 10,
            elapsed_s: 0,
        };
        assert!(!mark.due(10 + CHECKPOINT_POINTS - 1, 0));
        assert!(mark.due(10 + CHECKPOINT_POINTS, 0));
    }

    #[test]
    fn either_trigger_alone_is_enough() {
        // Early in a run the point trigger gets the growing track to flash
        // within minutes; once the track is full only the time trigger (which
        // refreshes the totals) can still fire.
        let mark = CheckpointMark {
            points: 200,
            elapsed_s: 500,
        };
        assert!(mark.due(200, 500 + CHECKPOINT_INTERVAL_S), "time only");
        assert!(mark.due(200 + CHECKPOINT_POINTS, 500), "points only");
        assert!(!mark.due(200, 500), "neither");
    }

    #[test]
    fn a_late_mark_saturates_instead_of_wrapping() {
        // A ~136-year uptime must not wrap either next-due threshold into the
        // past and then checkpoint on every single event, burning the page. Both
        // saturate at u32::MAX instead, so the run stays not-yet-due right up to
        // the clamp — where `>=` finally admits it, harmlessly, since elapsed_s
        // cannot advance past u32::MAX either.
        let mark = CheckpointMark {
            points: u32::MAX - 10,
            elapsed_s: u32::MAX - 10,
        };
        assert!(!mark.due(1, u32::MAX - 10));
        assert!(mark.due(1, u32::MAX));
    }

    #[test]
    fn altitude_narrows_to_decimetres() {
        assert_eq!(ele_dm_from_m(0.0), Some(0));
        assert_eq!(ele_dm_from_m(1610.5), Some(16105));
        assert_eq!(ele_dm_from_m(-100.0), Some(-1000));
    }

    #[test]
    fn out_of_range_altitude_stores_nothing_rather_than_a_wrong_value() {
        // The i16 decimetre field is a frozen wire width; a Himalayan or
        // garbage reading must degrade to "no elevation", never to a wrapped
        // one.
        assert_eq!(ele_dm_from_m(4000.0), None);
        assert_eq!(ele_dm_from_m(-4000.0), None);
        assert_eq!(ele_dm_from_m(f32::NAN), None);
        assert_eq!(ele_dm_from_m(f32::INFINITY), None);
        assert_eq!(ele_dm_from_m(f32::NEG_INFINITY), None);
    }

    #[test]
    fn altitude_range_edges_are_inclusive_at_the_top() {
        assert_eq!(ele_dm_from_m(i16::MAX as f32 / 10.0), Some(i16::MAX));
        assert_eq!(ele_dm_from_m(i16::MIN as f32 / 10.0), None);
    }

    #[test]
    fn bpm_narrows_to_a_byte() {
        assert_eq!(bpm_u8(Some(1)), Some(1));
        assert_eq!(bpm_u8(Some(150)), Some(150));
        assert_eq!(bpm_u8(Some(255)), Some(255));
    }

    #[test]
    fn a_dropped_pulse_stores_no_bpm() {
        // None is the blanked reading past its hold budget; 0 and >255 have no
        // honest byte, and the wire format has no sentinel to spend on them.
        assert_eq!(bpm_u8(None), None);
        assert_eq!(bpm_u8(Some(0)), None);
        assert_eq!(bpm_u8(Some(256)), None);
        assert_eq!(bpm_u8(Some(u16::MAX)), None);
    }

    #[test]
    fn sea_level_window_accepts_real_weather_and_rejects_the_rest() {
        assert!(plausible_sea_level_pa(101_325.0));
        assert!(plausible_sea_level_pa(MIN_SEA_LEVEL_PA));
        assert!(plausible_sea_level_pa(MAX_SEA_LEVEL_PA));
        assert!(!plausible_sea_level_pa(MIN_SEA_LEVEL_PA - 1.0));
        assert!(!plausible_sea_level_pa(MAX_SEA_LEVEL_PA + 1.0));
        assert!(!plausible_sea_level_pa(0.0));
    }

    #[test]
    fn a_non_finite_qnh_push_is_rejected() {
        // NaN would poison every altitude the baro task derives from it, and a
        // range comparison against NaN is false — pinned so the guard can never
        // be rewritten into a clamp.
        assert!(!plausible_sea_level_pa(f32::NAN));
        assert!(!plausible_sea_level_pa(f32::INFINITY));
        assert!(!plausible_sea_level_pa(f32::NEG_INFINITY));
    }

    #[test]
    fn run_active_covers_every_state() {
        // A new RecordState variant must be classified deliberately, not fall
        // through whichever arm the matches! happens to have.
        for s in STATES {
            let _ = run_active(s);
        }
        assert_eq!(STATES.iter().filter(|s| run_active(**s)).count(), 2);
    }
}
