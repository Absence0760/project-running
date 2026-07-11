//! Achievement badge catalogue — the badge/tier/threshold definitions plus the
//! pure `evaluate_badges` dispatcher, defined as code (the guided-runs pattern).
//!
//! Parity port of web `social/badges.ts` (twin of
//! `apps/mobile_android/lib/badges.dart`). The lockstep contract is the badge
//! ids, tier thresholds, tier order, icon ligature names, and the dispatcher
//! output — all of which must also match the SQL `award_achievements_for_user`
//! function (pinned web-side by `badges.test.ts` + pgtap `achievements_test.sql`).
//!
//! What is deliberately NOT ported: the English label/description *strings*.
//! Web reads those from `i18n/locales/en` and resolves them at display time via
//! `m(labelKey)`; the SSR-only `englishBadge` helper that inlines them is a
//! web/Lambda concern with no place on the watch. This module carries only the
//! i18n key *identifiers* ([`label_key`](BadgeTier::label_key) /
//! [`desc_key`](BadgeTier::desc_key)) so a presentation layer can resolve the
//! localized text later — the keys are identifiers, not the lockstep, and hold
//! no English prose.
//!
//! Pure logic, no peripherals, no allocator — like the rest of `core`.

use heapless::Vec;

/// Tier order, low → high. The earned tier is the highest threshold met.
/// Variants are declared ascending so the derived `Ord` matches this array.
pub const TIER_ORDER: [AchievementTier; 4] = [
    AchievementTier::Bronze,
    AchievementTier::Silver,
    AchievementTier::Gold,
    AchievementTier::Platinum,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AchievementTier {
    Bronze,
    Silver,
    Gold,
    Platinum,
}

/// The family a badge belongs to. `Segment` exists in the web union but no
/// catalogue entry uses it yet; kept for parity with the source type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum AchievementSourceKind {
    Pr,
    Segment,
    Streak,
    Distance,
    Plan,
}

/// Stable catalogue id, matches the DB `badge_key`. [`key`](BadgeId::key)
/// returns the string form the DB + web share.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "defmt", derive(defmt::Format))]
pub enum BadgeId {
    DistanceSingle,
    DistanceLifetime,
    Streak,
    Pr,
    PlanFinisher,
}

impl BadgeId {
    pub const fn key(self) -> &'static str {
        match self {
            BadgeId::DistanceSingle => "distance_single",
            BadgeId::DistanceLifetime => "distance_lifetime",
            BadgeId::Streak => "streak",
            BadgeId::Pr => "pr",
            BadgeId::PlanFinisher => "plan_finisher",
        }
    }
}

/// One tier of a badge family: its threshold, Material Symbols icon ligature,
/// and the i18n key identifiers for its label/description (resolved by the
/// display layer, never English prose here).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BadgeTier {
    pub tier: AchievementTier,
    /// Numeric threshold in the family's native unit (metres / days / count).
    pub threshold: f64,
    /// Material Symbols ligature name.
    pub icon: &'static str,
    pub label_key: &'static str,
    pub desc_key: &'static str,
}

/// A catalogue family: an id, its source kind, and its tiers ordered low →
/// high ([`evaluate_badges`] returns the highest tier met).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Badge {
    pub id: BadgeId,
    pub source_kind: AchievementSourceKind,
    pub tiers: &'static [BadgeTier],
}

/// The numeric the user fed in that earned the tier (display + DB dedupe).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EarnedBadge {
    pub badge_key: BadgeId,
    pub source_kind: AchievementSourceKind,
    pub tier: AchievementTier,
    pub threshold: f64,
    pub icon: &'static str,
    pub label_key: &'static str,
    pub desc_key: &'static str,
    /// The user's actual value that cleared the threshold.
    pub value_num: f64,
}

/// Primitives the catalogue evaluates. All non-negative; absent → 0. Web uses
/// `number` for every field, so all stay `f64` even where the value is a count.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct BadgeInput {
    /// Best single-run distance in metres (longest run).
    pub longest_run_m: f64,
    /// Lifetime summed distance in metres.
    pub lifetime_distance_m: f64,
    /// Best run streak in days.
    pub best_streak_days: f64,
    /// Count of distinct PR distances held (0–5: 5k/10k/half/marathon/mile).
    pub pr_count: f64,
    /// Count of completed training plans.
    pub completed_plan_count: f64,
}

/// Cap on the earned set. `evaluate_badges` returns at most one per family, so
/// this need only be ≥ the catalogue size.
pub const MAX_EARNED_BADGES: usize = 8;

