//! Which data screen the run view shows, and the order the page button walks.
//!
//! Pure + host-tested like the rest of `core`: this decides the cycle order,
//! the app's `button` task owns only the debounce that advances it, and
//! [`crate::face::page_rows`] renders whichever page is current. Pages apply to
//! an in-progress run only — the idle status face ignores the page entirely.

/// The run-view pages, in button-cycle order. [`Page::Dashboard`] is the full
/// multi-metric view; the others are single-metric "glance" screens that put
/// one number up large.
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
    /// Distance banked in each pace bucket for the run so far — the pace
    /// analogue of the zones page (buckets from [`crate::pace_segments`]).
    Splits,
    /// Current HR up large, with the live zone and the per-zone moving-time
    /// breakdown as context.
    Zones,
    /// Virtual-partner ahead/behind time up large, with the goal, projected
    /// finish, and distance delta as context; an honest inactive state while
    /// no goal is configured.
    Pacer,
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
    /// Breadcrumb course view: the loaded course polyline with the current
    /// position marked, distance-along-course, and the off-course alert.
    Nav,
    /// Distance back to the run's start up large, with a relative direction
    /// arrow, heading/bearing rows, and the TrackBack breadcrumb map.
    BackToStart,
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
    /// The run's elevation profile as a mini-profile sparkline over the whole
    /// run ([`crate::record::ElevProfileView`]), with total ascent / descent as
    /// context; an honest "NO ELEVATION" until the first altitude sample lands.
    ElevationProfile,
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
    /// The re-plan proposal counts around missed sessions ([`crate::plan_replan`]);
    /// empty until synced.
    PlanReplan,
    /// The training-readiness score + band ([`crate::readiness`]); empty until
    /// synced.
    Readiness,
    /// The primary goal's ring progress ([`crate::goals`]); empty until synced.
    Goals,
    /// The next turn on the loaded course ([`crate::turn_cues`]); empty until
    /// synced.
    TurnCue,
    /// A simplified-course point/length summary ([`crate::route_simplify`]);
    /// empty until synced.
    RouteSimplify,
    /// Auto-segment-effort match counts ([`crate::auto_segment_effort`]); empty
    /// until synced.
    AutoEffort,
    /// The loaded course's elevation gain/loss summary ([`crate::route_elevation`]);
    /// empty until synced.
    RouteElev,
    /// The race-day countdown + goal-feasibility verdict ([`crate::race_day`]);
    /// empty until synced.
    RaceDay,
}

impl Page {
    /// The next page in the button's cycle order, wrapping back to the start.
    pub fn next(self) -> Self {
        match self {
            Page::Dashboard => Page::Distance,
            Page::Distance => Page::Pace,
            Page::Pace => Page::Lap,
            Page::Lap => Page::Splits,
            Page::Splits => Page::Zones,
            Page::Zones => Page::Pacer,
            Page::Pacer => Page::RacePredictor,
            Page::RacePredictor => Page::TrainingLoad,
            Page::TrainingLoad => Page::DistanceBand,
            Page::DistanceBand => Page::CutoffEta,
            Page::CutoffEta => Page::Roadbook,
            Page::Roadbook => Page::Fuel,
            Page::Fuel => Page::Nav,
            Page::Nav => Page::BackToStart,
            Page::BackToStart => Page::GearWear,
            Page::GearWear => Page::TrainingPaces,
            Page::TrainingPaces => Page::Fitness,
            Page::Fitness => Page::ElevationProfile,
            Page::ElevationProfile => Page::Recap,
            Page::Recap => Page::Streaks,
            Page::Streaks => Page::RunStats,
            Page::RunStats => Page::PrRecency,
            Page::PrRecency => Page::PlanReplan,
            Page::PlanReplan => Page::Readiness,
            Page::Readiness => Page::Goals,
            Page::Goals => Page::TurnCue,
            Page::TurnCue => Page::RouteSimplify,
            Page::RouteSimplify => Page::AutoEffort,
            Page::AutoEffort => Page::RouteElev,
            Page::RouteElev => Page::RaceDay,
            Page::RaceDay => Page::Dashboard,
        }
    }

    /// The previous page in the cycle — the exact inverse of [`Page::next`],
    /// wrapping from the first page back to the last. With 31 pages a forward-
    /// only walk needs up to ~30 presses to reach a late page; a reverse
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_the_dashboard() {
        assert_eq!(Page::default(), Page::Dashboard);
    }

    /// Every page, in declaration (`as u8`) order.
    const ALL: [Page; 31] = [
        Page::Dashboard,
        Page::Distance,
        Page::Pace,
        Page::Lap,
        Page::Splits,
        Page::Zones,
        Page::Pacer,
        Page::RacePredictor,
        Page::TrainingLoad,
        Page::DistanceBand,
        Page::CutoffEta,
        Page::Roadbook,
        Page::Fuel,
        Page::Nav,
        Page::BackToStart,
        Page::GearWear,
        Page::TrainingPaces,
        Page::Fitness,
        Page::ElevationProfile,
        Page::Recap,
        Page::Streaks,
        Page::RunStats,
        Page::PrRecency,
        Page::PlanReplan,
        Page::Readiness,
        Page::Goals,
        Page::TurnCue,
        Page::RouteSimplify,
        Page::AutoEffort,
        Page::RouteElev,
        Page::RaceDay,
    ];

    #[test]
    fn next_cycles_every_page_and_wraps() {
        assert_eq!(Page::Dashboard.next(), Page::Distance);
        assert_eq!(Page::Lap.next(), Page::Splits);
        assert_eq!(Page::Splits.next(), Page::Zones);
        assert_eq!(Page::RacePredictor.next(), Page::TrainingLoad);
        assert_eq!(Page::TrainingLoad.next(), Page::DistanceBand);
        assert_eq!(Page::DistanceBand.next(), Page::CutoffEta);
        assert_eq!(Page::CutoffEta.next(), Page::Roadbook);
        assert_eq!(Page::Roadbook.next(), Page::Fuel);
        assert_eq!(Page::Fuel.next(), Page::Nav);
        assert_eq!(Page::BackToStart.next(), Page::GearWear);
        assert_eq!(Page::GearWear.next(), Page::TrainingPaces);
        assert_eq!(Page::TrainingPaces.next(), Page::Fitness);
        assert_eq!(Page::Fitness.next(), Page::ElevationProfile);
        assert_eq!(Page::ElevationProfile.next(), Page::Recap);
        assert_eq!(Page::Recap.next(), Page::Streaks);
        assert_eq!(Page::Goals.next(), Page::TurnCue);
        assert_eq!(Page::RouteElev.next(), Page::RaceDay);
        assert_eq!(Page::RaceDay.next(), Page::Dashboard);
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
    fn prev_reaches_the_last_page_in_one_step_and_wraps() {
        // The whole point of the reverse traversal: the last page (RaceDay) is
        // one press back from the default, not ~30 forward.
        assert_eq!(Page::Dashboard.prev(), Page::RaceDay);
        assert_eq!(Page::RaceDay.prev(), Page::RouteElev);
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
