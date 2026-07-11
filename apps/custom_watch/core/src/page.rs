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
            Page::Fitness => Page::Dashboard,
        }
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
    const ALL: [Page; 18] = [
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
        assert_eq!(Page::Fitness.next(), Page::Dashboard);
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
}
