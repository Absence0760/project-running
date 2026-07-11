//! Checkpoint cutoff projection — the live-results companion to [`roadbook`].
//!
//! From a race-director's runner's actual aid-station crossings, project arrival
//! at every remaining checkpoint and grade each cutoff safe / tight / miss.
//! Where the roadbook projects a crew schedule from a goal time BEFORE the race,
//! this projects from the crossings logged DURING it. Both grade cutoffs on the
//! same scale, so the "tight" span and the verdict type are reused rather than
//! redefined: [`CUTOFF_TIGHT_S`] comes from `cutoff_eta` and [`CutoffStatus`]
//! from `roadbook`, one source of truth for "what counts as tight".
//!
//! The pace model is deliberately simple: average pace from the start to the
//! last checkpoint actually reached, extrapolated linearly to the remaining
//! distance. It does not grade-adjust the remaining legs.
//!
//! Parity port of web `runs/checkpoint_projection.ts` `projectRunner` (twin of
//! `apps/mobile_android/lib/checkpoint_projection.dart`) — keep the projection,
//! cutoff rules, edge cases, and test count in lockstep.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use core::cmp::Ordering;

use heapless::Vec;

use crate::cutoff_eta::CUTOFF_TIGHT_S;
use crate::roadbook::{CutoffStatus, MAX_ROADBOOK_LEGS};

/// One checkpoint along the course.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ProjectionCheckpoint<'a> {
    pub id: &'a str,
    /// Distance along the course from the start, metres.
    pub position_m: f64,
    /// Cutoff as elapsed seconds from the race start. `None` = no cutoff here.
    pub cutoff_elapsed_s: Option<f64>,
}

/// A runner's actual arrival at a checkpoint.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ProjectionCrossing<'a> {
    pub checkpoint_id: &'a str,
    /// Arrival (in_time) as elapsed seconds from the race start.
    pub elapsed_s: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RunnerStatus {
    Racing,
    Finished,
    Dnf,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CutoffVerdict {
    pub margin_s: f64,
    pub status: CutoffStatus,
}

/// One projected checkpoint row.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ProjectionLeg<'a> {
    pub checkpoint_id: &'a str,
    pub position_m: f64,
    pub reached: bool,
    /// Elapsed seconds at the actual crossing, when reached.
    pub actual_elapsed_s: Option<f64>,
    /// Linearly-projected elapsed seconds, when not yet reached + pace known.
    pub projected_elapsed_s: Option<f64>,
    pub cutoff_elapsed_s: Option<f64>,
    /// Cutoff grade against the actual (reached) or projected (future) arrival.
    pub cutoff: Option<CutoffVerdict>,
}

pub struct RunnerProjection<'a> {
    pub legs: Vec<ProjectionLeg<'a>, MAX_ROADBOOK_LEGS>,
    pub last_checkpoint_id: Option<&'a str>,
    pub last_elapsed_s: Option<f64>,
    /// Distance covered to the last reached checkpoint, metres.
    pub covered_m: f64,
    /// Average seconds per metre to the last reached checkpoint. `None` until 1+.
    pub pace_s_per_m: Option<f64>,
    pub status: RunnerStatus,
}

fn grade_cutoff(cutoff_s: f64, arrival_s: f64) -> CutoffVerdict {
    let margin_s = cutoff_s - arrival_s;
    let status = if margin_s < 0.0 {
        CutoffStatus::Miss
    } else if margin_s < CUTOFF_TIGHT_S as f64 {
        CutoffStatus::Tight
    } else {
        CutoffStatus::Safe
    };
    CutoffVerdict { margin_s, status }
}

/// Earliest crossing stamp for a checkpoint id, mirroring the web map that keeps
/// the smallest stamp when a checkpoint somehow has two.
fn earliest_crossing(crossings: &[ProjectionCrossing<'_>], id: &str) -> Option<f64> {
    let mut best: Option<f64> = None;
    for x in crossings {
        if x.checkpoint_id == id {
            match best {
                Some(b) if b <= x.elapsed_s => {}
                _ => best = Some(x.elapsed_s),
            }
        }
    }
    best
}

fn clamp_pos(p: f64) -> f64 {
    if p.is_finite() {
        p.max(0.0)
    } else {
        0.0
    }
}

#[derive(Clone, Copy)]
struct OrderedCp<'a> {
    id: &'a str,
    position_m: f64,
    cutoff_elapsed_s: Option<f64>,
}