/// The catalogue. Thresholds are the lockstep contract with the SQL award
/// function — if you change a number here, change it in
/// `20270208_001_achievements.sql` too (the pgtap pins it).
pub const BADGE_CATALOGUE: &[Badge] = &[
    Badge {
        id: BadgeId::DistanceSingle,
        source_kind: AchievementSourceKind::Distance,
        tiers: &[
            BadgeTier {
                tier: AchievementTier::Bronze,
                threshold: 5000.0,
                icon: "directions_run",
                label_key: "badges.distanceSingle5k.label",
                desc_key: "badges.distanceSingle5k.desc",
            },
            BadgeTier {
                tier: AchievementTier::Silver,
                threshold: 21097.0,
                icon: "military_tech",
                label_key: "badges.distanceSingleHalf.label",
                desc_key: "badges.distanceSingleHalf.desc",
            },
            BadgeTier {
                tier: AchievementTier::Gold,
                threshold: 42195.0,
                icon: "military_tech",
                label_key: "badges.distanceSingleMarathon.label",
                desc_key: "badges.distanceSingleMarathon.desc",
            },
            BadgeTier {
                tier: AchievementTier::Platinum,
                threshold: 50000.0,
                icon: "workspace_premium",
                label_key: "badges.distanceSingleUltra.label",
                desc_key: "badges.distanceSingleUltra.desc",
            },
        ],
    },
    Badge {
        id: BadgeId::DistanceLifetime,
        source_kind: AchievementSourceKind::Distance,
        tiers: &[
            BadgeTier {
                tier: AchievementTier::Bronze,
                threshold: 100000.0,
                icon: "route",
                label_key: "badges.distanceLifetime100.label",
                desc_key: "badges.distanceLifetime100.desc",
            },
            BadgeTier {
                tier: AchievementTier::Silver,
                threshold: 500000.0,
                icon: "route",
                label_key: "badges.distanceLifetime500.label",
                desc_key: "badges.distanceLifetime500.desc",
            },
            BadgeTier {
                tier: AchievementTier::Gold,
                threshold: 1000000.0,
                icon: "public",
                label_key: "badges.distanceLifetime1000.label",
                desc_key: "badges.distanceLifetime1000.desc",
            },
            BadgeTier {
                tier: AchievementTier::Platinum,
                threshold: 5000000.0,
                icon: "public",
                label_key: "badges.distanceLifetime5000.label",
                desc_key: "badges.distanceLifetime5000.desc",
            },
        ],
    },
    Badge {
        id: BadgeId::Streak,
        source_kind: AchievementSourceKind::Streak,
        tiers: &[
            BadgeTier {
                tier: AchievementTier::Bronze,
                threshold: 7.0,
                icon: "local_fire_department",
                label_key: "badges.streak7.label",
                desc_key: "badges.streak7.desc",
            },
            BadgeTier {
                tier: AchievementTier::Silver,
                threshold: 30.0,
                icon: "local_fire_department",
                label_key: "badges.streak30.label",
                desc_key: "badges.streak30.desc",
            },
            BadgeTier {
                tier: AchievementTier::Gold,
                threshold: 100.0,
                icon: "local_fire_department",
                label_key: "badges.streak100.label",
                desc_key: "badges.streak100.desc",
            },
            BadgeTier {
                tier: AchievementTier::Platinum,
                threshold: 365.0,
                icon: "whatshot",
                label_key: "badges.streak365.label",
                desc_key: "badges.streak365.desc",
            },
        ],
    },
    Badge {
        id: BadgeId::Pr,
        source_kind: AchievementSourceKind::Pr,
        tiers: &[
            BadgeTier {
                tier: AchievementTier::Bronze,
                threshold: 1.0,
                icon: "timer",
                label_key: "badges.pr1.label",
                desc_key: "badges.pr1.desc",
            },
            BadgeTier {
                tier: AchievementTier::Silver,
                threshold: 3.0,
                icon: "timer",
                label_key: "badges.pr3.label",
                desc_key: "badges.pr3.desc",
            },
            BadgeTier {
                tier: AchievementTier::Gold,
                threshold: 5.0,
                icon: "trophy",
                label_key: "badges.pr5.label",
                desc_key: "badges.pr5.desc",
            },
        ],
    },
    Badge {
        id: BadgeId::PlanFinisher,
        source_kind: AchievementSourceKind::Plan,
        tiers: &[
            BadgeTier {
                tier: AchievementTier::Bronze,
                threshold: 1.0,
                icon: "flag",
                label_key: "badges.plan1.label",
                desc_key: "badges.plan1.desc",
            },
            BadgeTier {
                tier: AchievementTier::Silver,
                threshold: 3.0,
                icon: "flag",
                label_key: "badges.plan3.label",
                desc_key: "badges.plan3.desc",
            },
            BadgeTier {
                tier: AchievementTier::Gold,
                threshold: 10.0,
                icon: "emoji_events",
                label_key: "badges.plan10.label",
                desc_key: "badges.plan10.desc",
            },
        ],
    },
];

