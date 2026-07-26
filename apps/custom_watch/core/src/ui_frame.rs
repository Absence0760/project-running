//! Per-frame screen decisions — the pure half of the UI + button tasks.
//!
//! The screen task owns the framebuffer and the sleep cadence; the button task
//! owns edge detection and debounce. What each of them *decides* from the
//! published state — whether to animate, which band the hero row shows, which
//! rows may be skipped this frame, whether a time-based refresh is still owed,
//! and what an absent snapshot means — is host-tested here.

use crate::button::stop_arm_pending;
use crate::elevation::{RezeroStatus, REZERO_BANNER_TTL_S};
use crate::face::{
    IdleView, CLOCK_HERO_ROWS, CLOCK_HERO_TOP_ROW, NAV_PANEL_ROWS, NAV_PANEL_TOP_ROW,
};
use crate::fix::Fix;
use crate::page::Page;
use crate::record::{RecordState, Snapshot};

/// Seconds after the last button press for which the face keeps animating (REC
/// blink, HR pulse, GPS search). Outside this window every animation holds a
/// steady frame, so an idle wrist stops paying the per-second display redraw on
/// a reflective panel where dark pixels save nothing — only fewer updates do.
pub const ANIM_WINDOW_S: u32 = 8;

pub fn animating(now_s: u32, last_interaction_s: u32) -> bool {
    now_s.saturating_sub(last_interaction_s) < ANIM_WINDOW_S
}

/// The page filter (data-present and curated) in force. No snapshot yet means
/// no filter — every page is walkable rather than none, so a pre-run press can
/// never dead-end on an empty cycle.
pub fn pages_mask(rec: Option<&Snapshot>) -> u64 {
    rec.map_or(u64::MAX, |s| s.pages_mask)
}

/// The recorder state the buttons act on. Before the first published snapshot
/// the run is idle, which is what the hardware actually is.
pub fn record_state(rec: Option<&Snapshot>) -> RecordState {
    rec.map_or(RecordState::Idle, |s| s.state)
}

/// Whether the alert engine considers a run under way — its in-run states, so
/// the standing fuel-overdue latch clears between runs. Narrower than
/// [`crate::face::run_view`]: a `Finished` run still shows a run view but its
/// reminders are over.
pub fn alerts_run_active(rec: Option<&Snapshot>) -> bool {
    rec.is_some_and(|s| matches!(s.state, RecordState::Recording | RecordState::Paused))
}

/// Whether the latest fix is still inside the staleness budget the face renders
/// with (see [`crate::face::stale_after_s`]) — the screen task's cue that a
/// fresh -> stale flip is a refresh it still owes.
pub fn fix_fresh(fix: Option<&Fix>, now_s: u32, stale_after_s: u32) -> bool {
    fix.is_some_and(|f| now_s.saturating_sub(f.uptime_s) <= stale_after_s)
}

/// The manual QNH re-zero's transient banner: shown for its TTL, and only on
/// the idle face — the gesture only exists there, and a run view's hero band
/// belongs to the run's own alerts.
pub fn rezero_banner_status(
    rezero: Option<(RezeroStatus, u32)>,
    now_s: u32,
    run_view: bool,
) -> Option<RezeroStatus> {
    if run_view {
        return None;
    }
    rezero
        .filter(|(_, at)| now_s.saturating_sub(*at) < REZERO_BANNER_TTL_S)
        .map(|(status, _)| status)
}

/// Whether the armed-stop prompt is showing: an arm inside its confirm window,
/// on a run view. An invisible arm reads as a dead button.
pub fn stop_pending(run_view: bool, stop_armed_at_s: Option<u32>, now_s: u32) -> bool {
    run_view && stop_armed_at_s.is_some_and(|armed_at| stop_arm_pending(armed_at, now_s))
}

