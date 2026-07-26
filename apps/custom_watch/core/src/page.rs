//! Which data screen the run view shows, and the order the page button walks.
//!
//! Pure + host-tested like the rest of `core`: this decides the cycle order,
//! the app's `button` task owns only the debounce that advances it, and
//! [`crate::face::page_rows`] renders whichever page is current. Pages apply to
//! an in-progress run only — the idle status face ignores the page entirely.
//!
//! **Cycle order minimises presses for what a runner actually glances at
//! mid-run** (2026-07-21, issue #596 follow-up): the cycle is bidirectional
//! (short press = next, long press = previous), so a page's cost is its
//! distance from the Dashboard in EITHER direction. Pages are clustered by
//! theme and the clusters ordered by mid-run glance frequency — live run
//! metrics first, then course / race operations, then effort analysis, then
//! the synced training pages, with the rarely-mid-run summary pages in the
//! back half where the long-press walk covers them — and [`Page::BackToStart`]
//! sits LAST so the safety page is exactly one long-press from home. The
//! declaration order IS the cycle order (and therefore the [`Page::bit`]
//! order in the settings pages bitmask — renumbered with this reorder while
//! the deployed fleet is zero watches); `statusbar::page_indicator`'s rank
//! math relies on that equivalence and a test pins it.

/// The run-view pages, in button-cycle order (see the module doc for the
/// ordering policy). [`Page::Dashboard`] is the full multi-metric view; the
/// others are single-metric "glance" screens that put one number up large.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum Page {
    /// The detailed dashboard: elapsed-time hero + every metric row.
    #[default]
    Dashboard,
    /// Distance up large, with pace / time / HR as context.
    Distance,
    /// Average pace up large, with distance / time / HR / live
    /// grade-adjusted pace as context.
    Pace,
    /// Current lap time up large, with lap number / last-lap split / lap
    /// distance / HR as context.
    Lap,
    /// Current HR up large, with the live zone and the per-zone moving-time
    /// breakdown as context.
    Zones,
    /// Distance banked in each pace bucket for the run so far — the pace
    /// analogue of the zones page (buckets from [`crate::pace_segments`]).
    Splits,
    /// Virtual-partner ahead/behind time up large, with the goal, projected
    /// finish, and distance delta as context; an honest inactive state while
    /// no goal is configured.
    Pacer,
    /// The armed scripted coach run ([`crate::guided_runs`]): how much of the
    /// run is left, which cue the elapsed time has reached, and how long until
    /// the next one; an honest inactive state until a guided run is armed.
    GuidedRun,
    /// Breadcrumb course view: the loaded course polyline with the current
    /// position marked, distance-along-course, and the off-course alert.
    Nav,
    /// The next turn on the loaded course ([`crate::turn_cues`]); empty until
    /// synced.
    TurnCue,
    /// The next cut-off ETA up large (on / tight / behind vs the cutoff limit),
    /// with the distance to it and the projected arrival; an honest inactive
    /// state when no course cutoffs are loaded.
    CutoffEta,
    /// The race roadbook: the upcoming checkpoints from the current position,
    /// each with its projected arrival + safe/tight/miss cutoff verdict; an
    /// honest inactive state when no roadbook is loaded
    /// ([`crate::roadbook`]).
    Roadbook,
    /// The race fuelling plan: what to carry to the next aid + the run totals,
    /// scaled onto the roadbook timeline ([`crate::fuel_plan`]); inactive
    /// without a roadbook.
    Fuel,
    /// The run's elevation profile as a mini-profile sparkline over the whole
    /// run ([`crate::record::ElevProfileView`]), with total ascent / descent as
    /// context; an honest "NO ELEVATION" until the first altitude sample lands.
    ElevationProfile,
    /// The 5K/10K/Half/Marathon race-time ladder projected from the current
    /// run, with a per-rung confidence flag; blank until the run is long
    /// enough to project honestly.
    RacePredictor,
    /// This run's training-load stress contribution so far — the single-run
    /// distance/TRIMP model from [`crate::training_load`].
    TrainingLoad,
    /// The race-distance band the run's distance falls in
    /// ([`crate::distance_bands`]); an honest "no band" between windows.
    DistanceBand,
    /// Gear wear: the active shoe's accumulated distance vs its replacement
    /// target ([`crate::gear_wear`]); an honest inactive state when no gear is
    /// synced.
    GearWear,
    /// The five Daniels intensity-zone training paces (easy / marathon / tempo /
    /// interval / repetition) derived from a synced goal-race pace
    /// ([`crate::training_paces`]); an honest "NO GOAL SET" until one is synced.
    TrainingPaces,
    /// The synced fitness snapshot — VO2 max / VDOT + the recovery-advice verdict
    /// pushed from the phone ([`crate::fitness`]); an honest `--` until synced.
    /// Only what a single synced snapshot can present: the rolling CTL/ATL/TSB
    /// needs multi-day history the watch doesn't hold.
    Fitness,
    /// The training-readiness score + band ([`crate::readiness`]); empty until
    /// synced.
    Readiness,
    /// The primary goal's ring progress ([`crate::goals`]); empty until synced.
    Goals,
    /// The race-day countdown + goal-feasibility verdict ([`crate::race_day`]);
    /// empty until synced.
    RaceDay,
    /// The re-plan proposal counts around missed sessions ([`crate::plan_replan`]);
    /// empty until synced.
    PlanReplan,
    /// The multi-week adherence trend behind the adaptive re-plan
    /// ([`crate::plan_adaptive_replan`]); empty until synced.
    PlanAdaptive,
    /// Year/Month-in-Running totals pushed from the phone ([`crate::recap`]); an
    /// honest empty state until synced.
    Recap,
    /// Current + best run-streak day counts ([`crate::streaks`]); empty until
    /// synced.
    Streaks,
    /// A synced run-stats summary — moving time / gain / split count
    /// ([`crate::run_stats`]); empty until synced.
    RunStats,
    /// How long ago the current PR was set, bucketed ([`crate::pr_recency`]);
    /// empty until synced.
    PrRecency,
    /// A simplified-course point/length summary ([`crate::route_simplify`]);
    /// empty until synced.
    RouteSimplify,
    /// The loaded course's elevation gain/loss summary ([`crate::route_elevation`]);
    /// empty until synced.
    RouteElev,
    /// Auto-segment-effort match counts ([`crate::auto_segment_effort`]); empty
    /// until synced.
    AutoEffort,
    /// Distance back to the run's start up large, with a relative direction
    /// arrow, heading/bearing rows, and the TrackBack breadcrumb map.
    BackToStart,
}

