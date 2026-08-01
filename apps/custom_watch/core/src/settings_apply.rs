//! Phone→watch settings fan-out: which sink each present
//! [`crate::settings::WatchSettings`] field feeds, lifted out of the app's
//! `record` task body so the *routing* is host-tested and not just the
//! individual guards.
//!
//! [`crate::settings`] owns the wire format and decides whether a field is
//! present; each recorder / alert-engine setter owns that field's plausibility
//! guard. What was left in between, and lives here, is the fan-out: a decoded
//! frame in, an ordered list of typed [`SettingsEffect`]s out — one per present
//! field — that the task executes against its sinks. This is the
//! highest-churn seam in the firmware (the frame took two wire bumps in one
//! week) and its failure mode is invisible: a field wired to the wrong sink, or
//! a newly-added field never wired at all, still decodes cleanly and the watch
//! just quietly ignores what the phone sent.
//!
//! Adding a field to `WatchSettings` therefore cannot be silent here.
//! [`plan_apply`] destructures the struct with no `..` rest pattern, so a new
//! field is a missing-field compile error; binding it without emitting an
//! effect is an `unused_variables` warning, which the workspace clippy gate
//! denies; a new [`SettingsEffect`] variant is a compile error in both
//! [`SettingsEffect::kind`] and [`EffectKind::next`]; and the plan's capacity
//! derives from that chain rather than from a hand-kept number.
//!
//! Effects come out in the frame's own field order, so a plan reads like the
//! bytes that produced it. The sinks are independent, so the order carries no
//! semantics — it is there to make the plan comparable.
//!
//! Some guards are not a setter's and so run here, meaning an implausible value
//! yields NO effect rather than a clamped one: the QNH sea-level reference
//! ([`crate::record_cadence::plausible_sea_level_pa`], whose sink is a `state`
//! watch the baro task consumes), the home-clock timezone offset
//! ([`crate::settings::plausible_tz_offset_min`], whose sink is the watch the
//! ui task consumes), and the fuel-reminder cadences
//! ([`crate::settings::plausible_fuel_interval_s`], whose setter must keep
//! accepting the seconds-scale cadences the bench sim arms, so its only guard
//! of its own is a zero-check). Every other field is routed unconditionally and
//! rejected, if at all, at its setter.

use heapless::Vec;

use crate::auto_lap::AutoLap;
use crate::ice::IceCard;
use crate::race_phases::RacePhasePreset;
use crate::record_cadence::plausible_sea_level_pa;
use crate::settings::{
    plausible_fuel_interval_s, plausible_tz_offset_min, race_phase_preset_from_wire, GuidedRunId,
    WatchSettings,
};

/// One routed settings field: which sink to feed and the value to feed it,
/// carried in the sink's own argument shape so the task's executor is a bare
/// match with no arithmetic of its own.
#[derive(Clone, Copy, Debug, PartialEq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum SettingsEffect {
    /// [`crate::record::Recorder::set_max_hr`]
    MaxHr(u16),
    /// [`crate::record::Recorder::set_pacer_goal`]
    PacerGoal { distance_m: u32, time_s: u32 },
    /// [`crate::record::Recorder::set_gear`], widened to the setter's `f64`.
    Gear {
        baseline_m: f64,
        target_m: Option<f64>,
    },
    /// [`crate::alerts::AlertEngine::set_zone_ceiling`]; `None` clears it, which
    /// is a real update and not the same as the field being absent.
    ZoneCeiling(Option<u8>),
    /// The baro task's QNH reference watch (`state::SEA_LEVEL_PA`).
    SeaLevelPa(f32),
    /// [`crate::alerts::AlertEngine::set_fuel_intervals`]. An arm that failed
    /// its plausibility guard arrives as that setter's own leave-alone zero,
    /// so the other arm's update still lands.
    FuelIntervals {
        drink_interval_s: u32,
        eat_interval_s: u32,
    },
    /// [`crate::record::Recorder::set_pages_enabled`], widened from the wire's
    /// 32-bit field by [`crate::page::mask_from_wire`].
    PagesEnabled(u64),
    /// [`crate::record::Recorder::set_hide_empty_pages`]
    HideEmptyPages(bool),
    /// The ui task's home-clock offset watch (`state::TZ_OFFSET_MIN`).
    TzOffsetMin(i16),
    /// [`crate::alerts::AlertEngine::set_distance_interval`]; `None` disarms the
    /// alert, which is a real update and not the same as the field being absent.
    DistanceInterval(Option<u32>),
    /// [`crate::alerts::AlertEngine::set_time_interval`]; `None` disarms.
    TimeInterval(Option<u32>),
    /// [`crate::alerts::AlertEngine::set_pace_band`], in that setter's own
    /// `(fast, slow)` shape; `None` disarms. The transposition risk two
    /// same-typed arguments carry is held off by naming the edges everywhere
    /// upstream of here (`settings::PaceBandCfg`) and by the setter rejecting an
    /// inverted band, so this is the only place the pair is positional.
    PaceBand(Option<(u32, u32)>),
    /// [`crate::record::Recorder::set_race_phases`]; a `None` distance is how
    /// that setter is told to clear the plan.
    RacePhases {
        distance_m: Option<f64>,
        goal_time_s: Option<f64>,
        preset: RacePhasePreset,
    },
    /// [`crate::record::Recorder::set_guided_run`]; `None` deselects.
    GuidedRun(Option<GuidedRunId>),
    /// [`crate::record::Recorder::set_resting_hr`]
    RestingHr(u16),
    /// The `state::ICE` watch the ui task renders the responder card from, and
    /// the flash record the record task writes beside it; `None` clears the
    /// card. Unlike every other effect this one has TWO sinks, because a
    /// medical ID that vanishes on a power cycle is not a medical ID.
    Ice(Option<IceCard>),
    /// [`crate::record::Recorder::set_auto_lap`], and the `CFG1` flags byte the
    /// record task persists it in. Two sinks like [`SettingsEffect::Ice`], and
    /// for the same reason: a trigger that reverts to 1 km on a mid-race
    /// battery pull silently re-splits the rest of the race.
    AutoLap(AutoLap),
    /// [`crate::alerts::AlertEngine::set_storm_alert`], and — when armed — the
    /// baro task's threshold watch (`state::STORM_THRESHOLD_HPA`), which is
    /// where [`crate::storm::StormTracker::set_fall_threshold_hpa`]'s
    /// plausibility guard runs. The third two-sink effect, and the only one
    /// whose second sink is conditional: a disarm turns the banner off and
    /// deliberately leaves the tracker's threshold where it is, because the
    /// page keeps classifying and a disarm is not a re-calibration.
    /// `None` disarms, which is a real update and not the same as the field
    /// being absent.
    StormAlert(Option<f32>),
}

