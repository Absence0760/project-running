//! Persistent top status strip + the run-view page-position indicator.
//!
//! Pure geometry / state, like the rest of `core`: the strip's GPS *signal
//! bars* (0..=4) and the page-dot indicator are modelled here as plain
//! numbers; the `face` / display layer owns the actual pixels. The bar scale
//! is quantised to 0..=4 because the strip renders it as a small run of
//! filled/empty ticks a runner reads at a glance — an exact count is noise at
//! wrist scale.

use crate::fix::Fix;
use crate::page::Page;

/// Number of ticks either signal bar can fill — the strip draws this many
/// slots, 0 of them lit meaning "empty / searching".
pub const MAX_BARS: u8 = 4;

/// GPS acquisition-confidence bars (0..=4) from the current fix + its
/// freshness. `0` is the honest "searching" state a runner must be able to
/// distinguish from a weak-but-real fix: it means either no fix at all or one
/// older than `stale_after_s`, so a receiver that has silently dropped out
/// never reads as locked. A present, fresh fix is always at least one bar (we
/// have a position); the satellite count only refines the confidence above
/// that. Uptime subtraction saturates so a fix stamped in the future (clock
/// skew) can't underflow into a false "stale".
///
/// Satellite ladder: `<4` → 1, `4-5` → 2, `6-8` → 3, `>=9` → 4 — the rough
/// count-to-quality mapping where a handful of birds is a usable fix, six-plus
/// is solid, and nine-plus is the open-sky ceiling worth showing full bars.
pub fn gps_bars(fix: Option<&Fix>, uptime_s: u32, stale_after_s: u32) -> u8 {
    let Some(fix) = fix else { return 0 };
    if uptime_s.saturating_sub(fix.uptime_s) > stale_after_s {
        return 0;
    }
    match fix.sats {
        0..=3 => 1,
        4..=5 => 2,
        6..=8 => 3,
        _ => 4,
    }
}

/// The run-view page-dot indicator: which dot is lit (`active`) out of how
/// many (`total`). `active` is the page's position in the cycle, `total` the
/// number of pages, so the strip draws `total` dots with the `active`-th
/// filled.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct PageIndicator {
    pub active: usize,
    pub total: usize,
}

/// Total pages, counted by walking [`Page::next`] once around its cycle rather
/// than hardcoding a count — so adding a page (in the cycle) grows the dot row
/// automatically and can't silently desync from the enum.
fn page_count() -> usize {
    let mut count = 1;
    let mut p = Page::Dashboard.next();
    while p != Page::Dashboard {
        count += 1;
        p = p.next();
    }
    count
}

/// Build the dot indicator for the current page. `active` is the page's
/// discriminant (its cycle position); `total` is the live variant count.
pub fn page_indicator(page: Page) -> PageIndicator {
    PageIndicator {
        active: page as usize,
        total: page_count(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fix_at(sats: u8, uptime_s: u32) -> Fix {
        Fix {
            lat_deg: 40.0,
            lon_deg: -105.0,
            speed_mps: 3.0,
            course_deg: None,
            sats,
            alt_m: None,
            time_of_day: None,
            uptime_s,
        }
    }

    #[test]
    fn no_fix_is_searching() {
        assert_eq!(gps_bars(None, 100, 30), 0);
    }

    #[test]
    fn stale_fix_is_searching() {
        let f = fix_at(9, 60);
        // 100 - 60 = 40 > 30 → stale → 0, even with a full sat count.
        assert_eq!(gps_bars(Some(&f), 100, 30), 0);
    }

    #[test]
    fn fix_exactly_at_the_stale_boundary_is_still_live() {
        let f = fix_at(6, 70);
        // 100 - 70 = 30, not > 30 → still counts.
        assert_eq!(gps_bars(Some(&f), 100, 30), 3);
    }

    #[test]
    fn sat_ladder_maps_to_bars() {
        assert_eq!(gps_bars(Some(&fix_at(0, 100)), 100, 30), 1);
        assert_eq!(gps_bars(Some(&fix_at(3, 100)), 100, 30), 1);
        assert_eq!(gps_bars(Some(&fix_at(4, 100)), 100, 30), 2);
        assert_eq!(gps_bars(Some(&fix_at(5, 100)), 100, 30), 2);
        assert_eq!(gps_bars(Some(&fix_at(6, 100)), 100, 30), 3);
        assert_eq!(gps_bars(Some(&fix_at(8, 100)), 100, 30), 3);
        assert_eq!(gps_bars(Some(&fix_at(9, 100)), 100, 30), 4);
        assert_eq!(gps_bars(Some(&fix_at(20, 100)), 100, 30), 4);
    }

    #[test]
    fn future_stamped_fix_saturates_instead_of_underflowing() {
        let f = fix_at(7, 200);
        // uptime 100 < fix.uptime 200: saturating_sub → 0, never > stale.
        assert_eq!(gps_bars(Some(&f), 100, 30), 3);
    }

    #[test]
    fn gps_bars_never_exceed_the_scale() {
        for sats in 0..=64u8 {
            assert!(gps_bars(Some(&fix_at(sats, 100)), 100, 30) <= MAX_BARS);
        }
    }

    #[test]
    fn indicator_first_and_last_pages() {
        let first = page_indicator(Page::Dashboard);
        assert_eq!(first.active, 0);
        let last = page_indicator(Page::GearWear);
        // GearWear is the final variant, so its index is total - 1.
        assert_eq!(last.active, last.total - 1);
    }

    #[test]
    fn total_matches_the_live_variant_count() {
        // Pinned to today's page set; a new page must move this deliberately.
        assert_eq!(page_indicator(Page::Dashboard).total, 16);
    }

    #[test]
    fn walking_next_visits_every_active_index_once() {
        let total = page_indicator(Page::Dashboard).total;
        let mut seen = [false; 64];
        let mut p = Page::default();
        for _ in 0..total {
            let ind = page_indicator(p);
            assert_eq!(ind.total, total);
            assert!(ind.active < total);
            assert!(!seen[ind.active], "index {} seen twice", ind.active);
            seen[ind.active] = true;
            p = p.next();
        }
        for slot in seen.iter().take(total) {
            assert!(*slot, "an active index was never produced");
        }
        // A full walk returns to the default page.
        assert_eq!(p, Page::default());
    }
}
