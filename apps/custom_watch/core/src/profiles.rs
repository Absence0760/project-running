//! Activity profiles — Run / Trail / Ultra / Hike, each a named preset over
//! the knobs the watch already has (the §284/§286 curated page mask and the
//! GNSS recording mode), selected from the §351 idle settings menu.
//!
//! A profile is a **macro, not a container**: selecting one applies its preset
//! through the SAME paths a phone push or a quick-cycle press takes
//! (`Recorder::set_pages_enabled` via the settings channel, the shared
//! `set_gnss_mode`), so the §351 last-writer rule holds unchanged — a later
//! `SET1` pages push or an idle mode cycle simply overwrites the knob it
//! names, and the stored profile id remains "last applied", never a live
//! claim that every knob still matches. That is also why the presets carry no
//! alert-cadence axis: the fuel cadences are `fuel_plan`-derived product
//! numbers, and inventing per-profile physiology on the watch would pioneer a
//! feature web doesn't have (§24) — a desert runner's denser cadence already
//! has its wire (`SET1` `FLAG_FUEL`).
//!
//! The page masks are **curation presets, not capability gates**: they choose
//! emphasis for the §286 cycle (which still intersects with data-present
//! pages), and any page a preset drops returns via a phone pages push, a
//! different profile, or hide-empty-off. Two rows are in every preset by
//! contract: the Dashboard (the apply side force-includes it anyway) and
//! Back-to-start — §286's safety page stays one backward tap from home in
//! every profile, because getting un-lost is not an activity-specific need.

use crate::gnss_mode::GnssMode;
use crate::page::Page;

/// The four tier-1 activity profiles, in ladder order: rightward reads as
/// "longer / slower / more battery" (Run's every-second fixes through Hike's
/// Expedition cadence), so the §351 menu's directional edit has a true axis
/// to clamp on rather than an arbitrary cycle.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum ActivityProfile {
    Run,
    Trail,
    Ultra,
    Hike,
}

/// What a profile applies: the curated run-view page set (the same 64-bit
/// `Page::bit` mask `SET1` pushes) and the GNSS recording mode.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub struct ProfilePreset {
    pub pages: u64,
    pub gnss_mode: GnssMode,
}

impl ActivityProfile {
    /// The persisted / published discriminant. Stable — the CFG1 record
    /// stores it, so a reorder here would re-point a stored selection.
    pub const fn to_byte(self) -> u8 {
        match self {
            Self::Run => 0,
            Self::Trail => 1,
            Self::Ultra => 2,
            Self::Hike => 3,
        }
    }

    /// The profile a stored byte names, `None` for a byte that names none —
    /// a corrupt record reads as "no profile", never a wrong one.
    pub const fn from_byte(b: u8) -> Option<Self> {
        match b {
            0 => Some(Self::Run),
            1 => Some(Self::Trail),
            2 => Some(Self::Ultra),
            3 => Some(Self::Hike),
            _ => None,
        }
    }

    /// The menu row's value text.
    pub const fn label(self) -> &'static str {
        match self {
            Self::Run => "RUN",
            Self::Trail => "TRAIL",
            Self::Ultra => "ULTRA",
            Self::Hike => "HIKE",
        }
    }

    /// One rung right on the ladder — toward the longer activities; clamped,
    /// the §351 directional-edit rule (a press past the end must not wrap to
    /// the opposite extreme).
    pub const fn right(self) -> Self {
        match self {
            Self::Run => Self::Trail,
            Self::Trail => Self::Ultra,
            Self::Ultra | Self::Hike => Self::Hike,
        }
    }

    /// One rung left — toward the shorter, denser-fix activities; clamped.
    pub const fn left(self) -> Self {
        match self {
            Self::Hike => Self::Ultra,
            Self::Ultra => Self::Trail,
            Self::Trail | Self::Run => Self::Run,
        }
    }
}

fn mask(pages: &[Page]) -> u64 {
    let mut m = 0u64;
    for p in pages {
        m |= p.bit();
    }
    m
}

/// The full-cycle mask — every page enabled, which is also the recorder's
/// default before any curation.
fn all_pages() -> u64 {
    u64::MAX
}

/// The road-running preset drops the pushed-course cluster a road race rarely
/// loads; everything else stays. Built as a subtraction so a NEW page is
/// road-visible by default — a page has to be argued OUT of a preset, not
/// remembered into it.
fn run_pages() -> u64 {
    all_pages()
        & !mask(&[
            Page::Nav,
            Page::TurnCue,
            Page::CutoffEta,
            Page::Roadbook,
            Page::Fuel,
            Page::RouteElev,
            Page::RouteSimplify,
        ])
}

