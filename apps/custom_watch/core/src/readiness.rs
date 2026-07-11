//! Readiness-to-run score — training balance (form / TSB), last night's sleep,
//! and resting-HR drift vs a baseline folded into one 0..100 number.
//!
//! Deltas move around a neutral baseline of 75: positive contributors push it
//! up, negative ones drag it down, clamped to 0..100. Garmin Body Battery,
//! Whoop Recovery and Oura Readiness are the precedents.
//!
//! Parity port of web `training/readiness.ts` `computeReadiness` (twin of
//! `apps/mobile_android/lib/readiness.dart`) — keep the deltas, band
//! thresholds, dominant-advice pick, and test count in lockstep. The web
//! contributor `note` + `advice` are English display strings; here they are
//! carried as enum identifiers (the face localises them), never text.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// At most one contributor per signal: form, sleep, resting HR.
pub const MAX_CONTRIBUTORS: usize = 3;

/// Neutral starting point. A user with no inputs at all gets 75.
const BASELINE_SCORE: i32 = 75;

#[derive(Clone, Copy, Debug, Default)]
pub struct ReadinessInputs {
    /// Training Stress Balance (Form). Positive = fresh, negative = fatigued.
    /// `None` if unknown.
    pub tsb: Option<f64>,
    /// Hours of sleep last night. `None` if unknown.
    pub sleep_hours: Option<f64>,
    /// This morning's resting heart rate, bpm. `None` if unknown.
    pub resting_hr_bpm: Option<f64>,
    /// 30-day baseline resting heart rate, bpm. `None` if unknown.
    pub baseline_resting_hr_bpm: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ReadinessBand {
    Low,
    Moderate,
    High,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ContributorName {
    FormTsb,
    Sleep,
    RestingHr,
}

/// Machine-readable reason a contributor moved the score — the web `note`
/// string collapsed to an identifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ContributorNote {
    HeavyFatigue,
    Fatigued,
    SlightFatigue,
    FormNeutral,
    FreshRecovered,
    VeryFresh,
    OverTapered,
    VeryLittleSleep,
    ShortSleep,
    UnderTargetSleep,
    WellRested,
    ExtendedSleep,
    HrWellAboveBaseline,
    HrAboveBaseline,
    HrSlightlyElevated,
    HrAtBaseline,
    HrBelowBaseline,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ReadinessContribution {
    pub name: ContributorName,
    pub delta: i32,
    pub note: ContributorNote,
}

/// The band-driven tail appended to the dominant note — the web `tail` string.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AdviceTail {
    EasyOrRest,
    SteadyModerate,
    HarderEffort,
}

/// One-line guidance. With no signals it falls back to a band-aware line; with
/// signals it names the dominant contributor's note plus the band tail.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Advice {
    /// No signals at all. `encouraging` = high band (push the pace), else the
    /// connect-your-data nudge.
    NoSignals { encouraging: bool },
    Dominant {
        note: ContributorNote,
        tail: AdviceTail,
    },
}

pub struct Readiness {
    pub score: i32,
    pub band: ReadinessBand,
    pub advice: Advice,
    pub contributors: Vec<ReadinessContribution, MAX_CONTRIBUTORS>,
}

fn band_for(score: i32) -> ReadinessBand {
    if score >= 70 {
        ReadinessBand::High
    } else if score >= 40 {
        ReadinessBand::Moderate
    } else {
        ReadinessBand::Low
    }
}

fn score_tsb(tsb: Option<f64>) -> Option<ReadinessContribution> {
    let tsb = tsb?;
    let (delta, note) = if tsb < -20.0 {
        (-20, ContributorNote::HeavyFatigue)
    } else if tsb < -10.0 {
        (-12, ContributorNote::Fatigued)
    } else if tsb < -5.0 {
        (-6, ContributorNote::SlightFatigue)
    } else if tsb <= 5.0 {
        (0, ContributorNote::FormNeutral)
    } else if tsb <= 15.0 {
        (8, ContributorNote::FreshRecovered)
    } else if tsb <= 25.0 {
        (5, ContributorNote::VeryFresh)
    } else {
        (-3, ContributorNote::OverTapered)
    };
    Some(ReadinessContribution {
        name: ContributorName::FormTsb,
        delta,
        note,
    })
}