impl Page {
    /// This page's bit in a pages bitmask (`1 << discriminant`). The mask is a
    /// `u64` — the 33rd page ([`Page::GuidedRun`]) overflowed the `u32` the mask
    /// used to be, which in release builds would have wrapped `1 << 32` back
    /// onto the Dashboard's bit rather than failing; a 65th page needs a wider
    /// mask again, and the `all_pages_fit_in_the_mask` test pins the headroom.
    pub fn bit(self) -> u64 {
        1 << self as u8
    }

    /// The page's short code for the [`crate::page_grid`] overview — at most
    /// four glyphs so four columns of codes fit the 21-cell text grid, unique
    /// so no two cells read the same (both test-pinned).
    pub fn code(self) -> &'static str {
        match self {
            Page::Dashboard => "DASH",
            Page::Distance => "DIST",
            Page::Pace => "PACE",
            Page::Lap => "LAP",
            Page::Zones => "ZONE",
            Page::Splits => "SPLT",
            Page::Pacer => "PACR",
            Page::GuidedRun => "GUID",
            Page::Nav => "NAV",
            Page::TurnCue => "TURN",
            Page::CutoffEta => "CUT",
            Page::Roadbook => "ROAD",
            Page::Fuel => "FUEL",
            Page::ElevationProfile => "ELEV",
            Page::RacePredictor => "PRED",
            Page::TrainingLoad => "LOAD",
            Page::DistanceBand => "BAND",
            Page::GearWear => "GEAR",
            Page::TrainingPaces => "TPCE",
            Page::Fitness => "FITN",
            Page::Readiness => "REDY",
            Page::Goals => "GOAL",
            Page::RaceDay => "RDAY",
            Page::PlanReplan => "PLAN",
            Page::PlanAdaptive => "ADPT",
            Page::Recap => "RCAP",
            Page::Streaks => "STRK",
            Page::RunStats => "STAT",
            Page::PrRecency => "PR",
            Page::RouteSimplify => "SMPL",
            Page::RouteElev => "RELV",
            Page::AutoEffort => "AEFF",
            Page::BackToStart => "BACK",
        }
    }

    /// The next page whose bit is set in `mask`, walking the cycle order —
    /// the filtered BTN3 press. [`Page::Dashboard`] is always treated as
    /// enabled (a mask can never empty the cycle), and a page the runner is
    /// parked on stays reachable as the walk's origin even when its own bit
    /// has since cleared (its data vanished mid-run) — the press moves off it
    /// and the cycle simply no longer returns.
    pub fn next_in(self, mask: u64) -> Self {
        let mask = mask | Page::Dashboard.bit();
        let mut p = self.next();
        while p != self && p.bit() & mask == 0 {
            p = p.next();
        }
        if p.bit() & mask == 0 {
            Page::Dashboard
        } else {
            p
        }
    }

    /// The previous enabled page — [`Page::next_in`]'s exact inverse over the
    /// same mask (the BTN3 long-press).
    pub fn prev_in(self, mask: u64) -> Self {
        let mask = mask | Page::Dashboard.bit();
        let mut p = self.prev();
        while p != self && p.bit() & mask == 0 {
            p = p.prev();
        }
        if p.bit() & mask == 0 {
            Page::Dashboard
        } else {
            p
        }
    }

    /// The next page in the button's cycle order, wrapping back to the start.
    pub fn next(self) -> Self {
        match self {
            Page::Dashboard => Page::Distance,
            Page::Distance => Page::Pace,
            Page::Pace => Page::Lap,
            Page::Lap => Page::Zones,
            Page::Zones => Page::Splits,
            Page::Splits => Page::Pacer,
            Page::Pacer => Page::GuidedRun,
            Page::GuidedRun => Page::Nav,
            Page::Nav => Page::TurnCue,
            Page::TurnCue => Page::CutoffEta,
            Page::CutoffEta => Page::Roadbook,
            Page::Roadbook => Page::Fuel,
            Page::Fuel => Page::ElevationProfile,
            Page::ElevationProfile => Page::RacePredictor,
            Page::RacePredictor => Page::TrainingLoad,
            Page::TrainingLoad => Page::DistanceBand,
            Page::DistanceBand => Page::GearWear,
            Page::GearWear => Page::TrainingPaces,
            Page::TrainingPaces => Page::Fitness,
            Page::Fitness => Page::Readiness,
            Page::Readiness => Page::Goals,
            Page::Goals => Page::RaceDay,
            Page::RaceDay => Page::PlanReplan,
            Page::PlanReplan => Page::PlanAdaptive,
            Page::PlanAdaptive => Page::Recap,
            Page::Recap => Page::Streaks,
            Page::Streaks => Page::RunStats,
            Page::RunStats => Page::PrRecency,
            Page::PrRecency => Page::RouteSimplify,
            Page::RouteSimplify => Page::RouteElev,
            Page::RouteElev => Page::AutoEffort,
            Page::AutoEffort => Page::BackToStart,
            Page::BackToStart => Page::Dashboard,
        }
    }

    /// The previous page in the cycle — the exact inverse of [`Page::next`],
    /// wrapping from the first page back to the last. With 33 pages a forward-
    /// only walk needs up to ~32 presses to reach a late page; a reverse
    /// traversal (the app maps it to a BTN3 long-press) puts the last pages one
    /// press away. Defined as the inverse of `next` rather than a second hand-
    /// written chain so the two can't drift.
    pub fn prev(self) -> Self {
        let mut p = self;
        // At most ALL-1 forward steps land on the page whose `next` is `self`.
        while p.next() != self {
            p = p.next();
        }
        p
    }
}

