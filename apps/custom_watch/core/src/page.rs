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
    /// The next cut-off ETA up large (on / tight / behind vs the cutoff limit),
    /// with the distance to it and the projected arrival; an honest inactive
    /// state when no course cutoffs are loaded.
    CutoffEta,
    /// Breadcrumb course view: the loaded course polyline with the current
    /// position marked, distance-along-course, and the off-course alert.
    Nav,
    /// Distance back to the run's start up large, with a relative direction
    /// arrow, heading/bearing rows, and the TrackBack breadcrumb map.
    BackToStart,
}

impl Page {
    /// The next page in the button's cycle order, wrapping back to the start.
    pub fn next(self) -> Self {
        match self {
            Page::Dashboard => Page::Distance,
            Page::Distance => Page::Pace,
            Page::Pace => Page::Lap,
            Page::Lap => Page::Zones,
            Page::Zones => Page::Pacer,
            Page::Pacer => Page::RacePredictor,
            Page::RacePredictor => Page::CutoffEta,
            Page::CutoffEta => Page::Nav,
            Page::Nav => Page::BackToStart,
            Page::BackToStart => Page::Dashboard,
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

    #[test]
    fn next_cycles_every_page_and_wraps() {
        assert_eq!(Page::Dashboard.next(), Page::Distance);
        assert_eq!(Page::Distance.next(), Page::Pace);
        assert_eq!(Page::Pace.next(), Page::Lap);
        assert_eq!(Page::Lap.next(), Page::Zones);
        assert_eq!(Page::Zones.next(), Page::Pacer);
        assert_eq!(Page::Pacer.next(), Page::RacePredictor);
        assert_eq!(Page::RacePredictor.next(), Page::CutoffEta);
        assert_eq!(Page::CutoffEta.next(), Page::Nav);
        assert_eq!(Page::Nav.next(), Page::BackToStart);
        assert_eq!(Page::BackToStart.next(), Page::Dashboard);
        // Walking `next` from the default visits all ten and returns home.
        let mut p = Page::default();
        let mut seen = [p; 10];
        for slot in seen.iter_mut().skip(1) {
            p = p.next();
            *slot = p;
        }
        seen.sort_by_key(|q| *q as u8);
        assert_eq!(
            seen,
            [
                Page::Dashboard,
                Page::Distance,
                Page::Pace,
                Page::Lap,
                Page::Zones,
                Page::Pacer,
                Page::RacePredictor,
                Page::CutoffEta,
                Page::Nav,
                Page::BackToStart
            ]
        );
        let mut p = Page::default();
        for _ in 0..10 {
            p = p.next();
        }
        assert_eq!(p, Page::default());
    }
}
