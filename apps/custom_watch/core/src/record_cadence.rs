//! Task-level cadence + wire-shaping decisions the app's `record` task layers
//! over the [`crate::record`] state machine — the half that used to live inside
//! the async task body and therefore could not be host-tested.
//!
//! [`crate::record`] owns the run maths (distance, moving time, pace, the
//! point-acceptance filter, auto-pause). This module owns the decisions the
//! task makes *around* it: when the wall-clock tick means anything and how fast
//! it is owed in the state the run is in, when
//! the in-progress run is due another best-effort flash checkpoint, how a held
//! HR / barometric altitude narrows into a [`crate::run_store::TrackPoint`]'s
//! frozen field widths, and whether a pushed QNH reference is plausible enough
//! to publish.

use crate::fix::Fix;
use crate::record::RecordState;
use crate::run_store::TrackPoint;

/// Whether a run is live: advancing its wall clock and consuming fixes at the
/// selected mode's cadence. Idle and Finished are inert — the `record` task
/// drops its 1 Hz tick there and waits purely on events, and the `gps` task
/// owes only the idle de-rate cadence
/// ([`crate::gnss_cadence::min_interval_s`]). Paused counts as live because an
/// auto-pause resumes off the next moving fix, so it must keep seeing them.
pub const fn run_active(state: RecordState) -> bool {
    matches!(state, RecordState::Recording | RecordState::Paused)
}

/// The wall-clock tick the `record` task owes a live run, seconds. Distance,
/// pace and the race clock all move at this resolution and the panel shows them.
pub const TICK_INTERVAL_S: u32 = 1;

/// The tick a **manually** paused run owes instead. A 200-mile racer naps 20-90
/// minutes at a sleep station with the recorder paused, and every one of those
/// seconds woke this task — ~5,400 wakes per nap — for a clock whose only
/// consumers are a second-resolution elapsed row and a nap budget shown in
/// minutes.
///
/// Five seconds, not thirty, because the tick cadence *is* the displayed clock's
/// cadence: `Recorder::tick` advances elapsed through a pause and the `ui` task
/// re-renders off the snapshot, so a 30 s tick would show a runner standing at
/// an aid station a clock that freezes and then jumps half a minute. At 5 s the
/// row is never more than five seconds behind, which still reads as a clock, and
/// the § 373 nap budget — `cut-off margin` less a reserve, rendered in minutes —
/// is at worst 1/12 of its smallest displayed unit stale, so the backoff cannot
/// make it useless. The saving is most of the waste either way: a 90-minute nap
/// goes 5,400 → 1,080 wakes, a 20-minute one 1,200 → 240.
pub const PAUSED_TICK_INTERVAL_S: u32 = 5;

