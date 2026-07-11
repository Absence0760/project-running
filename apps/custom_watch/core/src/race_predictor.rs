//! Multi-distance race-time predictor — the whole standard race ladder
//! (5K / 10K / Half / Marathon) projected at once, each rung graded for
//! confidence independently, so a runner with a recent 10K sees a
//! high-confidence 10K and a clearly-flagged low-confidence marathon side by
//! side.
//!
//! Parity port of the web/Dart helper — keep the algorithm, constants, and
//! edge cases in lockstep with:
//! - `apps/web/src/lib/training/race_predictor.ts` (canonical `predictRaceLadder`),
//! - `apps/mobile_android/lib/race_predictor.dart` (Dart twin),
//! - the reused `riegelPredict` + `predictionConfidence` in
//!   `apps/web/src/lib/training/training.ts`.
//!
//! Two things make it richer than "best single run, one distance". First, a
//! recency-weighted anchor: every qualifying effort is Riegel-equivalenced to
//! a common reference distance, then the anchor is the recency-weighted best,
//! so a recent strong effort out-anchors a stale PR (exponential half-life
//! decay, [`ANCHOR_RECENCY_HALFLIFE_DAYS`]). Second, per-distance confidence:
//! each rung reuses [`prediction_confidence`] with the same thresholds the
//! single-distance panel uses.
//!
//! The final ladder always projects from the chosen anchor's ACTUAL distance
//! and time, so the predictions are honest Riegel equivalences, never weighted
//! fabrications. Pure logic, no peripherals, no allocator — like the rest of
//! `core`.

/// The standard race ladder we project, in metres: 5K / 10K / Half / Marathon.
/// Ordered shortest-to-longest so the ladder renders that way.
pub const RACE_LADDER_M: [f64; 4] = [5000.0, 10000.0, 21097.5, 42195.0];

/// Half-life (days) of the recency weight when picking the anchor. At 30 days
/// an effort counts half as much as a same-quality effort today; at 60 days a
/// quarter. Matches the ~30-day "recent" cliff in [`prediction_confidence`].
pub const ANCHOR_RECENCY_HALFLIFE_DAYS: f64 = 30.0;

/// Riegel's 1981 exponent: `t2 = t1 * (d2/d1)^1.06`. The call sites default to
/// this; [`riegel_predict`] takes it as a param so a caller can override.
const RIEGEL_EXPONENT: f64 = 1.06;

/// Beyond this Riegel extrapolation factor (target/known distance, or its
/// reciprocal) the prediction is little better than a guess — a marathon off a
/// 5K is ~8.4x. Caps confidence at [`PredictionConfidence::Low`].
const RIEGEL_FAR_FACTOR: f64 = 4.0;

/// Reference distance the anchor comparison is normalised to. 10K sits in the
/// middle of the ladder, minimising the average Riegel extrapolation across
/// the candidate pool. Only affects WHICH effort wins the anchor slot, never
/// the final per-rung predictions.
const ANCHOR_REFERENCE_M: f64 = 10000.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PredictionConfidence {
    High,
    Moderate,
    Low,
}

/// Machine-readable reason for the binding limit on a prediction's confidence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum PredictionReason {
    Similar,
    Extrapolated,
    Stale,
    Limited,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PredictionQuality {
    pub confidence: PredictionConfidence,
    pub reason: PredictionReason,
}