/// How many pages the `SET1` settings frame's 32-bit curated-page mask can
/// address ([`crate::settings::WatchSettings::pages`]).
pub const WIRE_MASK_BITS: u8 = 32;

/// Widen a phone-pushed curated-page mask to the watch's internal `u64`.
///
/// The wire field is 32 bits wide, so a phone cannot express a page past
/// discriminant 31. Those pages are left **enabled** rather than curated out: a
/// zero-extension would hide a page the phone never meant to touch — and
/// silently, since a curation push looks identical either way. Data presence
/// still gates them, so nothing empty appears in the cycle. Widening the wire
/// (a version bump plus the Dart encoder) retires this.
pub fn mask_from_wire(wire: u32) -> u64 {
    u64::from(wire) | !((1u64 << WIRE_MASK_BITS) - 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_the_dashboard() {
        assert_eq!(Page::default(), Page::Dashboard);
    }

    /// Every page, in declaration (`as u8`) order.
    const ALL: [Page; 33] = [
        Page::Dashboard,
        Page::Distance,
        Page::Pace,
        Page::Lap,
        Page::Zones,
        Page::Splits,
        Page::Pacer,
        Page::GuidedRun,
        Page::Nav,
        Page::TurnCue,
        Page::CutoffEta,
        Page::Roadbook,
        Page::Fuel,
        Page::ElevationProfile,
        Page::RacePredictor,
        Page::TrainingLoad,
        Page::DistanceBand,
        Page::GearWear,
        Page::TrainingPaces,
        Page::Fitness,
        Page::Readiness,
        Page::Goals,
        Page::RaceDay,
        Page::PlanReplan,
        Page::PlanAdaptive,
        Page::Recap,
        Page::Streaks,
        Page::RunStats,
        Page::PrRecency,
        Page::RouteSimplify,
        Page::RouteElev,
        Page::AutoEffort,
        Page::BackToStart,
    ];

    #[test]
    fn next_cycles_every_page_and_wraps() {
        assert_eq!(Page::Dashboard.next(), Page::Distance);
        assert_eq!(Page::Pace.next(), Page::Lap);
        assert_eq!(Page::Lap.next(), Page::Zones);
        assert_eq!(Page::Splits.next(), Page::Pacer);
        assert_eq!(
            Page::Pacer.next(),
            Page::GuidedRun,
            "guidance pages close the live cluster"
        );
        assert_eq!(
            Page::GuidedRun.next(),
            Page::Nav,
            "course ops follow the live cluster"
        );
        assert_eq!(Page::Nav.next(), Page::TurnCue);
        assert_eq!(Page::CutoffEta.next(), Page::Roadbook);
        assert_eq!(Page::Roadbook.next(), Page::Fuel);
        assert_eq!(Page::Fuel.next(), Page::ElevationProfile);
        assert_eq!(Page::RacePredictor.next(), Page::TrainingLoad);
        assert_eq!(Page::DistanceBand.next(), Page::GearWear);
        assert_eq!(Page::RaceDay.next(), Page::PlanReplan);
        assert_eq!(Page::PlanReplan.next(), Page::PlanAdaptive);
        assert_eq!(Page::PrRecency.next(), Page::RouteSimplify);
        assert_eq!(Page::AutoEffort.next(), Page::BackToStart);
        assert_eq!(
            Page::BackToStart.next(),
            Page::Dashboard,
            "safety page wraps home"
        );
        // Walking `next` from the default visits every page exactly once and
        // returns home.
        let mut p = Page::default();
        let mut seen = [p; ALL.len()];
        for slot in seen.iter_mut().skip(1) {
            p = p.next();
            *slot = p;
        }
        seen.sort_by_key(|q| *q as u8);
        assert_eq!(seen, ALL);
        let mut p = Page::default();
        for _ in 0..ALL.len() {
            p = p.next();
        }
        assert_eq!(p, Page::default());
    }

    #[test]
    fn prev_is_the_exact_inverse_of_next() {
        for &p in ALL.iter() {
            assert_eq!(p.next().prev(), p, "next then prev should return to {p:?}");
            assert_eq!(p.prev().next(), p, "prev then next should return to {p:?}");
        }
    }

    #[test]
    fn codes_are_short_and_unique() {
        for &p in ALL.iter() {
            assert!(
                p.code().len() <= 4,
                "{p:?} code {:?} exceeds the four-glyph grid cell",
                p.code()
            );
            assert!(!p.code().is_empty());
        }
        for (i, &a) in ALL.iter().enumerate() {
            for &b in ALL.iter().skip(i + 1) {
                assert_ne!(a.code(), b.code(), "{a:?} and {b:?} share a code");
            }
        }
    }

    #[test]
    fn all_pages_fit_in_the_mask() {
        // One u64 bit each, collision-free and inside the mask: the 33rd page
        // is exactly what overflowed the u32 this mask used to be, and in a
        // release build `1 << 32` would have wrapped onto the Dashboard's bit
        // instead of panicking.
        let mut seen = 0u64;
        for &p in ALL.iter() {
            assert!(
                (p as u8) < u64::BITS as u8,
                "{p:?} sits past the mask's width"
            );
            assert_eq!(seen & p.bit(), 0, "duplicate bit for {p:?}");
            seen |= p.bit();
        }
        assert_eq!(seen.count_ones() as usize, ALL.len());
    }

    #[test]
    fn a_wire_mask_leaves_the_pages_it_cannot_address_enabled() {
        // The phone's 32-bit field cannot express GuidedRun onward; zero-
        // extending would curate them out invisibly on every curation push.
        let curated = mask_from_wire(1u32 << (Page::Pace as u8));
        assert_ne!(curated & Page::Pace.bit(), 0);
        assert_eq!(curated & Page::Nav.bit(), 0, "an addressed page stays off");
        assert_eq!(mask_from_wire(0) & Page::Pace.bit(), 0);
        for &p in ALL.iter().filter(|p| (**p as u8) >= WIRE_MASK_BITS) {
            assert_ne!(curated & p.bit(), 0, "{p:?} is past the wire's reach");
            assert_ne!(mask_from_wire(0) & p.bit(), 0, "{p:?} on an empty mask");
        }
    }

    #[test]
    fn next_in_skips_disabled_pages() {
        let mask = Page::Dashboard.bit() | Page::Pace.bit() | Page::Nav.bit();
        assert_eq!(Page::Dashboard.next_in(mask), Page::Pace);
        assert_eq!(Page::Pace.next_in(mask), Page::Nav);
        assert_eq!(Page::Nav.next_in(mask), Page::Dashboard, "wraps the subset");
    }

    #[test]
    fn prev_in_is_the_inverse_of_next_in() {
        let mask = Page::Dashboard.bit() | Page::Zones.bit() | Page::Fuel.bit() | Page::Recap.bit();
        let mut p = Page::Dashboard;
        for _ in 0..8 {
            let n = p.next_in(mask);
            assert_eq!(n.prev_in(mask), p);
            p = n;
        }
    }

    #[test]
    fn dashboard_is_always_reachable_even_from_an_empty_mask() {
        assert_eq!(Page::Splits.next_in(0), Page::Dashboard);
        assert_eq!(Page::Splits.prev_in(0), Page::Dashboard);
        assert_eq!(Page::Dashboard.next_in(0), Page::Dashboard);
    }

    #[test]
    fn a_parked_on_disabled_page_moves_off_and_does_not_return() {
        // The runner is on Roadbook when its data vanishes from the mask.
        let mask = Page::Dashboard.bit() | Page::Distance.bit();
        assert_eq!(Page::Roadbook.next_in(mask), Page::Dashboard);
        assert_eq!(Page::Roadbook.prev_in(mask), Page::Distance);
    }

    #[test]
    fn full_mask_matches_the_plain_cycle() {
        let mut p = Page::default();
        for _ in 0..ALL.len() {
            assert_eq!(p.next_in(u64::MAX), p.next());
            assert_eq!(p.prev_in(u64::MAX), p.prev());
            p = p.next();
        }
    }

    #[test]
    fn prev_reaches_the_last_page_in_one_step_and_wraps() {
        // The whole point of the reverse traversal: the LAST page is one press
        // back from the default — and the last page is deliberately the
        // Back-to-start safety page, so "lost" is one long-press from home.
        assert_eq!(Page::Dashboard.prev(), Page::BackToStart);
        assert_eq!(Page::BackToStart.prev(), Page::AutoEffort);
        assert_eq!(Page::Distance.prev(), Page::Dashboard);
        // Walking `prev` from the default visits every page exactly once and
        // returns home.
        let mut p = Page::default();
        let mut seen = [p; ALL.len()];
        for slot in seen.iter_mut().skip(1) {
            p = p.prev();
            *slot = p;
        }
        seen.sort_by_key(|q| *q as u8);
        assert_eq!(seen, ALL);
        assert_eq!(p.prev(), Page::default());
    }
}