/// The hike preset drops the racing cluster — pacing a hike against a virtual
/// partner or a race ladder is noise — and keeps the whole nav + fuelling +
/// health surface.
fn hike_pages() -> u64 {
    all_pages()
        & !mask(&[
            Page::Pacer,
            Page::GuidedRun,
            Page::RacePredictor,
            Page::TrainingPaces,
            Page::RaceDay,
            Page::Splits,
            Page::DistanceBand,
        ])
}

/// The preset a profile applies. Trail and Ultra keep the full cycle — the
/// course, effort, and safety surfaces are exactly what those runs use — and
/// differ on the GNSS cadence alone (an ultra trades fix density for the
/// multi-day battery, the §227 Expedition class).
pub fn preset(p: ActivityProfile) -> ProfilePreset {
    match p {
        ActivityProfile::Run => ProfilePreset {
            pages: run_pages(),
            gnss_mode: GnssMode::Performance,
        },
        ActivityProfile::Trail => ProfilePreset {
            pages: all_pages(),
            gnss_mode: GnssMode::Balanced,
        },
        ActivityProfile::Ultra => ProfilePreset {
            pages: all_pages(),
            gnss_mode: GnssMode::Expedition,
        },
        ActivityProfile::Hike => ProfilePreset {
            pages: hike_pages(),
            gnss_mode: GnssMode::Expedition,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: [ActivityProfile; 4] = [
        ActivityProfile::Run,
        ActivityProfile::Trail,
        ActivityProfile::Ultra,
        ActivityProfile::Hike,
    ];

    #[test]
    fn bytes_roundtrip_and_garbage_reads_as_none() {
        for p in ALL {
            assert_eq!(ActivityProfile::from_byte(p.to_byte()), Some(p));
        }
        assert_eq!(ActivityProfile::from_byte(4), None);
        assert_eq!(ActivityProfile::from_byte(0xff), None);
    }

    #[test]
    fn the_ladder_clamps_at_both_ends() {
        use ActivityProfile::*;
        assert_eq!(Run.right(), Trail);
        assert_eq!(Trail.right(), Ultra);
        assert_eq!(Ultra.right(), Hike);
        assert_eq!(Hike.right(), Hike);
        assert_eq!(Hike.left(), Ultra);
        assert_eq!(Ultra.left(), Trail);
        assert_eq!(Trail.left(), Run);
        assert_eq!(Run.left(), Run);
    }

    #[test]
    fn every_preset_keeps_the_dashboard_and_the_safety_page() {
        // Back-to-start is §286's safety contract — one backward tap from
        // home in EVERY profile; the Dashboard is the cycle's anchor.
        for p in ALL {
            let m = preset(p).pages;
            assert!(m & Page::Dashboard.bit() != 0, "{p:?} dropped Dashboard");
            assert!(
                m & Page::BackToStart.bit() != 0,
                "{p:?} dropped Back-to-start"
            );
        }
    }

    #[test]
    fn the_road_preset_drops_the_course_cluster_and_keeps_the_race_one() {
        let m = preset(ActivityProfile::Run).pages;
        assert_eq!(m & Page::Nav.bit(), 0);
        assert_eq!(m & Page::Roadbook.bit(), 0);
        assert_eq!(m & Page::CutoffEta.bit(), 0);
        assert!(m & Page::Pacer.bit() != 0);
        assert!(m & Page::RacePredictor.bit() != 0);
        assert_eq!(
            preset(ActivityProfile::Run).gnss_mode,
            GnssMode::Performance
        );
    }

    #[test]
    fn the_hike_preset_drops_the_racing_cluster_and_keeps_nav_and_fuel() {
        let m = preset(ActivityProfile::Hike).pages;
        assert_eq!(m & Page::Pacer.bit(), 0);
        assert_eq!(m & Page::RacePredictor.bit(), 0);
        assert!(m & Page::Nav.bit() != 0);
        assert!(m & Page::Fuel.bit() != 0);
        assert!(m & Page::ElevationProfile.bit() != 0);
        assert_eq!(
            preset(ActivityProfile::Hike).gnss_mode,
            GnssMode::Expedition
        );
    }

    #[test]
    fn trail_and_ultra_keep_the_full_cycle_and_differ_on_cadence_alone() {
        assert_eq!(preset(ActivityProfile::Trail).pages, u64::MAX);
        assert_eq!(preset(ActivityProfile::Ultra).pages, u64::MAX);
        assert_eq!(preset(ActivityProfile::Trail).gnss_mode, GnssMode::Balanced);
        assert_eq!(
            preset(ActivityProfile::Ultra).gnss_mode,
            GnssMode::Expedition
        );
    }

    #[test]
    fn labels_fit_a_menu_row_value() {
        for p in ALL {
            assert!(p.label().len() <= 5);
        }
    }
}