fn score_sleep(hours: Option<f64>) -> Option<ReadinessContribution> {
    let hours = hours?;
    let (delta, note) = if hours < 5.0 {
        (-25, ContributorNote::VeryLittleSleep)
    } else if hours < 6.5 {
        (-12, ContributorNote::ShortSleep)
    } else if hours < 7.5 {
        (-3, ContributorNote::UnderTargetSleep)
    } else if hours <= 9.0 {
        (5, ContributorNote::WellRested)
    } else {
        (0, ContributorNote::ExtendedSleep)
    };
    Some(ReadinessContribution {
        name: ContributorName::Sleep,
        delta,
        note,
    })
}

fn score_resting_hr(resting: Option<f64>, baseline: Option<f64>) -> Option<ReadinessContribution> {
    let diff = resting? - baseline?;
    let (delta, note) = if diff > 10.0 {
        (-18, ContributorNote::HrWellAboveBaseline)
    } else if diff > 5.0 {
        (-10, ContributorNote::HrAboveBaseline)
    } else if diff > 2.0 {
        (-4, ContributorNote::HrSlightlyElevated)
    } else if diff >= -2.0 {
        (0, ContributorNote::HrAtBaseline)
    } else {
        (3, ContributorNote::HrBelowBaseline)
    };
    Some(ReadinessContribution {
        name: ContributorName::RestingHr,
        delta,
        note,
    })
}

/// Pick the contributor that pushed the score the most in absolute terms; the
/// first-scanned wins a tie (matching web's stable descending sort + `[0]`).
fn dominant_advice(contributors: &[ReadinessContribution], band: ReadinessBand) -> Advice {
    let Some((first, rest)) = contributors.split_first() else {
        return Advice::NoSignals {
            encouraging: band == ReadinessBand::High,
        };
    };
    let mut dom = first;
    for c in rest {
        if c.delta.abs() > dom.delta.abs() {
            dom = c;
        }
    }
    let tail = match band {
        ReadinessBand::Low => AdviceTail::EasyOrRest,
        ReadinessBand::Moderate => AdviceTail::SteadyModerate,
        ReadinessBand::High => AdviceTail::HarderEffort,
    };
    Advice::Dominant {
        note: dom.note,
        tail,
    }
}