/// Map a catalogue family to the input value it evaluates against.
fn value_for_badge(id: BadgeId, input: &BadgeInput) -> f64 {
    match id {
        BadgeId::DistanceSingle => input.longest_run_m,
        BadgeId::DistanceLifetime => input.lifetime_distance_m,
        BadgeId::Streak => input.best_streak_days,
        BadgeId::Pr => input.pr_count,
        BadgeId::PlanFinisher => input.completed_plan_count,
    }
}

/// Pure dispatcher. Returns at most one [`EarnedBadge`] per catalogue family —
/// the highest tier whose threshold the user's value clears. A user at gold
/// does NOT also earn bronze/silver of the same family (one tile per family,
/// highest tier wins). Deterministic + side-effect-free so it matches the SQL
/// award function; output order follows [`BADGE_CATALOGUE`].
pub fn evaluate_badges(input: &BadgeInput) -> Vec<EarnedBadge, MAX_EARNED_BADGES> {
    let mut out: Vec<EarnedBadge, MAX_EARNED_BADGES> = Vec::new();
    for badge in BADGE_CATALOGUE {
        let value = value_for_badge(badge.id, input);
        let mut earned: Option<&BadgeTier> = None;
        for t in badge.tiers {
            if value >= t.threshold {
                earned = Some(t);
            }
        }
        if let Some(t) = earned {
            let _ = out.push(EarnedBadge {
                badge_key: badge.id,
                source_kind: badge.source_kind,
                tier: t.tier,
                threshold: t.threshold,
                icon: t.icon,
                label_key: t.label_key,
                desc_key: t.desc_key,
                value_num: value,
            });
        }
    }
    out
}