impl SettingsEffect {
    /// Which sink this effect feeds, without its value — the identity a plan is
    /// asserted against.
    pub const fn kind(&self) -> EffectKind {
        match self {
            Self::MaxHr(_) => EffectKind::MaxHr,
            Self::PacerGoal { .. } => EffectKind::PacerGoal,
            Self::Gear { .. } => EffectKind::Gear,
            Self::ZoneCeiling(_) => EffectKind::ZoneCeiling,
            Self::SeaLevelPa(_) => EffectKind::SeaLevelPa,
            Self::FuelIntervals { .. } => EffectKind::FuelIntervals,
            Self::PagesEnabled(_) => EffectKind::PagesEnabled,
            Self::HideEmptyPages(_) => EffectKind::HideEmptyPages,
            Self::TzOffsetMin(_) => EffectKind::TzOffsetMin,
            Self::DistanceInterval(_) => EffectKind::DistanceInterval,
            Self::TimeInterval(_) => EffectKind::TimeInterval,
            Self::PaceBand(_) => EffectKind::PaceBand,
            Self::RacePhases { .. } => EffectKind::RacePhases,
            Self::GuidedRun(_) => EffectKind::GuidedRun,
            Self::RestingHr(_) => EffectKind::RestingHr,
            Self::Ice(_) => EffectKind::Ice,
            Self::AutoLap(_) => EffectKind::AutoLap,
            Self::StormAlert(_) => EffectKind::StormAlert,
        }
    }
}

/// A [`SettingsEffect`] with its value stripped, linked into a chain
/// ([`EffectKind::next`]) that [`EffectKind::COUNT`] and the plan's capacity are
/// both derived from — so a new effect variant grows them by being linked in,
/// never by someone remembering to bump a number.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum EffectKind {
    MaxHr,
    PacerGoal,
    Gear,
    ZoneCeiling,
    SeaLevelPa,
    FuelIntervals,
    PagesEnabled,
    HideEmptyPages,
    TzOffsetMin,
    DistanceInterval,
    TimeInterval,
    PaceBand,
    RacePhases,
    GuidedRun,
    RestingHr,
    Ice,
    AutoLap,
    StormAlert,
}

impl EffectKind {
    /// Head of the chain, and the kind a fully-populated frame's plan starts on.
    pub const FIRST: Self = Self::MaxHr;