/// Which tick interval the task owes right now.
///
/// Backed off only on a **manual** pause, and that distinction is load-bearing
/// rather than tidy. An auto-pause means the fixes dried up, and the workout
/// runner's clock deliberately runs through one (`Recorder::workout_clock_s`
/// halts on a manual pause only), so a timed recovery step would settle up to
/// five seconds late in exactly the state the runner did not choose. A manual
/// pause is the deliberate "I am stopping here" the sleep station is made of.
///
/// An armed backyard keeps the full-rate clock even manually paused: § 372's
/// corral whistles at 3 / 2 / 1 minutes are folded in on the tick, the format
/// eliminates a runner for being seconds late to the corral, and a warning that
/// can arrive five seconds after its minute is a different instrument.
///
/// Idle and Finished are unreachable here while the task honours
/// [`run_active`], and answering [`TICK_INTERVAL_S`] for them is the fail-safe:
/// a caller that forgets the gate gets today's cadence, never a silently slow
/// clock.
pub const fn tick_interval_s(state: RecordState, manual_paused: bool, backyard_armed: bool) -> u32 {
    if matches!(state, RecordState::Paused) && manual_paused && !backyard_armed {
        PAUSED_TICK_INTERVAL_S
    } else {
        TICK_INTERVAL_S
    }
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
/// `i16` decimetre range (-3276.8 m..=3276.7 m — a frozen
/// [`crate::run_store::TrackPoint`] limit; tier-2 widens it) so an out-of-range
/// reading stores `None`, never a wrong value.
///
/// The range is inclusive at BOTH ends: every `i16` decimetre value is
/// representable, so there is no reason for the bottom of the field to store
/// nothing while the top stores fine. A NaN or infinite metre value compares
/// false against both ends and so is dropped, never saturated.
pub fn ele_dm_from_m(alt_m: f32) -> Option<i16> {
    let dm = alt_m * 10.0;
    (i16::MIN as f32..=i16::MAX as f32)
        .contains(&dm)
        .then_some(dm as i16)
}

/// A held HR estimate ([`crate::hr_duty::shown_bpm`]) → a track point's `bpm`,
/// dropping out-of-`u8` values. Zero is dropped too: the wire format has no
/// sentinel, so a stored 0 would read back as a real 0 bpm pulse.
pub fn bpm_u8(bpm: Option<u16>) -> Option<u8> {
    bpm.and_then(|b| ((1..=255).contains(&b)).then_some(b as u8))
}

/// Shape one accepted fix into the stored track point, stamped with the held HR
/// and the freshest barometric altitude.
///
/// The barometer is preferred over the fix's own GPS altitude — it is the
/// steadier of the two over a climb — but each candidate narrows through
/// [`ele_dm_from_m`] on its own, so an out-of-range barometric reading falls
/// THROUGH to the fix's GPS altitude rather than discarding the elevation
/// entirely: a wild baro value is a bad sensor reading, while the GPS altitude
/// beside it is a real measurement, and storing it beats storing nothing. Only
/// when neither candidate is storable does the point carry no elevation.
pub fn track_point(
    fix: &Fix,
    start_uptime_s: u32,
    bpm: Option<u16>,
    baro_alt_m: Option<f32>,
) -> TrackPoint {
    TrackPoint {
        lat_e7: (fix.lat_deg * 1e7) as i32,
        lon_e7: (fix.lon_deg * 1e7) as i32,
        t_offset_s: fix.uptime_s.saturating_sub(start_uptime_s),
        ele_dm: baro_alt_m
            .and_then(ele_dm_from_m)
            .or_else(|| fix.alt_m.and_then(ele_dm_from_m)),
        bpm: bpm_u8(bpm),
    }
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
    fn a_recording_run_keeps_the_one_second_clock() {
        for manual in [false, true] {
            for backyard in [false, true] {
                assert_eq!(
                    tick_interval_s(RecordState::Recording, manual, backyard),
                    TICK_INTERVAL_S,
                    "manual {manual} backyard {backyard}"
                );
            }
        }
    }

    #[test]
    fn a_manual_pause_backs_the_clock_off() {
        assert_eq!(
            tick_interval_s(RecordState::Paused, true, false),
            PAUSED_TICK_INTERVAL_S
        );
    }

    /// An auto-pause is the fixes drying up, not a decision — and the workout
    /// runner's clock runs through one, so a timed step must not settle late.
    #[test]
    fn an_auto_pause_keeps_the_one_second_clock() {
        assert_eq!(
            tick_interval_s(RecordState::Paused, false, false),
            TICK_INTERVAL_S
        );
    }

    /// A corral whistle that can arrive five seconds after its minute is a
    /// different instrument, so an armed backyard is never backed off.
    #[test]
    fn an_armed_backyard_keeps_the_one_second_clock_through_a_pause() {
        assert_eq!(
            tick_interval_s(RecordState::Paused, true, true),
            TICK_INTERVAL_S
        );
    }

    /// The gate is `run_active`'s job; answering the base rate for the inert
    /// states means forgetting it costs no clock resolution.
    #[test]
    fn the_inert_states_answer_the_base_rate() {
        for state in [RecordState::Idle, RecordState::Finished] {
            assert_eq!(tick_interval_s(state, true, false), TICK_INTERVAL_S);
        }
    }

    /// The backoff is a real one and stays inside the second-resolution row it
    /// feeds — a 30 s tick would show a jumping clock, a 1 s tick saves nothing.
    #[test]
    fn the_paused_interval_is_a_saving_the_display_can_absorb() {
        assert!(PAUSED_TICK_INTERVAL_S > TICK_INTERVAL_S);
        assert!(PAUSED_TICK_INTERVAL_S <= 5, "a jumping elapsed row");
        // A 90-minute nap: the wakes the backoff actually removes.
        let nap_s = 90 * 60;
        assert_eq!(nap_s / TICK_INTERVAL_S, 5_400);
        assert_eq!(nap_s / PAUSED_TICK_INTERVAL_S, 1_080);
    }

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
    fn altitude_range_edges_are_inclusive_at_both_ends() {
        // Both extremes are representable decimetre values, so both store. The
        // bounds used to be asymmetric (`>` at the bottom, `<=` at the top), which
        // silently dropped exactly -3276.8 m while +3276.7 m stored fine.
        assert_eq!(ele_dm_from_m(i16::MAX as f32 / 10.0), Some(i16::MAX));
        assert_eq!(ele_dm_from_m(i16::MIN as f32 / 10.0), Some(i16::MIN));
    }

    #[test]
    fn one_decimetre_past_either_edge_stores_nothing_rather_than_saturating() {
        // `as i16` would clamp to the same edge value, which reads back as a real
        // altitude the runner never reached.
        assert_eq!(ele_dm_from_m((i16::MAX as f32 + 1.0) / 10.0), None);
        assert_eq!(ele_dm_from_m((i16::MIN as f32 - 1.0) / 10.0), None);
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

    fn fix_at(lat_deg: f64, lon_deg: f64, alt_m: Option<f32>, uptime_s: u32) -> Fix {
        Fix {
            lat_deg,
            lon_deg,
            speed_mps: 3.0,
            course_deg: None,
            sats: 8,
            alt_m,
            time_of_day: None,
            date: None,
            uptime_s,
        }
    }

    #[test]
    fn a_track_point_carries_the_fix_scaled_to_e7() {
        let p = track_point(
            &fix_at(40.0158083, -105.2705, None, 1_100),
            1_000,
            Some(150),
            None,
        );
        assert_eq!(p.lat_e7, 400_158_083);
        assert_eq!(p.lon_e7, -1_052_705_000);
        assert_eq!(p.t_offset_s, 100);
        assert_eq!(p.bpm, Some(150));
    }

    #[test]
    fn the_barometric_altitude_is_preferred_over_the_fixs_own() {
        // The barometer is the steadier of the two over a climb, so it wins when
        // both are present, and the GPS altitude is the fallback when it is not.
        let fix = fix_at(40.0, -105.0, Some(1_500.0), 1_000);
        assert_eq!(
            track_point(&fix, 1_000, None, Some(1_610.0)).ele_dm,
            Some(16_100)
        );
        assert_eq!(track_point(&fix, 1_000, None, None).ele_dm, Some(15_000));
        let no_alt = fix_at(40.0, -105.0, None, 1_000);
        assert_eq!(track_point(&no_alt, 1_000, None, None).ele_dm, None);
    }

    #[test]
    fn an_out_of_range_baro_altitude_falls_back_to_the_gps_one() {
        // A wild barometric reading is a bad sensor value; the GPS altitude beside
        // it is a real measurement. Each candidate narrows on its own so the fix's
        // altitude still reaches the wire — the preference used to be picked BEFORE
        // the narrowing, which stored no elevation at all.
        let fix = fix_at(40.0, -105.0, Some(1_500.0), 1_000);
        assert_eq!(
            track_point(&fix, 1_000, None, Some(9_000.0)).ele_dm,
            Some(15_000)
        );
        assert_eq!(
            track_point(&fix, 1_000, None, Some(f32::NAN)).ele_dm,
            Some(15_000)
        );
    }

    #[test]
    fn a_point_stores_no_elevation_only_when_neither_candidate_is_storable() {
        let out_of_range = fix_at(40.0, -105.0, Some(9_000.0), 1_000);
        assert_eq!(
            track_point(&out_of_range, 1_000, None, Some(9_000.0)).ele_dm,
            None
        );
        let no_gps_alt = fix_at(40.0, -105.0, None, 1_000);
        assert_eq!(
            track_point(&no_gps_alt, 1_000, None, Some(9_000.0)).ele_dm,
            None
        );
    }

    #[test]
    fn a_fix_older_than_the_run_start_clamps_its_offset_to_zero() {
        // The run's start uptime and the fix's are stamped by different tasks; a
        // fix that raced the start must not wrap its offset to ~136 years.
        let p = track_point(&fix_at(40.0, -105.0, None, 999), 1_000, None, None);
        assert_eq!(p.t_offset_s, 0);
    }

    #[test]
    fn an_absurd_position_saturates_rather_than_wrapping() {
        // Rust's float-to-int `as` cast saturates, so a corrupt position pins at
        // the i32 ends instead of wrapping to a plausible-looking coordinate on
        // the other side of the planet.
        let p = track_point(&fix_at(1e300, -1e300, None, 1_000), 1_000, None, None);
        assert_eq!((p.lat_e7, p.lon_e7), (i32::MAX, i32::MIN));
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
