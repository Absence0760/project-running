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
    /// Average pace up large, with distance / time / HR as context.
    Pace,
}

impl Page {
    /// The next page in the button's cycle order, wrapping back to the start.
    pub fn next(self) -> Self {
        match self {
            Page::Dashboard => Page::Distance,
            Page::Distance => Page::Pace,
            Page::Pace => Page::Dashboard,
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
        assert_eq!(Page::Pace.next(), Page::Dashboard);
        // Walking `next` from the default visits all three and returns home.
        let mut p = Page::default();
        let mut seen = [p, p.next(), p.next().next()];
        seen.sort_by_key(|q| *q as u8);
        assert_eq!(seen, [Page::Dashboard, Page::Distance, Page::Pace]);
        for _ in 0..3 {
            p = p.next();
        }
        assert_eq!(p, Page::default());
    }
}
