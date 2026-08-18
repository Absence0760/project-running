//! The manual QNH re-zero decision — what the app's `baro` task does when the
//! runner long-presses BTN3 on the idle face
//! ([`crate::button::btn3_action`]), lifted out of the async task body so the
//! refusal paths are host-tested rather than only reachable on a bench.
//!
//! [`crate::elevation`] owns the barometric maths: the altitude conversion, the
//! complementary-filter bias, the vert accumulator, and
//! [`rezero_reference`]'s judgement of whether the GPS side is fresh and
//! plausible enough to re-base against. This module owns the *task-level*
//! composition around it — crucially the barometer's own freshness gate.
//!
//! Both sides of the snap get the same [`REZERO_MAX_FIX_AGE_S`] budget: a
//! barometer that stopped answering must read as [`RezeroStatus::NoBaro`], not
//! silently re-base the altitude frame against its last good sample from
//! minutes ago. Every outcome is explicit — a refusal is reported, never a
//! silent no-op, so the face's transient banner can always say what happened.

use crate::elevation::{
    plausible_alt, rezero_reference, Reading, RezeroStatus, VertAccumulator, REZERO_MAX_FIX_AGE_S,
};
use crate::fix::Fix;

/// The most recent barometric altitude and the uptime it was sampled at — what
/// the task carries between samples so a request-time decision can judge how
/// old the barometer's word is.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct BaroSample {
    pub alt_m: f32,
    pub at_s: u32,
}

/// The barometric altitude a re-zero may snap from, or `None` when there is
/// none worth snapping from: no sample yet, a sensor that stopped answering
/// more than [`REZERO_MAX_FIX_AGE_S`] ago, or a reading outside
/// [`plausible_alt`]'s window. A fresh sample is not the same as an honest one,
/// and a sensor answering with nonsense reads as `NoBaro` — the refusal a
/// runner can act on — rather than as a snap onto it.
pub fn fresh_altitude_m(sample: Option<BaroSample>, now_s: u32) -> Option<f32> {
    sample
        .filter(|s| now_s.saturating_sub(s.at_s) <= REZERO_MAX_FIX_AGE_S)
        .and_then(|s| plausible_alt(s.alt_m))
}

/// Resolve a manual re-zero request against the freshest barometer sample and
/// GPS fix, snapping `vert`'s altitude reference when both sides are honest.
///
/// [`RezeroStatus::Applied`] carries the snapped altitude the caller publishes
/// so the face's ALT row moves with the banner rather than a sample later. The
/// two refusals are distinct on purpose: `NoBaro` means the barometer has
/// nothing current to snap *from*, `NoGps` that there is nothing to snap *to*.
/// Only `Applied` mutates `vert`.
pub fn rezero(
    vert: &mut VertAccumulator,
    sample: Option<BaroSample>,
    fix: Option<&Fix>,
    now_s: u32,
) -> RezeroStatus {
    let Some(alt_m) = fresh_altitude_m(sample, now_s) else {
        return RezeroStatus::NoBaro;
    };
    match vert.rezero(alt_m, rezero_reference(fix, now_s)) {
        Some(snapped) => RezeroStatus::Applied(snapped),
        None => RezeroStatus::NoGps,
    }
}