/// What occupies the hero band (the top two rows) this frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum HeroBand {
    /// An on-run alert's inverse-video banner — the most unmissable treatment
    /// the panel gives, so it outranks the page's own hero.
    AlertBanner,
    /// The idle face's transient QNH re-zero feedback banner.
    RezeroBanner,
    /// A single-metric glance page's headline number in the generated numeral
    /// faces (three rows tall).
    BigNumHero,
    /// A numeral hero in the generated 16x32 medium face, over the same two
    /// rows a [`Self::TextHero`] occupies. Every page but Distance / Pace puts
    /// a label on row 2, so the three-row band would erase it; the medium face
    /// is the same cell size as the doubled text font and natively rasterised,
    /// so the geometry is unchanged and only the strokes improve.
    MedNumHero,
    /// A hero the numeral faces cannot spell, doubled over rows 0-1.
    TextHero,
    None,
}

/// The characters the generated numeral faces carry (`sharp_mip::bignum`'s
/// glyph set). The face choice is a frame decision, so it lives here rather
/// than in the driver; `watch_render`'s preview tests pin the two equal, so a
/// regenerated table that gains a glyph cannot silently leave this behind.
pub const NUMERAL_GLYPHS: &[u8] = b"0123456789:-.";

/// Whether `text` can be drawn entirely from the numeral faces. A glyph the
/// faces lack advances blank, and on a signed hero (`+0:42` ahead vs `-1:05`
/// behind) the sign is the one character that may not silently disappear — so
/// anything outside the set keeps the whole hero in the text font.
pub fn numeral_hero(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| NUMERAL_GLYPHS.contains(&b))
}

/// The frame inputs the hero band is decided from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HeroFrame {
    pub alert: bool,
    pub rezero_banner: bool,
    pub hero: bool,
    /// [`numeral_hero`] of the hero string.
    pub numeral: bool,
    /// The armed-stop banner spans two rows, and a three-row numeral hero would
    /// otherwise peek out under it (a two-row hero is covered outright).
    pub stop_pending: bool,
    pub page: Page,
}

pub fn hero_band(frame: HeroFrame) -> HeroBand {
    if frame.alert {
        HeroBand::AlertBanner
    } else if frame.rezero_banner {
        HeroBand::RezeroBanner
    } else if !frame.hero {
        HeroBand::None
    } else if !frame.numeral {
        HeroBand::TextHero
    } else if matches!(frame.page, Page::Distance | Page::Pace) {
        if frame.stop_pending {
            HeroBand::None
        } else {
            HeroBand::BigNumHero
        }
    } else {
        HeroBand::MedNumHero
    }
}

/// How one text row of the composed face is written to the framebuffer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum RowPaint {
    /// Left alone — its pixels are owned by a layer that composes them whole
    /// (the Nav map panel, the home clock band) and re-blanking them would
    /// dirty their lines every frame.
    Skip,
    /// The run dashboard's field grid: the row and its hairline dividers in one
    /// compare-write, so a separate rule pass can't re-dirty the rules.
    Ruled,
    Text,
}

/// The frame's row-layout inputs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FrameLayout {
    pub page: Page,
    pub run_view: bool,
    pub idle_view: IdleView,
    /// The Nav map panel is being composed this frame.
    pub panel_active: bool,
    /// The panel's pixels changed and are being redrawn, so its rows are
    /// blanked and rewritten rather than held.
    pub panel_repaint: bool,
}

pub fn row_paint(row: usize, layout: FrameLayout) -> RowPaint {
    let panel_rows = NAV_PANEL_TOP_ROW..NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS;
    if layout.panel_active && !layout.panel_repaint && panel_rows.contains(&row) {
        return RowPaint::Skip;
    }
    let clock_rows = CLOCK_HERO_TOP_ROW..CLOCK_HERO_TOP_ROW + CLOCK_HERO_ROWS;
    if !layout.run_view && layout.idle_view == IdleView::Home && clock_rows.contains(&row) {
        return RowPaint::Skip;
    }
    if layout.page == Page::Dashboard && layout.run_view {
        RowPaint::Ruled
    } else {
        RowPaint::Text
    }
}

