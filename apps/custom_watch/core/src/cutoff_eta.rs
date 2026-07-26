//! Live next-cutoff ETA — the spectator-side cutoff projection.
//!
//! A parity port of web `runs/live_cutoff_eta.ts` `nextCutoffEta` (twin of
//! `live_cutoff_eta.dart`): from a runner's current distance-along-route +
//! recent pace, find the nearest cutoff still ahead and project whether they
//! will make it — [`On`](CutoffEtaStatus::On) / [`Tight`](CutoffEtaStatus::Tight)
//! / [`Behind`](CutoffEtaStatus::Behind). The projection is deliberately FLAT
//! pace (no grade adjustment), the same honest simplification the app makes.
//!
//! The honesty rule that justifies [`Unknown`](CutoffEtaStatus::Unknown): when
//! the live fix is **stale** — or the recent pace is unknown or non-positive —
//! withhold the time entirely rather than fabricate an arrival off an old
//! position, so a lost-signal runner never reads as "on pace". The checkpoint
//! *distance* is still reported in that case; only the projected time and
//! margin go `None`. [`CUTOFF_TIGHT_S`] is the same 30-minute "tight" span the
//! app's roadbook + checkpoint-projection surfaces share.
//!
//! [`CutoffEta::required_pace_s_per_km`] is the flip side of the projection:
//! the flat pace the runner must average over the remaining distance to arrive
//! exactly at the limit. Unlike the ETA it does NOT depend on recent pace, so
//! it is still computed when the fix is stale or the pace is unknown — a runner
//! with no recent pace still deserves "you need 6:30s to make it".
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

/// Margin under which a made cutoff still reads as "tight" — 30 minutes, the
/// app's shared `CUTOFF_TIGHT_S`.
pub const CUTOFF_TIGHT_S: u32 = 1800;

/// Whether the runner is projected to make the next cutoff, or [`Unknown`] when
/// the fix is too stale (or the pace too uncertain) to project honestly.
///
/// [`Unknown`]: CutoffEtaStatus::Unknown
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum CutoffEtaStatus {
    #[default]
    Unknown,
    On,
    Tight,
    Behind,
}

/// One cutoff along the route.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CutoffLeg {
    /// Distance from route start to this cutoff, metres.
    pub cum_dist_m: f64,
    /// Elapsed-seconds limit to reach it.
    pub limit_elapsed_s: u32,
}

/// The next-cutoff projection at the runner's current position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CutoffEta {
    /// `false` when no cutoff remains ahead — hide the card.
    pub has_cutoff: bool,
    /// Distance from the runner to the next cutoff, metres; 0 when none.
    pub distance_to_m: f64,
    /// Projected arrival as elapsed seconds from the start; `None` when unknown.
    pub projected_arrival_elapsed_s: Option<u32>,
    /// `limit - projected`, signed seconds; `None` when unknown.
    pub margin_s: Option<i32>,
    /// Flat pace (s/km) needed over the remaining distance to hit the limit
    /// exactly; independent of recent pace, so present even when the status is
    /// [`Unknown`](CutoffEtaStatus::Unknown). `None` when there is no cutoff
    /// ahead, when it is under 50 m out, or when the limit has passed.
    pub required_pace_s_per_km: Option<f64>,
    /// The cutoff's limit is already in the past — no pace can make it. The
    /// explicit flag exists because [`required_pace_s_per_km`] is `None` for
    /// TWO reasons (limit passed / too close to project a meaningful pace) and
    /// a "you cannot make it" surface must never fire from the second.
    ///
    /// [`required_pace_s_per_km`]: CutoffEta::required_pace_s_per_km
    pub limit_passed: bool,
    pub status: CutoffEtaStatus,
}