pub fn compute_readiness(inputs: &ReadinessInputs) -> Readiness {
    let mut contributors: Vec<ReadinessContribution, MAX_CONTRIBUTORS> = Vec::new();
    if let Some(c) = score_tsb(inputs.tsb) {
        let _ = contributors.push(c);
    }
    if let Some(c) = score_sleep(inputs.sleep_hours) {
        let _ = contributors.push(c);
    }
    if let Some(c) = score_resting_hr(inputs.resting_hr_bpm, inputs.baseline_resting_hr_bpm) {
        let _ = contributors.push(c);
    }

    let sum: i32 = contributors.iter().map(|c| c.delta).sum();
    let score = (BASELINE_SCORE + sum).clamp(0, 100);
    let band = band_for(score);
    let advice = dominant_advice(&contributors, band);
    Readiness {
        score,
        band,
        advice,
        contributors,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/readiness.test.ts` — same
    /// scenarios, same expected values, so the ports can't drift.
    #[test]
    fn neutral_inputs_baseline_high() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(0.0),
            ..Default::default()
        });
        assert_eq!(r.score, 75);
        assert_eq!(r.band, ReadinessBand::High);
        assert_eq!(r.contributors.len(), 1);
    }

    #[test]
    fn all_null_baseline_no_contributors() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: None,
            ..Default::default()
        });
        assert_eq!(r.score, 75);
        assert_eq!(r.contributors.len(), 0);
        // 75 is the high band, so the encouraging no-signal variant.
        assert_eq!(r.advice, Advice::NoSignals { encouraging: true });
    }

    #[test]
    fn heavy_fatigue_plus_bad_sleep_low() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(-25.0),
            sleep_hours: Some(4.0),
            ..Default::default()
        });
        // -20 (TSB) + -25 (sleep) = -45 -> 75 - 45 = 30 -> low.
        assert_eq!(r.score, 30);
        assert_eq!(r.band, ReadinessBand::Low);
        assert_eq!(
            r.advice,
            Advice::Dominant {
                note: ContributorNote::VeryLittleSleep,
                tail: AdviceTail::EasyOrRest,
            }
        );
    }

    #[test]
    fn fresh_plus_great_sleep_high() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(10.0),
            sleep_hours: Some(8.5),
            resting_hr_bpm: Some(55.0),
            baseline_resting_hr_bpm: Some(58.0),
        });
        // 75 + 8 (fresh) + 5 (great sleep) + 3 (HR below baseline) = 91.
        assert_eq!(r.score, 91);
        assert_eq!(r.band, ReadinessBand::High);
        assert_eq!(
            r.advice,
            Advice::Dominant {
                note: ContributorNote::FreshRecovered,
                tail: AdviceTail::HarderEffort,
            }
        );
    }

    #[test]
    fn clamps_to_0_100_on_extreme_inputs() {
        let low = compute_readiness(&ReadinessInputs {
            tsb: Some(-50.0),
            sleep_hours: Some(2.0),
            resting_hr_bpm: Some(100.0),
            baseline_resting_hr_bpm: Some(55.0),
        });
        assert_eq!(low.score, 12);
        assert_eq!(low.band, ReadinessBand::Low);

        let high = compute_readiness(&ReadinessInputs {
            tsb: Some(10.0),
            sleep_hours: Some(8.0),
            resting_hr_bpm: Some(50.0),
            baseline_resting_hr_bpm: Some(55.0),
        });
        assert!((75..=100).contains(&high.score));
    }

    #[test]
    fn over_tapered_small_negative_not_positive() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(30.0),
            ..Default::default()
        });
        assert_eq!(r.score, 75 - 3);
        let tsb = r
            .contributors
            .iter()
            .find(|c| c.name == ContributorName::FormTsb)
            .unwrap();
        assert_eq!(tsb.delta, -3);
        assert_eq!(tsb.note, ContributorNote::OverTapered);
    }

    #[test]
    fn resting_hr_well_above_baseline_strong_negative() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(0.0),
            resting_hr_bpm: Some(70.0),
            baseline_resting_hr_bpm: Some(58.0),
            ..Default::default()
        });
        // 12 above -> "well above baseline" band, -18.
        assert_eq!(r.score, 75 - 18);
        assert_eq!(r.band, ReadinessBand::Moderate);
        assert_eq!(
            r.advice,
            Advice::Dominant {
                note: ContributorNote::HrWellAboveBaseline,
                tail: AdviceTail::SteadyModerate,
            }
        );
    }

    #[test]
    fn dominant_input_drives_the_advice_line() {
        // Big sleep deficit dominates a mild TSB.
        let r = compute_readiness(&ReadinessInputs {
            tsb: Some(-3.0),
            sleep_hours: Some(4.0),
            ..Default::default()
        });
        // Sleep contributor (-25) beats the neutral TSB (0).
        match r.advice {
            Advice::Dominant { note, .. } => assert_eq!(note, ContributorNote::VeryLittleSleep),
            other => panic!("expected dominant advice, got {other:?}"),
        }
    }

    #[test]
    fn partial_inputs_only_sleep_present() {
        let r = compute_readiness(&ReadinessInputs {
            tsb: None,
            sleep_hours: Some(8.5),
            ..Default::default()
        });
        // Baseline 75 + sleep +5 = 80, high band.
        assert_eq!(r.score, 80);
        assert_eq!(r.band, ReadinessBand::High);
        assert_eq!(r.contributors.len(), 1);
    }

    #[test]
    fn band_thresholds_40_moderate_70_high() {
        // Neutral TSB -> 75 -> high band.
        assert_eq!(
            compute_readiness(&ReadinessInputs {
                tsb: Some(0.0),
                ..Default::default()
            })
            .band,
            ReadinessBand::High
        );
        // Slight fatigue -> 75-6=69 -> moderate.
        assert_eq!(
            compute_readiness(&ReadinessInputs {
                tsb: Some(-10.0),
                ..Default::default()
            })
            .band,
            ReadinessBand::Moderate
        );
        // Heavy fatigue -> 75-20=55 -> still moderate (>= 40).
        assert_eq!(
            compute_readiness(&ReadinessInputs {
                tsb: Some(-25.0),
                ..Default::default()
            })
            .band,
            ReadinessBand::Moderate
        );
        // Heavy fatigue + bad sleep -> 75-20-25=30 -> low.
        assert_eq!(
            compute_readiness(&ReadinessInputs {
                tsb: Some(-25.0),
                sleep_hours: Some(3.0),
                ..Default::default()
            })
            .band,
            ReadinessBand::Low
        );
    }

    #[test]
    fn deterministic_same_inputs_same_output() {
        let a = compute_readiness(&ReadinessInputs {
            tsb: Some(5.0),
            sleep_hours: Some(7.0),
            ..Default::default()
        });
        let b = compute_readiness(&ReadinessInputs {
            tsb: Some(5.0),
            sleep_hours: Some(7.0),
            ..Default::default()
        });
        assert_eq!(a.score, b.score);
        assert_eq!(a.band, b.band);
        assert_eq!(a.advice, b.advice);
    }
}
