//! Guided runs — scripted coach-voice workouts as a fixed library of timed
//! cues, plus the pure tick dispatcher that fires each cue as the run's
//! elapsed time crosses its mark.
//!
//! A guided-run glance page picks a run from [`guided_run_library`] and, on
//! every recorder tick, asks [`cues_due`] which cues fall in the
//! `(prev, now]` elapsed window — the same shape as the [`crate::alerts`]
//! moving-time cadence, one cue fired exactly once as the second mark passes.
//!
//! Parity port of web `training/guided_runs.ts` (twin of
//! `apps/mobile_android/lib/guided_runs.dart`) — keep `cues_due`, the
//! validity rules, the library timing/ids, the edge cases, and the test count
//! in lockstep.
//!
//! What is deliberately NOT ported: the on-device TTS speaking, web's
//! `GuidedTranslate` function-injection, and the English cue/title *strings*.
//! Web resolves those from the message catalogue at render time; the watch
//! carries only the stable i18n key *identifiers* ([`GuidedCue::text_key`] and
//! the run's title/subtitle/description keys) so a presentation layer can
//! resolve the localized text later. The keys are identifiers, not the
//! lockstep, and hold no prose — the same convention as [`crate::route_markers`]
//! and [`crate::badges`].
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// A single tick can only ever surface as many cues as a run carries, and the
/// largest library run has 11. Cap the dispatch buffer comfortably above that
/// so a large elapsed jump (e.g. a resume after a long pause) still returns
/// every crossed cue.
pub const MAX_GUIDED_CUES: usize = 16;

/// A timed coach cue: when it fires and the i18n key of the line to speak/show.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GuidedCue<'a> {
    /// Seconds from the start of the run when the cue should fire.
    pub at_sec: f64,
    /// i18n key of the line the presentation layer speaks/shows (identifier,
    /// resolved by the caller — never English prose here).
    pub text_key: &'a str,
}

/// One scripted guided run: identity, timing, and its ordered cues.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GuidedRun<'a> {
    pub id: &'a str,
    /// i18n key of the run title.
    pub title_key: &'a str,
    /// i18n key of the short coach-voice subtitle.
    pub subtitle_key: &'a str,
    /// Target duration in seconds. Used for the library list + countdown.
    pub duration_sec: f64,
    /// i18n key of the one-paragraph detail blurb.
    pub description_key: &'a str,
    /// Ordered cues, ascending by `at_sec`.
    pub cues: &'a [GuidedCue<'a>],
}

/// Cues whose `at_sec` falls inside `(prev_elapsed_sec, now_elapsed_sec]`.
///
/// The recorder calls this on every tick with the previous and current elapsed
/// seconds; the dispatcher surfaces any cues that should fire between the two.
/// Idempotent w.r.t. duplicate ticks — the same range twice in a row returns
/// the cues once, then an empty buffer.
pub fn cues_due<'a>(
    guided: &GuidedRun<'a>,
    prev_elapsed_sec: f64,
    now_elapsed_sec: f64,
) -> Vec<GuidedCue<'a>, MAX_GUIDED_CUES> {
    let mut out = Vec::new();
    if now_elapsed_sec <= prev_elapsed_sec {
        return out;
    }
    for c in guided.cues {
        if c.at_sec > prev_elapsed_sec && c.at_sec <= now_elapsed_sec {
            let _ = out.push(*c);
        }
    }
    out
}

/// Validate that a guided run's cues are sorted and within duration.
pub fn is_guided_run_valid(g: &GuidedRun) -> bool {
    if g.duration_sec <= 0.0 {
        return false;
    }
    let mut prev: Option<f64> = None;
    for c in g.cues {
        if c.at_sec < 0.0 || c.at_sec > g.duration_sec {
            return false;
        }
        if let Some(p) = prev {
            if c.at_sec < p {
                return false;
            }
        }
        if c.text_key.trim().is_empty() {
            return false;
        }
        prev = Some(c.at_sec);
    }
    true
}

static EASY_30_CUES: [GuidedCue<'static>; 8] = [
    GuidedCue {
        at_sec: 0.0,
        text_key: "guidedRuns.easy30.cue0",
    },
    GuidedCue {
        at_sec: 300.0,
        text_key: "guidedRuns.easy30.cue1",
    },
    GuidedCue {
        at_sec: 600.0,
        text_key: "guidedRuns.easy30.cue2",
    },
    GuidedCue {
        at_sec: 900.0,
        text_key: "guidedRuns.easy30.cue3",
    },
    GuidedCue {
        at_sec: 1200.0,
        text_key: "guidedRuns.easy30.cue4",
    },
    GuidedCue {
        at_sec: 1500.0,
        text_key: "guidedRuns.easy30.cue5",
    },
    GuidedCue {
        at_sec: 1740.0,
        text_key: "guidedRuns.easy30.cue6",
    },
    GuidedCue {
        at_sec: 1800.0,
        text_key: "guidedRuns.easy30.cue7",
    },
];