/// Project arrival at the nearest cutoff strictly ahead of the runner. `legs`
/// need not be sorted — the nearest-ahead is picked by smallest `cum_dist_m`.
/// Distances are metres, times seconds, pace seconds per km.
pub fn next_cutoff_eta(
    dist_along_route_m: f64,
    elapsed_s: u32,
    recent_pace_s_per_km: Option<f64>,
    stale: bool,
    legs: &[CutoffLeg],
) -> CutoffEta {
    let mut nearest: Option<CutoffLeg> = None;
    for leg in legs {
        if leg.cum_dist_m > dist_along_route_m {
            match nearest {
                Some(n) if n.cum_dist_m <= leg.cum_dist_m => {}
                _ => nearest = Some(*leg),
            }
        }
    }

    let Some(leg) = nearest else {
        return CutoffEta {
            has_cutoff: false,
            distance_to_m: 0.0,
            projected_arrival_elapsed_s: None,
            margin_s: None,
            required_pace_s_per_km: None,
            limit_passed: false,
            status: CutoffEtaStatus::Unknown,
        };
    };

    let distance_to_m = leg.cum_dist_m - dist_along_route_m;
    let remaining_s = f64::from(leg.limit_elapsed_s) - f64::from(elapsed_s);
    let limit_passed = remaining_s <= 0.0;
    let required_pace_s_per_km = if distance_to_m >= 50.0 && remaining_s > 0.0 {
        Some(remaining_s / (distance_to_m / 1000.0))
    } else {
        None
    };

    let pace = match recent_pace_s_per_km {
        Some(p) if p > 0.0 && !stale => p,
        _ => {
            return CutoffEta {
                has_cutoff: true,
                distance_to_m,
                projected_arrival_elapsed_s: None,
                margin_s: None,
                required_pace_s_per_km,
                limit_passed,
                status: CutoffEtaStatus::Unknown,
            };
        }
    };

    let projected = elapsed_s as f64 + (distance_to_m / 1000.0) * pace;
    let margin = leg.limit_elapsed_s as f64 - projected;
    let status = if margin < 0.0 {
        CutoffEtaStatus::Behind
    } else if margin < CUTOFF_TIGHT_S as f64 {
        CutoffEtaStatus::Tight
    } else {
        CutoffEtaStatus::On
    };

    CutoffEta {
        has_cutoff: true,
        distance_to_m,
        projected_arrival_elapsed_s: Some(libm::round(projected) as u32),
        margin_s: Some(libm::round(margin) as i32),
        required_pace_s_per_km,
        limit_passed,
        status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HALFWAY: CutoffLeg = CutoffLeg {
        cum_dist_m: 20000.0,
        limit_elapsed_s: 7200,
    };
    const FINISH_GATE: CutoffLeg = CutoffLeg {
        cum_dist_m: 40000.0,
        limit_elapsed_s: 18000,
    };

    /// The default input: 10 km in at 1:00:00 elapsed, running 6:00/km, fresh.
    fn eta(dist: f64, pace: Option<f64>, stale: bool, legs: &[CutoffLeg]) -> CutoffEta {
        next_cutoff_eta(dist, 3600, pace, stale, legs)
    }

    #[test]
    fn on_pace_grades_on() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(180.0), false, &legs);
        assert!((e.distance_to_m - 10000.0).abs() < 1e-9);
        assert_eq!(e.projected_arrival_elapsed_s, Some(5400));
        assert_eq!(e.margin_s, Some(1800));
        assert_eq!(e.status, CutoffEtaStatus::On);
    }

    #[test]
    fn just_under_tight_threshold_is_tight() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(180.1), false, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Tight);
        assert_eq!(e.margin_s, Some(1799));
    }

    #[test]
    fn negative_margin_is_behind() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(540.0), false, &legs);
        assert_eq!(e.projected_arrival_elapsed_s, Some(9000));
        assert_eq!(e.margin_s, Some(-1800));
        assert_eq!(e.status, CutoffEtaStatus::Behind);
    }

    #[test]
    fn stale_fix_is_unknown_but_keeps_checkpoint() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(180.0), true, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
        assert_eq!(e.projected_arrival_elapsed_s, None);
        assert_eq!(e.margin_s, None);
        assert!(e.has_cutoff);
        assert!((e.distance_to_m - 10000.0).abs() < 1e-9);
    }

    #[test]
    fn null_pace_is_unknown() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, None, false, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
        assert_eq!(e.projected_arrival_elapsed_s, None);
        assert_eq!(e.margin_s, None);
        assert!(e.has_cutoff);
    }

    #[test]
    fn zero_pace_is_unknown() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(0.0), false, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
        assert_eq!(e.projected_arrival_elapsed_s, None);
    }

    #[test]
    fn negative_pace_is_unknown() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(-5.0), false, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
    }

    #[test]
    fn past_the_last_cutoff_has_no_checkpoint() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(40000.0, Some(180.0), false, &legs);
        assert!(!e.has_cutoff);
        assert_eq!(e.distance_to_m, 0.0);
        assert_eq!(e.projected_arrival_elapsed_s, None);
        assert_eq!(e.margin_s, None);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
    }

    #[test]
    fn picks_the_nearest_cutoff_ahead() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(5000.0, Some(180.0), false, &legs);
        assert!((e.distance_to_m - 15000.0).abs() < 1e-9);
    }

    #[test]
    fn ignores_cutoffs_behind_the_runner() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(25000.0, Some(180.0), false, &legs);
        assert!((e.distance_to_m - 15000.0).abs() < 1e-9);
    }

    #[test]
    fn empty_legs_has_no_checkpoint() {
        let e = eta(10000.0, Some(180.0), false, &[]);
        assert!(!e.has_cutoff);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
    }

    #[test]
    fn exactly_at_a_cutoff_treats_it_as_behind() {
        let legs = [HALFWAY, FINISH_GATE];
        // The 20 km cutoff is NOT ahead (strict >), so the nearest is the gate.
        let e = eta(20000.0, Some(180.0), false, &legs);
        assert!((e.distance_to_m - 20000.0).abs() < 1e-9);
    }

    #[test]
    fn cutoff_tight_s_is_thirty_minutes() {
        assert_eq!(CUTOFF_TIGHT_S, 1800);
    }

    #[test]
    fn nan_pace_is_unknown() {
        // The `p > 0.0` guard rejects NaN (NaN > 0.0 is false), so a corrupt pace
        // withholds the ETA rather than fabricating a NaN "on pace" arrival.
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(f64::NAN), false, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
        assert_eq!(e.projected_arrival_elapsed_s, None);
        assert_eq!(e.margin_s, None);
        assert!(e.has_cutoff);
    }

    #[test]
    fn nan_distance_along_route_has_no_checkpoint() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(f64::NAN, Some(180.0), false, &legs);
        assert!(!e.has_cutoff);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
    }

    #[test]
    fn stale_beats_a_good_pace_regardless_of_leg_order() {
        // The staleness gate runs after nearest-selection, so no leg ordering can
        // sneak a confident ETA past a stale fix.
        let legs = [FINISH_GATE, HALFWAY];
        let e = eta(10000.0, Some(180.0), true, &legs);
        assert_eq!(e.status, CutoffEtaStatus::Unknown);
        assert_eq!(e.projected_arrival_elapsed_s, None);
        assert!((e.distance_to_m - 10000.0).abs() < 1e-9);
    }

    #[test]
    fn a_multi_day_ultra_projects_a_finite_arrival() {
        let leg = CutoffLeg {
            cum_dist_m: 386_000.0,
            limit_elapsed_s: 400_000,
        };
        // 200 km in at 200_000 s elapsed, hiking 300 s/km.
        let e = next_cutoff_eta(200_000.0, 200_000, Some(300.0), false, &[leg]);
        assert!((e.distance_to_m - 186_000.0).abs() < 1e-9);
        assert_eq!(e.projected_arrival_elapsed_s, Some(255_800));
        assert_eq!(e.margin_s, Some(144_200));
        assert_eq!(e.status, CutoffEtaStatus::On);
    }

    #[test]
    fn required_pace_is_the_remaining_budget_over_the_remaining_distance() {
        // 7200 limit - 3600 elapsed = 3600 s left over 10 km → 360 s/km.
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(360.0), false, &legs);
        assert_eq!(e.required_pace_s_per_km, Some(360.0));
    }

    #[test]
    fn no_checkpoint_means_no_required_pace() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(40000.0, Some(180.0), false, &legs);
        assert!(!e.has_cutoff);
        assert_eq!(e.required_pace_s_per_km, None);
    }

    #[test]
    fn a_cutoff_under_fifty_metres_away_has_no_meaningful_required_pace() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(19960.0, Some(360.0), false, &legs);
        assert!((e.distance_to_m - 40.0).abs() < 1e-9);
        assert_eq!(e.required_pace_s_per_km, None);
        assert_eq!(e.status, CutoffEtaStatus::On);
    }

    #[test]
    fn a_limit_already_passed_cannot_be_made_at_any_pace() {
        let legs = [HALFWAY, FINISH_GATE];
        for elapsed_s in [7200, 8000] {
            let e = next_cutoff_eta(10000.0, elapsed_s, Some(360.0), false, &legs);
            assert_eq!(e.required_pace_s_per_km, None);
            assert_eq!(e.status, CutoffEtaStatus::Behind);
        }
    }

    #[test]
    fn limit_passed_separates_an_expired_limit_from_a_too_close_projection() {
        let legs = [HALFWAY, FINISH_GATE];
        let expired = next_cutoff_eta(10000.0, 8000, Some(360.0), false, &legs);
        assert_eq!(expired.required_pace_s_per_km, None);
        assert!(expired.limit_passed);

        // 40 m out with time still on the clock: the required pace is None only
        // because the projection is meaningless — the limit has NOT passed.
        let close = eta(19960.0, Some(360.0), false, &legs);
        assert_eq!(close.required_pace_s_per_km, None);
        assert!(!close.limit_passed);
    }

    #[test]
    fn a_stale_fix_or_unknown_pace_still_reports_the_required_pace() {
        let legs = [HALFWAY, FINISH_GATE];
        let stale = eta(10000.0, Some(360.0), true, &legs);
        assert_eq!(stale.status, CutoffEtaStatus::Unknown);
        assert_eq!(stale.projected_arrival_elapsed_s, None);
        assert_eq!(stale.required_pace_s_per_km, Some(360.0));

        let no_pace = eta(10000.0, None, false, &legs);
        assert_eq!(no_pace.status, CutoffEtaStatus::Unknown);
        assert_eq!(no_pace.required_pace_s_per_km, Some(360.0));
    }

    #[test]
    fn an_absurd_pace_saturates_instead_of_panicking() {
        let legs = [HALFWAY, FINISH_GATE];
        let e = eta(10000.0, Some(1e12), false, &legs);
        assert_eq!(e.projected_arrival_elapsed_s, Some(u32::MAX));
        assert_eq!(e.margin_s, Some(i32::MIN));
        assert_eq!(e.status, CutoffEtaStatus::Behind);
    }
}