/// Whether the screen still owes a refresh with no state change behind it: an
/// animation frame to advance, a fresh -> stale fix flip to land, a duty-cycled
/// HR reading whose hold budget expires, or a banner to retire. With none of
/// those the task falls back to its long heartbeat so a truly idle wrist wakes
/// the CPU seconds apart, not every second.
pub fn owes_timed_refresh(
    animating: bool,
    fix_fresh: bool,
    hr_shown: bool,
    rezero_banner: bool,
) -> bool {
    animating || fix_fresh || hr_shown || rezero_banner
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::record::Recorder;

    fn snapshot(state: RecordState) -> Snapshot {
        let mut r = Recorder::new();
        match state {
            RecordState::Idle => {}
            RecordState::Recording => r.start(0),
            RecordState::Paused => {
                r.start(0);
                r.pause(1);
            }
            RecordState::Finished => {
                r.start(0);
                r.stop(1);
            }
        }
        r.snapshot()
    }

    fn fix_at(uptime_s: u32) -> Fix {
        Fix {
            lat_deg: 40.0,
            lon_deg: -105.0,
            speed_mps: 2.0,
            course_deg: None,
            sats: 8,
            alt_m: None,
            time_of_day: None,
            uptime_s,
        }
    }

    #[test]
    fn the_animation_window_closes_at_its_boundary() {
        assert!(animating(0, 0));
        assert!(animating(ANIM_WINDOW_S - 1, 0));
        assert!(!animating(ANIM_WINDOW_S, 0));
        // A stamp from the future (clock skew) reads as a fresh press, never as
        // a wrapped-around expiry.
        assert!(animating(0, 5));
    }

    #[test]
    fn no_snapshot_means_no_page_filter_and_an_idle_recorder() {
        assert_eq!(pages_mask(None), u64::MAX);
        assert_eq!(record_state(None), RecordState::Idle);
        let snap = snapshot(RecordState::Recording);
        assert_eq!(pages_mask(Some(&snap)), snap.pages_mask);
        assert_eq!(record_state(Some(&snap)), RecordState::Recording);
    }

    #[test]
    fn alert_run_active_covers_the_in_run_states_only() {
        assert!(!alerts_run_active(None));
        assert!(alerts_run_active(Some(&snapshot(RecordState::Recording))));
        assert!(alerts_run_active(Some(&snapshot(RecordState::Paused))));
        assert!(!alerts_run_active(Some(&snapshot(RecordState::Finished))));
        assert!(!alerts_run_active(Some(&snapshot(RecordState::Idle))));
    }

    #[test]
    fn fix_freshness_is_inclusive_at_the_budget() {
        let f = fix_at(100);
        assert!(fix_fresh(Some(&f), 100, 5));
        assert!(fix_fresh(Some(&f), 105, 5));
        assert!(!fix_fresh(Some(&f), 106, 5));
        // No fix at all is never fresh.
        assert!(!fix_fresh(None, 100, 5));
        // A fix stamped ahead of now clamps to age zero rather than wrapping.
        assert!(fix_fresh(Some(&f), 99, 5));
    }

    #[test]
    fn the_rezero_banner_shows_for_its_ttl_on_the_idle_face_only() {
        let r = Some((RezeroStatus::NoGps, 100));
        assert_eq!(
            rezero_banner_status(r, 100, false),
            Some(RezeroStatus::NoGps)
        );
        assert_eq!(
            rezero_banner_status(r, 100 + REZERO_BANNER_TTL_S - 1, false),
            Some(RezeroStatus::NoGps)
        );
        assert_eq!(
            rezero_banner_status(r, 100 + REZERO_BANNER_TTL_S, false),
            None
        );
        // A run view's hero band belongs to the run's own alerts.
        assert_eq!(rezero_banner_status(r, 100, true), None);
        assert_eq!(rezero_banner_status(None, 100, false), None);
    }

    #[test]
    fn the_stop_prompt_shows_only_on_a_run_view_inside_the_confirm_window() {
        assert!(stop_pending(true, Some(10), 10));
        assert!(!stop_pending(true, None, 10));
        assert!(!stop_pending(false, Some(10), 10));
        // Past the guard's own window the prompt retires with the arm.
        assert!(!stop_pending(
            true,
            Some(10),
            10 + crate::button::STOP_CONFIRM_WINDOW_S + 1
        ));
    }

    #[test]
    fn an_alert_banner_outranks_every_other_hero_band() {
        let frame = HeroFrame {
            alert: true,
            rezero_banner: true,
            hero: true,
            numeral: true,
            stop_pending: false,
            page: Page::Distance,
        };
        assert_eq!(hero_band(frame), HeroBand::AlertBanner);
        assert_eq!(
            hero_band(HeroFrame {
                alert: false,
                ..frame
            }),
            HeroBand::RezeroBanner
        );
    }

    #[test]
    fn the_glance_pages_headline_in_numerals_and_yield_to_an_armed_stop() {
        let frame = HeroFrame {
            alert: false,
            rezero_banner: false,
            hero: true,
            numeral: true,
            stop_pending: false,
            page: Page::Distance,
        };
        assert_eq!(hero_band(frame), HeroBand::BigNumHero);
        assert_eq!(
            hero_band(HeroFrame {
                page: Page::Pace,
                ..frame
            }),
            HeroBand::BigNumHero
        );
        // The three-row numeral hero would peek out under the two-row banner.
        assert_eq!(
            hero_band(HeroFrame {
                stop_pending: true,
                ..frame
            }),
            HeroBand::None
        );
        // Every other page's two-row hero is covered outright, so it still
        // draws.
        assert_eq!(
            hero_band(HeroFrame {
                page: Page::Dashboard,
                stop_pending: true,
                ..frame
            }),
            HeroBand::MedNumHero
        );
    }

    #[test]
    fn every_other_numeral_hero_takes_the_medium_face() {
        let frame = HeroFrame {
            alert: false,
            rezero_banner: false,
            hero: true,
            numeral: true,
            stop_pending: false,
            page: Page::Lap,
        };
        for page in [
            Page::Dashboard,
            Page::Lap,
            Page::Zones,
            Page::GuidedRun,
            Page::RacePredictor,
            Page::ElevationProfile,
            Page::BackToStart,
            Page::Splits,
            Page::DistanceBand,
            Page::TrainingLoad,
            Page::Roadbook,
            Page::Fuel,
            Page::GearWear,
            Page::TrainingPaces,
            Page::Fitness,
        ] {
            assert_eq!(
                hero_band(HeroFrame { page, ..frame }),
                HeroBand::MedNumHero,
                "{page:?}"
            );
        }
    }

    #[test]
    fn a_hero_the_numeral_faces_cannot_spell_stays_in_the_text_font() {
        let frame = HeroFrame {
            alert: false,
            rezero_banner: false,
            hero: true,
            numeral: false,
            stop_pending: false,
            page: Page::Pacer,
        };
        assert_eq!(hero_band(frame), HeroBand::TextHero);
        // Even the three-row pages fall back rather than advance a blank cell
        // where a glyph the faces lack should be.
        assert_eq!(
            hero_band(HeroFrame {
                page: Page::Distance,
                ..frame
            }),
            HeroBand::TextHero
        );
        // Accepted consequence of deciding on glyphs rather than on a page
        // list: the signed pages' honest inactive `--` is spellable, so it
        // takes the numeral face while their live `+0:42` does not. The face
        // follows the string, and the day a regeneration adds `+` both states
        // converge with no page list to update.
        assert_eq!(
            hero_band(HeroFrame {
                numeral: true,
                ..frame
            }),
            HeroBand::MedNumHero
        );
        assert_eq!(
            hero_band(HeroFrame {
                page: Page::CutoffEta,
                numeral: true,
                ..frame
            }),
            HeroBand::MedNumHero
        );
    }

    #[test]
    fn the_numeral_test_admits_exactly_the_generated_glyph_set() {
        assert!(numeral_hero("32.40"));
        assert!(numeral_hero("6:20"));
        assert!(numeral_hero("1:02:03"));
        assert!(numeral_hero("--:--"));
        assert!(numeral_hero("-12"));
        // The signed split's `+` is not in the faces, so the whole hero (sign
        // included) has to stay in the text font — the alternative is a Pacer
        // page that cannot show ahead from behind.
        assert!(!numeral_hero("+0:42"));
        assert!(!numeral_hero("1.5 KM"));
        assert!(!numeral_hero("SET"));
        // An empty hero is not a numeral hero.
        assert!(!numeral_hero(""));
    }

    #[test]
    fn no_hero_leaves_the_band_empty() {
        assert_eq!(
            hero_band(HeroFrame {
                alert: false,
                rezero_banner: false,
                hero: false,
                numeral: true,
                stop_pending: false,
                page: Page::Dashboard,
            }),
            HeroBand::None
        );
    }

    #[test]
    fn a_resting_nav_panel_holds_its_rows() {
        let layout = FrameLayout {
            page: Page::Nav,
            run_view: true,
            idle_view: IdleView::Home,
            panel_active: true,
            panel_repaint: false,
        };
        for row in NAV_PANEL_TOP_ROW..NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS {
            assert_eq!(row_paint(row, layout), RowPaint::Skip, "row {row}");
        }
        // The rows outside the panel still compose normally.
        assert_eq!(row_paint(0, layout), RowPaint::Text);
        assert_eq!(
            row_paint(NAV_PANEL_TOP_ROW + NAV_PANEL_ROWS, layout),
            RowPaint::Text
        );
        // A repainting panel blanks and rewrites its rows.
        assert_eq!(
            row_paint(
                NAV_PANEL_TOP_ROW,
                FrameLayout {
                    panel_repaint: true,
                    ..layout
                }
            ),
            RowPaint::Text
        );
    }

    #[test]
    fn the_home_clock_band_is_composed_whole_and_skipped_here() {
        let layout = FrameLayout {
            page: Page::Dashboard,
            run_view: false,
            idle_view: IdleView::Home,
            panel_active: false,
            panel_repaint: false,
        };
        for row in CLOCK_HERO_TOP_ROW..CLOCK_HERO_TOP_ROW + CLOCK_HERO_ROWS {
            assert_eq!(row_paint(row, layout), RowPaint::Skip, "row {row}");
        }
        // The diagnostics face has no clock band, so every row writes.
        assert_eq!(
            row_paint(
                CLOCK_HERO_TOP_ROW,
                FrameLayout {
                    idle_view: IdleView::Diagnostics,
                    ..layout
                }
            ),
            RowPaint::Text
        );
        // A run view has no clock band either, even on the Dashboard page —
        // where the field grid takes over.
        assert_eq!(
            row_paint(
                CLOCK_HERO_TOP_ROW,
                FrameLayout {
                    run_view: true,
                    ..layout
                }
            ),
            RowPaint::Ruled
        );
    }

    #[test]
    fn only_the_run_dashboard_rules_its_rows() {
        let layout = FrameLayout {
            page: Page::Dashboard,
            run_view: true,
            idle_view: IdleView::Home,
            panel_active: false,
            panel_repaint: false,
        };
        assert_eq!(row_paint(0, layout), RowPaint::Ruled);
        assert_eq!(
            row_paint(
                0,
                FrameLayout {
                    page: Page::Pace,
                    ..layout
                }
            ),
            RowPaint::Text
        );
        assert_eq!(
            row_paint(
                0,
                FrameLayout {
                    run_view: false,
                    ..layout
                }
            ),
            RowPaint::Text
        );
    }

    #[test]
    fn a_timed_refresh_is_owed_for_any_time_based_reason_alone() {
        assert!(!owes_timed_refresh(false, false, false, false));
        assert!(owes_timed_refresh(true, false, false, false));
        assert!(owes_timed_refresh(false, true, false, false));
        assert!(owes_timed_refresh(false, false, true, false));
        assert!(owes_timed_refresh(false, false, false, true));
    }
}