/// One past effort (or the current run, treated as a single effort).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Effort {
    pub distance_m: f64,
    pub duration_s: u32,
    /// Age of the effort in days at prediction time; may be negative (clock
    /// skew) or non-finite (filtered out).
    pub age_days: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LadderRung {
    pub distance_m: f64,
    /// Predicted finish time in seconds — kept as f64 for exactness, round at
    /// render.
    pub predicted_s: f64,
    pub pace_s_per_km: f64,
    pub quality: PredictionQuality,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RacePrediction {
    /// The anchor effort the whole ladder is projected from.
    pub anchor: Effort,
    /// Number of qualifying efforts that fed the anchor selection.
    pub qualifying_count: usize,
    /// One prediction per ladder rung, shortest-to-longest.
    pub rungs: [LadderRung; 4],
}

/// Predict a time at a different distance given a known result. Riegel 1981:
/// `t2 = t1 * (d2/d1)^exponent`. No guards — the caller filters the pool.
pub fn riegel_predict(
    known_distance_m: f64,
    known_time_s: f64,
    target_distance_m: f64,
    exponent: f64,
) -> f64 {
    known_time_s * libm::pow(target_distance_m / known_distance_m, exponent)
}

/// Recency weight for an effort `age_days` old: `0.5 ^ (age / halflife)`,
/// clamped so a future-dated effort (clock skew) can't exceed weight 1.
fn recency_weight(age_days: f64) -> f64 {
    libm::pow(0.5, age_days.max(0.0) / ANCHOR_RECENCY_HALFLIFE_DAYS)
}

/// Grade the data quality behind a Riegel race-time prediction. First match
/// wins — order matters. The three levers are how far we extrapolate from the
/// anchor (distance gap), how recent it is, and how many qualifying efforts
/// back it up.
pub fn prediction_confidence(
    known_distance_m: f64,
    target_distance_m: f64,
    days_since_best: i32,
    qualifying_run_count: usize,
) -> PredictionQuality {
    if known_distance_m <= 0.0 || target_distance_m <= 0.0 || qualifying_run_count == 0 {
        return PredictionQuality {
            confidence: PredictionConfidence::Low,
            reason: PredictionReason::Limited,
        };
    }

    let ratio = target_distance_m / known_distance_m;
    let factor = if ratio > 1.0 / ratio {
        ratio
    } else {
        1.0 / ratio
    };

    // Extrapolating far past the anchor dominates every other signal.
    if factor > RIEGEL_FAR_FACTOR {
        return PredictionQuality {
            confidence: PredictionConfidence::Low,
            reason: PredictionReason::Extrapolated,
        };
    }

    let close = factor <= 2.0;
    let recent = days_since_best <= 30;
    let well_sampled = qualifying_run_count >= 3;

    if close && recent && well_sampled {
        return PredictionQuality {
            confidence: PredictionConfidence::High,
            reason: PredictionReason::Similar,
        };
    }

    // One or more levers are soft. Report the binding constraint, distance
    // gap first (it hurts the prediction most).
    if !close {
        return PredictionQuality {
            confidence: PredictionConfidence::Moderate,
            reason: PredictionReason::Extrapolated,
        };
    }
    if !recent {
        // Older than two months is too stale to anchor at all, not just a
        // soft caveat.
        return if days_since_best > 60 {
            PredictionQuality {
                confidence: PredictionConfidence::Low,
                reason: PredictionReason::Stale,
            }
        } else {
            PredictionQuality {
                confidence: PredictionConfidence::Moderate,
                reason: PredictionReason::Stale,
            }
        };
    }
    // Close + recent but thinly sampled.
    PredictionQuality {
        confidence: PredictionConfidence::Moderate,
        reason: PredictionReason::Limited,
    }
}

/// Build the multi-distance race prediction from a pool of qualifying efforts.
///
/// Returns `None` when the pool is empty — the caller hides the surface rather
/// than showing a fabricated ladder (fail-closed, same as the single-distance
/// panel which shows nothing without a qualifying run).
///
/// Anchor selection: each effort is Riegel-equivalenced to
/// [`ANCHOR_REFERENCE_M`], giving a common-distance time; the effort whose
/// recency-weighted equivalent time is fastest wins (weighting divides the
/// equivalent time by the recency weight, so a stale effort's effective time
/// is inflated). Ties keep the first-scanned effort (strict `<`). The ladder
/// then projects from the chosen anchor's ACTUAL distance + time.
pub fn predict_race_ladder(efforts: &[Effort]) -> Option<RacePrediction> {
    let is_qualifying =
        |e: &Effort| e.distance_m > 0.0 && e.duration_s > 0 && e.age_days.is_finite();

    let count = efforts.iter().filter(|e| is_qualifying(e)).count();
    if count == 0 {
        return None;
    }

    let mut best: Option<Effort> = None;
    let mut best_effective = f64::INFINITY;
    for e in efforts.iter().filter(|e| is_qualifying(e)) {
        let equiv = riegel_predict(
            e.distance_m,
            e.duration_s as f64,
            ANCHOR_REFERENCE_M,
            RIEGEL_EXPONENT,
        );
        let w = recency_weight(e.age_days);
        // Guard a zero weight (an absurdly old effort) so it can't divide to
        // Infinity and then never lose to a finite candidate via the strict <.
        let effective = if w > 0.0 { equiv / w } else { f64::INFINITY };
        if effective < best_effective {
            best_effective = effective;
            best = Some(*e);
        }
    }

    // Every effort had weight 0 (all impossibly old) — fall back to the raw
    // fastest equivalent so we still anchor on something rather than null out.
    if best.is_none() {
        best_effective = f64::INFINITY;
        for e in efforts.iter().filter(|e| is_qualifying(e)) {
            let equiv = riegel_predict(
                e.distance_m,
                e.duration_s as f64,
                ANCHOR_REFERENCE_M,
                RIEGEL_EXPONENT,
            );
            if equiv < best_effective {
                best_effective = equiv;
                best = Some(*e);
            }
        }
    }

    let anchor = best.unwrap();
    let days_since_best = libm::round(anchor.age_days) as i32;

    let mut rungs = [LadderRung {
        distance_m: 0.0,
        predicted_s: 0.0,
        pace_s_per_km: 0.0,
        quality: PredictionQuality {
            confidence: PredictionConfidence::Low,
            reason: PredictionReason::Limited,
        },
    }; 4];
    for (rung, &distance_m) in rungs.iter_mut().zip(RACE_LADDER_M.iter()) {
        let predicted_s = riegel_predict(
            anchor.distance_m,
            anchor.duration_s as f64,
            distance_m,
            RIEGEL_EXPONENT,
        );
        *rung = LadderRung {
            distance_m,
            predicted_s,
            pace_s_per_km: predicted_s / (distance_m / 1000.0),
            quality: prediction_confidence(anchor.distance_m, distance_m, days_since_best, count),
        };
    }

    Some(RacePrediction {
        anchor,
        qualifying_count: count,
        rungs,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/race_predictor.test.ts` /
    /// `apps/mobile_android/test/race_predictor_test.dart` — same scenarios,
    /// same expected values, so the ports can't drift.
    fn effort(distance_m: f64, duration_s: u32, age_days: f64) -> Effort {
        Effort {
            distance_m,
            duration_s,
            age_days,
        }
    }

    #[test]
    fn empty_pool_is_none() {
        assert_eq!(predict_race_ladder(&[]), None);
    }

    #[test]
    fn filters_non_positive_and_non_finite() {
        let efforts = [
            effort(0.0, 1200, 1.0),
            effort(5000.0, 0, 1.0),
            effort(5000.0, 1200, f64::NAN),
        ];
        assert_eq!(predict_race_ladder(&efforts), None);
    }

    #[test]
    fn one_effort_gives_four_rungs() {
        let pred = predict_race_ladder(&[effort(5000.0, 1200, 3.0)]).unwrap();
        assert_eq!(pred.rungs.len(), 4);
        let ladder: [f64; 4] = core::array::from_fn(|i| pred.rungs[i].distance_m);
        assert_eq!(ladder, [5000.0, 10000.0, 21097.5, 42195.0]);
    }

    #[test]
    fn rungs_match_riegel() {
        let pred = predict_race_ladder(&[effort(5000.0, 1200, 0.0)]).unwrap();
        for rung in &pred.rungs {
            let expected = riegel_predict(5000.0, 1200.0, rung.distance_m, 1.06);
            assert!((rung.predicted_s - expected).abs() < 1e-6);
        }
    }

    #[test]
    fn pace_is_time_per_km() {
        let pred = predict_race_ladder(&[effort(10000.0, 2400, 1.0)]).unwrap();
        // The 10K rung of a 10K anchor: 2400 s / 10 km = 240 s/km.
        assert!((pred.rungs[1].pace_s_per_km - 240.0).abs() < 1e-6);
    }

    #[test]
    fn recent_out_anchors_faster_but_stale_pr() {
        // A faster but 60-day-old PR vs a slower fresh effort: the fresh one
        // wins because the weight inflates the stale effort's effective time.
        let pred = predict_race_ladder(&[effort(10000.0, 2400, 60.0), effort(10000.0, 2700, 0.0)])
            .unwrap();
        assert_eq!(pred.anchor.duration_s, 2700);
        assert_eq!(pred.anchor.age_days, 0.0);
    }

    #[test]
    fn recent_pr_wins_when_also_fastest() {
        let pred =
            predict_race_ladder(&[effort(10000.0, 3000, 1.0), effort(10000.0, 2400, 1.0)]).unwrap();
        assert_eq!(pred.anchor.duration_s, 2400);
    }

    #[test]
    fn qualifying_count_is_filtered_size() {
        let pred = predict_race_ladder(&[
            effort(5000.0, 1200, 1.0),
            effort(10000.0, 2700, 5.0),
            effort(0.0, 999, 1.0),
        ])
        .unwrap();
        assert_eq!(pred.qualifying_count, 2);
    }

    #[test]
    fn ten_k_anchor_grades_marathon_low() {
        let pred = predict_race_ladder(&[effort(10000.0, 2400, 1.0)]).unwrap();
        // Marathon (index 3) is >4x the 10K anchor: low.
        assert_eq!(pred.rungs[3].quality.confidence, PredictionConfidence::Low);
        // The 10K rung (index 1) itself is not low.
        assert_ne!(pred.rungs[1].quality.confidence, PredictionConfidence::Low);
    }

    #[test]
    fn stale_only_pool_still_predicts() {
        let pred = predict_race_ladder(&[effort(10000.0, 2700, 5000.0)]).unwrap();
        assert_eq!(pred.rungs.len(), 4);
        assert_eq!(
            pred.rungs[1].quality,
            PredictionQuality {
                confidence: PredictionConfidence::Low,
                reason: PredictionReason::Stale,
            }
        );
    }

    #[test]
    fn future_dated_effort_not_amplified() {
        let pred = predict_race_ladder(&[effort(5000.0, 1200, -3.0)]).unwrap();
        assert_eq!(pred.anchor.age_days, -3.0);
    }

    #[test]
    fn riegel_is_reference_equation() {
        let got = riegel_predict(5000.0, 1200.0, 10000.0, 1.06);
        let expected = 1200.0 * libm::pow(2.0, 1.06);
        assert!((got - expected).abs() < 1e-6);
    }

    #[test]
    fn prediction_confidence_bands() {
        // high / similar: close, recent, well-sampled.
        assert_eq!(
            prediction_confidence(10000.0, 10000.0, 5, 3),
            PredictionQuality {
                confidence: PredictionConfidence::High,
                reason: PredictionReason::Similar,
            }
        );
        // low / extrapolated: factor > 4 (marathon off a 5K).
        assert_eq!(
            prediction_confidence(5000.0, 42195.0, 5, 5),
            PredictionQuality {
                confidence: PredictionConfidence::Low,
                reason: PredictionReason::Extrapolated,
            }
        );
        // moderate / extrapolated: 2 < factor <= 4.
        assert_eq!(
            prediction_confidence(5000.0, 15000.0, 5, 5),
            PredictionQuality {
                confidence: PredictionConfidence::Moderate,
                reason: PredictionReason::Extrapolated,
            }
        );
        // low / stale: close but days > 60.
        assert_eq!(
            prediction_confidence(10000.0, 10000.0, 90, 5),
            PredictionQuality {
                confidence: PredictionConfidence::Low,
                reason: PredictionReason::Stale,
            }
        );
        // moderate / stale: close but 30 < days <= 60.
        assert_eq!(
            prediction_confidence(10000.0, 10000.0, 45, 5),
            PredictionQuality {
                confidence: PredictionConfidence::Moderate,
                reason: PredictionReason::Stale,
            }
        );
        // moderate / limited: close + recent but thinly sampled.
        assert_eq!(
            prediction_confidence(10000.0, 10000.0, 5, 2),
            PredictionQuality {
                confidence: PredictionConfidence::Moderate,
                reason: PredictionReason::Limited,
            }
        );
        // low / limited: no qualifying runs.
        assert_eq!(
            prediction_confidence(10000.0, 10000.0, 5, 0),
            PredictionQuality {
                confidence: PredictionConfidence::Low,
                reason: PredictionReason::Limited,
            }
        );
    }
}