static TEMPO_25_CUES: [GuidedCue<'static>; 9] = [
    GuidedCue {
        at_sec: 0.0,
        text_key: "guidedRuns.tempo25.cue0",
    },
    GuidedCue {
        at_sec: 240.0,
        text_key: "guidedRuns.tempo25.cue1",
    },
    GuidedCue {
        at_sec: 300.0,
        text_key: "guidedRuns.tempo25.cue2",
    },
    GuidedCue {
        at_sec: 600.0,
        text_key: "guidedRuns.tempo25.cue3",
    },
    GuidedCue {
        at_sec: 900.0,
        text_key: "guidedRuns.tempo25.cue4",
    },
    GuidedCue {
        at_sec: 1080.0,
        text_key: "guidedRuns.tempo25.cue5",
    },
    GuidedCue {
        at_sec: 1200.0,
        text_key: "guidedRuns.tempo25.cue6",
    },
    GuidedCue {
        at_sec: 1380.0,
        text_key: "guidedRuns.tempo25.cue7",
    },
    GuidedCue {
        at_sec: 1500.0,
        text_key: "guidedRuns.tempo25.cue8",
    },
];

static FIRST_15_CUES: [GuidedCue<'static>; 11] = [
    GuidedCue {
        at_sec: 0.0,
        text_key: "guidedRuns.first15.cue0",
    },
    GuidedCue {
        at_sec: 180.0,
        text_key: "guidedRuns.first15.cue1",
    },
    GuidedCue {
        at_sec: 240.0,
        text_key: "guidedRuns.first15.cue2",
    },
    GuidedCue {
        at_sec: 300.0,
        text_key: "guidedRuns.first15.cue3",
    },
    GuidedCue {
        at_sec: 360.0,
        text_key: "guidedRuns.first15.cue4",
    },
    GuidedCue {
        at_sec: 420.0,
        text_key: "guidedRuns.first15.cue5",
    },
    GuidedCue {
        at_sec: 480.0,
        text_key: "guidedRuns.first15.cue6",
    },
    GuidedCue {
        at_sec: 540.0,
        text_key: "guidedRuns.first15.cue7",
    },
    GuidedCue {
        at_sec: 600.0,
        text_key: "guidedRuns.first15.cue8",
    },
    GuidedCue {
        at_sec: 840.0,
        text_key: "guidedRuns.first15.cue9",
    },
    GuidedCue {
        at_sec: 900.0,
        text_key: "guidedRuns.first15.cue10",
    },
];

static LIBRARY: [GuidedRun<'static>; 3] = [
    GuidedRun {
        id: "easy-30",
        title_key: "guidedRuns.easy30.title",
        subtitle_key: "guidedRuns.easy30.subtitle",
        duration_sec: 1800.0,
        description_key: "guidedRuns.easy30.description",
        cues: &EASY_30_CUES,
    },
    GuidedRun {
        id: "tempo-builder-25",
        title_key: "guidedRuns.tempo25.title",
        subtitle_key: "guidedRuns.tempo25.subtitle",
        duration_sec: 1500.0,
        description_key: "guidedRuns.tempo25.description",
        cues: &TEMPO_25_CUES,
    },
    GuidedRun {
        id: "first-timer-15",
        title_key: "guidedRuns.first15.title",
        subtitle_key: "guidedRuns.first15.subtitle",
        duration_sec: 900.0,
        description_key: "guidedRuns.first15.description",
        cues: &FIRST_15_CUES,
    },
];

/// The fixed library of MVP guided runs. Locale-independent: identity + timing
/// only; the title/subtitle/description/cue keys are resolved by the caller.
pub fn guided_run_library() -> &'static [GuidedRun<'static>] {
    &LIBRARY
}