    /// The next kind in field order, `None` past the last.
    pub const fn next(self) -> Option<Self> {
        match self {
            Self::MaxHr => Some(Self::PacerGoal),
            Self::PacerGoal => Some(Self::Gear),
            Self::Gear => Some(Self::ZoneCeiling),
            Self::ZoneCeiling => Some(Self::SeaLevelPa),
            Self::SeaLevelPa => Some(Self::FuelIntervals),
            Self::FuelIntervals => Some(Self::PagesEnabled),
            Self::PagesEnabled => Some(Self::HideEmptyPages),
            Self::HideEmptyPages => Some(Self::TzOffsetMin),
            Self::TzOffsetMin => Some(Self::DistanceInterval),
            Self::DistanceInterval => Some(Self::TimeInterval),
            Self::TimeInterval => Some(Self::PaceBand),
            Self::PaceBand => Some(Self::RacePhases),
            Self::RacePhases => Some(Self::GuidedRun),
            Self::GuidedRun => Some(Self::RestingHr),
            Self::RestingHr => Some(Self::Ice),
            Self::Ice => Some(Self::AutoLap),
            Self::AutoLap => Some(Self::StormAlert),
            Self::StormAlert => None,
        }
    }

    /// How many kinds the chain visits.
    pub const COUNT: usize = {
        let mut n = 1;
        let mut kind = Self::FIRST;
        while let Some(next) = kind.next() {
            n += 1;
            kind = next;
        }
        n
    };
}

/// Ceiling on a plan's length: one effect per sink, which is the most a single
/// frame can ask for since every field routes to a sink of its own.
pub const MAX_SETTINGS_EFFECTS: usize = EffectKind::COUNT;

pub type SettingsPlan = Vec<SettingsEffect, MAX_SETTINGS_EFFECTS>;