/// Project a single runner from their crossings. `checkpoints` need not be
/// pre-sorted; a NaN/negative position is treated as 0.
pub fn project_runner<'a>(
    checkpoints: &[ProjectionCheckpoint<'a>],
    crossings: &[ProjectionCrossing<'_>],
) -> RunnerProjection<'a> {
    let mut ordered: Vec<OrderedCp<'a>, MAX_ROADBOOK_LEGS> = Vec::new();
    for c in checkpoints {
        let cp = OrderedCp {
            id: c.id,
            position_m: clamp_pos(c.position_m),
            cutoff_elapsed_s: c.cutoff_elapsed_s,
        };
        if ordered.push(cp).is_err() {
            break;
        }
    }
    ordered.sort_unstable_by(|a, b| {
        a.position_m
            .partial_cmp(&b.position_m)
            .unwrap_or(Ordering::Equal)
    });

    // Last reached checkpoint = the reached one with the greatest position.
    let mut last_checkpoint_id: Option<&'a str> = None;
    let mut last_elapsed_s: Option<f64> = None;
    let mut covered_m = 0.0_f64;
    for c in &ordered {
        let Some(e) = earliest_crossing(crossings, c.id) else {
            continue;
        };
        if last_elapsed_s.is_none() || c.position_m >= covered_m {
            last_checkpoint_id = Some(c.id);
            last_elapsed_s = Some(e);
            covered_m = c.position_m;
        }
    }

    let pace_s_per_m = match last_elapsed_s {
        Some(le) if covered_m > 0.0 => Some(le / covered_m),
        _ => None,
    };

    let mut blown_cutoff = false;
    let mut legs: Vec<ProjectionLeg<'a>, MAX_ROADBOOK_LEGS> = Vec::new();
    for c in &ordered {
        let actual = earliest_crossing(crossings, c.id);
        let reached = actual.is_some();
        let projected = match (reached, pace_s_per_m) {
            (false, Some(pace)) if c.position_m > covered_m => Some(pace * c.position_m),
            _ => None,
        };

        let mut cutoff = None;
        if let Some(cutoff_s) = c.cutoff_elapsed_s {
            let arrival = if reached { actual } else { projected };
            if let Some(a) = arrival {
                let v = grade_cutoff(cutoff_s, a);
                if reached && v.status == CutoffStatus::Miss {
                    blown_cutoff = true;
                }
                cutoff = Some(v);
            }
        }

        let _ = legs.push(ProjectionLeg {
            checkpoint_id: c.id,
            position_m: c.position_m,
            reached,
            actual_elapsed_s: if reached { actual } else { None },
            projected_elapsed_s: projected,
            cutoff_elapsed_s: c.cutoff_elapsed_s,
            cutoff,
        });
    }

    let reached_last = match (ordered.last(), last_checkpoint_id) {
        (Some(last), Some(id)) => last.id == id,
        _ => false,
    };
    let status = if blown_cutoff {
        RunnerStatus::Dnf
    } else if reached_last {
        RunnerStatus::Finished
    } else {
        RunnerStatus::Racing
    };

    RunnerProjection {
        legs,
        last_checkpoint_id,
        last_elapsed_s,
        covered_m,
        pace_s_per_m,
        status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/runs/checkpoint_projection.test.ts` — same
    /// scenarios, same expected values, so the ports can't drift.
    fn cps() -> [ProjectionCheckpoint<'static>; 3] {
        [
            ProjectionCheckpoint {
                id: "a",
                position_m: 10_000.0,
                cutoff_elapsed_s: None,
            },
            ProjectionCheckpoint {
                id: "b",
                position_m: 20_000.0,
                cutoff_elapsed_s: Some(7_200.0), // 2h cutoff at 20k
            },
            ProjectionCheckpoint {
                id: "c",
                position_m: 40_000.0,
                cutoff_elapsed_s: Some(18_000.0), // 5h cutoff at finish
            },
        ]
    }

    fn leg<'a, 'b>(p: &'b RunnerProjection<'a>, id: &str) -> &'b ProjectionLeg<'a> {
        p.legs.iter().find(|l| l.checkpoint_id == id).unwrap()
    }

    #[test]
    fn no_crossings_racing_no_pace_nothing_reached() {
        let cps = cps();
        let p = project_runner(&cps, &[]);
        assert_eq!(p.status, RunnerStatus::Racing);
        assert_eq!(p.pace_s_per_m, None);
        assert_eq!(p.last_checkpoint_id, None);
        assert!(p.covered_m.abs() < 1e-9);
        assert!(p.legs.iter().all(|l| !l.reached));
        assert!(p.legs.iter().all(|l| l.projected_elapsed_s.is_none()));
    }

    #[test]
    fn one_crossing_sets_pace_and_last_checkpoint() {
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 3_600.0,
        }];
        let p = project_runner(&cps(), &cr);
        assert_eq!(p.last_checkpoint_id, Some("a"));
        assert!((p.last_elapsed_s.unwrap() - 3_600.0).abs() < 1e-9);
        assert!((p.covered_m - 10_000.0).abs() < 1e-9);
        assert!((p.pace_s_per_m.unwrap() - 3_600.0 / 10_000.0).abs() < 1e-12); // 0.36 s/m == 6:00/km
        assert_eq!(p.status, RunnerStatus::Racing);
    }

    #[test]
    fn future_checkpoints_are_linearly_projected_from_pace() {
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 3_600.0,
        }];
        let p = project_runner(&cps(), &cr);
        let b = leg(&p, "b");
        let c = leg(&p, "c");
        assert!((b.projected_elapsed_s.unwrap() - 0.36 * 20_000.0).abs() < 1e-9); // 7200
        assert!((c.projected_elapsed_s.unwrap() - 0.36 * 40_000.0).abs() < 1e-9);
        // 14400
    }

    #[test]
    fn projected_arrival_exactly_on_the_cutoff_is_tight_not_miss() {
        // pace 0.36 → projected b = 7200 == cutoff 7200 → margin 0 → tight
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 3_600.0,
        }];
        let p = project_runner(&cps(), &cr);
        let cutoff = leg(&p, "b").cutoff.unwrap();
        assert!(cutoff.margin_s.abs() < 1e-9);
        assert_eq!(cutoff.status, CutoffStatus::Tight);
    }

    #[test]
    fn comfortable_projection_is_safe() {
        // faster: 30 min to 10k → 0.18 s/m → b projected 3600, margin 3600 > tight
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 1_800.0,
        }];
        let p = project_runner(&cps(), &cr);
        let cutoff = leg(&p, "b").cutoff.unwrap();
        assert_eq!(cutoff.status, CutoffStatus::Safe);
        assert!(cutoff.margin_s > CUTOFF_TIGHT_S as f64);
    }

    #[test]
    fn slow_projection_blows_a_future_cutoff_still_racing() {
        // 90 min to 10k → 0.54 s/m → b projected 10800 > 7200 cutoff → miss
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 5_400.0,
        }];
        let p = project_runner(&cps(), &cr);
        let cutoff = leg(&p, "b").cutoff.unwrap();
        assert_eq!(cutoff.status, CutoffStatus::Miss);
        assert!(cutoff.margin_s < 0.0);
        assert_eq!(p.status, RunnerStatus::Racing); // projected miss is a warning, not a DNF
    }

    #[test]
    fn a_reached_checkpoint_past_its_cutoff_is_a_dnf() {
        let cr = [
            ProjectionCrossing {
                checkpoint_id: "a",
                elapsed_s: 3_600.0,
            },
            ProjectionCrossing {
                checkpoint_id: "b",
                elapsed_s: 7_500.0, // arrived after the 7200 cutoff
            },
        ];
        let p = project_runner(&cps(), &cr);
        let b = leg(&p, "b");
        assert!(b.reached);
        assert_eq!(b.cutoff.unwrap().status, CutoffStatus::Miss);
        assert_eq!(p.status, RunnerStatus::Dnf);
    }

    #[test]
    fn reaching_the_last_checkpoint_within_cutoff_is_finished() {
        let cr = [
            ProjectionCrossing {
                checkpoint_id: "a",
                elapsed_s: 3_600.0,
            },
            ProjectionCrossing {
                checkpoint_id: "b",
                elapsed_s: 7_000.0,
            },
            ProjectionCrossing {
                checkpoint_id: "c",
                elapsed_s: 16_000.0,
            },
        ];
        let p = project_runner(&cps(), &cr);
        assert_eq!(p.status, RunnerStatus::Finished);
        assert_eq!(p.last_checkpoint_id, Some("c"));
    }

    #[test]
    fn checkpoints_are_sorted_by_position_before_projecting() {
        let base = cps();
        let unsorted = [base[2], base[0], base[1]];
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 3_600.0,
        }];
        let p = project_runner(&unsorted, &cr);
        assert_eq!(p.legs[0].checkpoint_id, "a");
        assert_eq!(p.legs[1].checkpoint_id, "b");
        assert_eq!(p.legs[2].checkpoint_id, "c");
    }

    #[test]
    fn a_reached_checkpoint_has_no_projection_only_an_actual() {
        let cr = [ProjectionCrossing {
            checkpoint_id: "a",
            elapsed_s: 3_600.0,
        }];
        let p = project_runner(&cps(), &cr);
        let a = leg(&p, "a");
        assert!(a.reached);
        assert!((a.actual_elapsed_s.unwrap() - 3_600.0).abs() < 1e-9);
        assert_eq!(a.projected_elapsed_s, None);
    }
}