/// The elevation reading a resolved re-zero owes its consumers, or `None` when
/// nothing was applied.
///
/// An [`RezeroStatus::Applied`] snap always yields one, deliberately bypassing
/// [`crate::elevation::should_publish`]: the runner asked for this and the
/// face's banner announces it, so the ALT row must move with the banner even
/// when the snap lands inside the gate's quantum — a snap against a barometer
/// that was already nearly right would otherwise say `SET 1610M` over an
/// unchanged row.
pub fn published_reading(vert: &VertAccumulator, status: RezeroStatus) -> Option<Reading> {
    match status {
        RezeroStatus::Applied(snapped) => Some(vert.reading(snapped)),
        RezeroStatus::NoGps | RezeroStatus::NoBaro => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::elevation::should_publish;

    fn fix_at(alt_m: Option<f32>, uptime_s: u32) -> Fix {
        Fix {
            lat_deg: 40.0,
            lon_deg: -105.0,
            speed_mps: 0.0,
            course_deg: None,
            sats: 8,
            alt_m,
            time_of_day: None,
            date: None,
            uptime_s,
        }
    }

    const SAMPLE: BaroSample = BaroSample {
        alt_m: 1_630.0,
        at_s: 100,
    };

    #[test]
    fn the_barometer_gets_the_same_freshness_budget_as_the_fix() {
        assert_eq!(fresh_altitude_m(Some(SAMPLE), 100), Some(1_630.0));
        assert_eq!(
            fresh_altitude_m(Some(SAMPLE), 100 + REZERO_MAX_FIX_AGE_S),
            Some(1_630.0)
        );
        assert_eq!(
            fresh_altitude_m(Some(SAMPLE), 101 + REZERO_MAX_FIX_AGE_S),
            None
        );
    }

    #[test]
    fn no_sample_yet_is_not_fresh() {
        assert_eq!(fresh_altitude_m(None, 100), None);
    }

    #[test]
    fn a_sample_stamped_ahead_of_the_clock_reads_fresh_not_ancient() {
        // Racing the second boundary must saturate to age zero, not wrap to a
        // huge age and refuse a genuinely current reading.
        assert_eq!(fresh_altitude_m(Some(SAMPLE), 99), Some(1_630.0));
    }

    #[test]
    fn a_wedged_barometer_refuses_instead_of_re_basing_on_a_stale_sample() {
        // The failure this gate exists for: the sensor stopped answering, so
        // the altitude frame must not silently snap against a minutes-old
        // reading — the runner would trust a number derived from nothing.
        let mut vert = VertAccumulator::new();
        let fresh_fix = fix_at(Some(1_600.0), 400);
        assert_eq!(
            rezero(&mut vert, Some(SAMPLE), Some(&fresh_fix), 400),
            RezeroStatus::NoBaro
        );
    }

    #[test]
    fn a_refused_rezero_leaves_the_accumulator_untouched() {
        let mut vert = VertAccumulator::new();
        vert.push(1_000.0, true, None);
        vert.push(1_050.0, true, None);
        let gain = vert.gain_m();
        let loss = vert.loss_m();
        assert_eq!(rezero(&mut vert, None, None, 100), RezeroStatus::NoBaro);
        assert_eq!(
            rezero(&mut vert, Some(SAMPLE), None, 100),
            RezeroStatus::NoGps
        );
        assert_eq!((vert.gain_m(), vert.loss_m()), (gain, loss));
    }

    #[test]
    fn a_fresh_pair_snaps_to_the_gps_altitude() {
        let mut vert = VertAccumulator::new();
        let status = rezero(
            &mut vert,
            Some(SAMPLE),
            Some(&fix_at(Some(1_600.0), 100)),
            100,
        );
        assert_eq!(status, RezeroStatus::Applied(1_600.0));
        // The published reading now carries the snapped altitude, so the face's
        // ALT row moves with the banner.
        assert_eq!(vert.reading(1_600.0).alt_m, 1_600.0);
    }

    #[test]
    fn a_fresh_barometer_with_no_usable_fix_reports_no_gps_not_no_baro() {
        // The two refusals are what the banner distinguishes: "nothing to snap
        // from" versus "nothing to snap to". A stale, altitude-less, or
        // implausible fix is all the second kind.
        let mut vert = VertAccumulator::new();
        for fix in [
            None,
            Some(fix_at(Some(1_600.0), 100 - REZERO_MAX_FIX_AGE_S - 1)),
            Some(fix_at(None, 100)),
            Some(fix_at(Some(f32::NAN), 100)),
        ] {
            assert_eq!(
                rezero(&mut vert, Some(SAMPLE), fix.as_ref(), 100),
                RezeroStatus::NoGps
            );
        }
    }

    #[test]
    fn a_refusal_publishes_nothing() {
        let vert = VertAccumulator::new();
        assert_eq!(published_reading(&vert, RezeroStatus::NoBaro), None);
        assert_eq!(published_reading(&vert, RezeroStatus::NoGps), None);
    }

    #[test]
    fn an_applied_snap_publishes_even_when_the_gate_would_suppress_it() {
        // The barometer was already within the publication gate's quantum of
        // GPS, so `should_publish` sees no news — but the runner pressed the
        // button and the banner will say SET, so the reading goes out anyway.
        let mut vert = VertAccumulator::new();
        let raw = vert.push(1_000.0, true, None).expect("plausible sample");
        let before = vert.reading(raw);
        let sample = BaroSample {
            alt_m: 1_000.0,
            at_s: 100,
        };
        let status = rezero(
            &mut vert,
            Some(sample),
            Some(&fix_at(Some(1_000.05), 100)),
            100,
        );
        assert_eq!(status, RezeroStatus::Applied(1_000.05));
        let after = published_reading(&vert, status).expect("an applied snap publishes");
        assert!(
            !should_publish(Some(before), after),
            "pick a snap the gate really would have suppressed"
        );
    }

    #[test]
    fn a_repeated_rezero_against_the_same_pair_is_idempotent() {
        // A runner mashing the long-press must not walk the altitude frame.
        let mut vert = VertAccumulator::new();
        let fix = fix_at(Some(1_600.0), 100);
        for _ in 0..5 {
            assert_eq!(
                rezero(&mut vert, Some(SAMPLE), Some(&fix), 100),
                RezeroStatus::Applied(1_600.0)
            );
        }
        assert_eq!((vert.gain_m(), vert.loss_m()), (0.0, 0.0));
    }
}