/// Route a decoded settings frame into the effects that apply it.
///
/// An absent field produces no effect at all — a partial push is a partial
/// update, never a reset of the rest to a default. A present field produces
/// exactly one effect, except where a guard that has no setter to live in
/// rejects the value (see the module docs), which produces none.
pub fn plan_apply(s: &WatchSettings) -> SettingsPlan {
    let WatchSettings {
        max_hr,
        pacer,
        gear,
        zone_ceiling,
        sea_level_pa,
        fuel,
        pages,
        hide_empty_pages,
        tz_offset_min,
        distance_interval_m,
        time_interval_s,
        pace_band,
        race_phases,
        guided_run,
        resting_hr,
        ice,
        auto_lap,
        storm_alert,
    } = *s;

    let mut plan = SettingsPlan::new();
    if let Some(bpm) = max_hr {
        let _ = plan.push(SettingsEffect::MaxHr(bpm));
    }
    if let Some(p) = pacer {
        let _ = plan.push(SettingsEffect::PacerGoal {
            distance_m: p.distance_m,
            time_s: p.time_s,
        });
    }
    if let Some(g) = gear {
        let _ = plan.push(SettingsEffect::Gear {
            baseline_m: f64::from(g.baseline_m),
            target_m: g.target_m.map(f64::from),
        });
    }
    if let Some(zone) = zone_ceiling {
        let _ = plan.push(SettingsEffect::ZoneCeiling(zone));
    }
    if let Some(pa) = sea_level_pa.filter(|pa| plausible_sea_level_pa(*pa)) {
        let _ = plan.push(SettingsEffect::SeaLevelPa(pa));
    }
    if let Some(f) = fuel {
        // A guard the setter cannot own (the bench sim legitimately arms
        // seconds-scale cadences there), run per arm rather than per field: an
        // implausible arm routes as the setter's leave-alone zero — dropped,
        // not clamped, so the arm keeps the cadence the runner last chose —
        // while a good arm beside it still lands. A tiny interval would
        // otherwise win the shared alert slot nearly every tick and starve the
        // safety alerts. When neither arm survives there is nothing to route.
        let drink_interval_s = if plausible_fuel_interval_s(f.drink_interval_s) {
            f.drink_interval_s
        } else {
            0
        };
        let eat_interval_s = if plausible_fuel_interval_s(f.eat_interval_s) {
            f.eat_interval_s
        } else {
            0
        };
        if drink_interval_s != 0 || eat_interval_s != 0 {
            let _ = plan.push(SettingsEffect::FuelIntervals {
                drink_interval_s,
                eat_interval_s,
            });
        }
    }
    if let Some(mask) = pages {
        // Already the recorder's full-width mask: since the v4 frame carries 64
        // bits, the widening that used to happen here now happens once in
        // `settings::decode`, where the frame's version says whether it is owed.
        let _ = plan.push(SettingsEffect::PagesEnabled(mask));
    }
    if let Some(hide) = hide_empty_pages {
        let _ = plan.push(SettingsEffect::HideEmptyPages(hide));
    }
    if let Some(m) = plausible_tz_offset_min(tz_offset_min) {
        let _ = plan.push(SettingsEffect::TzOffsetMin(m));
    }
    if let Some(m) = distance_interval_m {
        let _ = plan.push(SettingsEffect::DistanceInterval(m));
    }
    if let Some(s) = time_interval_s {
        let _ = plan.push(SettingsEffect::TimeInterval(s));
    }
    if let Some(band) = pace_band {
        let _ =
            plan.push(SettingsEffect::PaceBand(band.map(|b| {
                (u32::from(b.fast_s_per_km), u32::from(b.slow_s_per_km))
            })));
    }
    if let Some(cfg) = race_phases {
        // The third guard with no setter to live in: a preset byte naming no
        // member of the enum is not a value `set_race_phases` can be handed, so
        // it is dropped here — costing only this field, never the frame.
        if let Some(preset) = race_phase_preset_from_wire(cfg.preset) {
            let _ = plan.push(SettingsEffect::RacePhases {
                distance_m: cfg.distance_m.map(f64::from),
                goal_time_s: cfg.goal_time_s.map(f64::from),
                preset,
            });
        }
    }
    if let Some(id) = guided_run {
        let _ = plan.push(SettingsEffect::GuidedRun(id));
    }
    if let Some(bpm) = resting_hr {
        let _ = plan.push(SettingsEffect::RestingHr(bpm));
    }
    if let Some(card) = ice {
        // No guard here: the card's only plausibility rule is that its bytes
        // are renderable, and `settings::decode` already refuses the whole
        // frame otherwise — there is nothing left for this seam to reject.
        let _ = plan.push(SettingsEffect::Ice(card));
    }
    if let Some(trigger) = auto_lap.and_then(AutoLap::from_byte) {
        // The fourth guard with no setter to live in: the setter takes the
        // enum, so a byte naming no rung is dropped here — costing only this
        // field, never the frame, and leaving the trigger already armed alone
        // rather than resetting a race's splits to a default.
        let _ = plan.push(SettingsEffect::AutoLap(trigger));
    }
    if let Some(threshold) = storm_alert {
        // No guard here: an armed threshold's plausibility window lives on the
        // tracker's setter, which leaves the current threshold standing rather
        // than clamping — routing it unconditionally keeps this seam a pure
        // fan-out, the same as the distance and time cadences.
        let _ = plan.push(SettingsEffect::StormAlert(threshold));
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::record_cadence::{MAX_SEA_LEVEL_PA, MIN_SEA_LEVEL_PA};
    use crate::settings::{
        race_phase_preset_to_wire, PaceBandCfg, RacePhasesCfg, GUIDED_RUN_ID_LEN,
    };
    use crate::settings::{
        FuelCfg, GearCfg, PacerGoalCfg, FUEL_INTERVAL_MAX_S, FUEL_INTERVAL_MIN_S, MAX_SETTINGS_LEN,
        TZ_OFFSET_LIMIT_MIN,
    };

    /// A frame carrying every field, each with a value its guard accepts. An
    /// exhaustive struct literal on purpose: a new `WatchSettings` field is a
    /// compile error here, so the fixture can't quietly stop being full.
    fn fully_populated() -> WatchSettings {
        WatchSettings {
            auto_lap: Some(AutoLap::Km5.to_byte()),
            max_hr: Some(185),
            pacer: Some(PacerGoalCfg {
                distance_m: 42_195,
                time_s: 12_600,
            }),
            gear: Some(GearCfg {
                baseline_m: 700_000.0,
                target_m: Some(800_000.0),
            }),
            zone_ceiling: Some(Some(3)),
            sea_level_pa: Some(101_325.0),
            fuel: Some(FuelCfg {
                drink_interval_s: 900,
                eat_interval_s: 1_800,
            }),
            pages: Some(0b1010),
            hide_empty_pages: Some(true),
            tz_offset_min: Some(-420),
            distance_interval_m: Some(Some(1_000)),
            time_interval_s: Some(Some(1_800)),
            pace_band: Some(Some(PaceBandCfg {
                fast_s_per_km: 300,
                slow_s_per_km: 420,
            })),
            race_phases: Some(RacePhasesCfg {
                distance_m: Some(42_195),
                goal_time_s: Some(12_600),
                preset: race_phase_preset_to_wire(RacePhasePreset::TenTenTen),
            }),
            guided_run: Some(GuidedRunId::new("easy-30")),
            resting_hr: Some(48),
            ice: Some(IceCard::new(
                "ALEX MORGAN",
                "O NEG",
                "PENICILLIN, ASTHMA",
                "JAMIE MORGAN",
                "+1 555 0134",
            )),
            storm_alert: Some(Some(crate::storm::STORM_FALL_HPA)),
        }
    }

    /// How many fields the frame actually carries, counted off the wire's own
    /// presence bitfields rather than off a list kept here. A new settings field
    /// cannot reach the watch without a presence bit, so this oracle grows with
    /// the format and stays independent of [`EffectKind`].
    fn present_field_count(s: &WatchSettings) -> usize {
        let mut buf = [0u8; MAX_SETTINGS_LEN];
        s.encode(&mut buf).expect("the fixture encodes");
        (buf[5].count_ones() + buf[6].count_ones() + buf[7].count_ones()) as usize
    }

    type Kinds = Vec<EffectKind, MAX_SETTINGS_EFFECTS>;

    fn kind_chain() -> Kinds {
        let mut kinds = Kinds::new();
        let mut kind = Some(EffectKind::FIRST);
        while let Some(k) = kind {
            kinds.push(k).expect("the chain fits its own count");
            kind = k.next();
        }
        kinds
    }

    fn kinds_of(plan: &SettingsPlan) -> Kinds {
        plan.iter().map(SettingsEffect::kind).collect()
    }

    #[test]
    fn every_present_field_routes_to_exactly_one_effect() {
        // The load-bearing guard: a field the phone sent that this module never
        // routes is invisible at runtime — the frame decodes, the watch just
        // ignores it. Both sides of the count are derived (the wire's presence
        // bits, the effect chain), so neither can be satisfied by editing a
        // number here.
        let s = fully_populated();
        let plan = plan_apply(&s);
        assert_eq!(plan.len(), present_field_count(&s));
        assert_eq!(kinds_of(&plan), kind_chain());
    }

    #[test]
    fn the_kind_chain_visits_every_effect_once() {
        let chain = kind_chain();
        assert_eq!(chain.len(), EffectKind::COUNT);
        for (i, a) in chain.iter().enumerate() {
            for b in chain.iter().skip(i + 1) {
                assert_ne!(a, b, "{a:?} appears twice in the chain");
            }
        }
    }

    #[test]
    fn a_full_plan_exactly_fills_its_capacity() {
        // A plan that outgrew its capacity would drop effects off the end
        // silently, which is the same invisible failure the routing itself has.
        assert_eq!(plan_apply(&fully_populated()).len(), MAX_SETTINGS_EFFECTS);
    }

    #[test]
    fn an_empty_frame_applies_nothing() {
        // Absent is "leave it alone", never "reset to a default": a phone that
        // pushes one field must not wipe the eight it didn't mention.
        assert!(plan_apply(&WatchSettings::default()).is_empty());
    }

    #[test]
    fn each_field_routes_to_its_own_sink_and_nothing_else() {
        let full = fully_populated();
        let expected = [
            (
                WatchSettings {
                    max_hr: full.max_hr,
                    ..WatchSettings::default()
                },
                SettingsEffect::MaxHr(185),
            ),
            (
                WatchSettings {
                    pacer: full.pacer,
                    ..WatchSettings::default()
                },
                SettingsEffect::PacerGoal {
                    distance_m: 42_195,
                    time_s: 12_600,
                },
            ),
            (
                WatchSettings {
                    gear: full.gear,
                    ..WatchSettings::default()
                },
                SettingsEffect::Gear {
                    baseline_m: 700_000.0,
                    target_m: Some(800_000.0),
                },
            ),
            (
                WatchSettings {
                    zone_ceiling: full.zone_ceiling,
                    ..WatchSettings::default()
                },
                SettingsEffect::ZoneCeiling(Some(3)),
            ),
            (
                WatchSettings {
                    sea_level_pa: full.sea_level_pa,
                    ..WatchSettings::default()
                },
                SettingsEffect::SeaLevelPa(101_325.0),
            ),
            (
                WatchSettings {
                    fuel: full.fuel,
                    ..WatchSettings::default()
                },
                SettingsEffect::FuelIntervals {
                    drink_interval_s: 900,
                    eat_interval_s: 1_800,
                },
            ),
            (
                WatchSettings {
                    pages: full.pages,
                    ..WatchSettings::default()
                },
                // Verbatim, not widened: the v4 frame already carries all 64 bits.
                SettingsEffect::PagesEnabled(0b1010),
            ),
            (
                WatchSettings {
                    hide_empty_pages: full.hide_empty_pages,
                    ..WatchSettings::default()
                },
                SettingsEffect::HideEmptyPages(true),
            ),
            (
                WatchSettings {
                    tz_offset_min: full.tz_offset_min,
                    ..WatchSettings::default()
                },
                SettingsEffect::TzOffsetMin(-420),
            ),
            (
                WatchSettings {
                    distance_interval_m: full.distance_interval_m,
                    ..WatchSettings::default()
                },
                SettingsEffect::DistanceInterval(Some(1_000)),
            ),
            (
                WatchSettings {
                    time_interval_s: full.time_interval_s,
                    ..WatchSettings::default()
                },
                SettingsEffect::TimeInterval(Some(1_800)),
            ),
            (
                WatchSettings {
                    pace_band: full.pace_band,
                    ..WatchSettings::default()
                },
                SettingsEffect::PaceBand(Some((300, 420))),
            ),
            (
                WatchSettings {
                    race_phases: full.race_phases,
                    ..WatchSettings::default()
                },
                SettingsEffect::RacePhases {
                    distance_m: Some(42_195.0),
                    goal_time_s: Some(12_600.0),
                    preset: RacePhasePreset::TenTenTen,
                },
            ),
            (
                WatchSettings {
                    guided_run: full.guided_run,
                    ..WatchSettings::default()
                },
                SettingsEffect::GuidedRun(GuidedRunId::new("easy-30")),
            ),
            (
                WatchSettings {
                    resting_hr: full.resting_hr,
                    ..WatchSettings::default()
                },
                SettingsEffect::RestingHr(48),
            ),
            (
                WatchSettings {
                    ice: full.ice,
                    ..WatchSettings::default()
                },
                SettingsEffect::Ice(IceCard::new(
                    "ALEX MORGAN",
                    "O NEG",
                    "PENICILLIN, ASTHMA",
                    "JAMIE MORGAN",
                    "+1 555 0134",
                )),
            ),
            (
                WatchSettings {
                    auto_lap: full.auto_lap,
                    ..WatchSettings::default()
                },
                SettingsEffect::AutoLap(AutoLap::Km5),
            ),
            (
                WatchSettings {
                    storm_alert: full.storm_alert,
                    ..WatchSettings::default()
                },
                SettingsEffect::StormAlert(Some(crate::storm::STORM_FALL_HPA)),
            ),
        ];
        for (frame, effect) in expected {
            let plan = plan_apply(&frame);
            assert_eq!(plan.as_slice(), &[effect][..], "one field, one effect");
        }
        assert_eq!(expected.len(), EffectKind::COUNT, "a sink went unpinned");
    }

    #[test]
    fn an_untracked_shoe_keeps_its_baseline_and_loses_only_its_target() {
        let plan = plan_apply(&WatchSettings {
            gear: Some(GearCfg {
                baseline_m: 250_000.0,
                target_m: None,
            }),
            ..WatchSettings::default()
        });
        assert_eq!(
            plan.as_slice(),
            [SettingsEffect::Gear {
                baseline_m: 250_000.0,
                target_m: None,
            }]
        );
    }

    #[test]
    fn clearing_the_zone_ceiling_is_an_update_not_an_absence() {
        // `Some(None)` is the phone disarming the alert and must reach the
        // engine; `None` is the field not being in the frame at all. Collapsing
        // the two would leave a ceiling armed that the runner turned off.
        assert_eq!(
            plan_apply(&WatchSettings {
                zone_ceiling: Some(None),
                ..WatchSettings::default()
            })
            .as_slice(),
            [SettingsEffect::ZoneCeiling(None)]
        );
        assert!(plan_apply(&WatchSettings {
            zone_ceiling: None,
            ..WatchSettings::default()
        })
        .is_empty());
    }

    #[test]
    fn an_implausible_qnh_is_dropped_rather_than_clamped() {
        // The reference feeds every barometric altitude the watch derives, so a
        // corrupt push must leave the current one standing. NaN included: it
        // would poison the altitude rather than merely offset it.
        for pa in [
            MIN_SEA_LEVEL_PA - 1.0,
            MAX_SEA_LEVEL_PA + 1.0,
            0.0,
            f32::NAN,
            f32::INFINITY,
        ] {
            let plan = plan_apply(&WatchSettings {
                sea_level_pa: Some(pa),
                ..WatchSettings::default()
            });
            assert!(plan.is_empty(), "{pa} must not be published");
        }
        for pa in [MIN_SEA_LEVEL_PA, 101_325.0, MAX_SEA_LEVEL_PA] {
            let plan = plan_apply(&WatchSettings {
                sea_level_pa: Some(pa),
                ..WatchSettings::default()
            });
            assert_eq!(plan.as_slice(), &[SettingsEffect::SeaLevelPa(pa)][..]);
        }
    }

    #[test]
    fn an_implausible_timezone_offset_is_dropped_rather_than_clamped() {
        // A clamped clock is confidently wrong; an unshifted one stays honestly
        // UTC-labelled.
        for m in [
            TZ_OFFSET_LIMIT_MIN + 1,
            -TZ_OFFSET_LIMIT_MIN - 1,
            i16::MAX,
            i16::MIN,
        ] {
            let plan = plan_apply(&WatchSettings {
                tz_offset_min: Some(m),
                ..WatchSettings::default()
            });
            assert!(plan.is_empty(), "{m} must not be published");
        }
        for m in [-TZ_OFFSET_LIMIT_MIN, 0, TZ_OFFSET_LIMIT_MIN] {
            let plan = plan_apply(&WatchSettings {
                tz_offset_min: Some(m),
                ..WatchSettings::default()
            });
            assert_eq!(plan.as_slice(), &[SettingsEffect::TzOffsetMin(m)][..]);
        }
    }

    #[test]
    fn an_implausible_fuel_cadence_is_dropped_rather_than_clamped() {
        // A 1 s cadence would win the shared alert slot nearly every tick and
        // starve the GPS-lost / off-course / cutoff alerts; a clamp would
        // chirp a cadence the runner never chose all race. Dropping leaves the
        // arm on the cadence it already had, and with neither arm surviving
        // there is no effect at all.
        for s in [
            1,
            FUEL_INTERVAL_MIN_S - 1,
            FUEL_INTERVAL_MAX_S + 1,
            u32::MAX,
        ] {
            let plan = plan_apply(&WatchSettings {
                fuel: Some(FuelCfg {
                    drink_interval_s: s,
                    eat_interval_s: s,
                }),
                ..WatchSettings::default()
            });
            assert!(plan.is_empty(), "{s} must not be routed");
        }
        for s in [FUEL_INTERVAL_MIN_S, 900, FUEL_INTERVAL_MAX_S] {
            let plan = plan_apply(&WatchSettings {
                fuel: Some(FuelCfg {
                    drink_interval_s: s,
                    eat_interval_s: s,
                }),
                ..WatchSettings::default()
            });
            assert_eq!(
                plan.as_slice(),
                &[SettingsEffect::FuelIntervals {
                    drink_interval_s: s,
                    eat_interval_s: s,
                }][..]
            );
        }
    }

    #[test]
    fn a_bad_fuel_arm_costs_only_itself_not_its_sibling() {
        // The guard runs per arm: a desert runner's tightened drink cadence
        // must not vanish because the eat half of the same push was corrupt.
        // The failed arm routes as the setter's leave-alone zero, so its
        // current cadence stands.
        for (drink, eat, effect) in [
            (
                1,
                1_800,
                SettingsEffect::FuelIntervals {
                    drink_interval_s: 0,
                    eat_interval_s: 1_800,
                },
            ),
            (
                900,
                FUEL_INTERVAL_MAX_S + 1,
                SettingsEffect::FuelIntervals {
                    drink_interval_s: 900,
                    eat_interval_s: 0,
                },
            ),
        ] {
            let plan = plan_apply(&WatchSettings {
                fuel: Some(FuelCfg {
                    drink_interval_s: drink,
                    eat_interval_s: eat,
                }),
                ..WatchSettings::default()
            });
            assert_eq!(plan.as_slice(), &[effect][..]);
        }
    }

    #[test]
    fn a_rejected_guard_costs_only_its_own_field() {
        // These guards live outside their sinks, so a bad value there must not
        // take the rest of the frame down with it.
        let mut s = fully_populated();
        s.sea_level_pa = Some(f32::NAN);
        s.tz_offset_min = Some(i16::MAX);
        s.fuel = Some(FuelCfg {
            drink_interval_s: 1,
            eat_interval_s: u32::MAX,
        });
        let plan = plan_apply(&s);
        assert_eq!(plan.len(), EffectKind::COUNT - 3);
        assert!(!kinds_of(&plan).contains(&EffectKind::SeaLevelPa));
        assert!(!kinds_of(&plan).contains(&EffectKind::TzOffsetMin));
        assert!(!kinds_of(&plan).contains(&EffectKind::FuelIntervals));
    }

    #[test]
    fn disarming_a_v4_setting_is_an_update_not_an_absence() {
        // `Some(None)` is the phone turning a feature off and must reach its
        // sink; `None` is the field not being in the frame. Collapsing the two
        // would leave an alert armed, or a guided run selected, that the runner
        // switched off — the same distinction `zone_ceiling` has always carried.
        for (frame, effect) in [
            (
                WatchSettings {
                    distance_interval_m: Some(None),
                    ..WatchSettings::default()
                },
                SettingsEffect::DistanceInterval(None),
            ),
            (
                WatchSettings {
                    time_interval_s: Some(None),
                    ..WatchSettings::default()
                },
                SettingsEffect::TimeInterval(None),
            ),
            (
                WatchSettings {
                    pace_band: Some(None),
                    ..WatchSettings::default()
                },
                SettingsEffect::PaceBand(None),
            ),
            (
                WatchSettings {
                    guided_run: Some(None),
                    ..WatchSettings::default()
                },
                SettingsEffect::GuidedRun(None),
            ),
            (
                WatchSettings {
                    storm_alert: Some(None),
                    ..WatchSettings::default()
                },
                SettingsEffect::StormAlert(None),
            ),
            (
                WatchSettings {
                    race_phases: Some(RacePhasesCfg {
                        distance_m: None,
                        goal_time_s: None,
                        preset: race_phase_preset_to_wire(RacePhasePreset::Even),
                    }),
                    ..WatchSettings::default()
                },
                // A `None` distance IS the clear, so the effect still routes and
                // the setter drops the plan on arrival.
                SettingsEffect::RacePhases {
                    distance_m: None,
                    goal_time_s: None,
                    preset: RacePhasePreset::Even,
                },
            ),
        ] {
            assert_eq!(plan_apply(&frame).as_slice(), &[effect][..]);
        }
    }

    #[test]
    fn an_unknown_race_phase_preset_byte_costs_only_its_own_field() {
        // The third guard with no setter to live in. A byte naming no preset
        // cannot be handed to `set_race_phases` at all, so it is dropped — but
        // dropping the frame would let one bad byte discard a whole push.
        let mut s = fully_populated();
        s.race_phases = Some(RacePhasesCfg {
            distance_m: Some(42_195),
            goal_time_s: Some(12_600),
            preset: 3,
        });
        let plan = plan_apply(&s);
        assert!(!kinds_of(&plan).contains(&EffectKind::RacePhases));
        assert_eq!(plan.len(), EffectKind::COUNT - 1);
        for b in 0..=2u8 {
            let plan = plan_apply(&WatchSettings {
                race_phases: Some(RacePhasesCfg {
                    distance_m: Some(10_000),
                    goal_time_s: None,
                    preset: b,
                }),
                ..WatchSettings::default()
            });
            assert_eq!(plan.len(), 1, "preset byte {b} must route");
        }
    }

    #[test]
    fn an_auto_lap_byte_naming_no_rung_costs_only_its_own_field() {
        // The trigger's guard has no setter to live in either, so it runs here.
        // A garbage byte must not reset a race's splits to a default, and must
        // not take the rest of the push down with it.
        let mut s = fully_populated();
        s.auto_lap = Some(200);
        let plan = plan_apply(&s);
        assert!(!kinds_of(&plan).contains(&EffectKind::AutoLap));
        assert_eq!(plan.len(), EffectKind::COUNT - 1);
        for t in [
            AutoLap::Off,
            AutoLap::Km1,
            AutoLap::Mi1,
            AutoLap::Km5,
            AutoLap::Mi5,
            AutoLap::Min5,
            AutoLap::Min10,
            AutoLap::Min30,
        ] {
            let plan = plan_apply(&WatchSettings {
                auto_lap: Some(t.to_byte()),
                ..WatchSettings::default()
            });
            assert_eq!(plan.as_slice(), &[SettingsEffect::AutoLap(t)][..]);
        }
    }

    #[test]
    fn a_pace_band_reaches_the_setter_edges_unswapped() {
        // The one place the pair goes positional. A transposition here would arm
        // an inverted band the setter then refuses, so the runner's push would
        // vanish with no error anywhere.
        let plan = plan_apply(&WatchSettings {
            pace_band: Some(Some(PaceBandCfg {
                fast_s_per_km: 300,
                slow_s_per_km: 420,
            })),
            ..WatchSettings::default()
        });
        assert_eq!(
            plan.as_slice(),
            &[SettingsEffect::PaceBand(Some((300, 420)))][..]
        );
    }

    #[test]
    fn a_guided_run_id_routes_as_the_library_string_not_an_index() {
        // The whole point of carrying the id: a later firmware build that
        // reorders `guided_run_library()` must not re-point what the phone sent.
        let plan = plan_apply(&WatchSettings {
            guided_run: Some(GuidedRunId::new("tempo-builder-25")),
            ..WatchSettings::default()
        });
        let [SettingsEffect::GuidedRun(Some(id))] = plan.as_slice() else {
            panic!("expected one guided-run effect, got {plan:?}");
        };
        assert_eq!(id.as_str(), "tempo-builder-25");
        // An id too long for the field is refused at construction rather than
        // truncated into a different (or prefix-matching) run.
        assert_eq!(GuidedRunId::new(&"x".repeat(GUIDED_RUN_ID_LEN + 1)), None);
    }

    #[test]
    fn a_plan_preserves_the_frames_field_order() {
        // Not a semantic requirement (the sinks are independent) but a pinned
        // one, so a plan reads like the bytes that produced it.
        let plan = plan_apply(&WatchSettings {
            hide_empty_pages: Some(false),
            max_hr: Some(190),
            zone_ceiling: Some(Some(4)),
            ..WatchSettings::default()
        });
        assert_eq!(
            kinds_of(&plan),
            [
                EffectKind::MaxHr,
                EffectKind::ZoneCeiling,
                EffectKind::HideEmptyPages
            ]
        );
    }
}