/// Look up a guided run by id. `None` if not in the library.
pub fn find_guided_run(id: &str) -> Option<&'static GuidedRun<'static>> {
    guided_run_library().iter().find(|g| g.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mirror of `apps/web/src/lib/training/guided_runs.test.ts` — same
    /// scenarios, same expected values, so the ports can't drift. The two
    /// web-only "localization" cases (raw-key leak check + de-catalogue
    /// re-localize) are dropped: they exercise the `GuidedTranslate`
    /// function-injection and locale catalogues, which the watch does not
    /// carry — keys here are identifiers, not resolved prose.
    fn mk_run<'a>(cues: &'a [GuidedCue<'a>]) -> GuidedRun<'a> {
        let max = cues.iter().map(|c| c.at_sec).fold(0.0_f64, f64::max);
        GuidedRun {
            id: "test",
            title_key: "t",
            subtitle_key: "s",
            duration_sec: max + 10.0,
            description_key: "d",
            cues,
        }
    }

    // ─────────── cues_due ───────────

    #[test]
    fn no_cues_in_range_is_empty() {
        let cues = [
            GuidedCue {
                at_sec: 10.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 60.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 120.0,
                text_key: "c",
            },
        ];
        let g = mk_run(&cues);
        assert!(cues_due(&g, 30.0, 50.0).is_empty());
    }

    #[test]
    fn cue_at_boundary_fires_on_the_tick_it_crosses() {
        let cues = [GuidedCue {
            at_sec: 60.0,
            text_key: "c",
        }];
        let g = mk_run(&cues);
        assert_eq!(cues_due(&g, 59.0, 60.0).len(), 1);
        assert_eq!(cues_due(&g, 60.0, 61.0).len(), 0);
    }

    #[test]
    fn multiple_cues_in_the_same_window_all_fire() {
        let cues = [
            GuidedCue {
                at_sec: 10.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 11.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 12.0,
                text_key: "c",
            },
        ];
        let g = mk_run(&cues);
        let out = cues_due(&g, 9.0, 12.0);
        assert_eq!(out.len(), 3);
        let at: [f64; 3] = core::array::from_fn(|i| out[i].at_sec);
        assert_eq!(at, [10.0, 11.0, 12.0]);
    }

    #[test]
    fn prev_equals_now_is_empty() {
        let cues = [GuidedCue {
            at_sec: 60.0,
            text_key: "c",
        }];
        let g = mk_run(&cues);
        assert!(cues_due(&g, 60.0, 60.0).is_empty());
    }

    #[test]
    fn now_before_prev_is_empty() {
        let cues = [GuidedCue {
            at_sec: 60.0,
            text_key: "c",
        }];
        let g = mk_run(&cues);
        assert!(cues_due(&g, 120.0, 60.0).is_empty());
    }

    #[test]
    fn cue_at_zero_fires_when_prev_is_minus_one() {
        let cues = [GuidedCue {
            at_sec: 0.0,
            text_key: "c",
        }];
        let g = mk_run(&cues);
        assert_eq!(cues_due(&g, -1.0, 0.0).len(), 1);
    }

    // ─────────── is_guided_run_valid ───────────

    #[test]
    fn well_formed_run_passes() {
        let cues = [
            GuidedCue {
                at_sec: 0.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 60.0,
                text_key: "c",
            },
            GuidedCue {
                at_sec: 300.0,
                text_key: "c",
            },
        ];
        let g = mk_run(&cues);
        assert!(is_guided_run_valid(&g));
    }

    #[test]
    fn out_of_order_cues_fail() {
        let cues = [
            GuidedCue {
                at_sec: 60.0,
                text_key: "a",
            },
            GuidedCue {
                at_sec: 30.0,
                text_key: "b",
            },
        ];
        let g = GuidedRun {
            id: "x",
            title_key: "x",
            subtitle_key: "x",
            duration_sec: 600.0,
            description_key: "x",
            cues: &cues,
        };
        assert!(!is_guided_run_valid(&g));
    }

    #[test]
    fn cue_beyond_duration_fails() {
        let cues = [GuidedCue {
            at_sec: 120.0,
            text_key: "late",
        }];
        let g = GuidedRun {
            id: "x",
            title_key: "x",
            subtitle_key: "x",
            duration_sec: 60.0,
            description_key: "x",
            cues: &cues,
        };
        assert!(!is_guided_run_valid(&g));
    }

    #[test]
    fn blank_cue_text_fails() {
        let cues = [GuidedCue {
            at_sec: 30.0,
            text_key: "   ",
        }];
        let g = GuidedRun {
            id: "x",
            title_key: "x",
            subtitle_key: "x",
            duration_sec: 60.0,
            description_key: "x",
            cues: &cues,
        };
        assert!(!is_guided_run_valid(&g));
    }

    // ─────────── library ───────────

    #[test]
    fn every_library_entry_is_valid() {
        let lib = guided_run_library();
        assert!(lib.len() >= 3);
        for g in lib {
            assert!(is_guided_run_valid(g), "{} is malformed", g.id);
        }
    }

    #[test]
    fn library_ids_are_unique() {
        let lib = guided_run_library();
        for (i, a) in lib.iter().enumerate() {
            for b in &lib[i + 1..] {
                assert_ne!(a.id, b.id);
            }
        }
    }

    #[test]
    fn find_guided_run_is_none_for_unknown_id() {
        assert!(find_guided_run("nope").is_none());
    }

    #[test]
    fn find_guided_run_returns_the_run_for_a_known_id() {
        let id = guided_run_library()[0].id;
        let found = find_guided_run(id);
        assert!(found.is_some());
        assert_eq!(found.unwrap().id, id);
    }

    #[test]
    fn library_durations_are_sensible() {
        for g in guided_run_library() {
            assert!(g.duration_sec >= 5.0 * 60.0, "{} too short", g.id);
            assert!(g.duration_sec <= 90.0 * 60.0, "{} too long", g.id);
        }
    }

    #[test]
    fn every_run_has_a_kickoff_cue_near_zero() {
        for g in guided_run_library() {
            assert!(
                !g.cues.is_empty() && g.cues[0].at_sec <= 5.0,
                "{} missing a kickoff cue in the first 5s",
                g.id
            );
        }
    }

    #[test]
    fn every_run_has_a_finish_cue_at_exactly_duration() {
        for g in guided_run_library() {
            let last = g.cues[g.cues.len() - 1];
            assert!(
                (last.at_sec - g.duration_sec).abs() < 1e-9,
                "{} missing a finish cue at duration",
                g.id
            );
        }
    }
}