/// Resolve a catalogue entry's tier definition from a stored award. Takes the
/// string `badge_key` (as the DB stores it) so an unknown key returns `None`,
/// mirroring web's `string` parameter.
pub fn tier_for(badge_key: &str, tier: AchievementTier) -> Option<BadgeTier> {
    let badge = BADGE_CATALOGUE.iter().find(|b| b.id.key() == badge_key)?;
    badge.tiers.iter().find(|t| t.tier == tier).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn find(input: &BadgeInput, key: BadgeId) -> Option<EarnedBadge> {
        evaluate_badges(input)
            .into_iter()
            .find(|e| e.badge_key == key)
    }

    fn tier_index(t: AchievementTier) -> usize {
        TIER_ORDER.iter().position(|x| *x == t).unwrap()
    }

    #[test]
    fn no_milestones_no_badges() {
        assert!(evaluate_badges(&BadgeInput::default()).is_empty());
    }

    #[test]
    fn catalogue_ids_unique_and_tiers_ascend_by_threshold() {
        let mut seen: Vec<&str, MAX_EARNED_BADGES> = Vec::new();
        for b in BADGE_CATALOGUE {
            assert!(!seen.contains(&b.id.key()), "duplicate id {}", b.id.key());
            let _ = seen.push(b.id.key());
            for i in 1..b.tiers.len() {
                assert!(
                    b.tiers[i].threshold > b.tiers[i - 1].threshold,
                    "{} tiers not ascending",
                    b.id.key()
                );
                assert!(
                    tier_index(b.tiers[i].tier) > tier_index(b.tiers[i - 1].tier),
                    "{} tier order wrong",
                    b.id.key()
                );
            }
        }
    }

    #[test]
    fn single_run_5k_bronze_boundary_inclusive() {
        let input = BadgeInput {
            longest_run_m: 5000.0,
            ..Default::default()
        };
        let e = find(&input, BadgeId::DistanceSingle).unwrap();
        assert_eq!(e.tier, AchievementTier::Bronze);
        assert_eq!(e.value_num, 5000.0);
    }

    #[test]
    fn single_run_just_under_5k_earns_nothing() {
        let input = BadgeInput {
            longest_run_m: 4999.0,
            ..Default::default()
        };
        assert_eq!(find(&input, BadgeId::DistanceSingle), None);
    }

    #[test]
    fn single_run_marathon_gold_not_also_lower() {
        let input = BadgeInput {
            longest_run_m: 42195.0,
            ..Default::default()
        };
        let single: Vec<EarnedBadge, MAX_EARNED_BADGES> = evaluate_badges(&input)
            .into_iter()
            .filter(|e| e.badge_key == BadgeId::DistanceSingle)
            .collect();
        assert_eq!(single.len(), 1);
        assert_eq!(single[0].tier, AchievementTier::Gold);
    }

    #[test]
    fn single_run_50k_plus_platinum_ultra() {
        let input = BadgeInput {
            longest_run_m: 60000.0,
            ..Default::default()
        };
        assert_eq!(
            find(&input, BadgeId::DistanceSingle).map(|e| e.tier),
            Some(AchievementTier::Platinum)
        );
    }

    #[test]
    fn lifetime_100km_bronze_1000km_gold() {
        let bronze = BadgeInput {
            lifetime_distance_m: 100000.0,
            ..Default::default()
        };
        assert_eq!(
            find(&bronze, BadgeId::DistanceLifetime).map(|e| e.tier),
            Some(AchievementTier::Bronze)
        );
        let gold = BadgeInput {
            lifetime_distance_m: 1_000_000.0,
            ..Default::default()
        };
        assert_eq!(
            find(&gold, BadgeId::DistanceLifetime).map(|e| e.tier),
            Some(AchievementTier::Gold)
        );
    }

    #[test]
    fn lifetime_5000km_platinum_is_the_cap() {
        let input = BadgeInput {
            lifetime_distance_m: 9_000_000.0,
            ..Default::default()
        };
        assert_eq!(
            find(&input, BadgeId::DistanceLifetime).map(|e| e.tier),
            Some(AchievementTier::Platinum)
        );
    }

    #[test]
    fn streak_thresholds() {
        for (days, tier) in [
            (7.0, AchievementTier::Bronze),
            (30.0, AchievementTier::Silver),
            (100.0, AchievementTier::Gold),
            (365.0, AchievementTier::Platinum),
        ] {
            let input = BadgeInput {
                best_streak_days: days,
                ..Default::default()
            };
            assert_eq!(find(&input, BadgeId::Streak).map(|e| e.tier), Some(tier));
        }
    }

    #[test]
    fn streak_6_days_earns_nothing() {
        let input = BadgeInput {
            best_streak_days: 6.0,
            ..Default::default()
        };
        assert_eq!(find(&input, BadgeId::Streak), None);
    }

    #[test]
    fn pr_thresholds() {
        for (count, tier) in [
            (1.0, AchievementTier::Bronze),
            (3.0, AchievementTier::Silver),
            (5.0, AchievementTier::Gold),
        ] {
            let input = BadgeInput {
                pr_count: count,
                ..Default::default()
            };
            assert_eq!(find(&input, BadgeId::Pr).map(|e| e.tier), Some(tier));
        }
    }

    #[test]
    fn plan_finisher_thresholds() {
        for (count, tier) in [
            (1.0, AchievementTier::Bronze),
            (3.0, AchievementTier::Silver),
            (10.0, AchievementTier::Gold),
        ] {
            let input = BadgeInput {
                completed_plan_count: count,
                ..Default::default()
            };
            assert_eq!(
                find(&input, BadgeId::PlanFinisher).map(|e| e.tier),
                Some(tier)
            );
        }
    }

    #[test]
    fn maxed_out_user_earns_one_per_family_at_top_tier() {
        let input = BadgeInput {
            longest_run_m: 100000.0,
            lifetime_distance_m: 6_000_000.0,
            best_streak_days: 400.0,
            pr_count: 5.0,
            completed_plan_count: 12.0,
        };
        let all = evaluate_badges(&input);
        assert_eq!(all.len(), BADGE_CATALOGUE.len());
        for b in BADGE_CATALOGUE {
            let count = all.iter().filter(|x| x.badge_key == b.id).count();
            assert_eq!(count, 1, "{} should appear once", b.id.key());
        }
        assert_eq!(
            all.iter()
                .find(|e| e.badge_key == BadgeId::DistanceSingle)
                .map(|e| e.tier),
            Some(AchievementTier::Platinum)
        );
        assert_eq!(
            all.iter()
                .find(|e| e.badge_key == BadgeId::Pr)
                .map(|e| e.tier),
            Some(AchievementTier::Gold)
        );
    }

    #[test]
    fn output_order_follows_catalogue_order() {
        let input = BadgeInput {
            longest_run_m: 5000.0,
            lifetime_distance_m: 100000.0,
            best_streak_days: 7.0,
            pr_count: 1.0,
            completed_plan_count: 1.0,
        };
        let all = evaluate_badges(&input);
        let order: Vec<BadgeId, MAX_EARNED_BADGES> = all.iter().map(|e| e.badge_key).collect();
        let expected: Vec<BadgeId, MAX_EARNED_BADGES> =
            BADGE_CATALOGUE.iter().map(|b| b.id).collect();
        assert_eq!(order, expected);
    }

    #[test]
    fn tier_for_resolves_stored_award() {
        assert_eq!(
            tier_for("streak", AchievementTier::Gold).map(|t| t.threshold),
            Some(100.0)
        );
        assert_eq!(tier_for("nope", AchievementTier::Bronze), None);
        assert_eq!(
            tier_for("streak", AchievementTier::Platinum).map(|t| t.threshold),
            Some(365.0)
        );
    }
}
